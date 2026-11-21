import Foundation
import Testing
@testable import PulseCore

// Begleiter "Aktivierung": library and ladders, planner, progression, activity check, texts.

private let actCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? TimeZone(secondsFromGMT: 3_600) ?? .current
    return calendar
}()

private func actDate(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    actCalendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)) ?? .distantPast
}

private func actInput(_ slot: ActivationSlot, dayType: CompanionDayType = .recovered, infection: InfectionLevel = .none,
                      settings: ActivationSettings = ActivationSettings(),
                      profile: ActivationProfile = ActivationProfile(),
                      coach: CoachPreferences = CoachPreferences(), done: [ActivationResult] = [],
                      now: Date = actDate(21, 7)) -> ActivationInput {
    ActivationInput(slot: slot, now: now, calendar: actCalendar, settings: settings, profile: profile, coach: coach,
                    dayType: dayType, infectionLevel: infection, doneToday: done)
}

private func actSteps(_ value: Double, at start: Date) -> HealthSample {
    HealthSample(profileID: nil, kind: .steps, value: value, unit: .count, start: start,
                 end: start.addingTimeInterval(60), timeZoneIdentifier: "Europe/Berlin", source: .colmiRing,
                 deviceID: "ring", originalSampleID: UUID().uuidString, importedAt: actDate(21, 12), quality: .valid,
                 method: .deviceHistory)
}

private func actPlan(_ blocks: [ActivationBlock], rounds: Int, format: ActivationFormat = .circuit,
                     warmUp: [ActivationBlock] = []) -> ActivationPlan {
    ActivationPlan(slot: .morning, dayStamp: "20261121", format: format, readiness: .full, warmUp: warmUp,
                   blocks: blocks, circuitRounds: rounds, estimatedSeconds: 300, reason: "", summary: "")
}

private func actBlock(_ exerciseID: String, _ family: ActivationFamily, _ target: ActivationTarget) -> ActivationBlock {
    ActivationBlock(id: "morning.0.\(exerciseID)", exerciseID: exerciseID, family: family, target: target, rounds: 1,
                    restSeconds: 0)
}

private func actResult(_ block: ActivationBlock, done: [Int], rounds: Int, feedback: ActivationFeedback? = .right,
                       format: ActivationFormat = .circuit) -> ActivationResult {
    let plan = actPlan([block], rounds: rounds, format: format)
    let blockResult = ActivationBlockResult(blockID: block.id, exerciseID: block.exerciseID, family: block.family,
                                            done: done)
    return ActivationResult(plan: plan, results: [blockResult], feedback: feedback, finishedAt: actDate(21, 7, 20))
}

private func actProfile(_ family: ActivationFamily, _ id: String, best: Int) -> ActivationProfile {
    ActivationProfile(levels: [family: ActivationLevel(family: family, exerciseID: id, best: best,
                                                       updatedAt: actDate(20, 7))])
}

private func actReps(_ plan: ActivationPlan, _ family: ActivationFamily) -> Int? {
    guard let block = plan.blocks.first(where: { $0.family == family }) else { return nil }
    if case .reps(let reps) = block.target { return reps }
    return nil
}

@Suite("Aktivierung – Bibliothek und Leitern")
struct ActivationLibraryTests {
    @Test func everyLadderIDResolves() {
        for family in ActivationFamily.allCases {
            for id in ActivationLibrary.ladder(family) {
                #expect(ActivationLibrary.exercise(id) != nil, "missing \(id)")
            }
        }
        #expect(ActivationLibrary.exercise("band-row") != nil)
    }

    @Test func ownEntriesDoNotDuplicateCoachEntries() {
        let coachIDs = Set(ExerciseLibrary.all.map(\.id))
        let ownIDs = ActivationLibrary.all.map(\.id)
        #expect(Set(ownIDs).count == ownIDs.count)
        #expect(Set(ownIDs).isDisjoint(with: coachIDs))
        #expect(ActivationLibrary.all == ExerciseLibrary.activationEntries)
        for exercise in ActivationLibrary.all {
            #expect(exercise.uses.contains(.activation))
            #expect((2...4).contains(exercise.steps.count))
            #expect((1...5).contains(exercise.difficulty))
            #expect(exercise.origin == "PULSE ONE (eigener Text)")
        }
    }

