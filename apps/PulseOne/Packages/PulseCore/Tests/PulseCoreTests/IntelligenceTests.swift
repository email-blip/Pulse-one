import Foundation
import Testing
@testable import PulseCore

private let owner = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
/// 2026-11-21 12:00 Europe/Berlin.
private let now = Date(timeIntervalSince1970: 1_795_258_800)

private var berlin: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return c
}

/// One sample `daysAgo` days before `now`, at `hour` local time.
private func sample(_ kind: SampleKind, _ value: Double, daysAgo: Int, hour: Int = 8, profile: UUID? = owner,
                    quality: SampleQuality = .valid) -> HealthSample {
    let day = berlin.date(byAdding: .day, value: -daysAgo, to: berlin.startOfDay(for: now))!
    let start = berlin.date(byAdding: .hour, value: hour, to: day)!
    let end = kind == .sleepDuration ? start.addingTimeInterval(value) : start
    return HealthSample(profileID: profile, kind: kind, value: value, unit: kind.canonicalUnit, start: start, end: end,
                        timeZoneIdentifier: "Europe/Berlin", source: .appleHealth, deviceID: "watch-1",
                        originalSampleID: "\(kind.rawValue)-\(daysAgo)-\(hour)", importedAt: now, quality: quality,
                        method: .healthStore, originDetail: "Apple Watch")
}

/// 40 days: resting pulse 54–56, sleep 7 h ± 0.5, steps 8000 ± 1000.
private func history(days: Int = 40) -> [HealthSample] {
    var result: [HealthSample] = []
    for d in 0..<days {
        let pulse: Double = 54 + Double(d % 3)
        let sleepHours: Double = 7 + Double(d % 2) - 0.25
        let steps: Double = 8_000 + Double((d % 3) - 1) * 1_000
        result.append(sample(.restingHeartRate, pulse, daysAgo: d))
        result.append(sample(.sleepDuration, sleepHours * 3_600, daysAgo: d, hour: 0))
        result.append(sample(.steps, steps, daysAgo: d, hour: 12))
    }
    return result
}

private func fact(_ id: String, _ kind: SampleKind, _ value: Double, unit: String, n: Int = 7, coverage: Double = 1,
                  baseline: FactBaseline? = nil) -> AnalysisFact {
    AnalysisFact(id: id, kind: kind.rawValue, title: kind.title, stat: "median", value: value, unit: unit,
                 period: "2026-11-15/2026-11-21", n: n, coverage: coverage, baseline: baseline, source: "apple_health",
                 quality: "valid")
}

private func context(_ facts: [AnalysisFact], correlations: [CorrelationFact] = []) -> HealthAnalysisContext {
    HealthAnalysisContext(analysisType: "weekly", generatedAt: "2026-11-21T12:00:00+01:00",
                          period: AnalysisPeriod(start: "2026-11-15", end: "2026-11-21", timezone: "Europe/Berlin"),
                          comparisonPeriod: nil, profile: .empty, consentedCategories: ["heart"], facts: facts,
                          correlations: correlations, events: [], dataGaps: [])
}

private func report(summary: [ReportStatement], referral: ReferralLevel = .none) -> AnalysisReport {
    AnalysisReport(summary: summary, dataSituation: [], sections: [], openQuestions: [], uncertainties: [], actions: [],
                   medicalReferral: MedicalReferral(level: referral, reason: "", evidence: []))
}

@Suite("Intelligence statistics")
struct IntelligenceStatsTests {
    @Test func quantilesAndRanks() {
        #expect(IntelligenceStats.median([3, 1, 2]) == 2)
        #expect(IntelligenceStats.quantile([1, 2, 3, 4], 0.25) == 1.75)
        #expect(IntelligenceStats.ranks([10, 20, 20, 30]) == [1, 2.5, 2.5, 4])
        // Same definition as the TODAY screen's personal band.
        #expect(IntelligenceStats.quantile([5, 1, 9, 3], 0.75) == PersonalBaselineReference.percentile([1, 3, 5, 9], 0.75))
    }

    @Test func spearmanDetectsMonotonicAndConstant() {
        #expect(IntelligenceStats.spearman([1, 2, 3, 4], [10, 20, 30, 45]) == 1)
        #expect(IntelligenceStats.spearman([1, 2, 3, 4], [4, 3, 2, 1]) == -1)
        #expect(IntelligenceStats.spearman([1, 2, 3], [5, 5, 5]) == nil)
    }
}

/// Type-7 percentile as used by `PersonalBaseline` (kept here so this test does not depend on Welle 1 files).
private enum PersonalBaselineReference {
    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        let rank = p * Double(sorted.count - 1)
        let low = Int(rank.rounded(.down))
        let high = min(low + 1, sorted.count - 1)
        return sorted[low] + (sorted[high] - sorted[low]) * (rank - Double(low))
    }
}

