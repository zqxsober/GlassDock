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

import GlassDockCore
import SwiftUI

struct WidgetTile: View {
    @EnvironmentObject private var store: AppStore
    let configuration: DockWidgetConfiguration
    @ObservedObject var runtime: WidgetRuntime
    var preview = false
    @State private var isPresented = false

    var body: some View {
        tileContent
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            WidgetDetails(configurationID: configuration.id)
                .environmentObject(store)
        }
        .onChange(of: isPresented) { _, editing in store.isWidgetEditorPresented = editing }
        .onDisappear { if isPresented { store.isWidgetEditorPresented = false } }
        .onChange(of: store.presentedWidgetID) { _, presentedID in
            guard !preview, presentedID == configuration.id else { return }
            isPresented = true
            store.presentedWidgetID = nil
        }
        .onChange(of: store.preferences.customWidgets.contains { $0.id == configuration.id }) { _, stillExists in
            if !stillExists {
                isPresented = false
                store.presentedWidgetID = nil
            }
        }
        .contextMenu {
            Button("配置组件", systemImage: "slider.horizontal.3") { isPresented = true }
            Divider()
            Button("从 Dock 移除", systemImage: "minus.circle", role: .destructive) {
                store.removeWidget(id: configuration.id)
            }
        }
    }

    @ViewBuilder
    private var tileContent: some View {
        if isMusicWidget {
            widgetFace
        } else {
            Button {
                isPresented = true
            } label: {
                widgetFace
            }
            .buttonStyle(.plain)
            .focusable()
            .focusEffectDisabled()
            .accessibilityLabel(widgetAccessibilityLabel)
            .help(widgetHelpDescription)
        }
    }

    private var widgetFace: some View {
        WidgetFace(configuration: configuration, runtime: runtime,
                   batteryPercent: store.batteryPercent, batterySymbol: store.batterySymbol)
    }

    private var isMusicWidget: Bool {
        configuration.kind == .musicFull || configuration.kind == .musicMini
    }

    private var isAIUsageWidget: Bool {
        configuration.kind.category == .ai
    }

    private var widgetAccessibilityLabel: String {
        if configuration.kind.isCPUTemperature {
            return CPUTemperatureDescription.accessibilityLabel(
                title: configuration.displayTitle, state: runtime.cpuTemperature, unit: configuration.resolvedTemperatureUnit)
        }
        guard isAIUsageWidget else { return "\(configuration.displayTitle)，按回车打开配置" }
        let fiveHour = usagePercentLabel(runtime.codexUsage?.fiveHour?.remainingPercent)
        let sevenDay = usagePercentLabel(runtime.codexUsage?.sevenDay?.remainingPercent)
        let error = runtime.codexUsageError.map { "，\($0)" } ?? ""
        return "\(configuration.displayTitle)，5 小时额度剩余 \(fiveHour)，7 天额度剩余 \(sevenDay)\(error)，按回车打开配置"
    }

    private var widgetHelpDescription: String {
        if configuration.kind.isCPUTemperature {
            return CPUTemperatureDescription.help(state: runtime.cpuTemperature, unit: configuration.resolvedTemperatureUnit)
        }
        guard isAIUsageWidget else { return configuration.displayTitle }
        return runtime.codexUsageError.map { "\(configuration.displayTitle)：\($0)" }
            ?? "\(configuration.displayTitle)，本机 Codex 额度"
    }

    private func usagePercentLabel(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(Int(min(100, max(0, value)).rounded()))%"
    }
}

struct WidgetDetails: View {
    @EnvironmentObject private var store: AppStore
    let configurationID: UUID

    var body: some View {
        ObservedWidgetDetails(configurationID: configurationID, runtime: store.widgets)
    }
}

