# Architecture Decision Records

Short records of the significant, sometimes non-obvious decisions behind
this codebase — what was decided, why, and what alternatives were
rejected and why. Written in [Michael Nygard's ADR format](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions).

These are retrospective: written after the decisions were made and
implemented, not before, since the project's actual practice throughout
has been "prove it works, then document it" (see the main README's
testing philosophy). They exist so a decision's reasoning survives
independently of the person who made it, and so a reviewer doesn't have
to reverse-engineer *why* from the diff alone.

| ADR | Decision |
| --- | --- |
| [0001](0001-event-sourcing-and-cqrs.md) | Event sourcing and CQRS for the ledger domain |
| [0002](0002-sequence-cursors-not-hlc-for-sync.md) | Sequence cursors, not HLC comparison, drive sync |
| [0003](0003-drift-sqlite-local-store.md) | Drift over SQLite as the local, offline-first event store |
| [0004](0004-riverpod-projections-only-presentation.md) | Riverpod, and presentation only ever reads projections |
| [0005](0005-isolate-offload-threshold.md) | Threshold-based isolate offload for CPU-bound decode |
| [0006](0006-regex-import-scan-architecture-test.md) | Enforce layering with a regex-based import scan |
| [0007](0007-sync-server-separate-repository.md) | The sync server is a separate repository |
| [0008](0008-signed-release-builds.md) | Real signed release builds, via `key.properties` locally and secrets in CI |
| [0009](0009-firebase-crashlytics.md) | Firebase Crashlytics for crash reporting, over Sentry |
