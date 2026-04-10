import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/controller.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

const _domainRuleActions = [
  RuleAction.DOMAIN,
  RuleAction.DOMAIN_SUFFIX,
  RuleAction.DOMAIN_KEYWORD,
  RuleAction.DOMAIN_REGEX,
];

bool _isDomainProxyRule(Rule rule) {
  final parsedRule = ParsedRule.parseString(rule.value);
  return _domainRuleActions.contains(parsedRule.ruleAction) &&
      (parsedRule.content?.trim().isNotEmpty ?? false);
}

List<Rule> _filterDomainProxyRules(Iterable<Rule> rules) {
  return rules.where(_isDomainProxyRule).toList();
}

String _cannotContainCommaText() {
  return Intl.message('Cannot contain commas', name: 'cannotContainCommas');
}

class DomainRulesView extends ConsumerStatefulWidget {
  const DomainRulesView({super.key});

  @override
  ConsumerState<DomainRulesView> createState() => _DomainRulesViewState();
}

class _DomainRulesViewState extends ConsumerState<DomainRulesView> {
  Future<void> _handleAddOrUpdate([Rule? rule]) async {
    final res = await globalState.showCommonDialog<Rule>(
      child: _AddOrEditDomainRuleDialog(rule: rule),
    );
    if (res == null) {
      return;
    }
    ref.read(globalRulesProvider.notifier).put(res);
  }

  Future<void> _handleDelete(Rule rule) async {
    final res = await globalState.showMessage(
      title: appLocalizations.tip,
      message: TextSpan(
        text: appLocalizations.deleteTip(appLocalizations.rule),
      ),
    );
    if (res != true) {
      return;
    }
    ref.read(globalRulesProvider.notifier).delAll([rule.id]);
  }

  @override
  void dispose() {
    super.dispose();
    appController.autoApplyProfile();
  }

  @override
  Widget build(BuildContext context) {
    final allRules = ref.watch(globalRulesProvider).value ?? [];
    final rules = _filterDomainProxyRules(allRules);
    return BaseScaffold(
      title: Intl.message(PageLabel.domain.name),
      actions: [
        CommonMinFilledButtonTheme(
          child: FilledButton.tonal(
            onPressed: () {
              _handleAddOrUpdate();
            },
            child: Text(appLocalizations.add),
          ),
        ),
        SizedBox(width: 8),
      ],
      body: rules.isEmpty
          ? NullStatus(
              label:
                  '${appLocalizations.nullTip(appLocalizations.rule)} (${appLocalizations.domain})',
              illustration: RuleEmptyIllustration(),
            )
          : ListView.builder(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              itemCount: rules.length,
              itemBuilder: (context, index) {
                final rule = rules[index];
                return _DomainRuleItem(
                  key: ValueKey(rule.id),
                  rule: rule,
                  onEdit: () {
                    _handleAddOrUpdate(rule);
                  },
                  onDelete: () {
                    _handleDelete(rule);
                  },
                );
              },
            ),
    );
  }
}

