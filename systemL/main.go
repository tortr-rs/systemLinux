// systemL - minimal PID 1 init for systemLinux v0.3.
//
// Boot sequence: core pseudo-filesystems -> udev -> loopback -> D-Bus ->
// NetworkManager -> respawning root shell on the console TTY.
// Build: CGO_ENABLED=0 go build -o systemL .   Install as /sbin/systemL and
// boot with init=/sbin/systemL.
//
// Runtime control (root): systemL status | start|stop|restart <service> |
// reboot | poweroff | halt. Invoked as reboot/poweroff/halt/shutdown it acts
// as that command.
//
// Config (all optional): /etc/systemL/login makes tty1 run agetty/login
// instead of an unauthenticated root shell; /etc/systemL/services.conf lists
// extra daemons to supervise, one "<name> <command> [args...]" per line
// (this is how `goget install` enables a display manager).
//
// PID 1 signals (busybox convention): SIGTERM/SIGINT reboot, SIGUSR1 halt,
// SIGUSR2 power off. Service logs go to /run/log/systemL/<name>.log.
// The console TTY defaults to /dev/tty1 (override with $SYSTEML_TTY).
package main

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
	"unsafe"
)

const (
	defaultPath = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
	logDir      = "/run/log/systemL"
	confDir     = "/etc/systemL"
	dbusSocket  = "/run/dbus/system_bus_socket"
	banner      = "\x1b[3J\x1b[2J\x1b[H\n" +
		"  +------------------------------------------+\n" +
		"  |                                          |\n" +
		"  |   systemLinux v0.3                       |\n" +
		"  |   (systemL Init Engine)                  |\n" +
		"  |                                          |\n" +
		"  +------------------------------------------+\n\n"
)

var (
	mu           sync.Mutex
	waiters      = map[int]chan int{} // pid -> exit code, guarded by mu
	shuttingDown atomic.Bool
)

func logf(format string, a ...any) {
	fmt.Fprintf(os.Stderr, "[systemL] "+format+"\n", a...)
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

// run executes a command to completion.
func run(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Stdout, cmd.Stderr = os.Stderr, os.Stderr
	_, ch, err := start(cmd)
	if err != nil {
		return err
	}
	if code := <-ch; code != 0 {
		return fmt.Errorf("%s exited with status %d", name, code)
	}
	return nil
}

// supervise registers a daemon and keeps it running in the background,
// restarting it with exponential backoff (1s..30s) whenever it exits. It can
// be controlled at runtime with `systemL start|stop|restart <name>`.
func supervise(name string, argv ...string) {
	sv := &service{name: name, argv: argv, wantUp: true, kick: make(chan struct{}, 1)}
	svcMu.Lock()
	services[name] = sv
	svcOrder = append(svcOrder, name)
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
	if err := os.Chmod("/tmp", 0o1777); err != nil {
		logf("chmod /tmp: %v", err)
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
	if err := os.WriteFile("/proc/sys/kernel/printk", []byte("3 4 1 3\n"), 0o644); err != nil {
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
		f := strings.Fields(line)
		if len(f) < 2 {
			logf("services.conf: ignoring malformed line %q", line)
			continue
		}
		supervise(f[0], f[1:]...)
	}
}

// ---- console shell -----------------------------------------------------

func consoleShell() {
	tty := os.Getenv("SYSTEML_TTY")
	if tty == "" {
		tty = "/dev/tty1"
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
		if agetty, err := exec.LookPath("agetty"); err == nil && pathExists(confDir+"/login") {
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
	silenceKernelLog()
	setupDevLinks()
	setHostname()
	syscall.Reboot(syscall.LINUX_REBOOT_CMD_CAD_OFF) // Ctrl-Alt-Del -> SIGINT
	go handleSignals()
	serveControl()

	udev := startUdev()
	go mountFstab(udev)
	startNetworking()
	startConfiguredServices()
	consoleShell()
}
