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
- **Read path (partly built):** the event log itself is persisted in SQLite via
  Drift (`DriftEventStore`, tested against the same behavioural contract as
  the in-memory store used elsewhere in tests). Projection *tables* — the
  materialised, query-ready read models the UI will actually watch — aren't
  built yet; today `ProjectionRunner` folds the log into in-memory state. The
  write model and read model will never share types.
- **Money** is an integer-minor-unit value object with an explicit currency —
  never `double`. Double-entry transactions must balance to zero.
- **Concurrency (planned):** rebuilding projections from a long event log will
  run in a dedicated `Isolate` so the UI thread never blocks — Dart has no
  shared-memory threads; isolates communicate by message passing. Not wired up
  yet: `ProjectionRunner` currently folds on the caller's isolate. See
  [docs/concurrency.md](docs/concurrency.md) for the design and why isolates
  are the answer to "virtual threads" here.

## Status

Work in progress; built in dependency order, foundations first. See the
commit history for the exact sequence.

- ✅ `Money` / `Currency` — exact arithmetic, largest-remainder allocation
- ✅ Hybrid Logical Clock — causal ordering across devices
- ✅ Event-sourcing core — `DomainEvent`, `EventRegistry`, `Aggregate`,
  `Projection` / `ProjectionRunner`
- ✅ `EventStore` — an `InMemoryEventStore` and a Drift/SQLite-backed
  `DriftEventStore`, both verified against one shared behavioural contract
  (`test/eventsourcing/event_store_contract.dart`)
- ⏳ `sync/` — HLC-based merge between devices (not started)
- ⏳ `accounts` / `transactions` / `reports` features
- ⏳ Presentation layer (Riverpod providers, pages)

## Running

```bash
flutter pub get
dart run build_runner build
flutter test
flutter run
```

Requires Flutter 3.47+ / Dart 3.13+.
