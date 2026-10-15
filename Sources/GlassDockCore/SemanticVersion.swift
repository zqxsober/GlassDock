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

/// major.minor.patch 版本号；忽略开头的 v/V，缺失的段补 0，带 `-` 后缀的视为预发布。
public struct SemanticVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let isPrerelease: Bool

    public init(major: Int, minor: Int = 0, patch: Int = 0, isPrerelease: Bool = false) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.isPrerelease = isPrerelease
    }

    public init?(_ text: String) {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.first == "v" || value.first == "V" { value.removeFirst() }
        if let plus = value.firstIndex(of: "+") { value = String(value[..<plus]) }
        var prerelease = false
        if let dash = value.firstIndex(of: "-") {
            prerelease = true
            value = String(value[..<dash])
        }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isASCII), let number = Int(part), number >= 0 else { return nil }
            numbers.append(number)
        }
        while numbers.count < 3 { numbers.append(0) }
        self.init(major: numbers[0], minor: numbers[1], patch: numbers[2], isPrerelease: prerelease)
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        // 同号时预发布版本更低（1.0.0-beta < 1.0.0）。
        return lhs.isPrerelease && !rhs.isPrerelease
    }
}

public enum UpdatePolicy {
    public static let checkInterval: TimeInterval = 24 * 60 * 60
    public static let autoCheckKey = "GlassDock.update.autoCheck"
    public static let skippedVersionKey = "GlassDock.update.skippedVersion"
    public static let lastCheckDateKey = "GlassDock.update.lastCheckDate"

    /// 最新 release 比当前版本新、且不是 draft/预发布时返回它的版本号。
    /// 任一版本号无法解析（例如开发构建的 "dev"）时视为没有更新。
    public static func newerVersion(current: String, latestTag: String,
                                    isDraft: Bool = false, isPrerelease: Bool = false) -> SemanticVersion? {
        guard !isDraft, !isPrerelease,
              let latest = SemanticVersion(latestTag), !latest.isPrerelease,
              let installed = SemanticVersion(current), installed < latest else { return nil }
        return latest
    }

    /// 自动检查是否应弹出提示：忽略的版本和本次启动内点过「稍后」的版本不再提示。
    public static func shouldPromptAutomatically(latestTag: String, skippedVersion: String?,
                                                 snoozedVersions: Set<String> = []) -> Bool {
        guard let latest = SemanticVersion(latestTag) else { return false }
        if let skippedVersion, SemanticVersion(skippedVersion) == latest { return false }
        return !snoozedVersions.contains { SemanticVersion($0) == latest }
    }

    /// 开发构建（版本号无法解析）或关闭开关时不做自动检查。
    public static func shouldAutoCheck(enabled: Bool, currentVersion: String) -> Bool {
        enabled && SemanticVersion(currentVersion) != nil
    }

    /// 距上次检查已满 24 小时（或从未检查、时钟回拨）时到期。
    public static func isCheckDue(lastCheck: Date?, now: Date, interval: TimeInterval = checkInterval) -> Bool {
        guard let lastCheck else { return true }
        let elapsed = now.timeIntervalSince(lastCheck)
        return elapsed >= interval || elapsed < 0
    }

    /// 发布说明摘要：取前 `limit` 个字符。
    public static func summary(of notes: String?, limit: Int = 600) -> String {
        let trimmed = (notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "…"
    }
}
