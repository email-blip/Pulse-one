import Foundation

/// German display of a kind's canonical value: number text, unit and symbol. One place, so every
/// screen and every module shows "6,8 h", "8.412" and "58 bpm" the same way.
extension SampleKind {
    public var displayUnit: String {
        switch self {
        case .heartRate, .restingHeartRate: "bpm"
        case .heartRateVariability: "ms"
        case .oxygenSaturation, .deviceBattery: "%"
        case .skinTemperature, .bodyTemperature, .skinTemperatureDeviation: "°C"
        case .steps: "Schritte"
        case .activeEnergy, .basalEnergy: "kcal"
        case .distance: "km"
        case .elevationGain: "m"
        case .sleepDuration, .trainingDuration: "h"
        case .respiratoryRate: "/min"
        case .vo2Max: "ml/kg/min"
        case .bodyMass: "kg"
        case .height: "m"
        }
    }

    /// Converts the canonical value into the display unit (seconds → hours, meters → km).
    public func displayNumber(_ canonical: Double) -> Double {
        switch self {
        case .sleepDuration, .trainingDuration: canonical / 3600
        case .distance: canonical / 1000
        default: canonical
        }
    }

    public var fractionDigits: Int {
        switch self {
        case .sleepDuration, .trainingDuration, .distance, .skinTemperature, .bodyTemperature,
             .skinTemperatureDeviation, .respiratoryRate, .vo2Max, .bodyMass: 1
        case .height: 2
        default: 0
        }
    }

    public func display(_ canonical: Double, locale: Locale = Locale(identifier: "de_DE")) -> String {
        displayNumber(canonical).formatted(.number.precision(.fractionLength(fractionDigits)).locale(locale))
    }

    public var systemImage: String {
        switch self {
        case .heartRate: "heart.fill"
        case .restingHeartRate: "heart"
        case .heartRateVariability: "waveform.path.ecg"
        case .oxygenSaturation: "lungs"
        case .skinTemperature, .skinTemperatureDeviation, .bodyTemperature: "thermometer.medium"
        case .steps: "figure.walk"
        case .activeEnergy, .basalEnergy: "flame"
        case .distance: "point.topleft.down.to.point.bottomright.curvepath"
        case .sleepDuration: "bed.double"
        case .trainingDuration: "figure.run"
        case .elevationGain: "mountain.2"
        case .deviceBattery: "battery.75percent"
        case .respiratoryRate: "wind"
        case .vo2Max: "gauge.with.dots.needle.67percent"
        case .bodyMass: "scalemass"
        case .height: "ruler"
        }
    }

    /// What one daily value means, for "Wie berechnet?" lines.
    public var dailyMeaning: String {
        switch aggregation {
        case .point: "Tagesmittel"
        case .cumulative: "Tagessumme"
        case .interval: "Dauer, Beginn an diesem Tag"
        case .derived, .vendorScore: "Tageswert der Quelle"
        }
    }
}
