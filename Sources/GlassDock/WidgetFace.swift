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
import Foundation
import GlassDockCore
import SwiftUI

struct WidgetFace: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.widgetScale) private var widgetScale
    @Environment(\.colorSchemeContrast) private var contrast
    let configuration: DockWidgetConfiguration
    @ObservedObject var runtime: WidgetRuntime
    let batteryPercent: Int?
    let batterySymbol: String

    private var accent: Color { store.accent }
    private var metrics: WidgetMetrics { WidgetMetrics(scale: widgetScale) }
    private var height: CGFloat { metrics.height }
    private var width: CGFloat { metrics.dimension(CGFloat(configuration.kind.preferredWidth)) }
    private func d(_ value: CGFloat) -> CGFloat { metrics.dimension(value) }
    private func f(_ value: CGFloat) -> CGFloat { metrics.fontSize(value) }
    private var isMusicWidget: Bool {
        configuration.kind == .musicFull || configuration.kind == .musicMini
    }

    var body: some View {
        Group {
            if isMusicWidget {
                faceContent()
            } else {
                faceContent()
                    .frame(width: width, height: height)
                    .widgetGlassSurface(radius: d(15))
            }
        }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .foregroundStyle(.primary)
            .accessibilityElement(children: isMusicWidget ? .contain : .combine)
            .focusEffectDisabled()
    }

    @ViewBuilder
    private func faceContent() -> some View {
        switch configuration.kind {
        case .clock: clockFace
        case .worldClock: worldClockFace
        case .stopwatch: timerFace(symbol: "stopwatch", title: "秒表")
        case .focusTimer: timerFace(symbol: "leaf", title: "专注")
        case .timeProgress: timeProgressFace
        case .countdown: timerFace(symbol: "hourglass", title: "倒计时")
        case .alarm: alarmFace
        case .hydration: hydrationFace
        case .remindersList: remindersFace(style: .list)
        case .reminderNext: remindersFace(style: .next)
        case .reminderCount: remindersFace(style: .count)
        case .calendarNext: calendarFace(style: .next)
        case .calendarDateNext: calendarFace(style: .dateNext)
        case .calendarAgenda: calendarFace(style: .agenda)
        case .calendarDate: calendarDateFace
        case .stickyNote: stickyNoteFace
        case .musicFull: MusicWidgetFace(runtime: runtime, compact: false)
        case .musicMini: MusicWidgetFace(runtime: runtime, compact: true)
        case .batteryStatus: batteryFace(style: .status)
        case .batteryRing: batteryFace(style: .ring)
        case .batteryIcon: batteryFace(style: .icon)
        case .systemNumbers: systemFace(style: .numbers)
        case .systemRings: systemFace(style: .rings)
        case .systemBars: systemFace(style: .bars)
        case .networkNumbers: networkFace(style: .numbers)
        case .networkChart: networkFace(style: .chart)
        case .aiNumbers:
            CodexUsageFace(runtime: runtime, accent: accent, title: configuration.displayTitle, style: .numbers)
        case .aiRings:
            CodexUsageFace(runtime: runtime, accent: accent, title: configuration.displayTitle, style: .rings)
        case .aiBars:
            CodexUsageFace(runtime: runtime, accent: accent, title: configuration.displayTitle, style: .bars)
        case .aiCapsules:
            CodexUsageFace(runtime: runtime, accent: accent, title: configuration.displayTitle, style: .capsules)
        case .shortcut: shortcutFace
        case .airDrop: airDropFace
        case .cpuTemperatureNumber: temperatureFace(style: .number)
        case .cpuTemperatureRing: temperatureFace(style: .ring)
        case .weatherCurrent, .weatherConditions, .weatherHourly,
             .stripeChart, .stripeNumber, .paddleChart, .paddleNumber, .shopifyChart, .shopifyNumber,
             .stock, .watchlist:
            WidgetExternalFace(configuration: configuration, accent: accent)
        }
    }

    private var clockFace: some View {
        HStack(spacing: d(8)) {
            MiniAnalogClock(date: runtime.now, timeZoneIdentifier: TimeZone.current.identifier, size: d(29))
            VStack(alignment: .leading, spacing: d(2)) {
                Text(runtime.now, format: .dateTime.hour().minute())
                    .font(.system(size: f(21), weight: .regular, design: .rounded)).monospacedDigit()
                Text(formattedDate(runtime.now, timeZoneIdentifier: TimeZone.current.identifier))
                    .font(.system(size: f(8))).foregroundStyle(.secondary)
            }
        }
    }

    private var worldClockFace: some View {
        HStack(spacing: d(10)) {
            MiniAnalogClock(date: runtime.now, timeZoneIdentifier: configuration.timeZoneIdentifier, size: d(30))
            VStack(alignment: .leading, spacing: d(metrics.height < 48 ? 1 : 3)) {
                Text(worldClockTitle).font(.system(size: f(10), weight: .medium)).lineLimit(1)
                Text(formattedTime(runtime.now, timeZoneIdentifier: configuration.timeZoneIdentifier))
                    .font(.system(size: f(19), weight: .regular, design: .rounded)).monospacedDigit()
                if metrics.height >= 48 {
                    Text(formattedDate(runtime.now, timeZoneIdentifier: configuration.timeZoneIdentifier))
                        .font(.system(size: f(8))).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, d(10))
        .accessibilityLabel(worldClockAccessibilityLabel)
        .help(worldClockAccessibilityLabel)
    }

    private func timerFace(symbol: String, title: String) -> some View {
        HStack(spacing: d(9)) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: d(3))
                Circle().trim(from: 0, to: timerProgress)
                    .stroke(accent, style: StrokeStyle(lineWidth: d(3), lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: symbol).font(.system(size: f(12), weight: .medium)).foregroundStyle(accent)
            }.frame(width: d(36), height: d(36))
            VStack(alignment: .leading, spacing: d(2)) {
                Text(timerLabel).font(.system(size: f(17), weight: .regular, design: .rounded)).monospacedDigit()
                Text(configuration.title.isEmpty ? title : configuration.title)
                    .font(.system(size: f(9))).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, d(9))
    }

    private var timeProgressFace: some View {
        let progress = DockWidgetConfiguration.yearProgress(at: runtime.now)
        return HStack(spacing: d(9)) {
            YearTickRing(value: progress, color: accent, size: d(35))
            VStack(alignment: .leading, spacing: d(3)) {
                Text("今年").font(.system(size: f(9))).foregroundStyle(.secondary)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: f(18), weight: .regular, design: .rounded)).monospacedDigit()
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, d(9))
    }

    private var alarmFace: some View {
        HStack(spacing: d(8)) {
            Image(systemName: runtime.alarmIsArmed(configuration.id) ? "alarm.fill" : "alarm")
                .font(.system(size: f(19), weight: .regular)).foregroundStyle(runtime.alarmIsArmed(configuration.id) ? accent : .secondary)
            VStack(alignment: .leading, spacing: d(2)) {
                Text(configuration.targetDate, format: .dateTime.hour().minute())
                    .font(.system(size: f(19), weight: .regular, design: .rounded)).monospacedDigit()
                Text(runtime.alarmIsArmed(configuration.id) ? "已启用" : "闹钟")
                    .font(.system(size: f(9))).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, d(10))
    }

    private var hydrationFace: some View {
        let count = Calendar.current.isDate(configuration.hydrationDate, inSameDayAs: runtime.now)
            ? configuration.hydrationCount : 0
        return HStack(spacing: d(9)) {
            Image(systemName: "drop.fill").font(.system(size: f(21), weight: .regular)).foregroundStyle(accent)
            VStack(alignment: .leading, spacing: d(2)) {
                Text("\(count) 杯").font(.system(size: f(18), weight: .regular, design: .rounded)).monospacedDigit()
                Text("今日饮水").font(.system(size: f(9))).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, d(10))
    }

    private enum ReminderStyle { case list, next, count }

    private func remindersFace(style: ReminderStyle) -> some View {
        let incomplete = runtime.reminders.filter { !$0.completed }
        return Group {
            switch runtime.remindersAccess {
            case .authorized:
                switch style {
                case .count:
                    HStack(spacing: d(8)) {
                        Image(systemName: "checklist").font(.system(size: f(14))).foregroundStyle(accent)
                        Text("\(incomplete.count)").font(.system(size: f(23), weight: .regular, design: .rounded)).monospacedDigit()
                        Text("待办").font(.system(size: f(9))).foregroundStyle(.secondary)
                    }
                case .next:
                    HStack(spacing: d(7)) {
                        Image(systemName: "checkmark.circle").font(.system(size: f(14))).foregroundStyle(accent)
                        Text(incomplete.first?.title ?? "暂无待办").font(.system(size: f(10))).lineLimit(2)
                    }.padding(.horizontal, d(8))
                case .list:
                    VStack(alignment: .leading, spacing: d(4)) {
                        ForEach(Array(incomplete.prefix(2)), id: \.id) { reminder in
                            HStack(spacing: d(5)) {
                                Image(systemName: "circle").font(.system(size: f(8))).foregroundStyle(accent)
                                Text(reminder.title).font(.system(size: f(9))).lineLimit(1)
                            }
                        }
                        if incomplete.isEmpty { Text("暂无待办").font(.system(size: f(10))).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, d(9))
                }
            case .notRequested: accessPrompt("连接提醒事项", symbol: "checklist")
            case .denied: accessPrompt("未授权提醒事项", symbol: "lock.fill")
            case .unavailable: accessPrompt("提醒事项不可用", symbol: "xmark.circle")
            }
        }
    }

    private enum CalendarStyle { case next, dateNext, agenda }

    private func calendarFace(style: CalendarStyle) -> some View {
        let upcoming = upcomingEvents
        return Group {
            switch runtime.calendarAccess {
            case .authorized:
                switch style {
                case .next:
                    HStack(spacing: d(8)) {
                        Image(systemName: "calendar").font(.system(size: f(14))).foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: d(3)) {
                            Text(upcoming.first?.title ?? "暂无日程").font(.system(size: f(10), weight: .medium)).lineLimit(1)
                            if let event = upcoming.first {
                                Text(event.start, format: .dateTime.hour().minute())
                                    .font(.system(size: f(9))).foregroundStyle(.secondary)
                            } else { Text("今天").font(.system(size: f(9))).foregroundStyle(.secondary) }
                        }
                    }.padding(.horizontal, d(8))
                case .dateNext:
                    HStack(spacing: d(9)) {
                        dayTile
                        VStack(alignment: .leading, spacing: d(3)) {
                            Text(upcoming.first?.title ?? "暂无日程").font(.system(size: f(9), weight: .medium)).lineLimit(2)
                            if let event = upcoming.first {
                                Text(event.start, format: .dateTime.hour().minute())
                                    .font(.system(size: f(8))).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }.padding(.horizontal, d(8))
                case .agenda:
                    HStack(spacing: d(10)) {
                        dayTile
                        VStack(alignment: .leading, spacing: d(4)) {
                            ForEach(Array(upcoming.prefix(2)), id: \.id) { event in
                                HStack(spacing: d(4)) {
                                    Text(event.start, format: .dateTime.hour().minute())
                                        .font(.system(size: f(8), design: .rounded)).monospacedDigit().foregroundStyle(.secondary)
                                    Text(event.title).font(.system(size: f(9))).lineLimit(1)
                                }
                            }
                            if upcoming.isEmpty { Text("暂无日程").font(.system(size: f(9))).foregroundStyle(.secondary) }
                        }
                        Spacer(minLength: 0)
                    }.padding(.horizontal, d(8))
                }
            case .notRequested: accessPrompt("连接日历", symbol: "calendar")
            case .denied: accessPrompt("未授权日历", symbol: "lock.fill")
            case .unavailable: accessPrompt("日历不可用", symbol: "xmark.circle")
            }
        }
    }

    private var calendarDateFace: some View { dayTile }

    private var dayTile: some View {
        VStack(spacing: d(0)) {
            Text(runtime.now, format: .dateTime.weekday(.abbreviated))
                .font(.system(size: f(8), weight: .medium)).foregroundStyle(.secondary)
            Text(runtime.now, format: .dateTime.day())
                .font(.system(size: f(22), weight: .regular, design: .rounded)).monospacedDigit()
        }.frame(width: d(36), height: metrics.height < 48 ? metrics.height : d(43))
    }

    private var stickyNoteFace: some View {
        HStack(alignment: .top, spacing: d(7)) {
            Image(systemName: "note.text").font(.system(size: f(13))).foregroundStyle(accent)
            Text(configuration.text.isEmpty ? "点击编辑便签" : configuration.text)
                .font(.system(size: f(8))).lineLimit(metrics.height < 48 ? 2 : 4).multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }.padding(.horizontal, d(9)).padding(.vertical, d(6))
    }

    private enum BatteryStyle { case status, ring, icon }

    private func batteryFace(style: BatteryStyle) -> some View {
        Group {
            if let batteryPercent {
                switch style {
                case .status:
                    HStack(spacing: d(8)) {
                        Image(systemName: batterySymbol).font(.system(size: f(18), weight: .regular)).foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: d(3)) {
                            Text("\(batteryPercent)%").font(.system(size: f(19), weight: .regular, design: .rounded)).monospacedDigit()
                            Text("本机电池").font(.system(size: f(9))).foregroundStyle(.secondary)
                        }
                    }
                case .ring:
                    HStack(spacing: d(8)) {
                        SmallRing(value: Double(batteryPercent) / 100, color: accent, size: d(36))
                        VStack(alignment: .leading, spacing: d(3)) {
                            Text("\(batteryPercent)%").font(.system(size: f(17), weight: .regular, design: .rounded)).monospacedDigit()
                            Text("电量").font(.system(size: f(9))).foregroundStyle(.secondary)
                        }
                    }
                case .icon:
                    VStack(spacing: d(2)) {
                        Image(systemName: batterySymbol).font(.system(size: f(20), weight: .regular)).foregroundStyle(accent)
                        Text("\(batteryPercent)%").font(.system(size: f(8), design: .rounded)).monospacedDigit()
                    }
                }
            } else {
                HStack(spacing: d(6)) {
                    Image(systemName: batterySymbol).font(.system(size: f(14))).foregroundStyle(.secondary)
                    Text("交流电源").font(.system(size: f(9))).foregroundStyle(.secondary)
                }
            }
        }
    }

    private enum SystemStyle { case numbers, rings, bars }

    private func systemFace(style: SystemStyle) -> some View {
        let cpu = runtime.metrics.cpuPercent
        let memory = runtime.metrics.memoryPercent
        return Group {
            if cpu == nil && memory == nil {
                waitingFace(title: "系统活动", symbol: "cpu")
            } else {
                switch style {
                case .numbers:
                    HStack(spacing: d(12)) {
                        metricNumber("CPU", value: cpu)
                        metricNumber("内存", value: memory)
                    }
                case .rings:
                    HStack(spacing: d(14)) {
                        metricRing("CPU", value: cpu)
                        metricRing("内存", value: memory)
                    }
                case .bars:
                    VStack(alignment: .leading, spacing: d(7)) {
                        metricBar("CPU", value: cpu)
                        metricBar("内存", value: memory)
                    }.padding(.horizontal, d(10))
                }
            }
        }
    }

    private enum TemperatureStyle { case number, ring }

    private func temperatureColor(_ level: TemperatureLevel) -> Color {
        switch level {
        case .normal: accent
        case .warm: Color(nsColor: .systemOrange)
        case .hot: Color(nsColor: .systemRed)
        }
    }

    @ViewBuilder
    private func temperatureFace(style: TemperatureStyle) -> some View {
        let unit = configuration.resolvedTemperatureUnit
        switch runtime.cpuTemperature {
        case .sampling:
            waitingFace(title: "CPU 温度", symbol: "thermometer.medium")
        case .unavailable:
            switch style {
            case .number:
                HStack(spacing: d(6)) {
                    Image(systemName: "thermometer.slash").font(.system(size: f(14))).foregroundStyle(.secondary)
                    Text("不可用").font(.system(size: f(9))).foregroundStyle(.secondary)
                }
            case .ring:
                HStack(spacing: d(8)) {
                    ZStack {
                        SmallRing(value: nil, color: accent, size: d(36))
                        Image(systemName: "thermometer.slash").font(.system(size: f(11))).foregroundStyle(.secondary)
                    }
                    Text("不可用").font(.system(size: f(9))).foregroundStyle(.secondary)
                }
            }
        case .reading(let aggregate):
            let level = aggregate.level
            let color = temperatureColor(level)
            let highContrast = contrast == .increased
            let valueColor: Color = highContrast && level != .normal ? color : .primary
            switch style {
            case .number:
                HStack(spacing: d(8)) {
                    Image(systemName: level.symbol).font(.system(size: f(18), weight: .regular)).foregroundStyle(color)
                    VStack(alignment: .leading, spacing: d(3)) {
                        Text(unit.formatted(celsius: aggregate.average))
                            .font(.system(size: f(19), weight: level == .hot ? .semibold : .regular, design: .rounded))
                            .monospacedDigit().foregroundStyle(valueColor)
                        Text("CPU · 最高 \(unit.rounded(celsius: aggregate.maximum))°")
                            .font(.system(size: f(9))).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            case .ring:
                HStack(spacing: d(8)) {
                    ZStack {
                        SmallRing(value: aggregate.ringProgress, color: color, size: d(36), lineWidth: highContrast ? 4 : 3)
                        Image(systemName: level.symbol).font(.system(size: f(11))).foregroundStyle(color)
                    }
                    VStack(alignment: .leading, spacing: d(3)) {
                        Text(unit.formatted(celsius: aggregate.average))
                            .font(.system(size: f(17), weight: level == .hot ? .semibold : .regular, design: .rounded))
                            .monospacedDigit().foregroundStyle(valueColor)
                        Text("CPU 温度 · \(level.title)").font(.system(size: f(9))).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
    }

    private enum NetworkStyle { case numbers, chart }

    private func networkFace(style: NetworkStyle) -> some View {
        let download = runtime.metrics.downloadBytesPerSecond
        let upload = runtime.metrics.uploadBytesPerSecond
        return Group {
            switch style {
            case .numbers:
                if download == nil && upload == nil {
                    waitingFace(title: "网络速度", symbol: "network")
                } else {
                    HStack(spacing: d(11)) {
                        VStack(alignment: .leading, spacing: d(3)) {
                            Text("↓ \(widgetNetworkRateLabel(download))").font(.system(size: f(11), weight: .medium, design: .rounded)).monospacedDigit()
                            Text("下载").font(.system(size: f(8))).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: d(3)) {
                            Text("↑ \(widgetNetworkRateLabel(upload))").font(.system(size: f(11), weight: .medium, design: .rounded)).monospacedDigit()
                            Text("上传").font(.system(size: f(8))).foregroundStyle(.secondary)
                        }
                    }
                }
            case .chart:
                if runtime.metrics.networkHistory.isEmpty {
                    waitingFace(title: "网络曲线", symbol: "waveform.path")
                } else {
                    VStack(spacing: d(2)) {
                        Sparkline(values: runtime.metrics.networkHistory, color: accent).frame(height: d(29))
                        Text("网络速度").font(.system(size: f(8))).foregroundStyle(.secondary)
                    }.padding(.horizontal, d(10))
                }
            }
        }
    }

    private var shortcutFace: some View {
        HStack(spacing: d(8)) {
            Image(systemName: "shortcuts").font(.system(size: f(18), weight: .regular)).foregroundStyle(accent)
            VStack(alignment: .leading, spacing: d(2)) {
                Text(configuration.shortcutName.isEmpty ? "快捷指令" : configuration.shortcutName)
                    .font(.system(size: f(10), weight: .medium)).lineLimit(1)
                Text(configuration.shortcutName.isEmpty ? "点击配置" : "已就绪")
                    .font(.system(size: f(8))).foregroundStyle(.secondary)
            }
        }
    }

    private var airDropFace: some View {
        VStack(spacing: d(3)) {
            Image(systemName: "airdrop").font(.system(size: f(19), weight: .regular)).foregroundStyle(accent)
            Text("隔空投送").font(.system(size: f(8)))
        }
    }

    private func accessPrompt(_ title: String, symbol: String) -> some View {
        HStack(spacing: d(6)) {
            Image(systemName: symbol).font(.system(size: f(14))).foregroundStyle(.secondary)
            Text(title).font(.system(size: f(9))).foregroundStyle(.secondary).lineLimit(1)
        }.padding(.horizontal, d(8))
    }

    private func waitingFace(title: String, symbol: String) -> some View {
        HStack(spacing: d(7)) {
            Image(systemName: symbol).font(.system(size: f(15), weight: .regular)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: d(2)) {
                Text(title).font(.system(size: f(9), weight: .medium)).lineLimit(1)
                Text("正在采样").font(.system(size: f(8))).foregroundStyle(.secondary)
            }
        }
    }

    private func metricNumber(_ title: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: d(2)) {
            Text(value.map { "\(Int($0.rounded()))%" } ?? "—")
                .font(.system(size: f(14), weight: .regular, design: .rounded)).monospacedDigit()
            Text(title).font(.system(size: f(8))).foregroundStyle(.secondary)
        }
    }

    private func metricRing(_ title: String, value: Double?) -> some View {
        VStack(spacing: d(3)) {
            ZStack {
                SmallRing(value: value.map { min(1, max(0, $0 / 100)) }, color: accent, size: d(32))
                Text(value.map { "\(Int($0.rounded()))" } ?? "—")
                    .font(.system(size: f(7), weight: .medium, design: .rounded)).monospacedDigit()
            }
            Text(title).font(.system(size: f(8))).foregroundStyle(.secondary)
        }
    }

    private func metricBar(_ title: String, value: Double?) -> some View {
        HStack(spacing: d(6)) {
            Text(title).font(.system(size: f(8))).foregroundStyle(.secondary).frame(width: d(28), alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    if let value {
                        Capsule().fill(accent).frame(width: geometry.size.width * CGFloat(min(1, max(0, value / 100))))
                    }
                }
            }.frame(height: d(5))
            Text(value.map { "\(Int($0.rounded()))%" } ?? "—")
                .font(.system(size: f(8), design: .rounded)).monospacedDigit().frame(width: d(28), alignment: .trailing)
        }
    }

    private var timerLabel: String {
        let seconds = max(0, Int(runtime.timerValue(configuration).rounded(.up)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private var timerProgress: Double {
        guard configuration.durationSeconds > 0 else { return 0 }
        let value = runtime.timerValue(configuration)
        if configuration.kind == .stopwatch { return runtime.timerIsRunning(configuration.id) ? 1 : 0 }
        return min(1, max(0, value / Double(configuration.durationSeconds)))
    }

    private var upcomingEvents: [WidgetCalendarEvent] {
        runtime.events.filter { $0.end >= runtime.now }.sorted { $0.start < $1.start }
    }

    private func formattedTime(_ date: Date, timeZoneIdentifier: String) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func formattedDate(_ date: Date, timeZoneIdentifier: String) -> String {
        widgetDateLabel(date, timeZoneIdentifier: timeZoneIdentifier)
    }

    private var worldClockTitle: String {
        guard configuration.title.isEmpty else { return configuration.title }
        return configuration.timeZoneIdentifier.split(separator: "/").last
            .map { String($0).replacingOccurrences(of: "_", with: " ") } ?? "世界时钟"
    }

    private var worldClockAccessibilityLabel: String {
        let time = formattedTime(runtime.now, timeZoneIdentifier: configuration.timeZoneIdentifier)
        let date = formattedDate(runtime.now, timeZoneIdentifier: configuration.timeZoneIdentifier)
        return "\(worldClockTitle)，\(time)，\(date)"
    }

}
