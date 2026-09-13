# ADR 0001: Event sourcing and CQRS for the ledger domain

Date: 2026-09-13
Status: Accepted (implemented since the first commit)

## Context

The app's core requirement is a shared household ledger that multiple
people edit from different phones, often offline, without ever silently
losing a write when devices reconcile, and with every balance auditable
down to the entry that produced it. A CRUD model (accounts and
transactions as mutable rows, synced by last-write-wins or row-level
timestamps) makes exactly the failure mode this app cannot afford easy
to hit: two offline edits to the same row silently clobber each other on
merge, and there is no record of what actually happened, only the final
state.

## Decision

Every change is captured as an immutable domain event
(`AccountOpened`, `TransactionRecorded`, `TransactionVoided`, ...)
appended to a local, append-only log. Balances and reports are never
stored directly — they are **projections**, pure folds over that log,
rebuilt (or incrementally maintained) from it. Reads and writes are
split along a CQRS seam: `Command` → aggregate rehydrated from its own
events → invariants checked → new events appended (the write side);
`ProjectionRunner` folding the log into read state (the read side). The
two sides never share types.

## Consequences

- Multi-device merge becomes tractable: syncing is push-then-pull,
  de-duplicated by event id. There are no destructive updates to
  reconcile, because nothing is ever overwritten — only appended to.
- Every balance is auditable by construction: it is a fold over a
  specific, inspectable sequence of events, not an opaque mutated
  number.
- Genuine business-rule conflicts (an account closed on one device,
  used on another) are future work to be resolved with explicit
  **compensating events**, not by picking a winner and discarding the
  other write — a deliberate consequence of this model, not an
  afterthought bolted onto a CRUD system that was never designed for
  conflict at all.
- Cost: more moving parts than CRUD for a domain this size (event
  registry, codec, projection runner) — justified here specifically
  because offline multi-device conflict is the problem the whole app
  exists to demonstrate, not because every domain needs this.

## Alternatives considered

- **CRUD + last-write-wins sync** — rejected: exactly the "silent data
  loss on conflicting offline edits" failure mode the problem statement
  rules out.
- **CRDTs** (e.g. a G-Set or OR-Set per account) — would solve merge
  without a server, but the domain (double-entry transactions that must
  balance to zero) has invariants that don't map cleanly onto standard
  CRDT primitives without significant custom design; event sourcing
  gets the audit trail this domain also wants "for free," which a bare
  CRDT does not.
