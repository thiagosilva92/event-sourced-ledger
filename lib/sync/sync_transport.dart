import 'package:ledger/eventsourcing/domain_event.dart';
import 'package:meta/meta.dart';

/// Thrown by a [SyncTransport] for anything that should be treated as a
/// transient failure — worth retrying on the next sync, not a bug.
class SyncTransportException implements Exception {
  SyncTransportException(this.message);

  final String message;

  @override
  String toString() => 'SyncTransportException: $message';
}

/// One page pulled from the remote.
@immutable
final class PulledBatch {
  const PulledBatch(this.events, this.remoteSequence);

  /// Events the remote had after the requested cursor, in remote order.
  final List<DomainEvent> events;

  /// The remote's own sequence number to resume from on the next pull.
  /// Opaque to the caller: never compare this across different remotes or
  /// devices, only pass it back to [SyncTransport.pull].
  final int remoteSequence;
}

/// What the sync engine needs from "the server" (or a peer), independent of
/// how the bytes actually travel. `FakeSyncTransport` implements this
/// in-process for development and tests; a real implementation would speak
/// HTTP to the .NET sync server.
///
/// Both methods must be safe to retry: a caller that doesn't know whether a
/// previous call actually reached the remote (e.g. the response was lost)
/// will call again with the same arguments.
abstract interface class SyncTransport {
  /// Sends locally-new events to the remote. The remote de-duplicates by
  /// `eventId`, so sending the same event twice is harmless.
  ///
  /// Throws [SyncTransportException] on a transient failure (network,
  /// timeout). The caller does not advance its push cursor when this
  /// throws, so the same batch is retried on the next sync.
  Future<void> push(List<DomainEvent> events);

  /// Fetches events the remote has after [afterSequence], in the remote's
  /// own sequence numbering — never the same numbering as this device's
  /// local `EventStore`, and never derived from `Hlc`. See `SyncService`'s
  /// doc comment for why a sequence cursor, not an `Hlc` cursor, is what
  /// makes sync correct under concurrent writers.
  ///
  /// Throws [SyncTransportException] on a transient failure.
  Future<PulledBatch> pull({required int afterSequence, int limit = 200});
}
