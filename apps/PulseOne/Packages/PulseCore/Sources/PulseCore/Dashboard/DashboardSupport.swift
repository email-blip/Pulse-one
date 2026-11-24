import Foundation

// Team 03 (Dashboard). Tile packing, saving the layout per profile, what a tile shows, and the hypnogram rules.

/// Packs tiles into rows of a two-column grid in the user's order: two small tiles share a row,
/// wide and large tiles take a row of their own. The order is never changed to fill holes.
public enum DashboardGrid {
    public static func rows(_ tiles: [DashboardTile]) -> [[DashboardTile]] {
        var rows: [[DashboardTile]] = []
        var waiting: DashboardTile?
        for tile in tiles {
            if tile.size == .small {
                if let first = waiting {
                    rows.append([first, tile])
                    waiting = nil
                } else {
                    waiting = tile
                }
            } else {
                if let first = waiting {
                    rows.append([first])
                    waiting = nil
                }
                rows.append([tile])
            }
        }
        if let waiting { rows.append([waiting]) }
        return rows
    }
}

extension DashboardLayout {
    /// UserDefaults key of one profile's layout. `namespace` keeps UI-test layouts apart from real ones.
    public static func storageKey(subjectID: UUID?, namespace: String? = nil) -> String {
        let profile = subjectID?.uuidString ?? "default"
        if let namespace, !namespace.isEmpty { return "dashboard.layout.\(namespace).\(profile)" }
        return "dashboard.layout.\(profile)"
    }

    /// The saved layout, or the standard one. Tiles added in later releases are appended at the end,
    /// so the user's order stays.
    public static func restore(_ data: Data?, subjectID: UUID?) -> DashboardLayout {
        let standard = DashboardLayout.standard(subjectID: subjectID)
        guard let data, let saved = try? JSONDecoder().decode(DashboardLayout.self, from: data) else { return standard }
        var layout = DashboardLayout(subjectID: subjectID, tiles: saved.tiles)
        layout.appendMissing(standard.tiles)
        return layout
    }

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }

    /// Accessible alternative to dragging: one step up or down among the *visible* tiles.
    public mutating func step(id: String, by offset: Int) {
        let visible = visibleTiles
        guard let position = visible.firstIndex(where: { $0.id == id }) else { return }
        let target = position + offset
        guard visible.indices.contains(target), let index = tiles.firstIndex(where: { $0.id == visible[target].id }) else { return }
        move(id: id, to: index)
    }
}

extension DashboardTile {
    /// The kind behind a metric tile ("metric.heart_rate"), nil for sleep and training.
    public var metricKind: SampleKind? {
        guard id.hasPrefix("metric.") else { return nil }
        return SampleKind(rawValue: String(id.dropFirst("metric.".count)))
    }

    public var title: String {
        if let kind = metricKind {
            return switch kind {
            case .ringHRV: "HRV"
            case .ringStress: "Stress"
            case .oxygenSaturation: "SpO₂"
            default: kind.title
            }
        }
        return switch id {
        case "sleep": "Schlaf"
        case "training": "Training"
        default: id
        }
    }

    public var systemImage: String {
        if let kind = metricKind { return kind.systemImage }
        return id == "sleep" ? "bed.double" : "figure.run"
    }

    /// The Verlauf track a tile opens.
    public var track: TimelineTrack {
        switch metricKind {
        case .heartRate?, .restingHeartRate?: .heartRate
        case .ringHRV?, .heartRateVariability?: .hrv
        case .oxygenSaturation?: .spo2
        case .ringStress?: .stress
        case .steps?, .activeEnergy?: .movement
        default: id == "sleep" ? .sleepPhases : .training
        }
    }
}

/// What a tile shows: the newest valid value with the time it refers to, and a mini history of real points.
public struct TileReading: Equatable, Sendable {
    public let value: Double
    /// Display text of the value ("7:12", "64", "8.412").
    public let text: String
    public let unit: String
    /// Upper-case reference line, e.g. "NACHT · 07:00", "HEUTE · 14:05".
    public let reference: String
    /// The moment the value refers to (for "Warum?" and the Verlauf focus).
    public let at: Date
    /// Real points for the mini history, oldest first; never filled.
    public let spark: [SparkPoint]
    /// Older than a day: shown dimmed with its date.
    public let isOld: Bool

    public init(value: Double, text: String, unit: String, reference: String, at: Date, spark: [SparkPoint], isOld: Bool) {
        self.value = value
        self.text = text
        self.unit = unit
        self.reference = reference
        self.at = at
        self.spark = spark
        self.isOld = isOld
    }
}

public struct SparkPoint: Equatable, Sendable, Identifiable {
    public let at: Date
    public let value: Double
    /// A new run starts after a gap; the mini history breaks the line there.
    public let run: Int
    public var id: Date { at }

    public init(at: Date, value: Double, run: Int) {
        self.at = at
        self.value = value
        self.run = run
    }
}

public enum TileSummary {
    static let german = Locale(identifier: "de_DE")

    /// "06:55": two-digit hours always (`.shortened` gives "6:55" on some systems).
    public static func clockStyle(_ calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(locale: german, calendar: calendar, timeZone: calendar.timeZone)
            .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
    }

