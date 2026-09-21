package main

import (
	"bufio"
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// `goget upgrade`: image-based system updates. An installed systemLinux boots a read-only squashfs
// image (with a persistent overlay for your files and settings) from the data partition. Upgrading
// downloads the newest signed image next to the current one, adds it to GRUB, and boots it once;
// the running system makes it the default after it has stayed up for a minute, otherwise the next
// boot returns to the previous image.

const (
	defaultUpdateURL = "https://github.com/tortr-rs/systemLinux/releases/latest/download/latest.json"
	// Ed25519 public key that signs latest.json (the private half never leaves the maintainer).
	updatePublicKeyHex = "cb93031cf89e0c1345a431b6e2b50f293d8beaaa0547f64b68640f3135b265bf"
	dataBoot           = "/data/boot"
)

type updateFile struct {
	Name   string `json:"name"`
	URL    string `json:"url"`
	SHA256 string `json:"sha256"`
	Size   int64  `json:"size"`
}

type updateIndex struct {
	Version  string       `json:"version"`
	Released string       `json:"released"`
	Notes    string       `json:"notes"`
	Files    []updateFile `json:"files"`
}

// versionLess compares dotted versions numerically ("0.4.10" > "0.4.9").
func versionLess(a, b string) bool {
	split := func(s string) []int {
		var out []int
		for _, p := range strings.FieldsFunc(s, func(r rune) bool { return r == '.' || r == '-' }) {
			n, err := strconv.Atoi(p)
			if err != nil {
				n = 0
			}
			out = append(out, n)
		}
		return out
	}
	x, y := split(a), split(b)
	for i := 0; i < len(x) || i < len(y); i++ {
		var xi, yi int
		if i < len(x) {
			xi = x[i]
		}
		if i < len(y) {
			yi = y[i]
		}
		if xi != yi {
			return xi < yi
		}
	}
	return false
}

func cmdlineValue(key string) string {
	b, err := os.ReadFile("/proc/cmdline")
	if err != nil {
		return ""
	}
	for _, f := range strings.Fields(string(b)) {
		if strings.HasPrefix(f, key) {
			return strings.TrimPrefix(f, key)
		}
	}
	return ""
}

func verifyIndex(body, sigB64 string) error {
	pub, err := hex.DecodeString(updatePublicKeyHex)
	if err != nil || len(pub) != ed25519.PublicKeySize {
		return fmt.Errorf("bad built-in public key")
	}
	if override, err := os.ReadFile("/usr/share/systemlinux/update.pub"); err == nil {
		if p, err := hex.DecodeString(strings.TrimSpace(string(override))); err == nil && len(p) == ed25519.PublicKeySize {
			pub = p
		}
	}
	sig, err := base64.StdEncoding.DecodeString(strings.TrimSpace(sigB64))
	if err != nil || !ed25519.Verify(ed25519.PublicKey(pub), []byte(body), sig) {
		return fmt.Errorf("the update index signature does not match; refusing to use it")
	}
	return nil
}

func fileSHA256(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

// downloadResumable downloads url to dest, continuing a previous partial download.
func downloadResumable(url, dest string, size int64) error {
	var have int64
	if fi, err := os.Stat(dest); err == nil {
		have = fi.Size()
	}
	if size > 0 && have == size {
		return nil
	}
	if size > 0 && have > size {
		have = 0
		os.Remove(dest)
	}
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return err
	}
	if have > 0 {
		req.Header.Set("Range", fmt.Sprintf("bytes=%d-", have))
	}
	client := &http.Client{Timeout: 0}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	flags := os.O_CREATE | os.O_WRONLY
	switch resp.StatusCode {
	case http.StatusPartialContent:
		flags |= os.O_APPEND
	case http.StatusOK:
		flags |= os.O_TRUNC // the server ignored Range: start over
		have = 0
	default:
		return fmt.Errorf("download failed: HTTP %d", resp.StatusCode)
	}
	out, err := os.OpenFile(dest, flags, 0o644)
	if err != nil {
		return err
	}
	defer out.Close()

	total := size
	if total == 0 {
		total = have + resp.ContentLength
	}
	buf := make([]byte, 1<<20)
	done := have
	last := time.Now()
	for {
		n, rerr := resp.Body.Read(buf)
		if n > 0 {
			if _, err := out.Write(buf[:n]); err != nil {
				return err
			}
			done += int64(n)
			if time.Since(last) > 500*time.Millisecond && total > 0 {
				fmt.Fprintf(os.Stderr, "\r  %s  %3d%%  %d / %d MB", filepath.Base(dest), done*100/total, done>>20, total>>20)
				last = time.Now()
			}
		}
		if rerr == io.EOF {
			break
		}
		if rerr != nil {
			return rerr
		}
	}
	fmt.Fprintf(os.Stderr, "\r  %s  100%%  %d MB            \n", filepath.Base(dest), done>>20)
	return out.Sync()
}

func freeBytes(path string) int64 {
	var st syscall.Statfs_t
	if err := syscall.Statfs(path, &st); err != nil {
		return -1
	}
	return int64(st.Bavail) * int64(st.Bsize)
}

func installedVersions() []string {
	entries, _ := os.ReadDir(filepath.Join(dataBoot, "images"))
	var vs []string
	for _, e := range entries {
		if e.IsDir() && !strings.HasSuffix(e.Name(), ".part") {
			vs = append(vs, e.Name())
		}
	}
	sort.Slice(vs, func(i, j int) bool { return versionLess(vs[j], vs[i]) })
	return vs
}

func upgradeRun(args []string) int {
	fs := flag.NewFlagSet("upgrade", flag.ContinueOnError)
	check := fs.Bool("check", false, "only report whether a newer image exists")
	yes := fs.Bool("yes", false, "do not ask for confirmation")
	url := fs.String("url", "", "update index URL (default: the latest systemLinux release)")
	fs.Usage = func() {
		fmt.Fprintln(os.Stderr, "usage: goget upgrade [--check] [--yes] [--url URL]")
		fs.PrintDefaults()
	}
	if err := fs.Parse(args); err != nil {
		return 2
	}

	current := cmdlineValue("systeml.version=")
	if current == "" || cmdlineValue("systeml.image=") == "" {
		printErr("upgrade works on an installed systemLinux (booted from its disk); this system is running from the live medium or an unversioned image")
		return 1
	}
	indexURL := *url
	if indexURL == "" {
		indexURL = os.Getenv("GOGET_UPDATE_URL")
	}
	if indexURL == "" {
		indexURL = defaultUpdateURL
	}

	printInfo("running image %s; checking %s", current, indexURL)
	body, status := httpGet(indexURL, nil)
	if status < 200 || status >= 300 {
		printErr("could not fetch the update index (HTTP %d)", status)
		return 1
	}
	sig, status := httpGet(indexURL+".sig", nil)
	if status < 200 || status >= 300 {
		printErr("could not fetch the update signature (HTTP %d)", status)
		return 1
	}
	if err := verifyIndex(body, sig); err != nil {
		printErr("%v", err)
		return 1
	}
	var idx updateIndex
	if err := json.Unmarshal([]byte(body), &idx); err != nil || idx.Version == "" || len(idx.Files) == 0 {
		printErr("the update index is malformed")
		return 1
	}
	if !versionLess(current, idx.Version) {
		printOK("you are up to date (image %s)", current)
		return 0
	}
	printInfo("new image available: %s (you have %s)", idx.Version, current)
	if idx.Notes != "" {
		fmt.Println(idx.Notes)
	}
	var need int64
	for _, f := range idx.Files {
		need += f.Size
	}
	if *check {
		return 0
	}
	if os.Geteuid() != 0 {
		printErr("upgrade must be run as root")
		return 1
	}
	if !pathIsDir(filepath.Join(dataBoot, "images")) {
		printErr("%s/images not found: is the data partition mounted at /data?", dataBoot)
		return 1
	}
	if free := freeBytes(dataBoot); free >= 0 && free < need+(512<<20) {
		printErr("not enough free space on the system disk: need about %d MB, have %d MB", (need+(512<<20))>>20, free>>20)
		return 1
	}
	if !*yes {
		fmt.Printf("Download %d MB and install image %s? [Y/n] ", need>>20, idx.Version)
		line, _ := bufio.NewReader(os.Stdin).ReadString('\n')
		if s := strings.TrimSpace(strings.ToLower(line)); s != "" && s[0] != 'y' {
			printInfo("aborting.")
			return 1
		}
	}

	part := filepath.Join(dataBoot, "images", idx.Version+".part")
	final := filepath.Join(dataBoot, "images", idx.Version)
	if err := os.MkdirAll(part, 0o755); err != nil {
		printErr("cannot create %s: %v", part, err)
		return 1
	}
	for _, f := range idx.Files {
		if f.Name == "" || strings.ContainsAny(f.Name, "/\\") || strings.HasPrefix(f.Name, ".") {
			printErr("refusing suspicious file name %q in the index", f.Name)
			return 1
		}
		dest := filepath.Join(part, f.Name)
		printInfo("downloading %s", f.Name)
		if err := downloadResumable(f.URL, dest, f.Size); err != nil {
			printErr("download of %s failed: %v (run the command again to resume)", f.Name, err)
			return 1
		}
		sum, err := fileSHA256(dest)
		if err != nil || !strings.EqualFold(sum, f.SHA256) {
			os.Remove(dest)
			printErr("checksum of %s does not match the signed index; deleted it (run the command again)", f.Name)
			return 1
		}
	}
	os.RemoveAll(final)
	if err := os.Rename(part, final); err != nil {
		printErr("cannot install the image: %v", err)
		return 1
	}

	uuid := strings.TrimPrefix(cmdlineValue("systeml.data="), "UUID=")
	if uuid == "" {
		printErr("cannot tell which disk holds the images (no systeml.data= on the kernel command line)")
		return 1
	}
	if rc := runCommand("", []string{"systemlinux-grubcfg", dataBoot, uuid}); rc != 0 {
		printErr("could not update GRUB's menu")
		return 1
	}
	if rc := runCommand("", []string{"grub-reboot", "--boot-directory=" + dataBoot, idx.Version}); rc != 0 {
		printErr("could not schedule the new image for the next boot")
		return 1
	}

	// keep the running image and the new one; drop older ones to save space
	for _, v := range installedVersions() {
		if v != idx.Version && v != current {
			printInfo("removing old image %s", v)
			os.RemoveAll(filepath.Join(dataBoot, "images", v))
		}
	}
	runCommand("", []string{"systemlinux-grubcfg", dataBoot, uuid})

	printOK("image %s is installed. Reboot to start it.", idx.Version)
	printInfo("it boots once as a trial: if it does not come up, the next boot returns to %s automatically.", current)
	return 0
}
