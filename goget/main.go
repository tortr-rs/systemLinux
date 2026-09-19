package main

import (
	"fmt"
	"os"
)

func printUsage(prog string) {
	fmt.Fprintf(os.Stderr,
		"usage: %s <command> [args]\n"+
			"commands:\n"+
			"  build [--latest] <repo>\n"+
			"                  build and install from source (prefers the latest\n"+
			"                  tagged release's source archive over a full git\n"+
			"                  clone when one exists; --latest forces git instead)\n"+
			"  fetch <repo>    install a prebuilt release binary\n"+
			"  show <repo>     show README + build script\n"+
			"  genpkg [--aur] [--ebuild] <repo>\n"+
			"                  generate a starting-point PKGBUILD and/or .ebuild for\n"+
			"                  <repo> in the current directory (both if neither flag\n"+
			"                  is given) -- templates, not submission-ready recipes\n"+
			"  config          print current configuration\n"+
			"  makeuser        create a new user account (requires root)\n",
		prog)
}

// resolveBareName searches GitHub/GitLab/Codeberg for a bare short name
// and either confirms the single match, offers a numbered picker for
// multiple matches, or reports zero matches. Returns a new
// repospecFull spec, or nil if nothing was resolved (already reported
// to the user).
func resolveBareName(bareSpec *repospec) *repospec {
	cfg := configLoad()
	results := searchByName(cfg, bareSpec.repo)

	if len(results) == 0 {
		printInfo("no repository named '%s' found on GitHub, GitLab, or Codeberg.", bareSpec.repo)
		return nil
	}

	var chosen searchResult
	if len(results) == 1 {
		msg := fmt.Sprintf("Found %s on %s -- proceed?", results[0].repo, results[0].host)
		if !promptYesNo(msg, true) {
			printInfo("aborting.")
			return nil
		}
		chosen = results[0]
	} else {
		labels := make([]string, len(results))
		for i, r := range results {
			labels[i] = fmt.Sprintf("%s/%s on %s (%d stars)", r.owner, r.repo, r.host, r.stars)
		}
		idx := promptPick(labels)
		if idx < 0 {
			printInfo("aborting.")
			return nil
		}
		chosen = results[idx]
	}

	return &repospec{kind: repospecFull, host: chosen.host, owner: chosen.owner, repo: chosen.repo}
}

// resolveSpec resolves a repo spec argument to a repospecFull spec,
// searching GitHub/GitLab/Codeberg for bare short names. Returns nil if
// resolution isn't possible; caller should treat that as "already
// reported, just return".
func resolveSpec(arg string) *repospec {
	spec := parseRepospec(arg)
	if spec == nil {
		printErr("could not parse repo spec '%s'", arg)
		return nil
	}
	if spec.kind == repospecBareName {
		return resolveBareName(spec)
	}
	return spec
}

// resolveSpecChecked is like resolveSpec, but also enforces the
// pkg.repos{} host allow-list -- used by build/fetch, which actually
// pull code/binaries from the resolved host, but not by show, which is
// read-only inspection.
func resolveSpecChecked(arg string) *repospec {
	spec := resolveSpec(arg)
	if spec == nil {
		return nil
	}

	cfg := configLoad()
	if configHostEnabled(cfg, spec.host) {
		return spec
	}

	msg := fmt.Sprintf("%s found on %s, which is disabled in your config. Allow this source?", spec.repo, spec.host)
	choice := promptOnceAlwaysCancel(msg)

	if choice == 'a' {
		configSetHostEnabled(cfg, spec.host, true)
		configSave(cfg)
	}

	if choice == 'c' {
		printInfo("aborting.")
		return nil
	}
	return spec // 'o' or 'a': proceed
}

// buildWithSpec/fetchWithSpec take an already-resolved spec and hand
// off to each other directly on fallback (rather than re-resolving from
// the original command-line string) -- for a bare short name, that
// would otherwise mean re-running the GitHub/GitLab/Codeberg search and
// making the user pick a match a second time, possibly a *different*
// one than they just picked.

