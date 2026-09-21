package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
)

// Direct-compile build paths, used when a project has no Makefile, CMake,
// autotools or PKGBUILD: the language is recognised from its files and the
// project is compiled with that language's own toolchain (go, cargo, gcc, g++).

var versionSuffix = regexp.MustCompile(`[-_.]v?[0-9][0-9A-Za-z.+_-]*$`)

// projectBinaryName derives the name the installed program gets from the source
// directory ("fastfetch-2.40.4" -> "fastfetch").
func projectBinaryName(dir string) string {
	name := filepath.Base(filepath.Clean(dir))
	if s := versionSuffix.ReplaceAllString(name, ""); s != "" {
		name = s
	}
	return name
}

func installBinary(src, name string) int {
	dst := filepath.Join("/usr/local/bin", name)
	printInfo("installing %s (sudo install)...", dst)
	rc := runCommand("", []string{"sudo", "install", "-Dm755", src, dst})
	if rc != 0 {
		printErr("could not install %s", dst)
	}
	return rc
}

// ---- Go ----------------------------------------------------------------

// goMainPackage finds the package to build: the root if it is package main,
// otherwise cmd/<name> (or the only cmd/ entry).
func goMainPackage(dir, name string) (string, bool) {
	isMain := func(d string) bool {
		files, _ := filepath.Glob(filepath.Join(d, "*.go"))
		for _, f := range files {
			if strings.HasSuffix(f, "_test.go") {
				continue
			}
			if b, err := os.ReadFile(f); err == nil && regexp.MustCompile(`(?m)^package\s+main\b`).Match(b) {
				return true
			}
		}
		return false
	}
	if isMain(dir) {
		return ".", true
	}
	if pathIsDir(filepath.Join(dir, "cmd", name)) && isMain(filepath.Join(dir, "cmd", name)) {
		return "./cmd/" + name, true
	}
	entries, _ := os.ReadDir(filepath.Join(dir, "cmd"))
	var found []string
	for _, e := range entries {
		if e.IsDir() && isMain(filepath.Join(dir, "cmd", e.Name())) {
			found = append(found, e.Name())
		}
	}
	if len(found) == 1 {
		return "./cmd/" + found[0], true
	}
	return "", false
}

func buildGoImpl(dir string) int {
	name := projectBinaryName(dir)
	pkg, ok := goMainPackage(dir, name)
	if !ok {
		printErr("no main package found in %s (a Go library has nothing to install)", dir)
		return 1
	}
	out := filepath.Join(dir, name)
	rc := runCommandSpinner(dir, []string{"go", "build", "-o", out, pkg}, "building with go...", false)
	if rc != 0 {
		printErr("go build failed")
		return rc
	}
	printOK("compiled")
	return installBinary(out, name)
}

// ---- Rust --------------------------------------------------------------

func buildCargoImpl(dir string) int {
	rc := runCommandSpinner(dir, []string{"cargo", "build", "--release"}, "building with cargo...", false)
	if rc != 0 {
		printErr("cargo build failed")
		return rc
	}
	printOK("compiled")
	rel := filepath.Join(dir, "target", "release")
	entries, _ := os.ReadDir(rel)
	var bins []string
	for _, e := range entries {
		p := filepath.Join(rel, e.Name())
		if !e.IsDir() && !strings.Contains(e.Name(), ".") && pathIsExecutableFile(p) {
			bins = append(bins, p)
		}
	}
	if len(bins) == 0 {
		printErr("cargo produced no executable in target/release (a Rust library has nothing to install)")
		return 1
	}
	for _, b := range bins {
		if rc := installBinary(b, filepath.Base(b)); rc != 0 {
			return rc
		}
	}
	return 0
}

// ---- C / C++ (gcc, g++) -------------------------------------------------

var skipDirs = map[string]bool{
	".git": true, "test": true, "tests": true, "testing": true, "example": true, "examples": true,
	"doc": true, "docs": true, "build": true, "bench": true, "benchmark": true, "benchmarks": true,
	"fuzz": true, "contrib": true, "samples": true, "sample": true, "node_modules": true, "target": true,
}

type cSources struct {
	c, cxx, mains []string
	incDirs       map[string]bool
}

