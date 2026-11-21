import Foundation
import Testing
@testable import PulseCore

// Shared day rules (verzahnung plan): one guard for Coach, Begleiter, activation and TODAY.

private var pushUp: Exercise {
    ExerciseLibrary.all.first { $0.pattern == .push && $0.loads.contains(.shoulder) }!
}

private var gentleMobility: Exercise {
    ExerciseLibrary.all.first { $0.pattern == .mobility && $0.difficulty == 1 && $0.loads.isEmpty }
        ?? ExerciseLibrary.all.first { $0.pattern == .mobility && $0.difficulty == 1 }!
}

@Suite("Day guard – one limit for all modules")
struct DayGuardTests {
    @Test func nothingKnownIsOpen() {
        let guardrail = DayGuard.evaluate(DayGuardInput())
        #expect(guardrail.limit == .full)
        #expect(guardrail.reasons.isEmpty)
        #expect(guardrail.allows(pushUp))
    }

    @Test func shoulderPainBlocksPushUpsButNotTheDay() {
        let guardrail = DayGuard.evaluate(DayGuardInput(subjective: SubjectiveCheck(painRegions: [.shoulder])))
        #expect(guardrail.limit == .full)
        #expect(guardrail.avoidRegions.contains(.shoulder))
        #expect(!guardrail.allows(pushUp))
        #expect(guardrail.reasons.contains { $0.contains("Schulter") })
    }

    @Test func permanentLimitationIsAvoided() {
        let guardrail = DayGuard.evaluate(DayGuardInput(limitations: [.elbowWrist]))
        #expect(!guardrail.allows(pushUp))
    }

    @Test func alarmSymptomsStopEverythingAndAskForHelp() {
        let guardrail = DayGuard.evaluate(DayGuardInput(coachDecision: .asPlanned,
                                                        subjective: SubjectiveCheck(alarmSymptoms: true),
                                                        companionDayType: .recovered))
        #expect(guardrail.limit == .noTraining)
        #expect(guardrail.seekHelp)
        #expect(!guardrail.allows(gentleMobility))
        #expect(guardrail.reasons.first?.contains("112") == true)
    }

    @Test func feelingSickMeansNoTraining() {
        #expect(DayGuard.evaluate(DayGuardInput(subjective: SubjectiveCheck(feelsSick: true))).limit == .noTraining)
        #expect(DayGuard.evaluate(DayGuardInput(coachDecision: .rest)).limit == .noTraining)
    }

    @Test func nightPatternAllowsOnlyGentleMovement() {
        let guardrail = DayGuard.evaluate(DayGuardInput(coachDecision: .asPlanned, infectionLevel: .pattern))
        #expect(guardrail.limit == .gentleOnly)
        #expect(!guardrail.allowsStrength)
        #expect(!guardrail.allows(pushUp))
        #expect(guardrail.allows(gentleMobility))
    }

    @Test func companionAndCoachAgreeOnTheStricterView() {
        // The coach sees nothing unusual, the Begleiter sees a short night: the day is lighter for both.
        let guardrail = DayGuard.evaluate(DayGuardInput(coachDecision: .asPlanned, companionDayType: .shortNight))
        #expect(guardrail.limit == .reduced)
        #expect(guardrail.allowsStrength)
        #expect(!guardrail.allowsProgression)
        #expect(guardrail.limit.volumeFactor < 1)
    }

    @Test func strictestReasonComesFirst() {
        let guardrail = DayGuard.evaluate(DayGuardInput(coachDecision: .offerLighter, infectionLevel: .clarify))
        #expect(guardrail.limit == .noTraining)
        #expect(guardrail.reasons.count == 2)
        #expect(guardrail.reasons.first?.contains("Nachtwerte") == true)
    }

    @Test func medicalClearanceKeepsItLight() {
        #expect(DayGuard.evaluate(DayGuardInput(needsMedicalClearance: true)).limit == .reduced)
    }

    @Test func limitsAreOrdered() {
        #expect(DayLoadLimit.full < .reduced)
        #expect(DayLoadLimit.reduced < .gentleOnly)
        #expect(DayLoadLimit.gentleOnly < .noTraining)
    }
}

