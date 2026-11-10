import 'dart:async';

import 'package:fl_clash/common/weekly_traffic.dart';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TrafficAnalysisManager extends ConsumerStatefulWidget {
  final Widget child;

  const TrafficAnalysisManager({super.key, required this.child});

  @override
  ConsumerState<TrafficAnalysisManager> createState() =>
      _TrafficAnalysisManagerState();
}

class _TrafficAnalysisManagerState
    extends ConsumerState<TrafficAnalysisManager> {
  Timer? _timer;
  bool _isPolling = false;

  @override
  void initState() {
    super.initState();
    if (system.isAndroid) {
      unawaited(weeklyTrafficStore.initialize());
      unawaited(_loadAppLabels());
    }
    ref.listenManual(coreStatusProvider, (prev, next) {
      if (prev != next) {
        trafficAnalysisStore.resetActiveConnections();
      }
    });
    ref.listenManual(packagesProvider, (prev, next) {
      trafficAnalysisStore.setAppLabels({
        for (final package in next) package.packageName: package.label,
      });
    }, fireImmediately: true);
    if (system.isMacOS || system.isAndroid) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
      unawaited(_poll());
    }
  }

  Future<void> _loadAppLabels() async {
    try {
      final packages = await app?.getPackages();
      if (mounted && packages != null) {
        ref.read(packagesProvider.notifier).value = packages;
      }
    } catch (_) {
      // Package names remain usable when Android cannot resolve app labels.
    }
  }

  Future<void> _poll() async {
    if (_isPolling) {
      return;
    }
    _isPolling = true;
    try {
      final connections = await coreController.getConnections();
      trafficAnalysisStore.recordActiveConnections(connections);
    } catch (_) {
      // Keep existing baselines so a transient polling failure does not double
      // count the next successful sample for long-lived connections.
    } finally {
      _isPolling = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
