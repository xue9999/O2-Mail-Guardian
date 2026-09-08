package service

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestHeartbeatRoundTripIsPrivateAndContainsNoMailData(t *testing.T) {
	dir := t.TempDir()
	attempt := time.Date(2026, 8, 20, 10, 0, 0, 0, time.UTC)
	success := attempt.Add(-time.Hour)
	want := Heartbeat{
		LastAttempt: &attempt, LastSuccess: &success, Stage: "mailbox",
		ErrorCode: "IMAP_UIDVALIDITY", Version: "0.3.0",
	}
	if err := WriteHeartbeat(dir, want); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, HeartbeatFileName)
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("heartbeat permissions = %o, want 600", info.Mode().Perm())
	}
	got, err := ReadHeartbeat(dir)
	if err != nil {
		t.Fatal(err)
	}
	if got.Protocol != 1 || got.Stage != want.Stage || got.ErrorCode != want.ErrorCode ||
		got.LastAttempt == nil || !got.LastAttempt.Equal(attempt) {
		t.Fatalf("unexpected heartbeat: %#v", got)
	}
}

func TestHeartbeatRejectsOversizedOrUnknownProtocol(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, HeartbeatFileName)
	if err := os.WriteFile(path, make([]byte, (32<<10)+1), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := ReadHeartbeat(dir); err == nil {
		t.Fatal("oversized heartbeat was accepted")
	}
	if err := os.WriteFile(path, []byte(`{"protocol":2,"stage":"ok"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := ReadHeartbeat(dir); err == nil {
		t.Fatal("unknown heartbeat protocol was accepted")
	}
}
