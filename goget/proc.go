package main

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"sync/atomic"
	"time"
)

// exitCodeFromError converts the error from cmd.Wait() into the same
// convention run_command used in the C version: 0-255 on normal exit,
// -1 if the process was killed by a signal or couldn't be started.
func exitCodeFromError(err error) int {
	if err == nil {
		return 0
	}
	if exitErr, ok := err.(*exec.ExitError); ok {
		if exitErr.ProcessState.Exited() {
			return exitErr.ExitCode()
		}
		fmt.Fprintf(os.Stderr, "goget: process was killed by signal: %v\n", exitErr)
		return -1
	}
	fmt.Fprintf(os.Stderr, "goget: %v\n", err)
	return -1
}

// runCommand runs argv (no shell -- argv[0] found via PATH, so no
// argument is ever subject to shell interpretation), inheriting
// stdin/stdout/stderr so interactive prompts (sudo's password prompt)
// and a tool's own progress output work normally. cwd may be "" to
// inherit the caller's working directory.
func runCommand(cwd string, argv []string) int {
	cmd := exec.Command(argv[0], argv[1:]...)
	cmd.Dir = cwd
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return exitCodeFromError(cmd.Run())
}

// runCommandCapture runs argv and captures its stdout into a string,
// discarding stderr. Used for parsing tool output, not for anything
// interactive.
func runCommandCapture(argv []string) (string, int) {
	cmd := exec.Command(argv[0], argv[1:]...)
	var out bytes.Buffer
	cmd.Stdout = &out
	err := cmd.Run()
	return out.String(), exitCodeFromError(err)
}

// runCommandWithStdin runs argv, feeding input to its stdin (then
// closing it) instead of inheriting the caller's stdin. Used for
// chpasswd, which reads "user:password\n" from stdin rather than taking
// it as an argument (an argument would leak the password via
// /proc/<pid>/cmdline).
func runCommandWithStdin(argv []string, input string) int {
	cmd := exec.Command(argv[0], argv[1:]...)
	cmd.Stdin = strings.NewReader(input)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return exitCodeFromError(cmd.Run())
}

var spinnerFrames = []string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}

// lastCmakePercent scans buf for cmake's own "[ NN%]" build-progress
// marker and returns the LAST one found (cmake emits one per compiled
// file; the most recent is the current progress), or -1 if none.
func lastCmakePercent(buf []byte) int {
	best := -1
	for i := 0; i < len(buf); i++ {
		if buf[i] != '[' {
			continue
		}
		j := i + 1
		for j < len(buf) && buf[j] == ' ' {
			j++
		}
		digitStart := j
		val := 0
		for j < len(buf) && buf[j] >= '0' && buf[j] <= '9' {
			val = val*10 + int(buf[j]-'0')
			j++
		}
		if j == digitStart || j >= len(buf) || buf[j] != '%' {
			continue
		}
		j++
		if j >= len(buf) || buf[j] != ']' {
			continue
		}
		best = val
	}
	return best
}

// runCommandSpinner is like runCommand, but for long-running, noisy
// commands (compiling, cloning) whose line-by-line output is only
// interesting when something goes wrong: stdout+stderr are captured
// (not shown live) while a colored, animated one-line spinner labeled
// `label` plays instead. On success the spinner line is cleared and the
// captured output discarded; on failure the spinner line is cleared and
// the FULL captured output is dumped to stdout before returning, so
// real compiler/linker errors are never actually hidden -- only the
// "everything's fine so far" noise is.
//
// If parseCmakePercent is true, cmake's own "[ NN%]" build-progress
// markers are parsed out of the stream and drive a numeric percentage
// in the spinner instead of a bare animation.
//
// When stdout isn't a real terminal, an animated \r-based spinner would
// just be garbage, so this falls back to runCommand's plain passthrough
// behavior, live output and all.
//
// Deliberately NOT used for anything that needs the live terminal
// itself mid-command (sudo's password prompt): those keep using
// runCommand directly.
func runCommandSpinner(cwd string, argv []string, label string, parseCmakePercent bool) int {
	if !isTerminal(os.Stdout) {
		return runCommand(cwd, argv)
	}

	cmd := exec.Command(argv[0], argv[1:]...)
	cmd.Dir = cwd
	pr, pw := io.Pipe()
	cmd.Stdout = pw
	cmd.Stderr = pw

	if err := cmd.Start(); err != nil {
		fmt.Fprintf(os.Stderr, "goget: failed to run '%s': %v\n", argv[0], err)
		return 127
	}

	var buf bytes.Buffer
	var lastPercent int32 = -1
	readDone := make(chan struct{})
	go func() {
		defer close(readDone)
		chunk := make([]byte, 4096)
		for {
			n, err := pr.Read(chunk)
			if n > 0 {
				buf.Write(chunk[:n])
				if parseCmakePercent {
					if p := lastCmakePercent(chunk[:n]); p >= 0 {
						atomic.StoreInt32(&lastPercent, int32(p))
					}
				}
			}
			if err != nil {
				return
			}
		}
	}()

	waitErr := make(chan error, 1)
	go func() {
		waitErr <- cmd.Wait()
		pw.Close()
	}()

	colored := colorEnabledFor(os.Stdout)
	start := time.Now()
	frame := 0
	ticker := time.NewTicker(120 * time.Millisecond)
	defer ticker.Stop()

	for {
		select {
		case err := <-waitErr:
			<-readDone
			fmt.Print("\r\x1b[K")

			exitCode := exitCodeFromError(err)
			if exitCode != 0 {
				os.Stdout.Write(buf.Bytes())
			}
			return exitCode

		case <-ticker.C:
			elapsed := int(time.Since(start).Seconds())
			percent := atomic.LoadInt32(&lastPercent)
			if colored {
				fmt.Printf("\r%s%s%s %s", cCyan, spinnerFrames[frame], cReset, label)
				if percent >= 0 {
					fmt.Printf(" %s%3d%%%s", cBold, percent, cReset)
				}
				fmt.Printf(" %s(%ds)%s ", cDim, elapsed, cReset)
			} else {
				fmt.Printf("%s ", label)
				if percent >= 0 {
					fmt.Printf("%d%% ", percent)
				}
				fmt.Printf("(%ds) ", elapsed)
			}
			frame = (frame + 1) % len(spinnerFrames)
		}
	}
}
