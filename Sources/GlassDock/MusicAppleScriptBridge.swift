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

enum MusicAppleScriptBridge {
    private static let applicationBundleIdentifier = "com.apple.Music"
    private static let scriptQueue = DispatchQueue(label: "GlassDock.MusicAppleScriptBridge")

    static var isRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: applicationBundleIdentifier)
            .contains { !$0.isTerminated }
    }

    enum Command: Sendable {
        case playPause
        case nextTrack
        case previousTrack

        fileprivate var source: String {
            switch self {
            case .playPause: "with timeout of 3 seconds\ntell application \"Music\" to playpause\nend timeout"
            case .nextTrack: "with timeout of 3 seconds\ntell application \"Music\" to next track\nend timeout"
            case .previousTrack: "with timeout of 3 seconds\ntell application \"Music\" to previous track\nend timeout"
            }
        }
    }

    struct Response: Sendable {
        var access: WidgetAccessState
        var snapshot: WidgetMusicState?
        var errorNumber: Int?
        var errorMessage: String?
        var artworkLookupTrackIdentity: String? = nil
    }

    static func query(askUserIfNeeded: Bool, knownArtworkTrackIdentity: String?) -> Response {
        scriptQueue.sync {
            queryNow(askUserIfNeeded: askUserIfNeeded, knownArtworkTrackIdentity: knownArtworkTrackIdentity)
        }
    }

    static func performAndQuery(_ command: Command, knownArtworkTrackIdentity: String?) -> Response {
        scriptQueue.sync {
            guard isRunning else {
                return Response(access: .unavailable, snapshot: nil, errorNumber: nil, errorMessage: "音乐 App 已关闭。")
            }
            let access = determineAccess(askUserIfNeeded: false)
            guard access == .authorized else {
                return Response(access: access, snapshot: nil, errorNumber: nil, errorMessage: nil)
            }
            let commandResult = execute(command.source)
            guard commandResult.succeeded else {
                return Response(
                    access: commandResult.errorNumber == -1743 ? .denied : access,
                    snapshot: nil,
                    errorNumber: commandResult.errorNumber,
                    errorMessage: commandResult.errorMessage
                )
            }
            return queryAuthorizedMusic(knownArtworkTrackIdentity: knownArtworkTrackIdentity)
        }
    }

    static func accessState(forPermissionStatus status: OSStatus) -> WidgetAccessState {
        if status == noErr { return .authorized }
        if status == OSStatus(errAEEventWouldRequireUserConsent) { return .notRequested }
        if status == OSStatus(errAEEventNotPermitted) { return .denied }
        return .unavailable
    }

    static func parseSnapshot(_ descriptor: NSAppleEventDescriptor) -> WidgetMusicState? {
        guard descriptor.numberOfItems >= 6 else { return nil }

        let title = descriptor.atIndex(1)?.stringValue ?? ""
        let artist = descriptor.atIndex(2)?.stringValue ?? ""
        let position = nonnegativeNumber(descriptor.atIndex(3))
        let duration = nonnegativeNumber(descriptor.atIndex(4))
        let playerState = descriptor.atIndex(5)?.stringValue ?? ""
        let persistentIdentity = descriptor.atIndex(6)?.stringValue ?? ""
        let album = descriptor.numberOfItems >= 7 ? descriptor.atIndex(7)?.stringValue ?? "" : ""
        let identity = trackIdentity(persistentIdentity: persistentIdentity, title: title, artist: artist, album: album)
        return WidgetMusicState(
            title: title,
            artist: artist,
            isPlaying: playerState.localizedCaseInsensitiveCompare("playing") == .orderedSame,
            position: position,
            duration: duration,
            isConnected: true,
            currentTrackIdentity: identity
        )
    }

    static func parseArtwork(_ descriptor: NSAppleEventDescriptor, expectedTrackIdentity: String) -> Data? {
        guard descriptor.numberOfItems >= 5 else { return nil }
        let persistentIdentity = descriptor.atIndex(1)?.stringValue ?? ""
        let title = descriptor.atIndex(2)?.stringValue ?? ""
        let artist = descriptor.atIndex(3)?.stringValue ?? ""
        let album = descriptor.atIndex(4)?.stringValue ?? ""
        guard trackIdentity(persistentIdentity: persistentIdentity, title: title, artist: artist, album: album)
                == expectedTrackIdentity,
              let dataDescriptor = descriptor.atIndex(5) else { return nil }
        let data = dataDescriptor.data
        return data.isEmpty ? nil : data
    }

    private static func trackIdentity(persistentIdentity: String, title: String, artist: String, album: String) -> String? {
        let normalizedPersistentIdentity = persistentIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPersistentIdentity = !normalizedPersistentIdentity.isEmpty
            && normalizedPersistentIdentity.contains(where: { $0 != "0" })
        guard hasPersistentIdentity || !title.isEmpty else { return nil }
        let components = [hasPersistentIdentity ? normalizedPersistentIdentity : "", title, artist, album]
        return components.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
    }

    private static func queryNow(askUserIfNeeded: Bool, knownArtworkTrackIdentity: String?) -> Response {
        guard isRunning else {
            return Response(access: .unavailable, snapshot: nil, errorNumber: nil, errorMessage: "音乐 App 已关闭。")
        }
        let access = determineAccess(askUserIfNeeded: askUserIfNeeded)
        guard access == .authorized else {
            return Response(access: access, snapshot: nil, errorNumber: nil, errorMessage: nil)
        }
        return queryAuthorizedMusic(knownArtworkTrackIdentity: knownArtworkTrackIdentity)
    }

    private static func queryAuthorizedMusic(knownArtworkTrackIdentity: String?) -> Response {
        let result = execute(snapshotSource)
        guard result.succeeded, let descriptor = result.descriptor,
              var snapshot = parseSnapshot(descriptor) else {
            return Response(
                access: result.errorNumber == -1743 ? .denied : .authorized,
                snapshot: nil,
                errorNumber: result.errorNumber,
                errorMessage: result.errorMessage ?? "音乐 App 返回的数据格式无法识别。"
            )
        }
        snapshot.positionUpdatedAt = Date()

        var artworkLookupTrackIdentity: String?
        if let trackIdentity = snapshot.currentTrackIdentity,
           trackIdentity != knownArtworkTrackIdentity {
            let artworkResult = artworkData(expectedTrackIdentity: trackIdentity)
            snapshot.artworkData = artworkResult.data
            if artworkResult.matchedExpectedTrack { artworkLookupTrackIdentity = trackIdentity }
        }
        return Response(
            access: .authorized,
            snapshot: snapshot,
            errorNumber: nil,
            errorMessage: nil,
            artworkLookupTrackIdentity: artworkLookupTrackIdentity
        )
    }

    private static func determineAccess(askUserIfNeeded: Bool) -> WidgetAccessState {
        guard isRunning else { return .unavailable }
        let target = NSAppleEventDescriptor(bundleIdentifier: applicationBundleIdentifier)
        guard let addressDescriptor = target.aeDesc else { return .unavailable }
        let status = AEDeterminePermissionToAutomateTarget(
            addressDescriptor,
            typeWildCard,
            typeWildCard,
            askUserIfNeeded
        )
        return accessState(forPermissionStatus: status)
    }

    private static func artworkData(expectedTrackIdentity: String) -> ArtworkResult {
        let source = #"""
        with timeout of 3 seconds
            tell application "Music"
                set persistentIdentityValue to ""
                set titleValue to ""
                set artistValue to ""
                set albumValue to ""
                set artworkValue to missing value
                try
                    set trackValue to current track
                    try
                        set persistentIdentityValue to (persistent ID of trackValue as text)
                    end try
                    try
                        set titleValue to (name of trackValue as text)
                    end try
                    try
                        set artistValue to (artist of trackValue as text)
                    end try
                    try
                        set albumValue to (album of trackValue as text)
                    end try
                    try
                        set artworkValue to (raw data of artwork 1 of trackValue)
                    on error
                        try
                            set artworkValue to (data of artwork 1 of trackValue)
                        end try
                    end try
                end try
                return {persistentIdentityValue, titleValue, artistValue, albumValue, artworkValue}
            end tell
        end timeout
        """#
        let result = execute(source)
        guard result.succeeded, let descriptor = result.descriptor else {
            return ArtworkResult(data: nil, matchedExpectedTrack: false)
        }
        let actualIdentity = trackIdentity(
            persistentIdentity: descriptor.atIndex(1)?.stringValue ?? "",
            title: descriptor.atIndex(2)?.stringValue ?? "",
            artist: descriptor.atIndex(3)?.stringValue ?? "",
            album: descriptor.atIndex(4)?.stringValue ?? ""
        )
        guard actualIdentity == expectedTrackIdentity else {
            return ArtworkResult(data: nil, matchedExpectedTrack: false)
        }
        return ArtworkResult(
            data: parseArtwork(descriptor, expectedTrackIdentity: expectedTrackIdentity),
            matchedExpectedTrack: true
        )
    }

    private static let snapshotSource = #"""
    with timeout of 3 seconds
        tell application "Music"
            set titleValue to ""
            set artistValue to ""
            set albumValue to ""
            set streamTitleValue to ""
            set positionValue to 0.0
            set durationValue to 0.0
            set stateValue to ""
            set persistentIdentityValue to ""
            set trackValue to missing value
            try
                set stateValue to (player state as text)
            end try
            try
                set streamTitleValue to (current stream title as text)
            end try
            try
                set positionValue to (player position as real)
            end try
            try
                set trackValue to current track
            end try
            if trackValue is not missing value then
                try
                    set titleValue to (name of trackValue as text)
                end try
                try
                    set artistValue to (artist of trackValue as text)
                end try
                try
                    set albumValue to (album of trackValue as text)
                end try
                try
                    set durationValue to (duration of trackValue as real)
                end try
                try
                    set persistentIdentityValue to (persistent ID of trackValue as text)
                end try
            end if
            if titleValue is "" then set titleValue to streamTitleValue
            return {titleValue, artistValue, positionValue, durationValue, stateValue, persistentIdentityValue, albumValue}
        end tell
    end timeout
    """#

    private static func execute(_ source: String) -> ScriptResult {
        guard let script = NSAppleScript(source: source) else {
            return ScriptResult(descriptor: nil, succeeded: false, errorNumber: nil, errorMessage: "无法创建音乐控制脚本。")
        }
        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let dictionary = errorInfo as? [String: Any]
            return ScriptResult(
                descriptor: nil,
                succeeded: false,
                errorNumber: dictionary?["NSAppleScriptErrorNumber"] as? Int,
                errorMessage: dictionary?["NSAppleScriptErrorBriefMessage"] as? String
                    ?? dictionary?["NSAppleScriptErrorMessage"] as? String
            )
        }
        return ScriptResult(descriptor: descriptor, succeeded: true, errorNumber: nil, errorMessage: nil)
    }

    private static func nonnegativeNumber(_ descriptor: NSAppleEventDescriptor?) -> Double {
        guard let descriptor else { return 0 }
        let value = descriptor.doubleValue
        return value.isFinite ? max(0, value) : 0
    }

    private struct ScriptResult {
        var descriptor: NSAppleEventDescriptor?
        var succeeded: Bool
        var errorNumber: Int?
        var errorMessage: String?
    }

    private struct ArtworkResult {
        var data: Data?
        var matchedExpectedTrack: Bool
    }
}
