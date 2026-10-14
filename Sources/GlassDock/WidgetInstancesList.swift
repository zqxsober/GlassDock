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
import SwiftUI

/// 已添加的组件使用与悬浮 Dock 相同的预览与编辑入口。
struct WidgetInstancesList: View {
    @EnvironmentObject var store: AppStore

    private var minimumCardWidth: CGFloat {
        max(230, CGFloat(store.preferences.customWidgets.map { $0.kind.preferredWidth }.max() ?? 0) + 32)
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumCardWidth), spacing: 14)], spacing: 14) {
            ForEach(store.preferences.customWidgets) { configuration in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(configuration.displayTitle).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Spacer()
                        Button { store.removeWidget(id: configuration.id) } label: {
                            Image(systemName: "minus.circle")
                        }.buttonStyle(.plain).help("移除\(configuration.displayTitle)")
                            .accessibilityLabel("移除\(configuration.displayTitle)")
                    }
                    WidgetTile(configuration: configuration, runtime: store.widgets, preview: true)
                        .frame(maxWidth: .infinity)
                    Text(configuration.kind.category == .ai ? "本机 Codex 额度，点击配置或刷新" : configuration.kind.requiresExternalData ? "待配置外部数据" :
                         (configuration.kind == .musicFull || configuration.kind == .musicMini ? "直接控制播放，右键配置组件" : "点击预览编辑设置"))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(16).contentCard(radius: 18)
            }
        }
    }
}
