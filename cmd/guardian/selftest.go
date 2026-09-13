package main

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/o2-mail-guardian/guardian/internal/store"
)

// Runs without user configuration, Keychain, IMAP, or services.
func (a *application) selfTest() error {
	root, err := os.MkdirTemp("", "guardian-self-test-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(root)
	db, err := store.Open(filepath.Join(root, "test.db"))
	if err != nil {
		return err
	}
	defer db.Close()
	if _, err := db.Summary(context.Background(), time.Now()); err != nil {
		return err
	}
	fmt.Fprintln(a.out, "Samokontrola silnika: OK")
	return nil
}
