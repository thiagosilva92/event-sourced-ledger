# ADR 0002: Sequence cursors, not HLC comparison, drive sync — the HLC is for causal timestamps only

Date: 2026-09-13
Status: Accepted

## Context

Every event carries a [Hybrid Logical Clock](https://cse.buffalo.edu/tech-reports/2014-04.pdf)
timestamp, so it was tempting to also use HLC comparison to decide "what
hasn't this device seen yet" when syncing — compare the highest HLC a
device has seen against each candidate event's HLC. That turns out to be
the wrong tool for that specific job.

## Decision

Sync is push-then-pull, cursored by **plain, gapless sequence numbers**
assigned by the sending side (the local event store's own insertion
order for push; the server's own sequence for pull) — not by comparing
HLC timestamps across devices. `SyncService`'s own doc comment records
the concrete gap this closes: two events can tie on `(wallMillis,
counter)` and sort differently depending on `nodeId` alone — a scalar
HLC-based cursor can permanently skip such an event, not just reorder
it. This was pinned down with a test, not left as a theoretical concern.

The HLC itself is kept, but demoted to what it is actually good at:
giving every event a causal timestamp that is consistent across devices,
useful wherever "ordering by when it causally happened" matters (a
future conflict-review UI, audit views) — just not as the thing that
decides whether an event has already been synced.

## Consequences

- Sync cursors are simple integers with total order per side, which is
  exactly the property a "have I seen everything up to N" comparison
  needs and a distributed HLC comparison does not reliably provide.
- The HLC is still fully implemented and tested (`Hlc.now`/`.receive`)
  and available for genuine causal-ordering use cases later — this
  decision narrows its role, it does not remove it.
- Two independent correctness mechanisms (sequence cursors for "what to
  sync," event-id deduplication for "don't apply it twice") instead of
  one mechanism trying to do both jobs — more explicit, and each one is
  independently testable.

## Alternatives considered

- **HLC-based sync cursor** — rejected for the concrete missed-event gap
  above.
- **Vector clocks per event** — would correctly capture causality across
  arbitrarily many devices, but is unnecessary complexity here: the
  server is the single point every device eventually syncs through, so
  a per-side sequence number already gives a well-defined "everything up
  to here" cursor without needing to track a growing vector across every
  device that has ever existed.
