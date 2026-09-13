# Changelog

Notable changes to this project, loosely following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). There's been one
continuous line of development so far, no prior releases to diff against —
see `git log` for the exact commit-by-commit history this summarizes.

## [1.0.0] - 2026-09-13

### Added

- Core value types: `Money` (exact integer-minor-unit arithmetic, no
  floating point), `Currency`, a Hybrid Logical Clock for causal event
  ordering across devices.
- Event sourcing / CQRS core: `DomainEvent`, `EventRegistry`, `Aggregate`,
  `Projection` — see [ADR 0001](docs/adr/0001-event-sourcing-and-cqrs.md).
- `EventStore`: an `InMemoryEventStore` and a Drift/SQLite-backed
  `DriftEventStore`, both verified against one shared behavioral contract
  — see [ADR 0003](docs/adr/0003-drift-sqlite-local-store.md).
- `accounts` and `transactions` features (domain, application, and
  read-model layers), and the Riverpod presentation layer: accounts list,
  open-account, and record-transaction screens — see
  [ADR 0004](docs/adr/0004-riverpod-projections-only-presentation.md).
- Device-to-device sync (`SyncService`, push then pull, sequence-cursor
  based — see
  [ADR 0002](docs/adr/0002-sequence-cursors-not-hlc-for-sync.md)), first
  against an in-process `FakeSyncTransport`, later against a real
  `HttpSyncTransport` speaking to
  [`ledger-sync-server`](https://github.com/thiagosilva92/ledger-sync-server)
  — see [ADR 0007](docs/adr/0007-sync-server-separate-repository.md).
- Isolate-offloaded JSON decode for large event batches (projection
  rebuild and incoming sync batches), above a measured threshold — see
  [ADR 0005](docs/adr/0005-isolate-offload-threshold.md) and
  `docs/concurrency.md`.
- Automated architecture/layering enforcement via a regex-based import
  scan — see
  [ADR 0006](docs/adr/0006-regex-import-scan-architecture-test.md).
- Formal performance benchmarks (`package:benchmark_harness`) with a
  committed baseline and a warn-only regression check in CI.
- A real schema migration, and a persisted device node id surviving app
  restarts.
- Accessibility: semantic labels and a custom action for the account
  list's long-press-to-close gesture, verified against Flutter's own
  guideline checks (tap target size, labeling, contrast).
- Localization: English and Portuguese, generated from `lib/l10n/*.arb`,
  verified with a real locale-switch test.
- Signed Android release builds (a real upload keystore, not the debug
  key) — see [ADR 0008](docs/adr/0008-signed-release-builds.md).
- Crash reporting via Firebase Crashlytics — see
  [ADR 0009](docs/adr/0009-firebase-crashlytics.md).
- Dependabot (pub + GitHub Actions ecosystems); CodeQL was evaluated and
  found inapplicable (it doesn't support Dart) — documented rather than
  silently skipped.
- CI: GitHub Actions (analyze, format check, test with coverage,
  Codecov), a separate `benchmark` job gated to pushes on `main`, and a
  `release-build` job producing a verified-signed release APK artifact.
- 7 Architecture Decision Records (`docs/adr/`) documenting the
  non-obvious calls behind the codebase, retrospectively.

### Fixed

- A leftover debug tool (`lib/main_debug_smoke_test.dart`) shared the
  same on-device database as the real app, leaving unrecognized events
  that crashed projection rebuild — found only by running on real
  hardware, not by any test. Deleted the tool entirely.
- A form (`RecordTransactionPage`) overflowed once the on-screen keyboard
  opened on a real device — no widget test's viewport ever shrinks the
  way a real keyboard does. Fixed by wrapping the form in a
  `SingleChildScrollView`.
