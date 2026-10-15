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
import Foundation
import GlassDockCore
import IOKit

/// 一次温度读取的来源。实现只在采样器的后台串行队列上调用，句柄创建一次后复用。
protocol CPUTemperatureSource: AnyObject {
    /// 读取接口是否存在（私有符号可解析、服务可打开）。false 时直接判定为不可用。
    var isAvailable: Bool { get }
    /// CPU 相关传感器的摄氏读数；调用失败返回 nil。
    func readCPUTemperatures() -> [Double]?
}

/// 每 2 秒在后台队列读取一次 CPU 温度，结果回到主线程。只在有温度组件时运行。
@MainActor
final class CPUTemperatureSampler {
    static let interval: TimeInterval = 2

    private(set) var machine = CPUTemperatureStateMachine()
    private let makeSource: @Sendable () -> CPUTemperatureSource?
    private let queue = DispatchQueue(label: "GlassDock.CPUTemperature", qos: .utility)
    private let onUpdate: (CPUTemperatureState) -> Void
    private nonisolated(unsafe) var source: CPUTemperatureSource?
    private nonisolated(unsafe) var didCreateSource = false
    private var timer: Timer?
    private var inFlight = false
    private var generation = 0

    init(makeSource: @escaping @Sendable () -> CPUTemperatureSource? = CPUTemperatureSampler.platformSource,
         onUpdate: @escaping (CPUTemperatureState) -> Void) {
        self.makeSource = makeSource
        self.onUpdate = onUpdate
    }

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.sample() }
        }
        timer?.tolerance = 0.5
        sample()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        generation += 1
        inFlight = false
        machine.reset()
        onUpdate(machine.state)
    }

    /// 发起一次读取；上一次尚未返回时跳过，避免读取变慢时排队堆积。
    func sample(completion: (@MainActor () -> Void)? = nil) {
        guard !inFlight else { completion?(); return }
        inFlight = true
        let token = generation
        queue.async { [self] in
            let result = readOnQueue()
            Task { @MainActor in
                defer { completion?() }
                guard token == self.generation else { return }
                self.inFlight = false
                self.machine.record(readings: result.readings, sourceAvailable: result.available)
                self.onUpdate(self.machine.state)
            }
        }
    }

    private nonisolated func readOnQueue() -> (readings: [Double]?, available: Bool) {
        if !didCreateSource {
            didCreateSource = true
            source = makeSource()
        }
        guard let source, source.isAvailable else { return (nil, false) }
        return (source.readCPUTemperatures(), true)
    }

    nonisolated static func platformSource() -> CPUTemperatureSource? {
        #if arch(arm64)
        return AppleSiliconTemperatureSource()
        #elseif arch(x86_64)
        return IntelSMCTemperatureSource()
        #else
        return nil
        #endif
    }
}

// MARK: - Apple 芯片：IOHIDEventSystem（未公开接口）

/// 通过 dlsym 解析 IOKit 中未公开的 HID 温度接口；任一符号缺失时 `isAvailable == false`，
/// 不在链接期依赖私有符号，系统更新移除接口后只会降级为“不可用”。
final class AppleSiliconTemperatureSource: CPUTemperatureSource {
    private typealias CreateClient = @convention(c) (CFAllocator?) -> UnsafeMutableRawPointer?
    private typealias SetMatching = @convention(c) (UnsafeMutableRawPointer, CFDictionary) -> Int32
    private typealias CopyServices = @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?
    private typealias CopyProperty = @convention(c) (UnsafeMutableRawPointer, CFString) -> UnsafeMutableRawPointer?
    private typealias CopyEvent = @convention(c) (UnsafeMutableRawPointer, Int64, Int32, Int64) -> UnsafeMutableRawPointer?
    private typealias GetFloatValue = @convention(c) (UnsafeMutableRawPointer, Int32) -> Double

    private static let temperatureEventType: Int64 = 15 // kIOHIDEventTypeTemperature
    private static let temperatureField = Int32(15 << 16) // IOHIDEventFieldBase(kIOHIDEventTypeTemperature)

    private let copyEvent: CopyEvent?
    private let getFloatValue: GetFloatValue?
    /// 匹配到的 CPU 传感器服务（已 retain），只枚举一次。
    private var services: [UnsafeMutableRawPointer] = []
    private var client: UnsafeMutableRawPointer?

