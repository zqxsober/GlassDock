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

struct CodexUsageFace: View {
    @Environment(\.widgetScale) private var widgetScale
    enum Style { case numbers, rings, bars, capsules }

    let runtime: WidgetRuntime
    let accent: Color
    let title: String
    let style: Style

    private var metrics: WidgetMetrics { WidgetMetrics(scale: widgetScale) }
    private func d(_ value: CGFloat) -> CGFloat { metrics.dimension(value) }
    private func f(_ value: CGFloat) -> CGFloat { metrics.fontSize(value) }
    private var fiveHourPercent: Double? { runtime.codexUsage?.fiveHour?.remainingPercent }
    private var sevenDayPercent: Double? { runtime.codexUsage?.sevenDay?.remainingPercent }
    private var fiveHourReset: Date? { runtime.codexUsage?.fiveHour?.resetsAt }
    private var sevenDayReset: Date? { runtime.codexUsage?.sevenDay?.resetsAt }
    private var compactLayout: Bool { metrics.height < 54 }
    private var ringSize: CGFloat {
        max(d(18), min(d(32), metrics.height - f(6) * 1.2 - d(2) - 2 * d(6)))
    }
    private var capsuleTrackHeight: CGFloat {
        let availableHeight = metrics.height - d(12) - f(6) * 1.2 - d(2)
        return min(max(d(18), f(8) * 1.4), max(0, availableHeight))
    }

