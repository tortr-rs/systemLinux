// lenine - minimal PID 1 init for systemLinux.
//
// Boot sequence: core pseudo-filesystems -> udev -> loopback -> D-Bus ->
// NetworkManager -> configured services and timers -> respawning root shell
// on the console TTY.
// Build: CGO_ENABLED=0 go build -o lenine .   Install as /sbin/lenine and
// boot with init=/sbin/lenine.
//
// Runtime control (root): lenine status | start|stop|restart <service> |
// reboot | poweroff | halt. Invoked as reboot/poweroff/halt/shutdown it acts
// as that command.
//
// Config (all optional): /etc/lenine/autologin (a user name) logs that user in on tty1 automatically;
// /etc/lenine/login makes tty1 run agetty/login instead of an unauthenticated root shell;
// /etc/lenine/services.conf lists extra daemons to supervise, one line per service:
//
//	[after=svc1,svc2] [mem=<size>] [cpu=<percent>%] <name> <command> [args...]
//
// after= waits (up to 10s) for the listed services to be running before each start attempt.
// mem=/cpu= apply a cgroup v2 memory.max / cpu.max limit (sizes take K/M/G suffixes).
// /etc/lenine/timers.conf runs a command on a fixed interval instead of supervising it as a
// daemon, one line per timer: <name> every=<duration> <command> [args...] (duration takes
// s/m/h/d suffixes, e.g. every=6h).
//
// PID 1 signals (busybox convention): SIGTERM/SIGINT reboot, SIGUSR1 halt,
// SIGUSR2 power off. Service logs go to /run/log/lenine/<name>.log.
// The console TTY defaults to /dev/tty1 (override with $LENINE_TTY).
package main

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
	"unsafe"
)

const (
	defaultPath = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
	logDir      = "/run/log/lenine"
	confDir     = "/etc/lenine"
	dbusSocket  = "/run/dbus/system_bus_socket"
	cgroupRoot  = "/sys/fs/cgroup/lenine.slice"
	banner      = "\x1b[3J\x1b[2J\x1b[H\n" +
		"  +------------------------------------------+\n" +
		"  |                                          |\n" +
		"  |   systemLinux                            |\n" +
		"  |   (lenine Init Engine)                   |\n" +
		"  |                                          |\n" +
		"  +------------------------------------------+\n\n"
)

var (
	mu           sync.Mutex
	waiters      = map[int]chan int{} // pid -> exit code, guarded by mu
	shuttingDown atomic.Bool
)

// lenine's own messages go to /run/log/lenine/lenine.log, not to the terminal
// (read them with `lenine log`). Add lenine.verbose=1 to the kernel command line to
// see them on the console as well.
var (
	logMu      sync.Mutex
	logFile    *os.File
	logPending []string
	logVerbose bool
)

func logf(format string, a ...any) {
	line := fmt.Sprintf("[lenine] "+format, a...)
	logMu.Lock()
	defer logMu.Unlock()
	if logVerbose {
		fmt.Fprintln(os.Stderr, line)
	}
	if logFile == nil {
		logPending = append(logPending, line) // /run is not mounted yet: keep it until it is
		return
	}
	fmt.Fprintln(logFile, line)
}

// openLog starts writing to the log file once /run exists and flushes what was kept so far.
func openLog() {
	if b, err := os.ReadFile("/proc/cmdline"); err == nil && strings.Contains(string(b), "lenine.verbose=1") {
		logVerbose = true
	}
	if err := os.MkdirAll(logDir, 0o755); err != nil {
		return
	}
	f, err := os.OpenFile(logDir+"/lenine.log", os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return
	}
	logMu.Lock()
	defer logMu.Unlock()
	logFile = f
	for _, l := range logPending {
		fmt.Fprintln(f, l)
	}
	logPending = nil
}

// helperOutput is where the output of helper commands (mount -a, udevadm, ...) goes.
func helperOutput() *os.File {
	logMu.Lock()
	defer logMu.Unlock()
	if logFile != nil {
		return logFile
	}
	if f, err := os.OpenFile("/dev/null", os.O_WRONLY, 0); err == nil {
		return f
	}
	return os.Stderr
}

