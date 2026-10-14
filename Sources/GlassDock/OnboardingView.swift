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
import ApplicationServices
import Combine
import EventKit
import GlassDockCore
import SwiftUI

enum OnboardingPermission: String, CaseIterable, Identifiable {
    case accessibility, calendar, reminders, music
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .accessibility: "macwindow"
        case .calendar: "calendar"
        case .reminders: "checklist"
        case .music: "music.note"
        }
    }

    var title: String {
        switch self {
        case .accessibility: L10n.text(zh: "辅助功能", en: "Accessibility")
        case .calendar: L10n.text(zh: "日历", en: "Calendar")
        case .reminders: L10n.text(zh: "提醒事项", en: "Reminders")
        case .music: L10n.text(zh: "自动化（音乐）", en: "Automation (Music)")
        }
    }

    var detail: String {
        switch self {
        case .accessibility: L10n.text(zh: "读取窗口标题，切换和关闭指定窗口；无需屏幕录制。",
                                       en: "Read window titles, switch to and close specific windows. No screen recording needed.")
        case .calendar: L10n.text(zh: "在日历组件中显示下一个日程和今日议程。",
                                  en: "Show your next event and today's agenda in the Calendar widget.")
        case .reminders: L10n.text(zh: "在提醒事项组件中显示列表，并可标记完成。",
                                   en: "Show reminder lists and mark items complete.")
        case .music: L10n.text(zh: "读取 Apple Music 当前播放并响应播放控制。",
                               en: "Read Apple Music's now playing and control playback.")
        }
    }

    var settingsURL: URL? {
        let pane = switch self {
        case .accessibility: "Privacy_Accessibility"
        case .calendar: "Privacy_Calendars"
        case .reminders: "Privacy_Reminders"
        case .music: "Privacy_Automation"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
    }
}

/// 引导打开期间读取各项权限的实时状态。
@MainActor
final class OnboardingPermissionMonitor: ObservableObject {
    @Published private(set) var statuses: [OnboardingPermission: PermissionStatus] = [:]
    private let defaults: UserDefaults
    private var subscriptions = Set<AnyCancellable>()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        refresh()
    }

    func status(for permission: OnboardingPermission) -> PermissionStatus { statuses[permission] ?? .unavailable }

    /// 从系统设置返回时刷新；AX 授权不会通知前台 App，所以另外每 2 秒轮询。
    func start() {
        guard subscriptions.isEmpty else { return }
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        Timer.publish(every: 2, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        refresh()
    }

    func stop() { subscriptions.removeAll() }

    func markAccessibilityPrompted() {
        defaults.set(true, forKey: OnboardingPolicy.accessibilityPromptedKey)
    }

    func refresh() {
        let next: [OnboardingPermission: PermissionStatus] = [
            .accessibility: PermissionStatusMapping.accessibility(
                isTrusted: AXIsProcessTrusted(),
                hasPrompted: defaults.bool(forKey: OnboardingPolicy.accessibilityPromptedKey)
            ),
            .calendar: PermissionStatusMapping.eventKit(Self.eventKitAuthorization(for: .event)),
            .reminders: PermissionStatusMapping.eventKit(Self.eventKitAuthorization(for: .reminder)),
            .music: PermissionStatusMapping.appleEvents(MusicAppleScriptBridge.automationPermissionStatus(askUserIfNeeded: false))
        ]
        if next != statuses { statuses = next }
    }

    private static func eventKitAuthorization(for entityType: EKEntityType) -> EventKitAuthorization {
        switch EKEventStore.authorizationStatus(for: entityType) {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .fullAccess: .fullAccess
        case .writeOnly: .writeOnly
        @unknown default: .unknown
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var monitor = OnboardingPermissionMonitor()

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 24)).foregroundStyle(store.accent)
                    .frame(width: 56, height: 56)
                    .glassEffect(.regular, in: Circle())
                Text(L10n.text(zh: "欢迎使用 GlassDock", en: "Welcome to GlassDock"))
                    .font(.system(size: 20, weight: .semibold))
                Text(L10n.text(zh: "以下权限都是可选的。授权后解锁对应功能，随时可以在系统设置中更改。",
                               en: "All permissions are optional. Each unlocks a feature; you can change them anytime in System Settings."))
                    .font(.system(size: 12)).foregroundStyle(Color.muted).multilineTextAlignment(.center)
            }.padding(.horizontal, 28).padding(.top, 26).padding(.bottom, 18)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(OnboardingPermission.allCases) { permission in
                        PermissionRow(permission: permission, status: monitor.status(for: permission)) {
                            request(permission)
                        } openSettings: {
                            openSettings(for: permission)
                        }
                        Divider().opacity(0.3)
                    }
                    codexRow
                }.padding(.horizontal, 18).contentCard(radius: 20)
            }.padding(.horizontal, 24)
            HStack {
                Button(L10n.text(zh: "稍后再说", en: "Not Now")) { store.finishOnboarding() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.text(zh: "完成", en: "Done")) { store.finishOnboarding() }
                    .buttonStyle(.borderedProminent).tint(store.accent)
                    .keyboardShortcut(.defaultAction)
            }.padding(.horizontal, 24).padding(.vertical, 18)
        }
        .frame(width: 600, height: 520)
        .background(Color.canvas)
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }

    private var codexRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "gauge.with.dots.needle.33percent").font(.system(size: 17)).frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.text(zh: "Codex 额度（仅说明）", en: "Codex Usage (info only)")).font(.system(size: 13, weight: .medium))
                Text(L10n.text(zh: "需要先安装并登录 Codex CLI，GlassDock 不申请任何权限。",
                               en: "Requires Codex CLI installed and signed in. No permission is requested."))
                    .font(.system(size: 11)).foregroundStyle(Color.muted)
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private func request(_ permission: OnboardingPermission) {
        switch permission {
        case .accessibility:
            monitor.markAccessibilityPrompted()
            store.windowTracker.requestAccessibilityAccess()
        case .calendar:
            store.widgets.requestCalendarAccess()
        case .reminders:
            store.widgets.requestRemindersAccess()
        case .music:
            store.widgets.connectMusic()
        }
        monitor.refresh()
    }

    private func openSettings(for permission: OnboardingPermission) {
        guard let url = permission.settingsURL, NSWorkspace.shared.open(url) else {
            store.errorMessage = L10n.text(zh: "无法打开系统设置，请手动前往“隐私与安全性”。",
                                           en: "Couldn't open System Settings. Open Privacy & Security manually.")
            return
        }
    }
}

