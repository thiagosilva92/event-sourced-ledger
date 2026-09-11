import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/clock/hlc.dart';
import 'package:ledger/eventsourcing/eventsourcing.dart';

import 'support/tally_fixture.dart';

void main() {
  group('EventRegistry', () {
    test('round-trips an event through register/deserialize', () {
      final registry = EventRegistry()..registerTallyEvents();

      final rebuilt = registry.deserialize(
        'tally.incremented',
        const EventMetadata(
          eventId: 'e1',
          aggregateId: 't1',
          timestamp: Hlc(wallMillis: 1, counter: 0, nodeId: 'n'),
        ),
        {'by': 7},
      );

      expect(rebuilt, isA<TallyIncremented>());
      expect((rebuilt as TallyIncremented).by, 7);
      expect(rebuilt.eventId, 'e1');
    });

    test('unknown type throws a helpful error', () {
      expect(
        () => EventRegistry().deserialize(
          'nope',
          const EventMetadata(
            eventId: 'e',
            aggregateId: 'a',
            timestamp: Hlc.zero('n'),
          ),
          const {},
        ),
        throwsA(isA<UnknownEventTypeError>()),
      );
    });

    test('double registration throws', () {
      final registry = EventRegistry()
        ..register('x', (m, p) => throw UnimplementedError());
      expect(
        () => registry.register('x', (m, p) => throw UnimplementedError()),
        throwsStateError,
      );
    });
  });
}