// ---- process management ------------------------------------------------
//
// As PID 1 we inherit every orphan, so all children are reaped centrally
// with wait4(-1). Children we spawn are registered by pid so their exit
// status can be delivered to whoever is supervising them. cmd.Wait is never
// used: it would race the reaper for the exit status.

func exitCode(ws syscall.WaitStatus) int {
	if ws.Signaled() {
		return 128 + int(ws.Signal())
	}
	return ws.ExitStatus()
}

func initReaper() {
	sigs := make(chan os.Signal, 16)
	signal.Notify(sigs, syscall.SIGCHLD)
	go func() {
		for range sigs {
			reapAll()
		}
	}()
}

func reapAll() {
	for {
		var ws syscall.WaitStatus
		pid, err := syscall.Wait4(-1, &ws, syscall.WNOHANG, nil)
		if err == syscall.EINTR {
			continue
		}
		if err != nil || pid <= 0 {
			return
		}
		mu.Lock() // blocks until start() has registered a just-spawned pid
		ch, ok := waiters[pid]
		delete(waiters, pid)
		mu.Unlock()
		if ok {
			ch <- exitCode(ws)
		}
	}
}

// start launches cmd and returns its pid plus a channel that receives its
// exit code.
func start(cmd *exec.Cmd) (int, <-chan int, error) {
	mu.Lock()
	defer mu.Unlock()
	if err := cmd.Start(); err != nil {
		return 0, nil, err
	}
	pid := cmd.Process.Pid
	ch := make(chan int, 1)
	waiters[pid] = ch
	cmd.Process.Release()
	return pid, ch, nil
}

// runCode executes a command to completion and returns its exit code.
func runCode(name string, args ...string) (int, error) {
	cmd := exec.Command(name, args...)
	out := helperOutput()
	cmd.Stdout, cmd.Stderr = out, out
	_, ch, err := start(cmd)
	if err != nil {
		return -1, err
	}
	code := <-ch
	if code != 0 {
		return code, fmt.Errorf("%s exited with status %d", name, code)
	}
	return code, nil
}

// run executes a command to completion.
func run(name string, args ...string) error {
	_, err := runCode(name, args...)
	return err
}

// waitDeps waits (bounded) for each named service to be running before a dependent
// service starts. It never blocks boot forever: a missing or slow dependency just
// gets logged and the dependent starts anyway.
func waitDeps(after []string, timeout time.Duration) {
	for _, dep := range after {
		dep = strings.TrimSpace(dep)
		if dep == "" {
			continue
		}
		deadline := time.Now().Add(timeout)
		for {
			if d := lookupService(dep); d != nil {
				d.mu.Lock()
				running := d.pid > 0
				d.mu.Unlock()
				if running {
					break
				}
			}
			if time.Now().After(deadline) {
				logf("dependency %q did not come up in time", dep)
				break
			}
			time.Sleep(100 * time.Millisecond)
		}
	}
}

// parseSize parses a byte size with an optional K/M/G suffix (e.g. "256M").
func parseSize(s string) (int64, bool) {
	s = strings.ToUpper(strings.TrimSpace(s))
	mult := int64(1)
	switch {
	case strings.HasSuffix(s, "G"):
		mult, s = 1<<30, strings.TrimSuffix(s, "G")
	case strings.HasSuffix(s, "M"):
		mult, s = 1<<20, strings.TrimSuffix(s, "M")
	case strings.HasSuffix(s, "K"):
		mult, s = 1<<10, strings.TrimSuffix(s, "K")
	}
	n, err := strconv.ParseFloat(s, 64)
	if err != nil {
		return 0, false
	}
	return int64(n * float64(mult)), true
}

// setupCgroups enables the memory and cpu controllers on the root cgroup and creates
// lenine.slice, the parent of every supervised service's own leaf cgroup.
func setupCgroups() {
	if err := os.WriteFile("/sys/fs/cgroup/cgroup.subtree_control", []byte("+memory +cpu"), 0o644); err != nil {
		logf("cgroup: enabling controllers on the root: %v", err)
		return
	}
	if err := os.MkdirAll(cgroupRoot, 0o755); err != nil {
		logf("cgroup: mkdir %s: %v", cgroupRoot, err)
		return
	}
	if err := os.WriteFile(cgroupRoot+"/cgroup.subtree_control", []byte("+memory +cpu"), 0o644); err != nil {
		logf("cgroup: enabling controllers on %s: %v", cgroupRoot, err)
	}
}

