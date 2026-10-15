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
@testable import GlassDock

private final class FakeTemperatureSource: CPUTemperatureSource, @unchecked Sendable {
    var isAvailable: Bool
    var readings: [Double]?
    init(isAvailable: Bool = true, readings: [Double]?) {
        self.isAvailable = isAvailable
        self.readings = readings
    }
    func readCPUTemperatures() -> [Double]? { readings }
}

@Suite("CPU temperature sampler", .serialized)
@MainActor
struct CPUTemperatureSamplerTests {
    private func sample(_ sampler: CPUTemperatureSampler) async {
        await withCheckedContinuation { continuation in
            sampler.sample { continuation.resume() }
        }
    }

    @Test func fakeSourceReadingsReachState() async {
        let source = FakeTemperatureSource(readings: [48, 52])
        var states: [CPUTemperatureState] = []
        let sampler = CPUTemperatureSampler(makeSource: { source }) { states.append($0) }
        await sample(sampler)
        #expect(states.last == .reading(TemperatureAggregate(sensors: [48, 52])!))
    }

    @Test func unavailableSourceAndMissingPlatformAreUnavailable() async {
        var states: [CPUTemperatureState] = []
        let missing = CPUTemperatureSampler(makeSource: { nil }) { states.append($0) }
        await sample(missing)
        #expect(states.last == .unavailable)

        let closed = FakeTemperatureSource(isAvailable: false, readings: [50])
        let sampler = CPUTemperatureSampler(makeSource: { closed }) { states.append($0) }
        await sample(sampler)
        #expect(states.last == .unavailable)
    }

    @Test func stopResetsToSampling() async {
        let source = FakeTemperatureSource(readings: [60])
        var states: [CPUTemperatureState] = []
        let sampler = CPUTemperatureSampler(makeSource: { source }) { states.append($0) }
        sampler.start()
        #expect(sampler.isRunning)
        sampler.stop()
        #expect(!sampler.isRunning)
        #expect(states.last == .sampling)
    }

    @Test func appleSiliconSensorNameFilter() {
        #expect(AppleSiliconTemperatureSource.isCPUSensor(name: "PMU tdie1"))
        #expect(AppleSiliconTemperatureSource.isCPUSensor(name: "PMU2 tdie3"))
        #expect(!AppleSiliconTemperatureSource.isCPUSensor(name: "PMU tdev1"))
        #expect(!AppleSiliconTemperatureSource.isCPUSensor(name: "NAND CH0 temp"))
    }

    @Test func smcDecoding() {
        let sp78 = IntelSMCTemperatureSource.fourCharCode("sp78")
        #expect(IntelSMCTemperatureSource.decode(type: sp78, bytes: [0x34, 0x80]) == 52.5)
        #expect(IntelSMCTemperatureSource.decode(type: sp78, bytes: [0x34]) == nil)
        let flt = IntelSMCTemperatureSource.fourCharCode("flt ")
        let bits = Float(61.25).bitPattern
        let bytes = [UInt8(bits & 0xff), UInt8(bits >> 8 & 0xff), UInt8(bits >> 16 & 0xff), UInt8(bits >> 24)]
        #expect(IntelSMCTemperatureSource.decode(type: flt, bytes: bytes) == 61.25)
        #expect(IntelSMCTemperatureSource.fourCharCode("TC0P") == 0x5443_3050)
    }
}
