#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let size = 1024

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}

let space = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: space,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("Cannot create context")
}

context.clear(CGRect(x: 0, y: 0, width: size, height: size))

let iconRect = CGRect(x: 92, y: 92, width: 840, height: 840)
let corner: CGFloat = 188
let iconPath = CGPath(roundedRect: iconRect, cornerWidth: corner, cornerHeight: corner, transform: nil)

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -18), blur: 34, color: color(0, 0, 0, 0.35))
context.addPath(iconPath)
context.setFillColor(color(0.09, 0.05, 0.15))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(iconPath)
context.clip()

let gradient = CGGradient(
    colorsSpace: space,
    colors: [color(0.10, 0.06, 0.18), color(0.26, 0.10, 0.31), color(0.52, 0.18, 0.36)] as CFArray,
    locations: [0, 0.55, 1]
)!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: iconRect.minX, y: iconRect.maxY),
    end: CGPoint(x: iconRect.maxX, y: iconRect.minY),
    options: []
)

let glow = CGGradient(
    colorsSpace: space,
    colors: [color(1.0, 0.35, 0.43, 0.38), color(1.0, 0.35, 0.43, 0)] as CFArray,
    locations: [0, 1]
)!
context.drawRadialGradient(
    glow,
    startCenter: CGPoint(x: 560, y: 370),
    startRadius: 10,
    endCenter: CGPoint(x: 560, y: 370),
    endRadius: 440,
    options: []
)

let barGradient = CGGradient(
    colorsSpace: space,
    colors: [color(1.0, 0.41, 0.50), color(0.98, 0.27, 0.40), color(0.66, 0.38, 0.94)] as CFArray,
    locations: [0, 0.55, 1]
)!
let barHeights: [CGFloat] = [148, 246, 364, 468, 364, 246, 148]
let barWidth: CGFloat = 34
let gap: CGFloat = 26
let totalWidth = CGFloat(barHeights.count) * barWidth + CGFloat(barHeights.count - 1) * gap
var x = (CGFloat(size) - totalWidth) / 2
let centerY = CGFloat(size) / 2

for height in barHeights {
    let rect = CGRect(x: x, y: centerY - height / 2, width: barWidth, height: height)
    let path = CGPath(roundedRect: rect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil)
    context.saveGState()
    context.addPath(path)
    context.clip()
    context.drawLinearGradient(
        barGradient,
        start: CGPoint(x: x, y: rect.maxY),
        end: CGPoint(x: x + barWidth, y: rect.minY),
        options: []
    )
    context.restoreGState()
    x += barWidth + gap
}

context.setStrokeColor(color(1, 1, 1, 0.10))
context.setLineWidth(2)
context.addPath(iconPath)
context.strokePath()
context.restoreGState()

guard let image = context.makeImage() else {
    fatalError("Cannot create image")
}

let iconset = outputDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "CadenceIcon", code: 1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "CadenceIcon", code: 2)
    }
}

func resized(_ image: CGImage, to pixel: Int) -> CGImage {
    guard let ctx = CGContext(
        data: nil,
        width: pixel,
        height: pixel,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("Cannot create resize context")
    }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: pixel, height: pixel))
    return ctx.makeImage()!
}

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, pixel) in variants {
    try writePNG(resized(image, to: pixel), to: iconset.appendingPathComponent(name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", outputDirectory.appendingPathComponent("AppIcon.icns").path]
try process.run()
process.waitUntilExit()
if process.terminationStatus != 0 {
    fatalError("iconutil failed")
}
try? FileManager.default.removeItem(at: iconset)
print("Wrote \(outputDirectory.appendingPathComponent("AppIcon.icns").path)")
