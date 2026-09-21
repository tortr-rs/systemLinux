package main

import (
	"archive/tar"
	"bufio"
	"compress/gzip"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// Arch Linux repositories: <url>/<repo>/os/x86_64/<repo>.db (a gzip'd tar of desc files), .pkg.tar.zst packages.
type archBackend struct {
	rc    repoConf
	pkgs  map[string]*pmPkg
	provs map[string]*pmPkg
}

func (a *archBackend) conf() repoConf { return a.rc }

func (a *archBackend) repos() []string {
	r := a.rc.opts["repos"]
	if r == "" {
		r = "core,extra"
	}
	return strings.Split(r, ",")
}

func (a *archBackend) dbFile(r string) string { return filepath.Join(pmIndexDir(a.rc.name), r+".db") }

func (a *archBackend) base(r string) string { return a.rc.url + "/" + r + "/os/x86_64/" }

func (a *archBackend) refresh() error {
	if err := mkdirP(pmIndexDir(a.rc.name)); err != nil {
		return err
	}
	for _, r := range a.repos() {
		if err := downloadTo(a.base(r)+r+".db", a.dbFile(r)); err != nil {
			return err
		}
	}
	return nil
}

// archDepName strips a version constraint: "glibc>=2.40" -> "glibc", "libfoo.so=1-64" -> "libfoo.so".
func archDepName(s string) depAtom {
	i := strings.IndexAny(s, "<>=")
	if i < 0 {
		return depAtom{name: s}
	}
	a := depAtom{name: s[:i]}
	rest := s[i:]
	j := 0
	for j < len(rest) && strings.ContainsRune("<>=", rune(rest[j])) {
		j++
	}
	a.op, a.ver = rest[:j], rest[j:]
	return a
}

func (a *archBackend) load() error {
	if a.pkgs != nil {
		return nil
	}
	a.pkgs, a.provs = map[string]*pmPkg{}, map[string]*pmPkg{}
	found := false
	for _, r := range a.repos() {
		f, err := os.Open(a.dbFile(r))
		if err != nil {
			continue
		}
		found = true
		gz, err := gzip.NewReader(f)
		if err != nil {
			f.Close()
			return fmt.Errorf("%s: %w", a.dbFile(r), err)
		}
		tr := tar.NewReader(gz)
		for {
			h, err := tr.Next()
			if err == io.EOF {
				break
			}
			if err != nil {
				f.Close()
				return err
			}
			if !strings.HasSuffix(h.Name, "/desc") {
				continue
			}
			sc := bufio.NewScanner(tr)
			sec := ""
			vals := map[string][]string{}
			for sc.Scan() {
				l := strings.TrimSpace(sc.Text())
				if l == "" {
					continue
				}
				if strings.HasPrefix(l, "%") && strings.HasSuffix(l, "%") {
					sec = l
					continue
				}
				vals[sec] = append(vals[sec], l)
			}
			one := func(k string) string {
				if v := vals[k]; len(v) > 0 {
					return v[0]
				}
				return ""
			}
			p := &pmPkg{name: one("%NAME%"), version: one("%VERSION%"), repo: a.rc.name, kind: "arch",
				sha256: one("%SHA256SUM%"), desc: one("%DESC%")}
			if p.name == "" {
				continue
			}
			fmt.Sscan(one("%CSIZE%"), &p.size)
			p.url = a.base(r) + one("%FILENAME%")
			for _, d := range vals["%DEPENDS%"] {
				p.deps = append(p.deps, []depAtom{archDepName(d)})
			}
			for _, pv := range vals["%PROVIDES%"] {
				p.provides = append(p.provides, archDepName(pv).name)
			}
			if old, ok := a.pkgs[p.name]; !ok || verCompare(p.version, old.version) > 0 {
				a.pkgs[p.name] = p
			}
			for _, pv := range p.provides {
				if _, ok := a.provs[pv]; !ok {
					a.provs[pv] = p
				}
			}
		}
		f.Close()
	}
	if !found {
		return fmt.Errorf("no index for %s: run `goget refresh`", a.rc.name)
	}
	return nil
}

func (a *archBackend) lookup(name string) *pmPkg {
	if p, ok := a.pkgs[name]; ok {
		return p
	}
	return a.provs[name]
}

func (a *archBackend) search(term string) []*pmPkg {
	var out []*pmPkg
	for _, p := range a.pkgs {
		if strings.Contains(p.name, term) || strings.Contains(strings.ToLower(p.desc), strings.ToLower(term)) {
			out = append(out, p)
		}
	}
	return out
}

func (a *archBackend) fetch(p *pmPkg, cacheDir string) (string, error) {
	dest := filepath.Join(cacheDir, filepath.Base(p.url))
	if h, err := fileSHA256(dest); err == nil && h == p.sha256 {
		return dest, nil
	}
	return dest, downloadTo(p.url, dest)
}

func (a *archBackend) unpack(file, stage string) error {
	out, err := exec.Command("tar", "-xpf", file, "-C", stage).CombinedOutput()
	if err != nil {
		return fmt.Errorf("%v: %s", err, strings.TrimSpace(string(out)))
	}
	return nil
}
