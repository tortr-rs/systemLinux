package main

import (
	"encoding/json"
	"strings"
)

// binRepoAsset is one downloadable file in a goget repo index entry.
// This is goget's own wire format (unlike releaseAsset, which mirrors
// GitHub's API field names) -- kept as a distinct type so the index
// format reads sensibly on its own, converted to []releaseAsset
// in-process so pickAndInstallAsset/tryAsset/checksumVerify/
// pickBinaryInDir all work unmodified against either source.
type binRepoAsset struct {
	Name string `json:"name"`
	URL  string `json:"url"`
}

type binRepoPackageEntry struct {
	Version string         `json:"version"`
	Assets  []binRepoAsset `json:"assets"`
}

type binRepoIndex struct {
	Packages map[string]binRepoPackageEntry `json:"packages"`
}

func (e binRepoPackageEntry) releaseAssets() []releaseAsset {
	assets := make([]releaseAsset, len(e.Assets))
	for i, a := range e.Assets {
		assets[i] = releaseAsset{Name: a.Name, URL: a.URL}
	}
	return assets
}

// binRepoLookup checks the configured goget package repo (pkg.binrepo{}
// in goget.conf) for a prebuilt entry matching shortName.
//
// Returns ok=false if the repo isn't configured (no url set, or
// enabled.off), unreachable, or simply doesn't have this package --
// all three are treated identically: the caller falls back to today's
// GitHub-based build silently, since "not found" and "no repo
// configured yet" should feel the same to the user until the repo
// actually exists.
func binRepoLookup(cfg *gogetConfig, shortName string) (binRepoPackageEntry, bool) {
	if cfg.binRepoURL == "" || !cfg.binRepoEnabled {
		return binRepoPackageEntry{}, false
	}

	indexURL := strings.TrimRight(cfg.binRepoURL, "/") + "/index.json"
	body, status := httpGet(indexURL, nil)
	if status < 200 || status >= 300 {
		return binRepoPackageEntry{}, false
	}

	var idx binRepoIndex
	if err := json.Unmarshal([]byte(body), &idx); err != nil {
		return binRepoPackageEntry{}, false
	}

	entry, ok := idx.Packages[shortName]
	if !ok || len(entry.Assets) == 0 {
		return binRepoPackageEntry{}, false
	}
	return entry, true
}

// binRepoInstall picks the best-matching asset from entry (same
// architecture/compat/checksum logic as a GitHub release) and installs
// it to /usr/local/bin/<shortName>. Same return convention as
// releaseFetchAndInstall.
func binRepoInstall(entry binRepoPackageEntry, shortName string) int {
	return pickAndInstallAsset(entry.releaseAssets(), shortName)
}
