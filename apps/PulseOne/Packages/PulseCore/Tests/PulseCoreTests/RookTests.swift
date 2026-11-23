import Foundation
import Testing
@testable import PulseCore

// ROOK (Auftrag 04): interpretation → direction → action, "Warum?", corrections with revision, the strict
// check of Claude's answers and the guard against routine sentences.

private let rookCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
    return calendar
}()

private let rookNow: Date = rookCalendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 7, minute: 30)) ?? .distantPast
private let rookProfile = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA") ?? UUID()

private func demo(_ demoCase: RookDemo.Case) -> RookStatement {
    RookDemo.statement(demoCase, now: rookNow, profileID: rookProfile, calendar: rookCalendar)
}

private func validate(_ json: String, _ context: HealthAnalysisContext, mode: SafetyMode = .clinical) throws -> RookStatement {
    try RookValidator.statement(json: json, context: context, mode: mode, now: rookNow, subjectID: rookProfile,
                                calendar: rookCalendar)
}

private func reply(interpretation: String, observation: String = "", direction: String = "stable",
                   evidence: [String] = ["F1"]) -> String {
    struct Body: Encodable {
        let headline: String, interpretation: String, observation: String, direction: String
        let action: [String: String], evidence: [String], alternatives: [[String: String]], uncertainty: String
        let recheckHours: Int
    }
    let body = Body(headline: "Kurz gesagt", interpretation: interpretation, observation: observation, direction: direction,
                    action: ["kind": "startWorkout", "title": "Los geht's"], evidence: evidence, alternatives: [],
                    uncertainty: "", recheckHours: 0)
    return String(data: (try? JSONEncoder().encode(body)) ?? Data(), encoding: .utf8) ?? ""
}

private func fact(_ value: Double, n: Int, median: Double) -> AnalysisFact {
    AnalysisFact(id: "F1", kind: SampleKind.restingHeartRate.rawValue, title: "Ruhepuls", stat: "mean", value: value, unit: "bpm",
                 period: "letzte 7 Tage", n: n, coverage: 1,
                 baseline: FactBaseline(median: median, p25: median - 1, p75: median + 1, windowDays: 28, n: 26),
                 source: "ring", quality: "ok")
}

private func context(_ facts: [AnalysisFact]) -> HealthAnalysisContext {
    HealthAnalysisContext(analysisType: "checkin", generatedAt: "2026-11-23T07:30:00+01:00",
                          period: AnalysisPeriod(start: "2026-11-23", end: "2026-11-23", timezone: "Europe/Berlin"),
                          comparisonPeriod: nil, profile: .empty, consentedCategories: [], facts: facts,
                          correlations: [], events: [], dataGaps: [])
}

/// Visible text of a statement: headline, interpretation, action and every cue.
private func visibleText(_ statement: RookStatement) -> String {
    ([statement.headline, statement.insight.interpretation, statement.insight.action?.title ?? ""]
        + statement.cues.map(\.text)).joined(separator: " ")
}

@Suite("ROOK demo cases")
struct RookDemoTests {
    @Test func positiveDevelopmentReadsAsImproving() {
        let statement = demo(.positive)
        #expect(statement.source == .demo)
        #expect(statement.insight.direction == .improving)
        #expect(statement.headline == "Wieder im Rhythmus")
        #expect(statement.insight.interpretation.hasPrefix("Dein Rhythmus wird wieder stabiler."))
        #expect(RookTextGuard.sentences(statement.insight.interpretation).count <= 3)
        // No numbers in the visible text; they sit behind "Warum?".
        #expect(statement.insight.interpretation.rangeOfCharacter(from: .decimalDigits) == nil)
        #expect(statement.insight.action?.kind == .startWorkout)
        #expect(!statement.insight.evidence.isEmpty)
        #expect(statement.insight.evidence.contains { $0.kind == .restingHeartRate && $0.shownValue == "53 bpm" })
        #expect(statement.insight.recheckAt != nil)
        #expect(statement.cues.first?.anchor != nil)
        #expect(!statement.why.calculation.isEmpty)
        #expect(!statement.why.comparison.isEmpty)
    }