@Suite("HRV source – one rule, never mixed")
struct HRVSourcePolicyTests {
    @Test func ringWinsWhenPresent() {
        let picked = HRVSourcePolicy.series(ring: [40.0], apple: [55.0, 60.0])
        #expect(picked.kind == .ringHRV)
        #expect(picked.values == [40.0])
    }

    @Test func appleWhenNoRing() {
        let picked = HRVSourcePolicy.series(ring: [Double](), apple: [55.0])
        #expect(picked.kind == .heartRateVariability)
        #expect(picked.values == [55.0])
    }

    @Test func nothingWhenNeither() {
        let picked = HRVSourcePolicy.series(ring: [Double](), apple: [Double]())
        #expect(picked.kind == nil)
        #expect(picked.values.isEmpty)
    }

    @Test func coachBandUsesTheSharedPercentile() {
        let sorted: [Double] = [3, 1, 4, 1, 5, 9, 2, 6].sorted()
        for p in [0.25, 0.5, 0.75] {
            #expect(RecoveryBand.percentile(sorted, p) == PersonalBaseline.percentile(sorted, p))
        }
    }
}

// MARK: - Begleiter follows the day guard

private let guardCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
    return calendar
}()

private func guardMorning(_ dayOffset: Int) -> Date {
    let base = guardCalendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 6, minute: 45))!
    return guardCalendar.date(byAdding: .day, value: dayOffset, to: base)!
}

private func calmNight() -> NightSummary {
    NightSummary(sleepStart: guardMorning(-1).addingTimeInterval(-8 * 3_600),
                 wake: WakeEstimate(time: guardMorning(0), method: .confirmed, confidence: 1),
                 sleepDuration: 7.5 * 3_600, sleepDurationIsEstimated: false,
                 nightRestingHeartRate: 54, lowestHeartRate: 50, hrv: 44,
                 hrvKind: .ringHRV, spo2Average: 96, restingHeartRatePosition: .within,
                 hrvPosition: .within, sleepPosition: .within, morningHeartRate: nil, missing: [])
}

@Suite("Begleiter – Jetzt tun follows the shared day guard")
struct CompanionDayGuardTests {
    private func picks(_ dayGuard: DayGuard) -> Set<String> {
        var ids = Set<String>()
        for offset in 0..<21 {
            for dayType in [CompanionDayType.recovered, .normal] {
                let actions = QuickActionPicker.pick(dayType: dayType, night: calmNight(), weather: nil,
                                                     preferences: CompanionPreferences(), now: guardMorning(offset),
                                                     calendar: guardCalendar, dayGuard: dayGuard)
                ids.formUnion(actions.map(\.id))
            }
        }
        return ids
    }

    @Test func withoutLimitsStrengthStepsAppear() {
        #expect(picks(.open).contains(QuickActionCatalog.pushUpsID))
    }

    @Test func shoulderPainRemovesPushUpsAndPullUps() {
        let dayGuard = DayGuard.evaluate(DayGuardInput(subjective: SubjectiveCheck(painRegions: [.shoulder])))
        let ids = picks(dayGuard)
        #expect(!ids.contains(QuickActionCatalog.pushUpsID))
        #expect(!ids.contains(QuickActionCatalog.pullUpsID))
    }

    @Test func feelingSickRemovesStrengthAndCold() {
        let dayGuard = DayGuard.evaluate(DayGuardInput(subjective: SubjectiveCheck(feelsSick: true)))
        let ids = picks(dayGuard)
        #expect(ids.isDisjoint(with: QuickActionCatalog.strengthIDs))
        #expect(ids.isDisjoint(with: QuickActionCatalog.coldIDs))
    }

    @Test func inputBuildsTheGuardFromCoachReview() {
        let input = CompanionInput(now: guardMorning(0), calendar: guardCalendar, samples: [],
                                   preferences: CompanionPreferences(), birthYear: nil,
                                   painRegions: [.knee], limitations: [.shoulder])
        let dayGuard = input.dayGuard(dayType: .recovered, infection: .none)
        #expect(dayGuard.avoidRegions == [.knee, .shoulder])
        #expect(dayGuard.limit == .full)
        #expect(!QuickActionPicker.fits(QuickActionCatalog.squatsID, dayGuard: dayGuard))
        #expect(QuickActionPicker.fits(QuickActionCatalog.waterID, dayGuard: dayGuard))
    }
}
