import Foundation
import Testing
@testable import PulseCore

// Welle 3 – PULSE COACH engine (COACH-ENGINE-SPEC §3–§6).

private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

private let nov21 = Date(timeIntervalSince1970: 1_795_219_200)   // 2026-11-21 00:00 UTC

private func day(_ offset: Int) -> Date { utc.date(byAdding: .day, value: offset, to: nov21)! }

/// 30 window days (offset −32…−3) with values cycling through `base`, plus the given recent days (−2…0).
private func series(base: [Double], recent: [Double]) -> [DayValue] {
    var result: [DayValue] = []
    for i in 0..<30 { result.append(DayValue(day: day(-32 + i), value: base[i % base.count])) }
    for (i, v) in recent.enumerated() { result.append(DayValue(day: day(-(recent.count - 1) + i), value: v)) }
    return result
}

private func makeSignal(_ kind: RecoverySignalKind, _ state: SignalState) -> RecoverySignal {
    RecoverySignal(kind: kind, state: state, text: "")
}

@Suite("Coach – recovery signals")
struct CoachSignalTests {
    @Test func percentileInterpolates() {
        #expect(RecoveryBand.percentile([1, 2, 3, 4, 5], 0.5) == 3)
        #expect(RecoveryBand.percentile([1, 2, 3, 4], 0.25) == 1.75)
    }

    @Test func tooFewDaysIsUnknownNotGood() {
        let few = (0..<10).map { DayValue(day: day(-12 + $0), value: 55) } + [DayValue(day: day(-1), value: 70), DayValue(day: day(0), value: 72)]
        let s = RecoveryAssessment.restingHR(few, today: nov21, calendar: utc)
        #expect(s.state == .unknown)
    }

    @Test func restingPulseAboveBandOnTwoDaysIsNotable() {
        let values = series(base: [54, 55, 56, 57, 58], recent: [56, 63, 64])
        let s = RecoveryAssessment.restingHR(values, today: nov21, calendar: utc)
        #expect(s.state == .notable)
        #expect(s.text.contains("über deinem üblichen Bereich"))
        let one = RecoveryAssessment.restingHR(series(base: [54, 55, 56, 57, 58], recent: [56, 57, 64]), today: nov21, calendar: utc)
        #expect(one.state == .usual)
    }

    @Test func hrvBelowBandIsNotable() {
        let s = RecoveryAssessment.hrv(series(base: [40, 42, 44, 46, 48], recent: [30, 31, 45]), today: nov21, calendar: utc)
        #expect(s.state == .notable)
    }

    @Test func shortSleepTwoOfThreeNights() {
        let h: Double = 3_600
        let s = RecoveryAssessment.sleepSignal(series(base: [7 * h, 7.5 * h, 8 * h], recent: [5.5 * h, 7.5 * h, 6 * h]),
                                               today: nov21, calendar: utc)
        #expect(s.state == .notable)
        #expect(!s.text.contains("Überlastung"))
    }

    @Test func decisionsFollowTheRules() {
        let usual = RecoverySignalKind.allCases.map { makeSignal($0, .usual) }
        #expect(CoachRules.decide(signals: usual, subjective: nil) == .asPlanned)
        let one = [makeSignal(.restingHeartRate, .notable), makeSignal(.sleep, .usual), makeSignal(.heartRateVariability, .unknown)]
        #expect(CoachRules.decide(signals: one, subjective: nil) == .offerLighter)
        let two = [makeSignal(.restingHeartRate, .notable), makeSignal(.sleep, .notable)]
        #expect(CoachRules.decide(signals: two, subjective: nil) == .easyOrRecovery)
        #expect(CoachRules.decide(signals: usual, subjective: SubjectiveCheck(feelsSick: true)) == .rest)
        #expect(CoachRules.decide(signals: usual, subjective: SubjectiveCheck(alarmSymptoms: true)) == .seekHelp)
        #expect(ReadinessDecision.seekHelp.explanation.contains("112"))
    }

    @Test func unknownSignalsAreNotCountedAsGoodAndAreNamed() {
        let unknown = [makeSignal(.restingHeartRate, .unknown), makeSignal(.heartRateVariability, .unknown), makeSignal(.sleep, .usual)]
        #expect(CoachRules.decide(signals: unknown, subjective: nil) == .asPlanned)
        #expect(CoachRules.coverageNote(unknown)?.contains("2 von 3") == true)
    }
}

