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

import Darwin
import IOKit.ps
import Foundation
import SystemConfiguration

public struct WidgetSystemMetrics: Equatable, Sendable {
    public var cpuPercent: Double?
    public var memoryPercent: Double?
    public var downloadBytesPerSecond: Double?
    public var uploadBytesPerSecond: Double?
    public var networkHistory: [Double]
    /// Battery charge as a percentage from 0 through 100.
    public var batteryPercent: Double?
    public var batteryIsCharging: Bool?
    public var batteryTimeRemainingMinutes: Int?

    public init(
        cpuPercent: Double? = nil,
        memoryPercent: Double? = nil,
        downloadBytesPerSecond: Double? = nil,
        uploadBytesPerSecond: Double? = nil,
        networkHistory: [Double] = [],
        batteryPercent: Double? = nil,
        batteryIsCharging: Bool? = nil,
        batteryTimeRemainingMinutes: Int? = nil
    ) {
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
        self.networkHistory = networkHistory
        self.batteryPercent = batteryPercent
        self.batteryIsCharging = batteryIsCharging
        self.batteryTimeRemainingMinutes = batteryTimeRemainingMinutes
    }

    public static let empty = WidgetSystemMetrics()
}

struct WidgetNetworkCounters: Equatable, Sendable {
    let received: UInt32
    let sent: UInt32
}

struct WidgetNetworkRates: Equatable, Sendable {
    let downloadBytesPerSecond: Double
    let uploadBytesPerSecond: Double
}

enum WidgetNetworkRateSampler {
    /// Calculate interface rates using wrapping 32-bit counters returned by getifaddrs.
    static func rates(
        previous: WidgetNetworkCounters,
        current: WidgetNetworkCounters,
        elapsed: TimeInterval
    ) -> WidgetNetworkRates? {
        guard elapsed.isFinite, elapsed > 0 else { return nil }
        guard let receivedDelta = counterDelta(previous: previous.received, current: current.received),
              let sentDelta = counterDelta(previous: previous.sent, current: current.sent) else { return nil }
        return WidgetNetworkRates(
            downloadBytesPerSecond: Double(receivedDelta) / elapsed,
            uploadBytesPerSecond: Double(sentDelta) / elapsed
        )
    }

    private static func counterDelta(previous: UInt32, current: UInt32) -> UInt64? {
        if current >= previous { return UInt64(current - previous) }
        let wrapWindow = UInt32.max / 16
        guard previous > UInt32.max - wrapWindow, current < wrapWindow else { return nil }
        return UInt64(UInt32.max - previous) + 1 + UInt64(current)
    }
}

@MainActor
final class WidgetSystemMetricsProvider {
    private struct NetworkSample {
        let interfaceName: String
        let counters: WidgetNetworkCounters
        let date: Date
    }

    private struct InterfaceCounters {
        let name: String
        let counters: WidgetNetworkCounters
    }

    private var previousCPUTicks: (total: UInt32, idle: UInt32)?
    private var previousNetworkSample: NetworkSample?
    private var history: [Double] = []

    func reset() {
        previousCPUTicks = nil
        previousNetworkSample = nil
        history.removeAll(keepingCapacity: false)
    }

    func sample(at date: Date, includeBattery: Bool) -> WidgetSystemMetrics {
        let networkInterface = primaryInterfaceCounters()
        var downloadRate: Double?
        var uploadRate: Double?

        if let current = networkInterface {
            if let previous = previousNetworkSample,
               previous.interfaceName == current.name,
               let rates = WidgetNetworkRateSampler.rates(
                   previous: previous.counters,
                   current: current.counters,
                   elapsed: date.timeIntervalSince(previous.date)
               ) {
                downloadRate = rates.downloadBytesPerSecond
                uploadRate = rates.uploadBytesPerSecond
                history.append(rates.downloadBytesPerSecond + rates.uploadBytesPerSecond)
            }
            previousNetworkSample = NetworkSample(interfaceName: current.name, counters: current.counters, date: date)
        } else {
            previousNetworkSample = nil
        }
        if history.count > 30 { history.removeFirst(history.count - 30) }

        let battery = includeBattery ? readBattery() : nil
        return WidgetSystemMetrics(
            cpuPercent: sampleCPUPercent(),
            memoryPercent: sampleMemoryPercent(),
            downloadBytesPerSecond: downloadRate,
            uploadBytesPerSecond: uploadRate,
            networkHistory: history,
            batteryPercent: battery?.percent,
            batteryIsCharging: battery?.isCharging,
            batteryTimeRemainingMinutes: battery?.timeRemainingMinutes
        )
    }

