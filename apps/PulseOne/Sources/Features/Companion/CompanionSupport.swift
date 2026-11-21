import Foundation
import PulseCore
import SwiftUI

/// Small view helpers shared by the companion ("Begleiter") screens. Every place where the UI depends on a
/// detail of the services layer (T4) is kept here, so a contract change is fixed in one file.
enum CompanionUI {
    /// Scenario names of the UI tests.
    static let scenario = "companion"
    static let wakeScenario = "companionWake"

    /// Clock of the companion views: `TestScenario.fixedTime` in test scenarios (like TODAY), else now.
    static var now: Date { LaunchOptions.current.usesTestScenario ? TestScenario.fixedTime : Date.now }

    /// Maps the core statement type 1:1 onto the design system badge.
    static func statementKind(_ statement: CompanionStatement) -> StatementKind {
        switch statement {
        case .measured: .measured
        case .computed: .computed
        case .observed: .observed
        case .interpretation: .interpretation
        case .suggestion: .suggestion
        case .medicalCheck: .medicalCheck
        }
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func clock(hour: Int, minute: Int) -> String {
        let h = min(max(hour, 0), 23)
        let m = min(max(minute, 0), 59)
        return (h < 10 ? "0" : "") + "\(h):" + (m < 10 ? "0" : "") + "\(m)"
    }

    /// "7 h 30 min" for a duration in hours.
    static func hoursText(_ hours: Double) -> String {
        let totalMinutes = Int((hours * 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    static func percentText(_ share: Double) -> String {
        "\(Int((min(max(share, 0), 1) * 100).rounded())) %"
    }

    /// First name for greetings: own setting first, else the profile's display name.
    static func firstName(preferences: CompanionPreferences, profile: UserProfile) -> String {
        let own = preferences.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        return own.isEmpty ? profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines) : own
    }

    /// "München, Bayern" from a geocoding result.
    static func placeTitle(_ place: GeoPlace) -> String {
        let extras: [String?] = [place.admin1, place.country]
        let parts = [place.name] + extras.compactMap { $0 }.filter { !$0.isEmpty }
        return parts.joined(separator: ", ")
    }
}

/// Weekdays of the alarm, using `Calendar` weekday numbers (1 = Sunday … 7 = Saturday), listed Monday first.
struct CompanionWeekday: Identifiable, Sendable {
    let number: Int
    let short: String
    let name: String
    var id: Int { number }

    static let all: [CompanionWeekday] = [
        CompanionWeekday(number: 2, short: "Mo", name: "Montag"),
        CompanionWeekday(number: 3, short: "Di", name: "Dienstag"),
        CompanionWeekday(number: 4, short: "Mi", name: "Mittwoch"),
        CompanionWeekday(number: 5, short: "Do", name: "Donnerstag"),
        CompanionWeekday(number: 6, short: "Fr", name: "Freitag"),
        CompanionWeekday(number: 7, short: "Sa", name: "Samstag"),
        CompanionWeekday(number: 1, short: "So", name: "Sonntag")
    ]

    /// Weekday numbers in display order (Monday first).
    static func ordered(_ days: Set<Int>) -> [Int] {
        all.map(\.number).filter { days.contains($0) }
    }

    static func summary(_ days: Set<Int>) -> String {
        if days.count == 7 { return "täglich" }
        if days == [2, 3, 4, 5, 6] { return "Mo–Fr" }
        if days == [1, 7] { return "Sa und So" }
        if days.isEmpty { return "einmalig, zur nächsten passenden Zeit" }
        return all.filter { days.contains($0.number) }.map(\.short).joined(separator: " · ")
    }
}
