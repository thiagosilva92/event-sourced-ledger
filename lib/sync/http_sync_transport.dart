import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:ledger/eventsourcing/domain_event.dart';
import 'package:ledger/eventsourcing/event_codec.dart';
import 'package:ledger/sync/sync_transport.dart';

/// Talks to the real sync server — `ledger-sync-server`, kept in a
/// separate repository (see docs/adr/0007-sync-server-separate-repository.md)
/// — over HTTP, implementing the same [SyncTransport] contract
/// `FakeSyncTransport` plays in-process for tests and local development.
///
/// The wire format is not invented here: [EventCodec.encode] already
/// produces the flat `{eventId, aggregateId, eventType, timestamp,
/// payload}` map that server's `POST /events` expects (it reads only
/// `eventId` and stores the rest verbatim) and returns unchanged from
/// `GET /events` — the exact shape [EventCodec.decode] expects back.
class HttpSyncTransport implements SyncTransport {
  /// [registryFactory] must be a **top-level or static function**, not a
  /// method tear-off or closure capturing anything — [pull] hands it to
  /// [EventCodec.decodeManyFromJson], which sends it unevaluated to a
  /// worker isolate for large batches. Same requirement as
  /// `FakeSyncTransport` and `DriftEventStore`.
  HttpSyncTransport({
    required Uri baseUrl,
    required String apiKey,
    required EventRegistry Function() registryFactory,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _baseUrl = baseUrl,
       _apiKey = apiKey,
       _registryFactory = registryFactory,
       _codec = EventCodec(registryFactory()),
       _client = client ?? http.Client();

  final Uri _baseUrl;
  final String _apiKey;
  final EventRegistry Function() _registryFactory;
  final EventCodec _codec;
  final http.Client _client;

  /// Applied to every request. The server itself has no notion of a
  /// client-side timeout; this is purely so a stalled connection surfaces
  /// as a retryable [SyncTransportException] instead of hanging the sync
  /// cycle indefinitely.
  final Duration timeout;

  @override
  Future<void> push(List<DomainEvent> events) async {
    if (events.isEmpty) return;
    final body = jsonEncode(events.map(_codec.encode).toList());
    final response = await _send(
      () => _client.post(_eventsUri(), headers: _headers, body: body),
    );
    _throwUnlessOk(response, context: 'push');
  }

  @override
  Future<PulledBatch> pull({
    required int afterSequence,
    int limit = 200,
  }) async {
    final uri = _eventsUri(
      queryParameters: {'after': '$afterSequence', 'limit': '$limit'},
    );
    final response = await _send(() => _client.get(uri, headers: _headers));
    _throwUnlessOk(response, context: 'pull');

    final decodedBody = jsonDecode(response.body) as Map<String, Object?>;
    final rawEvents = (decodedBody['events']! as List)
        .cast<Map<String, Object?>>();
    final remoteSequence = (decodedBody['remoteSequence']! as num).toInt();
    if (rawEvents.isEmpty) return PulledBatch(const [], remoteSequence);

    // Re-stringify each event so the same isolate-offload threshold logic
    // FakeSyncTransport and DriftEventStore.readAll use applies here too,
    // via one shared implementation rather than a third copy of it.
    final jsonPayloads = rawEvents.map(jsonEncode).toList();
    final decoded = await EventCodec.decodeManyFromJson(
      jsonPayloads,
      _registryFactory,
    );
    return PulledBatch(decoded, remoteSequence);
  }

  Uri _eventsUri({Map<String, String>? queryParameters}) {
    final path = _baseUrl.path.endsWith('/')
        ? '${_baseUrl.path}events'
        : '${_baseUrl.path}/events';
    return _baseUrl.replace(path: path, queryParameters: queryParameters);
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'X-Api-Key': _apiKey,
  };

  /// Maps every failure mode — network, timeout, and (see
  /// [_throwUnlessOk]) a non-2xx response, auth failures included — onto
  /// [SyncTransportException]. [SyncTransport]'s contract defines only
  /// one exception type for "retry on the next sync"; a 401 from a
  /// misconfigured key would currently retry forever exactly like a
  /// dropped connection would, which is a real, known limitation of that
  /// single-exception design, not something this transport works around
  /// on its own.
  Future<http.Response> _send(Future<http.Response> Function() call) async {
    try {
      return await call().timeout(timeout);
    } on TimeoutException catch (e) {
      throw SyncTransportException('timed out: $e');
    } on SocketException catch (e) {
      throw SyncTransportException('network error: $e');
    } on http.ClientException catch (e) {
      throw SyncTransportException('client error: $e');
    }
  }

  void _throwUnlessOk(http.Response response, {required String context}) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SyncTransportException(
        '$context failed: HTTP ${response.statusCode} ${response.body}',
      );
    }
  }

  /// Releases the underlying HTTP client's resources (connection pool).
  /// Call once when this transport is no longer needed — not after every
  /// sync cycle.
  void close() => _client.close();
}
