// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 zqxsober
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import AppKit
import GlassDockCore
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<DashboardPage?>(get: { store.page }, set: { if let page = $0 { store.page = page } })) {
                Section("工作空间") {
                    ForEach(DashboardPage.allCases) { page in
                        Label(page.rawValue, systemImage: page.symbol)
                            .badge(page == .dock ? store.preferences.applications.count : 0)
                            .tag(page)
                            .accessibilityIdentifier("nav-\(page.id)")
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("GlassDock")
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
            .safeAreaInset(edge: .bottom) {
                Label("本地运行 · GlassDock \(AppVersion.current)", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary).padding(18)
            }
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(store.page == .overview ? "桌面，恰到好处。" : store.page.rawValue)
                            .font(.system(size: 25, weight: .semibold))
                        Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    }
                    Group {
                        switch store.page {
                        case .overview: OverviewPage()
                        case .dock: DockPage()
                        case .widgets: WidgetsPage()
                        case .preferences: PreferencesPage()
                        }
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.canvas)
            .navigationTitle(store.page.rawValue)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { store.isDockVisible.toggle() } label: {
                        Label(store.isDockVisible ? "隐藏 Dock" : "显示 Dock", systemImage: store.isDockVisible ? "eye" : "eye.slash")
                    }
                    .help("显示或隐藏悬浮 Dock · ⌘⇧D")
                    .accessibilityIdentifier("toggle-dock")
                }
            }
        }
        .foregroundStyle(.primary)
        .tint(store.accent)
        .focusEffectDisabled()
        .frame(minWidth: 1010, minHeight: 720)
        .overlay(alignment: .bottom) {
            if let toast = store.toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12)).padding(.horizontal, 20).padding(.vertical, 13)
                    .glassEffect(.regular, in: Capsule()).padding(.bottom, 20)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.toast)
        .alert("GlassDock", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("知道了", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .background(WindowSetup())
    }

    private var subtitle: String {
        switch store.page {
        case .overview: return "你的常用应用、文件夹与日常灵感，都在触手可及的地方。"
        case .dock: return "固定常用应用和文件夹，按你的习惯排列。所有更改实时保存。"
        case .widgets: return "有用的信息，不多不少。只留下你需要的。"
        case .preferences: return "调整细节，让 GlassDock 更像你。"
        }
    }
}

