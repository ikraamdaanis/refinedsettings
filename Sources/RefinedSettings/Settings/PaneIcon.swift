import SwiftUI

/// A pane's coloured rounded-square icon, at sidebar size or header size.
struct PaneIcon: View {
    let pane: SettingsPane
    let size: CGFloat

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
    }

    var body: some View {
        glyph
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(pane.iconGradient, in: shape)
            .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: size / 40, y: size / 40)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var glyph: some View {
        if pane == .general {
            Image(nsImage: GearGlyph.image(pointSize: size * 0.74, accessibilityDescription: nil))
                .renderingMode(.template)
        } else {
            Image(systemName: pane.symbolName)
                .font(.system(size: size * 0.55, weight: .semibold))
        }
    }
}
