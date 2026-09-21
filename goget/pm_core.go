package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// goget as a package manager: packages come from the repositories chosen at install time
// (/etc/goget/repos.conf): Debian, Ubuntu, Arch, the Gentoo binary host, or plain Git hosts
// (owner/repo, built from source as before). This file holds the shared pieces: repository
// configuration, the installed-package database, version comparison and dependency resolution.

// pmRoot is the target root all package operations act on ("/" unless --root or $GOGET_ROOT is given).
var pmRoot = "/"

func pmPath(rel string) string { return filepath.Join(pmRoot, rel) }

type depAtom struct{ name, op, ver string }

type pmPkg struct {
	name, version, repo, kind string
	deps                      [][]depAtom // each group is a list of alternatives
	provides                  []string
	url, sha256               string
	size                      int64
	desc                      string
}

type repoConf struct {
	kind, name, url string
	opts            map[string]string
}

// backend is one repository: it knows how to read its index and how to unpack its package format.
type backend interface {
	conf() repoConf
	refresh() error
	load() error
	lookup(name string) *pmPkg // exact name, or a package that provides it
	search(term string) []*pmPkg
	fetch(p *pmPkg, cacheDir string) (string, error)
	unpack(file, stage string) error
}

// ---- repository configuration -------------------------------------------------------------

func pmReposPath() string { return pmPath("etc/goget/repos.conf") }

func pmLoadRepos() []repoConf {
	data, err := os.ReadFile(pmReposPath())
	if err != nil {
		return nil
	}
	var out []repoConf
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		f := strings.Fields(line)
		if len(f) < 3 {
			continue
		}
		rc := repoConf{kind: f[0], name: f[1], url: strings.TrimRight(f[2], "/"), opts: map[string]string{}}
		for _, kv := range f[3:] {
			if k, v, ok := strings.Cut(kv, "="); ok {
				rc.opts[k] = v
			}
		}
		out = append(out, rc)
	}
	return out
}

