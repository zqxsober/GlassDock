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
import Testing
@testable import GlassDock

@Suite("Native application", .serialized)
@MainActor
struct AppTests {
    private func isolatedDefaults() -> (String, UserDefaults) {
        let name = "GlassDockTests.\(UUID().uuidString)"
        return (name, UserDefaults(suiteName: name)!)
    }

    @Test func preferencesPersistAcrossStores() {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = AppStore(defaults: defaults)
        store.preferences.accent = .rose
        store.preferences.iconSize = 24
        store.preferences.iconScale = 0.5
        store.preferences.verticalSpacing = 0
        store.preferences.showClock = false
        store.preferences.showFocus = false
        store.preferences.showBattery = false
        store.preferences.showDockOnLaunch = false
        store.preferences.magnification = false
        store.updateFocusDuration(40)
        store.preferences.applications = []
        let loaded = AppStore(defaults: defaults)
        #expect(loaded.preferences == store.preferences)
        #expect(loaded.focusLabel == "40:00")
    }

    @Test func folderAndWidgetChoicesPersistAndRemovalKeepsOriginalFolderReference() {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = AppStore(defaults: defaults)
        let folder = PinnedApplication(name: "Projects", path: "/Users/example/Projects", kind: .folder)
        store.preferences.applications = [folder]
        store.preferences.cornerRadius = 12
        store.preferences.showClock = false
        store.addWidget(kind: .stickyNote)
        var note = store.preferences.customWidgets[0]
        note.text = "保留这条便签"
        store.updateWidget(note)
        let loaded = AppStore(defaults: defaults)
        #expect(loaded.preferences == store.preferences)
        #expect(loaded.preferences.customWidgets[0].text == "保留这条便签")
        loaded.removeWidget(id: note.id)
        #expect(loaded.preferences.applications == [folder])
        #expect(!loaded.preferences.showClock)
    }

