import Foundation

// "Jetzt tun" catalogue (BEGLEITER-KREATIVTEAM.md §2.4). Short morning steps with an evidence label.
// Wording: "kann helfen, wacher zu werden", never a promise or a treatment.

public enum QuickActionCatalog {
    // Stable ids (stored with briefings, used by the UI). Never rename.
    public static let waterID = "water"
    public static let daylightID = "daylight"
    public static let coldFaceID = "coldFace"
    public static let coldShowerID = "coldShower"
    public static let pushUpsID = "pushUps"
    public static let pullUpsID = "pullUps"
    public static let squatsID = "squats"
    public static let mobilityID = "mobility"
    public static let calmBreathingID = "calmBreathing"
    public static let activatingBreathingID = "activatingBreathing"
    public static let coffeeNowID = "coffeeNow"
    public static let coffeeDelayID = "coffeeDelay"
    public static let strongCoffeeID = "strongCoffee"
    public static let greenTeaID = "greenTea"
    public static let makeBedID = "makeBed"
    public static let activeWayID = "activeWay"
    public static let proteinBreakfastID = "proteinBreakfast"

    /// Steps that need muscular effort (only with `allowsStrengthTips`, never on short nights or unusual patterns).
    public static let strengthIDs: Set<String> = [pushUpsID, pullUpsID, squatsID]
    /// Cold exposure (never on short nights or unusual patterns).
    public static let coldIDs: Set<String> = [coldFaceID, coldShowerID]
    /// Caffeine options (only with `allowsCaffeineTips`).
    public static let caffeineIDs: Set<String> = [coffeeNowID, coffeeDelayID, strongCoffeeID, greenTeaID]

    public static let all: [QuickAction] = [
        QuickAction(id: waterID, title: "Glas Wasser",
                    detail: "300 bis 500 ml direkt nach dem Aufstehen, nach der Nacht ein einfacher Anfang.",
                    symbol: "drop", minutes: 1, label: .a),
        QuickAction(id: daylightID, title: "Tageslicht",
                    detail: "Fenster auf, Balkon oder kurz raus, 5 bis 10 Minuten. Licht am Morgen kann helfen, wacher zu werden.",
                    symbol: "sun.max", minutes: 5, label: .a),
        QuickAction(id: coldFaceID, title: "Kaltes Wasser ins Gesicht",
                    detail: "30 Sekunden kaltes Wasser ins Gesicht kann helfen, wacher zu werden.",
                    symbol: "drop.fill", minutes: 1, label: .b),
        QuickAction(id: coldShowerID, title: "Kalter Dusch-Abschluss",
                    detail: "Die letzten 30 bis 60 Sekunden der Dusche kalt. Nur, wenn es sich für dich gut anfühlt.",
                    symbol: "shower", minutes: 1, label: .b),
        QuickAction(id: pushUpsID, title: "Liegestütze",
                    detail: "5 bis 15 Stück, gern an der Wand oder auf den Knien. Bringt den Kreislauf in Schwung.",
                    symbol: "figure.strengthtraining.traditional", minutes: 2, label: .a),
        QuickAction(id: pullUpsID, title: "Klimmzüge oder Hängen",
                    detail: "1 bis 5 Klimmzüge oder 20 Sekunden locker hängen, wenn du eine Stange hast.",
                    symbol: "figure.strengthtraining.functional", minutes: 2, label: .a),
        QuickAction(id: squatsID, title: "Kniebeugen",
                    detail: "10 ruhige Kniebeugen oder Ausfallschritte als sanfte Aktivierung.",
                    symbol: "figure.cooldown", minutes: 2, label: .a),
        QuickAction(id: mobilityID, title: "Mobilität",
                    detail: "2 Minuten Hüfte, Brustwirbelsäule und Nacken locker bewegen.",
                    symbol: "figure.flexibility", minutes: 2, label: .a),
        QuickAction(id: calmBreathingID, title: "Ruhig atmen",
                    detail: "2 Minuten: 4 Sekunden ein, 6 Sekunden aus. Ein ruhiger Einstieg in den Tag.",
                    symbol: "lungs", minutes: 2, label: .b),
        QuickAction(id: activatingBreathingID, title: "Aktivierende Atmung",
                    detail: "30 Sekunden etwas schneller durch die Nase atmen. Bei Schwindel sofort aufhören.",
                    symbol: "wind", minutes: 1, label: .c),
        QuickAction(id: coffeeNowID, title: "Kaffee",
                    detail: "Dein gewohnter Kaffee passt jetzt gut, mit Abstand zur Schlafenszeit.",
                    symbol: "cup.and.saucer", minutes: 1, label: .a),
        QuickAction(id: coffeeDelayID, title: "Kaffee später",
                    detail: "Den ersten Kaffee 60 bis 90 Minuten nach dem Aufwachen trinken, als eigenes Experiment. Die Belege sind schwach.",
                    symbol: "cup.and.saucer", minutes: 1, label: .c),
        QuickAction(id: strongCoffeeID, title: "Starker Kaffee",
                    detail: "Nach einer kurzen Nacht ein starker Kaffee, wenn du magst. Am Nachmittag besser keinen mehr.",
                    symbol: "cup.and.saucer", minutes: 1, label: .b),
        QuickAction(id: greenTeaID, title: "Grüner Tee",
                    detail: "Grüner Tee statt Kaffee ist heute die sanftere Wahl.",
                    symbol: "leaf", minutes: 3, label: .b),
        QuickAction(id: makeBedID, title: "Bett machen und lüften",
                    detail: "Bett machen und das Fenster öffnen: ein leichter erster Erfolg am Morgen.",
                    symbol: "bed.double", minutes: 2, label: .b),
        QuickAction(id: activeWayID, title: "Bewegter Weg",
                    detail: "Treppe statt Aufzug oder 10 Minuten zu Fuß auf dem Weg.",
                    symbol: "figure.walk", minutes: 10, label: .a),
        QuickAction(id: proteinBreakfastID, title: "Frühstück mit Eiweiß",
                    detail: "Zum Beispiel Joghurt, Quark, Eier oder Hülsenfrüchte zum Frühstück.",
                    symbol: "fork.knife", minutes: 3, label: .b)
    ]

