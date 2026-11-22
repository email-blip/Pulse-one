import Foundation
import Testing
@testable import PulseCore

// "Tagesabschluss": one evening step for the Coach review and the note.

private let closeoutCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
    return calendar
}()

private let evening = closeoutCalendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 20)) ?? .distantPast
private let planned = PlannedSession(kind: .main, sport: .running, minutes: 40, intensity: .moderate)

@Suite("Tagesabschluss")
struct DayCloseoutTests {
    @Test func aNewCloseoutDoesNotLogTheSessionAsDone() {
        let review = DayCloseout.startingReview(day: evening, planned: planned, calendar: closeoutCalendar)
        #expect(!review.completed)
        #expect(review.minutes == 40)
        #expect(review.sport == .running)
        #expect(review.day == closeoutCalendar.startOfDay(for: evening))
        #expect(DayCloseout.startingReview(day: evening, planned: .rest, calendar: closeoutCalendar).minutes == nil)
    }

    @Test func savingSharesTheMoodAndKeepsEffortOnlyForADoneSession() {
        var review = DayCloseout.startingReview(day: evening, planned: planned, calendar: closeoutCalendar)
        review.rpe = 7
        let skipped = DayCloseout.finalReview(review, effortGiven: true, mood: 4)
        #expect(skipped.rpe == nil)
        #expect(skipped.mood == 4)
        review.completed = true
        #expect(DayCloseout.finalReview(review, effortGiven: true, mood: nil).rpe == 7)
        #expect(DayCloseout.finalReview(review, effortGiven: false, mood: nil).rpe == nil)
        review.rpe = nil
        #expect(DayCloseout.finalReview(review, effortGiven: true, mood: 9).rpe == 5)
        #expect(DayCloseout.finalReview(review, effortGiven: true, mood: 9).mood == 5)
    }

    @Test func anEmptyNoteIsNotKept() {
        #expect(!DayCloseout.keepsNote(text: "  \n", tags: [], mood: nil))
        #expect(DayCloseout.keepsNote(text: "", tags: [.stress], mood: nil))
        #expect(DayCloseout.keepsNote(text: "", tags: [], mood: 3))
    }

    @Test func summaryShowsMovementTagsAndMoodButNeverTheText() {
        #expect(DayCloseout.summary(review: nil, note: nil) == nil)
        var review = DayCloseout.startingReview(day: evening, planned: planned, calendar: closeoutCalendar)
        review.completed = true
        review.rpe = 5
        review.mood = 2
        let note = ContextEvent(date: evening, tags: [.stress], mood: 4, text: "Stressiger Tag im Büro")
        let text = DayCloseout.summary(review: review, note: note) ?? ""
        #expect(text.contains("Erledigt · 40 min · Anstrengung 5/10"))
        #expect(text.contains("Stimmung 4/5"))
        #expect(!text.contains("Büro"))
        #expect(DayCloseout.summary(review: review, note: nil)?.contains("Stimmung 2/5") == true)
        #expect(DayCloseout.summary(review: nil, note: note)?.hasPrefix("Bewegung") == false)
    }
}
