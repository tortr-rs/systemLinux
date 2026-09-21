package main

import (
	"fmt"
	"os"
	"sort"
	"strings"
)

type pmOpts struct {
	yes, nodeps bool
	args        []string
}

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
		case "--nodeps":
			o.nodeps = true
		case "--root":
			if i+1 < len(args) {
				pmRoot = args[i+1]
				i++
			}
		default:
			o.args = append(o.args, a)
		}
	}
	dbCache = nil
	return o
}

func pmNeedRoot() bool {
	if pmRoot == "/" && os.Geteuid() != 0 {
		printErr("this needs root (try sudo)")
		return false
	}
	return true
}

// pmLoadAll loads every repository's index, refreshing first when an index is missing.
func pmLoadAll() []backend {
	bs := pmBackends()
	if len(bs) == 0 {
		printErr("no package repositories are configured; choose one with: goget repo use debian|ubuntu|arch|gentoo")
		return nil
	}
	var ok []backend
	for _, b := range bs {
		if err := b.load(); err != nil {
			printInfo("fetching the %s package index...", b.conf().name)
			if err := b.refresh(); err != nil {
				printErr("%s: %v", b.conf().name, err)
				continue
			}
			b = newBackend(b.conf())
			if err := b.load(); err != nil {
				printErr("%s: %v", b.conf().name, err)
				continue
			}
		}
		ok = append(ok, b)
	}
	return ok
}

func cmdRefresh(args []string) int {
	pmParse(args)
	if !pmNeedRoot() {
		return 1
	}
	bs := pmBackends()
	if len(bs) == 0 {
		printErr("no package repositories are configured; choose one with: goget repo use debian|ubuntu|arch|gentoo")
		return 1
	}
	rc := 0
	for _, b := range bs {
		printInfo("refreshing %s (%s)", b.conf().name, b.conf().kind)
		if err := b.refresh(); err != nil {
			printErr("%s: %v", b.conf().name, err)
			rc = 1
		}
	}
	return rc
}

func cmdInstall(args []string) int {
	o := pmParse(args)
	if len(o.args) == 0 {
		fmt.Fprintln(os.Stderr, "usage: goget install [-y] [--nodeps] [--root DIR] <package|owner/repo>...")
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
		if !pmNeedRoot() {
			return 1
		}
		bs := pmLoadAll()
		if len(bs) == 0 {
			return 1
		}
		r := &resolver{backends: bs, nodeps: o.nodeps, planSet: map[string]bool{}}
		for _, n := range names {
			if err := r.visit(n, nil, true); err != nil {
				printErr("%v", err)
				return 1
			}
		}
		for _, w := range r.warnings {
			printWarn("%s", w)
		}
		if len(r.plan) == 0 {
			printOK("nothing to do: already installed")
		} else {
			var total int64
			fmt.Println("packages to install:")
			for _, it := range r.plan {
				tag := ""
				if !it.explicit {
					tag = "  (dependency)"
				}
				fmt.Printf("  %-32s %-18s %s%s\n", it.p.name, it.p.version, it.p.repo, tag)
				total += it.p.size
			}
			fmt.Printf("download size: %.1f MB\n", float64(total)/1048576)
			if !o.yes && !promptYesNo("Proceed?", true) {
				printInfo("aborting.")
				return 1
			}
			var touched []string
			for _, it := range r.plan {
				printInfo("installing %s %s", it.p.name, it.p.version)
				if err := pmInstallOne(it); err != nil {
					printErr("%v", err)
					rc = 1
					break
				}
				touched = append(touched, pmDBAll()[it.p.name].Files...)
			}
			pmAfterInstall(touched)
			if rc == 0 {
				printOK("installed %d package(s)", len(r.plan))
			}
		}
	}
	for _, g := range gits {
		if c := cmdBuild(g, false); c != 0 {
			rc = c
		}
	}
	return rc
}

