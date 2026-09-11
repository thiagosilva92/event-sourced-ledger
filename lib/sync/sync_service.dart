import 'package:ledger/eventsourcing/event_store.dart';
import 'package:ledger/sync/sync_cursor.dart';
import 'package:ledger/sync/sync_transport.dart';
import 'package:meta/meta.dart';

/// Outcome of one [SyncService.syncOnce] call.
@immutable
final class SyncResult {
  const SyncResult({required this.pushedCount, required this.pulledCount});

  final int pushedCount;

  /// Events newly merged into the local store — not the raw count fetched
  /// over the wire, which can include events this device pushed earlier in
  /// the same [SyncService.syncOnce] call and gets handed back unasked.
  final int pulledCount;

  @override
  String toString() => 'SyncResult(pushed: $pushedCount, pulled: $pulledCount)';
}

/// Synchronises this device's [EventStore] with one remote over a
/// [SyncTransport]: push what's new locally, then pull what's new remotely.
///
/// ## Why the cursors are sequence numbers, not `Hlc` timestamps
///
/// `EventStore.readSince(Hlc)` looks like the obvious cursor for "give me
/// what changed" — it's exactly what this service needs, conceptually. It
/// is deliberately **not** used for that here.
///
/// `Hlc.compareTo` breaks ties between events with the same
/// `(wallMillis, counter)` using `nodeId`, which makes it a *total* order
/// but not one related to when an event actually reached a given store. Two
/// devices can independently produce events that tie on
/// `(wallMillis, counter)`; whichever one sorts first by `nodeId` can then
/// compare as *older* than a cursor it never influenced, even though it
/// arrived at the remote after that cursor was taken — see the
/// "characterization" test next to `EventStore.readSince`'s tests, which
/// pins this down as a documented gap in a scalar-HLC cursor.
///
/// A `sequence` cursor doesn't have this problem: it's the store's own
/// gapless, strictly-increasing insertion order. `readAll(afterSequence:
/// cursor)` — already used to feed `ProjectionRunner` — returns exactly
/// "everything inserted after the last thing I looked at", full stop, no
/// tie-break needed. Each side of a sync tracks the *other* side's sequence
/// numbering as an opaque cursor (never compared across stores, only
/// round-tripped), which is enough for a two-party (device ↔ server) sync
/// and sidesteps the whole class of problem `readSince` has.
///
/// `readSince` remains useful for other things (e.g. a future "what else
/// happened around this disputed edit" conflict view) — it just isn't the
/// right tool for this job.
class SyncService {
  SyncService({
    required EventStore localStore,
    required SyncTransport transport,
    required SyncCursorStore cursorStore,
    this.batchSize = 200,
  }) : _localStore = localStore,
       _transport = transport,
       _cursorStore = cursorStore;

  final EventStore _localStore;
  final SyncTransport _transport;
  final SyncCursorStore _cursorStore;

  /// Max events per push/pull round-trip.
  final int batchSize;

  /// Pushes locally-new events, then pulls and merges remotely-new ones.
  ///
  /// A cursor only advances once the corresponding step has fully
  /// succeeded, so a failure partway through — a thrown
  /// [SyncTransportException] — leaves the cursors exactly where a retry
  /// picks up the same work. Nothing is lost; at worst, an already-pushed
  /// batch is resent, which [SyncTransport.push] must tolerate.
  Future<SyncResult> syncOnce() async {
    final cursors = await _cursorStore.read();

    final pushedThrough = await _pushPending(cursors.lastPushedLocalSequence);
    var progress = SyncCursors(
      lastPushedLocalSequence: pushedThrough.throughSequence,
      lastPulledRemoteSequence: cursors.lastPulledRemoteSequence,
    );
    await _cursorStore.write(progress);

    final pulled = await _pullNew(progress.lastPulledRemoteSequence);
    progress = SyncCursors(
      lastPushedLocalSequence: progress.lastPushedLocalSequence,
      lastPulledRemoteSequence: pulled.throughSequence,
    );
    await _cursorStore.write(progress);

    return SyncResult(
      pushedCount: pushedThrough.count,
      pulledCount: pulled.count,
    );
  }

  Future<_Progress> _pushPending(int from) async {
    final pending = await _localStore.readAll(afterSequence: from);
    var cursor = from;
    var sent = 0;
    for (final batch in _chunked(pending, batchSize)) {
      await _transport.push(batch.map((s) => s.event).toList());
      cursor = batch.last.sequence;
      sent += batch.length;
    }
    return _Progress(cursor, sent);
  }

  Future<_Progress> _pullNew(int from) async {
    var cursor = from;
    var newlyMerged = 0;
    while (true) {
      final page = await _transport.pull(
        afterSequence: cursor,
        limit: batchSize,
      );
      if (page.events.isEmpty) break;
      // page.events can include events this device pushed earlier in the
      // same syncOnce() — the remote doesn't know who a device already told
      // it something. merge()'s return value is the count actually new to
      // *this* store (eventId de-duplicated), which is what pulledCount
      // should report. Fetching them again is a little wasteful; fixing
      // that needs the transport to hand back the remote sequence it
      // assigned to a push, which is a reasonable next optimization, not
      // a correctness issue — merge() is idempotent either way.
      newlyMerged += await _localStore.merge(page.events);
      cursor = page.remoteSequence;
      if (page.events.length < batchSize) break; // that was the last page
    }
    return _Progress(cursor, newlyMerged);
  }
}

Iterable<List<T>> _chunked<T>(List<T> items, int size) sync* {
  for (var i = 0; i < items.length; i += size) {
    yield items.sublist(i, i + size > items.length ? items.length : i + size);
  }
}

class _Progress {
  const _Progress(this.throughSequence, this.count);

  final int throughSequence;
  final int count;
}
