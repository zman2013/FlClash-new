import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/clash_config.dart';

const domainRuleActions = [
  RuleAction.DOMAIN,
  RuleAction.DOMAIN_SUFFIX,
  RuleAction.DOMAIN_KEYWORD,
  RuleAction.DOMAIN_REGEX,
];

bool isDomainRuleAction(RuleAction action) {
  return domainRuleActions.contains(action);
}

bool isDomainProxyRule(Rule rule) {
  final parsedRule = ParsedRule.parseString(rule.value);
  return isDomainRuleAction(parsedRule.ruleAction) &&
      (parsedRule.content?.trim().isNotEmpty ?? false);
}

List<Rule> filterDomainProxyRules(Iterable<Rule> rules) {
  return rules.where(isDomainProxyRule).toList();
}

String buildDomainProxyGroupName(int id) {
  return 'FLCLASH-DOMAIN-$id';
}

String normalizeDomainHost(String value) {
  final host = value.trim().replaceFirst(RegExp(r'^\*\.'), '');
  return host.startsWith('.') ? host.substring(1) : host;
}

String? buildDomainProbeUrl({
  required RuleAction ruleAction,
  required String content,
}) {
  if (![RuleAction.DOMAIN, RuleAction.DOMAIN_SUFFIX].contains(ruleAction)) {
    return null;
  }
  final host = normalizeDomainHost(content);
  if (host.isEmpty) {
    return null;
  }
  return 'https://$host';
}
