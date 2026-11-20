import SwiftUI

/// The living centre of the connect screen: a glowing orb whose rings expand with the
/// live heart rate, or breathe slowly while no live value exists. Canvas + TimelineView,
/// frozen under Reduce Motion and in screenshot runs.
struct PulseOrb: View {
    let bpm: Int?
    let isConnected: Bool
    @Environment(\.reduceMotionEffective) private var reduceMotion
    @Environment(\.freezeAnimations) private var freeze
    @ScaledMetric(relativeTo: .largeTitle) private var valueSize: CGFloat = 56
    @ScaledMetric(relativeTo: .body) private var orbHeight: CGFloat = 260

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion || freeze)) { context in
            let time = (reduceMotion || freeze) ? 0.35 : context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                draw(in: &canvas, size: size, time: time)
            }
        }
        // Grows with Dynamic Type so the readout always fits inside the core.
        .frame(height: min(orbHeight, 420))
        .overlay { readout }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Puls")
        .accessibilityValue(bpm.map { "\($0) Schläge pro Minute, live vom Ring" } ?? "kein Live-Wert")
        .accessibilityIdentifier("orb")
    }

    private var readout: some View {
        VStack(spacing: 2) {
            Text(bpm.map { "\($0)" } ?? "–")
                .font(Typography.vital(size: valueSize))
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(bpm == nil ? (isConnected ? "bereit" : "kein Ring") : "bpm live")
                .font(Typography.label)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Palette.inkMuted)
        }
        // The orb element itself carries label and value; the visual readout is not read twice.
        .frame(maxWidth: min(orbHeight, 420) * 0.48)
        .accessibilityHidden(true)
    }

    private func draw(in canvas: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * 0.30
        let live = bpm != nil
        let period = bpm.map { 60.0 / Double(max($0, 30)) } ?? 4.0
        let phase = (time.truncatingRemainder(dividingBy: period)) / period
        let accent = live ? Palette.pulseCoral : Palette.bioCyan

        // Soft glow behind the core.
        let glowRect = CGRect(x: center.x - radius * 1.8, y: center.y - radius * 1.8, width: radius * 3.6, height: radius * 3.6)
        canvas.fill(Path(ellipseIn: glowRect), with: .radialGradient(
            Gradient(colors: [Palette.neuralViolet.opacity(0.35), Palette.bioCyan.opacity(0.10), .clear]),
            center: center, startRadius: 0, endRadius: radius * 1.8))

        // Three expanding rings, staggered across one beat.
        for index in 0..<3 {
            let p = (phase + Double(index) / 3).truncatingRemainder(dividingBy: 1)
            let r = radius * (1 + 0.7 * p)
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            canvas.stroke(Path(ellipseIn: rect), with: .color(accent.opacity(0.55 * (1 - p))), lineWidth: 2)
        }

        // Core: a beat-shaped scale (quick rise, slow fall) when live, slow breathing otherwise.
        let beat = live ? pow(max(0, 1 - phase * 3), 2) : 0.5 + 0.5 * sin(phase * 2 * .pi)
        let core = radius * (0.92 + 0.08 * beat)
        let coreRect = CGRect(x: center.x - core, y: center.y - core, width: core * 2, height: core * 2)
        canvas.fill(Path(ellipseIn: coreRect), with: .radialGradient(
            Gradient(colors: [Palette.surfaceRaised, Palette.obsidian]),
            center: center, startRadius: 0, endRadius: core))
        canvas.stroke(Path(ellipseIn: coreRect), with: .linearGradient(
            Gradient(colors: [accent, Palette.neuralViolet]),
            startPoint: CGPoint(x: coreRect.minX, y: coreRect.minY),
            endPoint: CGPoint(x: coreRect.maxX, y: coreRect.maxY)), lineWidth: 3)
    }
}
