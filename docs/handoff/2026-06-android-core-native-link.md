# Android core native 链接与实机代理启动排障

Status: closed  
Period: 2026-06-23  
Tags: Android, Flutter, Gradle, CMake, libclash.so, libcore.so, VPN, GitHub Release

## 一句话结论

Android 代理页为空、启动代理无反应时，不要只看 APK 是否包含 `libclash.so`；必须确认 `libcore.so` 也真正链接了 `libclash.so`。本次问题的根因是 APK 带了 `libclash.so`，但 `libcore.so` 仍是未链接 `libclash` 的 JNI stub，导致 core 调用超时，代理组加载失败，VPN 不会启动。

## 症状

- Android 实机安装 `com.go.class.dev` 后，仪表盘能打开，但代理页显示“暂无代理”。
- 点击启动入口后没有建立 VPN，系统里看不到 `TRANSPORT_VPN` 网络，也没有 `tun0`。
- Flutter 日志里 core 调用会长时间卡住，例如：
  - `Invoke getConfig ... /data/user/0/com.go.class.dev/files/profiles/<id>.yaml`
  - 约 180 秒后才继续
  - `getProxies` 无有效代理组结果
- 生成的 `files/config.yaml` 只剩默认 patch 内容，例如 `proxy-groups: []`，说明 profile 没有被 core 正常解析合并。

## 先排除配置问题

1. 检查用户提供的配置文件是否真是明文 Clash YAML。
2. 如果文件没有 `proxies:`、`proxy-groups:`、`rules:`、`mixed-port:` 等关键字段，或看起来是 base64/加密二进制，不要直接当 YAML 导入。
3. 对实机私有目录里的 profile 做只读检查：

```bash
/opt/homebrew/bin/adb shell run-as com.go.class.dev sh -c \
  'find files/profiles -maxdepth 1 -type f -print -exec wc -c {} \;'

/opt/homebrew/bin/adb exec-out run-as com.go.class.dev \
  grep -n -m 5 -E '^(proxies|proxy-groups|rules|mixed-port|port|socks-port|allow-lan|mode):' \
  files/profiles/<profile-id>.yaml
```

4. 如果 profile 文件本身有 `proxies:` 和 `proxy-groups:`，但代理页仍为空，就优先怀疑 native core 链路，而不是 UI。

## APK 内容检查

先看 APK 是否包含 Android core：

```bash
unzip -l build/app/outputs/flutter-apk/app-debug.apk | \
  rg 'lib/(arm64-v8a|armeabi-v7a|x86_64)/(libclash|libcore)\.so'
```

只看到 `libcore.so`、没有 `libclash.so` 时，说明没有跑 Android core 构建。先生成 `libclash/android`：

```bash
export ANDROID_NDK=/opt/homebrew/share/android-commandlinetools/ndk/28.0.13004108
/Users/manzhiyuan/flutter-sdk/bin/dart setup.dart android
```

如果 `setup.dart android` 在最后的 `flutter_distributor` 失败，但已经生成了 `libclash/android/<abi>/libclash.so`，可以先用 Gradle 直接重打 APK。

## 更关键的动态依赖检查

即使 APK 包含 `libclash.so`，也要检查 `libcore.so` 是否链接它：

```bash
APK=/Users/manzhiyuan/workspaces/github/FlClash-new/build/app/outputs/flutter-apk/app-debug.apk
TMP=/tmp/flclash-apk-check
rm -rf "$TMP" && mkdir -p "$TMP"
unzip -q "$APK" 'lib/arm64-v8a/libcore.so' 'lib/arm64-v8a/libclash.so' -d "$TMP"

READELF=/opt/homebrew/share/android-commandlinetools/ndk/28.0.13004108/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-readelf
"$READELF" -d "$TMP/lib/arm64-v8a/libcore.so" | rg 'NEEDED|SONAME'
```

正确结果必须包含：

```text
NEEDED Shared library: [libclash.so]
```

错误结果包括：

- 只有 `libm.so` / `libdl.so` / `libc.so`，没有 `libclash.so`：`libcore.so` 是 stub 或未链接 core。
- `NEEDED` 是构建机绝对路径，例如 `/Users/.../jniLibs/arm64-v8a/libclash.so`：Android 运行时不可靠，应该改成普通 `libclash.so`。

