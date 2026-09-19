package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"os/user"
	"strings"
)

func groupExists(name string) bool {
	_, err := user.LookupGroup(name)
	return err == nil
}

// readMaskedLine reads a line with terminal echo disabled via `stty`
// (falling back to a plain read if stdin isn't a tty, e.g. piped input
// during testing) rather than failing outright. Never prints asterisks
// or any other stand-in for the typed characters -- genuinely
// suppresses echo, matching how passwd/sudo prompts behave.
func readMaskedLine(promptMsg string) (string, bool) {
	fmt.Print(promptMsg)

	haveTTY := isTerminal(os.Stdin)
	if haveTTY {
		exec.Command("stty", "-F", "/dev/tty", "-echo").Run()
		defer exec.Command("stty", "-F", "/dev/tty", "echo").Run()
	}

	reader := bufio.NewReader(os.Stdin)
	line, err := reader.ReadString('\n')
	fmt.Println() // the Enter keypress's newline was never echoed either
	if err != nil && line == "" {
		return "", false
	}
	return strings.TrimRight(line, "\r\n"), true
}

// detectAdminGroup resolves which group grants admin/sudo privileges on
// this system. Only one of wheel/sudo existing is used automatically;
// if both exist or neither does, the operator running makeuser is
// asked.
func detectAdminGroup() (string, bool) {
	hasWheel := groupExists("wheel")
	hasSudo := groupExists("sudo")

	if hasWheel && !hasSudo {
		return "wheel", true
	}
	if hasSudo && !hasWheel {
		return "sudo", true
	}
	if hasWheel && hasSudo {
		fmt.Println("Both 'wheel' and 'sudo' admin groups exist on this system.")
		idx := promptPick([]string{"wheel", "sudo"})
		if idx < 0 {
			return "", false
		}
		return []string{"wheel", "sudo"}[idx], true
	}

	fmt.Println("Neither 'wheel' nor 'sudo' admin group exists on this system.")
	name, ok := promptLine("Admin group name to use (created if it doesn't exist): ")
	if !ok || name == "" {
		return "", false
	}
	return name, true
}

// makeuserRun interactively creates a new user account: prompts for
// username, masked password (twice, to confirm), and whether to add
// them to the system's admin group. Must be run as root.
func makeuserRun() int {
	if os.Geteuid() != 0 {
		fmt.Fprintln(os.Stderr, "goget: makeuser must be run as root.")
		return 1
	}

	username, ok := promptLine("Username: ")
	if !ok || username == "" {
		fmt.Fprintln(os.Stderr, "goget: no username given, aborting.")
		return 1
	}

	var password string
	for attempt := 0; attempt < 3 && password == ""; attempt++ {
		p1, ok1 := readMaskedLine("Password: ")
		p2, ok2 := readMaskedLine("Confirm password: ")
		if ok1 && ok2 && p1 != "" && p1 == p2 {
			password = p1
		} else {
			fmt.Println("Passwords did not match (or were empty); try again.")
		}
	}
	if password == "" {
		fmt.Fprintln(os.Stderr, "goget: too many failed password attempts, aborting.")
		return 1
	}

	group, haveGroup := detectAdminGroup()
	addToAdmin := false
	if haveGroup {
		addToAdmin = promptYesNo(fmt.Sprintf("Add '%s' to the admin group (%s)?", username, group), false)
	}

	if rc := runCommand("", []string{"useradd", "-m", username}); rc != 0 {
		fmt.Fprintf(os.Stderr, "goget: useradd failed for '%s'\n", username)
		return 1
	}

	// chpasswd (not passwd) because it takes "user:password" over stdin
	// non-interactively; plain passwd on many distros expects an
	// interactive terminal.
	if rc := runCommandWithStdin([]string{"chpasswd"}, username+":"+password+"\n"); rc != 0 {
		fmt.Fprintf(os.Stderr, "goget: setting password failed for '%s'\n", username)
		return 1
	}
	password = "" // best-effort: drop our only reference so it can be GC'd promptly

	if addToAdmin && haveGroup {
		if !groupExists(group) {
			runCommand("", []string{"groupadd", group}) // usermod below fails loudly if this didn't work
		}
		if rc := runCommand("", []string{"usermod", "-aG", group, username}); rc != 0 {
			fmt.Fprintf(os.Stderr, "goget: usermod failed to add '%s' to group '%s'\n", username, group)
			return 1
		}
	}

	suffix := ""
	if addToAdmin {
		suffix = " (admin)"
	}
	fmt.Printf("goget: created user '%s'%s\n", username, suffix)
	return 0
}
