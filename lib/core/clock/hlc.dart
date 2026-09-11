import 'package:meta/meta.dart';

/// Thrown when the logical clock drifts implausibly far ahead of the wall
/// clock, which usually means a device sent a timestamp from the future.
class ClockDriftError extends Error {
  ClockDriftError(this.driftMillis, this.maxDriftMillis);

  final int driftMillis;
  final int maxDriftMillis;

  @override
  String toString() =>
      'ClockDriftError: logical time is ${driftMillis}ms ahead of the wall '
      'clock (max allowed ${maxDriftMillis}ms)';
}

/// A Hybrid Logical Clock timestamp: a wall-clock component in milliseconds
/// (`wallMillis`) plus a monotonic `counter` that breaks ties when events
/// happen within the same millisecond or when clocks are skewed.
///
/// `nodeId` makes the order **total**: two nodes can otherwise produce the
/// same `(wallMillis, counter)` pair.
///
/// See "Logical Physical Clocks and Consistent Snapshots in Globally
/// Distributed Databases", Kulkarni et al., 2014.
@immutable
final class Hlc implements Comparable<Hlc> {
  const Hlc({
    required this.wallMillis,
    required this.counter,
    required this.nodeId,
  }) : assert(wallMillis >= 0, 'wallMillis must be non-negative'),
       assert(counter >= 0, 'counter must be non-negative');

  /// The smallest possible timestamp for [nodeId] — useful as a sync cursor
  /// meaning "everything".
  const Hlc.zero(String nodeId)
    : this(wallMillis: 0, counter: 0, nodeId: nodeId);

  /// Parses the canonical `wallMillis-counter-nodeId` form produced by
  /// [toString], e.g. `1694300000000-00003-device-a`.
  factory Hlc.parse(String value) {
    final firstDash = value.indexOf('-');
    final secondDash = value.indexOf('-', firstDash + 1);
    if (firstDash <= 0 || secondDash <= firstDash) {
      throw FormatException('not an HLC timestamp: "$value"');
    }
    final wall = int.parse(value.substring(0, firstDash));
    final counter = int.parse(value.substring(firstDash + 1, secondDash));
    final nodeId = value.substring(secondDash + 1);
    if (nodeId.isEmpty) {
      throw FormatException('HLC timestamp has no nodeId: "$value"');
    }
    return Hlc(wallMillis: wall, counter: counter, nodeId: nodeId);
  }

  final int wallMillis;
  final int counter;
  final String nodeId;

  /// Ordering: wall time, then counter, then nodeId for a stable total order.
  @override
  int compareTo(Hlc other) {
    final byWall = wallMillis.compareTo(other.wallMillis);
    if (byWall != 0) return byWall;
    final byCounter = counter.compareTo(other.counter);
    if (byCounter != 0) return byCounter;
    return nodeId.compareTo(other.nodeId);
  }

  bool operator <(Hlc other) => compareTo(other) < 0;
  bool operator <=(Hlc other) => compareTo(other) <= 0;
  bool operator >(Hlc other) => compareTo(other) > 0;
  bool operator >=(Hlc other) => compareTo(other) >= 0;

  /// Canonical, parseable string form: `wallMillis-counter-nodeId`.
  ///
  /// This is for storage, logs and transport — always order [Hlc] values
  /// with [compareTo] or the relational operators, never by sorting this
  /// string. The counter is zero-padded to 5 digits for readability only;
  /// it does not by itself guarantee lexical order matches [compareTo]
  /// order (`wallMillis` isn't fixed-width, and a wider `maxCounter` than
  /// [HybridLogicalClock]'s default would overflow the padding).
  @override
  String toString() =>
      '$wallMillis-${counter.toString().padLeft(5, '0')}-$nodeId';

  @override
  bool operator ==(Object other) =>
      other is Hlc &&
      other.wallMillis == wallMillis &&
      other.counter == counter &&
      other.nodeId == nodeId;

  @override
  int get hashCode => Object.hash(wallMillis, counter, nodeId);
}

/// Stateful Hybrid Logical Clock for a single node.
///
/// Call [now] when creating a local event and [receive] when ingesting a
/// remote event; both advance the clock so that causally-later events always
/// compare greater.
class HybridLogicalClock {
  HybridLogicalClock({
    required this.nodeId,
    required int Function() physicalTimeMillis,
    Hlc? initial,
    this.maxDriftMillis = _defaultMaxDriftMillis,
    this.maxCounter = _defaultMaxCounter,
    // Named parameters cannot be private, so this cannot be an initializing
    // formal; the field stays private on purpose.
    // ignore: prefer_initializing_formals
  }) : _physicalTimeMillis = physicalTimeMillis,
       _last = initial ?? Hlc(wallMillis: 0, counter: 0, nodeId: nodeId) {
    if (initial != null && initial.nodeId != nodeId) {
      throw ArgumentError.value(
        initial,
        'initial',
        'initial timestamp belongs to node "${initial.nodeId}", not "$nodeId"',
      );
    }
  }

  static const int _defaultMaxDriftMillis = 60 * 1000;
  static const int _defaultMaxCounter = 0xFFFF;

  final String nodeId;
  final int Function() _physicalTimeMillis;
  final int maxDriftMillis;
  final int maxCounter;

  Hlc _last;

  /// The most recently issued or observed timestamp.
  Hlc get last => _last;

  /// Issues a new timestamp for a locally-created event.
  Hlc now() {
    final physical = _physicalTimeMillis();
    final wall = physical > _last.wallMillis ? physical : _last.wallMillis;
    final counter = wall == _last.wallMillis ? _last.counter + 1 : 0;
    _guard(wall, counter, physical);
    return _last = Hlc(wallMillis: wall, counter: counter, nodeId: nodeId);
  }

  /// Merges an incoming [remote] timestamp into local state and returns the
  /// resulting local timestamp. Idempotent for already-seen timestamps in the
  /// sense that it never moves the clock backwards.
  Hlc receive(Hlc remote) {
    final physical = _physicalTimeMillis();
    final wall = [
      physical,
      _last.wallMillis,
      remote.wallMillis,
    ].reduce((a, b) => a > b ? a : b);

    final int counter;
    if (wall == _last.wallMillis && wall == remote.wallMillis) {
      counter =
          (_last.counter > remote.counter ? _last.counter : remote.counter) + 1;
    } else if (wall == _last.wallMillis) {
      counter = _last.counter + 1;
    } else if (wall == remote.wallMillis) {
      counter = remote.counter + 1;
    } else {
      counter = 0;
    }

    _guard(wall, counter, physical);
    return _last = Hlc(wallMillis: wall, counter: counter, nodeId: nodeId);
  }

  void _guard(int wall, int counter, int physical) {
    if (wall - physical > maxDriftMillis) {
      throw ClockDriftError(wall - physical, maxDriftMillis);
    }
    if (counter > maxCounter) {
      throw StateError(
        'HLC counter overflow ($counter > $maxCounter) within a single '
        'millisecond — clock is being called far too fast',
      );
    }
  }
}