func cmdBuild(arg string, forceGit bool) int {
	spec := resolveSpecChecked(arg)
	if spec == nil {
		return 1
	}
	return buildWithSpec(spec, forceGit)
}

func cmdFetch(arg string) int {
	spec := resolveSpecChecked(arg)
	if spec == nil {
		return 1
	}
	return fetchWithSpec(spec)
}

func buildWithSpec(spec *repospec, forceGit bool) int {
	// Gentoo ebuilds aren't git-clonable per-package (the real portage
	// tree is one multi-gigabyte repo covering every package at once),
	// so this doesn't fit the generic tarball/git/buildsys-detect
	// pipeline below at all -- it gets its own dedicated path.
	if spec.host == gentooHost {
		return buildGentoo(spec)
	}

	cfg := configLoad()

	// Before touching git/tarball/cmake at all: check goget's own
	// package repo (pkg.binrepo{} in goget.conf, unconfigured by
	// default -- see binrepo.go). If it has this package, the choice of
	// source-vs-binary is made up front instead of only offering a
	// prebuilt fallback after a build-system-detection failure. If the
	// repo isn't configured, doesn't have this package, or the host has
	// no compatible asset in it, this falls straight through to the
	// existing source-build flow below with no interruption.
	if entry, ok := binRepoLookup(cfg, spec.repo); ok {
		label := spec.repo
		if entry.Version != "" {
			label += " " + entry.Version
		}
		printInfo("found %s in the goget package repo.", label)
		choice := promptPick([]string{"Build from source (GitHub)", "Install prebuilt binary (goget repo)"})
		if choice < 0 {
			printInfo("aborting.")
			return 1
		}
		if choice == 1 {
			switch rc := binRepoInstall(entry, spec.repo); rc {
			case 0:
				printOK("successfully installed %s", spec.repo)
				return 0
			case -1:
				printErr("installing %s from the goget repo failed", spec.repo)
				return 1
			default:
				printWarn("no compatible prebuilt asset for this host in the goget repo; building from source instead")
			}
		}
	}

	// Prefer downloading the latest tagged release's source archive over
	// `git clone` -- same end result, without pulling the repo's entire
	// history just to build one version. Falls back to git whenever
	// that's not possible or not wanted; either way, the exact same
	// detect/configure/build/install pipeline below runs regardless of
	// which path actually got the source onto disk.
	var srcDir string
	if !forceGit {
		if dir, tag, result := srctarballFetch(spec); result == srctarballOK {
			printInfo("using release %s source archive for %s", tag, spec.repo)
			srcDir = dir
		}
	}

	if srcDir == "" {
		srcDir = cacheRepoDir(spec)
		rc := gitSync(gitCloneURL(spec), srcDir)
		if rc != 0 {
			printErr("failed to fetch source for %s", spec.repo)
			return 1
		}
	}

	kind := buildsysDetect(srcDir)
	if kind == buildNone {
		msg := fmt.Sprintf("No source build available for %s. Install prebuilt binary instead?", spec.repo)
		if !promptYesNo(msg, true) {
			printInfo("aborting.")
			return 1
		}
		return fetchWithSpec(spec) // ownership of spec passes on
	}

	printInfo("detected %s build system for %s", buildsysName(kind), spec.repo)

	var useArgs []string
	if kind == buildCMake {
		useArgs = configBuildUseCmakeArgs(cfg, spec.repo)
		for _, a := range useArgs {
			printInfo("USE flag build option: %s", a)
		}
	}

	rc := buildsysBuildAndInstall(kind, srcDir, useArgs)
	if rc != 0 {
		printErr("build/install failed for %s", spec.repo)
		return 1
	}
	printOK("successfully built and installed %s", spec.repo)
	return 0
}

