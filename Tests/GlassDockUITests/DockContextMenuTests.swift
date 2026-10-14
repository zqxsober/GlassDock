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
import SwiftUI
import Testing
@testable import GlassDock

@Suite("Dock context menu", .serialized)
@MainActor
struct DockContextMenuTests {
    @Test func menuSizeFollowsDockScaleWithoutLosingReadableMinimum() {
        #expect(DockContextMenuNSView.menuFontSize(dockScale: 10.0 / 48) == 10)
        #expect(DockContextMenuNSView.menuFontSize(dockScale: 28.0 / 48) == 10)
        #expect(DockContextMenuNSView.menuFontSize(dockScale: 1) == 14)
        #expect(DockContextMenuNSView.menuFontSize(dockScale: 2) == 28)
        func measuredSize(_ scale: CGFloat) -> NSSize {
            let menu = NSMenu()
            menu.font = .systemFont(ofSize: DockContextMenuNSView.menuFontSize(dockScale: scale))
            for title in ["切换到此窗口", "关闭此窗口", "取消固定应用"] {
                menu.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: ""))
            }
            menu.update()
            return menu.size
        }
        let compact = measuredSize(28.0 / 48)
        let large = measuredSize(2)
        #expect(compact.width < large.width)
        #expect(compact.height < large.height)
    }

    @Test func threeRowMenuFitsAboveBottomDockEntry() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1200, height: 800)
        let entryFrame = NSRect(x: 300, y: 8, width: 40, height: 48)
        let menuSize = NSSize(width: 220, height: 132)

        let point = DockContextMenuPlacement.topLeft(
            entryFrame: entryFrame,
            menuSize: menuSize,
            visibleFrame: visibleFrame
        )

        #expect(point.x == entryFrame.minX)
        #expect(point.y == entryFrame.maxY + menuSize.height + 6)
        #expect(point.y - menuSize.height >= visibleFrame.minY)
        #expect(point.y <= visibleFrame.maxY)
    }

    @Test func placementClampsToNegativeOriginScreenRightEdge() {
        let visibleFrame = NSRect(x: -1280, y: 0, width: 1280, height: 800)
        let entryFrame = NSRect(x: -28, y: 100, width: 40, height: 40)
        let menuSize = NSSize(width: 220, height: 150)

        let point = DockContextMenuPlacement.topLeft(
            entryFrame: entryFrame,
            menuSize: menuSize,
            visibleFrame: visibleFrame
        )

        #expect(point.x == visibleFrame.maxX - menuSize.width)
        #expect(point.y - menuSize.height >= visibleFrame.minY)
        #expect(point.y <= visibleFrame.maxY)
    }

    @Test func onlyContextClickEventsHitTheBridge() {
        let view = DockContextMenuNSView(frame: .zero)

        #expect(!view.handlesMenuEvent(mouseEvent(type: .leftMouseDown)))
        #expect(view.handlesMenuEvent(mouseEvent(type: .leftMouseDown, modifiers: .control)))
        #expect(view.handlesMenuEvent(mouseEvent(type: .rightMouseDown)))
        #expect(!view.handlesMenuEvent(mouseEvent(type: .rightMouseUp)))
        #expect(!view.handlesMenuEvent(mouseEvent(type: .leftMouseUp, modifiers: .control)))
    }

    @Test func menuActionUsesTheActionCapturedWhenMenuWasBuilt() {
        var originalActionCount = 0
        var updatedActionCount = 0
        var currentItems: [(title: String, action: () -> Void)] = [
            ("Original", { originalActionCount += 1 })
        ]
        let menuItems = currentItems
        let target = DockContextMenuActionTarget(action: menuItems[0].action)

        currentItems = [("Updated", { updatedActionCount += 1 })]
        target.invokeMenuAction(NSMenuItem(title: "", action: nil, keyEquivalent: ""))

        #expect(originalActionCount == 1)
        #expect(updatedActionCount == 0)
    }

    @Test func appKitDispatchesActionAfterMenuCreationScopeEnds() throws {
        _ = NSApplication.shared
        var closedCount = 0
        let menu = DockContextMenuNSView.makeMenu(items: [("关闭此窗口", { closedCount += 1 })], dockScale: 1)
        let target = try #require(menu.items[0].target as? NSObject)
        let selector = try #require(menu.items[0].action)
        #expect(NSStringFromSelector(selector) == "invokeMenuAction:")
        try #require(target.responds(to: selector))
        menu.performActionForItem(at: 0)
        #expect(closedCount == 1)
    }

    @Test func menuRoutingUsesVisibleScaledCoordinatesAndOwnWindow() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 180),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 180))
        window.contentView = root
        let view = DockContextMenuNSView(frame: NSRect(x: 100, y: 20, width: 80, height: 40))
        view.bounds = NSRect(x: 0, y: 0, width: 160, height: 80)
        view.items = [("Test", {})]
        root.addSubview(view)
        window.orderFront(nil)
        #expect(view.isMonitoring)
        let point = NSPoint(x: 120, y: 40)
        #expect(view.matchesMenuEvent(mouseEvent(type: .rightMouseDown, location: point, windowNumber: window.windowNumber)))
        #expect(view.matchesMenuEvent(mouseEvent(type: .leftMouseDown, modifiers: .control, location: point, windowNumber: window.windowNumber)))
        #expect(!view.matchesMenuEvent(mouseEvent(type: .leftMouseDown, location: point, windowNumber: window.windowNumber)))
        #expect(!view.matchesMenuEvent(mouseEvent(type: .rightMouseDown, location: .zero, windowNumber: window.windowNumber)))
        #expect(!view.matchesMenuEvent(mouseEvent(type: .rightMouseDown, location: point)))
        view.isHidden = true
        #expect(!view.matchesMenuEvent(mouseEvent(type: .rightMouseDown, location: point, windowNumber: window.windowNumber)))
        view.isHidden = false
        window.orderOut(nil)
        #expect(!view.matchesMenuEvent(mouseEvent(type: .rightMouseDown, location: point, windowNumber: window.windowNumber)))
        view.removeFromSuperview()
        #expect(!view.isMonitoring)
    }

    @Test func swiftUIOverlayHasClickableBoundsAfterScaling() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 180),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: Button("Test") {}.frame(width: 144, height: 80)
            .overlay { DockContextMenuBridge(items: [("Test", {})]) }
            .scaleEffect(0.5).frame(width: 72, height: 40))
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        func findBridge(_ view: NSView) -> DockContextMenuNSView? {
            if let bridge = view as? DockContextMenuNSView { return bridge }
            return view.subviews.lazy.compactMap(findBridge).first
        }
        let bridge = try #require(findBridge(host))
        #expect(bridge.isMonitoring)
        #expect(bridge.bounds.width > 0 && bridge.bounds.height > 0)
        let center = bridge.convert(NSPoint(x: bridge.bounds.midX, y: bridge.bounds.midY), to: nil)
        #expect(bridge.matchesMenuEvent(mouseEvent(type: .rightMouseDown, location: center, windowNumber: window.windowNumber)))
    }

    private func mouseEvent(
        type: NSEvent.EventType,
        modifiers: NSEvent.ModifierFlags = [],
        location: NSPoint = .zero,
        windowNumber: Int = 0
    ) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        )!
    }
}
