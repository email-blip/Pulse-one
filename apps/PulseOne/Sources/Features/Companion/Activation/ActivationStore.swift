import Foundation
import Observation
import PulseCore
import SwiftData

/// State of the companion's "Aktivierung": settings and levels, today's planned sessions, finished sessions,
/// the activity status from today's steps, and the session/checkpoint notifications. The core decides
/// (`ActivationPlanner`, `ActivationProgression`, `ActivityCheck`); this type only does I/O.
/// In UI tests it never schedules notifications.
@MainActor
@Observable
final class ActivationStore {
    /// All activation notifications share this prefix (slot sessions and activity checkpoints).
    static let notificationPrefix = "companion.activation."
    static let checkpointPrefix = "companion.activation.check."
    /// A checkpoint is dropped when a session finished within this time before it.
    static let checkpointQuietWindow: TimeInterval = 2 * 3600
    /// Wake time used for checkpoints when the companion has none for today (07:00).
    static let defaultWakeHour = 7

    private(set) var record: ActivationSettingsRecord
    private(set) var coach = CoachPreferences()
    /// Today's planned sessions for the enabled slots (morning, midday, evening), empty when switched off.
    private(set) var plans: [ActivationPlan] = []
    /// Sessions finished today (any slot), oldest first.
    private(set) var doneToday: [ActivationResult] = []
    private(set) var activityStatus: ActivityStatus = .unknown
    private(set) var dayType: CompanionDayType = .notEnoughData
    private(set) var infectionLevel: InfectionLevel = .none
    /// Today's wake time from the companion (confirmed or estimated), nil when unknown.
    private(set) var wakeToday: Date?
    /// False when activation notifications could not be scheduled (permission off or an error).
    private(set) var remindersDelivered = true

    private let context: ModelContext
    private let isUITesting: Bool
    @ObservationIgnored private var calendar: Calendar = .current

