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

public enum DockWidgetCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case clocks, calendar, reminders, notes, media, system, ai, weather, business, stocks
    public var id: String { rawValue }
    public static var availableCategories: [Self] {
        allCases.filter { category in DockWidgetKind.availableKinds.contains { $0.category == category } }
    }
    public var title: String {
        switch self {
        case .clocks: "时钟与计时"
        case .calendar: "日历"
        case .reminders: "提醒事项"
        case .notes: "便签"
        case .media: "媒体"
        case .system: "系统"
        case .ai: "AI"
        case .weather: "天气"
        case .business: "商业数据"
        case .stocks: "股票"
        }
    }
    public var symbol: String {
        switch self {
        case .clocks: "clock"
        case .calendar: "calendar"
        case .reminders: "checklist"
        case .notes: "note.text"
        case .media: "play.rectangle"
        case .system: "desktopcomputer"
        case .ai: "brain.head.profile"
        case .weather: "cloud.sun"
        case .business: "chart.xyaxis.line"
        case .stocks: "chart.line.uptrend.xyaxis"
        }
    }
}

/// 45 种已知组件布局；原始值用于兼容历史设置，停用项不进入选择器。
public enum DockWidgetKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case clock, worldClock, stopwatch, focusTimer, timeProgress, countdown, alarm
    case hydration, remindersList, reminderNext, reminderCount
    case calendarNext, calendarDateNext, calendarAgenda, calendarDate
    case stickyNote, musicFull, musicMini
    case batteryStatus, batteryRing, batteryIcon, systemNumbers, systemRings, systemBars
    case networkNumbers, networkChart, aiNumbers, aiRings, aiBars, aiCapsules, shortcut, airDrop
    case weatherCurrent, weatherConditions, weatherHourly
    case stripeChart, stripeNumber, paddleChart, paddleNumber, shopifyChart, shopifyNumber
    case stock, watchlist
    case cpuTemperatureNumber, cpuTemperatureRing

    public static var availableKinds: [Self] { allCases.filter(\.isAvailable) }

    public var id: String { rawValue }
    public var isAvailable: Bool { category != .business && category != .stocks }
    public var category: DockWidgetCategory {
        switch self {
        case .clock, .worldClock, .stopwatch, .focusTimer, .timeProgress, .countdown, .alarm: .clocks
        case .hydration, .remindersList, .reminderNext, .reminderCount: .reminders
        case .calendarNext, .calendarDateNext, .calendarAgenda, .calendarDate: .calendar
        case .stickyNote: .notes
        case .musicFull, .musicMini: .media
        case .batteryStatus, .batteryRing, .batteryIcon, .systemNumbers, .systemRings, .systemBars,
             .networkNumbers, .networkChart, .shortcut, .airDrop,
             .cpuTemperatureNumber, .cpuTemperatureRing: .system
        case .aiNumbers, .aiRings, .aiBars, .aiCapsules: .ai
        case .weatherCurrent, .weatherConditions, .weatherHourly: .weather
        case .stripeChart, .stripeNumber, .paddleChart, .paddleNumber, .shopifyChart, .shopifyNumber: .business
        case .stock, .watchlist: .stocks
        }
    }
    public var title: String {
        switch self {
        case .clock: "时钟"
        case .worldClock: "世界时钟"
        case .stopwatch: "秒表"
        case .focusTimer: "专注计时"
        case .timeProgress: "时间进度"
        case .countdown: "倒计时"
        case .alarm: "闹钟"
        case .hydration: "喝水提醒"
        case .remindersList: "提醒事项 · 列表"
        case .reminderNext: "下一条提醒"
        case .reminderCount: "提醒事项 · 数量"
        case .calendarNext: "下一个日程"
        case .calendarDateNext: "日期与日程"
        case .calendarAgenda: "日期与议程"
        case .calendarDate: "日期"
        case .stickyNote: "便签"
        case .musicFull: "正在播放 · 完整"
        case .musicMini: "正在播放 · 迷你"
        case .batteryStatus: "电量 · 状态"
        case .batteryRing: "电量 · 环形"
        case .batteryIcon: "电量 · 图标"
        case .systemNumbers: "系统活动 · 数字"
        case .systemRings: "系统活动 · 环形"
        case .systemBars: "系统活动 · 条形"
        case .networkNumbers: "网络速度 · 数字"
        case .networkChart: "网络速度 · 曲线"
        case .aiNumbers: "AI 额度 · 数字"
        case .aiRings: "AI 额度 · 环形"
        case .aiBars: "AI 额度 · 条形"
        case .aiCapsules: "AI 额度 · 胶囊"
        case .shortcut: "快捷指令"
        case .airDrop: "隔空投送"
        case .weatherCurrent: "天气 · 当前"
        case .weatherConditions: "天气 · 状况"
        case .weatherHourly: "天气 · 小时预报"
        case .stripeChart: "Stripe · 曲线"
        case .stripeNumber: "Stripe · 数字"
        case .paddleChart: "Paddle · 曲线"
        case .paddleNumber: "Paddle · 数字"
        case .shopifyChart: "Shopify · 曲线"
        case .shopifyNumber: "Shopify · 数字"
        case .stock: "股票"
        case .watchlist: "股票自选列表"
        case .cpuTemperatureNumber: "CPU 温度 · 数字"
        case .cpuTemperatureRing: "CPU 温度 · 环形"
        }
    }
    public var requiresExternalData: Bool {
        category == .weather || category == .business || category == .stocks
            || category == .ai
    }
    public var requiresCalendarAccess: Bool { [.calendarNext, .calendarDateNext, .calendarAgenda].contains(self) }
    public var requiresRemindersAccess: Bool { [.remindersList, .reminderNext, .reminderCount].contains(self) }
    public var isCPUTemperature: Bool { self == .cpuTemperatureNumber || self == .cpuTemperatureRing }
    public var isTimer: Bool { [.stopwatch, .focusTimer, .countdown, .hydration].contains(self) }
    public var preferredWidth: Double {
        switch self {
        case .musicFull: 280
        case .aiNumbers, .aiRings, .aiBars, .aiCapsules, .networkNumbers: 220
        case .calendarAgenda, .watchlist: 190
        case .worldClock, .calendarDateNext, .calendarNext, .remindersList, .reminderNext,
             .weatherCurrent, .weatherConditions, .weatherHourly: 160
        case .batteryIcon, .musicMini, .airDrop, .calendarDate: 62
        default: 132
        }
    }
}

