import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/clock/hlc.dart';
import 'package:ledger/eventsourcing/eventsourcing.dart';
import 'package:ledger/sync/sync.dart';

import '../eventsourcing/support/tally_fixture.dart';

/// One simulated device: its own local store, syncing against a shared
/// remote store through its own [FakeSyncTransport] and cursor.
class _Device {
  _Device(EventStore remote)
    : local = InMemoryEventStore(),
      _transport = FakeSyncTransport(
        remote,
        EventRegistry()..registerTallyEvents(),
      ),
      cursors = InMemorySyncCursorStore() {
    service = SyncService(
      localStore: local,
      transport: _transport,
      cursorStore: cursors,
    );
  }

  final InMemoryEventStore local;
  final FakeSyncTransport _transport;
  final InMemorySyncCursorStore cursors;
  late final SyncService service;

  int get failNextCalls => _transport.failNextCalls;
  set failNextCalls(int n) => _transport.failNextCalls = n;

  Future<void> dispose() => local.dispose();
}

void main() {
  setUp(resetTallyFixture);

  late InMemoryEventStore remote;

  setUp(() => remote = InMemoryEventStore());
  tearDown(() => remote.dispose());

  test('pushes local pending events to an empty remote', () async {
    final device = _Device(remote);
    addTearDown(device.dispose);
    final t = Tally('t1')
      ..start('x')
      ..add(1);
    await device.local.append('t1', t.pendingEvents);

    final result = await device.service.syncOnce();

    expect(result.pushedCount, 2);
    expect(result.pulledCount, 0);
    expect(await remote.readAggregate('t1'), hasLength(2));
  });

  test('pulls events another device already pushed to the remote', () async {
    final deviceA = _Device(remote);
    final deviceB = _Device(remote);
    addTearDown(deviceA.dispose);
    addTearDown(deviceB.dispose);

    final t = Tally('t1')..start('groceries');
    await deviceA.local.append('t1', t.pendingEvents);
    await deviceA.service.syncOnce();

    final result = await deviceB.service.syncOnce();

    expect(result.pulledCount, 1);
    final onB = await deviceB.local.readAggregate('t1');
    expect(onB, hasLength(1));
    expect((onB.single as TallyStarted).label, 'groceries');
  });

  test('two devices converge to the same events after syncing through the '
      'shared remote', () async {
    final deviceA = _Device(remote);
    final deviceB = _Device(remote);
    addTearDown(deviceA.dispose);
    addTearDown(deviceB.dispose);

    // Both create different events while offline from each other.
    final onA = Tally('t1')
      ..start('shared tab')
      ..add(10);
    await deviceA.local.append('t1', onA.pendingEvents);

    final onB = Tally('t2')..start('groceries');
    await deviceB.local.append('t2', onB.pendingEvents);

    // A syncs first (pushes its events, nothing to pull yet).
    await deviceA.service.syncOnce();
    // B syncs (pushes its own events, pulls A's).
    await deviceB.service.syncOnce();
    // A syncs again to pick up B's events.
    await deviceA.service.syncOnce();

    final idsOnA = (await deviceA.local.readAll())
        .map((s) => s.event.eventId)
        .toSet();
    final idsOnB = (await deviceB.local.readAll())
        .map((s) => s.event.eventId)
        .toSet();
    final idsOnRemote = (await remote.readAll())
        .map((s) => s.event.eventId)
        .toSet();

    expect(idsOnA, idsOnB);
    expect(idsOnA, idsOnRemote);
    expect(idsOnA, hasLength(3)); // 1 started + 1 incremented + 1 started
  });

  test('repeated syncOnce with no new events is a no-op', () async {
    final device = _Device(remote);
    addTearDown(device.dispose);
    final t = Tally('t1')..start('x');
    await device.local.append('t1', t.pendingEvents);
    await device.service.syncOnce();

    final result = await device.service.syncOnce();

    expect(result.pushedCount, 0);
    expect(result.pulledCount, 0);
  });

  test(
    'a failed push does not advance the cursor; the retry succeeds',
    () async {
      final device = _Device(remote);
      addTearDown(device.dispose);
      final t = Tally('t1')..start('x');
      await device.local.append('t1', t.pendingEvents);

      device.failNextCalls = 1;
      await expectLater(
        device.service.syncOnce,
        throwsA(isA<SyncTransportException>()),
      );
      expect(await remote.readAggregate('t1'), isEmpty);

      final result = await device.service.syncOnce();

      expect(result.pushedCount, 1);
      expect(await remote.readAggregate('t1'), hasLength(1));
    },
  );

  test('events that tie on wallMillis/counter but differ by nodeId both '
      'arrive via sync, even though a scalar readSince cursor would drop '
      'one — see EventStore.readSince and SyncService doc comments', () async {
    final deviceA = _Device(remote);
    final deviceB = _Device(remote);
    final observer = _Device(remote); // a third device, pulls everything
    addTearDown(deviceA.dispose);
    addTearDown(deviceB.dispose);
    addTearDown(observer.dispose);

    const tiedWallMillis = 5000;
    const tiedCounter = 2;
    final fromA = TallyIncremented.raised(
      aggregateId: 't1',
      by: 1,
      at: const Hlc(
        wallMillis: tiedWallMillis,
        counter: tiedCounter,
        nodeId: 'aaa-device',
      ),
    );
    final fromZ = TallyIncremented.raised(
      aggregateId: 't1',
      by: 2,
      at: const Hlc(
        wallMillis: tiedWallMillis,
        counter: tiedCounter,
        nodeId: 'zzz-device',
      ),
    );

    await deviceA.local.append('t1', [fromA]);
    await deviceA.service.syncOnce(); // remote sequence 1: fromA

    await deviceB.local.append('t1', [fromZ]);
    await deviceB.service.syncOnce(); // remote sequence 2: fromZ

    await observer.service.syncOnce();

    final observedIds = (await observer.local.readAggregate('t1'))
        .map((e) => e.eventId)
        .toSet();
    expect(observedIds, {fromA.eventId, fromZ.eventId});
  });
}
