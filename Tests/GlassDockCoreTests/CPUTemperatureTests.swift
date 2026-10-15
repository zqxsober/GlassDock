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
import GlassDockCore
import Testing

@Suite("CPU temperature")
struct CPUTemperatureTests {
    @Test func unitConversionRoundsAfterConverting() {
        #expect(TemperatureUnit.celsius.convert(celsius: 52) == 52)
        #expect(TemperatureUnit.fahrenheit.convert(celsius: 0) == 32)
        #expect(TemperatureUnit.fahrenheit.convert(celsius: 100) == 212)
        #expect(TemperatureUnit.fahrenheit.convert(celsius: -40) == -40)
        #expect(TemperatureUnit.fahrenheit.rounded(celsius: 52) == 126) // 125.6
        #expect(TemperatureUnit.celsius.formatted(celsius: 52.4) == "52°C")
        #expect(TemperatureUnit.celsius.formatted(celsius: 52.5) == "53°C")
        #expect(TemperatureUnit.fahrenheit.formatted(celsius: 52) == "126°F")
    }

    @Test func levelThresholdsUseUnroundedCelsius() {
        #expect(TemperatureLevel(celsius: 69.9) == .normal)
        #expect(TemperatureLevel(celsius: 70) == .warm)
        #expect(TemperatureLevel(celsius: 85) == .warm)
        #expect(TemperatureLevel(celsius: 85.1) == .hot)
        #expect(TemperatureLevel(celsius: 30) == .normal)
    }

    @Test func aggregateAveragesAndMaximum() throws {
        let aggregate = try #require(TemperatureAggregate(sensors: [50, 60, 70]))
        #expect(aggregate.average == 60)
        #expect(aggregate.maximum == 70)
        #expect(aggregate.level == .normal)
    }

    @Test func aggregateFiltersOutliersAndHandlesEmptyLists() throws {
        #expect(TemperatureAggregate(sensors: []) == nil)
        #expect(TemperatureAggregate(sensors: [0, -5, 151, .nan, .infinity]) == nil)
        let aggregate = try #require(TemperatureAggregate(sensors: [40, 0, 200, .nan, 60, 150]))
        #expect(aggregate.maximum == 150)
        #expect(aggregate.average == (40 + 60 + 150) / 3)
    }

    @Test func ringMapsThirtyToHundredAndClamps() {
        #expect(TemperatureAggregate.ringProgress(celsius: 30) == 0)
        #expect(TemperatureAggregate.ringProgress(celsius: 65) == 0.5)
        #expect(TemperatureAggregate.ringProgress(celsius: 100) == 1)
        #expect(TemperatureAggregate.ringProgress(celsius: 10) == 0)
        #expect(TemperatureAggregate.ringProgress(celsius: 120) == 1)
        #expect(TemperatureAggregate.ringProgress(celsius: .nan) == 0)
        #expect(abs(TemperatureAggregate(sensors: [51])!.ringProgress - 0.3) < 1e-9)
    }

    @Test func stateMachineStartsSamplingAndReportsReadings() {
        var machine = CPUTemperatureStateMachine()
        #expect(machine.state == .sampling)
        machine.record(readings: [55, 65])
        #expect(machine.state == .reading(TemperatureAggregate(sensors: [55, 65])!))
    }

    @Test func failuresBeforeFirstReadingStaySampling() {
        var machine = CPUTemperatureStateMachine()
        machine.record(readings: nil)
        #expect(machine.state == .sampling)
    }

    @Test func missingSourceIsImmediatelyUnavailable() {
        var machine = CPUTemperatureStateMachine()
        machine.record(readings: nil, sourceAvailable: false)
        #expect(machine.state == .unavailable)
    }

    @Test func emptyOrInvalidReadingsAreUnavailableWithoutFakeData() {
        var machine = CPUTemperatureStateMachine()
        machine.record(readings: [])
        #expect(machine.state == .unavailable)
        machine.record(readings: [0, 999])
        #expect(machine.state == .unavailable)
    }

    @Test func fiveConsecutiveFailuresBecomeUnavailableAndRecover() {
        var machine = CPUTemperatureStateMachine()
        machine.record(readings: [60])
        for _ in 0..<(CPUTemperatureStateMachine.failureLimit - 1) { machine.record(readings: nil) }
        #expect(machine.state == .reading(TemperatureAggregate(sensors: [60])!)) // 上限内保留上次读数
        #expect(machine.consecutiveFailures == CPUTemperatureStateMachine.failureLimit - 1)
        machine.record(readings: nil)
        #expect(machine.state == .unavailable)
        machine.record(readings: [61])
        #expect(machine.state == .reading(TemperatureAggregate(sensors: [61])!))
        #expect(machine.consecutiveFailures == 0)
    }

    @Test func descriptionsUseSpokenUnits() {
        let reading = CPUTemperatureState.reading(TemperatureAggregate(sensors: [50, 61])!)
        #expect(CPUTemperatureDescription.accessibilityLabel(title: "CPU 温度", state: reading, unit: .celsius)
            == "CPU 温度，平均 56 摄氏度，最高 61 摄氏度，正常，按回车打开配置")
        #expect(CPUTemperatureDescription.accessibilityLabel(title: "CPU 温度", state: .unavailable, unit: .celsius)
            == "CPU 温度，不可用，按回车打开配置")
        #expect(CPUTemperatureDescription.help(state: reading, unit: .fahrenheit) == "CPU 温度：平均 132°F · 最高 142°F · 正常")
    }

    @Test func perWidgetUnitPersistsAndOldJSONDefaultsToCelsius() throws {
        var preferences = DockPreferences()
        var fahrenheit = DockWidgetConfiguration(kind: .cpuTemperatureNumber)
        fahrenheit.temperatureUnit = .fahrenheit
        let celsius = DockWidgetConfiguration(kind: .cpuTemperatureRing)
        preferences.customWidgets = [fahrenheit, celsius]
        let restored = try JSONDecoder().decode(DockPreferences.self, from: JSONEncoder().encode(preferences))
        #expect(restored.customWidgets[0].resolvedTemperatureUnit == .fahrenheit)
        #expect(restored.customWidgets[1].resolvedTemperatureUnit == .celsius)

        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(DockWidgetConfiguration(kind: .systemNumbers))) as! [String: Any]
        legacy.removeValue(forKey: "temperatureUnit")
        let decoded = try JSONDecoder().decode(DockWidgetConfiguration.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.temperatureUnit == nil)
        #expect(decoded.resolvedTemperatureUnit == .celsius)
    }

    @Test func temperatureWidgetsAreAvailableSystemWidgets() {
        #expect(DockWidgetKind.cpuTemperatureNumber.category == .system)
        #expect(DockWidgetKind.cpuTemperatureRing.category == .system)
        #expect(DockWidgetKind.availableKinds.contains(.cpuTemperatureNumber))
        #expect(DockWidgetKind.cpuTemperatureNumber.title == "CPU 温度 · 数字")
        #expect(DockWidgetKind.cpuTemperatureRing.title == "CPU 温度 · 环形")
        #expect(DockWidgetKind.cpuTemperatureRing.preferredWidth == 132)
        #expect(!DockWidgetKind.cpuTemperatureRing.requiresExternalData)
    }
}
