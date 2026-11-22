import BackgroundTasks
import Foundation
import Observation
import os
import PulseCore
import SwiftData
import UIKit

/// One automatic check-in of the companion, kept on the device.
@Model
final class StoredCheckIn {
    var id: UUID = UUID()
    var date: Date = Date.distantPast
    var slotRaw: String = ""
    var headline: String = ""
    var text: String = ""
    var suggestion: String = ""
    var urgencyRaw: String = "none"
    /// `[CheckInMarker]` as JSON.
    var markersJSON: Data?
    /// "claude" or "local".
    var source: String = "local"
    var costUSD: Double = 0
    /// How it started: "foreground", "background", "manual".
    var trigger: String = ""
    /// `CheckInPolicy.fingerprint` of the facts it was based on; equal next time = nothing new.
    var fingerprint: String = ""
    /// A notification was sent for it.
    var notified: Bool = false
    /// Newest measurement it was based on.
    var dataThrough: Date?

    init(date: Date, slot: CheckInSlot, message: CheckInMessage, source: String, costUSD: Double, trigger: String) {
        id = UUID()
        self.date = date
        slotRaw = slot.rawValue
        headline = message.headline
        text = message.text
        suggestion = message.suggestion
        urgencyRaw = message.urgency.rawValue
        markersJSON = try? JSONEncoder().encode(message.markers)
        self.source = source
        self.costUSD = costUSD
        self.trigger = trigger
    }

    var slot: CheckInSlot { CheckInSlot(rawValue: slotRaw) ?? .morning }
    var urgency: CheckInUrgency { CheckInUrgency(rawValue: urgencyRaw) ?? .none }
    var markers: [CheckInMarker] {
        guard let markersJSON else { return [] }
        return (try? JSONDecoder().decode([CheckInMarker].self, from: markersJSON)) ?? []
    }
}

/// Record of the standing permission (P1-005): what goes where, how often, within which budget, under which
/// prompt version. A new row whenever any of it changes, including switching it off.
@Model
final class StoredConsentLog {
    var date: Date = Date.distantPast
    var enabled: Bool = false
    var recipient: String = ""
    /// Consented categories (raw values), sorted.
    var categories: [String] = []
    var cadence: String = ""
    var modelID: String = ""
    var monthlyBudgetUSD: Double = 0
    var maxSendsPerMonth: Int = 0
    var promptVersion: Int = 0

    init(date: Date, enabled: Bool, recipient: String, categories: [String], cadence: String, modelID: String,
         monthlyBudgetUSD: Double, maxSendsPerMonth: Int, promptVersion: Int) {
        self.date = date
        self.enabled = enabled
        self.recipient = recipient
        self.categories = categories
        self.cadence = cadence
        self.modelID = modelID
        self.monthlyBudgetUSD = monthlyBudgetUSD
        self.maxSendsPerMonth = maxSendsPerMonth
        self.promptVersion = promptVersion
    }

    var signature: String {
        "\(enabled)|\(recipient)|\(categories.joined(separator: ","))|\(cadence)|\(modelID)|\(monthlyBudgetUSD)|\(maxSendsPerMonth)|\(promptVersion)"
    }
}

enum CheckInPersistence {
    static let models: [any PersistentModel.Type] = [StoredCheckIn.self, StoredConsentLog.self]
}

/// Settings of the active companion (concept §10, owner's answers of 2026-11-22).
struct CheckInSettings {
    static let enabledKey = "checkin.enabled"
    static let claudeKey = "checkin.useClaude"
    static let nameKey = "checkin.companionName"

    /// The companion is active by default; the owner wants it to speak up by itself.
    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    /// Standing permission to send the short summary to Claude (granted 2026-11-22).
    var useClaude: Bool {
        get { UserDefaults.standard.object(forKey: Self.claudeKey) as? Bool ?? true }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: Self.claudeKey) }
    }

    var name: String {
        get {
            let stored = UserDefaults.standard.string(forKey: Self.nameKey)?.trimmingCharacters(in: .whitespaces) ?? ""
            return stored.isEmpty ? Self.defaultName : stored
        }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: Self.nameKey) }
    }

    static let defaultName = "Nox"
}

/// The active companion: looks at the values in the morning, at midday and in the evening without being
/// asked and keeps the ring history fresh in the background. Checks run silently; a notification only
/// follows something new that matters (`CheckInPolicy`). iOS decides when background time is granted, so
/// two paths lead here: the app coming to the foreground and a background refresh.
@MainActor
@Observable
final class CheckInService {
    nonisolated static let taskIdentifier = "de.sommerlabs.pulseone.checkin"
    nonisolated static let notificationPrefix = "checkin."
    /// Background refreshes are asked for at least this often so the ring history stays current.
    static let refreshInterval: TimeInterval = 30 * 60
    /// Hard daily cap of automatic Claude calls, also for "Jetzt prüfen" (keeps the cost bounded).
    static let maxClaudeCallsPerDay = 4

    /// The live instance for the background task handler (set once at launch).
    static weak var current: CheckInService?

