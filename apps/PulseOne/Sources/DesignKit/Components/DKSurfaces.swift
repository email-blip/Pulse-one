import SwiftUI

extension View {
    /// Wrap instead of truncating at any Dynamic Type size.
    func wraps() -> some View { fixedSize(horizontal: false, vertical: true) }

    /// Page background of every screen: Obsidian with the soft glow behind the coach head.
    func dkPageBackground() -> some View {
        background { DKPageBackground() }
    }
}

extension View {
    /// Navigation and tab bar opaque in Obsidian: scrolled content never shows through the bar or slides
    /// visibly under the floating buttons (Build 18 feedback). Put it on the root view inside the NavigationStack.
    func dkOpaqueBars() -> some View { modifier(DKOpaqueBars()) }
}

struct DKOpaqueBars: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbarBackground(DKColor.background, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbarBackground(DKColor.background, for: .tabBar)
            .toolbarBackgroundVisibility(.visible, for: .tabBar)
            .modifier(HardScrollEdges())
            .overlay { OpaqueBottomStrip() }
    }
}

/// iOS 26 blurs content into the bars ("scroll edge effect"); the hard style cuts it off at the bar instead.
private struct HardScrollEdges: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.hard, for: [.top, .bottom])
        } else {
            content
        }
    }
}

/// The floating tab bar of iOS 26 has no bar background of its own: an Obsidian strip behind it keeps
/// tiles from running visibly underneath.
private struct OpaqueBottomStrip: View {
    var body: some View {
        GeometryReader { proxy in
            let inset = proxy.safeAreaInsets.bottom
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                DKColor.background.frame(height: inset > 0 ? inset + DKSpace.xxl : 0)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct DKPageBackground: View {
    var body: some View {
        MeshGradient(width: 3, height: 3,
                     points: [[0, 0], [0.5, 0], [1, 0], [0, 0.35], [0.55, 0.3], [1, 0.35], [0, 1], [0.5, 1], [1, 1]],
                     colors: DKColor.backgroundMesh)
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

/// Opaque card: contrast never depends on what is behind it.
struct DKCard<Content: View>: View {
    var padding: CGFloat = DKSpace.l
    /// Violet hairline for the coach's own blocks; default hairline otherwise.
    var isCoach = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DKSpace.m) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: DKRadius.card, style: .continuous)
                    .fill(DKColor.surface)
                    .overlay(RoundedRectangle(cornerRadius: DKRadius.card, style: .continuous)
                        .strokeBorder(isCoach ? DKColor.coach.opacity(0.5) : DKColor.hairline, lineWidth: 1))
            )
    }
}

/// Section head ("Dein Cockpit") with an optional ⓘ explanation and an optional trailing action
/// ("Kacheln anordnen").
struct DKSectionHeader: View {
    let title: String
    /// Explanation behind an ⓘ next to the title instead of a hint text on the screen.
    var info: String?
    var actionTitle: String?
    var actionIdentifier: String?
    var action: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if DKLayout.stacksHeader(typeSize) {
            VStack(alignment: .leading, spacing: DKSpace.xs) {
                titleRow
                actionButton
            }
        } else {
            HStack(alignment: .firstTextBaseline) {
                titleRow
                Spacer(minLength: DKSpace.s)
                actionButton
            }
        }
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: DKSpace.xs) {
            Text(title)
                .font(DKFont.section)
                .foregroundStyle(DKColor.textPrimary)
                .wraps()
                .accessibilityAddTraits(.isHeader)
            if let info {
                DKInfoButton(title: title, text: info)
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if let actionTitle, let action {
            Button(actionTitle, action: action)
                .buttonStyle(DKTextButtonStyle())
                .accessibilityIdentifier(actionIdentifier ?? "section.action")
        }
    }
}

/// Selectable chip (Tag / Woche / Monat, filters). The selected chip is marked by fill, weight and a checkmark,
/// never by color alone, and reports `.isSelected` to VoiceOver.
struct DKChip: View {
    let title: String
    var systemImage: String?
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DKSpace.xs) {
                if isSelected {
                    Image(systemName: "checkmark").accessibilityHidden(true)
                } else if let systemImage {
                    Image(systemName: systemImage).accessibilityHidden(true)
                }
                Text(title)
            }
            .font(isSelected ? DKFont.label.weight(.semibold) : DKFont.label)
            .foregroundStyle(isSelected ? DKColor.onAccent : DKColor.textPrimary)
            .padding(.horizontal, DKSpace.m)
            .frame(minHeight: DKSize.minTouch)
            .background(Capsule().fill(isSelected ? DKColor.accent : DKColor.surfaceRaised))
            .overlay(Capsule().strokeBorder(isSelected ? Color.clear : DKColor.lineStrong, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Uppercase reference line under a value ("NACHT · 07:00").
struct DKReference: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(DKFont.caption)
            .tracking(DKTracking.caption)
            .foregroundStyle(DKColor.textTertiary)
            .wraps()
    }
}
