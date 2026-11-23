import PulseCore
import SwiftUI

/// Fills a shape in a sleep phase's color and pattern (solid, stripes, dots, dashed outline).
/// Team 03 uses it for hypnogram blocks; the legend below uses it for the key.
struct SleepPhaseFill: View {
    let phase: SleepPhase
    var cornerRadius: CGFloat = 4

    var body: some View {
        let style = SleepPhaseStyle.of(phase)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let clip = shape.path(in: rect)
            switch style.pattern {
            case .solid:
                context.fill(clip, with: .color(style.color))
            case .striped:
                context.fill(clip, with: .color(style.color.opacity(0.55)))
                context.clip(to: clip)
                var stripes = Path()
                var x = -size.height
                while x < size.width {
                    stripes.move(to: CGPoint(x: x, y: size.height))
                    stripes.addLine(to: CGPoint(x: x + size.height, y: 0))
                    x += 6
                }
                context.stroke(stripes, with: .color(style.color), lineWidth: 2)
            case .dotted:
                context.fill(clip, with: .color(style.color.opacity(0.55)))
                context.clip(to: clip)
                var dots = Path()
                var y: CGFloat = 2.5
                while y < size.height {
                    var x: CGFloat = 2.5
                    while x < size.width {
                        dots.addEllipse(in: CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3))
                        x += 6
                    }
                    y += 6
                }
                context.fill(dots, with: .color(style.color))
            case .dashedOutline:
                context.stroke(shape.path(in: rect.insetBy(dx: 1, dy: 1)), with: .color(style.color),
                               style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Key for the hypnogram: swatch + name per phase, wraps at large type.
struct SleepPhaseLegend: View {
    var phases: [SleepPhase] = SleepPhase.allCases

    var body: some View {
        FlowLayout(spacing: DKSpace.m) {
            ForEach(phases, id: \.self) { phase in
                HStack(spacing: DKSpace.xs) {
                    SleepPhaseFill(phase: phase, cornerRadius: 3)
                        .frame(width: 18, height: 12)
                    Text(SleepPhaseStyle.of(phase).name)
                        .font(DKFont.caption)
                        .foregroundStyle(DKColor.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Simple wrapping row layout for chips and legends.
struct FlowLayout: Layout {
    var spacing: CGFloat = DKSpace.s

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
