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
import ApplicationServices
import Combine
import CoreGraphics
import Foundation
import GlassDockCore
import OSLog

private let windowingLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "GlassDock",
    category: "Windowing"
)

private func logWindowActivation(
    _ processID: Int32,
    stage: String,
    result: String,
    axError: AXError? = nil
) {
    if let axError, axError != .success {
        windowingLogger.error(
            "window activation pid=\(processID, privacy: .public) stage=\(stage, privacy: .public) result=\(result, privacy: .public) axError=\(axError.rawValue, privacy: .public)"
        )
    } else {
        windowingLogger.debug(
            "window activation pid=\(processID, privacy: .public) stage=\(stage, privacy: .public) result=\(result, privacy: .public)"
        )
    }
}

/// 读取当前显示器上的普通应用窗口，并在用户明确授权后提供窗口级激活。
@MainActor
final class DockWindowTracker: ObservableObject {
    @Published private(set) var windows: [DockWindowSnapshot] = []
    @Published private(set) var hasAccessibilityPermission: Bool
    @Published var errorMessage: String?

    private let accessibilityQueue = DispatchQueue(label: "GlassDock.DockWindowTracker.Accessibility", qos: .userInitiated)
    private let accessibilityReader = DockAccessibilityWindowReader()
    private var generation: UInt64 = 0
    private var refreshInFlight = false
    private var currentRequest: RefreshRequest?
    private var latestRequest: RefreshRequest?
    private var currentCancellation: DockWindowCancellation?
    private var pendingWindowActivationID: UUID?
    private var pendingWindowActivationObserver: NSObjectProtocol?
    private var pendingWindowActivationTimeout: DispatchWorkItem?
    private var pendingWindowActionCancellation: DockWindowCancellation?
    private var lastScreenFrame: NSRect?
    private lazy var eventMonitor = DockAccessibilityEventMonitor { [weak self] processID in
        self?.refreshForAccessibilityEvent(processID)
    }

    init() {
        hasAccessibilityPermission = AXIsProcessTrusted()
    }

    /// 更新一个显示器上的窗口清单；AX 查询异步执行，重复刷新只保留最新请求。
    func refresh(screenFrame: NSRect) {
        refresh(screenFrame: screenFrame, priorityProcessIDs: nil)
    }

    /// 只优先重读触发事件的进程，其余进程继续使用可见窗口缓存。
    func refresh(screenFrame: NSRect, forProcessID processID: Int32) {
        refresh(screenFrame: screenFrame, priorityProcessIDs: [processID])
    }

    private func refresh(screenFrame: NSRect, priorityProcessIDs: Set<Int32>?) {
        lastScreenFrame = screenFrame
        generation &+= 1
        currentCancellation?.cancel()
        hasAccessibilityPermission = AXIsProcessTrusted()

        let mappings = Self.displayMappings()
        let applications = Self.runningApplications()
        eventMonitor.updateLiveApplications(Set(applications.keys))
        guard let target = DockWindowTrackerPolicy.targetDisplayFrame(for: screenFrame, mappings: mappings) else {
            windows = []
            latestRequest = nil
            return
        }

        let records = Self.windowRecords()
        let snapshots = DockWindowTrackerPolicy.snapshots(
            from: records,
            applications: applications,
            targetDisplayFrame: target,
            displayFrames: mappings.map(\.quartzFrame),
            currentProcessID: Int32(ProcessInfo.processInfo.processIdentifier)
        )

        guard hasAccessibilityPermission else {
            windows = snapshots
            latestRequest = nil
            return
        }

        errorMessage = nil
        let request = RefreshRequest(
            generation: generation,
            records: records,
            applications: applications,
            targetDisplayFrame: target,
            displayFrames: mappings.map(\.quartzFrame),
            currentProcessID: Int32(ProcessInfo.processInfo.processIdentifier),
            priorityProcessIDs: DockWindowTrackerPolicy.coalescedPriorityProcessIDs(
                active: currentRequest?.priorityProcessIDs,
                pending: latestRequest?.priorityProcessIDs,
                incoming: priorityProcessIDs
            )
        )
        latestRequest = request
        startLatestRefreshIfNeeded()
    }

    private func refreshForAccessibilityEvent(_ processID: Int32) {
        guard let lastScreenFrame else { return }
        refresh(screenFrame: lastScreenFrame, priorityProcessIDs: [processID])
    }

    /// 显示系统辅助功能授权流程；此方法只由用户明确点击授权按钮时调用。
    func requestAccessibilityAccess() {
        errorMessage = nil
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        hasAccessibilityPermission = AXIsProcessTrustedWithOptions(options)
        guard !hasAccessibilityPermission else {
            if let lastScreenFrame {
                refresh(screenFrame: lastScreenFrame)
            }
            return
        }

        let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        if let settingsURL, !NSWorkspace.shared.open(settingsURL) {
            errorMessage = "无法打开系统设置的辅助功能页面，请手动前往“隐私与安全性 → 辅助功能”。"
        }
    }

