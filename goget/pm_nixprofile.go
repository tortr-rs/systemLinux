package main

import (
	"crypto/sha1"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"syscall"
)

// Profiles: an environment is a directory of symlinks into the store, one per generation, so every change
// (install, remove, apply, update) can be rolled back. root's profile is the system's; everyone else has
// their own under ~/.local/state/goget/profile.

type nixPkg struct {
	Name    string   `json:"name"`
	Version string   `json:"version"`
	Paths   []string `json:"paths"`
}

type nixGen struct {
	N    int      `json:"n"`
	Time string   `json:"time"`
	Pkgs []nixPkg `json:"pkgs"`
}

func nixProfileDir() string {
	if nixForceSystem {
		return filepath.Join(nixVarDir(), "profiles", "system")
	}
	if pmRoot != "/" {
		return filepath.Join(nixVarDir(), "profiles", "test")
	}
	if os.Geteuid() == 0 {
		return filepath.Join(nixVarDir(), "profiles", "system")
	}
	return filepath.Join(homeDir(), ".local/state/goget/profile")
}

func nixGenNumbers(profile string) []int {
	ents, _ := os.ReadDir(profile)
	var ns []int
	for _, e := range ents {
		if strings.HasPrefix(e.Name(), "gen-") && strings.HasSuffix(e.Name(), ".json") {
			if n, err := strconv.Atoi(strings.TrimSuffix(strings.TrimPrefix(e.Name(), "gen-"), ".json")); err == nil {
				ns = append(ns, n)
			}
		}
	}
	sort.Ints(ns)
	return ns
}

func nixLoadGen(profile string, n int) *nixGen {
	data, err := os.ReadFile(filepath.Join(profile, fmt.Sprintf("gen-%d.json", n)))
	if err != nil {
		return nil
	}
	var g nixGen
	if json.Unmarshal(data, &g) != nil {
		return nil
	}
	return &g
}

func nixCurrentN(profile string) int {
	t, err := os.Readlink(filepath.Join(profile, "current"))
	if err != nil {
		return 0
	}
	n, _ := strconv.Atoi(strings.TrimPrefix(t, "gen-"))
	return n
}

func nixCurrent(profile string) *nixGen {
	if n := nixCurrentN(profile); n > 0 {
		if g := nixLoadGen(profile, n); g != nil {
			return g
		}
	}
	return &nixGen{}
}

// mirror links every file of the store path (real is where it is on disk, logical its /nix/store name)
// into dst, merging directories.
func mirror(real, logical, dst string, conflicts *[]string) {
	ents, err := os.ReadDir(real)
	if err != nil {
		return
	}
	for _, e := range ents {
		name := e.Name()
		if name == "nix-support" || name == "propagated-build-inputs" {
			continue
		}
		rs, s, d := filepath.Join(real, name), filepath.Join(logical, name), filepath.Join(dst, name)
		fi, err := os.Stat(rs)
		if err == nil && fi.IsDir() && e.Type()&os.ModeSymlink == 0 {
			if l, err := os.Lstat(d); err == nil && l.Mode()&os.ModeSymlink != 0 {
				continue
			}
			os.MkdirAll(d, 0o755)
			mirror(rs, s, d, conflicts)
			continue
		}
		if l, err := os.Lstat(d); err == nil {
			if t, _ := os.Readlink(d); t != s && l != nil {
				*conflicts = append(*conflicts, name)
			}
			continue
		}
		os.Symlink(s, d)
	}
}

func nixSwitch(profile string, pkgs []nixPkg) (int, error) {
	if err := mkdirP(profile); err != nil {
		return 0, err
	}
	ns := nixGenNumbers(profile)
	n := 1
	if len(ns) > 0 {
		n = ns[len(ns)-1] + 1
	}
	farm := filepath.Join(profile, fmt.Sprintf("gen-%d", n))
	os.RemoveAll(farm)
	if err := os.MkdirAll(farm, 0o755); err != nil {
		return 0, err
	}
	var conflicts []string
	for _, p := range pkgs {
		for _, sp := range p.Paths {
			mirror(filepath.Join(nixStoreDir(), strings.TrimPrefix(sp, nixStorePrefix)), sp, farm, &conflicts)
		}
	}
	if len(conflicts) > 0 {
		sort.Strings(conflicts)
		printWarn("%d file(s) are provided by more than one package; the first one wins (e.g. %s)", len(conflicts), conflicts[0])
	}
	g := nixGen{N: n, Time: pmNow(), Pkgs: pkgs}
	data, _ := json.MarshalIndent(g, "", " ")
	if err := os.WriteFile(filepath.Join(profile, fmt.Sprintf("gen-%d.json", n)), data, 0o644); err != nil {
		return 0, err
	}
	if err := nixSetCurrent(profile, n); err != nil {
		return 0, err
	}
	nixRegisterRoot(profile)
	return n, nil
}

