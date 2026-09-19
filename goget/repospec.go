package main

import "strings"

type repospecKind int

const (
	repospecFull repospecKind = iota
	repospecBareName
)

type repospec struct {
	kind  repospecKind
	host  string // "" if kind == repospecBareName
	owner string // "" if kind == repospecBareName
	repo  string // always set; ".git" suffix stripped
}

func stripGitSuffix(repo string) string {
	return strings.TrimSuffix(repo, ".git")
}

func containsDot(s string) bool {
	return strings.Contains(s, ".")
}

// parseRepospec parses one of:
//   - full URL:              https://github.com/owner/repo(.git)?
//   - ssh spec:               git@github.com:owner/repo.git  or  ssh://git@host/owner/repo
//   - bare host/owner/repo:   github.com/owner/repo
//   - bare owner/repo (no host): assumed to be github.com (documented assumption)
//   - bare short name:        fastfetch  ->  repospecBareName, needs search
//
// Returns nil on malformed input (empty string, embedded whitespace, etc).
func parseRepospec(input string) *repospec {
	s := strings.TrimSpace(input)
	if s == "" {
		return nil
	}
	for _, r := range s {
		if r == ' ' || r == '\t' || r == '\n' || r == '\r' || r == '\v' || r == '\f' {
			return nil
		}
	}

	rest := s
	switch {
	case strings.HasPrefix(s, "https://"):
		rest = s[len("https://"):]
	case strings.HasPrefix(s, "http://"):
		rest = s[len("http://"):]
	case strings.HasPrefix(s, "ssh://"):
		rest = s[len("ssh://"):]
	case strings.HasPrefix(s, "git://"):
		rest = s[len("git://"):]
	}
	hadScheme := rest != s

	rest = strings.TrimRight(rest, "/")
	if rest == "" {
		return nil
	}

	// Detect scp-like ssh syntax: user@host:path (only meaningful when no
	// scheme was already stripped, since ssh:// URLs use user@host/path).
	isScpForm := false
	if at := strings.Index(rest, "@"); at >= 0 {
		afterAt := rest[at+1:]
		slashAfterAt := strings.Index(afterAt, "/")
		colonAfterAt := strings.Index(afterAt, ":")
		if !hadScheme && colonAfterAt >= 0 && (slashAfterAt < 0 || colonAfterAt < slashAfterAt) {
			isScpForm = true
		}
		rest = afterAt // skip "user@" either way
	}

	var host, pathStart string

	if isScpForm {
		colon := strings.Index(rest, ":")
		if colon < 0 {
			return nil
		}
		host = strings.ToLower(rest[:colon])
		pathStart = rest[colon+1:]
	} else {
		slash := strings.Index(rest, "/")
		if slash < 0 {
			// No '/' anywhere: only a bare short name if there was no
			// scheme/user@ involved (a URL with no path is malformed).
			if rest != s {
				return nil
			}
			repo := stripGitSuffix(rest)
			if repo == "" {
				return nil
			}
			return &repospec{kind: repospecBareName, repo: repo}
		}

		if rest != s {
			// Came from a URL scheme (or ssh://user@host/...): the segment
			// up to the first '/' is unambiguously the host.
			host = strings.ToLower(rest[:slash])
			pathStart = rest[slash+1:]
		} else {
			// Bare form with no scheme: "X/Y" or "X/Y/Z...". Heuristic: if
			// the first segment looks like a domain (contains a '.'),
			// treat it as host/owner/repo; otherwise assume it's a bare
			// "owner/repo" with no host and default to github.com. This is
			// a documented assumption, not part of the original spec,
			// which only calls out host/owner/repo and bare short names.
			firstSeg := rest[:slash]
			if containsDot(firstSeg) {
				host = strings.ToLower(firstSeg)
				pathStart = rest[slash+1:]
			} else {
				host = "github.com"
				pathStart = rest
			}
		}
	}

	if pathStart == "" {
		return nil
	}

	lastSlash := strings.LastIndex(pathStart, "/")
	if lastSlash < 0 {
		// Host is known but only one path segment given: not enough to
		// determine both owner and repo.
		return nil
	}

	owner := pathStart[:lastSlash]
	repo := stripGitSuffix(pathStart[lastSlash+1:])
	if owner == "" || repo == "" {
		return nil
	}

	return &repospec{kind: repospecFull, host: host, owner: owner, repo: repo}
}
