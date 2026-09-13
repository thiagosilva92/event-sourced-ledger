# ADR 0007: The sync server is a separate repository, `FakeSyncTransport` is the seam

Date: 2026-09-13
Status: Accepted (server now exists, is live, and this client now has a real `HttpSyncTransport` — see Consequences)

## Context

`SyncService` needs something implementing `SyncTransport` (push a batch,
pull events after a cursor) to actually reach another device's events.
That something is a networked service with its own persistence,
authentication, scaling, and deployment concerns — a different kind of
system than a Flutter client, with a different natural technology choice
and release cadence.

## Decision

Keep the sync server out of this repository entirely. `SyncTransport` is
defined here as a pure interface; `FakeSyncTransport` is an in-process
stand-in that still serializes every event to JSON and back through the
same `EventCodec` a real HTTP transport would use, so tests catch a
forgotten event registration exactly the way a real deployment would.
The real implementation lives in a separate repository,
[`ledger-sync-server`](https://github.com/thiagosilva92/ledger-sync-server)
(ASP.NET Core / PostgreSQL), built and released independently.

## Consequences

- This repository never needs a database, a server framework, or
  deployment infrastructure of its own for sync — its only obligation is
  to the `SyncTransport` interface's contract.
- The client/server boundary is enforced by repository separation, not
  just a namespace convention — there is no possible accidental import
  from `lib/sync` into server-side code, because there is no server-side
  code in this checkout at all.
- `ledger-sync-server` is built, tested, and deployed live, and this
  client now has a real `HttpSyncTransport`
  (`lib/sync/http_sync_transport.dart`) implementing the same
  `SyncTransport` contract `FakeSyncTransport` does, sending exactly the
  wire format `EventCodec.encode` already produces to that server's
  `POST`/`GET /events`. Verified two ways: `http_sync_transport_test.dart`
  asserts the exact request/response shape against a mocked HTTP client
  (no network), and `http_sync_transport_live_test.dart` (tagged
  `live_server`, excluded from the default `flutter test` run the same
  way `benchmark` is) pushes and pulls real events through a real,
  running `ledger-sync-server` instance (`docker compose up` in that
  repository) — confirmed via that server's own request logs that the
  push and pull actually landed on two different container replicas
  behind its YARP gateway, not just that the test asserted green.
- Two repositories, two CI pipelines, two release cadences — a deliberate
  cost, matching how a mobile client and its backend genuinely do evolve
  on independent schedules in practice, rather than collapsing them into
  one repository for convenience.

## Alternatives considered

- **Monorepo with client and server as separate packages** — would keep
  a single source-of-truth commit history and simplify cross-cutting
  changes to the wire contract, at the cost of coupling two genuinely
  different technology stacks' tooling (Flutter/Dart CI vs .NET CI) into
  one repository's build — rejected in favor of the separation that
  mirrors how these two systems would actually be owned and deployed.