func nixSetCurrent(profile string, n int) error {
	tmp := filepath.Join(profile, ".current-tmp")
	os.Remove(tmp)
	if err := os.Symlink(fmt.Sprintf("gen-%d", n), tmp); err != nil {
		return err
	}
	return os.Rename(tmp, filepath.Join(profile, "current"))
}

func nixRegisterRoot(profile string) {
	sum := sha1.Sum([]byte(profile))
	dir := filepath.Join(nixVarDir(), "roots")
	if mkdirP(dir) == nil {
		os.WriteFile(filepath.Join(dir, hex.EncodeToString(sum[:8])), []byte(profile+"\n"), 0o644)
	}
}

func nixEntryPath(e *nixEntry) string { return nixStorePrefix + e.hash + "-" + e.name }

func withoutName(pkgs []nixPkg, names map[string]bool) []nixPkg {
	var out []nixPkg
	for _, p := range pkgs {
		if !names[p.Name] {
			out = append(out, p)
		}
	}
	return out
}

// nixResolveAll resolves package names and makes sure their whole closure is in the store.
func nixResolveAll(o pmOpts, names []string, confirm bool) ([]nixPkg, int) {
	rc := nixRepo()
	idx, err := nixLoadIndex(rc)
	if err != nil {
		printErr("%v", err)
		return nil, 1
	}
	cache := nixCacheURL(rc)
	var pkgs []nixPkg
	var roots []string
	for _, n := range names {
		e, err := idx.resolve(cache, n)
		if err != nil {
			printErr("%v", err)
			return nil, 1
		}
		pkgs = append(pkgs, nixPkg{Name: n, Version: e.base, Paths: []string{nixEntryPath(e)}})
		roots = append(roots, e.hash)
	}
	if err := nixInitStore(); err != nil {
		printErr("%v", err)
		return nil, 1
	}
	closure, err := nixClosure(cache, roots)
	if err != nil {
		printErr("%v", err)
		return nil, 1
	}
	var need int64
	count := 0
	for _, n := range closure {
		if n != nil && !nixStoreHas(n) {
			need += n.narSize
			count++
		}
	}
	for _, p := range pkgs {
		fmt.Printf("  %-28s %s\n", p.Name, p.Version)
	}
	if confirm && count > 0 {
		fmt.Printf("%d new store paths, %.1f MB unpacked\n", count, float64(need)/1048576)
		if !o.yes && !promptYesNo("Proceed?", true) {
			printInfo("aborting.")
			return nil, 1
		}
	}
	if err := nixEnsure(cache, closure); err != nil {
		printErr("%v", err)
		return nil, 1
	}
	return pkgs, 0
}

func nixInstall(o pmOpts, names []string) int {
	pkgs, rc := nixResolveAll(o, names, true)
	if rc != 0 {
		return rc
	}
	profile := nixProfileDir()
	set := map[string]bool{}
	for _, p := range pkgs {
		set[p.Name] = true
	}
	all := append(withoutName(nixCurrent(profile).Pkgs, set), pkgs...)
	n, err := nixSwitch(profile, all)
	if err != nil {
		printErr("%v", err)
		return 1
	}
	printOK("installed %d package(s) (generation %d)", len(pkgs), n)
	if nixNeedsGL(pkgs) && !pathExists(pmPath("run/opengl-driver")) {
		printInfo("these programs draw with OpenGL: run `sudo goget graphics` once so they can use your GPU")
	}
	return 0
}

// nixNeedsGL reports whether any installed package's closure contains libglvnd (an OpenGL program).
func nixNeedsGL(pkgs []nixPkg) bool {
	seen := map[string]bool{}
	var walk func(h string, depth int) bool
	walk = func(h string, depth int) bool {
		if seen[h] || depth > 6 {
			return false
		}
		seen[h] = true
		data, err := os.ReadFile(nixDBPath(h))
		if err != nil {
			return false
		}
		ni, err := parseNarinfo(string(data))
		if err != nil {
			return false
		}
		for _, r := range ni.refs {
			if strings.Contains(r, "-libglvnd-") || strings.Contains(r, "-mesa-") {
				return true
			}
			if walk(r[:32], depth+1) {
				return true
			}
		}
		return false
	}
	for _, p := range pkgs {
		for _, sp := range p.Paths {
			if walk(strings.TrimPrefix(sp, nixStorePrefix)[:32], 0) {
				return true
			}
		}
	}
	return false
}

