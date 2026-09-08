package runlock

import (
	"path/filepath"
	"testing"
)

func TestAcquirePreventsOverlap(t *testing.T) {
	path := filepath.Join(t.TempDir(), "guardian.lock")
	first, err := Acquire(path)
	if err != nil {
		t.Fatal(err)
	}
	defer first.Close()
	if _, err := Acquire(path); err == nil {
		t.Fatal("second process should be rejected")
	}
	if err := first.Close(); err != nil {
		t.Fatal(err)
	}
	second, err := Acquire(path)
	if err != nil {
		t.Fatal(err)
	}
	_ = second.Close()
}