func fetchWithSpec(spec *repospec) int {
	var rc int
	if spec.host != "github.com" {
		printInfo("fetch only checks GitHub Releases; %s is hosted on %s.", spec.repo, spec.host)
		rc = 1
	} else {
		rc = releaseFetchAndInstall(spec.owner, spec.repo, spec.repo)
	}

	if rc == 0 {
		printOK("successfully installed %s", spec.repo)
		return 0
	}
	if rc == -1 {
		printErr("fetch failed for %s", spec.repo)
		return 1
	}

	// rc == 1: no compatible release found.
	msg := fmt.Sprintf("No compatible prebuilt binary available for %s -- must build from source. Continue?", spec.repo)
	if !promptYesNo(msg, true) {
		printInfo("aborting.")
		return 1
	}
	return buildWithSpec(spec, false) // ownership of spec passes on
}

func cmdShow(arg string) int {
	spec := resolveSpec(arg)
	if spec == nil {
		return 1
	}

	content, rc := showFetch(spec.host, spec.owner, spec.repo)
	if rc == 1 {
		printErr("show only supports github.com, gitlab.com, and codeberg.org; %s is hosted on %s.", spec.repo, spec.host)
		return 1
	}
	if rc == -1 {
		printErr("could not fetch README/build script for %s", spec.repo)
		return 1
	}

	if content.readme == "" && content.buildScript == "" {
		printErr("no README or recognized build script found for %s", spec.repo)
		return 1
	}

	var combined string
	if content.readme != "" {
		combined += "=== README ===\n" + content.readme + "\n\n"
	}
	if content.buildScript != "" {
		combined += "=== BUILD SCRIPT (" + content.buildScriptLabel + ") ===\n" + content.buildScript + "\n"
	}

	showPage(combined)
	return 0
}

func main() {
	if len(os.Args) < 2 {
		printUsage(os.Args[0])
		os.Exit(1)
	}

	cmd := os.Args[1]

	switch cmd {
	case "build":
		var repoArg string
		forceGit := false
		for _, a := range os.Args[2:] {
			if a == "--latest" {
				forceGit = true
			} else {
				repoArg = a
			}
		}
		if repoArg == "" {
			fmt.Fprintf(os.Stderr, "usage: %s build [--latest] <repo>\n", os.Args[0])
			os.Exit(1)
		}
		os.Exit(cmdBuild(repoArg, forceGit))

	case "fetch":
		if len(os.Args) < 3 {
			fmt.Fprintf(os.Stderr, "usage: %s fetch <repo>\n", os.Args[0])
			os.Exit(1)
		}
		os.Exit(cmdFetch(os.Args[2]))

	case "show":
		if len(os.Args) < 3 {
			fmt.Fprintf(os.Stderr, "usage: %s show <repo>\n", os.Args[0])
			os.Exit(1)
		}
		os.Exit(cmdShow(os.Args[2]))

	case "genpkg":
		var repoArg string
		wantAUR, wantEbuild := false, false
		for _, a := range os.Args[2:] {
			switch a {
			case "--aur":
				wantAUR = true
			case "--ebuild":
				wantEbuild = true
			default:
				repoArg = a
			}
		}
		if repoArg == "" {
			fmt.Fprintf(os.Stderr, "usage: %s genpkg [--aur] [--ebuild] <repo>\n", os.Args[0])
			os.Exit(1)
		}
		os.Exit(cmdGenpkg(repoArg, wantAUR, wantEbuild))

	case "config":
		configPrint(configLoad())
		os.Exit(0)

	case "makeuser":
		os.Exit(makeuserRun())

	case "parse":
		if len(os.Args) < 3 {
			fmt.Fprintf(os.Stderr, "usage: %s parse <spec>\n", os.Args[0])
			os.Exit(1)
		}
		spec := parseRepospec(os.Args[2])
		if spec == nil {
			fmt.Printf("parse error: could not parse '%s'\n", os.Args[2])
		} else if spec.kind == repospecBareName {
			fmt.Printf("kind=BARE_NAME repo=%s\n", spec.repo)
		} else {
			fmt.Printf("kind=FULL host=%s owner=%s repo=%s\n", spec.host, spec.owner, spec.repo)
		}
		os.Exit(0)

	default:
		printErr("unknown command '%s'", cmd)
		printUsage(os.Args[0])
		os.Exit(1)
	}
}
