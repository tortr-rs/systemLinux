package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
)

type showContent struct {
	readme           string
	buildScript      string
	buildScriptLabel string
}

func getDefaultBranch(host, owner, repo string) string {
	var u string
	switch host {
	case "github.com":
		u = fmt.Sprintf("https://api.github.com/repos/%s/%s", owner, repo)
	case "gitlab.com":
		u = "https://gitlab.com/api/v4/projects/" + urlEncodeSlashes(owner+"/"+repo)
	case "codeberg.org":
		u = fmt.Sprintf("https://codeberg.org/api/v1/repos/%s/%s", owner, repo)
	default:
		return ""
	}
	body, status := httpGet(u, nil)
	if status < 200 || status >= 300 {
		return ""
	}
	return jsonStringField(body, "default_branch")
}

func urlEncodeSlashes(s string) string {
	return strings.ReplaceAll(s, "/", "%2F")
}

func buildRawURL(host, owner, repo, branch, path string) string {
	switch host {
	case "github.com":
		return fmt.Sprintf("https://raw.githubusercontent.com/%s/%s/%s/%s", owner, repo, branch, path)
	case "gitlab.com":
		return fmt.Sprintf("https://gitlab.com/%s/%s/-/raw/%s/%s", owner, repo, branch, path)
	case "codeberg.org":
		return fmt.Sprintf("https://codeberg.org/%s/%s/raw/branch/%s/%s", owner, repo, branch, path)
	default:
		return ""
	}
}

func tryFetchRaw(host, owner, repo, branch, path string) string {
	body, status := httpGet(buildRawURL(host, owner, repo, branch, path), nil)
	if status < 200 || status >= 300 {
		return ""
	}
	return body
}

// showFetch fetches just the README and a recognized build-system
// marker file for a fully-resolved repo, via each host's raw-file API
// -- no clone, and nothing touches goget's cache. Only github.com,
// gitlab.com, and codeberg.org are supported.
//
// Returns 0 on success (individual fields may still be empty), 1 if
// host isn't one of the three supported hosts, -1 on a hard
// network/API error.
func showFetch(host, owner, repo string) (*showContent, int) {
	if host != "github.com" && host != "gitlab.com" && host != "codeberg.org" {
		return nil, 1
	}

	branch := getDefaultBranch(host, owner, repo)
	if branch == "" {
		fmt.Fprintf(os.Stderr, "goget: could not determine default branch for %s/%s on %s\n", owner, repo, host)
		return nil, -1
	}

	content := &showContent{}
	for _, cand := range []string{"README.md", "README", "README.rst", "README.txt"} {
		if content.readme = tryFetchRaw(host, owner, repo, branch, cand); content.readme != "" {
			break
		}
	}

	// Same priority order as buildsysDetect.
	for _, cand := range []string{"CMakeLists.txt", "configure", "Makefile"} {
		if content.buildScript = tryFetchRaw(host, owner, repo, branch, cand); content.buildScript != "" {
			content.buildScriptLabel = cand
			break
		}
	}

	return content, 0
}

// showPage pipes text through $PAGER (falling back to "less").
func showPage(text string) {
	pager := os.Getenv("PAGER")
	if pager == "" {
		pager = "less"
	}
	cmd := exec.Command(pager)
	cmd.Stdin = strings.NewReader(text)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		fmt.Print(text)
	}
}
