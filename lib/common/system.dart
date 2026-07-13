import 'dart:ffi';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:ffi/ffi.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/input.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';

class System {
  static System? _instance;

  System._internal();

  factory System() {
    _instance ??= System._internal();
    return _instance!;
  }

  bool get isDesktop => isWindows || isMacOS || isLinux;

  bool get isWindows => Platform.isWindows;

  bool get isMacOS => Platform.isMacOS;

  bool get isAndroid => Platform.isAndroid;

  bool get isLinux => Platform.isLinux;

  Future<int> get version async {
    final deviceInfo = await DeviceInfoPlugin().deviceInfo;
    return switch (Platform.operatingSystem) {
      'macos' => (deviceInfo as MacOsDeviceInfo).majorVersion,
      'android' => (deviceInfo as AndroidDeviceInfo).version.sdkInt,
      'windows' => (deviceInfo as WindowsDeviceInfo).majorVersion,
      String() => 0,
    };
  }

  Future<bool> checkIsAdmin() async {
    final corePath = appPath.corePath.replaceAll(' ', '\\\\ ');
    if (system.isWindows) {
      final result = await windows?.checkService();
      return result == WindowsHelperServiceStatus.running;
    } else if (system.isMacOS) {
      final result = await Process.run('stat', ['-f', '%Su:%Sg %Sp', corePath]);
      final output = result.stdout.trim();
      if (output.startsWith('root:admin') && output.contains('rws')) {
        return true;
      }
      return false;
    } else if (Platform.isLinux) {
      final result = await Process.run('stat', ['-c', '%U:%G %A', corePath]);
      final output = result.stdout.trim();
      if (output.startsWith('root:') && output.contains('rws')) {
        return true;
      }
      return false;
    }
    return true;
  }

  Future<AuthorizeCode> authorizeCore() async {
    if (system.isAndroid) {
      return AuthorizeCode.error;
    }
    final corePath = appPath.corePath.replaceAll(' ', '\\\\ ');
    final isAdmin = await checkIsAdmin();
    if (isAdmin) {
      return AuthorizeCode.none;
    }

    if (system.isWindows) {
      final result = await windows?.registerService();
      if (result == true) {
        return AuthorizeCode.success;
      }
      return AuthorizeCode.error;
    }

    if (system.isMacOS) {
      final shell = 'chown root:admin $corePath; chmod +sx $corePath';
      final arguments = [
        '-e',
        'do shell script "$shell" with administrator privileges',
      ];
      final result = await Process.run('osascript', arguments);
      if (result.exitCode != 0) {
        return AuthorizeCode.error;
      }
      return AuthorizeCode.success;
    } else if (Platform.isLinux) {
      final shell = Platform.environment['SHELL'] ?? 'bash';
      final password = await globalState.showCommonDialog<String>(
        child: InputDialog(
          obscureText: true,
          title: appLocalizations.pleaseInputAdminPassword,
          value: '',
        ),
      );
      final arguments = [
        '-c',
        'echo "$password" | sudo -S chown root:root "$corePath" && echo "$password" | sudo -S chmod +sx "$corePath"',
      ];
      final result = await Process.run(shell, arguments);
      if (result.exitCode != 0) {
        return AuthorizeCode.error;
      }
      return AuthorizeCode.success;
    }
    return AuthorizeCode.error;
  }

  Future<void> back() async {
    await app?.moveTaskToBack();
    await window?.hide();
  }

  Future<void> exit() async {
    if (system.isAndroid) {
      await SystemNavigator.pop();
    }
    await window?.close();
  }
}

final system = System();

class Windows {
  static Windows? _instance;
  late DynamicLibrary _shell32;

  Windows._internal() {
    _shell32 = DynamicLibrary.open('shell32.dll');
  }

  factory Windows() {
    _instance ??= Windows._internal();
    return _instance!;
  }