    private(set) var latest: StoredCheckIn?
    private(set) var isRunning = false
    var settings = CheckInSettings()
    let schedule = CheckInSchedule.standard

    private let context: ModelContext
    private let ring: RingStore
    private let sources: SourcesStore
    private let profile: ProfileStore
    private let companion: CompanionStore
    private let engine: IntelligenceEngine
    private let options: LaunchOptions
    private let log = Logger(subsystem: "de.sommerlabs.pulseone", category: "checkin")
    @ObservationIgnored private var calendar: Calendar = .current

    init(context: ModelContext, ring: RingStore, sources: SourcesStore, profile: ProfileStore, companion: CompanionStore,
         options: LaunchOptions = .current) {
        self.context = context
        self.ring = ring
        self.sources = sources
        self.profile = profile
        self.companion = companion
        self.options = options
        engine = IntelligenceEngine()
        if options.usesTestScenario { seedTestScenario() }
        latest = fetchLatest()
    }

    // MARK: Running

    /// Runs the slot that is due now, if any. Called when the app becomes active and from the background task.
    func runIfDue(trigger: String) async {
        guard settings.enabled, !options.isUITesting, !isRunning else { return }
        let now = Date()
        let wake = companion.today?.night.wake.time
        guard let slot = schedule.dueSlot(now: now, wake: wake, lastRuns: lastRuns(on: now), calendar: calendar) else { return }
        await run(slot: slot, trigger: trigger)
    }

