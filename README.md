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
  each side (see "Why event sourcing" above). Two `SyncTransport`
  implementations exist: `FakeSyncTransport`, an in-process stand-in for
  tests that still serialises every event to JSON and back through
  `EventCodec` — the same codepath a real HTTP transport uses — so tests
  catch a forgotten event registration the same way a real deployment
  would; and `HttpSyncTransport`, which speaks real HTTP to
  [`ledger-sync-server`](https://github.com/thiagosilva92/ledger-sync-server),
  a separate repository (see [docs/adr/0007](docs/adr/0007-sync-server-separate-repository.md)).

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
| Real device | the app itself, run on physical Android hardware | not a `test/` file — running the real app is what caught a bug nothing else here could: an earlier standalone tool that exercised the production database path wrote its own throwaway events into the *same* on-device database the real app reads, and the app's event registry (correctly) didn't know how to decode them. See the note below. |
| Performance benchmark | `test/performance/benchmark_test.dart`, `test/performance/benchmarks/` | steady-state cost of the operations that matter (`Money.allocate`, `Hlc.now`/`.receive`, `DriftEventStore.append`/`merge`/`readAll`), measured with `package:benchmark_harness` (warm-up + a timed exercise window) rather than a single `Stopwatch` reading, and compared against a committed baseline every run |
| Schema migration | `test/core/database/app_database_migration_test.dart` | upgrading a real pre-existing database (built by hand at schema v1) adds the new table and keeps existing data intact — the one path every other test skips by always starting from a fresh database at the current version |
| Cross-repo integration | `test/sync/http_sync_transport_live_test.dart` (tagged `live_server`, excluded from the default run — see the file's own doc comment for how to run it) | `HttpSyncTransport` actually talks to a real, running `ledger-sync-server` instance over HTTP: push then pull round-trips real events through a real ASP.NET Core process and a real PostgreSQL database in a separate repository, confirmed by reading that server's own request logs afterward — not just that this repo's mocked-client tests (`http_sync_transport_test.dart`) produce the right bytes |
| Accessibility | `test/features/accessibility_test.dart` | every screen (empty states, the open-account form, the record-transaction form) against Flutter's own guideline checks — minimum tap target size (Android and iOS), every tappable element labeled, and text contrast — not just that a `Semantics` node exists somewhere |
| Localization | `test/l10n/localization_test.dart` | forcing `locale: Locale('pt')` actually renders the Portuguese strings (including one only shown after a real form submission) and that the English strings are absent — not just that `AppLocalizations` compiles |

### A bug only a real device could have caught

Before the presentation layer existed, `lib/main_debug_smoke_test.dart` (a
separate Flutter entry point) was how the production `AppDatabase()` path —
real file via `path_provider`, real native SQLite, real background isolate —
got verified on physical hardware. It worked; see the commit history. Its own
doc comment said to delete it once a real screen existed to do that job
instead, "since it would stop being the only thing touching `AppDatabase()`
on-device."

That turned out to be exactly right, and for a reason worth writing down: the
first time the *real* app ran on the same physical device afterward, it threw
`UnknownEventTypeError: no deserializer registered for
"debug.smoke_test_pinged"` on startup. Both entry points open the same
on-device database file (same app id, same install) — the debug tool's
throwaway events were still sitting in the event log, and the real app's
event registry (`buildLedgerEventRegistry`) correctly has no idea what a
`debug.smoke_test_pinged` event is. Nothing in `test/` could have caught
this: every test opens a fresh database. Only running the actual app on the
actual device, after the debug tool had already written to it, surfaced it.

Fixed by clearing the device's app data and removing the debug tool now that
its replacement exists — not by teaching the registry to ignore unknown
events, which would have hidden a real problem (a genuinely corrupt or
newer-than-this-build event) behind the same code path. The lesson that's
staying in the design: a throwaway tool and the real app should never share
a database, and now they structurally can't — there's only one thing left
that opens `AppDatabase()` on-device.

### A bug only a second widget test file could have caught

`buildAppRouter()` used to be `final GoRouter appRouter = GoRouter(...)` — a
module-level singleton, built once, that `LedgerApp` just referenced.
Every widget test up to this point pumped `LedgerApp` once per test and
happened to only ever assert on the screen it had just navigated *to* — so
nothing noticed that `GoRouter` carries its own navigation stack as mutable
internal state, and a shared singleton means that state persists for the
lifetime of the test *process*, not the test.

The new transaction-recording widget tests (`record_transaction_flow_test.dart`)
were the first in this repo to run several `testWidgets` in one file that
each navigate away from `/` and never navigate back before the test ends.
Every test after the first one in that file started on whatever screen the
previous test had last pushed — not `/` — and failed looking for a widget
that was never going to be on screen, for a reason that had nothing to do
with the transaction form itself. Fixed by making the router a function,
`buildAppRouter()`, and having `LedgerApp` build and keep exactly one
instance of it per app instance (`late final GoRouter _router` in a
`State`, not a top-level `final`) — which also fixes the same latent
problem for two real `LedgerApp` instances ever existing in the same
process, not just for tests.

### A bug only a phone's own keyboard could have caught

`RecordTransactionPage`'s form — two dropdowns, an amount field, a
description field, a date picker, a button — fit comfortably in a widget
test's default viewport and on a phone screen with no keyboard up. The
first time a real finger tapped the amount field on the physical Xiaomi,
the on-screen keyboard took roughly the bottom half of the screen and
Flutter logged `A RenderFlex overflowed by 36 pixels on the bottom`: a
plain `Column` inside a `Padding` doesn't scroll, so the fields below
whatever was focused had nowhere to go.

Fixed by wrapping the form in a `SingleChildScrollView`. The regression
test for it (`record_transaction_flow_test.dart`) doesn't need a real
keyboard to catch this again — `tester.view.viewInsets =
FakeViewPadding(bottom: 400)` simulates exactly the "half the screen is
gone" layout constraint a keyboard imposes, at the exact viewport size
where the real bug reproduced. Deliberately checked *before* trusting the
fix: reverting the `SingleChildScrollView` change and re-running that one
test reproduced the same class of error
(`RenderFlex overflowed by 120 pixels`, different number because of the
test's viewport size, same shape of bug) — the test was written to fail
first, the same discipline every other test in this repo follows.

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

Each benchmark's warm-up + exercise window costs a deliberate ~2 seconds —
that's the methodology, not overhead to shave off, so `benchmark_test.dart`
is tagged `@Tags(['benchmark'])` and kept out of the fast path instead:

```bash
flutter test --exclude-tags=benchmark   # what CI runs on every push/PR
flutter test --tags=benchmark           # just the benchmarks, ~20s
```

CI mirrors that split: the main job excludes benchmarks so PR feedback
stays fast; a separate `benchmark` job runs them only on pushes to `main`
— i.e. right when code is about to ship, which is what "before production"
actually calls for, not on every PR iteration.

### What's deliberately not here

- **Testcontainers** — the right tool for spinning up a real external
  service (Postgres, Kafka) in Docker for an integration test. This repo
  has no external service: SQLite is embedded in-process, so
  `DriftEventStore`'s tests already run against a real SQLite engine with
  no container needed. It's the right call for
  [`ledger-sync-server`](https://github.com/thiagosilva92/ledger-sync-server)
  (a real Postgres to test against) — not here.
- **A benchmark trend dashboard** — the baseline is one committed snapshot,
  refreshed manually; there's no history of every commit's numbers charted
  over time, and no automatic bisection of when a regression landed. The
  warn-only local/CI comparison catches a sudden large regression at the
  moment it's introduced; it doesn't catch six small 5% regressions
  accumulating over months. A real dashboard is more infrastructure than a
  portfolio repo's CI needs to prove the underlying skill.
- **CodeQL** — GitHub's static analysis doesn't support Dart as a scanned
  language (the supported list is C/C++, C#, Go, Java/Kotlin,
  JavaScript/TypeScript, Python, Ruby, and Swift). Running it against just
  the thin, Flutter-generated Android/iOS platform wrapper code in
  `android/`/`ios/` — the only Kotlin/Swift here, and not this app's own
  logic — would be scanning theater, not real coverage. Dependabot
  (`.github/dependabot.yml`) still applies: dependency scanning and
  language-level static analysis are different concerns, and only one of
  them has a tool that covers Dart.
  [`ledger-sync-server`](https://github.com/thiagosilva92/ledger-sync-server)
  runs CodeQL against its C# code.

## Architecture Decision Records

The non-obvious calls behind this codebase — event sourcing over CRUD,
why sync uses sequence cursors instead of comparing HLC timestamps,
Drift/Riverpod, threshold-based isolate offload, the regex-based
architecture test, and keeping the sync server in a separate repository
— are written up with context, consequences, and rejected alternatives
in [docs/adr](docs/adr/README.md).

## Status

**Feature-complete for what this repo sets out to prove**: event sourcing,
CQRS, and multi-device sync architecture, built in dependency order from a
pure-Dart domain layer up through a working Flutter UI — verified on
physical Android hardware, not just in `flutter test`. Every gap this
README has ever flagged with a ⏳ has since been closed; the checklist
below is now all ✅, in the order it was actually built (see the commit
history for the exact sequence). What isn't here is either listed above
under "What's deliberately not here," with a stated reason, or belongs to
`ledger-sync-server`'s own repository (the server side of the same
integration, e.g. its API, database, and deployment).

- ✅ `Money` / `Currency` — exact arithmetic, largest-remainder allocation
- ✅ Hybrid Logical Clock — causal ordering across devices
- ✅ Event-sourcing core — `DomainEvent`, `EventRegistry`, `Aggregate`,
  `Projection` / `ProjectionRunner`
- ✅ `EventStore` — an `InMemoryEventStore` and a Drift/SQLite-backed
  `DriftEventStore`, both verified against one shared behavioural contract
  (`test/eventsourcing/event_store_contract.dart`)
- ✅ `sync/` — `SyncService` push/pull against a `SyncTransport`
  (`FakeSyncTransport` for tests, `HttpSyncTransport` for the real
  server), cursor persistence, retry-safe on transport failure, verified
  with a multi-device convergence test. Deliberately uses a `sequence`
  cursor rather than `readSince`'s `Hlc` cursor — see `SyncService`'s doc
  comment for why.
- ✅ `HttpSyncTransport` — a real `SyncTransport` speaking HTTP to
  [`ledger-sync-server`](https://github.com/thiagosilva92/ledger-sync-server)
  (see [docs/adr/0007](docs/adr/0007-sync-server-separate-repository.md)),
  verified against a mocked client for exact wire-format correctness and,
  separately, against that server actually running via its own
  `docker compose up` — push and pull both proven to reach real container
  replicas behind its load balancer, per that server's own request logs.
- ✅ Isolate-offloaded decode for large event-log reads, confirmed on real
  device hardware and a test that proves the calling isolate stays
  responsive during it, not just a smaller number — see
  [docs/concurrency.md](docs/concurrency.md)
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
- ✅ Isolate offload for a large incoming sync batch —
  `EventCodec.decodeManyFromJson` extracts the same threshold-and-`Isolate.run`
  logic `DriftEventStore.readAll` already used, so a sync pull's wire
  payloads and a database read share one implementation instead of two
  copies of the same idea. Both `FakeSyncTransport.pull` and
  `HttpSyncTransport.pull` call it. Proven with the same kind of test
  as the database-read case, not just a matching code shape: a concurrent
  heartbeat timer keeps ticking while an 8,000-payload batch decodes
  (`test/performance/sync_batch_decode_load_test.dart`) — see
  [docs/concurrency.md](docs/concurrency.md).
- ✅ `RecordTransactionPage` (`features/transactions/presentation/`) — a
  form over `RecordTransactionHandler`, shaped as the simplest case
  double-entry actually needs day to day: money moves from one open account
  to another, i.e. exactly two legs (`-amount` / `+amount`). The domain
  layer already supports splitting one amount across more legs than that
  (`Leg`, `LedgerTransaction`) — only this MVP screen's UI doesn't yet. The
  "to" dropdown is filtered to accounts sharing the "from" account's
  currency, so the form can't be submitted into a failure
  `LedgerTransaction.record` would just reject anyway (`InvalidLegs`) —
  verified by a widget test that opens two accounts in different
  currencies and checks the mismatched one is never offered. Reached from
  the accounts list via an app bar action, not a second
  `FloatingActionButton` (Scaffold only supports one). Manually verified on
  the physical Xiaomi device, which is what surfaced a real keyboard-overflow
  bug — see "A bug only a phone's own keyboard could have caught" below.
- ✅ Persisted device node id — `DeviceIdentityStore` (`core/clock/`, pure
  Dart, next to `Hlc` itself) plus `DriftDeviceIdentityStore`
  (`core/database/`), the same interface/adapter split as `EventStore` and
  `SyncCursorStore`, verified against one shared contract
  (`test/core/clock/device_identity_store_contract.dart`) run against both
  `InMemoryDeviceIdentityStore` and the Drift-backed one. This is the
  app's second real schema migration (v2 → v3, adding
  `device_identity_rows`) — `app_database_migration_test.dart` now proves
  the full v1 → v3 chain runs both additive steps, not just the one it
  proved before. Resolved once in `main.dart`, *before* `runApp`, and
  handed in via `ProviderScope` overrides — not a `FutureProvider`, so
  nothing downstream (the HLC clock, every command handler) has to deal
  with an `AsyncValue` for something that only needs to be async once, at
  startup.
- ✅ Persisted (Drift-backed) `SyncCursorStore` — `DriftSyncCursorStore`
  survives an app restart, verified against the same contract as
  `InMemorySyncCursorStore` (`test/sync/sync_cursor_store_contract.dart`).
  This is also the app's first real schema migration (v1 → v2, adding the
  `sync_cursor_rows` table): `test/core/database/app_database_migration_test.dart`
  hand-builds a v1 database file and checks upgrading it preserves the
  existing event log — the path every other test skips by always opening a
  fresh database at the current schema version. Writing this surfaced that
  `sync/` had been miscategorized as an "upper" consumer layer in the
  architecture test, when `DriftSyncCursorStore` implementing its interface
  from `core/database/` is the same adapter-depends-on-port relationship
  `DriftEventStore` already has with `eventsourcing/` — fixed there too
- ✅ `accounts` / `transactions` domain and application layers — the first
  real feature built on the foundation, not a test fixture:
  - `Account` (`features/accounts/`) — name, currency, open/closed
    lifecycle.
  - `LedgerTransaction` (`features/transactions/`) — a double-entry
    posting. Enforces everything it can see from its own event stream
    (≥2 legs, none zero, one currency, sum to exactly zero — `Money`
    arithmetic, no floating point) before ever raising
    `TransactionRecorded`. `TransactionVoided` is a compensating event,
    not an edit or delete.
  - The two aggregates reference each other by id only. Whether a leg's
    account exists and is open is a cross-aggregate check `LedgerTransaction`
    has no way to make on its own — that's what
    `features/*/application/` (command handlers) is for: load what's
    needed, validate, then call the aggregate. First real production use
    of `Result<T, F>` and of the CQRS `application` layer the README's
    architecture diagram has described since the first commit.
  - `AccountBalanceProjection` (`features/reports/`) — running balance
    per account, folded from `TransactionRecorded`/`TransactionVoided`.
    First real use of `Projection`/`ProjectionRunner` outside a test
    fixture; correctly reverses a voided transaction by remembering its
    legs internally, since `TransactionVoided` doesn't carry them.
  - 51 new tests, including a case that would have crashed the
    projection at runtime on any account event (an un-exhaustive
    `switch` with no default) had the test not caught it before it
    shipped.
- ✅ Presentation layer (Riverpod providers, pages) — the app has a real
  screen now, wired end-to-end to the write and read paths above:
  - `app/providers/` — one `Provider`/`NotifierProvider` per infrastructure
    piece and command handler, plus `_LiveProjectionNotifier<S>`, a base
    class that subscribes to `EventStore.changes` and keeps a projection's
    in-memory state current (`rebuild()` once, `catchUp()` on every new
    event) so the UI never polls.
  - `AccountsListPage` / `OpenAccountPage` (`features/accounts/presentation/`),
    routed with `go_router`. `AccountSummary` merges the balance projection
    and the directory projection into one view-model so the widget layer
    never touches either projection directly.
  - Verified two ways: widget tests
    (`test/features/accounts/presentation/`) drive the real `LedgerApp`
    widget tree against a `ProviderScope`-overridden in-memory stack, and —
    the test no widget test can substitute for — **manually, on the same
    physical Xiaomi device** referenced above: opened two accounts, both
    listed correctly, closed one via long-press, zero exceptions. That run
    is what confirmed the debug-tool bug below was actually gone, not just
    theoretically fixed.
  - 178/178 tests passing (unit, contract, architecture, load, benchmark,
    migration, widget), locally and in CI — see the current total below;
    three more milestones (isolate offload for sync, the transaction
    screen, and the persisted device id) landed after this one.
- ✅ Accessibility — every screen labeled for a screen reader, not just
  visually complete: the account list's long-press-to-close gesture (never
  discoverable to a screen reader on its own) is also exposed as an
  explicit `CustomSemanticsAction`; balances get a spoken-friendly label
  ("negative balance 12.34 USD", not a raw "-12.34 USD" string a screen
  reader reads digit-by-digit as a minus sign); purely decorative icons
  (the two empty states) are excluded from the semantics tree instead of
  announcing as an unlabeled "image"; and the loading spinner shown while
  a form submits gets an explicit "Submitting" label, since a bare
  `CircularProgressIndicator` announces nothing on its own. Verified with
  Flutter's own accessibility guideline checks (minimum tap target size,
  every tappable element labeled, text contrast) against every real
  screen state — see the Testing strategy table above.
- ✅ Localization — English and Portuguese, generated from
  [`lib/l10n/*.arb`](lib/l10n/) via `flutter gen-l10n` (`generate: true`
  in `pubspec.yaml`; the generated `app_localizations*.dart` files aren't
  committed, same convention as Drift's `*.g.dart` — see `.gitignore`).
  Every user-visible string in the presentation layer goes through
  `AppLocalizations`, including the accessibility semantic labels above
  and dynamically-shown validator messages, not just the static labels
  visible on first build. Verified two ways: every existing widget test
  still runs against the English default, and
  `test/l10n/localization_test.dart` forces `locale: Locale('pt')` and
  asserts the Portuguese strings actually render — including a validator
  message only shown after a real form submission — while asserting the
  English strings are *absent*, which is what actually proves this isn't
  silently falling back to the default locale.

**Current totals**: 210/210 tests passing, `flutter analyze` clean, CI
green on every push to `main` — see the badge at the top of this file for
live status.

## Running

```bash
flutter pub get
dart run build_runner build
flutter test
flutter run
```

Requires Flutter 3.47+ / Dart 3.13+.

`flutter run -d <device>` now runs the real app — confirmed on Android 16 /
arm64. See "A bug only a real device could have caught" above for why there
used to be a separate command for this.