## 本次修复点

`android/core/src/main/cpp/CMakeLists.txt`：

- 用 `CMAKE_CURRENT_LIST_DIR` 生成稳定路径。
- `if (EXISTS ...)` 必须给路径加引号。
- 使用 `target_include_directories` 和 `target_link_directories`，再 `target_link_libraries(... clash)`，让最终 `NEEDED` 保持为 `libclash.so`。
- 不要用 `IMPORTED_LOCATION` 直接传入构建机绝对路径，否则 `NEEDED` 可能也写成绝对路径。

`android/core/build.gradle.kts`：

- `preBuild` 依赖 `copyNativeLibs` 不够。
- `configureCMake*` 和 `externalNativeBuild*` 也要依赖 `copyNativeLibs`，否则直接跑 native build 时 CMake 可能先于 native lib 复制执行，落入 stub 分支。

## 强制干净重编

修完 CMake / Gradle 后，必须清掉 native 中间产物，否则 APK 可能继续打进旧的 `libcore.so`：

```bash
rm -rf \
  android/core/.cxx \
  build/core/intermediates/cxx \
  build/core/intermediates/cmake \
  build/core/intermediates/stripped_native_libs \
  build/core/intermediates/library_and_local_jars_jni \
  build/app/intermediates/merged_native_libs \
  build/app/intermediates/stripped_native_libs \
  build/app/outputs/flutter-apk/app-debug.apk

export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
export PATH="$JAVA_HOME/bin:/Users/manzhiyuan/flutter-sdk/bin:/opt/homebrew/bin:$PATH"

/Users/manzhiyuan/.gradle/wrapper/dists/gradle-8.14-all/c2qonpi39x1mddn7hk5gh9iqj/gradle-8.14/bin/gradle \
  :app:assembleDebug --no-daemon --console=plain --stacktrace
```

构建日志里要看到：

```text
C/C++: Found libclash.so for ABI arm64-v8a
C/C++: Found libclash.so for ABI armeabi-v7a
C/C++: Found libclash.so for ABI x86_64
```

## 实机验证方法

安装并启动：

```bash
/opt/homebrew/bin/adb install -r build/app/outputs/flutter-apk/app-debug.apk
/opt/homebrew/bin/adb logcat -c
/opt/homebrew/bin/adb shell am force-stop com.go.class.dev
/opt/homebrew/bin/adb shell am start -W -n com.go.class.dev/com.follow.clash.MainActivity
```

看 core 调用是否恢复毫秒级：

```bash
MAIN_PID=$(/opt/homebrew/bin/adb shell pidof com.go.class.dev | tr -d '\r')
/opt/homebrew/bin/adb logcat -d --pid "$MAIN_PID" -t 2000 | \
  rg -i 'Invoke|getConfig|setupConfig|getProxies|initClash|APP'
```

健康结果示例：

```text
Invoke getIsInit 6ms
Invoke initClash 1ms
Invoke getConfig 29ms
Invoke setupConfig 566ms
Invoke getProxies 12ms
```

代理页验证：

- UI 不再显示“暂无代理”。
- 日志里能看到 `getExternalProvider` / 代理组名，例如 `🔰节点选择`、`♻️自动选择`。

VPN 验证：

```bash
/opt/homebrew/bin/adb shell dumpsys connectivity | \
  rg -i 'NetworkAgentInfo\{|Transports: VPN|InterfaceName: tun|com\.go\.class\.dev|VpnNetworkProvider'

/opt/homebrew/bin/adb shell ip addr show | rg -n '(^[0-9]+: tun|tun0|clash|vpn)'
```

如果 adb 点击没有效果，先确认是否被锁屏/AOD 层挡住。`uiautomator dump` 里如果顶层 package 是 `com.android.systemui` / `com.miui.aod`，点击会落到系统层，不代表 app 按钮无效。

## 应用访问控制语义

