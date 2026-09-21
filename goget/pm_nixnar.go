package main

import (
	"bufio"
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// The pieces of the Nix binary-cache protocol goget needs: unpacking a NAR archive, Nix's base32
// alphabet for hashes, and verifying narinfo signatures (ed25519).

const nix32Chars = "0123456789abcdfghijklmnpqrsvwxyz"

// nix32 encodes a hash the way Nix prints it ("sha256:1alv5lz...").
func nix32(h []byte) string {
	n := (len(h)*8-1)/5 + 1
	out := make([]byte, 0, n)
	for i := n - 1; i >= 0; i-- {
		b := uint(i * 5)
		j, k := b/8, b%8
		c := h[j] >> k
		if int(j) < len(h)-1 {
			c |= h[j+1] << (8 - k)
		}
		out = append(out, nix32Chars[c&0x1f])
	}
	return string(out)
}

// nixCacheKeys are the binary caches goget trusts, by key name.
var nixCacheKeys = map[string]string{
	"cache.nixos.org-1": "6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=",
}

func nixVerifySig(fingerprint string, sigs []string) error {
	for _, s := range sigs {
		name, b64, ok := strings.Cut(s, ":")
		if !ok {
			continue
		}
		keyB64, trusted := nixCacheKeys[name]
		if !trusted {
			continue
		}
		key, err1 := base64.StdEncoding.DecodeString(keyB64)
		sig, err2 := base64.StdEncoding.DecodeString(b64)
		if err1 != nil || err2 != nil || len(key) != ed25519.PublicKeySize {
			continue
		}
		if ed25519.Verify(ed25519.PublicKey(key), []byte(fingerprint), sig) {
			return nil
		}
	}
	return fmt.Errorf("no valid signature from a trusted cache key")
}

// ---- NAR ---------------------------------------------------------------------------------------

type narReader struct {
	r   *bufio.Reader
	buf [8]byte
}

func (n *narReader) u64() (uint64, error) {
	if _, err := io.ReadFull(n.r, n.buf[:]); err != nil {
		return 0, err
	}
	return binary.LittleEndian.Uint64(n.buf[:]), nil
}

func (n *narReader) pad(l uint64) error {
	if p := l % 8; p != 0 {
		_, err := io.CopyN(io.Discard, n.r, int64(8-p))
		return err
	}
	return nil
}

func (n *narReader) str() (string, error) {
	l, err := n.u64()
	if err != nil {
		return "", err
	}
	if l > 1<<20 {
		return "", fmt.Errorf("nar: string of %d bytes", l)
	}
	b := make([]byte, l)
	if _, err := io.ReadFull(n.r, b); err != nil {
		return "", err
	}
	return string(b), n.pad(l)
}

func (n *narReader) expect(want string) error {
	s, err := n.str()
	if err != nil {
		return err
	}
	if s != want {
		return fmt.Errorf("nar: expected %q, got %q", want, s)
	}
	return nil
}

// unpackNAR extracts the archive read from r at dst.
func unpackNAR(r io.Reader, dst string) error {
	n := &narReader{r: bufio.NewReaderSize(r, 1<<20)}
	if err := n.expect("nix-archive-1"); err != nil {
		return err
	}
	return n.node(dst)
}

func (n *narReader) node(dst string) error {
	if err := n.expect("("); err != nil {
		return err
	}
	if err := n.expect("type"); err != nil {
		return err
	}
	typ, err := n.str()
	if err != nil {
		return err
	}
	switch typ {
	case "regular":
		exec := false
		tag, err := n.str()
		if err != nil {
			return err
		}
		if tag == "executable" {
			exec = true
			if err := n.expect(""); err != nil {
				return err
			}
			if tag, err = n.str(); err != nil {
				return err
			}
		}
		if tag != "contents" {
			return fmt.Errorf("nar: unexpected %q in file", tag)
		}
		l, err := n.u64()
		if err != nil {
			return err
		}
		mode := os.FileMode(0o444)
		if exec {
			mode = 0o555
		}
		f, err := os.OpenFile(dst, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
		if err != nil {
			return err
		}
		if _, err := io.CopyN(f, n.r, int64(l)); err != nil {
			f.Close()
			return err
		}
		if err := f.Close(); err != nil {
			return err
		}
		if err := n.pad(l); err != nil {
			return err
		}
		if err := os.Chmod(dst, mode); err != nil {
			return err
		}
		return n.expect(")")
	case "symlink":
		if err := n.expect("target"); err != nil {
			return err
		}
		t, err := n.str()
		if err != nil {
			return err
		}
		if err := os.Symlink(t, dst); err != nil {
			return err
		}
		return n.expect(")")
	case "directory":
		if err := os.Mkdir(dst, 0o755); err != nil && !os.IsExist(err) {
			return err
		}
		for {
			tag, err := n.str()
			if err != nil {
				return err
			}
			if tag == ")" {
				return os.Chmod(dst, 0o555)
			}
			if tag != "entry" {
				return fmt.Errorf("nar: unexpected %q in directory", tag)
			}
			if err := n.expect("("); err != nil {
				return err
			}
			if err := n.expect("name"); err != nil {
				return err
			}
			name, err := n.str()
			if err != nil {
				return err
			}
			if name == "" || name == "." || name == ".." || strings.ContainsRune(name, '/') {
				return fmt.Errorf("nar: bad entry name %q", name)
			}
			if err := n.expect("node"); err != nil {
				return err
			}
			if err := n.node(filepath.Join(dst, name)); err != nil {
				return err
			}
			if err := n.expect(")"); err != nil {
				return err
			}
		}
	}
	return fmt.Errorf("nar: unknown node type %q", typ)
}

// hashingReader computes the SHA-256 of everything read through it.
type hashingReader struct {
	r io.Reader
	h interface {
		io.Writer
		Sum([]byte) []byte
	}
}

func newHashingReader(r io.Reader) *hashingReader { return &hashingReader{r: r, h: sha256.New()} }

func (h *hashingReader) Read(p []byte) (int, error) {
	n, err := h.r.Read(p)
	h.h.Write(p[:n])
	return n, err
}

func (h *hashingReader) nix32() string { return nix32(h.h.Sum(nil)) }
