import 'package:ledger/core/clock/hlc.dart';
import 'package:meta/meta.dart';

/// Base type for every fact the system records.
///
/// A domain event is immutable and past-tense: it describes something that
/// already happened. State (balances, reports) is always derived by folding
/// events — never stored directly and never mutated.
@immutable
abstract base class DomainEvent {
  const DomainEvent({
    required this.eventId,
    required this.aggregateId,
    required this.timestamp,
  });

  /// Globally unique, time-ordered id (UUID v7). Used to de-duplicate events
  /// that arrive more than once during sync.
  final String eventId;

  /// Id of the aggregate this event belongs to.
  final String aggregateId;

  /// Hybrid Logical Clock timestamp establishing causal order across devices.
  final Hlc timestamp;

  /// Stable discriminator used to persist and rehydrate the event. Must be
  /// unique across the whole application and must never change once shipped.
  String get eventType;

  /// The event-specific payload, without the metadata above.
  Map<String, Object?> toPayload();

  @override
  bool operator ==(Object other) =>
      other is DomainEvent && other.eventId == eventId;

  @override
  int get hashCode => eventId.hashCode;

  @override
  String toString() => '$eventType($aggregateId @ $timestamp)';
}

/// Rebuilds a [DomainEvent] from its persisted form.
typedef EventDeserializer =
    DomainEvent Function(EventMetadata metadata, Map<String, Object?> payload);

/// Metadata common to every persisted event, separated from the payload.
@immutable
final class EventMetadata {
  const EventMetadata({
    required this.eventId,
    required this.aggregateId,
    required this.timestamp,
  });

  final String eventId;
  final String aggregateId;
  final Hlc timestamp;
}

/// Thrown when the store is asked to rehydrate an event type nobody registered.
class UnknownEventTypeError extends Error {
  UnknownEventTypeError(this.eventType);

  final String eventType;

  @override
  String toString() =>
      'UnknownEventTypeError: no deserializer registered for "$eventType". '
      'Did you forget to call EventRegistry.register in a feature module?';
}

/// Maps `eventType` strings to the code that can rebuild them.
///
/// Each feature module registers its own events at startup, so the core has
/// no compile-time dependency on feature event classes.
class EventRegistry {
  final Map<String, EventDeserializer> _deserializers = {};

  Iterable<String> get registeredTypes => _deserializers.keys;

  void register(String eventType, EventDeserializer deserializer) {
    if (_deserializers.containsKey(eventType)) {
      throw StateError('event type "$eventType" is already registered');
    }
    _deserializers[eventType] = deserializer;
  }

  DomainEvent deserialize(
    String eventType,
    EventMetadata metadata,
    Map<String, Object?> payload,
  ) {
    final deserializer = _deserializers[eventType];
    if (deserializer == null) throw UnknownEventTypeError(eventType);
    return deserializer(metadata, payload);
  }
}
