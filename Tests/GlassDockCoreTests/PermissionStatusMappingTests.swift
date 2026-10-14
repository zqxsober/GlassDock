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

import GlassDockCore
import Testing

@Suite("Permission status mapping")
struct PermissionStatusMappingTests {
    @Test func eventKitStatuses() {
        #expect(PermissionStatusMapping.eventKit(.fullAccess) == .granted)
        #expect(PermissionStatusMapping.eventKit(.notDetermined) == .notGranted)
        #expect(PermissionStatusMapping.eventKit(.denied) == .denied)
        #expect(PermissionStatusMapping.eventKit(.restricted) == .denied)
        #expect(PermissionStatusMapping.eventKit(.writeOnly) == .denied)
        #expect(PermissionStatusMapping.eventKit(.unknown) == .unavailable)
    }

    @Test func appleEventStatuses() {
        #expect(PermissionStatusMapping.appleEvents(0) == .granted)
        #expect(PermissionStatusMapping.appleEvents(-1744) == .notGranted)
        #expect(PermissionStatusMapping.appleEvents(-1743) == .denied)
        #expect(PermissionStatusMapping.appleEvents(-600) == .unavailable)
    }

    @Test func accessibilityUsesPromptedFlagAsDenied() {
        #expect(PermissionStatusMapping.accessibility(isTrusted: true, hasPrompted: false) == .granted)
        #expect(PermissionStatusMapping.accessibility(isTrusted: true, hasPrompted: true) == .granted)
        #expect(PermissionStatusMapping.accessibility(isTrusted: false, hasPrompted: false) == .notGranted)
        #expect(PermissionStatusMapping.accessibility(isTrusted: false, hasPrompted: true) == .denied)
    }
}
