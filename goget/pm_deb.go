package main

import (
	"bufio"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// Debian and Ubuntu repositories: dists/<suite>/<component>/binary-amd64/Packages.xz, .deb packages.
type debBackend struct {
	rc    repoConf
	pkgs  map[string]*pmPkg
	provs map[string]*pmPkg
}

func (d *debBackend) conf() repoConf { return d.rc }

func (d *debBackend) suite() string {
	if s := d.rc.opts["suite"]; s != "" {
		return s
	}
	if d.rc.kind == "ubuntu" {
		return "noble"
	}
	return "trixie"
}

func (d *debBackend) components() []string {
	c := d.rc.opts["components"]
	if c == "" {
		c = "main"
	}
	return strings.Split(c, ",")
}

func (d *debBackend) indexFile(comp string) string {
	return filepath.Join(pmIndexDir(d.rc.name), comp+".Packages")
}

// releaseHashes reads the SHA256 section of the suite's InRelease so the downloaded indexes can be checked.
func (d *debBackend) releaseHashes() map[string]string {
	body, status := httpGet(d.rc.url+"/dists/"+d.suite()+"/InRelease", nil)
	if status != 200 {
		body, status = httpGet(d.rc.url+"/dists/"+d.suite()+"/Release", nil)
		if status != 200 {
			return nil
		}
	}
	out := map[string]string{}
	in := false
	for _, line := range strings.Split(body, "\n") {
		if strings.HasPrefix(line, "SHA256:") {
			in = true
			continue
		}
		if in {
			if !strings.HasPrefix(line, " ") {
				in = false
				continue
			}
			f := strings.Fields(line)
			if len(f) == 3 {
				out[f[2]] = f[0]
			}
		}
	}
	return out
}

func (d *debBackend) refresh() error {
	if err := mkdirP(pmIndexDir(d.rc.name)); err != nil {
		return err
	}
	hashes := d.releaseHashes()
	if hashes == nil {
		printWarn("%s: could not read the release file; indexes are not checked", d.rc.name)
	}
	for _, comp := range d.components() {
		rel := comp + "/binary-amd64/Packages.xz"
		tmp := d.indexFile(comp) + ".xz"
		if err := httpDownload(d.rc.url+"/dists/"+d.suite()+"/"+rel, tmp); err != nil {
			return err
		}
		if want, ok := hashes[rel]; ok {
			h, err := fileSHA256(tmp)
			if err != nil {
				return err
			}
			if h != want {
				os.Remove(tmp)
				return fmt.Errorf("%s: index %s does not match the release file", d.rc.name, rel)
			}
		}
		out, err := exec.Command("xz", "-dc", tmp).Output()
		os.Remove(tmp)
		if err != nil {
			return fmt.Errorf("decompressing %s: %w", rel, err)
		}
		if err := os.WriteFile(d.indexFile(comp), out, 0o644); err != nil {
			return err
		}
	}
	return nil
}

func parseDebDeps(s string) [][]depAtom {
	var groups [][]depAtom
	for _, part := range strings.Split(s, ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		var alts []depAtom
		for _, alt := range strings.Split(part, "|") {
			alt = strings.TrimSpace(alt)
			a := depAtom{}
			if i := strings.Index(alt, "("); i >= 0 {
				cons := strings.Trim(strings.TrimSpace(alt[i:]), "()")
				alt = strings.TrimSpace(alt[:i])
				if f := strings.Fields(cons); len(f) == 2 {
					a.op, a.ver = f[0], f[1]
				}
			}
			if i := strings.Index(alt, ":"); i >= 0 { // name:any, name:amd64
				alt = alt[:i]
			}
			if i := strings.Index(alt, "["); i >= 0 {
				alt = strings.TrimSpace(alt[:i])
			}
			a.name = alt
			if a.name != "" {
				alts = append(alts, a)
			}
		}
		if len(alts) > 0 {
			groups = append(groups, alts)
		}
	}
	return groups
}

func (d *debBackend) load() error {
	if d.pkgs != nil {
		return nil
	}
	d.pkgs, d.provs = map[string]*pmPkg{}, map[string]*pmPkg{}
	found := false
	for _, comp := range d.components() {
		f, err := os.Open(d.indexFile(comp))
		if err != nil {
			continue
		}
		found = true
		sc := bufio.NewScanner(f)
		sc.Buffer(make([]byte, 1<<20), 1<<20)
		fields := map[string]string{}
		flush := func() {
			if fields["Package"] == "" {
				fields = map[string]string{}
				return
			}
			p := &pmPkg{name: fields["Package"], version: fields["Version"], repo: d.rc.name, kind: d.rc.kind,
				url: d.rc.url + "/" + fields["Filename"], sha256: fields["SHA256"], desc: fields["Description"]}
			fmt.Sscan(fields["Size"], &p.size)
			deps := fields["Pre-Depends"]
			if fields["Depends"] != "" {
				if deps != "" {
					deps += ", "
				}
				deps += fields["Depends"]
			}
			p.deps = parseDebDeps(deps)
			for _, pv := range strings.Split(fields["Provides"], ",") {
				pv = strings.TrimSpace(pv)
				if i := strings.Index(pv, " "); i >= 0 {
					pv = pv[:i]
				}
				if pv != "" {
					p.provides = append(p.provides, pv)
				}
			}
			if old, ok := d.pkgs[p.name]; !ok || verCompare(p.version, old.version) > 0 {
				d.pkgs[p.name] = p
			}
			for _, pv := range p.provides {
				if _, ok := d.provs[pv]; !ok {
					d.provs[pv] = p
				}
			}
			fields = map[string]string{}
		}
		last := ""
		for sc.Scan() {
			line := sc.Text()
			if line == "" {
				flush()
				continue
			}
			if line[0] == ' ' || line[0] == '\t' {
				continue // continuation lines (long description) are not needed
			}
			if k, v, ok := strings.Cut(line, ": "); ok {
				last = k
				fields[k] = v
			} else {
				_ = last
			}
		}
		flush()
		f.Close()
	}
	if !found {
		return fmt.Errorf("no index for %s: run `goget refresh`", d.rc.name)
	}
	return nil
}

func (d *debBackend) lookup(name string) *pmPkg {
	if p, ok := d.pkgs[name]; ok {
		return p
	}
	return d.provs[name]
}

func (d *debBackend) search(term string) []*pmPkg {
	var out []*pmPkg
	for _, p := range d.pkgs {
		if strings.Contains(p.name, term) || strings.Contains(strings.ToLower(p.desc), strings.ToLower(term)) {
			out = append(out, p)
		}
	}
	return out
}

func (d *debBackend) fetch(p *pmPkg, cacheDir string) (string, error) {
	dest := filepath.Join(cacheDir, filepath.Base(p.url))
	if h, err := fileSHA256(dest); err == nil && h == p.sha256 {
		return dest, nil
	}
	return dest, downloadTo(p.url, dest)
}

func (d *debBackend) unpack(file, stage string) error {
	out, err := exec.Command("ar", "t", file).Output()
	if err != nil {
		return fmt.Errorf("not a .deb: %w", err)
	}
	member := ""
	for _, m := range strings.Fields(string(out)) {
		if strings.HasPrefix(m, "data.tar") {
			member = m
		}
	}
	if member == "" {
		return fmt.Errorf("no data.tar in %s", filepath.Base(file))
	}
	flag := ""
	switch {
	case strings.HasSuffix(member, ".xz"):
		flag = "-J"
	case strings.HasSuffix(member, ".zst"):
		flag = "--zstd"
	case strings.HasSuffix(member, ".gz"):
		flag = "-z"
	case strings.HasSuffix(member, ".bz2"):
		flag = "-j"
	}
	ar := exec.Command("ar", "p", file, member)
	tarArgs := []string{"-x", "-p", "-f", "-", "-C", stage}
	if flag != "" {
		tarArgs = append([]string{flag}, tarArgs...)
	}
	tar := exec.Command("tar", tarArgs...)
	pipe, err := ar.StdoutPipe()
	if err != nil {
		return err
	}
	tar.Stdin = pipe
	if err := tar.Start(); err != nil {
		return err
	}
	if err := ar.Run(); err != nil {
		tar.Process.Kill()
		return err
	}
	return tar.Wait()
}

var _ = sha256.New
var _ = hex.EncodeToString
