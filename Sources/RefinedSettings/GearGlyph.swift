import AppKit

/// The app icon's gear (a toothed rim, three spokes and a hub) as a one-colour template image, for the menu bar
/// and menus. Same shape as `scripts/make-icon.swift`, with fewer, wider teeth and a thicker rim so it stays
/// legible at 15 to 18 points.
enum GearGlyph {
    /// Drawing space: the gear is centred at (512, 512) like the app icon, with this outer (tooth tip) radius.
    private static let tipRadius: CGFloat = 336
    private static let rootRadius: CGFloat = 300
    private static let rimInnerRadius: CGFloat = 244
    private static let toothCount = 24
    private static let toothWidth: CGFloat = 42
    private static let hubRadius: CGFloat = 70
    /// The app icon's blue hub, cut out so it reads as a dot in the middle.
    private static let hubHoleRadius: CGFloat = 32

    static func image(pointSize: CGFloat, accessibilityDescription: String?) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }

            draw(in: context, rect: rect)

            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription

        return image
    }

    private static func draw(in context: CGContext, rect: CGRect) {
        let scale = min(rect.width, rect.height) / (tipRadius * 2)
        context.translateBy(x: rect.midX, y: rect.midY)
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(NSColor.black.cgColor)
        // A transparency layer keeps the cut-outs below from punching through whatever the image is drawn on.
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.fillEllipse(in: circle(radius: rootRadius))

        for index in 0..<toothCount {
            let angle = CGFloat(index) / CGFloat(toothCount) * .pi * 2
            let tooth = CGRect(x: -toothWidth / 2, y: rootRadius - 12, width: toothWidth, height: tipRadius - rootRadius + 12)
            var transform = CGAffineTransform(rotationAngle: angle)
            context.addPath(CGPath(roundedRect: tooth, cornerWidth: 12, cornerHeight: 12, transform: &transform))
            context.fillPath()
        }

        context.setBlendMode(.clear)
        context.fillEllipse(in: circle(radius: rimInnerRadius))
        context.setBlendMode(.normal)

        for index in 0..<3 {
            let spoke = CGMutablePath()
            spoke.move(to: CGPoint(x: -34, y: 0))
            spoke.addLine(to: CGPoint(x: -22, y: rimInnerRadius + 16))
            spoke.addLine(to: CGPoint(x: 22, y: rimInnerRadius + 16))
            spoke.addLine(to: CGPoint(x: 34, y: 0))
            spoke.closeSubpath()
            var transform = CGAffineTransform(rotationAngle: CGFloat(index) / 3 * .pi * 2)

            if let rotatedSpoke = spoke.copy(using: &transform) {
                context.addPath(rotatedSpoke)
                context.fillPath()
            }
        }

        context.fillEllipse(in: circle(radius: hubRadius))
        context.setBlendMode(.clear)
        context.fillEllipse(in: circle(radius: hubHoleRadius))
        context.endTransparencyLayer()
    }

    private static func circle(radius: CGFloat) -> CGRect {
        CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
    }
}
