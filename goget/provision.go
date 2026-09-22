package main

import (
	"bufio"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// Target-environment provisioning for a hard drive install: brand identity,
// login banner, the default user with explicit groups, and the wheel sudo
// rule. Every function takes the target root (e.g. "/mnt/target") and only
// touches files under it, so it is safe to run against a mounted install.

const (
	brandName    = "systemLinux"
	brandVersion = "1.0"
)

// provisionGroups are the explicit groups every provisioned user joins.
var provisionGroups = []string{"wheel", "networkmanager"}

const bannerScript = `# systemLinux login banner (installed by goget)
if [ -t 1 ] && [ -z "${SYSTEMLINUX_BANNER:-}" ]; then
	SYSTEMLINUX_BANNER=1
	export SYSTEMLINUX_BANNER
	printf '\033[38;5;179m'
	cat <<'SYSTEMLINUX_CAT'

        ,
       /|\
     ,/ | \,
     \\ | //
    ,/\\|//\,
    \\ \|/ //
     '\ | /'
   \     |     /
    '-.  |  .-'
        \|/
         |

SYSTEMLINUX_CAT
	printf '  systemLinux v1.0 GNU/Linux\n\n\033[0m'
fi
`

type provisionConfig struct {
	user     string
	password string
	sudo     bool // add the wheel sudo rule (only applied when user is set)
}

// provisionWrite replaces rel under root with content. An existing file or
// symlink is removed first so writing never follows a link out of the target
// (e.g. /etc/os-release -> ../usr/lib/os-release).
func provisionWrite(root, rel, content string, mode os.FileMode) error {
	path := filepath.Join(root, rel)
	if err := mkdirP(filepath.Dir(path)); err != nil {
		return err
	}
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		return err
	}
	return os.WriteFile(path, []byte(content), mode)
}

// provisionIdentity writes the branded /etc/issue, release files and os-release.
func provisionIdentity(root string) error {
	release := fmt.Sprintf("%s GNU/Linux release %s\n", brandName, brandVersion)
	files := []struct{ rel, content string }{
		{"etc/issue", fmt.Sprintf("%s v%s GNU/Linux (\\l)\n", brandName, brandVersion)},
		{"etc/release", release},
		{"etc/os-release", fmt.Sprintf(
			"NAME=\"%s\"\nVERSION=\"%s\"\nID=systemlinux\nPRETTY_NAME=\"%s v%s GNU/Linux (lenine Core)\"\nVERSION_ID=\"%s\"\n",
			brandName, brandVersion, brandName, brandVersion, brandVersion)},
	}
	for _, f := range files {
		if err := provisionWrite(root, f.rel, f.content, 0o644); err != nil {
			return fmt.Errorf("write %s: %w", f.rel, err)
		}
	}
	return nil
}

// provisionBanner installs the cyan mascot as a profile.d script so every
// interactive login session shows it.
func provisionBanner(root string) error {
	return provisionWrite(root, "etc/profile.d/systemlinux.sh", bannerScript, 0o644)
}

// provisionSudoers appends the wheel rule to /etc/sudoers.d/10_wheel
// (idempotent), keeping the drop-in mode 0440 as sudo requires.
func provisionSudoers(root string) error {
	const rule = "%wheel ALL=(ALL:ALL) ALL"
	path := filepath.Join(root, "etc/sudoers.d/10_wheel")
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		return err
	}
	existing, err := os.ReadFile(path)
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	for _, line := range strings.Split(string(existing), "\n") {
		if strings.TrimSpace(line) == rule {
			return os.Chmod(path, 0o440)
		}
	}
	content := string(existing)
	if content != "" && !strings.HasSuffix(content, "\n") {
		content += "\n"
	}
	content += rule + "\n"
	if err := os.WriteFile(path, []byte(content), 0o440); err != nil {
		return err
	}
	return os.Chmod(path, 0o440)
}

func targetHasEntry(root, dbFile, name string) bool {
	f, err := os.Open(filepath.Join(root, "etc", dbFile))
	if err != nil {
		return false
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		if first, _, ok := strings.Cut(sc.Text(), ":"); ok && first == name {
			return true
		}
	}
	return false
}

// provisionEnsureGroups creates any of provisionGroups missing on the target
// (useradd -G fails on unknown groups).
func provisionEnsureGroups(root string) error {
	for _, g := range provisionGroups {
		if targetHasEntry(root, "group", g) {
			continue
		}
		if rc := runCommand("", []string{"groupadd", "-R", root, "-r", g}); rc != 0 {
			return fmt.Errorf("groupadd %s failed (exit %d)", g, rc)
		}
	}
	return nil
}

