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
import Foundation
import GlassDockCore

struct GitHubRelease: Decodable, Equatable, Identifiable, Sendable {
    var id: String { tagName }
    var tagName: String
    var name: String?
    var body: String?
    var htmlURL: URL
    var draft: Bool
    var prerelease: Bool
    var publishedAt: Date?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name", name, body, htmlURL = "html_url", draft, prerelease, publishedAt = "published_at"
    }

    var displayVersion: String { SemanticVersion(tagName)?.description ?? tagName }
}

enum UpdateFetchResult: Equatable, Sendable {
    case release(GitHubRelease)
    /// 仓库还没有任何 release（404）。
    case noRelease
}

enum UpdateFetchError: Error, Equatable {
    case httpStatus(Int)
    case invalidResponse
}

protocol UpdateFetching: Sendable {
    func fetchLatestRelease(userAgent: String) async throws -> UpdateFetchResult
}

/// 只读取 GitHub 公开 API：不带 Cookie、不带 token、不上传任何用户数据。
struct GitHubReleaseFetcher: UpdateFetching {
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/zqxsober/GlassDock/releases/latest")!

    func fetchLatestRelease(userAgent: String) async throws -> UpdateFetchResult {
        var request = URLRequest(url: Self.latestReleaseURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateFetchError.invalidResponse }
        if http.statusCode == 404 { return .noRelease }
        guard (200..<300).contains(http.statusCode) else { throw UpdateFetchError.httpStatus(http.statusCode) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return .release(try decoder.decode(GitHubRelease.self, from: data))
    }
}

enum UpdateCheckState: Equatable {
    case idle
    case checking
    case upToDate(current: String)
    case available(GitHubRelease, skipped: Bool)
    case failed(devBuild: Bool)
}

@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var state: UpdateCheckState = .idle
    /// 菜单栏「有新版本…」与小圆点：自动/手动检查发现、尚未忽略的新版本。
    @Published private(set) var pendingRelease: GitHubRelease?
    /// 非 nil 时主窗口弹出更新提示 sheet。
    @Published var presentedRelease: GitHubRelease?
    @Published private(set) var lastCheckDate: Date?
    @Published var isAutoCheckEnabled: Bool {
        didSet {
            defaults.set(isAutoCheckEnabled, forKey: UpdatePolicy.autoCheckKey)
            isAutoCheckEnabled ? scheduleTimer() : cancelTimer()
        }
    }

    let currentVersion: String
    private let defaults: UserDefaults
    private let fetcher: UpdateFetching
    private let isMainWindowVisible: @MainActor () -> Bool
    private var timer: Timer?
    private var activationObserver: AnyCancellable?
    private var snoozedVersions: Set<String> = []
    private var isChecking = false
    private var started = false

    init(defaults: UserDefaults = .standard,
         fetcher: UpdateFetching = GitHubReleaseFetcher(),
         currentVersion: String = AppVersion.current,
         isMainWindowVisible: @escaping @MainActor () -> Bool = { UpdateChecker.mainWindowIsVisible() }) {
        self.defaults = defaults
        self.fetcher = fetcher
        self.currentVersion = currentVersion
        self.isMainWindowVisible = isMainWindowVisible
        isAutoCheckEnabled = defaults.object(forKey: UpdatePolicy.autoCheckKey) as? Bool ?? true
        lastCheckDate = defaults.object(forKey: UpdatePolicy.lastCheckDateKey) as? Date
    }

    var skippedVersion: String? { defaults.string(forKey: UpdatePolicy.skippedVersionKey) }

    private var canAutoCheck: Bool {
        UpdatePolicy.shouldAutoCheck(enabled: isAutoCheckEnabled, currentVersion: currentVersion)
    }

