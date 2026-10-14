#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 zqxsober
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
if [[ $# -eq 2 && $1 == --version ]]; then
    [[ $2 == "$version" ]] || { echo "Requested version does not match Resources/Info.plist ($version)." >&2; exit 1; }
elif [[ $# -ne 0 ]]; then
    echo "Usage: $0 [--version $version]" >&2
    exit 1
fi
if [[ -n "${NOTARYTOOL_PROFILE:-}" && -z "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    echo "Notarization requires DEVELOPER_ID_APPLICATION." >&2
    exit 1
fi
export GLASSDOCK_ARCHITECTURES="arm64 x86_64"
bash "$ROOT/build.sh"
app="$ROOT/dist/GlassDock.app"
xcrun lipo "$app/Contents/MacOS/GlassDock" -verify_arch arm64 x86_64
stage="$(mktemp -d "$ROOT/.build/dmg-stage.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/GlassDock.app"
ln -s /Applications "$stage/Applications"
cp "$ROOT/LICENSE" "$ROOT/NOTICE" "$stage/"
cat > "$stage/INSTALL.txt" <<'INSTALL'
GlassDock — macOS 26+

中文：拖动 GlassDock.app 到 Applications 后启动。
首次使用窗口管理需在系统设置的“隐私与安全性 → 辅助功能”中授权。
如本版本未公证，请在系统设置“隐私与安全性”中按 macOS 的提示确认打开。
不要全局关闭 Gatekeeper。授权日历、提醒事项和音乐均为可选操作。

English: Drag GlassDock.app to Applications, then launch it.
Enable Accessibility in System Settings > Privacy & Security for window management.
For an unnotarized release, follow macOS's explicit approval prompt in Privacy & Security.
Do not disable Gatekeeper globally. Calendar, Reminders, and Music permissions are optional.
INSTALL
name="GlassDock-v$version-universal"
dmg="$ROOT/dist/$name.dmg"
if [[ -e "$dmg" ]]; then
    echo "Release artifact already exists; choose a new version or move it aside: $dmg" >&2
    exit 1
fi
hdiutil create -volname "GlassDock $version" -srcfolder "$stage" -format UDZO -imagekey zlib-level=9 "$dmg"
trust="Ad-hoc signed; not notarized / 临时签名，未公证"
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    codesign --sign "$DEVELOPER_ID_APPLICATION" --timestamp "$dmg"
    trust="Developer ID signed; not notarized / Developer ID 签名，未公证"
fi
if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
    xcrun notarytool submit "$dmg" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
    xcrun stapler staple "$dmg"
    xcrun stapler validate "$dmg"
    spctl --assess --type open --context context:primary-signature "$dmg"
    trust="Developer ID signed and notarized / 已签名并公证"
fi
hdiutil verify "$dmg"
(cd "$ROOT/dist" && shasum -a 256 "$name.dmg" > "$name.dmg.sha256")
printf 'Version: %s\nArchitecture: arm64, x86_64\nmacOS: 26+\nTrust: %s\n' "$version" "$trust" > "$ROOT/dist/$name-build-info.txt"
printf '\nDMG: %s\nTrust: %s\n' "$dmg" "$trust"
