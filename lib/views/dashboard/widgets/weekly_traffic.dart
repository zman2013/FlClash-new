import 'dart:async';
import 'dart:math';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/weekly_traffic.dart';
import 'package:flutter/material.dart';
import 'package:fl_clash/models/models.dart';

class WeeklyTraffic extends StatefulWidget {
  const WeeklyTraffic({super.key});

  @override
  State<WeeklyTraffic> createState() => _WeeklyTrafficState();
}

class _WeeklyTrafficState extends State<WeeklyTraffic> {
  String? _selected;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(weeklyTrafficStore.initialize());
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Widget _apps(Map<String, num> apps) {
    final entries = apps.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) return const Text('暂无代理流量记录');
    return Column(
      children: entries
          .map(
            (entry) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.apps, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(entry.value.traffic.show),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: weeklyTrafficStore,
      builder: (context, _) {
        final store = weeklyTrafficStore;
        final dates = store.dates(DateTime.now());
        final selected = dates.contains(_selected) ? _selected! : dates.last;
        final totals = store.totals(dates);
        final values = dates
            .map(
              (day) => store.totals([day]).values.fold<num>(0, (a, b) => a + b),
            )
            .toList();
        final peak = max<num>(1, values.reduce(max));
        return Card(
          margin: const EdgeInsets.only(top: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('近一周流量统计', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                const Text('含今天在内最近七天 · 仅统计代理流量'),
                if (store.completeSince != null &&
                    store.completeSince!.isAfter(
                      DateTime.now().subtract(const Duration(days: 7)),
                    ))
                  Text(
                    '完整采集始于 ${store.completeSince!.showFull}；此前历史为旧版采样，可能不完整。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (store.error != null)
                  Text(
                    store.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 160,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(
                      7,
                      (i) => Expanded(
                        child: Semantics(
                          label: '${dates[i]} ${values[i].traffic.show}',
                          selected: dates[i] == selected,
                          button: true,
                          child: InkWell(
                            onTap: () => setState(() => _selected = dates[i]),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  FittedBox(
                                    child: Text(values[i].traffic.show),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    height: max(
                                      2,
                                      100 * values[i] / peak,
                                    ).toDouble(),
                                    width: 24,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(4),
                                      color: dates[i] == selected
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : Theme.of(
                                              context,
                                            ).colorScheme.primaryContainer,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(dates[i].substring(5)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '$selected · 各 App 流量',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                _apps(store.totals([selected])),
                const Divider(height: 24),
                Text(
                  '近一周总计 ${totals.values.fold<num>(0, (a, b) => a + b).traffic.show}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                _apps(totals),
              ],
            ),
          ),
        );
      },
    );
  }
}