    @Test func missingOrInvalidFolderReportsErrorWithoutOpeningIt() throws {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = AppStore(defaults: defaults)
        store.launch(PinnedApplication(name: "Missing folder", path: "/GlassDock-Definitely-Missing-Folder", kind: .folder))
        #expect(store.errorMessage?.contains("找不到文件夹") == true)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("GlassDock-folder-test-\(UUID().uuidString)")
        try Data("file".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        store.launch(PinnedApplication(name: "File", path: file.path, kind: .folder))
        #expect(store.errorMessage?.contains("已不再是文件夹") == true)
    }

    @Test func focusUsesInteractionTimeAndPreservesActiveDuration() {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = AppStore(defaults: defaults)
        store.now = Date(timeIntervalSince1970: 0)
        store.toggleFocus()
        #expect(store.focus.isRunning)
        #expect(store.now.timeIntervalSinceNow > -1)
        #expect(store.focus.remaining(at: Date()) > 1498)
        store.updateFocusDuration(10)
        #expect(store.focus.duration == 1500)
        store.toggleFocus()
        #expect(!store.focus.isRunning)
        store.toggleFocus()
        #expect(store.focus.isRunning)
        store.resetFocus()
        #expect(store.focus.state == .idle)
        #expect(store.focusLabel == "10:00")
    }

    @Test func restoreAppearancePreservesPinnedAppsAndWidgetChoices() {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = AppStore(defaults: defaults)
        let applications = store.preferences.applications
        store.preferences.accent = .ocean
        store.preferences.iconSize = 64
        store.preferences.iconScale = 0.5
        store.preferences.verticalSpacing = 24
        store.preferences.magnification = false
        store.preferences.showClock = false
        store.restoreAppearance()
        #expect(store.preferences.accent == .mint)
        #expect(store.preferences.iconSize == 48)
        #expect(store.preferences.iconScale == 1)
        #expect(store.preferences.verticalSpacing == 8)
        #expect(store.preferences.magnification)
        #expect(!store.preferences.showClock)
        #expect(store.preferences.applications == applications)
    }

    @Test func missingAppReportsActionableError() {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = AppStore(defaults: defaults)
        store.launch(PinnedApplication(name: "Missing", path: "/Applications/GlassDock-Definitely-Not-Installed.app"))
        #expect(store.errorMessage?.contains("Missing") == true)
        #expect(store.errorMessage?.contains("重新添加") == true)
    }

    @Test func floatingDockSupportsKeyboardActivationAndRetainsResponderWhenResized() throws {
        _ = NSApplication.shared
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = AppStore(defaults: defaults)
        store.preferences.applications = [
            PinnedApplication(name: "Keyboard Test", path: "/Applications/GlassDock-Keyboard-Test-Missing.app"),
            PinnedApplication(name: "Next App", path: "/Applications/GlassDock-Next-Test-Missing.app")
        ]
        store.preferences.showClock = false
        store.preferences.showFocus = false
        store.preferences.showBattery = false
        let controller = DockPanelController(store: store)
        controller.focusDock()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let panel = try #require(NSApp.windows.compactMap { $0 as? FloatingDockPanel }.first)
        defer {
            panel.orderOut(nil)
            panel.close()
            withExtendedLifetime(controller) {}
        }
        #expect(store.isDockVisible)
        #expect(panel.canBecomeKey && !panel.canBecomeMain)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        let contentView = try #require(panel.contentView)
        let firstResponder = try #require(panel.firstResponder)
        #expect(firstResponder !== panel)
        let originalSize = panel.frame.size
        store.preferences.iconScale = 0.5
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        #expect(panel.frame.size == originalSize)
        #expect(panel.firstResponder === firstResponder)
        store.preferences.iconSize = 24
        store.preferences.verticalSpacing = 0
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        #expect(panel.contentView === contentView)
        #expect(panel.firstResponder === firstResponder)
        #expect(panel.frame.height < originalSize.height)
        let screen = try #require(panel.screen)
        #expect(panel.frame.minY == screen.frame.minY)
        #expect(abs(panel.frame.height - contentView.fittingSize.height) < 1)
        let space = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel.windowNumber, context: nil, characters: " ", charactersIgnoringModifiers: " ",
            isARepeat: false, keyCode: 49
        ))
        panel.sendEvent(space)
        #expect(store.errorMessage?.contains("Keyboard Test") == true)
        var forwardedActions = 0
        let observation = NotificationCenter.default.addObserver(forName: .dockKeyboardAction, object: nil, queue: nil) { _ in
            forwardedActions += 1
        }
        store.isWidgetEditorPresented = true
        #expect(!panel.acceptsDockKeyboardNavigation)
        panel.sendEvent(space)
        #expect(forwardedActions == 0)
        store.isWidgetEditorPresented = false
        #expect(panel.acceptsDockKeyboardNavigation)
        NotificationCenter.default.removeObserver(observation)
        let tab = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel.windowNumber, context: nil, characters: "\t", charactersIgnoringModifiers: "\t",
            isARepeat: false, keyCode: 48
        ))
        panel.sendEvent(tab)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        panel.sendEvent(space)
        #expect(store.errorMessage?.contains("Next App") == true)
        let reverseTab = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.shift], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel.windowNumber, context: nil, characters: "\t", charactersIgnoringModifiers: "\t",
            isARepeat: false, keyCode: 48
        ))
        panel.sendEvent(reverseTab)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        panel.sendEvent(space)
        #expect(store.errorMessage?.contains("Keyboard Test") == true)
    }

    @Test func inactiveHoverTrackingUsesBoundedActiveAlwaysAreaWithoutTakingFocus() throws {
        _ = NSApplication.shared
        let view = ActiveHoverTrackingNSView(frame: NSRect(x: 0, y: 0, width: 72, height: 64))
        view.updateTrackingAreas()
        let trackingArea = try #require(view.trackingAreas.first { $0.options.contains(.activeAlways) })
        #expect(trackingArea.options.contains(.mouseEnteredAndExited))
        #expect(trackingArea.options.contains(.mouseMoved))
        #expect(!trackingArea.options.contains(.inVisibleRect))
        #expect(trackingArea.rect == view.bounds.intersection(view.visibleRect))
        #expect(!view.acceptsFirstResponder)
        #expect(view.hitTest(NSPoint(x: 20, y: 20)) == nil)
    }

    @Test func detachedHoverTrackingResetsAndIgnoresStaleQueuedSync() throws {
        _ = NSApplication.shared
        let tracker = ActiveHoverTrackingNSView(frame: NSRect(x: 0, y: 0, width: 64, height: 64))
        var hoverChanges: [Bool] = []
        tracker.onHoverChanged = { hoverChanges.append($0) }
        tracker.scheduleHoverSynchronization()
        tracker.setHovered(true)
        #expect(tracker.isHovered)
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        #expect(tracker.isHovered)

        tracker.synchronizeHoverState()
        #expect(!tracker.isHovered)
        #expect(hoverChanges == [true, false])
    }

    @Test func namedWindowIconUsesSharedMagnificationRulesWithoutChangingItsFrame() {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = AppStore(defaults: defaults)
        let application = PinnedApplication(name: "Notes", path: "/Applications/GlassDock-Notes-Test.app")
        let window = DockWindowSnapshot(
            id: 42,
            processID: 84,
            application: application,
            title: "Project Notes",
            bounds: CGRect(x: 0, y: 0, width: 500, height: 400)
        )
        let entry = DockApplicationEntry(application: application, window: window, showsWindowTitle: true)
        let idleIcon = NSHostingView(rootView: DockIconImage(
            application: entry.application, size: 48, iconScale: 1, hovered: false
        ).environmentObject(store))
        let hoveredIcon = NSHostingView(rootView: DockIconImage(
            application: entry.application, size: 48, iconScale: 1, hovered: true
        ).environmentObject(store))

        #expect(entry.showsWindowTitle)
        #expect(DockIconImage.magnificationScale(hovered: true, enabled: true, reduceMotion: false) == 1.15)
        #expect(DockIconImage.magnificationScale(hovered: true, enabled: false, reduceMotion: false) == 1)
        #expect(DockIconImage.magnificationScale(hovered: true, enabled: true, reduceMotion: true) == 1)
        #expect(idleIcon.fittingSize == hoveredIcon.fittingSize)
    }

    @Test func pinnedAndWindowIconsShareTheSameVerticalSlotAtEveryDockSize() {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = AppStore(defaults: defaults)
        let application = PinnedApplication(name: "Notes", path: "/Applications/GlassDock-Notes-Test.app")

        for size in [CGFloat(10), 24, 48, 64, 96] {
            let plain = NSHostingView(rootView: DockApplicationIconLayout(
                application: application,
                size: size,
                iconScale: 1,
                hovered: false,
                title: nil,
                slotWidth: size + 12,
                statusColor: .clear
            ).environmentObject(store))
            let titled = NSHostingView(rootView: DockApplicationIconLayout(
                application: application,
                size: size,
                iconScale: 1,
                hovered: false,
                title: "窗口名称",
                slotWidth: size + 30 + DockApplicationButton.measuredTitleWidth(for: "窗口名称"),
                statusColor: store.accent
            ).environmentObject(store))

            #expect(abs(plain.fittingSize.height - (size + 21)) < 0.01)
            #expect(abs(titled.fittingSize.height - plain.fittingSize.height) < 0.01)
        }
    }

    @Test func windowTitlesUseEightCharactersAndMeasureCJKAndEmojiText() {
        #expect(DockApplicationButton.displayTitle(for: "12345678") == "12345678")
        #expect(DockApplicationButton.displayTitle(for: "123456789") == "12345678...")

        let familyEmojiTitle = "ABCD👨‍👩‍👧‍👦EFGH"
        #expect(familyEmojiTitle.count == 9)
        #expect(DockApplicationButton.displayTitle(for: familyEmojiTitle) == "ABCD👨‍👩‍👧‍👦EFG...")
        let emojiTitle = String(repeating: "😀", count: 12)
        let visibleEmojiTitle = DockApplicationButton.displayTitle(for: emojiTitle)
        #expect(visibleEmojiTitle == String(repeating: "😀", count: 8) + "...")
        #expect(DockApplicationButton.measuredTitleWidth(for: visibleEmojiTitle) > 64)

        let application = PinnedApplication(name: "Notes", path: "/Applications/GlassDock-Notes-Test.app")
        let fullTitle = "窗口标题测试很长尾新建窗口名称超过八个可见字符"
        let window = DockWindowSnapshot(
            id: 43,
            processID: 84,
            application: application,
            title: fullTitle,
            bounds: CGRect(x: 0, y: 0, width: 500, height: 400)
        )
        let entry = DockApplicationEntry(application: application, window: window, showsWindowTitle: true)
        let visibleTitle = DockApplicationButton.displayTitle(for: fullTitle)
        let measuredVisibleWidth = DockApplicationButton.measuredTitleWidth(for: visibleTitle)
        let measuredFullWidth = DockApplicationButton.measuredTitleWidth(for: fullTitle)

        #expect(visibleTitle == "窗口标题测试很长...")
        #expect(measuredVisibleWidth > CGFloat(visibleTitle.count * 7))
        #expect(measuredVisibleWidth < measuredFullWidth)
        for size in [CGFloat(10), 24, 48, 64, 96] {
            #expect(DockApplicationButton.width(for: entry, iconSize: size) == size + 36 + measuredVisibleWidth)
        }
        let emojiWindow = DockWindowSnapshot(
            id: 44,
            processID: 84,
            application: application,
            title: emojiTitle,
            bounds: CGRect(x: 0, y: 0, width: 500, height: 400)
        )
        let emojiEntry = DockApplicationEntry(application: application, window: emojiWindow, showsWindowTitle: true)
        let emojiWidth = DockApplicationButton.measuredTitleWidth(for: visibleEmojiTitle)
        #expect(DockApplicationButton.width(for: emojiEntry, iconSize: 10) == 46 + emojiWidth)
    }

    private enum TestAppearance: String, CaseIterable {
        case light, dark

        var colorScheme: ColorScheme { self == .light ? .light : .dark }
        var appKitName: NSAppearance.Name { self == .light ? .aqua : .darkAqua }
    }

    private func pagePreview(_ page: DashboardPage) -> (content: AnyView, filename: String) {
        switch page {
        case .overview: (AnyView(OverviewPage()), "overview")
        case .dock: (AnyView(DockPage()), "dock")
        case .widgets: (AnyView(WidgetsPage()), "widgets")
        case .preferences: (AnyView(PreferencesPage()), "preferences")
        }
    }

    private func expectSaneSize(_ size: NSSize, context: String) {
        #expect(size.width.isFinite && size.width > 0, "\(context): width")
        #expect(size.height.isFinite && size.height > 0, "\(context): height")
    }

    private func checkHostedLayout<Content: View>(
        _ content: Content,
        appearance: TestAppearance,
        size: NSSize = NSSize(width: 1120, height: 820),
        context: String
    ) throws {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: 80, y: 100), size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer {
            window.orderOut(nil)
            window.contentViewController = nil
            window.close()
        }
        window.title = "GlassDock layout test"
        window.appearance = NSAppearance(named: appearance.appKitName)
        let controller = NSHostingController(rootView: content.environment(\.colorScheme, appearance.colorScheme))
        window.contentViewController = controller
        let view = controller.view
        view.frame = NSRect(origin: .zero, size: size)
        window.setContentSize(size)
        window.orderFront(nil)
        // Allow native toolbar installation and deferred window setup before measuring.
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        window.setContentSize(size)
        view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        #expect(window.styleMask.contains(.titled), "\(context)")
        #expect(window.isVisible && view.window === window, "\(context)")
        #expect(view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == appearance.appKitName, "\(context)")
        let fitting = view.fittingSize
        expectSaneSize(fitting, context: "\(context) fitting")
        expectSaneSize(view.bounds.size, context: "\(context) bounds")
        #expect(fitting.width <= size.width + 10, "\(context): fitting width exceeds available width")
        #expect(fitting.height <= size.height + 10, "\(context): fitting height exceeds available height")
        #expect(view.bounds.width <= size.width + 1, "\(context): laid-out width")
        #expect(view.bounds.height <= size.height + 1, "\(context): laid-out height")
    }

    @Test func dashboardPagesHaveSaneNativeLayoutInBothAppearances() throws {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = AppStore(defaults: defaults)
        for appearance in TestAppearance.allCases {
            for page in DashboardPage.allCases {
                store.page = page
                try checkHostedLayout(
                    DashboardView().environmentObject(store),
                    appearance: appearance,
                    context: "\(page) / \(appearance.rawValue)"
                )
            }
        }
    }

    @Test func exportPageOnlyPreviewsInBothAppearances() throws {
        _ = NSApplication.shared
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = AppStore(defaults: defaults)
        let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/previews")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for appearance in TestAppearance.allCases {
            let appKitAppearance = try #require(NSAppearance(named: appearance.appKitName))
            for page in DashboardPage.allCases {
                store.page = page
                let preview = pagePreview(page)
                var renderedImage: NSImage?
                appKitAppearance.performAsCurrentDrawingAppearance {
                    // ImageRenderer does not capture AppKit-backed ScrollView content or the live glass backdrop.
                    let renderer = ImageRenderer(content: preview.content.environmentObject(store)
                        .foregroundStyle(.primary)
                        .frame(width: 825).fixedSize(horizontal: false, vertical: true)
                        .padding(28).background(Color.canvas)
                        .environment(\.colorScheme, appearance.colorScheme))
                    renderer.scale = 2
                    renderedImage = renderer.nsImage
                }
                let image = try #require(renderedImage)
                expectSaneSize(image.size, context: "\(preview.filename)-\(appearance.rawValue) preview")
                let tiff = try #require(image.tiffRepresentation)
                let bitmap = try #require(NSBitmapImageRep(data: tiff))
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                #expect(png.count > 10_000)
                try png.write(to: output.appendingPathComponent("\(preview.filename)-\(appearance.rawValue).png"))
            }
        }
    }

    @Test func dockEdgeCasesHaveBoundedNativeLayoutInBothAppearances() throws {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = AppStore(defaults: defaults)
        for appearance in TestAppearance.allCases {
            for count in [0, 12] {
                for iconSize in [10.0, 24.0, 48.0, 96.0] {
                    for widgetsEnabled in [true, false] {
                        for maxWidth in [CGFloat(700), CGFloat(900)] {
                            for preview in [false, true] {
                                // Reset every preference for every case, including the next application count.
                                store.preferences.applications = (0..<count).map {
                                    PinnedApplication(name: "App \($0)", path: "/Applications/Test\($0).app")
                                }
                                store.preferences.iconSize = iconSize
                                store.preferences.showClock = widgetsEnabled
                                store.preferences.showFocus = widgetsEnabled
                                store.preferences.showBattery = widgetsEnabled
                                #expect(store.enabledWidgetCount == (widgetsEnabled ? 3 : 0))
                                try checkHostedLayout(
                                    DockStrip(preview: preview, maxWidth: maxWidth).environmentObject(store),
                                    appearance: appearance,
                                    size: NSSize(width: maxWidth, height: 180),
                                    context: "Dock \(count) apps / \(iconSize)px / widgets \(widgetsEnabled) / width \(maxWidth) / preview \(preview) / \(appearance.rawValue)"
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func dockSizeScalesBothAxesWithWidgetsAndWithoutPreviewPlateau() throws {
        _ = NSApplication.shared
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = AppStore(defaults: defaults)
        store.preferences.applications = [PinnedApplication(name: "Folder", path: "/tmp", kind: .folder)]
        store.preferences.customWidgets = [.init(kind: .musicFull)]
        for preview in [false, true] {
            store.preferences.iconSize = 48
            let baseline = NSHostingView(rootView: DockStrip(preview: preview, maxWidth: 2000).environmentObject(store)).fittingSize
            for size in [10.0, 22, 24, 64, 96] {
                store.preferences.iconSize = size
                let fitting = NSHostingView(rootView: DockStrip(preview: preview, maxWidth: 2000).environmentObject(store)).fittingSize
                // NSHostingView 将 fittingSize 向上取整到点，允许不到 1pt 的舍入差。
                #expect(abs(fitting.width - baseline.width * size / 48) < 1)
                #expect(abs(fitting.height - baseline.height * size / 48) < 1)
            }
        }
    }

    @Test func floatingDockHeightTracksSmallSizesWithMusicWidgets() throws {
        _ = NSApplication.shared
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = AppStore(defaults: defaults)
        store.preferences.applications = [PinnedApplication(name: "Folder", path: "/tmp", kind: .folder)]
        store.preferences.customWidgets = [.init(kind: .musicFull)]
        let controller = DockPanelController(store: store)
        controller.focusDock()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let panel = try #require(NSApp.windows.compactMap { $0 as? FloatingDockPanel }.first)
        defer {
            panel.orderOut(nil)
            panel.close()
            withExtendedLifetime(controller) {}
        }
        for size in [10.0, 22, 24, 48, 96] {
            store.preferences.iconSize = size
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            #expect(abs(panel.frame.height - (80 * size / 48 + 12)) < 1)
        }
    }

    @Test func independentIconScaleKeepsDockSizeAndMusicFitsPreview() throws {
        _ = NSApplication.shared
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = AppStore(defaults: defaults)
        store.preferences.applications = [PinnedApplication(name: "Folder", path: "/tmp", kind: .folder)]
        store.preferences.customWidgets = [.init(kind: .musicFull), .init(kind: .musicMini)]
        for preview in [true, false] {
            for iconSize in [10.0, 24.0, 48.0, 64.0, 96.0] {
                var baseline: NSSize?
                for spacing in [0.0, 24.0] {
                    store.preferences.iconSize = iconSize
                    store.preferences.verticalSpacing = spacing
                    store.preferences.iconScale = 1
                    let original = NSHostingView(rootView: DockStrip(preview: preview, maxWidth: 652).environmentObject(store)).fittingSize
                    // 整体尺寸随 Dock 尺寸变化，独立图标比例与旧间距字段不影响外框。
                    #expect(abs(original.height - 80 * iconSize / 48) < 1)
                    if let baseline {
                        #expect(original == baseline)
                    } else {
                        baseline = original
                    }
                    for scale in [0.5, 0.75, 1.25] {
                        store.preferences.iconScale = scale
                        let scaled = NSHostingView(rootView: DockStrip(preview: preview, maxWidth: 652).environmentObject(store)).fittingSize
                        #expect(scaled == original)
                    }
                }
            }
        }
    }

    @Test func legacySpacingDoesNotAffectDockLayoutAndKeepsEdgeLayoutsValid() throws {
        _ = NSApplication.shared
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = AppStore(defaults: defaults)
        for appearance in TestAppearance.allCases {
            for count in [0, 12] {
                for iconSize in [10.0, 24.0, 48.0, 64.0, 96.0] {
                    store.preferences.applications = (0..<count).map {
                        PinnedApplication(name: "App \($0)", path: "/Applications/SpacingTest\($0).app")
                    }
                    store.preferences.iconSize = iconSize
                    store.preferences.showClock = count > 0
                    store.preferences.showFocus = count > 0
                    store.preferences.showBattery = count > 0
                    var baseline: NSSize?
                    for spacing in [0.0, 8.0, 24.0] {
                        store.preferences.verticalSpacing = spacing
                        let fittingSize = NSHostingView(rootView: DockStrip(maxWidth: 700).environmentObject(store)).fittingSize
                        if let baseline {
                            #expect(fittingSize == baseline)
                        } else {
                            baseline = fittingSize
                        }
                        try checkHostedLayout(
                            DockStrip(maxWidth: 700).environmentObject(store), appearance: appearance,
                            size: NSSize(width: 700, height: 180),
                            context: "Spacing \(spacing) / \(count) apps / \(iconSize)px / \(appearance.rawValue)"
                        )
                    }
                }
            }
        }
    }

    @Test func everyWidgetFaceHasSaneLayoutInBothAppearances() throws {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = AppStore(defaults: defaults)
        for appearance in TestAppearance.allCases {
            for kind in DockWidgetKind.availableKinds {
                let configuration = DockWidgetConfiguration(kind: kind)
                let width = kind == .musicFull ? 280 : 240
                try checkHostedLayout(
                    WidgetFace(configuration: configuration, runtime: store.widgets, batteryPercent: nil, batterySymbol: "bolt.fill").environmentObject(store),
                    appearance: appearance, size: NSSize(width: width, height: 100),
                    context: "Widget \(kind.rawValue) / \(appearance.rawValue)"
                )
            }
        }
    }

    @Test func manyWidgetsStayInsideNarrowDockAndPickerHasSaneLayout() throws {
        _ = NSApplication.shared
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = AppStore(defaults: defaults)
        store.preferences.customWidgets = DockWidgetKind.availableKinds.map { DockWidgetConfiguration(kind: $0) }
        for appearance in TestAppearance.allCases {
            for preview in [false, true] {
                let root = DockStrip(preview: preview, maxWidth: 700).environmentObject(store)
                let fitting = NSHostingView(rootView: root).fittingSize
                #expect(fitting.width <= 700.5)
                try checkHostedLayout(root, appearance: appearance, size: NSSize(width: 700, height: 160), context: "All widgets / preview \(preview)")
            }
            try checkHostedLayout(WidgetPicker().environmentObject(store), appearance: appearance,
                                  size: NSSize(width: 940, height: 720), context: "Widget picker / \(appearance.rawValue)")
        }
    }

    // Only inject accessibility values when the SDK exposes writable public keys.
    @Test(.enabled(
        if: (\EnvironmentValues.accessibilityReduceTransparency) is WritableKeyPath<EnvironmentValues, Bool>,
        "accessibilityReduceTransparency requires a publicly writable environment key"
    ))
    func reducedTransparencyHasSaneNativeLayout() throws {
        try checkAccessibilityLayout(keyPath: \.accessibilityReduceTransparency, value: true)
    }

    @Test(.enabled(
        if: (\EnvironmentValues.accessibilityReduceMotion) is WritableKeyPath<EnvironmentValues, Bool>,
        "accessibilityReduceMotion requires a publicly writable environment key"
    ))
    func reducedMotionHasSaneNativeLayout() throws {
        try checkAccessibilityLayout(keyPath: \.accessibilityReduceMotion, value: true)
    }

    @Test(.enabled(
        if: (\EnvironmentValues.colorSchemeContrast) is WritableKeyPath<EnvironmentValues, ColorSchemeContrast>,
        "colorSchemeContrast requires a publicly writable environment key"
    ))
    func increasedContrastHasSaneNativeLayout() throws {
        try checkAccessibilityLayout(keyPath: \.colorSchemeContrast, value: ColorSchemeContrast.increased)
    }

    private func checkAccessibilityLayout<Value>(keyPath: KeyPath<EnvironmentValues, Value>, value: Value) throws {
        let writableKeyPath = try #require(keyPath as? WritableKeyPath<EnvironmentValues, Value>)
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = AppStore(defaults: defaults)
        for appearance in TestAppearance.allCases {
            for page in DashboardPage.allCases {
                store.page = page
                try checkHostedLayout(
                    DashboardView().environmentObject(store).environment(writableKeyPath, value),
                    appearance: appearance,
                    context: "Accessibility \(keyPath) / \(page) / \(appearance.rawValue)"
                )
            }
            try checkHostedLayout(
                DockStrip(preview: false, maxWidth: 700).environmentObject(store).environment(writableKeyPath, value),
                appearance: appearance,
                size: NSSize(width: 700, height: 180),
                context: "Accessibility \(keyPath) / Dock / \(appearance.rawValue)"
            )
        }
    }

    private func resolve(_ color: Color, appearance: TestAppearance) throws -> Color.Resolved {
        _ = NSApplication.shared
        var environment = EnvironmentValues()
        environment.colorScheme = appearance.colorScheme
        let appKitAppearance = try #require(NSAppearance(named: appearance.appKitName))
        var resolved: Color.Resolved?
        appKitAppearance.performAsCurrentDrawingAppearance {
            resolved = color.resolve(in: environment)
        }
        return try #require(resolved)
    }

    @Test func semanticColorsResolveDifferentlyInLightAndDark() throws {
        for (name, color) in [("canvas", Color.canvas), ("muted", Color.muted)] {
            let light = try resolve(color, appearance: .light)
            let dark = try resolve(color, appearance: .dark)
            for resolved in [light, dark] {
                #expect([resolved.linearRed, resolved.linearGreen, resolved.linearBlue, resolved.opacity].allSatisfy { $0.isFinite }, "\(name)")
            }
            #expect(light != dark, "Color.\(name) should adapt to the appearance")
        }
    }
}
