import PulseCore
import SwiftUI

/// Coach head of the dashboard (reference mockup, Neubau plan §4 point 1):
/// orb + "ROOK" on the left, "Vorlesen" on the right.
struct RookHeader: View {
    var presence: RookPresence
    var name = "ROOK"
    /// Nil hides the button (e.g. while nothing is there to read).
    var onReadAloud: (() -> Void)?
    /// While the coach speaks, the button stops instead.
    var isSpeaking = false

    @ScaledMetric(relativeTo: .headline) private var orbSize: CGFloat = 32
    @Environment(\.dynamicTypeSize) private var typeSize

    // An explicit switch instead of ViewThatFits: the accessibility audit reported text inside ViewThatFits
    // as "Dynamic Type partially unsupported" (run 166).
    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: DKSpace.m) {
                identity
                readButton
            }
        } else {
            HStack(spacing: DKSpace.m) {
                identity
                Spacer(minLength: DKSpace.s)
                readButton
            }
        }
    }

    private var identity: some View {
        HStack(spacing: DKSpace.m) {
            RookOrb(presence: presence, size: orbSize)
            Text(name)
                .font(DKFont.wordmark)
                .tracking(DKTracking.wordmark)
                .foregroundStyle(DKColor.textPrimary)
                .accessibilityHidden(true)   // the orb already says "ROOK …"
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var readButton: some View {
        if let onReadAloud {
            Button(action: onReadAloud) {
                Label(isSpeaking ? "Stopp" : "Vorlesen",
                      systemImage: isSpeaking ? "stop.fill" : "speaker.wave.2")
            }
            .buttonStyle(DKPillButtonStyle())
            .accessibilityIdentifier("rook.readAloud")
        }
    }
}

/// The coach's headline with its one or two sentences of interpretation (plan §4 point 2).
struct CoachHeadline: View {
    let headline: String
    var interpretation: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DKSpace.m) {
            Text(headline)
                .font(DKFont.headline)
                .foregroundStyle(DKColor.textPrimary)
                .wraps()
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("coach.headline")
            if let interpretation {
                Text(interpretation)
                    .font(DKFont.body)
                    .foregroundStyle(DKColor.textSecondary)
                    .lineSpacing(3)
                    .wraps()
                    .accessibilityIdentifier("coach.interpretation")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
