import Foundation
import Observation
import PulseCore
import SwiftData

/// The one ROOK of the app: today's statement and the conversation, shared by the dashboard card (03) and the
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

    /// Builds today's statement: a demo case in its test scenario, otherwise the newest valid stored statement
    /// (Claude's check-in or a corrected one) or ROOK's local reading of the stored nights.
    func load(modelContext: ModelContext, owner: UUID) {
        let now = now
        if LaunchOptions.current.usesTestScenario, let scenario = LaunchOptions.current.scenario,
           let demo = RookDemo.Case(rawValue: scenario) {
            if current?.source != .demo {
                current = RookDemo.statement(demo, now: now, profileID: owner, calendar: calendar)
            }
            return
        }
        let snapshot = RookMemory.load()
        turns = snapshot.turns
        if let stored = RookMemory.latestValid(at: now, subjectID: owner) {
            current = stored
            return
        }
        let input = InsightInputBuilder.make(context: modelContext, owner: owner, now: now, calendar: calendar)
        current = RookLocal.statement(from: InsightEngine.build(input, calendar: calendar), subjectID: owner, calendar: calendar)
    }

    /// A quick answer below the statement. Local, immediate, no network; the old text stays as a revision.
    func apply(_ feedback: RookFeedback) {
        guard let statement = current, feedback != .why else { return }
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
