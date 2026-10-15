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
import EventKit
import Foundation
import GlassDockCore

public enum WidgetAccessState: String, Equatable, Sendable {
    case notRequested
    case authorized
    case denied
    case unavailable
}

public struct WidgetCalendarEvent: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date

    public init(id: String, title: String, start: Date, end: Date) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
    }
}

public struct WidgetReminder: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let completed: Bool
    public let dueDate: Date?

    public init(id: String, title: String, completed: Bool, dueDate: Date? = nil) {
        self.id = id
        self.title = title
        self.completed = completed
        self.dueDate = dueDate
    }
}

enum WidgetReminderOrdering {
    static func sorted(_ reminders: [WidgetReminder]) -> [WidgetReminder] {
        reminders.sorted {
            if $0.completed != $1.completed { return !$0.completed }
            switch ($0.dueDate, $1.dueDate) {
            case let (left?, right?) where left != right:
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        }
    }
}

public struct WidgetMusicState: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var isPlaying: Bool
    public var position: Double
    public var duration: Double
    public var isConnected: Bool
    public var currentTrackIdentity: String?
    public var artworkData: Data?
    public var positionUpdatedAt: Date?

    public init(
        title: String = "",
        artist: String = "",
        isPlaying: Bool = false,
        position: Double = 0,
        duration: Double = 0,
        isConnected: Bool = false,
        currentTrackIdentity: String? = nil,
        artworkData: Data? = nil,
        positionUpdatedAt: Date? = nil
    ) {
        self.title = title
        self.artist = artist
        self.isPlaying = isPlaying
        self.position = position
        self.duration = duration
        self.isConnected = isConnected
        self.currentTrackIdentity = currentTrackIdentity
        self.artworkData = artworkData
        self.positionUpdatedAt = positionUpdatedAt
    }
}

@MainActor
public final class WidgetRuntime: ObservableObject {
    @Published public private(set) var now = Date()
    @Published public private(set) var metrics = WidgetSystemMetrics.empty
    @Published public private(set) var cpuTemperature: CPUTemperatureState = .sampling
    @Published public private(set) var events: [WidgetCalendarEvent] = []
    @Published public private(set) var reminders: [WidgetReminder] = []
    @Published public private(set) var calendarAccess: WidgetAccessState
    @Published public private(set) var remindersAccess: WidgetAccessState
    @Published public private(set) var musicAccess: WidgetAccessState = .notRequested
    @Published public private(set) var music = WidgetMusicState()
    @Published public private(set) var codexUsage: CodexUsageSnapshot?
    @Published public private(set) var codexUsageError: String?
    @Published public private(set) var isCodexUsageLoading = false
    @Published public var errorMessage: String?
    @Published public var alertMessage: String?

    private let eventStore = EKEventStore()
    private let metricsProvider = WidgetSystemMetricsProvider()
    /// 独立于系统活动指标：2 秒一次、后台队列读取，仅在有温度组件时运行。
    private lazy var temperatureSampler = CPUTemperatureSampler { [weak self] state in
        guard let self, self.cpuTemperature != state else { return }
        self.cpuTemperature = state
    }
    private let codexUsageClient = CodexUsageClient()
    private var clockTimer: Timer?
    private var activeConfigurations: [UUID: DockWidgetConfiguration] = [:]
    private var timerStates: [UUID: WidgetTimerState] = [:]
    private var alarmDeadlines: [UUID: Date] = [:]
    private var hasMetricWidgets = false
    private var hasBatteryWidgets = false
    private var lastMetricsSampleAt: Date?
    private var lastCalendarRefreshAt: Date?
    private var lastReminderRefreshAt: Date?
    private var lastMusicRefreshAt: Date?
    private var lastCodexUsageRefreshAt: Date?
    private var codexUsageRevision = 0
    private(set) var cachedArtworkTrackIdentity: String?
    private var musicOperationRevision = 0
    private var musicQueryInFlightRevision: Int?
    private var pendingMusicCommands: [MusicAppleScriptBridge.Command] = []
    private var musicCommandInFlight = false

