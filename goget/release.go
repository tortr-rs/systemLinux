package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

type releaseAsset struct {
	Name string `json:"name"`
	URL  string `json:"browser_download_url"`
}

type githubReleaseFull struct {
	Assets []releaseAsset `json:"assets"`
}

var otherOSTokens = []string{
	"darwin", "macos", "osx", "apple", "ios", "windows",
	"win32", "win64", "freebsd", "openbsd", "netbsd", "dragonfly",
	"solaris", "illumos", "aix", "wasm", "wasi", "android",
	"haiku", "redox", "serenity", "plan9", "hpux", "irix",
	"sunos", "minix", "hurd",
}

// looksLikeOtherOS is necessarily a blocklist (every possible Linux
// asset name can't be enumerated up front), so an unrecognized OS name
// could slip through -- but that's caught later regardless:
// binaryLibcKind rejects anything that isn't a valid Linux ELF as
// libcUnknown, which binaryIsCompatible treats as incompatible. This
// filter just avoids wasting a download on the obvious cases.
func looksLikeOtherOS(name string) bool {
	for _, tok := range otherOSTokens {
		if strCIContains(name, tok) {
			return true
		}
	}
	return strEndsWith(name, ".exe") || strEndsWith(name, ".msi") ||
		strEndsWith(name, ".dmg") || strEndsWith(name, ".app")
}

func looksLikePackageFormat(name string) bool {
	return strEndsWith(name, ".deb") || strEndsWith(name, ".rpm") ||
		strEndsWith(name, ".pkg") || strEndsWith(name, ".apk")
}

func isArchiveName(name string) bool {
	for _, suf := range []string{".tar.gz", ".tgz", ".tar.xz", ".txz", ".tar.bz2", ".tbz2", ".zip"} {
		if strEndsWith(name, suf) {
			return true
		}
	}
	return false
}

// pickBinaryInDir recursively searches root for the binary to install,
// per priority order: a same-named file under a bin/ path, then a
// same-named file with the executable bit set, then any same-named
// file (handles archives with multiple files sharing a name, e.g. a
// binary and a same-named bash-completion script). If nothing shares
// the repo's name, falls back to the sole executable regular file in
// the tree, if there's exactly one.
func pickBinaryInDir(root, wantedName string) string {
	var binMatch, execMatch, anyMatch, loneExec string
	execCount := 0

	filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() {
			return nil
		}
		isWanted := info.Name() == wantedName
		isExec := info.Mode()&0111 != 0

		if isWanted {
			if binMatch == "" && pathContainsBinSegment(path) {
				binMatch = path
			}
			if execMatch == "" && isExec {
				execMatch = path
			}
			if anyMatch == "" {
				anyMatch = path
			}
		}
		if isExec {
			execCount++
			if execCount == 1 {
				loneExec = path
			} else {
				loneExec = ""
			}
		}
		return nil
	})

	switch {
	case binMatch != "":
		return binMatch
	case execMatch != "":
		return execMatch
	case anyMatch != "":
		return anyMatch
	case execCount == 1:
		return loneExec
	default:
		return ""
	}
}

func pathContainsBinSegment(path string) bool {
	return strings.Contains(path, string(filepath.Separator)+"bin"+string(filepath.Separator))
}

type tryResult int

const (
	trySuccess tryResult = iota
	trySkip
	tryHardFail
)

