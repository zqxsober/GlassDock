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

final class MockFetcher: UpdateFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls = 0
    var result: Result<UpdateFetchResult, Error>

    init(_ result: Result<UpdateFetchResult, Error>) { self.result = result }

    var calls: Int { lock.withLock { _calls } }

    func fetchLatestRelease(userAgent: String) async throws -> UpdateFetchResult {
        lock.withLock { _calls += 1 }
        return try result.get()
    }
}

@Suite("Update checker", .serialized)
@MainActor
struct UpdateCheckerTests {
    private func isolatedDefaults() -> (String, UserDefaults) {
        let name = "GlassDockTests.\(UUID().uuidString)"
        return (name, UserDefaults(suiteName: name)!)
    }

    private func release(_ tag: String, prerelease: Bool = false) -> GitHubRelease {
        GitHubRelease(tagName: tag, name: tag, body: "新功能", htmlURL: URL(string: "https://github.com/zqxsober/GlassDock/releases/tag/\(tag)")!,
                      draft: false, prerelease: prerelease, publishedAt: nil)
    }

    @Test func automaticCheckFindsNewerReleaseAndPromptsWhenWindowVisible() async {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let fetcher = MockFetcher(.success(.release(release("v0.1.0"))))
        let checker = UpdateChecker(defaults: defaults, fetcher: fetcher, currentVersion: "0.0.1", isMainWindowVisible: { true })
        await checker.check(manual: false)
        #expect(fetcher.calls == 1)
        #expect(checker.presentedRelease?.tagName == "v0.1.0")
        #expect(checker.pendingRelease?.tagName == "v0.1.0")
        #expect(checker.lastCheckDate != nil)
    }

    @Test func closedWindowOnlyShowsMenuItemUntilWindowOpens() async {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let checker = UpdateChecker(defaults: defaults, fetcher: MockFetcher(.success(.release(release("v0.1.0")))),
                                    currentVersion: "0.0.1", isMainWindowVisible: { false })
        await checker.check(manual: false)
        #expect(checker.presentedRelease == nil)
        #expect(checker.pendingRelease?.tagName == "v0.1.0")
        checker.mainWindowDidAppear()
        #expect(checker.presentedRelease?.tagName == "v0.1.0")
    }

    @Test func skippedVersionIsNotPromptedButNewerIs() async {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let fetcher = MockFetcher(.success(.release(release("v0.1.0"))))
        let checker = UpdateChecker(defaults: defaults, fetcher: fetcher, currentVersion: "0.0.1", isMainWindowVisible: { true })
        await checker.check(manual: false)
        checker.skip(release("v0.1.0"))
        #expect(checker.pendingRelease == nil)
        await checker.check(manual: false)
        #expect(checker.presentedRelease == nil)
        #expect(checker.pendingRelease == nil)
        #expect(checker.state == .available(release("v0.1.0"), skipped: true))

        fetcher.result = .success(.release(release("v0.2.0")))
        await checker.check(manual: false)
        #expect(checker.presentedRelease?.tagName == "v0.2.0")
    }

    @Test func laterSuppressesAutomaticPromptForThisSessionOnly() async {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let fetcher = MockFetcher(.success(.release(release("v0.1.0"))))
        let checker = UpdateChecker(defaults: defaults, fetcher: fetcher, currentVersion: "0.0.1", isMainWindowVisible: { true })
        await checker.check(manual: false)
        checker.snooze(release("v0.1.0"))
        await checker.check(manual: false)
        #expect(checker.presentedRelease == nil)
        #expect(checker.pendingRelease != nil)

        let relaunched = UpdateChecker(defaults: defaults, fetcher: fetcher, currentVersion: "0.0.1", isMainWindowVisible: { true })
        await relaunched.check(manual: false)
        #expect(relaunched.presentedRelease?.tagName == "v0.1.0")
    }

    @Test func disabledAutoCheckMakesNoRequests() async {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(false, forKey: UpdatePolicy.autoCheckKey)
        let fetcher = MockFetcher(.success(.release(release("v0.1.0"))))
        let checker = UpdateChecker(defaults: defaults, fetcher: fetcher, currentVersion: "0.0.1", isMainWindowVisible: { true })
        checker.start()
        await checker.check(manual: false)
        await Task.yield()
        #expect(fetcher.calls == 0)
        #expect(!checker.hasScheduledTimer)
        await checker.check(manual: true)
        #expect(fetcher.calls == 1)
    }

    @Test func turningOffAutoCheckCancelsTimer() async {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let checker = UpdateChecker(defaults: defaults, fetcher: MockFetcher(.success(.noRelease)),
                                    currentVersion: "0.0.1", isMainWindowVisible: { false })
        checker.start()
        #expect(checker.hasScheduledTimer)
        checker.isAutoCheckEnabled = false
        #expect(!checker.hasScheduledTimer)
        #expect(defaults.object(forKey: UpdatePolicy.autoCheckKey) as? Bool == false)
    }

    @Test func networkFailureIsSilentForAutomaticAndShownForManual() async {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let fetcher = MockFetcher(.failure(URLError(.notConnectedToInternet)))
        let checker = UpdateChecker(defaults: defaults, fetcher: fetcher, currentVersion: "0.0.1", isMainWindowVisible: { true })
        await checker.check(manual: false)
        #expect(checker.state == .idle)
        #expect(checker.presentedRelease == nil)
        await checker.check(manual: true)
        #expect(checker.state == .failed(devBuild: false))

        fetcher.result = .failure(UpdateFetchError.httpStatus(429))
        await checker.check(manual: true)
        #expect(checker.state == .failed(devBuild: false))
    }

    @Test func manualResultsCoverUpToDateAndNoRelease() async {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let fetcher = MockFetcher(.success(.release(release("v0.0.1"))))
        let checker = UpdateChecker(defaults: defaults, fetcher: fetcher, currentVersion: "0.0.1", isMainWindowVisible: { true })
        await checker.check(manual: true)
        #expect(checker.state == .upToDate(current: "0.0.1"))
        fetcher.result = .success(.noRelease)
        await checker.check(manual: true)
        #expect(checker.state == .upToDate(current: "0.0.1"))
        fetcher.result = .success(.release(release("v0.2.0-beta.1", prerelease: true)))
        await checker.check(manual: true)
        #expect(checker.state == .upToDate(current: "0.0.1"))
    }

    @Test func devBuildSkipsAutomaticCheck() async {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let fetcher = MockFetcher(.success(.release(release("v0.1.0"))))
        let checker = UpdateChecker(defaults: defaults, fetcher: fetcher, currentVersion: "dev", isMainWindowVisible: { true })
        await checker.check(manual: false)
        #expect(fetcher.calls == 0)
        await checker.check(manual: true)
        #expect(fetcher.calls == 0)
        #expect(checker.state == .failed(devBuild: true))
    }

    @Test func decodesGitHubReleasePayload() throws {
        let json = Data("""
        {"tag_name":"v0.1.0","name":"GlassDock 0.1.0","body":"- 新增引导","html_url":"https://github.com/zqxsober/GlassDock/releases/tag/v0.1.0",
         "draft":false,"prerelease":false,"published_at":"2026-10-14T09:00:00Z","assets":[]}
        """.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(GitHubRelease.self, from: json)
        #expect(decoded.tagName == "v0.1.0")
        #expect(decoded.displayVersion == "0.1.0")
        #expect(decoded.publishedAt != nil)
    }
}
