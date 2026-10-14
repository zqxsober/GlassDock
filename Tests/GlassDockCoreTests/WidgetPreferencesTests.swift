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

@Suite("Widget catalog and migration")
struct WidgetPreferencesTests {
    @Test func catalogIncludesAllDocksetLayoutsWithStableUniqueIdentifiers() {
        #expect(DockWidgetKind.allCases.count == 43)
        #expect(Set(DockWidgetKind.allCases.map(\.rawValue)).count == 43)
        #expect(Set(DockWidgetKind.allCases.map(\.category)) == Set(DockWidgetCategory.allCases))
        #expect(DockWidgetKind.availableKinds.count == 35)
        #expect(Set(DockWidgetKind.availableKinds.map(\.category)) == Set(DockWidgetCategory.availableCategories))
        #expect(!DockWidgetKind.availableKinds.contains { [.business, .stocks].contains($0.category) })
        #expect(DockWidgetKind.allCases.filter(\.requiresExternalData).count == 15)
    }

    @Test func aiLayoutsUseTheirOwnCategoryAndKeepStableIdentifiers() {
        #expect(DockWidgetCategory.ai.rawValue == "ai")
        #expect(DockWidgetCategory.ai.title == "AI")
        #expect(Set(DockWidgetKind.allCases.filter { $0.category == .ai }) == [.aiNumbers, .aiRings, .aiBars, .aiCapsules])
        #expect(DockWidgetKind.aiNumbers.rawValue == "aiNumbers")
        #expect(DockWidgetKind.aiRings.rawValue == "aiRings")
        #expect(DockWidgetKind.aiBars.rawValue == "aiBars")
        #expect(DockWidgetKind.aiCapsules.rawValue == "aiCapsules")
        #expect(DockWidgetKind.aiCapsules.title == "AI 额度 · 胶囊")
        #expect(DockWidgetKind.aiCapsules.category == .ai)
        #expect(DockWidgetKind.aiCapsules.preferredWidth == 220)
        #expect(DockWidgetKind.aiCapsules.requiresExternalData)
        #expect(DockWidgetKind.allCases.count == 43)
    }

    @Test func oldSettingsKeepAppsAndChoicesWithoutNewFields() throws {
        let legacy = Data("""
        {"applications":[{"name":"Safari","path":"/Applications/Safari.app"}],
         "iconSize":24,"verticalSpacing":0,"magnification":false,"showClock":false,
         "showFocus":false,"showBattery":true,"showDockOnLaunch":false,"accent":"rose","focusMinutes":40}
        """.utf8)
        let preferences = try JSONDecoder().decode(DockPreferences.self, from: legacy)
        #expect(preferences.cornerRadius == 26)
        #expect(preferences.customWidgets.isEmpty)
        #expect(preferences.iconSize == 24 && preferences.verticalSpacing == 0)
        #expect(preferences.applications.first?.kind == .application)
        #expect(preferences.applications.first?.name == "Safari")
        #expect(preferences.accent == .rose && !preferences.showClock && preferences.showBattery)
        #expect(!preferences.showDockOnLaunch && preferences.focusMinutes == 40)
    }

    @Test func folderAndEveryWidgetConfigurationSurviveRoundTrip() throws {
        var preferences = DockPreferences()
        preferences.applications = [PinnedApplication(name: "项目", path: "/Users/example/Projects", kind: .folder)]
        preferences.customWidgets = DockWidgetKind.allCases.map { kind in
            var widget = DockWidgetConfiguration(kind: kind)
            widget.title = "我的\(kind.title)"
            widget.text = "一条本地便签\n第二行"
            widget.shortcutName = "含空格 & 中文的快捷指令"
            widget.timeZoneIdentifier = "Europe/London"
            return widget
        }
        let data = try JSONEncoder().encode(preferences)
        let restored = try JSONDecoder().decode(DockPreferences.self, from: data)
        #expect(restored == preferences)
        #expect(restored.customWidgets.map(\.id) == preferences.customWidgets.map(\.id))
    }

    @Test func normalizationDeduplicatesWidgetIdsAndProtectsEditableLimits() {
        var widget = DockWidgetConfiguration(kind: .countdown)
        widget.durationSeconds = -4
        widget.hydrationCount = -1
        widget.timeZoneIdentifier = "Not/A_Real_Zone"
        widget.text = String(repeating: "便", count: 2100)
        var preferences = DockPreferences()
        preferences.customWidgets = [widget, widget]
        preferences.normalize()
        #expect(preferences.customWidgets.count == 1)
        #expect(preferences.customWidgets[0].durationSeconds == 1)
        #expect(preferences.customWidgets[0].hydrationCount == 0)
        #expect(preferences.customWidgets[0].text.count == 2000)
        #expect(TimeZone(identifier: preferences.customWidgets[0].timeZoneIdentifier) != nil)
    }

    @Test func removingLegacyBusinessWidgetsPreservesPinsAndAvailableWidgets() throws {
        var preferences = DockPreferences()
        preferences.applications = [PinnedApplication(name: "Safari", path: "/Applications/Safari.app")]
        let clock = DockWidgetConfiguration(kind: .clock)
        let stripe = DockWidgetConfiguration(kind: .stripeChart)
        let stock = DockWidgetConfiguration(kind: .stock)
        let shopify = DockWidgetConfiguration(kind: .shopifyNumber)
        preferences.customWidgets = [clock, stripe, stock, shopify]

        let previousSettings = try JSONEncoder().encode(preferences)
        var loaded = try JSONDecoder().decode(DockPreferences.self, from: previousSettings)
        #expect(loaded.customWidgets.map(\.kind) == [.clock, .stripeChart, .stock, .shopifyNumber])

        loaded.normalize()
        let savedAgain = try JSONEncoder().encode(loaded)
        let restored = try JSONDecoder().decode(DockPreferences.self, from: savedAgain)

        #expect(restored.applications == preferences.applications)
        #expect(restored.customWidgets == [clock])
    }

    @Test func yearProgressUsesLeapYearCalendarDuration() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let start = try #require(calendar.date(from: DateComponents(year: 2024, month: 1, day: 1)))
        let halfway = start.addingTimeInterval(183 * 86_400)
        #expect(DockWidgetConfiguration.yearProgress(at: start, calendar: calendar) == 0)
        #expect(abs(DockWidgetConfiguration.yearProgress(at: halfway, calendar: calendar) - 0.5) < 0.00001)
    }
}
