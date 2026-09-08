package archive

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"filippo.io/age"
)

func TestEncryptedArchiveRoundTrip(t *testing.T) {
	id, err := age.GenerateX25519Identity()
	if err != nil {
		t.Fatal(err)
	}
	root := t.TempDir()
	manager, err := New(root, id)
	if err != nil {
		t.Fatal(err)
	}
	raw := []byte("From: sender@example.org\r\nMessage-ID: <one@example.org>\r\n\r\nsecret body")
	hash := SHA256(raw)
	path, err := manager.Save(raw, hash, time.Date(2026, 7, 25, 8, 0, 0, 0, time.UTC))
	if err != nil {
		t.Fatal(err)
	}
	onDisk, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(onDisk) == string(raw) {
		t.Fatal("archive is plaintext")
	}
	got, err := manager.Read(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != string(raw) {
		t.Fatalf("round trip mismatch: %q", got)
	}
	info, _ := os.Stat(path)
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("archive permissions are %o", info.Mode().Perm())
	}
}

func TestArchiveRejectsWrongHashAndOutsidePath(t *testing.T) {
	id, _ := age.GenerateX25519Identity()
	root := t.TempDir()
	manager, _ := New(root, id)
	if _, err := manager.Save([]byte("mail"), "wrong", time.Now()); err == nil {
		t.Fatal("expected hash mismatch")
	}
	outside := filepath.Join(filepath.Dir(root), "outside.age")
	if _, err := manager.Read(outside); err == nil {
		t.Fatal("expected path traversal rejection")
	}
	missingInside := filepath.Join(root, "missing.eml.age")
	if _, err := manager.Read(missingInside); !os.IsNotExist(err) {
		t.Fatalf("missing in-root file should retain os.ErrNotExist: %v", err)
	}
}

func TestArchiveDetectsTampering(t *testing.T) {
	id, _ := age.GenerateX25519Identity()
	manager, _ := New(t.TempDir(), id)
	raw := []byte("message")
	path, err := manager.Save(raw, SHA256(raw), time.Now())
	if err != nil {
		t.Fatal(err)
	}
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_APPEND, 0)
	if err != nil {
		t.Fatal(err)
	}
	_, _ = f.Write([]byte("tamper"))
	_ = f.Close()
	if err := manager.Verify(path, SHA256(raw)); err == nil {
		t.Fatal("expected tamper detection")
	}
}

func TestHasEncryptedFilesFailsClosed(t *testing.T) {
	missing := filepath.Join(t.TempDir(), "missing")
	found, err := HasEncryptedFiles(missing)
	if err != nil || found {
		t.Fatalf("missing archive: found=%v err=%v", found, err)
	}

	root := t.TempDir()
	nested := filepath.Join(root, "2026", "07")
	if err := os.MkdirAll(nested, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(nested, "notes.txt"), []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}
	found, err = HasEncryptedFiles(root)
	if err != nil || found {
		t.Fatalf("unrelated file: found=%v err=%v", found, err)
	}
	if err := os.WriteFile(filepath.Join(nested, "copy.eml.age"), []byte("ciphertext"), 0o600); err != nil {
		t.Fatal(err)
	}
	found, err = HasEncryptedFiles(root)
	if err != nil || !found {
		t.Fatalf("encrypted file: found=%v err=%v", found, err)
	}
}

func TestArchiveRejectsSymlinkEscape(t *testing.T) {
	id, _ := age.GenerateX25519Identity()
	root := t.TempDir()
	outside := t.TempDir()
	year := filepath.Join(root, time.Now().UTC().Format("2006"))
	if err := os.Symlink(outside, year); err != nil {
		t.Fatal(err)
	}
	manager, err := New(root, id)
	if err != nil {
		t.Fatal(err)
	}
	raw := []byte("From: sender@example.org\r\n\r\nbody")
	if _, err := manager.Save(raw, SHA256(raw), time.Now()); err == nil {
		t.Fatal("archive followed a symlink outside its root")
	}
	if entries, err := os.ReadDir(outside); err != nil || len(entries) != 0 {
		t.Fatalf("archive wrote through the symlink: entries=%d err=%v", len(entries), err)
	}
	if _, err := HasEncryptedFiles(root); err == nil {
		t.Fatal("key-rotation guard accepted an archive containing a symlink")
	}
}
