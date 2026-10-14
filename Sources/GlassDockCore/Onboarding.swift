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

/// 引导页展示的统一权限状态。
public enum PermissionStatus: String, Equatable, Sendable {
    case notGranted
    case granted
    case denied
    /// 目前无法判断，例如“音乐”未运行。
    case unavailable
}

/// 与 `EKAuthorizationStatus` 一一对应，便于在 Core 中测试映射。
public enum EventKitAuthorization: Equatable, Sendable {
    case notDetermined, restricted, denied, fullAccess, writeOnly, unknown
}

public enum PermissionStatusMapping {
    /// 辅助功能没有系统层面的“拒绝”：点过授权仍未授予时按被拒绝处理，引导用户去系统设置。
    public static func accessibility(isTrusted: Bool, hasPrompted: Bool) -> PermissionStatus {
        if isTrusted { return .granted }
        return hasPrompted ? .denied : .notGranted
    }

    public static func eventKit(_ status: EventKitAuthorization) -> PermissionStatus {
        switch status {
        case .fullAccess: .granted
        case .notDetermined: .notGranted
        case .denied, .restricted, .writeOnly: .denied
        case .unknown: .unavailable
        }
    }

    /// `AEDeterminePermissionToAutomateTarget` 的返回值。
    public static func appleEvents(_ status: Int32) -> PermissionStatus {
        switch status {
        case 0: .granted // noErr
        case -1744: .notGranted // errAEEventWouldRequireUserConsent
        case -1743: .denied // errAEEventNotPermitted
        default: .unavailable // procNotFound 等：音乐未运行
        }
    }
}

public enum OnboardingPolicy {
    /// 引导内容有实质变化时调高，老用户会再次看到引导。
    public static let currentVersion = 1
    /// 全新安装首次弹出后、尚未完成时写入的占位值。
    public static let pendingVersion = 0
    public static let completedVersionKey = "GlassDock.onboarding.completedVersion"
    public static let accessibilityPromptedKey = "GlassDock.onboarding.axPrompted"

    public enum LaunchDecision: Equatable, Sendable {
        /// 全新安装：自动弹出引导。
        case present
        /// v0.0.1 老用户升级：不弹，并直接记为已完成。
        case markCompletedSilently
        /// 已完成过：什么都不做。
        case none
    }

    /// 必须在 AppStore 首次保存偏好之前判定，否则新用户会被误判为老用户。
    public static func launchDecision(completedVersion: Int?, hasExistingPreferences: Bool,
                                      currentVersion: Int = currentVersion) -> LaunchDecision {
        if let completedVersion, completedVersion >= currentVersion { return .none }
        if completedVersion == nil, hasExistingPreferences { return .markCompletedSilently }
        return .present
    }
}
