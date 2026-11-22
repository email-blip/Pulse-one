import Foundation
import Testing
@testable import PulseCore

// "Jetzt dran" on TODAY: one next step, chosen by time of day from Begleiter, activation and Coach.

private let nowCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
    return calendar
}()

private func at(_ hour: Int, _ minute: Int = 0) -> Date {
    nowCalendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: hour, minute: minute)) ?? .distantPast
}

private func input(_ hour: Int, _ minute: Int = 0) -> NowInput {
    NowInput(now: at(hour, minute), calendar: nowCalendar)
}

private let session = PlannedSession(kind: .main, sport: .running, minutes: 40, intensity: .moderate)

@Suite("Jetzt dran – one next step")
struct NowPlannerTests {
    @Test func morningStartsWithTheReportThenTheActivation() {
        var morning = input(7, 10)
        morning.morningActivationOpen = true
        morning.morningActivationSeconds = 600
        #expect(NowPlanner.pick(morning).id == "morningReport")
        morning.hasMorningReport = true
        let item = NowPlanner.pick(morning)
        #expect(item.id == "activation.morning")
        #expect(item.target == .companion)
        #expect(item.detail.hasPrefix("Etwa 10 Minuten"))
        #expect(!item.detail.hasSuffix(" "))
    }

    @Test func middaySessionIsDueAroundItsTime() {
        var noon = input(12, 20)
        noon.hasMorningReport = true
        noon.coachSession = session
        noon.nextActivation = (slot: .midday, time: at(12, 30), seconds: 300)
        #expect(NowPlanner.pick(noon).id == "activation.midday")
        // Two hours before, in the morning: nothing due yet, the session is announced.
        noon.now = at(10, 30)
        #expect(NowPlanner.pick(noon).id == "upcoming.midday")
        // From 11:00 the coach's main session is the next thing until the midday session is due.
        noon.now = at(11, 0)
        #expect(NowPlanner.pick(noon).id == "coach")
    }

    @Test func quietHoursAskForASnack() {
        var afternoon = input(15)
        afternoon.hasMorningReport = true
        afternoon.coachSession = session
        afternoon.snackHint = "Seit 3 Stunden wenig Bewegung."
        let item = NowPlanner.pick(afternoon)
        #expect(item.id == "snack")
        #expect(item.detail == "Seit 3 Stunden wenig Bewegung.")
    }

    @Test func eveningAsksForTheCloseoutUntilItIsDone() {
        var evening = input(19)
        evening.hasMorningReport = true
        #expect(NowPlanner.pick(evening).id == "closeout")
        #expect(NowPlanner.pick(evening).target == .eveningNote)
        evening.eveningReviewDone = true
        #expect(NowPlanner.pick(evening).id == "clear")
        evening.now = at(22)
        #expect(NowPlanner.pick(evening).id == "windDown")
    }

    @Test func dayGuardWinsOverEverything() {
        var sick = input(7)
        sick.morningActivationOpen = true
        sick.dayGuard = DayGuard.evaluate(DayGuardInput(subjective: SubjectiveCheck(feelsSick: true)))
        #expect(NowPlanner.pick(sick).id == "rest")
        sick.dayGuard = DayGuard.evaluate(DayGuardInput(subjective: SubjectiveCheck(alarmSymptoms: true)))
        let help = NowPlanner.pick(sick)
        #expect(help.id == "seekHelp")
        #expect(help.detail.contains("112"))
    }

    @Test func lighterDaysShrinkTheCoachSession() {
        var day = input(14)
        day.hasMorningReport = true
        day.coachSession = session
        day.dayGuard = DayGuard.evaluate(DayGuardInput(companionDayType: .shortNight))
        #expect(NowPlanner.pick(day).detail.hasPrefix("24 min"))
        day.dayGuard = DayGuard.evaluate(DayGuardInput(infectionLevel: .pattern))
        #expect(NowPlanner.pick(day).title == "Heute nur sanft bewegen")
    }

    @Test func restDayFromTheCoachIsNotATask() {
        var day = input(14)
        day.hasMorningReport = true
        day.coachSession = .rest
        #expect(NowPlanner.pick(day).id == "clear")
    }
}
