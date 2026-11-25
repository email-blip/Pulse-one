import SwiftUI

/// Type scale. Every style is tied to a Dynamic Type text style, so all text grows up to XXXL
/// (accessibility sizes included). Large numbers take their size from `@ScaledMetric` in the view.
enum DKFont {
    /// The coach's headline on the dashboard ("Heute ist Platz für einen guten Reiz."), 2–3 lines.
    static let headline = Font.system(.largeTitle, design: .default).weight(.bold)
    /// Screen and card titles.
    static let title = Font.system(.title2, design: .default).weight(.semibold)
    /// Section heads ("Dein Cockpit").
    static let section = Font.system(.title3, design: .default).weight(.semibold)
    /// Reading text (the coach's one or two sentences).
    static let body = Font.system(.body, design: .default)
    static let bodyEmphasis = Font.system(.body, design: .default).weight(.semibold)
    /// Tile names, button labels.
    static let label = Font.system(.subheadline, design: .default).weight(.medium)
    /// Units next to big numbers ("bpm").
    static let unit = Font.system(.subheadline, design: .default)
    /// Small caps references ("NACHT · 07:00"); always uppercase with tracking.
    static let caption = Font.system(.caption, design: .default).weight(.medium)
    /// The coach's name next to the orb ("ROOK"), tracked uppercase.
    static let wordmark = Font.system(.headline, design: .default).weight(.semibold)
    /// Chart axis values and time ticks ("03:00", "60"); tabular digits so ticks line up.
    static let axis = Font.system(.caption, design: .default).monospacedDigit()

    /// Big measured numbers: SF Pro Expanded, tabular digits so values do not jump while they change.
    /// Pass a size from `@ScaledMetric(relativeTo: .largeTitle)`.
    static func number(size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .default).width(.expanded).monospacedDigit()
    }
}

/// Tracking (letter spacing) for uppercase labels.
enum DKTracking {
    static let caption: CGFloat = 0.8
    static let wordmark: CGFloat = 3
}

/// 4-pt spacing grid.
enum DKSpace {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
    /// Side margin of every screen.
    static let page: CGFloat = 20
}

enum DKRadius {
    /// Chips and small controls use capsules; these are for rectangles.
    static let small: CGFloat = 12
    /// Buttons with a rectangle shape.
    static let control: CGFloat = 16
    /// Tiles and cards.
    static let card: CGFloat = 24
}

/// Minimum touch target (Apple HIG).
enum DKSize {
    static let minTouch: CGFloat = 44
    static let buttonHeight: CGFloat = 52
}

/// Layout switches for large text. Johannes reads at a large but not yet accessibility size, so two-column
/// rows and side-by-side headers give up earlier than `isAccessibilitySize` (Build 18 feedback: "Sau-er-stoff",
/// "14…", "Schri tte"). Explicit switches instead of ViewThatFits: the accessibility audit flags text inside
/// ViewThatFits as "Dynamic Type partially unsupported" (run 166).
enum DKLayout {
    /// Tiles in one column, buttons full width.
    static func isSingleColumn(_ size: DynamicTypeSize) -> Bool { size >= .xxLarge }
    /// Title and trailing action stacked instead of side by side.
    static func stacksHeader(_ size: DynamicTypeSize) -> Bool { size >= .xxLarge }
}
