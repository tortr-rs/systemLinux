package main

import (
	"encoding/json"
	"os"
	"strings"
)

// jsonStringField extracts one top-level string field from a JSON
// object body, or "" if it's absent, not a string, or the body doesn't
// parse.
func jsonStringField(body, field string) string {
	var m map[string]json.RawMessage
	if err := json.Unmarshal([]byte(body), &m); err != nil {
		return ""
	}
	raw, ok := m[field]
	if !ok {
		return ""
	}
	var s string
	if err := json.Unmarshal(raw, &s); err != nil {
		return ""
	}
	return s
}

func strEndsWith(s, suffix string) bool { return strings.HasSuffix(s, suffix) }
func strStartsWith(s, prefix string) bool { return strings.HasPrefix(s, prefix) }

func strCIContains(haystack, needle string) bool {
	return strings.Contains(strings.ToLower(haystack), strings.ToLower(needle))
}

// mkdirP creates path and all missing parents with mode 0755.
func mkdirP(path string) error {
	return os.MkdirAll(path, 0755)
}

func pathExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func pathIsDir(path string) bool {
	fi, err := os.Stat(path)
	return err == nil && fi.IsDir()
}

// pathIsExecutableFile reports whether path is a regular file with any
// executable bit set (matches path_is_executable_file's access(X_OK)
// check closely enough for goget's own use: detecting a repo's own
// `configure` script, which is always meant to be run by its owner).
func pathIsExecutableFile(path string) bool {
	fi, err := os.Stat(path)
	if err != nil || !fi.Mode().IsRegular() {
		return false
	}
	return fi.Mode()&0111 != 0
}

func homeDir() string {
	if h := os.Getenv("HOME"); h != "" {
		return h
	}
	h, err := os.UserHomeDir()
	if err != nil {
		printErr("cannot determine home directory")
		os.Exit(1)
	}
	return h
}