    @Test func clearChangeAdvisesToHaveItChecked() {
        let statement = demo(.clarify)
        #expect(statement.insight.direction == .clarify)
        #expect(statement.insight.interpretation.hasPrefix("Diese Veränderung würde ich abklären lassen."))
        #expect(statement.insight.action?.kind == .seeDoctor)
        #expect(statement.insight.priority > demo(.positive).insight.priority)
        #expect(RookTextGuard.sentences(statement.insight.interpretation).count <= 3)
        #expect(!statement.why.alternatives.isEmpty)
        #expect(statement.why.alternatives.allSatisfy { !$0.note.contains("%") })
        #expect(statement.checkInMessage.urgency == .clarify)
    }

    @Test func demoTextsPassTheGuard() {
        for demoCase in RookDemo.Case.allCases {
            let statement = demo(demoCase)
            #expect(RookTextGuard.violations(in: visibleText(statement)).isEmpty)
            #expect(RookTextGuard.violations(in: RookDemo.sampleReply(demoCase)).isEmpty)
        }
    }
}

@Suite("ROOK without a personal basis")
struct RookGreetingTests {
    @Test func noFreshNightGivesAGreetingAndAnOffer() {
        let statement = RookLocal.greeting(at: rookNow, slot: .morning, subjectID: rookProfile, calendar: rookCalendar)
        #expect(statement.headline == "Guten Morgen")
        #expect(statement.insight.action?.kind == .askUser)
        #expect(statement.insight.evidence.isEmpty)
        #expect(statement.insight.interpretation.rangeOfCharacter(from: .decimalDigits) == nil)
        #expect(RookTextGuard.violations(in: visibleText(statement)).isEmpty)
    }

    @Test func firstNightIsComparedWithExperienceValues() {
        let today = rookCalendar.startOfDay(for: rookNow)
        let input = InsightInput(profileID: rookProfile, now: rookNow,
                                 nights: [NightPoint(date: today, restingHeartRate: 52, hrv: 40, sleepHours: 7.3)],
                                 origin: "Ring", hrvMethod: "Ring-HRV",
                                 newestSample: today.addingTimeInterval(6 * 3_600), lastSync: nil)
        let insight = InsightEngine.build(input, calendar: rookCalendar)
        #expect(insight.insightCase == .learning)
        let statement = RookLocal.statement(from: insight, slot: .morning, calendar: rookCalendar)
        #expect(statement.insight.direction == .stable)
        #expect(statement.insight.action?.kind == .startWorkout)
        #expect(statement.insight.evidence.count == 3)
        #expect(statement.insight.evidence.first?.comparison?.hasPrefix("Erfahrungswert") == true)
        #expect(RookTextGuard.violations(in: visibleText(statement)).isEmpty)
    }

    @Test func localCheckInTextsAreClean() {
        let empty = LocalCheckIn.compose(slot: .midday, context: context([]), name: RookLocal.name)
        #expect(RookTextGuard.violations(in: empty.headline + " " + empty.text).isEmpty)
        let stale = CheckInPolicy.staleMessage(newestSample: nil, now: rookNow, calendar: rookCalendar)
        #expect(stale.headline == "Guten Morgen")
        #expect(stale.markers.isEmpty)
        #expect(RookTextGuard.violations(in: stale.headline + " " + stale.text).isEmpty)
    }
}

@Suite("ROOK corrections")
struct RookCorrectionTests {
    @Test func illnessRevisesTheAdviceAndKeepsTheOldText() throws {
        let original = demo(.positive)
        let revised = RookReviser.apply(.sick, to: original, at: rookNow.addingTimeInterval(60))
        #expect(revised.insight.interpretation != original.insight.interpretation)
        #expect(revised.insight.revisions.count == 1)
        #expect(revised.insight.revisions.first?.interpretation == original.insight.interpretation)
        #expect(revised.insight.corrections.first?.text == "Ich bin krank")
        // Measurements never change.
        #expect(revised.insight.evidence == original.insight.evidence)
        #expect(revised.insight.observation == original.insight.observation)
        // A gentle unit that can still be started (M1 walkthrough starts it next).
        let action = try #require(revised.insight.action)
        #expect(action.kind == .startWorkout)
        #expect(RookWorkoutRequest(payload: action.payload) == RookWorkoutRequest(minutes: 10, intensity: "easy"))
        #expect(revised.why.events.count == original.why.events.count + 1)
        #expect(revised.cues.allSatisfy { $0.anchor == nil })
        #expect(revised.spokenText == revised.insight.interpretation)
    }

