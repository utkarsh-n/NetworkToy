#!/usr/bin/env swift
import AppKit
import ImageIO
import UniformTypeIdentifiers

// Rebuild the app icon without fonts, external artwork or a raster source.
// Run: swift -module-cache-path /private/tmp/snoopynet-icon-cache Tools/generate-icon.swift
let size = 1024
let output = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0) }
    ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("NetworkToy/Assets.xcassets/AppIcon.appiconset/AppIcon.png")

guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let bitmap = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
          bytesPerRow: size * 4, space: colorSpace,
          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("Could not create the opaque RGB icon canvas")
}

let background = NSColor(srgbRed: 0.008, green: 0.021, blue: 0.037, alpha: 1)
let blue = NSColor(srgbRed: 0.07, green: 0.60, blue: 1.0, alpha: 1)
bitmap.setFillColor(background.cgColor)
bitmap.fill(CGRect(x: 0, y: 0, width: size, height: size))
bitmap.setShouldAntialias(true)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmap, flipped: false)

let center = CGPoint(x: 512, y: 540)
let radius = 350.0
NSGraphicsContext.saveGraphicsState()
NSBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius,
    width: radius * 2, height: radius * 2)).addClip()

let ink = NSBezierPath()
func thickness(x: Double, row: Double) -> Double {
    let highlight = exp(-pow((x + 0.40) / 0.37, 2)) * exp(-pow((row + 0.28) / 0.64, 2))
    return 0.115 - highlight * 0.067
}

// The same horizontal band geometry used by the interactive CRT globe.
for stripe in 0..<13 {
    let row = -0.98 + Double(stripe) * (1.96 / 12)
    let band = NSBezierPath()
    for step in 0...96 {
        let x = -1.03 + Double(step) / 96 * 2.06
        let point = CGPoint(x: Double(center.x) + x * radius,
            y: Double(center.y) - (row - thickness(x: x, row: row) / 2) * radius)
        if step == 0 { band.move(to: point) } else { band.line(to: point) }
    }
    for step in stride(from: 96, through: 0, by: -1) {
        let x = -1.03 + Double(step) / 96 * 2.06
        band.line(to: CGPoint(x: Double(center.x) + x * radius,
            y: Double(center.y) - (row + thickness(x: x, row: row) / 2) * radius))
    }
    band.close()
    ink.append(band)
}
let bloom = NSShadow()
bloom.shadowColor = blue.withAlphaComponent(0.65)
bloom.shadowBlurRadius = 18
bloom.shadowOffset = .zero
bloom.set()
blue.setFill()
ink.fill()
NSGraphicsContext.restoreGraphicsState()

bitmap.setStrokeColor(NSColor(srgbRed: 0.25, green: 0.70, blue: 1, alpha: 0.035).cgColor)
bitmap.setLineWidth(1)
for y in stride(from: 0, through: size, by: 6) {
    bitmap.move(to: CGPoint(x: 0, y: y))
    bitmap.addLine(to: CGPoint(x: size, y: y))
}
bitmap.strokePath()

// Seven unobtrusive registration dots are the breakup Easter egg. The globe
// remains the only large mark, so the icon also reads cleanly at small sizes.
blue.setFill()
for index in 0..<7 {
    let angle = (225 + Double(index) * 15) * .pi / 180
    let point = CGPoint(x: Double(center.x) + cos(angle) * 414,
        y: Double(center.y) + sin(angle) * 414)
    NSBezierPath(ovalIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)).fill()
}
NSGraphicsContext.restoreGraphicsState()

guard let image = bitmap.makeImage(),
      let destination = CGImageDestinationCreateWithURL(output as CFURL,
          UTType.png.identifier as CFString, 1, nil) else {
    fatalError("Could not create the PNG output")
}
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not save AppIcon.png") }
print("Wrote opaque 1024 × 1024 RGB icon: \(output.path)")
