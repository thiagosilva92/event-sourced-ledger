import 'package:ledger/eventsourcing/domain_event.dart';

/// Base class for a write-model aggregate.
///
/// An aggregate is rebuilt from its event history, then guards invariants
/// while producing new events. It never talks to infrastructure — command
/// handlers load history into it and persist the events it raises.
///
/// Subclasses implement [applyEvent] as a pure state mutation and call
/// [raise] from their command methods.
abstract class Aggregate<E extends DomainEvent> {
  Aggregate(this.id);

  /// Aggregate identity, shared by every event in its stream.
  final String id;

  int _version = 0;
  final List<E> _pending = [];

  /// Number of events that have been applied (from history + newly raised).
  int get version => _version;

  /// Events raised since the last [markEventsCommitted]; what the command
  /// handler must persist.
  List<E> get pendingEvents => List.unmodifiable(_pending);

  bool get hasPendingEvents => _pending.isNotEmpty;

  /// Replays persisted [history] to restore current state. Does not mark the
  /// events as pending.
  void loadFromHistory(Iterable<E> history) {
    if (_version != 0 || _pending.isNotEmpty) {
      throw StateError('loadFromHistory called on a non-fresh aggregate');
    }
    for (final event in history) {
      _requireOwnEvent(event);
      applyEvent(event);
      _version++;
    }
  }

  /// Restores state from a [snapshotVersion] and the events that came after.
  void loadFromSnapshot(int snapshotVersion, Iterable<E> tail) {
    if (_version != 0 || _pending.isNotEmpty) {
      throw StateError('loadFromSnapshot called on a non-fresh aggregate');
    }
    _version = snapshotVersion;
    for (final event in tail) {
      _requireOwnEvent(event);
      applyEvent(event);
      _version++;
    }
  }

  /// Applies [event] to current state and queues it for persistence.
  void raise(E event) {
    _requireOwnEvent(event);
    applyEvent(event);
    _version++;
    _pending.add(event);
  }

  /// Called by the command handler once [pendingEvents] have been stored.
  void markEventsCommitted() => _pending.clear();

  /// Pure state transition for [event]. Must not throw for events that were
  /// already accepted once — replay has to be deterministic.
  void applyEvent(E event);

  void _requireOwnEvent(E event) {
    if (event.aggregateId != id) {
      throw ArgumentError(
        'event ${event.eventType} targets ${event.aggregateId}, not $id',
      );
    }
  }
}