/// 一个已添加的组件及其可编辑设置；不保存服务密钥或示例实时数据。
public struct DockWidgetConfiguration: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: DockWidgetKind
    public var title: String
    public var text: String
    public var timeZoneIdentifier: String
    public var durationSeconds: Int
    public var targetDate: Date
    public var shortcutName: String
    public var hydrationCount: Int
    public var hydrationDate: Date
    /// 仅 CPU 温度组件使用；可选以兼容不含该字段的旧设置，nil 视为摄氏。
    public var temperatureUnit: TemperatureUnit?

    public init(kind: DockWidgetKind, id: UUID = UUID()) {
        self.id = id
        self.kind = kind
        title = ""
        text = ""
        timeZoneIdentifier = TimeZone.current.identifier
        durationSeconds = kind == .hydration ? 2700 : (kind == .focusTimer ? 1500 : 300)
        targetDate = Date().addingTimeInterval(3600)
        shortcutName = ""
        hydrationCount = 0
        hydrationDate = Date()
    }

    public var resolvedTemperatureUnit: TemperatureUnit { temperatureUnit ?? .celsius }

    public var displayTitle: String { title.isEmpty ? kind.title : title }
    public var keyboardID: String { "widget-\(id.uuidString)" }

    /// 限制可编辑数值并修正失效时区，防止损坏设置影响整个 Dock 布局。
    public mutating func normalize() {
        durationSeconds = min(86_400, max(1, durationSeconds))
        hydrationCount = min(1000, max(0, hydrationCount))
        title = String(title.prefix(60))
        text = String(text.prefix(2000))
        shortcutName = String(shortcutName.prefix(200))
        if TimeZone(identifier: timeZoneIdentifier) == nil { timeZoneIdentifier = TimeZone.current.identifier }
    }

    /// 按实际日历区间计算年度进度，包含闰年和时区变化。
    public static func yearProgress(at date: Date, calendar: Calendar = .current) -> Double {
        guard let interval = calendar.dateInterval(of: .year, for: date), interval.duration > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(interval.start) / interval.duration))
    }
}
