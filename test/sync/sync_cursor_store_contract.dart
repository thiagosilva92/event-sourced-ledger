import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/sync/sync.dart';

/// Behavioral contract every [SyncCursorStore] implementation must satisfy —
/// the same pattern as `test/eventsourcing/event_store_contract.dart`, so
/// `InMemorySyncCursorStore` (tests) and `DriftSyncCursorStore` (the app)
/// can't quietly drift apart.
void runSyncCursorStoreContractTests(SyncCursorStore Function() createStore) {
  late SyncCursorStore store;

  setUp(() => store = createStore());

  test('reads zero cursors when nothing has been written yet', () async {
    expect(await store.read(), SyncCursors.zero);
  });

  test('write then read round-trips exactly', () async {
    const cursors = SyncCursors(
      lastPushedLocalSequence: 12,
      lastPulledRemoteSequence: 7,
    );
    await store.write(cursors);
    expect(await store.read(), cursors);
  });

  test('a second write overwrites the first, not merges with it', () async {
    await store.write(
      const SyncCursors(
        lastPushedLocalSequence: 1,
        lastPulledRemoteSequence: 1,
      ),
    );
    await store.write(
      const SyncCursors(
        lastPushedLocalSequence: 99,
        lastPulledRemoteSequence: 42,
      ),
    );

    expect(
      await store.read(),
      const SyncCursors(
        lastPushedLocalSequence: 99,
        lastPulledRemoteSequence: 42,
      ),
    );
  });

  test('repeated writes of the same value are idempotent', () async {
    const cursors = SyncCursors(
      lastPushedLocalSequence: 5,
      lastPulledRemoteSequence: 5,
    );
    await store.write(cursors);
    await store.write(cursors);
    await store.write(cursors);
    expect(await store.read(), cursors);
  });
}
