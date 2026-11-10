# 本机 Android 构建依赖与复用

核验日期：2026-11-10。适用于当前 macOS 开发机；换机器先核验路径，不要复制缓存绝对路径配置到共享 Gradle 工程。

## 已有工具与缓存

| 项目 | 当前本机路径 / 版本 |
| --- | --- |
| Flutter | `/Users/manzhiyuan/flutter-sdk`，3.41.6 stable，revision `db50e20168` |
| Dart | Flutter 自带 3.11.4 |
| JDK | `/opt/homebrew/opt/openjdk@17`，17.0.18 |
| Android SDK | `/opt/homebrew/share/android-commandlinetools` |
| SDK 平台 | 已安装 android-34、android-35、android-36；项目 compileSdk / targetSdk 36 |
| Build Tools | 已安装 28.0.3、34.0.0、35.0.0 |
| NDK | 已安装 28.0.13004108、28.2.13676358；项目配置 28.0.13004108 |
| CMake | SDK 内 `cmake/3.22.1` |
| Gradle | wrapper 8.13；缓存 `/Users/manzhiyuan/.gradle/wrapper/dists/gradle-8.13-all/` |
| AGP / Kotlin | `android/settings.gradle.kts`：8.12.2 / 2.2.10 |
| Gradle 依赖缓存 | `/Users/manzhiyuan/.gradle/caches/` |
| Dart 包缓存 | `/Users/manzhiyuan/.pub-cache/` |
| Flutter 引擎缓存 | `/Users/manzhiyuan/flutter-sdk/bin/cache/` |
| Android 原生代理内核 | 仓库 `libclash/android/{arm64-v8a,armeabi-v7a,x86_64}/libclash.so` 与 `libclash/android/includes/` |

`android/local.properties` 已有 `flutter.sdk` 与 `sdk.dir`，该文件被 Git 忽略。`libclash/` 内核也被忽略，但本机已存在；Gradle 的 `copyNativeLibs` 会将其复制到 `android/core/src/main/jniLibs`。只改 Dart UI 不需要重编 Go 内核。

## 首选复用流程

在仓库根目录执行，保留现有 `build/`、`.dart_tool/` 和全局缓存，不要先执行 `flutter clean`、删除缓存或升级依赖。

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@17
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
/Users/manzhiyuan/flutter-sdk/bin/flutter build apk --debug --no-pub --target-platform android-arm64
```

本机真机是 arm64。APK：`build/app/outputs/flutter-apk/app-debug.apk`；debug 包名 `com.go.class.dev`。`--no-pub` 跳过重复解析 Dart 依赖，但 **不会** 禁止 Gradle 联网。

需要强制验证 Gradle 缓存时，在 `android/` 运行：

```bash
JAVA_HOME=/opt/homebrew/opt/openjdk@17 \
ANDROID_HOME=/opt/homebrew/share/android-commandlinetools \
./gradlew :app:assembleDebug --offline \
  -Ptarget-platform=android-arm64 -Ptarget=lib/main.dart