    @Test func noPullUpBarMeansNoBarExercises() throws {
        let coach = CoachPreferences(level: .trained)
        #expect(ActivationLibrary.allowedLadder(.pull, coach: coach) == ["table-row"])
        let withBands = CoachPreferences(level: .trained, equipment: [.bands])
        #expect(ActivationLibrary.allowedLadder(.pull, coach: withBands) == ["table-row", "band-row"])
        for family in ActivationFamily.allCases {
            for id in ActivationLibrary.allowedLadder(family, coach: coach) {
                let exercise = try #require(ActivationLibrary.exercise(id))
                #expect(!exercise.equipment.contains(.pullUpBar))
            }
        }
        let start = ActivationLibrary.startLevel(.pull, coach: coach, now: actDate(21, 7))
        #expect(start.exerciseID == "table-row")
        #expect(start.best == 10)
        let plan = ActivationPlanner.plan(actInput(.morning, coach: coach))
        for block in plan.blocks {
            let exercise = try #require(ActivationLibrary.exercise(block.exerciseID))
            #expect(!exercise.equipment.contains(.pullUpBar))
        }
    }

    @Test func barUnlocksPullUpLadder() {
        let coach = CoachPreferences(level: .active, equipment: [.pullUpBar])
        #expect(ActivationLibrary.allowedLadder(.pull, coach: coach)
            == ["table-row", "dead-hang", "scapular-pull", "pullup-negative", "pullup"])
        #expect(ActivationLibrary.startLevel(.pull, coach: coach, now: actDate(21, 7)).exerciseID == "pullup-negative")
    }

    @Test func medicalClearanceKeepsDifficultyLow() throws {
        let coach = CoachPreferences(level: .performance, equipment: Set(Equipment.allCases), needsMedicalClearance: true)
        for family in ActivationFamily.allCases {
            for id in ActivationLibrary.allowedLadder(family, coach: coach) {
                let exercise = try #require(ActivationLibrary.exercise(id))
                #expect(exercise.difficulty <= 2, "\(id)")
            }
        }
        let plan = ActivationPlanner.plan(actInput(.morning, coach: coach))
        for block in plan.blocks + plan.warmUp {
            let exercise = try #require(ActivationLibrary.exercise(block.exerciseID))
            #expect(exercise.difficulty <= 2, "\(block.exerciseID)")
        }
    }

    @Test func limitationsExcludeLoadedRegions() throws {
        let coach = CoachPreferences(limitations: [.shoulder])
        #expect(ActivationLibrary.allowedLadder(.push, coach: coach).isEmpty)
        let plan = ActivationPlanner.plan(actInput(.morning, coach: coach))
        for block in plan.blocks + plan.warmUp {
            let exercise = try #require(ActivationLibrary.exercise(block.exerciseID))
            #expect(!exercise.loads.contains(.shoulder))
        }
    }

    @Test func holdsAreHolds() {
        #expect(ActivationLibrary.isHold("plank"))
        #expect(ActivationLibrary.isHold("dead-hang"))
        #expect(ActivationLibrary.isHold("hollow-hold"))
        #expect(!ActivationLibrary.isHold("pushup"))
    }
}

@Suite("Aktivierung – Planer")
struct ActivationPlannerTests {
    @Test(arguments: [5, 8, 15])
    func morningPlanFitsBudget(minutes: Int) {
        let settings = ActivationSettings(morningMinutes: minutes)
        let coach = CoachPreferences(equipment: [.pullUpBar])
        let plan = ActivationPlanner.plan(actInput(.morning, settings: settings, coach: coach))
        let budget = minutes * 60
        let limit = Int(Double(budget) * 1.1)
        #expect(plan.estimatedSeconds <= limit)
        #expect(plan.estimatedSeconds > 0)
        #expect(!plan.warmUp.isEmpty)
        #expect(plan.format == .circuit)
        #expect((2...5).contains(plan.circuitRounds))
        let families = Set(plan.blocks.map(\.family))
        #expect(families.contains(.push))
        #expect(families.contains(.core))
        #expect(families.contains(.pull))
        #expect(plan.dayStamp == "20261121")
        #expect(plan.blocks.allSatisfy { $0.id.hasPrefix("morning.") })
    }

    @Test func budgetsAreClamped() {
        let settings = ActivationSettings(morningMinutes: 40, shortMinutes: 1)
        #expect(ActivationPlanner.budgetSeconds(slot: .morning, settings: settings) == 900)
        #expect(ActivationPlanner.budgetSeconds(slot: .midday, settings: settings) == 180)
        #expect(ActivationPlanner.budgetSeconds(slot: .evening, settings: settings) == 180)
        #expect(ActivationPlanner.budgetSeconds(slot: .snack, settings: settings) == 150)
    }