    /// 激活指定窗口；无 AX 权限时，仅在该进程只有一个当前窗口时退回应用激活。
    func activate(_ window: DockWindowSnapshot) {
        cancelPendingWindowActivation()
        guard let application = NSRunningApplication(processIdentifier: pid_t(window.processID)),
              application.activationPolicy == .regular,
              let applicationURL = application.bundleURL,
              applicationURL.path == window.application.path,
              !Self.excludedSystemBundleIdentifiers.contains(application.bundleIdentifier ?? ""),
              window.processID != Int32(ProcessInfo.processInfo.processIdentifier) else {
            logWindowActivation(window.processID, stage: "request.validate", result: "rejected")
            return
        }
        logWindowActivation(
            window.processID,
            stage: "request.begin",
            result: application.isActive ? "application-active" : "application-inactive"
        )

        guard hasAccessibilityPermission else {
            let currentRecords = Self.windowRecords().filter {
                $0.processID == window.processID && $0.layer == 0 && $0.alpha > 0 && $0.hasValidBounds
            }
            guard currentRecords.contains(where: { $0.id == window.id }) else { return }
            guard DockWindowTrackerPolicy.shouldUseApplicationActivationFallback(
                targetWindowIsCurrent: true,
                processWindowCount: currentRecords.count
            ) else {
                errorMessage = "需要辅助功能权限才能安全切换多个窗口，请先开启授权。"
                return
            }
            if !application.activate(options: []) {
                logWindowActivation(window.processID, stage: "fallback.activate", result: "rejected")
                errorMessage = "无法将目标应用切换到前台，请稍后重试。"
            } else {
                logWindowActivation(window.processID, stage: "fallback.activate", result: "accepted")
            }
            return
        }

        guard let accessibilityIdentity = window.accessibilityIdentity else {
            logWindowActivation(window.processID, stage: "request.identity", result: "missing")
            if let screenFrame = lastScreenFrame {
                refresh(screenFrame: screenFrame)
            }
            errorMessage = "目标窗口已关闭或正在更新，请稍后重试。"
            return
        }

        currentCancellation?.cancel()
        let activationID = UUID()
        let cancellation = DockWindowCancellation()
        pendingWindowActivationID = activationID
        pendingWindowActionCancellation = cancellation
        let reader = accessibilityReader

        let activateAXWindow: (@escaping (Bool) -> Void) -> Void = { [weak self] completion in
            guard let self else { completion(false); return }
            self.accessibilityQueue.async {
                guard !cancellation.isCancelled else {
                    Task { @MainActor in completion(false) }
                    return
                }
                let didActivate = reader.activate(
                    accessibilityIdentity: accessibilityIdentity,
                    processID: window.processID,
                    applicationPath: window.application.path,
                    cancellation: cancellation
                )
                Task { @MainActor in completion(didActivate) }
            }
        }

        if application.isActive {
            logWindowActivation(window.processID, stage: "frontmost.preexisting", result: "confirmed")
            activateAXWindow { [weak self] didActivate in
                self?.finishWindowActivation(
                    didActivate,
                    activationID: activationID,
                    processID: window.processID,
                    applicationPath: window.application.path
                )
            }
            return
        }

        DockWindowActivationFlow.request(
            isRequestCurrent: { [weak self] in
                self?.pendingWindowActivationID == activationID
            },
            installFrontmostObserver: { [weak self] onFrontmost in
                guard let self else { return }
                let center = NSWorkspace.shared.notificationCenter
                self.pendingWindowActivationObserver = center.addObserver(
                    forName: NSWorkspace.didActivateApplicationNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    guard let activatedApplication = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                          activatedApplication.processIdentifier == pid_t(window.processID),
                          activatedApplication.bundleURL?.path == window.application.path,
                          !activatedApplication.isTerminated,
                          activatedApplication.isActive else { return }
                    Task { @MainActor [weak self] in
                        guard let self,
                              self.pendingWindowActivationID == activationID else { return }
                        logWindowActivation(window.processID, stage: "frontmost.notification", result: "confirmed")
                        onFrontmost(true)
                    }
                }
                logWindowActivation(window.processID, stage: "frontmost.observer", result: "installed")

                let timeout = DispatchWorkItem { [weak self] in
                    logWindowActivation(window.processID, stage: "frontmost.timeout", result: "expired")
                    self?.finishWindowActivation(
                        false,
                        activationID: activationID,
                        processID: window.processID,
                        applicationPath: window.application.path,
                        failureMessage: "目标应用未能切换到前台，请稍后重试。"
                    )
                }
                self.pendingWindowActivationTimeout = timeout
                DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: timeout)
            },
            requestActivation: { [weak self] completion in
                guard let self else { completion(false); return }
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                configuration.createsNewApplicationInstance = false
                configuration.allowsRunningApplicationSubstitution = false
                configuration.addsToRecentItems = false
                configuration.promptsUserIfNeeded = false

                NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) { openedApplication, error in
                    Task { @MainActor [weak self] in
                        guard let self,
                              self.pendingWindowActivationID == activationID else { return }
                        let matchesTarget = openedApplication?.processIdentifier == pid_t(window.processID) &&
                            openedApplication?.bundleURL?.path == applicationURL.path &&
                            openedApplication?.isTerminated == false
                        if let error {
                            let errorCode = (error as NSError).code
                            windowingLogger.error(
                                "window activation pid=\(window.processID, privacy: .public) stage=workspace.open result=failed errorCode=\(errorCode, privacy: .public)"
                            )
                        }
                        logWindowActivation(
                            window.processID,
                            stage: "workspace.open.completion",
                            result: matchesTarget ? "same-process-confirmed" : "target-mismatch"
                        )
                        completion(matchesTarget)
                    }
                }
            },
            activateWindow: activateAXWindow,
            completion: { [weak self] didActivate in
                self?.finishWindowActivation(
                    didActivate,
                    activationID: activationID,
                    processID: window.processID,
                    applicationPath: applicationURL.path,
                    failureMessage: didActivate || application.isActive
                        ? nil
                        : "系统未能激活目标应用，请稍后重试。"
                )
            }
        )
    }

    /// 关闭快照对应的单个窗口；没有 AX 权限或精确窗口身份时不会退化为退出应用。
    func close(_ window: DockWindowSnapshot) {
        cancelPendingWindowActivation()
        guard AXIsProcessTrusted() else {
            hasAccessibilityPermission = false
            errorMessage = "需要辅助功能权限才能关闭指定窗口，请先开启授权。"
            return
        }
        hasAccessibilityPermission = true
        guard let accessibilityIdentity = window.accessibilityIdentity,
              let application = NSRunningApplication(processIdentifier: pid_t(window.processID)),
              !application.isTerminated,
              application.activationPolicy == .regular,
              application.bundleURL?.path == window.application.path,
              !Self.excludedSystemBundleIdentifiers.contains(application.bundleIdentifier ?? ""),
              window.processID != Int32(ProcessInfo.processInfo.processIdentifier) else {
            if let lastScreenFrame { refresh(screenFrame: lastScreenFrame) }
            errorMessage = "目标窗口已关闭或身份已失效，请稍后刷新重试。"
            return
        }

        currentCancellation?.cancel()
        let reader = accessibilityReader
        accessibilityQueue.async { [weak self] in
            let result = reader.close(
                accessibilityIdentity: accessibilityIdentity,
                processID: window.processID,
                applicationPath: window.application.path
            )
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let screenFrame = self.lastScreenFrame { self.refresh(screenFrame: screenFrame) }
                self.errorMessage = result.errorMessage
            }
        }
    }

    /// 移除前台切换观察器并取消超时任务。
    private func stopWaitingForWindowActivation() {
        if let observer = pendingWindowActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            pendingWindowActivationObserver = nil
        }
        pendingWindowActivationTimeout?.cancel()
        pendingWindowActivationTimeout = nil
    }

    /// 取消尚未完成的窗口激活请求及其 AX 操作。
    private func cancelPendingWindowActivation() {
        stopWaitingForWindowActivation()
        pendingWindowActionCancellation?.cancel()
        pendingWindowActionCancellation = nil
        pendingWindowActivationID = nil
    }

    /// 收敛窗口激活结果；失败时阻止队列中的 AX 操作继续执行。
    private func finishWindowActivation(
        _ didActivate: Bool,
        activationID: UUID,
        processID: Int32,
        applicationPath: String,
        failureMessage: String? = nil
    ) {
        guard pendingWindowActivationID == activationID else { return }
        stopWaitingForWindowActivation()
        pendingWindowActivationID = nil
        if !didActivate { pendingWindowActionCancellation?.cancel() }
        pendingWindowActionCancellation = nil

        let application = NSRunningApplication(processIdentifier: pid_t(processID))
        let applicationIsActive = application?.isActive ?? false
        if didActivate,
           let application,
           application.isActive,
           application.activationPolicy == .regular,
           application.bundleURL?.path == applicationPath {
            windowingLogger.info(
                "window activation pid=\(processID, privacy: .public) stage=finish result=success"
            )
            errorMessage = nil
            return
        }
        windowingLogger.error(
            "window activation pid=\(processID, privacy: .public) stage=finish result=failed applicationActive=\(applicationIsActive, privacy: .public)"
        )
        hasAccessibilityPermission = AXIsProcessTrusted()
        if let lastScreenFrame { refresh(screenFrame: lastScreenFrame) }
        errorMessage = failureMessage ?? (hasAccessibilityPermission
            ? "目标窗口已关闭或无法激活，请稍后重试。"
            : "需要辅助功能权限才能安全切换多个窗口，请先开启授权。")
    }

    private func startLatestRefreshIfNeeded() {
        guard !refreshInFlight, let request = latestRequest else { return }
        latestRequest = nil
        refreshInFlight = true
        currentRequest = request
        let cancellation = DockWindowCancellation()
        currentCancellation = cancellation
        let reader = accessibilityReader

        accessibilityQueue.async { [weak self] in
            let result = reader.snapshots(for: request, cancellation: cancellation)
            Task { @MainActor [weak self] in
                self?.finishRefresh(request, result: result, cancellation: cancellation)
            }
        }
    }

    private func finishRefresh(
        _ request: RefreshRequest,
        result: DockAccessibilityScanResult,
        cancellation: DockWindowCancellation
    ) {
        refreshInFlight = false
        if currentRequest?.generation == request.generation { currentRequest = nil }
        if currentCancellation === cancellation { currentCancellation = nil }
        if request.generation == generation, hasAccessibilityPermission {
            for (processID, elements) in result.observedWindows {
                eventMonitor.updateObservedWindows(elements, forProcessID: processID)
            }
            windows = result.snapshots
        }
        startLatestRefreshIfNeeded()
    }

    private static func displayMappings() -> [DockWindowDisplayMapping] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let bounds = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
            guard !bounds.isNull, !bounds.isEmpty else { return nil }
            return DockWindowDisplayMapping(appKitFrame: screen.frame, quartzFrame: bounds)
        }
    }

    private static func runningApplications() -> [Int32: DockWindowApplicationInfo] {
        var result: [Int32: DockWindowApplicationInfo] = [:]
        for application in NSWorkspace.shared.runningApplications {
            let processID = Int32(application.processIdentifier)
            let bundleIdentifier = application.bundleIdentifier ?? ""
            guard processID != Int32(ProcessInfo.processInfo.processIdentifier),
                  application.activationPolicy == .regular,
                  !application.isTerminated,
                  !excludedSystemBundleIdentifiers.contains(bundleIdentifier),
                  let path = application.bundleURL?.path else { continue }
            let name = application.localizedName ?? bundleIdentifier
            result[processID] = DockWindowApplicationInfo(
                application: PinnedApplication(name: name, path: path),
                isRegular: true,
                isExcludedSystemApplication: false
            )
        }
        return result
    }

    private static let excludedSystemBundleIdentifiers: Set<String> = [
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.WindowServer",
        "com.apple.WindowManager",
        "com.apple.controlcenter",
        "com.apple.SystemUIServer",
        "com.apple.notificationcenterui"
    ]

    nonisolated fileprivate static func windowRecords() -> [DockWindowRecord] {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return windows.compactMap { info in
            guard let windowID = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let processID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue,
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                  !bounds.isNull else { return nil }
            return DockWindowRecord(
                id: windowID,
                processID: processID,
                layer: layer,
                alpha: alpha,
                title: info[kCGWindowName as String] as? String ?? "",
                bounds: bounds
            )
        }
    }
}

