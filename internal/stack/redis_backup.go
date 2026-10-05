package stack

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type redisBackupInfo struct {
	Spam    uint64    `json:"spam_revision"`
	Ham     uint64    `json:"ham_revision"`
	SHA256  string    `json:"sha256"`
	Created time.Time `json:"created_at"`
}

func validateRedisRDB(data []byte) error {
	if len(data) < 18 || !bytes.HasPrefix(data, []byte("REDIS")) || data[len(data)-9] != 0xff {
		return errors.New("nieprawidłowy zrzut Redis")
	}
	var table [256]uint64
	for i := range table {
		v := uint64(i)
		for n := 0; n < 8; n++ {
			if v&1 != 0 {
				v = (v >> 1) ^ 0x95ac9329ac4bc9b5
			} else {
				v >>= 1
			}
		}
		table[i] = v
	}
	var checksum uint64
	for _, b := range data[:len(data)-8] {
		checksum = table[byte(checksum)^b] ^ (checksum >> 8)
	}
	if checksum != binary.LittleEndian.Uint64(data[len(data)-8:]) {
		return errors.New("błędna suma kontrolna kopii Redis")
	}
	return nil
}

func redisRDBPayload(data []byte) ([]byte, error) {
	if err := validateRedisRDB(data); err == nil {
		return data, nil
	}
	// redis-cli cannot truncate stdout, so diskless --rdb - may retain the
	// 40-byte replication EOF marker. Strip it only if the RDB checksum proves
	// the exact preceding bytes are a complete, uncorrupted RDB.
	if len(data) >= 58 {
		marker := data[len(data)-40:]
		if _, err := hex.DecodeString(string(marker)); err == nil {
			payload := data[:len(data)-40]
			if err := validateRedisRDB(payload); err == nil {
				return payload, nil
			}
		}
	}
	return nil, errors.New("otrzymano uszkodzoną lub niepełną kopię Redis")
}

type rdbBuffer struct{ bytes.Buffer }

func (b *rdbBuffer) Write(p []byte) (int, error) {
	if b.Len()+len(p) > 128<<20 {
		return 0, errors.New("kopia Redis przekracza 128 MiB")
	}
	return b.Buffer.Write(p)
}

// BackupRedis preserves two checksummed generations outside the VM. A model
// rollback cannot replace the last good generation. Paired metadata and RDB
// are published as one directory, so a crash cannot mix their contents.
func (m Manager) BackupRedis(dataDir string, spam, ham uint64) error {
	root := filepath.Join(dataDir, "redis-backup")
	current, previous := filepath.Join(root, "current"), filepath.Join(root, "previous")
	baseline := current
	if _, err := os.Stat(current); os.IsNotExist(err) {
		baseline = previous
	}
	if meta, err := os.ReadFile(filepath.Join(baseline, "metadata.json")); err == nil {
		var old redisBackupInfo
		if err := json.Unmarshal(meta, &old); err != nil {
			return err
		}
		data, err := os.ReadFile(filepath.Join(baseline, "model.rdb"))
		if err != nil {
			return err
		}
		if err := validateRedisRDB(data); err != nil {
			return err
		}
		hash := sha256.Sum256(data)
		if hex.EncodeToString(hash[:]) != old.SHA256 {
			return errors.New("kopia Redis nie zgadza się z metadanymi")
		}
		if spam < old.Spam || ham < old.Ham {
			return errors.New("model Bayesa cofnął się; poprzednia kopia została zachowana")
		}
		if spam == old.Spam && ham == old.Ham && time.Since(old.Created) < 12*time.Hour {
			return nil
		}
	} else if !os.IsNotExist(err) {
		return err
	}
	if err := os.MkdirAll(root, 0o700); err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
	defer cancel()
	docker := commandPath("docker")
	if docker == "" {
		return errors.New("brakuje Dockera do zabezpieczenia modelu")
	}
	cmd := stackCommand(ctx, docker, m.dockerComposeArgs("exec", "-T", "redis", "redis-cli", "--rdb", "-")...)
	cmd.Env = append(cmd.Env, "GUARDIAN_RUNTIME_DIR="+m.RuntimeDir)
	var output rdbBuffer
	var diagnostic bytes.Buffer
	cmd.Stdout, cmd.Stderr = &output, &diagnostic
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("eksport modelu Redis: %w (%s)", err, safeOutput(diagnostic.Bytes()))
	}
	payload, err := redisRDBPayload(output.Bytes())
	if err != nil {
		return err
	}
	hash := sha256.Sum256(payload)
	info := redisBackupInfo{Spam: spam, Ham: ham, SHA256: hex.EncodeToString(hash[:]), Created: time.Now().UTC()}
	return publishRedisBackup(root, payload, info)
}

func publishRedisBackup(root string, payload []byte, info redisBackupInfo) error {
	if err := validateRedisRDB(payload); err != nil {
		return err
	}
	hash := sha256.Sum256(payload)
	if info.SHA256 != hex.EncodeToString(hash[:]) {
		return errors.New("metadane nie zgadzają się z kopią Redis")
	}
	current, previous := filepath.Join(root, "current"), filepath.Join(root, "previous")
	meta, _ := json.Marshal(info)
	stage, err := os.MkdirTemp(root, ".stage-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(stage)
	for name, data := range map[string][]byte{"model.rdb": payload, "metadata.json": meta} {
		f, err := os.OpenFile(filepath.Join(stage, name), os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
		if err != nil {
			return err
		}
		_, writeErr := f.Write(data)
		syncErr, closeErr := f.Sync(), f.Close()
		if writeErr != nil {
			return writeErr
		}
		if syncErr != nil {
			return syncErr
		}
		if closeErr != nil {
			return closeErr
		}
	}
	if _, err := os.Stat(current); err == nil {
		if err := os.RemoveAll(previous); err != nil {
			return err
		}
		if err := os.Rename(current, previous); err != nil {
			return err
		}
	}
	if err := os.Rename(stage, current); err != nil {
		return err
	}
	directory, err := os.Open(root)
	if err != nil {
		return err
	}
	defer directory.Close()
	return directory.Sync()
}

func validateRedisPersistence(output string) error {
	fields := map[string]string{}
	for _, line := range strings.Split(output, "\n") {
		key, value, ok := strings.Cut(strings.TrimSpace(line), ":")
		if ok {
			fields[key] = value
		}
	}
	for _, key := range []string{"aof_last_write_status", "rdb_last_bgsave_status"} {
		if fields[key] != "ok" {
			return errors.New("Redis nie potwierdza poprawnego zapisu danych; filtr wymaga sprawdzenia dysku Colimy")
		}
	}
	if fields["aof_enabled"] != "1" {
		return errors.New("dziennik trwałego zapisu Redis jest wyłączony")
	}
	return nil
}

func (m Manager) checkRedisPersistence() error {
	ctx, cancel := context.WithTimeout(context.Background(), shortCommandTimeout)
	defer cancel()
	cmd := stackCommand(ctx, commandPath("docker"), m.dockerComposeArgs("exec", "-T", "redis", "redis-cli", "--raw", "INFO", "persistence")...)
	cmd.Env = append(cmd.Env, "GUARDIAN_RUNTIME_DIR="+m.RuntimeDir)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("kontrola trwałości Redis: %w (%s)", err, safeOutput(output))
	}
	return validateRedisPersistence(string(output))
}