struct OverviewPage: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        VStack(spacing: 20) {
            hero
            HStack(spacing: 14) {
                metric("固定入口", value: "\(store.preferences.applications.count)", suffix: "个常用伙伴", symbol: "square.stack.3d.up")
                metric("桌面组件", value: "\(store.enabledWidgetCount)", suffix: "个恰好的信息", symbol: "square.grid.2x2")
                metric("隐私优先", value: "100", suffix: "% 本地设置", symbol: "lock.shield")
            }
            HStack(alignment: .top, spacing: 18) {
                focusCard
                appearanceCard
            }
            HStack {
                Image(systemName: "command").font(.system(size: 10))
                Text("⌘ ⇧ D  显示 / 隐藏 Dock").font(.system(size: 10))
                Spacer()
                Text("DESIGNED TO FEEL AT HOME").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1.8)
            }.foregroundStyle(.secondary).padding(.horizontal, 4).padding(.top, 1)
        }
    }

    private var hero: some View {
        GlassEffectContainer(spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label("你的日常，轻盈呈现", systemImage: "sparkle")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(store.accent)
                    Spacer()
                    HStack(spacing: 5) {
                        Circle().fill(store.accent).frame(width: 4, height: 4)
                        Text("LIVE PREVIEW").font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(1.6)
                    }.foregroundStyle(.secondary)
                }
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("一方轻盈，\n盛下你的日常。")
                            .font(.system(size: 34, weight: .medium)).tracking(-1).lineSpacing(3)
                        Text("流动的玻璃质感，熟悉的桌面体验。\n不取代你的习惯，只让它更顺手。")
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(5)
                    }
                    Spacer(minLength: 0)
                    ClockOrb(size: 139).padding(.trailing, 24)
                }.padding(.top, 23).padding(.bottom, 28)
                HStack {
                    Spacer(minLength: 0)
                    DockStrip(preview: true, maxWidth: 652)
                    Spacer(minLength: 0)
                }
                HStack {
                    Image(systemName: "cursorarrow.rays")
                    Text("悬停试试 · 点击图标打开应用或文件夹")
                }.font(.system(size: 9)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.top, 13)
            }
        }
        .padding(25)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26))
    }

    private func metric(_ title: String, value: String, suffix: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(title).font(.system(size: 10)).foregroundStyle(Color.muted)
                Spacer()
                Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(value).font(.system(size: 26, weight: .medium, design: .rounded))
                Text(suffix).font(.system(size: 9)).foregroundStyle(Color.muted)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).contentCard(radius: 18)
    }

    private var focusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("留一点时间，给专注", systemImage: "leaf")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(store.focus.isRunning ? "进行中" : "慢下来，也很好")
                    .font(.system(size: 8)).foregroundStyle(Color.muted)
            }
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(Color(nsColor: .separatorColor), lineWidth: 3)
                    Circle().trim(from: 0, to: max(0.015, store.focus.progress(at: store.now)))
                        .stroke(store.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                    Image(systemName: store.focus.isRunning ? "leaf.fill" : "leaf").font(.system(size: 23)).foregroundStyle(store.accent)
                }.frame(width: 63, height: 63)
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.focusLabel).font(.system(size: 29, weight: .light, design: .rounded)).monospacedDigit()
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 12) {
                            Button(store.focusButtonTitle) { store.toggleFocus() }
                                .buttonStyle(.glassProminent).tint(store.accent)
                            Button { store.resetFocus() } label: { Image(systemName: "arrow.counterclockwise") }
                                .buttonStyle(.glass).tint(nil).help("重置专注计时器")
                                .accessibilityLabel("重置专注计时器")
                        }
                        .controlSize(.small)
                        .buttonBorderShape(.capsule)
                    }
                }
                Spacer(minLength: 0)
            }
        }.padding(21).frame(maxWidth: .infinity, minHeight: 146, alignment: .topLeading).contentCard(radius: 20)
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Text("一点属于你的颜色").font(.system(size: 12, weight: .medium))
                Spacer()
                Image(systemName: "circle.lefthalf.filled").foregroundStyle(Color.muted)
            }
            HStack {
                AccentPicker()
                Spacer()
                Text(store.preferences.accent.title).font(.system(size: 10)).foregroundStyle(Color.muted)
            }
            Button { store.page = .preferences } label: {
                HStack {
                    Text("微调我的桌面")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }.font(.system(size: 10)).foregroundStyle(.secondary)
            }.buttonStyle(.plain)
        }.padding(21).frame(maxWidth: .infinity, minHeight: 146, alignment: .topLeading).contentCard(radius: 20)
    }
}

