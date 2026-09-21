package main

import (
	"bufio"
	"crypto/sha256"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

// goget on nixpkgs: packages are the prebuilt, signed store paths of the NixOS binary cache
// (cache.nixos.org), installed into /nix/store with their whole runtime closure and exposed through
// profiles with generations (install, remove, roll back, garbage-collect). No Nix tools are needed:
// goget reads the channel's list of store paths for names and the cache's .narinfo files for
// dependencies, hashes and signatures.

const nixStorePrefix = "/nix/store/"

func nixStoreDir() string { return pmPath("nix/store") }
func nixVarDir() string   { return pmPath("nix/var/goget") }

func nixCacheURL(rc *repoConf) string {
	if u := rc.opts["cache"]; u != "" {
		return strings.TrimRight(u, "/")
	}
	return "https://cache.nixos.org"
}

// ---- the package index: channel store-paths list ------------------------------------------------

type nixEntry struct {
	hash, name, pname, ver, base, output string
}

type nixIndex struct{ by map[string][]nixEntry }

var nixOutputs = []string{"bin", "dev", "doc", "man", "info", "debug", "lib", "static", "devdoc", "terminfo", "out", "lib32", "libgcc", "modsdev"}

func nixIndexFile(rc *repoConf) string { return filepath.Join(nixVarDir(), "index", rc.name+".paths") }

func nixRefreshIndex(rc *repoConf) error {
	if err := mkdirP(filepath.Dir(nixIndexFile(rc))); err != nil {
		return err
	}
	tmp := nixIndexFile(rc) + ".xz"
	if err := httpDownload(rc.url+"/store-paths.xz", tmp); err != nil {
		return err
	}
	out, err := exec.Command("xz", "-dc", tmp).Output()
	os.Remove(tmp)
	if err != nil {
		return fmt.Errorf("decompressing the package index: %w", err)
	}
	return os.WriteFile(nixIndexFile(rc), out, 0o644)
}

func nixLoadIndex(rc *repoConf) (*nixIndex, error) {
	f, err := os.Open(nixIndexFile(rc))
	if err != nil {
		printInfo("fetching the %s package index...", rc.name)
		if err := nixRefreshIndex(rc); err != nil {
			return nil, err
		}
		if f, err = os.Open(nixIndexFile(rc)); err != nil {
			return nil, err
		}
	}
	defer f.Close()
	idx := &nixIndex{by: map[string][]nixEntry{}}
	mainVer := map[string]map[string]bool{} // pname -> versions that have a plain main output
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := sc.Text()
		if !strings.HasPrefix(line, nixStorePrefix) || len(line) < len(nixStorePrefix)+34 {
			continue
		}
		rest := line[len(nixStorePrefix):]
		e := nixEntry{hash: rest[:32], name: rest[33:]}
		i := -1
		for j := 0; j+1 < len(e.name); j++ {
			if e.name[j] == '-' && isDigit(e.name[j+1]) {
				i = j
				break
			}
		}
		if i < 0 {
			e.pname = e.name
		} else {
			e.pname, e.ver = e.name[:i], e.name[i+1:]
		}
		idx.by[e.pname] = append(idx.by[e.pname], e)
		if e.ver != "" && !strings.Contains(e.ver, "-") {
			if mainVer[e.pname] == nil {
				mainVer[e.pname] = map[string]bool{}
			}
			mainVer[e.pname][e.ver] = true
		}
	}
	// a dashed suffix after a version that also exists plainly is an output of that version (dev, doc, bin,
	// spirv2dxil, ...); otherwise the whole string is the version ("2.40-66", "1.0-rc1")
	for p, es := range idx.by {
		for k := range es {
			e := &es[k]
			e.base = e.ver
			if e.ver == "" {
				continue
			}
			if i := strings.Index(e.ver, "-"); i > 0 && mainVer[p][e.ver[:i]] {
				e.base, e.output = e.ver[:i], e.ver[i+1:]
			}
		}
	}
	return idx, sc.Err()
}

// nixSystemOf reports the platform a store path was built for. The channel's list mixes all platforms, and
// nothing in a name says which is which, so goget follows the path's references to its glibc and reads which
// dynamic loader that glibc contains (ld-linux-x86-64.so.2 or ld-linux-aarch64.so.1): only the start of its
// archive is downloaded. Paths without any glibc in reach (data, scripts) come back empty and are accepted.
func nixSystemOf(cache, hash string) string {
	memo := filepath.Join(nixVarDir(), "db", hash+".system")
	if data, err := os.ReadFile(memo); err == nil {
		return strings.TrimSpace(string(data))
	}
	sys := ""
	seen := map[string]bool{hash: true}
	frontier := []string{hash}
	for depth := 0; depth < 4 && sys == "" && len(frontier) > 0; depth++ {
		var next []string
		for _, h := range frontier {
			ni, err := nixNarinfo(cache, h)
			if err != nil {
				continue
			}
			for _, r := range ni.refs {
				rh := r[:32]
				if seen[rh] {
					continue
				}
				seen[rh] = true
				if isGlibcName(r[33:]) {
					if a := nixGlibcArch(cache, rh); a != "" {
						sys = a
						break
					}
				}
				next = append(next, rh)
			}
			if sys != "" {
				break
			}
		}
		frontier = next
	}
	if mkdirP(filepath.Dir(memo)) == nil {
		os.WriteFile(memo, []byte(sys+"\n"), 0o644)
	}
	return sys
}