@Suite("Evening note")
struct EveningNoteTests {
    @Test func findsTagsAcrossSports() {
        let note = EveningNoteParser.parse("Krafttraining Beine, viel Stress im Büro, zwei Bier")
        #expect(note.tags == [.stress, .alcohol, .training])
        #expect(EveningNoteParser.parse("Heute 10 km gerudert, danach Sauna").tags == [.training, .relaxed])
        #expect(EveningNoteParser.parse("Mit dem Hund lange wandern gewesen").tags == [.training])
    }

    @Test func negationAndFalseFriends() {
        let note = EveningNoteParser.parse("Kein Kaffee heute, aber schlecht geschlafen")
        #expect(!note.tags.contains(.caffeine))
        #expect(note.tags.contains(.poorSleep))
        #expect(note.mood == nil)  // "schlecht geschlafen" is about sleep
        #expect(EveningNoteParser.parse("Preise verglichen, gerade gelesen").tags.isEmpty)
    }

    @Test func mood() {
        #expect(EveningNoteParser.parse("Stimmung 4, Umzugskartons geschleppt").mood == 4)
        #expect(EveningNoteParser.parse("Ziemlich genervt heute").mood == 2)
        #expect(EveningNoteParser.parse("Super Tag").mood == 5)
    }

    @Test func eventLabelHasNoFreeText() {
        let e = ContextEvent(date: now, tags: [.alcohol], mood: 3, text: "Bei Anna Geburtstag gefeiert")
        #expect(e.tagLabel == "Alkohol, Stimmung 3/5")
        #expect(!e.tagLabel.contains("Anna"))
    }
}

@Suite("Analysis context")
struct ContextBuilderTests {
    @Test func weeklyFactsWithBaselineAndIDs() throws {
        let ctx = ContextBuilder(calendar: berlin).build(samples: history(), events: [], kind: .weekly, now: now,
                                                         consent: ConsentCategory.defaultConsent, profile: .empty)
        #expect(ctx.contextVersion == 1)
        #expect(ctx.period.start == "2026-11-15")
        #expect(ctx.period.end == "2026-11-21")
        let rhr = try #require(ctx.facts.first { $0.kind == SampleKind.restingHeartRate.rawValue })
        #expect(rhr.id.hasPrefix("F"))
        #expect(rhr.n == 7)
        #expect(rhr.coverage == 1)
        let base = try #require(rhr.baseline)
        #expect(base.windowDays == 28)
        #expect(base.n == 28)
        #expect(base.median == 55)
        let sleep = try #require(ctx.facts.first { $0.kind == SampleKind.sleepDuration.rawValue })
        #expect(sleep.unit == "h")
        #expect(Set(ctx.facts.map(\.id)).count == ctx.facts.count)
    }

    /// Steps of the running day are never compared with whole days, and never enter a weekly mean.
    @Test func runningDayIsNotComparedForCounters() throws {
        let daily = ContextBuilder(calendar: berlin).build(samples: history(), events: [], kind: .daily, now: now,
                                                           consent: ConsentCategory.defaultConsent, profile: .empty)
        let today = try #require(daily.facts.first { $0.kind == SampleKind.steps.rawValue })
        #expect(today.stat == "so_far_today")
        #expect(today.baseline == nil)
        #expect(LocalSentences.describe(today).contains("bisher heute"))
        let weekly = ContextBuilder(calendar: berlin).build(samples: history(), events: [], kind: .weekly, now: now,
                                                            consent: ConsentCategory.defaultConsent, profile: .empty)
        let week = try #require(weekly.facts.first { $0.kind == SampleKind.steps.rawValue })
        #expect(week.stat == "mean_per_day")
        #expect(week.n == 6)
        #expect(week.baseline != nil)
    }

    @Test func ringHRVStaysApartAndRingStressIsOnlyAPattern() throws {
        var samples = history()
        for d in 0..<40 {
            let ringHRV: Double = 44 + Double(d % 4)
            let stress: Double = 30 + Double(d % 5)
            samples.append(sample(.ringHRV, ringHRV, daysAgo: d, hour: 6))
            samples.append(sample(.ringStress, stress, daysAgo: d, hour: 15))
        }
        let builder = ContextBuilder(calendar: berlin)
        // Stress needs its own opt-in; ring HRV goes with the heart category.
        #expect(!ConsentCategory.defaultConsent.contains(.ringStress))
        #expect(ConsentCategory.category(for: .ringHRV) == .heart)
        let standard = builder.build(samples: samples, events: [], kind: .weekly, now: now,
                                     consent: ConsentCategory.defaultConsent, profile: .empty)
        #expect(!standard.facts.contains { $0.kind == SampleKind.ringStress.rawValue })
        let hrv = try #require(standard.facts.first { $0.kind == SampleKind.ringHRV.rawValue })
        #expect(hrv.title == SampleKind.ringHRV.title)
        #expect(hrv.baseline != nil)
        #expect(!standard.facts.contains { $0.kind == SampleKind.heartRateVariability.rawValue })

        let withStress = builder.build(samples: samples, events: [], kind: .weekly, now: now,
                                       consent: ConsentCategory.defaultConsent.union([.ringStress]), profile: .empty)
        let stress = try #require(withStress.facts.first { $0.kind == SampleKind.ringStress.rawValue })
        #expect(stress.stat == "vendor_median")
        #expect(stress.baseline == nil)
        #expect(LocalSentences.describe(stress).contains("ohne Bewertung"))
        #expect(!BodyDetective.featureKinds.contains(.ringStress))
        #expect(!CorrelationPair.standard.contains { $0.a == .ringStress || $0.b == .ringStress })
        #expect(IntelligencePrompts.version >= 3)
    }

