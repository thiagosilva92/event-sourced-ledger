import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/eventsourcing/eventsourcing.dart';

import 'support/tally_fixture.dart';

void main() {
  group('ProjectionRunner', () {
    late InMemoryEventStore store;
    late GrandTotalProjection projection;
    late ProjectionRunner runner;

    setUp(() {
      resetTallyFixture();
      store = InMemoryEventStore();
      projection = GrandTotalProjection();
      runner = ProjectionRunner(store, [projection]);
    });
    tearDown(() => store.dispose());

    test('rebuild folds the whole log', () async {
      final t = Tally('t1')
        ..start('x')
        ..add(4)
        ..add(6);
      await store.append('t1', t.pendingEvents);

      await runner.rebuild();

      expect(projection.state, 10);
      expect(projection.lastSequence, 3);
    });

    test('catchUp applies only new events, no double counting', () async {
      final t = Tally('t1')
        ..start('x')
        ..add(5);
      await store.append('t1', t.pendingEvents);
      await runner.rebuild();

      await store.merge([TallyIncremented.raised(aggregateId: 't1', by: 3)]);
      await runner.catchUp();

      expect(projection.state, 8);

      await runner.catchUp(); // no-op
      expect(projection.state, 8);
    });

    test('rebuild is deterministic and idempotent', () async {
      final t = Tally('t1')
        ..start('x')
        ..add(2)
        ..add(2);
      await store.append('t1', t.pendingEvents);

      await runner.rebuild();
      final first = projection.state;
      await runner.rebuild();

      expect(projection.state, first);
    });
  });
}
