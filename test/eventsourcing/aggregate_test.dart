import 'package:flutter_test/flutter_test.dart';

import 'support/tally_fixture.dart';

void main() {
  setUp(resetTallyFixture);

  test('raise applies state and queues pending events', () {
    final tally = Tally('t1')
      ..start('groceries')
      ..add(3)
      ..add(2);

    expect(tally.label, 'groceries');
    expect(tally.total, 5);
    expect(tally.version, 3);
    expect(tally.pendingEvents, hasLength(3));
  });

  test('markEventsCommitted clears pending but keeps state and version', () {
    final tally = Tally('t1')
      ..start('x')
      ..add(1)
      ..markEventsCommitted();

    expect(tally.hasPendingEvents, isFalse);
    expect(tally.version, 2);
    expect(tally.total, 1);
  });

  test('loadFromHistory rebuilds state without pending events', () {
    final source = Tally('t1')
      ..start('rent')
      ..add(10);
    final history = source.pendingEvents;

    final rebuilt = Tally('t1')..loadFromHistory(history);

    expect(rebuilt.total, 10);
    expect(rebuilt.label, 'rent');
    expect(rebuilt.version, 2);
    expect(rebuilt.hasPendingEvents, isFalse);
  });

  test('loadFromSnapshot resumes from a version plus a tail', () {
    final tally = Tally('t1')..start('x');
    tally.markEventsCommitted();
    tally
      ..add(4)
      ..add(6);
    final tail = tally.pendingEvents;

    final rebuilt = Tally('t1')..loadFromSnapshot(1, tail);
    expect(rebuilt.version, 3);
    expect(rebuilt.total, 10);
  });

  test('rejects events belonging to another aggregate', () {
    final foreign = TallyIncremented.raised(aggregateId: 'other', by: 1);
    expect(() => Tally('t1').loadFromHistory([foreign]), throwsArgumentError);
  });

  test('rejects loadFromHistory on a used aggregate', () {
    final tally = Tally('t1')..start('x');
    expect(() => tally.loadFromHistory([]), throwsStateError);
  });
}