private struct PermissionRow: View {
    var permission: OnboardingPermission
    var status: PermissionStatus
    var request: () -> Void
    var openSettings: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: permission.symbol).font(.system(size: 17)).frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(permission.title).font(.system(size: 13, weight: .medium))
                Text(permission.detail).font(.system(size: 11)).foregroundStyle(Color.muted)
            }
            Spacer(minLength: 12)
            HStack(spacing: 5) {
                Circle().fill(statusColor).frame(width: 7, height: 7)
                Text(statusTitle).font(.system(size: 11)).foregroundStyle(Color.muted)
            }.fixedSize()
            action.fixedSize()
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(permission.title)，\(statusTitle)")
    }

    @ViewBuilder private var action: some View {
        switch status {
        case .granted:
            EmptyView()
        case .notGranted:
            Button(L10n.text(zh: "授权", en: "Allow"), action: request).controlSize(.small)
        case .denied:
            Button(L10n.text(zh: "打开系统设置", en: "Open System Settings"), action: openSettings).controlSize(.small)
        case .unavailable:
            // 音乐未运行时无法判断状态；connectMusic 会先打开“音乐”再申请。
            Button(L10n.text(zh: "授权", en: "Allow"), action: request).controlSize(.small)
        }
    }

    private var statusTitle: String {
        switch status {
        case .granted: L10n.text(zh: "已授权", en: "Granted")
        case .notGranted: L10n.text(zh: "未授权", en: "Not Granted")
        case .denied: L10n.text(zh: "被拒绝", en: "Denied")
        case .unavailable: permission == .music
            ? L10n.text(zh: "需先打开“音乐”", en: "Open Music first")
            : L10n.text(zh: "不可用", en: "Unavailable")
        }
    }

    private var statusColor: Color {
        switch status {
        case .granted: .green
        case .notGranted: .gray
        case .denied: .red
        case .unavailable: .orange
        }
    }
}
