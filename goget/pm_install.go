package main

import (
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

// Unpacking a package into a staging directory, merging it into the root without clobbering the
// base image, and recording what it owns.

// mapTop maps a package's top-level layout onto the merged-/usr layout of systemLinux.
func mapTop(rel string) (string, bool) {
	switch rel {
	case "bin", "sbin", "lib", "lib64", "usr/sbin":
		return "", false
	}
	for _, m := range [][2]string{{"bin/", "usr/bin/"}, {"sbin/", "usr/bin/"}, {"usr/sbin/", "usr/bin/"},
		{"lib/", "usr/lib/"}, {"lib64/", "usr/lib64/"}} {
		if strings.HasPrefix(rel, m[0]) {
			return m[1] + rel[len(m[0]):], true
		}
	}
	return rel, true
}

func copyFile(src, dst string, mode os.FileMode) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, mode.Perm())
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return err
	}
	return out.Close()
}

// pmMerge moves the unpacked package from stage into pmRoot. Files that already exist and belong to
// nothing in the database (the base image) or to another package are kept, as are existing /etc files.
func pmMerge(stage string, ip *installedPkg, owners map[string]string) (skipped []string, err error) {
	err = filepath.WalkDir(stage, func(path string, d fs.DirEntry, werr error) error {
		if werr != nil {
			return werr
		}
		rel, _ := filepath.Rel(stage, path)
		if rel == "." {
			return nil
		}
		if !strings.Contains(rel, "/") && strings.HasPrefix(rel, ".") {
			if d.IsDir() {
				return filepath.SkipDir
			}
			return nil // .PKGINFO, .MTREE, .INSTALL ...
		}
		dstRel, ok := mapTop(rel)
		if !ok {
			return nil
		}
		dst := filepath.Join(pmRoot, dstRel)
		info, _ := d.Info()
		if d.IsDir() {
			if fi, e := os.Lstat(dst); e == nil {
				if fi.IsDir() || fi.Mode()&os.ModeSymlink != 0 {
					return nil
				}
				skipped = append(skipped, dstRel)
				return filepath.SkipDir
			}
			return os.MkdirAll(dst, info.Mode().Perm())
		}
		if fi, e := os.Lstat(dst); e == nil {
			if owners[dstRel] == ip.Name {
				os.Remove(dst)
			} else {
				// present already (base image, config or another package): keep it
				_ = fi
				skipped = append(skipped, dstRel)
				return nil
			}
		}
		if e := mkdirP(filepath.Dir(dst)); e != nil {
			return e
		}
		if d.Type()&fs.ModeSymlink != 0 {
			target, e := os.Readlink(path)
			if e != nil {
				return e
			}
			if e := os.Symlink(target, dst); e != nil {
				return e
			}
		} else if d.Type().IsRegular() {
			if e := os.Rename(path, dst); e != nil {
				if e2 := copyFile(path, dst, info.Mode()); e2 != nil {
					return e2
				}
				os.Chmod(dst, info.Mode())
			}
		} else {
			return nil // devices, fifos: not shipped by packages we install
		}
		ip.Files = append(ip.Files, dstRel)
		return nil
	})
	return skipped, err
}

// pmInstallOne downloads, verifies, unpacks and merges one package.
func pmInstallOne(it planItem) error {
	p := it.p
	if err := mkdirP(pmCacheDir()); err != nil {
		return err
	}
	file, err := it.b.fetch(p, pmCacheDir())
	if err != nil {
		return err
	}
	if p.sha256 != "" {
		got, err := fileSHA256(file)
		if err != nil {
			return err
		}
		if got != p.sha256 {
			os.Remove(file)
			return fmt.Errorf("%s: checksum mismatch (got %s, want %s); the download was removed", p.name, got, p.sha256)
		}
	}
	stage, err := os.MkdirTemp(pmPath("var/cache/goget"), "stage-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(stage)
	if err := it.b.unpack(file, stage); err != nil {
		return fmt.Errorf("%s: unpacking failed: %w", p.name, err)
	}
	ip := &installedPkg{Name: p.name, Version: p.version, Repo: p.repo, Provides: p.provides,
		Explicit: it.explicit, Time: pmNow()}
	for _, g := range p.deps {
		if len(g) > 0 {
			ip.Deps = append(ip.Deps, g[0].name)
		}
	}
	if old, ok := pmDBAll()[p.name]; ok {
		ip.Explicit = ip.Explicit || old.Explicit
	}
	skipped, err := pmMerge(stage, ip, pmOwners())
	if err != nil {
		return fmt.Errorf("%s: %w", p.name, err)
	}
	sort.Strings(ip.Files)
	if err := pmDBSave(ip); err != nil {
		return err
	}
	if len(skipped) > 0 {
		printInfo("%s: kept %d file(s) that already exist on this system", p.name, len(skipped))
	}
	return nil
}

func pmAfterInstall(touched []string) {
	// Debian's multiarch library directory must be on the loader path
	conf := pmPath("etc/ld.so.conf")
	if data, err := os.ReadFile(conf); err == nil && !strings.Contains(string(data), "/usr/lib/x86_64-linux-gnu") {
		f, _ := os.OpenFile(conf, os.O_APPEND|os.O_WRONLY, 0o644)
		if f != nil {
			f.WriteString("/usr/lib/x86_64-linux-gnu\n")
			f.Close()
		}
	}
	if pmRoot != "/" {
		return
	}
	schemas := false
	for _, f := range touched {
		if strings.HasPrefix(f, "usr/share/glib-2.0/schemas/") {
			schemas = true
		}
	}
	runQuiet("ldconfig")
	if schemas {
		runQuiet("glib-compile-schemas", "/usr/share/glib-2.0/schemas")
	}
}

func runQuiet(name string, args ...string) {
	if _, err := exec.LookPath(name); err != nil {
		return
	}
	exec.Command(name, args...).Run()
}

// pmRemove deletes a package's files and its database entry.
func pmRemove(name string) error {
	ip, ok := pmDBAll()[name]
	if !ok {
		return fmt.Errorf("%s is not installed (or was not installed by goget)", name)
	}
	owners := pmOwners()
	for _, f := range ip.Files {
		if owners[f] != name {
			continue
		}
		p := filepath.Join(pmRoot, f)
		os.Remove(p)
		for d := filepath.Dir(p); d != filepath.Clean(pmRoot) && len(d) > len(pmRoot); d = filepath.Dir(d) {
			if os.Remove(d) != nil { // only empty directories go
				break
			}
		}
	}
	pmDBDelete(name)
	return nil
}

func downloadTo(url, dest string) error {
	tmp := dest + ".part"
	if err := httpDownload(url, tmp); err != nil {
		os.Remove(tmp)
		return err
	}
	return os.Rename(tmp, dest)
}