    @Test func readinessRules() {
        #expect(ActivationPlanner.readiness(dayType: .recovered, infectionLevel: .none) == .full)
        #expect(ActivationPlanner.readiness(dayType: .normal, infectionLevel: .watch) == .full)
        #expect(ActivationPlanner.readiness(dayType: .shortNight, infectionLevel: .none) == .reduced)
        #expect(ActivationPlanner.readiness(dayType: .notEnoughData, infectionLevel: .none) == .reduced)
        #expect(ActivationPlanner.readiness(dayType: .unusualPattern, infectionLevel: .none) == .gentle)
        #expect(ActivationPlanner.readiness(dayType: .normal, infectionLevel: .pattern) == .gentle)
    }

    @Test func shortNightGivesSmallerTargets() throws {
        let profile = actProfile(.push, "pushup", best: 10)
        let recovered = ActivationPlanner.plan(actInput(.morning, dayType: .recovered, profile: profile))
        let short = ActivationPlanner.plan(actInput(.morning, dayType: .shortNight, profile: profile))
        let full = try #require(actReps(recovered, .push))
        let reduced = try #require(actReps(short, .push))
        #expect(full == 6)
        #expect(reduced < full)
        #expect(short.readiness == .reduced)
        #expect(short.reason == "Kurze Nacht: heute etwas weniger.")
    }

    @Test func unusualPatternIsGentleWithoutPush() {
        let plan = ActivationPlanner.plan(actInput(.morning, dayType: .unusualPattern))
        #expect(plan.format == .gentle)
        #expect(plan.readiness == .gentle)
        #expect(!plan.blocks.isEmpty)
        #expect(plan.blocks.allSatisfy { $0.family == .mobility })
        #expect(plan.circuitRounds == 1)
        #expect(plan.estimatedSeconds <= 8 * 60)
        let infection = ActivationPlanner.plan(actInput(.midday, dayType: .normal, infection: .pattern))
        #expect(infection.format == .gentle)
        #expect(!infection.blocks.contains { $0.family == .push })
    }

    @Test func eveningIsShorterAfterTwoSessions() {
        let settings = ActivationSettings(shortMinutes: 10)
        let earlier = ActivationPlanner.plan(actInput(.morning))
        let done = [
            ActivationResult(plan: earlier, results: [], feedback: .right, finishedAt: actDate(21, 7, 15)),
            ActivationResult(plan: earlier, results: [], feedback: .right, finishedAt: actDate(21, 12, 40))
        ]
        let normal = ActivationPlanner.plan(actInput(.evening, settings: settings, now: actDate(21, 18)))
        let shorter = ActivationPlanner.plan(actInput(.evening, settings: settings, done: done, now: actDate(21, 18)))
        #expect(shorter.estimatedSeconds < normal.estimatedSeconds)
        #expect(shorter.estimatedSeconds <= Int(Double(420) * 1.1))
        #expect(shorter.reason == "Heute schon viel bewegt: abends etwas kürzer.")
        let families = Set(normal.blocks.map(\.family))
        #expect(families == [.core, .pull, .mobility])
    }

    @Test func middayAndSnackShapes() {
        let midday = ActivationPlanner.plan(actInput(.midday, now: actDate(21, 12, 30)))
        #expect(midday.warmUp.isEmpty)
        #expect(Set(midday.blocks.map(\.family)) == [.legs, .cardio, .push])
        #expect(midday.estimatedSeconds <= Int(Double(300) * 1.1))
        let snack = ActivationPlanner.plan(actInput(.snack, now: actDate(21, 15)))
        #expect(snack.circuitRounds == 1)
        #expect(snack.warmUp.isEmpty)
        #expect((1...2).contains(snack.blocks.count))
        #expect(snack.blocks.allSatisfy { $0.family == .cardio || $0.family == .legs })
        #expect(snack.estimatedSeconds <= 165)
    }

    @Test func planIsDeterministic() {
        let a = ActivationPlanner.plan(actInput(.morning))
        let b = ActivationPlanner.plan(actInput(.morning))
        #expect(a == b)
    }

