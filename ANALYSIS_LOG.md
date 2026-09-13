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
- `GuardianModel.perform` returns true only after work and state refresh succeed.
  Use that result for follow-up actions and confirmation dismissal; absence of
  `failure` also occurs on cancellation or a busy-state rejection. Cancellation
  invalidates snapshot trust because earlier steps may already have completed.
- Do not expose mail bodies, HTML, links or attachments in the GUI. Headers are
  decrypted only on explicit preview and retained only in the archive view.

- Dashboard order: status and schedule, user actions, observation progress,
  statistics, diagnostic details. Avoid duplicate observation summaries.
- The corrections journey opens `https://poczta.o2.pl/`; the user selects the
  folder in webmail. Processing corrections is a full scan in the current mode.
- Archive neighbor navigation is confined to the current page and invalidates
  preview/restore state. Date filtering uses inclusive/exclusive RFC3339 instants before backend
  pagination; GUI turns local calendar days into these bounds (including DST).
  Dates refer to `first_seen`, not the message Date header.
- Archive reads discard previous rows/pagination before requesting data and
  retain the requested page for retry. Failed reads must disable pagination;
  empty later pages must offer a return to page one without clearing filters.
  The isolated `archive-error` preview exercises list failure without mail access.

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
  Cached compilers can be found under `~/go/pkg/mod/golang.org/toolchain*/bin/go`.
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

## Native UI transport failure

- A closed native pipe during Return in the mock onboarding has coincided with
  `SkyComputerUseService` crash reports (`EXC_BREAKPOINT`, `Array.remove(at:)`).
  Reports live in `~/Library/Logs/DiagnosticReports/SkyComputerUseService-*.ips`.
  Distinguish this tool-service crash from an application crash; do not change
  Guardian behavior merely to conceal a failed UI driver.
- If reconnecting and resetting the CUA session fail, interactive verification
  requires restored native transport. Do not repeat the same submission blindly
  or switch to real-account operations. Read the current wizard step first.
- Crash signature confirmed in the 2026-09-12 diagnostic report: Codex Computer
  Use service build 26.902.1000968 on macOS 26.6.2, `EXC_BREAKPOINT` / `SIGTRAP`,
  faulting thread in Swift `Array.remove(at:)` while mapping accessibility data.
  The service is external to this repository; changing Guardian's submission
  behavior would not repair that process. A later CUA read and screenshot of the
  mock dashboard succeeded, so transport may recover without the defect being
  fixed. Continue the mock audit from observed state and mark any interrupted
  action unconfirmed until its resulting UI state is observed.
- Updating the Codex host to 26.908.40834 did not resolve the mock onboarding
  Return failure. The bundled CUA service remained at 26.902.1000968; a fresh
  isolated wizard with fictional credentials crashed that service on Return
  with the same `EXC_BREAKPOINT` / `Array.remove(at:)` signature. Resetting the
  CUA session did not restore a readable wizard. Avoid repeated submissions;
  a vendor fix or a separately authorized alternate UI driver is needed.

## Binary distribution and installer verification

- `make package GO=...` builds the arm64 Go backend and Swift release app,
  ad-hoc signs them, checks Mach-O minimum OS and self-tests, then packages
  source plus `.payload/prebuilt` with RELEASE-MANIFEST and a ZIP checksum.
- `.payload` is always a binary distribution; a missing marker/manifest must
  fail closed, never fall back to installing compilers. The source checkout
  retains its original build route. Checksums detect corruption, not origin.
- `install-lock.sh` shares a per-user lock between wrapper and child core.
  Do not delete stale locks automatically or truncate logs before acquiring it.
- Core results are success/attention/failed. Missing completion is a failure.
  Preserve backups if any rollback step fails; do not claim recovery from exit
  status alone. Resume services only after successful file recovery. Attention
  includes failed doctor, service resume or app launch.
- `test-install-prebuilt.sh` runs real staging/signature/self-tests with isolated
  HOME and a narrow external-effects driver; it never operates real services,
  Keychain or IMAP. Full live Docker and older-macOS claims need separate proof.
