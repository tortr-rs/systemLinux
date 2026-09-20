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
	name string
	argv []string
	kick chan struct{} // wakes the supervisor loop out of the stopped state

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

// ---- control socket (server side, runs in PID 1) ------------------------

const defaultCtlSock = "/run/systemL.sock"

// ctlSock is the control socket path ($SYSTEML_SOCK overrides it for testing).
func ctlSock() string {
	if p := os.Getenv("SYSTEML_SOCK"); p != "" {
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
		return statusTable()
	case "start", "stop", "restart":
		if len(args) != 2 {
			return "error: usage: systemL " + args[0] + " <service>\n"
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

// ---- client side (systemL run as a normal process) -----------------------

const usage = `usage: systemL <command>
  status                 list supervised services
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
	if os.Geteuid() != 0 {
		fmt.Fprintln(os.Stderr, "systemL: must be root")
		return 1
	}
	c, err := net.DialTimeout("unix", ctlSock(), 2*time.Second)
	if err != nil {
		fmt.Fprintf(os.Stderr, "systemL: cannot reach init (%v); is systemL running as PID 1?\n", err)
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
