import 'dart:io';

import 'package:fl_clash/common/weekly_traffic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('seven calendar dates cross year boundaries', () {
    final store = WeeklyTrafficStore();
    expect(store.dates(DateTime(2026, 1, 2)), [
      '2025-12-27',
      '2025-12-28',
      '2025-12-29',
      '2025-12-30',
      '2025-12-31',
      '2026-01-01',
      '2026-01-02',
    ]);
    store.dispose();
  });

  test(
    'core totals replace samples without double counting and merge labels',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'weekly-projection',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/weekly.json');
      await file.writeAsString('{"2026-11-10":{"App A":100}}');
      final store = WeeklyTrafficStore(storageFile: file);
      await store.initialize();
      final snapshot = {
        'completeSince': '2026-11-10T15:00:00+08:00',
        'days': {
          '2026-11-10': {'app.a': 200, 'App A': 100},
        },
      };
      store.setAppLabels({'app.a': 'App A'});
      store.replaceFromCore(snapshot);
      store.replaceFromCore(snapshot);
      expect(store.totals(['2026-11-10']), {'App A': 300});
      expect(
        store.completeSince,
        DateTime.parse('2026-11-10T15:00:00+08:00').toLocal(),
      );
      // Rendering and refreshing history must never write into the core's file.
      expect(await file.readAsString(), '{"2026-11-10":{"App A":100}}');
      store.replaceFromCore({...snapshot, 'error': 'disk full'});
      expect(store.error, contains('disk full'));
      store.replaceFromCore(snapshot);
      expect(store.error, isNull);
      store.dispose();
    },
  );

  test('late disk load cannot replace a newer core snapshot', () async {
    final directory = await Directory.systemTemp.createTemp('weekly-race');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/weekly.json');
    await file.writeAsString('{"2026-11-10":{"App":100}}');
    final store = WeeklyTrafficStore(storageFile: file);
    final loading = store.initialize();
    store.replaceFromCore({
      'completeSince': '2026-11-10T15:00:00+08:00',
      'days': {
        '2026-11-10': {'App': 500},
      },
    });
    await loading;
    expect(store.totals(['2026-11-10']), {'App': 500});
    store.dispose();
  });
}