    @Test func illnessWithAClearChangeKeepsTheReferral() {
        let revised = RookReviser.apply(.sick, to: demo(.clarify), at: rookNow)
        #expect(revised.insight.action?.kind == .seeDoctor)
        #expect(revised.insight.direction == .clarify)
    }

    @Test func otherQuickAnswers() {
        let original = demo(.positive)
        let ten = RookReviser.apply(.onlyTenMinutes, to: original, at: rookNow)
        #expect(RookWorkoutRequest(payload: ten.insight.action?.payload).minutes == 10)
        let lighter = RookReviser.apply(.lighter, to: original, at: rookNow)
        #expect(RookWorkoutRequest(payload: lighter.insight.action?.payload).intensity == "easy")
        #expect(RookReviser.apply(.doesNotFit, to: original, at: rookNow).insight.action?.kind == .askUser)
        #expect(RookReviser.apply(.why, to: original, at: rookNow) == original)
        for feedback in RookFeedback.allCases {
            for demoCase in RookDemo.Case.allCases {
                let revised = RookReviser.apply(feedback, to: demo(demoCase), at: rookNow)
                #expect(RookTextGuard.sentences(revised.insight.interpretation).count <= 3)
                #expect(RookTextGuard.violations(in: visibleText(revised)).isEmpty)
            }
        }
    }

    @Test func typedMessagesMatchQuickAnswers() {
        #expect(RookFeedback.match("Ich glaube, ich bin krank") == .sick)
        #expect(RookFeedback.match("heute nur 10 Minuten bitte") == .onlyTenMinutes)
        #expect(RookFeedback.match("Geht das leichter?") == .lighter)
        #expect(RookFeedback.match("Das passt nicht zu mir") == .doesNotFit)
        #expect(RookFeedback.match("Warum sagst du das?") == .why)
        #expect(RookFeedback.match("Wie war meine Woche?") == nil)
    }

    @Test func workoutPayloadRoundTrip() {
        let request = RookWorkoutRequest(minutes: 20, intensity: "easy")
        #expect(request.payload == "minutes=20;intensity=easy")
        #expect(RookWorkoutRequest(payload: request.payload) == request)
        #expect(RookWorkoutRequest(payload: nil) == RookWorkoutRequest())
    }
}

@Suite("ROOK answer check")
struct RookValidatorTests {
    @Test func sampleAnswersBecomeStatements() throws {
        let positive = try validate(RookDemo.sampleReply(.positive), RookDemo.sampleContext(.positive))
        #expect(positive.source == .claude)
        #expect(positive.insight.direction == .improving)
        #expect(positive.insight.evidence.count == 2)
        #expect(positive.insight.evidence.first?.shownValue == "53 bpm")
        #expect(positive.insight.recheckAt == rookNow.addingTimeInterval(24 * 3_600))
        #expect(positive.why.comparison.contains("26.10."))

        let clarify = try validate(RookDemo.sampleReply(.clarify), RookDemo.sampleContext(.clarify))
        #expect(clarify.insight.direction == .clarify)
        #expect(clarify.insight.action?.kind == .seeDoctor)
        #expect(clarify.why.alternatives.map(\.fit) == [.partial, .weak])
    }

