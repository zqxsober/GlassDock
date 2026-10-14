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

import CoreFoundation
import Foundation

public struct CodexUsageWindow: Equatable, Sendable {
    public let remainingPercent: Double
    public let resetsAt: Date?

    public init(usedPercent: Double, resetsAt: Date? = nil) {
        self.remainingPercent = min(100, max(0, 100 - usedPercent))
        if let resetsAt {
            let timestamp = resetsAt.timeIntervalSince1970
            self.resetsAt = timestamp.isFinite && (0...253_402_300_799).contains(timestamp) ? resetsAt : nil
        } else {
            self.resetsAt = nil
        }
    }
}

public struct CodexUsageSnapshot: Equatable, Sendable {
    public let fiveHour: CodexUsageWindow?
    public let sevenDay: CodexUsageWindow?

    public init(fiveHour: CodexUsageWindow?, sevenDay: CodexUsageWindow?) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }
}

public enum CodexUsageParser {
    public static func parse(responseData: Data) -> CodexUsageSnapshot? {
        guard let response = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let result = response["result"] as? [String: Any] else { return nil }
        return parse(result: result)
    }

    public static func parse(result: [String: Any]) -> CodexUsageSnapshot? {
        let codexLimits = (result["rateLimitsByLimitId"] as? [String: Any])?["codex"] as? [String: Any]
        let fallbackLimits = result["rateLimits"] as? [String: Any]

        if let codexLimits, let snapshot = parse(limits: codexLimits) { return snapshot }
        guard let fallbackLimits else { return nil }
        return parse(limits: fallbackLimits)
    }

    private static func parse(limits: [String: Any]) -> CodexUsageSnapshot? {
        var fiveHour: CodexUsageWindow?
        var sevenDay: CodexUsageWindow?

        let orderedKeys = ["primary", "secondary"] + limits.keys.filter { $0 != "primary" && $0 != "secondary" }.sorted()
        let candidates = orderedKeys.compactMap { limits[$0] as? [String: Any] }
        let values = candidates.isEmpty && limits["windowDurationMins"] != nil ? [limits] : candidates

        for value in values {
            guard let duration = number(value["windowDurationMins"]),
                  let usedPercent = number(value["usedPercent"]) else { continue }

            let resetDate = number(value["resetsAt"]).map(Date.init(timeIntervalSince1970:))
            let window = CodexUsageWindow(usedPercent: usedPercent, resetsAt: resetDate)
            switch duration {
            case 300 where fiveHour == nil:
                fiveHour = window
            case 10_080 where sevenDay == nil:
                sevenDay = window
            default:
                continue
            }
        }

        guard fiveHour != nil || sevenDay != nil else { return nil }
        return CodexUsageSnapshot(fiveHour: fiveHour, sevenDay: sevenDay)
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        let number = value.doubleValue
        return number.isFinite ? number : nil
    }
}

public enum CodexUsageCountdown {
    public static func formatted(until date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let seconds = max(0, Int(ceil(date.timeIntervalSince(now))))
        guard seconds > 0 else { return "即将重置" }

        let days = seconds / 86_400
        let hours = seconds % 86_400 / 3_600
        let minutes = seconds % 3_600 / 60
        if days > 0 { return hours > 0 ? "\(days)天\(hours)小时" : "\(days)天" }
        if hours > 0 { return minutes > 0 ? "\(hours)小时\(minutes)分" : "\(hours)小时" }
        let roundedMinutes = (seconds % 3_600 + 59) / 60
        return "\(max(1, roundedMinutes))分"
    }
}
