package main

import (
	"bufio"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"text/tabwriter"
	"time"
)

// ---- service registry --------------------------------------------------

type service struct {
	name   string
	argv   []string
	after  []string // services.conf "after=": waited on (bounded) before each start
	memMax string   // services.conf "mem=": cgroup memory.max
	cpuPct int       // services.conf "cpu=": cgroup cpu.max, as a percentage of one CPU period
	kick   chan struct{} // wakes the supervisor loop out of the stopped state

	mu          sync.Mutex
	pid         int
	wantUp      bool
	starts      int
	since       time.Time
	lastExit    int
	skipBackoff bool
}

var (
	svcMu    sync.Mutex
	services = map[string]*service{}
	svcOrder []string
)

func lookupService(name string) *service {
	svcMu.Lock()
	defer svcMu.Unlock()
	return services[name]
}

func (sv *service) state() string {
	switch {
	case sv.pid > 0:
		return "running"
	case sv.wantUp:
		return "starting"
	}
	return "stopped"
}

func (sv *service) start() {
	sv.mu.Lock()
	sv.wantUp = true
	sv.mu.Unlock()
	select {
	case sv.kick <- struct{}{}:
	default:
	}
}

func (sv *service) stop() {
	sv.mu.Lock()
	sv.wantUp = false
	pid := sv.pid
	sv.mu.Unlock()
	if pid > 0 {
		syscall.Kill(pid, syscall.SIGTERM)
		go func() {
			time.Sleep(5 * time.Second)
			sv.mu.Lock()
			still := sv.pid == pid
			sv.mu.Unlock()
			if still {
				syscall.Kill(pid, syscall.SIGKILL)
			}
		}()
	}
}

func (sv *service) restart() {
	sv.mu.Lock()
	pid := sv.pid
	sv.skipBackoff = true
	sv.mu.Unlock()
	if pid > 0 {
		sv.stop()
		sv.mu.Lock()
		sv.wantUp = true // stop() cleared it; the loop restarts it after the exit
		sv.mu.Unlock()
		return
	}
	sv.start()
}

func statusTable() string {
	var b strings.Builder
	tw := tabwriter.NewWriter(&b, 0, 4, 2, ' ', 0)
	fmt.Fprintln(tw, "SERVICE\tSTATE\tPID\tRESTARTS\tUPTIME\tLAST EXIT")
	svcMu.Lock()
	names := append([]string(nil), svcOrder...)
	svcMu.Unlock()
	for _, n := range names {
		sv := lookupService(n)
		sv.mu.Lock()
		up, pid, restarts, last := "-", "-", sv.starts-1, "-"
		if restarts < 0 {
			restarts = 0
		}
		if sv.pid > 0 {
			pid = fmt.Sprint(sv.pid)
			up = time.Since(sv.since).Truncate(time.Second).String()
		}
		if sv.starts > 0 && sv.pid == 0 {
			last = fmt.Sprint(sv.lastExit)
		}
		fmt.Fprintf(tw, "%s\t%s\t%s\t%d\t%s\t%s\n", sv.name, sv.state(), pid, restarts, up, last)
		sv.mu.Unlock()
	}
	tw.Flush()
	return b.String()
}

// timerStatusTable renders the TIMERS table appended to `lenine status` when any
// timers.conf entries are configured; it's omitted entirely otherwise.
func timerStatusTable() string {
	timerMu.Lock()
	names := append([]string(nil), timerOrder...)
	timerMu.Unlock()
	if len(names) == 0 {
		return ""
	}
	var b strings.Builder
	b.WriteString("\n")
	tw := tabwriter.NewWriter(&b, 0, 4, 2, ' ', 0)
	fmt.Fprintln(tw, "TIMER\tINTERVAL\tLAST RUN\tLAST EXIT\tNEXT RUN")
	for _, n := range names {
		timerMu.Lock()
		t := timers[n]
		timerMu.Unlock()
		t.mu.Lock()
		last, lastExit := "-", "-"
		if t.ran {
			last = time.Since(t.lastRun).Truncate(time.Second).String() + " ago"
			lastExit = fmt.Sprint(t.lastExit)
		}
		next := time.Until(t.nextRun).Truncate(time.Second)
		if next < 0 {
			next = 0
		}
		fmt.Fprintf(tw, "%s\t%s\t%s\t%s\t%s\n", t.name, t.interval, last, lastExit, next)
		t.mu.Unlock()
	}
	tw.Flush()
	return b.String()
}

// ---- control socket (server side, runs in PID 1) ------------------------