    public init() {
        calendarAccess = Self.accessState(for: .event)
        remindersAccess = Self.accessState(for: .reminder)
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        if let clockTimer { RunLoop.main.add(clockTimer, forMode: .common) }
    }

    deinit {
        clockTimer?.invalidate()
        codexUsageClient.cancel()
    }

    public var musicPosition: Double {
        let elapsed = music.isPlaying ? max(0, now.timeIntervalSince(music.positionUpdatedAt ?? now)) : 0
        let position = max(0, music.position + elapsed)
        return music.duration > 0 ? min(music.duration, position) : position
    }

    /// Synchronize the active Dock widgets and discard state for removed widgets.
    public func sync(configurations: [DockWidgetConfiguration]) {
        let nextConfigurations = Dictionary(configurations.map { ($0.id, $0) }, uniquingKeysWith: { _, next in next })
        guard nextConfigurations != activeConfigurations else { return }
        let hadMetricWidgets = hasMetricWidgets
        let hadMusicWidgets = activeConfigurations.values.contains { $0.kind == .musicFull || $0.kind == .musicMini }
        let hadCodexUsageWidgets = Self.hasCodexUsageWidgets(activeConfigurations.values)

        for (id, configuration) in nextConfigurations {
            let previous = activeConfigurations[id]
            if configuration.kind.isTimer {
                let durationChanged = previous?.kind == configuration.kind
                    && previous?.durationSeconds != configuration.durationSeconds
                let hydrationDateChanged = previous?.kind == .hydration
                    && configuration.kind == .hydration
                    && previous?.hydrationDate != configuration.hydrationDate
                if timerStates[id] == nil || previous?.kind != configuration.kind || durationChanged || hydrationDateChanged {
                    timerStates[id] = WidgetTimerState(
                        kind: configuration.kind,
                        duration: TimeInterval(configuration.durationSeconds),
                        hydrationDate: configuration.hydrationDate
                    )
                }
            } else {
                timerStates.removeValue(forKey: id)
            }

            if configuration.kind == .alarm {
                if previous?.kind == .alarm, previous?.targetDate != configuration.targetDate {
                    if alarmDeadlines[id] != nil, configuration.targetDate > now {
                        alarmDeadlines[id] = configuration.targetDate
                    } else if configuration.targetDate <= now {
                        alarmDeadlines.removeValue(forKey: id)
                    }
                }
            } else {
                alarmDeadlines.removeValue(forKey: id)
            }
        }

        let activeIDs = Set(nextConfigurations.keys)
        timerStates = timerStates.filter { activeIDs.contains($0.key) }
        alarmDeadlines = alarmDeadlines.filter { activeIDs.contains($0.key) }
        activeConfigurations = nextConfigurations

        let hasCodexUsageWidgets = Self.hasCodexUsageWidgets(nextConfigurations.values)
        if hasCodexUsageWidgets, !hadCodexUsageWidgets {
            refreshCodexUsage()
        } else if !hasCodexUsageWidgets, hadCodexUsageWidgets {
            codexUsageRevision += 1
            codexUsageClient.cancel()
            codexUsage = nil
            codexUsageError = nil
            isCodexUsageLoading = false
            lastCodexUsageRefreshAt = nil
        }

        if configurations.contains(where: \.kind.isCPUTemperature) {
            temperatureSampler.start()
        } else if temperatureSampler.isRunning {
            temperatureSampler.stop()
        }
        hasMetricWidgets = configurations.contains { Self.usesSystemMetrics($0.kind) }
        hasBatteryWidgets = configurations.contains { Self.usesBatteryMetrics($0.kind) }
        if hasMetricWidgets { sampleMetrics(force: !hadMetricWidgets) }
        else {
            metrics = .empty
            lastMetricsSampleAt = nil
            metricsProvider.reset()
        }
        let hasMusicWidgets = configurations.contains { $0.kind == .musicFull || $0.kind == .musicMini }
        if !hasMusicWidgets {
            if hadMusicWidgets {
                musicOperationRevision += 1
                pendingMusicCommands.removeAll()
            }
            music = WidgetMusicState()
            lastMusicRefreshAt = nil
            cachedArtworkTrackIdentity = nil
        }
        if !configurations.contains(where: { $0.kind.requiresCalendarAccess }) { events = [] }
        if !configurations.contains(where: { $0.kind.requiresRemindersAccess }) { reminders = [] }
        if calendarAccess == .authorized, configurations.contains(where: { $0.kind.requiresCalendarAccess }) {
            refreshCalendarEvents()
        }
        if remindersAccess == .authorized, configurations.contains(where: { $0.kind.requiresRemindersAccess }) {
            refreshReminders()
        }
        if hasMusicWidgets, !hadMusicWidgets { refreshMusicSnapshot(askUserIfNeeded: false) }
    }