func isGlibcName(name string) bool {
	if !strings.HasPrefix(name, "glibc-") || len(name) < 7 || !isDigit(name[6]) {
		return false
	}
	for _, c := range name[6:] {
		if !(c >= '0' && c <= '9') && c != '.' && c != '-' {
			return false
		}
	}
	return true
}

// nixGlibcArch finds out which platform a glibc store path is for by scanning the start of its archive.
func nixGlibcArch(cache, hash string) string {
	memo := filepath.Join(nixVarDir(), "db", hash+".arch")
	if data, err := os.ReadFile(memo); err == nil {
		return strings.TrimSpace(string(data))
	}
	ni, err := nixNarinfo(cache, hash)
	if err != nil {
		return ""
	}
	resp, err := nixHTTP.Get(cache + "/" + ni.url)
	if err != nil || resp.StatusCode != 200 {
		return ""
	}
	defer resp.Body.Close()
	var r io.Reader = resp.Body
	if tool := map[string]string{"xz": "xz", "zstd": "zstd", "bzip2": "bzip2"}[ni.compression]; tool != "" {
		cmd := exec.Command(tool, "-dc")
		cmd.Stdin = resp.Body
		out, err := cmd.StdoutPipe()
		if err != nil || cmd.Start() != nil {
			return ""
		}
		defer func() { cmd.Process.Kill(); cmd.Wait() }()
		r = out
	}
	buf := make([]byte, 1<<20)
	var tail string
	arch := ""
	for read := 0; read < 24<<20 && arch == ""; {
		n, err := r.Read(buf)
		if n > 0 {
			chunk := tail + string(buf[:n])
			switch {
			case strings.Contains(chunk, "ld-linux-x86-64.so.2"):
				arch = nixSystem
			case strings.Contains(chunk, "ld-linux-aarch64.so.1"):
				arch = "aarch64-linux"
			}
			if len(chunk) > 64 {
				tail = chunk[len(chunk)-64:]
			}
			read += n
		}
		if err != nil {
			break
		}
	}
	if arch != "" && mkdirP(filepath.Dir(memo)) == nil {
		os.WriteFile(memo, []byte(arch+"\n"), 0o644)
	}
	return arch
}

// resolve picks the store path to install for a package name: the newest version built for this machine,
// its "bin" output when there is one (otherwise the main output).
func (idx *nixIndex) resolve(cache string, name string) (*nixEntry, error) {
	es := idx.by[name]
	if len(es) == 0 {
		var near []string
		for p := range idx.by {
			if strings.Contains(p, name) && len(near) < 5 {
				near = append(near, p)
			}
		}
		sort.Strings(near)
		msg := fmt.Sprintf("package %q not found in the nixpkgs index", name)
		if len(near) > 0 {
			msg += " (similar: " + strings.Join(near, ", ") + ")"
		}
		return nil, fmt.Errorf("%s", msg)
	}
	// versions, newest first
	seen := map[string]bool{}
	var versions []string
	for _, e := range es {
		if e.ver != "" && !seen[e.base] {
			seen[e.base] = true
			versions = append(versions, e.base)
		}
	}
	sort.Slice(versions, func(i, j int) bool { return verCompare(versions[i], versions[j]) > 0 })
	for _, v := range versions {
		var main, bin []nixEntry
		for _, e := range es {
			if e.base != v {
				continue
			}
			switch e.output {
			case "":
				main = append(main, e)
			case "bin":
				bin = append(bin, e)
			}
		}
		cand := main
		if len(bin) > 0 {
			cand = bin
		}
		// keep the builds made for this machine; several builds of the same name: the largest contents win
		var pick *nixEntry
		var size int64 = -1
		for i := range cand {
			if sys := nixSystemOf(cache, cand[i].hash); sys != "" && sys != nixSystem {
				continue
			}
			ni, err := nixNarinfo(cache, cand[i].hash)
			if err == nil && ni.narSize > size {
				size, pick = ni.narSize, &cand[i]
			}
		}
		if pick != nil {
			return pick, nil
		}
	}
	return nil, fmt.Errorf("package %q has no %s build in this channel", name, nixSystem)
}

