import 'package:fl_clash/common/system.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('macOS network cleanup parsing', () {
    test('keeps network service names containing spaces', () {
      expect(MacOS.parseNetworkServiceName('(1) Wi-Fi'), 'Wi-Fi');
      expect(
        MacOS.parseNetworkServiceName('(2) USB 10/100/1000 LAN'),
        'USB 10/100/1000 LAN',
      );
      expect(MacOS.parseNetworkServiceName('invalid'), isNull);
    });

    test('detects enabled proxies and reset DNS output', () {
      expect(
        MacOS.isProxyEnabledOutput('Enabled: Yes\nServer: 127.0.0.1'),
        isTrue,
      );
      expect(
        MacOS.isProxyEnabledOutput('Enabled: No\nServer: 127.0.0.1'),
        isFalse,
      );
      expect(
        MacOS.isDnsResetOutput("There aren't any DNS Servers set on Wi-Fi."),
        isTrue,
      );
      expect(MacOS.isDnsResetOutput('223.5.5.5'), isFalse);
    });
  });

  test('cleanup failure exposes copyable reset and verification commands', () {
    const result = MacOSNetworkCleanupResult(
      serviceName: 'USB LAN',
      issues: ['DNS reset failed'],
    );

    expect(result.success, isFalse);
    expect(
      result.manualResetCommands,
      contains("networksetup -setdnsservers 'USB LAN' Empty"),
    );
    expect(result.manualResetCommands, contains('mDNSResponder'));
    expect(
      result.verificationCommands,
      contains("networksetup -getdnsservers 'USB LAN'"),
    );
    expect(result.verificationCommands, contains('scutil --proxy'));
  });
}
