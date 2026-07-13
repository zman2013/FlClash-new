import 'package:fl_clash/common/task.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'domain routing rules take precedence over app access control',
    () async {
      const chromePath = '/Applications/Google Chrome.app';
      const proxyGroup = 'proxy';
      final result = await makeRealProfileTask(
        MakeRealProfileState(
          profilesPath: '/tmp/flclash-task-test',
          profileId: 1,
          rawConfig: {
            'rules': ['MATCH,$proxyGroup'],
            'proxy-groups': [
              {
                'name': proxyGroup,
                'type': 'select',
                'proxies': ['DIRECT'],
              },
            ],
          },
          realPatchConfig: defaultClashConfig,
          overrideDns: true,
          appendSystemDns: false,
          domainItems: const [
            DomainRoutingItem(
              id: 1,
              ruleAction: RuleAction.DOMAIN_SUFFIX,
              content: 'chehejia.com',
              target: 'DIRECT',
            ),
          ],
          addedRules: const [],
          accessControlProps: const AccessControlProps(
            enable: true,
            mode: AccessControlMode.acceptSelected,
            acceptList: [chromePath],
            appProxyMap: {chromePath: proxyGroup},
          ),
          defaultUA: 'test',
        ),
      );

      final rules = List<String>.from(result['rules'] as List);
      expect(rules[0], 'DOMAIN-SUFFIX,chehejia.com,DIRECT');
      expect(
        rules[1],
        r'PROCESS-PATH-REGEX,^/Applications/Google Chrome\.app(/.*)?$,proxy',
      );
      expect(rules[2], 'MATCH,DIRECT');
    },
  );
}