private struct ObservedWidgetDetails: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let configurationID: UUID
    @ObservedObject var runtime: WidgetRuntime
    private var configuration: DockWidgetConfiguration? {
        store.preferences.customWidgets.first { $0.id == configurationID }
    }

    var body: some View {
        Group {
            if let configuration {
                detailContent(configuration)
            } else {
                ContentUnavailableView("组件已移除", systemImage: "square.dashed")
                    .frame(width: 340, height: 150)
            }
        }
        .onChange(of: store.preferences.customWidgets.contains { $0.id == configurationID }) { _, stillExists in
            if !stillExists { store.presentedWidgetID = nil }
        }
    }

    private func detailContent(_ configuration: DockWidgetConfiguration) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                HStack(spacing: 10) {
                    Image(systemName: configuration.kind.category.symbol)
                        .font(.system(size: 17)).foregroundStyle(store.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(configuration.displayTitle).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text(configuration.kind.category.title).font(.system(size: 9)).foregroundStyle(Color.muted)
                    }
                    Spacer(minLength: 0)
                    Button("完成") { dismiss() }.buttonStyle(.glass).controlSize(.small)
                }
                Divider()
                configurationControls(configuration)
            }
            .padding(18)
        }
        .frame(width: 360, height: 440)
        .focusEffectDisabled()
    }

    @ViewBuilder
    private func configurationControls(_ configuration: DockWidgetConfiguration) -> some View {
        switch configuration.kind {
        case .clock, .timeProgress, .calendarDate, .batteryStatus, .batteryRing, .batteryIcon,
             .systemNumbers, .systemRings, .systemBars, .networkNumbers, .networkChart,
             .weatherCurrent, .weatherConditions, .weatherHourly,
             .stripeChart, .stripeNumber, .paddleChart, .paddleNumber, .shopifyChart, .shopifyNumber,
             .stock, .watchlist:
            commonTitle
            if configuration.kind.requiresExternalData { externalDataNotice(configuration.kind) }
        case .aiNumbers, .aiRings, .aiBars, .aiCapsules:
            commonTitle
            codexUsageControls
        case .worldClock:
            commonTitle
            timeZonePicker
        case .stopwatch, .focusTimer, .countdown:
            commonTitle
            timerControls(configuration)
            timerAvailabilityNote
        case .alarm:
            commonTitle
            alarmControls(configuration)
            timerAvailabilityNote
        case .hydration:
            commonTitle
            timerControls(configuration)
            timerAvailabilityNote
            hydrationControls(configuration)
        case .remindersList, .reminderNext, .reminderCount:
            commonTitle
            remindersControls
        case .calendarNext, .calendarDateNext, .calendarAgenda:
            commonTitle
            calendarControls
        case .stickyNote:
            commonTitle
            noteEditor
        case .musicFull, .musicMini:
            commonTitle
            musicControls(configuration)
        case .shortcut:
            commonTitle
            shortcutControls
        case .airDrop:
            commonTitle
            airDropControls
        case .cpuTemperatureNumber, .cpuTemperatureRing:
            commonTitle
            temperatureUnitControls
        }
    }

    private var temperatureUnitControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("单位").font(.system(size: 10, weight: .medium))
            Picker("单位", selection: Binding(
                get: { configuration?.resolvedTemperatureUnit ?? .celsius },
                set: { unit in updateConfiguration { $0.temperatureUnit = unit } }
            )) {
                Text("摄氏 °C").tag(TemperatureUnit.celsius)
                Text("华氏 °F").tag(TemperatureUnit.fahrenheit)
            }
            .pickerStyle(.segmented).labelsHidden()
            Text("温度读取自系统未公开的传感器接口，只读、不联网；读不到时显示“不可用”。")
                .font(.system(size: 9)).foregroundStyle(Color.muted)
        }
    }

    private var commonTitle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("显示名称").font(.system(size: 10, weight: .medium))
            TextField(configuration?.kind.title ?? "组件名称", text: textBinding(\.title))
                .textFieldStyle(.plain).padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .font(.system(size: 11))
        }
    }

    private var timeZonePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("时区").font(.system(size: 10, weight: .medium))
            Picker("时区", selection: textBinding(\.timeZoneIdentifier)) {
                ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { identifier in
                    Text(identifier.replacingOccurrences(of: "_", with: " ")).tag(identifier)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private func timerControls(_ configuration: DockWidgetConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("计时").font(.system(size: 10, weight: .medium))
                Spacer()
                Text(timerLabel(runtime.timerValue(configuration)))
                    .font(.system(size: 21, weight: .light, design: .rounded)).monospacedDigit()
            }
            if configuration.kind != .stopwatch {
                Stepper(value: durationMinutesBinding, in: 1...1440) {
                    Text("时长 · \(durationMinutes) 分钟").font(.system(size: 10)).monospacedDigit()
                }
            }
            HStack(spacing: 8) {
                Button(runtime.timerIsRunning(configuration.id) ? "暂停" : "开始 / 继续") {
                    runtime.toggleTimer(configuration)
                }
                .buttonStyle(.glassProminent).tint(store.accent).controlSize(.small)
                Button("重置", systemImage: "arrow.counterclockwise") {
                    runtime.resetTimer(configuration)
                }
                .buttonStyle(.glass).controlSize(.small)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }

    private var timerAvailabilityNote: some View {
        Label("GlassDock 保持运行时提供计时提醒；退出应用后不会唤醒。", systemImage: "info.circle")
            .font(.system(size: 9)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
    }

    private func alarmControls(_ configuration: DockWidgetConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DatePicker("目标时间", selection: dateBinding(\.targetDate), displayedComponents: [.date, .hourAndMinute])
                .font(.system(size: 10))
            Button(runtime.alarmIsArmed(configuration.id) ? "关闭闹钟" : "启用闹钟",
                   systemImage: runtime.alarmIsArmed(configuration.id) ? "alarm" : "alarm.fill") {
                runtime.toggleAlarm(configuration)
            }
            .buttonStyle(.glassProminent).tint(store.accent).controlSize(.small)
        }
    }

    private func hydrationControls(_ configuration: DockWidgetConfiguration) -> some View {
        let count = Calendar.current.isDate(configuration.hydrationDate, inSameDayAs: runtime.now)
            ? configuration.hydrationCount : 0
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("今日饮水").font(.system(size: 10, weight: .medium))
                    Text("\(count) 杯").font(.system(size: 15, weight: .light, design: .rounded)).monospacedDigit()
                }
                Spacer()
                Button("记录一杯", systemImage: "drop.fill") {
                    store.recordHydration(id: configuration.id)
                }
                .buttonStyle(.glass).controlSize(.small)
            }
            Text("记录会保存在本机，并按当前日期统计。")
                .font(.system(size: 9)).foregroundStyle(Color.muted)
        }
    }

    private var calendarControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            accessExplanation(title: "日历", state: runtime.calendarAccess)
            if runtime.calendarAccess == .authorized {
                if runtime.events.isEmpty {
                    Text("没有可显示的日程。日历内容只来自你授权的系统日历。")
                        .font(.system(size: 10)).foregroundStyle(Color.muted)
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(runtime.events.sorted { $0.start < $1.start }.prefix(5)), id: \.id) { event in
                            HStack(alignment: .top, spacing: 8) {
                                Text(event.start, format: .dateTime.hour().minute())
                                    .font(.system(size: 9, design: .rounded)).monospacedDigit().foregroundStyle(.secondary)
                                Text(event.title).font(.system(size: 10)).lineLimit(2)
                            }
                        }
                    }
                }
            } else {
                Button("连接系统日历", systemImage: "calendar.badge.plus") { runtime.requestCalendarAccess() }
                    .buttonStyle(.glassProminent).tint(store.accent).controlSize(.small)
                    .disabled(runtime.calendarAccess == .unavailable)
            }
        }
    }

    private var remindersControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            accessExplanation(title: "提醒事项", state: runtime.remindersAccess)
            if runtime.remindersAccess == .authorized {
                let reminders = runtime.reminders
                if reminders.isEmpty {
                    Text("没有可显示的提醒。完成操作只会更新系统提醒事项。")
                        .font(.system(size: 10)).foregroundStyle(Color.muted)
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(reminders.prefix(6)), id: \.id) { reminder in
                            HStack(spacing: 8) {
                                Image(systemName: reminder.completed ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(reminder.completed ? Color.secondary : store.accent)
                                Text(reminder.title).font(.system(size: 10)).lineLimit(1)
                                Spacer(minLength: 0)
                                if !reminder.completed {
                                    Button("完成") { runtime.completeReminder(reminder.id) }
                                        .buttonStyle(.borderless).font(.system(size: 9))
                                }
                            }
                        }
                    }
                }
            } else {
                Button("连接提醒事项", systemImage: "checklist") { runtime.requestRemindersAccess() }
                    .buttonStyle(.glassProminent).tint(store.accent).controlSize(.small)
                    .disabled(runtime.remindersAccess == .unavailable)
            }
        }
    }

    private func accessExplanation(title: String, state: WidgetAccessState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 10, weight: .medium))
            switch state {
            case .notRequested:
                Text("点击连接后，GlassDock 才会请求读取\(title)。")
                    .font(.system(size: 9)).foregroundStyle(Color.muted)
            case .authorized:
                Text("已连接 · 显示系统中的真实记录")
                    .font(.system(size: 9)).foregroundStyle(Color.muted)
            case .denied:
                Text("访问被拒绝。可在 macOS 系统设置中更改权限。")
                    .font(.system(size: 9)).foregroundStyle(Color.muted)
            case .unavailable:
                Text("此设备当前无法访问\(title)。")
                    .font(.system(size: 9)).foregroundStyle(Color.muted)
            }
        }
    }

    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("便签内容").font(.system(size: 10, weight: .medium))
            TextEditor(text: textBinding(\.text))
                .font(.system(size: 11))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 100)
                .padding(5)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
            Text("最多保存 2000 个字符，仅保存在本机。")
                .font(.system(size: 9)).foregroundStyle(Color.muted)
        }
    }

    private func musicControls(_ configuration: DockWidgetConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if runtime.music.isConnected {
                VStack(alignment: .leading, spacing: 3) {
                    Text(runtime.music.title.isEmpty ? "未提供曲目名称" : runtime.music.title)
                        .font(.system(size: 11, weight: .medium)).lineLimit(1)
                    Text(runtime.music.artist.isEmpty ? "未提供艺术家" : runtime.music.artist)
                        .font(.system(size: 9)).foregroundStyle(Color.muted).lineLimit(1)
                }
                if configuration.kind == .musicMini {
                    Button(runtime.music.isPlaying ? "暂停" : "播放",
                           systemImage: runtime.music.isPlaying ? "pause.fill" : "play.fill") {
                        runtime.playPauseMusic()
                    }
                    .buttonStyle(.glass).controlSize(.small)
                } else {
                    HStack(spacing: 12) {
                        Button("上一首", systemImage: "backward.end.fill") { runtime.previousMusicTrack() }
                        Button(runtime.music.isPlaying ? "暂停" : "播放",
                               systemImage: runtime.music.isPlaying ? "pause.fill" : "play.fill") {
                            runtime.playPauseMusic()
                        }
                        Button("下一首", systemImage: "forward.end.fill") { runtime.nextMusicTrack() }
                    }
                    .buttonStyle(.glass).controlSize(.small)
                }
            } else {
                Text(musicConnectionDescription)
                    .font(.system(size: 10)).foregroundStyle(Color.muted)
                Button("连接 Apple Music", systemImage: "music.note") { runtime.connectMusic() }
                    .buttonStyle(.glass).controlSize(.small)
            }
        }
    }

    private var musicConnectionDescription: String {
        switch runtime.musicAccess {
        case .notRequested: "连接后显示 Apple Music 当前曲目，并可控制播放。"
        case .authorized: "Apple Music 尚未连接，点击连接读取播放状态。"
        case .denied: "Apple Music 访问未授权，可点击重新连接。"
        case .unavailable: "Apple Music 当前不可用。"
        }
    }

    private var shortcutControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("快捷指令名称").font(.system(size: 10, weight: .medium))
            TextField("例如：开始专注", text: textBinding(\.shortcutName))
                .textFieldStyle(.plain).padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8)).font(.system(size: 10))
            Button("运行快捷指令", systemImage: "play.fill") {
                guard let name = configuration?.shortcutName.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return }
                runtime.runShortcut(name: name)
            }
            .buttonStyle(.glassProminent).tint(store.accent).controlSize(.small)
            .disabled(configuration?.shortcutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
            Text("运行操作只会在你点击时执行。")
                .font(.system(size: 9)).foregroundStyle(Color.muted)
        }
    }

    private var airDropControls: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("打开 macOS 隔空投送窗口，选择文件和接收对象后再发送。")
                .font(.system(size: 10)).foregroundStyle(Color.muted)
            Button("打开隔空投送", systemImage: "airdrop") { runtime.openAirDrop() }
                .buttonStyle(.glassProminent).tint(store.accent).controlSize(.small)
        }
    }

    private func externalDataNotice(_ kind: DockWidgetKind) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("数据连接").font(.system(size: 10, weight: .medium))
            Text("此样式当前显示“待配置”。GlassDock 不会生成示例实时数据，也不会收集服务账号或密钥。")
                .font(.system(size: 9)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            Text("\(kind.title) 可在数据接入完成后展示真实内容。")
                .font(.system(size: 9)).foregroundStyle(Color.muted)
        }
        .padding(11)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }

    private var codexUsageControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("本机 Codex 额度").font(.system(size: 10, weight: .medium))
            if runtime.isCodexUsageLoading {
                Text("正在读取额度…").font(.system(size: 9)).foregroundStyle(Color.muted)
            } else if let error = runtime.codexUsageError {
                Text(error).font(.system(size: 9)).foregroundStyle(Color.muted)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            } else if runtime.codexUsage == nil {
                Text("尚未连接。请先在本机安装并登录 Codex CLI，再重试读取。")
                    .font(.system(size: 9)).foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("已读取本机账号的 5 小时和 7 天额度。")
                    .font(.system(size: 9)).foregroundStyle(Color.muted)
            }
            Button("重试读取额度", systemImage: "arrow.clockwise") {
                runtime.refreshCodexUsage()
            }
            .buttonStyle(.glass).controlSize(.small).disabled(runtime.isCodexUsageLoading)
        }
        .padding(11)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }

    private var durationMinutes: Int { max(1, (configuration?.durationSeconds ?? 60) / 60) }
    private var durationMinutesBinding: Binding<Int> {
        Binding(
            get: { max(1, (configuration?.durationSeconds ?? 60) / 60) },
            set: { minutes in updateConfiguration { $0.durationSeconds = min(86_400, max(60, minutes * 60)) } }
        )
    }

    private func textBinding(_ keyPath: WritableKeyPath<DockWidgetConfiguration, String>) -> Binding<String> {
        Binding(
            get: { configuration?[keyPath: keyPath] ?? "" },
            set: { value in updateConfiguration { $0[keyPath: keyPath] = value } }
        )
    }

    private func dateBinding(_ keyPath: WritableKeyPath<DockWidgetConfiguration, Date>) -> Binding<Date> {
        Binding(
            get: { configuration?[keyPath: keyPath] ?? Date() },
            set: { value in updateConfiguration { $0[keyPath: keyPath] = value } }
        )
    }

    private func updateConfiguration(_ update: (inout DockWidgetConfiguration) -> Void) {
        guard var latest = configuration else { return }
        update(&latest)
        store.updateWidget(latest)
    }

    private func timerLabel(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded(.up)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
