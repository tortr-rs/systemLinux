package main

import (
	"encoding/json"
	"fmt"
	"net/url"
	"sort"
	"strings"
)

type searchResult struct {
	host, owner, repo string
	stars             int64
}

func sortAndCap(results []searchResult, cap int) []searchResult {
	sort.Slice(results, func(i, j int) bool { return results[i].stars > results[j].stars })
	if len(results) > cap {
		results = results[:cap]
	}
	return results
}

type githubSearchResponse struct {
	Items []struct {
		Name  string `json:"name"`
		Owner struct {
			Login string `json:"login"`
		} `json:"owner"`
		Stars int64 `json:"stargazers_count"`
	} `json:"items"`
}

func fetchGithubSearch(name string) []searchResult {
	query := fmt.Sprintf("\"%s\" in:name", name)
	u := "https://api.github.com/search/repositories?q=" + url.QueryEscape(query) + "&sort=stars&order=desc"
	body, status := httpGet(u, []string{"Accept: application/vnd.github+json"})
	if status < 200 || status >= 300 {
		return nil
	}

	var resp githubSearchResponse
	if err := json.Unmarshal([]byte(body), &resp); err != nil {
		return nil
	}

	var out []searchResult
	for _, item := range resp.Items {
		if !strings.EqualFold(item.Name, name) {
			continue
		}
		out = append(out, searchResult{host: "github.com", owner: item.Owner.Login, repo: item.Name, stars: item.Stars})
	}
	return out
}

type gitlabSearchResult struct {
	Path      string `json:"path"`
	Stars     int64  `json:"star_count"`
	Namespace struct {
		FullPath string `json:"full_path"`
	} `json:"namespace"`
}

func fetchGitlabSearch(name string) []searchResult {
	u := "https://gitlab.com/api/v4/projects?search=" + url.QueryEscape(name) + "&order_by=star_count&sort=desc&per_page=20"
	body, status := httpGet(u, nil)
	if status < 200 || status >= 300 {
		return nil
	}

	var items []gitlabSearchResult
	if err := json.Unmarshal([]byte(body), &items); err != nil {
		return nil
	}

	var out []searchResult
	for _, item := range items {
		if !strings.EqualFold(item.Path, name) {
			continue
		}
		out = append(out, searchResult{host: "gitlab.com", owner: item.Namespace.FullPath, repo: item.Path, stars: item.Stars})
	}
	return out
}

type codebergSearchResponse struct {
	Data []struct {
		Name  string `json:"name"`
		Stars int64  `json:"stars_count"`
		Owner struct {
			Login string `json:"login"`
		} `json:"owner"`
	} `json:"data"`
}

func fetchCodebergSearch(name string) []searchResult {
	u := "https://codeberg.org/api/v1/repos/search?q=" + url.QueryEscape(name) + "&limit=20"
	body, status := httpGet(u, nil)
	if status < 200 || status >= 300 {
		return nil
	}

	var resp codebergSearchResponse
	if err := json.Unmarshal([]byte(body), &resp); err != nil {
		return nil
	}

	var out []searchResult
	for _, item := range resp.Data {
		if !strings.EqualFold(item.Name, name) {
			continue
		}
		out = append(out, searchResult{host: "codeberg.org", owner: item.Owner.Login, repo: item.Name, stars: item.Stars})
	}
	return out
}

// searchByName searches GitHub, GitLab, Codeberg, and AUR (skipping any
// disabled in cfg) for packages whose name exactly matches name,
// case-insensitively. Results are capped at 3 per host, sorted by stars
// (or AUR votes) descending within each host, and ordered github ->
// gitlab -> codeberg -> aur overall. A network/API error on one host
// yields zero results for that host rather than aborting the whole
// search.
func searchByName(cfg *gogetConfig, name string) []searchResult {
	var combined []searchResult
	if configHostEnabled(cfg, "github.com") {
		combined = append(combined, sortAndCap(fetchGithubSearch(name), 3)...)
	}
	if configHostEnabled(cfg, "gitlab.com") {
		combined = append(combined, sortAndCap(fetchGitlabSearch(name), 3)...)
	}
	if configHostEnabled(cfg, "codeberg.org") {
		combined = append(combined, sortAndCap(fetchCodebergSearch(name), 3)...)
	}
	if configHostEnabled(cfg, aurHost) {
		combined = append(combined, sortAndCap(fetchAURSearch(name), 3)...)
	}
	if configHostEnabled(cfg, gentooHost) {
		combined = append(combined, fetchGentooSearch(name)...)
	}
	return combined
}
