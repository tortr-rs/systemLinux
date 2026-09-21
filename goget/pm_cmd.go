package main

import (
	"fmt"
	"os"
	"strings"
)

// The command layer of the package manager. Everything here is the Nix-style store model in pm_nix*.go.

func cmdInstall(args []string) int {
	o := pmParse(args)
	if len(o.args) == 0 {
		fmt.Fprintln(os.Stderr, "usage: goget install [-y] <package|owner/repo>...")
		return 1
	}
	var names, gits []string
	for _, a := range o.args {
		if strings.Contains(a, "/") || strings.Contains(a, "://") {
			gits = append(gits, a)
		} else {
			names = append(names, a)
		}
	}
	rc := 0
	if len(names) > 0 {
		rc = nixInstall(o, names)
	}
	for _, g := range gits { // owner/repo names build from Git hosts
		if c := cmdBuild(g, false); c != 0 {
			rc = c
		}
	}
	return rc
}

func cmdRemove(args []string) int {
	o := pmParse(args)
	if len(o.args) == 0 {
		fmt.Fprintln(os.Stderr, "usage: goget remove <package>...")
		return 1
	}
	return nixRemove(o)
}

func cmdList(args []string) int { pmParse(args); return nixList() }

func cmdInfo(args []string) int {
	o := pmParse(args)
	if len(o.args) != 1 {
		fmt.Fprintln(os.Stderr, "usage: goget info <package>")
		return 1
	}
	return nixInfo(o.args[0])
}

func cmdFind(args []string) int {
	o := pmParse(args)
	if len(o.args) != 1 {
		fmt.Fprintln(os.Stderr, "usage: goget find <term>")
		return 1
	}
	return nixFind(o.args[0])
}

func cmdRefresh(args []string) int {
	pmParse(args)
	if err := nixInitStore(); err != nil {
		printErr("%v", err)
		return 1
	}
	printInfo("refreshing the package index (%s)", pmChannel())
	if err := nixRefreshIndex(nixRepo()); err != nil {
		printErr("%v", err)
		return 1
	}
	return 0
}

func cmdUpdate(args []string) int { return nixUpdate(pmParse(args)) }

// cmdChannel shows or changes which nixpkgs channel packages come from.
func cmdChannel(args []string) int {
	o := pmParse(args)
	if len(o.args) == 0 {
		fmt.Println(pmChannel())
		return 0
	}
	c := o.args[0]
	switch c {
	case "stable":
		c = defaultChannel
	case "unstable":
		c = "nixos-unstable"
	}
	if !strings.HasPrefix(c, "nixos-") {
		printErr("channel names look like nixos-25.05 or nixos-unstable (or: stable, unstable)")
		return 1
	}
	if os.Geteuid() != 0 && pmRoot == "/" {
		printErr("changing the channel needs root (try sudo)")
		return 1
	}
	if err := pmSetChannel(c); err != nil {
		printErr("%v", err)
		return 1
	}
	printOK("channel set to %s; run `goget refresh` and then `goget update`", c)
	return 0
}
