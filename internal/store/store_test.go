package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"testing"
	"time"
)

func TestVersionTwoDatabaseMigratesFeedbackIntentTransactionally(t *testing.T) {
	path := filepath.Join(t.TempDir(), "state.db")
	legacy, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatal(err)
	}
	_, err = legacy.Exec(`CREATE TABLE messages (
		id INTEGER PRIMARY KEY, account TEXT NOT NULL, source_folder TEXT NOT NULL,
		current_folder TEXT NOT NULL, uidvalidity INTEGER NOT NULL, uid INTEGER NOT NULL,
		message_id_hash TEXT NOT NULL, raw_sha256 TEXT NOT NULL, size_bytes INTEGER NOT NULL,
		verdict TEXT NOT NULL, score REAL NOT NULL, symbols_json TEXT NOT NULL,
		action TEXT NOT NULL, status TEXT NOT NULL, first_seen TEXT NOT NULL,
		last_scanned TEXT NOT NULL, quarantined_at TEXT, delete_after TEXT,
		archive_path TEXT NOT NULL DEFAULT '', archive_until TEXT,
		feedback TEXT NOT NULL DEFAULT '', last_error TEXT NOT NULL DEFAULT '')`)
	if err != nil {
		t.Fatal(err)
	}
	if err := legacy.Close(); err != nil {
		t.Fatal(err)
	}

	db, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	now := time.Now().UTC()
	id, err := db.UpsertMessage(context.Background(), &Message{
		Account: "test@o2.pl", SourceFolder: "training", CurrentFolder: "AI-Naucz-wazne",
		UIDValidity: 1, UID: 1, MessageIDHash: "mid", RawSHA256: "raw", Verdict: "ham",
		Action: "learn_ham", Status: "pending_learn", FirstSeen: now, LastScanned: now,
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.MarkFeedbackIntent(context.Background(), id, "ham"); err != nil {
		t.Fatal(err)
	}
	message, err := db.MessageByID(context.Background(), id)
	if err != nil || message.FeedbackIntent != "ham" {
		t.Fatalf("migration did not preserve the new intent field: %#v err=%v", message, err)
	}
}

func TestRequireFreshDryRunResetsSafetyStateAtomically(t *testing.T) {
	db, err := Open(filepath.Join(t.TempDir(), "state.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	ctx := context.Background()
	for key, value := range map[string]string{
		"first_dry_run_completed_at": "2026-08-01T12:00:00Z",
		"active_since":               "2026-07-01T12:00:00Z",
		"protect_since":              "2026-06-01T12:00:00Z",
	} {
		if err := db.SetSetting(ctx, key, value); err != nil {
			t.Fatal(err)
		}
	}
	now := time.Date(2026, 8, 22, 9, 30, 0, 0, time.FixedZone("CEST", 2*60*60))
	if err := db.RequireFreshDryRun(ctx, now); err != nil {
		t.Fatal(err)
	}
	if value, exists, err := db.GetSettingWithPresence(ctx, "first_dry_run_completed_at"); err != nil || !exists || value != "" {
		t.Fatalf("explicit dry-run reset lost its presence: value=%q exists=%v err=%v", value, exists, err)
	}
	if value, exists, err := db.GetSettingWithPresence(ctx, "never-created"); err != nil || exists || value != "" {
		t.Fatalf("missing setting was not distinguished: value=%q exists=%v err=%v", value, exists, err)
	}
	for key, want := range map[string]string{
		"first_dry_run_completed_at": "",
		"active_since":               "",
		"protect_since":              "2026-08-22T07:30:00Z",
	} {
		got, err := db.GetSetting(ctx, key)
		if err != nil || got != want {
			t.Fatalf("%s = %q, want %q (err=%v)", key, got, want, err)
		}
	}
}

func TestMessageLifecycleAndPurgeCandidate(t *testing.T) {
	db, err := Open(filepath.Join(t.TempDir(), "state.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	ctx := context.Background()
	now := time.Now().UTC().Add(-31 * 24 * time.Hour)
	deleteAfter := now.Add(30 * 24 * time.Hour)
	archiveUntil := now.Add(35 * 24 * time.Hour)
	m := &Message{
		Account: "test@o2.pl", SourceFolder: "INBOX", CurrentFolder: "AI-Kwarantanna",
		UIDValidity: 7, UID: 42, MessageIDHash: "mid", RawSHA256: "raw",
		SizeBytes: 123, Verdict: "spam", Score: 15, Symbols: []string{"BAYES_SPAM"},
		Action: "quarantine", Status: "quarantined", FirstSeen: now, LastScanned: now,
		QuarantinedAt: &now, DeleteAfter: &deleteAfter, ArchivePath: "/tmp/example.age",
		ArchiveUntil: &archiveUntil,
	}
	id, err := db.UpsertMessage(ctx, m)
	if err != nil {
		t.Fatal(err)
	}
	if id == 0 {
		t.Fatal("missing id")
	}
	other := *m
	other.ID = 0
	other.Account = "other@o2.pl"
	other.RawSHA256 = "other-raw"
	if _, err := db.UpsertMessage(ctx, &other); err != nil {
		t.Fatal(err)
	}
	processed, err := db.LocationProcessed(ctx, m.Account, m.CurrentFolder, m.UIDValidity, m.UID, true)
	if err != nil || !processed {
		t.Fatalf("processed=%v err=%v", processed, err)
	}
	candidates, err := db.PurgeCandidates(ctx, m.Account, time.Now().UTC())
	if err != nil {
		t.Fatal(err)
	}
	if len(candidates) != 1 || candidates[0].ID != id {
		t.Fatalf("unexpected candidates: %#v", candidates)
	}
	if err := db.MarkPurged(ctx, id); err != nil {
		t.Fatal(err)
	}
	candidates, _ = db.PurgeCandidates(ctx, m.Account, time.Now().UTC())
	if len(candidates) != 0 {
		t.Fatal("purged message remained eligible")
	}
}

func TestObservedMessageIsRescannedAfterActivation(t *testing.T) {
	db, err := Open(filepath.Join(t.TempDir(), "state.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	ctx := context.Background()
	now := time.Now().UTC()
	_, err = db.UpsertMessage(ctx, &Message{
		Account: "test@o2.pl", SourceFolder: "inbox", CurrentFolder: "INBOX",
		UIDValidity: 1, UID: 3, MessageIDHash: "mid", RawSHA256: "raw",
		Verdict: "uncertain", Action: "keep", Status: "observed",
		FirstSeen: now, LastScanned: now,
	})
	if err != nil {
		t.Fatal(err)
	}
	if got, _ := db.LocationProcessed(ctx, "test@o2.pl", "INBOX", 1, 3, false); !got {
		t.Fatal("protect mode should skip already observed UID")
	}
	if got, _ := db.LocationProcessed(ctx, "test@o2.pl", "INBOX", 1, 3, true); got {
		t.Fatal("active mode must re-evaluate observed UID")
	}
}

func TestPendingMoveIsNeverTreatedAsProcessed(t *testing.T) {
	db, err := Open(filepath.Join(t.TempDir(), "state.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	ctx := context.Background()
	now := time.Now().UTC()
	message := &Message{
		Account: "test@o2.pl", SourceFolder: "inbox", CurrentFolder: "INBOX",
		UIDValidity: 4, UID: 7, MessageIDHash: "mid", RawSHA256: "raw",
		Verdict: "spam", Action: "quarantined", Status: "pending_move",
		FirstSeen: now, LastScanned: now,
	}
	if _, err := db.UpsertMessage(ctx, message); err != nil {
		t.Fatal(err)
	}
	processed, err := db.LocationProcessed(ctx, message.Account, message.CurrentFolder, message.UIDValidity, message.UID, true)
	if err != nil {
		t.Fatal(err)
	}
	if processed {
		t.Fatal("pending_move must remain retryable")
	}
	pending, err := db.PendingMessages(ctx, message.Account)
	if err != nil || len(pending) != 1 || pending[0].ID != message.ID {
		t.Fatalf("pending=%#v err=%v", pending, err)
	}
	if err := db.UpdateLocation(ctx, message.ID, message.CurrentFolder, message.UIDValidity, message.UID, "move_ambiguous"); err != nil {
		t.Fatal(err)
	}
	pending, err = db.PendingMessages(ctx, message.Account)
	if err != nil || len(pending) != 1 || pending[0].ID != message.ID {
		t.Fatalf("move_ambiguous must remain reconcilable: pending=%#v err=%v", pending, err)
	}
}

func TestPendingLearnIsRetried(t *testing.T) {
	db, err := Open(filepath.Join(t.TempDir(), "state.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	ctx := context.Background()
	now := time.Now().UTC()
	_, err = db.UpsertMessage(ctx, &Message{
		Account: "test@o2.pl", SourceFolder: "training", CurrentFolder: "AI-Naucz-spam",
		UIDValidity: 2, UID: 7, MessageIDHash: "mid", RawSHA256: "raw",
		Verdict: "spam", Action: "learn_spam", Status: "pending_learn",
		FirstSeen: now, LastScanned: now,
	})
	if err != nil {
		t.Fatal(err)
	}
	if got, err := db.LocationProcessed(ctx, "test@o2.pl", "AI-Naucz-spam", 2, 7, true); err != nil || got {
		t.Fatalf("pending learn must be retried: processed=%v err=%v", got, err)
	}
}

func TestRunSummary(t *testing.T) {
	db, err := Open(filepath.Join(t.TempDir(), "state.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	ctx := context.Background()
	run, _ := db.BeginRun(ctx, "run", false)
	run.Scanned, run.Rescued, run.Errors = 5, 2, 1
	if err := db.FinishRun(ctx, run, nil); err != nil {
		t.Fatal(err)
	}
	dryRun, _ := db.BeginRun(ctx, "run", true)
	dryRun.Scanned, dryRun.Rescued, dryRun.Errors = 50, 20, 10
	if err := db.FinishRun(ctx, dryRun, nil); err != nil {
		t.Fatal(err)
	}
	failedRun, _ := db.BeginRun(ctx, "purge", false)
	if err := db.FinishRun(ctx, failedRun, errors.New("quality gate failed")); err != nil {
		t.Fatal(err)
	}
	s, err := db.Summary(ctx, time.Now().Add(-time.Hour))
	if err != nil {
		t.Fatal(err)
	}
	if s.Runs != 3 || s.DryRuns != 1 || s.Scanned != 5 || s.Rescued != 2 || s.Errors != 2 {
		t.Fatalf("unexpected summary: %#v", s)
	}
}

func TestBeginRunMarksInterruptedRunAsFailed(t *testing.T) {
	db, err := Open(filepath.Join(t.TempDir(), "state.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	ctx := context.Background()
	interrupted, err := db.BeginRun(ctx, "run", false)
	if err != nil {
		t.Fatal(err)
	}
	current, err := db.BeginRun(ctx, "run", false)
	if err != nil {
		t.Fatal(err)
	}
	if err := db.FinishRun(ctx, current, nil); err != nil {
		t.Fatal(err)
	}

	var status string
	var finishedAt any
	if err := db.sql.QueryRowContext(ctx,
		`SELECT status,finished_at FROM runs WHERE id=?`, interrupted.ID).
		Scan(&status, &finishedAt); err != nil {
		t.Fatal(err)
	}
	if status != "error" || finishedAt == nil {
		t.Fatalf("interrupted run was not recovered: status=%q finished=%v", status, finishedAt)
	}
	summary, err := db.Summary(ctx, time.Now().Add(-time.Hour))
	if err != nil {
		t.Fatal(err)
	}
	if summary.Errors != 1 {
		t.Fatalf("interrupted run disappeared from diagnostics: %#v", summary)
	}
}

func TestIdenticalMessagesAtDifferentUIDsRemainSeparate(t *testing.T) {
	db, err := Open(filepath.Join(t.TempDir(), "state.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	ctx := context.Background()
	now := time.Now().UTC()
	base := Message{
		Account: "test@o2.pl", SourceFolder: "inbox", CurrentFolder: "INBOX",
		UIDValidity: 1, MessageIDHash: "same-mid", RawSHA256: "same-raw",
		Verdict: "spam", Action: "quarantine", Status: "pending_move",
		FirstSeen: now, LastScanned: now,
	}
	first := base
	first.UID = 10
	firstID, err := db.UpsertMessage(ctx, &first)
	if err != nil {
		t.Fatal(err)
	}
	second := base
	second.UID = 11
	secondID, err := db.UpsertMessage(ctx, &second)
	if err != nil {
		t.Fatal(err)
	}
	if firstID == secondID {
		t.Fatal("identical deliveries at different UIDs must not overwrite each other")
	}
}

func TestTrainingTotals(t *testing.T) {
	db, err := Open(filepath.Join(t.TempDir(), "state.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	ctx := context.Background()
	now := time.Now().UTC()
	for i, sample := range []struct {
		label string
		raw   string
	}{
		{label: "spam", raw: "spam-a"},
		{label: "spam", raw: "spam-b"},
		{label: "spam", raw: "spam-a"}, // repeated drag must not inflate totals
		{label: "ham", raw: "ham-a"},
	} {
		_, err := db.UpsertMessage(ctx, &Message{
			Account: "test@o2.pl", SourceFolder: "training", CurrentFolder: "training",
			UIDValidity: 1, UID: uint32(i + 1), MessageIDHash: sample.label,
			RawSHA256: sample.raw, Verdict: sample.label,
			Action: "learn_" + sample.label, Status: "rescued", Feedback: sample.label,
			FirstSeen: now, LastScanned: now,
		})
		if err != nil {
			t.Fatal(err)
		}
	}
	_, err = db.UpsertMessage(ctx, &Message{
		Account: "other@o2.pl", SourceFolder: "training", CurrentFolder: "training",
		UIDValidity: 1, UID: 1, MessageIDHash: "other", RawSHA256: "other-spam",
		Verdict: "spam", Action: "learn_spam", Status: "quarantined", Feedback: "spam",
		FirstSeen: now, LastScanned: now,
	})
	if err != nil {
		t.Fatal(err)
	}
	spam, ham, err := db.TrainingTotals(ctx, "test@o2.pl")
	if err != nil || spam != 2 || ham != 1 {
		t.Fatalf("spam=%d ham=%d err=%v", spam, ham, err)
	}
}

func TestFeedbackLookupAndActivationQualityUseUniqueMessages(t *testing.T) {
	db, err := Open(filepath.Join(t.TempDir(), "state.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	ctx := context.Background()
	now := time.Now().UTC()
	add := func(uid uint32, raw, verdict, action, status, feedback string, at time.Time) {
		t.Helper()
		if _, err := db.UpsertMessage(ctx, &Message{
			Account: "test@o2.pl", SourceFolder: "test", CurrentFolder: "folder",
			UIDValidity: 1, UID: uid, MessageIDHash: raw, RawSHA256: raw,
			Verdict: verdict, Action: action, Status: status, Feedback: feedback,
			FirstSeen: at, LastScanned: at,
		}); err != nil {
			t.Fatal(err)
		}
	}
	// Nine samples were previously classified as spam. The tenth was safely
	// placed in review, satisfying the 90% + review remainder rule.
	for i := uint32(1); i <= 9; i++ {
		raw := string(rune('a' + i))
		add(i, raw, "spam", "quarantined", "superseded", "", now.Add(-time.Hour))
		add(100+i, raw, "spam", "learn_spam", "quarantined", "spam", now)
	}
	add(20, "reviewed", "uncertain", "review", "review", "", now.Add(-time.Hour))
	add(120, "reviewed", "spam", "learn_spam", "quarantined", "spam", now)
	add(121, "reviewed", "spam", "learn_spam", "quarantined", "spam", now.Add(time.Second))

	quality, err := db.ActivationQuality(ctx, "test@o2.pl", now.Add(-24*time.Hour))
	if err != nil {
		t.Fatal(err)
	}
	if !quality.Ready() || quality.SpamFeedback != 10 || quality.SpamPreviouslySpam != 9 ||
		quality.SpamPreviouslyReview != 1 || quality.SpamUnexplained != 0 {
		t.Fatalf("unexpected activation quality: %#v", quality)
	}
	activationCutoff := now.Add(time.Second)
	add(200, "late-correction", "spam", "quarantined", "superseded", "", now.Add(2*time.Second))
	add(201, "late-correction", "ham", "learn_ham", "rescued", "ham", now.Add(3*time.Second))
	frozen, err := db.ActivationQualityUntil(ctx, "test@o2.pl", now.Add(-24*time.Hour), activationCutoff)
	if err != nil || !frozen.Ready() {
		t.Fatalf("post-activation correction changed the frozen gate: %#v err=%v", frozen, err)
	}
	later, err := db.ActivationQualityUntil(ctx, "test@o2.pl", now.Add(-24*time.Hour), now.Add(4*time.Second))
	if err != nil || later.FalsePositives != 1 {
		t.Fatalf("rolling quality failed to see the later correction: %#v err=%v", later, err)
	}
	knownSpam, err := db.HasSpamFeedback(ctx, "test@o2.pl", "reviewed")
	if err != nil || !knownSpam {
		t.Fatalf("knownSpam=%v err=%v", knownSpam, err)
	}
	knownHam, err := db.HasHamFeedback(ctx, "test@o2.pl", "reviewed")
	if err != nil || knownHam {
		t.Fatalf("knownHam=%v err=%v", knownHam, err)
	}
}

func TestFinalizeMoveStartsRetentionAtConfirmation(t *testing.T) {
	db, err := Open(filepath.Join(t.TempDir(), "state.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	ctx := context.Background()
	attempted := time.Now().UTC().Add(-10 * 24 * time.Hour)
	archiveUntil := attempted.Add(35 * 24 * time.Hour)
	message := &Message{
		Account: "test@o2.pl", SourceFolder: "inbox", CurrentFolder: "INBOX",
		UIDValidity: 1, UID: 8, MessageIDHash: "mid", RawSHA256: "raw",
		Verdict: "spam", Action: "quarantined", Status: "pending_move",
		FirstSeen: attempted, LastScanned: attempted, ArchiveUntil: &archiveUntil,
	}
	id, err := db.UpsertMessage(ctx, message)
	if err != nil {
		t.Fatal(err)
	}
	confirmed := time.Now().UTC()
	if err := db.FinalizeMove(ctx, id, "AI-Kwarantanna", 2, 9, "quarantined", confirmed, 30, 35); err != nil {
		t.Fatal(err)
	}
	got, err := db.MessageByID(ctx, id)
	if err != nil {
		t.Fatal(err)
	}
	if got.QuarantinedAt == nil || !got.QuarantinedAt.Equal(confirmed) {
		t.Fatalf("quarantined_at=%v want=%v", got.QuarantinedAt, confirmed)
	}
	if got.DeleteAfter == nil || !got.DeleteAfter.Equal(confirmed.AddDate(0, 0, 30)) {
		t.Fatalf("delete_after=%v", got.DeleteAfter)
	}
	if got.ArchiveUntil == nil || !got.ArchiveUntil.Equal(confirmed.AddDate(0, 0, 35)) {
		t.Fatalf("archive_until=%v", got.ArchiveUntil)
	}
}

func TestOpenUsesPrivateDatabasePermissions(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Unix permission bits are not applicable")
	}
	path := filepath.Join(t.TempDir(), "state.db")
	db, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if got := info.Mode().Perm(); got != 0o600 {
		t.Fatalf("database mode=%#o want=0600", got)
	}
}

func TestMisclassificationsSince(t *testing.T) {
	db, err := Open(filepath.Join(t.TempDir(), "state.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	ctx := context.Background()
	now := time.Now().UTC()
	prior := &Message{
		Account: "test@o2.pl", SourceFolder: "inbox", CurrentFolder: "AI-Kwarantanna",
		UIDValidity: 1, UID: 1, MessageIDHash: "m", RawSHA256: "same",
		Verdict: "spam", Action: "quarantine", Status: "superseded",
		FirstSeen: now.Add(-time.Hour), LastScanned: now.Add(-time.Hour),
	}
	if _, err := db.UpsertMessage(ctx, prior); err != nil {
		t.Fatal(err)
	}
	feedback := &Message{
		Account: "test@o2.pl", SourceFolder: "training", CurrentFolder: "INBOX",
		UIDValidity: 2, UID: 2, MessageIDHash: "m", RawSHA256: "same",
		Verdict: "ham", Action: "learn_ham", Status: "rescued", Feedback: "ham",
		FirstSeen: now, LastScanned: now,
	}
	if _, err := db.UpsertMessage(ctx, feedback); err != nil {
		t.Fatal(err)
	}
	falseSpam, falseHam, err := db.MisclassificationsSince(ctx, "test@o2.pl", now.Add(-24*time.Hour))
	if err != nil || falseSpam != 1 || falseHam != 0 {
		t.Fatalf("falseSpam=%d falseHam=%d err=%v", falseSpam, falseHam, err)
	}
}

func TestArchivedPageKeepsOlderCopiesReachableAndScopesAccount(t *testing.T) {
	db, err := Open(filepath.Join(t.TempDir(), "state.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	ctx := context.Background()
	base := time.Now().UTC().Add(-time.Hour)
	for i, raw := range []string{"oldest", "middle", "newest"} {
		if _, err := db.UpsertMessage(ctx, &Message{
			Account: "test@o2.pl", SourceFolder: "inbox", CurrentFolder: "AI-Do-sprawdzenia",
			UIDValidity: 1, UID: uint32(i + 1), MessageIDHash: raw, RawSHA256: raw,
			Verdict: "uncertain", Action: "review", Status: "review",
			FirstSeen:   base.Add(time.Duration(i) * time.Minute),
			LastScanned: base.Add(time.Duration(i) * time.Minute),
			ArchivePath: filepath.Join("/private/archive", raw+".eml.age"),
		}); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := db.UpsertMessage(ctx, &Message{
		Account: "other@o2.pl", SourceFolder: "inbox", CurrentFolder: "AI-Do-sprawdzenia",
		UIDValidity: 1, UID: 1, MessageIDHash: "other", RawSHA256: "other",
		Verdict: "uncertain", Action: "review", Status: "review",
		FirstSeen: base.Add(10 * time.Minute), LastScanned: base.Add(10 * time.Minute),
		ArchivePath: "/private/archive/other.eml.age",
	}); err != nil {
		t.Fatal(err)
	}

	first, err := db.ArchivedPage(ctx, "test@o2.pl", 2, 0)
	if err != nil || len(first) != 2 ||
		first[0].RawSHA256 != "newest" || first[1].RawSHA256 != "middle" {
		t.Fatalf("first page=%#v err=%v", first, err)
	}
	second, err := db.ArchivedPage(ctx, "test@o2.pl", 2, 2)
	if err != nil || len(second) != 1 || second[0].RawSHA256 != "oldest" {
		t.Fatalf("second page=%#v err=%v", second, err)
	}
}

func TestIntegrityCheckAndTechnicalHistoryRetention(t *testing.T) {
	db, err := Open(filepath.Join(t.TempDir(), "state.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	ctx := context.Background()
	if err := db.IntegrityCheck(ctx); err != nil {
		t.Fatal(err)
	}

	now := time.Now().UTC()
	message := &Message{
		Account: "test@o2.pl", SourceFolder: "training", CurrentFolder: "INBOX",
		UIDValidity: 1, UID: 1, MessageIDHash: "mid", RawSHA256: "raw",
		Verdict: "ham", Action: "learn_ham", Status: "rescued", Feedback: "ham",
		FirstSeen: now.AddDate(-1, 0, 0), LastScanned: now,
	}
	id, err := db.UpsertMessage(ctx, message)
	if err != nil {
		t.Fatal(err)
	}
	old := now.AddDate(0, 0, -200).Format(time.RFC3339Nano)
	recent := now.AddDate(0, 0, -10).Format(time.RFC3339Nano)
	if _, err := db.sql.ExecContext(ctx, `
INSERT INTO events(message_id,at,action,detail) VALUES(?,?,?,?),(?,?,?,?)`,
		id, old, "old", "", id, recent, "recent", ""); err != nil {
		t.Fatal(err)
	}
	if _, err := db.sql.ExecContext(ctx, `
INSERT INTO runs(started_at,finished_at,command,dry_run,status)
VALUES(?,?,?,?,?),(?,?,?,?,?)`,
		old, old, "run", 0, "ok", recent, recent, "run", 0, "ok"); err != nil {
		t.Fatal(err)
	}

	if err := db.PruneTechnicalHistory(ctx, now.AddDate(0, 0, -180)); err != nil {
		t.Fatal(err)
	}
	var events, runs, messages, feedback int
	if err := db.sql.QueryRowContext(ctx, `SELECT COUNT(*) FROM events`).Scan(&events); err != nil {
		t.Fatal(err)
	}
	if err := db.sql.QueryRowContext(ctx, `SELECT COUNT(*) FROM runs`).Scan(&runs); err != nil {
		t.Fatal(err)
	}
	if err := db.sql.QueryRowContext(ctx, `SELECT COUNT(*) FROM messages`).Scan(&messages); err != nil {
		t.Fatal(err)
	}
	if err := db.sql.QueryRowContext(ctx, `SELECT COUNT(*) FROM messages WHERE feedback='ham'`).Scan(&feedback); err != nil {
		t.Fatal(err)
	}
	if events != 1 || runs != 1 || messages != 1 || feedback != 1 {
		t.Fatalf("retention touched durable message state: events=%d runs=%d messages=%d feedback=%d", events, runs, messages, feedback)
	}
}

func TestSummaryPropagatesAuxiliaryQueryFailure(t *testing.T) {
	db, err := Open(filepath.Join(t.TempDir(), "state.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	ctx := context.Background()
	if _, err := db.BeginRun(ctx, "run", false); err != nil {
		t.Fatal(err)
	}
	if _, err := db.sql.ExecContext(ctx, `DROP TABLE messages`); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Summary(ctx, time.Now().Add(-time.Hour)); err == nil {
		t.Fatal("summary hid an auxiliary database error")
	}
}

func TestLastRunTimesSeparatesAttemptFromSuccess(t *testing.T) {
	db, err := Open(filepath.Join(t.TempDir(), "state.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	ctx := context.Background()
	failed, err := db.BeginRun(ctx, "run", false)
	if err != nil {
		t.Fatal(err)
	}
	if err := db.FinishRun(ctx, failed, errors.New("simulated")); err != nil {
		t.Fatal(err)
	}
	attempt, success, err := db.LastRunTimes(ctx)
	if err != nil || attempt == nil || success != nil {
		t.Fatalf("unexpected failed-run times: attempt=%v success=%v err=%v", attempt, success, err)
	}
	ok, err := db.BeginRun(ctx, "run", false)
	if err != nil {
		t.Fatal(err)
	}
	if err := db.FinishRun(ctx, ok, nil); err != nil {
		t.Fatal(err)
	}
	attempt, success, err = db.LastRunTimes(ctx)
	if err != nil || attempt == nil || success == nil {
		t.Fatalf("unexpected successful-run times: attempt=%v success=%v err=%v", attempt, success, err)
	}
}

func TestArchiveFilterRunsBeforePaginationAndStaysWithinAccount(t *testing.T) {
	db, err := Open(filepath.Join(t.TempDir(), "archive.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	ctx := context.Background()
	now := time.Now().UTC()
	for i := 0; i < 15; i++ {
		account, status := "mine@o2.pl", "quarantined"
		if i%3 == 0 {
			status = "review"
		}
		if i == 14 {
			account = "other@o2.pl"
			status = "review"
		}
		_, err := db.UpsertMessage(ctx, &Message{
			Account: account, SourceFolder: "INBOX", CurrentFolder: "archive", UIDValidity: 1, UID: uint32(i + 1),
			RawSHA256: fmt.Sprintf("hash-%d", i), Verdict: "spam", Status: status,
			FirstSeen: now.Add(time.Duration(i) * time.Minute), LastScanned: now, ArchivePath: fmt.Sprintf("copy-%d.age", i),
		})
		if err != nil {
			t.Fatal(err)
		}
	}
	first, err := db.ArchivedPageFiltered(ctx, "mine@o2.pl", 2, 0, "review")
	if err != nil {
		t.Fatal(err)
	}
	second, err := db.ArchivedPageFiltered(ctx, "mine@o2.pl", 2, 2, "review")
	if err != nil {
		t.Fatal(err)
	}
	if len(first) != 2 || len(second) != 2 || first[0].UID != 13 || first[1].UID != 10 || second[0].UID != 7 || second[1].UID != 4 {
		t.Fatalf("filter or pagination failed: %+v / %+v", first, second)
	}
	for _, item := range append(first, second...) {
		if item.Account != "mine@o2.pl" || item.Status != "review" {
			t.Fatalf("foreign result: %+v", item)
		}
	}
}

func TestArchiveDateRangeBeforePagination(t *testing.T) {
	db, err := Open(filepath.Join(t.TempDir(), "archive.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	ctx := context.Background()
	start := time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC)
	for i := 0; i < 20; i++ {
		account, status := "mine@o2.pl", "review"
		if i == 7 {
			account = "other@o2.pl"
		}
		if i == 8 {
			status = "quarantined"
		}
		_, err := db.UpsertMessage(ctx, &Message{Account: account, SourceFolder: "INBOX", CurrentFolder: "archive", UIDValidity: 1, UID: uint32(i + 1), RawSHA256: fmt.Sprintf("date-%d", i), Verdict: "spam", Status: status, FirstSeen: start.Add(time.Duration(i) * time.Hour), LastScanned: start, ArchivePath: fmt.Sprintf("copy-%d.age", i)})
		if err != nil {
			t.Fatal(err)
		}
	}
	from, until := start.Add(5*time.Hour), start.Add(10*time.Hour)
	first, err := db.ArchivedPageInRange(ctx, "mine@o2.pl", 2, 0, "review", from, until)
	if err != nil {
		t.Fatal(err)
	}
	second, err := db.ArchivedPageInRange(ctx, "mine@o2.pl", 2, 2, "review", from, until)
	if err != nil {
		t.Fatal(err)
	}
	if len(first) != 2 || len(second) != 1 || first[0].UID != 10 || first[1].UID != 7 || second[0].UID != 6 {
		t.Fatalf("unexpected filtered pages: %+v / %+v", first, second)
	}
	empty, err := db.ArchivedPageInRange(ctx, "mine@o2.pl", 10, 0, "", start.AddDate(0, 0, 1), start.AddDate(0, 0, 2))
	if err != nil || len(empty) != 0 {
		t.Fatalf("expected empty range: %+v %v", empty, err)
	}
}
