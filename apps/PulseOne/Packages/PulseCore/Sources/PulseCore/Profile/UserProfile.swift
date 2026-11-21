import Foundation

/// The owner's own profile, kept on the device only. Every field is optional: the app works
/// without any of them, and nothing is guessed.
public struct UserProfile: Codable, Equatable, Sendable {
    public enum Sex: String, Codable, CaseIterable, Sendable {
        case female, male, diverse, undisclosed

        public var title: String {
            switch self {
            case .female: "weiblich"
            case .male: "männlich"
            case .diverse: "divers"
            case .undisclosed: "keine Angabe"
            }
        }
    }

    public var displayName: String
    public var birthYear: Int?
    public var sex: Sex?
    public var heightCm: Double?
    public var weightKg: Double?

    public init(displayName: String = "", birthYear: Int? = nil, sex: Sex? = nil,
                heightCm: Double? = nil, weightKg: Double? = nil) {
        self.displayName = displayName
        self.birthYear = birthYear
        self.sex = sex
        self.heightCm = heightCm
        self.weightKg = weightKg
    }

    public static let birthYearRange = 1900...2026
    public static let heightRange = 50.0...250.0
    public static let weightRange = 20.0...400.0

    /// Drops values outside plausible ranges instead of storing them.
    public func sanitized() -> UserProfile {
        var copy = self
        copy.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let year = birthYear, !Self.birthYearRange.contains(year) { copy.birthYear = nil }
        if let height = heightCm, !Self.heightRange.contains(height) { copy.heightCm = nil }
        if let weight = weightKg, !Self.weightRange.contains(weight) { copy.weightKg = nil }
        return copy
    }

    /// Age in full years at `date`, only when the birth year is known (±1 year, the birthday is not stored).
    public func approximateAge(at date: Date, calendar: Calendar) -> Int? {
        guard let birthYear else { return nil }
        return calendar.component(.year, from: date) - birthYear
    }

    /// Greeting for the top of TODAY.
    public func greeting(at date: Date, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        let base = switch hour {
        case 5..<11: "Guten Morgen"
        case 11..<17: "Hallo"
        case 17..<23: "Guten Abend"
        default: "Hallo"
        }
        return displayName.isEmpty ? base : "\(base), \(displayName)"
    }
}
