import Foundation

// Day rhythm nudges: light, meals, movement, wind-down and bedtime around the wake time. Suggestions,
// not orders. Only future times, never in the quiet hours, at most `maxNudgesPerDay` per day by priority.

public enum DayRhythmPlanner {
    /// Priority when the daily cap is reached (first = most important).
    public static let priority: [NudgeKind] = [
        .bedtime, .windDown, .sportWindow, .nap, .caffeineCutoff, .lunch, .movement, .daylight, .dinner, .breakfast, .hydration
    ]

    public static func plan(wake: Date, dayType: CompanionDayType, night: NightSummary,
                            weather: BodyWeatherReport?, preferences: CompanionPreferences,
                            now: Date, calendar: Calendar) -> [CompanionNudge] {
        let day = calendar.startOfDay(for: wake)
        let stamp = dateStamp(day, calendar: calendar)
        func at(_ hour: Int, _ minute: Int) -> Date? {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
        }
        func minutes(_ value: Double, after date: Date) -> Date { date.addingTimeInterval(value * 60) }

        var sleepNeed = min(max(preferences.sleepNeedHours, 4), 12)
        if dayType == .shortNight || dayType == .unusualPattern { sleepNeed += 0.5 }
        let bedtime = wake.addingTimeInterval((24 - sleepNeed) * 3_600)

        var drafts: [(kind: NudgeKind, time: Date, title: String, body: String)] = []
        func add(_ kind: NudgeKind, _ time: Date?, _ title: String, _ body: String) {
            if let time { drafts.append((kind, time, title, body)) }
        }

        add(.daylight, minutes(20, after: wake), "Tageslicht",
            "Wenn es passt: 10 Minuten nach draußen oder ans Fenster.")
        add(.breakfast, minutes(45, after: wake), "Frühstück",
            "Wenn du magst, jetzt in Ruhe frühstücken.")
        if preferences.allowsCaffeineTips {
            add(.caffeineCutoff, bedtime.addingTimeInterval(-8 * 3_600), "Letzter Kaffee",
                "Ab jetzt lieber koffeinfrei, das kann den Abend ruhiger machen.")
        }
        if let lunchFixed = at(12, 30) {
            add(.lunch, max(lunchFixed, wake.addingTimeInterval(5 * 3_600)), "Mittagspause",
                "Zeit für eine Pause mit Mittagessen.")
        }
        add(.movement, at(15, 0), "Bewegungspause", "Kurz aufstehen und 5 Minuten gehen.")

        switch dayType {
        case .recovered, .normal, .notEnoughData:
            if let window = weather?.bestOutdoorWindow,
               (10...19).contains(calendar.component(.hour, from: window.start)),
               calendar.isDate(window.start, inSameDayAs: day) {
                add(.sportWindow, window.start, "Bewegungsfenster",
                    "Draußen passt das Wetter jetzt gut, falls du dich heute bewegen möchtest.")
            } else {
                add(.sportWindow, at(17, 30), "Bewegungsfenster",
                    "Ein guter Zeitpunkt für Training oder Bewegung, falls du heute magst.")
            }
        case .shortNight:
            add(.sportWindow, at(17, 30), "Leichte Bewegung",
                "Nach der kurzen Nacht passt eher leichte Bewegung, zum Beispiel ein Spaziergang.")
        case .unusualPattern:
            add(.sportWindow, at(17, 30), "Locker bleiben",
                "Deine Werte weichen heute vom Üblichen ab: heute nur locker oder Pause.")
        }

        if dayType == .shortNight, let earliest = at(13, 0), let latest = at(15, 0) {
            let napTime = min(max(wake.addingTimeInterval(7 * 3_600), earliest), latest)
            add(.nap, napTime, "Kurze Pause", "Wenn es geht: 10–20 Minuten hinlegen, Wecker stellen.")
        }
        add(.dinner, bedtime.addingTimeInterval(-3 * 3_600), "Abendessen",
            "Ein Abendessen jetzt lässt bis zum Schlafen etwas Zeit.")
        add(.windDown, minutes(-45, after: bedtime), "Runterfahren",
            "Licht dimmen, Bildschirm weglegen und den Tag ausklingen lassen.")
        add(.bedtime, bedtime, "Schlafenszeit",
            "Für \(hoursText(sleepNeed)) Stunden Schlaf wäre jetzt ein guter Zeitpunkt.")
        if let report = weather, report.bodyNotes.contains(BodyWeather.heatNote) {
            add(.hydration, at(10, 30), "Trinken", "Bei der Hitze zwischendurch ein Glas Wasser.")
        }

        // Wind-down and bedtime are the point of the evening, so quiet hours do not hide them.
        let allowed = drafts.filter { draft in
            draft.kind == .bedtime || draft.kind == .windDown
                || !isQuiet(draft.time, preferences: preferences, calendar: calendar)
        }
        // The cap applies to the whole day, past nudges included, so re-planning later in the day never adds
        // more. Only the still-future ones of that fixed daily set are returned.
        let rank: (NudgeKind) -> Int = { kind in Self.priority.firstIndex(of: kind) ?? Self.priority.count }
        let cap = max(preferences.maxNudgesPerDay, 0)
        let kept = allowed.sorted { rank($0.kind) < rank($1.kind) }.prefix(cap).filter { $0.time > now }
        return kept
            .sorted { $0.time == $1.time ? rank($0.kind) < rank($1.kind) : $0.time < $1.time }
            .map { CompanionNudge(id: "companion.\($0.kind.rawValue).\(stamp)", kind: $0.kind, time: $0.time,
                                  title: $0.title, body: $0.body) }
    }

    /// Quiet hours [start, end) in local hours; wrap past midnight when start > end; none when equal.
    static func isQuiet(_ time: Date, preferences: CompanionPreferences, calendar: Calendar) -> Bool {
        let hour = calendar.component(.hour, from: time)
        let start = preferences.quietStartHour
        let end = preferences.quietEndHour
        if start == end { return false }
        if start < end { return hour >= start && hour < end }
        return hour >= start || hour < end
    }

    /// "yyyyMMdd" of the day in the calendar's time zone.
    static func dateStamp(_ day: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04ld%02ld%02ld", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func hoursText(_ hours: Double) -> String {
        let rounded = (hours * 2).rounded() / 2
        if rounded == rounded.rounded() { return "\(Int(rounded))" }
        return String(format: "%.1f", rounded).replacingOccurrences(of: ".", with: ",")
    }
}
