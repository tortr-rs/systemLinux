package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
)

// The one place in goget that reads a line of interactive input. Every
// prompt function below goes through this, never reading stdin directly
// -- important because a single run can chain multiple prompts (e.g.
// "host disabled, allow it?" followed later by "no compatible binary,
// build from source instead?"), and they must not lose input the user
// already typed ahead of a prompt appearing.
var stdinReader = bufio.NewReader(os.Stdin)

func readLine() (string, bool) {
	line, err := stdinReader.ReadString('\n')
	if err != nil && line == "" {
		return "", false
	}
	return strings.TrimRight(line, "\r\n"), true
}

// promptYesNo prints "message [Y/n] " (or "[y/N] " if defaultYes is
// false), reads a line, and returns true for yes, false for no. Empty
// input takes the default. Reprompts on unrecognized input; returns
// false if stdin hits EOF.
func promptYesNo(message string, defaultYes bool) bool {
	suffix := "y/N"
	if defaultYes {
		suffix = "Y/n"
	}
	for {
		fmt.Printf("%s [%s] ", message, suffix)
		line, ok := readLine()
		if !ok {
			fmt.Println()
			return false
		}
		s := strings.TrimSpace(line)
		if s == "" {
			return defaultYes
		}
		switch s[0] {
		case 'y', 'Y':
			return true
		case 'n', 'N':
			return false
		}
		fmt.Println("Please answer 'y' or 'n'.")
	}
}

// promptPick prints labels as a 1-based numbered list and reads a
// selection. Returns the 0-based index chosen, or -1 if the user typed
// 'c'/'C' to cancel or stdin hit EOF. Reprompts on invalid input.
func promptPick(labels []string) int {
	for {
		for i, l := range labels {
			fmt.Printf("  %d) %s\n", i+1, l)
		}
		fmt.Printf("Select 1-%d, or 'c' to cancel: ", len(labels))
		line, ok := readLine()
		if !ok {
			fmt.Println()
			return -1
		}
		s := strings.TrimSpace(line)
		if s == "" {
			fmt.Println("Invalid selection.")
			continue
		}
		if s[0] == 'c' || s[0] == 'C' {
			return -1
		}
		v, err := strconv.Atoi(s)
		if err == nil && v >= 1 && v <= len(labels) {
			return v - 1
		}
		fmt.Println("Invalid selection.")
	}
}

// promptOnceAlwaysCancel is the three-way prompt used by the config
// host allow-list override. Returns 'o', 'a', or 'c'; reprompts on
// invalid input, returns 'c' on EOF.
func promptOnceAlwaysCancel(message string) byte {
	for {
		fmt.Printf("%s [Once/Always/Cancel] ", message)
		line, ok := readLine()
		if !ok {
			fmt.Println()
			return 'c'
		}
		s := strings.TrimSpace(line)
		if s != "" {
			switch s[0] | 0x20 { // lowercase
			case 'o':
				return 'o'
			case 'a':
				return 'a'
			case 'c':
				return 'c'
			}
		}
		fmt.Println("Please choose Once, Always, or Cancel.")
	}
}

// promptLine prints message (no trailing newline added), reads one
// line, and returns a trimmed copy (may be empty). Returns "", false on
// EOF.
func promptLine(message string) (string, bool) {
	fmt.Print(message)
	line, ok := readLine()
	if !ok {
		return "", false
	}
	return strings.TrimSpace(line), true
}
