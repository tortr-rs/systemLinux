package main

import (
	"fmt"
	"os"
	"strings"
)

// pkgInfo is everything genPKGBUILD/genEbuild need, gathered once via
// metadata-only lookups (no clone, no download) so `genpkg` is cheap
// and safe to run against anything goget can resolve.
type pkgInfo struct {
	spec        *repospec
	tag         string // "" if no tagged release was found
	tarballURL  string // "" if tag == ""
	homepage    string
	description string
	buildLabel  string // "CMakeLists.txt" / "configure" / "Makefile" / "" (unknown)
}

func gatherPkgInfo(spec *repospec) *pkgInfo {
	info := &pkgInfo{spec: spec, homepage: fmt.Sprintf("https://%s/%s/%s", spec.host, spec.owner, spec.repo)}

	if tag, tarURL, noRelease, ok := resolveLatestTag(spec); ok && !noRelease {
		info.tag = tag
		info.tarballURL = tarURL
	}

	if content, rc := showFetch(spec.host, spec.owner, spec.repo); rc == 0 {
		info.buildLabel = content.buildScriptLabel
		if content.readme != "" {
			// First non-empty, non-heading line of the README as a
			// rough one-line description -- better than nothing, never
			// claimed to be authoritative.
			for _, line := range strings.Split(content.readme, "\n") {
				line = strings.TrimSpace(line)
				line = strings.TrimLeft(line, "#= ")
				if line != "" {
					info.description = line
					break
				}
			}
		}
	}

	return info
}

func pkgVersion(tag string) string {
	return strings.TrimPrefix(tag, "v")
}

// genPKGBUILD produces a starting-point PKGBUILD. It is NOT a
// submission-ready package: sha256sums is deliberately "SKIP" (real
// checksums need the actual tarball downloaded and hashed, e.g. via
// `updpkgsums`), license is a placeholder, and the build()/package()
// bodies are templated from goget's own build-system detection, not
// independently verified to actually build.
func genPKGBUILD(info *pkgInfo) string {
	var sb strings.Builder
	spec := info.spec

	fmt.Fprintf(&sb, "# Maintainer: FIXME\npkgname=%s\n", spec.repo)

	if info.tag != "" {
		fmt.Fprintf(&sb, "pkgver=%s\n", pkgVersion(info.tag))
	} else {
		sb.WriteString("pkgver=0 # FIXME: no tagged release found; this is a VCS-style live package\n")
	}
	sb.WriteString("pkgrel=1\n")

	desc := info.description
	if desc == "" {
		desc = "FIXME"
	}
	fmt.Fprintf(&sb, "pkgdesc=\"%s\"\n", strings.ReplaceAll(desc, "\"", "\\\""))
	sb.WriteString("arch=('x86_64')\n")
	fmt.Fprintf(&sb, "url=\"%s\"\n", info.homepage)
	sb.WriteString("license=('unknown') # FIXME\n")

	if info.tag != "" {
		fmt.Fprintf(&sb, "source=(\"$pkgname-$pkgver.tar.gz::%s\")\n", info.tarballURL)
		sb.WriteString("sha256sums=('SKIP') # FIXME: run `updpkgsums` to fill this in\n")
	} else {
		sb.WriteString("source=(\"$pkgname::git+" + gitCloneURL(spec) + "\")\n")
		sb.WriteString("sha256sums=('SKIP')\n")
		sb.WriteString("\npkgver() {\n  cd \"$pkgname\"\n  git describe --tags --long 2>/dev/null | sed 's/^v//;s/-/./g' || printf \"r%s.%s\" \"$(git rev-list --count HEAD)\" \"$(git rev-parse --short HEAD)\"\n}\n")
	}

	srcDir := "$pkgname-$pkgver"
	if info.tag == "" {
		srcDir = "$pkgname"
	}

	buildBody, packageBody := pkgbuildPhaseBodies(info.buildLabel, srcDir)
	fmt.Fprintf(&sb, "\nbuild() {\n%s}\n\npackage() {\n%s}\n", buildBody, packageBody)

	return sb.String()
}

func pkgbuildPhaseBodies(buildLabel, srcDir string) (build, pkg string) {
	switch buildLabel {
	case "CMakeLists.txt":
		build = fmt.Sprintf("  cd %q\n  cmake -B build -S . -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release\n  cmake --build build\n", srcDir)
		pkg = fmt.Sprintf("  cd %q\n  DESTDIR=\"$pkgdir\" cmake --install build\n", srcDir)
	case "configure":
		build = fmt.Sprintf("  cd %q\n  ./configure --prefix=/usr\n  make\n", srcDir)
		pkg = fmt.Sprintf("  cd %q\n  make DESTDIR=\"$pkgdir\" install\n", srcDir)
	case "Makefile":
		build = fmt.Sprintf("  cd %q\n  make\n", srcDir)
		pkg = fmt.Sprintf("  cd %q\n  make DESTDIR=\"$pkgdir\" install\n", srcDir)
	default:
		build = fmt.Sprintf("  cd %q\n  # FIXME: no recognized build system detected -- fill in manually\n", srcDir)
		pkg = fmt.Sprintf("  cd %q\n  # FIXME\n", srcDir)
	}
	return
}

