# Mail Guardian: design, CX and verification

## Product constraints

- Native macOS SwiftUI application; keep native keyboard controls, system
  accessibility, light/dark appearance and scrolling at smaller window sizes.
- Distinguish service health, automation schedule, inbox observation, active
  sorting and permanent deletion. A healthy service is not permission to move mail.
- `protect` leaves INBOX unchanged automatically, but moves server-SPAM messages
  to review and processes explicit training corrections. Do not say this mode
  never moves any mail. See `internal/engine/engine.go`, `decide` and training.
- Backend safety checks remain authoritative. Presentation data is read-only;
  activation still requires the existing typed confirmation and backend recheck.
- Do not expose mail bodies, HTML, links or attachments in the GUI. Headers are
  decrypted only on explicit preview and retained only in the archive view.

## Source map

- `macos/Sources/O2MailGuardianApp/O2MailGuardianApp.swift`: JSON bridge, model,
  app lifecycle, configuration wizard and menu bar.
- `GuardianDesign.swift` in the same directory: shared visual components,
  navigation, dashboard, service/mode presentation and operation feedback.
- `GuardianWorkflows.swift`: archive, corrections, settings and contextual help.
- `cmd/guardian/presentation.go`: observation/readiness and exact scan counts.
  Never substitute the daily aggregate for a particular dry-run result.
- `internal/store/store.go`: account-scoped archive filtering before pagination.
- `docs/GUI-I-PIERWSZE-KROKI.md`: current user journeys and preview instructions.

## Verification routes

- `make check` is the project verification entry point. Override `GO` with the
  path to a suitable compiler if Go is not on PATH; `go.mod` pins the toolchain.
  Deployment config tests explicitly report when Docker Compose is unavailable.
- `scripts/test-swift.sh` uses a local mock and configures the standalone Apple
  Command Line Tools Testing framework. Swift tests sharing ProcessController
  belong to the same serialized suite, including tests in extensions.
- `scripts/preview-gui.sh SCENARIO [dark]` builds an isolated `.app` with its
  own embedded mock. A bare SwiftPM executable is not reliably discoverable by
  native UI tools; use the returned bundle path. Preview mode does not connect to
  IMAP, Keychain, Rspamd or launchd. It starts with fresh demonstration state.
- Verify observation, manual, active, error, readiness, setup and archive flows.
  Changing a selected copy/category/page must invalidate the previous preview.
- If the native UI transport fails, reconnect once and reset the tool session.
  If it still fails, continue process/model tests and report the visual QA limit;
  do not substitute real-account actions for mock-based UI verification.