    init(context: ModelContext) {
        self.context = context
        isUITesting = LaunchOptions.current.isUITesting
        let existing = (try? context.fetch(FetchDescriptor<ActivationSettingsRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])))?.first
        if let existing {
            record = existing
        } else {
            let created = ActivationSettingsRecord()
            context.insert(created)
            try? context.save()
            record = created
        }
    }

    // MARK: Settings and levels

    var settings: ActivationSettings { record.settings }
    var profile: ActivationProfile { record.profile }

    func save(settings: ActivationSettings, now: Date) {
        var clean = settings
        clean.morningMinutes = min(max(clean.morningMinutes, ActivationSettings.morningRange.lowerBound),
                                   ActivationSettings.morningRange.upperBound)
        clean.shortMinutes = min(max(clean.shortMinutes, ActivationSettings.shortRange.lowerBound),
                                 ActivationSettings.shortRange.upperBound)
        record.settings = clean
        touchAndSave()
        replan(now: now)
    }

    /// The person's level in a family, or the start level the planner would use.
    func level(_ family: ActivationFamily, now: Date) -> ActivationLevel {
        profile.levels[family] ?? ActivationLibrary.startLevel(family, coach: coach, now: now)
    }

    func hasOwnLevel(_ family: ActivationFamily) -> Bool { profile.levels[family] != nil }

    /// Back to the start level of the fitness level (from the Coach settings).
    func resetLevel(_ family: ActivationFamily, now: Date) {
        var current = profile
        current.levels[family] = nil
        record.profile = current
        touchAndSave()
        replan(now: now)
    }

    // MARK: Refresh

    /// Reads the Coach preferences, today's sessions and steps, and plans today's sessions.
    func refresh(now: Date, profileID: UUID?, day: CompanionDay?) {
        calendar = .current
        if let day {
            dayType = day.dayType
            infectionLevel = day.infection.level
            wakeToday = day.night.wake.time.flatMap { calendar.isDate($0, inSameDayAs: now) ? $0 : nil }
        }
        coach = CoachRepository(context: context).settings()?.preferences ?? CoachPreferences()
        doneToday = loadDoneToday(now: now)
        activityStatus = loadActivityStatus(now: now, profileID: profileID)
        replan(now: now)
    }

    private func replan(now: Date) {
        guard settings.isEnabled else {
            plans = []
            return
        }
        plans = Self.enabledSlots(settings).map { plan(for: $0, dayType: dayType, infectionLevel: infectionLevel, now: now) }
    }

    static func enabledSlots(_ settings: ActivationSettings) -> [ActivationSlot] {
        var slots: [ActivationSlot] = [.morning]
        if settings.middayEnabled { slots.append(.midday) }
        if settings.eveningEnabled { slots.append(.evening) }
        return slots
    }

    func plan(for slot: ActivationSlot, dayType: CompanionDayType, infectionLevel: InfectionLevel, now: Date) -> ActivationPlan {
        let input = ActivationInput(slot: slot, now: now, calendar: calendar, settings: settings, profile: profile,
                                    coach: coach, dayType: dayType, infectionLevel: infectionLevel, doneToday: doneToday)
        return ActivationPlanner.plan(input)
    }

    /// Plan for a slot with today's known day type.
    func plan(for slot: ActivationSlot, now: Date) -> ActivationPlan {
        if slot != .snack, let planned = plans.first(where: { $0.slot == slot }) { return planned }
        return plan(for: slot, dayType: dayType, infectionLevel: infectionLevel, now: now)
    }

    func isDone(_ slot: ActivationSlot) -> Bool {
        doneToday.contains { $0.plan.slot == slot }
    }

    /// Fixed time of a slot today (midday, evening); nil for the morning (after waking) and snacks.
    func time(of slot: ActivationSlot, now: Date) -> Date? {
        let s = settings
        switch slot {
        case .midday: return calendar.date(bySettingHour: s.middayHour, minute: s.middayMinute, second: 0, of: now)
        case .evening: return calendar.date(bySettingHour: s.eveningHour, minute: s.eveningMinute, second: 0, of: now)
        case .morning, .snack: return nil
        }
    }

    /// Next open midday/evening session still ahead today.
    func nextOpenPlan(now: Date) -> (plan: ActivationPlan, time: Date)? {
        for plan in plans where !isDone(plan.slot) {
            if let slotTime = time(of: plan.slot, now: now), slotTime > now { return (plan: plan, time: slotTime) }
        }
        return nil
    }

    /// First session of today that is not finished yet (any enabled slot).
    var firstOpenPlan: ActivationPlan? { plans.first { !isDone($0.slot) } }

    /// In-app hint after quiet hours; nil when switched off, active, or the data is too thin.
    func snackHint(now: Date) -> String? {
        guard settings.isEnabled, settings.activityReminders,
              ActivityCheck.shouldSuggestSnack(activityStatus, doneToday: doneToday, now: now) else { return nil }
        return ActivityCheck.hint(activityStatus)
    }

    // MARK: Results

    /// Stores a session, updates the levels and returns calm progress lines ("Bester Satz Liegestütze: 13").
    @discardableResult
    func save(result: ActivationResult, startedAt: Date) -> [String] {
        let day = calendar.startOfDay(for: result.finishedAt)
        let minutes = ActivationRun.minutes(from: startedAt, to: result.finishedAt)
        context.insert(ActivationSessionRecord(result: result, day: day, minutes: minutes))
        let old = profile
        let updated = ActivationProgression.update(old, with: result, coach: coach, now: result.finishedAt)
        record.profile = updated
        touchAndSave()
        doneToday = loadDoneToday(now: result.finishedAt)
        replan(now: result.finishedAt)
        return Self.progressLines(old: old, new: updated)
    }

    static func progressLines(old: ActivationProfile, new: ActivationProfile) -> [String] {
        ActivationFamily.allCases.compactMap { family in
            guard let level = new.levels[family] else { return nil }
            return ActivationProgression.progressText(old.levels[family], level)
        }
    }

    // MARK: Notifications

    /// Replaces all pending activation notifications: today's midday/evening sessions (the morning is covered
    /// by the alarm) with the plan summary, and up to two activity checkpoints. A checkpoint is left out when
    /// the last hours were active and it is close, or a session finished in the two hours before it.
    /// Nothing in UI tests. These do not count toward the companion's nudge cap (owner request).
    func scheduleReminders(now: Date, dayType: CompanionDayType, infection: InfectionLevel, wake: Date?) async {
        guard !isUITesting else { return }
        await CompanionNotifications.removePending(ids: [], prefix: Self.notificationPrefix)
        guard settings.isEnabled else { return }

        var requests: [(id: String, title: String, body: String, date: Date)] = []
        for slot in Self.enabledSlots(settings) where slot != .morning && !isDone(slot) {
            guard let slotTime = time(of: slot, now: now), slotTime > now else { continue }
            let slotPlan = plan(for: slot, dayType: dayType, infectionLevel: infection, now: now)
            requests.append((id: Self.notificationPrefix + slot.rawValue, title: slot.title, body: slotPlan.summary, date: slotTime))
        }
        if settings.activityReminders {
            let wakeTime = wake ?? wakeToday ?? calendar.date(bySettingHour: Self.defaultWakeHour, minute: 0, second: 0, of: now) ?? now
            let checkpoints = ActivityCheck.checkpointTimes(wake: wakeTime, settings: settings, now: now, calendar: calendar)
            for (index, time) in checkpoints.prefix(2).enumerated() where time > now && keepsCheckpoint(time, now: now) {
                requests.append((id: Self.checkpointPrefix + String(index), title: "Bewegungs-Check",
                                 body: "Kurzer Bewegungs-Check: Wenn du länger gesessen hast, passt jetzt ein 2-Minuten-Snack.",
                                 date: time))
            }
        }
        guard !requests.isEmpty else { return }
        guard await CompanionNotifications.ensureAuthorized() else {
            remindersDelivered = false
            return
        }
        var allScheduled = true
        for request in requests {
            do {
                try await CompanionNotifications.add(id: request.id, title: request.title, body: request.body,
                                                     components: NudgeScheduler.components(for: request.date, calendar: calendar))
            } catch {
                allScheduled = false
            }
        }
        remindersDelivered = allScheduled
    }

    /// False when the checkpoint would only repeat what already happened: a session finished in the two hours
    /// before it, or the last hours were active and the checkpoint is within the next two hours.
    private func keepsCheckpoint(_ time: Date, now: Date) -> Bool {
        let window = Self.checkpointQuietWindow
        if doneToday.contains(where: { $0.finishedAt <= time && time.timeIntervalSince($0.finishedAt) < window }) {
            return false
        }
        if activityStatus == .active && time.timeIntervalSince(now) <= window { return false }
        return true
    }

    // MARK: Loading

    private func loadDoneToday(now: Date) -> [ActivationResult] {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let descriptor = FetchDescriptor<ActivationSessionRecord>(
            predicate: #Predicate { $0.day >= start && $0.day < end },
            sortBy: [SortDescriptor(\.finishedAt)])
        return ((try? context.fetch(descriptor)) ?? []).compactMap(\.result)
    }

    private func loadActivityStatus(now: Date, profileID: UUID?) -> ActivityStatus {
        let samples = SampleReader(context: context).samples([.steps], since: calendar.startOfDay(for: now),
                                                             profileID: profileID)
        let hourly = ActivityCheck.hourlySteps(samples, day: now, calendar: calendar)
        return ActivityCheck.status(hourlySteps: hourly.isEmpty ? nil : hourly, now: now, wakeHours: coach.wakeHours,
                                    calendar: calendar)
    }

    private func touchAndSave() {
        record.updatedAt = Date()
        try? context.save()
    }
}
