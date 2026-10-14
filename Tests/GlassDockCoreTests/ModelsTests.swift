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
import GlassDockCore

@Suite("Pinned applications")
struct PinnedApplicationTests {
    private func app(_ index: Int) -> PinnedApplication {
        PinnedApplication(name: "App \(index)", path: "/Applications/App\(index).app")
    }

    private func folder(_ index: Int) -> PinnedApplication {
        PinnedApplication(name: "Folder \(index)", path: "/Users/example/Folder \(index)", kind: .folder)
    }

    @Test func pinUsesPathAsUniqueIdentity() {
        var preferences = DockPreferences()
        let first = app(1)
        let renamed = PinnedApplication(name: "Renamed", path: first.path)
        let sameName = PinnedApplication(name: first.name, path: app(2).path)

        #expect(first.id == first.path)
        let didPinFirst = preferences.pin(first)
        #expect(didPinFirst)
        let didPinDuplicate = preferences.pin(first)
        #expect(!didPinDuplicate)
        let didPinRenamed = preferences.pin(renamed)
        #expect(!didPinRenamed)
        let didPinSameName = preferences.pin(sameName)
        #expect(didPinSameName)
        #expect(preferences.applications == [first, sameName])
    }

    @Test func pinRejectsInvalidPathsWithoutMutation() {
        let paths = [
            "", "Applications/Test.app", "./Test.app", "~/Applications/Test.app",
            "file:///Applications/Test.app", "/Applications/Test",
            "/Applications/Test.txt", "/Applications/Test.app/",
            "/Applications/Test.app.bak"
        ]
        var preferences = DockPreferences()
        let didPinValidApplication = preferences.pin(app(1))
        #expect(didPinValidApplication)
        let original = preferences

        for path in paths {
            let didPinInvalidApplication = preferences.pin(PinnedApplication(name: "Invalid", path: path))
            #expect(!didPinInvalidApplication)
            #expect(preferences == original)
        }
    }

    @Test func pinAcceptsAbsolutePathsWithCaseInsensitiveAppExtension() {
        var preferences = DockPreferences()
        let applications = [
            PinnedApplication(name: "Uppercase", path: "/Applications/Uppercase.APP"),
            PinnedApplication(name: "Mixed case", path: "/Users/example/My Apps/Mixed.ApP")
        ]
        for application in applications {
            let didPinApplication = preferences.pin(application)
            #expect(didPinApplication)
        }
        #expect(preferences.applications == applications)
    }

    @Test func pinPreservesMixedApplicationAndFolderOrderAndDeduplicatesPaths() {
        var preferences = DockPreferences()
        let entries = [app(1), folder(1), app(2), folder(2)]
        for entry in entries {
            let didPin = preferences.pin(entry)
            #expect(didPin)
        }
        let didPinDuplicate = preferences.pin(PinnedApplication(name: "Renamed folder", path: folder(1).path, kind: .folder))
        let didPinRelativeFolder = preferences.pin(PinnedApplication(name: "Relative folder", path: "Users/example/Folder", kind: .folder))
        let didPinInvalidApp = preferences.pin(PinnedApplication(name: "Invalid app", path: "/Applications/Invalid.txt"))
        #expect(!didPinDuplicate)
        #expect(!didPinRelativeFolder)
        #expect(!didPinInvalidApp)
        #expect(preferences.applications == entries)
    }

    @Test func pinAppliesTwelveItemLimitAcrossApplicationsAndFolders() {
        var preferences = DockPreferences()
        let entries = (0..<12).map { index in
            index.isMultiple(of: 2) ? app(index) : folder(index)
        }
        for entry in entries {
            let didPin = preferences.pin(entry)
            #expect(didPin)
        }
        let didPinBeyondCapacityApp = preferences.pin(app(12))
        let didPinBeyondCapacityFolder = preferences.pin(folder(13))
        #expect(!didPinBeyondCapacityApp)
        #expect(!didPinBeyondCapacityFolder)
        #expect(preferences.applications == entries)
        #expect(preferences.applications.count == 12)
    }