// applyCgroup puts pid into its own leaf cgroup under lenine.slice and applies the
// service's mem=/cpu= limits, if any were set.
func applyCgroup(name string, pid int, memMax string, cpuPct int) {
	if memMax == "" && cpuPct <= 0 {
		return
	}
	dir := cgroupRoot + "/" + name
	if err := os.MkdirAll(dir, 0o755); err != nil {
		logf("%s: cgroup mkdir: %v", name, err)
		return
	}
	if memMax != "" {
		if bytes, ok := parseSize(memMax); ok {
			if err := os.WriteFile(dir+"/memory.max", []byte(strconv.FormatInt(bytes, 10)), 0o644); err != nil {
				logf("%s: memory.max: %v", name, err)
			}
		} else {
			logf("%s: invalid mem= value %q", name, memMax)
		}
	}
	if cpuPct > 0 {
		const period = 100000
		quota := period * cpuPct / 100
		if err := os.WriteFile(dir+"/cpu.max", []byte(fmt.Sprintf("%d %d", quota, period)), 0o644); err != nil {
			logf("%s: cpu.max: %v", name, err)
		}
	}
	if err := os.WriteFile(dir+"/cgroup.procs", []byte(strconv.Itoa(pid)), 0o644); err != nil {
		logf("%s: cgroup.procs: %v", name, err)
	}
}

// supervise registers a plain daemon (no dependencies or resource limits) and keeps
// it running in the background. Used for the handful of services lenine itself starts
// unconditionally (udevd, dbus, NetworkManager); everything from services.conf goes
// through superviseConf instead.
func supervise(name string, argv ...string) {
	superviseConf(&svcConf{name: name, argv: argv})
}

// superviseConf registers a service from a parsed services.conf entry (or an internal
// one) and starts its supervisor loop.
func superviseConf(sc *svcConf) {
	sv := &service{name: sc.name, argv: sc.argv, after: sc.after, memMax: sc.memMax, cpuPct: sc.cpuPct,
		wantUp: true, kick: make(chan struct{}, 1)}
	svcMu.Lock()
	services[sc.name] = sv
	svcOrder = append(svcOrder, sc.name)
	svcMu.Unlock()
	go sv.loop()
}

