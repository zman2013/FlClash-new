# AGENTS.md

本文件用于给进入本仓库协作的编码代理提供最小但足够的上下文。

## 项目概览

- 项目名：`FlClash-new`
- 类型：Flutter 桌面优先项目，当前协作重点是 `macOS app`
- 主要语言：Dart、Swift、Objective-C/CocoaPods、少量 C/C++
- 状态管理：Riverpod
- 数据模型：Freezed + `json_serializable`
- 本地数据库：Drift
- 本地插件：`plugins/proxy`、`plugins/window_ext`、`plugins/tray_manager`

## 当前协作约束

- 平台侧只关注 `macOS`，除非用户明确要求，不要扩散到 Android/iOS/Windows/Linux。
- 配置类改动优先检查：
  - `lib/models/config.dart`
  - `lib/providers/config.dart`
  - `lib/providers/state.dart`
- 页面级改动优先检查：
  - `lib/views/`
  - `lib/common/navigation.dart`
  - `lib/application.dart`
  - `lib/manager/`

## 常用目录

- `lib/application.dart`
  - 应用入口和全局 manager 挂载链路
- `lib/views/`
  - 页面 UI
- `lib/providers/`
  - Riverpod providers
- `lib/models/`
  - Freezed / JSON 模型
- `lib/common/`
  - 公共函数、常量、导航、工具逻辑
- `lib/manager/`
  - 常驻运行时管理器
- `lib/database/`
  - Drift 表、DAO、数据库生成物
- `macos/`
  - macOS 原生工程
- `plugins/`
  - 仓库内自带插件

## 修改原则

- 不要随意修改 `plugins/` 下第三方示例工程，除非任务明确要求。
- 改 Freezed / Riverpod / Drift 模型后，必须重新生成代码。
- 新配置优先走现有配置持久化链路，不要先入手做数据库迁移，除非确实需要关系型数据。
- 新的常驻逻辑优先放在 `lib/manager/`，不要把周期任务直接塞进页面。
- 如果功能属于一级菜单页面，记得同时检查导航和页面入口是否一致。

## 代码生成

修改以下内容后需要运行代码生成：

- `lib/models/**`
- `lib/providers/**`
- `lib/database/**`

命令：

```bash
/Users/manzhiyuan/flutter-sdk/bin/flutter pub run build_runner build --delete-conflicting-outputs
```

## 分析与验证

优先使用这些命令：

```bash
/Users/manzhiyuan/flutter-sdk/bin/flutter analyze lib/application.dart lib/manager lib/models lib/providers lib/views
/Users/manzhiyuan/flutter-sdk/bin/flutter analyze lib macos
```

说明：

- 全仓 `flutter analyze` 会扫到 `plugins/` 下若干示例和子包，噪音很多，不适合作为本项目改动是否通过的唯一依据。
- 若只验证本次改动，优先精确分析 touched files 或主工程 `lib` / `macos`。

## macOS 构建

当前机器上 Flutter SDK 不在默认 `PATH`，使用绝对路径：

```bash
/Users/manzhiyuan/flutter-sdk/bin/flutter
```

当前机器上完整 Xcode 已安装在：

```bash
/Applications/Xcode.app/Contents/Developer
```

但系统全局 `xcode-select` 可能仍指向 `CommandLineTools`。如果普通 `flutter build macos` 失败并提示找不到 `xcodebuild`，优先使用：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Users/manzhiyuan/flutter-sdk/bin/flutter build macos --debug
```

调试构建产物默认位置：

```bash
build/macos/Build/Products/Debug/FlClash.app
```

Release 构建产物默认位置：

```bash
build/macos/Build/Products/Release/FlClash.app
```

## 提交前检查

提交前至少完成：

1. 代码生成
2. `flutter analyze` 针对本次改动范围通过
3. 若任务涉及桌面功能，尽量执行一次 `flutter build macos --debug`

## 已知仓库特性

- `flutter analyze lib macos` 目前可能存在少量历史 `info` 级提示，不一定是本次改动引入。
- macOS 构建时，Pods 和部分三方依赖可能产生大量 warning；先区分 warning 和真正的 build failure。
- 域名代理相关能力现在已经有独立一级页面，不应再塞回“高级配置”。

## 推荐工作流

1. 先定位入口文件和数据流。
2. 修改模型与 provider。
3. 修改页面或 manager。
4. 跑 `build_runner`。
5. 跑定向 `flutter analyze`。
6. 若涉及 macOS 功能，再跑一次 macOS build。
