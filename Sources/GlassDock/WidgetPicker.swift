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

struct WidgetPicker: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedCategory: DockWidgetCategory?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 205)
            Divider()
            catalog
        }
        .frame(width: 860, height: 620)
        .background(Color.canvas)
        .focusEffectDisabled()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("添加组件").font(.system(size: 18, weight: .semibold))
                Text("选择你想放在 Dock 的信息")
                    .font(.system(size: 10)).foregroundStyle(Color.muted)
            }
            TextField("搜索组件", text: $searchText)
                .textFieldStyle(.plain)
                .padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .font(.system(size: 11))
                .accessibilityLabel("搜索组件")
            ScrollView {
                VStack(spacing: 3) {
                    categoryButton(nil, title: "全部组件", symbol: "square.grid.2x2", count: DockWidgetKind.availableKinds.count)
                    ForEach(DockWidgetCategory.availableCategories) { category in
                        categoryButton(category, title: category.title, symbol: category.symbol,
                                       count: DockWidgetKind.availableKinds.filter { $0.category == category }.count)
                    }
                }
            }.scrollIndicators(.hidden)
            Spacer(minLength: 0)
            Label("已添加的组件可在 Dock 中配置", systemImage: "hand.tap")
                .font(.system(size: 9)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
    }

    private var catalog: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedCategory?.title ?? (searchText.isEmpty ? "全部组件" : "搜索结果"))
                        .font(.system(size: 16, weight: .semibold))
                    Text("\(filteredKinds.count) 种样式 · 点击添加，可连续选择")
                        .font(.system(size: 10)).foregroundStyle(Color.muted)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .buttonStyle(.glass).controlSize(.small).keyboardShortcut(.cancelAction)
            }
            ScrollView {
                if filteredKinds.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(filteredKinds) { kind in
                            WidgetPickerCard(kind: kind, runtime: store.widgets,
                                             batteryPercent: store.batteryPercent, batterySymbol: store.batterySymbol)
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
            .scrollIndicators(.visible)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var filteredKinds: [DockWidgetKind] {
        DockWidgetKind.availableKinds.filter { kind in
            let categoryMatches = selectedCategory == nil || kind.category == selectedCategory
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let searchMatches = query.isEmpty || kind.title.localizedCaseInsensitiveContains(query)
                || kind.category.title.localizedCaseInsensitiveContains(query)
                || kind.rawValue.localizedCaseInsensitiveContains(query)
            return categoryMatches && searchMatches
        }
    }

    private func categoryButton(_ category: DockWidgetCategory?, title: String, symbol: String, count: Int) -> some View {
        let selected = selectedCategory == category
        return Button {
            selectedCategory = category
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol).frame(width: 16)
                Text(title).lineLimit(1)
                Spacer(minLength: 3)
                Text("\(count)").font(.system(size: 9, design: .rounded)).foregroundStyle(.secondary)
            }
            .font(.system(size: 10, weight: selected ? .medium : .regular))
            .padding(.horizontal, 9).padding(.vertical, 8)
            .background(selected ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }
}

private struct WidgetPickerCard: View {
    @EnvironmentObject private var store: AppStore
    let kind: DockWidgetKind
    let runtime: WidgetRuntime
    let batteryPercent: Int?
    let batterySymbol: String
    @State private var status: String?

    private var existingCount: Int { store.preferences.customWidgets.filter { $0.kind == kind }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: kind.category.symbol).font(.system(size: 9)).foregroundStyle(store.accent)
                Text(kind.category.title).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                if existingCount > 0 {
                    Text("已添加 \(existingCount)").font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }
            GeometryReader { geometry in
                let scale = min(1, max(0.1, (geometry.size.width - 4) / CGFloat(DockWidgetKind.musicFull.preferredWidth)))
                WidgetFace(configuration: DockWidgetConfiguration(kind: kind), runtime: runtime,
                           batteryPercent: batteryPercent, batterySymbol: batterySymbol)
                    .environment(\.widgetScale, scale)
                    .frame(width: geometry.size.width, height: 64)
            }
                .frame(height: 64)
            HStack(alignment: .center, spacing: 6) {
                Text(kind.title).font(.system(size: 10, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
                if let status {
                    Text(status).font(.system(size: 8)).foregroundStyle(store.accent).lineLimit(1)
                }
                Button {
                    let countBefore = existingCount
                    store.addWidget(kind: kind)
                    let countAfter = existingCount
                    status = countAfter > countBefore ? "已添加" : (countBefore > 0 ? "已存在" : "未添加")
                } label: {
                    Label("添加", systemImage: "plus")
                        .font(.system(size: 9, weight: .medium))
                }
                .buttonStyle(.glass)
                .controlSize(.mini)
                .help("添加\(kind.title)")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 0.6)
        }
        .focusEffectDisabled()
    }
}