    init() {
        let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let handle, let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }
        let create = symbol("IOHIDEventSystemClientCreate", as: CreateClient.self)
        let setMatching = symbol("IOHIDEventSystemClientSetMatching", as: SetMatching.self)
        let copyServices = symbol("IOHIDEventSystemClientCopyServices", as: CopyServices.self)
        let copyProperty = symbol("IOHIDServiceClientCopyProperty", as: CopyProperty.self)
        copyEvent = symbol("IOHIDServiceClientCopyEvent", as: CopyEvent.self)
        getFloatValue = symbol("IOHIDEventGetFloatValue", as: GetFloatValue.self)
        guard let create, let setMatching, let copyServices, let copyProperty,
              copyEvent != nil, getFloatValue != nil,
              let client = create(kCFAllocatorDefault) else { return }
        self.client = client
        // PrimaryUsagePage 0xff00 / PrimaryUsage 5：Apple 厂商温度传感器。
        let matching = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary
        _ = setMatching(client, matching)
        guard let servicesPointer = copyServices(client) else { return }
        let all = Unmanaged<CFArray>.fromOpaque(servicesPointer).takeRetainedValue()
        for index in 0..<CFArrayGetCount(all) {
            guard let raw = CFArrayGetValueAtIndex(all, index) else { continue }
            let service = UnsafeMutableRawPointer(mutating: raw)
            guard let namePointer = copyProperty(service, "Product" as CFString) else { continue }
            let name = Unmanaged<AnyObject>.fromOpaque(namePointer).takeRetainedValue() as? String ?? ""
            if Self.isCPUSensor(name: name) {
                _ = Unmanaged<AnyObject>.fromOpaque(service).retain()
                services.append(service)
            }
        }
    }

    deinit {
        for service in services { Unmanaged<AnyObject>.fromOpaque(service).release() }
        if let client { Unmanaged<AnyObject>.fromOpaque(client).release() }
    }

    /// CPU die 传感器：M1 为 “PMU tdie*”，M2 及以后还有 “PMU2 tdie*”。
    static func isCPUSensor(name: String) -> Bool {
        name.hasPrefix("PMU") && name.contains("tdie")
    }

    var isAvailable: Bool { client != nil && !services.isEmpty }

    func readCPUTemperatures() -> [Double]? {
        guard let copyEvent, let getFloatValue, !services.isEmpty else { return nil }
        var values: [Double] = []
        for service in services {
            guard let event = copyEvent(service, Self.temperatureEventType, 0, 0) else { continue }
            values.append(getFloatValue(event, Self.temperatureField))
            Unmanaged<AnyObject>.fromOpaque(event).release()
        }
        return values.isEmpty ? nil : values
    }
}

// MARK: - Intel：AppleSMC

/// 读取 AppleSMC 的 CPU 温度 key。IOKit 调用是公开的，SMC key 协议没有公开文档。
final class IntelSMCTemperatureSource: CPUTemperatureSource {
    private struct KeyVersion { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0, release: UInt16 = 0 }
    private struct PLimitData { var version: UInt16 = 0, length: UInt16 = 0, cpuPLimit: UInt32 = 0, gpuPLimit: UInt32 = 0, memPLimit: UInt32 = 0 }
    private struct KeyInfo { var dataSize: UInt32 = 0, dataType: UInt32 = 0, dataAttributes: UInt8 = 0 }
    /// 与 AppleSMC 用户客户端的 SMCKeyData_t 布局一致（80 字节）。
    private struct KeyData {
        var key: UInt32 = 0
        var vers = KeyVersion()
        var pLimitData = PLimitData()
        var keyInfo = KeyInfo()
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private static let handleYPCEvent: UInt32 = 2
    private static let readKeyCommand: UInt8 = 5
    private static let keyInfoCommand: UInt8 = 9
    /// CPU proximity / die / PECI 等 key，存在哪个读哪个。
    static let cpuKeys = ["TC0P", "TC0D", "TC0E", "TC0F", "TC1C", "TC2C", "TC3C", "TC4C", "TCXC"]

    private var connection: io_connect_t = 0
    private var usableKeys: [String]?

    init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        if IOServiceOpen(service, mach_task_self_, 0, &connection) != kIOReturnSuccess { connection = 0 }
    }

    deinit { if connection != 0 { IOServiceClose(connection) } }

    var isAvailable: Bool { connection != 0 }

    func readCPUTemperatures() -> [Double]? {
        guard connection != 0 else { return nil }
        if usableKeys == nil { usableKeys = Self.cpuKeys.filter { read(key: $0) != nil } }
        let values = (usableKeys ?? []).compactMap { read(key: $0) }
        return values.isEmpty ? nil : values
    }

    static func fourCharCode(_ text: String) -> UInt32 {
        text.utf8.prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }
    }

    /// sp78：有符号 8.8 定点；flt：小端 Float32。
    static func decode(type: UInt32, bytes: [UInt8]) -> Double? {
        if type == fourCharCode("sp78"), bytes.count >= 2 {
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        }
        if type == fourCharCode("flt "), bytes.count >= 4 {
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: bits))
        }
        return nil
    }

    private func read(key: String) -> Double? {
        var input = KeyData()
        input.key = Self.fourCharCode(key)
        input.data8 = Self.keyInfoCommand
        guard let info = call(&input), info.result == 0 else { return nil }
        var request = KeyData()
        request.key = input.key
        request.keyInfo.dataSize = info.keyInfo.dataSize
        request.data8 = Self.readKeyCommand
        guard let output = call(&request), output.result == 0 else { return nil }
        let size = Int(min(32, info.keyInfo.dataSize))
        let bytes = withUnsafeBytes(of: output.bytes) { Array($0.prefix(size)) }
        return Self.decode(type: info.keyInfo.dataType, bytes: bytes)
    }

    private func call(_ input: inout KeyData) -> KeyData? {
        var output = KeyData()
        var outputSize = MemoryLayout<KeyData>.stride
        let status = IOConnectCallStructMethod(connection, Self.handleYPCEvent,
                                               &input, MemoryLayout<KeyData>.stride, &output, &outputSize)
        return status == kIOReturnSuccess ? output : nil
    }
}