const defaultCtlSock = "/run/lenine.sock"

// ctlSock is the control socket path ($LENINE_SOCK overrides it for testing).
func ctlSock() string {
	if p := os.Getenv("LENINE_SOCK"); p != "" {
		return p
	}
	return defaultCtlSock
}

func serveControl() {
	os.Remove(ctlSock())
	l, err := net.Listen("unix", ctlSock())
	if err != nil {
		logf("control socket: %v", err)
		return
	}
	os.Chmod(ctlSock(), 0o600) // root only
	go func() {
		for {
			c, err := l.Accept()
			if err != nil {
				time.Sleep(100 * time.Millisecond)
				continue
			}
			go handleControl(c)
		}
	}()
}

func handleControl(c net.Conn) {
	defer c.Close()
	c.SetDeadline(time.Now().Add(5 * time.Second))
	line, _ := bufio.NewReader(io.LimitReader(c, 1024)).ReadString('\n')
	io.WriteString(c, runControl(strings.Fields(line)))
}

func runControl(args []string) string {
	if len(args) == 0 {
		return "error: empty command\n"
	}
	switch args[0] {
	case "status":
		return statusTable() + timerStatusTable()
	case "start", "stop", "restart":
		if len(args) != 2 {
			return "error: usage: lenine " + args[0] + " <service>\n"
		}
		sv := lookupService(args[1])
		if sv == nil {
			return "error: no such service: " + args[1] + "\n"
		}
		switch args[0] {
		case "start":
			sv.start()
		case "stop":
			sv.stop()
		default:
			sv.restart()
		}
		return args[0] + ": " + args[1] + "\n"
	case "reboot":
		go shutdown(syscall.LINUX_REBOOT_CMD_RESTART)
		return "rebooting\n"
	case "poweroff":
		go shutdown(syscall.LINUX_REBOOT_CMD_POWER_OFF)
		return "powering off\n"
	case "halt":
		go shutdown(syscall.LINUX_REBOOT_CMD_HALT)
		return "halting\n"
	}
	return "error: unknown command: " + args[0] + "\n"
}

// ---- client side (lenine run as a normal process) -----------------------

const usage = `usage: lenine <command>
  status                 list supervised services and timers
  log [service]          show lenine's own log, or a service's (nothing is printed to the terminal)
  start|stop|restart <service>
  reboot | poweroff | halt

Also acts as reboot, poweroff, halt and shutdown [-r] when invoked by those names.
`

// clientMain handles every invocation that is not PID 1.
func clientMain() int {
	args := os.Args[1:]
	switch name := filepath.Base(os.Args[0]); name {
	case "reboot", "poweroff", "halt":
		args = []string{name}
	case "shutdown":
		args = []string{"poweroff"}
		for _, a := range os.Args[1:] {
			if a == "-r" {
				args = []string{"reboot"}
			} else if a == "-H" {
				args = []string{"halt"}
			}
		}
	}
	if len(args) == 0 || args[0] == "-h" || args[0] == "--help" {
		fmt.Fprint(os.Stderr, usage)
		return 2
	}
	if args[0] == "log" { // read a log file directly: `lenine log` (init's own) or `lenine log <service>`
		name := "lenine"
		if len(args) > 1 {
			name = args[1]
		}
		if name == "" || strings.ContainsAny(name, "/\\") || strings.HasPrefix(name, ".") {
			fmt.Fprintln(os.Stderr, "lenine: invalid log name")
			return 1
		}
		b, err := os.ReadFile(logDir + "/" + name + ".log")
		if err != nil {
			fmt.Fprintf(os.Stderr, "lenine: no log for %q (%v)\n", name, err)
			return 1
		}
		os.Stdout.Write(b)
		return 0
	}
	if os.Geteuid() != 0 {
		fmt.Fprintln(os.Stderr, "lenine: must be root")
		return 1
	}
	c, err := net.DialTimeout("unix", ctlSock(), 2*time.Second)
	if err != nil {
		fmt.Fprintf(os.Stderr, "lenine: cannot reach init (%v); is lenine running as PID 1?\n", err)
		return 1
	}
	defer c.Close()
	c.SetDeadline(time.Now().Add(10 * time.Second))
	fmt.Fprintln(c, strings.Join(args, " "))
	out, _ := io.ReadAll(c)
	if strings.HasPrefix(string(out), "error:") {
		fmt.Fprint(os.Stderr, string(out))
		return 1
	}
	fmt.Print(string(out))
	return 0
}
