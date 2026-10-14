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
import SwiftUI
import Testing
@testable import GlassDock

@Suite("Music widget face")
@MainActor
struct MusicWidgetUITests {
    @Test func fullAndMiniFacesKeepTheirFootprintsAndAccessibilityContainer() {
        let runtime = WidgetRuntime()
        let faces: [(compact: Bool, width: CGFloat, height: CGFloat)] = [
            (false, 280, 64),
            (true, 62, 64)
        ]

        for face in faces {
            let hostedView = NSHostingView(rootView: MusicWidgetFace(runtime: runtime, compact: face.compact))
            let fittedSize = hostedView.fittingSize
            #expect(abs(fittedSize.width - face.width) < 1)
            #expect(abs(fittedSize.height - face.height) < 1)
            #expect(hostedView.accessibilityRole()?.rawValue == "AXGroup")
        }

        #expect(runtime.musicAccess == .notRequested)
    }

    @Test func miniButtonLabelsDescribeConnectAndPlaybackStates() {
        #expect(MusicWidgetAccessibility.miniActionLabel(isConnected: false, isPlaying: false) == "连接 Apple Music")
        #expect(MusicWidgetAccessibility.miniActionLabel(isConnected: true, isPlaying: false) == "播放 Apple Music")
        #expect(MusicWidgetAccessibility.miniActionLabel(isConnected: true, isPlaying: true) == "暂停 Apple Music")
        #expect(MusicWidgetAccessibility.playPauseLabel(isPlaying: false) == "播放")
        #expect(MusicWidgetAccessibility.playPauseLabel(isPlaying: true) == "暂停")
    }

    @Test func firstMiniActionConnectsWithoutTogglingPlayback() {
        var connectCount = 0
        var playPauseCount = 0
        let connect = { connectCount += 1 }
        let playPause = { playPauseCount += 1 }

        MusicWidgetPlaybackAction.activate(isConnected: false, connect: connect, playPause: playPause)
        #expect(connectCount == 1)
        #expect(playPauseCount == 0)

        MusicWidgetPlaybackAction.activate(isConnected: true, connect: connect, playPause: playPause)
        #expect(connectCount == 1)
        #expect(playPauseCount == 1)
    }
}