func (sv *service) loop() {
	backoff := time.Second
	for !shuttingDown.Load() {
		sv.mu.Lock()
		up := sv.wantUp
		sv.mu.Unlock()
		if !up {
			<-sv.kick
			backoff = time.Second
			continue
		}

		waitDeps(sv.after, 10*time.Second)

		cmd := exec.Command(sv.argv[0], sv.argv[1:]...)
		var lf *os.File
		if err := os.MkdirAll(logDir, 0o755); err == nil {
			lf, _ = os.OpenFile(logDir+"/"+sv.name+".log", os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
		}
		if lf != nil {
			cmd.Stdout, cmd.Stderr = lf, lf
		}
		began := time.Now()
		pid, ch, err := start(cmd)
		if lf != nil {
			lf.Close()
		}
		if err != nil {
			logf("%s: cannot start: %v", sv.name, err)
		} else {
			sv.mu.Lock()
			sv.pid, sv.since = pid, began
			sv.starts++
			sv.mu.Unlock()
			logf("%s started (pid %d)", sv.name, pid)
			applyCgroup(sv.name, pid, sv.memMax, sv.cpuPct)
			code := <-ch
			sv.mu.Lock()
			sv.pid, sv.lastExit = 0, code
			sv.mu.Unlock()
			logf("%s exited with status %d", sv.name, code)
		}
		if shuttingDown.Load() {
			return
		}

		sv.mu.Lock()
		up, skip := sv.wantUp, sv.skipBackoff
		sv.skipBackoff = false
		sv.mu.Unlock()
		if !up || skip {
			backoff = time.Second
			continue
		}
		if time.Since(began) > 10*time.Second {
			backoff = time.Second
		}
		time.Sleep(backoff)
		if backoff *= 2; backoff > 30*time.Second {
			backoff = 30 * time.Second
		}
	}
}

// ---- filesystems -------------------------------------------------------

func isMounted(target string) bool {
	data, err := os.ReadFile("/proc/self/mounts")
	if err != nil {
		return false
	}
	for _, line := range bytes.Split(data, []byte("\n")) {
		if f := strings.Fields(string(line)); len(f) > 1 && f[1] == target {
			return true
		}
	}
	return false
}

func mount(fstype, target string, flags uintptr, data string) {
	if isMounted(target) {
		return
	}
	if err := os.MkdirAll(target, 0o755); err != nil {
		logf("mkdir %s: %v", target, err)
		return
	}
	if err := syscall.Mount(fstype, target, fstype, flags, data); err != nil && err != syscall.EBUSY {
		logf("mount %s on %s: %v", fstype, target, err)
	}
}

func mountCore() {
	const secure = syscall.MS_NOSUID | syscall.MS_NODEV | syscall.MS_NOEXEC
	mount("proc", "/proc", secure, "")
	mount("sysfs", "/sys", secure, "")
	mount("cgroup2", "/sys/fs/cgroup", secure, "") // elogind tracks sessions with it; lenine uses it for per-service limits
	mount("devtmpfs", "/dev", syscall.MS_NOSUID, "mode=0755")
	mount("devpts", "/dev/pts", syscall.MS_NOSUID|syscall.MS_NOEXEC, "gid=5,mode=0620,ptmxmode=0666")
	mount("tmpfs", "/dev/shm", syscall.MS_NOSUID|syscall.MS_NODEV, "mode=1777")
	mount("tmpfs", "/run", syscall.MS_NOSUID|syscall.MS_NODEV, "mode=0755")
	mount("tmpfs", "/tmp", syscall.MS_NOSUID|syscall.MS_NODEV, "mode=1777")
	// Created after /run is mounted, otherwise the tmpfs would hide them.
	for _, d := range []string{"/run/dbus", "/run/lock", logDir} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			logf("mkdir %s: %v", d, err)
		}
	}
	setupCgroups()
	// Nix-built graphics programs look for the GPU drivers in /run/opengl-driver (see `goget graphics`)
	if _, err := os.Stat("/nix/var/goget/profiles/system/current/lib/dri"); err == nil {
		os.Symlink("/nix/var/goget/profiles/system/current", "/run/opengl-driver")
	}
	if err := os.Chmod("/tmp", 0o777|os.ModeSticky); err != nil {
		logf("chmod /tmp: %v", err)
	}
	// the sticky socket directories X11, Wayland's Xwayland and ICE need (systemd creates them with tmpfiles)
	for _, d := range []string{"/tmp/.X11-unix", "/tmp/.ICE-unix", "/tmp/.font-unix", "/tmp/.XIM-unix"} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			logf("mkdir %s: %v", d, err)
			continue
		}
		os.Chmod(d, 0o777|os.ModeSticky) // Go needs ModeSticky: the numeric 01000 bit is not part of Perm()
	}
}

// setupDevLinks creates the conventional /dev symlinks; with devpts as its
// own instance, /dev/ptmx must point into it.
func setupDevLinks() {
	links := [][2]string{
		{"pts/ptmx", "/dev/ptmx"},
		{"/proc/self/fd", "/dev/fd"},
		{"/proc/self/fd/0", "/dev/stdin"},
		{"/proc/self/fd/1", "/dev/stdout"},
		{"/proc/self/fd/2", "/dev/stderr"},
	}
	for _, l := range links {
		os.Remove(l[1])
		if err := os.Symlink(l[0], l[1]); err != nil {
			logf("symlink %s: %v", l[1], err)
		}
	}
	if _, err := os.Lstat("/var/run"); os.IsNotExist(err) {
		os.MkdirAll("/var", 0o755)
		os.Symlink("/run", "/var/run")
	}
}

// silenceKernelLog lowers the kernel console log level to KERN_ERR so
// informational messages don't scribble over the console.
// printk = [console_loglevel, default_message_loglevel,
// minimum_console_loglevel, default_console_loglevel].
func silenceKernelLog() {
	if err := os.WriteFile("/proc/sys/kernel/printk", []byte("1 4 1 3\n"), 0o644); err != nil {
		logf("failed to set printk silence level: %v", err)
	}
}

func setHostname() {
	name := "systemlinux" // default when /etc/hostname is missing or empty
	if b, err := os.ReadFile("/etc/hostname"); err == nil {
		if h := strings.TrimSpace(string(b)); h != "" {
			name = h
		}
	}
	if err := syscall.Sethostname([]byte(name)); err != nil {
		logf("sethostname: %v", err)
	}
}

