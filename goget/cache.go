package main

import "path/filepath"

// cacheRepoDir returns $HOME/.cache/goget/src/<host>/<owner>/<repo> for a
// fully-resolved repo spec. Does not create the directory.
func cacheRepoDir(spec *repospec) string {
	return filepath.Join(homeDir(), ".cache/goget/src", spec.host, spec.owner, spec.repo)
}

// cacheRepoVersionDir returns the cache directory for one tagged-release
// source tree: $HOME/.cache/goget/src/<host>/<owner>/<repo>@<tag>.
// Deliberately a SIBLING of cacheRepoDir's plain <repo> directory (not
// nested inside it): that one is a git working tree, and `git clone`
// refuses to clone into a non-empty directory, so a tarball extraction
// living inside it would break a later git-based build of the same repo.
func cacheRepoVersionDir(spec *repospec, tag string) string {
	return filepath.Join(homeDir(), ".cache/goget/src", spec.host, spec.owner, spec.repo+"@"+tag)
}
