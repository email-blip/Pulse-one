import Foundation
import Observation
import PulseCore
import SwiftData

/// The one ROOK of the app: today's statement and the conversation, shared by the dashboard card (03) and the
/// Coach tab, so a correction made in one place shows in the other. Corrections are applied locally and at
/// once; only typed questions go to Claude (standing permission of the check-ins, same budget and checks).
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

    var now: Date { LaunchOptions.current.usesTestScenario ? TestScenario.fixedTime : .now }

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

    /// A typed message. Quick answers in words ("ich bin krank") are handled locally; everything else goes to
    /// Claude when the standing permission, key and budget allow it.
    func send(_ text: String, modelContext: ModelContext, owner: UUID, profile: UserProfile) async {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isThinking else { return }
        if let feedback = RookFeedback.match(message), feedback != .why {
            apply(feedback)
            return
        }
        let at = now
        let question = RookTurn(at: at, role: .person, text: message)
        turns.append(question)
        localReason = blocker(modelContext: modelContext)
        let answer: RookTurn
        if localReason == nil {
            isThinking = true
            let context = engine.reportContext(.daily, modelContext: modelContext, owner: owner, profile: profile)
            let result = await engine.runRookConversation(message: message, history: Array(turns.dropLast()), current: current,
                                                          context: context, subjectID: owner, modelContext: modelContext)
            isThinking = false
            if let statement = result?.statement {
                answer = RookTurn(at: now, role: .rook, text: statement.insight.interpretation, statement: statement)
                current = statement
                RookMemory.record(statement)
            } else {
                answer = localAnswer(reason: "Claude hat gerade nicht sauber geantwortet")
            }
        } else {
            answer = localAnswer(reason: localReason ?? "")
        }
        turns.append(answer)
        RookMemory.append([question, answer])
    }

    private func blocker(modelContext: ModelContext) -> String? {
        if LaunchOptions.current.usesTestScenario { return "Testansicht" }
        if !CheckInSettings().useClaude { return "Senden an Claude ist ausgeschaltet" }
        return engine.checkInBlocker(modelContext: modelContext)
    }

    /// Without Claude ROOK still answers, briefly and without excuses about data.
    private func localAnswer(reason: String) -> RookTurn {
        let text = "Für eine ausführliche Antwort frage ich Claude, das geht gerade nicht (\(reason)). "
            + "Meine Deutung von heute steht oben, unter „Warum?“ findest du alles, worauf sie beruht."
        return RookTurn(at: now, role: .rook, text: text)
    }
}
