import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
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
    ref.listenManual(runTimeProvider, (prev, next) {
      if (prev != next) {
        trafficAnalysisStore.resetActiveConnections();
      }
    });
    if (system.isMacOS) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
      unawaited(_poll());
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