    @Test func pinCapsAtTwelveAndReusesRemovedSlot() {
        var preferences = DockPreferences()
        let applications = (0..<12).map { app($0) }
        for application in applications {
            let didPinApplication = preferences.pin(application)
            #expect(didPinApplication)
        }
        let full = preferences
        let didPinBeyondCapacity = preferences.pin(app(12))
        #expect(!didPinBeyondCapacity)
        #expect(preferences == full)

        preferences.remove(id: applications[0].id)
        let didPinInRemovedSlot = preferences.pin(app(12))
        #expect(didPinInRemovedSlot)
        #expect(preferences.applications == Array(applications.dropFirst()) + [app(12)])
        #expect(preferences.applications.count == 12)
        #expect(Set(preferences.applications.map(\.id)).count == 12)
        let didPinAfterRefillingCapacity = preferences.pin(app(13))
        #expect(!didPinAfterRefillingCapacity)
    }

    @Test func removeDeletesAllMatchingPathsAndIgnoresMissingIdentity() {
        var preferences = DockPreferences()
        let first = app(1)
        let other = PinnedApplication(name: first.name, path: app(2).path)
        preferences.applications = [
            first, other, PinnedApplication(name: "Alias", path: first.path)
        ]

        preferences.remove(id: "/Applications/Missing.app")
        #expect(preferences.applications.count == 3)
        preferences.remove(id: first.id)
        #expect(preferences.applications == [other])
        preferences.remove(id: first.id)
        #expect(preferences.applications == [other])
        preferences.remove(id: other.id)
        #expect(preferences.applications.isEmpty)
    }

    @Test func moveSwapsDestinationsAndPreservesUniqueApplications() {
        var preferences = DockPreferences()
        let applications = (0..<4).map { app($0) }
        preferences.applications = applications

        preferences.move(id: applications[0].id, offset: 2)
        #expect(preferences.applications == [applications[2], applications[1], applications[0], applications[3]])
        preferences.move(id: applications[3].id, offset: -2)
        #expect(preferences.applications == [applications[2], applications[3], applications[0], applications[1]])
        #expect(Set(preferences.applications.map(\.id)) == Set(applications.map(\.id)))
        #expect(preferences.applications.count == applications.count)
    }

    @Test func moveOutsideBoundsOrWithMissingIdentityDoesNothing() {
        var preferences = DockPreferences()
        preferences.move(id: app(0).id, offset: 1)
        #expect(preferences.applications.isEmpty)
        preferences.applications = (0..<3).map { app($0) }
        let original = preferences
        let moves = [
            (app(0).id, -1), (app(0).id, -3),
            (app(2).id, 1), (app(2).id, 3),
            (app(1).id, 0), (app(99).id, 1)
        ]
        for (id, offset) in moves {
            preferences.move(id: id, offset: offset)
            #expect(preferences == original)
        }
    }
}

@Suite("Dock preferences")
struct DockPreferencesTests {
    @Test func normalizeIconSizeHandlesNonfiniteValuesAndBounds() {
        let cases: [(Double, Double)] = [
            (.nan, 48), (.infinity, 48), (-.infinity, 48),
            (-.greatestFiniteMagnitude, 10), (-1, 10), (0, 10),
            (9, 10), (10, 10), (10.5, 10.5), (23.5, 23.5), (24, 24),
            (35.5, 35.5), (36, 36), (48, 48), (50.5, 50.5),
            (64, 64), (64.5, 64.5), (96, 96), (96.5, 96), (.greatestFiniteMagnitude, 96)
        ]
        for (input, expected) in cases {
            var preferences = DockPreferences()
            preferences.iconSize = input
            preferences.normalize()
            #expect(preferences.iconSize == expected)
            #expect(preferences.iconSize.isFinite)
        }
    }

