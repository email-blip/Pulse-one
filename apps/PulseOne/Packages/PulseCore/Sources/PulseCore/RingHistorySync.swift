import Foundation

/// Fetches the ring's stored history one request at a time, in Gadgetbridge's order:
/// steps → heart rate → stress → SpO₂ → sleep → HRV. Pure state machine: the Bluetooth layer
/// sends what it returns and feeds back answers or a timeout.
///
/// Model independent: a step runs only when `RingFeatureSupport` allows the feature. A feature
/// whose first request stays unanswered is marked unsupported and its other days are skipped,
/// so a ring without, say, HRV history costs one timeout and nothing else.
public struct RingHistorySync: Sendable {
    public enum Step: Equatable, Sendable {
        case activity(daysAgo: Int)
        case heartRate(daysAgo: Int)
        case stress
        case spo2
        case sleep
        case hrv(daysAgo: Int)

        public var feature: RingFeature {
            switch self {
            case .activity: .steps
            case .heartRate: .heartRate
            case .stress: .stress
            case .spo2: .spo2
            case .sleep: .sleep
            case .hrv: .hrv
            }
        }

        public var title: String {
            switch self {
            case .activity(let days): "Schritte, \(Self.dayLabel(days))"
            case .heartRate(let days): "Puls, \(Self.dayLabel(days))"
            case .stress: "Stresswert, heute"
            case .spo2: "Sauerstoff, letzte Tage"
            case .sleep: "Schlaf, letzte Nächte"
            case .hrv(let days): "HRV, \(Self.dayLabel(days))"
            }
        }

        static func dayLabel(_ daysAgo: Int) -> String {
            switch daysAgo {
            case 0: "heute"
            case 1: "gestern"
            default: "vor \(daysAgo) Tagen"
            }
        }
    }

    public enum Channel: Sendable, Equatable {
        case uart
        case bigData
    }

    public struct Request: Equatable, Sendable {
        public let step: Step
        public let channel: Channel
        public let packet: [UInt8]
    }

    /// Result per feature, for the user and the diagnosis.
    public struct Report: Equatable, Sendable {
        public var values: [RingFeature: Int] = [:]
        public var silent: Set<RingFeature> = []
        public var finished = false

        public var summary: String {
            let parts = RingFeature.allCases.compactMap { feature -> String? in
                if silent.contains(feature) { return "\(feature.title): keine Antwort" }
                return values[feature].map { "\(feature.title): \($0)" }
            }
            return parts.isEmpty ? "Keine gespeicherten Werte auf dem Ring" : parts.joined(separator: " · ")
        }
    }

    public private(set) var support: RingFeatureSupport
    public private(set) var observations: [RawObservation] = []
    /// Sleep phases of the nights the ring sent, as real intervals (`SleepSegment`).
    public private(set) var sleepSegments: [SleepSegment] = []
    public private(set) var report = Report()
    public private(set) var current: Step?

    private var queue: [Step]
    private let mapper: RingHistoryMapper
    private var dayLog: DayLogAccumulator?
    private var activity = ActivityAccumulator()
    private var bigData = BigDataAssembler()
    private var answered = false

    /// - Parameters:
    ///   - days: how many days back (1 = today only, at most 7 like Gadgetbridge).
    ///   - hasBigDataChannel: the second service (SpO₂, sleep) was found on the ring.
    public init(days: Int, support: RingFeatureSupport, hasBigDataChannel: Bool, mapper: RingHistoryMapper) {
        let range = 0..<min(max(days, 1), 7)
        var steps: [Step] = range.map { .activity(daysAgo: $0) }
        steps += range.map { .heartRate(daysAgo: $0) }
        steps.append(.stress)
        if hasBigDataChannel { steps += [.spo2, .sleep] }
        steps += range.map { .hrv(daysAgo: $0) }
        var support = support
        if !hasBigDataChannel {
            support.markSilent(.spo2)
            support.markSilent(.sleep)
        }
        self.support = support
        self.queue = steps.filter { support.mayUse($0.feature) }
        self.mapper = mapper
    }

    public var isFinished: Bool { report.finished }

    /// Steps after the current one.
    public var remaining: Int { queue.count }

    /// The first request; nil when nothing is to be fetched.
    public mutating func start() -> Request? { advance() }

    /// Feeds a decoded UART answer. Returns the next request when the current step finished.
    public mutating func handle(_ response: ColmiProtocol.Response) -> Request? {
        guard let current, case .history(let log, let packet) = response else { return nil }
        switch (current, log) {
        case (.activity, .activity):
            guard activity.feed(packet) else { return nil }
            answered = true
            guard activity.isComplete else { return nil }
            add(mapper.activity(activity.entries), for: .steps)
        case (.heartRate(let days), .heartRate), (.hrv(let days), .hrv):
            return feedDayLog(packet, log: log, daysAgo: days)
        case (.stress, .stress):
            return feedDayLog(packet, log: log, daysAgo: 0)
        default:
            return nil
        }
        return advance()
    }

