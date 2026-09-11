import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ledger/core/clock/hlc.dart';
import 'package:ledger/core/database/app_database.dart';
import 'package:ledger/core/database/drift_event_store.dart';
import 'package:ledger/eventsourcing/eventsourcing.dart';

/// TEMPORARY — proves the production database path (real file on disk via
/// `path_provider`, real native SQLite, real background isolate) actually
/// works on a physical device, before any real UI exists to exercise it.
///
/// Delete this whole `app/debug/` folder once `features/` has a real home
/// screen reading from a real projection — that's the point where this
/// stops being the only thing touching `AppDatabase()` on-device.
class DbSmokeTestScreen extends StatefulWidget {
  const DbSmokeTestScreen({super.key});

  @override
  State<DbSmokeTestScreen> createState() => _DbSmokeTestScreenState();
}

class _DbSmokeTestScreenState extends State<DbSmokeTestScreen> {
  final List<String> _log = [];
  bool _running = false;
  bool? _passed;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _passed = null;
      _log.clear();
    });

    AppDatabase? db;
    try {
      _step('Opening AppDatabase() — real file, real native SQLite…');
      db = AppDatabase();
      // Touch the connection now so a failure surfaces here, not on the
      // first real query below.
      await db.customStatement('SELECT 1');
      _step('✓ database open');

      final store = DriftEventStore(db, _buildSmokeTestRegistry);

      final before = await store.latestSequence();
      _step('✓ latestSequence() before = $before');

      final event = _SmokeTestPinged.now(
        note: 'device smoke test @ ${DateTime.now().toIso8601String()}',
      );
      _step('Appending one event…');
      await store.append('smoke-test', [event]);
      _step('✓ append() completed');

      _step('Reading it back…');
      final readBack = await store.readAggregate('smoke-test');
      final ok =
          readBack.length == 1 && readBack.single.eventId == event.eventId;
      _step(
        ok
            ? '✓ read back ${readBack.length} event, eventId matches'
            : '✗ MISMATCH: read back ${readBack.length} events',
      );

      final after = await store.latestSequence();
      _step('✓ latestSequence() after = $after (was $before)');

      _step(
        'Appending 600 more events to cross the isolate-decode '
        'threshold (500)…',
      );
      final bulk = List.generate(
        600,
        (i) => _SmokeTestPinged.now(note: 'bulk $i'),
      );
      await store.append('smoke-test', bulk);

      final readStopwatch = Stopwatch()..start();
      final all = await store.readAll(); // 601 rows crosses the 500 threshold
      readStopwatch.stop();
      final bulkOk = all.length == 601; // the 1 earlier + 600 here
      _step(
        '${bulkOk ? '✓' : '✗'} readAll() with 601 rows (decoded via a '
        'worker isolate, real hardware) took '
        '${readStopwatch.elapsedMilliseconds}ms',
      );

      await store.dispose();
      setState(() => _passed = ok && after == before + 1 && bulkOk);
    } on Object catch (error, stackTrace) {
      // Intentionally broad: a debug smoke test must report any failure
      // (Exception or Error) on screen, not let it crash silently.
      _step('✗ FAILED: $error');
      _step(stackTrace.toString());
      setState(() => _passed = false);
    } finally {
      setState(() => _running = false);
    }
  }

  void _step(String message) {
    print('[DbSmokeTest] $message');
    setState(() => _log.add(message));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DB smoke test (debug only)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_passed != null)
              Container(
                padding: const EdgeInsets.all(12),
                color: _passed! ? Colors.green.shade100 : Colors.red.shade100,
                child: Text(
                  _passed! ? 'PASSED ✓' : 'FAILED ✗',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: _log.length,
                itemBuilder: (context, i) => Text(
                  _log[i],
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
            FilledButton(
              onPressed: _running ? null : _run,
              child: Text(_running ? 'Running…' : 'Run again'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Top-level, as `DriftEventStore` requires (see its constructor doc) — it
/// rebuilds this inside a worker isolate for the bulk-read step below.
EventRegistry _buildSmokeTestRegistry() => EventRegistry()
  ..register(
    'debug.smoke_test_pinged',
    (meta, payload) => _SmokeTestPinged(
      eventId: meta.eventId,
      aggregateId: meta.aggregateId,
      timestamp: meta.timestamp,
      note: payload['note']! as String,
    ),
  );

base class _SmokeTestPinged extends DomainEvent {
  const _SmokeTestPinged({
    required super.eventId,
    required super.aggregateId,
    required super.timestamp,
    required this.note,
  });

  factory _SmokeTestPinged.now({required String note}) => _SmokeTestPinged(
    eventId: DateTime.now().microsecondsSinceEpoch.toString(),
    aggregateId: 'smoke-test',
    timestamp: Hlc(
      wallMillis: DateTime.now().millisecondsSinceEpoch,
      counter: 0,
      nodeId: 'device-smoke-test',
    ),
    note: note,
  );

  final String note;

  @override
  String get eventType => 'debug.smoke_test_pinged';

  @override
  Map<String, Object?> toPayload() => {'note': note};
}