class _DomainRuleItem extends StatelessWidget {
  final Rule rule;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DomainRuleItem({
    super.key,
    required this.rule,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final parsedRule = ParsedRule.parseString(rule.value);
    final content = parsedRule.content ?? '';
    final target = parsedRule.ruleTarget ?? '';
    return Container(
      margin: EdgeInsets.only(bottom: 10),
      child: CommonCard(
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
            content,
            style: context.textTheme.bodyLarge?.toJetBrainsMono,
          ),
          subtitle: Padding(
            padding: EdgeInsets.only(top: 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _RuleBadge(label: parsedRule.ruleAction.value),
                _RuleBadge(label: target),
              ],
            ),
          ),
          trailing: IconButton(
            tooltip: appLocalizations.delete,
            onPressed: onDelete,
            icon: Icon(Icons.delete_outline),
          ),
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
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
  final Rule? rule;

  const _AddOrEditDomainRuleDialog({this.rule});

  @override
  ConsumerState<_AddOrEditDomainRuleDialog> createState() =>
      _AddOrEditDomainRuleDialogState();
}

class _AddOrEditDomainRuleDialogState
    extends ConsumerState<_AddOrEditDomainRuleDialog> {
  final _formKey = GlobalKey<FormState>();
  final _contentController = TextEditingController();
  final _targetController = TextEditingController();
  RuleAction _ruleAction = _domainRuleActions.first;
  List<String> _targetSuggestions = [];

  @override
  void initState() {
    super.initState();
    _initForm();
    _loadTargetSuggestions();
  }

  void _initForm() {
    if (widget.rule == null) {
      return;
    }
    final parsedRule = ParsedRule.parseString(widget.rule!.value);
    _ruleAction = parsedRule.ruleAction;
    _contentController.text = parsedRule.content ?? '';
    _targetController.text = parsedRule.ruleTarget ?? '';
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

    for (final group in ref.read(groupsProvider)) {
      addTarget(group.name);
    }

    final profileId = ref.read(currentProfileIdProvider);
    if (profileId != null) {
      try {
        final config = await coreController.getConfig(profileId);
        final snippet = ClashConfigSnippet.fromJson(config);
        for (final proxyGroup in snippet.proxyGroups) {
          addTarget(proxyGroup.name);
        }
      } catch (_) {}
    }

    addTarget(RuleTarget.DIRECT.name);
    addTarget(RuleTarget.REJECT.name);

    if (!mounted) {
      return;
    }
    setState(() {
      _targetSuggestions = targets;
      if (_targetController.text.isEmpty && _targetSuggestions.isNotEmpty) {
        _targetController.text = _targetSuggestions.first;
      }
    });
  }

  void _handleSubmit() {
    if (_formKey.currentState?.validate() == false) {
      return;
    }
    final parsedRule = ParsedRule(
      ruleAction: _ruleAction,
      content: _contentController.text.trim(),
      ruleTarget: _targetController.text.trim(),
    );
    final rule = widget.rule != null
        ? widget.rule!.copyWith(value: parsedRule.value)
        : Rule.value(parsedRule.value);
    Navigator.of(context).pop(rule);
  }

  @override
  void dispose() {
    _contentController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      title: widget.rule == null
          ? '${appLocalizations.add}${appLocalizations.rule}'
          : appLocalizations.editRule,
      actions: [
        TextButton(
          onPressed: _handleSubmit,
          child: Text(appLocalizations.confirm),
        ),
      ],
      child: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            DropdownButtonFormField<RuleAction>(
              initialValue: _ruleAction,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: appLocalizations.ruleName,
                  ),
                  items: _domainRuleActions
                      .map(
                        (item) => DropdownMenuItem<RuleAction>(
                          value: item,
                          child: Text(item.value),
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
                SizedBox(height: 20),
                TextFormField(
                  controller: _contentController,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: appLocalizations.domain,
                  ),
                  onFieldSubmitted: (_) {
                    _handleSubmit();
                  },
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) {
                      return appLocalizations.emptyTip(appLocalizations.domain);
                    }
                    if (text.contains(',')) {
                      return _cannotContainCommaText();
                    }
                    return null;
                  },
                ),
                SizedBox(height: 20),
                TextFormField(
                  controller: _targetController,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: appLocalizations.proxyGroup,
                  ),
                  onFieldSubmitted: (_) {
                    _handleSubmit();
                  },
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) {
                      return appLocalizations.emptyTip(
                        appLocalizations.proxyGroup,
                      );
                    }
                    if (text.contains(',')) {
                      return _cannotContainCommaText();
                    }
                    return null;
                  },
                ),
                if (_targetSuggestions.isNotEmpty) ...[
                  SizedBox(height: 16),
                  Text(
                    '${appLocalizations.proxyGroup}:',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _targetSuggestions.map((target) {
                      return ActionChip(
                        label: Text(target),
                        onPressed: () {
                          _targetController.text = target;
                        },
                      );
                    }).toList(),
                  ),
                ],
                SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
