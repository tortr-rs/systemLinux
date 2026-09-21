package main

import (
	"os"
	"path/filepath"
	"strings"
	"time"
)

// Shared helpers of the package manager (see pm_nix*.go): the root it operates on, the channel setting,
// flag parsing and version comparison.

// pmRoot is the root all package operations act on ("/" unless --root or $GOGET_ROOT is given).
var pmRoot = "/"

func pmPath(rel string) string { return filepath.Join(pmRoot, rel) }

func pmNow() string { return time.Now().UTC().Format(time.RFC3339) }

type repoConf struct {
	kind, name, url string
	opts            map[string]string
}

const defaultChannel = "nixos-25.05"

func pmChannelFile() string { return pmPath("etc/goget/channel") }

// pmChannel is the nixpkgs channel packages come from ("nixos-25.05" or "nixos-unstable").
func pmChannel() string {
	if data, err := os.ReadFile(pmChannelFile()); err == nil {
		if c := strings.TrimSpace(string(data)); c != "" {
			return c
		}
	}
	return defaultChannel
}

func pmSetChannel(c string) error {
	if err := mkdirP(filepath.Dir(pmChannelFile())); err != nil {
		return err
	}
	return os.WriteFile(pmChannelFile(), []byte(c+"\n"), 0o644)
}

func nixRepo() *repoConf {
	return &repoConf{kind: "nix", name: "nixpkgs", url: "https://channels.nixos.org/" + pmChannel(),
		opts: map[string]string{"cache": "https://cache.nixos.org"}}
}

type pmOpts struct {
	yes  bool
	args []string
}

// nixForceSystem (--system) uses the system profile even when not running as root.
var nixForceSystem bool

// pmParse handles the flags shared by the package commands and applies --root.
func pmParse(args []string) pmOpts {
	var o pmOpts
	pmRoot = "/"
	if r := os.Getenv("GOGET_ROOT"); r != "" {
		pmRoot = r
	}
	for i := 0; i < len(args); i++ {
		switch a := args[i]; a {
		case "-y", "--yes":
			o.yes = true
		case "--system":
			nixForceSystem = true
		case "--root":
			if i+1 < len(args) {
				pmRoot = args[i+1]
				i++
			}
		default:
			o.args = append(o.args, a)
		}
	}
	return o
}

// ---- version comparison (epoch, then alternating digit/non-digit runs) ---------------------------------

func verCompare(a, b string) int {
	ea, ra := splitEpoch(a)
	eb, rb := splitEpoch(b)
	if ea != eb {
		if ea < eb {
			return -1
		}
		return 1
	}
	return cmpSegments(ra, rb)
}

func splitEpoch(v string) (int, string) {
	if i := strings.Index(v, ":"); i > 0 {
		n := 0
		for _, c := range v[:i] {
			if c < '0' || c > '9' {
				return 0, v
			}
			n = n*10 + int(c-'0')
		}
		return n, v[i+1:]
	}
	return 0, v
}

func cmpSegments(a, b string) int {
	order := func(c byte) int {
		switch {
		case c == '~':
			return -1
		case c >= 'a' && c <= 'z', c >= 'A' && c <= 'Z':
			return int(c)
		default:
			return int(c) + 256
		}
	}
	for a != "" || b != "" {
		for (a != "" && !isDigit(a[0])) || (b != "" && !isDigit(b[0])) {
			var ca, cb int
			if a != "" && !isDigit(a[0]) {
				ca = order(a[0])
			}
			if b != "" && !isDigit(b[0]) {
				cb = order(b[0])
			}
			if ca != cb {
				if ca < cb {
					return -1
				}
				return 1
			}
			if a != "" && !isDigit(a[0]) {
				a = a[1:]
			}
			if b != "" && !isDigit(b[0]) {
				b = b[1:]
			}
		}
		var da, db string
		for a != "" && isDigit(a[0]) {
			da += string(a[0])
			a = a[1:]
		}
		for b != "" && isDigit(b[0]) {
			db += string(b[0])
			b = b[1:]
		}
		da, db = strings.TrimLeft(da, "0"), strings.TrimLeft(db, "0")
		if len(da) != len(db) {
			if len(da) < len(db) {
				return -1
			}
			return 1
		}
		if da != db {
			if da < db {
				return -1
			}
			return 1
		}
	}
	return 0
}

func isDigit(c byte) bool { return c >= '0' && c <= '9' }