  bool runas(String command, String arguments) {
    final commandPtr = command.toNativeUtf16();
    final argumentsPtr = arguments.toNativeUtf16();
    final operationPtr = 'runas'.toNativeUtf16();

    final shellExecute = _shell32
        .lookupFunction<
          Int32 Function(
            Pointer<Utf16> hwnd,
            Pointer<Utf16> lpOperation,
            Pointer<Utf16> lpFile,
            Pointer<Utf16> lpParameters,
            Pointer<Utf16> lpDirectory,
            Int32 nShowCmd,
          ),
          int Function(
            Pointer<Utf16> hwnd,
            Pointer<Utf16> lpOperation,
            Pointer<Utf16> lpFile,
            Pointer<Utf16> lpParameters,
            Pointer<Utf16> lpDirectory,
            int nShowCmd,
          )
        >('ShellExecuteW');

    final result = shellExecute(
      nullptr,
      operationPtr,
      commandPtr,
      argumentsPtr,
      nullptr,
      1,
    );

    calloc.free(commandPtr);
    calloc.free(argumentsPtr);
    calloc.free(operationPtr);

    commonPrint.log(
      'windows runas: $command $arguments resultCode:$result',
      logLevel: LogLevel.warning,
    );

    if (result <= 32) {
      return false;
    }
    return true;
  }

  // Future<void> _killProcess(int port) async {
  //   final result = await Process.run('netstat', ['-ano']);
  //   final lines = result.stdout.toString().trim().split('\n');
  //   for (final line in lines) {
  //     if (!line.contains(':$port') || !line.contains('LISTENING')) {
  //       continue;
  //     }
  //     final parts = line.trim().split(RegExp(r'\s+'));
  //     final pid = int.tryParse(parts.last);
  //     if (pid != null) {
  //      await Process.run('taskkill', ['/PID', pid.toString(), '/F']);
  //     }
  //   }
  // }

  Future<WindowsHelperServiceStatus> checkService() async {
    // final qcResult = await Process.run('sc', ['qc', appHelperService]);
    // final qcOutput = qcResult.stdout.toString();
    // if (qcResult.exitCode != 0 || !qcOutput.contains(appPath.helperPath)) {
    //   return WindowsHelperServiceStatus.none;
    // }
    final result = await Process.run('sc', ['query', appHelperService]);
    if (result.exitCode != 0) {
      return WindowsHelperServiceStatus.none;
    }
    final output = result.stdout.toString();
    if (output.contains('RUNNING') && await request.pingHelper()) {
      return WindowsHelperServiceStatus.running;
    }
    return WindowsHelperServiceStatus.presence;
  }

  Future<bool> registerService() async {
    final status = await checkService();

    if (status == WindowsHelperServiceStatus.running) {
      return true;
    }

    final command = [
      '/c',
      if (status == WindowsHelperServiceStatus.presence) ...[
        'taskkill',
        '/F',
        '/IM',
        '$appHelperService.exe'
            ' & '
            'sc',
        'delete',
        appHelperService,
        '&',
      ],
      'sc',
      'create',
      appHelperService,
      'binPath= "${appPath.helperPath}"',
      'start= auto',
      '&&',
      'sc',
      'start',
      appHelperService,
    ].join(' ');

    final res = runas('cmd.exe', command);

    await Future.delayed(Duration(milliseconds: 300));
    final retryStatus = await retry(
      task: checkService,
      maxAttempts: 5,
      retryIf: (status) => status != WindowsHelperServiceStatus.running,
      delay: Duration(seconds: 1),
    );
    return res && retryStatus == WindowsHelperServiceStatus.running;
  }

  Future<bool> registerTask(String appName) async {
    final taskXml =
        '''
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.3" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Principals>
    <Principal id="Author">
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Triggers>
    <LogonTrigger/>
  </Triggers>
  <Settings>
    <MultipleInstancesPolicy>Parallel</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>false</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT72H</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>"${Platform.resolvedExecutable}"</Command>
    </Exec>
  </Actions>
</Task>''';
    final taskPath = join(await appPath.tempPath, 'task.xml');
    await File(taskPath).create(recursive: true);
    await File(
      taskPath,
    ).writeAsBytes(taskXml.encodeUtf16LeWithBom, flush: true);
    final commandLine = [
      '/Create',
      '/TN',
      appName,
      '/XML',
      '%s',
      '/F',
    ].join(' ');
    return runas('schtasks', commandLine.replaceFirst('%s', taskPath));
  }
}