    @Test func consentAndMinimisation() {
        let events = [ContextEvent(date: now.addingTimeInterval(-3_600), tags: [.stress], mood: nil, text: "Ärger mit Chef Müller")]
        let ctx = ContextBuilder(calendar: berlin).build(samples: history(), events: events, kind: .weekly, now: now,
                                                         consent: [.heart], profile: ProfileSummary(ageRange: "40-49", sex: "male", goals: []))
        #expect(ctx.facts.allSatisfy { $0.kind == SampleKind.restingHeartRate.rawValue })
        #expect(ctx.events.isEmpty)  // notes not consented
        let json = ctx.compactJSON()
        #expect(!json.contains("watch-1"))
        #expect(!json.contains("Müller"))
        #expect(!json.contains("Apple Watch"))
        #expect(ctx.consentedCategories == ["heart"])
    }

    @Test func notesSendTagsOnly() {
        let events = [ContextEvent(date: now.addingTimeInterval(-3_600), tags: [.stress], mood: nil, text: "Ärger mit Chef Müller")]
        let ctx = ContextBuilder(calendar: berlin).build(samples: history(), events: events, kind: .weekly, now: now,
                                                         consent: [.heart, .notes], profile: .empty)
        #expect(ctx.events.map(\.label) == ["Stress"])
        #expect(!ctx.compactJSON().contains("Müller"))
    }

    @Test func unresolvedAndImplausibleSamplesAreLeftOut() {
        let odd = [sample(.restingHeartRate, 130, daysAgo: 0, hour: 9, profile: nil),
                   sample(.restingHeartRate, 20, daysAgo: 1, hour: 9, quality: .implausible)]
        let ctx = ContextBuilder(calendar: berlin).build(samples: history() + odd, events: [], kind: .weekly, now: now,
                                                         consent: [.heart], profile: .empty)
        #expect(ctx.facts.first?.value ?? 0 < 60)
    }

    @Test func correlationNeedsEnoughDays() {
        let short = ContextBuilder(calendar: berlin).build(samples: history(days: 10), events: [], kind: .weekly, now: now,
                                                           consent: ConsentCategory.defaultConsent, profile: .empty)
        #expect(short.correlations.isEmpty)
    }

    @Test func ageRange() {
        #expect(ProfileSummary.ageRange(birthYear: 1981, now: now, calendar: berlin) == "40-49")
        #expect(ProfileSummary.ageRange(birthYear: nil, now: now, calendar: berlin) == nil)
    }
}

@Suite("Response validator")
struct ResponseValidatorTests {
    let ctx = context([
        fact("F1", .restingHeartRate, 58, unit: "bpm",
             baseline: FactBaseline(median: 55, p25: 53, p75: 57, windowDays: 28, n: 28)),
        fact("F2", .steps, 8_432, unit: "count"),
    ])

    @Test func keepsTraceableStatements() {
        let ok = ReportStatement(text: "Dein Ruhepuls lag im Median bei 58 bpm, 3 bpm über deinem üblichen Wert von 55 bpm.",
                                 type: .computed, evidence: ["F1"])
        let steps = ReportStatement(text: "Im Mittel 8.432 Schritte pro Tag.", type: .computed, evidence: ["F2"])
        let result = ResponseValidator(context: ctx).validate(report(summary: [ok, steps]))
        #expect(result.report.summary == [ok, steps])
        #expect(result.rejectedCount == 0)
    }

    @Test func rejectsInventedNumbersUnknownIDsAndMissingEvidence() {
        let invented = ReportStatement(text: "Dein Ruhepuls lag bei 61 bpm.", type: .measured, evidence: ["F1"])
        let unknown = ReportStatement(text: "Der Schlaf war kürzer.", type: .observation, evidence: ["F9"])
        let bare = ReportStatement(text: "Der Ruhepuls stieg.", type: .observation, evidence: [])
        let result = ResponseValidator(context: ctx).validate(report(summary: [invented, unknown, bare]))
        #expect(result.report.summary.isEmpty)
        #expect(result.issues.map(\.rule) == ["Zahl", "ID", "Beleg"])
    }

    @Test func safetyRulesApply() {
        let diagnosis = ReportStatement(text: "Das deutet auf eine Infektion hin.", type: .interpretation, evidence: ["F1"])
        let causal = ReportStatement(text: "Der Ruhepuls war höher, weil du wenig geschlafen hast.", type: .interpretation, evidence: ["F1"])
        let result = ResponseValidator(context: ctx, mode: .descriptive).validate(report(summary: [diagnosis, causal]))
        #expect(result.report.summary == [causal])
        #expect(result.flagged[causal.text] != nil)
        #expect(result.issues.contains { $0.rule == "S1" && $0.severity == .rejected })
    }