const nixSystem = "x86_64-linux"

// ---- binary cache: narinfo ------------------------------------------------------------------------

type narinfo struct {
	storePath, url, compression, fileHash, narHash, deriver string
	fileSize, narSize                                       int64
	refs, sigs                                              []string
}

func (n *narinfo) hash() string { return strings.TrimPrefix(n.storePath, nixStorePrefix)[:32] }

var nixHTTP = &http.Client{Transport: &http.Transport{ResponseHeaderTimeout: 45 * time.Second, MaxIdleConnsPerHost: 16}}

func parseNarinfo(body string) (*narinfo, error) {
	n := &narinfo{}
	for _, line := range strings.Split(body, "\n") {
		k, v, ok := strings.Cut(line, ": ")
		if !ok {
			continue
		}
		switch k {
		case "StorePath":
			n.storePath = v
		case "URL":
			n.url = v
		case "Compression":
			n.compression = v
		case "FileHash":
			n.fileHash = v
		case "NarHash":
			n.narHash = v
		case "Deriver":
			n.deriver = v
		case "FileSize":
			n.fileSize, _ = strconv.ParseInt(v, 10, 64)
		case "NarSize":
			n.narSize, _ = strconv.ParseInt(v, 10, 64)
		case "References":
			n.refs = strings.Fields(v)
		case "Sig":
			n.sigs = append(n.sigs, v)
		}
	}
	if n.storePath == "" || n.url == "" || n.narHash == "" {
		return nil, fmt.Errorf("incomplete narinfo")
	}
	return n, nil
}

func nixDBPath(hash string) string { return filepath.Join(nixVarDir(), "db", hash+".narinfo") }

// nixNarinfo returns the signed metadata of a store path, from the local database or the cache.
func nixNarinfo(cache, hash string) (*narinfo, error) {
	if data, err := os.ReadFile(nixDBPath(hash)); err == nil {
		if n, err := parseNarinfo(string(data)); err == nil {
			return n, nil
		}
	}
	resp, err := nixHTTP.Get(cache + "/" + hash + ".narinfo")
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("%s is not in the binary cache (HTTP %d)", hash, resp.StatusCode)
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	n, err := parseNarinfo(string(body))
	if err != nil {
		return nil, err
	}
	fp := "1;" + n.storePath + ";" + n.narHash + ";" + strconv.FormatInt(n.narSize, 10) + ";"
	var rs []string
	for _, r := range n.refs {
		rs = append(rs, nixStorePrefix+r)
	}
	fp += strings.Join(rs, ",")
	if err := nixVerifySig(fp, n.sigs); err != nil {
		return nil, fmt.Errorf("%s: %w", n.storePath, err)
	}
	if err := mkdirP(filepath.Dir(nixDBPath(hash))); err == nil {
		os.WriteFile(nixDBPath(hash), body, 0o644)
	}
	return n, nil
}

func nixStoreHas(n *narinfo) bool {
	_, err := os.Lstat(filepath.Join(nixStoreDir(), strings.TrimPrefix(n.storePath, nixStorePrefix)))
	return err == nil
}

// nixClosure fetches the narinfo of the given store path hashes and everything they reference.
func nixClosure(cache string, roots []string) (map[string]*narinfo, error) {
	out := map[string]*narinfo{}
	var mu sync.Mutex
	var firstErr error
	frontier := roots
	for len(frontier) > 0 {
		var next []string
		var wg sync.WaitGroup
		sem := make(chan struct{}, 16)
		for _, h := range frontier {
			mu.Lock()
			_, seen := out[h]
			if !seen {
				out[h] = nil
			}
			mu.Unlock()
			if seen {
				continue
			}
			wg.Add(1)
			sem <- struct{}{}
			go func(h string) {
				defer wg.Done()
				defer func() { <-sem }()
				n, err := nixNarinfo(cache, h)
				mu.Lock()
				defer mu.Unlock()
				if err != nil {
					if firstErr == nil {
						firstErr = err
					}
					return
				}
				out[h] = n
				for _, r := range n.refs {
					rh := r[:32]
					if _, ok := out[rh]; !ok {
						next = append(next, rh)
					}
				}
			}(h)
		}
		wg.Wait()
		if firstErr != nil {
			return nil, firstErr
		}
		frontier = next
	}
	return out, nil
}

// ---- installing store paths -----------------------------------------------------------------------