func nixRemove(o pmOpts) int {
	profile := nixProfileDir()
	cur := nixCurrent(profile)
	set := map[string]bool{}
	for _, a := range o.args {
		found := false
		for _, p := range cur.Pkgs {
			if p.Name == a {
				found = true
			}
		}
		if !found {
			printErr("%s is not installed in this profile", a)
			return 1
		}
		set[a] = true
	}
	n, err := nixSwitch(profile, withoutName(cur.Pkgs, set))
	if err != nil {
		printErr("%v", err)
		return 1
	}
	printOK("removed %s (generation %d; `goget gc` frees the space)", strings.Join(o.args, ", "), n)
	return 0
}

func nixList() int {
	profile := nixProfileDir()
	cur := nixCurrent(profile)
	if len(cur.Pkgs) == 0 {
		printInfo("nothing installed in this profile yet (%s)", profile)
		return 0
	}
	fmt.Printf("generation %d of %s\n", cur.N, profile)
	pkgs := append([]nixPkg(nil), cur.Pkgs...)
	sort.Slice(pkgs, func(i, j int) bool { return pkgs[i].Name < pkgs[j].Name })
	for _, p := range pkgs {
		fmt.Printf("  %-28s %s\n", p.Name, p.Version)
	}
	return 0
}

func nixFind(term string) int {
	idx, err := nixLoadIndex(nixRepo())
	if err != nil {
		printErr("%v", err)
		return 1
	}
	best := map[string]string{}
	for p, es := range idx.by {
		if !strings.Contains(p, term) {
			continue
		}
		for _, e := range es {
			if e.output == "" || e.output == "bin" {
				if best[p] == "" || verCompare(e.base, best[p]) > 0 {
					best[p] = e.base
				}
			}
		}
	}
	var names []string
	for p := range best {
		names = append(names, p)
	}
	sort.Slice(names, func(i, j int) bool {
		// exact and prefix matches first
		ai, aj := names[i] == term, names[j] == term
		if ai != aj {
			return ai
		}
		return names[i] < names[j]
	})
	if len(names) == 0 {
		printInfo("nothing found for %q", term)
		return 0
	}
	for i, p := range names {
		if i >= 50 {
			printInfo("(more results not shown; narrow the search)")
			break
		}
		fmt.Printf("%-32s %s\n", p, best[p])
	}
	return 0
}

func nixInfo(name string) int {
	rc := nixRepo()
	idx, err := nixLoadIndex(rc)
	if err != nil {
		printErr("%v", err)
		return 1
	}
	e, err := idx.resolve(nixCacheURL(rc), name)
	if err != nil {
		printErr("%v", err)
		return 1
	}
	ni, err := nixNarinfo(nixCacheURL(rc), e.hash)
	if err != nil {
		printErr("%v", err)
		return 1
	}
	fmt.Printf("Name:     %s\nVersion:  %s\nStore:    %s\nSize:     %.1f MB (%.1f MB to download)\nDepends:  %d store paths\nSigned:   yes (cache.nixos.org)\n",
		name, e.ver, ni.storePath, float64(ni.narSize)/1048576, float64(ni.fileSize)/1048576, len(ni.refs))
	return 0
}

func nixGenerations() int {
	profile := nixProfileDir()
	cur := nixCurrentN(profile)
	for _, n := range nixGenNumbers(profile) {
		g := nixLoadGen(profile, n)
		if g == nil {
			continue
		}
		mark := " "
		if n == cur {
			mark = "*"
		}
		var names []string
		for _, p := range g.Pkgs {
			names = append(names, p.Name)
		}
		fmt.Printf("%s %3d  %s  %s\n", mark, n, g.Time, strings.Join(names, " "))
	}
	return 0
}

func nixRollback(args []string) int {
	profile := nixProfileDir()
	cur := nixCurrentN(profile)
	ns := nixGenNumbers(profile)
	target := 0
	if len(args) > 0 {
		target, _ = strconv.Atoi(args[0])
	} else {
		for _, n := range ns {
			if n < cur {
				target = n
			}
		}
	}
	if target == 0 || nixLoadGen(profile, target) == nil {
		printErr("no such generation to go back to")
		return 1
	}
	if err := nixSetCurrent(profile, target); err != nil {
		printErr("%v", err)
		return 1
	}
	printOK("switched to generation %d", target)
	return 0
}

