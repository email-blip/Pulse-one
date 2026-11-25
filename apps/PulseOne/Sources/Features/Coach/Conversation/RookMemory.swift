import Foundation
import PulseCore

/// ROOK's memory on this iPhone: the statements of the last weeks (with corrections and revisions) and the one
/// conversation of the Coach tab, as a JSON file in Application Support. Health data never leave the device
/// through it. Kept outside SwiftData so the rebuild needs no schema change (00 owns the schema; a model
/// `StoredRookStatement` can replace this file in the M2 migration). UI-test scenarios use memory only.
@MainActor
enum RookMemory {
    struct Snapshot: Codable, Equatable {
        var statements: [RookStatement] = []
        var turns: [RookTurn] = []
    }

    static let maxStatements = 60
    static let maxTurns = 200

    /// Test scenarios never touch the real file.
    private static var scenarioSnapshot = Snapshot()

    static var fileURL: URL { URL.applicationSupportDirectory.appending(path: "rook-memory.json") }

    static func load() -> Snapshot {
        if LaunchOptions.current.usesTestScenario { return scenarioSnapshot }
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return Snapshot() }
        return snapshot
    }

    static func save(_ snapshot: Snapshot) {
        var trimmed = snapshot
        trimmed.statements = Array(trimmed.statements.suffix(maxStatements))
        trimmed.turns = Array(trimmed.turns.suffix(maxTurns))
        if LaunchOptions.current.usesTestScenario {
            scenarioSnapshot = trimmed
            return
        }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(trimmed).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            // Losing the memory file only loses the conversation history; the measurements are elsewhere.
        }
    }

    /// Stores a statement, replacing an older version with the same id (after a correction).
    static func record(_ statement: RookStatement) {
        var snapshot = load()
        if let index = snapshot.statements.firstIndex(where: { $0.id == statement.id }) {
            snapshot.statements[index] = statement
        } else {
            snapshot.statements.append(statement)
        }
        save(snapshot)
    }

    static func append(_ turns: [RookTurn]) {
        var snapshot = load()
        snapshot.turns.append(contentsOf: turns)
        save(snapshot)
    }

    /// The person's corrections on the day of `date` ("Ich bin krank", "Heute nur zehn Minuten", ...), oldest first.
    /// Team 05's day plan reads these through `CoachRepository.correctionsProvider`.
    static func corrections(on date: Date, calendar: Calendar = .current) -> [(feedback: RookFeedback, at: Date)] {
        load().turns.compactMap { turn in
            guard turn.role == .person, calendar.isDate(turn.at, inSameDayAs: date),
                  let feedback = RookFeedback.match(turn.text), feedback != .why else { return nil }
            return (feedback, turn.at)
        }
    }

    /// The newest reading Claude worded within `interval` before `now` (opening readings and check-ins).
    static func recentClaude(within interval: TimeInterval, at now: Date, subjectID: UUID?) -> RookStatement? {
        load().statements.last { statement in
            let age = now.timeIntervalSince(statement.insight.createdAt)
            return statement.source == .claude && statement.insight.subjectID == subjectID && age >= 0 && age < interval
        }
    }

    /// The newest statement that is valid now: Claude's check-in or a corrected one beats the plain local reading.
    static func latestValid(at now: Date, subjectID: UUID?) -> RookStatement? {
        load().statements.last { $0.insight.isValid(at: now) && $0.insight.subjectID == subjectID }
    }
}