@Suite("Coach – programs and hard limits")
struct CoachProgramTests {
    static let sportSets: [[Sport]] = [[], [.running], [.strength, .cycling], [.football, .rowing, .hiking], [.riding, .mobility]]

    @Test(arguments: FitnessLevel.allCases)
    func everyCombinationStaysWithinHardLimits(level: FitnessLevel) {
        for days in 0...7 {
            for sports in Self.sportSets {
                for history in [nil, 50.0, 400.0, 2_000.0] as [Double?] {
                    for clearance in [false, true] {
                        let p = CoachPreferences(sports: sports, trainingDaysPerWeek: days, minutesPerSession: 45, level: level,
                                                 needsMedicalClearance: clearance)
                        let program = ProgramBuilder.build(preferences: p, start: nov21, recentWeeklyLoad: history, calendar: utc)
                        let violations = ProgramRules.violations(program, preferences: p, recentWeeklyLoad: history)
                        #expect(violations.isEmpty, "\(level) \(days) \(sports) \(String(describing: history)): \(violations)")
                        #expect(program.weeks.count == 4)
                        #expect(program.weeks.allSatisfy { $0.trainingDays <= 6 })
                    }
                }
            }
        }
    }

    @Test func lighterFourthWeekAndNoAdjacentHardDays() {
        let p = CoachPreferences(sports: [.running, .strength], trainingDaysPerWeek: 5, minutesPerSession: 60, level: .trained)
        let program = ProgramBuilder.build(preferences: p, start: nov21, recentWeeklyLoad: nil, calendar: utc)
        #expect(program.weeks[3].isLighter)
        #expect(program.weeks[3].plannedLoad < program.weeks[2].plannedLoad * 0.8)
        for week in program.weeks {
            let hard = week.days.indices.filter { week.days[$0].intensity == .hard && week.days[$0].kind == .main }
            for (a, b) in zip(hard, hard.dropFirst()) { #expect(b - a > 1) }
        }
        #expect(program.weeks[1].days.contains { $0.intensity == .hard })
    }

    @Test func medicalClearanceKeepsEverythingLight() {
        let p = CoachPreferences(sports: [.running], trainingDaysPerWeek: 4, level: .performance, needsMedicalClearance: true)
        let program = ProgramBuilder.build(preferences: p, start: nov21, recentWeeklyLoad: nil, calendar: utc)
        #expect(program.weeks.flatMap(\.days).allSatisfy { $0.intensity <= .easy })
    }

    @Test func noSportIsAFullPlanOfEverydayMovement() {
        let p = CoachPreferences(sports: [], trainingDaysPerWeek: 3)
        let program = ProgramBuilder.build(preferences: p, start: nov21, recentWeeklyLoad: nil, calendar: utc)
        let sessions = program.weeks[0].days.filter { $0.kind == .main }
        #expect(sessions.count == 3)
        #expect(sessions.allSatisfy { $0.sport == nil && $0.intensity <= .easy })
        #expect(sessions.first?.title == "Alltagsbewegung")
    }

    @Test func historyCapsTheFirstWeek() {
        let p = CoachPreferences(sports: [.cycling], trainingDaysPerWeek: 4, minutesPerSession: 90, level: .active)
        let program = ProgramBuilder.build(preferences: p, start: nov21, recentWeeklyLoad: 300, calendar: utc)
        #expect(program.weeks[0].plannedLoad <= 330.5)
    }

    @Test func sessionLookupByDate() {
        let p = CoachPreferences(sports: [.running], trainingDaysPerWeek: 3)
        let program = ProgramBuilder.build(preferences: p, start: nov21, recentWeeklyLoad: nil, calendar: utc)
        #expect(program.session(on: day(0), calendar: utc)?.kind == .main)   // slot 0
        #expect(program.session(on: day(1), calendar: utc)?.kind == .rest)
        #expect(program.session(on: day(-1), calendar: utc) == nil)
        #expect(program.session(on: day(28), calendar: utc) == nil)
    }
}

@Suite("Coach – daily plan and adjustments")
struct CoachDailyPlanTests {
    let prefs = CoachPreferences(sports: [.strength], trainingDaysPerWeek: 3, minutesPerSession: 40, level: .trained,
                                 equipment: [.mat, .dumbbells])
    var program: TrainingProgram { ProgramBuilder.build(preferences: prefs, start: day(-7), recentWeeklyLoad: nil, calendar: utc) }
    let noon = nov21.addingTimeInterval(12 * 3_600)

