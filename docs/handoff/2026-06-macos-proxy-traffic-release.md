# macOS 代理控制与流量统计功能线

Status: closed  
Period: 2026-06-21 .. 2026-06-23  
Tags: macOS, Flutter, Riverpod, Freezed, traffic_analysis.jsonl, app proxy, domain proxy, GitHub Release

## 一句话结论

这条功能线把“事后看流量”改成了“运行时采样 + 持久 JSONL”，同时把代理控制扩展到域名和应用维度；验证必须覆盖源码、生成代码、编译产物、安装路径和 GitHub Release 资产。

## 最终交付

- `v0.8.93`: 添加流量统计页面与 `traffic_analysis.jsonl`。
- `v0.8.94`: 合并域名代理控制与应用级代理控制，并发布 macOS arm64 DMG。
- Release: `https://github.com/zman2013/FlClash-new/releases/tag/v0.8.94`

## 需求判断流程

1. 用户问“近一小时流量花在哪里”时，先检查是否真的有历史请求记录。
2. 旧状态下 `flutter_01.log`、app support 目录、`database.sqlite` 都不足以复原历史流量；配置里 `openLogs: false` 且 `log-level: error` 时，不能假装能从日志还原。
3. 结论应明确切换：历史不可可靠补算，后续必须在运行时采样并持久化。
4. 用户问“除了域名还有更进一步 URL 吗”时，要说明代理层通常只有 host/SNI/目标地址/进程信息；HTTPS URL path 不会被普通代理连接元数据暴露，不能承诺完整 URL。

## 实现落点

流量统计：

- `lib/common/traffic_analysis.dart`: `TrafficAnalysisStore` 维护一小时滑动窗口、连接基线和 JSONL 写入。
- `lib/models/traffic_analysis.dart`: 记录、快照、聚合项模型。
- `lib/manager/traffic_analysis_manager.dart`: macOS 上每秒轮询 `coreController.getConnections()`。
- `lib/manager/core_manager.dart`: 连接结束时补记短连接最终 delta。
- `lib/views/traffic_analysis.dart`: 按应用和目的地展示近一小时流量。
- `lib/common/path.dart`: 固定日志路径 `traffic_analysis.jsonl`。
- `lib/common/navigation.dart`: 一级页面入口。

域名与应用级代理：

- `lib/common/task.dart`: 最终 Clash 配置生成的核心位置。
- 域名规则先规范化目标代理组，必要时克隆 hidden proxy group 用于自动选择最低延迟。
- 应用级代理复用 `AccessControlProps.currentList`，新增 `appProxyMap` 存每个 app path 对应代理组。
- 生成规则使用 `PROCESS_PATH_REGEX`，规则必须插到用户 profile rules 前面。
- allow-selected 模式下，选中 app 走指定代理或 fallback target，尾部补 `MATCH,DIRECT` 保持未选中 app 直连。
- reject-selected 模式下，选中 app 默认 `DIRECT`，但如果配置了 per-app proxy，则走指定代理。

配置与 UI：

- 新配置优先走 `lib/models/config.dart`、`lib/providers/state.dart` 的现有持久化链路。
- 页面级能力放在 `lib/views/`，一级菜单同步改 `lib/common/navigation.dart`。
- macOS 安装应用列表等平台数据放在 macOS 原生侧和 plugin bridge，不把平台扫描逻辑塞进 Flutter 页面。

## 关键设计经验

1. 流量统计要按 delta 算，不能把 `TrackerInfo.upload/download` 当作每次新增值直接累加。
2. 采样失败时保留连接基线，避免下一次成功采样把长连接重复计入。
3. 运行时重启、核心重启或配置切换时清空 active connection baseline，避免不同 core session 的连接 id 污染。
4. 只统计代理流量时，判断条件应基于 `chains` 且排除 `DIRECT` / `REJECT`，否则会把直连也算进去。
5. JSONL 是后续分析接口，不是 UI 状态来源；UI 保持内存一小时滑窗，日志用于离线追溯。
6. 代理组名称会变，保存的配置需要在 profile/group 变化后做 normalize，避免 UI 里仍指向旧 group name。
7. app path 规则要用 regex escape，避免路径里的特殊字符破坏 Clash rule。

## 验证命令

代码生成：

```bash
/Users/manzhiyuan/flutter-sdk/bin/flutter pub run build_runner build --delete-conflicting-outputs
```

定向分析：

```bash
/Users/manzhiyuan/flutter-sdk/bin/flutter analyze lib/application.dart lib/manager lib/models lib/providers lib/views
```

macOS release 构建：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Users/manzhiyuan/flutter-sdk/bin/flutter build macos --release
```

项目打包脚本：

```bash
PATH=/Users/manzhiyuan/flutter-sdk/bin:$HOME/.pub-cache/bin:$PATH \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
RELEASE_VERSION=v0.8.94 \
/Users/manzhiyuan/flutter-sdk/bin/dart setup.dart macos --arch arm64 --env stable
```

编译产物确认：

```bash
plutil -p build/macos/Build/Products/Release/FlClash.app/Contents/Info.plist | rg 'CFBundleShortVersionString|CFBundleVersion'
strings build/macos/Build/Products/Release/FlClash.app/Contents/Frameworks/App.framework/Versions/A/App | rg 'trafficAnalysis|TrafficAnalysisView|traffic_analysis.jsonl'
```

DMG 校验：

```bash
shasum -a 256 dist/FlClash-0.8.94-macos-arm64.dmg > dist/FlClash-0.8.94-macos-arm64.dmg.sha256
```

## 发版流程

1. 确认 PR 已 merge 到 `main`，本地 `main` fast-forward 到 `origin/main`。
2. 更新 `pubspec.yaml` 版本号，例如 `0.8.94+15`。
3. 提交版本号变更并 push `main`。
4. 清理旧 `dist/` 后跑 release 打包脚本。
5. 检查 `Info.plist`、DMG 文件名、SHA256。
6. 检查 `git status`；如果 `setup.dart` / `flutter pub upgrade` 只把 `pubspec.lock` 的 Flutter SDK 下限带高，恢复它，不要把本机 SDK 副作用发进 main。
7. 创建并 push annotated tag，例如 `v0.8.94`。
8. 如果 GitHub Actions 没有产出 release 资产，用 GitHub API 创建 Release，并上传 DMG 与 `.sha256`。

## 安装验证踩坑

- 手工安装时必须替换整个 `/Applications/FlClash.app`。
- 如果复制出了 `/Applications/FlClash.app/FlClash.app` 嵌套结构，macOS 可能仍启动外层旧 bundle，表现为“源码和 release 都有页面，但安装后看不到”。
- 判断页面是否编进 app，不要只看 Dart 源码；用 `strings App.framework/.../App` 查关键字符串。

## 下次开发同类功能的短流程

1. 先定位数据是否已经存在：日志、数据库、配置、core API。
2. 如果历史不可追溯，明确告诉用户边界，然后加运行时采样和持久日志。
3. 常驻逻辑放 `lib/manager/`，模型放 `lib/models/`，页面放 `lib/views/`，配置走 providers/config 的既有链路。
4. 修改模型/provider 后立即跑 build_runner，避免后面被生成物错误拖慢。
5. 先做定向 analyze，再做 macOS build。
6. 发版前用编译产物和安装 bundle 证明功能存在。
7. release 资产发布后记录 tag、DMG、sha256 和工作区干净状态。