    public static func action(id: String) -> QuickAction? {
        all.first { $0.id == id }
    }

    /// Indoor variant of the daylight step while it is still dark outside.
    static let indoorLight = QuickAction(id: daylightID, title: "Helles Licht",
                                         detail: "Draußen ist es noch dunkel: mach drinnen helles Licht an, das kann helfen, wacher zu werden.",
                                         symbol: "lightbulb", minutes: 1, label: .b)

    /// Short phrase for running text ("Jetzt: ein Glas Wasser, Tageslicht und …").
    static func phrase(for action: QuickAction) -> String {
        switch action.id {
        case waterID: "ein Glas Wasser"
        case daylightID: action.title == indoorLight.title ? "helles Licht" : "fünf Minuten Tageslicht"
        case coldFaceID: "kaltes Wasser ins Gesicht"
        case coldShowerID: "ein kalter Dusch-Abschluss"
        case pushUpsID: "ein paar Liegestütze"
        case pullUpsID: "Klimmzüge oder kurz hängen"
        case squatsID: "zehn Kniebeugen"
        case mobilityID: "zwei Minuten Mobilität"
        case calmBreathingID: "zwei Minuten ruhig atmen"
        case activatingBreathingID: "30 Sekunden aktivierende Atmung"
        case coffeeNowID: "dein Kaffee"
        case coffeeDelayID: "Kaffee etwas später"
        case strongCoffeeID: "ein starker Kaffee, wenn du magst"
        case greenTeaID: "gern grüner Tee statt Kaffee"
        case makeBedID: "Bett machen und lüften"
        case activeWayID: "ein bewegter Weg"
        case proteinBreakfastID: "ein Frühstück mit Eiweiß"
        default: action.title
        }
    }
}