func pmSaveRepos(rs []repoConf) error {
	var b strings.Builder
	b.WriteString("# goget package repositories: <kind> <name> <url> [key=value ...]\n")
	b.WriteString("# kinds: debian, ubuntu, arch, gentoo. Order matters: the first repository that has a package wins.\n")
	b.WriteString("# owner/repo names always build from Git hosts (GitHub, GitLab, Codeberg), whatever is listed here.\n")
	for _, r := range rs {
		keys := make([]string, 0, len(r.opts))
		for k := range r.opts {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		line := r.kind + " " + r.name + " " + r.url
		for _, k := range keys {
			line += " " + k + "=" + r.opts[k]
		}
		b.WriteString(line + "\n")
	}
	if err := mkdirP(filepath.Dir(pmReposPath())); err != nil {
		return err
	}
	return os.WriteFile(pmReposPath(), []byte(b.String()), 0o644)
}

// pmPresets are the repository sets the installer offers and `goget repo use` selects.
func pmPreset(name string) []repoConf {
	switch name {
	case "debian":
		return []repoConf{{"debian", "debian", "https://deb.debian.org/debian", map[string]string{"suite": "trixie", "components": "main"}}}
	case "ubuntu":
		return []repoConf{{"ubuntu", "ubuntu", "https://archive.ubuntu.com/ubuntu", map[string]string{"suite": "noble", "components": "main,universe"}}}
	case "arch":
		return []repoConf{{"arch", "arch", "https://geo.mirror.pkgbuild.com", map[string]string{"repos": "core,extra"}}}
	case "gentoo":
		return []repoConf{{"gentoo", "gentoo", "https://distfiles.gentoo.org/releases/amd64/binpackages/23.0/x86-64", map[string]string{}}}
	}
	return nil
}

func newBackend(rc repoConf) backend {
	switch rc.kind {
	case "debian", "ubuntu":
		return &debBackend{rc: rc}
	case "arch":
		return &archBackend{rc: rc}
	case "gentoo":
		return &gentooBackend{rc: rc}
	}
	return nil
}

func pmBackends() []backend {
	var bs []backend
	for _, rc := range pmLoadRepos() {
		if b := newBackend(rc); b != nil {
			bs = append(bs, b)
		} else {
			printWarn("ignoring repository %q: unknown kind %q", rc.name, rc.kind)
		}
	}
	return bs
}

func pmIndexDir(name string) string { return pmPath("var/lib/goget/index/" + name) }
func pmCacheDir() string            { return pmPath("var/cache/goget/pkgs") }

// ---- installed-package database -------------------------------------------------------------

type installedPkg struct {
	Name     string   `json:"name"`
	Version  string   `json:"version"`
	Repo     string   `json:"repo"`
	Provides []string `json:"provides,omitempty"`
	Deps     []string `json:"deps,omitempty"`
	Files    []string `json:"files"`
	Explicit bool     `json:"explicit"`
	Time     string   `json:"time"`
}

func pmDBDir() string { return pmPath("var/lib/goget/db") }

var dbCache map[string]*installedPkg

func pmDBAll() map[string]*installedPkg {
	if dbCache != nil {
		return dbCache
	}
	dbCache = map[string]*installedPkg{}
	ents, _ := os.ReadDir(pmDBDir())
	for _, e := range ents {
		if !strings.HasSuffix(e.Name(), ".json") {
			continue
		}
		data, err := os.ReadFile(filepath.Join(pmDBDir(), e.Name()))
		if err != nil {
			continue
		}
		var ip installedPkg
		if json.Unmarshal(data, &ip) == nil && ip.Name != "" {
			dbCache[ip.Name] = &ip
		}
	}
	return dbCache
}

func pmDBSave(ip *installedPkg) error {
	if err := mkdirP(pmDBDir()); err != nil {
		return err
	}
	data, _ := json.MarshalIndent(ip, "", " ")
	if err := os.WriteFile(filepath.Join(pmDBDir(), ip.Name+".json"), data, 0o644); err != nil {
		return err
	}
	pmDBAll()[ip.Name] = ip
	return nil
}

func pmDBDelete(name string) {
	os.Remove(filepath.Join(pmDBDir(), name+".json"))
	delete(pmDBAll(), name)
}

// pmOwners maps every installed file to the package that owns it.
func pmOwners() map[string]string {
	m := map[string]string{}
	for n, ip := range pmDBAll() {
		for _, f := range ip.Files {
			m[f] = n
		}
	}
	return m
}

// baseProvides are packages/libraries the systemLinux base image already contains (its glibc,
// GNU userland, toolchain runtime); a dependency on one of these is considered satisfied.
var baseProvides = strings.Fields(`libc6 libc-bin libc6-dev glibc lib32-glibc libgcc-s1 libgcc1 gcc-libs libstdc++6 zlib1g zlib
	coreutils bash dash sed grep gawk findutils tar gzip bzip2 xz-utils xz util-linux util-linux-libs mount login passwd
	base-files base-passwd filesystem tzdata debianutils diffutils sysvinit-utils init-system-helpers adduser
	libtinfo6 ncurses-base ncurses libncursesw6 ncurses-bin readline libreadline8t64 libreadline8 lsb-base
	systemd systemd-libs libsystemd0 libudev1 udev dbus dbus-bin dbus-libs perl-base linux-libc-headers
	libgmp10 libmpfr6 libmpc3 libcap2 libattr1 libacl1 libselinux1 libpcre2-8-0 pcre2 libssl3t64 libssl3 openssl
	timezone-data libxcrypt gcc libgcc ca-certificates ca-certificates-utils libzstd1 zstd liblzma5 libbz2-1.0 libexpat1 expat`)

var baseSetCache map[string]bool

// baseSet is everything the image already provides: the built-in list plus the package names recorded at
// build time in /usr/share/goget/base-provides* (the base userland and the Debian packages of the desktop).
func baseSet() map[string]bool {
	if baseSetCache != nil {
		return baseSetCache
	}
	baseSetCache = map[string]bool{}
	for _, b := range baseProvides {
		baseSetCache[b] = true
	}
	files, _ := filepath.Glob(pmPath("usr/share/goget/base-provides*"))
	for _, f := range files {
		if data, err := os.ReadFile(f); err == nil {
			for _, l := range strings.Fields(string(data)) {
				baseSetCache[l] = true
			}
		}
	}
	return baseSetCache
}

func pmSatisfied(a depAtom, plan map[string]bool) bool {
	n := a.name
	if plan[n] {
		return true
	}
	if i := strings.Index(n, "/"); i > 0 { // Gentoo category/name: virtuals are always satisfied, the rest by short name
		if n[:i] == "virtual" {
			return true
		}
		if pmSatisfied(depAtom{name: n[i+1:]}, plan) {
			return true
		}
	}
	if baseSet()[n] {
		return true
	}
	db := pmDBAll()
	if _, ok := db[n]; ok {
		return true
	}
	for _, ip := range db {
		for _, p := range ip.Provides {
			if p == n {
				return true
			}
		}
	}
	// a plain library dependency ("libfoo.so.1"): satisfied when the library is on disk
	if strings.HasPrefix(n, "lib") && strings.Contains(n, ".so") {
		base := n
		if i := strings.Index(base, "="); i >= 0 {
			base = base[:i]
		}
		for _, d := range []string{"usr/lib64", "usr/lib", "usr/lib/x86_64-linux-gnu"} {
			if pathExists(pmPath(d + "/" + base)) {
				return true
			}
		}
	}
	return false
}

// ---- version comparison (Debian-style: epoch, then alternating digit/non-digit runs) ----------

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
		na, nb := 0, 0
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
		_, _ = na, nb
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

// ---- dependency resolution --------------------------------------------------------------------

type planItem struct {
	p        *pmPkg
	b        backend
	explicit bool
}

type resolver struct {
	backends []backend
	nodeps   bool
	planSet  map[string]bool
	plan     []planItem
	warnings []string
}

func (r *resolver) find(name string) (*pmPkg, backend) {
	for _, b := range r.backends {
		if p := b.lookup(name); p != nil {
			return p, b
		}
	}
	return nil, nil
}

func (r *resolver) visit(name string, b backend, explicit bool) error {
	var p *pmPkg
	if b == nil {
		p, b = r.find(name)
		if p == nil {
			return fmt.Errorf("package %q not found in any repository (try `goget refresh`, `goget find %s`)", name, name)
		}
	} else {
		p = b.lookup(name)
		if p == nil {
			return fmt.Errorf("package %q not found", name)
		}
	}
	if r.planSet[p.name] {
		return nil
	}
	if ip, ok := pmDBAll()[p.name]; ok && !explicit {
		_ = ip
		return nil
	}
	r.planSet[p.name] = true
	for _, pv := range p.provides {
		r.planSet[pv] = true
	}
	if !r.nodeps {
		for _, group := range p.deps {
			ok := false
			for _, a := range group {
				if pmSatisfied(a, r.planSet) {
					ok = true
					break
				}
			}
			if ok {
				continue
			}
			resolved := false
			for _, a := range group {
				if q := b.lookup(a.name); q != nil {
					if err := r.visit(q.name, b, false); err == nil {
						resolved = true
						break
					}
				}
			}
			if !resolved && len(group) > 0 {
				r.warnings = append(r.warnings, fmt.Sprintf("%s: dependency %s could not be resolved", p.name, group[0].name))
			}
		}
	}
	r.plan = append(r.plan, planItem{p: p, b: b, explicit: explicit})
	return nil
}

func pmNow() string { return time.Now().UTC().Format(time.RFC3339) }
