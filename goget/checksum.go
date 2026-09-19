package main

import (
	"crypto/sha256"
	"encoding/hex"
	"io"
	"os"
	"strings"
)

type checksumResult int

const (
	checksumOK        checksumResult = iota // a checksum file was found and it matched
	checksumMismatch                        // a checksum file was found but did NOT match -- hard fail
	checksumMissing                         // no checksum file found (or no entry for this asset) -- warn and continue
)

type checksumCandidate struct {
	name string
	url  string
}

// checksumIsChecksumFilename reports whether name looks like a checksum
// manifest (*.sha256, *.sha256sum, or containing "checksums"/"sha256sums").
func checksumIsChecksumFilename(name string) bool {
	if strEndsWith(name, ".sha256") || strEndsWith(name, ".sha256sum") {
		return true
	}
	return strCIContains(name, "checksums") || strCIContains(name, "sha256sums")
}

// findExpectedHash parses a checksum manifest looking for assetName's
// entry. Handles both the multi-entry "<hash>  <filename>" format
// (checksums.txt/SHA256SUMS, one line per released file, filename
// possibly prefixed with '*' for sha256sum's binary mode) and the
// single-entry "<hash>" format some projects use for a per-asset
// "<assetname>.sha256" file.
func findExpectedHash(content, assetName string) string {
	var matched, singleToken string
	lineCount := 0
	multiTokenLineSeen := false

	for _, line := range strings.Split(content, "\n") {
		l := strings.TrimSpace(line)
		if l == "" {
			continue
		}
		lineCount++

		fields := strings.Fields(l)
		hash := fields[0]
		if len(fields) > 1 {
			multiTokenLineSeen = true
			fname := fields[1]
			fname = strings.TrimPrefix(fname, "*")
			base := fname
			if idx := strings.LastIndex(fname, "/"); idx >= 0 {
				base = fname[idx+1:]
			}
			if base == assetName && matched == "" {
				matched = hash
			}
		} else if singleToken == "" {
			singleToken = hash
		}
	}

	if matched != "" {
		return matched
	}
	if !multiTokenLineSeen && lineCount == 1 && singleToken != "" {
		return singleToken
	}
	return ""
}

func sha256Hex(path string) (string, error) {
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

// checksumVerify looks for a checksum-style asset among candidates,
// downloads it, finds the entry for assetName within it (or, for a
// single-hash-only file, takes it unconditionally), and compares
// against the actual sha256 of the local file at localPath.
func checksumVerify(candidates []checksumCandidate, assetName, localPath string) checksumResult {
	var found *checksumCandidate
	for i := range candidates {
		if checksumIsChecksumFilename(candidates[i].name) {
			found = &candidates[i]
			break
		}
	}
	if found == nil {
		return checksumMissing
	}

	content, status := httpGet(found.url, nil)
	if status < 200 || status >= 300 || content == "" {
		return checksumMissing
	}

	expected := findExpectedHash(content, assetName)
	if expected == "" {
		return checksumMissing
	}

	actual, err := sha256Hex(localPath)
	if err != nil {
		return checksumMissing
	}

	if strings.EqualFold(expected, actual) {
		return checksumOK
	}
	return checksumMismatch
}
