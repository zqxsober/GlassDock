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

import AppKit

let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let background = NSBezierPath(roundedRect: NSRect(x: 42, y: 42, width: 940, height: 940), xRadius: 218, yRadius: 218)
NSGradient(colors: [NSColor(red: 0.12, green: 0.25, blue: 0.23, alpha: 1), NSColor(red: 0.035, green: 0.085, blue: 0.095, alpha: 1)])!.draw(in: background, angle: -60)
NSColor.white.withAlphaComponent(0.2).setStroke()
background.lineWidth = 3
background.stroke()
let widths: [CGFloat] = [156, 172, 156]
let heights: [CGFloat] = [310, 484, 378]
let positions: [CGFloat] = [228, 427, 642]
for index in 0..<3 {
    let rectangle = NSRect(x: positions[index], y: 266, width: widths[index], height: heights[index])
    let shape = NSBezierPath(roundedRect: rectangle, xRadius: 65, yRadius: 65)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 35
    shadow.shadowOffset = NSSize(width: 0, height: -18)
    shadow.set()
    NSColor(red: 0.67, green: 0.93, blue: 0.83, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.95), NSColor(red: 0.53, green: 0.83, blue: 0.76, alpha: 1)])!.draw(in: shape, angle: -70)
    NSColor.white.withAlphaComponent(0.7).setStroke()
    shape.lineWidth = 2
    shape.stroke()
    let reflection = NSBezierPath(roundedRect: NSRect(x: rectangle.minX + 15, y: rectangle.minY + 36, width: 7, height: rectangle.height - 82), xRadius: 3, yRadius: 3)
    NSColor.white.withAlphaComponent(0.5).setFill()
    reflection.fill()
}
image.unlockFocus()
guard CommandLine.arguments.count == 2,
      let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("An output PNG path is required") }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