func cmdRemove(args []string) int {
	o := pmParse(args)
	if len(o.args) == 0 {
		fmt.Fprintln(os.Stderr, "usage: goget remove [-y] [--root DIR] <package>...")
		return 1
	}
	if !pmNeedRoot() {
		return 1
	}
	db := pmDBAll()
	for _, n := range o.args {
		if _, ok := db[n]; !ok {
			printErr("%s is not installed (or was not installed by goget)", n)
			return 1
		}
		var users []string
		for _, ip := range db {
			for _, d := range ip.Deps {
				if d == n && ip.Name != n {
					users = append(users, ip.Name)
				}
			}
		}
		if len(users) > 0 {
			printWarn("%s is needed by: %s", n, strings.Join(users, ", "))
		}
	}
	if !o.yes && !promptYesNo("Remove "+strings.Join(o.args, ", ")+"?", false) {
		printInfo("aborting.")
		return 1
	}
	for _, n := range o.args {
		if err := pmRemove(n); err != nil {
			printErr("%v", err)
			return 1
		}
		printOK("removed %s", n)
	}
	if pmRoot == "/" {
		runQuiet("ldconfig")
	}
	return 0
}

func cmdList(args []string) int {
	pmParse(args)
	var names []string
	for n := range pmDBAll() {
		names = append(names, n)
	}
	sort.Strings(names)
	for _, n := range names {
		ip := pmDBAll()[n]
		mark := " "
		if !ip.Explicit {
			mark = "d"
		}
		fmt.Printf("%s %-32s %-18s %s\n", mark, ip.Name, ip.Version, ip.Repo)
	}
	if len(names) == 0 {
		printInfo("no packages installed with goget yet")
	}
	return 0
}

func cmdInfo(args []string) int {
	o := pmParse(args)
	if len(o.args) != 1 {
		fmt.Fprintln(os.Stderr, "usage: goget info <package>")
		return 1
	}
	n := o.args[0]
	if ip, ok := pmDBAll()[n]; ok {
		fmt.Printf("Name:      %s\nVersion:   %s\nRepository: %s\nInstalled: %s\nFiles:     %d\nDepends:   %s\n",
			ip.Name, ip.Version, ip.Repo, ip.Time, len(ip.Files), strings.Join(ip.Deps, ", "))
		return 0
	}
	for _, b := range pmLoadAll() {
		if p := b.lookup(n); p != nil {
			var deps []string
			for _, g := range p.deps {
				var alts []string
				for _, a := range g {
					alts = append(alts, a.name)
				}
				deps = append(deps, strings.Join(alts, " | "))
			}
			fmt.Printf("Name:      %s\nVersion:   %s\nRepository: %s (%s)\nSize:      %.1f MB\nDepends:   %s\n%s\n",
				p.name, p.version, p.repo, p.kind, float64(p.size)/1048576, strings.Join(deps, ", "), p.desc)
			return 0
		}
	}
	printErr("package %q not found", n)
	return 1
}

func cmdFind(args []string) int {
	o := pmParse(args)
	if len(o.args) != 1 {
		fmt.Fprintln(os.Stderr, "usage: goget find <term>")
		return 1
	}
	shown := 0
	for _, b := range pmLoadAll() {
		res := b.search(o.args[0])
		sort.Slice(res, func(i, j int) bool { return res[i].name < res[j].name })
		for _, p := range res {
			if shown >= 60 {
				printInfo("(more results not shown; narrow the search)")
				return 0
			}
			d := p.desc
			if len(d) > 60 {
				d = d[:57] + "..."
			}
			fmt.Printf("%-30s %-16s %-8s %s\n", p.name, p.version, p.repo, d)
			shown++
		}
	}
	if shown == 0 {
		printInfo("nothing found for %q", o.args[0])
	}
	return 0
}

