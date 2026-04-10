import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

String _cannotContainCommaText() {
  return Intl.message('Cannot contain commas', name: 'cannotContainCommas');
}

String _domainRefreshIntervalText() {
  return Intl.message(
    'Latency refresh interval',
    name: 'domainRefreshIntervalText',
  );
}

String _domainMinSwitchIntervalText() {
  return Intl.message(
    'Minimum proxy switch interval',
    name: 'domainMinSwitchIntervalText',
  );
}

String _domainAutoSelectLowestDelayText() {
  return Intl.message(
    'Auto switch to the lowest-latency proxy',
    name: 'domainAutoSelectLowestDelayText',
  );
}

String _domainAutoSelectHintText() {
  return Intl.message(
    'Available only when the target is a proxy group and the domain can be probed',
    name: 'domainAutoSelectHintText',
  );
}

String _domainLatencyText() {
  return Intl.message('Latency', name: 'domainLatencyText');
}

String _domainProxyInfoText() {
  return Intl.message('Proxy', name: 'domainProxyInfoText');
}

String _domainFailureCountText(int count) {
  return Intl.message(
    '$count consecutive failures',
    name: 'domainFailureCountText',
    args: [count],
  );
}

String _domainFailureSwitchHintText() {
  return Intl.message(
    'Switch immediately after 3 consecutive failures',
    name: 'domainFailureSwitchHintText',
  );
}

String _domainSecondsLabelText() {
  return Intl.message('Seconds', name: 'domainSecondsLabelText');
}

String _domainUnsupportedLatencyText() {
  return Intl.message('Unsupported', name: 'domainUnsupportedLatencyText');
}

String _timeoutText() {
  return Intl.message('Timeout', name: 'domainTimeoutText');
}

String _formatDurationText(int seconds) {
  if (seconds < 60) {
    return '$seconds s';
  }
  final minutes = seconds ~/ 60;
  final remainSeconds = seconds % 60;
  if (remainSeconds == 0) {
    return '$minutes min';
  }
  return '$minutes min $remainSeconds s';
}

class DomainRulesView extends ConsumerWidget {
  const DomainRulesView({super.key});

  Future<void> _handleAddOrUpdate(
    WidgetRef ref, {
    DomainRoutingItem? item,
  }) async {
    final result = await globalState.showCommonDialog<DomainRoutingItem>(
      child: _AddOrEditDomainRuleDialog(item: item),
    );
    if (result == null) {
      return;
    }
    ref
        .read(domainSettingProvider.notifier)
        .update(
          (state) => state.copyWith(items: state.items.copyAndPut(result)),
        );
  }

  Future<void> _handleDelete(WidgetRef ref, DomainRoutingItem item) async {
    final result = await globalState.showMessage(
      title: appLocalizations.tip,
      message: TextSpan(
        text: appLocalizations.deleteTip(appLocalizations.rule),
      ),
    );
    if (result != true) {
      return;
    }
    ref.read(domainSettingProvider.notifier).update((state) {
      return state.copyWith(
        items: state.items.where((element) => element.id != item.id).toList(),
      );
    });
  }

  Future<void> _handleUpdateRefreshInterval(
    WidgetRef ref,
    DomainRoutingProps settings,
  ) async {
    final value = await globalState.showCommonDialog<int>(
      child: _DurationSettingDialog(
        title: _domainRefreshIntervalText(),
        initialValue: settings.refreshIntervalSeconds,
        minValue: 5,
      ),
    );
    if (value == null) {
      return;
    }
    ref
        .read(domainSettingProvider.notifier)
        .update((state) => state.copyWith(refreshIntervalSeconds: value));
  }

