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
import SwiftUI

/// 非激活悬浮栏传递给 SwiftUI 的键盘操作。
enum DockKeyboardAction {
    case first, next, previous, activate
}

extension Notification.Name {
    static let dockKeyboardAction = Notification.Name("GlassDock.keyboardAction")
}

final class FloatingDockPanel: NSPanel {
    var acceptsDockKeyboardNavigation = true
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// 按 Escape 释放悬浮栏的键盘焦点。
    override func cancelOperation(_ sender: Any?) { resignKey() }

    /// 将悬浮栏导航键交给 SwiftUI，避免系统键盘导航设置跳过普通按钮。
    override func sendEvent(_ event: NSEvent) {
        guard acceptsDockKeyboardNavigation, event.type == .keyDown,
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            super.sendEvent(event)
            return
        }
        let action: DockKeyboardAction
        switch event.keyCode {
        case 48: action = event.modifierFlags.contains(.shift) ? .previous : .next
        case 36, 49, 76:
            guard !event.isARepeat else { return }
            action = .activate
        case 53:
            resignKey()
            return
        default:
            super.sendEvent(event)
            return
        }
        NotificationCenter.default.post(name: .dockKeyboardAction, object: action)
    }
}

final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
}

struct ActiveHoverTrackingView: NSViewRepresentable {
    @Binding var isHovered: Bool

    func makeNSView(context: Context) -> ActiveHoverTrackingNSView {
        let view = ActiveHoverTrackingNSView(frame: .zero)
        view.onHoverChanged = { [binding = $isHovered] hovered in
            if binding.wrappedValue != hovered { binding.wrappedValue = hovered }
        }
        return view
    }

    func updateNSView(_ nsView: ActiveHoverTrackingNSView, context: Context) {
        nsView.onHoverChanged = { [binding = $isHovered] hovered in
            if binding.wrappedValue != hovered { binding.wrappedValue = hovered }
        }
        nsView.scheduleHoverSynchronization()
    }
}

struct DockContextMenuBridge: NSViewRepresentable {
    var items: [(title: String, action: () -> Void)]
    var dockScale: CGFloat = 1

    func makeNSView(context: Context) -> DockContextMenuNSView {
        let view = DockContextMenuNSView(frame: .zero)
        view.items = items
        view.dockScale = dockScale
        return view
    }

    func updateNSView(_ nsView: DockContextMenuNSView, context: Context) {
        nsView.items = items
        nsView.dockScale = dockScale
    }

    static func dismantleNSView(_ nsView: DockContextMenuNSView, coordinator: ()) {
        nsView.stopMonitoring()
    }
}

final class DockContextMenuNSView: NSView {
    var items: [(title: String, action: () -> Void)] = []
    var dockScale: CGFloat = 1
    private var eventMonitor: Any?
    var isMonitoring: Bool { eventMonitor != nil }

    /// 跟随 Dock 的实际比例，保留小尺寸可读性和大尺寸菜单的合理高度。
    static func menuFontSize(dockScale: CGFloat) -> CGFloat {
        min(28, max(10, 14 * dockScale))
    }

    override var acceptsFirstResponder: Bool { false }