struct DockPage: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            VStack(spacing: 20) {
                HStack { Eyebrow(text: "YOUR EVERYDAY ESSENTIALS"); Spacer(); Text("实时预览").font(.system(size: 10)).foregroundStyle(Color.muted) }
                DockStrip(preview: true, maxWidth: 652).padding(.vertical, 16)
            }.padding(24).frame(maxWidth: .infinity).contentCard()
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("触手可及的应用与文件夹").font(.system(size: 16, weight: .medium))
                    Text("用箭头调整快捷入口顺序，右键 Dock 图标也可以移除。").font(.system(size: 10)).foregroundStyle(Color.muted)
                }
                Spacer()
                HStack(spacing: 10) {
                    AccentButton(title: "添加应用", symbol: "plus") { store.addApplications() }
                    QuietButton(title: "添加文件夹", symbol: "folder.badge.plus") { store.addFolders() }
                }
            }
            VStack(spacing: 0) {
                if store.preferences.applications.isEmpty {
                    ContentUnavailableView("从应用或文件夹开始", systemImage: "app.badge", description: Text("点击「添加应用」或「添加文件夹」，打造属于你的 Dock。"))
                        .frame(height: 200)
                }
                ForEach(Array(store.preferences.applications.enumerated()), id: \.element.id) { index, application in
                    HStack(spacing: 14) {
                        Text(String(format: "%02d", index + 1)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).frame(width: 20)
                        Image(nsImage: store.icon(for: application)).resizable().frame(width: 37, height: 37)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(application.name).font(.system(size: 12, weight: .medium))
                            Text(application.path).font(.system(size: 9)).foregroundStyle(Color.muted).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        if application.kind == .application && store.runningPaths.contains(application.path) {
                            Text("运行中").font(.system(size: 9)).foregroundStyle(store.accent).padding(.trailing, 8)
                        }
                        Button { store.preferences.move(id: application.id, offset: -1) } label: { Image(systemName: "chevron.up") }
                            .disabled(index == 0).help("向前移动")
                        Button { store.preferences.move(id: application.id, offset: 1) } label: { Image(systemName: "chevron.down") }
                            .disabled(index == store.preferences.applications.count - 1).help("向后移动")
                        Button { store.remove(application) } label: { Image(systemName: "minus.circle") }
                            .help("移除 \(application.name)").padding(.leading, 8)
                    }.font(.system(size: 11)).buttonStyle(.borderless).padding(.horizontal, 20).padding(.vertical, 13)
                    if index < store.preferences.applications.count - 1 {
                        Divider().padding(.leading, 66)
                    }
                }
            }.contentCard(radius: 20)
            Label("最多固定 12 个应用或文件夹。只保存快捷入口，不移动或修改目标。", systemImage: "info.circle")
                .font(.system(size: 10)).foregroundStyle(Color.muted)
        }
    }
}

struct WidgetsPage: View {
    @EnvironmentObject var store: AppStore
    @State private var showingPicker = false
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("组件资料库").font(.system(size: 17, weight: .medium))
                    Text("\(DockWidgetKind.availableKinds.count) 种样式，按需添加到悬浮 Dock。音乐可直接控制播放，右键可配置组件。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                AccentButton(title: "添加小组件", symbol: "plus") { showingPicker = true }
            }
            if !store.preferences.customWidgets.isEmpty {
                WidgetInstancesList().environmentObject(store)
            }
            HStack(spacing: 16) {
                widgetCard("时钟与日期", subtitle: "此刻，就是好时刻", symbol: "clock", enabled: $store.preferences.showClock) {
                    VStack(spacing: 10) {
                        Text(store.now, format: .dateTime.hour().minute()).font(.system(size: 33, weight: .light, design: .rounded)).monospacedDigit()
                        Text(store.now, format: .dateTime.month(.wide).day().weekday(.wide)).font(.system(size: 10)).foregroundStyle(Color.muted)
                    }
                }
                widgetCard("专注计时", subtitle: "为重要的事留白", symbol: "leaf", enabled: $store.preferences.showFocus) {
                    VStack(spacing: 10) {
                        Text(store.focusLabel).font(.system(size: 33, weight: .light, design: .rounded)).monospacedDigit()
                        Button(store.focusButtonTitle) { store.toggleFocus() }
                            .buttonStyle(.glassProminent).controlSize(.small).tint(store.accent)
                    }
                }
                widgetCard("电量状态", subtitle: "从容掌握剩余能量", symbol: "bolt", enabled: $store.preferences.showBattery) {
                    VStack(spacing: 12) {
                        Image(systemName: store.batterySymbol).font(.system(size: 33, weight: .light)).foregroundStyle(store.accent)
                        Text(store.batteryLabel + (store.isCharging ? " · 充电中" : "")).font(.system(size: 12)).foregroundStyle(Color.muted)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 18) {
                Eyebrow(text: "LESS, BUT BETTER")
                Text("信息刚刚好，注意力留给你。").font(.system(size: 21, weight: .medium))
                Text("计时与系统组件使用本机数据。日历和提醒仅在你主动连接后读取；音乐获得授权后自动恢复连接。\nAI 额度使用本机 Codex 登录读取。天气组件目前显示待配置。")
                    .font(.system(size: 12)).foregroundStyle(Color.muted).lineSpacing(7)
                HStack(spacing: 20) {
                    Label("无需登录", systemImage: "person.crop.circle.badge.checkmark")
                    Label("没有订阅", systemImage: "checkmark.seal")
                    Label("随时隐藏", systemImage: "eye.slash")
                }.font(.system(size: 10)).foregroundStyle(store.accent.opacity(0.8)).padding(.top, 5)
            }.padding(30).frame(maxWidth: .infinity, alignment: .leading).contentCard()
        }
        .sheet(isPresented: $showingPicker) { WidgetPicker().environmentObject(store) }
    }