// genEbuild produces a starting-point Gentoo ebuild (EAPI=8). Like
// genPKGBUILD, this is a template, not a submission-ready package:
// LICENSE is a placeholder Portage will reject until corrected to a
// real entry in its license list, and KEYWORDS is left unstable-masked
// (~amd64) since nothing here has verified it actually builds.
func genEbuild(info *pkgInfo) string {
	var sb strings.Builder
	spec := info.spec

	sb.WriteString("# Copyright FIXME\n# Distributed under the terms of the GNU General Public License v2\n\n")
	sb.WriteString("EAPI=8\n\n")

	liveEbuild := info.tag == ""
	if liveEbuild {
		sb.WriteString("inherit git-r3\n\n")
	} else if info.buildLabel == "CMakeLists.txt" {
		sb.WriteString("inherit cmake\n\n")
	}

	desc := info.description
	if desc == "" {
		desc = "FIXME"
	}
	fmt.Fprintf(&sb, "DESCRIPTION=\"%s\"\n", strings.ReplaceAll(desc, "\"", "\\\""))
	fmt.Fprintf(&sb, "HOMEPAGE=\"%s\"\n", info.homepage)

	if liveEbuild {
		fmt.Fprintf(&sb, "EGIT_REPO_URI=\"%s\"\n", gitCloneURL(spec))
		sb.WriteString("KEYWORDS=\"\" # live ebuilds ship with no keywords\n")
	} else {
		fmt.Fprintf(&sb, "SRC_URI=\"%s -> ${P}.tar.gz\"\n", info.tarballURL)
		sb.WriteString("KEYWORDS=\"~amd64\" # unstable until someone actually verifies this builds\n")
	}

	sb.WriteString("LICENSE=\"FIXME\"\n")
	sb.WriteString("SLOT=\"0\"\n")

	if info.buildLabel != "CMakeLists.txt" && !liveEbuild {
		// Portage's own EAPI-8 default src_configure/src_compile/
		// src_install phases already run `econf`/`emake`/`emake install
		// DESTDIR=...` for a standard autotools/make project -- no
		// custom phase functions or eclass needed for the common case.
		sb.WriteString("\n# No custom phase functions: EAPI 8's default src_configure/src_compile/\n" +
			"# src_install already do the right thing for a standard\n" +
			"# ./configure && make && make install project.\n")
		if info.buildLabel == "" {
			sb.WriteString("# FIXME: no recognized build system was detected -- verify this is\n" +
				"# actually an autotools/make project, or add explicit phase functions.\n")
		}
	}

	return sb.String()
}

// cmdGenpkg resolves arg and writes the requested recipe file(s) to the
// current directory. wantAUR/wantEbuild: generate both if neither is
// explicitly requested.
func cmdGenpkg(arg string, wantAUR, wantEbuild bool) int {
	if !wantAUR && !wantEbuild {
		wantAUR, wantEbuild = true, true
	}

	spec := resolveSpec(arg)
	if spec == nil {
		return 1
	}

	printInfo("gathering metadata for %s...", spec.repo)
	info := gatherPkgInfo(spec)
	if info.tag == "" {
		printWarn("no tagged release found for %s -- generating a VCS/live-style package", spec.repo)
	}
	if info.buildLabel == "" {
		printWarn("no recognized build system detected -- generated recipe will need manual build steps")
	}

	wroteAny := false
	if wantAUR {
		path := "PKGBUILD"
		if err := os.WriteFile(path, []byte(genPKGBUILD(info)), 0644); err != nil {
			printErr("could not write %s: %v", path, err)
			return 1
		}
		printOK("wrote %s (starting point -- fill in the FIXME fields, run `updpkgsums`)", path)
		wroteAny = true
	}
	if wantEbuild {
		version := pkgVersion(info.tag)
		if info.tag == "" {
			version = "9999"
		}
		path := fmt.Sprintf("%s-%s.ebuild", spec.repo, version)
		if err := os.WriteFile(path, []byte(genEbuild(info)), 0644); err != nil {
			printErr("could not write %s: %v", path, err)
			return 1
		}
		printOK("wrote %s (starting point -- fill in the FIXME fields)", path)
		wroteAny = true
	}

	if !wroteAny {
		return 1
	}
	return 0
}
