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

final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in AppCoordinator.shared.showMainWindow() }
        return true
    }
}

@main
struct GlassDockApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var delegate
    @StateObject private var store = AppStore()

    var body: some Scene {
        Window("GlassDock", id: "main") {
            MainWindowContent().environmentObject(store)
        }
        .defaultSize(width: 1120, height: 820)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button(L10n.text(zh: "检查更新…", en: "Check for Updates…")) {
                    AppCoordinator.shared.showMainWindow()
                    store.page = .preferences
                    store.updateChecker.checkNow()
                }
            }
            CommandGroup(after: .windowArrangement) {
                Button(store.isDockVisible ? "隐藏悬浮 Dock" : "显示悬浮 Dock") { store.isDockVisible.toggle() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Button("打开控制中心") { AppCoordinator.shared.showMainWindow() }
                Button("聚焦悬浮 Dock") { AppCoordinator.shared.focusDock() }
                    .keyboardShortcut("d", modifiers: [.command, .option, .shift])
            }
        }
        MenuBarExtra {
            if let release = store.updateChecker.pendingRelease {
                Button(L10n.text(zh: "有新版本 \(release.displayVersion)…", en: "Version \(release.displayVersion) Available…")) {
                    AppCoordinator.shared.showMainWindow()
                    store.updateChecker.showPendingRelease()
                }
                Divider()
            }
            Button("打开 GlassDock") { AppCoordinator.shared.showMainWindow() }
            Button(L10n.text(zh: "欢迎引导…", en: "Welcome Guide…")) { store.showOnboarding() }
            Divider()
            Toggle("显示悬浮 Dock", isOn: $store.isDockVisible)
            Button("聚焦悬浮 Dock") { AppCoordinator.shared.focusDock() }
            Button(store.focusButtonTitle + " · " + store.focusLabel) { store.toggleFocus() }
            Button("重置专注计时") { store.resetFocus() }
            Divider()
            Button("退出 GlassDock") { NSApp.terminate(nil) }.keyboardShortcut("q")
        } label: {
            Image(nsImage: MenuBarIcon.image(badged: store.updateChecker.pendingRelease != nil))
        }.menuBarExtraStyle(.menu)
    }
}

private struct MainWindowContent: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        DashboardView()
            .onAppear {
                AppCoordinator.shared.start(store: store) { openWindow(id: "main") }
                store.mainWindowDidAppear()
            }
    }
}
