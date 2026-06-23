import 'common.dart';

class TrafficAnalysisRecord {
  final DateTime time;
  final String connectionId;
  final String app;
  final String processPath;
  final String destination;
  final String host;
  final String destinationIP;
  final String destinationPort;
  final String remoteDestination;
  final String network;
  final String rule;
  final String rulePayload;
  final List<String> chains;
  final num up;
  final num down;

  const TrafficAnalysisRecord({
    required this.time,
    required this.connectionId,
    required this.app,
    required this.processPath,
    required this.destination,
    required this.host,
    required this.destinationIP,
    required this.destinationPort,
    required this.remoteDestination,
    required this.network,
    required this.rule,
    required this.rulePayload,
    required this.chains,
    required this.up,
    required this.down,
  });

  num get total => up + down;

  Map<String, Object?> toJson() {
    return {
      'type': 'traffic_delta',
      'time': time.toIso8601String(),
      'connectionId': connectionId,
      'app': app,
      'processPath': processPath,
      'destination': destination,
      'host': host,
      'destinationIP': destinationIP,
      'destinationPort': destinationPort,
      'remoteDestination': remoteDestination,
      'network': network,
      'rule': rule,
      'rulePayload': rulePayload,
      'chains': chains,
      'up': up,
      'down': down,
      'total': total,
    };
  }
}

class TrafficAnalysisItem {
  final String label;
  final num up;
  final num down;

  const TrafficAnalysisItem({
    required this.label,
    required this.up,
    required this.down,
  });

  num get total => up + down;

  Traffic get traffic => Traffic(up: up, down: down);
}

class TrafficAnalysisSnapshot {
  final DateTime generatedAt;
  final DateTime startedAt;
  final List<TrafficAnalysisItem> appItems;
  final List<TrafficAnalysisItem> destinationItems;
  final Traffic total;

  const TrafficAnalysisSnapshot({
    required this.generatedAt,
    required this.startedAt,
    required this.appItems,
    required this.destinationItems,
    required this.total,
  });

  factory TrafficAnalysisSnapshot.empty(DateTime now) {
    return TrafficAnalysisSnapshot(
      generatedAt: now,
      startedAt: now,
      appItems: const [],
      destinationItems: const [],
      total: const Traffic(),
    );
  }

  bool get hasData => total.up + total.down > 0;
}