    @Test func inventedNumbersAreRejected() {
        let json = reply(interpretation: "Alles ruhig.", observation: "Ruhepuls 61 bpm.")
        #expect(throws: RookValidator.Failure.invented("61")) {
            try validate(json, context([fact(53, n: 1, median: 58)]))
        }
    }

    @Test func adviceDurationsAreNotMeasurements() throws {
        let json = reply(interpretation: "Heute locker. Geh 20 Minuten raus und sei um 22 Uhr im Bett.")
        let statement = try validate(json, context([fact(53, n: 1, median: 58)]))
        #expect(statement.insight.interpretation.contains("20 Minuten"))
    }

    @Test func routineSentencesAndGuessedPercentagesAreRemoved() throws {
        let json = reply(interpretation: "Ich bin kein Arzt. Dein Puls ist ruhig (etwa 75 %). Die Basislinie fehlt noch.")
        let statement = try validate(json, context([fact(53, n: 1, median: 58)]))
        #expect(statement.insight.interpretation == "Dein Puls ist ruhig.")
        #expect(RookTextGuard.violations(in: visibleText(statement)).isEmpty)
    }

    @Test func onlyRoutineSentencesIsNoAnswer() {
        #expect(throws: RookValidator.Failure.empty) {
            try validate(reply(interpretation: "Ich lerne dein Normal noch."), context([]))
        }
        #expect(throws: RookValidator.Failure.unreadable) { try validate("kein json", context([])) }
    }

    @Test func atMostThreeSentencesAndUnknownIDsDropped() throws {
        let json = reply(interpretation: "Eins. Zwei. Drei. Vier.", evidence: ["F1", "F9"])
        let statement = try validate(json, context([fact(53, n: 1, median: 58)]))
        #expect(RookTextGuard.sentences(statement.insight.interpretation).count == 3)
        #expect(statement.insight.evidence.count == 1)
    }

    @Test func fixedThresholdsRaiseTheDirection() throws {
        // Resting pulse over 100 for a week: whatever Claude wrote, ROOK advises to have it checked.
        let high = try validate(reply(interpretation: "Alles gut, weiter so."), context([fact(105, n: 7, median: 60)]))
        #expect(high.insight.direction == .clarify)
        #expect(high.insight.action?.kind == .seeDoctor)
        #expect(high.insight.interpretation.hasPrefix("Das würde ich abklären lassen."))
        // Clearly above the own band for a week: at least "im Blick".
        let raised = try validate(reply(interpretation: "Alles gut."), context([fact(69, n: 7, median: 57)]))
        #expect(raised.insight.direction == .watch)
        #expect(!raised.why.uncertainty.isEmpty)
    }

    @Test func withoutFactsThereIsNoDiagnosisOfTheDay() throws {
        let statement = try validate(reply(interpretation: "Heute bist du angeschlagen.", direction: "strained", evidence: []),
                                     context([]))
        #expect(statement.insight.direction == .stable)
    }
}

@Suite("ROOK text guard")
struct RookTextGuardTests {
    @Test func promptsContainNoRoutineSentences() {
        for mode in SafetyMode.allCases {
            for slot in CheckInSlot.allCases {
                #expect(RookTextGuard.violations(in: RookPrompts.checkIn(slot: slot, mode: mode), visible: false).isEmpty)
            }
            #expect(RookTextGuard.violations(in: RookPrompts.conversation(mode: mode), visible: false).isEmpty)
            #expect(RookTextGuard.violations(in: IntelligencePrompts.rules(mode), visible: false).isEmpty)
        }
        #expect(RookPrompts.version == 3)
    }

    @Test func schemaRequiresAllFields() {
        let required = RookPrompts.schema["required"]?.arrayValue?.compactMap(\.stringValue) ?? []
        #expect(Set(required) == ["headline", "interpretation", "observation", "direction", "action", "evidence",
                                  "alternatives", "uncertainty", "recheckHours"])
    }

    @Test func cleanedDropsOnlyTheBadSentences() {
        let text = "Starke Nacht. PULSE ONE lernt noch deinen Bereich. Heute darfst du Gas geben."
        #expect(RookTextGuard.cleaned(text) == "Starke Nacht. Heute darfst du Gas geben.")
        #expect(RookTextGuard.violations(in: "Kann ich nicht lesen.") == ["nicht lesen"])
        #expect(RookTextGuard.violations(in: "Die Synchronisierung lief.").contains("synchronisier"))
        #expect(RookTextGuard.violations(in: "Die Synchronisierung lief.", visible: false).isEmpty)
    }
}

@Suite("ROOK free conversation (speech)")
struct RookSpeechTests {
    @Test("Streamed text becomes sentences as soon as each one is finished")
    func sentencesWhileStreaming() {
        var buffer = RookSentenceBuffer()
        #expect(buffer.append("Klingt nach einer zä").isEmpty)
        #expect(buffer.append("hen Nacht.").isEmpty) // waits for the next word before closing the sentence
        #expect(buffer.append(" Wie") == ["Klingt nach einer zähen Nacht."])
        #expect(buffer.append(" fühlst du dich? ").isEmpty)
        #expect(buffer.finish() == "Wie fühlst du dich?")
    }

