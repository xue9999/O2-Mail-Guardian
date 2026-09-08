package imapmail

import (
	"errors"
	"testing"
)

func TestSafeMoveSupported(t *testing.T) {
	tests := []struct {
		name string
		caps Capabilities
		want bool
	}{
		{
			name: "UIDPLUS alone is rejected",
			caps: Capabilities{UIDPlus: true},
			want: false,
		},
		{
			name: "MOVE is accepted",
			caps: Capabilities{Move: true},
			want: true,
		},
		{
			name: "IMAP4rev2 is accepted",
			caps: Capabilities{IMAP4rev2: true},
			want: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := safeMoveSupported(tt.caps); got != tt.want {
				t.Fatalf("safeMoveSupported(%+v) = %t, want %t", tt.caps, got, tt.want)
			}
		})
	}
}

func TestRequireUIDValidityFailsClosed(t *testing.T) {
	for _, values := range [][2]uint32{{0, 7}, {7, 0}, {7, 8}} {
		err := requireUIDValidity("INBOX", values[0], values[1])
		if !errors.Is(err, ErrUIDValidityChanged) {
			t.Fatalf("expected UIDVALIDITY error for %v, got %v", values, err)
		}
	}
	if err := requireUIDValidity("INBOX", 7, 7); err != nil {
		t.Fatalf("matching UIDVALIDITY was rejected: %v", err)
	}
}