```

直接 Gradle 构建产物可在 `build/app/outputs/apk/debug/` 查看。Dart 包解析状态缺失时先运行 `flutter pub get --offline`；只有明确缺少某个包/构件时才联网补齐，不必重装 SDK。Gradle 离线提示缺少构件时，使用同一环境去掉 `--offline` 补齐一次。

```bash
adb devices -l
adb install -r -t build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n com.go.class.dev/com.follow.clash.MainActivity
```

覆盖安装保留数据；遇到签名不一致或手机拒绝安装，不要卸载旧应用绕过，以免丢失配置与流量历史。

## 本次核验

- `flutter build apk --debug --target-platform android-arm64` 构建成功。
- 紧接着用上面的 Gradle `--offline` 命令构建成功，仅 15 秒；428 项任务中 398 项 UP-TO-DATE。
- ADB 流式安装本次返回空错误；改用 `adb push APK /data/local/tmp/flclash-weekly.apk` 后执行 `adb shell pm install -r -t /data/local/tmp/flclash-weekly.apk` 覆盖安装成功。
- 此次保留并使用了现有 SDK、JDK、NDK、wrapper 和代理内核，Gradle 仍下载了当前构建需要的未命中缓存的依赖，首次耗时约 10 分钟；不能将“SDK 已装”视为“全部 Maven 构件已缓存”。
- NDK 版本提示：`jni` 要求 28.2.13676358，项目仍配置 28.0.13004108。本次构建成功，未为此修改项目版本；将来若出现实际 NDK 编译失败，先使用已安装的较高版本，不要重新下载。

## 代理流量采集内核（2026-11-10 修复）

Android 周报已改为 Go 内核在实际 TCP/UDP 数据读写时累加，不再通过 Flutter 每秒采样连接估算。内核负责保存 `proxy-traffic-history.json`；Flutter 只读取。原有 `weekly-traffic.json` 仅用于首次导入，不会把旧版漏掉的流量虚构补齐。

这部分修改涉及本机忽略的 `libclash.so`，仅运行 Flutter/Gradle 不会自动重编 Go 内核。改 `core/` 后，在仓库根目录先运行：

```bash
scripts/build_android_core_local.sh
```

- 复用 `/opt/homebrew/bin/go`（本次为 Go 1.26.2）、`~/go/pkg/mod`、`~/Library/Caches/go-build` 和已安装的 NDK 28.0.13004108；默认 `GOPROXY=off GOSUMDB=off`。
- 仅重编当前真机需要的 arm64，保留其他 ABI 的旧产物；发布其他 ABI 前也必须用相应 GOARCH/NDK clang 重编，不能把未更新的内核作为已修复版本发布。
- `core/Clash.Meta` 是子模块，统计读写钩子通过独立 PR 合入其 `codex/request-failure-notify` 分支，主仓库固定到相应提交。重新克隆后运行 `git submodule update --init --recursive`，无需手动应用本地补丁；不要用浮动的远端分支替代主仓库固定的提交。
- 编译参数沿用 `setup.dart`：`CGO_ENABLED=1 GOOS=android GOARCH=arm64`、`-tags=with_gvisor`、`-buildmode=c-shared`，clang 为 NDK 的 `aarch64-linux-android21-clang`。
- 编译成功才替换 `libclash/android/arm64-v8a/libclash.so` 与对应头文件，再使用前述 Gradle 离线命令打包。
- Go 在 Android 上默认使用 UTC，采集器初始化时读取手机 `persist.sys.timezone`，按手机日历日期归档。
- 流量累计自动每秒原子保存，正常内核关闭时刷新；强杀进程或断电仍可能丢失最后一秒尚未保存的数据。

定向验证：

```bash
GOPROXY=off GOSUMDB=off go -C core test -race ./internal/traffichistory
GOPROXY=off GOSUMDB=off go -C core test github.com/metacubex/mihomo/tunnel/statistic
/Users/manzhiyuan/flutter-sdk/bin/flutter test --no-pub test/common/weekly_traffic_test.dart
```

本次流量修复验证结果：

- Go 历史存储与 TCP/UDP 钩子测试（含 `-race`）通过；覆盖短连接、缓冲/快速拷贝路径、嵌套 tracker 排重、并发落盘、跨午夜、重启、旧数据导入及损坏文件保护。
- Dart 三项投影测试通过，覆盖重复刷新不累加、包名/应用名合并、旧磁盘读取不能覆盖新内核数据。
- 真机确认：结束 Flutter 界面进程后，代理服务进程保持运行；在手机 Chrome 中发起代理请求，Chrome 的原生持久化累计增加 139,521 字节，重新打开界面仍保留数据，迁移生效时间不变。
- ADB shell 经混合端口发起的测试请求在此手机现有规则下走 DIRECT，正确不增加代理汇总；不能仅凭 HTTP 请求成功就判定统计验证通过。
- 测试后已恢复代理开关到测试前的停止状态。
