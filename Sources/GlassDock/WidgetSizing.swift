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

struct WidgetMetrics {
    let scale: CGFloat

    init(scale: CGFloat = 1) {
        self.scale = max(0, scale)
    }

    var height: CGFloat { 64 * scale }

    func dimension(_ value: CGFloat) -> CGFloat {
        value * scale
    }

    func fontSize(_ value: CGFloat) -> CGFloat {
        max(min(10, height / 4), value * 1.25 * scale)
    }
}

private struct WidgetScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var widgetScale: CGFloat {
        get { self[WidgetScaleKey.self] }
        set { self[WidgetScaleKey.self] = newValue }
    }
}
