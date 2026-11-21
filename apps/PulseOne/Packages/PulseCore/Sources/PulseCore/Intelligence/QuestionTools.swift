import Foundation

/// Local query tools for questions about one's own history (spec §5). Claude never gets the archive;
/// it asks for aggregates, the iPhone computes them and answers with numbered facts.
public struct QuestionTools: Sendable {
    public let samples: [HealthSample]
    public let events: [ContextEvent]
    public let consent: Set<ConsentCategory>
    public let calendar: Calendar
    public let policy: SourcePolicy
    /// The running day: totals (steps, energy, distance) of this day are unfinished and left out.
    public let now: Date
    public static let maxCalls = 8

    public init(samples: [HealthSample], events: [ContextEvent], consent: Set<ConsentCategory>,
                calendar: Calendar = .current, policy: SourcePolicy = SourcePolicy(), now: Date = Date()) {
        self.now = now
        self.samples = samples.filter { $0.quality.usableForAnalysis && $0.profileID != nil }
        self.events = events
        self.consent = consent
        self.calendar = calendar
        self.policy = policy
    }

    /// Kinds Claude may ask for: consented and analysable.
    public var askableKinds: [SampleKind] {
        ConsentCategory.allCases.filter { consent.contains($0) }.flatMap(\.kinds)
    }

    // MARK: Definitions (strict tool use)

