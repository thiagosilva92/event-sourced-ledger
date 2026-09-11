import 'package:ledger/core/clock/hlc.dart';
import 'package:ledger/eventsourcing/eventsourcing.dart';

/// A minimal, domain-neutral aggregate/event/projection trio used to
/// exercise the event-sourcing core across multiple test files, without
/// depending on a real feature (there isn't one yet) and without
/// duplicating fixture code in every file that needs one.

int _seq = 0;

/// Resets the fixture's fake clock. Call from `setUp` in every test file
/// that uses `.raised()` so ids/timestamps don't leak across files.
void resetTallyFixture() => _seq = 0;

Hlc _nextTimestamp() =>
    Hlc(wallMillis: 1000 + _seq, counter: 0, nodeId: 'test');

String _nextEventId() => 'evt-${(_seq++).toString().padLeft(4, '0')}';

base class TallyStarted extends DomainEvent {
  const TallyStarted({
    required super.eventId,
    required super.aggregateId,
    required super.timestamp,
    required this.label,
  });

  /// Convenience for tests: a fresh event as if just raised locally.
  factory TallyStarted.raised({
    required String aggregateId,
    required String label,
  }) => TallyStarted(
    eventId: _nextEventId(),
    aggregateId: aggregateId,
    timestamp: _nextTimestamp(),
    label: label,
  );

  final String label;

  @override
  String get eventType => 'tally.started';

  @override
  Map<String, Object?> toPayload() => {'label': label};
}

base class TallyIncremented extends DomainEvent {
  const TallyIncremented({
    required super.eventId,
    required super.aggregateId,
    required super.timestamp,
    required this.by,
  });

  /// Convenience for tests: a fresh event as if just raised locally, or
  /// stamped with an explicit [at] to set up a specific HLC scenario.
  factory TallyIncremented.raised({
    required String aggregateId,
    required int by,
    Hlc? at,
  }) => TallyIncremented(
    eventId: _nextEventId(),
    aggregateId: aggregateId,
    timestamp: at ?? _nextTimestamp(),
    by: by,
  );

  final int by;

  @override
  String get eventType => 'tally.incremented';

  @override
  Map<String, Object?> toPayload() => {'by': by};
}

class Tally extends Aggregate<DomainEvent> {
  Tally(super.id);

  String label = '';
  int total = 0;
  bool _started = false;

  void start(String label) {
    if (_started) throw StateError('already started');
    raise(TallyStarted.raised(aggregateId: id, label: label));
  }

  void add(int amount) {
    if (!_started) throw StateError('not started');
    if (amount <= 0) throw ArgumentError('amount must be positive');
    raise(TallyIncremented.raised(aggregateId: id, by: amount));
  }

  @override
  void applyEvent(DomainEvent event) {
    switch (event) {
      case TallyStarted(:final label):
        this.label = label;
        _started = true;
      case TallyIncremented(:final by):
        total += by;
    }
  }
}

class GrandTotalProjection extends Projection<int> {
  int _total = 0;

  @override
  int get state => _total;

  @override
  void handle(DomainEvent event) {
    if (event is TallyIncremented) _total += event.by;
  }

  @override
  void clear() => _total = 0;
}

/// Registers deserializers for the fixture's events. Required by any
/// [EventStore] that actually persists and reconstructs events (e.g.
/// `DriftEventStore`) rather than keeping the original Dart objects around,
/// the way `InMemoryEventStore` does.
extension RegisterTallyEvents on EventRegistry {
  void registerTallyEvents() {
    register(
      'tally.started',
      (meta, payload) => TallyStarted(
        eventId: meta.eventId,
        aggregateId: meta.aggregateId,
        timestamp: meta.timestamp,
        label: payload['label']! as String,
      ),
    );
    register(
      'tally.incremented',
      (meta, payload) => TallyIncremented(
        eventId: meta.eventId,
        aggregateId: meta.aggregateId,
        timestamp: meta.timestamp,
        by: payload['by']! as int,
      ),
    );
  }
}
