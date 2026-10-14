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

extension Color {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let muted = Color(nsColor: .secondaryLabelColor)
}

struct ContentSurface: ViewModifier {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    var radius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: colorSchemeContrast == .increased ? 1.5 : 0.7)
            }
    }
}

extension View {
    func contentCard(radius: CGFloat = 24) -> some View { modifier(ContentSurface(radius: radius)) }

    /// 与音乐组件共用中性玻璃表面，由系统绘制圆角边框并适配外观与辅助功能设置。
    func widgetGlassSurface(radius: CGFloat = 15) -> some View {
        glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct Eyebrow: View {
    var text: String
    var body: some View {
        Text(text).font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(2.3).foregroundStyle(Color.muted)
    }
}

struct AccentButton: View {
    @EnvironmentObject var store: AppStore
    var title: String
    var symbol: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
        }
        .buttonStyle(.glassProminent)
        .tint(store.accent)
        .controlSize(.large)
        .buttonBorderShape(.capsule)
    }
}

struct QuietButton: View {
    var title: String
    var symbol: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
        }
        .buttonStyle(.glass)
        .tint(nil)
        .controlSize(.large)
        .buttonBorderShape(.capsule)
    }
}

struct AppIconButton: View {
    @EnvironmentObject var store: AppStore
    let application: PinnedApplication
    var size: CGFloat = 48
    var showName = false
    var iconScale: CGFloat = 1
    let hovered: Bool

    var body: some View {
        Button { store.launch(application) } label: {
            if showName {
                VStack(spacing: 5) {
                    DockIconImage(application: application, size: size, iconScale: iconScale, hovered: hovered)
                    Text(application.name).font(.system(size: 10, weight: .medium))
                        .lineLimit(1).frame(width: size + 24)
                }
                .frame(width: size + 24, height: size + 21)
                .contentShape(Rectangle())
            } else {
                DockApplicationIconLayout(
                    application: application,
                    size: size,
                    iconScale: iconScale,
                    hovered: hovered,
                    title: nil,
                    slotWidth: size + 22,
                    statusColor: application.kind == .application && store.runningPaths.contains(application.path) ? store.accent : .clear
                )
            }
        }
        .buttonStyle(.plain)
        .focusable()
        .help(openActionTitle)
        .accessibilityLabel(openActionTitle)
        .contextMenu {
            Button(openActionTitle) { store.launch(application) }
            Divider()
            Button(application.kind == .folder ? "从 Dock 移除文件夹" : "从 Dock 移除应用", role: .destructive) { store.remove(application) }
        }
    }

    private var openActionTitle: String {
        application.kind == .folder ? "在 Finder 中打开 \(application.name)" : "打开 \(application.name)"
    }
}

struct DockIconImage: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let application: PinnedApplication
    let size: CGFloat
    let iconScale: CGFloat
    let hovered: Bool

    static func magnificationScale(hovered: Bool, enabled: Bool, reduceMotion: Bool) -> CGFloat {
        hovered && enabled && !reduceMotion ? 1.15 : 1
    }

    var body: some View {
        let magnified = Self.magnificationScale(
            hovered: hovered,
            enabled: store.preferences.magnification,
            reduceMotion: reduceMotion
        ) > 1
        Image(nsImage: store.icon(for: application))
            .resizable().interpolation(.high)
            .frame(width: size * iconScale, height: size * iconScale)
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.25), radius: 6, y: 4)
            .scaleEffect(Self.magnificationScale(
                hovered: hovered,
                enabled: store.preferences.magnification,
                reduceMotion: reduceMotion
            ))
            .offset(y: magnified ? -4 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.58), value: hovered)
    }
}

/// 普通入口和窗口入口共用图标行及状态点槽，保持图标垂直中心一致。
struct DockApplicationIconLayout: View {
    let application: PinnedApplication
    let size: CGFloat
    let iconScale: CGFloat
    let hovered: Bool
    let title: String?
    let slotWidth: CGFloat
    let statusColor: Color

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: title == nil ? 0 : 14) {
                DockIconImage(application: application, size: size, iconScale: iconScale, hovered: hovered)
                if let title {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(.horizontal, title == nil ? 0 : 8)
            .frame(width: title == nil ? slotWidth : slotWidth - 6, height: size + 6)
            .background {
                if title != nil {
                    RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.45))
                }
            }
            Circle().fill(statusColor).frame(width: 3, height: 3)
        }
        .frame(width: slotWidth, height: size + 21)
        .contentShape(Rectangle())
    }
}

struct DockStrip: View {
    @EnvironmentObject var store: AppStore
    @FocusState private var focusedControl: String?
    var preview = false
    var maxWidth: CGFloat = 1000

