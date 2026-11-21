import Foundation

// Clothing advice and body-related weather notes (I6 + P2). Descriptive suggestions only: weather can be
// felt by some people, nothing here is a diagnosis or a forecast about the person's health.

public enum ClothingAdvisor {
    /// Advice for the hours whose start lies in `from…to`.
    /// Base layer from the coldest felt temperature; rain, wind, UV, heat and a wide spread add items.
    public static func advise(_ weather: WeatherSnapshot, from: Date, to: Date, calendar: Calendar) -> ClothingAdvice {
        let hours = weather.hours.filter { $0.time >= from && $0.time <= to }.sorted { $0.time < $1.time }
        guard let coldest = hours.map(\.apparentTemperature).min(),
              let warmest = hours.map(\.apparentTemperature).max() else {
            return ClothingAdvice(items: [], sentence: "Für diesen Zeitraum liegen keine Wetterdaten vor.")
        }
        let maxRain = hours.compactMap(\.precipitationProbability).max() ?? 0
        let maxWind = hours.compactMap(\.windSpeed).max() ?? 0
        let maxUV = hours.compactMap(\.uvIndex).max() ?? 0

        let wear = baseLayer(for: coldest).filter { $0 != "Wasser mitnehmen" }
        var items = wear
        if warmest > 26 { items.append("Wasser mitnehmen") }

        var sentence = "Zieh heute " + joined(wear.map(phrase)) + " an"
        if maxRain >= 50 {
            items.append("Regenjacke oder Schirm")
            if let first = hours.first(where: { ($0.precipitationProbability ?? 0) >= 50 }),
               let start = hours.first, first.time > start.time {
                sentence += ", ab \(calendar.component(.hour, from: first.time)) Uhr Regen wahrscheinlich: Schirm mitnehmen."
            } else {
                sentence += ", Regen wahrscheinlich: Schirm mitnehmen."
            }
        } else if maxRain >= 30 {
            items.append("Schirm zur Sicherheit")
            sentence += ", Regen möglich: Schirm zur Sicherheit."
        } else {
            sentence += "."
        }
        if maxWind >= 30 {
            items.append("winddichte Schicht")
            sentence += " Windig: eine winddichte Schicht hilft."
        }
        if maxUV >= 6 {
            items.append("Sonnenschutz")
            sentence += " Hoher UV-Index: an Sonnenschutz denken."
        }
        if warmest > 26 { sentence += " Wasser mitnehmen." }
        if warmest - coldest >= 8 {
            items.append("Zwiebelprinzip: morgens kühl, später wärmer")
            sentence += " Zwiebelprinzip: morgens kühl, später wärmer."
        }
        return ClothingAdvice(items: items, sentence: sentence)
    }

    /// Items for the felt temperature (°C).
    static func baseLayer(for apparent: Double) -> [String] {
        if apparent <= 0 { return ["Wintermantel", "Mütze", "Handschuhe"] }
        if apparent < 8 { return ["warme Jacke", "Pullover"] }
        if apparent < 14 { return ["leichte Jacke", "Pullover"] }
        if apparent < 20 { return ["Langarm oder Pulli zum Überziehen"] }
        if apparent <= 26 { return ["T-Shirt"] }
        return ["luftige Kleidung", "Wasser mitnehmen"]
    }

    /// Accusative phrase with article for the sentence.
    static func phrase(_ item: String) -> String {
        switch item {
        case "Wintermantel": "einen Wintermantel"
        case "Mütze": "eine Mütze"
        case "warme Jacke": "eine warme Jacke"
        case "leichte Jacke": "eine leichte Jacke"
        case "Pullover": "einen Pullover"
        case "Langarm oder Pulli zum Überziehen": "etwas Langärmeliges oder einen Pulli zum Überziehen"
        case "T-Shirt": "ein T-Shirt"
        default: item
        }
    }

    /// "a", "a und b", "a, b und c".
    static func joined(_ parts: [String]) -> String {
        guard let last = parts.last else { return "" }
        let head = parts.dropLast()
        return head.isEmpty ? last : head.joined(separator: ", ") + " und " + last
    }
}

public enum BodyWeather {
    public static let pressureDropNote = "Luftdruck fällt deutlich. Manche Menschen spüren das, z. B. als Kopfdruck oder Müdigkeit."
    public static let heatNote = "Hitze: mehr trinken, Belastung in die kühleren Stunden."
    public static let humidNote = "Schwül: Nächte sind dann oft unruhiger."
    public static let airQualityNote = "Luftqualität mäßig: intensive Belastung draußen eher meiden."

