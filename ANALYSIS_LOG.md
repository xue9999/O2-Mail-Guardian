# Mail Guardian: design, CX and verification

## Product constraints

- Native macOS SwiftUI application; keep native keyboard controls, system
  accessibility, light/dark appearance and scrolling at smaller window sizes.
- Distinguish service health, automation schedule, inbox observation, active
  sorting and permanent deletion. A healthy service is not permission to move mail.
- `protect` leaves INBOX unchanged automatically, but moves server-SPAM messages
  to review and processes explicit training corrections. Do not say this mode
  never moves any mail. See `internal/engine/engine.go`, `decide` and training.
- On the tested o2 account, native IMAP MOVE succeeded without a destination UID.
  `MoveWithRaw` records destination UIDNEXT before the move and, if COPYUID is
  absent, confirms one exact raw hash among newly assigned destination UIDs.
  An ambiguous match remains pending. A completed run or accepted Rspamd
  correction alone does not prove the destination move was reconciled.
  Confirm exact
  source and destination state before restoring automation; user moves from
  review into training or Trash can change the destination before reconciliation.
- `tools/inspect_pending_mail.go` is a local aggregate IMAP comparison and
  narrowly scoped repair helper. `--deep` is read-only, `--apply` finalizes
  unique raw-hash matches in the expected destination, and `--find-other`
  searches all IMAP folders by exact size then full hash. `--ack-trash` records
  a uniquely verified external move to Trash without moving mail. Back up the
  SQLite database and keep automation off before any repair option.
- `--resolve-destination` uses size-narrowed searches across all IMAP folders
  to finalize a unique complete-hash match in the intended destination. Unlike
  ordinary diagnostic searches, any failed candidate read or folder search
  aborts this repair. It also rejects shared destination ownership and rechecks
  the full content before writing; it performs no IMAP moves. This route avoids
  reading unrelated damaged legacy messages during a full-folder investigation.
- On the tested o2 account, a small number of stable UIDs can be returned by
  SEARCH while the server replies `NO Fetch failed` to ENVELOPE and BODY FETCH.
  UID, size, flags and internal date remain readable. Retrying the whole scan
  or local installation repair cannot supply missing message content. Leave
  such messages on the server, report the server-side FETCH failure, and do not
  treat the rest of the successful scan as proof those messages were classified.
- Re-probe previously unreadable UIDs before diagnosing a persistent server
  failure: o2 FETCH errors can be transient. Keep read-only probes separate
  from classification and confirm a complete dry-run afterward.
- A pending review move may already be in a user training folder. Verify its
  full raw hash across folders first, then let normal training process the
  correction: `SupersedeOtherCopies` retires the obsolete pending record and
  `MoveWithRaw` confirms the new destination. Do not mark the training location
  processed manually, since that would skip the user's correction.
- Activation quality includes zero-tolerance historical conditions within the
  current protection period. When false rescue or unexplained-spam counts are
  nonzero, the remaining-day counter alone cannot make active mode eligible;
  do not reset the period merely to hide those observations.
- Dashboard service health follows the latest completed live run and current
  pending moves; daily historical error totals remain visible as history but
  do not make a later clean run appear broken.
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

- GitHub workflow `.github/workflows/check.yml` runs `make check` and packages
  on Apple Silicon macOS for changes, including vulnerability checks. Release
  only the tested commit and install the same verified package locally.
- Automatic pending-move reconciliation uses exact RFC822 size search when
  available, followed by complete content hashes on source and destination.
  Failed searches or candidate fetches do not prove absence. Duplicate matches
  stay ambiguous, and completed moves are never repeated. This bypasses
  unrelated broken server envelopes without weakening move confirmation.
- Current health reads the latest completed live run; starting a retry must
  not hide the previous error. Snapshot rotation retains the previous baseline
  even when publication is interrupted between directory renames.

