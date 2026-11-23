import PulseCore
import SwiftUI

/// Colour per score, only to tell the three apart; never a rating.
extension ScoreKind {
    var tint: Color {
        switch self {
        case .sleep: Palette.neuralViolet
        case .recovery: Palette.bioCyan
        case .activity: Palette.pulseCoral
        }
    }
}

/// The three rings at the top of TODAY. A tap opens the score with its building blocks.
struct ScoreRingsCard: View {
    let scores: [ScoreEntry]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: Spacing.m))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.m))
        Card {
            layout {
                ForEach(scores) { item in
                    NavigationLink { ScoreDetailScreen(kind: item.kind) } label: {
                        ScoreRingTile(kind: item.kind, result: item.result)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("today.score.\(item.kind.rawValue)")
                }
            }
        }
    }
}

struct ScoreRingTile: View {
    let kind: ScoreKind
    let result: ScoreResult

    var body: some View {
        VStack(spacing: Spacing.s) {
            ScoreRing(value: result.score?.value, tint: kind.tint, lineWidth: 8) {
                Text(result.score.map { "\($0.value)" } ?? "–")
                    .font(Typography.title.monospacedDigit())
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .frame(width: 76, height: 76)
            Text(kind.title).font(Typography.label).foregroundStyle(Palette.ink).wraps()
            Text(result.placeholder).font(Typography.caption).foregroundStyle(Palette.inkMuted)
                .multilineTextAlignment(.center).wraps()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.title): \(result.score.map { "\($0.value) von 100, \($0.word)" } ?? result.placeholder)")
        .accessibilityAddTraits(.isButton)
    }
}

/// A ring filled to `value` of 100; empty track when there is no number.
struct ScoreRing<Center: View>: View {
    let value: Int?
    let tint: Color
    let lineWidth: CGFloat
    @ViewBuilder var center: Center

    var body: some View {
        ZStack {
            Circle().stroke(Palette.hairline, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(value ?? 0) / 100)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center
        }
    }
}