    @Test func normalizeIconScaleHandlesNonfiniteValuesAndBounds() {
        #expect(DockPreferences().iconScale == 1)
        #expect(DockPreferences.iconScaleRange == 0.5...1.25)
        let cases: [(Double, Double)] = [
            (.nan, 1), (.infinity, 1), (-.infinity, 1),
            (-1, 0.5), (0.49, 0.5), (0.5, 0.5), (0.75, 0.75),
            (1, 1), (1.01, 1.01), (1.25, 1.25), (1.26, 1.25), (.greatestFiniteMagnitude, 1.25)
        ]
        for (input, expected) in cases {
            var preferences = DockPreferences()
            preferences.iconScale = input
            preferences.normalize()
            #expect(preferences.iconScale == expected)
            #expect(preferences.iconScale.isFinite)
        }
    }

    @Test func normalizeFocusMinutesClampsIncludingIntegerExtremes() {
        let cases = [(Int.min, 1), (-1, 1), (0, 1), (1, 1), (25, 25), (90, 90), (91, 90), (Int.max, 90)]
        for (input, expected) in cases {
            var preferences = DockPreferences()
            preferences.focusMinutes = input
            preferences.normalize()
            #expect(preferences.focusMinutes == expected)
        }
    }

    @Test func normalizeVerticalSpacingHandlesNonfiniteValuesAndBounds() {
        let cases: [(Double, Double)] = [
            (.nan, 8), (.infinity, 8), (-.infinity, 8),
            (-1, 0), (0, 0), (4, 4), (24, 24), (25, 24)
        ]
        for (input, expected) in cases {
            var preferences = DockPreferences()
            preferences.verticalSpacing = input
            preferences.normalize()
            #expect(preferences.verticalSpacing == expected)
        }
    }

    @Test func normalizeCornerRadiusHandlesNonfiniteValuesAndBounds() {
        #expect(DockPreferences().cornerRadius == 26)
        let cases: [(Double, Double)] = [
            (.nan, 26), (.infinity, 26), (-.infinity, 26),
            (-1, 0), (0, 0), (24, 24), (26, 26), (48, 48), (49, 48)
        ]
        for (input, expected) in cases {
            var preferences = DockPreferences()
            preferences.cornerRadius = input
            preferences.normalize()
            #expect(preferences.cornerRadius == expected)
            #expect(preferences.cornerRadius.isFinite)
        }
    }

