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

@Suite("Onboarding launch policy")
struct OnboardingPolicyTests {
    @Test func freshInstallPresentsGuide() {
        #expect(OnboardingPolicy.launchDecision(completedVersion: nil, hasExistingPreferences: false) == .present)
    }

    @Test func upgradingUserWithPreferencesIsNotInterrupted() {
        #expect(OnboardingPolicy.launchDecision(completedVersion: nil, hasExistingPreferences: true) == .markCompletedSilently)
    }

    @Test func unfinishedGuideIsShownAgainEvenAfterPreferencesWereSaved() {
        #expect(OnboardingPolicy.launchDecision(completedVersion: OnboardingPolicy.pendingVersion, hasExistingPreferences: true) == .present)
    }

    @Test func completedGuideIsNotShownAgain() {
        #expect(OnboardingPolicy.launchDecision(completedVersion: 1, hasExistingPreferences: true) == .none)
        #expect(OnboardingPolicy.launchDecision(completedVersion: 1, hasExistingPreferences: false) == .none)
        #expect(OnboardingPolicy.launchDecision(completedVersion: 2, hasExistingPreferences: false, currentVersion: 1) == .none)
    }

    @Test func newerGuideVersionIsShownToPreviousFinishers() {
        #expect(OnboardingPolicy.launchDecision(completedVersion: 1, hasExistingPreferences: true, currentVersion: 2) == .present)
    }

    @Test func completionPersistsInUserDefaults() {
        let name = "GlassDockTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(defaults.object(forKey: OnboardingPolicy.completedVersionKey) as? Int == nil)
        defaults.set(OnboardingPolicy.currentVersion, forKey: OnboardingPolicy.completedVersionKey)
        let reloaded = UserDefaults(suiteName: name)!
        let stored = reloaded.object(forKey: OnboardingPolicy.completedVersionKey) as? Int
        #expect(OnboardingPolicy.launchDecision(completedVersion: stored, hasExistingPreferences: false) == .none)
    }

    @Test func localizationFollowsPreferredLanguage() {
        #expect(L10n.text(zh: "完成", en: "Done", preferredLanguages: ["zh-Hans-CN"]) == "完成")
        #expect(L10n.text(zh: "完成", en: "Done", preferredLanguages: ["zh-Hant"]) == "完成")
        #expect(L10n.text(zh: "完成", en: "Done", preferredLanguages: ["en-US", "zh-Hans"]) == "Done")
        #expect(L10n.text(zh: "完成", en: "Done", preferredLanguages: ["ja"]) == "Done")
        #expect(L10n.text(zh: "完成", en: "Done", preferredLanguages: []) == "完成")
    }
}