    /// Runs a check-in for `slot` now ("Jetzt prüfen" or a due slot). P1-005: nothing new → no Claude call and
    /// no notification; stale data are said to be stale and never shown as the current night.
    func run(slot: CheckInSlot, trigger: String) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        let now = Date()
        let name = settings.name
        let owner = sources.ownerProfileID
        let analysisContext = engine.reportContext(.daily, modelContext: context, owner: owner, profile: profile.profile)
        let newest = engine.samples(in: context, owner: owner, days: 3).map(\.end).max()
        let stale = CheckInPolicy.isStale(newestSample: newest, now: now)
        let fingerprint = CheckInPolicy.fingerprint(analysisContext)
        let previous = fetchLatest()
        if trigger != "manual", let previous, previous.fingerprint == fingerprint, calendar.isDate(previous.date, inSameDayAs: now) {
            log.info("Check-in \(slot.rawValue, privacy: .public) skipped: nothing new")
            return
        }
        let local = stale ? CheckInPolicy.staleMessage(newestSample: newest, now: now)
            : LocalCheckIn.compose(slot: slot, context: analysisContext, name: name)
        var message = local
        var source = "local"
        var cost = 0.0
        let consented = recordConsent(now: now)
        let route = CheckInGate.route(.init(
            sendingEnabled: consented, consentedCategories: engine.settings.consent.count, testMode: options.isUITesting,
            claudeCallsToday: checkIns(on: now).filter { $0.source == "claude" }.count,
            maxClaudeCallsPerDay: Self.maxClaudeCallsPerDay, budgetBlocker: engine.checkInBlocker(modelContext: context),
            fingerprint: fingerprint, lastFingerprint: previous?.fingerprint, stale: stale,
            hasFacts: !analysisContext.facts.isEmpty))
        if route == .claude {
            // A provider error returns nil and keeps the local message.
            let answer = await engine.runCheckIn(slot: slot, context: analysisContext, name: name, modelContext: context)
            let merged = CheckInGate.merge(local: local, claude: answer?.message)
            message = merged.message
            if merged.fromClaude {
                source = "claude"
                cost = answer?.record.costUSD ?? 0
            }
        } else if case .local(let reason) = route {
            log.info("Check-in stays local: \(reason.rawValue, privacy: .public)")
        }
        let record = StoredCheckIn(date: now, slot: slot, message: message, source: source, costUSD: cost, trigger: trigger)
        record.fingerprint = fingerprint
        record.dataThrough = newest
        let freshNight = slot == .morning && !stale && !checkIns(on: now).contains { $0.slot == .morning && $0.dataThrough != nil }
        if UIApplication.shared.applicationState != .active,
           CheckInPolicy.shouldNotify(message, previous: previous.map(Self.message(of:)), freshNight: freshNight,
                                      pushesToday: checkIns(on: now).filter(\.notified).map(\.date), now: now, calendar: calendar) {
            record.notified = true
            await notify(record, name: name)
        }
        context.insert(record)
        try? context.save()
        latest = record
        log.info("Check-in \(slot.rawValue, privacy: .public) from \(source, privacy: .public) (\(trigger, privacy: .public))")
    }

    static func message(of record: StoredCheckIn) -> CheckInMessage {
        CheckInMessage(headline: record.headline, text: record.text, suggestion: record.suggestion, urgency: record.urgency,
                       markers: record.markers)
    }

    /// Writes a consent row when the standing permission or its terms changed. Returns whether sending is allowed.
    @discardableResult
    func recordConsent(now: Date) -> Bool {
        let intelligence = engine.settings
        let enabled = settings.enabled && settings.useClaude
        let entry = StoredConsentLog(
            date: now, enabled: enabled, recipient: "Anthropic Claude API (eigener Schlüssel)",
            categories: intelligence.consent.map(\.rawValue).sorted(),
            cadence: "bis zu 3 Prüfungen am Tag, nur bei neuen Werten",
            modelID: intelligence.model == .haiku ? ClaudeModel.haiku.id : ClaudeModel.sonnet.id,
            monthlyBudgetUSD: intelligence.monthlyBudgetUSD, maxSendsPerMonth: intelligence.maxSendsPerMonth,
            promptVersion: CheckInPrompts.version)
        var descriptor = FetchDescriptor<StoredConsentLog>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        let last = (try? context.fetch(descriptor))?.first
        if last?.signature != entry.signature {
            context.insert(entry)
            try? context.save()
        }
        return enabled
    }

    // MARK: Background

    /// Registers the refresh handler. Must run before the app finishes launching.
    nonisolated static func registerBackgroundTask() {
        _ = BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: .main) { task in
            let box = BackgroundTaskBox(task: task)
            let work = Task { @MainActor in
                if let service = CheckInService.current {
                    await service.backgroundRefresh()
                }
                box.task.setTaskCompleted(success: true)
            }
            box.task.expirationHandler = { work.cancel() }
        }
    }

    /// Fetches fresh ring and Apple Health data, runs a due check-in and asks for the next refresh.
    func backgroundRefresh() async {
        scheduleBackgroundRefresh()
        guard !options.usesTestScenario else { return }
        ring.syncIfDue()
        // A history fetch takes a few seconds over Bluetooth; iOS grants about 30 s in total.
        try? await Task.sleep(for: .seconds(12))
        await sources.syncHealthIfDue()
        await runIfDue(trigger: "background")
    }

    /// Asks iOS for the next background refresh: at the next check-in, at the latest in 30 minutes.
    func scheduleBackgroundRefresh() {
        guard !options.isUITesting else { return }
        let now = Date()
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = min(schedule.nextStart(after: now, calendar: calendar), now.addingTimeInterval(Self.refreshInterval))
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            log.error("Background refresh not scheduled: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Notifications

    private func notify(_ record: StoredCheckIn, name: String) async {
        let body = record.suggestion.isEmpty ? record.text : record.text + " " + record.suggestion
        let soon = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date().addingTimeInterval(2))
        try? await CompanionNotifications.add(id: Self.notificationPrefix + "message." + record.id.uuidString,
                                              title: "\(name): \(record.headline)", body: body, components: soon)
    }

    /// Asks for notification permission once the companion is active (no-op when already decided).
    func requestNotificationPermission() async {
        guard settings.enabled, !options.isUITesting else { return }
        _ = await CompanionNotifications.ensureAuthorized()
    }

    // MARK: Data

    func checkIns(on day: Date) -> [StoredCheckIn] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let descriptor = FetchDescriptor<StoredCheckIn>(predicate: #Predicate { $0.date >= start && $0.date < end },
                                                        sortBy: [SortDescriptor(\.date)])
        return (try? context.fetch(descriptor)) ?? []
    }

    private func lastRuns(on day: Date) -> [CheckInSlot: Date] {
        var runs: [CheckInSlot: Date] = [:]
        for record in checkIns(on: day) where record.trigger != "manual" {
            runs[record.slot] = record.date
        }
        return runs
    }

    private func fetchLatest() -> StoredCheckIn? {
        var descriptor = FetchDescriptor<StoredCheckIn>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// Screenshot runs show one check-in so the card is visible (test view with banner).
    private func seedTestScenario() {
        guard fetchLatest() == nil else { return }
        let message = CheckInMessage(
            headline: "Solide Nacht",
            text: "7 Stunden 10 geschlafen, Ruhepuls 54, vier unter deinem Üblichen. Dein Körper ist bereit für mehr.",
            suggestion: "Starte jetzt mit 10 Minuten Aktivierung.",
            urgency: .none,
            markers: [CheckInMarker(symbol: .sleep, metric: SampleKind.sleepDuration.rawValue, text: "7 h 10 Schlaf"),
                      CheckInMarker(symbol: .below, metric: SampleKind.restingHeartRate.rawValue, text: "Ruhepuls 54, üblich 58"),
                      CheckInMarker(symbol: .insight, metric: "", text: "Beste Nacht seit Dienstag")])
        let morning = calendar.date(bySettingHour: 7, minute: 15, second: 0, of: Date()) ?? Date()
        context.insert(StoredCheckIn(date: morning, slot: .morning, message: message, source: "claude", costUSD: 0, trigger: "background"))
    }
}

/// Carries the non-Sendable BGTask into the main-actor task. The handler runs on the main queue
/// (`using: .main`) and the task is only touched there.
private final class BackgroundTaskBox: @unchecked Sendable {
    let task: BGTask
    init(task: BGTask) { self.task = task }
}
