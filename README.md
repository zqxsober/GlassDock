<!-- Copyright 2026 zqxsober. SPDX-License-Identifier: Apache-2.0 -->

# GlassDock

中文 · [English](README.en.md)

[![macOS 26+](https://img.shields.io/badge/macOS-26%2B-black?logo=apple)](https://www.apple.com/macos/)
[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange?logo=swift)](https://swift.org/)
[![Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)

GlassDock 是一个为 macOS 26 及以上版本设计的原生悬浮 Dock。它把固定的应用和文件夹、当前运行窗口，以及时钟、系统状态、日历、提醒事项、音乐和 Codex 使用额度放在可调整的 Liquid Glass 栏中。

[下载最新版本](https://github.com/zqxsober/GlassDock/releases/latest) · [查看所有发布版本](https://github.com/zqxsober/GlassDock/releases)

## 功能

### Dock 与窗口

- 固定最多 12 个应用或文件夹；支持拖动调整顺序。
- 自动显示运行中的应用窗口。为多窗口应用展示独立窗口入口；点击入口可切换到对应窗口。
- 多窗口入口标题超过 8 个字符时显示省略号，完整标题仍可通过帮助提示和辅助功能读取。
- 在应用入口上右键或按住 Control 点击，可关闭单个窗口或取消固定应用；固定的应用和文件夹也可通过右键菜单移除。
- 悬停放大、图标比例、Dock 尺寸（10–96 点）、强调色和启动时显示均可设置。
- 使用快捷键 `⌘⇧D` 显示或隐藏悬浮 Dock。
- 可用 Tab / Shift-Tab 移动焦点，并用 Return 激活当前入口或组件。

### 小组件

可添加多个独立组件实例，并在控制中心编辑组件。当前可用类型包括：

| 类别 | 内容 |
| --- | --- |
| 时钟与计时 | 时钟、世界时钟、秒表、专注计时、时间进度、倒计时、闹钟、喝水提醒 |
| 日历与提醒 | 日期、下一个日程、议程、提醒列表、下一条提醒、未完成数量 |
| 便签 | 可编辑的便签 |
| 媒体 | Apple Music（macOS“音乐”App）的播放信息和播放控制 |
| 系统 | 电池状态、CPU 与内存活动、网络速度 |
| AI | Codex 账户 5 小时和 7 天额度的数字、圆环、条形或胶囊样式 |
| 系统快捷方式 | 运行指定的快捷指令，或选择文件后通过隔空投送分享 |

天气组件目前是界面占位，尚未连接天气服务，也不会显示实时天气数据。商业数据和股票组件不属于当前可用功能。

## 安装

1. 从 [GitHub Releases](https://github.com/zqxsober/GlassDock/releases/latest) 下载 GlassDock 的 DMG。
2. 打开 DMG，将 `GlassDock.app` 拖入“应用程序”文件夹，然后从那里启动。
3. 根据需要，在系统弹出的权限提示中允许对应功能。

`v0.0.1` DMG 使用临时签名，尚未经过 Apple 公证。首次打开时，Gatekeeper 可能会显示开发者无法验证或阻止启动的提示。请先查看对应发布页的签名状态，并按 macOS 的提示在“系统设置 → 隐私与安全性”中确认是否允许打开。后续版本的签名和公证状态以各自的发布说明为准。

## 权限与隐私

- **辅助功能**：连接后，GlassDock 可读取普通应用窗口标题，并支持按窗口切换或关闭。窗口管理使用 macOS 辅助功能 API，不需要“屏幕录制”权限。未授权时，窗口级操作可能不可用。
- **日历与提醒事项**：只有连接相应组件后才会请求访问权限。
- **自动化（音乐）**：只有连接 Apple Music 组件后才会请求控制 macOS“音乐”App。
- **Codex 额度**：需要安装 [Codex CLI](https://developers.openai.com/codex/cli/) 并登录 ChatGPT 账号，额度组件才可读取该账号的套餐额度。它只查询额度状态，不发送对话提示词，也不触发模型推理；数据包括 5 小时和 7 天窗口的剩余额度及重置时间。
- **本地设置**：Dock 布局和组件配置保存在本机的 UserDefaults 中。GlassDock 不要求 GlassDock 账户，也没有云端同步。

## 开发

需要 macOS 26 或更高版本，以及提供 Swift 6.2 工具链和 macOS 26 SDK 的 Xcode。SwiftPM 包使用 Swift 6.2 工具版本，并以 Swift 5 语言模式编译。

```bash
git clone https://github.com/zqxsober/GlassDock.git
cd GlassDock
./build.sh
```

本地构建会在 `dist/GlassDock.app` 生成应用，默认使用 ad-hoc 签名。运行测试：

```bash
xcrun swift test --disable-sandbox
```

设置 `DEVELOPER_ID_APPLICATION` 后，`build.sh` 可使用对应的 Developer ID Application 证书签名；未设置时默认使用 ad-hoc 签名。发布脚本目标是同时支持 Apple 芯片（arm64）和 Intel（x86_64）的通用 DMG。

创建 `v0.0.1` 发布包的命令：

```bash
./scripts/release.sh --version 0.0.1
```

若配置了 Developer ID Application 证书和 `notarytool` 凭据，可通过 `DEVELOPER_ID_APPLICATION` 与 `NOTARYTOOL_PROFILE` 环境变量进行签名和公证。发布脚本的结果及该版本的实际签名状态应以发布页说明为准。

## 项目结构

```text
Sources/GlassDock/       SwiftUI / AppKit 应用、浮动 Dock 和组件
Sources/GlassDockCore/   偏好设置、窗口分组、组件与额度数据模型
Tests/                  SwiftPM 核心逻辑和 UI 测试
Resources/              应用配置与图标生成资源
```

## 许可证

GlassDock 根据 [Apache License 2.0](LICENSE) 授权。