    @Test func legacyPreferencesWithoutSpacingPreserveUserChoices() throws {
        var original = DockPreferences()
        original.applications = [PinnedApplication(name: "自选应用", path: "/Applications/My App.app")]
        original.iconSize = 24
        original.accent = .rose
        original.showFocus = false
        original.showDockOnLaunch = false
        let data = try JSONEncoder().encode(original)
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "verticalSpacing")
        legacy.removeValue(forKey: "cornerRadius")
        let decoded = try JSONDecoder().decode(DockPreferences.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded == original)
        #expect(decoded.verticalSpacing == 8)
        #expect(decoded.cornerRadius == 26)
    }

    @Test func legacyPreferencesWithoutIconScaleDecodeWithDefault() throws {
        var original = DockPreferences()
        original.iconScale = 0.7
        let data = try JSONEncoder().encode(original)
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "iconScale")

        let decoded = try JSONDecoder().decode(DockPreferences.self, from: JSONSerialization.data(withJSONObject: legacy))
        var expected = original
        expected.iconScale = 1
        #expect(decoded == expected)
        #expect(decoded.iconScale == 1)
    }

    @Test func normalizeKeepsMixedApplicationsAndFoldersInOrderWhileFilteringAndCapping() {
        let valid = (0..<14).map { index in
            index.isMultiple(of: 2) ? PinnedApplication(name: "App \(index)", path: "/Applications/App\(index).app")
                : PinnedApplication(name: "Folder \(index)", path: "/Users/example/Folder \(index)", kind: .folder)
        }
        var preferences = DockPreferences()
        preferences.applications = [
            PinnedApplication(name: "Relative folder", path: "Users/example/Projects", kind: .folder),
            PinnedApplication(name: "Invalid app", path: "/Applications/Invalid.txt"),
            valid[0],
            PinnedApplication(name: "Duplicate path", path: valid[0].path, kind: .folder)
        ] + Array(valid.dropFirst())

        preferences.normalize()
        #expect(preferences.applications == Array(valid.prefix(12)))
        #expect(Set(preferences.applications.map(\.id)).count == 12)
        let normalized = preferences
        preferences.normalize()
        #expect(preferences == normalized)
    }

    @Test func normalizeApplicationsFiltersBeforeCapAndKeepsFirstOccurrence() {
        let valid = (0..<14).map {
            PinnedApplication(name: "App \($0)", path: "/Applications/App\($0).app")
        }
        var preferences = DockPreferences()
        preferences.applications = [
            PinnedApplication(name: "Empty", path: ""),
            PinnedApplication(name: "Relative", path: "Applications/Relative.app"),
            PinnedApplication(name: "Wrong extension", path: "/Applications/Wrong.txt"),
            PinnedApplication(name: "Trailing slash", path: "/Applications/Trailing.app/"),
            valid[0],
            PinnedApplication(name: "Duplicate name", path: valid[0].path)
        ] + Array(valid.dropFirst())

        preferences.normalize()
        #expect(preferences.applications == Array(valid.prefix(12)))
        #expect(Set(preferences.applications.map(\.id)).count == 12)
        let normalized = preferences
        preferences.normalize()
        #expect(preferences == normalized)
    }

    @Test func normalizePreservesValidValuesAndUnrelatedPreferences() {
        var preferences = DockPreferences()
        preferences.iconSize = 52.5
        preferences.focusMinutes = 42
        preferences.cornerRadius = 35
        preferences.magnification = false
        preferences.showClock = false
        preferences.showFocus = false
        preferences.showBattery = false
        preferences.showDockOnLaunch = false
        preferences.accent = .rose
        preferences.applications = [
            PinnedApplication(name: "Mixed", path: "/Applications/Mixed.ApP")
        ]
        let original = preferences
        preferences.normalize()
        #expect(preferences == original)
    }

    @Test func preferencesCodableRoundTripPreservesEveryField() throws {
        var defaults = DockPreferences()
        defaults.normalize()
        #expect(try JSONDecoder().decode(DockPreferences.self, from: JSONEncoder().encode(defaults)) == defaults)

        for accent in DockAccent.allCases {
            var preferences = DockPreferences()
            preferences.applications = [
                PinnedApplication(name: "备忘录", path: "/Applications/Notes.app"),
                PinnedApplication(name: "Projects", path: "/Users/example/Projects", kind: .folder),
                PinnedApplication(name: "My App", path: "/Users/example/My Apps/My App.APP")
            ]
            preferences.iconSize = 61.5
            preferences.iconScale = 0.73
            preferences.verticalSpacing = 24
            preferences.cornerRadius = 31
            preferences.focusMinutes = 89
            preferences.magnification = false
            preferences.showClock = false
            preferences.showFocus = false
            preferences.showBattery = false
            preferences.showDockOnLaunch = false
            preferences.accent = accent
            preferences.normalize()

            let data = try JSONEncoder().encode(preferences)
            let decoded = try JSONDecoder().decode(DockPreferences.self, from: data)
            #expect(decoded == preferences)
            #expect(decoded.applications.map(\.id) == preferences.applications.map(\.id))
        }
    }

    @Test func applicationCodableRoundTripPreservesNamePathAndIdentity() throws {
        let application = PinnedApplication(name: "我的应用", path: "/Applications/My App.app")
        let data = try JSONEncoder().encode(application)
        let decoded = try JSONDecoder().decode(PinnedApplication.self, from: data)
        #expect(decoded == application)
        #expect(decoded.id == application.path)
        #expect(decoded.kind == .application)
    }

    @Test func legacyPinnedApplicationWithoutKindDecodesAsApplication() throws {
        let data = Data(#"{"name":"Notes","path":"/Applications/Notes.app"}"#.utf8)
        let decoded = try JSONDecoder().decode(PinnedApplication.self, from: data)
        #expect(decoded == PinnedApplication(name: "Notes", path: "/Applications/Notes.app"))
        #expect(decoded.kind == .application)
    }
}

