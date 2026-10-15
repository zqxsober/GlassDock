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

import Foundation

/// 温度组件的显示单位，按组件单独保存；nil 视为摄氏。
public enum TemperatureUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case celsius, fahrenheit
    public var id: String { rawValue }
    public var symbol: String { self == .celsius ? "°C" : "°F" }
    public var spokenName: String { self == .celsius ? "摄氏度" : "华氏度" }

    /// 由摄氏换算到本单位（℉ = ℃ × 9/5 + 32），先换算再取整。
    public func convert(celsius: Double) -> Double {
        self == .celsius ? celsius : celsius * 9 / 5 + 32
    }

    public func rounded(celsius: Double) -> Int { Int(convert(celsius: celsius).rounded()) }

    public func formatted(celsius: Double) -> String { "\(rounded(celsius: celsius))\(symbol)" }
}

/// 三档阈值，始终按摄氏、取整前的值判断：<70 正常，70–85（含两端）偏高，>85 过热。
public enum TemperatureLevel: String, Equatable, Sendable {
    case normal, warm, hot

    public init(celsius: Double) {
        if celsius < 70 { self = .normal }
        else if celsius <= 85 { self = .warm }
        else { self = .hot }
    }

    public var title: String {
        switch self {
        case .normal: "正常"
        case .warm: "偏高"
        case .hot: "过热"
        }
    }

    public var symbol: String {
        switch self {
        case .normal: "thermometer.low"
        case .warm: "thermometer.medium"
        case .hot: "thermometer.high"
        }
    }
}

/// CPU 相关传感器的聚合结果（摄氏）。
public struct TemperatureAggregate: Equatable, Sendable {
    public let average: Double
    public let maximum: Double

    /// 过滤非有限值和 ≤0 或 >150 的异常读数；空列表或全部被过滤时返回 nil。
    public init?(sensors: [Double]) {
        let valid = sensors.filter { $0.isFinite && $0 > 0 && $0 <= 150 }
        guard let maximum = valid.max() else { return nil }
        average = valid.reduce(0, +) / Double(valid.count)
        self.maximum = maximum
    }

    public var level: TemperatureLevel { TemperatureLevel(celsius: average) }

    /// 圆环进度：30–100 ℃ 映射到 0–1 并截断。
    public var ringProgress: Double { Self.ringProgress(celsius: average) }

    public static let ringRange: ClosedRange<Double> = 30...100

    public static func ringProgress(celsius: Double) -> Double {
        guard celsius.isFinite else { return 0 }
        let span = ringRange.upperBound - ringRange.lowerBound
        return min(1, max(0, (celsius - ringRange.lowerBound) / span))
    }
}

/// 组件显示状态。
public enum CPUTemperatureState: Equatable, Sendable {
    /// 刚启动，还没有第一笔数据。
    case sampling
    case reading(TemperatureAggregate)
    /// 读取接口不存在、调用失败、没有有效传感器，或连续失败达到上限。
    case unavailable
}

/// 纯状态机：连续失败计数与恢复逻辑，便于脱离私有接口测试。
public struct CPUTemperatureStateMachine: Equatable, Sendable {
    /// 连续失败多少次判定为不可用（2 秒一次，约 10 秒）。
    public static let failureLimit = 5

    public private(set) var state: CPUTemperatureState = .sampling
    public private(set) var consecutiveFailures = 0

    public init() {}

    /// - Parameters:
    ///   - readings: 本次读到的传感器值；nil 表示读取调用失败。
    ///   - sourceAvailable: 读取接口是否存在（平台不支持、服务打不开时为 false，立即不可用）。
    public mutating func record(readings: [Double]?, sourceAvailable: Bool = true) {
        guard sourceAvailable else {
            consecutiveFailures = Self.failureLimit
            state = .unavailable
            return
        }
        guard let readings else {
            consecutiveFailures += 1
            // 失败期间不保留旧值：首笔前保持“正在采样”，达到上限后不可用。
            if consecutiveFailures >= Self.failureLimit {
                state = .unavailable
            } else if case .reading = state {
                state = .sampling
            }
            return
        }
        consecutiveFailures = 0
        // 读取成功但聚合为空（没有匹配的 CPU 传感器）：不可用。
        state = TemperatureAggregate(sensors: readings).map(CPUTemperatureState.reading) ?? .unavailable
    }

    public mutating func reset() {
        self = CPUTemperatureStateMachine()
    }
}

/// VoiceOver 标签与 help 文案；单位读作“摄氏度/华氏度”。
public enum CPUTemperatureDescription {
    public static func accessibilityLabel(title: String, state: CPUTemperatureState, unit: TemperatureUnit) -> String {
        switch state {
        case .sampling:
            return "\(title)，正在采样，按回车打开配置"
        case .unavailable:
            return "\(title)，不可用，按回车打开配置"
        case .reading(let aggregate):
            let average = unit.rounded(celsius: aggregate.average)
            let maximum = unit.rounded(celsius: aggregate.maximum)
            return "\(title)，平均 \(average) \(unit.spokenName)，最高 \(maximum) \(unit.spokenName)，\(aggregate.level.title)，按回车打开配置"
        }
    }

    public static func help(state: CPUTemperatureState, unit: TemperatureUnit) -> String {
        switch state {
        case .sampling:
            return "CPU 温度：正在采样"
        case .unavailable:
            return "未找到可读取的 CPU 温度传感器"
        case .reading(let aggregate):
            return "CPU 温度：平均 \(unit.formatted(celsius: aggregate.average)) · 最高 \(unit.formatted(celsius: aggregate.maximum)) · \(aggregate.level.title)"
        }
    }
}
