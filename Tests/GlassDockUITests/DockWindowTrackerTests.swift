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
import CoreGraphics
import GlassDockCore
import Testing
@testable import GlassDock

@Suite("Dock window tracker policies")
struct DockWindowTrackerTests {
    private let primaryAppKitFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let secondaryAppKitFrame = CGRect(x: 1440, y: 0, width: 1280, height: 800)
    private let primaryQuartzFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let secondaryQuartzFrame = CGRect(x: 1440, y: 0, width: 1280, height: 800)

    @Test func mapsAppKitScreenToItsQuartzDisplayByLargestIntersection() {
        let mappings = [
            DockWindowDisplayMapping(appKitFrame: primaryAppKitFrame, quartzFrame: primaryQuartzFrame),
            DockWindowDisplayMapping(appKitFrame: secondaryAppKitFrame, quartzFrame: secondaryQuartzFrame)
        ]

        let target = DockWindowTrackerPolicy.targetDisplayFrame(
            for: CGRect(x: 1300, y: 0, width: 400, height: 800),
            mappings: mappings
        )

        #expect(target == secondaryQuartzFrame)
        #expect(DockWindowTrackerPolicy.targetDisplayFrame(for: .zero, mappings: mappings) == nil)
    }

    @Test func includesOnlyVisibleRegularWindowsOwnedByTargetDisplay() {
        let app = PinnedApplication(name: "Notes", path: "/Applications/Notes.app")
        let applications: [Int32: DockWindowApplicationInfo] = [
            100: DockWindowApplicationInfo(application: app, isRegular: true, isExcludedSystemApplication: false),
            101: DockWindowApplicationInfo(application: app, isRegular: false, isExcludedSystemApplication: false),
            102: DockWindowApplicationInfo(application: app, isRegular: true, isExcludedSystemApplication: true)
        ]
        let records = [
            record(id: 1, pid: 100, bounds: CGRect(x: 100, y: 100, width: 300, height: 200)),
            record(id: 2, pid: 100, bounds: CGRect(x: 1500, y: 100, width: 300, height: 200)),
            record(id: 3, pid: 100, layer: 1),
            record(id: 4, pid: 100, alpha: 0),
            record(id: 5, pid: 101),
            record(id: 6, pid: 102),
            record(id: 7, pid: 999)
        ]

        let snapshots = DockWindowTrackerPolicy.snapshots(
            from: records,
            applications: applications,
            targetDisplayFrame: primaryQuartzFrame,
            displayFrames: [primaryQuartzFrame, secondaryQuartzFrame],
            currentProcessID: 999
        )

        #expect(snapshots.map(\.id) == [1])
        #expect(snapshots.first?.title == "Notes")
    }

    @Test func liveApplicationScanDoesNotDependOnTargetScreenWindows() {
        let app = PinnedApplication(name: "Notes", path: "/Applications/Notes.app")
        let applications: [Int32: DockWindowApplicationInfo] = [
            100: DockWindowApplicationInfo(application: app, isRegular: true, isExcludedSystemApplication: false),
            101: DockWindowApplicationInfo(application: app, isRegular: true, isExcludedSystemApplication: false),
            102: DockWindowApplicationInfo(application: app, isRegular: false, isExcludedSystemApplication: false),
            103: DockWindowApplicationInfo(application: app, isRegular: true, isExcludedSystemApplication: true)
        ]

        #expect(DockWindowTrackerPolicy.scanProcessIDs(from: applications, priorityProcessIDs: nil) == [100, 101])
        #expect(DockWindowTrackerPolicy.scanProcessIDs(from: applications, priorityProcessIDs: [101, 999]) == [101])
    }

