import PulseCore
import SwiftUI

/// Cockpit tile (plan §4 point 4): name + symbol, big number + unit, reference ("NACHT · 07:00"),
/// room for a mini trend. Sizes follow `DashboardTileSize` (small 1×1, wide 2×1, large 2×2);
/// team 03 lays them out, this view only draws one.
struct MetricTile<Trend: View>: View {
    let name: String
    let systemImage: String
    let tint: Color
    /// Already formatted ("56"); nil shows a dash, never an invented value.
    let value: String?
    let unit: String
    /// When and what ("Nacht · 07:00"); shown uppercase.
    let reference: String
    var size: DashboardTileSize = .small
    /// Mini trend (e.g. `Sparkline`); its own accessibility is hidden, the tile speaks for it.
    @ViewBuilder var trend: Trend

    @ScaledMetric(relativeTo: .largeTitle) private var smallNumber: CGFloat = 34
    @ScaledMetric(relativeTo: .largeTitle) private var largeNumber: CGFloat = 52
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: DKSpace.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                    .font(DKFont.label)
                    .foregroundStyle(DKColor.textSecondary)
                    .wraps()
                    .qaTextProbe("tile.title.\(name)", text: name)
                Spacer(minLength: DKSpace.xs)
                Image(systemName: systemImage)
                    .font(DKFont.label)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            }
            if size == .wide, !typeSize.isAccessibilitySize {
                HStack(alignment: .bottom, spacing: DKSpace.l) {
                    numberBlock
                    trendSlot.frame(maxWidth: .infinity, minHeight: 44, maxHeight: 56)
                }
            } else {
                numberBlock
                Spacer(minLength: 0)
                trendSlot.frame(maxWidth: .infinity, minHeight: size == .large ? 96 : 40,
                                maxHeight: size == .large ? 140 : 52)
            }
        }
        .padding(DKSpace.l)
        .frame(maxWidth: .infinity, minHeight: size == .large ? 260 : 150, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DKRadius.card, style: .continuous)
                .fill(DKColor.surface)
                .overlay(RoundedRectangle(cornerRadius: DKRadius.card, style: .continuous)
                    .strokeBorder(DKColor.hairline, lineWidth: 1))
        )
        .contentShape(RoundedRectangle(cornerRadius: DKRadius.card, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(value.map { "\($0) \(unit), \(reference)" } ?? "kein Wert, \(reference)")
    }

    private var numberBlock: some View {
        VStack(alignment: .leading, spacing: DKSpace.xs) {
            HStack(alignment: .firstTextBaseline, spacing: DKSpace.xs) {
                Text(value ?? "–")
                    .font(DKFont.number(size: size == .large ? largeNumber : smallNumber))
                    .foregroundStyle(DKColor.textPrimary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .qaTextProbe("tile.value.\(name)", text: value ?? "–", minimumScale: 0.6)
                Text(unit)
                    .font(DKFont.unit)
                    .foregroundStyle(DKColor.textSecondary)
                    .qaTextProbe("tile.unit.\(name)", text: unit)
            }
            DKReference(text: reference)
        }
    }

    private var trendSlot: some View {
        trend.accessibilityHidden(true)
    }
}

extension MetricTile where Trend == EmptyView {
    init(name: String, systemImage: String, tint: Color, value: String?, unit: String, reference: String,
         size: DashboardTileSize = .small) {
        self.init(name: name, systemImage: systemImage, tint: tint, value: value, unit: unit, reference: reference,
                  size: size) { EmptyView() }
    }
}

extension MetricTile {
    /// Tile for a measurement kind with its token color, symbol and name.
    init(kind: SampleKind, value: String?, unit: String, reference: String, size: DashboardTileSize = .small,
         @ViewBuilder trend: () -> Trend) {
        let style = MetricStyle.of(kind)
        self.init(name: style.name, systemImage: style.systemImage, tint: style.color, value: value, unit: unit,
                  reference: reference, size: size, trend: trend)
    }
}

/// Minimal mini trend for tiles: a line through the points, last point marked. Gaps (nil) break the line,
/// they are never bridged. Team 03 may replace it with a Swift Charts version that keeps this look.
struct Sparkline: View {
    let values: [Double?]
    var tint: Color = DKColor.accent

    var body: some View {
        Canvas { context, size in
            let known = values.compactMap { $0 }
            guard values.count > 1, let low = known.min(), let high = known.max() else { return }
            let span = max(high - low, 0.0001)
            let step = size.width / CGFloat(values.count - 1)
            func point(_ index: Int, _ value: Double) -> CGPoint {
                CGPoint(x: CGFloat(index) * step,
                        y: size.height - 3 - CGFloat((value - low) / span) * (size.height - 6))
            }
            var path = Path()
            var drawing = false
            for (index, value) in values.enumerated() {
                guard let value else { drawing = false; continue }
                if drawing { path.addLine(to: point(index, value)) } else { path.move(to: point(index, value)) }
                drawing = true
            }
            context.stroke(path, with: .color(tint), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            if let lastIndex = values.lastIndex(where: { $0 != nil }), let last = values[lastIndex] {
                let p = point(lastIndex, last)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)), with: .color(tint))
            }
        }
        .accessibilityHidden(true)
    }
}
