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
@testable import GlassDockCore

@Suite("Codex usage parsing")
struct CodexUsageTests {
    @Test func prefersCodexLimitsAndMatchesWindowsByDuration() throws {
        let response = try JSONSerialization.data(withJSONObject: [
            "result": [
                "rateLimitsByLimitId": [
                    "codex": [
                        "primary": ["usedPercent": 25.0, "windowDurationMins": 300, "resetsAt": 1_800_000_000],
                        "secondary": ["usedPercent": 60.0, "windowDurationMins": 10_080, "resetsAt": 1_800_100_000]
                    ]
                ],
                "rateLimits": [
                    "primary": ["usedPercent": 99.0, "windowDurationMins": 300]
                ]
            ]
        ])

        let snapshot = try #require(CodexUsageParser.parse(responseData: response))
        #expect(snapshot.fiveHour?.remainingPercent == 75)
        #expect(snapshot.fiveHour?.resetsAt == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(snapshot.sevenDay?.remainingPercent == 40)
        #expect(snapshot.sevenDay?.resetsAt == Date(timeIntervalSince1970: 1_800_100_000))
    }

    @Test func usesFallbackLimitsAndLeavesUnavailableWindowsNil() throws {
        let response = try JSONSerialization.data(withJSONObject: [
            "result": [
                "rateLimitsByLimitId": ["other": [:]],
                "rateLimits": [
                    "primary": ["usedPercent": 125.0, "windowDurationMins": 300],
                    "secondary": ["usedPercent": 30.0, "windowDurationMins": 1_440]
                ]
            ]
        ])

        let snapshot = try #require(CodexUsageParser.parse(responseData: response))
        #expect(snapshot.fiveHour?.remainingPercent == 0)
        #expect(snapshot.fiveHour?.resetsAt == nil)
        #expect(snapshot.sevenDay == nil)
    }

    @Test func countdownUsesResetDateAndReturnsNilWhenDateIsMissing() {
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(CodexUsageCountdown.formatted(until: nil, now: now) == nil)
        #expect(CodexUsageCountdown.formatted(until: now.addingTimeInterval(90), now: now) == "2分")
        #expect(CodexUsageCountdown.formatted(until: now, now: now) == "即将重置")
    }
}
