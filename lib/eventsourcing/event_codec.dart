import 'dart:convert';

import 'package:ledger/core/clock/hlc.dart';
import 'package:ledger/eventsourcing/domain_event.dart';

/// Converts a [DomainEvent] to and from a JSON-safe map.
///
/// This is the one place that defines what an event looks like on the wire.
/// `sync/` uses it to serialize events for `SyncTransport`; a real transport
/// (HTTP to the .NET sync server) would use exactly the same shape. Deriving
/// events back from a decoded map always goes through [EventRegistry], so a
/// peer that hasn't registered a given `eventType` fails loudly instead of
/// silently dropping data it doesn't understand.
class EventCodec {
  const EventCodec(this._registry);

  final EventRegistry _registry;

  /// Encodes [event] into a flat, JSON-encodable map.
  Map<String, Object?> encode(DomainEvent event) => {
    'eventId': event.eventId,
    'aggregateId': event.aggregateId,
    'eventType': event.eventType,
    'timestamp': event.timestamp.toString(),
    'payload': event.toPayload(),
  };

  /// The inverse of [encode].
  DomainEvent decode(Map<String, Object?> data) {
    final metadata = EventMetadata(
      eventId: data['eventId']! as String,
      aggregateId: data['aggregateId']! as String,
      timestamp: Hlc.parse(data['timestamp']! as String),
    );
    final payload = (data['payload']! as Map).cast<String, Object?>();
    final eventType = data['eventType']! as String;
    return _registry.deserialize(eventType, metadata, payload);
  }

  /// [encode] then JSON-stringify.
  String encodeToJson(DomainEvent event) => jsonEncode(encode(event));

  /// The inverse of [encodeToJson].
  DomainEvent decodeFromJson(String json) =>
      decode((jsonDecode(json) as Map).cast<String, Object?>());
}
