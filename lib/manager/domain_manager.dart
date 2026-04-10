import 'dart:async';

import 'package:collection/collection.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/controller.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class DomainManager extends ConsumerStatefulWidget {
  final Widget child;

  const DomainManager({super.key, required this.child});

  @override
  ConsumerState<DomainManager> createState() => _DomainManagerState();
}

class _DomainManagerState extends ConsumerState<DomainManager> {
  Timer? _timer;
  bool _isRefreshing = false;
  bool _pendingRefresh = false;
  DateTime? _lastSwitchAt;

  @override
  void initState() {
    super.initState();
    ref.listenManual(initProvider, (previous, next) {
      if (next) {
        _handleConfigChanged();
      }
    });
    ref.listenManual(domainSettingProvider, (previous, next) {
      _handleConfigChanged();
    });
    ref.listenManual(domainSettingProvider.select((state) => state.items), (
      prev,
      next,
    ) {
      if (prev != next && ref.read(initProvider)) {
        appController.applyProfileDebounce(silence: true);
        _requestRefresh();
      }
    });
    ref.listenManual(globalRulesProvider, (previous, next) {
      if (ref.read(initProvider)) {
        unawaited(_migrateLegacyRules());
      }
    });
    ref.listenManual(runTimeProvider, (previous, next) {
      if (ref.read(initProvider)) {
        _requestRefresh();
      }
    });
    ref.listenManual(groupsProvider, (previous, next) {
      if (ref.read(initProvider)) {
        _requestRefresh();
      }
    });
    ref.listenManual(selectedMapProvider, (previous, next) {
      if (ref.read(initProvider)) {
        _requestRefresh();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(initProvider)) {
        _handleConfigChanged();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _handleConfigChanged() {
    _restartTimer();
    unawaited(_migrateLegacyRules());
    _requestRefresh();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = null;
    if (!ref.read(initProvider)) {
      return;
    }
    final settings = ref.read(domainSettingProvider);
    if (settings.items.isEmpty) {
      ref.read(domainStatusesProvider.notifier).clear();
      return;
    }
    final interval = settings.refreshIntervalSeconds;
    if (interval <= 0) {
      return;
    }
    _timer = Timer.periodic(Duration(seconds: interval), (_) {
      _requestRefresh();
    });
  }

  void _requestRefresh() {
    unawaited(_refreshDomainStatuses());
  }

  Future<void> _migrateLegacyRules() async {
    final legacyRules = filterDomainProxyRules(
      ref.read(globalRulesProvider).value ?? [],
    );
    if (legacyRules.isEmpty) {
      return;
    }
    final settings = ref.read(domainSettingProvider);
    final existedKeys = settings.items.map((item) => item.key).toSet();
    final nextItems = List<DomainRoutingItem>.from(settings.items);
    final deleteIds = <int>[];
    for (final rule in legacyRules) {
      final parsedRule = ParsedRule.parseString(rule.value);
      final content = parsedRule.content?.trim();
      final target = parsedRule.ruleTarget?.trim();
      if (content == null ||
          content.isEmpty ||
          target == null ||
          target.isEmpty) {
        continue;
      }
      final item = DomainRoutingItem(
        id: rule.id,
        ruleAction: parsedRule.ruleAction,
        content: content,
        target: target,
      );
      if (existedKeys.add(item.key)) {
        nextItems.add(item);
      }
      deleteIds.add(rule.id);
    }
    if (nextItems.length != settings.items.length) {
      ref
          .read(domainSettingProvider.notifier)
          .update((state) => state.copyWith(items: nextItems));
    }
    if (deleteIds.isNotEmpty) {
      ref.read(globalRulesProvider.notifier).delAll(deleteIds);
    }
  }

  Future<void> _refreshDomainStatuses() async {
    if (!ref.read(initProvider)) {
      return;
    }
    if (_isRefreshing) {
      _pendingRefresh = true;
      return;
    }
    _isRefreshing = true;
    try {
      await _migrateLegacyRules();
      final settings = ref.read(domainSettingProvider);
      final items = settings.items;
      final statusesNotifier = ref.read(domainStatusesProvider.notifier);
      statusesNotifier.removeMissing(items.map((item) => item.id));
      if (items.isEmpty) {
        return;
      }
      final groups = ref.read(groupsProvider);
      final selectedMap = ref.read(selectedMapProvider);
      final isStarted = ref.read(runTimeProvider) != null;
      for (final item in items) {
        final result = await _evaluateItem(
          item: item,
          groups: groups,
          selectedMap: selectedMap,
          isStarted: isStarted,
          minSwitchIntervalSeconds: settings.minSwitchIntervalSeconds,
        );
        statusesNotifier.put(item.id, result.status);
        final switchRequest = result.switchRequest;
        if (switchRequest != null) {
          await _switchProxy(
            groupName: switchRequest.groupName,
            proxyName: switchRequest.proxyName,
          );
          _lastSwitchAt = DateTime.now();
        }
      }
    } finally {
      _isRefreshing = false;
      if (_pendingRefresh) {
        _pendingRefresh = false;
        _requestRefresh();
      }
    }
  }

  Future<_DomainEvaluationResult> _evaluateItem({
    required DomainRoutingItem item,
    required List<Group> groups,
    required Map<String, String> selectedMap,
    required bool isStarted,
    required int minSwitchIntervalSeconds,
  }) async {
    final previousStatus = ref.read(domainStatusesProvider)[item.id];
    final domainGroupName = buildDomainProxyGroupName(item.id);
    final target =
        item.autoSelectLowestDelay && groups.getGroup(domainGroupName) != null
        ? domainGroupName
        : item.target.trim();
    final probeUrl = item.probeUrl;
    final targetGroup = groups.getGroup(target);
    final resolvedState = computeRealSelectedProxyState(
      target,
      groups: groups,
      selectedMap: selectedMap,
    );
    final now = DateTime.now();
    if (!isStarted || groups.isEmpty) {
      return _DomainEvaluationResult(
        status: DomainRuntimeStatus(
          currentProxyName: resolvedState.proxyName,
          probeUrl: probeUrl,
          message: _waitingForProxyServiceText(),
          updatedAt: previousStatus?.updatedAt ?? now,
          failureCount: previousStatus?.failureCount ?? 0,
        ),
      );
    }
    if (probeUrl == null) {
      return _DomainEvaluationResult(
        status: DomainRuntimeStatus(
          currentProxyName: resolvedState.proxyName,
          probeUrl: probeUrl,
          message: _unsupportedProbeText(),
          updatedAt: now,
        ),
      );
    }
    if (target == RuleTarget.REJECT.name) {
      return _DomainEvaluationResult(
        status: DomainRuntimeStatus(
          currentProxyName: target,
          probeUrl: probeUrl,
          message: _rejectTargetText(),
          updatedAt: now,
        ),
      );
    }
    if (targetGroup == null) {
      final delay = await _testDelay(probeUrl: probeUrl, proxyName: target);
      final failureCount = _nextFailureCount(previousStatus, delay);
      return _DomainEvaluationResult(
        status: DomainRuntimeStatus(
          currentProxyName: resolvedState.proxyName.isNotEmpty
              ? resolvedState.proxyName
              : target,
          delay: delay,
          probeUrl: probeUrl,
          updatedAt: now,
          failureCount: failureCount,
          message: delay == null
              ? _probeFailedText()
              : delay <= 0
              ? _timeoutText()
              : null,
        ),
      );
    }
    final currentCandidateName = targetGroup.getCurrentSelectedName(
      selectedMap[targetGroup.name] ?? '',
    );
    final candidateResults = await Future.wait(
      targetGroup.all.map(
        (candidate) => _testGroupCandidate(
          candidate: candidate,
          groups: groups,
          selectedMap: selectedMap,
          probeUrl: probeUrl,
        ),
      ),
    );
    final currentCandidate = candidateResults.firstWhere(
      (candidate) => candidate.proxy.name == currentCandidateName,
      orElse: () => candidateResults.firstOrNull ?? _DomainCandidateResult(),
    );
    final bestCandidate = candidateResults
        .where((candidate) => (candidate.delay ?? -1) > 0)
        .sorted((a, b) => a.delay!.compareTo(b.delay!))
        .firstOrNull;
    final currentDelay = currentCandidate.delay;
    final currentProxyName = currentCandidate.resolvedProxyName.isNotEmpty
        ? currentCandidate.resolvedProxyName
        : resolvedState.proxyName;
    final failureCount = _nextFailureCount(previousStatus, currentDelay);
    final bypassInterval = failureCount >= 3;
    final canSwitch =
        item.autoSelectLowestDelay &&
        bestCandidate != null &&
        bestCandidate.proxy.name != currentCandidateName &&
        (_canSwitch(minSwitchIntervalSeconds) || bypassInterval);
    return _DomainEvaluationResult(
      status: DomainRuntimeStatus(
        currentProxyName: currentProxyName,
        delay: currentDelay,
        probeUrl: probeUrl,
        updatedAt: now,
        failureCount: failureCount,
        message: currentDelay == null
            ? _probeFailedText()
            : currentDelay <= 0
            ? _timeoutText()
            : null,
      ),
      switchRequest: canSwitch
          ? _DomainSwitchRequest(
              groupName: targetGroup.name,
              proxyName: bestCandidate.proxy.name,
            )
          : null,
    );
  }

  Future<_DomainCandidateResult> _testGroupCandidate({
    required Proxy candidate,
    required List<Group> groups,
    required Map<String, String> selectedMap,
    required String probeUrl,
  }) async {
    final resolvedState = computeRealSelectedProxyState(
      candidate.name,
      groups: groups,
      selectedMap: selectedMap,
    );
    final delay = await _testDelay(
      probeUrl: probeUrl,
      proxyName: resolvedState.proxyName,
    );
    return _DomainCandidateResult(
      proxy: candidate,
      delay: delay,
      resolvedProxyName: resolvedState.proxyName,
    );
  }

  Future<int?> _testDelay({
    required String probeUrl,
    required String proxyName,
  }) async {
    if (proxyName.isEmpty) {
      return null;
    }
    try {
      ref
          .read(delayDataSourceProvider.notifier)
          .setDelay(Delay(url: probeUrl, name: proxyName, value: 0));
      final delay = await coreController.getDelay(probeUrl, proxyName);
      ref.read(delayDataSourceProvider.notifier).setDelay(delay);
      return delay.value;
    } catch (_) {
      ref
          .read(delayDataSourceProvider.notifier)
          .setDelay(Delay(url: probeUrl, name: proxyName, value: -1));
      return -1;
    }
  }

  int _nextFailureCount(DomainRuntimeStatus? previousStatus, int? delay) {
    if (delay != null && delay > 0) {
      return 0;
    }
    return (previousStatus?.failureCount ?? 0) + 1;
  }

  bool _canSwitch(int minSwitchIntervalSeconds) {
    final lastSwitchAt = _lastSwitchAt;
    if (lastSwitchAt == null) {
      return true;
    }
    return DateTime.now().difference(lastSwitchAt).inSeconds >=
        minSwitchIntervalSeconds;
  }

  Future<void> _switchProxy({
    required String groupName,
    required String proxyName,
  }) async {
    appController.updateCurrentSelectedMap(groupName, proxyName);
    await appController.changeProxy(
      groupName: groupName,
      proxyName: proxyName,
      resetConnections: false,
    );
    appController.updateGroupsDebounce();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class _DomainEvaluationResult {
  final DomainRuntimeStatus status;
  final _DomainSwitchRequest? switchRequest;

  const _DomainEvaluationResult({required this.status, this.switchRequest});
}

class _DomainSwitchRequest {
  final String groupName;
  final String proxyName;

  const _DomainSwitchRequest({
    required this.groupName,
    required this.proxyName,
  });
}

class _DomainCandidateResult {
  final Proxy proxy;
  final int? delay;
  final String resolvedProxyName;

  const _DomainCandidateResult({
    this.proxy = const Proxy(name: '', type: ''),
    this.delay,
    this.resolvedProxyName = '',
  });
}

String _unsupportedProbeText() {
  return Intl.message(
    'Latency probing is supported only for DOMAIN and DOMAIN-SUFFIX rules',
    name: 'domainUnsupportedProbeText',
  );
}

String _rejectTargetText() {
  return Intl.message(
    'REJECT rules do not support latency probing',
    name: 'domainRejectTargetText',
  );
}

String _probeFailedText() {
  return Intl.message('Probe failed', name: 'domainProbeFailedText');
}

String _timeoutText() {
  return Intl.message('Timeout', name: 'domainTimeoutText');
}

String _waitingForProxyServiceText() {
  return Intl.message(
    'Waiting for the proxy service to become available',
    name: 'domainWaitingForProxyServiceText',
  );
}
