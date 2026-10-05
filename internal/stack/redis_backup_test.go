package stack

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// Minimal empty Redis RDB with its independently computed Jones CRC64.
const emptyRDBHex = "524544495330303131ffc0228a8d74389762"

func TestRedisRDBRejectsTruncationAndCorruption(t *testing.T) {
	valid, _ := hex.DecodeString(emptyRDBHex)
	if err := validateRedisRDB(valid); err != nil {
		t.Fatal(err)
	}
	corrupt := append([]byte(nil), valid...)
	corrupt[7] ^= 1
	for _, data := range [][]byte{nil, valid[:len(valid)-1], []byte("Redis backup failed"), corrupt} {
		if err := validateRedisRDB(data); err == nil {
			t.Fatal("invalid model snapshot was accepted")
		}
	}
}

func TestRedisCLIReplicationMarkerRequiresValidPayloadChecksum(t *testing.T) {
	valid, _ := hex.DecodeString(emptyRDBHex)
	stream := append(append([]byte(nil), valid...), []byte(strings.Repeat("a", 40))...)
	payload, err := redisRDBPayload(stream)
	if err != nil || string(payload) != string(valid) {
		t.Fatalf("valid stdout replication stream rejected: %v", err)
	}
	stream[7] ^= 1
	if _, err := redisRDBPayload(stream); err == nil {
		t.Fatal("marker concealed corrupt model")
	}
}

func TestRedisBackupPreservesLastGoodModelOnRollback(t *testing.T) {
	dir := t.TempDir()
	current := filepath.Join(dir, "redis-backup", "current")
	if err := os.MkdirAll(current, 0700); err != nil {
		t.Fatal(err)
	}
	data, _ := hex.DecodeString(emptyRDBHex)
	hash := sha256.Sum256(data)
	info := redisBackupInfo{Spam: 154, Ham: 137, SHA256: hex.EncodeToString(hash[:]), Created: time.Now().UTC()}
	meta, _ := json.Marshal(info)
	if err := os.WriteFile(filepath.Join(current, "model.rdb"), data, 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(current, "metadata.json"), meta, 0600); err != nil {
		t.Fatal(err)
	}
	m := Manager{}
	if err := m.BackupRedis(dir, 154, 137); err != nil {
		t.Fatalf("fresh verified snapshot unexpectedly needs Docker: %v", err)
	}
	for _, revisions := range [][2]uint64{{0, 0}, {153, 137}, {154, 136}} {
		if err := m.BackupRedis(dir, revisions[0], revisions[1]); err == nil || !strings.Contains(err.Error(), "cofnął") {
			t.Fatalf("rollback accepted: %v", err)
		}
	}
	got, _ := os.ReadFile(filepath.Join(current, "model.rdb"))
	if string(got) != string(data) {
		t.Fatal("last good model was changed")
	}
	gotMeta, _ := os.ReadFile(filepath.Join(current, "metadata.json"))
	if string(gotMeta) != string(meta) {
		t.Fatal("last good metadata was changed")
	}
}

func TestRedisPersistenceRequiresWorkingAOFAndRDB(t *testing.T) {
	valid := "aof_enabled:1\r\naof_last_write_status:ok\r\nrdb_last_bgsave_status:ok\r\n"
	if err := validateRedisPersistence(valid); err != nil {
		t.Fatal(err)
	}
	for _, data := range []string{"PONG", strings.Replace(valid, "aof_enabled:1", "aof_enabled:0", 1), strings.Replace(valid, "aof_last_write_status:ok", "aof_last_write_status:err", 1), strings.Replace(valid, "rdb_last_bgsave_status:ok", "rdb_last_bgsave_status:err", 1)} {
		if err := validateRedisPersistence(data); err == nil {
			t.Fatal("unprotected Redis accepted as healthy")
		}
	}
}

func TestRedisBackupRotationAndInterruptedPublicationPreserveBaseline(t *testing.T) {
	dir := t.TempDir()
	root := filepath.Join(dir, "redis-backup")
	if err := os.MkdirAll(root, 0700); err != nil {
		t.Fatal(err)
	}
	data, _ := hex.DecodeString(emptyRDBHex)
	hash := sha256.Sum256(data)
	for _, revision := range []uint64{1, 2, 3} {
		info := redisBackupInfo{Spam: revision, Ham: revision, SHA256: hex.EncodeToString(hash[:]), Created: time.Now().UTC()}
		if err := publishRedisBackup(root, data, info); err != nil {
			t.Fatal(err)
		}
	}
	for name, revision := range map[string]uint64{"current": 3, "previous": 2} {
		meta, err := os.ReadFile(filepath.Join(root, name, "metadata.json"))
		if err != nil {
			t.Fatal(err)
		}
		var info redisBackupInfo
		if err := json.Unmarshal(meta, &info); err != nil || info.Spam != revision {
			t.Fatalf("incorrect %s generation: %s %v", name, meta, err)
		}
		stat, err := os.Stat(filepath.Join(root, name, "model.rdb"))
		if err != nil || stat.Mode().Perm() != 0600 {
			t.Fatalf("snapshot permissions: %v %v", stat, err)
		}
	}
	// A crash between current -> previous and stage -> current still retains
	// the rollback guard. It cannot replace the model with an empty baseline.
	if err := os.RemoveAll(filepath.Join(root, "previous")); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(filepath.Join(root, "current"), filepath.Join(root, "previous")); err != nil {
		t.Fatal(err)
	}
	if err := (Manager{}).BackupRedis(dir, 0, 0); err == nil {
		t.Fatal("interrupted publication lost its rollback guard")
	}
}