    /// 启动时调用一次：检查一次并安排每 24 小时的定时检查；回到前台时超过 24 小时补检。
    func start() {
        guard !started else { return }
        started = true
        activationObserver = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.canAutoCheck,
                      UpdatePolicy.isCheckDue(lastCheck: self.lastCheckDate, now: Date()) else { return }
                Task { await self.check(manual: false) }
            }
        guard canAutoCheck else { return }
        scheduleTimer()
        Task { await check(manual: false) }
    }

    func checkNow() { Task { await check(manual: true) } }

    func check(manual: Bool) async {
        guard !isChecking else { return }
        guard manual || canAutoCheck else { return }
        guard SemanticVersion(currentVersion) != nil else {
            state = .failed(devBuild: true)
            return
        }
        isChecking = true
        defer { isChecking = false }
        if manual { state = .checking }
        let userAgent = "GlassDock/\(currentVersion)"
        do {
            let result = try await fetcher.fetchLatestRelease(userAgent: userAgent)
            recordCheck()
            handle(result, manual: manual)
        } catch {
            NSLog("GlassDock update check failed: %@", String(describing: error))
            state = manual ? .failed(devBuild: false) : .idle
        }
    }

    private func handle(_ result: UpdateFetchResult, manual: Bool) {
        guard case .release(let release) = result,
              UpdatePolicy.newerVersion(current: currentVersion, latestTag: release.tagName,
                                        isDraft: release.draft, isPrerelease: release.prerelease) != nil else {
            pendingRelease = nil
            state = .upToDate(current: currentVersion)
            return
        }
        let skipped = !UpdatePolicy.shouldPromptAutomatically(latestTag: release.tagName, skippedVersion: skippedVersion)
        state = .available(release, skipped: skipped)
        if manual {
            presentedRelease = release
            return
        }
        // 已忽略的版本不显示菜单项和小圆点。
        pendingRelease = skipped ? nil : release
        if UpdatePolicy.shouldPromptAutomatically(latestTag: release.tagName, skippedVersion: skippedVersion,
                                                  snoozedVersions: snoozedVersions),
           isMainWindowVisible() {
            presentedRelease = release
        }
    }

    /// 用户自己打开主窗口时，弹出尚未处理（未忽略、未点「稍后」）的新版本提示。
    func mainWindowDidAppear() {
        guard presentedRelease == nil, let pendingRelease,
              UpdatePolicy.shouldPromptAutomatically(latestTag: pendingRelease.tagName, skippedVersion: skippedVersion,
                                                     snoozedVersions: snoozedVersions) else { return }
        presentedRelease = pendingRelease
    }

    /// 菜单栏「有新版本…」：打开主窗口并显示提示。
    func showPendingRelease() {
        guard let pendingRelease else { return }
        presentedRelease = pendingRelease
    }

    func download(_ release: GitHubRelease) {
        NSWorkspace.shared.open(release.htmlURL)
        presentedRelease = nil
    }

    func skip(_ release: GitHubRelease) {
        defaults.set(release.tagName, forKey: UpdatePolicy.skippedVersionKey)
        if pendingRelease?.tagName == release.tagName { pendingRelease = nil }
        if case .available(let current, _) = state, current.tagName == release.tagName {
            state = .available(current, skipped: true)
        }
        presentedRelease = nil
    }

    /// 「稍后」：仅本次启动内不再自动弹出，菜单项保留以便手动打开。
    func snooze(_ release: GitHubRelease) {
        snoozedVersions.insert(release.tagName)
        presentedRelease = nil
    }

    private func recordCheck() {
        let now = Date()
        lastCheckDate = now
        defaults.set(now, forKey: UpdatePolicy.lastCheckDateKey)
    }

    private func scheduleTimer() {
        guard started, timer == nil, canAutoCheck else { return }
        timer = Timer.scheduledTimer(withTimeInterval: UpdatePolicy.checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.check(manual: false) }
        }
    }

    private func cancelTimer() {
        timer?.invalidate()
        timer = nil
    }

    var hasScheduledTimer: Bool { timer != nil }

    static func mainWindowIsVisible() -> Bool {
        NSApp?.windows.contains { $0.identifier?.rawValue == "glassdock-main" && $0.isVisible } ?? false
    }
}