    // SwiftUI 负责按钮命中；透明桥接不依赖 NSHostingView 是否向子视图派发右键。
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            guard let self, self.matchesMenuEvent(event) else { return event }
            self.presentMenu()
            return nil
        }
    }

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }

    func stopMonitoring() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }

    /// 仅接管本窗口中可见入口上的右键按下或 Control-click，普通点击原样传递。
    func matchesMenuEvent(_ event: NSEvent) -> Bool {
        guard handlesMenuEvent(event), !items.isEmpty, let window,
              event.window === window, window.isVisible,
              !isHiddenOrHasHiddenAncestor, !visibleRect.isEmpty else { return false }
        return bounds.intersection(visibleRect).contains(convert(event.locationInWindow, from: nil))
    }

    func handlesMenuEvent(_ event: NSEvent) -> Bool {
        switch event.type {
        case .rightMouseDown:
            return true
        case .leftMouseDown:
            return event.modifierFlags.contains(.control)
        default:
            return false
        }
    }

    private func presentMenu() {
        let menuItems = items
        guard !menuItems.isEmpty, let window, let screen = window.screen ?? NSScreen.main else { return }
        let menu = Self.makeMenu(items: menuItems, dockScale: dockScale)

        let entryFrame = window.convertToScreen(convert(bounds, to: nil))
        let point = DockContextMenuPlacement.topLeft(
            entryFrame: entryFrame,
            menuSize: menu.size,
            visibleFrame: screen.visibleFrame,
            gap: max(3, 6 * dockScale)
        )
        menu.popUp(positioning: nil, at: point, in: nil)
    }

    static func makeMenu(items: [(title: String, action: () -> Void)], dockScale: CGFloat) -> NSMenu {
        let menu = NSMenu()
        menu.font = NSFont.systemFont(ofSize: Self.menuFontSize(dockScale: dockScale))
        let targets = items.map { DockContextMenuActionTarget(action: $0.action) }
        for (index, entry) in items.enumerated() {
            let item = NSMenuItem(title: entry.title, action: nil, keyEquivalent: "")
            item.action = #selector(DockContextMenuActionTarget.invokeMenuAction(_:))
            item.target = targets[index]
            // target 是弱引用，菜单持有动作快照直到 AppKit 完成选项派发。
            item.representedObject = targets[index]
            menu.addItem(item)
        }
        menu.update()
        return menu
    }
}

final class DockContextMenuActionTarget: NSObject {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc func invokeMenuAction(_ sender: NSMenuItem) {
        action()
    }
}

enum DockContextMenuPlacement {
    static func topLeft(
        entryFrame: NSRect,
        menuSize: NSSize,
        visibleFrame: NSRect,
        gap: CGFloat = 6
    ) -> NSPoint {
        let minimumX = visibleFrame.minX
        let maximumX = max(minimumX, visibleFrame.maxX - menuSize.width)
        let maximumY = visibleFrame.maxY
        let minimumY = min(maximumY, visibleFrame.minY + menuSize.height)
        return NSPoint(
            x: min(max(entryFrame.minX, minimumX), maximumX),
            y: min(max(entryFrame.maxY + menuSize.height + gap, minimumY), maximumY)
        )
    }
}

final class ActiveHoverTrackingNSView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?
    private(set) var isHovered = false

    override var acceptsFirstResponder: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let visibleBounds = bounds.intersection(visibleRect)
        let trackingArea = NSTrackingArea(
            rect: visibleBounds.isEmpty ? .zero : visibleBounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
        scheduleHoverSynchronization()
    }

    override func mouseEntered(with event: NSEvent) { synchronizeHoverState(at: event.locationInWindow) }
    override func mouseMoved(with event: NSEvent) { synchronizeHoverState(at: event.locationInWindow) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { setHovered(false) }
        scheduleHoverSynchronization()
    }

    override func viewDidHide() {
        super.viewDidHide()
        scheduleHoverSynchronization()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        scheduleHoverSynchronization()
    }

    func scheduleHoverSynchronization() {
        let expectedHover = isHovered
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isHovered == expectedHover else { return }
            self.synchronizeHoverState()
            self.onHoverChanged?(self.isHovered)
        }
    }

    func synchronizeHoverState() {
        guard let window, window.isVisible, !isHiddenOrHasHiddenAncestor, !visibleRect.isEmpty else {
            setHovered(false)
            return
        }
        synchronizeHoverState(at: window.mouseLocationOutsideOfEventStream)
    }

    func synchronizeHoverState(at windowPoint: NSPoint) {
        guard let window, window.isVisible, !isHiddenOrHasHiddenAncestor, !visibleRect.isEmpty else {
            setHovered(false)
            return
        }
        setHovered(bounds.intersection(visibleRect).contains(convert(windowPoint, from: nil)))
    }

    func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        onHoverChanged?(hovered)
    }
}