/// Picks exactly three steps for the morning. Deterministic: a fixed anchor per day type plus a
/// day-of-year rotation through the eligible rest, so the same three do not repeat on consecutive days.
public enum QuickActionPicker {
    public static func pick(dayType: CompanionDayType, night: NightSummary, weather: WeatherSnapshot?,
                            preferences: CompanionPreferences, now: Date, calendar: Calendar) -> [QuickAction] {
        let plan = Self.plan(for: dayType)
        let eligible: (String) -> Bool = { id in
            isEligible(id, dayType: dayType, night: night, weather: weather, preferences: preferences, now: now, calendar: calendar)
        }

        var chosen: [String] = []
        for id in plan.fixed where eligible(id) && !chosen.contains(id) && chosen.count < 3 {
            chosen.append(id)
        }

        let pool = plan.rotating.filter { eligible($0) && !chosen.contains($0) }
        if !pool.isEmpty {
            let dayOfYear = calendar.ordinality(of: .day, in: .year, for: now) ?? 1
            let offset = dayOfYear % pool.count
            let rotated = Array(pool[offset...]) + Array(pool[..<offset])
            for id in rotated where chosen.count < 3 {
                chosen.append(id)
            }
        }

        // Safety fill: effortless steps that are always possible.
        let fallback = [QuickActionCatalog.waterID, QuickActionCatalog.makeBedID, QuickActionCatalog.calmBreathingID,
                        QuickActionCatalog.mobilityID, QuickActionCatalog.daylightID]
        for id in fallback where chosen.count < 3 && !chosen.contains(id) {
            chosen.append(id)
        }

        let isDark = isDarkOutside(weather: weather, now: now)
        return chosen.prefix(3).compactMap { (id: String) -> QuickAction? in
            if id == QuickActionCatalog.daylightID && isDark { return QuickActionCatalog.indoorLight }
            return QuickActionCatalog.action(id: id)
        }
    }

    // MARK: - Rules

    private struct Plan {
        let fixed: [String]
        let rotating: [String]
    }

    private static func plan(for dayType: CompanionDayType) -> Plan {
        typealias C = QuickActionCatalog
        switch dayType {
        case .recovered:
            return Plan(fixed: [C.waterID],
                        rotating: [C.coldFaceID, C.pushUpsID, C.daylightID, C.pullUpsID, C.activatingBreathingID,
                                   C.coldShowerID, C.proteinBreakfastID])
        case .normal:
            return Plan(fixed: [C.waterID],
                        rotating: [C.daylightID, C.mobilityID, C.pushUpsID, C.coffeeNowID, C.squatsID,
                                   C.proteinBreakfastID, C.coldFaceID, C.makeBedID, C.activeWayID])
        case .shortNight:
            return Plan(fixed: [C.waterID, C.daylightID],
                        rotating: [C.strongCoffeeID, C.calmBreathingID, C.mobilityID, C.coffeeNowID, C.makeBedID])
        case .unusualPattern:
            return Plan(fixed: [C.waterID, C.calmBreathingID],
                        rotating: [C.greenTeaID, C.daylightID, C.mobilityID, C.makeBedID])
        case .notEnoughData:
            return Plan(fixed: [C.waterID],
                        rotating: [C.daylightID, C.mobilityID, C.makeBedID, C.calmBreathingID, C.coffeeNowID])
        }
    }

    private static func isEligible(_ id: String, dayType: CompanionDayType, night: NightSummary, weather: WeatherSnapshot?,
                                   preferences: CompanionPreferences, now: Date, calendar: Calendar) -> Bool {
        typealias C = QuickActionCatalog
        // The delayed-coffee experiment is opt-in only and never picked automatically.
        if id == C.coffeeDelayID { return false }
        if C.strengthIDs.contains(id) && !preferences.allowsStrengthTips { return false }
        if C.caffeineIDs.contains(id) && !preferences.allowsCaffeineTips { return false }
        let gentleDay = dayType == .shortNight || dayType == .unusualPattern
        if gentleDay && (C.strengthIDs.contains(id) || C.coldIDs.contains(id) || id == C.activatingBreathingID) {
            return false
        }
        if dayType == .unusualPattern && id == C.strongCoffeeID { return false }
        // Coffee in the morning only, well before bedtime.
        if C.caffeineIDs.contains(id) && id != C.greenTeaID && calendar.component(.hour, from: now) >= 14 { return false }
        // Cold steps not when the night ended clearly above the personal resting band.
        if C.coldIDs.contains(id) && night.restingHeartRatePosition == .above { return false }
        // Walking route not in a storm.
        if id == C.activeWayID, let wind = currentHour(weather: weather, now: now)?.windSpeed, wind >= 60 { return false }
        return true
    }

    private static func currentHour(weather: WeatherSnapshot?, now: Date) -> WeatherHour? {
        guard let hours = weather?.hours, !hours.isEmpty else { return nil }
        return hours.min { abs($0.time.timeIntervalSince(now)) < abs($1.time.timeIntervalSince(now)) }
    }

    private static func isDarkOutside(weather: WeatherSnapshot?, now: Date) -> Bool {
        guard let sunrise = weather?.sunrise else { return false }
        return now < sunrise
    }
}