    private func sampleCPUPercent() -> Double? {
        var load = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &load) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let ticks = load.cpu_ticks
        let total = ticks.0 &+ ticks.1 &+ ticks.2 &+ ticks.3
        let idle = ticks.2
        defer { previousCPUTicks = (total, idle) }
        guard let previousCPUTicks else { return nil }
        let totalDelta = UInt64(total &- previousCPUTicks.total)
        guard totalDelta > 0 else { return 0 }
        let idleDelta = UInt64(idle &- previousCPUTicks.idle)
        return min(100, max(0, Double(totalDelta - min(totalDelta, idleDelta)) / Double(totalDelta) * 100))
    }

    private func sampleMemoryPercent() -> Double? {
        var statistics = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        var totalMemory: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname("hw.memsize", &totalMemory, &size, nil, 0) == 0, totalMemory > 0 else { return nil }
        let reclaimablePages = UInt64(statistics.free_count)
            + UInt64(statistics.inactive_count)
            + UInt64(statistics.speculative_count)
        let reclaimableBytes = reclaimablePages * UInt64(vm_page_size)
        let usedBytes = totalMemory - min(totalMemory, reclaimableBytes)
        return min(100, max(0, Double(usedBytes) / Double(totalMemory) * 100))
    }

    /// Sample one active en* interface so bridge, tunnel, and loopback counters are not double-counted.
    private func primaryInterfaceCounters() -> InterfaceCounters? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return nil }
        defer { freeifaddrs(addresses) }

        var candidates: [InterfaceCounters] = []
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let address = current {
            defer { current = address.pointee.ifa_next }
            guard let rawName = address.pointee.ifa_name,
                  let name = String(validatingUTF8: rawName),
                  name.hasPrefix("en"),
                  let socketAddress = address.pointee.ifa_addr,
                  Int32(socketAddress.pointee.sa_family) == AF_LINK,
                  (address.pointee.ifa_flags & UInt32(IFF_UP)) != 0,
                  (address.pointee.ifa_flags & UInt32(IFF_RUNNING)) != 0,
                  let data = address.pointee.ifa_data else { continue }

            let interfaceData = data.assumingMemoryBound(to: if_data.self).pointee
            candidates.append(InterfaceCounters(
                name: name,
                counters: WidgetNetworkCounters(received: interfaceData.ifi_ibytes, sent: interfaceData.ifi_obytes)
            ))
        }

        guard let primaryName = primaryInterfaceName() else { return nil }
        return candidates.first { $0.name == primaryName }
    }

    private func primaryInterfaceName() -> String? {
        guard let store = SCDynamicStoreCreate(kCFAllocatorDefault, "GlassDock.WidgetSystemMetrics" as CFString, nil, nil) else {
            return nil
        }
        for key in ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6"] {
            guard let state = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any],
                  let name = state["PrimaryInterface"] as? String else { continue }
            return name
        }
        return nil
    }

    private func readBattery() -> (percent: Double?, isCharging: Bool?, timeRemainingMinutes: Int?)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sourceList = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }

        for source in sourceList {
            guard let dictionary = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let current = dictionary[kIOPSCurrentCapacityKey as String] as? NSNumber,
                  let maximum = dictionary[kIOPSMaxCapacityKey as String] as? NSNumber,
                  maximum.doubleValue > 0 else { continue }

            let rawTime = (dictionary[kIOPSTimeToEmptyKey as String] as? NSNumber)?.intValue ?? -1
            return (
                percent: min(100, max(0, current.doubleValue / maximum.doubleValue * 100)),
                isCharging: dictionary[kIOPSIsChargingKey as String] as? Bool,
                timeRemainingMinutes: rawTime >= 0 ? rawTime : nil
            )
        }
        return nil
    }
}
