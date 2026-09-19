package main

import (
	"encoding/json"
	"net/url"
	"strings"
)

// AUR packages are a flat namespace (no owner) hosted as individual git
// repos at aur.archlinux.org/<name>.git -- resolved specs use
// host="aur.archlinux.org", owner="aur" (a placeholder; AUR has no real
// owner concept), repo=<package name>.
const aurHost = "aur.archlinux.org"

type aurSearchResponse struct {
	Results []struct {
		Name     string `json:"Name"`
		NumVotes int64  `json:"NumVotes"`
	} `json:"results"`
}

func fetchAURSearch(name string) []searchResult {
	u := "https://aur.archlinux.org/rpc/v5/search/" + url.QueryEscape(name)
	body, status := httpGet(u, nil)
	if status < 200 || status >= 300 {
		return nil
	}

	var resp aurSearchResponse
	if err := json.Unmarshal([]byte(body), &resp); err != nil {
		return nil
	}

	var out []searchResult
	for _, item := range resp.Results {
		if !strings.EqualFold(item.Name, name) {
			continue
		}
		out = append(out, searchResult{host: aurHost, owner: "aur", repo: item.Name, stars: item.NumVotes})
	}
	return out
}

// aurCloneURL returns the git clone URL for an AUR package. AUR ignores
// any owner field -- every package is a top-level git repo by name.
func aurCloneURL(repo string) string {
	return "https://aur.archlinux.org/" + repo + ".git"
}
