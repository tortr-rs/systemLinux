package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// The Gentoo binary package host: <url>/Packages lists gpkg archives. Only the runtime dependencies are
// followed, USE conditionals and blockers are skipped, and "|| ( a b )" picks the first alternative.
type gentooBackend struct {
	rc   repoConf
	pkgs map[string]*pmPkg
	full map[string]*pmPkg // category/name -> package
}

func (g *gentooBackend) conf() repoConf { return g.rc }

func (g *gentooBackend) indexFile() string { return filepath.Join(pmIndexDir(g.rc.name), "Packages") }

func (g *gentooBackend) refresh() error {
	if err := mkdirP(pmIndexDir(g.rc.name)); err != nil {
		return err
	}
	return downloadTo(g.rc.url+"/Packages", g.indexFile())
}

// gentooAtoms turns a dependency string into groups of alternatives named category/name.
func gentooAtoms(s string) [][]depAtom {
	var groups [][]depAtom
	toks := strings.Fields(s)
	skip := 0 // depth of a skipped ( ... ) group
	anyDepth := 0
	var anyAlts []depAtom
	depth := 0
	pendingSkip, pendingAny := false, false
	for _, t := range toks {
		switch {
		case t == "(":
			depth++
			if skip > 0 {
				skip++
			} else if pendingSkip {
				skip = 1
			} else if pendingAny {
				anyDepth = depth
			}
			pendingSkip, pendingAny = false, false
			continue
		case t == ")":
			if skip > 0 {
				skip--
			} else if anyDepth == depth && anyDepth > 0 {
				if len(anyAlts) > 0 {
					groups = append(groups, anyAlts)
				}
				anyAlts, anyDepth = nil, 0
			}
			depth--
			continue
		case t == "||":
			pendingAny = true
			continue
		case strings.HasSuffix(t, "?"):
			pendingSkip = true
			continue
		}
		if skip > 0 || strings.HasPrefix(t, "!") {
			continue
		}
		name := gentooAtomName(t)
		if name == "" {
			continue
		}
		if anyDepth > 0 {
			anyAlts = append(anyAlts, depAtom{name: name})
		} else {
			groups = append(groups, []depAtom{{name: name}})
		}
	}
	return groups
}

func gentooAtomName(t string) string {
	t = strings.TrimLeft(t, "<>=~!")
	if i := strings.Index(t, "["); i >= 0 {
		t = t[:i]
	}
	if i := strings.Index(t, ":"); i >= 0 {
		t = t[:i]
	}
	t = strings.TrimSuffix(t, "*")
	if !strings.Contains(t, "/") {
		return ""
	}
	// drop a trailing -version (a dash followed by a digit)
	for i := 0; i+1 < len(t); i++ {
		if t[i] == '-' && isDigit(t[i+1]) {
			return t[:i]
		}
	}
	return t
}

func (g *gentooBackend) load() error {
	if g.pkgs != nil {
		return nil
	}
	f, err := os.Open(g.indexFile())
	if err != nil {
		return fmt.Errorf("no index for %s: run `goget refresh`", g.rc.name)
	}
	defer f.Close()
	g.pkgs, g.full = map[string]*pmPkg{}, map[string]*pmPkg{}
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<20), 1<<20)
	fields := map[string]string{}
	first := true
	flush := func() {
		defer func() { fields = map[string]string{} }()
		if first { // the header block
			first = false
			if fields["CPV"] == "" {
				return
			}
		}
		cpv, path := fields["CPV"], fields["PATH"]
		if cpv == "" || path == "" {
			return
		}
		full := gentooAtomName("=" + cpv)
		if full == "" {
			return
		}
		ver := strings.TrimPrefix(cpv, full+"-")
		p := &pmPkg{name: full[strings.Index(full, "/")+1:], version: ver, repo: g.rc.name, kind: "gentoo",
			url: g.rc.url + "/" + path, sha256: "", desc: fields["DESC"]}
		fmt.Sscan(fields["SIZE"], &p.size)
		p.deps = gentooAtoms(fields["RDEPEND"] + " " + fields["PDEPEND"])
		if old, ok := g.full[full]; !ok || verCompare(ver, old.version) > 0 {
			g.full[full] = p
			g.pkgs[p.name] = p
			// dependencies name category/name; index the package under that too
			p.provides = append(p.provides, full)
		}
	}
	for sc.Scan() {
		line := sc.Text()
		if line == "" {
			flush()
			continue
		}
		if k, v, ok := strings.Cut(line, ": "); ok {
			fields[k] = v
		}
	}
	flush()
	return nil
}

func (g *gentooBackend) lookup(name string) *pmPkg {
	if p, ok := g.full[name]; ok {
		return p
	}
	return g.pkgs[name]
}

func (g *gentooBackend) search(term string) []*pmPkg {
	var out []*pmPkg
	for _, p := range g.pkgs {
		if strings.Contains(p.name, term) || strings.Contains(strings.ToLower(p.desc), strings.ToLower(term)) {
			out = append(out, p)
		}
	}
	return out
}

func (g *gentooBackend) fetch(p *pmPkg, cacheDir string) (string, error) {
	dest := filepath.Join(cacheDir, filepath.Base(p.url))
	if fi, err := os.Stat(dest); err == nil && p.size > 0 && fi.Size() == p.size {
		return dest, nil
	}
	return dest, downloadTo(p.url, dest)
}

// unpack handles a gpkg (a tar holding <name>/image.tar.<compression>).
func (g *gentooBackend) unpack(file, stage string) error {
	tmp, err := os.MkdirTemp(filepath.Dir(stage), "gpkg-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	if out, err := exec.Command("tar", "-xf", file, "-C", tmp).CombinedOutput(); err != nil {
		return fmt.Errorf("%v: %s", err, strings.TrimSpace(string(out)))
	}
	var image string
	filepath.WalkDir(tmp, func(p string, d os.DirEntry, err error) error {
		if err == nil && !d.IsDir() && strings.HasPrefix(d.Name(), "image.tar") && !strings.HasSuffix(d.Name(), ".sig") && !strings.HasSuffix(d.Name(), ".asc") {
			image = p
		}
		return nil
	})
	if image == "" {
		return fmt.Errorf("%s has no image archive (an old-format package?)", filepath.Base(file))
	}
	args := []string{"-xpf", image, "-C", stage}
	if lst, err := exec.Command("tar", "-tf", image).Output(); err == nil && strings.HasPrefix(string(lst), "image/") {
		args = append(args, "--strip-components=1") // gpkg images are wrapped in an image/ directory
	}
	if out, err := exec.Command("tar", args...).CombinedOutput(); err != nil {
		return fmt.Errorf("%v: %s", err, strings.TrimSpace(string(out)))
	}
	return nil
}
