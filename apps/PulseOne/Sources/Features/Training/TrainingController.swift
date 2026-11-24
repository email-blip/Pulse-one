import Foundation
import Observation
import PulseCore
import UserNotifications

/// Drives the one running `WorkoutSession` (contract). Screen, voice and the phase-end notification all read this
/// session; time comes only from its timestamps, so a locked or relaunched phone shows the right remaining time.
/// The running session is kept in `UserDefaults` until it ends (no health values in it, only steps and times).
@MainActor
@Observable
final class TrainingController {
    static let shared = TrainingController()

    private(set) var session: WorkoutSession?
    private(set) var title = ""
    private(set) var skipped: Set<String> = []
    /// Shown full screen while true (`TrainingSessionCover`).
    var isPresented = false
    /// Filled when the session ended; the summary screen saves it.
    private(set) var summary: WorkoutSummary?

    @ObservationIgnored private let audio: AudioCoordinator
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var spokenCountdowns: Set<WorkoutCueToken> = []
    /// Notification changes run one after another, so an older schedule can never land after a newer cancel.
    @ObservationIgnored private var notificationTask: Task<Void, Never>?
    private static let storageKey = "training.active"
    static let finishedDayKey = "training.lastFinishedAt"

    init(audio: AudioCoordinator = .shared) {
        self.audio = audio
        audio.trainingValidator = { [weak self] token in self?.session?.accepts(token) ?? false }
        audio.addInterruptionHandler { [weak self] in self?.pause() }
        restore()
    }

    private var now: Date { Date.now }

    /// A started session that was not closed yet (running, paused, or ended with the summary not saved).
    var hasOpenSession: Bool {
        guard let session else { return false }
        return session.state != .idle
    }

    // MARK: Opening

    /// Opens a prepared session (idle until the person taps Start). An unfinished session is kept instead.
    func open(_ newSession: WorkoutSession, title: String) {
        if !hasOpenSession {
            session = newSession
            self.title = title
            skipped = []
            summary = nil
            spokenCountdowns = []
            persist()
        }
        isPresented = true
    }

    /// Back to a running or paused session after a relaunch.
    func reopen() {
        guard session != nil else { return }
        isPresented = true
        refresh()
    }

    // MARK: Controls

    func start() {
        guard var session, session.state == .idle else { return }
        session.start(at: now)
        apply(session)
    }

    func pause() {
        guard var session, session.state == .running else { return }
        session.pause(at: now)
        audio.cancelTraining()
        apply(session)
    }

    func resume() {
        guard var session, session.state == .paused else { return }
        session.resume(at: now)
        apply(session)
    }

    /// A repetition set is done (or a timed phase ends early by hand).
    func next() {
        guard var session, session.state == .running || session.state == .paused else { return }
        audio.cancelTraining()
        session.advance(at: now)
        apply(session)
    }

    func skip() {
        guard var session, session.state == .running || session.state == .paused, let step = session.currentStep else { return }
        if session.phase == .work { skipped.insert(step.id) }
        audio.cancelTraining()
        session.skip(at: now)
        apply(session)
    }

    /// "Beenden": ends now and opens the summary; nothing is saved until the person saves it there.
    func finish() {
        guard var session else { return }
        audio.cancelTraining()
        if session.state == .idle {
            close()
            return
        }
        session.cancel(at: now)
        apply(session)
    }

    func setExertion(_ value: Int?) {
        summary?.perceivedExertion = value
        session?.perceivedExertion = value
    }

    func setReaction(_ reaction: WorkoutReaction?) {
        summary?.reaction = reaction
    }

    /// Closes the screen and forgets the session (after saving or discarding the summary).
    func close() {
        stopTicker()
        let previous = notificationTask
        notificationTask = Task {
            await previous?.value
            await TrainingNotifications.cancelPhaseEnd()
        }
        session = nil
        summary = nil
        skipped = []
        isPresented = false
        persist()
    }

    func markSaved(at date: Date) {
        UserDefaults.standard.set(date, forKey: Self.finishedDayKey)
    }

    // MARK: Time

    /// Catches up on phase ends (also after the phone was locked), speaks the pending cue, plans the notification.
    func refresh() {
        guard var session else { return }
        let before = session
        session.catchUp(to: now)
        if session != before {
            apply(session)
        } else {
            announce()
        }
    }

    private func apply(_ updated: WorkoutSession) {
        session = updated
        if updated.state == .finished || updated.state == .cancelled {
            if summary == nil {
                summary = WorkoutSummary.make(from: updated, title: title, skippedStepIDs: skipped)
            }
        }
        announce()
        persist()
        schedulePhaseEnd()
        updateTicker()
    }

    /// Hands the pending announcement (and the ten-second countdown) to the voice, then marks it spoken.
    private func announce() {
        guard var session else { return }
        let moment = now
        if session.announcement != .silent {
            if let cue = WorkoutCuePlanner.cue(for: session, at: moment) {
                audio.say(cue.text, channel: .training, sensitive: false, token: cue.token)
            }
            session.announcement = .silent
            self.session = session
        }
        if let countdown = WorkoutCuePlanner.countdown(for: session, at: moment, alreadySpoken: spokenCountdowns) {
            spokenCountdowns.insert(countdown.token)
            audio.say(countdown.text, channel: .training, sensitive: false, token: countdown.token)
        }
    }

    private func schedulePhaseEnd() {
        let snapshot = session
        let previous = notificationTask
        notificationTask = Task {
            await previous?.value
            await TrainingNotifications.cancelPhaseEnd()
            guard let snapshot, let end = snapshot.scheduledPhaseEnd,
                  let notice = WorkoutCuePlanner.phaseEndNotice(for: snapshot) else { return }
            await TrainingNotifications.schedulePhaseEnd(at: end, title: notice.title, body: notice.body)
        }
    }

    private func updateTicker() {
        if session?.state == .running {
            guard ticker == nil else { return }
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    self?.refresh()
                }
            }
        } else {
            stopTicker()
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    // MARK: Persistence

    private struct Stored: Codable {
        let session: WorkoutSession
        let title: String
        let skipped: Set<String>
    }

    private func persist() {
        let defaults = UserDefaults.standard
        guard let session, session.state != .idle else {
            defaults.removeObject(forKey: Self.storageKey)
            return
        }
        if let data = try? JSONEncoder().encode(Stored(session: session, title: title, skipped: skipped)) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private func restore() {
        guard !LaunchOptions.current.isUITesting,
              let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        session = stored.session
        title = stored.title
        skipped = stored.skipped
        if stored.session.state == .finished || stored.session.state == .cancelled {
            summary = WorkoutSummary.make(from: stored.session, title: stored.title, skippedStepIDs: stored.skipped)
        }
        // A session that ran while the app was closed keeps running from its timestamps.
        updateTicker()
    }
}

/// The local notification at the end of the running phase (lock screen). Asked for by the person by starting the
/// session, so quiet hours do not apply; inside the app the voice speaks instead (see `NotificationDelegate`).
enum TrainingNotifications {
    static let prefix = "training.phase."
    static let phaseEndID = prefix + "end"

    static func schedulePhaseEnd(at date: Date, title: String, body: String) async {
        guard !LaunchOptions.current.isUITesting else { return }
        let interval = date.timeIntervalSinceNow
        guard interval > 1, await CompanionNotifications.ensureAuthorized() else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: phaseEndID, content: content, trigger: trigger))
    }

    static func cancelPhaseEnd() async {
        guard !LaunchOptions.current.isUITesting else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [phaseEndID])
    }
}