    /// Reference line for a value: "HEUTE · 14:05", "GESTERN · 22:10", "NACHT · 07:00", "18.11. · 09:30".
    public static func reference(for date: Date, now: Date, night: Bool = false, until: Bool = false,
                                 calendar: Calendar) -> String {
        let clock = date.formatted(clockStyle(calendar))
        let today = calendar.startOfDay(for: now)
        let day: String
        if night, calendar.isDate(date, inSameDayAs: today) {
            day = "NACHT"
        } else if calendar.isDate(date, inSameDayAs: today) {
            day = "HEUTE"
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), calendar.isDate(date, inSameDayAs: yesterday) {
            day = night ? "LETZTE NACHT" : "GESTERN"
        } else {
            var style = Date.FormatStyle(locale: german).day(.twoDigits).month(.twoDigits)
            style.timeZone = calendar.timeZone
            day = date.formatted(style)
        }
        return until ? "\(day) · BIS \(clock)" : "\(day) · \(clock)"
    }

    /// Reading of one measured kind from its points (sorted or not). Point kinds: newest value and the real
    /// points of the 24 hours before it. Cumulative kinds: today's total so far (else the last day with data)
    /// and the hourly sums of that day.
    public static func reading(kind: SampleKind, points: [MeasurementPoint], now: Date, calendar: Calendar) -> TileReading? {
        let sorted = points.filter { $0.kind == kind && $0.measuredAt <= now }.sorted { $0.measuredAt < $1.measuredAt }
        guard let last = sorted.last else { return nil }
        let isOld = now.timeIntervalSince(last.measuredUntil) > 86_400
        if kind.isCumulative {
            let day = calendar.startOfDay(for: last.measuredAt)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            let window = DateInterval(start: day, end: dayEnd)
            let ofDay = sorted.filter { $0.measuredAt >= day && $0.measuredAt < dayEnd }
            let total = ofDay.reduce(0) { $0 + $1.value }
            let hourly = TrackSeries.values(ofDay, kind: kind, in: window, resolution: .hourly, calendar: calendar)
            let lastEnd = ofDay.map(\.measuredUntil).max() ?? last.measuredUntil
            return TileReading(value: total, text: kind.display(total), unit: kind.displayUnit,
                               reference: reference(for: lastEnd, now: now, until: true, calendar: calendar),
                               at: lastEnd, spark: hourly.map { SparkPoint(at: $0.at, value: $0.value, run: $0.run) },
                               isOld: isOld)
        }
        let from = last.measuredAt.addingTimeInterval(-86_400)
        let window = DateInterval(start: from, end: last.measuredUntil)
        let recent = sorted.filter { $0.measuredAt >= from }
        let daily = kind.aggregation == .derived
        let spark: [TrackValue]
        if daily {
            let week = DateInterval(start: last.measuredAt.addingTimeInterval(-7 * 86_400), end: last.measuredUntil)
            spark = TrackSeries.values(sorted, kind: kind, in: week, resolution: .original, calendar: calendar)
        } else {
            spark = TrackSeries.values(recent, kind: kind, in: window, resolution: .original, calendar: calendar)
        }
        return TileReading(value: last.value, text: kind.display(last.value), unit: kind.displayUnit,
                           reference: reference(for: last.measuredAt, now: now, night: kind == .restingHeartRate, calendar: calendar),
                           at: last.measuredAt, spark: thin(spark.map { SparkPoint(at: $0.at, value: $0.value, run: $0.run) }),
                           isOld: isOld)
    }

    /// At most `limit` points for a mini chart, keeping first, last and gap edges.
    public static func thin(_ points: [SparkPoint], limit: Int = 96) -> [SparkPoint] {
        guard points.count > limit else { return points }
        let stride = Int((Double(points.count) / Double(limit)).rounded(.up))
        return points.enumerated().compactMap { index, point in
            let edge = index == 0 || index == points.count - 1
                || points[index - 1].run != point.run || (index + 1 < points.count && points[index + 1].run != point.run)
            return edge || index % stride == 0 ? point : nil
        }
    }

    /// "7 h 12 min", "45 min".
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
}

/// Hypnogram rules: four lanes plus a separate lane for codes we cannot map; every interval keeps its real times.
public enum Hypnogram {
    /// Top to bottom, as in common hypnograms. `unknown` is drawn on its own lane below.
    public static let lanes: [SleepPhase] = [.awake, .rem, .light, .deep, .unknown]

    public static func title(_ phase: SleepPhase) -> String {
        switch phase {
        case .awake: "Wach"
        case .rem: "REM"
        case .light: "Leicht"
        case .deep: "Tief"
        case .unknown: "Unbekannt"
        }
    }

    /// The interval under the cursor; nil in a gap.
    public static func segment(at time: Date, in segments: [SleepSegment]) -> SleepSegment? {
        segments.first { $0.start <= time && time < $0.end }
    }

    /// Nights from loose segments, newest last.
    public static func nights(_ segments: [SleepSegment]) -> [SleepNight] { SleepSegmentSync.nights(segments) }

    /// "Tief · 01:10–01:45 · 35 min"
    public static func describe(_ segment: SleepSegment, calendar: Calendar) -> String {
        let time = TileSummary.clockStyle(calendar)
        return "\(title(segment.phase)) · \(segment.start.formatted(time))–\(segment.end.formatted(time)) · \(TileSummary.duration(segment.duration))"
    }
}