    @Test func twoSignalsMakeTheMainSessionEasy() {
        let signals = [makeSignal(.restingHeartRate, .notable), makeSignal(.sleep, .notable)]
        let plan = DailyPlanner.plan(now: noon, program: program, preferences: prefs, signals: signals, subjective: nil,
                                     feedback: .unchanged, hourlySteps: nil, revisions: [], calendar: utc)
        #expect(plan.decision == .easyOrRecovery)
        #expect(plan.suggested.intensity <= .easy)
        #expect(plan.blocks.first { $0.id == "main" }?.reason != nil)
    }

    @Test func alarmSymptomsMeanNoTrainingEvenAfterARevision() {
        let planned = program.session(on: nov21, calendar: utc)!
        let revision = PlanRevision(day: nov21, intent: .harder, before: planned, after: planned, reason: "", createdAt: noon)
        let plan = DailyPlanner.plan(now: noon, program: program, preferences: prefs, signals: [],
                                     subjective: SubjectiveCheck(alarmSymptoms: true), feedback: .unchanged,
                                     hourlySteps: nil, revisions: [revision], calendar: utc)
        #expect(plan.suggested.kind == .rest)
        #expect(!plan.blocks.contains { $0.kind == .activation || $0.kind == .movementSnack })
    }

    @Test func intentsStayWithinLimits() {
        let session = PlannedSession(kind: .main, sport: .running, minutes: 40, intensity: .moderate)
        let (short, _) = PlanAdjuster.apply(.timeLimit(minutes: 15), to: session, preferences: prefs, decision: .asPlanned)
        #expect(short.minutes == 15 && short.intensity == .moderate)
        let (bike, _) = PlanAdjuster.apply(.swapActivity(.cycling), to: session, preferences: prefs, decision: .asPlanned)
        #expect(bike.sport == .cycling && bike.plannedLoad == session.plannedLoad)
        let (capped, text) = PlanAdjuster.apply(.harder, to: session, preferences: prefs, decision: .easyOrRecovery)
        #expect(capped.intensity == .moderate)
        #expect(text.contains("Mehr ist heute nicht vorgesehen"))
        let (sore, _) = PlanAdjuster.apply(.soreness(region: .knee, level: 8), to: session, preferences: prefs, decision: .asPlanned)
        #expect(sore.kind == .recovery)
        let beginner = CoachPreferences(level: .beginner)
        let (beginnerHard, _) = PlanAdjuster.apply(.harder, to: session, preferences: beginner, decision: .asPlanned)
        #expect(beginnerHard.intensity == .moderate)
    }

    @Test func sorenessRevisionRemovesExercisesForThatRegion() {
        let planned = program.session(on: nov21, calendar: utc)!
        let (after, reason) = PlanAdjuster.apply(.soreness(region: .knee, level: 4), to: planned, preferences: prefs, decision: .asPlanned)
        let revision = PlanRevision(day: nov21, intent: .soreness(region: .knee, level: 4), before: planned, after: after,
                                    reason: reason, createdAt: noon)
        let plan = DailyPlanner.plan(now: noon, program: program, preferences: prefs, signals: [], subjective: nil,
                                     feedback: .unchanged, hourlySteps: nil, revisions: [revision], calendar: utc)
        let exercises = plan.blocks.flatMap(\.exercises)
        #expect(!exercises.isEmpty)
        #expect(exercises.allSatisfy { !$0.loads.contains(.knee) })
    }

    @Test func snacksFollowInactiveHours() {
        var steps: [Int: Double] = [:]
        for h in 7...11 { steps[h] = 1_000 }
        steps[9] = 40
        steps[10] = 0
        #expect(DailyPlanner.inactiveHours(hourlySteps: steps, now: noon, wakeHours: 7...21, calendar: utc) == [10, 9])
        let plan = DailyPlanner.plan(now: noon, program: program, preferences: prefs, signals: [], subjective: nil,
                                     feedback: .unchanged, hourlySteps: steps, revisions: [], calendar: utc)
        let snacks = plan.blocks.filter { $0.kind == .movementSnack }
        #expect(snacks.count == 2)
        #expect(snacks.first?.reason?.contains("10 und 11 Uhr") == true)
        #expect(DailyPlanner.inactiveHours(hourlySteps: nil, now: noon, wakeHours: 7...21, calendar: utc).isEmpty)
    }

