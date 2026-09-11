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
| Rebuild all projections from scratch | long-lived worker isolate | folding thousands of events would drop frames | planned — `ProjectionRunner.rebuild()` currently runs on the caller's isolate |
| Validate + order an incoming sync batch | `Isolate.run` | keeps the UI responsive during sync | planned — `sync/` not built yet |
| Single command handling | main isolate | cheap; rehydration is snapshot-bounded | current behaviour |

### Note on "virtual threads"

Virtual threads (JVM Project Loom, Java 21+) solve blocking-IO scalability on the
server. They are not a Dart or Flutter concept. The equivalent goals here —
never block the UI, scale concurrent IO — are met by the event-loop model for IO
and by isolates for CPU work. The .NET sync server (separate repository) uses
`async`/`await` and bounded channels for the same reasons.
