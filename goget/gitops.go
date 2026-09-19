package main

import (
	"fmt"
	"os"
	"path/filepath"
)

// gitCloneURL returns an https clone URL for a fully-resolved spec.
// goget always clones over https (even if the original spec was an
// ssh:// or git@ URL) since it has no SSH key/agent setup step of its
// own and https works for any public repo with no auth required.
//
// AUR is a special case: every package is a top-level git repo with no
// owner segment (aur.archlinux.org/<name>.git), unlike the
// host/owner/repo shape every other supported host uses.
func gitCloneURL(spec *repospec) string {
	if spec.host == aurHost {
		return aurCloneURL(spec.repo)
	}
	return fmt.Sprintf("https://%s/%s/%s.git", spec.host, spec.owner, spec.repo)
}

// gitSync clones destDir fresh if it doesn't already exist (creating
// parent directories as needed), or runs a fast-forward-only pull if
// it's already a git checkout. git's own noisy line-by-line output is
// hidden behind a spinner (runCommandSpinner falls back to plain
// passthrough on its own whenever stdout isn't a real terminal).
func gitSync(cloneURL, destDir string) int {
	if pathIsDir(filepath.Join(destDir, ".git")) {
		rc := runCommandSpinner(destDir, []string{"git", "pull", "--ff-only"}, "updating cached checkout...", false)
		if rc == 0 {
			printOK("updated cached checkout at %s", destDir)
		}
		return rc
	}

	if err := mkdirP(filepath.Dir(destDir)); err != nil {
		fmt.Fprintf(os.Stderr, "goget: could not create cache directory: %v\n", err)
		return -1
	}

	rc := runCommandSpinner("", []string{"git", "clone", cloneURL, destDir}, fmt.Sprintf("cloning %s...", cloneURL), false)
	if rc == 0 {
		printOK("cloned into %s", destDir)
	}
	return rc
}