- Android 规则使用 `PROCESS-NAME,<package>,<target>`，不是 macOS 的进程路径正则。
- 当前产品语义不是传统“黑名单/白名单”：只有用户显式选择了代理组的 App 才走该代理，其它 App 都应直连。
- 应用访问控制里每个 App 的“默认”表示没有显式 per-app proxy，语义固定为 `DIRECT`。
- 只有用户为某个 App 选择了具体代理组时，`appProxyMap` 才保存该 package，规则目标才会变成该代理组。
- `acceptSelected` 模式下，选中的 App 默认也应直连；需要走代理必须显式选代理组。尾部仍补 `MATCH,DIRECT`。
- `rejectSelected` 模式下，选中的 App 默认直连；如果选了代理组，Android VPN 侧不能把它加入 disallowed list，否则代理规则不会生效。
- 启用应用访问控制后，显式 App 规则后必须立刻补 `MATCH,DIRECT`。否则未显式配置代理组的 App 会继续命中订阅配置里的 `GEOSITE,...,🔰节点选择` 或末尾 `MATCH,🔰节点选择`，实际仍在走代理。
- UI 不应把空代理目标显示成“默认”，这会让用户误以为会跟随订阅的 `MATCH` 目标；应显示成 `DIRECT`。
- 因为上述语义，不能按旧 blacklist 预期删除 `MATCH,DIRECT`。那会让未显式选择代理组的 App 重新落入订阅规则，破坏“其它 App 都直连”。

健康配置形态：

```text
PROCESS-NAME,com.twitter.android,🔰节点选择
PROCESS-NAME,com.openai.chatgpt,🔰节点选择
MATCH,DIRECT
...
MATCH,🔰节点选择
```

其中前面的 `MATCH,DIRECT` 用来截断订阅规则，保证只有显式选了代理组的 App 走代理。

## X App 访问控制排障案例

现象：开启本 App 代理后，X (`com.twitter.android`) 加入访问控制但无法加载内容；同一配置用原版 FlClash 可以访问。

根因判断：

- 实机 `shared_prefs/FlutterSharedPreferences.xml` 里 `rejectList` 包含 `com.twitter.android`，但 `appProxyMap` 是空对象。
- 生成的 `files/config.yaml` 里实际规则是：

```text
PROCESS-NAME,com.twitter.android,DIRECT
...
MATCH,🔰节点选择
```

- 由于 `PROCESS-NAME` 规则插在 profile rules 前面，X 会先命中 `DIRECT`，后面的 `MATCH,🔰节点选择` 不再生效。
- 这不是包名识别失败，也不是 VPN 没捕获；是该 App 没有显式指定 per-app proxy。

取证命令：

```bash
/opt/homebrew/bin/adb shell pm list packages | rg 'twitter|x\.android|go\.class'

/opt/homebrew/bin/adb exec-out run-as com.go.class.dev \
  cat /data/user/0/com.go.class.dev/shared_prefs/FlutterSharedPreferences.xml | \
  rg -n 'accessControlProps|com\.twitter\.android|appProxyMap|selected-map'

/opt/homebrew/bin/adb exec-out run-as com.go.class.dev \
  cat /data/user/0/com.go.class.dev/files/config.yaml | \
  rg -n 'PROCESS-NAME,com\.twitter\.android|MATCH,|🔰节点选择'
```

修复/验证方式：

1. 在应用访问控制 UI 里给 X 显式选择代理组，例如 `🔰节点选择`，不要保持 `DIRECT`。
2. 重启 VPN 或重新生成配置后，确认规则变为：

```text
PROCESS-NAME,com.twitter.android,🔰节点选择
```

3. 确认 X UID 是否被 VPN 包含。X 本次实机 UID 是 `10378`，ChatGPT 是 `10388`，示例 VPN range 只排除了 ChatGPT：

```bash
/opt/homebrew/bin/adb shell dumpsys package com.twitter.android | rg -n 'uid=|appId='

/opt/homebrew/bin/adb shell dumpsys connectivity | \
  rg -i 'NetworkAgentInfo\{|Transports: VPN|InterfaceName: tun0|Uids: <|VPN:com\.go\.class\.dev'
```

健康信号：

- `tun0` 存在，`NetworkAgentInfo` 显示 `VPN:com.go.class.dev`。
- VPN `Uids` range 包含 X 的 UID。
- `dumpsys netstats detail` 中 X UID 出现在 `type=17` 的 VPN 统计项下，并有收发字节。

