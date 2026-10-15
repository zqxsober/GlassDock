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

/// 新增界面的中英双语文案：系统首选语言为中文时用中文，其余语言用英文。
public enum L10n {
    public static func text(zh: String, en: String) -> String {
        text(zh: zh, en: en, preferredLanguages: Locale.preferredLanguages)
    }

    public static func text(zh: String, en: String, preferredLanguages: [String]) -> String {
        guard let first = preferredLanguages.first else { return zh }
        return first.lowercased().hasPrefix("zh") ? zh : en
    }
}
