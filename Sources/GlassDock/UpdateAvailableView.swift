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
import GlassDockCore
import SwiftUI

struct UpdateAvailableView: View {
    @EnvironmentObject var store: AppStore
    let release: GitHubRelease

    var body: some View {
        let checker = store.updateChecker
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 22)).foregroundStyle(store.accent)
                    .frame(width: 48, height: 48)
                    .glassEffect(.regular, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text(zh: "GlassDock \(release.displayVersion) 可用", en: "GlassDock \(release.displayVersion) is available"))
                        .font(.system(size: 17, weight: .semibold))
                    Text(L10n.text(zh: "你当前使用的是 \(checker.currentVersion)", en: "You're using \(checker.currentVersion)"))
                        .font(.system(size: 12)).foregroundStyle(Color.muted)
                }
            }
            notes
            HStack {
                Button(L10n.text(zh: "忽略此版本", en: "Skip This Version")) { checker.skip(release) }
                Spacer()
                Button(L10n.text(zh: "稍后", en: "Later")) { checker.snooze(release) }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.text(zh: "前往下载", en: "Download")) { checker.download(release) }
                    .buttonStyle(.borderedProminent).tint(store.accent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(Color.canvas)
    }

    @ViewBuilder private var notes: some View {
        let summary = UpdatePolicy.summary(of: release.body)
        if summary.isEmpty {
            Link(L10n.text(zh: "查看完整发布说明", en: "View full release notes"), destination: release.htmlURL)
                .font(.system(size: 12))
        } else {
            ScrollView {
                Text(Self.render(summary))
                    .font(.system(size: 12)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .frame(maxHeight: 220)
            .contentCard(radius: 16)
        }
    }

    private static func render(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
    }
}

/// 菜单栏图标；有未处理的新版本时右上角加一个小圆点。
enum MenuBarIcon {
    static func image(badged: Bool) -> NSImage {
        let base = NSImage(systemSymbolName: "square.stack.3d.up.fill", accessibilityDescription: "GlassDock") ?? NSImage()
        guard badged else { return base }
        let size = base.size
        let image = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect)
            NSColor.black.setFill()
            let dot: CGFloat = 5
            NSBezierPath(ovalIn: NSRect(x: rect.maxX - dot, y: rect.maxY - dot, width: dot, height: dot)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = L10n.text(zh: "GlassDock，有新版本", en: "GlassDock, update available")
        return image
    }
}
