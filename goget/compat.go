package main

import (
	"debug/elf"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
)

type archT int

const (
	archUnknown archT = iota
	archAMD64
	archARM64
	archARM
	arch386
)

func hostArch() archT {
	switch runtime.GOARCH {
	case "amd64":
		return archAMD64
	case "arm64":
		return archARM64
	case "arm":
		return archARM
	case "386":
		return arch386
	default:
		return archUnknown
	}
}

// archFromAssetName is a best-effort guess at the architecture a release
// asset's filename refers to, from common naming conventions.
// archUnknown if nothing recognizable is found (caller should then not
// reject on arch alone).
func archFromAssetName(name string) archT {
	switch {
	case strCIContains(name, "aarch64") || strCIContains(name, "arm64"):
		return archARM64
	case strCIContains(name, "x86_64") || strCIContains(name, "amd64"):
		return archAMD64
	case strCIContains(name, "armv7") || strCIContains(name, "armhf") || strCIContains(name, "arm32"):
		return archARM
	case strCIContains(name, "i386") || strCIContains(name, "i686") || strCIContains(name, "386"):
		return arch386
	default:
		return archUnknown
	}
}

// hostIsMusl reports whether this host uses musl libc.
func hostIsMusl() bool {
	patterns := []string{
		"/lib/ld-musl-*.so.1",
		"/lib64/ld-musl-*.so.1",
		"/usr/lib/ld-musl-*.so.1",
	}
	for _, p := range patterns {
		matches, _ := filepath.Glob(p)
		if len(matches) > 0 {
			return true
		}
	}
	return false
}

// hostGlibcVersion returns "major.minor" for the host's glibc, or ""
// if the host is musl or the version couldn't be determined.
func hostGlibcVersion() string {
	if hostIsMusl() {
		return ""
	}
	out, status := runCommandCapture([]string{"ldd", "--version"})
	if status != 0 {
		return ""
	}
	firstLine := out
	if idx := strings.IndexByte(out, '\n'); idx >= 0 {
		firstLine = out[:idx]
	}
	fields := strings.Fields(firstLine)
	if len(fields) == 0 {
		return ""
	}
	token := fields[len(fields)-1]
	if token == "" || token[0] < '0' || token[0] > '9' {
		return ""
	}
	return token
}

type binaryLibcT int

const (
	libcStatic  binaryLibcT = iota // no dynamic interpreter -- libc compatibility doesn't apply
	libcGlibc
	libcMusl
	libcUnknown // has an interpreter, but not one recognized
)

var foreignABITokens = []string{"FreeBSD", "NetBSD", "OpenBSD", "Solaris", "HP-UX", "IRIX", "AIX", "Tru64"}

// binaryLibcKind inspects the ELF file at path directly (no readelf/
// objdump subprocess needed -- debug/elf reads the program headers and
// dynamic symbol table natively) to determine which libc it's linked
// against, if any.
func binaryLibcKind(path string) binaryLibcT {
	f, err := elf.Open(path)
	if err != nil {
		return libcUnknown
	}
	defer f.Close()

	// Defense in depth beyond filename-based OS filtering: reject ELF
	// binaries whose OS/ABI header field names a non-Linux UNIX. Not
	// exhaustive (many cross-platform toolchains, and Haiku which has no
	// registered ELFOSABI value at all, leave this as the generic "UNIX -
	// System V" default) but free to check since the header is already
	// parsed.
	osabi := f.OSABI.String()
	for _, tok := range foreignABITokens {
		if strCIContains(osabi, tok) {
			return libcUnknown
		}
	}

	var interp string
	for _, prog := range f.Progs {
		if prog.Type == elf.PT_INTERP {
			data := make([]byte, prog.Filesz)
			if _, err := prog.ReadAt(data, 0); err == nil {
				interp = strings.TrimRight(string(data), "\x00")
			}
			break
		}
	}

	if interp == "" {
		// Valid ELF with no PT_INTERP segment: statically linked, so
		// there's no dynamic libc dependency to check.
		return libcStatic
	}
	switch {
	case strCIContains(interp, "musl"):
		return libcMusl
	case strCIContains(interp, "ld-linux") || strCIContains(interp, "ld.so") || strCIContains(interp, "ld64.so"):
		return libcGlibc
	default:
		return libcUnknown
	}
}

func versionComponent(v string, idx int) int {
	parts := strings.Split(v, ".")
	if idx >= len(parts) {
		return 0
	}
	n, _ := strconv.Atoi(parts[idx])
	return n
}

// compareVersion does a numeric "major.minor[.patch...]" comparison,
// like strcmp's sign convention.
func compareVersion(a, b string) int {
	for i := 0; i < 4; i++ {
		va, vb := versionComponent(a, i), versionComponent(b, i)
		if va != vb {
			if va < vb {
				return -1
			}
			return 1
		}
	}
	return 0
}

// binaryMinGlibcVersion returns "major.minor" for the minimum glibc
// version a glibc-linked binary requires (the highest GLIBC_x.y symbol
// version among its imported dynamic symbols), or "" if none is found.
// Reads the ELF dynamic symbol table directly rather than shelling out
// to objdump.
func binaryMinGlibcVersion(path string) string {
	f, err := elf.Open(path)
	if err != nil {
		return ""
	}
	defer f.Close()

	syms, err := f.ImportedSymbols()
	if err != nil {
		return ""
	}

	best := ""
	for _, s := range syms {
		if !strings.HasPrefix(s.Version, "GLIBC_") {
			continue
		}
		ver := strings.TrimPrefix(s.Version, "GLIBC_")
		if best == "" || compareVersion(ver, best) > 0 {
			best = ver
		}
	}
	return best
}

// binaryIsCompatible is the full compatibility check: architecture
// match, musl-vs-glibc mismatch, and (if both glibc) minimum version.
// assetName is used only to guess the asset's architecture from its
// filename. An unrecognized dynamic linker is treated as incompatible --
// a wrongly-installed broken binary is worse than an unnecessary source
// build.
func binaryIsCompatible(path, assetName string) bool {
	assetArch := archFromAssetName(assetName)
	if assetArch != archUnknown && assetArch != hostArch() {
		return false
	}

	kind := binaryLibcKind(path)
	if kind == libcStatic {
		return true
	}
	if kind == libcUnknown {
		return false
	}

	muslHost := hostIsMusl()
	if kind == libcMusl {
		return muslHost
	}
	if muslHost {
		return false // kind == libcGlibc on a musl host
	}

	hostVer := hostGlibcVersion()
	binVer := binaryMinGlibcVersion(path)
	if hostVer != "" && binVer != "" && compareVersion(binVer, hostVer) > 0 {
		return false
	}
	return true
}
