import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ledger/eventsourcing/eventsourcing.dart';
import 'package:ledger/sync/sync.dart';

import '../eventsourcing/support/tally_fixture.dart';

/// These tests never touch a real network — [MockClient] intercepts every
/// request and asserts the exact wire format `ledger-sync-server`'s
/// `EventsEndpoints.cs` expects and returns. A separate, real end-to-end
/// proof against the actual server (running via that repo's
/// docker-compose) lives in `http_sync_transport_live_test.dart`, tagged
/// so it doesn't run as part of the normal suite.
void main() {
  setUp(resetTallyFixture);

  final baseUrl = Uri.parse('https://sync.example.test');

  HttpSyncTransport buildTransport(
    Future<http.Response> Function(http.Request) handler, {
    Duration timeout = const Duration(seconds: 5),
  }) => HttpSyncTransport(
    baseUrl: baseUrl,
    apiKey: 'test-key',
    registryFactory: buildTallyRegistry,
    client: MockClient(handler),
    timeout: timeout,
  );

  group('push', () {
    test('sends the events as a JSON array, keyed by X-Api-Key', () async {
      http.Request? captured;
      final transport = buildTransport((request) async {
        captured = request;
        return http.Response('{"insertedCount":1}', 200);
      });
      final event = TallyStarted.raised(aggregateId: 't1', label: 'x');

      await transport.push([event]);

      expect(captured!.method, 'POST');
      expect(captured!.url, Uri.parse('https://sync.example.test/events'));
      expect(captured!.headers['X-Api-Key'], 'test-key');
      expect(captured!.headers['Content-Type'], contains('application/json'));

      final body = jsonDecode(captured!.body) as List;
      expect(body, hasLength(1));
      final sent = (body.single as Map).cast<String, Object?>();
      expect(sent['eventId'], event.eventId);
      expect(sent['eventType'], 'tally.started');
      expect((sent['payload']! as Map)['label'], 'x');
    });

    test('an empty list makes no HTTP call', () async {
      var callCount = 0;
      final transport = buildTransport((request) async {
        callCount++;
        return http.Response('{"insertedCount":0}', 200);
      });

      await transport.push(const []);

      expect(callCount, 0);
    });

    test('a non-2xx response throws SyncTransportException', () async {
      final transport = buildTransport(
        (request) async => http.Response('server exploded', 500),
      );
      final event = TallyStarted.raised(aggregateId: 't1', label: 'x');

      await expectLater(
        () => transport.push([event]),
        throwsA(isA<SyncTransportException>()),
      );
    });

    test('a network error throws SyncTransportException', () async {
      final transport = buildTransport(
        (request) async => throw const SocketException('connection refused'),
      );
      final event = TallyStarted.raised(aggregateId: 't1', label: 'x');

      await expectLater(
        () => transport.push([event]),
        throwsA(isA<SyncTransportException>()),
      );
    });

    test('a stalled server throws SyncTransportException on timeout', () async {
      final transport = buildTransport((request) async {
        await Future<void>.delayed(const Duration(seconds: 2));
        return http.Response('{"insertedCount":1}', 200);
      }, timeout: const Duration(milliseconds: 50));
      final event = TallyStarted.raised(aggregateId: 't1', label: 'x');

      await expectLater(
        () => transport.push([event]),
        throwsA(isA<SyncTransportException>()),
      );
    });
  });

  group('pull', () {
    test('sends the cursor and limit as query parameters', () async {
      http.Request? captured;
      final transport = buildTransport((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'events': <Object?>[], 'remoteSequence': 7}),
          200,
        );
      });

      await transport.pull(afterSequence: 7, limit: 50);

      expect(captured!.method, 'GET');
      expect(captured!.url.path, '/events');
      expect(captured!.url.queryParameters['after'], '7');
      expect(captured!.url.queryParameters['limit'], '50');
      expect(captured!.headers['X-Api-Key'], 'test-key');
    });

    test('decodes returned events back into domain events', () async {
      final t = Tally('t1')
        ..start('x')
        ..add(1);
      final onWire = t.pendingEvents
          .map(EventCodec(buildTallyRegistry()).encode)
          .toList();
      final transport = buildTransport(
        (request) async => http.Response(
          jsonEncode({'events': onWire, 'remoteSequence': 2}),
          200,
        ),
      );

      final result = await transport.pull(afterSequence: 0);

      expect(result.events.map((e) => e.eventType), [
        'tally.started',
        'tally.incremented',
      ]);
      expect(result.remoteSequence, 2);
    });

    test('an empty page returns an unchanged cursor, not an error', () async {
      final transport = buildTransport(
        (request) async => http.Response(
          jsonEncode({'events': <Object?>[], 'remoteSequence': 3}),
          200,
        ),
      );

      final result = await transport.pull(afterSequence: 3);

      expect(result.events, isEmpty);
      expect(result.remoteSequence, 3);
    });

    test('a non-2xx response throws SyncTransportException', () async {
      final transport = buildTransport(
        (request) async => http.Response('unauthorized', 401),
      );

      await expectLater(
        () => transport.pull(afterSequence: 0),
        throwsA(isA<SyncTransportException>()),
      );
    });

    test('an unregistered event type fails loudly, not silently', () async {
      final t = Tally('t1')..start('x');
      final onWire = t.pendingEvents
          .map(EventCodec(buildTallyRegistry()).encode)
          .toList();
      final strictTransport = HttpSyncTransport(
        baseUrl: baseUrl,
        apiKey: 'test-key',
        registryFactory: EventRegistry.new,
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({'events': onWire, 'remoteSequence': 1}),
            200,
          ),
        ),
      );

      await expectLater(
        () => strictTransport.pull(afterSequence: 0),
        throwsA(isA<UnknownEventTypeError>()),
      );
    });
  });
}
