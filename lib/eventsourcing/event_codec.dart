import 'dart:convert';
import 'dart:isolate';

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

  /// Below this many payloads, decoding inline is faster than the fixed
  /// cost of spawning a worker isolate (a few ms) — the same threshold, for
  /// the same reason, as `DriftEventStore._isolateDecodeThreshold`: JSON
  /// decode plus registry dispatch is the same shape of work in both
  /// places, just fed by a sync pull's incoming batch here instead of a
  /// database read there.
  static const _isolateDecodeThreshold = 500;

  /// Decodes a batch of wire strings (as produced by [encodeToJson]),
  /// offloading to a worker isolate once the batch is large enough to make
  /// that worthwhile — mirrors `DriftEventStore._decodeInWorkerIsolate` for
  /// exactly the same reason: a `SyncTransport.pull()` that decodes a large
  /// incoming batch synchronously blocks whatever isolate is driving the
  /// UI for as long as that decode takes, sync running in the background
  /// or not.
  ///
  /// [registryFactory] must be a **top-level or static function**, not a
  /// method tear-off or a closure capturing anything — see
  /// `DriftEventStore`'s constructor doc comment for the full reasoning.
  /// It's called once here for small batches, and again inside the worker
  /// isolate for large ones; either way, the [EventCodec] this method
  /// itself was called on is never the one used to decode — only
  /// [registryFactory] and [jsonPayloads] cross the isolate boundary, both
  /// plain data.
  static Future<List<DomainEvent>> decodeManyFromJson(
    List<String> jsonPayloads,
    EventRegistry Function() registryFactory,
  ) async {
    if (jsonPayloads.length < _isolateDecodeThreshold) {
      final codec = EventCodec(registryFactory());
      return jsonPayloads.map(codec.decodeFromJson).toList();
    }
    final decoded = await Isolate.run(() {
      final codec = EventCodec(registryFactory());
      return jsonPayloads.map(codec.decodeFromJson).toList();
    });
    return decoded;
  }
}
