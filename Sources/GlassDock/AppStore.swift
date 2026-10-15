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
import Combine
import GlassDockCore
import IOKit.ps
import SwiftUI
import UniformTypeIdentifiers

enum DashboardPage: String, CaseIterable, Identifiable {
    case overview = "总览"
    case dock = "我的 Dock"
    case widgets = "小组件"
    case preferences = "偏好设置"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .dock: "dock.rectangle"
        case .widgets: "square.stack.3d.up"
        case .preferences: "slider.horizontal.3"
        }
    }
}

extension DockAccent {
    var color: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            switch self {
            case .mint:
                return dark ? NSColor(red: 0.64, green: 0.94, blue: 0.80, alpha: 1)
                    : NSColor(red: 0.06, green: 0.36, blue: 0.27, alpha: 1)
            case .ocean:
                return dark ? NSColor(red: 0.57, green: 0.78, blue: 1.0, alpha: 1)
                    : NSColor(red: 0.08, green: 0.30, blue: 0.62, alpha: 1)
            case .rose:
                return dark ? NSColor(red: 1.0, green: 0.68, blue: 0.80, alpha: 1)
                    : NSColor(red: 0.65, green: 0.17, blue: 0.34, alpha: 1)
            }
        })
    }
}

@MainActor
final class AppStore: ObservableObject {
    @Published var preferences: DockPreferences {
        didSet {
            save()
            widgets.sync(configurations: preferences.customWidgets)
        }
    }
    @Published var page: DashboardPage = .overview
    @Published var isDockVisible = false
    @Published var focus = FocusTimer()
    @Published var now = Date()
    @Published var batteryPercent: Int?
    @Published var isCharging = false
    @Published var errorMessage: String?
    @Published var runningPaths: Set<String> = []
    @Published var toast: String?
    @Published var presentedWidgetID: UUID?
    @Published var isWidgetEditorPresented = false
    @Published var isOnboardingPresented = false
    let widgets = WidgetRuntime()
    let windowTracker = DockWindowTracker()

