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
@testable import GlassDock

@Suite("Music artwork cache transitions")
@MainActor
struct MusicArtworkCacheTests {
    @Test func unavailableArtworkRemainsEligibleForAnotherPoll() {
        let runtime = WidgetRuntime()
        runtime.applyMusicResponse(.init(access: .authorized,
                                        snapshot: WidgetMusicState(title: "Loading", isConnected: true, currentTrackIdentity: "Loading"),
                                        errorNumber: nil, errorMessage: nil, artworkLookupTrackIdentity: "Loading"),
                                   showErrors: false)
        #expect(runtime.cachedArtworkTrackIdentity == nil)
    }

    @Test func failedArtworkOnAnotherTrackDoesNotKeepThePreviousTrackMarkedCached() {
        let runtime = WidgetRuntime()
        let artwork = Data([1, 2, 3])
        runtime.applyMusicResponse(.init(access: .authorized,
                                        snapshot: WidgetMusicState(title: "A", isConnected: true,
                                                                   currentTrackIdentity: "A", artworkData: artwork),
                                        errorNumber: nil, errorMessage: nil, artworkLookupTrackIdentity: "A"),
                                   showErrors: false)
        #expect(runtime.cachedArtworkTrackIdentity == "A")
        runtime.applyMusicResponse(.init(access: .authorized,
                                        snapshot: WidgetMusicState(title: "B", isConnected: true, currentTrackIdentity: "B"),
                                        errorNumber: nil, errorMessage: nil), showErrors: false)
        #expect(runtime.music.artworkData == nil)
        #expect(runtime.cachedArtworkTrackIdentity == nil)
        runtime.applyMusicResponse(.init(access: .authorized,
                                        snapshot: WidgetMusicState(title: "A", isConnected: true,
                                                                   currentTrackIdentity: "A", artworkData: artwork),
                                        errorNumber: nil, errorMessage: nil, artworkLookupTrackIdentity: "A"),
                                   showErrors: false)
        #expect(runtime.music.artworkData == artwork)
        #expect(runtime.cachedArtworkTrackIdentity == "A")
    }
}