// ---- networking --------------------------------------------------------

type ifreq struct {
	name  [syscall.IFNAMSIZ]byte
	flags uint16
	_     [22]byte
}

func ioctl(fd int, req uintptr, arg unsafe.Pointer) error {
	if _, _, e := syscall.Syscall(syscall.SYS_IOCTL, uintptr(fd), req, uintptr(arg)); e != 0 {
		return e
	}
	return nil
}

// loopbackUp is the native equivalent of `ip link set lo up`.
func loopbackUp() error {
	fd, err := syscall.Socket(syscall.AF_INET, syscall.SOCK_DGRAM|syscall.SOCK_CLOEXEC, 0)
	if err != nil {
		return err
	}
	defer syscall.Close(fd)
	var r ifreq
	copy(r.name[:], "lo")
	if err := ioctl(fd, syscall.SIOCGIFFLAGS, unsafe.Pointer(&r)); err != nil {
		return fmt.Errorf("SIOCGIFFLAGS: %w", err)
	}
	r.flags |= syscall.IFF_UP
	if err := ioctl(fd, syscall.SIOCSIFFLAGS, unsafe.Pointer(&r)); err != nil {
		return fmt.Errorf("SIOCSIFFLAGS: %w", err)
	}
	return nil
}

func pathExists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}

func waitForPath(path string, timeout time.Duration) bool {
	for deadline := time.Now().Add(timeout); time.Now().Before(deadline); time.Sleep(50 * time.Millisecond) {
		if _, err := os.Stat(path); err == nil {
			return true
		}
	}
	return false
}

// startUdev runs the device manager and coldplugs existing devices so
// NetworkManager (which relies on udev's device database) sees them. The
// trigger is asynchronous, so boot does not wait for it to settle.
func startUdev() bool {
	udevd := ""
	for _, p := range []string{
		"/lib/systemd/systemd-udevd", "/usr/lib/systemd/systemd-udevd",
		"/usr/lib/udev/udevd", "/sbin/udevd",
	} {
		if fi, err := os.Stat(p); err == nil && !fi.IsDir() {
			udevd = p
			break
		}
	}
	if udevd == "" {
		logf("udevd not found; device detection will be limited")
		return false
	}
	supervise("udevd", udevd)
	if !waitForPath("/run/udev/control", 5*time.Second) {
		logf("udevd control socket did not appear; skipping coldplug")
		return true
	}
	for _, typ := range []string{"subsystems", "devices"} {
		if err := run("udevadm", "trigger", "--type="+typ, "--action=add"); err != nil {
			logf("udevadm trigger %s: %v", typ, err)
		}
	}
	return true
}

// mountFstab mounts the non-root entries of /etc/fstab (e.g. /boot/efi on an
// installed system). It waits for udev to finish so UUID lookups succeed.
func mountFstab(udev bool) {
	if udev {
		run("udevadm", "settle", "--timeout=10")
	}
	if err := run("mount", "-a"); err != nil {
		logf("mount -a: %v", err)
	}
}

func startNetworking() {
	if err := loopbackUp(); err != nil {
		logf("loopback: %v", err)
	}
	if err := run("dbus-uuidgen", "--ensure=/etc/machine-id"); err != nil {
		logf("dbus-uuidgen: %v", err)
	}
	os.MkdirAll("/var/lib/dbus", 0o755)
	if _, err := os.Lstat("/var/lib/dbus/machine-id"); os.IsNotExist(err) {
		os.Symlink("/etc/machine-id", "/var/lib/dbus/machine-id")
	}
	supervise("dbus", "dbus-daemon", "--system", "--nofork", "--nopidfile")
	if !waitForPath(dbusSocket, 10*time.Second) {
		logf("system bus socket did not appear; starting NetworkManager anyway")
	}
	supervise("NetworkManager", "NetworkManager", "--no-daemon")
}

// svcConf is one parsed services.conf line.
type svcConf struct {
	name   string
	argv   []string
	after  []string
	memMax string
	cpuPct int
}