struct DockWindowDisplayMapping: Equatable {
    let appKitFrame: CGRect
    let quartzFrame: CGRect
}

struct DockWindowRecord: Equatable, Sendable {
    let id: UInt32
    let processID: Int32
    let layer: Int
    let alpha: Double
    let title: String
    let bounds: CGRect

    var hasValidBounds: Bool {
        bounds.width > 0 && bounds.height > 0 &&
            bounds.origin.x.isFinite && bounds.origin.y.isFinite &&
            bounds.width.isFinite && bounds.height.isFinite
    }
}

struct DockWindowApplicationInfo: Sendable {
    let application: PinnedApplication
    let isRegular: Bool
    let isExcludedSystemApplication: Bool
}

struct DockAccessibilityWindowDescriptor: Equatable, Sendable {
    let bounds: CGRect
    let title: String
    let isStandardWindow: Bool
    let isMinimized: Bool

    init(bounds: CGRect, title: String, isStandardWindow: Bool = true, isMinimized: Bool = false) {
        self.bounds = bounds
        self.title = title
        self.isStandardWindow = isStandardWindow
        self.isMinimized = isMinimized
    }
}

struct DockAccessibilityElementIdentity<Element> {
    let id: UInt32
    let accessibilityIdentity: UUID
    let element: Element
}

enum DockWindowTrackerPolicy {
    static func targetDisplayFrame(for appKitFrame: CGRect, mappings: [DockWindowDisplayMapping]) -> CGRect? {
        mappings.max { intersectionArea(appKitFrame, $0.appKitFrame) < intersectionArea(appKitFrame, $1.appKitFrame) }
            .flatMap { intersectionArea(appKitFrame, $0.appKitFrame) > 0 ? $0.quartzFrame : nil }
    }

    static func snapshots(
        from records: [DockWindowRecord],
        applications: [Int32: DockWindowApplicationInfo],
        targetDisplayFrame: CGRect,
        displayFrames: [CGRect],
        currentProcessID: Int32
    ) -> [DockWindowSnapshot] {
        records.compactMap { record in
            guard record.processID != currentProcessID,
                  record.layer == 0,
                  record.alpha > 0,
                  record.hasValidBounds,
                  let app = applications[record.processID],
                  app.isRegular,
                  !app.isExcludedSystemApplication,
                  DockWindowGrouping.belongsToScreen(record.bounds, target: targetDisplayFrame, screens: displayFrames) else {
                return nil
            }
            let title = record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? app.application.name
                : record.title
            return DockWindowSnapshot(
                id: record.id,
                processID: record.processID,
                application: app.application,
                title: title,
                bounds: record.bounds,
                isVerified: false
            )
        }
    }

    static func scanProcessIDs(
        from applications: [Int32: DockWindowApplicationInfo],
        priorityProcessIDs: Set<Int32>?
    ) -> [Int32] {
        let liveProcessIDs = Set(applications.compactMap { processID, application in
            application.isRegular && !application.isExcludedSystemApplication ? processID : nil
        })
        return (priorityProcessIDs.map { $0.intersection(liveProcessIDs) } ?? liveProcessIDs).sorted()
    }

