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

@Suite("Onboarding persistence", .serialized)
@MainActor
struct OnboardingStoreTests {
    private func isolatedDefaults() -> (String, UserDefaults) {
        let name = "GlassDockTests.\(UUID().uuidString)"
        return (name, UserDefaults(suiteName: name)!)
    }

    @Test func freshInstallPresentsOnceAndFinishingPersists() {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = AppStore(defaults: defaults)
        store.presentOnboardingIfNeeded()
        #expect(store.isOnboardingPresented)
        store.finishOnboarding()
        #expect(!store.isOnboardingPresented)
        #expect(defaults.integer(forKey: OnboardingPolicy.completedVersionKey) == OnboardingPolicy.currentVersion)

        let relaunched = AppStore(defaults: defaults)
        relaunched.presentOnboardingIfNeeded()
        #expect(!relaunched.isOnboardingPresented)
    }

    @Test func closingWithoutFinishingShowsAgainOnNextLaunch() {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = AppStore(defaults: defaults)
        store.presentOnboardingIfNeeded()
        store.sheetDismissedWithoutAction() // 主窗口关闭时 sheet 随之消失
        store.preferences.showClock = false // 新用户此时已经写入了偏好
        let relaunched = AppStore(defaults: defaults)
        relaunched.presentOnboardingIfNeeded()
        #expect(relaunched.isOnboardingPresented)
    }

    @Test func upgradingUserIsMarkedCompletedWithoutGuide() {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        AppStore(defaults: defaults).preferences.showClock = false // 模拟 v0.0.1 留下的偏好
        defaults.removeObject(forKey: OnboardingPolicy.completedVersionKey)
        let upgraded = AppStore(defaults: defaults)
        upgraded.presentOnboardingIfNeeded()
        #expect(!upgraded.isOnboardingPresented)
        #expect(defaults.integer(forKey: OnboardingPolicy.completedVersionKey) == OnboardingPolicy.currentVersion)
    }
}
