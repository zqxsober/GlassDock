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

public struct PinnedApplication: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case application
        case folder
    }

    public var id: String { path }
    public var name: String
    public var path: String
    public var kind: Kind

    public init(name: String, path: String, kind: Kind = .application) {
        self.name = name
        self.path = path
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey {
        case name, path, kind
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        path = try values.decode(String.self, forKey: .path)
        kind = try values.decodeIfPresent(Kind.self, forKey: .kind) ?? .application
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(name, forKey: .name)
        try values.encode(path, forKey: .path)
        try values.encode(kind, forKey: .kind)
    }
}

public enum DockAccent: String, Codable, CaseIterable, Identifiable {
    case mint, ocean, rose
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .mint: "薄荷绿"
        case .ocean: "冰川蓝"
        case .rose: "暮光粉"
        }
    }
}

public struct DockPreferences: Codable, Equatable {
    public static let iconSizeRange = 10.0...96.0
    public static let iconScaleRange = 0.5...1.25
    public static let verticalSpacingRange = 0.0...24.0
    public static let cornerRadiusRange = 0.0...48.0
    public var applications: [PinnedApplication] = []
    public var iconSize: Double = 48
    public var iconScale: Double = 1
    public var verticalSpacing: Double = 8
    public var cornerRadius: Double = 26
    public var customWidgets: [DockWidgetConfiguration] = []
    public var magnification = true
    public var showClock = true
    public var showFocus = true
    public var showBattery = true
    public var showDockOnLaunch = true
    public var accent: DockAccent = .mint
    public var focusMinutes = 25

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case applications, iconSize, iconScale, verticalSpacing, cornerRadius, magnification, showClock, showFocus
        case showBattery, showDockOnLaunch, accent, focusMinutes, customWidgets
    }

    /// 读取本地设置；旧版本缺少上下间距时保留原来的 8 点间距。
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        applications = try values.decode([PinnedApplication].self, forKey: .applications)
        iconSize = try values.decode(Double.self, forKey: .iconSize)
        iconScale = try values.decodeIfPresent(Double.self, forKey: .iconScale) ?? 1
        verticalSpacing = try values.decodeIfPresent(Double.self, forKey: .verticalSpacing) ?? 8
        cornerRadius = try values.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 26
        customWidgets = try values.decodeIfPresent([DockWidgetConfiguration].self, forKey: .customWidgets) ?? []
        magnification = try values.decode(Bool.self, forKey: .magnification)
        showClock = try values.decode(Bool.self, forKey: .showClock)
        showFocus = try values.decode(Bool.self, forKey: .showFocus)
        showBattery = try values.decode(Bool.self, forKey: .showBattery)
        showDockOnLaunch = try values.decode(Bool.self, forKey: .showDockOnLaunch)
        accent = try values.decode(DockAccent.self, forKey: .accent)
        focusMinutes = try values.decode(Int.self, forKey: .focusMinutes)
    }

    public mutating func normalize() {
        iconSize = iconSize.isFinite ? min(Self.iconSizeRange.upperBound, max(Self.iconSizeRange.lowerBound, iconSize)) : 48
        iconScale = iconScale.isFinite ? min(Self.iconScaleRange.upperBound, max(Self.iconScaleRange.lowerBound, iconScale)) : 1
        verticalSpacing = verticalSpacing.isFinite ? min(Self.verticalSpacingRange.upperBound, max(Self.verticalSpacingRange.lowerBound, verticalSpacing)) : 8
        cornerRadius = cornerRadius.isFinite ? min(Self.cornerRadiusRange.upperBound, max(Self.cornerRadiusRange.lowerBound, cornerRadius)) : 26
        focusMinutes = min(90, max(1, focusMinutes))
        var seen = Set<String>()
        applications = applications.filter { app in
            Self.isValidPin(app) && seen.insert(app.path).inserted
        }.prefix(12).map { $0 }
        var widgetIDs = Set<UUID>()
        customWidgets = customWidgets.filter { $0.kind.isAvailable && widgetIDs.insert($0.id).inserted }.map {
            var widget = $0
            widget.normalize()
            return widget
        }
    }

    @discardableResult
    public mutating func pin(_ application: PinnedApplication) -> Bool {
        guard applications.count < 12,
              Self.isValidPin(application),
              !applications.contains(where: { $0.path == application.path }) else { return false }
        applications.append(application)
        return true
    }

    private static func isValidPin(_ application: PinnedApplication) -> Bool {
        guard application.path.hasPrefix("/") else { return false }
        return switch application.kind {
        case .application:
            application.path.lowercased().hasSuffix(".app")
        case .folder:
            true
        }
    }

    public mutating func remove(id: String) {
        applications.removeAll { $0.id == id }
    }

    public mutating func move(id: String, offset: Int) {
        guard let index = applications.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + offset
        guard applications.indices.contains(destination) else { return }
        applications.swapAt(index, destination)
    }
}

public struct FocusTimer: Equatable {
    public enum State: Equatable {
        case idle
        case running(until: Date)
        case paused(seconds: TimeInterval)
        case completed
    }

    public private(set) var state: State = .idle
    public private(set) var duration: TimeInterval = 25 * 60

    public init() {}

    public var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    public func remaining(at date: Date) -> TimeInterval {
        switch state {
        case .idle: return duration
        case .running(let end): return max(0, end.timeIntervalSince(date))
        case .paused(let seconds): return max(0, seconds)
        case .completed: return 0
        }
    }

    public func progress(at date: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, 1 - remaining(at: date) / duration))
    }

    public func label(at date: Date) -> String {
        let seconds = Int(ceil(remaining(at: date)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    public mutating func start(minutes: Int, at date: Date) {
        duration = TimeInterval(min(90, max(1, minutes)) * 60)
        state = .running(until: date.addingTimeInterval(duration))
    }

    public mutating func pause(at date: Date) {
        guard isRunning else { return }
        let seconds = remaining(at: date)
        state = seconds > 0 ? .paused(seconds: seconds) : .completed
    }

    public mutating func resume(at date: Date) {
        guard case .paused(let seconds) = state else { return }
        state = .running(until: date.addingTimeInterval(seconds))
    }

    public mutating func reset(minutes: Int) {
        duration = TimeInterval(min(90, max(1, minutes)) * 60)
        state = .idle
    }

    @discardableResult
    public mutating func tick(at date: Date) -> Bool {
        guard case .running(let end) = state, date >= end else { return false }
        state = .completed
        return true
    }
}