    static func coalescedPriorityProcessIDs(
        active: Set<Int32>?,
        pending: Set<Int32>?,
        incoming: Set<Int32>?
    ) -> Set<Int32>? {
        guard let incoming else { return nil }
        return (active ?? []).union(pending ?? []).union(incoming)
    }

    static func shouldContinueProcessScan(isCancelled: Bool, deadlineNotReached: Bool) -> Bool {
        !isCancelled && deadlineNotReached
    }

    static func shouldUseApplicationActivationFallback(targetWindowIsCurrent: Bool, processWindowCount: Int) -> Bool {
        targetWindowIsCurrent && processWindowCount == 1
    }

    /// 尚未完整读取 AX 的应用保留普通图标；已有缓存只展示本次目标屏幕的窗口。
    static func presentationSnapshots(
        cached: [DockWindowSnapshot],
        raw: [DockWindowSnapshot],
        completedProcesses: Set<Int32>,
        targetDisplayFrame: CGRect,
        displayFrames: [CGRect]
    ) -> [DockWindowSnapshot] {
        let visible = cached.filter {
            DockWindowGrouping.belongsToScreen($0.bounds, target: targetDisplayFrame, screens: displayFrames)
        }
        let verifiedProcesses = Set(visible.map(\.processID))
        return visible + raw.filter {
            !completedProcesses.contains($0.processID) && !verifiedProcesses.contains($0.processID)
        }
    }

    static func stableAccessibilityIdentities<Element>(
        for elements: [Element],
        previous: [DockAccessibilityElementIdentity<Element>],
        inventoryIsComplete: Bool,
        areEqual: (Element, Element) -> Bool,
        allocateIdentity: () -> (id: UInt32, accessibilityIdentity: UUID)?
    ) -> [DockAccessibilityElementIdentity<Element>]? {
        guard inventoryIsComplete else { return nil }
        var unmatchedPrevious = previous
        var result: [DockAccessibilityElementIdentity<Element>] = []
        for element in elements {
            guard !result.contains(where: { areEqual($0.element, element) }) else { continue }
            if let match = unmatchedPrevious.firstIndex(where: { areEqual($0.element, element) }) {
                let previousIdentity = unmatchedPrevious.remove(at: match)
                result.append(DockAccessibilityElementIdentity(
                    id: previousIdentity.id,
                    accessibilityIdentity: previousIdentity.accessibilityIdentity,
                    element: element
                ))
            } else if let identity = allocateIdentity() {
                result.append(DockAccessibilityElementIdentity(
                    id: identity.id,
                    accessibilityIdentity: identity.accessibilityIdentity,
                    element: element
                ))
            }
        }
        return result
    }

    static func liveAccessibilityElement<Element>(
        matching target: Element,
        among elements: [Element],
        areEqual: (Element, Element) -> Bool
    ) -> Element? {
        elements.first { areEqual(target, $0) }
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}

@MainActor
enum DockWindowActivationFlow {
    static func request(
        isRequestCurrent: @escaping () -> Bool,
        installFrontmostObserver: (@escaping (Bool) -> Void) -> Void,
        requestActivation: (@escaping (Bool) -> Void) -> Void,
        activateWindow: @escaping (@escaping (Bool) -> Void) -> Void,
        completion: @escaping (Bool) -> Void
    ) {
        var activationCompleted = false
        var activationAccepted = false
        var frontmostConfirmed = false
        var activationStarted = false
        var completed = false

        func continueWhenReady() {
            guard !completed else { return }
            guard isRequestCurrent() else {
                completed = true
                return
            }
            guard activationCompleted, activationAccepted, frontmostConfirmed,
                  !activationStarted else { return }
            activationStarted = true
            activateWindow { success in
                guard !completed, isRequestCurrent() else {
                    completed = true
                    return
                }
                completed = true
                completion(success)
            }
        }

        installFrontmostObserver { isFrontmost in
            guard isFrontmost, !completed, isRequestCurrent() else { return }
            frontmostConfirmed = true
            continueWhenReady()
        }
        requestActivation { accepted in
            guard !completed else { return }
            guard isRequestCurrent() else {
                completed = true
                return
            }
            activationCompleted = true
            activationAccepted = accepted
            guard accepted else {
                completed = true
                completion(false)
                return
            }
            continueWhenReady()
        }
    }
}

enum DockWindowAXActivationSequence {
    static func perform(
        isMinimized: Bool,
        restoreMinimized: () -> Bool,
        setMain: () -> Bool,
        setFocused: () -> Bool,
        raise: () -> Bool
    ) -> Bool {
        if isMinimized, !restoreMinimized() { return false }
        _ = setMain()
        _ = setFocused()
        return raise()
    }
}

enum DockWindowCloseActionResult: Equatable, Sendable {
    case closed
    case targetUnavailable
    case closeButtonUnavailable
    case actionFailed

    var errorMessage: String? {
        switch self {
        case .closed:
            nil
        case .targetUnavailable:
            "目标窗口已关闭或身份已失效，请稍后刷新重试。"
        case .closeButtonUnavailable:
            "目标应用未提供可访问的窗口关闭按钮，无法安全关闭该窗口。"
        case .actionFailed:
            "目标窗口关闭操作失败，请稍后重试。"
        }
    }
}

enum DockWindowCloseSequence {
    static func perform<Window, Button>(
        target: Window,
        among windows: [Window],
        areEqual: (Window, Window) -> Bool,
        isSupportedWindow: (Window) -> Bool,
        closeButton: (Window) -> Button?,
        press: (Button) -> Bool
    ) -> DockWindowCloseActionResult {
        guard let liveWindow = DockWindowTrackerPolicy.liveAccessibilityElement(
            matching: target,
            among: windows,
            areEqual: areEqual
        ), isSupportedWindow(liveWindow) else {
            return .targetUnavailable
        }
        guard let button = closeButton(liveWindow) else { return .closeButtonUnavailable }
        return press(button) ? .closed : .actionFailed
    }
}

private struct RefreshRequest: Sendable {
    let generation: UInt64
    let records: [DockWindowRecord]
    let applications: [Int32: DockWindowApplicationInfo]
    let targetDisplayFrame: CGRect
    let displayFrames: [CGRect]
    let currentProcessID: Int32
    let priorityProcessIDs: Set<Int32>?
}

private final class DockWindowCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

private struct DockAccessibilityScanResult: @unchecked Sendable {
    let snapshots: [DockWindowSnapshot]
    let observedWindows: [Int32: [AXUIElement]]
}

private struct DockAccessibilityWindowReference {
    let descriptor: DockAccessibilityWindowDescriptor
    let element: AXUIElement
}

private struct DockAccessibilityWindowEnumeration {
    let references: [DockAccessibilityWindowReference]
    let isComplete: Bool
}

/// 所有实例方法只在同一条 serial queue 上调用，AX 元素缓存因此无需锁。
private final class DockAccessibilityWindowReader: @unchecked Sendable {
    private struct WindowKey: Hashable {
        let processID: Int32
        let accessibilityIdentity: UUID
    }