func nixFetchOne(cache string, n *narinfo) error {
	if nixStoreHas(n) {
		return nil
	}
	resp, err := nixHTTP.Get(cache + "/" + n.url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return fmt.Errorf("%s: HTTP %d", n.url, resp.StatusCode)
	}
	fileHR := newHashingReader(resp.Body)
	var narSrc io.Reader = fileHR
	var cmd *exec.Cmd
	switch n.compression {
	case "xz":
		cmd = exec.Command("xz", "-dc")
	case "zstd":
		cmd = exec.Command("zstd", "-dc")
	case "bzip2":
		cmd = exec.Command("bzip2", "-dc")
	case "none", "":
	default:
		return fmt.Errorf("%s: unsupported compression %q", n.storePath, n.compression)
	}
	if cmd != nil {
		cmd.Stdin = fileHR
		out, err := cmd.StdoutPipe()
		if err != nil {
			return err
		}
		if err := cmd.Start(); err != nil {
			return err
		}
		narSrc = out
	}
	narHR := newHashingReader(narSrc)
	final := filepath.Join(nixStoreDir(), strings.TrimPrefix(n.storePath, nixStorePrefix))
	tmp := filepath.Join(nixStoreDir(), ".tmp-"+n.hash())
	forceRemove(tmp)
	uerr := unpackNAR(narHR, tmp)
	if cmd != nil {
		io.Copy(io.Discard, narHR)
		if werr := cmd.Wait(); uerr == nil && werr != nil {
			uerr = werr
		}
	}
	io.Copy(io.Discard, fileHR)
	if uerr != nil {
		forceRemove(tmp)
		return fmt.Errorf("%s: %w", n.storePath, uerr)
	}
	if got := "sha256:" + narHR.nix32(); got != n.narHash {
		forceRemove(tmp)
		return fmt.Errorf("%s: contents do not match the signed hash", n.storePath)
	}
	if n.fileHash != "" {
		if got := "sha256:" + fileHR.nix32(); got != n.fileHash {
			forceRemove(tmp)
			return fmt.Errorf("%s: download does not match its hash", n.storePath)
		}
	}
	return os.Rename(tmp, final)
}

// forceRemove deletes a tree whose directories may be read-only (store paths are 0555).
func forceRemove(p string) {
	filepath.Walk(p, func(path string, info os.FileInfo, err error) error {
		if err == nil && info.IsDir() {
			os.Chmod(path, 0o755)
		}
		return nil
	})
	os.RemoveAll(p)
}

// nixEnsure downloads every path of the closure that is not in the store yet.
func nixEnsure(cache string, closure map[string]*narinfo) error {
	var todo []*narinfo
	var total int64
	for _, n := range closure {
		if n != nil && !nixStoreHas(n) {
			todo = append(todo, n)
			total += n.fileSize
		}
	}
	if len(todo) == 0 {
		return nil
	}
	sort.Slice(todo, func(i, j int) bool { return todo[i].storePath < todo[j].storePath })
	printInfo("downloading %d store paths (%.1f MB)", len(todo), float64(total)/1048576)
	var mu sync.Mutex
	var firstErr error
	done := 0
	sem := make(chan struct{}, 4)
	var wg sync.WaitGroup
	for _, n := range todo {
		mu.Lock()
		stop := firstErr != nil
		mu.Unlock()
		if stop {
			break
		}
		wg.Add(1)
		sem <- struct{}{}
		go func(n *narinfo) {
			defer wg.Done()
			defer func() { <-sem }()
			err := nixFetchOne(cache, n)
			mu.Lock()
			defer mu.Unlock()
			if err != nil && firstErr == nil {
				firstErr = err
			}
			done++
			if isTerminal(os.Stderr) {
				fmt.Fprintf(os.Stderr, "\r  %d/%d  %-60.60s", done, len(todo), strings.TrimPrefix(n.storePath, nixStorePrefix)[33:])
			}
		}(n)
	}
	wg.Wait()
	if isTerminal(os.Stderr) {
		fmt.Fprintln(os.Stderr)
	}
	return firstErr
}

func nixInitStore() error {
	if err := os.MkdirAll(nixStoreDir(), 0o1775); err != nil {
		return fmt.Errorf("cannot create %s (run once as root: sudo goget init): %w", nixStoreDir(), err)
	}
	if err := mkdirP(nixVarDir()); err != nil {
		return err
	}
	if fi, err := os.Stat(nixStoreDir()); err == nil {
		if fi.Mode().Perm()&0o200 == 0 || (os.Geteuid() != 0 && unixAccess(nixStoreDir()) != nil) {
			return fmt.Errorf("%s is not writable for you (run once as root: sudo goget init)", nixStoreDir())
		}
	}
	return nil
}

func unixAccess(p string) error {
	f, err := os.CreateTemp(p, ".w-")
	if err != nil {
		return err
	}
	f.Close()
	return os.Remove(f.Name())
}

var _ = sha256.New