- Rspamd 4.1.2 uses HTTP 204 when classifier learning conditions deny a
  message (including token limits); an empty response is not successful Bayes
  learning. `ErrLearningSkipped` retains durable `feedback_intent`, records
  `learn_skipped`, and completes the user's destination move without setting
  `feedback` or increasing learned totals. Exact-content feedback guards and
  the ham purge veto still apply. Generic empty 200 replies and other errors
  remain failures. Never lower global token safeguards to silence one retry.
- Runs containing individual operation errors have status `error` even when
  folder traversal finishes. `service-run` propagates these errors to launchd
  and its heartbeat; CLI advice uses the latest live outcome while preserving
  historical daily error counts.

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

## Live macOS installation route

- Native macOS GUI processes can inherit only system PATH entries. Absolute
  discovery of Colima alone is insufficient because it launches `limactl`.
  Use `stackCommand` for every stack subprocess, including status and nested
  Docker helpers; preserve runtime variables and supply Homebrew dependency
  directories. Verify the native repair button and a minimal-PATH deep check.

- A healthy Redis PING does not prove persistence. Require AOF enabled,
  successful last AOF write and successful RDB save in stack startup and deep
  checks. After live scans keep two CRC-checked RDB generations with paired
  model revisions in the host data directory `redis-backup`; never replace a
  good generation with lower model revisions.
- Compare model rollback with the stored highest observed Rspamd revisions.
  Distinct raw corrections can be statistical duplicates; their SQL count is
  only a conservative fallback when no observed baseline exists.
- For Colima guest I/O errors, stop scans and preserve SQLite, binaries and
  both offline VM disks before repair. If Redis still serves memory, export it
  before stopping the VM using `tools/recover_redis_snapshot.py` and a private
  loopback SSH forward. Validate RDB CRC and `redis-check-rdb` before loading.
  Keep damaged AOF files; regenerate AOF from the validated recovered RDB in an
  isolated container without resetting training.
- `tools/check_colima_disk.py` checks the GPT filesystem partition in a sparse
  regular file because macOS raw-device e2fsck can fail at its final write.
  Repairs require an offline original and a distinct preserved disk backup;
  copy changes back only after an independent clean read-only filesystem check.
  Require VM restart, preserved model revisions and a clean live run before
  restoring scheduling.

- Install the verified prebuilt ZIP; source installation also needs Go and a
  working SwiftUI build toolchain. Keep release checksum, manifest and binary
  self-tests before changing the active installation.
- Rspamd 4.1.2 `rspamadm pw` does not take its password directly from stdin.
  Send it through stdin to a one-use, network-isolated container shell; never
  place the secret in a host command argument or installation log.
- The pinned Redis entrypoint needs privileges to switch from root. Run the
  container directly as `redis` so `cap_drop: ALL` remains in force; confirm
  `/data` is writable and the Redis healthcheck passes.
- Rspamd `/ping` may return `pong` with CRLF. Host shell probes must strip the
  terminal carriage return before comparison. Confirm both published loopback
  ports and `rspamadm configtest` before reporting the stack ready.
- An installed app with no account configuration is not protecting mail.
  Complete the GUI's IMAP probe and dry-run before enabling a scan schedule.
- The installed Swift GUI invokes `~/.local/bin/o2-mail-guardian/guardian`.
  A backend-only repair can use an atomic replacement of that binary after Go
  tests, vet, ad-hoc signature verification and self-test. Preserve a SQLite
  backup and the previous binary, stop the scanner during repair, and validate
  a live `service-run` with zero errors and zero pending moves before restoring
  its schedule. `doctor` and a successful dry-run alone do not prove live moves.
- The shipped 0.5.0 GUI encodes setup commit fields as `spamFolder` and
  `acceptExistingTraining`, while the Go API originally required snake_case.
  Keep strict unknown-field rejection but accept both spellings for this
  release; future Swift builds should use `.convertToSnakeCase`. Verify the
  actual GUI commit and a subsequent dry-run before calling onboarding done.
