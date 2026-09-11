import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/eventsourcing/eventsourcing.dart';

import 'support/tally_fixture.dart';

void main() {
  setUp(resetTallyFixture);

  late EventCodec codec;

  setUp(() {
    codec = EventCodec(EventRegistry()..registerTallyEvents());
  });

  test('encode produces a JSON-safe map with the expected shape', () {
    final event = TallyStarted.raised(aggregateId: 't1', label: 'groceries');

    final map = codec.encode(event);

    expect(map['eventId'], event.eventId);
    expect(map['aggregateId'], 't1');
    expect(map['eventType'], 'tally.started');
    expect(map['timestamp'], event.timestamp.toString());
    expect(map['payload'], {'label': 'groceries'});
  });

  test('decode is the inverse of encode', () {
    final original = TallyIncremented.raised(aggregateId: 't1', by: 7);

    final rebuilt = codec.decode(codec.encode(original)) as TallyIncremented;

    expect(rebuilt, original); // DomainEvent.== compares by eventId
    expect(rebuilt.by, 7);
    expect(rebuilt.aggregateId, 't1');
    expect(rebuilt.timestamp, original.timestamp);
  });

  test('encodeToJson / decodeFromJson round-trip through an actual string', () {
    final original = TallyStarted.raised(aggregateId: 't1', label: 'rent');

    final json = codec.encodeToJson(original);
    expect(json, isA<String>());

    final rebuilt = codec.decodeFromJson(json) as TallyStarted;
    expect(rebuilt, original);
    expect(rebuilt.label, 'rent');
  });

  test('decode throws for an unregistered event type', () {
    final unknownRegistry = EventRegistry(); // nothing registered
    final codecWithoutTally = EventCodec(unknownRegistry);
    final event = TallyStarted.raised(aggregateId: 't1', label: 'x');

    expect(
      () => codecWithoutTally.decode(codec.encode(event)),
      throwsA(isA<UnknownEventTypeError>()),
    );
  });
}
