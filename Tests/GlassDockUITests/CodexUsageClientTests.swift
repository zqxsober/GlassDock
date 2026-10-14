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
import Testing
@testable import GlassDock
import GlassDockCore

@Suite("Codex usage client")
struct CodexUsageClientTests {
    @Test func completesTheAppServerHandshakeAndReadsRateLimits() async throws {
        let executable = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlassDock-CodexUsage-\(UUID().uuidString).sh")
        defer { try? FileManager.default.removeItem(at: executable) }

        let script = #"""
        #!/bin/sh
        IFS= read -r initialize
        case "$initialize" in *initialize*) ;; *) exit 10 ;; esac
        printf '%s\n' '{"id":1,"result":{}}'
        IFS= read -r initialized
        case "$initialized" in *initialized*) ;; *) exit 11 ;; esac
        IFS= read -r rate_request
        case "$rate_request" in *account/rateLimits/read*) ;; *) exit 12 ;; esac
        printf '%s\n' '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":300,"resetsAt":1800000000},"secondary":{"usedPercent":35,"windowDurationMins":10080,"resetsAt":1800100000}}}}'
        """#
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let client = CodexUsageClient(executableURL: executable)
        let result: Result<CodexUsageSnapshot, CodexUsageClientError> = await withCheckedContinuation { continuation in
            client.fetch { result in continuation.resume(returning: result) }
        }

        switch result {
        case let .success(snapshot):
            #expect(snapshot.fiveHour?.remainingPercent == 80)
            #expect(snapshot.sevenDay?.remainingPercent == 65)
        case let .failure(error):
            Issue.record("Codex app-server handshake or rate-limit read failed: \(error).")
        }
    }
}
