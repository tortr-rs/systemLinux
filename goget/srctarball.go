package main

import (
	"encoding/json"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
)

type srctarballResult int

const (
	srctarballOK       srctarballResult = iota // dir/tag are set
	srctarballFallback                          // no tagged release, or the tarball path failed for
	// some other reason -- caller should fall back to gitSync unconditionally.
)

type githubRelease struct {
	TagName    string `json:"tag_name"`
	TarballURL string `json:"tarball_url"`
}

type giteaRelease struct { // codeberg
	TagName    string `json:"tag_name"`
	TarballURL string `json:"tarball_url"`
}

type gitlabRelease struct {
	TagName string `json:"tag_name"`
	Assets  struct {
		Sources []struct {
			Format string `json:"format"`
			URL    string `json:"url"`
		} `json:"sources"`
	} `json:"assets"`
}

// resolveLatestTag resolves spec's latest tagged release to a tag name
// and a ready-to-download source-archive (.tar.gz) URL, using each
// host's own release API:
//
//   - github.com and codeberg.org (Gitea) release objects both carry a
//     "tarball_url" field directly, so no URL construction is needed.
//   - gitlab.com release objects instead list downloadable archives
//     under assets.sources[]; the one with format "tar.gz" is picked.
//
// Returns ("", "", true) if the repo genuinely has no releases (normal,
// caller falls back to git silently), or ("", "", false) with ok=false
// on a network/API/parse error (also falls back to git, but worth a
// warning).
func resolveLatestTag(spec *repospec) (tag, tarballURL string, noRelease bool, ok bool) {
	switch spec.host {
	case "github.com":
		apiURL := fmt.Sprintf("https://api.github.com/repos/%s/%s/releases/latest", spec.owner, spec.repo)
		body, status := httpGet(apiURL, []string{"Accept: application/vnd.github+json"})
		if status == 404 {
			return "", "", true, true
		}
		if status < 200 || status >= 300 {
			return "", "", false, false
		}
		var rel githubRelease
		if err := json.Unmarshal([]byte(body), &rel); err != nil || rel.TagName == "" || rel.TarballURL == "" {
			return "", "", false, false
		}
		return rel.TagName, rel.TarballURL, false, true

	case "codeberg.org":
		apiURL := fmt.Sprintf("https://codeberg.org/api/v1/repos/%s/%s/releases/latest", spec.owner, spec.repo)
		body, status := httpGet(apiURL, nil)
		if status == 404 {
			return "", "", true, true
		}
		if status < 200 || status >= 300 {
			return "", "", false, false
		}
		var rel giteaRelease
		if err := json.Unmarshal([]byte(body), &rel); err != nil || rel.TagName == "" || rel.TarballURL == "" {
			return "", "", false, false
		}
		return rel.TagName, rel.TarballURL, false, true

	case "gitlab.com":
		encoded := url.QueryEscape(spec.owner + "/" + spec.repo)
		apiURL := fmt.Sprintf("https://gitlab.com/api/v4/projects/%s/releases?per_page=1", encoded)
		body, status := httpGet(apiURL, nil)
		if status < 200 || status >= 300 {
			return "", "", false, false
		}
		var rels []gitlabRelease
		if err := json.Unmarshal([]byte(body), &rels); err != nil {
			return "", "", false, false
		}
		if len(rels) == 0 {
			return "", "", true, true
		}
		for _, src := range rels[0].Assets.Sources {
			if src.Format == "tar.gz" {
				return rels[0].TagName, src.URL, false, true
			}
		}
		return "", "", false, false

	default:
		// Unrecognized host: no tarball path, git is the only option.
		return "", "", true, true
	}
}

// stripWrapperDir returns dir's single inner directory if that's the
// only entry present (the norm for github/gitlab/codeberg source
// archives, which wrap everything in a single "<repo>-<tag>/"
// directory); otherwise returns dir itself unchanged.
func stripWrapperDir(dir string) string {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return dir
	}
	var onlyDir string
	otherEntries := 0
	for _, e := range entries {
		if e.IsDir() && onlyDir == "" {
			onlyDir = filepath.Join(dir, e.Name())
		} else {
			otherEntries++
		}
	}
	if onlyDir != "" && otherEntries == 0 {
		return onlyDir
	}
	return dir
}

// srctarballFetch attempts to obtain the source tree for spec's latest
// tagged release via a plain HTTP download of the host's source archive
// for that tag, instead of a full `git clone` -- avoids pulling entire
// project history just to build one released version. Cached under
// cacheRepoVersionDir, keyed by tag, so re-requesting the same tag is a
// no-op.
func srctarballFetch(spec *repospec) (dir, tag string, result srctarballResult) {
	tag, tarURL, noRelease, ok := resolveLatestTag(spec)
	if noRelease {
		return "", "", srctarballFallback
	}
	if !ok {
		printWarn("could not check %s for a tagged release; falling back to git", spec.repo)
		return "", "", srctarballFallback
	}

	versionDir := cacheRepoVersionDir(spec, tag)
	marker := versionDir + ".complete"

	if pathExists(marker) {
		return stripWrapperDir(versionDir), tag, srctarballOK
	}

	if err := mkdirP(versionDir); err != nil {
		printWarn("could not create cache directory for %s@%s; falling back to git", spec.repo, tag)
		return "", "", srctarballFallback
	}

	archivePath := filepath.Join(versionDir, "source.tar.gz")
	printInfo("downloading source archive for %s %s...", spec.repo, tag)
	if err := httpDownload(tarURL, archivePath); err != nil {
		printWarn("source archive download failed; falling back to git")
		return "", "", srctarballFallback
	}

	if err := extractArchive(archivePath, versionDir); err != nil {
		printWarn("could not extract source archive; falling back to git")
		return "", "", srctarballFallback
	}
	os.Remove(archivePath)

	f, err := os.Create(marker)
	if err == nil {
		f.Close()
	}

	return stripWrapperDir(versionDir), tag, srctarballOK
}