```bash
/opt/homebrew/bin/adb shell dumpsys netstats detail | \
  rg -n 'uid=10378|iface=tun0|ident=\[\{type=17'
```

实机自动化注意：

- 如果设备锁屏需要 PIN，`uiautomator dump` 顶层会是 `com.android.systemui` / `com.miui.aod`，不要把 adb 点击失败误判成 App 功能失败。
- 通过 `com.go.class.dev.action.START` 启动服务时，Flutter 页面侧的流量统计 manager 可能不在前台运行；此时 `traffic_analysis.jsonl` 没有 X 记录不能作为反证，应优先看 `config.yaml`、VPN UID range 和 `dumpsys netstats`。
- 手工改 `files/config.yaml` 只能用于临时验证，持久修复必须改 `shared_prefs` 里的 `appProxyMap` 或通过 UI 保存。

## 默认直连 App 混入流量统计排障案例

现象：流量统计“最近一小时”出现 Chrome、爱奇艺、Google Play 等未显式选择代理的 App。

判断步骤：

1. 先看 `traffic_analysis.jsonl` 的 `chains` 和 `remoteDestination`：

```bash
/opt/homebrew/bin/adb exec-out run-as com.go.class.dev \
  tail -n 220 files/traffic_analysis.jsonl | \
  rg 'Chrome|爱奇艺|Google Play|chains|remoteDestination'
```

2. 如果记录类似：

```text
chains: ["🇭🇰 香港7h","♻️自动选择","🔰节点选择"]
remoteDestination: "hksdk07.18838008.xyz"
```

这不是统计误判直连，而是该 App 实际命中了代理链。

3. 检查生成后的规则顺序：

```bash
/opt/homebrew/bin/adb exec-out run-as com.go.class.dev \
  sed -n '2758,2772p;3576,3586p' files/config.yaml
```

错误形态：显式 App 规则后没有 `MATCH,DIRECT`，后续订阅规则继续生效：

```text
PROCESS-NAME,com.twitter.android,🔰节点选择
PROCESS-NAME,com.openai.chatgpt,🔰节点选择
GEOSITE,google,🔰节点选择
...
MATCH,🔰节点选择
```

修复后应为：

```text
PROCESS-NAME,com.twitter.android,🔰节点选择
PROCESS-NAME,com.openai.chatgpt,🔰节点选择
MATCH,DIRECT
GEOSITE,google,🔰节点选择
...
MATCH,🔰节点选择
```

结论：默认直连的语义不只是 UI 显示为 `DIRECT`，还必须在最终 Clash rules 中用 `MATCH,DIRECT` 阻止未显式配置的 App 继续落入订阅的全局代理规则。

## Release 资产更新

修复后重新上传 Android debug APK 到 `v0.8.94`：

- `FlClash-0.8.94-android-debug.apk`
- `FlClash-0.8.94-android-debug.apk.sha256`

替换 APK 后必须同步替换 `.sha256`，避免 Release 上 APK 和校验文件不匹配。

## 下次同类问题短流程

1. 先确认 profile 文件本身是否可解析，不要把加密/订阅缓存当成明文 YAML。
2. 如果 profile 有代理但 UI 显示空，抓 `getConfig` / `getProxies` 调用耗时。
3. 检查 APK 是否包含 `libclash.so`。
4. 检查 `libcore.so` 的 `NEEDED`，必须是 `libclash.so`。
5. 看 CMake 日志是否 `Found libclash.so for ABI arm64-v8a`。
6. 修 CMake / Gradle 后清 native 中间产物，避免旧 `libcore.so` 被重新打进 APK。
7. 实机验证时先确认屏幕未被 AOD/锁屏遮挡，再点启动和查 VPN/TUN 状态。
8. 单个 App 不能访问时，先看生成的 `PROCESS-NAME,<package>,<target>`，不要只看 App 是否被选中；被选中但 `appProxyMap` 为空时就是 `DIRECT`。
9. 验证 Android 按应用代理要同时看三个层面：持久配置 `appProxyMap`、生成配置 `config.yaml`、系统 VPN UID range / netstats。