// provisionUser creates cfg.user (home + skeleton) in wheel and
// networkmanager and sets the password. An existing user just gets the groups.
func provisionUser(root string, cfg provisionConfig) error {
	if cfg.user == "" || strings.ContainsAny(cfg.user, ":\n\r \t/") {
		return fmt.Errorf("invalid user name %q", cfg.user)
	}
	if cfg.password == "" || strings.ContainsAny(cfg.password, "\n\r") {
		return fmt.Errorf("user %s needs a single-line, non-empty password", cfg.user)
	}
	if err := provisionEnsureGroups(root); err != nil {
		return err
	}

	groups := strings.Join(provisionGroups, ",")
	if targetHasEntry(root, "passwd", cfg.user) {
		if rc := runCommand("", []string{"usermod", "-R", root, "-aG", groups, cfg.user}); rc != 0 {
			return fmt.Errorf("usermod %s failed (exit %d)", cfg.user, rc)
		}
	} else {
		shell := "/bin/sh"
		if pathExists(filepath.Join(root, "bin/bash")) {
			shell = "/bin/bash"
		}
		argv := []string{"useradd", "-R", root, "-m", "-s", shell, "-G", groups, cfg.user}
		if rc := runCommand("", argv); rc != 0 {
			return fmt.Errorf("useradd %s failed (exit %d)", cfg.user, rc)
		}
	}
	// chpasswd reads stdin, so the password never appears in the process list.
	if rc := runCommandWithStdin([]string{"chpasswd", "-R", root}, cfg.user+":"+cfg.password+"\n"); rc != 0 {
		return fmt.Errorf("chpasswd for %s failed (exit %d)", cfg.user, rc)
	}
	return nil
}

// provisionTarget runs the whole sequence against a mounted target root.
func provisionTarget(root string, cfg provisionConfig) error {
	if err := provisionIdentity(root); err != nil {
		return err
	}
	if err := provisionBanner(root); err != nil {
		return err
	}
	if cfg.user == "" {
		return nil
	}
	if err := provisionUser(root, cfg); err != nil {
		return err
	}
	if cfg.sudo {
		if !pathExists(filepath.Join(root, "usr/bin/sudo")) {
			printWarn("sudo is not installed in the target; %s is in wheel but has no sudo", cfg.user)
		}
		return provisionSudoers(root)
	}
	return nil
}

// provisionRun implements `goget provision <root> [--user NAME] [--no-sudo]`:
// brand a target root (or the live rootfs at build time) and optionally
// create its first user, prompting for the password.
func provisionRun(args []string) int {
	fs := flag.NewFlagSet("provision", flag.ContinueOnError)
	user := fs.String("user", "", "also create this user (prompts for a password)")
	noSudo := fs.Bool("no-sudo", false, "do not add the wheel sudo rule")
	fs.Usage = func() {
		fmt.Fprintln(os.Stderr, "usage: goget provision [--user NAME] [--no-sudo] <root>   (requires root)")
		fs.PrintDefaults()
	}
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if fs.NArg() != 1 {
		fs.Usage()
		return 2
	}
	if os.Geteuid() != 0 {
		printErr("provision must be run as root")
		return 1
	}
	root := fs.Arg(0)
	if !pathIsDir(filepath.Join(root, "etc")) {
		printErr("%s does not look like a system root (no etc/)", root)
		return 1
	}

	cfg := provisionConfig{user: *user, sudo: !*noSudo}
	if cfg.user != "" {
		for attempt := 0; attempt < 3 && cfg.password == ""; attempt++ {
			p1, ok1 := readMaskedLine("Password for " + cfg.user + ": ")
			p2, ok2 := readMaskedLine("Confirm password: ")
			if ok1 && ok2 && p1 != "" && p1 == p2 {
				cfg.password = p1
			} else {
				fmt.Println("Passwords did not match (or were empty); try again.")
			}
		}
		if cfg.password == "" {
			printErr("too many failed password attempts")
			return 1
		}
	}
	if err := provisionTarget(root, cfg); err != nil {
		printErr("provision failed: %v", err)
		return 1
	}
	printOK("provisioned %s (%s v%s)", root, brandName, brandVersion)
	return 0
}