var mainRe = regexp.MustCompile(`(?m)^\s*(?:int|void)\s+main\s*\(`)

// scanCSources walks dir (three levels deep) collecting C/C++ sources and header directories.
func scanCSources(dir string) cSources {
	s := cSources{incDirs: map[string]bool{dir: true}}
	var walk func(d string, depth int)
	walk = func(d string, depth int) {
		entries, err := os.ReadDir(d)
		if err != nil {
			return
		}
		for _, e := range entries {
			p := filepath.Join(d, e.Name())
			if e.IsDir() {
				if depth < 3 && !skipDirs[strings.ToLower(e.Name())] && !strings.HasPrefix(e.Name(), ".") {
					walk(p, depth+1)
				}
				continue
			}
			switch strings.ToLower(filepath.Ext(e.Name())) {
			case ".c":
				s.c = append(s.c, p)
			case ".cc", ".cpp", ".cxx":
				s.cxx = append(s.cxx, p)
			case ".h", ".hh", ".hpp", ".hxx":
				s.incDirs[d] = true
				continue
			default:
				continue
			}
			if b, err := os.ReadFile(p); err == nil && mainRe.Match(b) {
				s.mains = append(s.mains, p)
			}
		}
	}
	walk(dir, 0)
	return s
}

func buildCSourcesImpl(dir string) int {
	s := scanCSources(dir)
	if len(s.mains) == 0 {
		printErr("found C/C++ sources but no main() in %s: this looks like a library, so there is nothing to install", dir)
		return 1
	}
	cxx := len(s.cxx) > 0
	compiler, linker := "gcc", "gcc"
	if cxx {
		linker = "g++"
	}
	for _, tool := range []string{compiler, linker} {
		if _, err := exec.LookPath(tool); err != nil {
			printErr("%s is not installed", tool)
			return 1
		}
	}

	var incs []string
	for d := range s.incDirs {
		incs = append(incs, "-I"+d)
	}
	objDir := filepath.Join(dir, ".goget-obj")
	if err := mkdirP(objDir); err != nil {
		printErr("cannot create %s: %v", objDir, err)
		return 1
	}

	all := append(append([]string{}, s.c...), s.cxx...)
	isMain := map[string]bool{}
	for _, m := range s.mains {
		isMain[m] = true
	}
	objOf := func(src string) string {
		rel, _ := filepath.Rel(dir, src)
		return filepath.Join(objDir, strings.NewReplacer("/", "_", ".", "_").Replace(rel)+".o")
	}
	var shared, mainObjs []string
	for i, src := range all {
		cc, std := "gcc", []string{}
		if strings.ToLower(filepath.Ext(src)) != ".c" {
			cc, std = "g++", []string{"-std=gnu++17"}
		}
		argv := append([]string{cc, "-O2", "-pipe", "-w", "-D_GNU_SOURCE"}, std...)
		argv = append(argv, incs...)
		argv = append(argv, "-c", src, "-o", objOf(src))
		label := fmt.Sprintf("compiling %d/%d: %s", i+1, len(all), filepath.Base(src))
		if rc := runCommandSpinner(dir, argv, label, false); rc != 0 {
			printErr("%s failed to compile %s", cc, src)
			return rc
		}
		if isMain[src] {
			mainObjs = append(mainObjs, src)
		} else {
			shared = append(shared, objOf(src))
		}
	}
	printOK("compiled %d file(s)", len(all))

	name := projectBinaryName(dir)
	for _, m := range mainObjs {
		out := filepath.Join(dir, name)
		if len(mainObjs) > 1 {
			out = filepath.Join(dir, strings.TrimSuffix(filepath.Base(m), filepath.Ext(m)))
		}
		argv := append([]string{linker, "-o", out, objOf(m)}, shared...)
		argv = append(argv, "-lm", "-lpthread")
		if rc := runCommandSpinner(dir, argv, "linking "+filepath.Base(out), false); rc != 0 {
			printErr("linking %s failed (a library the project needs may be missing)", filepath.Base(out))
			return rc
		}
		if rc := installBinary(out, filepath.Base(out)); rc != 0 {
			return rc
		}
	}
	return 0
}