@MainActor
final class AppCoordinator {
    static let shared = AppCoordinator()
    private var controller: DockPanelController?
    private var openMain: (() -> Void)?

    func start(store: AppStore, openMain: @escaping () -> Void) {
        self.openMain = openMain
        guard controller == nil else { return }
        controller = DockPanelController(store: store)
        store.isDockVisible = store.preferences.showDockOnLaunch
        store.updateChecker.start()
    }

    func showMainWindow() {
        openMain?()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.identifier?.rawValue == "glassdock-main" }?.makeKeyAndOrderFront(nil)
    }

    /// 显示悬浮 Dock，并将键盘焦点交给其中的控件。
    func focusDock() { controller?.focusDock() }
}

@MainActor
final class DockPanelController {
    private let store: AppStore
    private let panel: FloatingDockPanel
    private var hostingView: FirstClickHostingView<AnyView>?
    private var hostedMaxWidth: CGFloat?
    private var subscriptions = Set<AnyCancellable>()

    init(store: AppStore) {
        self.store = store
        panel = FloatingDockPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "GlassDock Floating Dock"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.autorecalculatesKeyViewLoop = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .utilityWindow
        panel.setAccessibilityLabel("GlassDock 悬浮 Dock")

        store.$isDockVisible.receive(on: RunLoop.main).sink { [weak self] visible in
            guard let self, visible == self.store.isDockVisible else { return }
            if visible {
                self.updateLayout()
                self.panel.orderFrontRegardless()
            } else {
                self.panel.orderOut(nil)
            }
        }.store(in: &subscriptions)
        store.$preferences.removeDuplicates().receive(on: RunLoop.main).sink { [weak self] _ in
            self?.updateLayout(refreshWindows: false)
        }.store(in: &subscriptions)
        store.$isWidgetEditorPresented.sink { [weak self] editing in
            self?.panel.acceptsDockKeyboardNavigation = !editing
        }.store(in: &subscriptions)
        store.windowTracker.$windows.removeDuplicates().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateLayout(refreshWindows: false) }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.updateLayout() }
            .store(in: &subscriptions)
    }

    /// 显示面板并选择首个键盘可访问控件，不激活主窗口。
    func focusDock() {
        store.isDockVisible = true
        updateLayout()
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(panel.contentView)
        panel.selectNextKeyView(nil)
        NotificationCenter.default.post(name: .dockKeyboardAction, object: DockKeyboardAction.first)
    }

    private func updateLayout(refreshWindows: Bool = true) {
        let existingScreen = hostingView == nil ? nil : panel.screen
        guard let screen = existingScreen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        if refreshWindows { store.refreshDockWindows(on: screen) }
        let available = screen.visibleFrame
        let content = DockStrip(maxWidth: available.width - 64)
            .environmentObject(store)
            .foregroundStyle(.primary)
            .padding([.top, .leading, .trailing], 12)
        let view: FirstClickHostingView<AnyView>
        if let hostingView {
            if hostedMaxWidth != available.width - 64 {
                hostingView.rootView = AnyView(content)
                hostedMaxWidth = available.width - 64
            }
            view = hostingView
        } else {
            view = FirstClickHostingView(rootView: AnyView(content))
            view.sizingOptions = [.intrinsicContentSize]
            hostingView = view
            hostedMaxWidth = available.width - 64
            panel.contentView = view
        }
        view.layoutSubtreeIfNeeded()
        let fitting = view.fittingSize
        let size = NSSize(width: min(available.width - 32, max(150, fitting.width)), height: fitting.height)
        let frame = NSRect(x: available.midX - size.width / 2, y: screen.frame.minY, width: size.width, height: size.height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }
}

struct WindowSetup: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.identifier = NSUserInterfaceItemIdentifier("glassdock-main")
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