    /// Feeds one notification of the big-data channel.
    public mutating func handleBigData(_ chunk: [UInt8]) -> Request? {
        guard let current, current == .spo2 || current == .sleep, let packet = bigData.feed(chunk) else { return nil }
        answered = true
        if current == .spo2 {
            add(mapper.spo2(ColmiHistory.parseSpO2(packet)), for: .spo2)
        } else {
            let sessions = ColmiHistory.parseSleep(packet)
            sleepSegments += mapper.sleepSegments(sessions)
            add(mapper.sleep(sessions), for: .sleep)
        }
        return advance()
    }

    /// The current step got no (complete) answer in time. Keeps what arrived, moves on.
    public mutating func timeout() -> Request? {
        guard let current else { return nil }
        if !answered {
            support.markSilent(current.feature)
            if support.state(of: current.feature) == .unsupported {
                report.silent.insert(current.feature)
                queue.removeAll { $0.feature == current.feature }
            }
        } else if case .activity = current {
            add(mapper.activity(activity.entries), for: .steps)
        } else if let dayLog {
            collect(dayLog, step: current)
        }
        return advance()
    }

    private mutating func feedDayLog(_ packet: [UInt8], log: ColmiHistory.Log, daysAgo: Int) -> Request? {
        var accumulator = dayLog ?? DayLogAccumulator(log: log, expectedDayStart: expectedDayStart(daysAgo: daysAgo, log: log))
        guard accumulator.feed(packet) else { return nil }
        answered = true
        dayLog = accumulator
        guard accumulator.isComplete, let current else { return nil }
        collect(accumulator, step: current)
        return advance()
    }

    private func expectedDayStart(daysAgo: Int, log: ColmiHistory.Log) -> UInt32? {
        guard log == .heartRate,
              let day = mapper.calendar.date(byAdding: .day, value: -daysAgo, to: mapper.today) else { return nil }
        return ColmiHistory.ringMidnight(of: day, calendar: mapper.calendar)
    }

    private mutating func collect(_ accumulator: DayLogAccumulator, step: Step) {
        let daysAgo: Int
        switch step {
        case .heartRate(let days), .hrv(let days): daysAgo = days
        default: daysAgo = 0
        }
        add(mapper.dayLog(accumulator, daysAgo: daysAgo), for: step.feature)
    }

    private mutating func add(_ items: [RawObservation], for feature: RingFeature) {
        observations += items
        report.values[feature, default: 0] += items.count
        support.markAnswered(feature)
    }

    private mutating func advance() -> Request? {
        dayLog = nil
        activity = ActivityAccumulator()
        bigData.reset()
        answered = false
        guard !queue.isEmpty else {
            current = nil
            report.finished = true
            return nil
        }
        let step = queue.removeFirst()
        current = step
        return Self.request(for: step, mapper: mapper)
    }

    static func request(for step: Step, mapper: RingHistoryMapper) -> Request {
        switch step {
        case .activity(let days):
            Request(step: step, channel: .uart, packet: ColmiHistory.activityRequest(daysAgo: days))
        case .heartRate(let days):
            Request(step: step, channel: .uart, packet: ColmiHistory.heartRateLogRequest(
                day: mapper.calendar.date(byAdding: .day, value: -days, to: mapper.today) ?? mapper.today, calendar: mapper.calendar))
        case .stress:
            Request(step: step, channel: .uart, packet: ColmiHistory.stressLogRequest())
        case .spo2:
            Request(step: step, channel: .bigData, packet: ColmiHistory.bigDataRequest(.spo2))
        case .sleep:
            Request(step: step, channel: .bigData, packet: ColmiHistory.bigDataRequest(.sleep))
        case .hrv(let days):
            Request(step: step, channel: .uart, packet: ColmiHistory.hrvLogRequest(daysAgo: days))
        }
    }
}

/// When to fetch the history again: on every connect, and while the app is open at most every
/// `minimumGap` (default 6 hours), so "daily" holds without background Bluetooth.
public struct RingSyncSchedule: Equatable, Sendable {
    public var minimumGap: TimeInterval

    public init(minimumGap: TimeInterval = 6 * 3_600) { self.minimumGap = minimumGap }

    public func isDue(lastSync: Date?, now: Date) -> Bool {
        guard let lastSync else { return true }
        return now.timeIntervalSince(lastSync) >= minimumGap || now < lastSync
    }

    /// The ring keeps about 7 days. From day 4 without a fetch the app reminds the user to connect.
    public static let reminderAfterDays = 4

    public func reminder(lastSync: Date?, now: Date, calendar: Calendar) -> String? {
        guard let lastSync,
              let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastSync),
                                                 to: calendar.startOfDay(for: now)).day,
              days >= Self.reminderAfterDays else { return nil }
        return "Verlauf zuletzt vor \(days) Tagen abgerufen. Der Ring speichert nur etwa 7 Tage – bitte bald verbinden."
    }

    /// Days to fetch: since the last sync plus one overlap day, between 2 and 7 (first sync: 7).
    public func days(lastSync: Date?, now: Date, calendar: Calendar) -> Int {
        guard let lastSync else { return 7 }
        let gap = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastSync), to: calendar.startOfDay(for: now)).day ?? 7
        return min(max(gap + 1, 2), 7)
    }
}