// nixApply makes the profile contain exactly the packages listed in a plain text file.
func nixApply(o pmOpts, file string) int {
	if file == "" {
		if os.Geteuid() == 0 && pmRoot == "/" {
			file = "/etc/goget/packages"
		} else {
			file = filepath.Join(homeDir(), ".config/goget/packages")
		}
	}
	data, err := os.ReadFile(file)
	if err != nil {
		printErr("cannot read %s (one package name per line, # for comments): %v", file, err)
		return 1
	}
	var names []string
	seen := map[string]bool{}
	for _, line := range strings.Split(string(data), "\n") {
		if i := strings.Index(line, "#"); i >= 0 {
			line = line[:i]
		}
		for _, w := range strings.Fields(line) {
			if !seen[w] {
				seen[w] = true
				names = append(names, w)
			}
		}
	}
	profile := nixProfileDir()
	cur := nixCurrent(profile)
	pkgs, rc := nixResolveAll(o, names, true)
	if rc != 0 {
		return rc
	}
	same := len(cur.Pkgs) == len(pkgs)
	if same {
		old := map[string]string{}
		for _, p := range cur.Pkgs {
			old[p.Name] = strings.Join(p.Paths, ",")
		}
		for _, p := range pkgs {
			if old[p.Name] != strings.Join(p.Paths, ",") {
				same = false
			}
		}
	}
	if same {
		printOK("already matches %s", file)
		return 0
	}
	n, err := nixSwitch(profile, pkgs)
	if err != nil {
		printErr("%v", err)
		return 1
	}
	printOK("applied %s: %d package(s) (generation %d)", file, len(pkgs), n)
	return 0
}

func nixUpdate(o pmOpts) int {
	rc := nixRepo()
	if err := nixRefreshIndex(rc); err != nil {
		printErr("%v", err)
		return 1
	}
	cur := nixCurrent(nixProfileDir())
	if len(cur.Pkgs) == 0 {
		printOK("nothing installed")
		return 0
	}
	var names []string
	for _, p := range cur.Pkgs {
		names = append(names, p.Name)
	}
	idx, err := nixLoadIndex(rc)
	if err != nil {
		printErr("%v", err)
		return 1
	}
	changed := false
	for _, p := range cur.Pkgs {
		e, err := idx.resolve(nixCacheURL(rc), p.Name)
		if err == nil && nixEntryPath(e) != p.Paths[0] {
			fmt.Printf("  %-28s %s -> %s\n", p.Name, p.Version, e.ver)
			changed = true
		}
	}
	if !changed {
		printOK("all packages are up to date")
		return 0
	}
	if !o.yes && !promptYesNo("Upgrade these packages?", true) {
		return 1
	}
	return nixInstall(pmOpts{yes: true}, names)
}

// nixRun runs a program from a package without installing it into the profile.
func nixRun(o pmOpts, args []string, shell bool) int {
	var names []string
	var rest []string
	for i, a := range args {
		if a == "--" {
			rest = args[i+1:]
			break
		}
		if !shell && len(names) == 1 {
			rest = args[i:]
			break
		}
		names = append(names, a)
	}
	if len(names) == 0 {
		fmt.Fprintln(os.Stderr, "usage: goget run <package> [args...]   |   goget shell <package>...")
		return 1
	}
	o.yes = true
	pkgs, rc := nixResolveAll(o, names, false)
	if rc != 0 {
		return rc
	}
	var bins []string
	for _, p := range pkgs {
		bins = append(bins, filepath.Join(p.Paths[0], "bin"))
	}
	env := os.Environ()
	path := strings.Join(bins, ":") + ":" + os.Getenv("PATH")
	env = append(env, "PATH="+path)
	var argv []string
	if shell {
		sh := os.Getenv("SHELL")
		if sh == "" {
			sh = "/bin/sh"
		}
		argv = []string{sh}
		env = append(env, "GOGET_SHELL="+strings.Join(names, " "))
	} else {
		prog := filepath.Join(pkgs[0].Paths[0], "bin", names[0])
		if !pathExists(prog) {
			ents, _ := os.ReadDir(filepath.Join(pkgs[0].Paths[0], "bin"))
			if len(ents) == 0 {
				printErr("%s has no programs to run", names[0])
				return 1
			}
			prog = filepath.Join(pkgs[0].Paths[0], "bin", ents[0].Name())
		}
		argv = append([]string{prog}, rest...)
	}
	if err := syscall.Exec(argv[0], argv, env); err != nil {
		// a bare shell name has to be found on PATH
		if p, e := lookPathIn(argv[0], path); e == nil {
			err = syscall.Exec(p, argv, env)
		}
		printErr("cannot start %s: %v", argv[0], err)
		return 1
	}
	return 0
}