    @Test func onlyChosenBlocksAppear() {
        var p = prefs
        p.enabledBlocks = [.mainWorkout, .eveningReview]
        let plan = DailyPlanner.plan(now: noon, program: program, preferences: p, signals: [], subjective: nil,
                                     feedback: .unchanged, hourlySteps: nil, revisions: [], calendar: utc)
        #expect(Set(plan.blocks.map(\.id)).isSubset(of: ["main", "review"]))
    }
}

@Suite("Coach – exercises, load and feedback")
struct CoachLogTests {
    @Test func exerciseFilterRespectsEquipmentLimitsAndSport() {
        let p = CoachPreferences(sports: [.running], level: .performance, equipment: [], limitations: [.shoulder])
        let strength = ExerciseLibrary.allowed(for: .strength, preferences: p)
        #expect(!strength.isEmpty)
        #expect(strength.allSatisfy { $0.equipment.isEmpty && !$0.loads.contains(.shoulder) })
        #expect(ExerciseLibrary.allowed(for: .prevention, preferences: p).allSatisfy { $0.sport == nil })
        let football = CoachPreferences(sports: [.football], level: .performance, equipment: [.mat])
        #expect(ExerciseLibrary.allowed(for: .prevention, preferences: football).contains { $0.id == "nordic-hamstring" })
        #expect(Set(ExerciseLibrary.all.map(\.id)).count == ExerciseLibrary.all.count)
        #expect(ExerciseLibrary.all.allSatisfy { !$0.origin.isEmpty && !$0.steps.isEmpty })
    }

    @Test func ridingIsNeverADefault() {
        #expect(CoachPreferences().sports.isEmpty)
        #expect(Sport.riding.isOptionalModule)
        #expect(Sport.allCases.filter(\.isOptionalModule) == [.riding])
    }

    @Test func missingRPEStaysMissing() {
        let r = EveningReview(day: day(0), completed: true, sport: .running, minutes: 40, rpe: nil)
        #expect(r.load == nil)
        let summary = TrainingLoad.summary([r, EveningReview(day: day(-1), completed: true, minutes: 30, rpe: 5)],
                                           endingOn: day(0), calendar: utc)
        #expect(summary.weekLoad == 150)
        #expect(summary.missingRPE == 1)
        #expect(summary.fourWeekMean == nil)
    }

    @Test func monotony() {
        #expect(TrainingLoad.monotony([100, 100, 100]) == nil)
        #expect(TrainingLoad.monotony([0, 0, 0]) == nil)
        let m = TrainingLoad.monotony([0, 200, 0, 200])!
        #expect(abs(m - 1) < 0.0001)
    }

    @Test func feedbackLowersAfterTooHardSessions() {
        let reviews = (1...3).map { EveningReview(day: day(-$0), completed: true, minutes: 40, rpe: 9, plannedIntensity: .moderate) }
        let advice = FeedbackAdaptation.advice(reviews, before: day(0), style: .balanced, calendar: utc)
        #expect(advice.intensityShift == -1)
        #expect(advice.note != nil)
    }

    @Test func feedbackShortensAfterSkippedSessions() {
        let reviews = (1...3).map { EveningReview(day: day(-$0), completed: false, plannedIntensity: .moderate) }
        let advice = FeedbackAdaptation.advice(reviews, before: day(0), style: .balanced, calendar: utc)
        #expect(advice.minutesFactor == 0.8)
    }

    @Test func calmStyleDoesNotPushAfterEasySessions() {
        let reviews = (1...3).map { EveningReview(day: day(-$0), completed: true, minutes: 30, rpe: 2, plannedIntensity: .moderate) }
        #expect(FeedbackAdaptation.advice(reviews, before: day(0), style: .calm, calendar: utc) == .unchanged)
        #expect(FeedbackAdaptation.advice(reviews, before: day(0), style: .demanding, calendar: utc).minutesFactor == 1.1)
    }
}