    @Test("Abbreviations, dates and decimals do not end a sentence")
    func noFalseEnds() {
        var buffer = RookSentenceBuffer()
        let out = buffer.append("Geh z. B. zehn Minuten raus, am 26.10. war es ähnlich. Puls 7.5 höher? Ja. ")
            + buffer.append("Gut")
        #expect(out == ["Geh z. B. zehn Minuten raus, am 26.10. war es ähnlich.", "Puls 7.5 höher?", "Ja."])
        #expect(buffer.finish() == "Gut")
    }

    @Test("Spoken answers lose Markdown, list marks, guessed percentages and routine sentences")
    func speakable() {
        #expect(RookSpeech.speakable("- **Heute** locker bleiben.", mode: .clinical) == "Heute locker bleiben.")
        #expect(RookSpeech.speakable("Die Basislinie fehlt noch.", mode: .clinical) == nil)
        #expect(RookSpeech.speakable("   ", mode: .clinical) == nil)
        let percent = RookSpeech.speakable("Mit etwa 70 % ist es ein Infekt.", mode: .clinical) ?? ""
        #expect(!percent.contains("70"))
    }

    @Test("History alternates, starts with the person and ends with the new message")
    func messages() {
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        let history = [RookTurn(at: at, role: .rook, text: "Hallo"),
                       RookTurn(at: at, role: .person, text: "Bin müde"),
                       RookTurn(at: at, role: .rook, text: "Kurze Nacht?"),
                       RookTurn(at: at, role: .person, text: "Ja")]
        let messages = RookSpeech.messages(history: history, message: "Was soll ich heute machen?")
        let roles = messages.compactMap { message -> String? in
            if case .string(let role)? = message["role"] { return role }
            return nil
        }
        #expect(roles == ["user", "assistant", "user"])
        #expect(messages.last?["content"]?.encodedString().contains("Ja\\nWas soll ich heute machen?") == true)
        #expect(RookSpeech.messages(history: [], message: "Hi").count == 1)
    }

    @Test("The spoken prompt is free of routine phrases and carries today's figures")
    func prompt() {
        let context = RookDemo.sampleContext(.positive)
        let system = RookSpeech.system(mode: .clinical, context: context, current: nil)
        #expect(RookTextGuard.violations(in: system, visible: false).isEmpty)
        #expect(system.contains("Notruf 112"))
        #expect(system.contains(context.compactJSON()))
    }

    @Test("Server-sent events: text deltas, usage and stop reason")
    func streamParser() {
        let start = #"data: {"type":"message_start","message":{"id":"m","model":"claude-sonnet-5-5","usage":{"input_tokens":1200,"output_tokens":1,"cache_read_input_tokens":800}}}"#
        #expect(AnthropicStreamParser.event(fromLine: start)
                == .started(model: "claude-sonnet-5-5", usage: TokenUsage(inputTokens: 1200, outputTokens: 1, cacheReadInputTokens: 800)))
        let delta = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hallo"}}"#
        #expect(AnthropicStreamParser.event(fromLine: delta) == .text("Hallo"))
        let stop = #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":42}}"#
        #expect(AnthropicStreamParser.event(fromLine: stop) == .finished(stopReason: "end_turn", outputTokens: 42))
        #expect(AnthropicStreamParser.event(fromLine: "event: ping") == nil)
        #expect(AnthropicStreamParser.event(fromLine: #"data: {"type":"ping"}"#) == nil)
        let error = #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#
        #expect(AnthropicStreamParser.event(fromLine: error) == .failed("Overloaded"))
    }

    @Test("A streamed request asks for a stream and a small output cap")
    func streamingBody() {
        let body = AnthropicAPI.streaming(AnthropicAPI.body(model: .sonnet, system: "s", messages: [], schema: nil, effort: "low"),
                                          maxTokens: RookSpeech.maxOutputTokens)
        #expect(body["stream"] == .bool(true))
        #expect(body["max_tokens"] == .number(Double(RookSpeech.maxOutputTokens)))
    }
}