// parseServiceLine parses "[after=a,b] [mem=256M] [cpu=50%] <name> <command> [args...]".
func parseServiceLine(line string) (*svcConf, error) {
	f := strings.Fields(line)
	var sc svcConf
	i := 0
loop:
	for i < len(f) {
		switch {
		case strings.HasPrefix(f[i], "after="):
			sc.after = strings.Split(strings.TrimPrefix(f[i], "after="), ",")
		case strings.HasPrefix(f[i], "mem="):
			sc.memMax = strings.TrimPrefix(f[i], "mem=")
		case strings.HasPrefix(f[i], "cpu="):
			sc.cpuPct, _ = strconv.Atoi(strings.TrimSuffix(strings.TrimPrefix(f[i], "cpu="), "%"))
		default:
			break loop
		}
		i++
	}
	if i >= len(f) {
		return nil, fmt.Errorf("missing service name")
	}
	sc.name = f[i]
	sc.argv = f[i+1:]
	if len(sc.argv) == 0 {
		return nil, fmt.Errorf("missing command for %q", sc.name)
	}
	return &sc, nil
}

// startConfiguredServices supervises the daemons listed in services.conf.
func startConfiguredServices() {
	data, err := os.ReadFile(confDir + "/services.conf")
	if err != nil {
		return
	}
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		sc, err := parseServiceLine(line)
		if err != nil {
			logf("services.conf: ignoring malformed line %q: %v", line, err)
			continue
		}
		superviseConf(sc)
	}
}

// ---- timers --------------------------------------------------------------

type timerConf struct {
	name     string
	argv     []string
	interval time.Duration
}

type svcTimer struct {
	timerConf
	mu       sync.Mutex
	lastRun  time.Time
	lastExit int
	ran      bool
	nextRun  time.Time
}

var (
	timerMu    sync.Mutex
	timers     = map[string]*svcTimer{}
	timerOrder []string
)

// parseDuration extends time.ParseDuration with a "d" (day) suffix.
func parseDuration(s string) (time.Duration, error) {
	if strings.HasSuffix(s, "d") {
		n, err := strconv.Atoi(strings.TrimSuffix(s, "d"))
		if err != nil {
			return 0, err
		}
		return time.Duration(n) * 24 * time.Hour, nil
	}
	return time.ParseDuration(s)
}

// parseTimerLine parses "<name> every=<duration> <command> [args...]".
func parseTimerLine(line string) (*timerConf, error) {
	f := strings.Fields(line)
	if len(f) < 3 || !strings.HasPrefix(f[1], "every=") {
		return nil, fmt.Errorf("expected: <name> every=<duration> <command> [args...]")
	}
	d, err := parseDuration(strings.TrimPrefix(f[1], "every="))
	if err != nil {
		return nil, fmt.Errorf("bad interval: %w", err)
	}
	return &timerConf{name: f[0], interval: d, argv: f[2:]}, nil
}

func startConfiguredTimers() {
	data, err := os.ReadFile(confDir + "/timers.conf")
	if err != nil {
		return
	}
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		tc, err := parseTimerLine(line)
		if err != nil {
			logf("timers.conf: ignoring malformed line %q: %v", line, err)
			continue
		}
		t := &svcTimer{timerConf: *tc, nextRun: time.Now().Add(tc.interval)}
		timerMu.Lock()
		timers[tc.name] = t
		timerOrder = append(timerOrder, tc.name)
		timerMu.Unlock()
		go t.loop()
	}
}

func (t *svcTimer) loop() {
	for !shuttingDown.Load() {
		t.mu.Lock()
		wait := time.Until(t.nextRun)
		t.mu.Unlock()
		if wait > 0 {
			time.Sleep(wait)
		}
		if shuttingDown.Load() {
			return
		}
		t.mu.Lock()
		t.lastRun, t.ran = time.Now(), true
		t.mu.Unlock()
		code, err := runCode(t.argv[0], t.argv[1:]...)
		if err != nil {
			logf("timer %s: %v", t.name, err)
		}
		t.mu.Lock()
		t.lastExit = code
		t.nextRun = time.Now().Add(t.interval)
		t.mu.Unlock()
	}
}

// ---- console shell -----------------------------------------------------

