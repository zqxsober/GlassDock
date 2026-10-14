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

import SwiftUI

/// 日期与数字时间使用同一时区，避免世界时钟跨日时显示本地日期。
func widgetDateLabel(_ date: Date, timeZoneIdentifier: String) -> String {
    let formatter = DateFormatter()
    formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
    formatter.dateFormat = "EEE, MMM d"
    return formatter.string(from: date)
}

func widgetNetworkRateLabel(_ value: Double?) -> String {
    guard let value, value.isFinite, value >= 0 else { return "—" }
    if value >= 1_000_000 { return String(format: "%.1f MB/s", value / 1_000_000) }
    if value >= 1_000 { return String(format: "%.0f KB/s", value / 1_000) }
    return String(format: "%.0f B/s", value)
}

struct MiniAnalogClock: View {
    @Environment(\.widgetScale) private var widgetScale
    let date: Date
    let timeZoneIdentifier: String
    let size: CGFloat

    private var metrics: WidgetMetrics { WidgetMetrics(scale: widgetScale) }

    private var handAngles: (hour: Double, minute: Double) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = Double((components.hour ?? 0) % 12)
        let minute = Double(components.minute ?? 0)
        return ((hour + minute / 60) * 30, minute * 6)
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.2), lineWidth: metrics.dimension(1))
            ForEach(0..<4, id: \.self) { tick in
                Circle().fill(Color.primary.opacity(0.4)).frame(width: metrics.dimension(1.5), height: metrics.dimension(1.5))
                    .offset(y: -(size / 2 - metrics.dimension(3))).rotationEffect(.degrees(Double(tick) * 90))
            }
            Capsule().fill(Color.primary.opacity(0.85)).frame(width: metrics.dimension(1.8), height: size * 0.23)
                .offset(y: -size * 0.055).rotationEffect(.degrees(handAngles.hour))
            Capsule().fill(Color.primary.opacity(0.62)).frame(width: metrics.dimension(1.1), height: size * 0.32)
                .offset(y: -size * 0.09).rotationEffect(.degrees(handAngles.minute))
            Circle().fill(Color.primary.opacity(0.82)).frame(width: metrics.dimension(2.2), height: metrics.dimension(2.2))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct SmallRing: View {
    @Environment(\.widgetScale) private var widgetScale
    let value: Double?
    let color: Color
    let size: CGFloat

    private var metrics: WidgetMetrics { WidgetMetrics(scale: widgetScale) }

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: metrics.dimension(3))
            if let value {
                Circle().trim(from: 0, to: min(1, max(0, value)))
                    .stroke(color, style: StrokeStyle(lineWidth: metrics.dimension(3), lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                Circle().stroke(.tertiary, style: StrokeStyle(lineWidth: metrics.dimension(2), dash: [metrics.dimension(2), metrics.dimension(3)]))
            }
        }.frame(width: size, height: size)
    }
}

struct YearTickRing: View {
    @Environment(\.widgetScale) private var widgetScale
    let value: Double
    let color: Color
    let size: CGFloat

    private var metrics: WidgetMetrics { WidgetMetrics(scale: widgetScale) }

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: metrics.dimension(2))
            ForEach(0..<12, id: \.self) { index in
                Capsule()
                    .fill(Double(index) < value * 12 ? color : Color.primary.opacity(0.16))
                    .frame(width: metrics.dimension(2), height: metrics.dimension(5))
                    .offset(y: -(size / 2 - metrics.dimension(2.5)))
                    .rotationEffect(.degrees(Double(index) * 30))
            }
        }
        .frame(width: size, height: size)
    }
}

struct Sparkline: View {
    @Environment(\.widgetScale) private var widgetScale
    let values: [Double]
    let color: Color

    private var metrics: WidgetMetrics { WidgetMetrics(scale: widgetScale) }

    var body: some View {
        GeometryReader { geometry in
            let valid = values.filter { $0.isFinite }
            let low = valid.min() ?? 0
            let high = valid.max() ?? 1
            let spread = max(high - low, 1)
            Path { path in
                for (index, value) in valid.enumerated() {
                    let x = valid.count < 2 ? 0 : geometry.size.width * CGFloat(index) / CGFloat(valid.count - 1)
                    let y = geometry.size.height * (1 - CGFloat((value - low) / spread))
                    let point = CGPoint(x: x, y: y)
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: metrics.dimension(1.5), lineCap: .round, lineJoin: .round))
        }
    }
}
