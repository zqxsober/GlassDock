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

@Suite("Dashboard sheet coordination", .serialized)
@MainActor
struct DashboardSheetCoordinationTests {
    private func makeStore(tag: String = "v0.1.0") -> (String, UserDefaults, AppStore, MockFetcher) {
        let name = "GlassDockTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let release = GitHubRelease(tagName: tag, name: tag, body: "说明",
                                    htmlURL: URL(string: "https://github.com/zqxsober/GlassDock/releases/tag/\(tag)")!,
                                    draft: false, prerelease: false, publishedAt: nil)
        let fetcher = MockFetcher(.success(.release(release)))
        let checker = UpdateChecker(defaults: defaults, fetcher: fetcher, currentVersion: "0.0.1", isMainWindowVisible: { true })
        return (name, defaults, AppStore(defaults: defaults, updateChecker: checker), fetcher)
    }

    @Test func updateFoundDuringOnboardingIsShownAfterFinishing() async {
        let (name, defaults, store, _) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        store.mainWindowDidAppear()
        #expect(store.activeSheet == .onboarding)
        await store.updateChecker.check(manual: false)
        #expect(store.activeSheet == .onboarding)
        #expect(store.queuedSheet?.id == "update-v0.1.0")
        store.finishOnboarding()
        #expect(store.activeSheet?.id == "update-v0.1.0")
        #expect(store.queuedSheet == nil)
    }

    @Test func onboardingRequestedDuringUpdateReplacesItAndUpdateReturns() async {
        let (name, defaults, store, _) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(OnboardingPolicy.currentVersion, forKey: OnboardingPolicy.completedVersionKey)
        await store.updateChecker.check(manual: false)
        #expect(store.activeSheet?.id == "update-v0.1.0")
        store.presentSheet(.onboarding)
        #expect(store.activeSheet == .onboarding)
        #expect(store.queuedSheet?.id == "update-v0.1.0")
        store.finishOnboarding()
        #expect(store.activeSheet?.id == "update-v0.1.0")
    }

    @Test func skippingClosesUpdateSheet() async {
        let (name, defaults, store, _) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(OnboardingPolicy.currentVersion, forKey: OnboardingPolicy.completedVersionKey)
        await store.updateChecker.check(manual: false)
        guard case .update(let release) = store.activeSheet else { Issue.record("no update sheet"); return }
        store.updateChecker.skip(release)
        #expect(store.activeSheet == nil)
        #expect(store.queuedSheet == nil)
    }

    @Test func laterClosesUpdateSheetWithoutReprompting() async {
        let (name, defaults, store, _) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(OnboardingPolicy.currentVersion, forKey: OnboardingPolicy.completedVersionKey)
        await store.updateChecker.check(manual: false)
        guard case .update(let release) = store.activeSheet else { Issue.record("no update sheet"); return }
        store.updateChecker.snooze(release)
        #expect(store.activeSheet == nil)
        store.mainWindowDidAppear()
        #expect(store.activeSheet == nil)
    }

    @Test func windowCloseRequeuesUpdateAndDropsOnboarding() async {
        let (name, defaults, store, _) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        store.mainWindowDidAppear()
        await store.updateChecker.check(manual: false)
        store.sheetDismissedWithoutAction() // 主窗口在引导期间被关掉
        #expect(store.activeSheet == nil)
        #expect(defaults.integer(forKey: OnboardingPolicy.completedVersionKey) == OnboardingPolicy.pendingVersion)
        store.mainWindowDidAppear()
        #expect(store.activeSheet?.id == "update-v0.1.0")
        store.sheetDismissedWithoutAction() // 再次关窗：更新提示排回队列
        #expect(store.queuedSheet?.id == "update-v0.1.0")
        store.mainWindowDidAppear()
        #expect(store.activeSheet?.id == "update-v0.1.0")
    }

    @Test func newerUpdateReplacesOlderOne() async {
        let (name, defaults, store, fetcher) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(OnboardingPolicy.currentVersion, forKey: OnboardingPolicy.completedVersionKey)
        await store.updateChecker.check(manual: false)
        fetcher.result = .success(.release(GitHubRelease(
            tagName: "v0.2.0", name: nil, body: nil,
            htmlURL: URL(string: "https://github.com/zqxsober/GlassDock/releases/tag/v0.2.0")!,
            draft: false, prerelease: false, publishedAt: nil)))
        await store.updateChecker.check(manual: true)
        #expect(store.activeSheet?.id == "update-v0.2.0")
    }
}
