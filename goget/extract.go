package main

import (
	"archive/tar"
	"archive/zip"
	"compress/bzip2"
	"compress/gzip"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// extractArchive extracts the archive at archivePath into destDir
// (which must already exist). Format/compression is auto-detected from
// the file's magic bytes rather than trusted from its name. gzip, bzip2,
// plain tar, and zip are handled with the standard library alone (no
// libarchive, no shelling out); xz is the one format the standard
// library has no decompressor for, so that one case shells out to the
// system `tar`, which handles xz transparently on every Linux distro
// goget targets.
func extractArchive(archivePath, destDir string) error {
	f, err := os.Open(archivePath)
	if err != nil {
		return err
	}
	defer f.Close()

	magic := make([]byte, 6)
	n, _ := io.ReadFull(f, magic)
	magic = magic[:n]
	f.Seek(0, io.SeekStart)

	switch {
	case len(magic) >= 2 && magic[0] == 'P' && magic[1] == 'K':
		return extractZip(archivePath, destDir)
	case len(magic) >= 2 && magic[0] == 0x1f && magic[1] == 0x8b:
		gz, err := gzip.NewReader(f)
		if err != nil {
			return err
		}
		defer gz.Close()
		return extractTar(gz, destDir)
	case len(magic) >= 3 && string(magic[:3]) == "BZh":
		return extractTar(bzip2.NewReader(f), destDir)
	case len(magic) >= 6 && magic[0] == 0xFD && string(magic[1:6]) == "7zXZ\x00":
		exitCode := runCommand("", []string{"tar", "-xf", archivePath, "-C", destDir})
		if exitCode != 0 {
			return fmt.Errorf("tar -xf exited %d", exitCode)
		}
		return nil
	default:
		// Assume plain uncompressed tar.
		return extractTar(f, destDir)
	}
}

// safeJoin joins destDir with an archive entry's own path, refusing any
// entry that would extract outside destDir (a zip-slip / path-traversal
// guard -- the same property libarchive's ARCHIVE_EXTRACT_SECURE_NODOTDOT
// provided in the C version).
func safeJoin(destDir, entryName string) (string, error) {
	cleaned := filepath.Join(destDir, filepath.Clean("/"+entryName))
	if !strings.HasPrefix(cleaned, filepath.Clean(destDir)+string(filepath.Separator)) && cleaned != filepath.Clean(destDir) {
		return "", fmt.Errorf("archive entry %q escapes destination directory", entryName)
	}
	return cleaned, nil
}

func extractTar(r io.Reader, destDir string) error {
	tr := tar.NewReader(r)
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}

		target, err := safeJoin(destDir, hdr.Name)
		if err != nil {
			return err
		}

		switch hdr.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(target, os.FileMode(hdr.Mode)|0755); err != nil {
				return err
			}
		case tar.TypeSymlink:
			os.MkdirAll(filepath.Dir(target), 0755)
			os.Remove(target)
			if err := os.Symlink(hdr.Linkname, target); err != nil {
				return err
			}
		case tar.TypeReg, tar.TypeRegA:
			if err := os.MkdirAll(filepath.Dir(target), 0755); err != nil {
				return err
			}
			out, err := os.OpenFile(target, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, os.FileMode(hdr.Mode)|0644)
			if err != nil {
				return err
			}
			_, copyErr := io.Copy(out, tr)
			out.Close()
			if copyErr != nil {
				return copyErr
			}
		default:
			// Device nodes, FIFOs, etc: not meaningful for a source/binary
			// release archive, silently skipped.
		}
	}
}

func extractZip(archivePath, destDir string) error {
	zr, err := zip.OpenReader(archivePath)
	if err != nil {
		return err
	}
	defer zr.Close()

	for _, entry := range zr.File {
		target, err := safeJoin(destDir, entry.Name)
		if err != nil {
			return err
		}

		if entry.FileInfo().IsDir() {
			if err := os.MkdirAll(target, 0755); err != nil {
				return err
			}
			continue
		}

		if err := os.MkdirAll(filepath.Dir(target), 0755); err != nil {
			return err
		}
		rc, err := entry.Open()
		if err != nil {
			return err
		}
		out, err := os.OpenFile(target, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, entry.Mode()|0644)
		if err != nil {
			rc.Close()
			return err
		}
		_, copyErr := io.Copy(out, rc)
		out.Close()
		rc.Close()
		if copyErr != nil {
			return copyErr
		}
	}
	return nil
}
