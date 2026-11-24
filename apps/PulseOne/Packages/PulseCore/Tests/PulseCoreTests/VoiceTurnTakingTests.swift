import Foundation
import Testing
@testable import PulseCore

@Suite("Team 05: spoken conversation with ROOK")
struct VoiceTurnTakingTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

    @Test func utteranceEndsAfterSilenceNotBefore() {
        var voice = VoiceTurnTaking()
        voice.start(at: t0)
        #expect(voice.phase == .listening)
        #expect(voice.phase.presence == .listening)
        _ = voice.heard("Wie war", at: at(1))
        _ = voice.heard("Wie war meine Nacht", at: at(1.6))
        #expect(voice.tick(at: at(2.5)) == nil)
        #expect(voice.partial == "Wie war meine Nacht")
        let effect = voice.tick(at: at(2.9))
        #expect(effect == .utterance(VoiceUtterance(turn: 1, text: "Wie war meine Nacht", at: at(1.6))))
        #expect(voice.phase == .thinking)
        #expect(voice.phase.presence == .thinking)
        #expect(voice.partial.isEmpty)
    }

    @Test func noiseIsNotAnUtterance() {
        var voice = VoiceTurnTaking()
        voice.start(at: t0)
        _ = voice.heard("ä", at: at(1))
        #expect(voice.tick(at: at(5)) == nil)
        #expect(voice.phase == .listening)
    }

    @Test func answerThenListenAgain() {
        var voice = VoiceTurnTaking()
        voice.start(at: t0)
        _ = voice.heard("Soll ich heute trainieren", at: at(1))
        guard case .utterance(let utterance) = voice.tick(at: at(3)) else {
            Issue.record("no utterance")
            return
        }
        let started = voice.answerStarted(for: utterance.turn)
        #expect(started)
        #expect(voice.phase == .speaking)
        #expect(voice.phase.presence == .speaking)
        voice.answerFinished(at: at(8))
        #expect(voice.phase == .listening)
        #expect(voice.partial.isEmpty)
    }

    @Test func speakingIntoRookInterruptsHim() {
        var voice = VoiceTurnTaking()
        voice.start(at: t0)
        _ = voice.heard("Wie geht es mir", at: at(1))
        guard case .utterance(let utterance) = voice.tick(at: at(3)) else {
            Issue.record("no utterance")
            return
        }
        let started = voice.answerStarted(for: utterance.turn)
        #expect(started)
        // Echo or a short sound does not interrupt.
        #expect(voice.heard("ja", at: at(4)) == nil)
        #expect(voice.phase == .speaking)
        #expect(voice.heard("Warte mal, anders gefragt", at: at(5)) == .interruptRook)
        #expect(voice.phase == .listening)
        #expect(voice.partial == "Warte mal, anders gefragt")
        // The answer to the old turn may not start any more.
        let lateStart = voice.answerStarted(for: utterance.turn)
        #expect(!lateStart)
    }

    @Test func talkingOnWhileRookThinksDropsTheOldAnswer() {
        var voice = VoiceTurnTaking()
        voice.start(at: t0)
        _ = voice.heard("Wie war die Nacht", at: at(1))
        guard case .utterance(let first) = voice.tick(at: at(3)) else {
            Issue.record("no utterance")
            return
        }
        _ = voice.heard("und der Puls", at: at(3.5))
        #expect(voice.phase == .listening)
        let started = voice.answerStarted(for: first.turn)
        #expect(!started)
        guard case .utterance(let second) = voice.tick(at: at(5)) else {
            Issue.record("no second utterance")
            return
        }
        #expect(second.turn > first.turn)
        #expect(second.text == "und der Puls")
    }

    @Test func silenceEndsTheConversation() {
        var voice = VoiceTurnTaking()
        voice.start(at: t0)
        #expect(voice.tick(at: at(29)) == nil)
        #expect(voice.tick(at: at(31)) == .timedOut)
        #expect(voice.phase == .idle)
        #expect(voice.heard("Hallo ROOK", at: at(32)) == nil)
    }

    @Test func stopTurnsTheMicrophoneOff() {
        var voice = VoiceTurnTaking()
        voice.start(at: t0)
        _ = voice.heard("Hallo", at: at(1))
        voice.stop()
        #expect(voice.phase == .idle)
        #expect(voice.phase.presence == .idle)
        #expect(voice.tick(at: at(10)) == nil)
    }
}
