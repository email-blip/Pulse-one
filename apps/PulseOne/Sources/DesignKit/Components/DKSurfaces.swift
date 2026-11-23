import SwiftUI

extension View {
    /// Wrap instead of truncating at any Dynamic Type size.
    func wraps() -> some View { fixedSize(horizontal: false, vertical: true) }

    /// Page background of every screen: Obsidian with the soft glow behind the coach head.
    func dkPageBackground() -> some View {
        background { DKPageBackground() }
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

/// Section head ("Dein Cockpit") with an optional trailing action ("Kacheln anordnen").
struct DKSectionHeader: View {
    let title: String
    var actionTitle: String?
    var actionIdentifier: String?
    var action: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: DKSpace.xs) {
                titleText
                actionButton
            }
        } else {
            HStack(alignment: .firstTextBaseline) {
                titleText
                Spacer(minLength: DKSpace.s)
                actionButton
            }
        }
    }

    private var titleText: some View {
        Text(title)
            .font(DKFont.section)
            .foregroundStyle(DKColor.textPrimary)
            .wraps()
            .accessibilityAddTraits(.isHeader)
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