func lookPathIn(name, path string) (string, error) {
	if strings.Contains(name, "/") {
		return name, nil
	}
	for _, d := range strings.Split(path, ":") {
		if p := filepath.Join(d, name); pathIsExecutableFile(p) {
			return p, nil
		}
	}
	return "", fmt.Errorf("not found")
}

// nixGC removes store paths no generation of any profile needs.
func nixGC(deleteOld bool) int {
	rootsDir := filepath.Join(nixVarDir(), "roots")
	ents, _ := os.ReadDir(rootsDir)
	live := map[string]bool{}
	var walk func(hash string)
	walk = func(hash string) {
		if live[hash] {
			return
		}
		live[hash] = true
		data, err := os.ReadFile(nixDBPath(hash))
		if err != nil {
			return
		}
		if n, err := parseNarinfo(string(data)); err == nil {
			for _, r := range n.refs {
				walk(r[:32])
			}
		}
	}
	for _, e := range ents {
		rf := filepath.Join(rootsDir, e.Name())
		data, err := os.ReadFile(rf)
		if err != nil {
			continue
		}
		profile := strings.TrimSpace(string(data))
		if !pathIsDir(profile) {
			os.Remove(rf)
			continue
		}
		cur := nixCurrentN(profile)
		for _, n := range nixGenNumbers(profile) {
			if deleteOld && n != cur {
				os.Remove(filepath.Join(profile, fmt.Sprintf("gen-%d.json", n)))
				os.RemoveAll(filepath.Join(profile, fmt.Sprintf("gen-%d", n)))
				continue
			}
			if g := nixLoadGen(profile, n); g != nil {
				for _, p := range g.Pkgs {
					for _, sp := range p.Paths {
						walk(strings.TrimPrefix(sp, nixStorePrefix)[:32])
					}
				}
			}
		}
	}
	items, _ := os.ReadDir(nixStoreDir())
	var freed int64
	removed := 0
	for _, it := range items {
		name := it.Name()
		if len(name) < 33 || strings.HasPrefix(name, ".") {
			continue
		}
		h := name[:32]
		if live[h] {
			continue
		}
		if data, err := os.ReadFile(nixDBPath(h)); err == nil {
			if n, err := parseNarinfo(string(data)); err == nil {
				freed += n.narSize
			}
		}
		forceRemove(filepath.Join(nixStoreDir(), name))
		os.Remove(nixDBPath(h))
		removed++
	}
	printOK("removed %d store paths, %.1f MB freed", removed, float64(freed)/1048576)
	return 0
}

// nixInit prepares /nix so every member of wheel can install (the store is group-writable, sticky).
func nixInit() int {
	if os.Geteuid() != 0 && pmRoot == "/" {
		printErr("run as root: sudo goget init")
		return 1
	}
	if err := os.MkdirAll(nixStoreDir(), 0o755); err != nil {
		printErr("%v", err)
		return 1
	}
	os.MkdirAll(nixVarDir(), 0o755)
	os.Chmod(nixStoreDir(), 0o1775)
	if g := lookupGroupID("wheel"); g >= 0 {
		os.Chown(nixStoreDir(), 0, g)
		os.Chown(nixVarDir(), 0, g)
		os.Chmod(nixVarDir(), 0o2775)
	}
	printOK("%s is ready (members of wheel can install packages)", nixStoreDir())
	return 0
}

func lookupGroupID(name string) int {
	data, err := os.ReadFile("/etc/group")
	if err != nil {
		return -1
	}
	for _, l := range strings.Split(string(data), "\n") {
		f := strings.Split(l, ":")
		if len(f) >= 3 && f[0] == name {
			if n, err := strconv.Atoi(f[2]); err == nil {
				return n
			}
		}
	}
	return -1
}

// nixGraphics installs Mesa (OpenGL, Vulkan and video drivers) into the system profile and points
// /run/opengl-driver at it, which is where programs from the Nix cache look for the GPU drivers.
func nixGraphics(o pmOpts) int {
	nixForceSystem = true
	o.yes = true
	if rc := nixInstall(o, []string{"mesa"}); rc != 0 {
		return rc
	}
	link := "/run/opengl-driver"
	os.Remove(link)
	if err := os.Symlink("/nix/var/goget/profiles/system/current", link); err != nil {
		printWarn("could not create %s (%v); it is created at every boot", link, err)
	}
	printOK("graphics drivers ready: programs installed with goget now use your GPU")
	return 0
}
