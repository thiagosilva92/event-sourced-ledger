import 'package:ledger/eventsourcing/domain_event.dart';
import 'package:ledger/eventsourcing/event_store.dart';

/// A read model derived by folding the event log.
///
/// A projection is write-only from the domain's point of view: it consumes
/// events and exposes a query-friendly [state]. It must be able to rebuild
/// itself from scratch, so [apply] has to be deterministic and depend only on
/// the order of events it is handed.
abstract class Projection<S> {
  int _lastSequence = 0;

  /// Current read-model state.
  S get state;

  /// The last global sequence number folded in. `0` means nothing yet.
  int get lastSequence => _lastSequence;

  /// Folds one event (with its store sequence) into [state].
  ///
  /// The runner guarantees events arrive in ascending sequence order and
  /// never twice. Subclasses override [handle]; this method also advances
  /// [lastSequence].
  void apply(int sequence, DomainEvent event) {
    handle(event);
    _lastSequence = sequence;
  }

  /// Event-type-specific folding. Ignore anything not relevant to this
  /// projection.
  void handle(DomainEvent event);

  /// Discards derived state, returning the projection to empty.
  void reset() {
    _lastSequence = 0;
    clear();
  }

  /// Subclass hook to wipe [state] back to its empty value.
  void clear();
}

/// Drives one or more [Projection]s from an [EventStore]: an initial rebuild
/// followed by incremental catch-up.
class ProjectionRunner {
  ProjectionRunner(this._store, this._projections);

  final EventStore _store;
  final List<Projection<Object?>> _projections;

  /// Replays the entire log into every projection from scratch.
  Future<void> rebuild() async {
    for (final projection in _projections) {
      projection.reset();
    }
    await _drain(afterSequence: 0);
  }

  /// Applies only what was appended since the projections last folded.
  Future<void> catchUp() async {
    if (_projections.isEmpty) return;
    final from = _projections
        .map((p) => p.lastSequence)
        .reduce((a, b) => a < b ? a : b);
    await _drain(afterSequence: from);
  }

  Future<void> _drain({required int afterSequence}) async {
    final events = await _store.readAll(afterSequence: afterSequence);
    for (final sequenced in events) {
      for (final projection in _projections) {
        if (sequenced.sequence > projection.lastSequence) {
          projection.apply(sequenced.sequence, sequenced.event);
        }
      }
    }
  }
}