    public func timerValue(_ configuration: DockWidgetConfiguration) -> TimeInterval {
        guard configuration.kind.isTimer else { return 0 }
        return timerStates[configuration.id]?.value(at: now, duration: TimeInterval(configuration.durationSeconds))
            ?? (configuration.kind == .stopwatch ? 0 : TimeInterval(configuration.durationSeconds))
    }

    public func timerIsRunning(_ id: UUID) -> Bool {
        timerStates[id]?.isRunning(at: now) ?? false
    }

    public func toggleTimer(_ configuration: DockWidgetConfiguration) {
        guard configuration.kind.isTimer else { return }
        let interactionDate = Date()
        now = interactionDate
        var state = timerStates[configuration.id] ?? WidgetTimerState(
            kind: configuration.kind,
            duration: TimeInterval(configuration.durationSeconds),
            hydrationDate: configuration.hydrationDate
        )
        state.toggle(at: interactionDate, duration: TimeInterval(configuration.durationSeconds))
        timerStates[configuration.id] = state
    }

    public func resetTimer(_ configuration: DockWidgetConfiguration) {
        guard configuration.kind.isTimer else { return }
        let interactionDate = Date()
        now = interactionDate
        var state = timerStates[configuration.id] ?? WidgetTimerState(
            kind: configuration.kind,
            duration: TimeInterval(configuration.durationSeconds),
            hydrationDate: configuration.hydrationDate
        )
        state.reset(at: interactionDate, duration: TimeInterval(configuration.durationSeconds))
        timerStates[configuration.id] = state
    }

    public func alarmIsArmed(_ id: UUID) -> Bool {
        guard let deadline = alarmDeadlines[id] else { return false }
        return deadline > now
    }

    public func toggleAlarm(_ configuration: DockWidgetConfiguration) {
        guard configuration.kind == .alarm else { return }
        if alarmDeadlines.removeValue(forKey: configuration.id) != nil { return }
        let interactionDate = Date()
        now = interactionDate
        guard configuration.targetDate > interactionDate else {
            errorMessage = "闹钟时间已过，请先修改目标时间。"
            return
        }
        alarmDeadlines[configuration.id] = configuration.targetDate
        errorMessage = nil
    }

