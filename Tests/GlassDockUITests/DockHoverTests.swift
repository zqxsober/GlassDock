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

@Suite("Dock hover boundaries", .serialized)
@MainActor
struct DockHoverTests {
    @Test func adjacentIconsDoNotShareTheParentsVisibleHoverRegion() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        window.contentView = root
        let first = ActiveHoverTrackingNSView(frame: NSRect(x: 60, y: 10, width: 60, height: 70))
        let second = ActiveHoverTrackingNSView(frame: NSRect(x: 120, y: 10, width: 60, height: 70))
        root.addSubview(first)
        root.addSubview(second)
        window.orderFront(nil)
        let firstPoint = NSPoint(x: 80, y: 30)
        first.synchronizeHoverState(at: firstPoint)
        second.synchronizeHoverState(at: firstPoint)
        #expect(first.isHovered)
        #expect(!second.isHovered)
        let secondPoint = NSPoint(x: 140, y: 30)
        first.synchronizeHoverState(at: secondPoint)
        second.synchronizeHoverState(at: secondPoint)
        #expect(!first.isHovered)
        #expect(second.isHovered)
        first.synchronizeHoverState(at: .zero)
        second.synchronizeHoverState(at: .zero)
        #expect(!first.isHovered && !second.isHovered)
    }

    @Test func mouseMovementRespectsScaledBoundsAndHiddenWindowClearsHover() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        window.contentView = root
        let tracker = ActiveHoverTrackingNSView(frame: NSRect(x: 60, y: 10, width: 30, height: 40))
        tracker.bounds = NSRect(x: 0, y: 0, width: 60, height: 80)
        root.addSubview(tracker)
        window.orderFront(nil)
        let inside = NSPoint(x: 75, y: 30)
        let moved = try #require(NSEvent.mouseEvent(
            with: .mouseMoved, location: inside, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0
        ))
        tracker.mouseMoved(with: moved)
        #expect(tracker.isHovered)
        tracker.synchronizeHoverState(at: NSPoint(x: 110, y: 30))
        #expect(!tracker.isHovered)
        tracker.synchronizeHoverState(at: inside)
        window.orderOut(nil)
        tracker.synchronizeHoverState(at: inside)
        #expect(!tracker.isHovered)
        window.orderFront(nil)
        tracker.synchronizeHoverState(at: inside)
        #expect(tracker.isHovered)
        tracker.removeFromSuperview()
        #expect(!tracker.isHovered)
    }

    @Test func swiftUIBackgroundsHaveIndependentHoverRegionsAfterScaling() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: HStack(spacing: 0) {
            Color.clear.frame(width: 60, height: 70)
                .background { ActiveHoverTrackingView(isHovered: .constant(false)) }
            Color.clear.frame(width: 60, height: 70)
                .background { ActiveHoverTrackingView(isHovered: .constant(false)) }
        }.scaleEffect(0.5).frame(width: 60, height: 35))
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        func trackers(in view: NSView) -> [ActiveHoverTrackingNSView] {
            if let tracker = view as? ActiveHoverTrackingNSView { return [tracker] }
            return view.subviews.flatMap { trackers(in: $0) }
        }
        let views = trackers(in: host)
        #expect(views.count == 2)
        let first = try #require(views.first)
        let second = try #require(views.last)
        let point = first.convert(NSPoint(x: first.bounds.midX, y: first.bounds.midY), to: nil)
        first.synchronizeHoverState(at: point)
        second.synchronizeHoverState(at: point)
        #expect(first.isHovered)
        #expect(!second.isHovered)
    }
}
