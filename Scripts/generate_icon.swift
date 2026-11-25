#!/usr/bin/env swift

// Draws App/Assets.xcassets/AppIcon.appiconset (`just app` compiles it with actool): a tenge sign
// inside a three-part category ring, on a deep navy squircle. Same recipe as Batteries' icon
// (one bright mark, dark gradient). Run with `just icon`; pass a path to also write a 1024 px PNG.

import AppKit
import CoreText
import Foundation

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor { CGColor(colorSpace: sRGB, components: [r, g, b, 1])! }
let green = color(0.30, 0.85, 0.42), blue = color(0.25, 0.55, 1.0), purple = color(0.72, 0.40, 0.95)

/// `fullBleed`: the iPhone icon, a plain square the system masks itself (no squircle, no shadow).
func drawIcon(pixels: Int, fullBleed: Bool = false) -> NSBitmapImageRep {
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
  // Apple's macOS icon grid: the squircle is 824 of 1024 px, centred, with a soft drop shadow.
  let inset = fullBleed ? 0 : CGFloat(pixels) * 100 / 1024
  ctx.translateBy(x: inset, y: inset)
  let s = CGFloat(pixels) - inset * 2
  drawBackground(ctx, s, rounded: !fullBleed)
  drawRing(ctx, s)
  drawTenge(ctx, s)
  return rep
}

func drawBackground(_ ctx: CGContext, _ s: CGFloat, rounded: Bool) {
  let radius = rounded ? s * 0.225 : 0
  let path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s), cornerWidth: radius, cornerHeight: radius, transform: nil)
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: CGColor(gray: 0, alpha: 0.35))
  ctx.addPath(path)
  ctx.fillPath()
  ctx.restoreGState()
  ctx.saveGState()
  ctx.addPath(path)
  ctx.clip()
  let colors = [color(0.10, 0.13, 0.24), color(0.04, 0.05, 0.11)]
  let gradient = CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: [0, 1])!
  ctx.drawLinearGradient(gradient, start: CGPoint(x: s / 2, y: s), end: CGPoint(x: s / 2, y: 0), options: [])
  ctx.restoreGState()
}

/// Three arcs with gaps, as the widget's category bars colour them: food, transport, subscriptions.
func drawRing(_ ctx: CGContext, _ s: CGFloat) {
  let center = CGPoint(x: s / 2, y: s / 2)
  let radius = s * 0.30
  let gap = CGFloat.pi * 0.06
  let parts: [(CGColor, CGFloat)] = [(green, 0.5), (blue, 0.2), (purple, 0.3)]
  var start = CGFloat.pi / 2
  ctx.saveGState()
  ctx.setLineWidth(s * 0.07)
  ctx.setLineCap(.butt)
  for (stroke, share) in parts {
    let end = start - CGFloat.pi * 2 * share
    ctx.setStrokeColor(stroke)
    ctx.addArc(center: center, radius: radius, startAngle: start - gap / 2, endAngle: end + gap / 2, clockwise: true)
    ctx.strokePath()
    start = end
  }
  ctx.restoreGState()
}

func drawTenge(_ ctx: CGContext, _ s: CGFloat) {
  let base = NSFont.systemFont(ofSize: s * 0.36, weight: .bold)
  let font = NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: s * 0.36) ?? base
  let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: CGColor(gray: 1, alpha: 1)]
  let line = CTLineCreateWithAttributedString(NSAttributedString(string: "₸", attributes: attributes))
  let bounds = CTLineGetImageBounds(line, ctx)
  ctx.textPosition = CGPoint(x: (s - bounds.width) / 2 - bounds.minX, y: (s - bounds.height) / 2 - bounds.minY)
  CTLineDraw(line, ctx)
}

let projectDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = projectDir.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let name = "icon_\(points)x\(points)@\(scale)x.png"
    try drawIcon(pixels: points * scale).representation(using: .png, properties: [:])!
      .write(to: iconset.appendingPathComponent(name))
    images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
  }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
  .write(to: iconset.appendingPathComponent("Contents.json"))
let assets = projectDir.appendingPathComponent("App/Assets.xcassets/Contents.json")
try #"{"info":{"author":"xcode","version":1}}"#.write(to: assets, atomically: true, encoding: .utf8)
print("Created \(iconset.path)")

// The iPhone's: one 1024 px universal image, opaque.
let phoneIconset = projectDir.appendingPathComponent("iOS/Assets.xcassets/AppIcon.appiconset")
try? FileManager.default.removeItem(at: phoneIconset)
try FileManager.default.createDirectory(at: phoneIconset, withIntermediateDirectories: true)
try drawIcon(pixels: 1024, fullBleed: true).representation(using: .png, properties: [:])!
  .write(to: phoneIconset.appendingPathComponent("icon-1024.png"))
let phoneContents: [String: Any] = [
  "images": [["filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"]],
  "info": ["author": "xcode", "version": 1]
]
try JSONSerialization.data(withJSONObject: phoneContents, options: [.prettyPrinted, .sortedKeys])
  .write(to: phoneIconset.appendingPathComponent("Contents.json"))
try #"{"info":{"author":"xcode","version":1}}"#
  .write(to: projectDir.appendingPathComponent("iOS/Assets.xcassets/Contents.json"), atomically: true, encoding: .utf8)
print("Created \(phoneIconset.path)")

if CommandLine.arguments.count > 1 {
  let preview = URL(fileURLWithPath: CommandLine.arguments[1])
  try drawIcon(pixels: 1024).representation(using: .png, properties: [:])!.write(to: preview)
  print("Preview \(preview.path)")
}