    private struct CachedWindow {
        let id: UInt32
        let element: AXUIElement
    }

    private var windowCache: [WindowKey: CachedWindow] = [:]
    private var snapshotCache: [WindowKey: DockWindowSnapshot] = [:]
    private var nextWindowID: UInt32 = 1
    private var nextProcessOffset = 0
    private var completedProcesses = Set<Int32>()

    func snapshots(
        for request: RefreshRequest,
        cancellation: DockWindowCancellation
    ) -> DockAccessibilityScanResult {
        let deadline = CFAbsoluteTimeGetCurrent() + 0.9
        let processIDs = DockWindowTrackerPolicy.scanProcessIDs(
            from: request.applications,
            priorityProcessIDs: request.priorityProcessIDs
        ).filter { $0 != request.currentProcessID }
        let liveProcesses = Set(request.applications.keys).subtracting([request.currentProcessID])
        windowCache = windowCache.filter { liveProcesses.contains($0.key.processID) }
        snapshotCache = snapshotCache.filter { liveProcesses.contains($0.key.processID) }
        completedProcesses.formIntersection(liveProcesses)

        let processOrder: [Int32]
        if request.priorityProcessIDs != nil || processIDs.isEmpty {
            processOrder = processIDs
        } else {
            let offset = nextProcessOffset % processIDs.count
            processOrder = Array(processIDs[offset...]) + Array(processIDs[..<offset])
            nextProcessOffset = (offset + 1) % processIDs.count
        }

        var observedWindows: [Int32: [AXUIElement]] = [:]
        for processID in processOrder {
            guard DockWindowTrackerPolicy.shouldContinueProcessScan(
                isCancelled: cancellation.isCancelled,
                deadlineNotReached: CFAbsoluteTimeGetCurrent() < deadline
            ) else { break }
            guard let app = request.applications[processID] else { continue }
            let processDeadline = min(deadline, CFAbsoluteTimeGetCurrent() + 0.2)
            let enumeration = accessibilityWindows(processID: processID, deadline: processDeadline)
            let standardWindows = enumeration.references.filter { $0.descriptor.isStandardWindow }
            let previous = windowCache.compactMap { key, cached -> DockAccessibilityElementIdentity<AXUIElement>? in
                guard key.processID == processID else { return nil }
                return DockAccessibilityElementIdentity(
                    id: cached.id,
                    accessibilityIdentity: key.accessibilityIdentity,
                    element: cached.element
                )
            }
            guard let identities = DockWindowTrackerPolicy.stableAccessibilityIdentities(
                for: standardWindows.map(\.element),
                previous: previous,
                inventoryIsComplete: enumeration.isComplete,
                areEqual: { CFEqual($0, $1) },
                allocateIdentity: allocateWindowIdentity
            ) else { continue }
            completedProcesses.insert(processID)
            observedWindows[processID] = standardWindows.map(\.element)
            windowCache = windowCache.filter { $0.key.processID != processID }
            snapshotCache = snapshotCache.filter { $0.key.processID != processID }

            for identity in identities {
                let key = WindowKey(processID: processID, accessibilityIdentity: identity.accessibilityIdentity)
                windowCache[key] = CachedWindow(id: identity.id, element: identity.element)
                guard let reference = standardWindows.first(where: { CFEqual($0.element, identity.element) }),
                      !reference.descriptor.isMinimized,
                      DockWindowGrouping.belongsToScreen(
                        reference.descriptor.bounds,
                        target: request.targetDisplayFrame,
                        screens: request.displayFrames
                      ) else { continue }
                let title = reference.descriptor.title.trimmingCharacters(in: .whitespacesAndNewlines)
                snapshotCache[key] = DockWindowSnapshot(
                    id: identity.id,
                    processID: processID,
                    application: app.application,
                    title: title.isEmpty ? app.application.name : title,
                    bounds: reference.descriptor.bounds,
                    accessibilityIdentity: identity.accessibilityIdentity
                )
            }
        }
        let raw = DockWindowTrackerPolicy.snapshots(
            from: request.records,
            applications: request.applications,
            targetDisplayFrame: request.targetDisplayFrame,
            displayFrames: request.displayFrames,
            currentProcessID: request.currentProcessID
        )
        let snapshots = DockWindowTrackerPolicy.presentationSnapshots(
            cached: Array(snapshotCache.values), raw: raw,
            completedProcesses: completedProcesses,
            targetDisplayFrame: request.targetDisplayFrame, displayFrames: request.displayFrames
        ).sorted {
            if $0.processID == $1.processID { return $0.id < $1.id }
            return $0.processID < $1.processID
        }
        return DockAccessibilityScanResult(snapshots: snapshots, observedWindows: observedWindows)
    }

