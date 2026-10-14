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

import CoreGraphics
import Foundation

/// 当前桌面上属于目标屏幕的普通应用窗口；坐标沿用 Core Graphics 左上角坐标系。
public struct DockWindowSnapshot: Equatable, Identifiable, Sendable {
    public let id: UInt32
    public let processID: Int32
    public let application: PinnedApplication
    public let title: String
    public let bounds: CGRect
    public let isVerified: Bool
    public let accessibilityIdentity: UUID?

    public init(
        id: UInt32,
        processID: Int32,
        application: PinnedApplication,
        title: String,
        bounds: CGRect,
        isVerified: Bool = true,
        accessibilityIdentity: UUID? = nil
    ) {
        self.id = id
        self.processID = processID
        self.application = application
        self.title = title
        self.bounds = bounds
        self.isVerified = isVerified
        self.accessibilityIdentity = accessibilityIdentity
    }
}

/// 固定入口与本屏幕运行窗口合并后的单个 Dock 控件。
public struct DockApplicationEntry: Identifiable, Equatable, Sendable {
    public let application: PinnedApplication
    public let window: DockWindowSnapshot?
    public let showsWindowTitle: Bool
    public var id: String {
        guard let window else { return application.id }
        if let accessibilityIdentity = window.accessibilityIdentity {
            return "window-\(window.processID)-ax-\(accessibilityIdentity.uuidString)"
        }
        return "window-\(window.processID)-\(window.id)"
    }
    public var title: String {
        guard let window, !window.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return application.name
        }
        return window.title
    }

    public init(application: PinnedApplication, window: DockWindowSnapshot? = nil, showsWindowTitle: Bool = false) {
        self.application = application
        self.window = window
        self.showsWindowTitle = showsWindowTitle
    }
}

public enum DockWindowGrouping {
    /// 保留固定顺序，展开本屏幕的多窗口应用，最后追加未固定的运行窗口。
    public static func entries(pinned: [PinnedApplication], windows: [DockWindowSnapshot]) -> [DockApplicationEntry] {
        var seen = Set<String>()
        let unique = windows.filter { window in
            let identity = window.accessibilityIdentity.map { "ax-\($0.uuidString)" } ?? "cg-\(window.id)"
            return seen.insert("\(window.processID)-\(identity)").inserted
        }
        let discoveredApplications = Dictionary(unique.map { ($0.application.path, $0.application) }, uniquingKeysWith: { first, _ in first })
        // CG 清单也含应用的辅助窗口，只有 AX 确认的普通窗口才展开为窗口入口。
        let grouped = Dictionary(grouping: unique.filter { $0.isVerified }, by: { $0.application.path })
        var result: [DockApplicationEntry] = []

        func append(_ application: PinnedApplication) {
            let appWindows = (grouped[application.path] ?? []).sorted { $0.id < $1.id }
            if application.kind == .folder || appWindows.isEmpty {
                result.append(DockApplicationEntry(application: application))
            } else {
                result += appWindows.map {
                    DockApplicationEntry(application: application, window: $0, showsWindowTitle: appWindows.count > 1)
                }
            }
        }

        pinned.forEach(append)
        let pinnedPaths = Set(pinned.filter { $0.kind == .application }.map(\.path))
        let extras = discoveredApplications.keys.filter { !pinnedPaths.contains($0) }.sorted {
            let left = discoveredApplications[$0]?.name ?? $0
            let right = discoveredApplications[$1]?.name ?? $1
            if left == right { return $0 < $1 }
            return left.localizedStandardCompare(right) == .orderedAscending
        }
        for path in extras {
            if let application = discoveredApplications[path] { append(application) }
        }
        return result
    }

    /// 跨屏窗口归入占其可见面积最多的屏幕，避免在两块屏幕重复显示。
    public static func belongsToScreen(_ bounds: CGRect, target: CGRect, screens: [CGRect]) -> Bool {
        func area(_ rect: CGRect) -> CGFloat {
            let overlap = bounds.intersection(rect)
            return overlap.isNull ? 0 : overlap.width * overlap.height
        }
        guard !bounds.isEmpty, area(target) > 0 else { return false }
        let owner = screens.max { area($0) < area($1) }
        return owner == target
    }
}