    private func widgetCard<Preview: View>(_ title: String, subtitle: String, symbol: String, enabled: Binding<Bool>, @ViewBuilder preview: () -> Preview) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(store.accent)
                Spacer()
                Toggle(title, isOn: enabled).labelsHidden().toggleStyle(.switch).controlSize(.mini)
            }
            preview().frame(maxWidth: .infinity).frame(height: 130)
                .widgetGlassSurface()
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(subtitle).font(.system(size: 10)).foregroundStyle(Color.muted)
            }
        }.padding(22).frame(maxWidth: .infinity).contentCard(radius: 22)
    }
}

struct PreferencesPage: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            VStack(alignment: .leading, spacing: 5) {
                Eyebrow(text: "LOOK & FEEL").padding(.bottom, 9)
                SettingRow(title: "强调色", detail: "让细节带上一点你的个性") { AccentPicker() }
                Divider().opacity(0.3)
                SettingRow(title: "Dock 尺寸", detail: "整体调整图标、组件与 Dock 外框的宽高") {
                    HStack(spacing: 12) {
                        preferenceSlider($store.preferences.iconSize, in: DockPreferences.iconSizeRange, step: 2)
                            .frame(width: 150).accessibilityLabel("Dock 尺寸")
                        Text("\(Int(store.preferences.iconSize)) px").font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.muted).frame(width: 40)
                    }
                }
                Divider().opacity(0.3)
                SettingRow(title: "图标大小", detail: "只缩放应用与文件夹图标，Dock 外框尺寸保持不变") {
                    HStack(spacing: 12) {
                        preferenceSlider($store.preferences.iconScale, in: DockPreferences.iconScaleRange, step: 0.05)
                            .frame(width: 150).accessibilityLabel("图标大小")
                        Text("\(Int((store.preferences.iconScale * 100).rounded()))%")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.muted).frame(width: 40)
                    }
                }
                Divider().opacity(0.3)
                SettingRow(title: "Dock 圆角", detail: "调整悬浮 Dock 外框的圆角，实时生效") {
                    HStack(spacing: 12) {
                        preferenceSlider($store.preferences.cornerRadius, in: DockPreferences.cornerRadiusRange, step: 1)
                            .frame(width: 150).accessibilityLabel("Dock圆角")
                        Text("\(Int(store.preferences.cornerRadius)) px").font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.muted).frame(width: 40)
                    }
                }
                Divider().opacity(0.3)
                SettingRow(title: "悬停放大", detail: "光标经过时，给应用一个轻盈的回应") {
                    Toggle("悬停放大", isOn: $store.preferences.magnification).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }.padding(25).contentCard()
            VStack(alignment: .leading, spacing: 5) {
                Eyebrow(text: "YOUR RHYTHM").padding(.bottom, 9)
                SettingRow(title: "启动时显示 Dock", detail: "仅在打开 GlassDock 时显示，不设置开机启动") {
                    Toggle("启动时显示 Dock", isOn: $store.preferences.showDockOnLaunch).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                Divider().opacity(0.3)
                SettingRow(title: "专注时长", detail: "新的时长从下一轮开始，当前计时不受影响") {
                    Stepper(value: Binding(get: { store.preferences.focusMinutes }, set: { store.updateFocusDuration($0) }), in: 1...90) {
                        Text("\(store.preferences.focusMinutes) 分钟").font(.system(size: 12)).monospacedDigit().frame(width: 65)
                    }.frame(width: 118)
                }
            }.padding(25).contentCard()
            VStack(alignment: .leading, spacing: 12) {
                Text("本屏幕的应用窗口").font(.system(size: 13, weight: .semibold))
                Text("单窗口显示应用图标，多窗口按名称独立列出。包括本屏幕其他桌面空间的窗口，点击切换到对应窗口。固定入口和文件夹继续保留。")
                    .font(.system(size: 11)).foregroundStyle(Color.muted)
                if store.windowTracker.hasAccessibilityPermission {
                    Label("辅助功能已连接", systemImage: "checkmark.circle").font(.system(size: 11))
                } else {
                    Text("开启辅助功能权限后，可读取窗口名称并切换指定窗口；无需屏幕录制权限。")
                        .font(.system(size: 11)).foregroundStyle(Color.muted)
                    QuietButton(title: "连接窗口管理", symbol: "macwindow") {
                        store.windowTracker.requestAccessibilityAccess()
                    }
                }
            }.padding(25).frame(maxWidth: .infinity, alignment: .leading).contentCard()
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "lock.shield").font(.system(size: 21)).foregroundStyle(store.accent)
                VStack(alignment: .leading, spacing: 7) {
                    Text("你的桌面，只属于你。").font(.system(size: 12, weight: .medium))
                    Text(L10n.text(
                        zh: "设置仅保存在本机。不读取其他应用的登录信息。不修改系统 Dock。仅 CPU 温度组件会读取系统未公开的传感器接口，只读、不联网。关闭 GlassDock 即可移除悬浮栏。",
                        en: "Settings stay on this Mac. GlassDock never reads other apps' sign-in data. Never modifies the system Dock. Only the CPU Temperature widget reads an undocumented sensor interface — read-only, never sent anywhere. Quit GlassDock to remove the floating Dock."
                    ))
                        .font(.system(size: 11)).foregroundStyle(Color.muted).lineSpacing(5)
                }
            }.padding(23).frame(maxWidth: .infinity, alignment: .leading).contentCard(radius: 20)
            HStack {
                Text("GlassDock \(AppVersion.current) · macOS 26+").font(.system(size: 10)).foregroundStyle(Color.muted)
                Spacer()
                QuietButton(title: "恢复默认外观", symbol: "arrow.counterclockwise") { store.restoreAppearance() }
            }.padding(.top, 3)
        }
    }

    /// 使用无刻度原生滑块；拖动、方向键和辅助功能调节均按原步进更新数值。
    private func preferenceSlider(_ value: Binding<Double>, in bounds: ClosedRange<Double>, step: Double) -> some View {
        let steppedValue = Binding<Double>(get: { value.wrappedValue }, set: { proposed in
            let snapped = bounds.lowerBound + ((proposed - bounds.lowerBound) / step).rounded() * step
            value.wrappedValue = min(bounds.upperBound, max(bounds.lowerBound, snapped))
        })
        return Slider(value: steppedValue, in: bounds)
            .focusable().focusEffectDisabled()
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { key in
                let increasing = key.key == .rightArrow || key.key == .upArrow
                steppedValue.wrappedValue = value.wrappedValue + (increasing ? step : -step)
                return .handled
            }
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: steppedValue.wrappedValue = value.wrappedValue + step
                case .decrement: steppedValue.wrappedValue = value.wrappedValue - step
                @unknown default: break
                }
            }
    }
}
