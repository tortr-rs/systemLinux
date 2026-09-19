package main

import (
	"encoding/json"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// Gentoo has no JSON search/package API (confirmed by hand: the only
// public lookup is packages.gentoo.org, which is HTML-only). Resolving
// a package therefore means scraping its category out of that page,
// then reading the actual ebuild from the gentoo/gentoo GitHub mirror
// via raw-file access -- the same "don't clone the whole tree just for
// one file" approach srctarball.go already uses for tagged releases,
// which matters even more here: the real portage tree is itself
// multiple GB.
//
// A resolved Gentoo repospec uses host="gentoo.org" (repospec's own
// bare host/owner/repo heuristic requires a dot to recognize something
// as a host at all, rather than a bare "owner/repo" defaulting to
// GitHub -- so this can't just be "gentoo"), owner=<category> (e.g.
// "app-shells"), repo=<package name> (e.g. "fzf") -- category fills
// the role owner plays for every git-hosted source.
const gentooHost = "gentoo.org"
const gentooMirrorRepo = "gentoo/gentoo"

// gentooResolveCategory scrapes packages.gentoo.org's package page for
// name to find its category. Returns ok=false if there's no exact
// match (a disambiguation/search-results page instead of a direct hit,
// or a genuine 404) -- never guesses. The page's own body contains the
// literal "<category>/<name>" breadcrumb text when there's an exact
// hit, e.g. "app-shells/fzf" for a search of "fzf".
func gentooResolveCategory(name string) (string, bool) {
	body, status := httpGet("https://packages.gentoo.org/packages/search?q="+url.QueryEscape(name), nil)
	if status < 200 || status >= 300 {
		return "", false
	}
	re := regexp.MustCompile(`([a-z0-9]+-[a-z0-9]+)/` + regexp.QuoteMeta(name) + `\b`)
	m := re.FindStringSubmatch(body)
	if m == nil {
		return "", false
	}
	return m[1], true
}

type ghContentItem struct {
	Name string `json:"name"`
}

// gentooLatestEbuildVersion lists <category>/<name> in the gentoo/gentoo
// mirror via GitHub's contents API and returns the highest version among
// its .ebuild files.
func gentooLatestEbuildVersion(category, name string) (string, bool) {
	u := fmt.Sprintf("https://api.github.com/repos/%s/contents/%s/%s", gentooMirrorRepo, category, name)
	body, status := httpGet(u, nil)
	if status < 200 || status >= 300 {
		return "", false
	}
	var items []ghContentItem
	if err := json.Unmarshal([]byte(body), &items); err != nil {
		return "", false
	}

	prefix := name + "-"
	var versions []string
	for _, it := range items {
		if strings.HasPrefix(it.Name, prefix) && strings.HasSuffix(it.Name, ".ebuild") {
			versions = append(versions, strings.TrimSuffix(strings.TrimPrefix(it.Name, prefix), ".ebuild"))
		}
	}
	if len(versions) == 0 {
		return "", false
	}
	sort.Slice(versions, func(i, j int) bool { return compareVersion(versions[i], versions[j]) > 0 })
	return versions[0], true
}

// gentooFetchEbuild fetches one ebuild's raw content via a single HTTP
// GET -- no git clone of the (multi-gigabyte) portage tree involved.
func gentooFetchEbuild(category, name, version string) (string, bool) {
	u := fmt.Sprintf("https://raw.githubusercontent.com/%s/master/%s/%s/%s-%s.ebuild",
		gentooMirrorRepo, category, name, name, version)
	body, status := httpGet(u, nil)
	if status < 200 || status >= 300 {
		return "", false
	}
	return body, true
}

// fetchGentooSearch wraps category resolution in the searchByName
// interface: Gentoo has no ranking signal comparable to stars, so a hit
// is just reported as a single exact match.
func fetchGentooSearch(name string) []searchResult {
	category, ok := gentooResolveCategory(name)
	if !ok {
		return nil
	}
	return []searchResult{{host: gentooHost, owner: category, repo: name, stars: 0}}
}

// buildGentoo fetches spec's latest ebuild and, if this host has
// Gentoo's `ebuild` tool available, builds and installs it via `ebuild
// ... merge` (which operates on a standalone ebuild file directly, no
// portage-tree/overlay registration needed -- unlike `emerge`, which
// only resolves packages already registered in a configured repo).
//
// IMPORTANT: the fetch/detection path above is tested against the real
// Gentoo/GitHub infrastructure; this execution step is NOT -- there is
// no Gentoo system, and no emerge/ebuild/portage installed, anywhere
// this was developed and tested. It's implemented per Gentoo's
// documented `ebuild(1)` conventions but unverified end-to-end.
func buildGentoo(spec *repospec) int {
	category, name := spec.owner, spec.repo

	version, ok := gentooLatestEbuildVersion(category, name)
	if !ok {
		printErr("could not find any ebuild for %s/%s on Gentoo", category, name)
		return 1
	}

	content, ok := gentooFetchEbuild(category, name, version)
	if !ok {
		printErr("could not fetch the %s-%s ebuild", name, version)
		return 1
	}

	destDir := filepath.Join(cacheGentooDir(spec), fmt.Sprintf("%s-%s", name, version))
	if err := mkdirP(destDir); err != nil {
		printErr("could not create cache directory: %v", err)
		return 1
	}
	ebuildPath := filepath.Join(destDir, fmt.Sprintf("%s-%s.ebuild", name, version))
	if err := os.WriteFile(ebuildPath, []byte(content), 0644); err != nil {
		printErr("could not write ebuild file: %v", err)
		return 1
	}
	printInfo("fetched %s/%s-%s.ebuild", category, name, version)

	if !pathIsExecutableFile("/usr/bin/ebuild") && !pathIsExecutableFile("/usr/sbin/ebuild") {
		printErr("Gentoo's `ebuild` tool isn't available on this system -- Portage is required to "+
			"actually build/install an ebuild. The ebuild itself has been saved to %s if you want to "+
			"use it on a Gentoo system.", ebuildPath)
		return 1
	}

	rc := runCommand("", []string{"sudo", "ebuild", ebuildPath, "merge"})
	if rc != 0 {
		printErr("ebuild merge failed")
	}
	return rc
}

func cacheGentooDir(spec *repospec) string {
	return filepath.Join(homeDir(), ".cache/goget/src", gentooHost, spec.owner, spec.repo)
}