    var body: some View {
        stripContent
            .frame(width: contentWidth * layoutScale, height: contentHeight * layoutScale, alignment: .bottom)
    }

    private var stripContent: some View {
        HStack(spacing: 10 * layoutScale) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    GlassEffectContainer(spacing: 6) {
                        HStack(spacing: 0) {
                            ForEach(store.dockEntries) { entry in
                                DockApplicationButton(entry: entry, size: iconSize, iconScale: store.preferences.iconScale)
                                    .focused($focusedControl, equals: entry.id).id(entry.id)
                            }
                            if store.dockEntries.isEmpty {
                                Button { store.addApplications() } label: {
                                    Label("添加应用", systemImage: "plus").font(.system(size: 12))
                                        .frame(width: 110, height: 58)
                                }.buttonStyle(.plain).focusable()
                                    .focused($focusedControl, equals: "dock-add")
                            }
                        }.padding(.top, 8)
                    }
                }
                .scrollIndicators(.never)
                .frame(width: applicationsWidth, height: max(iconSize + 21, store.dockEntries.isEmpty ? 58 : 0) + 11)
                .onChange(of: focusedControl) { _, control in
                    if let control, store.dockEntries.contains(where: { $0.id == control }) {
                        proxy.scrollTo(control, anchor: .center)
                    }
                }
            }
            .scaleEffect(layoutScale, anchor: .center)
            .frame(width: applicationsWidth * layoutScale, height: 80 * layoutScale)

            if store.enabledWidgetCount > 0 {
                Divider().frame(width: layoutScale, height: 34 * layoutScale)
                widgetsArea
            }
            if !preview {
                Button { AppCoordinator.shared.showMainWindow() } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 17 * layoutScale))
                        .foregroundStyle(.secondary).frame(width: 32 * layoutScale, height: 44 * layoutScale)
                }.buttonStyle(.plain).help("打开 GlassDock 控制中心")
                    .focusable().focused($focusedControl, equals: "dock-settings")
                    .accessibilityLabel("打开控制中心")
            }
        }
        .foregroundStyle(.primary)
        .tint(store.accent)
        .padding(.horizontal, 16 * layoutScale)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: CGFloat(store.preferences.cornerRadius) * layoutScale))
        .fixedSize(horizontal: true, vertical: true)
        .focusEffectDisabled()
        .onReceive(NotificationCenter.default.publisher(for: .dockKeyboardAction)) { notification in
            guard !preview, let action = notification.object as? DockKeyboardAction else { return }
            switch action {
            case .first: focusedControl = keyboardControls.first
            case .next: moveKeyboardFocus(backward: false)
            case .previous: moveKeyboardFocus(backward: true)
            case .activate: activateKeyboardControl()
            }
        }
        .onChange(of: keyboardControls) { _, controls in
            if let focusedControl, !controls.contains(focusedControl) { self.focusedControl = controls.first }
        }
    }

    private var widgetsArea: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 10 * layoutScale) {
                    HStack(spacing: 10 * layoutScale) {
                        if store.preferences.showClock {
                            VStack(alignment: .leading, spacing: 3 * layoutScale) {
                                Text(store.now, format: .dateTime.hour().minute())
                                    .font(.system(size: widgetMetrics.fontSize(19), weight: .medium, design: .rounded)).monospacedDigit()
                                Text(store.now, format: .dateTime.month(.abbreviated).day().weekday(.abbreviated))
                                    .font(.system(size: widgetMetrics.fontSize(9))).foregroundStyle(.secondary).lineLimit(1)
                            }.padding(.horizontal, 8 * layoutScale)
                                .frame(width: 132 * layoutScale, height: widgetMetrics.height, alignment: .leading)
                                .widgetGlassSurface(radius: 15 * layoutScale)
                        }
                        if store.preferences.showFocus {
                            Button { store.toggleFocus() } label: {
                                VStack(spacing: 5 * layoutScale) {
                                    Image(systemName: store.focus.isRunning ? "pause.circle" : "leaf")
                                        .font(.system(size: widgetMetrics.fontSize(16))).foregroundStyle(store.accent)
                                    Text(store.focusLabel).font(.system(size: widgetMetrics.fontSize(10), weight: .medium, design: .monospaced))
                                }.frame(width: 56 * layoutScale, height: widgetMetrics.height)
                                    .widgetGlassSurface(radius: 15 * layoutScale)
                            }.buttonStyle(.plain).help(store.focusButtonTitle)
                                .focusable().focused($focusedControl, equals: "dock-focus")
                                .accessibilityLabel(store.focusButtonTitle)
                        }
                        if store.preferences.showBattery {
                            VStack(spacing: 5 * layoutScale) {
                                Image(systemName: store.batterySymbol).font(.system(size: widgetMetrics.fontSize(17))).foregroundStyle(store.accent)
                                Text(store.batteryLabel).font(.system(size: widgetMetrics.fontSize(9), weight: .medium))
                            }.frame(width: 58 * layoutScale, height: widgetMetrics.height)
                                .widgetGlassSurface(radius: 15 * layoutScale)
                        }
                        ForEach(store.preferences.customWidgets) { configuration in
                            WidgetTile(configuration: configuration, runtime: store.widgets, preview: preview)
                                .environment(\.widgetScale, layoutScale)
                                .focused($focusedControl, equals: configuration.keyboardID)
                                .id(configuration.keyboardID)
                        }
                    }
                    .padding(.vertical, 3 * layoutScale)
                }
            }
            .scrollIndicators(.never)
            .frame(width: widgetsWidth * layoutScale, height: widgetMetrics.height + 6 * layoutScale)
            .onChange(of: focusedControl) { _, control in
                if let control, control.hasPrefix("widget-") { proxy.scrollTo(control, anchor: .center) }
            }
        }
    }

    private var keyboardControls: [String] {
        let applications = store.dockEntries.map(\.id)
        return (applications.isEmpty ? ["dock-add"] : applications)
            + (store.preferences.showFocus ? ["dock-focus"] : [])
            + store.preferences.customWidgets.map(\.keyboardID)
            + (preview ? [] : ["dock-settings"])
    }

    /// 按 Tab 或 Shift-Tab 在悬浮栏控件之间循环移动焦点。
    private func moveKeyboardFocus(backward: Bool) {
        let controls = keyboardControls
        guard !controls.isEmpty else { return }
        let current = focusedControl.flatMap { controls.firstIndex(of: $0) } ?? 0
        focusedControl = controls[(current + (backward ? -1 : 1) + controls.count) % controls.count]
    }

    /// 激活当前键盘选中的应用或悬浮栏操作。
    private func activateKeyboardControl() {
        let control = focusedControl ?? keyboardControls.first
        switch control {
        case "dock-add": store.addApplications()
        case "dock-focus": store.toggleFocus()
        case "dock-settings": AppCoordinator.shared.showMainWindow()
        default:
            if let entry = store.dockEntries.first(where: { $0.id == control }) {
                store.activate(entry)
            } else if let widget = store.preferences.customWidgets.first(where: { $0.keyboardID == control }) {
                if widget.kind == .musicFull || widget.kind == .musicMini {
                    if store.widgets.music.isConnected { store.widgets.playPauseMusic() }
                    else { store.widgets.connectMusic() }
                } else {
                    store.presentedWidgetID = widget.id
                }
            }
        }
    }

    // 图标保留原有缩放；组件在实际尺寸下排版，避免字体经过整体变换。
    private var iconSize: CGFloat { 48 }
    private var widgetMetrics: WidgetMetrics { WidgetMetrics(scale: layoutScale) }
    private var layoutScale: CGFloat { CGFloat(store.preferences.iconSize) / iconSize }
    private var layoutMaxWidth: CGFloat { maxWidth / layoutScale }
    private var contentWidth: CGFloat { applicationsWidth + widgetsWidth + chromeWidth }
    private var contentHeight: CGFloat {
        max(iconSize + 32, store.dockEntries.isEmpty ? 69 : 0,
            store.enabledWidgetCount > 0 ? 70 : 0)
    }

    private var chromeWidth: CGFloat {
        32 + (preview ? 0 : 42) + (store.enabledWidgetCount > 0 ? 21 : 0)
    }

    private var widgetsWidth: CGFloat {
        let widths: [CGFloat] = [store.preferences.showClock ? 132 : 0,
                                  store.preferences.showFocus ? 56 : 0,
                                  store.preferences.showBattery ? 58 : 0].filter { $0 > 0 }
            + store.preferences.customWidgets.map { CGFloat($0.kind.preferredWidth) }
        let desired = widths.reduce(0, +) + CGFloat(max(0, widths.count - 1)) * 10
        return min(desired, max(0, layoutMaxWidth - chromeWidth - 100))
    }

    private var applicationsWidth: CGFloat {
        let desired = max(110, store.dockEntries.reduce(0) {
            $0 + DockApplicationButton.width(for: $1, iconSize: iconSize)
        })
        return min(desired, max(100, layoutMaxWidth - chromeWidth - widgetsWidth))
    }

}

