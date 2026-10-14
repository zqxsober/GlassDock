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

struct MusicWidgetFace: View {
    @Environment(\.widgetScale) private var widgetScale
    @ObservedObject var runtime: WidgetRuntime
    let compact: Bool

    private var metrics: WidgetMetrics { WidgetMetrics(scale: widgetScale) }
    private func d(_ value: CGFloat) -> CGFloat { metrics.dimension(value) }
    private func f(_ value: CGFloat) -> CGFloat { metrics.fontSize(value) }
    private var isConnected: Bool { runtime.music.isConnected }
    private var width: CGFloat { d(compact ? 62 : 280) }
    private var height: CGFloat { metrics.height }
    private var playPauseSymbol: String { isConnected && runtime.music.isPlaying ? "pause.fill" : "play.fill" }
    private var artwork: NSImage? {
        guard let data = runtime.music.artworkData else { return nil }
        return NSImage(data: data)
    }
    private var trackTitle: String {
        guard isConnected else { return "Apple Music" }
        return runtime.music.title.isEmpty ? "未提供曲目名称" : runtime.music.title
    }
    private var trackArtist: String {
        guard isConnected else {
            switch runtime.musicAccess {
            case .notRequested: return "点击连接后读取歌曲"
            case .authorized: return "尚未连接"
            case .denied: return "访问未授权"
            case .unavailable: return "Apple Music 不可用"
            }
        }
        return runtime.music.artist.isEmpty ? "未提供艺术家" : runtime.music.artist
    }
    private var progress: Double {
        let duration = runtime.music.duration
        let position = runtime.musicPosition
        guard duration.isFinite, duration > 0, position.isFinite else { return 0 }
        return min(1, max(0, position / duration))
    }

    var body: some View {
        faceContent
            .frame(width: width, height: height)
            .widgetGlassSurface(radius: d(compact ? 20 : 15))
            .foregroundStyle(.primary)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(compact ? "music-mini-widget" : "music-full-widget")
            .focusable()
            .focusEffectDisabled()
    }

    @ViewBuilder
    private var faceContent: some View {
        if compact {
            miniFace
        } else {
            fullFace
        }
    }

    private var fullFace: some View {
        HStack(spacing: d(9)) {
            albumArtwork
            VStack(alignment: .leading, spacing: d(metrics.height < 48 ? 1 : 5)) {
                HStack(spacing: d(5)) {
                    VStack(alignment: .leading, spacing: d(metrics.height < 48 ? 0 : 3)) {
                        Text(trackTitle)
                            .font(.system(size: f(11), weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(trackArtist)
                            .font(.system(size: f(9)))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if isConnected {
                        playbackControls
                    } else {
                        connectButton
                    }
                }
                progressRow
            }
        }
        .padding(.horizontal, d(8))
        .padding(.vertical, d(metrics.height < 48 ? 1 : 6))
    }

    private var miniFace: some View {
        Button(action: activatePlayPause) {
            Image(systemName: playPauseSymbol)
                .font(.system(size: f(17), weight: .medium))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .frame(width: width, height: height)
        .contentShape(RoundedRectangle(cornerRadius: d(20), style: .continuous))
        .accessibilityLabel(MusicWidgetAccessibility.miniActionLabel(
            isConnected: isConnected,
            isPlaying: runtime.music.isPlaying
        ))
        .accessibilityIdentifier("music-mini-play-pause")
        .help(MusicWidgetAccessibility.miniActionLabel(
            isConnected: isConnected,
            isPlaying: runtime.music.isPlaying
        ))
    }

    private var albumArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: d(7), style: .continuous)
                .fill(Color.primary.opacity(0.055))
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: f(17), weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: d(42), height: d(42))
        .clipShape(RoundedRectangle(cornerRadius: d(7), style: .continuous))
        .accessibilityHidden(true)
    }

    private var playbackControls: some View {
        HStack(spacing: d(3)) {
            playbackButton("backward.end.fill", label: "上一首", identifier: "music-previous") {
                runtime.previousMusicTrack()
            }
            playbackButton(playPauseSymbol, label: MusicWidgetAccessibility.playPauseLabel(isPlaying: runtime.music.isPlaying), identifier: "music-play-pause") {
                runtime.playPauseMusic()
            }
            playbackButton("forward.end.fill", label: "下一首", identifier: "music-next") {
                runtime.nextMusicTrack()
            }
        }
        .fixedSize()
    }

    private var connectButton: some View {
        Button {
            runtime.connectMusic()
        } label: {
            Label("连接 Apple Music", systemImage: "music.note")
                .font(.system(size: f(8), weight: .medium))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityIdentifier("music-connect")
    }

    private var progressRow: some View {
        HStack(spacing: d(5)) {
            Text(formattedTime(runtime.musicPosition, duration: runtime.music.duration))
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    Capsule()
                        .fill(Color.primary.opacity(0.70))
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: d(3))
            Text(formattedTime(runtime.music.duration, duration: runtime.music.duration))
        }
        .font(.system(size: f(8), design: .rounded))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(height: max(d(10), f(8) * 1.2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("播放进度")
        .accessibilityValue(runtime.music.duration > 0 ? "\(Int(progress * 100))%" : "暂无时长")
        .accessibilityIdentifier("music-progress")
    }

    private func playbackButton(
        _ symbol: String,
        label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: f(9), weight: .medium))
                .frame(width: d(19), height: d(19))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private func activatePlayPause() {
        MusicWidgetPlaybackAction.activate(
            isConnected: isConnected,
            connect: { runtime.connectMusic() },
            playPause: { runtime.playPauseMusic() }
        )
    }

    private func formattedTime(_ value: Double, duration: Double) -> String {
        guard duration.isFinite, duration > 0, value.isFinite else { return "—:—" }
        let seconds = max(0, Int(min(value, duration)))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

@MainActor
enum MusicWidgetPlaybackAction {
    static func activate(isConnected: Bool, connect: () -> Void, playPause: () -> Void) {
        if isConnected {
            playPause()
        } else {
            connect()
        }
    }
}

enum MusicWidgetAccessibility {
    static func miniActionLabel(isConnected: Bool, isPlaying: Bool) -> String {
        guard isConnected else { return "连接 Apple Music" }
        return isPlaying ? "暂停 Apple Music" : "播放 Apple Music"
    }

    static func playPauseLabel(isPlaying: Bool) -> String {
        isPlaying ? "暂停" : "播放"
    }
}