  Future<void> _handleUpdateMinSwitchInterval(
    WidgetRef ref,
    DomainRoutingProps settings,
  ) async {
    final value = await globalState.showCommonDialog<int>(
      child: _DurationSettingDialog(
        title: _domainMinSwitchIntervalText(),
        initialValue: settings.minSwitchIntervalSeconds,
        minValue: 0,
      ),
    );
    if (value == null) {
      return;
    }
    ref
        .read(domainSettingProvider.notifier)
        .update((state) => state.copyWith(minSwitchIntervalSeconds: value));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(domainSettingProvider);
    final statuses = ref.watch(domainStatusesProvider);
    final items = settings.items;
    return BaseScaffold(
      title: Intl.message(PageLabel.domain.name),
      actions: [
        CommonMinFilledButtonTheme(
          child: FilledButton.tonal(
            onPressed: () {
              _handleAddOrUpdate(ref);
            },
            child: Text(appLocalizations.add),
          ),
        ),
        SizedBox(width: 8),
      ],
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          _SettingTile(
            title: _domainRefreshIntervalText(),
            value: _formatDurationText(settings.refreshIntervalSeconds),
            onPressed: () {
              _handleUpdateRefreshInterval(ref, settings);
            },
          ),
          const SizedBox(height: 10),
          _SettingTile(
            title: _domainMinSwitchIntervalText(),
            value: _formatDurationText(settings.minSwitchIntervalSeconds),
            subtitle: _domainFailureSwitchHintText(),
            onPressed: () {
              _handleUpdateMinSwitchInterval(ref, settings);
            },
          ),
          const SizedBox(height: 16),
          if (items.isEmpty)
            NullStatus(
              label:
                  '${appLocalizations.nullTip(appLocalizations.rule)} (${appLocalizations.domain})',
              illustration: RuleEmptyIllustration(),
            )
          else
            ...items.map((item) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _DomainRuleItem(
                  item: item,
                  status: statuses[item.id],
                  onEdit: () {
                    _handleAddOrUpdate(ref, item: item);
                  },
                  onDelete: () {
                    _handleDelete(ref, item);
                  },
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final VoidCallback onPressed;

  const _SettingTile({
    required this.title,
    required this.value,
    this.subtitle,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return CommonCard(
      type: CommonCardType.filled,
      padding: EdgeInsets.zero,
      radius: 18,
      onPressed: onPressed,
      child: ListTile(
        minTileHeight: 0,
        minVerticalPadding: 0,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        title: Text(title),
        subtitle: subtitle == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(subtitle!),
              ),
        trailing: Text(
          value,
          style: context.textTheme.bodyMedium?.copyWith(
            color: context.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class _DomainRuleItem extends StatelessWidget {
  final DomainRoutingItem item;
  final DomainRuntimeStatus? status;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DomainRuleItem({
    required this.item,
    required this.status,
    required this.onEdit,
    required this.onDelete,
  });

  String _buildProxyInfo() {
    final currentProxyName = status?.currentProxyName ?? '';
    if (currentProxyName.isEmpty || currentProxyName == item.target) {
      return item.target;
    }
    return '${item.target} -> $currentProxyName';
  }

  String _buildLatencyInfo() {
    final probeUrl = item.probeUrl;
    final delay = status?.delay;
    if (probeUrl == null) {
      return _domainUnsupportedLatencyText();
    }
    if (delay == null) {
      return '--';
    }
    if (delay > 0) {
      return '$delay ms';
    }
    return _timeoutText();
  }

  @override
  Widget build(BuildContext context) {
    final failureCount = status?.failureCount ?? 0;
    return CommonCard(
      type: CommonCardType.filled,
      padding: EdgeInsets.zero,
      radius: 18,
      onPressed: onEdit,
      child: ListTile(
        minTileHeight: 0,
        minVerticalPadding: 0,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        title: Text(
          item.content,
          style: context.textTheme.bodyLarge?.toJetBrainsMono,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _RuleBadge(label: item.ruleAction.value),
                  _RuleBadge(label: item.target),
                  if (item.autoSelectLowestDelay)
                    _RuleBadge(label: _domainAutoSelectLowestDelayText()),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '${_domainProxyInfoText()}: ${_buildProxyInfo()}',
                style: context.textTheme.bodyMedium,
              ),
              const SizedBox(height: 6),
              Text(
                '${_domainLatencyText()}: ${_buildLatencyInfo()}',
                style: context.textTheme.bodyMedium,
              ),
              if (failureCount > 0) ...[
                const SizedBox(height: 6),
                Text(
                  _domainFailureCountText(failureCount),
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colorScheme.error,
                  ),
                ),
              ],
              if (status?.message?.isNotEmpty == true) ...[
                const SizedBox(height: 6),
                Text(
                  status!.message!,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        trailing: IconButton(
          tooltip: appLocalizations.delete,
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline),
        ),
      ),
    );
  }
}

class _RuleBadge extends StatelessWidget {
  final String label;

  const _RuleBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: context.textTheme.labelMedium?.copyWith(
            color: context.colorScheme.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}

class _AddOrEditDomainRuleDialog extends ConsumerStatefulWidget {
  final DomainRoutingItem? item;

  const _AddOrEditDomainRuleDialog({this.item});

  @override
  ConsumerState<_AddOrEditDomainRuleDialog> createState() =>
      _AddOrEditDomainRuleDialogState();
}

class _AddOrEditDomainRuleDialogState
    extends ConsumerState<_AddOrEditDomainRuleDialog> {
  final _formKey = GlobalKey<FormState>();
  final _contentController = TextEditingController();
  final _targetController = TextEditingController();
  RuleAction _ruleAction = domainRuleActions.first;
  bool _autoSelectLowestDelay = false;
  List<String> _targetSuggestions = [];

  @override
  void initState() {
    super.initState();
    _initForm();
    _loadTargetSuggestions();
  }

  void _initForm() {
    final item = widget.item;
    if (item == null) {
      return;
    }
    _ruleAction = item.ruleAction;
    _contentController.text = item.content;
    _targetController.text = item.target;
    _autoSelectLowestDelay = item.autoSelectLowestDelay;
  }

  Future<void> _loadTargetSuggestions() async {
    final targets = <String>[];

    void addTarget(String? value) {
      final text = value?.trim();
      if (text == null || text.isEmpty || targets.contains(text)) {
        return;
      }
      targets.add(text);
    }

    addTarget(_targetController.text);
    for (final group in ref.read(groupsProvider)) {
      addTarget(group.name);
    }
    addTarget(RuleTarget.DIRECT.name);
    addTarget(RuleTarget.REJECT.name);
    setState(() {
      _targetSuggestions = targets;
      if (_targetController.text.isEmpty && targets.isNotEmpty) {
        _targetController.text = targets.first;
      }
    });
  }

  void _handleSubmit() {
    final result = _formKey.currentState?.validate();
    if (result != true) {
      return;
    }
    Navigator.of(context).pop(
      DomainRoutingItem(
        id: widget.item?.id ?? snowflake.id,
        ruleAction: _ruleAction,
        content: _contentController.text.trim(),
        target: _targetController.text.trim(),
        autoSelectLowestDelay: _autoSelectLowestDelay,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      title: widget.item == null
          ? appLocalizations.addRule
          : appLocalizations.editRule,
      actions: [
        TextButton(
          onPressed: _handleSubmit,
          child: Text(appLocalizations.confirm),
        ),
      ],
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<RuleAction>(
              initialValue: _ruleAction,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: appLocalizations.ruleName,
              ),
              items: domainRuleActions
                  .map(
                    (ruleAction) => DropdownMenuItem(
                      value: ruleAction,
                      child: Text(ruleAction.value),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _ruleAction = value;
                });
              },
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _contentController,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: appLocalizations.content,
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) {
                  return appLocalizations.emptyTip(appLocalizations.content);
                }
                if (text.contains(',')) {
                  return _cannotContainCommaText();
                }
                return null;
              },
              onFieldSubmitted: (_) {
                _handleSubmit();
              },
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              initialValue: _targetSuggestions.contains(_targetController.text)
                  ? _targetController.text
                  : null,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: appLocalizations.ruleTarget,
              ),
              items: _targetSuggestions
                  .map(
                    (target) =>
                        DropdownMenuItem(value: target, child: Text(target)),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                _targetController.text = value;
              },
              validator: (_) {
                if (_targetController.text.trim().isEmpty) {
                  return appLocalizations.emptyTip(appLocalizations.ruleTarget);
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            CommonCard(
              type: CommonCardType.filled,
              padding: EdgeInsets.zero,
              radius: 18,
              onPressed: () {
                setState(() {
                  _autoSelectLowestDelay = !_autoSelectLowestDelay;
                });
              },
              child: SwitchListTile.adaptive(
                value: _autoSelectLowestDelay,
                onChanged: (value) {
                  setState(() {
                    _autoSelectLowestDelay = value;
                  });
                },
                title: Text(_domainAutoSelectLowestDelayText()),
                subtitle: Text(_domainAutoSelectHintText()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DurationSettingDialog extends StatefulWidget {
  final String title;
  final int initialValue;
  final int minValue;

  const _DurationSettingDialog({
    required this.title,
    required this.initialValue,
    required this.minValue,
  });

  @override
  State<_DurationSettingDialog> createState() => _DurationSettingDialogState();
}

class _DurationSettingDialogState extends State<_DurationSettingDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.initialValue}');
  }

  void _handleSubmit() {
    final result = _formKey.currentState?.validate();
    if (result != true) {
      return;
    }
    Navigator.of(context).pop(int.parse(_controller.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      title: widget.title,
      actions: [
        TextButton(
          onPressed: _handleSubmit,
          child: Text(appLocalizations.confirm),
        ),
      ],
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: TextFormField(
          controller: _controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: _domainSecondsLabelText(),
          ),
          validator: (value) {
            final text = value?.trim() ?? '';
            if (text.isEmpty) {
              return appLocalizations.emptyTip(_domainSecondsLabelText());
            }
            final number = int.tryParse(text);
            if (number == null) {
              return appLocalizations.numberTip(_domainSecondsLabelText());
            }
            if (number < widget.minValue) {
              return '${appLocalizations.numberTip(_domainSecondsLabelText())} >= ${widget.minValue}';
            }
            return null;
          },
          onFieldSubmitted: (_) {
            _handleSubmit();
          },
        ),
      ),
    );
  }
}
