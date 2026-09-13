# ADR 0005: Threshold-based isolate offload for CPU-bound decode, not always-on

Date: 2026-09-13
Status: Accepted

## Context

Dart has no shared-memory threads; `async`/`await` only interleaves work
on one event loop, so CPU-bound work (JSON-decoding a large batch of
events, then dispatching each through `EventRegistry`) blocks that
isolate for its full duration regardless of `await`. Projection rebuild
over a large event log, and decoding a large incoming sync batch, are
both this shape of work. See [docs/concurrency.md](../concurrency.md)
for the full measurement writeup this ADR summarizes.

## Decision

Offload this specific decode-and-dispatch work to a worker `Isolate`
(`Isolate.run`), but only above a measured size threshold (500 rows) —
below it, decoding stays inline on the calling isolate. The threshold
was chosen from measurement, not guessed: decoding 10,000 events cost
~180ms synchronously before this existed, while isolate spawning has its
own fixed overhead (startup, copying data across the boundary) that
would make small reads *slower*, not faster, if paid on every call
regardless of size. The worker isolate rebuilds its own `EventRegistry`
from a top-level factory function passed in, rather than receiving the
caller's registry object, since arbitrary closures registered by feature
code aren't guaranteed isolate-safe the way one designated top-level
function can be.

## Consequences

- The claim "the caller stays free to do other things" is verified by a
  runtime test, not inferred from wall-clock time alone: a concurrent
  2ms heartbeat timer keeps ticking throughout an offloaded decode, and
  provably could not before this existed.
- Total latency for one call can be similar to, or even slightly higher
  than, the fully-synchronous version — isolate spawning is not free.
  The benefit is exclusively to the calling isolate's responsiveness
  during the call (UI stays interactive; other queued work on that
  isolate still runs), not to this call's own completion time.
- The same threshold-and-offload shape now backs two call sites
  (`DriftEventStore.readAll` and `EventCodec.decodeManyFromJson`, used
  by both projection rebuild and sync batch decoding) through one shared
  implementation, rather than two independent copies that could drift
  apart.

## Alternatives considered

- **Always offload to an isolate, regardless of size** — rejected: pays
  isolate-spawn and message-copy overhead even for small, cheap reads,
  making the common case strictly worse for no benefit.
- **Never offload; accept synchronous decode cost** — rejected: it was
  the status quo this ADR replaces, measured to block the UI isolate for
  ~180ms on a 10,000-event rebuild, a user-visible jank on real hardware.
