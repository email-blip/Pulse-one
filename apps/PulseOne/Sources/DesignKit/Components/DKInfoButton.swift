import SwiftUI

/// "ⓘ" with the explanation in a popover. Replaces hint texts on screens ("Tippe auf die Spuren …",
/// "Jeder Punkt ist eine echte Messung …"): the screen shows values, the explanation is one tap away.
/// Warnings and anything urgent stay visible on the screen, never behind this button.
struct DKInfoButton: View {
    /// What the explanation is about; VoiceOver reads "Info: <title>".
    let title: String
    let text: String
    var identifier: String?

    @State private var isShown = false

    var body: some View {
        Button { isShown = true } label: {
            Image(systemName: "info.circle")
                .font(DKFont.bodyEmphasis)
                .foregroundStyle(DKColor.accent)
                .frame(minWidth: DKSize.minTouch, minHeight: DKSize.minTouch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Info: \(title)")
        .accessibilityHint(text)
        .accessibilityIdentifier(identifier ?? "info")
        .popover(isPresented: $isShown, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            DKInfoPopover(title: title, text: text)
                .presentationCompactAdaptation(.popover)
        }
    }
}

private struct DKInfoPopover: View {
    let title: String
    let text: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DKSpace.s) {
                Text(title)
                    .font(DKFont.bodyEmphasis)
                    .foregroundStyle(DKColor.textPrimary)
                    .wraps()
                    .accessibilityAddTraits(.isHeader)
                Text(text)
                    .font(DKFont.body)
                    .foregroundStyle(DKColor.textSecondary)
                    .wraps()
            }
            .padding(DKSpace.l)
            .frame(maxWidth: 340, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(idealWidth: 340, maxHeight: 420)
        .background(DKColor.surfaceRaised)
        .accessibilityIdentifier("info.popover")
    }
}