@Suite("Focus timer")
struct FocusTimerTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func initialStateIsIdleWithFullDefaultDuration() {
        var timer = FocusTimer()
        #expect(timer.state == .idle)
        #expect(!timer.isRunning)
        #expect(timer.duration == 1_500)
        #expect(timer.remaining(at: now) == 1_500)
        #expect(timer.label(at: now) == "25:00")
        #expect(timer.progress(at: now) == 0)
        let didCompleteWhileIdle = timer.tick(at: now.addingTimeInterval(10_000))
        #expect(!didCompleteWhileIdle)
        #expect(timer.state == .idle)
    }

    @Test func startSetsDeadlineAndRestartsRunningOrCompletedTimer() {
        var timer = FocusTimer()
        timer.start(minutes: 2, at: now)
        #expect(timer.state == .running(until: now.addingTimeInterval(120)))
        #expect(timer.isRunning)
        #expect(timer.duration == 120)
        #expect(timer.remaining(at: now.addingTimeInterval(30)) == 90)

        let restart = now.addingTimeInterval(30)
        timer.start(minutes: 1, at: restart)
        #expect(timer.duration == 60)
        #expect(timer.state == .running(until: restart.addingTimeInterval(60)))
        let didCompleteAtRestartedDeadline = timer.tick(at: restart.addingTimeInterval(60))
        #expect(didCompleteAtRestartedDeadline)
        timer.start(minutes: 3, at: restart.addingTimeInterval(90))
        #expect(timer.duration == 180)
        #expect(timer.state == .running(until: restart.addingTimeInterval(270)))
        #expect(timer.progress(at: restart.addingTimeInterval(90)) == 0)
    }

    @Test func pauseFreezesFractionalRemainingTime() {
        var timer = FocusTimer()
        timer.start(minutes: 2, at: now)
        timer.pause(at: now.addingTimeInterval(30.25))
        #expect(timer.state == .paused(seconds: 89.75))
        #expect(!timer.isRunning)
        #expect(timer.duration == 120)
        #expect(timer.remaining(at: now.addingTimeInterval(1_000)) == 89.75)
        #expect(timer.label(at: now.addingTimeInterval(1_000)) == "01:30")
        let didCompleteWhilePaused = timer.tick(at: now.addingTimeInterval(1_000))
        #expect(!didCompleteWhilePaused)
        #expect(timer.state == .paused(seconds: 89.75))
    }

    @Test func resumeShiftsDeadlineWithoutChangingDuration() {
        var timer = FocusTimer()
        timer.start(minutes: 2, at: now)
        timer.pause(at: now.addingTimeInterval(30.25))
        let resumedAt = now.addingTimeInterval(1_000)
        timer.resume(at: resumedAt)
        #expect(timer.isRunning)
        #expect(timer.duration == 120)
        #expect(timer.state == .running(until: resumedAt.addingTimeInterval(89.75)))
        #expect(timer.remaining(at: resumedAt) == 89.75)
        let didCompleteBeforeResumedDeadline = timer.tick(at: resumedAt.addingTimeInterval(89.5))
        #expect(!didCompleteBeforeResumedDeadline)
        let didCompleteAtResumedDeadline = timer.tick(at: resumedAt.addingTimeInterval(89.75))
        #expect(didCompleteAtResumedDeadline)
        #expect(timer.state == .completed)
    }

    @Test func resetClearsEveryStateAndRestoresFullDuration() {
        let idle = FocusTimer()
        var running = FocusTimer()
        running.start(minutes: 1, at: now)
        var paused = running
        paused.pause(at: now.addingTimeInterval(10))
        var completed = running
        let didCompleteBeforeReset = completed.tick(at: now.addingTimeInterval(60))
        #expect(didCompleteBeforeReset)

        for original in [idle, running, paused, completed] {
            var timer = original
            timer.reset(minutes: 3)
            #expect(timer.state == .idle)
            #expect(!timer.isRunning)
            #expect(timer.duration == 180)
            #expect(timer.remaining(at: now.addingTimeInterval(1_000)) == 180)
            #expect(timer.progress(at: now) == 0)
            #expect(timer.label(at: now) == "03:00")
            let didCompleteAfterReset = timer.tick(at: now.addingTimeInterval(1_000))
            #expect(!didCompleteAfterReset)
        }
    }

    @Test func tickCompletesExactlyAtDeadlineOnlyOnce() {
        var timer = FocusTimer()
        timer.start(minutes: 1, at: now)
        let deadline = now.addingTimeInterval(60)
        let didCompleteBeforeDeadline = timer.tick(at: deadline.addingTimeInterval(-0.25))
        #expect(!didCompleteBeforeDeadline)
        #expect(timer.isRunning)
        #expect(timer.remaining(at: deadline.addingTimeInterval(-0.25)) == 0.25)
        let didCompleteAtDeadline = timer.tick(at: deadline)
        #expect(didCompleteAtDeadline)
        #expect(timer.state == .completed)
        #expect(!timer.isRunning)
        #expect(timer.remaining(at: deadline) == 0)
        #expect(timer.label(at: deadline) == "00:00")
        let didCompleteAgainAtDeadline = timer.tick(at: deadline)
        #expect(!didCompleteAgainAtDeadline)
        let didCompleteAgainAfterDeadline = timer.tick(at: deadline.addingTimeInterval(1))
        #expect(!didCompleteAgainAfterDeadline)
        let didCompleteAgainBeforeDeadline = timer.tick(at: now)
        #expect(!didCompleteAgainBeforeDeadline)
        #expect(timer.state == .completed)
    }

    @Test func firstTickAfterDeadlineAlsoCompletesOnlyOnce() {
        var timer = FocusTimer()
        timer.start(minutes: 1, at: now)
        let didCompleteAfterDeadline = timer.tick(at: now.addingTimeInterval(60.25))
        #expect(didCompleteAfterDeadline)
        #expect(timer.state == .completed)
        let didCompleteAgainAfterDeadline = timer.tick(at: now.addingTimeInterval(1_000))
        #expect(!didCompleteAgainAfterDeadline)
    }

    @Test func pauseAtOrAfterDeadlineCompletesWithoutDuplicateTickEvent() {
        for elapsed in [60.0, 60.25, 1_000.0] {
            var timer = FocusTimer()
            timer.start(minutes: 1, at: now)
            timer.pause(at: now.addingTimeInterval(elapsed))
            #expect(timer.state == .completed)
            #expect(!timer.isRunning)
            #expect(timer.remaining(at: now) == 0)
            let didCompleteAgainAfterPause = timer.tick(at: now.addingTimeInterval(elapsed))
            #expect(!didCompleteAgainAfterPause)
            timer.resume(at: now.addingTimeInterval(elapsed + 1))
            #expect(timer.state == .completed)
        }
    }

    @Test func pauseAndResumeIgnoreInapplicableStates() {
        var timer = FocusTimer()
        let idle = timer
        timer.pause(at: now)
        timer.resume(at: now)
        #expect(timer == idle)

        timer.start(minutes: 1, at: now)
        let running = timer
        timer.resume(at: now.addingTimeInterval(10))
        #expect(timer == running)
        timer.pause(at: now.addingTimeInterval(10))
        let paused = timer
        timer.pause(at: now.addingTimeInterval(20))
        #expect(timer == paused)

        timer.start(minutes: 2, at: now)
        #expect(timer.state == .running(until: now.addingTimeInterval(120)))
        #expect(timer.duration == 120)
        let didCompleteAtDeadline = timer.tick(at: now.addingTimeInterval(120))
        #expect(didCompleteAtDeadline)
        let completed = timer
        timer.pause(at: now.addingTimeInterval(130))
        timer.resume(at: now.addingTimeInterval(140))
        #expect(timer == completed)
    }

    @Test func labelRoundsUpAcrossMinuteAndCompletionBoundaries() {
        var timer = FocusTimer()
        timer.start(minutes: 2, at: now)
        let cases: [(TimeInterval, String)] = [
            (-0.25, "02:01"), (0, "02:00"), (0.25, "02:00"),
            (59, "01:01"), (59.25, "01:01"), (60, "01:00"),
            (60.25, "01:00"), (119, "00:01"), (119.25, "00:01"),
            (119.75, "00:01"), (120, "00:00"), (120.25, "00:00")
        ]
        for (elapsed, expected) in cases {
            #expect(timer.label(at: now.addingTimeInterval(elapsed)) == expected)
        }
    }

    @Test func progressClampsBeforeStartAndAfterDeadline() {
        var timer = FocusTimer()
        timer.start(minutes: 1, at: now)
        let cases: [(TimeInterval, Double)] = [
            (-60, 0), (-0.25, 0), (0, 0), (15, 0.25),
            (30, 0.5), (45, 0.75), (60, 1), (60.25, 1), (1_000, 1)
        ]
        for (elapsed, expected) in cases {
            #expect(timer.progress(at: now.addingTimeInterval(elapsed)) == expected)
        }
    }

    @Test func progressFreezesWhilePausedAndStaysFullWhenCompleted() {
        var timer = FocusTimer()
        timer.start(minutes: 1, at: now)
        timer.pause(at: now.addingTimeInterval(15))
        #expect(timer.progress(at: now.addingTimeInterval(1_000)) == 0.25)
        timer.resume(at: now.addingTimeInterval(1_000))
        #expect(timer.progress(at: now.addingTimeInterval(1_000)) == 0.25)
        let didCompleteAtResumedDeadline = timer.tick(at: now.addingTimeInterval(1_045))
        #expect(didCompleteAtResumedDeadline)
        #expect(timer.progress(at: now) == 1)
        #expect(timer.progress(at: now.addingTimeInterval(2_000)) == 1)
    }

    @Test func startClampsMinutesIncludingIntegerExtremes() {
        let cases = [(Int.min, 1), (-1, 1), (0, 1), (1, 1), (25, 25), (90, 90), (91, 90), (Int.max, 90)]
        for (input, expected) in cases {
            var timer = FocusTimer()
            timer.start(minutes: input, at: now)
            let seconds = TimeInterval(expected * 60)
            #expect(timer.duration == seconds)
            #expect(timer.remaining(at: now) == seconds)
            #expect(timer.state == .running(until: now.addingTimeInterval(seconds)))
            #expect(timer.label(at: now) == String(format: "%02d:00", expected))
        }
    }

    @Test func resetClampsMinutesIncludingIntegerExtremes() {
        let cases = [(Int.min, 1), (-1, 1), (0, 1), (1, 1), (25, 25), (90, 90), (91, 90), (Int.max, 90)]
        for (input, expected) in cases {
            var timer = FocusTimer()
            timer.start(minutes: 2, at: now)
            timer.reset(minutes: input)
            #expect(timer.state == .idle)
            #expect(timer.duration == TimeInterval(expected * 60))
            #expect(timer.remaining(at: now) == TimeInterval(expected * 60))
            #expect(timer.progress(at: now) == 0)
        }
    }

    @Test func remainingNeverBecomesNegativeOrImplicitlyCompletesTimer() {
        var timer = FocusTimer()
        timer.start(minutes: 1, at: now)
        #expect(timer.remaining(at: now.addingTimeInterval(-30)) == 90)
        #expect(timer.remaining(at: now.addingTimeInterval(60)) == 0)
        #expect(timer.remaining(at: now.addingTimeInterval(1_000)) == 0)
        #expect(timer.state == .running(until: now.addingTimeInterval(60)))
        let didCompleteAfterDeadline = timer.tick(at: now.addingTimeInterval(1_000))
        #expect(didCompleteAfterDeadline)
        #expect(timer.remaining(at: now.addingTimeInterval(-30)) == 0)
    }
}
