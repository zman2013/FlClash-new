import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'path.dart';

/// Read-only UI projection. Android's proxy core owns collection and storage.
class WeeklyTrafficStore extends ChangeNotifier {
  final Map<String, Map<String, num>> days = {};
  Map<String, String> _appLabels = {};
  final File? storageFile;

  WeeklyTrafficStore({this.storageFile});
  Future<void>? _loading;
  bool _hasCoreSnapshot = false;
  DateTime? completeSince;
  String? error;

  static String dayKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  List<String> dates(DateTime now) => List.generate(
    7,
    (i) => dayKey(DateTime(now.year, now.month, now.day - 6 + i)),
  );

  void setAppLabels(Map<String, String> labels) {
    _appLabels = labels;
    notifyListeners();
  }

  Map<String, num> totals(Iterable<String> dates) {
    final result = <String, num>{};
    for (final date in dates) {
      for (final entry in (days[date] ?? <String, num>{}).entries) {
        result.update(
          _appLabels[entry.key] ?? entry.key,
          (v) => v + entry.value,
          ifAbsent: () => entry.value,
        );
      }
    }
    return result;
  }

  void replaceFromCore(Map<dynamic, dynamic> snapshot) {
    final parsed = _parseDays(snapshot['days'] as Map);
    final since = DateTime.parse(snapshot['completeSince'] as String).toLocal();
    days
      ..clear()
      ..addAll(parsed);
    completeSince = since;
    error = (snapshot['error'] as String?)?.isNotEmpty == true
        ? '代理流量记录保存异常：${snapshot['error']}'
        : null;
    _hasCoreSnapshot = true;
    notifyListeners();
  }

  Map<String, Map<String, num>> _parseDays(Map data) => data.map(
    (key, value) =>
        MapEntry(key as String, Map<String, num>.from(value as Map)),
  );

  Future<void> initialize() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final file =
          storageFile ??
          File('${await appPath.homeDirPath}/proxy-traffic-history.json');
      File source = file;
      if (storageFile == null && !await source.exists()) {
        source = File('${await appPath.homeDirPath}/weekly-traffic.json');
      }
      if (await source.exists()) {
        final data = jsonDecode(await source.readAsString()) as Map;
        if (_hasCoreSnapshot) return;
        if (data['days'] is Map) {
          replaceFromCore(data);
          return;
        }
        days.addAll(_parseDays(data));
      }
    } catch (e) {
      if (!_hasCoreSnapshot) error = '周流量记录读取失败：$e';
    }
    if (!_hasCoreSnapshot) notifyListeners();
  }
}

final weeklyTrafficStore = WeeklyTrafficStore();