    /// Weather line, clothing, body notes and the best outdoor window for today (local 06–22).
    /// Findings of the night researcher whose cause starts with "weather_" are added as extra notes.
    public static func report(_ weather: WeatherSnapshot, now: Date, calendar: Calendar,
                              findings: [ResearchFinding]) -> BodyWeatherReport {
        let today = calendar.startOfDay(for: now)
        let dayStart = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: today) ?? today
        let dayEnd = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: today) ?? today
        let hours = weather.hours.filter { $0.time >= dayStart && $0.time <= dayEnd }.sorted { $0.time < $1.time }

        let clothing = ClothingAdvisor.advise(weather, from: dayStart, to: dayEnd, calendar: calendar)
        return BodyWeatherReport(weatherLine: weatherLine(hours, now: now, calendar: calendar),
                                 clothing: clothing,
                                 bodyNotes: notes(weather, todayHours: hours, now: now, findings: findings),
                                 bestOutdoorWindow: bestOutdoorWindow(weather, now: now, calendar: calendar))
    }

    static func weatherLine(_ hours: [WeatherHour], now: Date, calendar: Calendar) -> String {
        guard let low = hours.map(\.temperature).min(), let high = hours.map(\.temperature).max() else {
            return "Für heute liegen keine Wetterdaten vor."
        }
        let lowText = degrees(low)
        let highText = degrees(high)
        var line = lowText == highText ? "Heute um \(lowText) Grad" : "Heute \(lowText) bis \(highText) Grad"
        let currentHourStart = now.addingTimeInterval(-3_600)
        if let rain = hours.first(where: { $0.time > currentHourStart && ($0.precipitationProbability ?? 0) >= 50 }) {
            line += ", ab \(calendar.component(.hour, from: rain.time)) Uhr Regen wahrscheinlich"
        }
        return line + "."
    }

    static func notes(_ weather: WeatherSnapshot, todayHours: [WeatherHour], now: Date,
                      findings: [ResearchFinding]) -> [String] {
        var notes: [String] = []
        // Pressure drop within the next 24 h: largest fall from an earlier to a later hour.
        let upcoming = weather.hours
            .filter { $0.time >= now.addingTimeInterval(-3_600) && $0.time <= now.addingTimeInterval(24 * 3_600) }
            .sorted { $0.time < $1.time }
            .compactMap(\.surfacePressure)
        var highest = -Double.infinity
        var largestDrop = 0.0
        for pressure in upcoming {
            highest = max(highest, pressure)
            largestDrop = max(largestDrop, highest - pressure)
        }
        if largestDrop >= 6 { notes.append(pressureDropNote) }
        if let hottest = todayHours.map(\.apparentTemperature).max(), hottest >= 28 { notes.append(heatNote) }
        if todayHours.contains(where: { ($0.relativeHumidity ?? 0) >= 80 && $0.temperature >= 22 }) {
            notes.append(humidNote)
        }
        let heavyPollen = weather.pollen.filter { $0.value >= 50 }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        for entry in heavyPollen { notes.append("Viel \(pollenWord(entry.key)) in der Luft.") }
        if let aqi = weather.europeanAQI, aqi >= 60 { notes.append(airQualityNote) }
        for finding in findings where finding.cause.hasPrefix("weather_") { notes.append(finding.sentence) }
        return notes
    }

    /// Longest run of consecutive hours (start 07:00 … 19:00, so the window ends by 20:00) that are not over
    /// yet, with rain chance < 30 % and felt temperature 8…26 °C. Earliest run wins a tie.
    static func bestOutdoorWindow(_ weather: WeatherSnapshot, now: Date, calendar: Calendar) -> DateInterval? {
        let today = calendar.startOfDay(for: now)
        let candidates = weather.hours
            .filter { hour in
                calendar.isDate(hour.time, inSameDayAs: today)
                    && (7..<20).contains(calendar.component(.hour, from: hour.time))
                    && hour.time.addingTimeInterval(3_600) > now
            }
            .sorted { $0.time < $1.time }
        var best: (start: Date, end: Date)?
        var current: (start: Date, end: Date)?
        for hour in candidates {
            let fits = (hour.precipitationProbability ?? 0) < 30 && hour.apparentTemperature >= 8 && hour.apparentTemperature <= 26
            guard fits else {
                current = nil
                continue
            }
            let end = hour.time.addingTimeInterval(3_600)
            if let run = current, run.end == hour.time {
                current = (run.start, end)
            } else {
                current = (hour.time, end)
            }
            if let run = current {
                let runLength = run.end.timeIntervalSince(run.start)
                let bestLength = best.map { $0.end.timeIntervalSince($0.start) } ?? 0
                if runLength > bestLength { best = run }
            }
        }
        guard let window = best else { return nil }
        return DateInterval(start: window.start, end: window.end)
    }

    static func degrees(_ value: Double) -> String {
        let whole = Int(value.rounded())
        return whole < 0 ? "\u{2212}\(-whole)" : "\(whole)"
    }

    static func pollenWord(_ name: String) -> String {
        switch name {
        case "Birke": "Birkenpollen"
        case "Gräser": "Gräserpollen"
        case "Erle": "Erlenpollen"
        case "Beifuß": "Beifußpollen"
        case "Ambrosia": "Ambrosiapollen"
        default: "\(name)-Pollen"
        }
    }
}
