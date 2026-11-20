import SwiftUI

/// Type scale mapped to text styles so Dynamic Type scales everything.
enum Typography {
    static let wordmark = Font.system(.title2, design: .rounded).weight(.heavy)
    static let motto    = Font.system(.caption, design: .rounded).weight(.semibold)
    /// Pass a size from `@ScaledMetric(relativeTo: .largeTitle)` so it follows Dynamic Type.
    static func vital(size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .rounded).monospacedDigit() }
    static let title    = Font.system(.title3, design: .rounded).weight(.semibold)
    static let body     = Font.system(.body, design: .rounded)
    static let label    = Font.system(.subheadline, design: .rounded).weight(.medium)
    static let caption  = Font.system(.footnote, design: .rounded)
}

enum Spacing {
    static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16
    static let xl: CGFloat = 24, xxl: CGFloat = 32
}

enum Radius {
    static let medium: CGFloat = 20
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.label.weight(.semibold))
            .foregroundStyle(Palette.obsidian)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, Spacing.l)
            .background(Capsule().fill(Palette.bioCyan))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.3), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.label)
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, Spacing.l)
            // Opaque so text contrast never depends on what is behind the button.
            .background(Capsule().fill(Palette.surfaceButton))
            .overlay(Capsule().strokeBorder(Palette.bioCyan.opacity(0.7), lineWidth: 1.5))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.3), value: configuration.isPressed)
    }
}

extension View {
    /// Wrap instead of truncating at any Dynamic Type size.
    func wraps() -> some View { fixedSize(horizontal: false, vertical: true) }
}

/// Raised glass-like card used for every block on the connect screen.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.l)
            .background(
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .fill(Palette.surfaceRaised)   // opaque: contrast must not depend on the background
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                            .strokeBorder(Palette.hairline, lineWidth: 1)
                    )
            )
    }
}