    public var definitions: [JSONValue] {
        let kinds = JSONValue.object(["type": .string("string"),
                                      "enum": .array(askableKinds.map { JSONValue.string($0.rawValue) })])
        let date = JSONValue.object(["type": .string("string"), "description": .string("Datum YYYY-MM-DD")])
        let integer = JSONValue.object(["type": .string("integer")])
        func tool(_ name: String, _ description: String, _ properties: [String: JSONValue]) -> JSONValue {
            .object([
                "name": .string(name),
                "description": .string(description),
                "strict": .bool(true),
                "input_schema": .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "required": .array(properties.keys.sorted().map { JSONValue.string($0) }),
                    "properties": .object(properties),
                ]),
            ])
        }
        var result = [
            tool("get_metric_summary", "Kennzahl eines Messwerts für einen Zeitraum, mit persönlicher Basislinie der 28 Tage davor.",
                 ["kind": kinds, "start": date, "end": date]),
            tool("compare_periods", "Vergleicht einen Messwert zwischen zwei Zeiträumen.",
                 ["kind": kinds, "a_start": date, "a_end": date, "b_start": date, "b_end": date]),
            tool("get_correlation", "Spearman-Rangkorrelation zweier Tageswerte; B wird lag_days nach A gelesen. Beobachteter Zusammenhang, keine Ursache.",
                 ["kind_a": kinds, "kind_b": kinds, "start": date, "end": date, "lag_days": integer]),
            tool("get_data_coverage", "An wie vielen Tagen eines Zeitraums es Daten zu einem Messwert gibt.",
                 ["kind": kinds, "start": date, "end": date]),
        ]
        if consent.contains(.notes) {
            result.append(tool("list_events", "Stichworte aus Abend-Notizen in einem Zeitraum.", ["start": date, "end": date]))
        }
        return result
    }

    // MARK: Execution

    public struct Output: Sendable {
        public let content: String
        public let facts: [AnalysisFact]
        public let correlations: [CorrelationFact]
        public let events: [ContextEventFact]
        public let isError: Bool
        /// Short line for "Claude hat abgefragt: …".
        public let summary: String
    }

    /// Runs one tool call. `nextID` hands out ids that are unique across the conversation.
    public func run(name: String, input: JSONValue, nextID: inout Int) -> Output {
        func fail(_ text: String) -> Output {
            Output(content: "{\"error\":\"\(text)\"}", facts: [], correlations: [], events: [], isError: true, summary: text)
        }
        func kind(_ key: String) -> SampleKind? {
            input[key]?.stringValue.flatMap(SampleKind.init(rawValue:)).flatMap { askableKinds.contains($0) ? $0 : nil }
        }
        func date(_ key: String) -> Date? { input[key]?.stringValue.flatMap(parseDay) }
        func encode<T: Encodable>(_ value: T) -> String {
            let e = JSONEncoder()
            e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            return (try? e.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        }

        switch name {
        case "get_metric_summary", "get_data_coverage":
            guard let k = kind("kind") else { return fail("nicht freigegeben oder unbekannt") }
            guard let s = date("start"), let e = date("end"), s <= e else { return fail("ungültiger Zeitraum") }
            guard let fact = summary(k, from: s, to: e, id: "Q\(nextID)") else {
                return fail("keine Daten für \(k.title) im Zeitraum")
            }
            nextID += 1
            return Output(content: encode(fact), facts: [fact], correlations: [], events: [], isError: false,
                          summary: "\(k.title), \(fact.period)")
        case "compare_periods":
            guard let k = kind("kind") else { return fail("nicht freigegeben oder unbekannt") }
            guard let aS = date("a_start"), let aE = date("a_end"), let bS = date("b_start"), let bE = date("b_end") else {
                return fail("ungültiger Zeitraum")
            }
            var facts: [AnalysisFact] = []
            if let a = summary(k, from: aS, to: aE, id: "Q\(nextID)") { facts.append(a); nextID += 1 }
            if let b = summary(k, from: bS, to: bE, id: "Q\(nextID)") { facts.append(b); nextID += 1 }
            guard facts.count == 2 else { return fail("in einem der Zeiträume fehlen Daten") }
            return Output(content: encode(facts), facts: facts, correlations: [], events: [], isError: false,
                          summary: "\(k.title): \(facts[0].period) gegen \(facts[1].period)")
        case "get_correlation":
            guard let a = kind("kind_a"), let b = kind("kind_b") else { return fail("nicht freigegeben oder unbekannt") }
            guard let s = date("start"), let e = date("end") else { return fail("ungültiger Zeitraum") }
            let lag = Int(input["lag_days"]?.numberValue ?? 0)
            let end = calendar.date(byAdding: .day, value: 1, to: e) ?? e
            let da = daily(a, from: s, to: calendar.date(byAdding: .day, value: max(lag, 0), to: end) ?? end)
            let db = daily(b, from: s, to: calendar.date(byAdding: .day, value: max(lag, 0), to: end) ?? end)
            guard let r = ContextBuilder.correlate(da, db, lagDays: lag, from: s, to: end, calendar: calendar), r.n >= 10 else {
                return fail("zu wenige gemeinsame Tage (mindestens 10)")
            }
            let c = CorrelationFact(id: "Q\(nextID)", a: a.rawValue, b: b.rawValue, titleA: a.title, titleB: b.title,
                                    method: "spearman", rho: IntelligenceStats.rounded(r.rho, decimals: 2), n: r.n,
                                    lagDays: lag, note: "beobachteter Zusammenhang, keine Ursache")
            nextID += 1
            return Output(content: encode(c), facts: [], correlations: [c], events: [], isError: false,
                          summary: "Zusammenhang \(a.title) und \(b.title)")
        case "list_events":
            guard consent.contains(.notes) else { return fail("nicht freigegeben") }
            guard let s = date("start"), let e = date("end") else { return fail("ungültiger Zeitraum") }
            let end = calendar.date(byAdding: .day, value: 1, to: e) ?? e
            var list: [ContextEventFact] = []
            for event in events.sorted(by: { $0.date < $1.date }) where event.date >= s && event.date < end {
                list.append(ContextEventFact(id: "Q\(nextID)", date: dayString(event.date), type: "note", label: event.tagLabel))
                nextID += 1
            }
            return Output(content: encode(list), facts: [], correlations: [], events: list, isError: false,
                          summary: "Notizen \(dayString(s)) bis \(dayString(e))")
        default:
            return fail("unbekanntes Werkzeug")
        }
    }

    func daily(_ kind: SampleKind, from: Date, to: Date) -> [Date: Double] {
        let end = kind.isRunningTotal ? min(to, calendar.startOfDay(for: now)) : to
        let relevant = samples.filter { $0.kind == kind && $0.start >= from && $0.start < end }
        return Dictionary(DailySeries.build(relevant, kind: kind, calendar: calendar, policy: policy).map { ($0.day, $0.value) },
                          uniquingKeysWith: { a, _ in a })
    }

    /// Median (point) or mean per day (cumulative) over [start, end], baseline = 28 days before.
    func summary(_ kind: SampleKind, from start: Date, to endDay: Date, id: String) -> AnalysisFact? {
        let end = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
        let baseStart = calendar.date(byAdding: .day, value: -ContextBuilder.baselineWindowDays, to: start) ?? start
        let values = daily(kind, from: start, to: end).values.map { $0 }
        guard !values.isEmpty else { return nil }
        let central = kind.isCumulative ? IntelligenceStats.mean(values) : IntelligenceStats.median(values)
        let base = daily(kind, from: baseStart, to: start).values.map { $0 }
        var baseline: FactBaseline?
        if !kind.isVendorScore, base.count >= ContextBuilder.baselineMinimumDays, let m = IntelligenceStats.median(base),
           let lo = IntelligenceStats.quantile(base, 0.25), let hi = IntelligenceStats.quantile(base, 0.75) {
            baseline = FactBaseline(median: FactUnits.display(kind, m).value, p25: FactUnits.display(kind, lo).value,
                                    p75: FactUnits.display(kind, hi).value,
                                    windowDays: ContextBuilder.baselineWindowDays, n: base.count)
        }
        let days = max(1, calendar.dateComponents([.day], from: start, to: end).day ?? 1)
        let shown = FactUnits.display(kind, central ?? 0)
        return AnalysisFact(id: id, kind: kind.rawValue, title: kind.title,
                            stat: kind.isVendorScore ? "vendor_median" : kind.isCumulative ? "mean_per_day" : "median",
                            value: shown.value, unit: shown.unit,
                            period: "\(dayString(start))/\(dayString(endDay))", n: values.count,
                            coverage: IntelligenceStats.rounded(min(1, Double(values.count) / Double(days)), decimals: 2),
                            baseline: baseline, source: "local", quality: "plausible")
    }

    func parseDay(_ text: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: text).map { calendar.startOfDay(for: $0) }
    }

    func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Wraps all facts handed out so far, so the same validator checks the answer.
    public static func context(facts: [AnalysisFact], correlations: [CorrelationFact], events: [ContextEventFact],
                               consent: Set<ConsentCategory>, now: Date) -> HealthAnalysisContext {
        HealthAnalysisContext(analysisType: "question", generatedAt: ISO8601DateFormatter().string(from: now),
                              period: AnalysisPeriod(start: "", end: "", timezone: TimeZone.current.identifier),
                              comparisonPeriod: nil, profile: .empty,
                              consentedCategories: ConsentCategory.allCases.filter { consent.contains($0) }.map(\.rawValue),
                              facts: facts, correlations: correlations, events: events, dataGaps: [])
    }

    /// Tool result block for the next user turn.
    public static func resultBlock(toolUseID: String, output: Output) -> JSONValue {
        .object(["type": .string("tool_result"), "tool_use_id": .string(toolUseID),
                 "content": .string(output.content), "is_error": .bool(output.isError)])
    }
}
