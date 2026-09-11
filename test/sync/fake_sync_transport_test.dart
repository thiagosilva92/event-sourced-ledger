import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/eventsourcing/eventsourcing.dart';
import 'package:ledger/sync/sync.dart';

import '../eventsourcing/support/tally_fixture.dart';

void main() {
  setUp(resetTallyFixture);

  late InMemoryEventStore remoteStore;
  late FakeSyncTransport transport;

  setUp(() {
    remoteStore = InMemoryEventStore();
    transport = FakeSyncTransport(
      remoteStore,
      EventRegistry()..registerTallyEvents(),
    );
  });
  tearDown(() => remoteStore.dispose());

  test('push round-trips events through JSON into the remote store', () async {
    final event = TallyStarted.raised(aggregateId: 't1', label: 'x');

    await transport.push([event]);

    final stored = await remoteStore.readAggregate('t1');
    expect(stored, hasLength(1));
    expect(stored.single, event); // == compares by eventId
    expect((stored.single as TallyStarted).label, 'x');
  });

  test('push of an empty list is a no-op', () async {
    await transport.push(const []);
    expect(await remoteStore.latestSequence(), 0);
  });

  test(
    'pull returns nothing and an unchanged cursor when there is nothing new',
    () async {
      final result = await transport.pull(afterSequence: 0);
      expect(result.events, isEmpty);
      expect(result.remoteSequence, 0);
    },
  );

  test('pull returns new events and the new cursor', () async {
    final t = Tally('t1')
      ..start('x')
      ..add(1);
    await remoteStore.append('t1', t.pendingEvents);

    final result = await transport.pull(afterSequence: 0);

    expect(result.events.map((e) => e.eventType), [
      'tally.started',
      'tally.incremented',
    ]);
    expect(result.remoteSequence, 2);
  });

  test('pull respects limit and returns a resumable cursor', () async {
    final t = Tally('t1')
      ..start('x')
      ..add(1)
      ..add(1)
      ..add(1);
    await remoteStore.append('t1', t.pendingEvents);

    final firstPage = await transport.pull(afterSequence: 0, limit: 2);
    expect(firstPage.events, hasLength(2));
    expect(firstPage.remoteSequence, 2);

    final secondPage = await transport.pull(
      afterSequence: firstPage.remoteSequence,
      limit: 2,
    );
    expect(secondPage.events, hasLength(2));
    expect(secondPage.remoteSequence, 4);
  });

  test(
    'decoding an unregistered event type fails loudly, not silently',
    () async {
      final registryWithoutTally = EventRegistry();
      final strictTransport = FakeSyncTransport(
        remoteStore,
        registryWithoutTally,
      );
      final event = TallyStarted.raised(aggregateId: 't1', label: 'x');

      expect(
        () => strictTransport.push([event]),
        throwsA(isA<UnknownEventTypeError>()),
      );
    },
  );

  group('failNextCalls', () {
    test(
      'throws SyncTransportException the configured number of times',
      () async {
        transport.failNextCalls = 2;
        final event = TallyStarted.raised(aggregateId: 't1', label: 'x');

        await expectLater(
          () => transport.push([event]),
          throwsA(isA<SyncTransportException>()),
        );
        await expectLater(
          () => transport.push([event]),
          throwsA(isA<SyncTransportException>()),
        );
        await transport.push([event]); // third call succeeds

        expect(await remoteStore.readAggregate('t1'), hasLength(1));
      },
    );
  });
}
