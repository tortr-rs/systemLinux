// imagesign: Ed25519 signing for systemLinux image updates.
//
//	imagesign keygen DIR       write DIR/update.key (private, keep secret) and DIR/update.pub (public, hex)
//	imagesign sign KEYFILE FILE   print the base64 signature of FILE
//	imagesign verify PUBHEX FILE SIGFILE
package main

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func die(format string, a ...any) {
	fmt.Fprintf(os.Stderr, "imagesign: "+format+"\n", a...)
	os.Exit(1)
}

func main() {
	if len(os.Args) < 2 {
		die("usage: imagesign keygen DIR | sign KEYFILE FILE | verify PUBHEX FILE SIGFILE")
	}
	switch os.Args[1] {
	case "keygen":
		if len(os.Args) != 3 {
			die("usage: imagesign keygen DIR")
		}
		dir := os.Args[2]
		if err := os.MkdirAll(dir, 0o700); err != nil {
			die("%v", err)
		}
		key := filepath.Join(dir, "update.key")
		if _, err := os.Stat(key); err == nil {
			die("%s already exists; refusing to overwrite a signing key", key)
		}
		pub, priv, err := ed25519.GenerateKey(rand.Reader)
		if err != nil {
			die("%v", err)
		}
		if err := os.WriteFile(key, []byte(base64.StdEncoding.EncodeToString(priv)+"\n"), 0o600); err != nil {
			die("%v", err)
		}
		if err := os.WriteFile(filepath.Join(dir, "update.pub"), []byte(hex.EncodeToString(pub)+"\n"), 0o644); err != nil {
			die("%v", err)
		}
		fmt.Println(hex.EncodeToString(pub))
	case "sign":
		if len(os.Args) != 4 {
			die("usage: imagesign sign KEYFILE FILE")
		}
		raw, err := os.ReadFile(os.Args[2])
		if err != nil {
			die("%v", err)
		}
		priv, err := base64.StdEncoding.DecodeString(strings.TrimSpace(string(raw)))
		if err != nil || len(priv) != ed25519.PrivateKeySize {
			die("%s is not an imagesign private key", os.Args[2])
		}
		msg, err := os.ReadFile(os.Args[3])
		if err != nil {
			die("%v", err)
		}
		fmt.Println(base64.StdEncoding.EncodeToString(ed25519.Sign(ed25519.PrivateKey(priv), msg)))
	case "verify":
		if len(os.Args) != 5 {
			die("usage: imagesign verify PUBHEX FILE SIGFILE")
		}
		pub, err := hex.DecodeString(strings.TrimSpace(os.Args[2]))
		if err != nil || len(pub) != ed25519.PublicKeySize {
			die("bad public key")
		}
		msg, _ := os.ReadFile(os.Args[3])
		sigb, _ := os.ReadFile(os.Args[4])
		sig, err := base64.StdEncoding.DecodeString(strings.TrimSpace(string(sigb)))
		if err != nil || !ed25519.Verify(ed25519.PublicKey(pub), msg, sig) {
			die("signature does NOT match")
		}
		fmt.Println("signature ok")
	default:
		die("unknown command %q", os.Args[1])
	}
}
