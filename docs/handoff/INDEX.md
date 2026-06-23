# Handoff Knowledge Tree

Scope: FlClash-new 跨 session 复用的功能开发流程、验证方法和已结案工作线经验。  
Status: bootstrap (2026-06-23)

## 核心摘要

本目录只记录后续功能开发会复用的 why + how，不重复 commits、PR 描述和普通变更列表。

当前仓库协作重点是 macOS Flutter app。涉及配置、Riverpod、Freezed、macOS 原生能力、发版安装的功能，优先参考这里的流程，再回到代码定位。

## 使用规则

- `INDEX.md` 只做导航和通用原则，不写长篇过程。
- 结案功能线写成 leaf 文档，放在同目录下。
- 每篇 leaf 优先写：需求判断、实现落点、验证命令、踩坑、下次复用步骤。
- 发现新的反复踩坑时，补充到对应 leaf，不要把临时聊天结论留在会话里。

## 已结案功能线

- [macOS 代理控制与流量统计功能线](./2026-06-macos-proxy-traffic-release.md)  
  覆盖流量统计 JSONL、域名代理独立入口、按应用选择代理、macOS release 构建、安装与 GitHub Release 发布。

## 通用原则

1. 先验证现有数据是否存在，再决定是分析历史还是补运行时记录。
2. macOS 桌面功能不要只看源码通过；必须验证编译产物和安装后的 app bundle。
3. Freezed / Riverpod / provider 模型改动后必须跑代码生成，再做定向 `flutter analyze`。
4. 发版构建前先确认版本号，构建后确认 `Info.plist` 和最终产物名。
5. `setup.dart` / Flutter 构建命令可能改动 lockfile，发版前必须检查 `git status`。

