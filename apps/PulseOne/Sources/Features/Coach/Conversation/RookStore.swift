import Foundation
import Observation
import PulseCore
import SwiftData

/// The one ROOK of the app: the reading of the moment (fresh at every opening) and the conversation, shared by the dashboard card (03) and the
/// Coach tab, so a correction made in one place shows in the other. Corrections are applied locally and at
/// once; what the person says or types goes to Claude as a free conversation (standing permission of the check-ins,
/// same budget and checks, decided by 00 and the owner on 2026-11-23).
@MainActor
@Observable
final class RookStore {
    static let shared = RookStore()

    private(set) var current: RookStatement?
    private(set) var turns: [RookTurn] = []
    private(set) var isThinking = false
    /// Why the last question stayed on the iPhone ("kein Claude-Schlüssel"), or nil.
    private(set) var localReason: String?

    @ObservationIgnored private let engine = IntelligenceEngine()
    @ObservationIgnored private let calendar = Calendar.current

    /// The app clock (team 03 patch): fixed in test scenarios, real in the M1 walkthrough, whose night is
    /// stored on the real day; with the fixed time ROOK found no last night there and showed no evidence.
    var now: Date { TimelineClock.now }

    /// True while Claude's wording of the moment streams in (the orb thinks, the card stays usable).
    private(set) var isUpdating = false
    /// Raised by every correction, so a reading still streaming in never overwrites it.
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var lastRefresh: Date?
    /// Counts every new assessment shown (local or Claude's), also when the text happens to be the same; the
    /// walkthrough (06, step 17) checks that reopening the app raises it.
    private(set) var generation = 0

    /// Claude words the moment at most every ten minutes and at most twelve times a day (about 1 $ a month with Sonnet).
    static let momentInterval: TimeInterval = 600
    static let dailyMomentCap = 12

    /// ROOK at every opening of the app (owner, 2026-11-25): a fresh reading of how it is going right now, from the
    /// current values. The local reading shows at once; Claude's wording streams in after it when the last one is
    /// older than ten minutes. Corrections made today ("Ich bin krank") stay applied. Demo scenarios show their case.
    func refresh(modelContext: ModelContext, owner: UUID, profile: UserProfile) async {
        configure(modelContext: modelContext, owner: owner, profile: profile)
        let now = now
        // Dashboard and Coach tab ask together when the app opens; one reading is enough. Wall time, not the app
        // clock: the clock stands still in test scenarios, and a reopening two seconds later must look again.
        let wall = Date()
        if let lastRefresh, current != nil, abs(wall.timeIntervalSince(lastRefresh)) < 1.5 { return }
        guard !isUpdating else { return }
        lastRefresh = wall
        if LaunchOptions.current.usesTestScenario, let scenario = LaunchOptions.current.scenario,
           let demo = RookDemo.Case(rawValue: scenario) {
            if current?.source != .demo {
                current = RookDemo.statement(demo, now: now, profileID: owner, calendar: calendar)
            }
            shown()
            return
        }
        turns = RookMemory.load().turns

        let since = now.addingTimeInterval(-Double(RookMoment.historyDays) * 86_400)
        let samples = SampleReader(context: modelContext).samples(RookMoment.sampleKinds, since: since, profileID: owner)
        let moment = RookMoment.build(samples: samples, now: now, calendar: calendar)
        let input = InsightInputBuilder.make(context: modelContext, owner: owner, now: now, calendar: calendar)
        var local = RookNow.statement(moment: moment, night: InsightEngine.build(input, calendar: calendar),
                                      subjectID: owner, calendar: calendar)
        let corrections = RookMemory.corrections(on: now, calendar: calendar)
        if let last = corrections.last {
            local = RookReviser.apply(last.feedback, to: local, at: last.at)
        }
        if corrections.isEmpty, let recent = RookMemory.recentClaude(within: Self.momentInterval, at: now, subjectID: owner) {
            show(recent)
            return
        }
        show(local)

        guard corrections.isEmpty, !RookNow.needsAttention(local),
              blocker(modelContext: modelContext) == nil,
              engine.momentCount(since: calendar.startOfDay(for: now), modelContext: modelContext) < Self.dailyMomentCap
        else { return }
        let started = revision
        isUpdating = true
        let answer = await engine.streamRookMoment(moment: moment, local: local, modelContext: modelContext) { statement in
            if revision == started { current = statement }
        }
        isUpdating = false
        guard revision == started else { return }
        if let answer {
            current = answer
            RookMemory.record(answer)
            shown()
        }
    }

    /// A new assessment is on screen.
    private func shown() {
        generation += 1
        QAProbe.note("rook.assessment", "\(generation)")
    }

    /// Shows a new assessment. When it reads exactly like the one on screen (same words, action and stamp minute),
    /// the card keeps its statement so nothing on screen is rebuilt; it still counts as a new look.
    private func show(_ statement: RookStatement) {
        if let current, current.source == statement.source, current.headline == statement.headline,
           current.insight.interpretation == statement.insight.interpretation,
           current.insight.action == statement.insight.action,
           calendar.isDate(current.insight.createdAt, equalTo: statement.insight.createdAt, toGranularity: .minute) {
            shown()
            return
        }
        current = statement
        shown()
    }

