# Concurrency model

Dart is single-threaded per isolate. There is no shared-memory threading and no
`async` keyword that magically parallelises CPU work — `async`/`await` only
interleaves work on one event loop.

For CPU-bound work (folding a long event log into projections, verifying a large
batch of events during sync) this app's design uses **isolates**:

- an isolate has its own memory heap; nothing is shared;
- isolates communicate by copying messages over ports (`SendPort`/`ReceivePort`),
  or via `Isolate.run` for one-shot computations;
- there are therefore no data races and no locks — the trade-off is copy cost at
  the boundary, which we bound by sending compact event DTOs, not domain objects.

### Where isolates are used

| Work | Mechanism | Why off the main isolate | Status |
| --- | --- | --- | --- |
| Decoding a large batch read from the event log (feeds `ProjectionRunner.rebuild()`) | `Isolate.run`, in `DriftEventStore.readAll` | measured: ~150-180ms of synchronous JSON-decode + registry dispatch for 10,000 events — see below | **done** |
| Decoding an incoming sync batch (`SyncTransport.pull` → `SyncService`) | `Isolate.run`, in `EventCodec.decodeManyFromJson` | same shape of cost as the row above, just fed by a pull's wire payloads instead of a database read | **done** |
| Single command handling | main isolate | cheap; rehydration is snapshot-bounded | current behaviour, by design (not worth offloading) |

#### Rebuild: measured, not assumed

`test/performance/projection_rebuild_load_test.dart` first measured the *old*
always-synchronous behavior before building anything: folding 10,000 events
cost ~180ms, entirely in reading rows and turning them into `DomainEvent`
objects (JSON decode + `EventRegistry` dispatch) — the fold step itself
measured ~0ms. That decode is what `DriftEventStore.readAll` now offloads to
a worker isolate once a batch crosses a size threshold (500 rows, chosen from
the same measurements). Below the threshold it stays inline — spawning an
isolate has its own fixed cost (isolate startup, copying data across), which
would make small reads *slower*, not faster.

The worker isolate rebuilds its own `EventRegistry` from a **top-level
factory function** passed into `DriftEventStore` rather than receiving the
caller's registry object — registered deserializers are arbitrary closures
from feature code, and "one designated top-level function must be
isolate-safe" is a much easier bar to guarantee than "every closure anyone
ever registers must be".

The proof this actually solved the problem isn't a smaller wall-clock number
— isolate spawning has real overhead, so total latency for one rebuild can be
similar or even a little higher. The proof is a test that runs a 2ms
heartbeat timer on the calling isolate concurrently with a large `readAll()`
and counts how many times it fires: with decoding blocking that isolate
synchronously, it could not fire even once until the call returned; with
decoding offloaded, it keeps ticking throughout. That's a runtime measurement
of the actual claim (the isolate stayed free to do other things), not a
description of what the code is supposed to do.

#### Incoming sync batch: the same pattern, a different caller

`EventCodec.decodeManyFromJson` is the isolate-offload logic itself,
extracted from `DriftEventStore.readAll` and generalized so both
call sites — a database read and a transport's pull — share one
implementation instead of two copies of the same threshold-and-`Isolate.run`
shape. `FakeSyncTransport.pull` calls it on the wire payloads it decodes
today; a real HTTP transport would call it on whatever a response body
deserializes into. Same 500-payload threshold (the underlying cost is
identical: JSON decode plus `EventRegistry` dispatch), same requirement
that the registry come from a top-level factory function so it can be
rebuilt inside the worker isolate, and the same style of proof —
`test/performance/sync_batch_decode_load_test.dart` runs the identical
concurrent-heartbeat test `projection_rebuild_load_test.dart` does, just
against `decodeManyFromJson` directly instead of `readAll`.

### Note on "virtual threads"

Virtual threads (JVM Project Loom, Java 21+) solve blocking-IO scalability on the
server. They are not a Dart or Flutter concept. The equivalent goals here —
never block the UI, scale concurrent IO — are met by the event-loop model for IO
and by isolates for CPU work. The .NET sync server (separate repository) uses
`async`/`await` and bounded channels for the same reasons.