    func activate(
        accessibilityIdentity: UUID,
        processID: Int32,
        applicationPath: String,
        cancellation: DockWindowCancellation
    ) -> Bool {
        let key = WindowKey(processID: processID, accessibilityIdentity: accessibilityIdentity)
        guard !cancellation.isCancelled else {
            logWindowActivation(processID, stage: "reader.begin", result: "cancelled")
            return false
        }
        guard AXIsProcessTrusted() else {
            logWindowActivation(processID, stage: "reader.permission", result: "denied")
            return false
        }
        guard let cached = windowCache[key] else {
            logWindowActivation(processID, stage: "reader.cache", result: "identity-missing")
            return false
        }
        guard let application = NSRunningApplication(processIdentifier: pid_t(processID)) else {
            logWindowActivation(processID, stage: "reader.application", result: "missing")
            return false
        }
        guard !application.isTerminated,
              application.activationPolicy == .regular,
              application.bundleURL?.path == applicationPath else {
            logWindowActivation(processID, stage: "reader.application", result: "identity-invalid")
            return false
        }
        guard application.isActive else {
            logWindowActivation(processID, stage: "reader.frontmost", result: "inactive-before-ax")
            return false
        }
        logWindowActivation(processID, stage: "reader.begin", result: "application-active")

        var elementProcessID: pid_t = 0
        let processIDError = AXUIElementGetPid(cached.element, &elementProcessID)
        guard processIDError == .success, elementProcessID == pid_t(processID) else {
            logWindowActivation(
                processID,
                stage: "reader.target.pid",
                result: "mismatch",
                axError: processIDError
            )
            return false
        }
        let deadline = CFAbsoluteTimeGetCurrent() + 1.0
        let applicationElement = AXUIElementCreateApplication(pid_t(processID))
        guard let value = copyAttribute(
                  kAXWindowsAttribute as CFString,
                  from: applicationElement,
                  deadline: deadline,
                  timeoutLimit: 1.0,
                  diagnosticStage: "reader.windows",
                  processID: processID
              ) else { return false }
        guard let elements = value as? [AXUIElement] else {
            logWindowActivation(processID, stage: "reader.windows", result: "invalid-type")
            return false
        }
        guard let liveElement = DockWindowTrackerPolicy.liveAccessibilityElement(
            matching: cached.element,
            among: elements,
            areEqual: { CFEqual($0, $1) }
        ) else {
            logWindowActivation(processID, stage: "reader.target.match", result: "not-in-live-windows")
            return false
        }
        guard let role = stringAttribute(
            kAXRoleAttribute,
            from: liveElement,
            deadline: deadline,
            diagnosticStage: "reader.target.role",
            processID: processID
        ), role == (kAXWindowRole as String) else {
            logWindowActivation(processID, stage: "reader.target.role", result: "not-standard-window")
            return false
        }
        guard let subrole = stringAttribute(
            kAXSubroleAttribute,
            from: liveElement,
            deadline: deadline,
            diagnosticStage: "reader.target.subrole",
            processID: processID
        ), subrole == (kAXStandardWindowSubrole as String) else {
            logWindowActivation(processID, stage: "reader.target.subrole", result: "not-standard-window")
            return false
        }
        guard let isMinimized = booleanAttribute(
            kAXMinimizedAttribute,
            from: liveElement,
            deadline: deadline,
            diagnosticStage: "reader.target.minimized",
            processID: processID
        ) else { return false }
        guard setMessagingTimeout(
            on: liveElement,
            deadline: deadline,
            diagnosticStage: "reader.target.timeout",
            processID: processID
        ) else { return false }
        logWindowActivation(processID, stage: "reader.target.match", result: isMinimized ? "matched-minimized" : "matched")

        let didActivate = DockWindowAXActivationSequence.perform(
            isMinimized: isMinimized,
            restoreMinimized: {
                guard !cancellation.isCancelled else {
                    logWindowActivation(processID, stage: "ax.minimized.restore", result: "cancelled")
                    return false
                }
                return self.setAttributeIfSettable(
                    kAXMinimizedAttribute as CFString,
                    value: kCFBooleanFalse,
                    on: liveElement,
                    deadline: deadline,
                    diagnosticStage: "ax.minimized.restore",
                    processID: processID
                )
            },
            setMain: {
                guard !cancellation.isCancelled else {
                    logWindowActivation(processID, stage: "ax.main.set", result: "cancelled")
                    return false
                }
                return self.setAttributeIfSettable(
                    kAXMainAttribute as CFString,
                    value: kCFBooleanTrue,
                    on: liveElement,
                    deadline: deadline,
                    diagnosticStage: "ax.main.set",
                    processID: processID
                )
            },
            setFocused: {
                guard !cancellation.isCancelled else {
                    logWindowActivation(processID, stage: "ax.focused.set", result: "cancelled")
                    return false
                }
                let windowFocused = self.setAttributeIfSettable(
                    kAXFocusedAttribute as CFString,
                    value: kCFBooleanTrue,
                    on: liveElement,
                    deadline: deadline,
                    diagnosticStage: "ax.focused.window-set",
                    processID: processID
                )
                let applicationFocused = self.setAttributeIfSettable(
                    kAXFocusedWindowAttribute as CFString,
                    value: liveElement,
                    on: applicationElement,
                    deadline: deadline,
                    diagnosticStage: "ax.focused.application-set",
                    processID: processID
                )
                logWindowActivation(
                    processID,
                    stage: "ax.focused.set",
                    result: "window-\(windowFocused ? "success" : "failed")-application-\(applicationFocused ? "success" : "failed")"
                )
                return windowFocused || applicationFocused
            },
            raise: {
                guard !cancellation.isCancelled else {
                    logWindowActivation(processID, stage: "ax.raise", result: "cancelled")
                    return false
                }
                guard application.isActive else {
                    logWindowActivation(processID, stage: "ax.raise", result: "application-inactive")
                    return false
                }
                guard self.setMessagingTimeout(
                    on: liveElement,
                    deadline: deadline,
                    diagnosticStage: "ax.raise.timeout",
                    processID: processID
                ) else { return false }
                let actionError = AXUIElementPerformAction(liveElement, kAXRaiseAction as CFString)
                logWindowActivation(
                    processID,
                    stage: "ax.raise",
                    result: actionError == .success ? "success" : "failed",
                    axError: actionError
                )
                return actionError == .success
            }
        )
        guard didActivate, !cancellation.isCancelled else {
            logWindowActivation(processID, stage: "reader.sequence", result: cancellation.isCancelled ? "cancelled" : "failed")
            return false
        }
        guard let focusedWindow = copyAttribute(
            kAXFocusedWindowAttribute as CFString,
            from: applicationElement,
            deadline: deadline,
            diagnosticStage: "reader.focused.verify",
            processID: processID
        ) else {
            logWindowActivation(processID, stage: "reader.focused.verify", result: "unavailable-assumed-success")
            return true
        }
        guard CFGetTypeID(focusedWindow) == AXUIElementGetTypeID() else {
            logWindowActivation(processID, stage: "reader.focused.verify", result: "invalid-type")
            return false
        }
        let targetIsFocused = CFEqual(liveElement, unsafeBitCast(focusedWindow, to: AXUIElement.self))
        logWindowActivation(processID, stage: "reader.focused.verify", result: targetIsFocused ? "target-focused" : "different-window-focused")
        return targetIsFocused
    }

    func close(
        accessibilityIdentity: UUID,
        processID: Int32,
        applicationPath: String
    ) -> DockWindowCloseActionResult {
        let key = WindowKey(processID: processID, accessibilityIdentity: accessibilityIdentity)
        guard AXIsProcessTrusted(),
              let cached = windowCache[key],
              let application = NSRunningApplication(processIdentifier: pid_t(processID)),
              !application.isTerminated,
              application.activationPolicy == .regular,
              application.bundleURL?.path == applicationPath else { return .targetUnavailable }

        var elementProcessID: pid_t = 0
        guard AXUIElementGetPid(cached.element, &elementProcessID) == .success,
              elementProcessID == pid_t(processID) else { return .targetUnavailable }
        let deadline = CFAbsoluteTimeGetCurrent() + 1.0
        let applicationElement = AXUIElementCreateApplication(pid_t(processID))
        guard let value = copyAttribute(
                  kAXWindowsAttribute as CFString,
                  from: applicationElement,
                  deadline: deadline,
                  timeoutLimit: 1.0
              ),
              let elements = value as? [AXUIElement] else { return .targetUnavailable }

        return DockWindowCloseSequence.perform(
            target: cached.element,
            among: elements,
            areEqual: { CFEqual($0, $1) },
            isSupportedWindow: { element in
                var ownerProcessID: pid_t = 0
                return AXUIElementGetPid(element, &ownerProcessID) == .success &&
                    ownerProcessID == pid_t(processID) &&
                    self.stringAttribute(kAXRoleAttribute, from: element, deadline: deadline) == (kAXWindowRole as String) &&
                    self.stringAttribute(kAXSubroleAttribute, from: element, deadline: deadline) == (kAXStandardWindowSubrole as String) &&
                    self.setMessagingTimeout(on: element, deadline: deadline)
            },
            closeButton: { element -> AXUIElement? in
                guard let closeButton = self.copyAttribute(
                    kAXCloseButtonAttribute as CFString,
                    from: element,
                    deadline: deadline
                ), CFGetTypeID(closeButton) == AXUIElementGetTypeID() else { return nil }
                return unsafeBitCast(closeButton, to: AXUIElement.self)
            },
            press: { (button: AXUIElement) in
                var ownerProcessID: pid_t = 0
                guard AXUIElementGetPid(button, &ownerProcessID) == .success,
                      ownerProcessID == pid_t(processID),
                      self.setMessagingTimeout(on: button, deadline: deadline) else { return false }
                return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
            }
        )
    }

