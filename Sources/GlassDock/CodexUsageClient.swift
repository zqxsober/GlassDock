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

enum CodexUsageClientError: Error, Sendable {
    case unavailable
    case launchFailed
    case timedOut
    case cancelled
    case protocolError
    case invalidResponse
}

final class CodexUsageClient: @unchecked Sendable {
    private static let requestTimeout: TimeInterval = 10
    private let queue = DispatchQueue(label: "GlassDock.CodexUsageClient", qos: .utility)
    private let executableURL: URL?
    private var request: Request?

    init() {
        self.executableURL = Self.discoverExecutable()
    }

    init(executableURL: URL?) {
        self.executableURL = executableURL
    }

    func fetch(completion: @escaping @Sendable (Result<CodexUsageSnapshot, CodexUsageClientError>) -> Void) {
        queue.async { [self] in
            guard request == nil else {
                completion(.failure(.protocolError))
                return
            }
            guard let executableURL else {
                completion(.failure(.unavailable))
                return
            }
            startRequest(executableURL: executableURL, completion: completion)
        }
    }

    func cancel() {
        queue.async { [self] in
            guard let request else { return }
            finish(request, with: .failure(.cancelled), forceKill: true)
        }
    }

    private func startRequest(
        executableURL: URL,
        completion: @escaping @Sendable (Result<CodexUsageSnapshot, CodexUsageClientError>) -> Void
    ) {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executableURL
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)

        let nextRequest = Request(process: process, input: input, output: output, completion: completion)
        request = nextRequest
        output.fileHandleForReading.readabilityHandler = { [weak self, weak nextRequest] handle in
            let data = handle.availableData
            guard let self, let nextRequest else { return }
            self.queue.async { [self] in
                guard self.request === nextRequest else { return }
                guard !data.isEmpty else {
                    self.finish(nextRequest, with: .failure(.protocolError), forceKill: true)
                    return
                }
                self.receive(data, for: nextRequest)
            }
        }
        // EOF 由 stdout 读取回调处理，避免退出回调抢在最后一条响应之前。

        do {
            try process.run()
        } catch {
            finish(nextRequest, with: .failure(.launchFailed), forceKill: true)
            return
        }

        let timeout = DispatchWorkItem { [self, weak nextRequest] in
            guard let nextRequest, request === nextRequest else { return }
            finish(nextRequest, with: .failure(.timedOut), forceKill: true)
        }
        nextRequest.timeout = timeout
        queue.asyncAfter(deadline: .now() + Self.requestTimeout, execute: timeout)
        sendInitialize(for: nextRequest)
    }

    private func receive(_ data: Data, for request: Request) {
        request.buffer.append(data)
        guard request.buffer.count <= 1_048_576 else {
            finish(request, with: .failure(.invalidResponse), forceKill: true)
            return
        }

        while let newline = request.buffer.firstIndex(of: 0x0A) {
            var line = Data(request.buffer[..<newline])
            request.buffer.removeSubrange(...newline)
            if line.last == 0x0D { line.removeLast() }
            guard !line.isEmpty,
                  let message = try? JSONSerialization.jsonObject(with: line, options: [.fragmentsAllowed]) as? [String: Any]
            else { continue }
            handle(message, for: request)
            guard self.request === request else { return }
        }
    }

    private func handle(_ message: [String: Any], for request: Request) {
        guard let responseID = (message["id"] as? NSNumber)?.intValue else { return }
        switch (request.stage, responseID) {
        case (.initializing, 1):
            guard message["error"] == nil else {
                finish(request, with: .failure(.protocolError), forceKill: true)
                return
            }
            request.stage = .reading
            do {
                try send(["method": "initialized"], through: request.input)
                try send(["id": 2, "method": "account/rateLimits/read", "params": [:]], through: request.input)
            } catch {
                finish(request, with: .failure(.protocolError), forceKill: true)
            }
        case (.reading, 2):
            guard message["error"] == nil,
                  let result = message["result"] as? [String: Any],
                  let snapshot = CodexUsageParser.parse(result: result) else {
                finish(request, with: .failure(.invalidResponse), forceKill: true)
                return
            }
            finish(request, with: .success(snapshot), forceKill: false)
        default:
            return
        }
    }

    private func sendInitialize(for request: Request) {
        let message: [String: Any] = [
            "id": 1,
            "method": "initialize",
            "params": [
                "clientInfo": [
                    "name": "glassdock",
                    "title": "GlassDock",
                    "version": AppVersion.current
                ]
            ]
        ]
        do {
            try send(message, through: request.input)
        } catch {
            finish(request, with: .failure(.protocolError), forceKill: true)
        }
    }

    private func send(_ message: [String: Any], through pipe: Pipe) throws {
        let data = try JSONSerialization.data(withJSONObject: message, options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes])
        var line = data
        line.append(0x0A)
        try pipe.fileHandleForWriting.write(contentsOf: line)
    }

    private func finish(
        _ request: Request,
        with result: Result<CodexUsageSnapshot, CodexUsageClientError>,
        forceKill: Bool
    ) {
        guard self.request === request else { return }
        self.request = nil
        request.timeout?.cancel()
        request.output.fileHandleForReading.readabilityHandler = nil
        request.input.fileHandleForWriting.closeFile()
        request.output.fileHandleForReading.closeFile()

        if request.process.isRunning {
            let processID = request.process.processIdentifier
            if forceKill {
                _ = kill(processID, SIGKILL)
            } else {
                request.process.terminate()
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.25) {
                    guard request.process.isRunning,
                          request.process.processIdentifier == processID else { return }
                    _ = kill(processID, SIGKILL)
                }
            }
        }
        request.completion(result)
    }

    private static func discoverExecutable() -> URL? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        var candidates = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0), isDirectory: true).appendingPathComponent("codex") }
        candidates.append(home.appendingPathComponent(".local/bin/codex"))

        let appBundles = [
            URL(fileURLWithPath: "/Applications/Codex.app", isDirectory: true),
            home.appendingPathComponent("Applications/Codex.app", isDirectory: true)
        ]
        for appBundle in appBundles {
            candidates += [
                appBundle.appendingPathComponent("Contents/Resources/codex"),
                appBundle.appendingPathComponent("Contents/MacOS/codex"),
                appBundle.appendingPathComponent("Contents/SharedSupport/codex")
            ]
        }
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    private final class Request {
        enum Stage {
            case initializing
            case reading
        }

        let process: Process
        let input: Pipe
        let output: Pipe
        let completion: @Sendable (Result<CodexUsageSnapshot, CodexUsageClientError>) -> Void
        var stage = Stage.initializing
        var buffer = Data()
        var timeout: DispatchWorkItem?

        init(
            process: Process,
            input: Pipe,
            output: Pipe,
            completion: @escaping @Sendable (Result<CodexUsageSnapshot, CodexUsageClientError>) -> Void
        ) {
            self.process = process
            self.input = input
            self.output = output
            self.completion = completion
        }
    }
}
