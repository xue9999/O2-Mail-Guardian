package main

import (
	"context"
	"time"

	"github.com/o2-mail-guardian/guardian/internal/config"
	"github.com/o2-mail-guardian/guardian/internal/store"
)

// Read-only presentation of the existing activation rules. modeCommand and
// the engine remain authoritative and recheck every rule before moving mail.
type apiProtection struct {
	RequiredDays   int    `json:"required_days"`
	RemainingDays  int    `json:"remaining_days"`
	PeriodComplete bool   `json:"period_complete"`
	QualityReady   bool   `json:"quality_ready"`
	Ready          bool   `json:"ready"`
	Message        string `json:"message"`
}

func protectionProgress(cfg config.Config, db *store.DB, now time.Time) *apiProtection {
	p := &apiProtection{RequiredDays: cfg.Safety.ProtectDays, RemainingDays: cfg.Safety.ProtectDays,
		Message: "Nie można jeszcze potwierdzić gotowości. Sprawdź i napraw ochronę."}
	ctx := context.Background()
	installed, err := db.GetSetting(ctx, "installed_at")
	if err != nil {
		return p
	}
	start, err := time.Parse(time.RFC3339, installed)
	if err != nil || start.After(now) {
		return p
	}
	reset, err := db.GetSetting(ctx, "protect_since")
	if err != nil {
		return p
	}
	if reset != "" {
		value, err := time.Parse(time.RFC3339, reset)
		if err != nil || value.Before(start) || value.After(now) {
			return p
		}
		start = value
	}
	remaining := start.Add(time.Duration(cfg.Safety.ProtectDays) * 24 * time.Hour).Sub(now)
	p.RemainingDays = max(0, int((remaining+24*time.Hour-1)/(24*time.Hour)))
	p.PeriodComplete = remaining <= 0
	quality, err := db.ActivationQualityUntil(ctx, cfg.Account.Email, start, now)
	if err != nil {
		return p
	}
	p.QualityReady = quality.Ready()
	p.Ready = p.PeriodComplete && p.QualityReady
	switch {
	case p.Ready:
		p.Message = "Warunki spełnione. Możesz włączyć przenoszenie spamu z Odebranych do kwarantanny."
	case quality.SpamFeedback == 0:
		p.Message = "Oznacz pomyłki w folderach nauki, aby Guardian mógł sprawdzić trafność swoich decyzji."
	case !p.QualityReady:
		p.Message = "Korekty wskazują, że filtr wymaga dalszej nauki. Przenoszenie z Odebranych pozostaje wyłączone."
	default:
		p.Message = "Jakość decyzji potwierdzona. Poczekaj do końca okresu obserwacji."
	}
	return p
}

// Only aggregate counts leave the backend. Headers, identifiers and message
// contents are deliberately absent, including for the initial dry-run.
func apiRunResult(run *store.Run, err error) map[string]any {
	result := map[string]any{"completed": err == nil}
	if err == nil && run != nil {
		result["summary"] = map[string]any{
			"dry_run": run.DryRun, "scanned": run.Scanned, "kept": run.Kept,
			"rescued": run.Rescued, "quarantined": run.Quarantined,
			"review": run.Review, "errors": run.Errors,
		}
	}
	return result
}