    var body: some View {
        Group {
            switch style {
            case .numbers:
                HStack(spacing: d(10)) {
                    numberLimit("5H", percent: fiveHourPercent, reset: fiveHourReset)
                    numberLimit("7D", percent: sevenDayPercent, reset: sevenDayReset)
                }
            case .rings:
                HStack(spacing: d(14)) {
                    ringLimit("5H", percent: fiveHourPercent, reset: fiveHourReset)
                    ringLimit("7D", percent: sevenDayPercent, reset: sevenDayReset)
                }
            case .bars:
                VStack(alignment: .leading, spacing: d(4)) {
                    barLimit("5H", percent: fiveHourPercent, reset: fiveHourReset)
                    barLimit("7D", percent: sevenDayPercent, reset: sevenDayReset)
                }
                .padding(.horizontal, d(9))
            case .capsules:
                HStack(spacing: d(12)) {
                    capsuleLimit(percent: fiveHourPercent, reset: fiveHourReset)
                    capsuleLimit(percent: sevenDayPercent, reset: sevenDayReset)
                }
                .padding(.horizontal, d(8))
                .padding(.vertical, d(6))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .help(helpDescription)
    }

    private func numberLimit(_ label: String, percent: Double?, reset: Date?) -> some View {
        Group {
            if compactLayout {
                VStack(alignment: .leading, spacing: d(1)) {
                    HStack(spacing: d(2)) {
                        Text(label).font(.system(size: f(7), weight: .medium)).foregroundStyle(.secondary)
                        Text(percentLabel(percent))
                            .font(.system(size: f(17), weight: .regular, design: .rounded)).monospacedDigit()
                    }
                    Text(resetLabel(reset, hasWindow: percent != nil))
                        .font(.system(size: f(6), design: .rounded)).monospacedDigit().foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            } else {
                VStack(alignment: .leading, spacing: d(2)) {
                    Text(label).font(.system(size: f(8), weight: .medium)).foregroundStyle(.secondary)
                    Text(percentLabel(percent))
                        .font(.system(size: f(17), weight: .regular, design: .rounded)).monospacedDigit()
                    Text(resetLabel(reset, hasWindow: percent != nil))
                        .font(.system(size: f(6), design: .rounded)).monospacedDigit().foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
        }
    }

    private func ringLimit(_ label: String, percent: Double?, reset: Date?) -> some View {
        VStack(spacing: d(2)) {
            ZStack {
                SmallRing(value: normalizedPercent(percent), color: accent, size: ringSize)
                Text(percentLabel(percent))
                    .font(.system(size: f(7), weight: .medium, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(width: ringSize, height: ringSize)
            Text(resetLabel(reset, hasWindow: percent != nil))
                .font(.system(size: f(6), design: .rounded)).monospacedDigit().foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label == "5H" ? "5 小时" : "7 天")额度，剩余 \(percentLabel(percent))，下次重置 \(resetLabel(reset, hasWindow: percent != nil))")
    }

    private func barLimit(_ label: String, percent: Double?, reset: Date?) -> some View {
        Group {
            if compactLayout {
                VStack(alignment: .leading, spacing: d(1)) {
                    HStack(spacing: d(3)) {
                        Text(label).font(.system(size: f(7))).foregroundStyle(.secondary)
                        Text(percentLabel(percent)).font(.system(size: f(7), design: .rounded)).monospacedDigit()
                        Spacer(minLength: 0)
                        Text(resetLabel(reset, hasWindow: percent != nil))
                            .font(.system(size: f(6), design: .rounded)).monospacedDigit().foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    progressBar(percent, height: d(3))
                }
            } else {
                VStack(alignment: .leading, spacing: d(2)) {
                    HStack(spacing: d(6)) {
                        Text(label).font(.system(size: f(7))).foregroundStyle(.secondary).frame(width: d(20), alignment: .leading)
                        progressBar(percent, height: d(4))
                        Text(percentLabel(percent)).font(.system(size: f(7), design: .rounded)).monospacedDigit()
                            .frame(width: d(27), alignment: .trailing)
                    }
                    Text(resetLabel(reset, hasWindow: percent != nil))
                        .font(.system(size: f(6), design: .rounded)).monospacedDigit().foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.7).padding(.leading, d(26))
                }
            }
        }
    }

    private func progressBar(_ percent: Double?, height: CGFloat) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                if let value = normalizedPercent(percent) {
                    Capsule().fill(accent).frame(width: geometry.size.width * CGFloat(value))
                }
            }
        }
        .frame(height: height)
    }

    private func capsuleLimit(percent: Double?, reset: Date?) -> some View {
        VStack(spacing: d(2)) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    if let value = normalizedPercent(percent) {
                        Capsule()
                            .fill(accent.opacity(0.32))
                            .frame(width: geometry.size.width * CGFloat(value))
                    }
                }
                .overlay {
                    Text(percentLabel(percent))
                        .font(.system(size: f(8), weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .overlay {
                    Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: d(0.8))
                }
                .clipShape(Capsule())
            }
            .frame(height: capsuleTrackHeight)
            Text(resetLabel(reset, hasWindow: percent != nil))
                .font(.system(size: f(6), design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func normalizedPercent(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return min(100, max(0, value)) / 100
    }

    private func percentLabel(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(Int(min(100, max(0, value)).rounded()))%"
    }

    private func resetLabel(_ date: Date?, hasWindow: Bool) -> String {
        guard hasWindow else { return runtime.codexUsage == nil ? unavailableLabel : "—" }
        guard let date else { return "—" }
        let seconds = Int(ceil(date.timeIntervalSince(runtime.now)))
        guard seconds > 0 else { return "等待刷新" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60
        let clock = String(format: "%02d:%02d:%02d", hours, minutes, remainder)
        return days > 0 ? "\(days)d \(clock)" : clock
    }

    private var unavailableLabel: String {
        if runtime.isCodexUsageLoading { return "读取中" }
        if runtime.codexUsageError != nil { return "读取失败" }
        return "未连接"
    }

    private var accessibilityDescription: String {
        "\(title)，5 小时额度剩余 \(percentLabel(fiveHourPercent))，重置倒计时 \(resetLabel(fiveHourReset, hasWindow: fiveHourPercent != nil))；7 天额度剩余 \(percentLabel(sevenDayPercent))，重置倒计时 \(resetLabel(sevenDayReset, hasWindow: sevenDayPercent != nil))"
            + (runtime.codexUsageError.map { "，\($0)" } ?? "")
    }

    private var helpDescription: String {
        runtime.codexUsageError.map { "\(title)：\($0)" } ?? "\(title)，显示本机 Codex 的 5 小时和 7 天剩余额度"
    }
}
