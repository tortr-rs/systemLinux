package main

import (
	"fmt"
	"os"
)

// Shared ANSI escape codes -- exposed as constants (not hidden inside the
// print* helpers) so other files that need raw terminal control the
// print* API doesn't cover (the spinner in proc.go, the download bar in
// net.go) match the same palette instead of inventing their own.
const (
	cReset   = "\x1b[0m"
	cBold    = "\x1b[1m"
	cDim     = "\x1b[2m"
	cRed     = "\x1b[31m"
	cGreen   = "\x1b[32m"
	cYellow  = "\x1b[33m"
	cBlue    = "\x1b[34m"
	cMagenta = "\x1b[35m"
	cCyan    = "\x1b[36m"
)

// isTerminal reports whether f is a real terminal device, with no
// external dependency: a char device is exactly what a tty is, and
// files/pipes/sockets never set that mode bit.
func isTerminal(f *os.File) bool {
	fi, err := f.Stat()
	if err != nil {
		return false
	}
	return fi.Mode()&os.ModeCharDevice != 0
}

// colorEnabledFor reports whether ANSI color codes should be emitted to
// stream: true only when it's a real terminal and $NO_COLOR isn't set.
func colorEnabledFor(f *os.File) bool {
	if os.Getenv("NO_COLOR") != "" {
		return false
	}
	return isTerminal(f)
}

func printTagged(stream *os.File, color, symbol, format string, a ...any) {
	colored := colorEnabledFor(stream)
	if colored {
		fmt.Fprintf(stream, "%s%s%s%s ", color, cBold, symbol, cReset)
	} else {
		fmt.Fprintf(stream, "%s ", symbol)
	}
	if colored {
		fmt.Fprint(stream, color)
	}
	fmt.Fprintf(stream, format, a...)
	if colored {
		fmt.Fprint(stream, cReset)
	}
	fmt.Fprintln(stream)
}

func printOK(format string, a ...any) {
	printTagged(os.Stdout, cGreen, "✓", format, a...)
}

func printInfo(format string, a ...any) {
	colored := colorEnabledFor(os.Stdout)
	if colored {
		fmt.Fprintf(os.Stdout, "%s%sgoget:%s ", cCyan, cBold, cReset)
	} else {
		fmt.Fprint(os.Stdout, "goget: ")
	}
	if colored {
		fmt.Fprint(os.Stdout, cCyan)
	}
	fmt.Fprintf(os.Stdout, format, a...)
	if colored {
		fmt.Fprint(os.Stdout, cReset)
	}
	fmt.Fprintln(os.Stdout)
}

func printWarn(format string, a ...any) {
	printTagged(os.Stdout, cYellow, "!", format, a...)
}

func printErr(format string, a ...any) {
	colored := colorEnabledFor(os.Stderr)
	if colored {
		fmt.Fprintf(os.Stderr, "%s%sgoget:%s ", cRed, cBold, cReset)
	} else {
		fmt.Fprint(os.Stderr, "goget: ")
	}
	if colored {
		fmt.Fprint(os.Stderr, cRed)
	}
	fmt.Fprintf(os.Stderr, format, a...)
	if colored {
		fmt.Fprint(os.Stderr, cReset)
	}
	fmt.Fprintln(os.Stderr)
}
