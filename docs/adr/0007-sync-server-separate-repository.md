# ADR 0007: The sync server is a separate repository, `FakeSyncTransport` is the seam

Date: 2026-09-13
Status: Accepted (server now exists and is live — see Consequences)

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
- As of this writing, `ledger-sync-server` is built, tested, and
  deployed live, but this client still runs against `FakeSyncTransport`
  — wiring a real `HttpSyncTransport` implementation is tracked as
  known follow-up work, not yet started (see that repository's own
  [ADR 0007](https://github.com/thiagosilva92/ledger-sync-server/blob/main/docs/adr/0007-split-cd-from-infra-changes.md)
  and status notes for where it stands today).
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