    private func allocateWindowIdentity() -> (id: UInt32, accessibilityIdentity: UUID)? {
        guard nextWindowID != 0 else { return nil }
        let id = nextWindowID
        nextWindowID = id == UInt32.max ? 0 : id + 1
        return (id, UUID())
    }

    private func accessibilityWindows(processID: Int32, deadline: CFAbsoluteTime) -> DockAccessibilityWindowEnumeration {
        guard CFAbsoluteTimeGetCurrent() < deadline else { return DockAccessibilityWindowEnumeration(references: [], isComplete: false) }
        let application = AXUIElementCreateApplication(pid_t(processID))
        guard let value = copyAttribute(kAXWindowsAttribute as CFString, from: application, deadline: deadline),
              let elements = value as? [AXUIElement] else {
            return DockAccessibilityWindowEnumeration(references: [], isComplete: false)
        }

        var result: [DockAccessibilityWindowReference] = []
        var isComplete = true
        for element in elements {
            guard CFAbsoluteTimeGetCurrent() < deadline else {
                isComplete = false
                break
            }
            let role = stringAttribute(kAXRoleAttribute, from: element, deadline: deadline)
            let subrole = stringAttribute(kAXSubroleAttribute, from: element, deadline: deadline)
            guard let role, let subrole,
                  let isMinimized = booleanAttribute(kAXMinimizedAttribute, from: element, deadline: deadline) else {
                isComplete = false
                continue
            }
            let isStandardWindow = role == (kAXWindowRole as String) &&
                subrole == (kAXStandardWindowSubrole as String)
            guard let positionValue = valueAttribute(kAXPositionAttribute, from: element, deadline: deadline),
                  CFGetTypeID(positionValue) == AXValueGetTypeID(),
                  let sizeValue = valueAttribute(kAXSizeAttribute, from: element, deadline: deadline),
                  CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
                isComplete = false
                continue
            }
            let position = unsafeBitCast(positionValue, to: AXValue.self)
            let size = unsafeBitCast(sizeValue, to: AXValue.self)
            var point = CGPoint.zero
            var dimensions = CGSize.zero
            guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &dimensions) else {
                isComplete = false
                continue
            }
            let bounds = CGRect(origin: point, size: dimensions)
            guard !bounds.isNull, !bounds.isEmpty,
                  bounds.origin.x.isFinite, bounds.origin.y.isFinite,
                  bounds.width.isFinite, bounds.height.isFinite,
                  let title = stringAttribute(kAXTitleAttribute, from: element, deadline: deadline) else {
                isComplete = false
                continue
            }
            result.append(DockAccessibilityWindowReference(
                descriptor: DockAccessibilityWindowDescriptor(
                    bounds: bounds,
                    title: title,
                    isStandardWindow: isStandardWindow,
                    isMinimized: isMinimized
                ),
                element: element
            ))
        }
        return DockAccessibilityWindowEnumeration(references: result, isComplete: isComplete)
    }

    private func stringAttribute(
        _ attribute: String,
        from element: AXUIElement,
        deadline: CFAbsoluteTime,
        diagnosticStage: String? = nil,
        processID: Int32? = nil
    ) -> String? {
        guard let value = copyAttribute(
            attribute as CFString,
            from: element,
            deadline: deadline,
            diagnosticStage: diagnosticStage,
            processID: processID
        ) else { return nil }
        guard let string = value as? String else {
            if let diagnosticStage, let processID {
                logWindowActivation(processID, stage: diagnosticStage, result: "invalid-type")
            }
            return nil
        }
        return string
    }

    private func booleanAttribute(
        _ attribute: String,
        from element: AXUIElement,
        deadline: CFAbsoluteTime,
        diagnosticStage: String? = nil,
        processID: Int32? = nil
    ) -> Bool? {
        guard let value = copyAttribute(
            attribute as CFString,
            from: element,
            deadline: deadline,
            diagnosticStage: diagnosticStage,
            processID: processID
        ) else { return nil }
        guard let boolean = value as? Bool else {
            if let diagnosticStage, let processID {
                logWindowActivation(processID, stage: diagnosticStage, result: "invalid-type")
            }
            return nil
        }
        return boolean
    }

    private func valueAttribute(_ attribute: String, from element: AXUIElement, deadline: CFAbsoluteTime) -> CFTypeRef? {
        copyAttribute(attribute as CFString, from: element, deadline: deadline)
    }

    private func copyAttribute(
        _ attribute: CFString,
        from element: AXUIElement,
        deadline: CFAbsoluteTime,
        timeoutLimit: TimeInterval = 0.3,
        diagnosticStage: String? = nil,
        processID: Int32? = nil
    ) -> CFTypeRef? {
        let remaining = deadline - CFAbsoluteTimeGetCurrent()
        guard remaining > 0 else {
            if let diagnosticStage, let processID {
                logWindowActivation(processID, stage: diagnosticStage, result: "deadline-expired")
            }
            return nil
        }
        let timeoutError = AXUIElementSetMessagingTimeout(element, Float(min(timeoutLimit, remaining)))
        if timeoutError != .success, let diagnosticStage, let processID {
            logWindowActivation(processID, stage: diagnosticStage, result: "messaging-timeout-set-failed", axError: timeoutError)
        }
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success else {
            if let diagnosticStage, let processID {
                logWindowActivation(processID, stage: diagnosticStage, result: "copy-failed", axError: error)
            }
            return nil
        }
        guard let value else {
            if let diagnosticStage, let processID {
                logWindowActivation(processID, stage: diagnosticStage, result: "copy-empty")
            }
            return nil
        }
        return value
    }

    private func setMessagingTimeout(
        on element: AXUIElement,
        deadline: CFAbsoluteTime,
        diagnosticStage: String? = nil,
        processID: Int32? = nil
    ) -> Bool {
        let remaining = deadline - CFAbsoluteTimeGetCurrent()
        guard remaining > 0 else {
            if let diagnosticStage, let processID {
                logWindowActivation(processID, stage: diagnosticStage, result: "deadline-expired")
            }
            return false
        }
        let error = AXUIElementSetMessagingTimeout(element, Float(min(1.0, remaining)))
        if error != .success, let diagnosticStage, let processID {
            logWindowActivation(processID, stage: diagnosticStage, result: "messaging-timeout-set-failed", axError: error)
        }
        return true
    }

    /// 仅在 AX 明确允许写入时设置属性。
    private func setAttributeIfSettable(
        _ attribute: CFString,
        value: CFTypeRef,
        on element: AXUIElement,
        deadline: CFAbsoluteTime,
        diagnosticStage: String? = nil,
        processID: Int32? = nil
    ) -> Bool {
        guard setMessagingTimeout(
            on: element,
            deadline: deadline,
            diagnosticStage: diagnosticStage,
            processID: processID
        ) else { return false }
        var isSettable = DarwinBoolean(false)
        let settableError = AXUIElementIsAttributeSettable(element, attribute, &isSettable)
        guard settableError == .success else {
            if let diagnosticStage, let processID {
                logWindowActivation(processID, stage: diagnosticStage, result: "settable-check-failed", axError: settableError)
            }
            return false
        }
        guard isSettable.boolValue else {
            if let diagnosticStage, let processID {
                logWindowActivation(processID, stage: diagnosticStage, result: "attribute-not-settable")
            }
            return false
        }
        let setError = AXUIElementSetAttributeValue(element, attribute, value)
        if let diagnosticStage, let processID {
            logWindowActivation(
                processID,
                stage: diagnosticStage,
                result: setError == .success ? "set-success" : "set-failed",
                axError: setError
            )
        }
        return setError == .success
    }

}

