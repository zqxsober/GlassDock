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

import Foundation
import Testing
@testable import GlassDockCore

@Suite("Per-screen Dock window grouping")
struct DockWindowGroupingTests {
    private let browser = PinnedApplication(name: "Browser", path: "/Applications/Browser.app")
    private let editor = PinnedApplication(name: "Editor", path: "/Applications/Editor.app")

    @Test func unverifiedHelperWindowsCollapseToOneAppIconUntilAccessibilityConfirmsThem() {
        let snapshots = (1...6).map {
            DockWindowSnapshot(id: UInt32($0), processID: 10, application: browser,
                               title: "Browser", bounds: CGRect(x: 0, y: 0, width: 500, height: 300), isVerified: false)
        }
        let entries = DockWindowGrouping.entries(pinned: [], windows: snapshots)
        #expect(entries.count == 1)
        #expect(entries[0].window == nil)
        #expect(!entries[0].showsWindowTitle)
    }

    private func window(_ id: UInt32, application: PinnedApplication, title: String = "Document") -> DockWindowSnapshot {
        DockWindowSnapshot(id: id, processID: application == browser ? 10 : 20,
                           application: application, title: title, bounds: CGRect(x: 0, y: 0, width: 400, height: 300))
    }

    @Test func oneWindowStaysAnIconAndMultipleWindowsExpandWithTitles() {
        let single = DockWindowGrouping.entries(pinned: [browser], windows: [window(1, application: browser)])
        #expect(single.count == 1)
        #expect(single[0].window?.id == 1)
        #expect(!single[0].showsWindowTitle)
        let multiple = DockWindowGrouping.entries(pinned: [browser], windows: [
            window(2, application: browser, title: "Second"), window(1, application: browser, title: "First")
        ])
        #expect(multiple.map(\.title) == ["First", "Second"])
        #expect(multiple.allSatisfy { $0.showsWindowTitle })
        #expect(Set(multiple.map(\.id)).count == 2)
    }

    @Test func fixedFoldersAndInactiveApplicationsRemainAndUnpinnedAppsAreAppended() {
        let folder = PinnedApplication(name: "Projects", path: "/Users/test/Projects", kind: .folder)
        let entries = DockWindowGrouping.entries(pinned: [folder, browser], windows: [window(7, application: editor)])
        #expect(entries.map(\.application) == [folder, browser, editor])
        #expect(entries[0].window == nil && entries[1].window == nil)
        #expect(entries[2].window?.id == 7)
    }

    @Test func windowClosureCollapsesGroupAndDuplicateSnapshotsDoNotDuplicateButtons() {
        let first = window(1, application: browser, title: "")
        let remaining = DockWindowGrouping.entries(pinned: [browser], windows: [first, first])
        #expect(remaining.count == 1)
        #expect(!remaining[0].showsWindowTitle)
        #expect(remaining[0].title == "Browser")
        let closed = DockWindowGrouping.entries(pinned: [browser], windows: [])
        #expect(closed.count == 1 && closed[0].window == nil)
    }

    @Test func crossDisplayWindowBelongsToLargestIntersectionOnly() {
        let left = CGRect(x: -1000, y: 0, width: 1000, height: 800)
        let right = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let spanning = CGRect(x: -100, y: 100, width: 400, height: 300)
        #expect(!DockWindowGrouping.belongsToScreen(spanning, target: left, screens: [left, right]))
        #expect(DockWindowGrouping.belongsToScreen(spanning, target: right, screens: [left, right]))
        #expect(!DockWindowGrouping.belongsToScreen(CGRect(x: 5000, y: 0, width: 100, height: 100),
                                                   target: right, screens: [left, right]))
    }

    @Test func windowOrderDoesNotChangeWhenFrontmostWindowChanges() {
        let a = window(1, application: browser)
        let b = window(2, application: browser)
        #expect(DockWindowGrouping.entries(pinned: [], windows: [a, b])
                == DockWindowGrouping.entries(pinned: [], windows: [b, a]))
    }
}