struct DockApplicationButton: View {
    @EnvironmentObject private var store: AppStore
    @State private var hovered = false
    let entry: DockApplicationEntry
    let size: CGFloat
    var iconScale: CGFloat = 1

    /// 按 Swift Character 截断可见标题，完整标题仍用于帮助提示和辅助功能标签。
    static func displayTitle(for title: String) -> String {
        guard title.count > 8 else { return title }
        return String(title.prefix(8)) + "..."
    }

    /// 使用实际字体测量短标题宽度，避免中文或 emoji 被字符数估算再次裁剪。
    static func measuredTitleWidth(for title: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let measuredWidth = (title as NSString).size(withAttributes: [.font: font]).width
        return max(64, ceil(measuredWidth) + 2)
    }

    static func width(for entry: DockApplicationEntry, iconSize: CGFloat) -> CGFloat {
        guard entry.showsWindowTitle else { return iconSize + 22 }
        return iconSize + 36 + measuredTitleWidth(for: displayTitle(for: entry.title))
    }

    var body: some View {
        Group {
            if entry.window == nil {
                AppIconButton(application: entry.application, size: size, iconScale: iconScale, hovered: hovered)
            } else {
                Button { store.activate(entry) } label: {
                    DockApplicationIconLayout(
                        application: entry.application,
                        size: size,
                        iconScale: iconScale,
                        hovered: hovered,
                        title: entry.showsWindowTitle ? Self.displayTitle(for: entry.title) : nil,
                        slotWidth: Self.width(for: entry, iconSize: size),
                        statusColor: store.accent
                    )
                }
                .buttonStyle(.plain).focusable().focusEffectDisabled()
                .help("切换到 \(entry.application.name)：\(entry.title)")
                .accessibilityLabel("切换到 \(entry.application.name)：\(entry.title)")
                .overlay {
                    DockContextMenuBridge(items: contextMenuItems, dockScale: CGFloat(store.preferences.iconSize) / 48)
                }
                .accessibilityActions {
                    if entry.showsWindowTitle {
                        Button("关闭此窗口") { store.close(entry) }
                    }
                    if store.preferences.applications.contains(where: { $0.id == entry.application.id }) {
                        Button("取消固定应用") { store.remove(entry.application) }
                    }
                }
            }
        }
        .background { ActiveHoverTrackingView(isHovered: $hovered) }
    }