    /// The person takes up a step that needs no other screen (breathe, wind down, bed); ROOK confirms it.
    func commit(_ action: CoachAction) {
        guard let statement = current else { return }
        revision += 1
        let at = now
        let confirmed = RookReviser.commit(action, to: statement, at: at)
        current = confirmed
        let exchange = [RookTurn(at: at, role: .person, text: action.title),
                        RookTurn(at: at, role: .rook, text: confirmed.insight.interpretation, statement: confirmed)]
        turns.append(contentsOf: exchange)
        RookMemory.record(confirmed)
        RookMemory.append(exchange)
    }

    /// A quick answer below the statement. Local, immediate, no network; the old text stays as a revision.
    func apply(_ feedback: RookFeedback) {
        guard let statement = current, feedback != .why else { return }
        revision += 1
        let at = now
        let revised = RookReviser.apply(feedback, to: statement, at: at)
        current = revised
        let exchange = [RookTurn(at: at, role: .person, text: feedback.title),
                        RookTurn(at: at, role: .rook, text: revised.insight.interpretation, statement: revised)]
        turns.append(contentsOf: exchange)
        RookMemory.record(revised)
        RookMemory.append(exchange)
    }

    /// Where the conversation takes its figures from; set by every screen that shows ROOK, so 05's voice channel can
    /// call `talk` without knowing SwiftData.
    @ObservationIgnored private var source: (modelContext: ModelContext, owner: UUID, profile: UserProfile)?

    /// ROOK's answer while it streams in, sentence by sentence (empty when he is not talking).
    private(set) var streamingText = ""

    func configure(modelContext: ModelContext, owner: UUID, profile: UserProfile) {
        source = (modelContext, owner, profile)
    }

    /// A typed message from the Coach tab.
    func send(_ text: String, modelContext: ModelContext, owner: UUID, profile: UserProfile) async {
        configure(modelContext: modelContext, owner: owner, profile: profile)
        await talk(text)
    }

    /// For 05's voice channel: what the person said (transcribed), ROOK's whole answer back.
    func reply(to transcript: String) async -> String {
        await talk(transcript)
    }

    /// One thing the person said or typed: a free conversation, like with a person. Corrections in words
    /// ("ich bin krank", "heute nur zehn Minuten") change today's plan at once on the iPhone, and ROOK still answers
    /// in his own words through Claude (standing permission of the check-ins, same budget, in the history with its
    /// cost). Each finished sentence goes to `onSentence` right away, so speech output can start after the first one.
    /// Spoken and typed turns share one memory.
    @discardableResult
    func talk(_ text: String, onSentence: (String) -> Void = { _ in }) async -> String {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isThinking else { return "" }
        let at = now
        let history = turns
        let question = RookTurn(at: at, role: .person, text: message)
        turns.append(question)

        var revised: RookStatement?
        if let feedback = RookFeedback.match(message), feedback != .why, let statement = current {
            revision += 1
            let updated = RookReviser.apply(feedback, to: statement, at: at)
            current = updated
            RookMemory.record(updated)
            revised = updated
        }

        var answer: String?
        if SafetyRules.isEmergency(message) {
            // Acute warning signs: the emergency advice comes first and at once, without waiting for the network.
            answer = SafetyRules.emergencyReply
            onSentence(SafetyRules.emergencyReply)
        } else if let source {
            localReason = blocker(modelContext: source.modelContext)
            if localReason == nil {
                isThinking = true
                streamingText = ""
                let context = engine.reportContext(.daily, modelContext: source.modelContext, owner: source.owner,
                                                   profile: source.profile)
                answer = await engine.streamRookSpeech(message: message, history: history, current: current, context: context,
                                                       modelContext: source.modelContext) { sentence in
                    streamingText += (streamingText.isEmpty ? "" : " ") + sentence
                    onSentence(sentence)
                }
                isThinking = false
                streamingText = ""
                if answer == nil { localReason = "Claude hat gerade nicht sauber geantwortet" }
            }
        } else {
            localReason = "ROOK ist noch nicht bereit"
        }
        if answer == nil {
            let local = revised?.insight.interpretation ?? localAnswer(reason: localReason ?? "")
            onSentence(local)
            answer = local
        }
        let text = answer ?? ""
        let reply = RookTurn(at: now, role: .rook, text: text, statement: revised)
        turns.append(reply)
        RookMemory.append([question, reply])
        return text
    }

    private func blocker(modelContext: ModelContext) -> String? {
        if LaunchOptions.current.usesTestScenario { return "Testansicht" }
        if !CheckInSettings().useClaude { return "Senden an Claude ist ausgeschaltet" }
        return engine.checkInBlocker(modelContext: modelContext)
    }

    /// Without Claude ROOK still answers, briefly and without excuses about data.
    private func localAnswer(reason: String) -> String {
        "Für ein richtiges Gespräch frage ich Claude, und das geht gerade nicht: \(reason). "
            + "Meine Deutung von heute steht oben, unter „Warum?“ findest du alles, worauf sie beruht."
    }
}