// tryAsset downloads, extracts (if needed), picks a binary out of, and
// compat-checks one candidate asset. On trySuccess, returns the binary
// path and the temp workdir the caller must remove after installing
// from it. Any other outcome cleans up after itself.
func tryAsset(assets []releaseAsset, idx int, shortName string) (binaryPath, workdir string, result tryResult) {
	a := assets[idx]

	workdir, err := os.MkdirTemp("", "goget-fetch-*")
	if err != nil {
		fmt.Fprintf(os.Stderr, "goget: mkdtemp: %v\n", err)
		return "", "", trySkip
	}

	downloadPath := filepath.Join(workdir, a.Name)
	printInfo("downloading %s...", a.Name)
	if err := httpDownload(a.URL, downloadPath); err != nil {
		os.RemoveAll(workdir)
		return "", "", trySkip
	}

	if isArchiveName(a.Name) {
		extractDir := filepath.Join(workdir, "extracted")
		mkdirP(extractDir)
		if err := extractArchive(downloadPath, extractDir); err != nil {
			printErr("failed to extract %s", a.Name)
			os.RemoveAll(workdir)
			return "", "", trySkip
		}
		picked := pickBinaryInDir(extractDir, shortName)
		if picked == "" {
			printErr("could not find a '%s' binary inside %s", shortName, a.Name)
			os.RemoveAll(workdir)
			return "", "", trySkip
		}
		binaryPath = picked
	} else {
		binaryPath = downloadPath
	}

	if !binaryIsCompatible(binaryPath, a.Name) {
		printWarn("%s is not compatible with this host, skipping", a.Name)
		os.RemoveAll(workdir)
		return "", "", trySkip
	}

	cands := make([]checksumCandidate, len(assets))
	for i, as := range assets {
		cands[i] = checksumCandidate{name: as.Name, url: as.URL}
	}
	switch checksumVerify(cands, a.Name, binaryPath) {
	case checksumMismatch:
		printErr("checksum verification FAILED for %s -- aborting.", a.Name)
		os.RemoveAll(workdir)
		return "", "", tryHardFail
	case checksumMissing:
		printWarn("no checksum file found for %s; continuing without verification", a.Name)
	default:
		printOK("checksum verified OK for %s", a.Name)
	}

	return binaryPath, workdir, trySuccess
}

// releaseFetchAndInstall tries every plausible Linux release asset
// (matching this host's architecture first, then arch-unnamed assets)
// until one passes the compatibility check, then verifies its checksum
// if a manifest is present, then installs it.
//
// Returns:
//
//	 0  success
//	 1  no compatible release found -- caller should offer the
//	    "must build from source" fallback prompt
//	-1  hard failure (checksum mismatch, network/API error, install
//	    step failed) -- caller should abort, not fall back silently
func releaseFetchAndInstall(owner, repo, shortName string) int {
	apiURL := fmt.Sprintf("https://api.github.com/repos/%s/%s/releases/latest", owner, repo)
	body, status := httpGet(apiURL, []string{"Accept: application/vnd.github+json"})

	if status == 0 {
		printErr("network error contacting the GitHub releases API")
		return -1
	}
	if status == 404 {
		return 1
	}
	if status < 200 || status >= 300 {
		printErr("GitHub releases API returned HTTP %d for %s/%s", status, owner, repo)
		return -1
	}

	var rel githubReleaseFull
	if err := json.Unmarshal([]byte(body), &rel); err != nil {
		printErr("could not parse GitHub releases response")
		return -1
	}
	if len(rel.Assets) == 0 {
		return 1
	}

	return pickAndInstallAsset(rel.Assets, shortName)
}

// pickAndInstallAsset tries every plausible Linux asset in assets
// (matching this host's architecture first, then arch-unnamed assets)
// until one passes the compatibility check, then verifies its checksum
// if a manifest is present among assets, then installs it to
// /usr/local/bin/<shortName>. Shared by releaseFetchAndInstall (GitHub
// Releases) and binRepoInstall (goget's own package repo) -- the two
// asset sources differ only in how the []releaseAsset list is obtained.
//
// Return convention matches releaseFetchAndInstall: 0 success, 1 no
// compatible asset found, -1 hard failure.
func pickAndInstallAsset(assets []releaseAsset, shortName string) int {
	host := hostArch()
	var order []int
	for i, a := range assets {
		if checksumIsChecksumFilename(a.Name) || looksLikeOtherOS(a.Name) || looksLikePackageFormat(a.Name) {
			continue
		}
		if archFromAssetName(a.Name) == host {
			order = append(order, i)
		}
	}
	for i, a := range assets {
		if checksumIsChecksumFilename(a.Name) || looksLikeOtherOS(a.Name) || looksLikePackageFormat(a.Name) {
			continue
		}
		if archFromAssetName(a.Name) == archUnknown {
			order = append(order, i)
		}
	}

	for _, idx := range order {
		binaryPath, workdir, rc := tryAsset(assets, idx, shortName)
		switch rc {
		case tryHardFail:
			return -1
		case trySuccess:
			dest := filepath.Join("/usr/local/bin", shortName)
			printInfo("installing to %s (sudo install)...", dest)
			installRC := runCommand("", []string{"sudo", "install", "-Dm755", binaryPath, dest})
			os.RemoveAll(workdir)
			if installRC == 0 {
				return 0
			}
			printErr("install step failed")
			return -1
		}
		// trySkip: loop continues to the next candidate.
	}

	return 1
}
