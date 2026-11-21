import Foundation
import Testing
@testable import PulseCore

// Begleiter – Expertenrunde: cost estimate, local safety check, synthesis sections, test replies.

@Suite("Begleiter – Expertenrunde")
struct CompanionConferenceTests {
    private let facts = CompanionConference.sampleFacts

    @Test func roundHasFiveRequests() {
        #expect(CompanionConference.requestCount == 5)
        #expect(CompanionConference.expectedOutputTokens == 4 * 600 + 1_500)
    }

    @Test func estimateCoversAllRequestsAndScalesWithModel() {
        let characters = CompanionConference.inputCharacters(facts: facts)
        // Every one of the five requests carries the fact list.
        #expect(characters > 5 * facts.count)
        let opus = CompanionConference.estimate(facts: facts, model: .opus)
        let haiku = CompanionConference.estimate(facts: facts, model: .haiku)
        #expect(opus.inputTokens == CostEstimator.tokens(forCharacters: characters))
        #expect(opus.outputTokens == CompanionConference.expectedOutputTokens)
        #expect(opus.usd > haiku.usd)
        #expect(opus.usd > 0)
    }

    @Test func previewCarriesExactFactsAndRemainingSends() {
        let preview = SendPreview.conference(facts: facts, consent: [.heart, .sleep, .spo2], model: .sonnet,
                                             sendBudget: SendBudget(maxSends: 30, used: 28))
        #expect(preview.payload == facts)
        #expect(preview.title == "Expertenrunde")
        #expect(preview.sendsRemaining == 2)
        #expect(preview.model == .sonnet)
        #expect(preview.factCount == 5)
        #expect(preview.estimate == CompanionConference.estimate(facts: facts, model: .sonnet))
        #expect(preview.categoriesSent == [.heart, .sleep, .spo2])
        #expect(!preview.categoriesWithheld.contains(.heart))
        #expect(preview.categoriesWithheld.contains(.body))
        #expect(preview.categoriesWithheld.contains(.activity))
    }

    @Test func missingConsentIsReportedInOrder() {
        #expect(CompanionConference.missingConsent(in: ConsentCategory.defaultConsent).isEmpty)
        #expect(CompanionConference.missingConsent(in: [.heart]) == [.sleep])
        #expect(CompanionConference.missingConsent(in: [.spo2]) == [.heart, .sleep])
    }

    @Test(arguments: [
        "Du bist nicht krank, deine Werte sehen gut aus.",
        "Dein Ruhepuls deutet auf eine Infektion hin.",
        "Du könntest dein Medikament reduzieren.",
        "Das Risiko für Bluthochdruck ist erhöht.",
        "Eine Therapie wäre sinnvoll."
    ])
    func forbiddenRepliesAreWithheld(_ reply: String) {
        let screened = CompanionConference.screen(reply)
        #expect(screened.withheld)
        #expect(screened.text == CompanionConference.withheldNotice)
    }

    @Test func allowedReplyIsTrimmedAndKept() {
        let screened = CompanionConference.screen("  Dein Nachtruhepuls lag im üblichen Bereich.\n")
        #expect(!screened.withheld)
        #expect(screened.text == "Dein Nachtruhepuls lag im üblichen Bereich.")
    }

    @Test func causalWordingIsOnlyAFlagAndStays() {
        #expect(CompanionConference.isAllowed("Der Puls war höher, weil du spät trainiert hast."))
    }

    @Test func emptyReplyIsNotWithheld() {
        let screened = CompanionConference.screen("   ")
        #expect(!screened.withheld)
        #expect(screened.text == CompanionConference.emptyNotice)
    }

    @Test func samplesPassTheSafetyCheck() {
        for role in CompanionPrompts.conferenceRoles {
            let statement = CompanionConference.sampleStatements[role.id] ?? ""
            #expect(!statement.isEmpty)
            #expect(CompanionConference.isAllowed(statement))
        }
        #expect(CompanionConference.isAllowed(CompanionConference.sampleSynthesis))
    }

    @Test func synthesisSplitsIntoFourSectionsWithDisagreement() {
        let sections = CompanionConference.sections(of: CompanionConference.sampleSynthesis)
        #expect(sections.map(\.title) == CompanionConference.sectionTitles)
        #expect(sections.map(\.index) == [0, 1, 2, 3])
        let disagreement = sections.filter(\.isDisagreement)
        #expect(disagreement.count == 1)
        #expect(disagreement.first?.body.hasPrefix("Sport sieht Raum") == true)
        #expect(sections.last?.body == "Wie fühlst du dich heute im Vergleich zu deinen Werten?")
    }

    @Test func markdownHeadingsAreRecognised() throws {
        let text = "## Beobachtungen\n- Puls 55\n**Hier sind wir uns nicht einig:**\nKeine Uneinigkeit.\n### vorschläge\n- Wasser"
        let sections = CompanionConference.sections(of: text)
        #expect(sections.map(\.title) == ["Beobachtungen", "Hier sind wir uns nicht einig", "Vorschläge"])
        try #require(sections.count == 3)
        #expect(sections[0].body == "- Puls 55")
        #expect(sections[1].body == "Keine Uneinigkeit.")
        #expect(sections[1].isDisagreement)
    }

    @Test func textWithoutHeadingsIsOneUntitledSection() {
        let sections = CompanionConference.sections(of: "Alles liegt im üblichen Bereich.")
        #expect(sections.count == 1)
        #expect(sections.first?.title == "")
        #expect(sections.first?.isDisagreement == false)
    }

    @Test func mockReplyMatchesPrompt() throws {
        let sport = try #require(CompanionPrompts.conferenceRoles.first { $0.id == "sport" })
        let round = CompanionPrompts.conferenceRound(role: sport, facts: facts)
        #expect(CompanionConference.mockReply(system: round.system) == CompanionConference.sampleStatements["sport"])
        let synthesis = CompanionPrompts.conferenceSynthesis(facts: facts, statements: [])
        #expect(CompanionConference.mockReply(system: synthesis.system) == CompanionConference.sampleSynthesis)
    }

    @Test func statementRoundTripsThroughJSON() throws {
        let role = try #require(CompanionPrompts.conferenceRoles.first)
        let statement = ConferenceStatement(role: role, text: "Text", withheld: false)
        let data = try JSONEncoder().encode([statement])
        let decoded = try JSONDecoder().decode([ConferenceStatement].self, from: data)
        #expect(decoded == [statement])
        #expect(decoded.first?.symbol == "heart")
    }
}