    /// Request EventKit full calendar access only after the user invokes this action.
    public func requestCalendarAccess() {
        switch calendarAccess {
        case .authorized:
            refreshCalendarEvents()
        case .denied:
            errorMessage = "日历访问已关闭，可在系统设置的隐私与安全性中重新允许。"
        case .unavailable:
            errorMessage = "当前系统无法读取日历。"
        case .notRequested:
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let granted = try await eventStore.requestFullAccessToEvents()
                    calendarAccess = granted ? .authorized : .denied
                    if granted {
                        errorMessage = nil
                        refreshCalendarEvents()
                    } else {
                        events = []
                        errorMessage = "未获得日历访问权限。"
                    }
                } catch {
                    calendarAccess = Self.accessState(for: .event)
                    errorMessage = "无法读取日历：\(error.localizedDescription)"
                }
            }
        }
    }

    /// Request EventKit full reminders access only after the user invokes this action.
    public func requestRemindersAccess() {
        switch remindersAccess {
        case .authorized:
            refreshReminders()
        case .denied:
            errorMessage = "提醒事项访问已关闭，可在系统设置的隐私与安全性中重新允许。"
        case .unavailable:
            errorMessage = "当前系统无法读取提醒事项。"
        case .notRequested:
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let granted = try await eventStore.requestFullAccessToReminders()
                    remindersAccess = granted ? .authorized : .denied
                    if granted {
                        errorMessage = nil
                        refreshReminders()
                    } else {
                        reminders = []
                        errorMessage = "未获得提醒事项访问权限。"
                    }
                } catch {
                    remindersAccess = Self.accessState(for: .reminder)
                    errorMessage = "无法读取提醒事项：\(error.localizedDescription)"
                }
            }
        }
    }

    public func refreshCalendarEvents() {
        guard calendarAccess == .authorized,
              activeConfigurations.values.contains(where: { $0.kind.requiresCalendarAccess }) else { return }
        let end = Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now.addingTimeInterval(30 * 86_400)
        let predicate = eventStore.predicateForEvents(withStart: now, end: end, calendars: nil)
        events = eventStore.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .prefix(50)
            .map { event in
                WidgetCalendarEvent(
                    id: event.eventIdentifier ?? event.calendarItemIdentifier,
                    title: event.title.flatMap { $0.isEmpty ? nil : $0 } ?? "（无标题日程）",
                    start: event.startDate,
                    end: event.endDate
                )
            }
        lastCalendarRefreshAt = now
    }

    public func refreshCodexUsage() {
        startCodexUsageRefresh(force: true)
    }

    private func refreshCodexUsageIfDue() {
        startCodexUsageRefresh(force: false)
    }

    private func startCodexUsageRefresh(force: Bool) {
        guard Self.hasCodexUsageWidgets(activeConfigurations.values),
              !isCodexUsageLoading else { return }
        let requestDate = Date()
        guard force || (lastCodexUsageRefreshAt.map({ requestDate.timeIntervalSince($0) >= 60 }) ?? true) else { return }

        lastCodexUsageRefreshAt = requestDate
        isCodexUsageLoading = true
        codexUsageRevision += 1
        let revision = codexUsageRevision
        codexUsageClient.fetch { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self,
                      self.codexUsageRevision == revision,
                      Self.hasCodexUsageWidgets(self.activeConfigurations.values) else { return }
                self.isCodexUsageLoading = false
                switch result {
                case let .success(snapshot):
                    self.codexUsage = snapshot
                    self.codexUsageError = nil
                case let .failure(error):
                    self.codexUsage = nil
                    self.codexUsageError = Self.codexUsageMessage(for: error)
                }
            }
        }
    }

    public func refreshReminders() {
        guard remindersAccess == .authorized,
              activeConfigurations.values.contains(where: { $0.kind.requiresRemindersAccess }) else { return }
        let predicate = eventStore.predicateForReminders(in: nil)
        eventStore.fetchReminders(matching: predicate) { [weak self] fetchedReminders in
            let values = (fetchedReminders ?? []).map { reminder in
                let dueDate = reminder.dueDateComponents.flatMap { dueComponents in
                    var components = dueComponents
                    if components.calendar == nil { components.calendar = .current }
                    return components.calendar?.date(from: components)
                }
                return WidgetReminder(
                    id: reminder.calendarItemIdentifier,
                    title: reminder.title.flatMap { $0.isEmpty ? nil : $0 } ?? "（无标题提醒）",
                    completed: reminder.isCompleted,
                    dueDate: dueDate
                )
            }
            let sortedValues = WidgetReminderOrdering.sorted(values)
            Task { @MainActor [weak self] in
                guard let self,
                      activeConfigurations.values.contains(where: { $0.kind.requiresRemindersAccess }) else { return }
                reminders = sortedValues
                lastReminderRefreshAt = now
            }
        }
    }

    /// Mark a reminder complete only in response to an explicit user action.
    public func completeReminder(_ id: String) {
        guard remindersAccess == .authorized else {
            errorMessage = "请先开启提醒事项访问权限。"
            return
        }
        guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
            errorMessage = "找不到这条提醒事项，列表将重新加载。"
            refreshReminders()
            return
        }
        reminder.isCompleted = true
        reminder.completionDate = now
        do {
            try eventStore.save(reminder, commit: true)
            errorMessage = nil
            refreshReminders()
        } catch {
            errorMessage = "无法完成提醒事项：\(error.localizedDescription)"
        }
    }

    /// Connect to Music after an explicit user action and request automation access if needed.
    public func connectMusic() {
        guard isMusicRunning else {
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") else {
                errorMessage = "找不到音乐 App，请确认它已安装。"
                return
            }
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let error {
                        errorMessage = "无法打开音乐 App：\(error.localizedDescription)"
                    } else {
                        guard await waitForMusicToStart() else {
                            errorMessage = "音乐 App 尚未启动，请稍后重试。"
                            return
                        }
                        refreshMusicSnapshot(askUserIfNeeded: true)
                    }
                }
            }
            return
        }
        refreshMusicSnapshot(askUserIfNeeded: true)
    }

    public func playPauseMusic() { performMusicCommand(.playPause) }
    public func nextMusicTrack() { performMusicCommand(.nextTrack) }
    public func previousMusicTrack() { performMusicCommand(.previousTrack) }

    /// Run the named shortcut through the public Shortcuts URL scheme without a shell.
    public func runShortcut(name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "请先为快捷指令组件填写名称。"
            return
        }
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "run-shortcut"
        components.queryItems = [URLQueryItem(name: "name", value: trimmedName)]
        guard let url = components.url, NSWorkspace.shared.open(url) else {
            errorMessage = "无法打开快捷指令“\(trimmedName)”，请检查名称并确认快捷指令 App 可用。"
            return
        }
        errorMessage = nil
    }

    /// Present a file picker, then invoke the public AirDrop sharing service for the chosen files.
    public func openAirDrop() {
        let panel = NSOpenPanel()
        panel.title = "选择要通过隔空投送发送的文件"
        panel.prompt = "选择"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.begin { [weak self] response in
            guard response == .OK, !panel.urls.isEmpty else { return }
            guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: panel.urls) else {
                Task { @MainActor [weak self] in self?.errorMessage = "隔空投送当前不可用，请检查 Wi-Fi、蓝牙和接收设置。" }
                return
            }
            service.perform(withItems: panel.urls)
        }
    }

    private var isMusicRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").contains { !$0.isTerminated }
    }

    private func performMusicCommand(_ command: MusicAppleScriptBridge.Command) {
        guard isMusicRunning else {
            disconnectClosedMusic()
            errorMessage = "请先打开音乐 App，再点击连接音乐。"
            return
        }
        pendingMusicCommands.append(command)
        processNextMusicCommand()
    }

    private func processNextMusicCommand() {
        guard !musicCommandInFlight, !pendingMusicCommands.isEmpty else { return }
        guard isMusicRunning else {
            pendingMusicCommands.removeAll()
            disconnectClosedMusic()
            errorMessage = "音乐 App 已关闭，播放控制已取消。"
            return
        }
        let command = pendingMusicCommands.removeFirst()
        musicCommandInFlight = true
        let revision = nextMusicOperationRevision()
        let knownArtworkTrackIdentity = cachedArtworkTrackIdentity
        Task { @MainActor [weak self] in
            let response = await Task.detached(priority: .userInitiated) {
                MusicAppleScriptBridge.performAndQuery(command, knownArtworkTrackIdentity: knownArtworkTrackIdentity)
            }.value
            guard let self else { return }
            musicCommandInFlight = false
            if WidgetMusicPolling.isLatestResponse(revision, latestRevision: musicOperationRevision),
               activeConfigurations.values.contains(where: { $0.kind == .musicFull || $0.kind == .musicMini }) {
                applyMusicResponse(response, showErrors: true)
                if response.snapshot != nil { lastMusicRefreshAt = now }
            }
            processNextMusicCommand()
        }
    }

    private func refreshMusicSnapshot(askUserIfNeeded: Bool) {
        guard activeConfigurations.values.contains(where: { $0.kind == .musicFull || $0.kind == .musicMini }) else { return }
        if !askUserIfNeeded,
           !WidgetMusicPolling.canStartAutomaticRefresh(
               queryInFlight: musicQueryInFlightRevision != nil,
               commandInFlight: musicCommandInFlight,
               pendingCommandCount: pendingMusicCommands.count
           ) { return }
        guard isMusicRunning else {
            if music.isConnected { disconnectClosedMusic() }
            return
        }
        lastMusicRefreshAt = now
        let revision = nextMusicOperationRevision()
        musicQueryInFlightRevision = revision
        let knownArtworkTrackIdentity = cachedArtworkTrackIdentity
        Task { @MainActor [weak self] in
            let response = await Task.detached(priority: askUserIfNeeded ? .userInitiated : .utility) {
                MusicAppleScriptBridge.query(
                    askUserIfNeeded: askUserIfNeeded,
                    knownArtworkTrackIdentity: knownArtworkTrackIdentity
                )
            }.value
            guard let self else { return }
            if musicQueryInFlightRevision == revision { musicQueryInFlightRevision = nil }
            guard WidgetMusicPolling.isLatestResponse(revision, latestRevision: musicOperationRevision),
                  activeConfigurations.values.contains(where: { $0.kind == .musicFull || $0.kind == .musicMini }) else { return }
            applyMusicResponse(response, showErrors: askUserIfNeeded)
        }
    }

    private func disconnectClosedMusic() {
        music.isConnected = false
        lastMusicRefreshAt = nil
        errorMessage = "音乐 App 已关闭，音乐组件已断开连接。"
    }

    func applyMusicResponse(_ response: MusicAppleScriptBridge.Response, showErrors: Bool) {
        musicAccess = response.access
        guard response.access == .authorized else {
            music.isConnected = false
            if showErrors { applyMusicError(response) }
            return
        }
        guard var snapshot = response.snapshot else {
            if let errorNumber = response.errorNumber, errorNumber == -1743 { musicAccess = .denied }
            if showErrors { applyMusicError(response) }
            return
        }

        let sameTrack = snapshot.currentTrackIdentity == music.currentTrackIdentity
        if sameTrack, snapshot.artworkData == nil {
            snapshot.artworkData = music.artworkData
        }
        music = snapshot
        if !sameTrack { cachedArtworkTrackIdentity = nil }
        if snapshot.currentTrackIdentity == nil {
            cachedArtworkTrackIdentity = nil
        } else if snapshot.artworkData != nil, let artworkLookupTrackIdentity = response.artworkLookupTrackIdentity {
            cachedArtworkTrackIdentity = artworkLookupTrackIdentity
        }
        errorMessage = nil
    }

    private func applyMusicError(_ response: MusicAppleScriptBridge.Response) {
        if response.errorNumber == -1743 {
            errorMessage = "请在系统设置的隐私与安全性 → 自动化中允许 GlassDock 控制音乐 App。"
        } else if response.access == .notRequested {
            errorMessage = "尚未获得音乐自动化权限，请重新连接音乐并允许控制。"
        } else if response.access == .unavailable {
            errorMessage = "音乐 App 暂不可用，请确认音乐 App 正在运行。"
        } else {
            errorMessage = response.errorMessage.map { "音乐 App 暂不可用：\($0)" } ?? "音乐 App 未返回可用信息。"
        }
    }

    private func waitForMusicToStart() async -> Bool {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if isMusicRunning { return true }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return isMusicRunning
    }

    private func nextMusicOperationRevision() -> Int {
        musicOperationRevision += 1
        return musicOperationRevision
    }

    private static func hasCodexUsageWidgets<S: Sequence>(_ configurations: S) -> Bool where S.Element == DockWidgetConfiguration {
        configurations.contains { $0.kind.category == .ai }
    }

    private static func codexUsageMessage(for error: CodexUsageClientError) -> String {
        switch error {
        case .unavailable:
            "未找到 Codex 命令行工具。"
        case .launchFailed:
            "无法启动 Codex 额度读取服务。"
        case .timedOut:
            "读取 Codex 额度超时。"
        case .cancelled:
            "Codex 额度读取已取消。"
        case .protocolError:
            "Codex 额度读取连接中断。"
        case .invalidResponse:
            "Codex 未返回可用的额度数据。"
        }
    }

    private func tick() {
        now = Date()
        var completedMessages: [String] = []

        for (id, configuration) in activeConfigurations where configuration.kind.isTimer {
            guard var state = timerStates[id], state.tick(at: now, duration: TimeInterval(configuration.durationSeconds)) else { continue }
            timerStates[id] = state
            completedMessages.append(configuration.kind == .hydration ? "喝水时间到了" : "\(configuration.displayTitle) 已完成")
        }

        for (id, deadline) in Array(alarmDeadlines) where deadline <= now {
            alarmDeadlines.removeValue(forKey: id)
            let title = activeConfigurations[id]?.displayTitle ?? "闹钟"
            completedMessages.append("\(title) 时间到了")
        }

        if !completedMessages.isEmpty { presentUserAlert(completedMessages.joined(separator: "、")) }
        if hasMetricWidgets, lastMetricsSampleAt.map({ now.timeIntervalSince($0) >= 3 }) ?? true {
            sampleMetrics(force: false)
        }
        if calendarAccess == .authorized,
           activeConfigurations.values.contains(where: { $0.kind.requiresCalendarAccess }),
           lastCalendarRefreshAt.map({ now.timeIntervalSince($0) >= 60 }) ?? true {
            refreshCalendarEvents()
        }
        if remindersAccess == .authorized,
           activeConfigurations.values.contains(where: { $0.kind.requiresRemindersAccess }),
           lastReminderRefreshAt.map({ now.timeIntervalSince($0) >= 60 }) ?? true {
            refreshReminders()
        }
        if Self.hasCodexUsageWidgets(activeConfigurations.values) { refreshCodexUsageIfDue() }
        let hasMusicWidgets = activeConfigurations.values.contains { $0.kind == .musicFull || $0.kind == .musicMini }
        if hasMusicWidgets, isMusicRunning,
           WidgetMusicPolling.shouldCheckPermissionOrRefresh(
               hasMusicWidgets: true,
               musicIsRunning: true,
               lastRefreshAt: lastMusicRefreshAt,
               now: now
           ) {
            refreshMusicSnapshot(askUserIfNeeded: false)
        } else if hasMusicWidgets, music.isConnected, !isMusicRunning {
            disconnectClosedMusic()
        }
    }

    private func sampleMetrics(force: Bool) {
        guard hasMetricWidgets else { return }
        guard force || lastMetricsSampleAt.map({ now.timeIntervalSince($0) >= 3 }) ?? true else { return }
        metrics = metricsProvider.sample(at: now, includeBattery: hasBatteryWidgets)
        lastMetricsSampleAt = now
    }

    private func presentUserAlert(_ message: String) {
        alertMessage = message
        NSSound.beep()
    }

    private static func accessState(for entityType: EKEntityType) -> WidgetAccessState {
        switch EKEventStore.authorizationStatus(for: entityType) {
        case .notDetermined: .notRequested
        case .fullAccess: .authorized
        case .denied, .restricted: .denied
        case .writeOnly: .unavailable
        @unknown default: .unavailable
        }
    }

    private static func usesSystemMetrics(_ kind: DockWidgetKind) -> Bool {
        switch kind {
        case .batteryStatus, .batteryRing, .batteryIcon,
             .systemNumbers, .systemRings, .systemBars, .networkNumbers, .networkChart:
            true
        default:
            false
        }
    }

    private static func usesBatteryMetrics(_ kind: DockWidgetKind) -> Bool {
        [.batteryStatus, .batteryRing, .batteryIcon].contains(kind)
    }
}

