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

@Suite("Semantic version comparison")
struct SemanticVersionTests {
    @Test func parsesWithAndWithoutPrefix() {
        #expect(SemanticVersion("0.0.1") == SemanticVersion(major: 0, minor: 0, patch: 1))
        #expect(SemanticVersion("v0.0.1") == SemanticVersion(major: 0, minor: 0, patch: 1))
        #expect(SemanticVersion("V1.2") == SemanticVersion(major: 1, minor: 2, patch: 0))
        #expect(SemanticVersion("2") == SemanticVersion(major: 2))
        #expect(SemanticVersion("1.0.0-beta.1")?.isPrerelease == true)
        #expect(SemanticVersion("1.0.0+build.5") == SemanticVersion(major: 1))
    }

    @Test func rejectsInvalidVersions() {
        #expect(SemanticVersion("dev") == nil)
        #expect(SemanticVersion("") == nil)
        #expect(SemanticVersion("1..2") == nil)
        #expect(SemanticVersion("1.2.3.4") == nil)
        #expect(SemanticVersion("1.-2.0") == nil)
    }

    @Test func equalVersionsAreNotAnUpdate() {
        #expect(UpdatePolicy.newerVersion(current: "0.0.1", latestTag: "v0.0.1") == nil)
        #expect(UpdatePolicy.newerVersion(current: "1.0", latestTag: "1.0.0") == nil)
    }

    @Test func higherPatchMinorAndMajorAreUpdates() {
        #expect(UpdatePolicy.newerVersion(current: "0.0.1", latestTag: "0.0.2") == SemanticVersion("0.0.2"))
        #expect(UpdatePolicy.newerVersion(current: "0.0.9", latestTag: "0.1.0") == SemanticVersion("0.1.0"))
        #expect(UpdatePolicy.newerVersion(current: "0.9.9", latestTag: "1.0.0") == SemanticVersion("1.0.0"))
        #expect(UpdatePolicy.newerVersion(current: "0.0.10", latestTag: "0.0.9") == nil)
        #expect(UpdatePolicy.newerVersion(current: "1.0.0", latestTag: "0.9.0") == nil)
    }

    @Test func vPrefixIsIgnoredOnEitherSide() {
        #expect(UpdatePolicy.newerVersion(current: "v0.0.1", latestTag: "v0.1.0") == SemanticVersion("0.1.0"))
        #expect(UpdatePolicy.newerVersion(current: "0.0.1", latestTag: "V0.1.0") == SemanticVersion("0.1.0"))
    }

    @Test func prereleaseAndDraftAreIgnored() {
        #expect(UpdatePolicy.newerVersion(current: "0.0.1", latestTag: "v0.1.0-beta.1") == nil)
        #expect(UpdatePolicy.newerVersion(current: "0.0.1", latestTag: "v0.1.0", isPrerelease: true) == nil)
        #expect(UpdatePolicy.newerVersion(current: "0.0.1", latestTag: "v0.1.0", isDraft: true) == nil)
        #expect(SemanticVersion("1.0.0-rc.1")! < SemanticVersion("1.0.0")!)
    }

    @Test func devBuildNeverReportsUpdate() {
        #expect(UpdatePolicy.newerVersion(current: "dev", latestTag: "v9.9.9") == nil)
    }
}
