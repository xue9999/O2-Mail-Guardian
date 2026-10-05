package stack

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestStackCommandFindsNestedDependenciesWithNativeAppPath(t *testing.T) {
	dir := t.TempDir()
	parent, dependency := filepath.Join(dir, "colima-fixture"), filepath.Join(dir, "limactl-fixture")
	for path, body := range map[string]string{
		parent:     "#!/bin/sh\nlimactl-fixture\n",
		dependency: "#!/bin/sh\nprintf '%s' \"$GUARDIAN_RUNTIME_DIR\"\n",
	} {
		if err := os.WriteFile(path, []byte(body), 0o700); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("PATH", "/usr/bin:/bin:/usr/sbin:/sbin")
	cmd := stackCommand(context.Background(), parent)
	cmd.Env = append(cmd.Env, "GUARDIAN_RUNTIME_DIR=fixture-runtime")
	output, err := cmd.CombinedOutput()
	if err != nil || strings.TrimSpace(string(output)) != "fixture-runtime" {
		t.Fatalf("native app subprocess failed: %v %s", err, output)
	}
	paths := 0
	for _, value := range cmd.Env {
		if strings.HasPrefix(value, "PATH=") {
			paths++
		}
	}
	if paths != 1 {
		t.Fatalf("expected one authoritative PATH, got %d", paths)
	}
}
