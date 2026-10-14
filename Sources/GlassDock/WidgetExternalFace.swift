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

struct WidgetExternalFace: View {
    @Environment(\.widgetScale) private var widgetScale
    let configuration: DockWidgetConfiguration
    let accent: Color

    private var metrics: WidgetMetrics { WidgetMetrics(scale: widgetScale) }
    private func d(_ value: CGFloat) -> CGFloat { metrics.dimension(value) }
    private func f(_ value: CGFloat) -> CGFloat { metrics.fontSize(value) }

    @ViewBuilder
    var body: some View {
        switch configuration.kind {
        case .weatherCurrent: currentWeather
        case .weatherConditions: weatherConditions
        case .weatherHourly: hourlyWeather
        case .stripeChart: businessChart("Stripe", symbol: "chart.xyaxis.line")
        case .stripeNumber: businessNumber("Stripe", symbol: "chart.bar")
        case .paddleChart: businessChart("Paddle", symbol: "chart.xyaxis.line")
        case .paddleNumber: businessNumber("Paddle", symbol: "chart.bar")
        case .shopifyChart: businessChart("Shopify", symbol: "chart.xyaxis.line")
        case .shopifyNumber: businessNumber("Shopify", symbol: "chart.bar")
        case .stock: stockFace
        case .watchlist: watchlistFace
        default: EmptyView()
        }
    }

    private var currentWeather: some View {
        HStack(spacing: d(8)) {
            Image(systemName: "cloud.sun.fill").font(.system(size: f(22), weight: .regular)).foregroundStyle(accent)
            VStack(alignment: .leading, spacing: d(2)) {
                Text("—°").font(.system(size: f(20), weight: .regular, design: .rounded)).monospacedDigit()
                Text("位置待配置").font(.system(size: f(8))).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, d(9))
    }

    private var weatherConditions: some View {
        HStack(spacing: d(8)) {
            Image(systemName: "cloud.sun").font(.system(size: f(20), weight: .regular)).foregroundStyle(accent)
            VStack(alignment: .leading, spacing: d(3)) {
                Text("天气状况").font(.system(size: f(9), weight: .medium))
                Text("待配置").font(.system(size: f(9))).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, d(9))
    }

    private var hourlyWeather: some View {
        Group {
            if metrics.height < 54 {
                VStack(spacing: d(2)) {
                    Text("逐小时 · 待配置").font(.system(size: f(7))).foregroundStyle(.secondary)
                    HStack(spacing: d(0)) {
                        ForEach(0..<3, id: \.self) { _ in
                            VStack(spacing: d(1)) {
                                Text("--").font(.system(size: f(8), design: .rounded)).foregroundStyle(.secondary)
                                HStack(spacing: d(1)) {
                                    Image(systemName: "cloud").font(.system(size: f(8), weight: .regular)).foregroundStyle(.tertiary)
                                    Text("—°").font(.system(size: f(8), weight: .medium, design: .rounded)).monospacedDigit()
                                }
                            }.frame(maxWidth: .infinity)
                        }
                    }
                }
            } else {
                VStack(spacing: d(2)) {
                    HStack(spacing: d(0)) {
                        ForEach(0..<3, id: \.self) { _ in
                            VStack(spacing: d(2)) {
                                Text("--").font(.system(size: f(8), design: .rounded)).foregroundStyle(.secondary)
                                Image(systemName: "cloud").font(.system(size: f(10), weight: .regular)).foregroundStyle(.tertiary)
                                Text("—°").font(.system(size: f(9), weight: .medium, design: .rounded)).monospacedDigit()
                            }.frame(maxWidth: .infinity)
                        }
                    }
                    Text("逐小时 · 待配置").font(.system(size: f(7))).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, d(8))
    }

    private func businessChart(_ service: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: d(2)) {
            HStack(spacing: d(5)) {
                Image(systemName: symbol).foregroundStyle(accent)
                Text(service).font(.system(size: f(9), weight: .medium))
                Spacer(minLength: 0)
                Text("待配置").font(.system(size: f(7))).foregroundStyle(.secondary)
            }
            Sparkline(values: [], color: accent).frame(height: d(26))
                .overlay { Text("暂无数据").font(.system(size: f(8))).foregroundStyle(.tertiary) }
        }.padding(.horizontal, d(9))
    }

    private func businessNumber(_ service: String, symbol: String) -> some View {
        HStack(spacing: d(7)) {
            Image(systemName: symbol).font(.system(size: f(16), weight: .regular)).foregroundStyle(accent)
            VStack(alignment: .leading, spacing: d(2)) {
                Text(service).font(.system(size: f(9), weight: .medium))
                HStack(alignment: .firstTextBaseline, spacing: d(4)) {
                    Text("—").font(.system(size: f(18), weight: .regular, design: .rounded))
                    Text("币种待配置").font(.system(size: f(7))).foregroundStyle(.secondary)
                }
            }
        }.padding(.horizontal, d(9))
    }

    private var stockFace: some View {
        HStack(spacing: d(8)) {
            Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: f(17), weight: .regular)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: d(2)) {
                Text("股票").font(.system(size: f(9), weight: .medium))
                Text("价格 — · 待配置").font(.system(size: f(8))).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, d(9))
    }

    private var watchlistFace: some View {
        VStack(alignment: .leading, spacing: d(metrics.height < 48 ? 1 : 4)) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: d(5)) {
                    Text("—").font(.system(size: f(9), weight: .medium, design: .rounded))
                    Spacer(minLength: 0)
                    Text("待配置").font(.system(size: f(7))).foregroundStyle(.secondary)
                }
            }
        }.padding(.horizontal, d(10))
    }
}