func consoleShell() {
	tty := os.Getenv("LENINE_TTY")
	if tty == "" {
		tty = "/dev/tty1"
		if _, err := os.Stat(confDir + "/display-manager"); err == nil {
			tty = "/dev/tty2" // the sign-in screen owns tty1; a text console stays on Ctrl+Alt+F2
		}
	}
	first := true
	for !shuttingDown.Load() {
		f, err := os.OpenFile(tty, os.O_RDWR, 0)
		if err != nil {
			logf("open %s: %v", tty, err)
			if tty != "/dev/console" {
				tty = "/dev/console"
			}
			time.Sleep(time.Second)
			continue
		}
		if first {
			f.WriteString(banner)
			first = false
		} else {
			f.WriteString("\n")
		}

		env := []string{
			"PATH=" + defaultPath, "HOME=/root", "USER=root", "LOGNAME=root",
			"SHELL=/bin/sh", "TERM=linux",
		}
		var cmd *exec.Cmd
		agetty, agettyErr := exec.LookPath("agetty")
		autoUser := ""
		if b, err := os.ReadFile(confDir + "/autologin"); err == nil {
			autoUser = strings.TrimSpace(string(b))
		}
		if agettyErr == nil && autoUser != "" {
			// Autologin (live session, or an installed system set to log in by itself): wait for the
			// login-session daemon so the session is registered with it.
			waitForPath("/run/systemd/seats/seat0", 15*time.Second)
			cmd = exec.Command(agetty, "--autologin", autoUser, "--noclear", strings.TrimPrefix(tty, "/dev/"), "linux")
			cmd.Env = env
			cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
		} else if agettyErr == nil && pathExists(confDir+"/login") {
			// Installed system: agetty opens the tty itself and runs login.
			cmd = exec.Command(agetty, "--noclear", strings.TrimPrefix(tty, "/dev/"), "linux")
			cmd.Env = env
			cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
		} else {
			cmd = exec.Command("/bin/sh")
			cmd.Args = []string{"-sh"} // leading '-' makes it a login shell
			cmd.Stdin, cmd.Stdout, cmd.Stderr = f, f, f
			cmd.Env = env
			if fi, err := os.Stat("/root"); err == nil && fi.IsDir() {
				cmd.Dir = "/root"
			}
			cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true, Setctty: true, Ctty: 0}
		}

		began := time.Now()
		_, ch, err := start(cmd)
		f.Close()
		if err != nil {
			logf("shell: cannot start: %v", err)
			time.Sleep(time.Second)
			continue
		}
		<-ch
		if time.Since(began) < 500*time.Millisecond { // guard against a spin loop
			time.Sleep(time.Second)
		}
	}
	select {} // shutting down: PID 1 must never return
}

// ---- shutdown ----------------------------------------------------------

func handleSignals() {
	c := make(chan os.Signal, 4)
	signal.Notify(c, syscall.SIGINT, syscall.SIGTERM, syscall.SIGUSR1, syscall.SIGUSR2)
	for s := range c {
		switch s {
		case syscall.SIGUSR1:
			shutdown(syscall.LINUX_REBOOT_CMD_HALT)
		case syscall.SIGUSR2:
			shutdown(syscall.LINUX_REBOOT_CMD_POWER_OFF)
		default:
			shutdown(syscall.LINUX_REBOOT_CMD_RESTART)
		}
	}
}

func shutdown(cmd int) {
	if !shuttingDown.CompareAndSwap(false, true) {
		return
	}
	logf("shutting down")
	syscall.Kill(-1, syscall.SIGTERM)
	time.Sleep(2 * time.Second)
	syscall.Kill(-1, syscall.SIGKILL)
	time.Sleep(200 * time.Millisecond)
	// Leave installed disks clean: unmount extra filesystems, root read-only
	// (the RAM-disk root just refuses the remount, which is fine).
	run("umount", "-a", "-r")
	syscall.Mount("", "/", "", syscall.MS_REMOUNT|syscall.MS_RDONLY, "")
	syscall.Sync()
	if err := syscall.Reboot(cmd); err != nil {
		logf("reboot: %v", err)
	}
}