final windows = system.isWindows ? Windows() : null;

class MacOS {
  static MacOS? _instance;

  static const managedDns = '223.5.5.5';

  List<String>? originDns;

  MacOS._internal();

  factory MacOS() {
    _instance ??= MacOS._internal();
    return _instance!;
  }

  Future<String?> get defaultServiceName async {
    final result = await Process.run('route', ['-n', 'get', 'default']);
    final output = result.stdout.toString();
    final deviceLine = output
        .split('\n')
        .firstWhere((s) => s.contains('interface:'), orElse: () => '');
    final lineSplits = deviceLine.trim().split(' ');
    if (lineSplits.length != 2) {
      return null;
    }
    final device = lineSplits[1];
    final serviceResult = await Process.run('networksetup', [
      '-listnetworkserviceorder',
    ]);
    final serviceResultOutput = serviceResult.stdout.toString();
    final currentService = serviceResultOutput
        .split('\n\n')
        .firstWhere((s) => s.contains('Device: $device'), orElse: () => '');
    if (currentService.isEmpty) {
      return null;
    }
    final currentServiceNameLine = currentService
        .split('\n')
        .firstWhere(
          (line) => RegExp(r'^\(\d+\).*').hasMatch(line),
          orElse: () => '',
        );
    return parseNetworkServiceName(currentServiceNameLine);
  }

  static String? parseNetworkServiceName(String line) {
    final match = RegExp(r'^\(\d+\)\s+(.+)$').firstMatch(line.trim());
    final serviceName = match?.group(1)?.trim();
    return serviceName?.isNotEmpty == true ? serviceName : null;
  }

  static bool isProxyEnabledOutput(String output) {
    return RegExp(
      r'^Enabled:\s*Yes$',
      caseSensitive: false,
      multiLine: true,
    ).hasMatch(output);
  }

  static bool isDnsResetOutput(String output) {
    final value = output.trim();
    return value.startsWith("There aren't any DNS Servers set on") ||
        value.startsWith('There are no DNS Servers set on');
  }

  Future<List<String>?> get systemDns async {
    final deviceServiceName = await defaultServiceName;
    if (deviceServiceName == null) {
      return null;
    }
    final result = await Process.run('networksetup', [
      '-getdnsservers',
      deviceServiceName,
    ]);
    final output = result.stdout.toString().trim();
    if (output.startsWith("There aren't any DNS Servers set on")) {
      originDns = [];
    } else {
      originDns = output.split('\n');
    }
    return originDns;
  }

  Future<void> updateDns(bool restore) async {
    final serviceName = await defaultServiceName;
    if (serviceName == null) {
      return;
    }
    List<String>? nextDns;
    if (restore) {
      nextDns = originDns;
      if (nextDns?.contains(managedDns) == true) {
        nextDns = [];
      }
    } else {
      final originDns = await systemDns;
      if (originDns == null) {
        return;
      }
      final needAddDns = managedDns;
      if (originDns.contains(needAddDns)) {
        return;
      }
      nextDns = List.from(originDns)..add(needAddDns);
    }
    if (nextDns == null) {
      return;
    }
    await Process.run('networksetup', [
      '-setdnsservers',
      serviceName,
      if (nextDns.isNotEmpty) ...nextDns,
      if (nextDns.isEmpty) 'Empty',
    ]);
  }

  Future<List<String>> _networkServiceNames() async {
    final result = await Process.run('/usr/sbin/networksetup', [
      '-listallnetworkservices',
    ]);
    if (result.exitCode != 0) {
      return [];
    }
    return result.stdout
        .toString()
        .split('\n')
        .map((line) => line.trim())
        .where(
          (line) =>
              line.isNotEmpty &&
              !line.startsWith('An asterisk') &&
              !line.startsWith('*'),
        )
        .toList();
  }

  Future<ProcessResult?> _runNetworkCommand(
    String executable,
    List<String> arguments,
  ) async {
    try {
      return await Process.run(
        executable,
        arguments,
      ).timeout(const Duration(seconds: 5));
    } catch (_) {
      return null;
    }
  }

