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
import Testing
@testable import GlassDock

@Suite("Widget sizing", .serialized)
@MainActor
struct WidgetSizingTests {
    @Test func everyAvailableFaceMatchesFullMusicHeightAtEachDockSize() {
        let name = "GlassDock.WidgetSizingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = AppStore(defaults: defaults)
        for size in [CGFloat(10), 28, 48, 96] {
            let scale = size / 48
            let music = NSHostingView(rootView: MusicWidgetFace(runtime: store.widgets, compact: false)
                .environment(\.widgetScale, scale)).fittingSize
            for kind in DockWidgetKind.availableKinds {
                let face = NSHostingView(rootView: WidgetFace(configuration: DockWidgetConfiguration(kind: kind),
                    runtime: store.widgets, batteryPercent: 80, batterySymbol: "battery.100percent")
                    .environmentObject(store).environment(\.widgetScale, scale)).fittingSize
                #expect(abs(face.height - music.height) < 0.5, "\(kind.rawValue) / \(size)px")
                // AppKit 的 fittingSize 将 SwiftUI 的小数尺寸向上取整为整点。
                #expect(abs(face.width - (CGFloat(kind.preferredWidth) * scale).rounded(.up)) < 0.5,
                        "\(kind.rawValue) / \(size)px width")
            }
        }
    }

    @Test func smallDockLabelsAreLargerThanUniformlyScaledLegacyText() {
        let metrics = WidgetMetrics(scale: 28 / 48)
        #expect(metrics.fontSize(8) >= 9)
        #expect(metrics.fontSize(19) > 19 * 28 / 48)
        #expect(WidgetMetrics().fontSize(8) >= 10)
    }

    @Test func capsuleWidgetStartsAndCancelsUsageRefreshWithoutOtherAIWidgets() {
        let runtime = WidgetRuntime()
        runtime.sync(configurations: [DockWidgetConfiguration(kind: .aiCapsules)])
        #expect(runtime.isCodexUsageLoading)

        runtime.sync(configurations: [])
        #expect(!runtime.isCodexUsageLoading)
        #expect(runtime.codexUsage == nil)
        #expect(runtime.codexUsageError == nil)
    }
}
