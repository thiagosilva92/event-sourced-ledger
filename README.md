# event-sourced-ledger

An offline-first shared household ledger for Android and iOS, built to
demonstrate **event sourcing**, **CQRS** and deterministic multi-device
synchronisation in a Flutter application.

> Fictional domain. No code, data model or business logic is derived from any
> employer's product — it is written from scratch.

## The problem

Several people in a household record shared expenses from different phones.
Connectivity is unreliable. Two people may edit the same thing while both are
offline. The app must:

- work fully offline — the UI never waits on the network;
- never silently lose a write when devices reconcile;
- keep every account balance auditable down to the individual entry.

## Why event sourcing

Every change is captured as an immutable domain event appended to a local log
(`AccountOpened`, `TransactionRecorded`, `TransactionVoided`, ...). Balances and
reports are **projections** — pure folds over that log.

This makes multi-device merge tractable: synchronisation is a merge-sort of two
append-only event streams, de-duplicated by event id and ordered by a
[Hybrid Logical Clock](https://cse.buffalo.edu/tech-reports/2014-04.pdf). There
are no destructive updates to reconcile. Genuine business-rule conflicts (an
account closed on one device, used on another) are resolved with explicit
**compensating events** rather than by overwriting state.

## Architecture

```
presentation  ── Riverpod, reads projections only
application   ── command handlers (write) · query services (read)   ← CQRS seam
domain        ── aggregates, domain events, invariants (pure Dart)
data          ── Drift event store, projection tables, sync client
```

- **Write path:** `Command` → aggregate rehydrated from its events → invariants
  checked → new events appended to the log and the outbox.
- **Read path:** projections materialised into Drift tables, exposed to the UI
  as reactive streams. The write model and read model never share types.
- **Money** is an integer-minor-unit value object with an explicit currency —
  never `double`. Double-entry transactions must balance to zero.
- **Concurrency (planned):** rebuilding projections from a long event log will
  run in a dedicated `Isolate` so the UI thread never blocks — Dart has no
  shared-memory threads; isolates communicate by message passing. Not wired up
  yet: `ProjectionRunner` currently folds on the caller's isolate. See
  [docs/concurrency.md](docs/concurrency.md) for the design and why isolates
  are the answer to "virtual threads" here.

## Status

Work in progress. See commit history for the build order: foundations
(`Money`, Hybrid Logical Clock, event store) first, then features.

## Running

```bash
flutter pub get
dart run build_runner build
flutter test
flutter run
```

Requires Flutter 3.47+ / Dart 3.13+.