    @Test func summaryContainsTheNumbers() throws {
        let profile = actProfile(.push, "pushup", best: 10)
        let plan = ActivationPlanner.plan(actInput(.morning, profile: profile))
        #expect(plan.summary.contains("\(plan.circuitRounds) Runden"))
        #expect(plan.summary.contains("6 × Liegestütz"))
        let first = try #require(plan.blocks.first)
        #expect(plan.summary.contains(ActivationText.target(first)))
        #expect(plan.summary.contains(ActivationText.duration(plan.estimatedSeconds)))
    }

    @Test func textHelpers() {
        #expect(ActivationText.duration(420) == "etwa 7 Minuten")
        #expect(ActivationText.duration(30) == "etwa 1 Minute")
        let reps = ActivationBlock(id: "x", exerciseID: "pushup", family: .push, target: .reps(12), rounds: 1,
                                   restSeconds: 0)
        #expect(ActivationText.target(reps) == "12 × Liegestütz")
        let hold = ActivationBlock(id: "y", exerciseID: "plank", family: .core, target: .seconds(40), rounds: 1,
                                   restSeconds: 0)
        #expect(ActivationText.target(hold) == "40 s Unterarmstütz")
        #expect(ActivationPlanner.dayStamp(actDate(3, 23, 30), calendar: actCalendar) == "20261103")
    }
}

@Suite("Aktivierung – Fortschritt")
struct ActivationProgressionTests {
    private let coach = CoachPreferences()
    private let now = actDate(21, 7, 30)
    private let push = actBlock("pushup", .push, .reps(6))

    @Test func metTargetRaisesBest() {
        let profile = actProfile(.push, "pushup", best: 10)
        let right = ActivationProgression.update(profile, with: actResult(push, done: [6, 6, 6], rounds: 3),
                                                 coach: coach, now: now)
        #expect(right.levels[.push]?.best == 11)
        let easy = ActivationProgression.update(profile, with: actResult(push, done: [6, 6, 6], rounds: 3,
                                                                         feedback: .tooEasy), coach: coach, now: now)
        #expect(easy.levels[.push]?.best == 12)
        #expect(easy.levels[.push]?.updatedAt == now)
    }

    @Test func missedTargetLowersBest() {
        let profile = actProfile(.push, "pushup", best: 10)
        let missed = ActivationProgression.update(profile, with: actResult(push, done: [6, 4, 6], rounds: 3),
                                                  coach: coach, now: now)
        #expect(missed.levels[.push]?.best == 9)
        let hard = ActivationProgression.update(profile, with: actResult(push, done: [6, 6, 6], rounds: 3,
                                                                         feedback: .tooHard), coach: coach, now: now)
        #expect(hard.levels[.push]?.best == 9)
    }

    @Test func strongRoundBecomesNewBest() throws {
        let profile = actProfile(.push, "pushup", best: 10)
        let updated = ActivationProgression.update(profile, with: actResult(push, done: [13, 6, 6], rounds: 3),
                                                   coach: coach, now: now)
        let level = try #require(updated.levels[.push])
        #expect(level.best == 13)
        #expect(ActivationProgression.progressText(profile.levels[.push], level) == "Neuer bester Satz Liegestütz: 13.")
    }

    @Test func thresholdPromotesToNextStep() throws {
        let profile = actProfile(.push, "pushup", best: 14)
        let updated = ActivationProgression.update(profile, with: actResult(push, done: [6, 6, 6], rounds: 3),
                                                   coach: coach, now: now)
        let level = try #require(updated.levels[.push])
        #expect(level.exerciseID == "diamond-pushup")
        #expect(level.best == 7)
        #expect(ActivationProgression.progressText(profile.levels[.push], level) == "Nächste Stufe: Liegestütz eng.")
    }

    @Test func veryLowBestMovesDown() throws {
        let profile = actProfile(.push, "pushup", best: 3)
        let block = actBlock("pushup", .push, .reps(2))
        let updated = ActivationProgression.update(profile, with: actResult(block, done: [1], rounds: 1),
                                                   coach: coach, now: now)
        let level = try #require(updated.levels[.push])
        // knee-pushup needs a mat, so the next easier allowed step is the incline push-up.
        #expect(level.exerciseID == "incline-pushup")
        #expect(level.best == 10)
        #expect(ActivationProgression.progressText(profile.levels[.push], level) == "Angepasste Stufe: Schräger Liegestütz.")
    }