  Future<MacOSNetworkCleanupResult> cleanupNetworkAfterCoreStop() async {
    final serviceName = await defaultServiceName;
    final services = await _networkServiceNames();
    final issues = <String>[];

    if (serviceName == null) {
      issues.add('无法识别默认网络服务');
    }
    if (services.isEmpty) {
      issues.add('无法读取网络服务列表');
    }

    for (final service in services) {
      for (final command in const [
        '-setautoproxystate',
        '-setwebproxystate',
        '-setsecurewebproxystate',
        '-setsocksfirewallproxystate',
      ]) {
        final result = await _runNetworkCommand('/usr/sbin/networksetup', [
          command,
          service,
          'off',
        ]);
        if (result == null || result.exitCode != 0) {
          issues.add('关闭 $service 的 $command 失败');
        }
      }
    }

    if (serviceName != null) {
      final resetResult = await _runNetworkCommand('/usr/sbin/networksetup', [
        '-setdnsservers',
        serviceName,
        'Empty',
      ]);
      if (resetResult == null || resetResult.exitCode != 0) {
        issues.add('重置 $serviceName 的 DNS 失败');
      }
    }

    await _runNetworkCommand('/usr/bin/dscacheutil', ['-flushcache']);
    await _runNetworkCommand('/usr/bin/killall', ['-HUP', 'mDNSResponder']);

    for (final service in services) {
      for (final command in const [
        '-getwebproxy',
        '-getsecurewebproxy',
        '-getsocksfirewallproxy',
      ]) {
        final result = await _runNetworkCommand('/usr/sbin/networksetup', [
          command,
          service,
        ]);
        if (result == null || result.exitCode != 0) {
          issues.add('验证 $service 的 $command 失败');
          continue;
        }
        if (isProxyEnabledOutput(result.stdout.toString())) {
          issues.add('$service 的代理仍处于开启状态');
        }
      }
    }

    if (serviceName != null) {
      final dnsResult = await _runNetworkCommand('/usr/sbin/networksetup', [
        '-getdnsservers',
        serviceName,
      ]);
      if (dnsResult == null || dnsResult.exitCode != 0) {
        issues.add('验证 $serviceName 的 DNS 失败');
      } else if (!isDnsResetOutput(dnsResult.stdout.toString())) {
        issues.add('$serviceName 仍存在手工 DNS');
      }
    }

    for (var attempt = 0; attempt < 6; attempt++) {
      final ifconfig = await _runNetworkCommand('/sbin/ifconfig', []);
      final hasFakeIpInterface =
          ifconfig?.stdout.toString().contains('inet 198.18.0.1') == true;
      if (!hasFakeIpInterface) {
        break;
      }
      if (attempt == 5) {
        issues.add('FlClash Fake-IP 虚拟网卡仍未释放');
        break;
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }

    return MacOSNetworkCleanupResult(
      serviceName: serviceName ?? 'Wi-Fi',
      issues: issues.toSet().toList(),
    );
  }
}

class MacOSNetworkCleanupResult {
  final String serviceName;
  final List<String> issues;

  const MacOSNetworkCleanupResult({
    required this.serviceName,
    required this.issues,
  });

  bool get success => issues.isEmpty;

  String get manualResetCommands {
    final service = _shellQuote(serviceName);
    return [
      'sudo /usr/sbin/networksetup -setdnsservers $service Empty',
      'sudo /usr/bin/dscacheutil -flushcache',
      'sudo /usr/bin/killall -HUP mDNSResponder',
    ].join('\n');
  }

  String get verificationCommands {
    final service = _shellQuote(serviceName);
    return [
      '/usr/sbin/networksetup -getdnsservers $service',
      "/usr/sbin/scutil --dns | /usr/bin/sed -n '1,80p'",
      '/usr/sbin/scutil --proxy',
      '/sbin/route -n get 8.8.8.8',
    ].join('\n');
  }

  static String _shellQuote(String value) {
    return "'${value.replaceAll("'", "'\\\"'\\\"'")}'";
  }
}

final macOS = system.isMacOS ? MacOS() : null;
