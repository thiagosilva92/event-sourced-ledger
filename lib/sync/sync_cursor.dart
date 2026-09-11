import 'package:meta/meta.dart';

/// How far this device has gotten with the (currently: one) remote it syncs
/// with, in each direction.
///
/// Both numbers are *sequence* cursors — the local `EventStore`'s own
/// gapless insertion order, or the remote's equivalent — never an `Hlc`.
/// See `SyncService`'s doc comment for why that distinction is the whole
/// point.
@immutable
final class SyncCursors {
  const SyncCursors({
    required this.lastPushedLocalSequence,
    required this.lastPulledRemoteSequence,
  });

  static const zero = SyncCursors(
    lastPushedLocalSequence: 0,
    lastPulledRemoteSequence: 0,
  );

  /// Local events up to and including this sequence have been pushed.
  final int lastPushedLocalSequence;

  /// Remote events up to and including this (remote) sequence have been
  /// pulled and merged locally.
  final int lastPulledRemoteSequence;

  @override
  bool operator ==(Object other) =>
      other is SyncCursors &&
      other.lastPushedLocalSequence == lastPushedLocalSequence &&
      other.lastPulledRemoteSequence == lastPulledRemoteSequence;

  @override
  int get hashCode =>
      Object.hash(lastPushedLocalSequence, lastPulledRemoteSequence);

  @override
  String toString() =>
      'SyncCursors(pushed: $lastPushedLocalSequence, '
      'pulled: $lastPulledRemoteSequence)';
}

/// Persists [SyncCursors] across app restarts.
abstract interface class SyncCursorStore {
  /// Returns [SyncCursors.zero] if nothing has been synced yet.
  Future<SyncCursors> read();

  Future<void> write(SyncCursors cursors);
}

/// In-memory [SyncCursorStore] for tests.
class InMemorySyncCursorStore implements SyncCursorStore {
  SyncCursors _cursors = SyncCursors.zero;

  @override
  Future<SyncCursors> read() async => _cursors;

  @override
  Future<void> write(SyncCursors cursors) async => _cursors = cursors;
}