// cmdUpdate refreshes the indexes and installs newer versions of what is installed.
func cmdUpdate(args []string) int {
	o := pmParse(args)
	if !pmNeedRoot() {
		return 1
	}
	for _, b := range pmBackends() {
		if err := b.refresh(); err != nil {
			printErr("%s: %v", b.conf().name, err)
			return 1
		}
	}
	bs := pmLoadAll()
	byName := map[string]backend{}
	for _, b := range bs {
		byName[b.conf().name] = b
	}
	var plan []planItem
	for _, ip := range pmDBAll() {
		b := byName[ip.Repo]
		if b == nil {
			continue
		}
		if p := b.lookup(ip.Name); p != nil && verCompare(p.version, ip.Version) > 0 {
			plan = append(plan, planItem{p: p, b: b, explicit: ip.Explicit})
		}
	}
	if len(plan) == 0 {
		printOK("all packages are up to date")
		return 0
	}
	sort.Slice(plan, func(i, j int) bool { return plan[i].p.name < plan[j].p.name })
	for _, it := range plan {
		old := pmDBAll()[it.p.name].Version
		fmt.Printf("  %-32s %s -> %s\n", it.p.name, old, it.p.version)
	}
	if !o.yes && !promptYesNo("Upgrade these packages?", true) {
		return 1
	}
	var touched []string
	for _, it := range plan {
		if err := pmInstallOne(it); err != nil {
			printErr("%v", err)
			return 1
		}
		touched = append(touched, pmDBAll()[it.p.name].Files...)
	}
	pmAfterInstall(touched)
	printOK("upgraded %d package(s)", len(plan))
	return 0
}

// cmdRepo shows or changes the configured repositories.
func cmdRepo(args []string) int {
	o := pmParse(args)
	if len(o.args) == 0 || o.args[0] == "list" {
		rs := pmLoadRepos()
		if len(rs) == 0 {
			printInfo("no distribution repositories configured (owner/repo Git sources still work)")
			fmt.Println("choose with: goget repo use debian|ubuntu|arch|gentoo   (several allowed)")
			return 0
		}
		for _, r := range rs {
			fmt.Printf("%-8s %-10s %s\n", r.kind, r.name, r.url)
		}
		return 0
	}
	if !pmNeedRoot() {
		return 1
	}
	switch o.args[0] {
	case "use":
		var rs []repoConf
		for _, n := range o.args[1:] {
			if n == "git" {
				continue
			}
			p := pmPreset(n)
			if p == nil {
				printErr("unknown repository %q (debian, ubuntu, arch, gentoo, git)", n)
				return 1
			}
			rs = append(rs, p...)
		}
		if err := pmSaveRepos(rs); err != nil {
			printErr("%v", err)
			return 1
		}
		if len(rs) == 0 {
			printOK("package repositories cleared: only Git sources (owner/repo) are used")
		} else {
			printOK("repositories set; run `goget refresh` to fetch their indexes")
		}
		return 0
	case "add":
		if len(o.args) < 4 {
			fmt.Fprintln(os.Stderr, "usage: goget repo add <kind> <name> <url> [key=value ...]")
			return 1
		}
		rc := repoConf{kind: o.args[1], name: o.args[2], url: strings.TrimRight(o.args[3], "/"), opts: map[string]string{}}
		for _, kv := range o.args[4:] {
			if k, v, ok := strings.Cut(kv, "="); ok {
				rc.opts[k] = v
			}
		}
		if newBackend(rc) == nil {
			printErr("unknown kind %q", rc.kind)
			return 1
		}
		rs := append(pmLoadRepos(), rc)
		if err := pmSaveRepos(rs); err != nil {
			printErr("%v", err)
			return 1
		}
		printOK("added %s", rc.name)
		return 0
	case "remove":
		if len(o.args) != 2 {
			fmt.Fprintln(os.Stderr, "usage: goget repo remove <name>")
			return 1
		}
		var keep []repoConf
		for _, r := range pmLoadRepos() {
			if r.name != o.args[1] {
				keep = append(keep, r)
			}
		}
		if err := pmSaveRepos(keep); err != nil {
			printErr("%v", err)
			return 1
		}
		printOK("removed %s", o.args[1])
		return 0
	}
	fmt.Fprintln(os.Stderr, "usage: goget repo [list | use <preset>... | add <kind> <name> <url> ... | remove <name>]")
	return 1
}
