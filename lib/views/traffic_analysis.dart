import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

String _trafficAnalysisText() {
  return Intl.message('Traffic analysis', name: 'trafficAnalysis');
}

String _trafficAnalysisDescText() {
  return Intl.message(
    'Analyze proxied traffic usage in the last hour',
    name: 'trafficAnalysisDesc',
  );
}

String _trafficAnalysisByAppText() {
  return Intl.message('App', name: 'trafficAnalysisByApp');
}

String _trafficAnalysisByDestinationText() {
  return Intl.message('Destination', name: 'trafficAnalysisByDestination');
}

String _trafficAnalysisLastHourText() {
  return Intl.message('Last hour', name: 'trafficAnalysisLastHour');
}

String _trafficAnalysisTotalText() {
  return Intl.message('Total', name: 'trafficAnalysisTotal');
}

String _trafficAnalysisResetText() {
  return Intl.message('Reset', name: 'trafficAnalysisReset');
}

String _trafficAnalysisLogPathText() {
  return Intl.message('Traffic log', name: 'trafficAnalysisLogPath');
}

class TrafficAnalysisView extends StatelessWidget {
  const TrafficAnalysisView({super.key});

  List<Widget> _buildActions() {
    return [
      IconButton(
        tooltip: _trafficAnalysisResetText(),
        icon: const Icon(Icons.restart_alt),
        onPressed: trafficAnalysisStore.reset,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: _trafficAnalysisText(),
      actions: _buildActions(),
      body: ValueListenableBuilder<TrafficAnalysisSnapshot>(
        valueListenable: trafficAnalysisStore,
        builder: (_, snapshot, _) {
          return DefaultTabController(
            length: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TrafficSummary(snapshot: snapshot),
                const Divider(height: 0),
                const _TrafficLogPath(),
                TabBar(
                  tabs: [
                    Tab(text: _trafficAnalysisByAppText()),
                    Tab(text: _trafficAnalysisByDestinationText()),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _TrafficAnalysisList(
                        icon: Icons.apps,
                        items: snapshot.appItems,
                      ),
                      _TrafficAnalysisList(
                        icon: Icons.language,
                        items: snapshot.destinationItems,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TrafficSummary extends StatelessWidget {
  final TrafficAnalysisSnapshot snapshot;

  const _TrafficSummary({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final total = snapshot.total.up + snapshot.total.down;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        spacing: 16,
        children: [
          Icon(Icons.query_stats, color: context.colorScheme.primary),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _trafficAnalysisLastHourText(),
                  style: context.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  _trafficAnalysisDescText(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.bodyMedium?.toLight,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _trafficAnalysisTotalText(),
                style: context.textTheme.bodySmall?.toLight,
              ),
              const SizedBox(height: 4),
              Text(
                total.traffic.show,
                style: context.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrafficLogPath extends StatelessWidget {
  const _TrafficLogPath();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: trafficAnalysisStore.logPath,
      builder: (_, snapshot) {
        final path = snapshot.data ?? '';
        return ListItem(
          leading: const Icon(Icons.description_outlined),
          title: Text(_trafficAnalysisLogPathText()),
          subtitle: path.isEmpty
              ? null
              : Text(path, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: path.isEmpty
              ? null
              : IconButton(
                  tooltip: appLocalizations.copy,
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: path));
                  },
                ),
        );
      },
    );
  }
}

class _TrafficAnalysisList extends StatelessWidget {
  final IconData icon;
  final List<TrafficAnalysisItem> items;

  const _TrafficAnalysisList({required this.icon, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return NullStatus(
        label: appLocalizations.nullTip(_trafficAnalysisText()),
      );
    }

    final maxTotal = items.first.total;
    return ListView.separated(
      itemBuilder: (_, index) {
        final item = items[index];
        return _TrafficAnalysisListItem(
          icon: icon,
          item: item,
          progress: maxTotal <= 0 ? 0 : item.total / maxTotal,
        );
      },
      separatorBuilder: (_, _) => const Divider(height: 0),
      itemCount: items.length,
    );
  }
}

class _TrafficAnalysisListItem extends StatelessWidget {
  final IconData icon;
  final TrafficAnalysisItem item;
  final num progress;

  const _TrafficAnalysisListItem({
    required this.icon,
    required this.item,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return ListItem(
      leading: Icon(icon),
      title: Row(
        spacing: 12,
        children: [
          Expanded(
            child: Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            item.total.traffic.show,
            style: context.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress.toDouble()),
          const SizedBox(height: 8),
          Text(item.traffic.desc, style: context.textTheme.bodySmall?.toLight),
        ],
      ),
    );
  }
}
