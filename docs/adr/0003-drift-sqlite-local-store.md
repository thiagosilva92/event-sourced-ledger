# ADR 0003: Drift over SQLite as the local, offline-first event store

Date: 2026-09-13
Status: Accepted

## Context

The app must work fully offline, on-device, with an event log that
survives app restarts, supports schema evolution as new event types and
tables are added, and can be queried efficiently as it grows (cursor
reads by sequence number, batch reads for projection rebuild). It needs
to be a real embedded database, not an in-memory structure that
disappears on restart or a flat file requiring hand-rolled indexing.

## Decision

Use [Drift](https://drift.simonbinder.eu/) over SQLite as the on-device
`EventStore` implementation (`DriftEventStore`), behind the same
`IEventLog`-equivalent interface (`EventStore`) that `InMemoryEventStore`
implements for fast unit tests — both are verified against one shared
behavioural contract (`event_store_contract.dart`), so they are provably
interchangeable rather than assumed to be.

## Consequences

- Real, versioned schema migrations are possible and tested
  (`app_database_migration_test.dart` upgrades an actual pre-existing
  v1 database and confirms existing data survives) — something an
  in-memory or hand-rolled-file store would have to reimplement from
  scratch.
- SQL gives indexed cursor reads (`readAll(afterSequence: cursor)`) for
  free, which is exactly the access pattern both projection rebuild and
  sync push/pull need.
- Drift generates typed Dart from the schema, so a column rename or type
  change is a compile error at every call site, not a runtime surprise
  discovered on a real device.
- Cost: a code-generation step (`build_runner`) is now part of the build,
  and CI has to run it before analysis/tests can pass.

## Alternatives considered

- **Hive / other pure-Dart key-value stores** — simpler for flat
  document storage, but the event log's natural access patterns
  (ordered cursor scans, uniqueness constraints on event id, future
  relational projections) fit SQL's strengths directly rather than
  needing to be reimplemented on top of a key-value model.
- **Hand-rolled file-based log (append-only file + manual index)** —
  would avoid a dependency, but reimplements durability, indexing, and
  migration from nothing, for no benefit over a mature embedded SQL
  engine already in Flutter's ecosystem.
