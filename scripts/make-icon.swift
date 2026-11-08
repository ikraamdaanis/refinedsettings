// Renders Resources/AppIcon.icns: a silver settings gear over a smaller inner gear, on a baby blue tile, with a blue
// hub as the accent. Drawn on Apple's 1024 pt icon grid.
// Run from the repo root: swift scripts/make-icon.swift
import AppKit

let outputDirectory = URL(fileURLWithPath: "Resources")
let iconsetURL = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
let center = CGPoint(x: 512, y: 512)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func linearGradient(_ colors: [CGColor]) -> CGGradient? {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)
}

func circle(radius: CGFloat) -> CGRect {
    CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
}

/// A gear ring: a disc with rounded teeth around it and a hole cut through the middle.
func fillGearRing(
    in context: CGContext,
    toothCount: Int,
    rootRadius: CGFloat,
    tipRadius: CGFloat,
    toothWidth: CGFloat,
    holeRadius: CGFloat,
    rotation: CGFloat
) {
    context.fillEllipse(in: circle(radius: rootRadius))

    for index in 0..<toothCount {
        let angle = CGFloat(index) / CGFloat(toothCount) * .pi * 2 + rotation
        let tooth = CGRect(x: -toothWidth / 2, y: rootRadius - 12, width: toothWidth, height: tipRadius - rootRadius + 12)
        var transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle)
        let corner = min(toothWidth / 2 - 1, 9)
        context.addPath(CGPath(roundedRect: tooth, cornerWidth: corner, cornerHeight: corner, transform: &transform))
        context.fillPath()
    }

    context.saveGState()
    context.setBlendMode(.clear)
    context.fillEllipse(in: circle(radius: holeRadius))
    context.restoreGState()
}

/// Fills everything drawn so far in the current transparency layer with a top-lit silver gradient.
func applyMetal(in context: CGContext, top: CGFloat, bottom: CGFloat, light: UInt32, dark: UInt32) {
    guard let metal = linearGradient([color(light), color(dark)]) else { return }

    context.saveGState()
    context.setBlendMode(.sourceIn)
    context.drawLinearGradient(metal, start: CGPoint(x: 512, y: top), end: CGPoint(x: 512, y: bottom), options: [])
    context.restoreGState()
}

func drawIcon(in context: CGContext) {
    // The rounded square sits inside a 100 pt margin, like every macOS app icon.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, alpha: 0.3))
    context.addPath(tilePath)
    context.setFillColor(color(0x000000))
    context.fillPath()
    context.restoreGState()

    // A light baby blue instead of System Settings' neutral grey.
    context.saveGState()
    context.addPath(tilePath)
    context.clip()

    if let background = linearGradient([color(0xB5DEF8), color(0x79B8E8)]) {
        context.drawLinearGradient(background, start: CGPoint(x: 512, y: tile.maxY), end: CGPoint(x: 512, y: tile.minY), options: [])
    }

    if let highlight = linearGradient([color(0xFFFFFF, alpha: 0.16), color(0xFFFFFF, alpha: 0)]) {
        context.drawLinearGradient(highlight, start: CGPoint(x: 512, y: tile.maxY), end: CGPoint(x: 512, y: tile.midY), options: [])
    }

    context.restoreGState()

    // The inner gear, set back behind the main one.
    context.saveGState()
    context.setAlpha(0.95)
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    context.setFillColor(color(0xFFFFFF))
    fillGearRing(in: context, toothCount: 26, rootRadius: 196, tipRadius: 222, toothWidth: 24, holeRadius: 158, rotation: 0.06)
    applyMetal(in: context, top: 734, bottom: 290, light: 0x5C9FDB, dark: 0x3B7CC2)
    context.endTransparencyLayer()
    context.restoreGState()

    // The main gear: rim, three spokes and a hub, as one silver piece with one shadow.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: color(0x1B1F27, alpha: 0.45))
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    context.setFillColor(color(0xFFFFFF))
    fillGearRing(in: context, toothCount: 36, rootRadius: 300, tipRadius: 336, toothWidth: 30, holeRadius: 254, rotation: 0)

    for index in 0..<3 {
        let angle = CGFloat(index) / 3 * .pi * 2
        let spoke = CGMutablePath()
        spoke.move(to: CGPoint(x: -26, y: 0))
        spoke.addLine(to: CGPoint(x: -15, y: 270))
        spoke.addLine(to: CGPoint(x: 15, y: 270))
        spoke.addLine(to: CGPoint(x: 26, y: 0))
        spoke.closeSubpath()
        var transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle)

        if let rotated = spoke.copy(using: &transform) {
            context.addPath(rotated)
            context.fillPath()
        }
    }

    context.fillEllipse(in: circle(radius: 52))
    applyMetal(in: context, top: 848, bottom: 176, light: 0xFFFFFF, dark: 0xC9CED8)
    context.endTransparencyLayer()
    context.restoreGState()

    // The twist: a blue hub where System Settings has a plain one.
    if let hub = linearGradient([color(0x4DA3FF), color(0x0A6CF0)]) {
        context.saveGState()
        context.addEllipse(in: circle(radius: 28))
        context.clip()
        context.drawLinearGradient(hub, start: CGPoint(x: 512, y: 540), end: CGPoint(x: 512, y: 484), options: [])
        context.restoreGState()
    }
}

func renderIcon(pixels: Int) -> Data? {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }

    let context = graphicsContext.cgContext
    let scale = CGFloat(pixels) / 1024
    context.scaleBy(x: scale, y: scale)
    drawIcon(in: context)
    graphicsContext.flushGraphics()

    return bitmap.representation(using: .png, properties: [:])
}

try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 1 ? "" : "@2x"
        let fileURL = iconsetURL.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
        try renderIcon(pixels: points * scale)?.write(to: fileURL)
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o", outputDirectory.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
