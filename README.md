# event-sourced-ledger

[![CI](https://github.com/thiagosilva92/event-sourced-ledger/actions/workflows/ci.yaml/badge.svg)](https://github.com/thiagosilva92/event-sourced-ledger/actions/workflows/ci.yaml)
[![codecov](https://codecov.io/gh/thiagosilva92/event-sourced-ledger/graph/badge.svg)](https://codecov.io/gh/thiagosilva92/event-sourced-ledger)

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

This makes multi-device merge tractable: syncing is push-then-pull against a
server, de-duplicated by event id, with each direction cursored by the
sending side's own gapless sequence number — not by comparing
[Hybrid Logical Clock](https://cse.buffalo.edu/tech-reports/2014-04.pdf)
timestamps across devices, which turns out to be the wrong tool for that job
(see `SyncService`'s doc comment: a scalar HLC cursor can permanently miss an
event that ties it on `(wallMillis, counter)` but sorts earlier by `nodeId` —
a real gap, pinned down by a test, not a hypothetical). The HLC still does
the job it's good at: giving every event a causal timestamp that's consistent
across devices, useful anywhere ordering-by-when-it-causally-happened matters
(a future conflict-review UI, audit views). There are no destructive updates
to reconcile — merges are pure appends. Genuine business-rule conflicts (an
account closed on one device, used on another) will be resolved with explicit
**compensating events** rather than by overwriting state, once there's a
domain that can have that kind of conflict.

## Architecture

```
presentation  ── Riverpod, reads projections only
application   ── command handlers (write) · query services (read)   ← CQRS seam
domain        ── aggregates, domain events, invariants (pure Dart)
data          ── Drift event store, projection tables, sync client
```

- **Sync:** `SyncService` pushes this device's new events to the server, then
  pulls the server's new events back, cursored by plain sequence numbers on
  each side (see "Why event sourcing" above). Today it runs against
  `FakeSyncTransport`, an in-process stand-in that still serialises every
  event to JSON and back through `EventCodec` — the same codepath a real
  HTTP transport would use — so tests catch a forgotten event registration
  the same way a real deployment would.

- **Write path:** `Command` → aggregate rehydrated from its events → invariants
  checked → new events appended to the log. There's no separate outbox table:
  the log plus `SyncService`'s own "last pushed" cursor already *is* the
  outbox — `readAll(afterSequence: cursor)` is "what hasn't been sent yet".
- **Read path (partly built):** the event log itself is persisted in SQLite via
  Drift (`DriftEventStore`, tested against the same behavioural contract as
  the in-memory store used elsewhere in tests). Projection *tables* — the
  materialised, query-ready read models the UI will actually watch — aren't
  built yet; today `ProjectionRunner` folds the log into in-memory state. The
  write model and read model will never share types.
- **Money** is an integer-minor-unit value object with an explicit currency —
  never `double`. Double-entry transactions must balance to zero.
- **Concurrency:** decoding a large batch read from the event log — what
  `ProjectionRunner.rebuild()` does over the whole log — runs in a worker
  `Isolate` above a size threshold, measured (not assumed) to matter: ~180ms
  of synchronous JSON-decode for 10,000 events before this existed. Dart has
  no shared-memory threads; isolates communicate by message passing. See
  [docs/concurrency.md](docs/concurrency.md) for the measurements, the
  runtime proof it actually stopped blocking the caller (a concurrent
  heartbeat timer that keeps ticking throughout), and why isolates are the
  answer to "virtual threads" here.

## Testing strategy

Different kinds of risk need different kinds of test. Each row below is a
real, runnable thing in this repo — not a checklist item claimed without
evidence.

| Kind | Where | What it actually proves |
| --- | --- | --- |
| Unit / domain | `test/core/`, `test/eventsourcing/` | `Money` arithmetic, HLC ordering, aggregate rehydration, projection folding — pure logic, no I/O |
| Contract | `test/eventsourcing/event_store_contract.dart` | `InMemoryEventStore` and `DriftEventStore` are truly interchangeable — one spec, run against both |
| Architecture / layering | `test/architecture/layering_test.dart` | the dependency rules this README claims (domain stays pure Dart, nothing depends "upward") actually hold, checked by scanning every `import` in `lib/` — not just asserted in prose |
| Load / stress | `test/performance/` | thousands of events, a 10,000-event offline-sync backlog absorbed in one call, 50 concurrent writers with no lost or interleaved data — of the **local embedded database**, since that's what this app has |
| Concurrency proof | `test/performance/projection_rebuild_load_test.dart` | isolate-offloaded decode genuinely stops blocking the caller — measured with a concurrent heartbeat timer, not inferred from a smaller wall-clock number |
| Device smoke test | `lib/main_debug_smoke_test.dart` | the production database path (real file, real native SQLite, real background isolate) actually works on physical Android hardware, not just in a test sandbox |
| Performance benchmark | `test/performance/benchmark_test.dart`, `test/performance/benchmarks/` | steady-state cost of the operations that matter (`Money.allocate`, `Hlc.now`/`.receive`, `DriftEventStore.append`/`merge`/`readAll`), measured with `package:benchmark_harness` (warm-up + a timed exercise window) rather than a single `Stopwatch` reading, and compared against a committed baseline every run |

### Benchmarks: what the regression check does and doesn't guarantee

`test/performance/benchmark_test.dart` runs every benchmark, prints the
current µs/op next to the number committed in `benchmark_baseline.json`, and
prints a `⚠ WARN` for anything more than 50% slower. It **never fails the
test** — two consecutive runs on the same idle laptop already swing 10-45%
from system noise alone (that's a measured range, not a guess: see the
commit that added this), so a tight CI gate would fail on noise far more
often than it would catch a real regression. What this *does* catch: a
change that makes something several times slower, which is exactly the kind
of thing generous per-call time budgets in the load tests can hide (they
pass as long as the whole batch finishes inside a multi-second ceiling).

Refresh the baseline deliberately, after understanding *why* the numbers
moved:

```bash
UPDATE_BENCHMARK_BASELINE=1 flutter test test/performance/benchmark_test.dart
```

### What's deliberately not here

- **Testcontainers** — the right tool for spinning up a real external
  service (Postgres, Kafka) in Docker for an integration test. This repo
  has no external service: SQLite is embedded in-process, so
  `DriftEventStore`'s tests already run against a real SQLite engine with
  no container needed. Testcontainers is the right call for **the .NET
  sync server** (a separate, planned repository) once it has integration
  tests against a real Postgres/SQL Server — not here.
- **A benchmark trend dashboard** — the baseline is one committed snapshot,
  refreshed manually; there's no history of every commit's numbers charted
  over time, and no automatic bisection of when a regression landed. The
  warn-only local/CI comparison catches a sudden large regression at the
  moment it's introduced; it doesn't catch six small 5% regressions
  accumulating over months. A real dashboard is more infrastructure than a
  portfolio repo's CI needs to prove the underlying skill.

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
- ✅ `sync/` — `SyncService` push/pull against a `SyncTransport`
  (`FakeSyncTransport` today; a real one would speak HTTP to the .NET sync
  server), cursor persistence, retry-safe on transport failure, verified
  with a multi-device convergence test. Deliberately uses a `sequence`
  cursor rather than `readSince`'s `Hlc` cursor — see `SyncService`'s doc
  comment for why.
- ✅ Isolate-offloaded decode for large event-log reads, with a real device
  smoke test (`lib/main_debug_smoke_test.dart`) and a test that proves the
  calling isolate stays responsive during it, not just a smaller number —
  see [docs/concurrency.md](docs/concurrency.md)
- ✅ Automated architecture/layering checks (`test/architecture/`) — a real
  regression test, not just a diagram. Writing the "domain stays pure Dart"
  rule surfaced that `DriftEventStore` (imports Drift) had been living
  under `eventsourcing/`, the pure-Dart zone; it moved to `core/database/`
  before this test was added, with a dedicated rule pinning its location
  so that specific mistake can't quietly come back
- ✅ Formal performance benchmarks (`test/performance/benchmark_test.dart`,
  `package:benchmark_harness`) with a committed baseline and a warn-only
  regression check — see "Testing strategy" above for what that does and
  doesn't guarantee
- ⏳ Isolate offload for a large incoming sync batch — same idea, not
  applied there yet
- ⏳ Persisted (Drift-backed) `SyncCursorStore` — today's `SyncCursorStore`
  is in-memory only; cursors don't survive an app restart yet
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

### Verifying the database on a real device

There's no real UI yet, so `flutter run` just shows a placeholder. To check
that the production database path (a real file via `path_provider`, native
SQLite, a background isolate) actually works on physical hardware:

```bash
flutter run -t lib/main_debug_smoke_test.dart -d <device>
```

Confirmed working on Android 16 / arm64. This is temporary — see the doc
comment on `DbSmokeTestScreen` for when to delete it.