struct WidgetTimerState: Equatable {
    let kind: DockWidgetKind
    private(set) var stopwatchElapsed: TimeInterval = 0
    private(set) var stopwatchStartedAt: Date?
    private(set) var countdownDeadline: Date?
    private(set) var pausedRemaining: TimeInterval?
    private(set) var completed = false

    init(kind: DockWidgetKind, duration: TimeInterval, hydrationDate: Date) {
        self.kind = kind
        if kind == .hydration { countdownDeadline = hydrationDate.addingTimeInterval(duration) }
    }

    func isRunning(at date: Date) -> Bool {
        if kind == .stopwatch { return stopwatchStartedAt != nil }
        guard let countdownDeadline else { return false }
        return countdownDeadline > date
    }

    func value(at date: Date, duration: TimeInterval) -> TimeInterval {
        if kind == .stopwatch {
            return max(0, stopwatchElapsed + (stopwatchStartedAt.map { date.timeIntervalSince($0) } ?? 0))
        }
        if let countdownDeadline { return max(0, countdownDeadline.timeIntervalSince(date)) }
        if let pausedRemaining { return max(0, pausedRemaining) }
        return completed ? 0 : max(0, duration)
    }

    mutating func toggle(at date: Date, duration: TimeInterval) {
        if kind == .stopwatch {
            if let stopwatchStartedAt {
                stopwatchElapsed += max(0, date.timeIntervalSince(stopwatchStartedAt))
                self.stopwatchStartedAt = nil
            } else {
                stopwatchStartedAt = date
            }
            return
        }

        if let countdownDeadline {
            let remaining = max(0, countdownDeadline.timeIntervalSince(date))
            self.countdownDeadline = nil
            pausedRemaining = remaining
            completed = remaining == 0
        } else {
            let remaining = completed ? duration : (pausedRemaining ?? duration)
            guard remaining > 0 else { return }
            countdownDeadline = date.addingTimeInterval(remaining)
            pausedRemaining = nil
            completed = false
        }
    }