    @Test func clinicalModeKeepsDiagnosesAndReferenceValuesButNotInventedMeasurements() {
        let diagnosis = ReportStatement(text: "Das deutet mit etwa 30 % Wahrscheinlichkeit auf einen beginnenden Infekt hin, weil der Ruhepuls über 100 bpm Grenze noch weit entfernt ist.",
                                        type: .interpretation, evidence: ["F1"])
        let disclaimer = ReportStatement(text: "Ich bin kein Arzt, bitte frag deine Hausärztin.", type: .interpretation, evidence: [])
        let invented = ReportStatement(text: "Dein Ruhepuls lag bei 61 bpm.", type: .measured, evidence: ["F1"])
        let medication = ReportStatement(text: "Du könntest mit deiner Ärztin besprechen, den Betablocker zu reduzieren.",
                                         type: .recommendation, evidence: [])
        let result = ResponseValidator(context: ctx).validate(report(summary: [diagnosis, disclaimer, invented, medication]))
        #expect(result.report.summary == [diagnosis, medication])
        #expect(result.flagged[medication.text] != nil)
        #expect(result.issues.contains { $0.rule == "S7" })
        #expect(result.issues.contains { $0.rule == "Zahl" })
    }

    @Test func fixedThresholdForcesReferral() {
        let high = context([fact("F1", .restingHeartRate, 105, unit: "bpm", n: 7)])
        let result = ResponseValidator(context: high).validate(report(summary: [], referral: .none))
        #expect(result.report.medicalReferral.level == .recommend)
        #expect(result.report.medicalReferral.evidence == ["F1"])
    }

    @Test func decodesJSONAndReportsBadShape() throws {
        let json = """
        {"summary":[{"text":"Ruhepuls im Median 58 bpm.","type":"measured","evidence":["F1"]}],"dataSituation":[],
         "sections":[],"openQuestions":[],"uncertainties":[],"actions":[],
         "medicalReferral":{"level":"none","reason":"","evidence":[]}}
        """
        let result = try ResponseValidator(context: ctx).validateReport(json: json)
        #expect(result.report.summary.count == 1)
        #expect(throws: ValidationError.notJSON) { try ResponseValidator(context: ctx).validateReport(json: "kein json") }
    }

    @Test func numberParsing() {
        let numbers = ResponseValidator.numbers(in: "Am 14.11. lag F1 bei 6,1 h und 8.432 Schritten um 07:30, SpO₂ 97 %.")
        #expect(numbers.map(\.value) == [6.1, 8_432, 97])
    }
}

@Suite("Safety rules")
struct SafetyRulesTests {
    @Test(arguments: [
        "Du hast vermutlich eine Schlafapnoe.",
        "Mit 70 % Wahrscheinlichkeit liegt eine Erkrankung vor.",
        "Du hast ein erhöhtes Risiko für Bluthochdruck.",
        "Du könntest deinen Betablocker reduzieren.",
        "Diagnose: Übertraining.",
    ])
    func rejects(_ text: String) {
        if case .reject = SafetyRules.check(text, mode: .descriptive) {} else { Issue.record("not rejected: \(text)") }
    }

    @Test(arguments: [
        "Du hast vermutlich eine Schlafapnoe.",
        "Mit 70 % Wahrscheinlichkeit liegt ein Infekt vor.",
        "Der Ruhepuls ist gestiegen, weil du wenig geschlafen hast.",
        "Diagnose: Übertraining.",
    ])
    func clinicalAllows(_ text: String) {
        #expect(SafetyRules.check(text) == .allow)
    }

    @Test func clinicalFlagsMedicationAndDropsDisclaimers() {
        if case .flag(let rule, _) = SafetyRules.check("Du könntest deinen Betablocker reduzieren.") {
            #expect(rule == "S3")
        } else {
            Issue.record("medication change not flagged")
        }
        let text = "Dein Ruhepuls ist erhöht. Ich bin kein Arzt. Lass das in zwei Wochen prüfen."
        #expect(SafetyRules.removingBoilerplate(text) == "Dein Ruhepuls ist erhöht. Lass das in zwei Wochen prüfen.")
    }

    @Test(arguments: [
        "Dein Ruhepuls lag über deinem üblichen Bereich.",
        "An Tagen mit mehr Schritten hast du eher länger geschlafen.",
        "Wenn das anhält, lass es ärztlich abklären.",
    ])
    func allows(_ text: String) {
        #expect(SafetyRules.check(text, mode: .descriptive) == .allow)
    }

    @Test func emergency() {
        #expect(SafetyRules.isEmergency("Ich habe seit einer Stunde Brustschmerzen"))
        #expect(!SafetyRules.isEmergency("Warum war mein Ruhepuls höher?"))
    }
}