    @Test func holdsMoveInFiveSecondSteps() {
        let profile = actProfile(.core, "plank", best: 40)
        let block = actBlock("plank", .core, .seconds(20))
        let updated = ActivationProgression.update(profile, with: actResult(block, done: [20, 20], rounds: 2),
                                                   coach: coach, now: now)
        #expect(updated.levels[.core]?.best == 45)
        let missed = ActivationProgression.update(profile, with: actResult(block, done: [20, 15], rounds: 2),
                                                  coach: coach, now: now)
        #expect(missed.levels[.core]?.best == 35)
    }

    @Test func gentleAndWarmUpAreIgnored() {
        let profile = actProfile(.push, "pushup", best: 10)
        let gentle = ActivationProgression.update(profile, with: actResult(push, done: [6, 6, 6], rounds: 3,
                                                                           format: .gentle), coach: coach, now: now)
        #expect(gentle == profile)
        let warm = ActivationBlock(id: "morning.w0.arm-circles", exerciseID: "arm-circles", family: .mobility,
                                   target: .seconds(30), rounds: 1, restSeconds: 0)
        let plan = actPlan([push], rounds: 3, warmUp: [warm])
        let result = ActivationResult(plan: plan, results: [
            ActivationBlockResult(blockID: warm.id, exerciseID: warm.exerciseID, family: .mobility, done: [30])
        ], feedback: .right, finishedAt: now)
        #expect(ActivationProgression.update(profile, with: result, coach: coach, now: now) == profile)
    }

    @Test func firstSessionStartsFromDefaults() {
        let updated = ActivationProgression.update(ActivationProfile(), with: actResult(push, done: [6, 6, 6], rounds: 3),
                                                   coach: coach, now: now)
        #expect(updated.levels[.push]?.exerciseID == "pushup")
        #expect(updated.levels[.push]?.best == 11)
        #expect(ActivationProgression.progressText(nil, ActivationLevel(family: .push, exerciseID: "pushup", best: 11,
                                                                        updatedAt: now)) == nil)
    }
}

@Suite("Aktivierung – Bewegung am Tag")
struct ActivityCheckTests {
    private let wake = 7...21

    @Test func hourlyStepsSumsStepsOfTheDay() {
        let samples = [
            actSteps(600, at: actDate(21, 8, 10)),
            actSteps(100, at: actDate(21, 8, 40)),
            actSteps(50, at: actDate(21, 9, 5)),
            actSteps(999, at: actDate(20, 8, 0))
        ]
        let hourly = ActivityCheck.hourlySteps(samples, day: actDate(21, 12), calendar: actCalendar)
        #expect(hourly == [8: 700, 9: 50])
    }

    @Test func quietHoursAreDetected() {
        let steps: [Int: Double] = [7: 300, 8: 1_000, 9: 100, 10: 50]
        let status = ActivityCheck.status(hourlySteps: steps, now: actDate(21, 11, 20), wakeHours: wake,
                                          calendar: actCalendar)
        #expect(status == .quiet(hours: 2))
        #expect(ActivityCheck.hint(status) != nil)
    }

