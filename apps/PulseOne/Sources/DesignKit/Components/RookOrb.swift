import PulseCore
import SwiftUI

/// The coach's sign: a ring with an inner orb, drawn natively. It reads nothing but `RookPresence`,
/// so a Rive file can replace the drawing later without touching any screen (Neubau plan §10).
///
/// Motion per state (rhythms in `OrbMotion`):
/// - idle: still, soft glow
/// - listening: slow breath of the outer ring (cyan)
/// - thinking: a violet arc turns around the ring
/// - speaking: the inner orb pulses calmly
/// - confirming: the ring closes once and fills (one shot)
/// - alerting: coral ring, inner orb bright, no movement (attention without alarm)
/// Reduce Motion or frozen screenshots: every state is drawn still, distinguishable by color and shape.
struct RookOrb: View {
    var presence: RookPresence
    var size: CGFloat = 32

    @Environment(\.reduceMotionEffective) private var reduceMotion
    @Environment(\.freezeAnimations) private var frozen
    @Environment(\.scenePhase) private var scenePhase

    private var loops: Bool {
        !reduceMotion && !frozen && scenePhase == .active
            && (presence == .listening || presence == .thinking || presence == .speaking)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !loops)) { context in
            let t = loops ? context.date.timeIntervalSinceReferenceDate : 0
            Canvas { canvas, area in
                draw(in: &canvas, size: area, time: t)
            }
        }
        .frame(width: size, height: size)
        .animation(frozen ? nil : OrbMotion.stateChange, value: presence)
        .accessibilityElement()
        .accessibilityLabel(Self.label(for: presence))
        .accessibilityIdentifier("rook.orb.\(presence.rawValue)")
    }

    static func label(for presence: RookPresence) -> String {
        switch presence {
        case .idle: "ROOK"
        case .listening: "ROOK hört zu"
        case .thinking: "ROOK denkt nach"
        case .speaking: "ROOK spricht"
        case .confirming: "ROOK bestätigt"
        case .alerting: "ROOK hat einen Hinweis"
        }
    }

    private var tint: Color {
        switch presence {
        case .idle, .listening, .speaking, .confirming: DKColor.bioCyan
        case .thinking: DKColor.neuralViolet
        case .alerting: DKColor.pulseCoral
        }
    }

    private func draw(in canvas: inout GraphicsContext, size: CGSize, time: Double) {
        let side = min(size.width, size.height)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let line = max(1.5, side * 0.07)
        var outer = side / 2 - line

        if presence == .listening {
            outer *= 0.92 + 0.08 * (0.5 + 0.5 * sin(time * 2 * .pi / OrbMotion.listeningPeriod))
        }

        // Soft glow behind the ring.
        let glow = Path(ellipseIn: CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2))
        canvas.fill(glow, with: .radialGradient(Gradient(colors: [tint.opacity(0.28), tint.opacity(0)]),
                                                center: center, startRadius: 0, endRadius: outer * 1.1))

        // Outer ring: full circle, or the turning arc while thinking.
        let ringRect = CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2)
        if presence == .thinking {
            canvas.stroke(Path(ellipseIn: ringRect), with: .color(tint.opacity(0.3)), lineWidth: line)
            let start = time * 2 * .pi / OrbMotion.thinkingPeriod
            var arc = Path()
            arc.addArc(center: center, radius: outer, startAngle: .radians(start),
                       endAngle: .radians(start + 110 * .pi / 180), clockwise: false)
            canvas.stroke(arc, with: .color(tint), style: StrokeStyle(lineWidth: line, lineCap: .round))
        } else {
            canvas.stroke(Path(ellipseIn: ringRect), with: .color(tint), lineWidth: line)
        }

        // Inner orb, slightly off-center like a planet in its orbit (the mockup's sign).
        var inner = outer * (presence == .confirming ? 0.62 : 0.42)
        if presence == .speaking {
            inner *= 0.85 + 0.25 * (0.5 + 0.5 * sin(time * 2 * .pi / OrbMotion.speakingPeriod))
        }
        let offset = presence == .confirming ? 0 : outer * 0.14
        let innerCenter = CGPoint(x: center.x - offset, y: center.y + offset * 0.4)
        let innerRect = CGRect(x: innerCenter.x - inner, y: innerCenter.y - inner, width: inner * 2, height: inner * 2)
        switch presence {
        case .confirming, .alerting:
            canvas.fill(Path(ellipseIn: innerRect), with: .color(tint))
        default:
            canvas.stroke(Path(ellipseIn: innerRect), with: .color(tint), lineWidth: line * 0.85)
        }
    }
}