    @Test func pendingEventRefreshesMergeProcessIDsAndFullRefreshSupersedesThem() {
        #expect(DockWindowTrackerPolicy.coalescedPriorityProcessIDs(
            active: [100], pending: [101], incoming: [102]
        ) == [100, 101, 102])
        #expect(DockWindowTrackerPolicy.coalescedPriorityProcessIDs(
            active: [100], pending: [101], incoming: nil
        ) == nil)
    }

    @Test func cancelledScanStopsBeforeStartingAnotherProcess() {
        #expect(DockWindowTrackerPolicy.shouldContinueProcessScan(isCancelled: false, deadlineNotReached: true))
        #expect(!DockWindowTrackerPolicy.shouldContinueProcessScan(isCancelled: true, deadlineNotReached: true))
        #expect(!DockWindowTrackerPolicy.shouldContinueProcessScan(isCancelled: false, deadlineNotReached: false))
    }

    @Test func accessibilityIdentitySeparatesWindowsWithSameBoundsAndTitles() throws {
        let bounds = CGRect(x: 10, y: 20, width: 300, height: 200)
        let elements = [
            accessibilityElement(title: "New Tab", bounds: bounds),
            accessibilityElement(title: "Yearning", bounds: bounds),
            accessibilityElement(title: "Same title", bounds: bounds),
            accessibilityElement(title: "Same title", bounds: bounds)
        ]
        var nextID: UInt32 = 20
        let identities = try #require(DockWindowTrackerPolicy.stableAccessibilityIdentities(
            for: elements,
            previous: [],
            inventoryIsComplete: true,
            areEqual: sameAccessibilityElement,
            allocateIdentity: {
                defer { nextID += 1 }
                return (nextID, UUID())
            }
        ))

        #expect(elements[0].descriptor.bounds == elements[1].descriptor.bounds)
        #expect(elements[0].descriptor.title != elements[1].descriptor.title)
        #expect(elements[2].descriptor == elements[3].descriptor)
        #expect(identities.count == 4)
        #expect(Set(identities.map(\.id)).count == 4)
        #expect(Set(identities.map(\.accessibilityIdentity)).count == 4)
    }

    @Test func accessibilityIdentitySurvivesEnumerationReordering() throws {
        let first = accessibilityElement(title: "First", bounds: primaryQuartzFrame)
        let second = accessibilityElement(title: "Second", bounds: primaryQuartzFrame)
        var nextID: UInt32 = 30
        let initial = try #require(DockWindowTrackerPolicy.stableAccessibilityIdentities(
            for: [first, second],
            previous: [],
            inventoryIsComplete: true,
            areEqual: sameAccessibilityElement,
            allocateIdentity: {
                defer { nextID += 1 }
                return (nextID, UUID())
            }
        ))
        let reordered = try #require(DockWindowTrackerPolicy.stableAccessibilityIdentities(
            for: [second, first],
            previous: initial,
            inventoryIsComplete: true,
            areEqual: sameAccessibilityElement,
            allocateIdentity: {
                defer { nextID += 1 }
                return (nextID, UUID())
            }
        ))
        let initialByElement = Dictionary(uniqueKeysWithValues: initial.map { ($0.element.token, $0) })

        #expect(reordered.map(\.element.token) == [second.token, first.token])
        #expect(reordered.allSatisfy {
            initialByElement[$0.element.token]?.id == $0.id &&
                initialByElement[$0.element.token]?.accessibilityIdentity == $0.accessibilityIdentity
        })
    }

    @Test func incompleteAccessibilityInventoryDoesNotAssignWindowIdentities() {
        let partial = accessibilityElement(title: "Partial", bounds: primaryQuartzFrame)
        var didAllocate = false
        let identities = DockWindowTrackerPolicy.stableAccessibilityIdentities(
            for: [partial],
            previous: [],
            inventoryIsComplete: false,
            areEqual: sameAccessibilityElement,
            allocateIdentity: {
                didAllocate = true
                return (1, UUID())
            }
        )

        #expect(identities == nil)
        #expect(!didAllocate)
    }

    @Test func closedAXReferenceCannotResolveToReplacementWithSameTitleAndBounds() throws {
        let bounds = CGRect(x: 10, y: 20, width: 300, height: 200)
        let closed = accessibilityElement(title: "Document", bounds: bounds)
        let replacement = accessibilityElement(title: "Document", bounds: bounds)
        #expect(closed.descriptor == replacement.descriptor)
        let cached = DockAccessibilityElementIdentity(
            id: 42,
            accessibilityIdentity: UUID(),
            element: closed
        )
        var nextID: UInt32 = 43
        let current = try #require(DockWindowTrackerPolicy.stableAccessibilityIdentities(
            for: [replacement],
            previous: [cached],
            inventoryIsComplete: true,
            areEqual: sameAccessibilityElement,
            allocateIdentity: {
                defer { nextID += 1 }
                return (nextID, UUID())
            }
        ))

        #expect(current.first?.id == 43)
        #expect(current.first?.accessibilityIdentity != cached.accessibilityIdentity)
        #expect(DockWindowTrackerPolicy.liveAccessibilityElement(
            matching: closed,
            among: [replacement],
            areEqual: sameAccessibilityElement
        ) == nil)
    }

    @Test func liveAXLookupMatchesExactReferenceAmongDuplicateWindowDescriptors() throws {
        let bounds = CGRect(x: 10, y: 20, width: 300, height: 200)
        let target = accessibilityElement(title: "Same title", bounds: bounds)
        let other = accessibilityElement(title: "Same title", bounds: bounds)

        let live = try #require(DockWindowTrackerPolicy.liveAccessibilityElement(
            matching: target,
            among: [other, target],
            areEqual: sameAccessibilityElement
        ))

        #expect(live.token == target.token)
    }

    @Test func accessibilityIdentityKeepsGroupingKeysDistinctFromCGWindowIDs() {
        let app = PinnedApplication(name: "Browser", path: "/Applications/Browser.app")
        let cgWindow = DockWindowSnapshot(
            id: 1,
            processID: 100,
            application: app,
            title: "Browser",
            bounds: primaryQuartzFrame
        )
        let axWindow = DockWindowSnapshot(
            id: 1,
            processID: 100,
            application: app,
            title: "Browser",
            bounds: primaryQuartzFrame,
            accessibilityIdentity: UUID()
        )

        let entries = DockWindowGrouping.entries(pinned: [], windows: [cgWindow, axWindow])

        #expect(entries.count == 2)
        #expect(Set(entries.map(\.id)).count == 2)
    }

    @Test func firstIncompleteOrSkippedAXScanKeepsOrdinaryApplicationIcons() {
        let app = PinnedApplication(name: "Browser", path: "/Applications/Browser.app")
        let raw = [10, 20, 30].map { pid in
            DockWindowSnapshot(id: 1, processID: Int32(pid), application: app,
                               title: "Browser", bounds: primaryQuartzFrame, isVerified: false)
        }
        let cached = DockWindowSnapshot(id: 2, processID: 20, application: app,
                                        title: "Document", bounds: primaryQuartzFrame,
                                        accessibilityIdentity: UUID())
        let result = DockWindowTrackerPolicy.presentationSnapshots(
            cached: [cached], raw: raw, completedProcesses: [20, 30],
            targetDisplayFrame: primaryQuartzFrame, displayFrames: [primaryQuartzFrame]
        )
        #expect(result.count == 2)
        #expect(result.contains(cached))
        #expect(result.contains { $0.processID == 10 && !$0.isVerified && $0.accessibilityIdentity == nil })
        // 进程 30 已完整确认没有普通窗口，不能重新显示辅助窗口的 CG 入口。
        #expect(!result.contains { $0.processID == 30 })
    }

    @Test func cachedWindowsFromPreviousScreenStayExcludedWhenAXScanFails() {
        let secondary = CGRect(x: primaryQuartzFrame.maxX, y: 0, width: 1200, height: 800)
        let app = PinnedApplication(name: "Browser", path: "/Applications/Browser.app")
        let cached = DockWindowSnapshot(id: 1, processID: 10, application: app,
                                        title: "Old screen", bounds: primaryQuartzFrame,
                                        accessibilityIdentity: UUID())
        let result = DockWindowTrackerPolicy.presentationSnapshots(
            cached: [cached], raw: [], completedProcesses: [10],
            targetDisplayFrame: secondary, displayFrames: [primaryQuartzFrame, secondary]
        )
        #expect(result.isEmpty)
    }

    @Test func applicationActivationFallbackRequiresOneCurrentWindow() {
        #expect(DockWindowTrackerPolicy.shouldUseApplicationActivationFallback(
            targetWindowIsCurrent: true,
            processWindowCount: 1
        ))
        #expect(!DockWindowTrackerPolicy.shouldUseApplicationActivationFallback(
            targetWindowIsCurrent: true,
            processWindowCount: 2
        ))
        #expect(!DockWindowTrackerPolicy.shouldUseApplicationActivationFallback(
            targetWindowIsCurrent: false,
            processWindowCount: 1
        ))
    }

    @MainActor
    @Test func activationFlowWaitsForFrontmostNotificationBeforeAXActions() {
        var events: [String] = []
        var onFrontmost: ((Bool) -> Void)?
        var onActivationComplete: ((Bool) -> Void)?
        var completionResult: Bool?

        DockWindowActivationFlow.request(
            isRequestCurrent: { true },
            installFrontmostObserver: { callback in
                events.append("observe")
                onFrontmost = callback
            },
            requestActivation: { callback in
                events.append("activate app")
                onActivationComplete = callback
            },
            activateWindow: { completion in
                let result = DockWindowAXActivationSequence.perform(
                    isMinimized: true,
                    restoreMinimized: { events.append("restore"); return true },
                    setMain: { events.append("main"); return true },
                    setFocused: { events.append("focused"); return true },
                    raise: { events.append("raise"); return true }
                )
                completion(result)
            },
            completion: { completionResult = $0 }
        )

        #expect(events == ["observe", "activate app"])
        #expect(completionResult == nil)
        onFrontmost?(true)
        #expect(events == ["observe", "activate app"])
        #expect(completionResult == nil)
        onActivationComplete?(true)
        #expect(events == ["observe", "activate app", "restore", "main", "focused", "raise"])
        #expect(completionResult == true)
    }

    @MainActor
    @Test func activationFlowWaitsForWorkspaceCompletionWhenItArrivesFirst() {
        var onFrontmost: ((Bool) -> Void)?
        var onActivationComplete: ((Bool) -> Void)?
        var didRunWindowAction = false
        var completionResult: Bool?

        DockWindowActivationFlow.request(
            isRequestCurrent: { true },
            installFrontmostObserver: { onFrontmost = $0 },
            requestActivation: { onActivationComplete = $0 },
            activateWindow: { completion in
                didRunWindowAction = true
                completion(true)
            },
            completion: { completionResult = $0 }
        )
        onActivationComplete?(true)
        #expect(!didRunWindowAction)
        #expect(completionResult == nil)
        onFrontmost?(true)
        #expect(didRunWindowAction)
        #expect(completionResult == true)
    }

    @MainActor
    @Test func activationFlowRejectsWorkspaceRequestAndIgnoresCancelledCallbacks() {
        var frontmostCallback: ((Bool) -> Void)?
        var rejectedActivationCallback: ((Bool) -> Void)?
        var didRunWindowAction = false
        var rejectedActivationResult: Bool?

        DockWindowActivationFlow.request(
            isRequestCurrent: { true },
            installFrontmostObserver: { frontmostCallback = $0 },
            requestActivation: { rejectedActivationCallback = $0 },
            activateWindow: { _ in didRunWindowAction = true },
            completion: { rejectedActivationResult = $0 }
        )
        rejectedActivationCallback?(false)
        frontmostCallback?(true)
        #expect(rejectedActivationResult == false)
        #expect(!didRunWindowAction)

        var requestIsCurrent = true
        var cancelledFrontmostCallback: ((Bool) -> Void)?
        var cancelledActivationCallback: ((Bool) -> Void)?
        var cancelledCompletionResult: Bool?
        DockWindowActivationFlow.request(
            isRequestCurrent: { requestIsCurrent },
            installFrontmostObserver: { cancelledFrontmostCallback = $0 },
            requestActivation: { cancelledActivationCallback = $0 },
            activateWindow: { _ in didRunWindowAction = true },
            completion: { cancelledCompletionResult = $0 }
        )
        requestIsCurrent = false
        cancelledActivationCallback?(true)
        cancelledFrontmostCallback?(true)
        #expect(cancelledCompletionResult == nil)
        #expect(!didRunWindowAction)

        var restoreEvents: [String] = []
        let restoreFailed = DockWindowAXActivationSequence.perform(
            isMinimized: true,
            restoreMinimized: { restoreEvents.append("restore"); return false },
            setMain: { restoreEvents.append("main"); return true },
            setFocused: { restoreEvents.append("focused"); return true },
            raise: { restoreEvents.append("raise"); return true }
        )
        #expect(!restoreFailed)
        #expect(restoreEvents == ["restore"])

        var raiseEvents: [String] = []
        let raiseFailed = DockWindowAXActivationSequence.perform(
            isMinimized: false,
            restoreMinimized: { raiseEvents.append("restore"); return true },
            setMain: { raiseEvents.append("main"); return false },
            setFocused: { raiseEvents.append("focused"); return false },
            raise: { raiseEvents.append("raise"); return false }
        )
        #expect(!raiseFailed)
        #expect(raiseEvents == ["main", "focused", "raise"])
    }

    @Test func closeSequenceRequiresExactLiveWindowAndItsCloseButton() {
        let target = accessibilityElement(title: "Same title", bounds: primaryQuartzFrame)
        let otherWindow = accessibilityElement(title: "Same title", bounds: primaryQuartzFrame)
        var pressedButtons: [String] = []

        let closed = DockWindowCloseSequence.perform(
            target: target,
            among: [otherWindow, target],
            areEqual: sameAccessibilityElement,
            isSupportedWindow: { $0.token == target.token },
            closeButton: { $0.token == target.token ? "target-close-button" : nil },
            press: { pressedButtons.append($0); return true }
        )
        #expect(closed == .closed)
        #expect(pressedButtons == ["target-close-button"])

        pressedButtons.removeAll()
        let missingTarget = DockWindowCloseSequence.perform(
            target: target,
            among: [otherWindow],
            areEqual: sameAccessibilityElement,
            isSupportedWindow: { _ in true },
            closeButton: { _ in "other-close-button" },
            press: { pressedButtons.append($0); return true }
        )
        #expect(missingTarget == .targetUnavailable)
        #expect(pressedButtons.isEmpty)

        let missingButton = DockWindowCloseSequence.perform(
            target: target,
            among: [target],
            areEqual: sameAccessibilityElement,
            isSupportedWindow: { _ in true },
            closeButton: { _ in nil as String? },
            press: { pressedButtons.append($0); return true }
        )
        #expect(missingButton == .closeButtonUnavailable)
        #expect(pressedButtons.isEmpty)
    }

    @MainActor
    @Test func titlelessSingleWindowEntryActivatesTheApplication() {
        let suiteName = "GlassDockTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AppStore(defaults: defaults)
        let app = PinnedApplication(name: "Missing app", path: "/GlassDock-\(UUID().uuidString).app")
        let window = DockWindowSnapshot(
            id: 1,
            processID: Int32(ProcessInfo.processInfo.processIdentifier),
            application: app,
            title: "Only window on this screen",
            bounds: primaryQuartzFrame
        )

        store.activate(DockApplicationEntry(application: app, window: window, showsWindowTitle: false))
        #expect(store.errorMessage?.contains("Missing app") == true)

        store.errorMessage = nil
        store.activate(DockApplicationEntry(application: app, window: window, showsWindowTitle: true))
        #expect(store.errorMessage == nil)
    }

    @MainActor
    @Test func closeRejectsApplicationOnlyEntries() {
        let suiteName = "GlassDockTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AppStore(defaults: defaults)
        let application = PinnedApplication(name: "Notes", path: "/Applications/Notes.app")

        store.close(DockApplicationEntry(application: application))

        #expect(store.errorMessage == "此入口没有可单独关闭的窗口。")
    }

    @MainActor
    @Test func restoreAppearanceResetsIconScale() {
        let suiteName = "GlassDockTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AppStore(defaults: defaults)
        store.preferences.iconScale = 0.5

        store.restoreAppearance()

        #expect(store.preferences.iconScale == DockPreferences().iconScale)
    }

    private func record(
        id: UInt32,
        pid: Int32,
        layer: Int = 0,
        alpha: Double = 1,
        title: String = "",
        bounds: CGRect = CGRect(x: 100, y: 100, width: 300, height: 200)
    ) -> DockWindowRecord {
        DockWindowRecord(id: id, processID: pid, layer: layer, alpha: alpha, title: title, bounds: bounds)
    }

    private func accessibilityElement(title: String, bounds: CGRect) -> TestAccessibilityElement {
        TestAccessibilityElement(
            token: UUID(),
            descriptor: DockAccessibilityWindowDescriptor(bounds: bounds, title: title)
        )
    }

    private func sameAccessibilityElement(_ lhs: TestAccessibilityElement, _ rhs: TestAccessibilityElement) -> Bool {
        lhs.token == rhs.token
    }

    private struct TestAccessibilityElement {
        let token: UUID
        let descriptor: DockAccessibilityWindowDescriptor
    }
}