    private var contextMenuItems: [(title: String, action: () -> Void)] {
        var items: [(title: String, action: () -> Void)] = []
        if entry.showsWindowTitle {
            items.append(("关闭此窗口", { store.close(entry) }))
        }
        if store.preferences.applications.contains(where: { $0.id == entry.application.id }) {
            items.append(("取消固定应用", { store.remove(entry.application) }))
        }
        return items
    }
}

struct ClockOrb: View {
    @EnvironmentObject var store: AppStore
    var size: CGFloat = 152
    var body: some View {
        ZStack {
            ForEach(0..<12) { tick in
                Capsule().fill(.primary.opacity(tick % 3 == 0 ? 0.65 : 0.22))
                    .frame(width: 1.5, height: tick % 3 == 0 ? 7 : 4)
                    .offset(y: -size * 0.4).rotationEffect(.degrees(Double(tick) * 30))
            }
            Capsule().fill(.primary).frame(width: 3, height: size * 0.24)
                .offset(y: -size * 0.105).rotationEffect(hourAngle)
            Capsule().fill(store.accent).frame(width: 2, height: size * 0.33)
                .offset(y: -size * 0.15).rotationEffect(minuteAngle)
            Circle().fill(.primary).frame(width: 7, height: 7)
        }.frame(width: size, height: size)
            .glassEffect(.regular, in: Circle())
    }
    private var hourAngle: Angle {
        let components = Calendar.current.dateComponents([.hour, .minute], from: store.now)
        return .degrees(Double(components.hour ?? 0) * 30 + Double(components.minute ?? 0) / 2)
    }
    private var minuteAngle: Angle { .degrees(Double(Calendar.current.component(.minute, from: store.now)) * 6) }
}

struct AccentPicker: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 12) {
            ForEach(DockAccent.allCases) { accent in
                Button { store.preferences.accent = accent } label: {
                    Circle().fill(accent.color.gradient).frame(width: 27, height: 27)
                        .overlay {
                            if store.preferences.accent == accent {
                                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.canvas)
                            }
                        }
                        .padding(4)
                        .overlay(Circle().strokeBorder(store.preferences.accent == accent ? accent.color.opacity(0.7) : .clear, lineWidth: 1))
                }.buttonStyle(.plain).help(accent.title).accessibilityLabel(accent.title)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.preferences.accent)
    }
}

struct SettingRow<Control: View>: View {
    var title: String
    var detail: String
    @ViewBuilder var control: Control
    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(Color.muted)
            }
            Spacer()
            control
        }.padding(.vertical, 12)
    }
}
