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
import GlassDockCore
import Testing
@testable import GlassDock

@Suite("Widget runtime timer state")
struct WidgetRuntimeTimerTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    @Test func worldClockDateCrossesMidnightInTheSelectedTimeZone() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-10-13T00:00:00Z"))
        let shanghai = widgetDateLabel(date, timeZoneIdentifier: "Asia/Shanghai")
        let honolulu = widgetDateLabel(date, timeZoneIdentifier: "Pacific/Honolulu")
        #expect(shanghai.contains("13"))
        #expect(honolulu.contains("12"))
        #expect(shanghai != honolulu)
    }

    @Test func stopwatchAccumulatesAcrossPauseAndResume() {
        var timer = WidgetTimerState(kind: .stopwatch, duration: 60, hydrationDate: start)
        timer.toggle(at: start, duration: 60)
        #expect(timer.isRunning(at: start))
        #expect(timer.value(at: start.addingTimeInterval(5), duration: 60) == 5)

        timer.toggle(at: start.addingTimeInterval(5), duration: 60)
        #expect(!timer.isRunning(at: start.addingTimeInterval(50)))
        #expect(timer.value(at: start.addingTimeInterval(50), duration: 60) == 5)

        timer.toggle(at: start.addingTimeInterval(50), duration: 60)
        #expect(timer.value(at: start.addingTimeInterval(53), duration: 60) == 8)
    }

    @Test func countdownUsesDeadlineAndCanResumeAfterPause() {
        var timer = WidgetTimerState(kind: .countdown, duration: 10, hydrationDate: start)
        timer.toggle(at: start, duration: 10)
        #expect(timer.value(at: start.addingTimeInterval(3), duration: 10) == 7)

        timer.toggle(at: start.addingTimeInterval(3), duration: 10)
        #expect(timer.value(at: start.addingTimeInterval(80), duration: 10) == 7)
        timer.toggle(at: start.addingTimeInterval(80), duration: 10)
        let beforeDeadline = timer.tick(at: start.addingTimeInterval(86), duration: 10)
        let atDeadline = timer.tick(at: start.addingTimeInterval(87), duration: 10)
        #expect(!beforeDeadline)
        #expect(atDeadline)
        #expect(timer.value(at: start.addingTimeInterval(87), duration: 10) == 0)
        #expect(!timer.isRunning(at: start.addingTimeInterval(87)))

        timer.toggle(at: start.addingTimeInterval(87), duration: 10)
        #expect(timer.value(at: start.addingTimeInterval(88), duration: 10) == 9)
    }

    @Test func hydrationTimerRepeatsFromActualCompletionTime() {
        let lastHydration = start.addingTimeInterval(-60)
        var timer = WidgetTimerState(kind: .hydration, duration: 60, hydrationDate: lastHydration)
        #expect(timer.value(at: start, duration: 60) == 0)
        let firstReminder = timer.tick(at: start, duration: 60)
        #expect(firstReminder)
        #expect(timer.value(at: start.addingTimeInterval(1), duration: 60) == 59)
        let nextReminder = timer.tick(at: start.addingTimeInterval(120), duration: 60)
        #expect(nextReminder)
        #expect(timer.value(at: start.addingTimeInterval(121), duration: 60) == 59)
    }
}

@Suite("Widget network rate sampling")
struct WidgetNetworkRateTests {
    @Test func computesRatesFromWrappingInterfaceCounters() {
        let rates = WidgetNetworkRateSampler.rates(
            previous: WidgetNetworkCounters(received: 1_000, sent: 4_000),
            current: WidgetNetworkCounters(received: 2_000, sent: 5_000),
            elapsed: 2
        )
        #expect(rates?.downloadBytesPerSecond == 500)
        #expect(rates?.uploadBytesPerSecond == 500)

        let wrapped = WidgetNetworkRateSampler.rates(
            previous: WidgetNetworkCounters(received: UInt32.max - 10, sent: UInt32.max - 20),
            current: WidgetNetworkCounters(received: 9, sent: 19),
            elapsed: 2
        )
        #expect(wrapped?.downloadBytesPerSecond == 10)
        #expect(wrapped?.uploadBytesPerSecond == 20)
    }

    @Test func ignoresCounterResetsAndInvalidSamplingIntervals() {
        let reset = WidgetNetworkRateSampler.rates(
            previous: WidgetNetworkCounters(received: 2_000_000_000, sent: 2_000_000_000),
            current: WidgetNetworkCounters(received: 100, sent: 100),
            elapsed: 3
        )
        #expect(reset == nil)

        let invalidInterval = WidgetNetworkRateSampler.rates(
            previous: WidgetNetworkCounters(received: 0, sent: 0),
            current: WidgetNetworkCounters(received: 10, sent: 10),
            elapsed: 0
        )
        #expect(invalidInterval == nil)
    }
}

@Suite("Widget runtime defaults")
@MainActor
struct WidgetRuntimeDefaultTests {
    @Test func stopwatchPreviewStartsAtZeroBeforeItIsSynchronized() {
        let runtime = WidgetRuntime()
        let stopwatch = DockWidgetConfiguration(kind: .stopwatch)
        #expect(runtime.timerValue(stopwatch) == 0)
    }

    @Test func alarmsAreArmedOnlyAfterTheExplicitAction() {
        let runtime = WidgetRuntime()
        var alarm = DockWidgetConfiguration(kind: .alarm)
        alarm.targetDate = Date().addingTimeInterval(60)
        runtime.sync(configurations: [alarm])
        #expect(!runtime.alarmIsArmed(alarm.id))

        runtime.toggleAlarm(alarm)
        #expect(runtime.alarmIsArmed(alarm.id))
        runtime.toggleAlarm(alarm)
        #expect(!runtime.alarmIsArmed(alarm.id))
    }
}

@Suite("Widget provider ordering and polling")
struct WidgetProviderOrderingTests {
    @Test func remindersSortByDueDateBeforeTitleAndLeaveUndatedLast() {
        let now = Date(timeIntervalSince1970: 10_000)
        let reminders = [
            WidgetReminder(id: "future", title: "A future", completed: false, dueDate: now.addingTimeInterval(86_400)),
            WidgetReminder(id: "soon", title: "Z due soon", completed: false, dueDate: now.addingTimeInterval(3_600)),
            WidgetReminder(id: "undated", title: "B no date", completed: false),
            WidgetReminder(id: "done", title: "C completed", completed: true, dueDate: now)
        ]

        let orderedIDs = WidgetReminderOrdering.sorted(reminders).map(\.id)
        #expect(orderedIDs == ["soon", "future", "undated", "done"])
    }

    @Test func musicPollingRequiresConnectedWidgetsRunningMusicAndFiveSeconds() {
        let now = Date(timeIntervalSince1970: 10_000)
        #expect(!WidgetMusicPolling.shouldRefresh(
            isConnected: true,
            hasMusicWidgets: true,
            musicIsRunning: false,
            lastRefreshAt: now.addingTimeInterval(-10),
            now: now
        ))
        #expect(!WidgetMusicPolling.shouldRefresh(
            isConnected: true,
            hasMusicWidgets: true,
            musicIsRunning: true,
            lastRefreshAt: now.addingTimeInterval(-4),
            now: now
        ))
        #expect(WidgetMusicPolling.shouldRefresh(
            isConnected: true,
            hasMusicWidgets: true,
            musicIsRunning: true,
            lastRefreshAt: now.addingTimeInterval(-5),
            now: now
        ))
    }
}