    mutating func reset(at date: Date, duration: TimeInterval) {
        stopwatchElapsed = 0
        stopwatchStartedAt = nil
        pausedRemaining = nil
        completed = false
        countdownDeadline = kind == .hydration ? date.addingTimeInterval(duration) : nil
    }

    /// Use absolute deadlines so sleep/wake and missed ticks do not drift timer duration.
    mutating func tick(at date: Date, duration: TimeInterval) -> Bool {
        guard kind != .stopwatch, let countdownDeadline, date >= countdownDeadline else { return false }
        if kind == .hydration {
            self.countdownDeadline = date.addingTimeInterval(duration)
            pausedRemaining = nil
            completed = false
        } else {
            self.countdownDeadline = nil
            pausedRemaining = 0
            completed = true
        }
        return true
    }
}

enum WidgetMusicPolling {
    static func canStartAutomaticRefresh(queryInFlight: Bool, commandInFlight: Bool, pendingCommandCount: Int) -> Bool {
        !queryInFlight && !commandInFlight && pendingCommandCount == 0
    }

    static func isLatestResponse(_ responseRevision: Int, latestRevision: Int) -> Bool {
        responseRevision == latestRevision
    }

    static func shouldRefresh(
        isConnected: Bool,
        hasMusicWidgets: Bool,
        musicIsRunning: Bool,
        lastRefreshAt: Date?,
        now: Date
    ) -> Bool {
        guard isConnected, hasMusicWidgets, musicIsRunning else { return false }
        return lastRefreshAt.map { now.timeIntervalSince($0) >= 5 } ?? true
    }

    static func shouldCheckPermissionOrRefresh(
        hasMusicWidgets: Bool,
        musicIsRunning: Bool,
        lastRefreshAt: Date?,
        now: Date
    ) -> Bool {
        guard hasMusicWidgets, musicIsRunning else { return false }
        return lastRefreshAt.map { now.timeIntervalSince($0) >= 5 } ?? true
    }
}
