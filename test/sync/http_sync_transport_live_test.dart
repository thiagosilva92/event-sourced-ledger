@Tags(['live_server'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/sync/sync.dart';

import '../eventsourcing/support/tally_fixture.dart';

/// Proves `HttpSyncTransport` actually talks to a real, running instance
/// of `ledger-sync-server` — a separate repository — not just that it
/// produces the right bytes against a mocked client (see
/// `http_sync_transport_test.dart` for that).
///
/// Not part of the default `flutter test` run (excluded via
/// `--exclude-tags=live_server`, same mechanism `benchmark` uses) because
/// it needs a real server listening. To run it:
///
/// ```bash
/// # In the ledger-sync-server repo:
/// docker compose up -d
///
/// # Back in this repo:
/// flutter test test/sync/http_sync_transport_live_test.dart --tags=live_server
/// ```
///
/// Uses the demo API key `docker-compose.yml` bakes into the gateway
/// (`demo-local-only-key`, hash `59b69b7c...` in that file) — never a
/// production key.
void main() {
  setUp(resetTallyFixture);

  test(
    'push then pull round-trips real events through the real server',
    () async {
      final transport = HttpSyncTransport(
        baseUrl: Uri.parse('http://localhost:8080'),
        apiKey: 'demo-local-only-key',
        registryFactory: buildTallyRegistry,
      );
      addTearDown(transport.close);

      // Drain to the current tip first: the server's Postgres volume
      // persists across runs, so "everything after 0" would also include
      // events a previous run of this same test already pushed.
      var startCursor = 0;
      while (true) {
        final page = await transport.pull(afterSequence: startCursor);
        if (page.events.isEmpty) break;
        startCursor = page.remoteSequence;
      }

      // Unique per run, so re-running this test never collides with a
      // previous run's aggregate on the same persisted server.
      final aggregateId = 'live-${DateTime.now().microsecondsSinceEpoch}';
      final t = Tally(aggregateId)
        ..start('live smoke test')
        ..add(3)
        ..add(4);

      await transport.push(t.pendingEvents);

      final result = await transport.pull(afterSequence: startCursor);

      expect(
        result.events.where((e) => e.aggregateId == aggregateId).length,
        3,
      );
      final pushedIds = t.pendingEvents.map((e) => e.eventId).toSet();
      final pulledIds = result.events
          .where((e) => e.aggregateId == aggregateId)
          .map((e) => e.eventId)
          .toSet();
      expect(pulledIds, pushedIds);
    },
  );

  test('an invalid API key is rejected, not silently accepted', () async {
    final transport = HttpSyncTransport(
      baseUrl: Uri.parse('http://localhost:8080'),
      apiKey: 'not-the-real-key',
      registryFactory: buildTallyRegistry,
    );
    addTearDown(transport.close);

    await expectLater(
      () => transport.pull(afterSequence: 0),
      throwsA(isA<SyncTransportException>()),
    );
  });
}