func main() {
	if os.Getpid() != 1 {
		os.Exit(clientMain()) // reboot/poweroff/halt/status/... talk to PID 1
	}
	// PID 1 must never exit: a panic would take the kernel down with it.
	defer func() {
		if r := recover(); r != nil {
			logf("fatal: %v", r)
			select {}
		}
	}()

	os.Setenv("PATH", defaultPath)
	syscall.Umask(0o022)
	initReaper()

	mountCore()
	openLog()
	silenceKernelLog()
	setupDevLinks()
	setHostname()
	syscall.Reboot(syscall.LINUX_REBOOT_CMD_CAD_OFF) // Ctrl-Alt-Del -> SIGINT
	go handleSignals()
	serveControl()

	go markBootGood() // installed images: a trial boot becomes the default once the system has stayed up
	go serialShell()  // lenine.serial=1: a root shell on the first serial port (debugging, VMs, headless boards)
	udev := startUdev()
	go mountFstab(udev)
	startNetworking()
	startConfiguredServices()
	startConfiguredTimers()
	consoleShell()
}

// serialShell runs a respawning root shell on /dev/ttyS0 when the kernel command line has
// lenine.serial=1 (add console=ttyS0 to see kernel messages there too).
func serialShell() {
	b, err := os.ReadFile("/proc/cmdline")
	if err != nil || !strings.Contains(string(b), "lenine.serial=1") {
		return
	}
	for !shuttingDown.Load() {
		f, err := os.OpenFile("/dev/ttyS0", os.O_RDWR, 0)
		if err != nil {
			time.Sleep(2 * time.Second)
			continue
		}
		cmd := exec.Command("/bin/sh")
		cmd.Args = []string{"-sh"}
		cmd.Stdin, cmd.Stdout, cmd.Stderr = f, f, f
		cmd.Env = []string{"PATH=" + defaultPath, "HOME=/root", "USER=root", "LOGNAME=root", "SHELL=/bin/sh", "TERM=vt100"}
		cmd.Dir = "/"
		cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true, Setctty: true, Ctty: 0}
		began := time.Now()
		_, ch, err := start(cmd)
		f.Close()
		if err != nil {
			time.Sleep(2 * time.Second)
			continue
		}
		<-ch
		if time.Since(began) < 500*time.Millisecond {
			time.Sleep(time.Second)
		}
	}
}

// cmdlineValue returns the value of key (e.g. "lenine.version=") on the kernel command line.
func cmdlineValue(cmdline, key string) string {
	for _, f := range strings.Fields(cmdline) {
		if strings.HasPrefix(f, key) {
			return strings.TrimPrefix(f, key)
		}
	}
	return ""
}

// capture runs a command and returns its standard output.
func capture(name string, args ...string) (string, error) {
	r, w, err := os.Pipe()
	if err != nil {
		return "", err
	}
	cmd := exec.Command(name, args...)
	cmd.Stdout = w
	_, ch, err := start(cmd)
	w.Close()
	if err != nil {
		r.Close()
		return "", err
	}
	var sb strings.Builder
	buf := make([]byte, 4096)
	for {
		n, err := r.Read(buf)
		sb.Write(buf[:n])
		if err != nil {
			break
		}
	}
	r.Close()
	if code := <-ch; code != 0 {
		return sb.String(), fmt.Errorf("%s exited with status %d", name, code)
	}
	return sb.String(), nil
}

// markBootGood makes a trial boot permanent. `goget upgrade` boots a new image once (grub-reboot);
// if the system stays up for a minute, that image works, so it becomes GRUB's default. If it never
// gets here (crash, hang, power cycle) the next boot falls back to the previous default.
func markBootGood() {
	b, err := os.ReadFile("/proc/cmdline")
	if err != nil {
		return
	}
	ver := cmdlineValue(string(b), "lenine.version=")
	if ver == "" || cmdlineValue(string(b), "lenine.image=") == "" {
		return // the live medium, or a system without versioned images
	}
	time.Sleep(60 * time.Second)
	out, err := capture("grub-editenv", "/data/boot/grub/grubenv", "list")
	if err != nil {
		logf("boot check: cannot read grubenv: %v", err)
		return
	}
	saved := ""
	for _, line := range strings.Split(out, "\n") {
		if strings.HasPrefix(line, "saved_entry=") {
			saved = strings.TrimPrefix(line, "saved_entry=")
		}
	}
	if saved == ver {
		return
	}
	if err := run("grub-set-default", "--boot-directory=/data/boot", ver); err != nil {
		logf("boot check: could not make %s the default: %v", ver, err)
		return
	}
	logf("image %s booted fine and is now the default (was %q)", ver, saved)
}
