import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart';

import 'path.dart';

class TrafficAnalysisStore extends ValueNotifier<TrafficAnalysisSnapshot> {
  static const window = Duration(hours: 1);

  final _records = Queue<TrafficAnalysisRecord>();
  final _lastTotals = <String, _ConnectionTraffic>{};
  final _logWriter = TrafficAnalysisLogWriter();
  DateTime _startedAt;

  TrafficAnalysisStore()
    : _startedAt = DateTime.now(),
      super(TrafficAnalysisSnapshot.empty(DateTime.now()));

  Future<String> get logPath => appPath.trafficAnalysisLogPath;

  void recordActiveConnections(List<TrackerInfo> connections) {
    final now = DateTime.now();
    final activeIds = <String>{};

    for (final connection in connections) {
      activeIds.add(connection.id);
      if (!_isProxied(connection)) {
        _lastTotals.remove(connection.id);
        continue;
      }

      final current = _ConnectionTraffic.fromTrackerInfo(connection);
      final previous = _lastTotals[connection.id];
      final delta = previous == null
          ? _initialDelta(connection, current)
          : current.deltaFrom(previous);

      _lastTotals[connection.id] = current;
      _addRecordIfNeeded(now, connection, delta);
    }

    _lastTotals.removeWhere((id, _) => !activeIds.contains(id));
    _publish(now);
  }

  void recordCompletedRequest(TrackerInfo trackerInfo) {
    if (!_isProxied(trackerInfo)) {
      _lastTotals.remove(trackerInfo.id);
      return;
    }

    final now = DateTime.now();
    final current = _ConnectionTraffic.fromTrackerInfo(trackerInfo);
    final previous = _lastTotals.remove(trackerInfo.id);
    final delta = previous == null
        ? _initialDelta(trackerInfo, current)
        : current.deltaFrom(previous);

    _addRecordIfNeeded(now, trackerInfo, delta);
    _publish(now);
  }

  void resetActiveConnections() {
    _lastTotals.clear();
  }

  void reset() {
    final now = DateTime.now();
    _records.clear();
    _lastTotals.clear();
    _startedAt = now;
    value = TrafficAnalysisSnapshot.empty(now);
  }

  _ConnectionTraffic _initialDelta(
    TrackerInfo trackerInfo,
    _ConnectionTraffic current,
  ) {
    if (trackerInfo.start.isBefore(_startedAt)) {
      return const _ConnectionTraffic(up: 0, down: 0);
    }
    return current;
  }

  void _addRecordIfNeeded(
    DateTime now,
    TrackerInfo trackerInfo,
    _ConnectionTraffic delta,
  ) {
    if (delta.total <= 0) {
      return;
    }

    final metadata = trackerInfo.metadata;
    final record = TrafficAnalysisRecord(
      time: now,
      connectionId: trackerInfo.id,
      app: _appNameOf(trackerInfo),
      processPath: metadata.processPath,
      destination: _destinationOf(trackerInfo),
      host: metadata.host,
      destinationIP: metadata.destinationIP,
      destinationPort: metadata.destinationPort,
      remoteDestination: metadata.remoteDestination,
      network: metadata.network,
      rule: trackerInfo.rule,
      rulePayload: trackerInfo.rulePayload,
      chains: trackerInfo.chains,
      up: delta.up,
      down: delta.down,
    );
    _records.add(record);
    unawaited(_logWriter.write(record));
  }

  void _publish(DateTime now) {
    _purgeExpired(now);
    value = _buildSnapshot(now);
  }

  void _purgeExpired(DateTime now) {
    final threshold = now.subtract(window);
    while (_records.isNotEmpty && _records.first.time.isBefore(threshold)) {
      _records.removeFirst();
    }
  }

  TrafficAnalysisSnapshot _buildSnapshot(DateTime now) {
    final appMap = <String, _ConnectionTraffic>{};
    final destinationMap = <String, _ConnectionTraffic>{};
    num up = 0;
    num down = 0;

    for (final record in _records) {
      up += record.up;
      down += record.down;
      appMap.update(
        record.app,
        (value) => value.add(record.up, record.down),
        ifAbsent: () => _ConnectionTraffic(up: record.up, down: record.down),
      );
      destinationMap.update(
        record.destination,
        (value) => value.add(record.up, record.down),
        ifAbsent: () => _ConnectionTraffic(up: record.up, down: record.down),
      );
    }

    return TrafficAnalysisSnapshot(
      generatedAt: now,
      startedAt: _startedAt,
      appItems: _toItems(appMap),
      destinationItems: _toItems(destinationMap),
      total: Traffic(up: up, down: down),
    );
  }

  List<TrafficAnalysisItem> _toItems(Map<String, _ConnectionTraffic> map) {
    final items = map.entries
        .map(
          (entry) => TrafficAnalysisItem(
            label: entry.key,
            up: entry.value.up,
            down: entry.value.down,
          ),
        )
        .toList();
    items.sort((a, b) => b.total.compareTo(a.total));
    return items;
  }
}

class TrafficAnalysisLogWriter {
  Future<void> _pending = Future.value();

  Future<void> write(TrafficAnalysisRecord record) {
    _pending = _pending
        .then((_) async {
          final file = File(await appPath.trafficAnalysisLogPath);
          if (!await file.exists()) {
            await file.create(recursive: true);
          }
          await file.writeAsString(
            '${json.encode(record.toJson())}\n',
            mode: FileMode.append,
            flush: false,
          );
        })
        .catchError((_) {});
    return _pending;
  }
}

class _ConnectionTraffic {
  final num up;
  final num down;

  const _ConnectionTraffic({required this.up, required this.down});

  factory _ConnectionTraffic.fromTrackerInfo(TrackerInfo trackerInfo) {
    return _ConnectionTraffic(
      up: max(0, trackerInfo.upload),
      down: max(0, trackerInfo.download),
    );
  }

  num get total => up + down;

  _ConnectionTraffic add(num up, num down) {
    return _ConnectionTraffic(up: this.up + up, down: this.down + down);
  }

  _ConnectionTraffic deltaFrom(_ConnectionTraffic previous) {
    return _ConnectionTraffic(
      up: max(0, up - previous.up),
      down: max(0, down - previous.down),
    );
  }
}

bool _isProxied(TrackerInfo trackerInfo) {
  if (trackerInfo.chains.isEmpty) {
    return false;
  }
  final outbound = trackerInfo.chains.last.toUpperCase();
  return outbound != 'DIRECT' && !outbound.startsWith('REJECT');
}

String _appNameOf(TrackerInfo trackerInfo) {
  final process = trackerInfo.metadata.process.trim();
  if (process.isNotEmpty) {
    return process;
  }

  final processPath = trackerInfo.metadata.processPath.trim();
  if (processPath.isNotEmpty) {
    return processPath.split('/').where((part) => part.isNotEmpty).last;
  }

  return 'Unknown App';
}

String _destinationOf(TrackerInfo trackerInfo) {
  final metadata = trackerInfo.metadata;
  if (metadata.host.trim().isNotEmpty) {
    return metadata.host.trim();
  }
  if (metadata.remoteDestination.trim().isNotEmpty) {
    return metadata.remoteDestination.trim();
  }
  if (metadata.destinationIP.trim().isEmpty) {
    return 'Unknown Destination';
  }
  if (metadata.destinationPort.trim().isEmpty) {
    return metadata.destinationIP.trim();
  }
  return '${metadata.destinationIP.trim()}:${metadata.destinationPort.trim()}';
}

final trafficAnalysisStore = TrafficAnalysisStore();
