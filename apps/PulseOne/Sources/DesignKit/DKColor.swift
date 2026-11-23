import PulseCore
import SwiftUI

/// PULSE ONE color tokens (Neubau plan §4). Views never use raw colors; everything here is checked for
/// WCAG AA by `scripts/assets/check-contrast.py` (text ≥ 4.5:1, graphics ≥ 3:1 on every surface).
///
/// Dark only for now: the five brand colors are fixed, the rest is derived from Obsidian and Ice White.
enum DKColor {
    // MARK: Brand (fixed)
    static let obsidian     = Color(hex: 0x070D19)
    static let bioCyan      = Color(hex: 0x15D9F3)
    static let neuralViolet = Color(hex: 0x9B70FF)
    static let pulseCoral   = Color(hex: 0xFF644F)
    static let iceWhite     = Color(hex: 0xE6F4FA)

    // MARK: Surfaces, from back to front
    /// Page background.
    static let background   = obsidian
    /// Cards and tiles.
    static let surface      = Color(hex: 0x0F1A2C)
    /// Buttons and controls on a card.
    static let surfaceRaised = Color(hex: 0x16243A)
    /// Pressed or selected controls.
    static let surfaceSelected = Color(hex: 0x1C2E4B)

    // MARK: Lines (decoration only; meaning never depends on them)
    static let hairline     = Color(hex: 0x23344F)
    static let lineStrong   = Color(hex: 0x3A5277)

    // MARK: Text levels (all ≥ 5:1 on every surface)
    // Surfaces, hairline, secondary text and mesh keep the exact Build-17 values: the legacy `Palette` maps onto
    // them, and Apple's pixel-based contrast audit flagged small captions on old screens when they shifted (run 166).
    static let textPrimary   = iceWhite
    static let textSecondary = Color(hex: 0xBACCDA)
    /// Captions such as "NACHT · 07:00".
    static let textTertiary  = Color(hex: 0x8AA3B8)
    /// Text on a Bio Cyan fill (primary button).
    static let onAccent      = obsidian

    // MARK: Roles
    static let accent  = bioCyan
    static let coach   = neuralViolet
    /// Warnings and "abklären lassen". Never the only signal: always with symbol and words.
    static let alert   = pulseCoral

    /// Page background with the soft cyan/violet glow behind the coach header (3×3 mesh, row by row).
    static let backgroundMesh: [Color] = [
        0x070D19, 0x0A1426, 0x070D19,
        0x0B1630, 0x14204A, 0x0E1430,
        0x070D19, 0x0A1224, 0x070D19
    ].map(Color.init(hex:))
}

// MARK: - Measurement kinds

/// Color, symbol and short name per measurement kind. Color is never the only meaning: tiles and
/// timeline tracks always show the symbol and the name as well.
struct MetricStyle: Equatable, Sendable {
    let color: Color
    let systemImage: String
    /// Short German name for tiles and track labels.
    let name: String

    static func of(_ kind: SampleKind) -> MetricStyle {
        switch kind {
        case .heartRate: MetricStyle(color: DKColor.pulseCoral, systemImage: "heart", name: "Puls")
        case .restingHeartRate: MetricStyle(color: Color(hex: 0xFF8FA3), systemImage: "heart.circle", name: "Ruhepuls")
        case .heartRateVariability: MetricStyle(color: DKColor.neuralViolet, systemImage: "waveform.path.ecg", name: "HRV")
        case .ringHRV: MetricStyle(color: DKColor.neuralViolet, systemImage: "waveform.path.ecg", name: "HRV")
        case .ringStress: MetricStyle(color: Color(hex: 0xFFB547), systemImage: "bolt.heart", name: "Anspannung")
        case .oxygenSaturation: MetricStyle(color: DKColor.bioCyan, systemImage: "lungs", name: "Sauerstoff")
        case .skinTemperature, .skinTemperatureDeviation, .bodyTemperature:
            MetricStyle(color: Color(hex: 0x6FC8FF), systemImage: "thermometer.medium", name: "Temperatur")
        case .steps: MetricStyle(color: Color(hex: 0x4FE0A6), systemImage: "figure.walk", name: "Schritte")
        case .activeEnergy, .basalEnergy: MetricStyle(color: Color(hex: 0xFF9F45), systemImage: "flame", name: "Energie")
        case .distance: MetricStyle(color: Color(hex: 0x4FE0A6), systemImage: "point.topleft.down.to.point.bottomright.curvepath", name: "Strecke")
        case .elevationGain: MetricStyle(color: Color(hex: 0x4FE0A6), systemImage: "mountain.2", name: "Höhenmeter")
        case .sleepDuration: MetricStyle(color: Color(hex: 0x8C9BFF), systemImage: "moon.stars", name: "Schlaf")
        case .trainingDuration: MetricStyle(color: Color(hex: 0xFF9F45), systemImage: "figure.run", name: "Training")
        case .respiratoryRate: MetricStyle(color: Color(hex: 0x3FD6C2), systemImage: "wind", name: "Atmung")
        case .vo2Max: MetricStyle(color: Color(hex: 0x3FD6C2), systemImage: "gauge.with.dots.needle.67percent", name: "VO₂max")
        case .deviceBattery: MetricStyle(color: DKColor.textSecondary, systemImage: "battery.75percent", name: "Ring-Akku")
        case .bodyMass: MetricStyle(color: DKColor.textSecondary, systemImage: "scalemass", name: "Gewicht")
        case .height: MetricStyle(color: DKColor.textSecondary, systemImage: "ruler", name: "Größe")
        }
    }
}

// MARK: - Sleep phases

/// How a sleep phase is drawn. Phases differ by color, by height in the hypnogram (`level`) and by fill
/// pattern, so they stay distinguishable without color (Neubau plan: color is never the only meaning).
struct SleepPhaseStyle: Equatable, Sendable {
    enum Pattern: Equatable, Sendable {
        /// Solid fill.
        case solid
        /// Diagonal stripes.
        case striped
        /// Dots.
        case dotted
        /// Outline only, dashed: the ring sent a code we do not know.
        case dashedOutline
    }

    let color: Color
    let pattern: Pattern
    let name: String
    /// Row in the hypnogram, 0 = top (awake) … 3 = bottom (deep). Unknown sits on its own row below.
    let level: Int

    static func of(_ phase: SleepPhase) -> SleepPhaseStyle {
        switch phase {
        case .awake: SleepPhaseStyle(color: Color(hex: 0xFFB37A), pattern: .striped, name: "Wach", level: 0)
        case .rem: SleepPhaseStyle(color: DKColor.bioCyan, pattern: .dotted, name: "REM", level: 1)
        case .light: SleepPhaseStyle(color: Color(hex: 0x6F8CFF), pattern: .solid, name: "Leicht", level: 2)
        case .deep: SleepPhaseStyle(color: DKColor.neuralViolet, pattern: .solid, name: "Tief", level: 3)
        case .unknown: SleepPhaseStyle(color: Color(hex: 0x7D8FA3), pattern: .dashedOutline, name: "Unbekannt", level: 4)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