    @Test func activeHourEndsTheStreak() {
        let steps: [Int: Double] = [7: 300, 8: 1_000, 9: 100, 10: 800]
        #expect(ActivityCheck.status(hourlySteps: steps, now: actDate(21, 11, 20), wakeHours: wake,
                                     calendar: actCalendar) == .active)
        #expect(ActivityCheck.hint(.active) == nil)
    }

    @Test func missingHourIsUnknownNotZero() {
        // 9 o'clock has no data: it breaks the streak instead of counting as quiet.
        let steps: [Int: Double] = [7: 100, 8: 100, 10: 50]
        #expect(ActivityCheck.status(hourlySteps: steps, now: actDate(21, 11, 20), wakeHours: wake,
                                     calendar: actCalendar) == .active)
    }

    @Test func sparseDataIsUnknown() {
        let steps: [Int: Double] = [13: 50, 14: 20]
        #expect(ActivityCheck.status(hourlySteps: steps, now: actDate(21, 15, 10), wakeHours: wake,
                                     calendar: actCalendar) == .unknown)
        #expect(ActivityCheck.status(hourlySteps: nil, now: actDate(21, 15), wakeHours: wake,
                                     calendar: actCalendar) == .unknown)
        #expect(ActivityCheck.status(hourlySteps: [:], now: actDate(21, 15), wakeHours: wake,
                                     calendar: actCalendar) == .unknown)
        #expect(ActivityCheck.hint(.unknown) == nil)
    }

    @Test func snackSuggestionRespectsRecentSession() {
        let now = actDate(21, 15)
        let quiet = ActivityStatus.quiet(hours: 3)
        #expect(ActivityCheck.shouldSuggestSnack(quiet, doneToday: [], now: now))
        #expect(!ActivityCheck.shouldSuggestSnack(.active, doneToday: [], now: now))
        #expect(!ActivityCheck.shouldSuggestSnack(.unknown, doneToday: [], now: now))
        let plan = actPlan([], rounds: 1)
        let recent = ActivationResult(plan: plan, results: [], feedback: nil, finishedAt: actDate(21, 14, 30))
        #expect(!ActivityCheck.shouldSuggestSnack(quiet, doneToday: [recent], now: now))
        let older = ActivationResult(plan: plan, results: [], feedback: nil, finishedAt: actDate(21, 12, 30))
        #expect(ActivityCheck.shouldSuggestSnack(quiet, doneToday: [older], now: now))
    }

    @Test func checkpointsAimAtMorningAndAfternoon() {
        let times = ActivityCheck.checkpointTimes(wake: actDate(21, 7), settings: ActivationSettings(),
                                                  now: actDate(21, 7, 5), calendar: actCalendar)
        #expect(times == [actDate(21, 10, 30), actDate(21, 15, 30)])
    }

    @Test func checkpointsShiftAfterLateWake() {
        let times = ActivityCheck.checkpointTimes(wake: actDate(21, 10), settings: ActivationSettings(),
                                                  now: actDate(21, 10, 5), calendar: actCalendar)
        #expect(times == [actDate(21, 11), actDate(21, 15, 30)])
    }

    @Test func checkpointsAvoidTwoHoursAfterSessions() {
        let settings = ActivationSettings(middayHour: 10, middayMinute: 0)
        let times = ActivityCheck.checkpointTimes(wake: actDate(21, 7), settings: settings, now: actDate(21, 7, 5),
                                                  calendar: actCalendar)
        #expect(times == [actDate(21, 12, 30), actDate(21, 15, 30)])
    }

    @Test func checkpointsAreFutureSpacedAndInsideWindow() {
        let now = actDate(21, 16)
        let times = ActivityCheck.checkpointTimes(wake: actDate(21, 7), settings: ActivationSettings(), now: now,
                                                  calendar: actCalendar)
        #expect(times.count <= 2)
        #expect(times == [actDate(21, 16, 30)])
        for time in times {
            #expect(time > now)
            #expect(time >= actDate(21, 9))
            #expect(time <= actDate(21, 20))
        }
        let late = ActivityCheck.checkpointTimes(wake: actDate(21, 7), settings: ActivationSettings(),
                                                 now: actDate(21, 20, 30), calendar: actCalendar)
        #expect(late.isEmpty)
    }
}

@Suite("Aktivierung – Textsicherheit")
struct ActivationSafetyTests {
    @Test func allTextsPassCompanionSafety() {
        var texts: [String] = []
        let coaches = [
            CoachPreferences(),
            CoachPreferences(level: .performance, equipment: [.pullUpBar, .mat]),
            CoachPreferences(level: .beginner, limitations: [.shoulder], needsMedicalClearance: true)
        ]
        let infections: [InfectionLevel] = [.none, .pattern]
        for coach in coaches {
            for slot in ActivationSlot.allCases {
                for dayType in CompanionDayType.allCases {
                    for infection in infections {
                        let plan = ActivationPlanner.plan(actInput(slot, dayType: dayType, infection: infection,
                                                                   coach: coach))
                        texts.append(plan.reason)
                        texts.append(plan.summary)
                    }
                }
            }
        }
        for hours in 2...5 {
            if let hint = ActivityCheck.hint(.quiet(hours: hours)) { texts.append(hint) }
        }
        for exercise in ActivationLibrary.all {
            texts.append(exercise.name)
            texts.append(exercise.safety)
            texts.append(contentsOf: exercise.steps)
        }
        let old = ActivationLevel(family: .push, exerciseID: "pushup", best: 14, updatedAt: actDate(20, 7))
        let next = ActivationLevel(family: .push, exerciseID: "diamond-pushup", best: 7, updatedAt: actDate(21, 7))
        if let text = ActivationProgression.progressText(old, next) { texts.append(text) }
        #expect(!texts.isEmpty)
        for text in texts {
            #expect(CompanionSafety.violations(in: text).isEmpty, "\(text)")
        }
    }
}
