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
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/dist/GlassDock.app"
ICONSET="$ROOT/.build/AppIcon.iconset"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT/.build/module-cache}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICONSET"
# Release builds use separate scratch directories for each architecture.
binaries=()
for arch in ${GLASSDOCK_ARCHITECTURES:-$(uname -m)}; do
    case "$arch" in arm64|x86_64) ;; *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; esac
    scratch="$ROOT/.build/release-$arch"
    args=(--package-path "$ROOT" -c release --disable-sandbox --scratch-path "$scratch" --triple "$arch-apple-macosx26.0")
    xcrun swift build "${args[@]}" --product GlassDock
    bin="$(xcrun swift build "${args[@]}" --show-bin-path)"
    binaries+=("$bin/GlassDock")
done
if [[ ${#binaries[@]} -gt 1 ]]; then
    xcrun lipo -create "${binaries[@]}" -output "$APP/Contents/MacOS/GlassDock"
else
    cp "${binaries[0]}" "$APP/Contents/MacOS/GlassDock"
fi
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/LICENSE" "$ROOT/NOTICE" "$APP/Contents/Resources/"
xcrun swift "$ROOT/Resources/GenerateIcon.swift" "$ROOT/.build/AppIcon.png"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ROOT/.build/AppIcon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$ROOT/.build/AppIcon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    codesign --force --sign "$DEVELOPER_ID_APPLICATION" --options runtime --timestamp \
        --entitlements "$ROOT/Resources/GlassDock.entitlements" "$APP"
else
    codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"
printf '\nBuilt: %s\n' "$APP"
