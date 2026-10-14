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

import AppKit
import Carbon
import Foundation
import Testing
@testable import GlassDock

@Suite("Music AppleEvent parsing")
struct MusicAppleScriptBridgeTests {
    @Test func parsesTypedValuesWithoutLocaleSensitiveTextConversion() {
        let descriptor = NSAppleEventDescriptor.list()
        descriptor.insert(NSAppleEventDescriptor(string: "Song\u{1f}, 1.5"), at: 1)
        descriptor.insert(NSAppleEventDescriptor(string: "Artist, One"), at: 2)
        descriptor.insert(NSAppleEventDescriptor(double: 17.25), at: 3)
        descriptor.insert(NSAppleEventDescriptor(double: 202.75), at: 4)
        descriptor.insert(NSAppleEventDescriptor(string: "playing"), at: 5)
        descriptor.insert(NSAppleEventDescriptor(string: "TRACK-1"), at: 6)
        descriptor.insert(NSAppleEventDescriptor(string: "Album 1"), at: 7)

        let snapshot = MusicAppleScriptBridge.parseSnapshot(descriptor)

        #expect(snapshot?.title == "Song\u{1f}, 1.5")
        #expect(snapshot?.artist == "Artist, One")
        #expect(snapshot?.position == 17.25)
        #expect(snapshot?.duration == 202.75)
        #expect(snapshot?.isPlaying == true)
        #expect(snapshot?.currentTrackIdentity?.contains("TRACK-1") == true)
        #expect(snapshot?.isConnected == true)
    }

    @Test func missingTrackPropertiesDoNotDiscardOtherMetadata() {
        let descriptor = NSAppleEventDescriptor.list()
        descriptor.insert(NSAppleEventDescriptor.null(), at: 1)
        descriptor.insert(NSAppleEventDescriptor(string: "Known artist"), at: 2)
        descriptor.insert(NSAppleEventDescriptor(double: -3), at: 3)
        descriptor.insert(NSAppleEventDescriptor(double: 0), at: 4)
        descriptor.insert(NSAppleEventDescriptor(string: "stopped"), at: 5)
        descriptor.insert(NSAppleEventDescriptor.null(), at: 6)
        descriptor.insert(NSAppleEventDescriptor(string: ""), at: 7)

        let snapshot = MusicAppleScriptBridge.parseSnapshot(descriptor)

        #expect(snapshot?.title == "")
        #expect(snapshot?.artist == "Known artist")
        #expect(snapshot?.position == 0)
        #expect(snapshot?.duration == 0)
        #expect(snapshot?.currentTrackIdentity == nil)
        #expect(snapshot?.isConnected == true)
    }