@Suite("Cost and budget")
struct CostTests {
    @Test func estimateAndActual() {
        let e = CostEstimator.estimate(inputCharacters: 30_000, expectedOutputTokens: 6_000, model: .opus)
        #expect(e.inputTokens == 10_000)
        #expect(abs(e.usd - 0.16) < 0.0001)
        let usage = TokenUsage(inputTokens: 1_000_000, outputTokens: 0, cacheCreationInputTokens: 0, cacheReadInputTokens: 1_000_000)
        #expect(abs(CostEstimator.cost(of: usage, model: .opus) - 4.2) < 0.0001)
    }

    @Test func budget() {
        let small = CostEstimate(inputTokens: 1, outputTokens: 1, usd: 0.5)
        #expect(SpendingBudget(limitUSD: 10, spentUSD: 1).status == .ok)
        #expect(SpendingBudget(limitUSD: 10, spentUSD: 8).status == .warning)
        #expect(SpendingBudget(limitUSD: 10, spentUSD: 10).status == .exhausted)
        #expect(!SpendingBudget(limitUSD: 10, spentUSD: 9.8).allows(small))
        #expect(SendBudget(maxSends: 30, used: 30).allowsSend == false)
    }
}

@Suite("Anthropic request and response")
struct AnthropicAPITests {
    @Test func bodyHasSchemaEffortAndFallback() throws {
        let body = AnthropicAPI.body(model: .opus, system: "S", messages: [AnthropicAPI.userText("{}")],
                                     schema: AnalysisSchema.reportV1, effort: "high")
        #expect(body["model"]?.stringValue == "claude-opus-5-5")
        #expect(body["output_config"]?["effort"]?.stringValue == "high")
        #expect(body["output_config"]?["format"]?["type"]?.stringValue == "json_schema")
        #expect(body["fallbacks"]?.stringValue == "default")
        #expect(body["temperature"] == nil)
        let json = body.encodedString()
        #expect(json.contains("\"max_tokens\":16000"))
        #expect(AnthropicAPI.headers(apiKey: "k")["anthropic-version"] == "2026-10-21")
    }

    @Test func schemaObjectsAreClosed() {
        let schema = AnalysisSchema.reportV1
        #expect(schema["additionalProperties"] == .bool(false))
        #expect(schema["required"]?.arrayValue?.count == 7)
        #expect(!schema.encodedString().contains("$ref"))
    }

    @Test func decodesResponse() throws {
        let data = Data("""
        {"id":"msg_1","model":"claude-opus-5-5","stop_reason":"end_turn","type":"message","role":"assistant",
         "content":[{"type":"thinking","thinking":""},{"type":"text","text":"{\\"a\\":1}"}],
         "usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":3}}
        """.utf8)
        let r = try AnthropicResponse.decode(data)
        #expect(r.text == "{\"a\":1}")
        #expect(r.usage.cacheReadInputTokens == 3)
        #expect(r.usage.cacheCreationInputTokens == 0)
    }

    @Test func errors() {
        #expect(AnthropicError.from(status: 401, body: Data(), retryAfter: nil) == .invalidKey)
        #expect(AnthropicError.from(status: 429, body: Data(), retryAfter: "12") == .rateLimited(retryAfter: 12))
        #expect(AnthropicError.from(status: 529, body: Data(), retryAfter: nil).isRetryable)
    }
}

@Suite("Question tools")
struct QuestionToolsTests {
    @Test func summaryAndConsent() {
        let tools = QuestionTools(samples: history(), events: [], consent: [.heart], calendar: berlin)
        var next = 1
        let ok = tools.run(name: "get_metric_summary",
                           input: ["kind": "resting_heart_rate", "start": "2026-11-15", "end": "2026-11-21"], nextID: &next)
        #expect(!ok.isError)
        #expect(ok.facts.first?.id == "Q1")
        #expect(ok.facts.first?.baseline != nil)
        #expect(next == 2)
        let denied = tools.run(name: "get_metric_summary",
                               input: ["kind": "sleep_duration", "start": "2026-11-15", "end": "2026-11-21"], nextID: &next)
        #expect(denied.isError)
        let names: [String] = tools.definitions.map { $0["name"]?.stringValue ?? "" }
        #expect(!names.contains("list_events"))
    }
}

@Suite("Body detective")
struct BodyDetectiveTests {
    @Test func findsDeviationAndAnalogues() throws {
        let recent = now.addingTimeInterval(-2 * 86_400)
        var samples = history().filter { s in !(s.kind == .restingHeartRate && s.start > recent) }
        samples += [sample(.restingHeartRate, 64, daysAgo: 0), sample(.restingHeartRate, 63, daysAgo: 1)]
        // An earlier similar day (20 days ago) followed by a note.
        let from = now.addingTimeInterval(-20.5 * 86_400)
        let to = now.addingTimeInterval(-19.5 * 86_400)
        samples = samples.filter { s in !(s.kind == .restingHeartRate && s.start > from && s.start < to) }
        samples.append(sample(.restingHeartRate, 64, daysAgo: 20))
        let cold = ContextEvent(date: berlin.date(byAdding: .day, value: -18, to: now)!, tags: [.feelingIll], mood: 2, text: "")
        let detective = BodyDetective(calendar: berlin)
        let cases = detective.cases(samples: samples, events: [cold], now: now)
        let rhr = try #require(cases.first { $0.deviation.kind == .restingHeartRate })
        #expect(rhr.deviation.direction == .above)
        #expect(rhr.deviation.consecutiveDays == 2)
        #expect(rhr.analogs.count == 5)
        #expect(rhr.analogs.allSatisfy { $0.day < berlin.date(byAdding: .day, value: -3, to: rhr.deviation.day)! })
        #expect(rhr.analogs.first?.followingTags == [.feelingIll])
        let ctx = detective.context(for: rhr, events: [cold], consent: ConsentCategory.defaultConsent, now: now)
        #expect(ctx.facts.first?.value == 64)
        #expect(ctx.events.contains { $0.type == "analog_day" })
    }