    private let defaults: UserDefaults
    private var subscriptions = Set<AnyCancellable>()
    private var icons: [String: NSImage] = [:]
    private var toastTask: Task<Void, Never>?
    private var tickCount = 0
    private var dockScreenFrame: NSRect?
    /// 本次启动是否需要自动弹出首次启动引导；在读取偏好前判定。
    private var shouldAutoPresentOnboarding = false
    private static let preferencesKey = "glassdock.preferences.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let onboardingDecision = OnboardingPolicy.launchDecision(
            completedVersion: defaults.object(forKey: OnboardingPolicy.completedVersionKey) as? Int,
            hasExistingPreferences: defaults.data(forKey: Self.preferencesKey) != nil
        )
        switch onboardingDecision {
        case .markCompletedSilently:
            defaults.set(OnboardingPolicy.currentVersion, forKey: OnboardingPolicy.completedVersionKey)
        case .present where defaults.object(forKey: OnboardingPolicy.completedVersionKey) == nil:
            // 记下“已开始未完成”，避免新用户写入偏好后、未完成引导就被误判为老用户。
            defaults.set(OnboardingPolicy.pendingVersion, forKey: OnboardingPolicy.completedVersionKey)
        default:
            break
        }
        if let data = defaults.data(forKey: Self.preferencesKey),
           var decoded = try? JSONDecoder().decode(DockPreferences.self, from: data) {
            decoded.normalize()
            preferences = decoded
        } else {
            var initial = DockPreferences()
            initial.applications = Self.defaultApplications()
            preferences = initial
        }
        shouldAutoPresentOnboarding = onboardingDecision == .present
        focus.reset(minutes: preferences.focusMinutes)
        widgets.sync(configurations: preferences.customWidgets)
        windowTracker.objectWillChange.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        windowTracker.$errorMessage.compactMap { $0 }.receive(on: RunLoop.main)
            .sink { [weak self] message in self?.errorMessage = message }.store(in: &subscriptions)
        widgets.$errorMessage.compactMap { $0 }.receive(on: RunLoop.main)
            .sink { [weak self] message in self?.errorMessage = message }.store(in: &subscriptions)
        widgets.$alertMessage.compactMap { $0 }.receive(on: RunLoop.main)
            .sink { [weak self] message in self?.errorMessage = message }.store(in: &subscriptions)
        refreshBattery()
        refreshRunningApplications()
        Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] date in
                guard let self else { return }
                self.now = date
                if self.focus.tick(at: date) {
                    self.showToast("这一段专注完成了，休息一下吧。")
                }
                self.tickCount += 1
                if self.tickCount % 30 == 0 { self.refreshBattery() }
                if self.tickCount % 5 == 0, self.isDockVisible || self.page == .dock {
                    self.refreshDockWindows()
                }
            }.store(in: &subscriptions)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            center.publisher(for: name).receive(on: RunLoop.main)
                .sink { [weak self] notification in
                    self?.refreshRunningApplications()
                    if name == NSWorkspace.activeSpaceDidChangeNotification {
                        self?.refreshDockWindows()
                    } else if let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                        let processID = Int32(application.processIdentifier)
                        if processID != Int32(ProcessInfo.processInfo.processIdentifier) {
                            self?.refreshDockWindows(forProcessID: processID)
                        }
                    } else {
                        self?.refreshDockWindows()
                    }
                }
                .store(in: &subscriptions)
        }
    }

    var accent: Color { preferences.accent.color }
    var dockEntries: [DockApplicationEntry] {
        DockWindowGrouping.entries(pinned: preferences.applications, windows: windowTracker.windows)
    }

    /// 使用实际悬浮栏所在显示器，防止激活其他应用后跳到另一屏。
    func refreshDockWindows(on screen: NSScreen? = nil) {
        if let screen { dockScreenFrame = screen.frame }
        guard let frame = dockScreenFrame ?? NSScreen.main?.frame else { return }
        windowTracker.refresh(screenFrame: frame)
    }

    func refreshDockWindows(forProcessID processID: Int32) {
        guard let frame = dockScreenFrame ?? NSScreen.main?.frame else { return }
        windowTracker.refresh(screenFrame: frame, forProcessID: processID)
    }

    func activate(_ entry: DockApplicationEntry) {
        // 无标题入口代表本屏的单个应用图标，本屏窗口唯一不代表该进程只有一个窗口。
        if entry.showsWindowTitle, let window = entry.window { windowTracker.activate(window) }
        else { launch(entry.application) }
    }

    /// 请求关闭入口对应的单个窗口，不会退出所属应用。
    func close(_ entry: DockApplicationEntry) {
        guard let window = entry.window else {
            errorMessage = "此入口没有可单独关闭的窗口。"
            return
        }
        windowTracker.close(window)
    }

    var enabledWidgetCount: Int {
        [preferences.showClock, preferences.showFocus, preferences.showBattery].filter { $0 }.count
            + preferences.customWidgets.count
    }
    var focusLabel: String { focus.label(at: now) }
    var focusButtonTitle: String {
        switch focus.state {
        case .running: "暂停专注"
        case .paused: "继续专注"
        case .idle, .completed: "开始专注"
        }
    }
    var batteryLabel: String {
        batteryPercent.map { "\($0)%" } ?? "交流电源"
    }
    var batterySymbol: String {
        if isCharging || batteryPercent == nil { return "bolt.fill" }
        guard let batteryPercent else { return "battery.100percent" }
        if batteryPercent < 15 { return "battery.0percent" }
        if batteryPercent < 40 { return "battery.25percent" }
        if batteryPercent < 70 { return "battery.50percent" }
        return "battery.100percent"
    }

    func icon(for application: PinnedApplication) -> NSImage {
        if let image = icons[application.path] { return image }
        let image = NSWorkspace.shared.icon(forFile: application.path)
        image.size = NSSize(width: 128, height: 128)
        icons[application.path] = image
        return image
    }

    func launch(_ application: PinnedApplication) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: application.path, isDirectory: &isDirectory) else {
            errorMessage = application.kind == .folder
                ? "找不到文件夹「\(application.name)」，它可能已被移动或删除。请移除后重新添加。"
                : "找不到「\(application.name)」，它可能已被移动或卸载。请移除后重新添加。"
            return
        }
        if application.kind == .folder {
            guard isDirectory.boolValue else {
                errorMessage = "「\(application.name)」已不再是文件夹。请移除后重新添加。"
                return
            }
            guard NSWorkspace.shared.open(URL(fileURLWithPath: application.path)) else {
                errorMessage = "无法在 Finder 中打开「\(application.name)」。请确认你仍有访问权限。"
                return
            }
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: application.path), configuration: configuration) { [weak self] _, error in
            if let error {
                Task { @MainActor in self?.errorMessage = "无法打开「\(application.name)」：\(error.localizedDescription)" }
            }
        }
    }

    func addApplications() {
        guard preferences.applications.count < 12 else {
            errorMessage = "最多固定 12 个应用或文件夹，请先移除一个。"
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "选择要固定的应用"
        panel.prompt = "添加到 Dock"
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.begin { [weak self] response in
            guard response == .OK, let self else { return }
            var updated = self.preferences
            var added = 0
            for url in panel.urls {
                guard let bundle = Bundle(url: url), bundle.executableURL != nil else { continue }
                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                if updated.pin(PinnedApplication(name: name, path: url.standardizedFileURL.path)) { added += 1 }
            }
            self.preferences = updated
            self.showToast(added > 0 ? "已固定 \(added) 个应用" : "没有添加新应用：应用已固定或已达到上限。")
        }
    }

    func addFolders() {
        guard preferences.applications.count < 12 else {
            errorMessage = "最多固定 12 个应用或文件夹，请先移除一个。"
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "选择要固定的文件夹"
        panel.prompt = "添加文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.begin { [weak self] response in
            guard response == .OK, let self else { return }
            var updated = self.preferences
            var added = 0
            for url in panel.urls {
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
                let path = url.standardizedFileURL.path
                let name = path == "/" ? "/" : url.lastPathComponent
                if updated.pin(PinnedApplication(name: name, path: path, kind: .folder)) { added += 1 }
            }
            self.preferences = updated
            self.showToast(added > 0 ? "已固定 \(added) 个文件夹" : "没有添加新文件夹：文件夹已固定或已达到上限。")
        }
    }

    func remove(_ application: PinnedApplication) {
        preferences.remove(id: application.id)
    }

    /// 添加一个独立组件实例，允许不同城市或便签使用同一种组件样式。
    func addWidget(kind: DockWidgetKind) {
        guard kind.isAvailable else {
            showToast("该组件已停用，未添加。")
            return
        }
        preferences.customWidgets.append(DockWidgetConfiguration(kind: kind))
        showToast("已添加\(kind.title)")
    }

    /// 保存组件编辑结果，保留已有实例的顺序和唯一标识。
    func updateWidget(_ configuration: DockWidgetConfiguration) {
        guard let index = preferences.customWidgets.firstIndex(where: { $0.id == configuration.id }) else { return }
        var clean = configuration
        clean.normalize()
        preferences.customWidgets[index] = clean
    }

    /// 移除快捷组件，不影响日历、提醒事项或外部服务中的原始数据。
    func removeWidget(id: UUID) {
        if presentedWidgetID == id { presentedWidgetID = nil }
        preferences.customWidgets.removeAll { $0.id == id }
    }

    /// 记录今日喝水次数，并在新的一天自动从第一杯开始。
    func recordHydration(id: UUID) {
        guard var configuration = preferences.customWidgets.first(where: { $0.id == id }) else { return }
        let now = Date()
        configuration.hydrationCount = Calendar.current.isDate(configuration.hydrationDate, inSameDayAs: now)
            ? configuration.hydrationCount + 1 : 1
        configuration.hydrationDate = now
        updateWidget(configuration)
        widgets.resetTimer(configuration)
    }

    func toggleFocus() {
        let interactionTime = Date()
        now = interactionTime
        switch focus.state {
        case .idle, .completed: focus.start(minutes: preferences.focusMinutes, at: interactionTime)
        case .running: focus.pause(at: interactionTime)
        case .paused: focus.resume(at: interactionTime)
        }
    }

    func resetFocus() { focus.reset(minutes: preferences.focusMinutes) }

    func updateFocusDuration(_ minutes: Int) {
        preferences.focusMinutes = min(90, max(1, minutes))
        if case .idle = focus.state { focus.reset(minutes: preferences.focusMinutes) }
    }

    func restoreAppearance() {
        let clean = DockPreferences()
        preferences.iconSize = clean.iconSize
        preferences.iconScale = clean.iconScale
        preferences.verticalSpacing = clean.verticalSpacing
        preferences.cornerRadius = clean.cornerRadius
        preferences.magnification = clean.magnification
        preferences.accent = clean.accent
        showToast("已恢复默认外观，固定应用和小组件保持不变。")
    }

    func showToast(_ message: String) {
        toastTask?.cancel()
        toast = message
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    private func save() {
        do {
            defaults.set(try JSONEncoder().encode(preferences), forKey: Self.preferencesKey)
        } catch {
            errorMessage = "设置保存失败：\(error.localizedDescription)"
        }
    }

    private func refreshRunningApplications() {
        runningPaths = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.path })
    }

    private func refreshBattery() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for source in sources {
            guard let value = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  let current = value["Current Capacity"] as? Int,
                  let maximum = value["Max Capacity"] as? Int, maximum > 0 else { continue }
            batteryPercent = min(100, max(0, current * 100 / maximum))
            isCharging = (value["Is Charging"] as? Bool) ?? false
            return
        }
        batteryPercent = nil
        isCharging = false
    }

    private static func defaultApplications() -> [PinnedApplication] {
        ["com.apple.finder", "com.apple.Safari", "com.apple.mail", "com.apple.iCal", "com.apple.Notes", "com.apple.Music"].compactMap { id in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
            let bundle = Bundle(url: url)
            let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            return PinnedApplication(name: name, path: url.path)
        }
    }

    // MARK: - 首次启动引导

    /// 主窗口出现时调用；只在全新安装的首次启动自动弹出一次。
    func presentOnboardingIfNeeded() {
        guard shouldAutoPresentOnboarding else { return }
        shouldAutoPresentOnboarding = false
        isOnboardingPresented = true
    }

    /// 设置与菜单栏中的“重新打开引导”入口，不改变已记录的完成状态。
    func showOnboarding() {
        AppCoordinator.shared.showMainWindow()
        isOnboardingPresented = true
    }

    /// “完成”与“稍后再说”都记为已完成；直接关闭主窗口不记录，下次启动会再弹。
    func finishOnboarding() {
        defaults.set(OnboardingPolicy.currentVersion, forKey: OnboardingPolicy.completedVersionKey)
        isOnboardingPresented = false
    }
}