    @Test func artworkParserReturnsRawDataForTheExpectedTrackOnly() throws {
        let artwork = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a])
        let metadata = NSAppleEventDescriptor.list()
        metadata.insert(NSAppleEventDescriptor(string: "Song"), at: 1)
        metadata.insert(NSAppleEventDescriptor(string: "Artist"), at: 2)
        metadata.insert(NSAppleEventDescriptor(double: 0), at: 3)
        metadata.insert(NSAppleEventDescriptor(double: 100), at: 4)
        metadata.insert(NSAppleEventDescriptor(string: "playing"), at: 5)
        metadata.insert(NSAppleEventDescriptor(string: "TRACK-1"), at: 6)
        metadata.insert(NSAppleEventDescriptor(string: "Album"), at: 7)
        let expectedTrackIdentity = try #require(MusicAppleScriptBridge.parseSnapshot(metadata)?.currentTrackIdentity)

        let descriptor = NSAppleEventDescriptor.list()
        descriptor.insert(NSAppleEventDescriptor(string: "TRACK-1"), at: 1)
        descriptor.insert(NSAppleEventDescriptor(string: "Song"), at: 2)
        descriptor.insert(NSAppleEventDescriptor(string: "Artist"), at: 3)
        descriptor.insert(NSAppleEventDescriptor(string: "Album"), at: 4)
        let artworkDescriptor = try #require(NSAppleEventDescriptor(descriptorType: typeData, data: artwork))
        descriptor.insert(artworkDescriptor, at: 5)

        #expect(MusicAppleScriptBridge.parseArtwork(descriptor, expectedTrackIdentity: expectedTrackIdentity) == artwork)
        #expect(MusicAppleScriptBridge.parseArtwork(descriptor, expectedTrackIdentity: "another-track") == nil)
    }

    @Test func mapsAutomationConsentStatesSeparately() {
        #expect(MusicAppleScriptBridge.accessState(forPermissionStatus: noErr) == .authorized)
        #expect(MusicAppleScriptBridge.accessState(forPermissionStatus: OSStatus(errAEEventWouldRequireUserConsent)) == .notRequested)
        #expect(MusicAppleScriptBridge.accessState(forPermissionStatus: OSStatus(errAEEventNotPermitted)) == .denied)
        #expect(MusicAppleScriptBridge.accessState(forPermissionStatus: OSStatus(procNotFound)) == .unavailable)
    }

    @Test func trackIdentityUsesStreamTitleWhenMusicHasNoUsefulPersistentID() {
        let descriptor = NSAppleEventDescriptor.list()
        descriptor.insert(NSAppleEventDescriptor(string: "Stream title"), at: 1)
        descriptor.insert(NSAppleEventDescriptor(string: "Artist"), at: 2)
        descriptor.insert(NSAppleEventDescriptor(double: 0), at: 3)
        descriptor.insert(NSAppleEventDescriptor(double: 180), at: 4)
        descriptor.insert(NSAppleEventDescriptor(string: "playing"), at: 5)
        descriptor.insert(NSAppleEventDescriptor(string: "0000000000000000"), at: 6)
        descriptor.insert(NSAppleEventDescriptor(string: "Album"), at: 7)

        #expect(MusicAppleScriptBridge.parseSnapshot(descriptor)?.currentTrackIdentity?.contains("Stream title") == true)
    }
}

@Suite("Music runtime polling")
struct MusicRuntimePollingTests {
    @Test func rechecksPermissionAndPollsEvenBeforeAConnectionSnapshotExists() {
        let now = Date(timeIntervalSince1970: 10_000)
        #expect(WidgetMusicPolling.shouldCheckPermissionOrRefresh(
            hasMusicWidgets: true,
            musicIsRunning: true,
            lastRefreshAt: nil,
            now: now
        ))
        #expect(!WidgetMusicPolling.shouldCheckPermissionOrRefresh(
            hasMusicWidgets: true,
            musicIsRunning: true,
            lastRefreshAt: now.addingTimeInterval(-4),
            now: now
        ))
        #expect(WidgetMusicPolling.shouldCheckPermissionOrRefresh(
            hasMusicWidgets: true,
            musicIsRunning: true,
            lastRefreshAt: now.addingTimeInterval(-5),
            now: now
        ))
        #expect(!WidgetMusicPolling.shouldCheckPermissionOrRefresh(
            hasMusicWidgets: true,
            musicIsRunning: false,
            lastRefreshAt: nil,
            now: now
        ))
    }

    @Test func serializesQueriesWithCommandsAndIgnoresOlderResponses() {
        #expect(!WidgetMusicPolling.canStartAutomaticRefresh(
            queryInFlight: true,
            commandInFlight: false,
            pendingCommandCount: 0
        ))
        #expect(!WidgetMusicPolling.canStartAutomaticRefresh(
            queryInFlight: false,
            commandInFlight: false,
            pendingCommandCount: 1
        ))
        #expect(WidgetMusicPolling.canStartAutomaticRefresh(
            queryInFlight: false,
            commandInFlight: false,
            pendingCommandCount: 0
        ))
        #expect(!WidgetMusicPolling.isLatestResponse(4, latestRevision: 5))
        #expect(WidgetMusicPolling.isLatestResponse(5, latestRevision: 5))
    }
}
