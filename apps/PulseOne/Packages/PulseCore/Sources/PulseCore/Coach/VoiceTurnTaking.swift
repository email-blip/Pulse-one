import Foundation

/// Phase of a spoken conversation with ROOK.
public enum VoicePhase: String, Codable, Sendable {
    /// Microphone off.
    case idle
    /// Microphone on, the person may speak.
    case listening
    /// An utterance was handed to ROOK; waiting for the answer.
    case thinking
    /// ROOK answers aloud; the microphone stays on so the person can interrupt.
    case speaking

    public var presence: RookPresence {
        switch self {
        case .idle: .idle
        case .listening: .listening
        case .thinking: .thinking
        case .speaking: .speaking
        }
    }
}

public enum VoiceSpeaker: String, Codable, Sendable {
    case person, rook
}

/// One turn of the conversation, as shown in the transcript and handed to ROOK as history.
public struct VoiceTurn: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public let speaker: VoiceSpeaker
    public let text: String
    public let at: Date

    public init(id: UUID = UUID(), speaker: VoiceSpeaker, text: String, at: Date) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.at = at
    }
}

/// A finished utterance of the person; `turn` ties ROOK's answer to it.
public struct VoiceUtterance: Equatable, Sendable {
    public let turn: Int
    public let text: String
    public let at: Date

    public init(turn: Int, text: String, at: Date) {
        self.turn = turn
        self.text = text
        self.at = at
    }
}

/// Turn-taking of a free conversation, independent of audio: end of an utterance after a silence, the person
/// interrupting ROOK (barge-in), back to listening after the answer. The app feeds recognizer results and a clock.
public struct VoiceTurnTaking: Equatable, Sendable {
    /// Silence after the last recognized word that ends an utterance.
    public var endOfUtteranceSilence: TimeInterval = 1.2
    /// Recognized text shorter than this is noise ("äh"), not an utterance or an interruption.
    public var minimumCharacters = 2
    /// While ROOK speaks, this much recognized text counts as the person interrupting (echo stays below it).
    public var bargeInCharacters = 6
    /// Listening without any speech this long ends the conversation (microphone off).
    public var idleTimeout: TimeInterval = 30

    public private(set) var phase: VoicePhase = .idle
    /// What the person says right now (live transcript of the current utterance).
    public private(set) var partial = ""
    public private(set) var lastHeardAt: Date?
    public private(set) var listeningSince: Date?
    /// Increases with every finished utterance; an answer for an older turn is dropped.
    public private(set) var turn = 0

    public init() {}

    public enum Effect: Equatable, Sendable {
        /// Stop ROOK's voice now: the person speaks.
        case interruptRook
        /// The utterance is complete: hand it to ROOK.
        case utterance(VoiceUtterance)
        /// Nobody spoke for a while: end the conversation.
        case timedOut
    }

    public mutating func start(at now: Date) {
        phase = .listening
        partial = ""
        lastHeardAt = nil
        listeningSince = now
    }

    public mutating func stop() {
        phase = .idle
        partial = ""
        lastHeardAt = nil
        listeningSince = nil
    }

    /// A (partial) recognizer result for the current utterance. The recognizer restarts after every utterance
    /// and after every answer, so `text` is always the whole current utterance.
    public mutating func heard(_ text: String, at now: Date) -> Effect? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch phase {
        case .idle:
            return nil
        case .listening:
            guard cleaned != partial else { return nil }
            partial = cleaned
            if cleaned.count >= minimumCharacters { lastHeardAt = now }
            return nil
        case .thinking:
            // The person keeps talking: the pending answer is stale, this is the new utterance.
            guard cleaned.count >= minimumCharacters else { return nil }
            turn += 1
            phase = .listening
            partial = cleaned
            lastHeardAt = now
            return nil
        case .speaking:
            guard cleaned.count >= bargeInCharacters else { return nil }
            turn += 1
            phase = .listening
            partial = cleaned
            lastHeardAt = now
            return .interruptRook
        }
    }

    /// Clock tick while the microphone is on: ends the utterance after the silence, or the conversation after
    /// the idle timeout.
    public mutating func tick(at now: Date) -> Effect? {
        guard phase == .listening else { return nil }
        if let last = lastHeardAt, partial.count >= minimumCharacters {
            guard now.timeIntervalSince(last) >= endOfUtteranceSilence else { return nil }
            turn += 1
            let utterance = VoiceUtterance(turn: turn, text: partial, at: last)
            phase = .thinking
            partial = ""
            lastHeardAt = nil
            return .utterance(utterance)
        }
        if let since = listeningSince, lastHeardAt == nil, now.timeIntervalSince(since) >= idleTimeout {
            stop()
            return .timedOut
        }
        return nil
    }

    /// ROOK starts the answer for `turn`; false (and nothing changes) when that turn is no longer current.
    public mutating func answerStarted(for answerTurn: Int) -> Bool {
        guard phase == .thinking, answerTurn == turn else { return false }
        phase = .speaking
        return true
    }

    /// The answer ended (or was cut): listen again with a fresh utterance.
    public mutating func answerFinished(at now: Date) {
        guard phase == .speaking || phase == .thinking else { return }
        phase = .listening
        partial = ""
        lastHeardAt = nil
        listeningSince = now
    }
}