private final class DockAccessibilityObserverContext: @unchecked Sendable {
    let processID: Int32
    private let onEvent: @MainActor (Int32) -> Void

    init(processID: Int32, onEvent: @escaping @MainActor (Int32) -> Void) {
        self.processID = processID
        self.onEvent = onEvent
    }

    func signal() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            onEvent(processID)
        }
    }
}

private let dockAccessibilityObserverCallback: AXObserverCallback = { _, _, _, refcon in
    guard let refcon else { return }
    Unmanaged<DockAccessibilityObserverContext>.fromOpaque(refcon).takeUnretainedValue().signal()
}

/// AXObserver source 留在主 RunLoop；只在主线程创建、更新和释放 observer。
@MainActor
private final class DockAccessibilityEventMonitor {
    private struct ProcessObserver: @unchecked Sendable {
        let observer: AXObserver
        let context: DockAccessibilityObserverContext
        let applicationElement: AXUIElement
        var windowElements: [AXUIElement]
    }

    private let onEvent: @MainActor (Int32) -> Void
    private let registrationQueue = DispatchQueue(label: "GlassDock.AXObserver.Registration", qos: .userInitiated)
    private var observers: [Int32: ProcessObserver] = [:]

    init(onEvent: @escaping @MainActor (Int32) -> Void) {
        self.onEvent = onEvent
    }

    deinit {
        for registration in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(registration.observer), .commonModes)
        }
    }

    func updateLiveApplications(_ processIDs: Set<Int32>) {
        guard AXIsProcessTrusted() else {
            shutdown()
            return
        }
        for processID in Array(observers.keys) where !processIDs.contains(processID) {
            removeObserver(forProcessID: processID)
        }
        for processID in processIDs where observers[processID] == nil {
            addObserver(forProcessID: processID)
        }
    }

    func updateObservedWindows(_ elements: [AXUIElement], forProcessID processID: Int32) {
        guard var registration = observers[processID] else { return }
        var uniqueElements: [AXUIElement] = []
        for element in elements where !uniqueElements.contains(where: { CFEqual($0, element) }) {
            uniqueElements.append(element)
        }

        let removed = registration.windowElements.filter { old in
            !uniqueElements.contains(where: { CFEqual(old, $0) })
        }
        for element in removed {
            removeWindowNotifications(from: element, registration: registration)
        }
        for element in uniqueElements where !registration.windowElements.contains(where: { CFEqual($0, element) }) {
            addWindowNotifications(to: element, registration: registration)
        }
        registration.windowElements = uniqueElements
        observers[processID] = registration
    }

    func shutdown() {
        for processID in Array(observers.keys) {
            removeObserver(forProcessID: processID)
        }
    }

    private func addObserver(forProcessID processID: Int32) {
        var observer: AXObserver?
        guard AXObserverCreate(pid_t(processID), dockAccessibilityObserverCallback, &observer) == .success,
              let observer else { return }

        let context = DockAccessibilityObserverContext(processID: processID, onEvent: onEvent)
        let applicationElement = AXUIElementCreateApplication(pid_t(processID))
        let registration = ProcessObserver(
            observer: observer,
            context: context,
            applicationElement: applicationElement,
            windowElements: []
        )
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        registrationQueue.async {
            AXUIElementSetMessagingTimeout(applicationElement, 0.05)
            for notification in Self.applicationNotifications {
                AXObserverAddNotification(observer, applicationElement, notification as CFString, Unmanaged.passUnretained(registration.context).toOpaque())
            }
        }
        observers[processID] = registration
    }

    private func removeObserver(forProcessID processID: Int32) {
        guard let registration = observers.removeValue(forKey: processID) else { return }
        for element in registration.windowElements {
            removeWindowNotifications(from: element, registration: registration)
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(registration.observer), .commonModes)
        registrationQueue.async {
            for notification in Self.applicationNotifications {
                AXObserverRemoveNotification(registration.observer, registration.applicationElement, notification as CFString)
            }
        }
    }

    private func addWindowNotifications(to element: AXUIElement, registration: ProcessObserver) {
        registrationQueue.async {
            AXUIElementSetMessagingTimeout(element, 0.05)
            let refcon = Unmanaged.passUnretained(registration.context).toOpaque()
            for notification in Self.windowNotifications {
                AXObserverAddNotification(registration.observer, element, notification as CFString, refcon)
            }
        }
    }

    private func removeWindowNotifications(from element: AXUIElement, registration: ProcessObserver) {
        registrationQueue.async {
            for notification in Self.windowNotifications {
                AXObserverRemoveNotification(registration.observer, element, notification as CFString)
            }
        }
    }

    nonisolated private static let applicationNotifications = [
        kAXWindowCreatedNotification as String,
        kAXFocusedWindowChangedNotification as String,
        kAXMainWindowChangedNotification as String
    ]

    nonisolated private static let windowNotifications = [
        kAXUIElementDestroyedNotification as String,
        kAXTitleChangedNotification as String,
        kAXMovedNotification as String,
        kAXResizedNotification as String,
        kAXWindowMiniaturizedNotification as String,
        kAXWindowDeminiaturizedNotification as String
    ]
}