    /// In the morning today's steps are low only because the day has just begun: no deviation.
    @Test func runningDayStepsAreNoDeviation() {
        let yesterday = berlin.date(byAdding: .day, value: -1, to: berlin.startOfDay(for: now))!
        var samples = history().filter { !($0.kind == .steps && $0.start >= yesterday) }
        samples.append(sample(.steps, 900, daysAgo: 0, hour: 9))
        samples.append(sample(.steps, 1_200, daysAgo: 1, hour: 12))
        let cases = BodyDetective(calendar: berlin).cases(samples: samples, events: [], now: now)
        #expect(!cases.contains { $0.deviation.kind == .steps })
        let profiles = BodyDetective(calendar: berlin).profiles(from: samples, now: now)
        #expect(profiles.last.map { $0.values[.steps] == nil } == true)
    }

    @Test func calmDataGivesNoCase() {
        #expect(BodyDetective(calendar: berlin).cases(samples: history(), events: [], now: now).isEmpty)
    }
}

@Suite("Experiment lab")
struct ExperimentLabTests {
    let plan = ExperimentPlan(title: "Kaffee nach 14 Uhr", targetKind: .sleepDuration, conditionA: "Kaffee erlaubt",
                              conditionB: "kein Kaffee nach 14 Uhr", blockDays: 3, blocks: 8, washoutDays: 0)

    @Test func scheduleAlternates() {
        let days = ExperimentLab.schedule(plan, start: now, calendar: berlin)
        #expect(days.count == 24)
        #expect(days.prefix(3).allSatisfy { $0.condition == .a })
        #expect(days[3].condition == .b)
        let withWashout = ExperimentPlan(title: "x", targetKind: .steps, conditionA: "a", conditionB: "b", blockDays: 3, blocks: 4, washoutDays: 1)
        #expect(ExperimentLab.schedule(withWashout, start: now, calendar: berlin).count == withWashout.totalDays)
    }

    @Test func evaluatesBlocks() {
        var values: [Date: Double] = [:]
        for day in ExperimentLab.schedule(plan, start: now, calendar: berlin) {
            values[berlin.startOfDay(for: day.date)] = day.condition == .a ? 6.5 * 3_600 : 7.4 * 3_600
        }
        let result = ExperimentLab.evaluate(plan, start: now, values: values, calendar: berlin)
        #expect(result.verdict == .difference)
        #expect(abs(result.difference - 0.9) < 0.001)
        #expect(abs(result.pValue - 2.0 / 70.0) < 0.0001)
        #expect(ExperimentLab.evaluate(plan, start: now, values: [:], calendar: berlin).verdict == .notEnoughData)
    }

    /// The smallest allowed plan can still show a clear difference; four blocks never could (p ≥ 1/3).
    @Test func smallestPlanCanShowADifference() {
        let six = ExperimentPlan(title: "x", targetKind: .sleepDuration, conditionA: "a", conditionB: "b", blockDays: 3,
                                 blocks: 4, washoutDays: 0).sanitized()
        #expect(six.blocks == 6)
        var values: [Date: Double] = [:]
        for day in ExperimentLab.schedule(six, start: now, calendar: berlin) {
            values[berlin.startOfDay(for: day.date)] = day.condition == .a ? 6.5 * 3_600 : 7.4 * 3_600
        }
        let result = ExperimentLab.evaluate(six, start: now, values: values, calendar: berlin)
        #expect(abs(result.pValue - 2.0 / 20.0) < 0.0001)
        #expect(result.verdict == .difference)
        // A three-day block needs two days with data: one value per block is not enough.
        var sparse: [Date: Double] = [:]
        var seen: Set<Int> = []
        for day in ExperimentLab.schedule(six, start: now, calendar: berlin) {
            guard let block = day.block, !seen.contains(block) else { continue }
            seen.insert(block)
            sparse[berlin.startOfDay(for: day.date)] = 7 * 3_600
        }
        #expect(ExperimentLab.evaluate(six, start: now, values: sparse, calendar: berlin).verdict == .notEnoughData)
    }

