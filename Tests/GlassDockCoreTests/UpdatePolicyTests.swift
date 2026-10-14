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

@Suite("Update check policy")
struct UpdatePolicyTests {
    @Test func skippedVersionIsNotPromptedButNewerOneIs() {
        #expect(!UpdatePolicy.shouldPromptAutomatically(latestTag: "v0.1.0", skippedVersion: "v0.1.0"))
        #expect(!UpdatePolicy.shouldPromptAutomatically(latestTag: "v0.1.0", skippedVersion: "0.1.0"))
        #expect(UpdatePolicy.shouldPromptAutomatically(latestTag: "v0.1.1", skippedVersion: "v0.1.0"))
        #expect(UpdatePolicy.shouldPromptAutomatically(latestTag: "v0.1.0", skippedVersion: nil))
    }

    @Test func snoozedVersionIsNotPromptedAgainThisSession() {
        #expect(!UpdatePolicy.shouldPromptAutomatically(latestTag: "v0.1.0", skippedVersion: nil, snoozedVersions: ["v0.1.0"]))
        #expect(UpdatePolicy.shouldPromptAutomatically(latestTag: "v0.2.0", skippedVersion: nil, snoozedVersions: ["v0.1.0"]))
    }

    @Test func autoCheckRequiresSwitchAndReleaseBuild() {
        #expect(UpdatePolicy.shouldAutoCheck(enabled: true, currentVersion: "0.0.1"))
        #expect(!UpdatePolicy.shouldAutoCheck(enabled: false, currentVersion: "0.0.1"))
        #expect(!UpdatePolicy.shouldAutoCheck(enabled: true, currentVersion: "dev"))
    }

    @Test func checkIsDueEvery24Hours() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(UpdatePolicy.isCheckDue(lastCheck: nil, now: now))
        #expect(!UpdatePolicy.isCheckDue(lastCheck: now.addingTimeInterval(-60), now: now))
        #expect(!UpdatePolicy.isCheckDue(lastCheck: now.addingTimeInterval(-(24 * 3600 - 1)), now: now))
        #expect(UpdatePolicy.isCheckDue(lastCheck: now.addingTimeInterval(-24 * 3600), now: now))
        #expect(UpdatePolicy.isCheckDue(lastCheck: now.addingTimeInterval(-30 * 3600), now: now))
        #expect(UpdatePolicy.isCheckDue(lastCheck: now.addingTimeInterval(3600), now: now))
    }

    @Test func summaryTrimsLongNotes() {
        #expect(UpdatePolicy.summary(of: nil) == "")
        #expect(UpdatePolicy.summary(of: "  短说明 \n") == "短说明")
        let long = String(repeating: "a", count: 700)
        #expect(UpdatePolicy.summary(of: long).count == 601)
    }
}