    @Test func limits() {
        #expect(ExperimentLab.admissibility(of: "Schlafe ich besser mit Magnesium?") != .ok)
        #expect(ExperimentLab.admissibility(of: "Schlafe ich besser ohne Bildschirm nach 22 Uhr?") == .ok)
        #expect(ExperimentLab.admissibility(of: "Bin ich nach Reisen müder?") == .ok)
        let wild = ExperimentPlan(title: "x", targetKind: .bodyMass, conditionA: "a", conditionB: "b", blockDays: 30, blocks: 5, washoutDays: 9)
        let clean = wild.sanitized()
        #expect(clean.blockDays == 7 && clean.blocks == 6 && clean.washoutDays == 2 && clean.targetKind == .sleepDuration)
        #expect(ExperimentLab.requiredDaysPerCondition(sd: 0.5, effect: 0.25) == 63)
    }
}

@Suite("Body biography")
struct BodyBiographyTests {
    /// Sleep and resting pulse move against each other for 60 days.
    func linked() -> [HealthSample] {
        var result: [HealthSample] = []
        for d in 0..<60 {
            let hours: Double = 6 + Double(d % 5) * 0.5
            result.append(sample(.sleepDuration, hours * 3_600, daysAgo: d, hour: 0))
            result.append(sample(.restingHeartRate, 66 - hours * 2, daysAgo: d))
        }
        return result
    }

    @Test func createsAndRechecksCards() throws {
        let cards = BodyBiography.candidates(samples: linked(), existing: [], now: now, calendar: berlin)
        let card = try #require(cards.first { $0.kindA == .sleepDuration && $0.kindB == .restingHeartRate })
        #expect(card.rho == -1)
        #expect(card.strength == .strong)
        #expect(card.statement == "In Nächten mit mehr Schlaf war dein Ruhepuls eher niedriger.")
        #expect(BodyBiography.candidates(samples: linked(), existing: cards, now: now, calendar: berlin).isEmpty)
        let later = berlin.date(byAdding: .day, value: 91, to: now)!
        #expect(BodyBiography.isDue(card, now: later))
        // 90 days later without data the pattern cannot be confirmed and fades.
        let rechecked = BodyBiography.recheck(card, samples: linked(), now: later, calendar: berlin)
        #expect(rechecked.status == .faded)
        let same = BodyBiography.recheck(card, samples: linked(), now: now, calendar: berlin)
        #expect(same.status == .active)
    }
}

@Suite("Two brains")
struct TwoBrainsTests {
    @Test func routing() {
        #expect(BrainRouter.route("Warum war mein Ruhepuls letzte Woche höher?") == .claude)
        #expect(BrainRouter.route("Wie viele Schritte habe ich heute?") == .local)
    }

    @Test func localSentencesAndPreview() {
        let ctx = context([fact("F1", .restingHeartRate, 58, unit: "bpm",
                                baseline: FactBaseline(median: 55, p25: 53, p75: 57, windowDays: 28, n: 28))])
        #expect(LocalSentences.summary(ctx) == ["Ruhepuls: Median 58 bpm, über deinem üblichen Bereich (53–57 bpm)."])
        #expect(LocalSentences.answer("Wie war mein Ruhepuls?", context: ctx) != nil)
        let preview = SendPreview.make(title: "Wochenbericht", context: ctx, consent: [.heart], model: .opus,
                                       systemPrompt: IntelligencePrompts.report(.clinical), expectedOutputTokens: 6_000,
                                       sendBudget: SendBudget(maxSends: 30, used: 2))
        #expect(preview.categoriesWithheld.contains(.sleep))
        #expect(preview.sendsRemaining == 28)
        #expect(preview.factCount == 1)
        #expect(preview.payload.contains("\"F1\""))
    }
}

@Suite("Consultation")
struct ConsultationTests {
    let ctx = context([
        fact("F1", .restingHeartRate, 58, unit: "bpm",
             baseline: FactBaseline(median: 55, p25: 53, p75: 57, windowDays: 28, n: 28)),
    ])

    func json(urgency: String = "none", reply: String = "Dein Ruhepuls ist leicht erhöht. Ich bin kein Arzt.") -> String {
        """
        {"reply":"\(reply)","assessment":[{"text":"Dein Ruhepuls lag bei 58 bpm.","type":"measured","evidence":["F1"]},\
        {"text":"Dein Ruhepuls lag bei 64 bpm.","type":"measured","evidence":["F1"]}],\
        "differentials":[{"name":"Beginnender Infekt","fit":"partial","reasoning":"Ruhepuls über dem Band.",\
        "supporting":["Ruhepuls erhöht"],"against":["kein Fieber berichtet"],"workup":["Temperatur messen"],"evidence":["F1","F9"]},\
        {"name":"Übertraining","fit":"strong","reasoning":"","supporting":[],"against":[],"workup":[],"evidence":[]}],\
        "recommendations":[{"area":"training","priority":"high","text":"Zwei Tage nur locker trainieren.","evidence":["F1"]},\
        {"area":"treatment","priority":"low","text":"Den Betablocker solltest du reduzieren.","evidence":[]}],\
        "anamnesisQuestions":["Hast du Fieber?","Ich bin kein Arzt."],"urgency":"\(urgency)","urgencyReason":"","memory":"Ruhepuls erhöht."}
        """
    }

    @Test func validatesAndSortsDifferentials() throws {
        let result = try ResponseValidator(context: ctx).validateConsultation(json: json(), userText: "Ich bin müde.")
        let reply = result.reply
        #expect(reply.reply == "Dein Ruhepuls ist leicht erhöht.")
        #expect(reply.assessment.map(\.text) == ["Dein Ruhepuls lag bei 58 bpm."])
        #expect(reply.differentials.map(\.name) == ["Übertraining", "Beginnender Infekt"])
        #expect(reply.differentials.first?.fit == .strong)
        #expect(reply.differentials.last?.evidence == ["F1"])
        #expect(reply.recommendations.count == 2)
        #expect(result.flagged["Den Betablocker solltest du reduzieren."] != nil)
        #expect(reply.anamnesisQuestions == ["Hast du Fieber?"])
        #expect(reply.urgency == ConsultationUrgency.none)
    }

    @Test func emergencyAndThresholdsRaiseUrgency() throws {
        let emergency = try ResponseValidator(context: ctx).validateConsultation(json: json(), userText: "Ich habe Brustschmerzen beim Treppensteigen")
        #expect(emergency.reply.urgency == .today)
        #expect(emergency.reply.urgencyReason == SafetyRules.consultationEmergencyNotice)
        let high = context([fact("F1", .restingHeartRate, 105, unit: "bpm", n: 7)])
        let threshold = try ResponseValidator(context: high).validateConsultation(json: json(), userText: "")
        #expect(threshold.reply.urgency == .soon)
        let claudeHigher = try ResponseValidator(context: high).validateConsultation(json: json(urgency: "emergency"), userText: "")
        #expect(claudeHigher.reply.urgency == .emergency)
    }

    @Test func openingCarriesContextMemoryAndMessage() {
        let text = ConsultationBuilder.opening(context: ctx, memory: ["Knie links seit März.", " "], message: "")
        #expect(text.contains("\"F1\""))
        #expect(text.contains("1. Knie links seit März."))
        #expect(text.contains(ConsultationBuilder.startMessage))
        let merged = ConsultationBuilder.merged(ctx, facts: [fact("Q1", .steps, 9_000, unit: "count"), fact("F1", .steps, 1, unit: "count")],
                                                correlations: [], events: [])
        #expect(merged.facts.map(\.id) == ["F1", "Q1"])
    }

    @Test func promptsFollowTheMode() {
        let clinical = IntelligencePrompts.report(.clinical)
        #expect(clinical.contains("Differenzialdiagnosen"))
        #expect(clinical.contains("Notruf 112"))
        #expect(!IntelligencePrompts.report(.descriptive).contains("Differenzialdiagnosen"))
        #expect(IntelligencePrompts.consultation.contains("anamnesisQuestions"))
        #expect(IntelligencePrompts.version == 4)
    }
}

@Suite("Analyse inputs")
struct AnalyseInputTests {
    /// Every kind reaches Claude through a consent category, or is deliberately never shared.
    @Test func everyKindHasACategory() {
        for kind in SampleKind.allCases where !ConsentCategory.neverShared.contains(kind) {
            #expect(ConsentCategory.category(for: kind) != nil, "\(kind.rawValue) has no consent category")
        }
        #expect(ConsentCategory.category(for: .skinTemperature) == .body)
    }

    /// The same SpO₂ reading from ring and Apple Health counts once.
    @Test func lowSpO2ReadingsAreNotDoubled() throws {
        var samples = history()
        for d in 0..<3 {
            let health = sample(.oxygenSaturation, 88, daysAgo: d, hour: 3)
            let ring = HealthSample(profileID: health.profileID, kind: .oxygenSaturation, value: 88, unit: health.unit,
                                    start: health.start, end: health.end, timeZoneIdentifier: "Europe/Berlin", source: .colmiRing,
                                    deviceID: "ring-1", originalSampleID: "ring-spo2-\(d)", importedAt: now, quality: .valid,
                                    method: .deviceHistory, originDetail: "Colmi R03")
            samples += [health, ring]
        }
        let ctx = ContextBuilder(calendar: berlin).build(samples: samples, events: [], kind: .weekly, now: now,
                                                         consent: [.spo2], profile: .empty)
        let low = try #require(ctx.facts.first { $0.kind == "spo2_low_readings" })
        #expect(low.value == 3)
    }

    /// Question tools leave out today's unfinished steps.
    @Test func questionToolsSkipTheRunningDay() {
        let tools = QuestionTools(samples: history(), events: [], consent: [.activity], calendar: berlin, now: now)
        let days = tools.daily(.steps, from: berlin.date(byAdding: .day, value: -3, to: berlin.startOfDay(for: now))!, to: now.addingTimeInterval(86_400))
        #expect(!days.keys.contains(berlin.startOfDay(for: now)))
        #expect(days.count == 3)
    }
}
