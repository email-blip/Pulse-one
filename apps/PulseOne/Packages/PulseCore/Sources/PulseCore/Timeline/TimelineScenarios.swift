import Foundation

// Synthetic test data for the Verlauf, the coach and QA (teams 03, 04, 06). Only for `-uiTesting YES`
// with the "Testansicht" banner; never shown as a ring measurement. The data runs through the real
// paths (sleep packet parser, ring mapper, normaliser, sync planner), so a scenario also tests them.

public enum TimelineScenario: String, CaseIterable, Sendable {
    /// One complete night with all four phases, pulse every 5 minutes, HRV, SpO₂, stress, steps.
    case fullNight
    /// The ring was off the finger for 70 minutes at night: no pulse, and a hole in the hypnogram.
    case nightWithGap
    /// The firmware sends a phase code we do not know (7); it stays `unknown`.
    case unknownPhaseCode
    /// The same ring history arrives twice; the store keeps every value once.
    case duplicateSync
    /// Measuring profile "Akku sparen": pulse only every 15 minutes, no SpO₂ and no stress.
    case batterySaverProfile
    /// The newest pulse is 18 hours old (ring not synced since yesterday).
    case staleValue
    /// Pulse at irregular distances (live measurement plus history).
    case irregularSpacing
    /// Night of the switch to summer time (29 March 2026, Europe/Berlin): the clock jumps from 2 to 3.
    case daylightSavingNight
}

public struct TimelineScenarioData: Equatable, Sendable {
    public let scenario: TimelineScenario
    /// "Now" the scenario was built for; use it as the clock of the screen.
    public let now: Date
    public let points: [MeasurementPoint]
    public let segments: [SleepSegment]
}

public enum TimelineScenarios {
    public static let deviceID = "testansicht"
    public static let firmware = "Testansicht"

    /// Fixed clock for UI tests: 23 Nov 2026, 08:30 in `calendar`'s zone.
    public static func defaultNow(calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 8, minute: 30)) ?? Date(timeIntervalSince1970: 1_795_420_000)
    }

    public static func make(_ scenario: TimelineScenario, now requested: Date? = nil, calendar: Calendar) -> TimelineScenarioData {
        var calendar = calendar
        if scenario == .daylightSavingNight, let berlin = TimeZone(identifier: "Europe/Berlin") { calendar.timeZone = berlin }
        let now: Date
        if scenario == .daylightSavingNight {
            now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 8, minute: 0)) ?? defaultNow(calendar: calendar)
        } else {
            now = requested ?? defaultNow(calendar: calendar)
        }
        let mapper = RingHistoryMapper(deviceID: deviceID, calendar: calendar, today: now)
        let night = nightStages(for: scenario)
        let packet = sleepPacket([(daysAgo: 0, start: night.start, end: night.end, stages: night.stages)])
        var segments = mapper.sleepSegments(ColmiHistory.parseSleep(packet), firmware: firmware)
        if scenario == .nightWithGap { segments = cutHole(segments, from: 150, minutes: 70) }

        let raw = observations(for: scenario, mapper: mapper, calendar: calendar, now: now)
        var samples = normalise(raw, now: now)
        if scenario == .duplicateSync {
            // Second sync of the same history: the planner finds every value already stored.
            let stored = Dictionary(uniqueKeysWithValues: samples.map { ($0.deduplicationKey, $0) })
            let again = SyncCoordinator.plan(batch: SyncBatch(observations: raw), existing: stored,
                                             profiles: .constant(nil), importedAt: now)
            samples += again.inserts
            segments += SleepSegmentSync.plan(incoming: segments, existing: segments).inserts
        }
        let points = samples.map { MeasurementPoint($0, receivedAt: $0.receivedAt) }
        return TimelineScenarioData(scenario: scenario, now: now, points: points.sorted { $0.measuredAt < $1.measuredAt },
                                    segments: segments)
    }

    // MARK: Sleep

    /// Test night for UI scenarios (team 06): wall-clock start and end in minutes after midnight, the night
    /// ending on the day of `now`. The standard stage pattern is repeated and the last stage cut so the
    /// stages fill the night exactly. `unknownCode` puts one code-7 stage in (drawn as `unknown`).
    /// Goes through the real `BC 27` parser and mapper; marked with the test device and firmware.
    public static func sleepNight(startMinute: Int, endMinute: Int, now: Date, calendar: Calendar,
                                  unknownCode: Bool = false) -> [SleepSegment] {
        let pattern = nightStages(for: unknownCode ? .unknownPhaseCode : .fullNight).stages
        var total = endMinute - startMinute
        if total <= 0 { total += 24 * 60 }
        var stages: [(code: Int, minutes: Int)] = []
        var left = total
        var index = 0
        while left > 0 {
            let stage = pattern[index % pattern.count]
            stages.append((stage.code, min(stage.minutes, left)))
            left -= stage.minutes
            index += 1
        }
        let mapper = RingHistoryMapper(deviceID: deviceID, calendar: calendar, today: now)
        let packet = sleepPacket([(daysAgo: 0, start: startMinute, end: endMinute, stages: stages)])
        return mapper.sleepSegments(ColmiHistory.parseSleep(packet), firmware: firmware)
    }

    /// Ring `BC 27` answer for the given nights (minutes after midnight, stages as (code, minutes)).
    public static func sleepPacket(_ nights: [(daysAgo: Int, start: Int, end: Int, stages: [(code: Int, minutes: Int)])]) -> [UInt8] {
        var body: [UInt8] = [UInt8(nights.count)]
        for night in nights {
            body += [UInt8(night.daysAgo), UInt8(4 + 2 * night.stages.count)]
            body += [UInt8(night.start & 0xFF), UInt8(night.start >> 8), UInt8(night.end & 0xFF), UInt8(night.end >> 8)]
            for stage in night.stages { body += [UInt8(stage.code), UInt8(stage.minutes)] }
        }
        // Length counts every byte after the 6-byte header, starting with the night count.
        return [0xBC, 0x27, UInt8(body.count & 0xFF), UInt8(body.count >> 8), 0x00, 0x00] + body
    }

    /// 23:10 to 06:50 (460 min). Codes: 2 light, 3 deep, 4 REM, 5 awake.
    static func nightStages(for scenario: TimelineScenario) -> (start: Int, end: Int, stages: [(code: Int, minutes: Int)]) {
        var stages: [(code: Int, minutes: Int)] = [(2, 20), (3, 55), (2, 40), (4, 25), (2, 35), (3, 40), (5, 5), (2, 45),
                                                   (4, 35), (2, 40), (3, 20), (2, 30), (4, 40), (5, 10), (2, 20)]
        if scenario == .unknownPhaseCode { stages[6] = (7, 5) }
        if scenario == .daylightSavingNight {
            // 23:30 to 07:00 wall clock is only 390 real minutes on this night (2:00 jumps to 3:00).
            return (23 * 60 + 30, 7 * 60, [(2, 30), (3, 60), (2, 60), (4, 30), (2, 60), (3, 30), (2, 40), (4, 40), (5, 10), (2, 30)])
        }
        return (23 * 60 + 10, 6 * 60 + 50, stages)
    }

    /// Removes `minutes` of segments from `from` minutes after the night start (the ring lost contact).
    static func cutHole(_ segments: [SleepSegment], from offset: Int, minutes: Int) -> [SleepSegment] {
        guard let first = segments.first else { return segments }
        let holeStart = first.start.addingTimeInterval(Double(offset) * 60)
        let holeEnd = holeStart.addingTimeInterval(Double(minutes) * 60)
        return segments.compactMap { segment in
            if segment.end <= holeStart || segment.start >= holeEnd { return segment }
            if segment.start < holeStart {
                return SleepSegment(id: segment.id, subjectID: nil, sessionID: segment.sessionID, rawCode: segment.rawCode,
                                    phase: segment.phase, start: segment.start, end: holeStart, source: segment.source,
                                    deviceID: segment.deviceID, firmware: segment.firmware)
            }
            if segment.end > holeEnd {
                return SleepSegment(id: segment.id, subjectID: nil, sessionID: segment.sessionID, rawCode: segment.rawCode,
                                    phase: segment.phase, start: holeEnd, end: segment.end, source: segment.source,
                                    deviceID: segment.deviceID, firmware: segment.firmware)
            }
            return nil
        }
    }

    // MARK: Values

    static func observations(for scenario: TimelineScenario, mapper: RingHistoryMapper, calendar: Calendar, now: Date) -> [RawObservation] {
        let zone = calendar.timeZone.identifier
        let windowStart = now.addingTimeInterval(-30 * 3600)
        let pulseEnd = scenario == .staleValue ? now.addingTimeInterval(-18 * 3600) : now
        let pulseStep: TimeInterval = scenario == .batterySaverProfile ? 15 * 60 : 5 * 60
        // Ring off the finger from 01:40 for 70 minutes (matches the hole in the hypnogram).
        let gapStart = scenario == .nightWithGap ? calendar.date(bySettingHour: 1, minute: 40, second: 0, of: now) : nil
        var result: [RawObservation] = []

        func raw(_ kind: SampleKind, _ value: Double, at start: Date, minutes: Int?) -> RawObservation {
            let end = minutes.map { start.addingTimeInterval(Double($0) * 60) }
            var item = mapper.observation(kind, value, start: start, end: end, interval: minutes ?? 5)
            item.timeZoneIdentifier = zone
            return item
        }
        func asleep(_ date: Date) -> Bool {
            let hour = calendar.component(.hour, from: date)
            return hour >= 23 || hour < 7
        }

        var time = windowStart
        var index = 0
        while time <= pulseEnd {
            let inGap = gapStart.map { time >= $0 && time < $0.addingTimeInterval(70 * 60) } ?? false
            if !inGap {
                let wave = Double((index * 7) % 11) - 5
                let base = asleep(time) ? 54.0 : 72.0
                result.append(raw(.heartRate, base + wave, at: time, minutes: nil))
            }
            index += 1
            if scenario == .irregularSpacing {
                time = time.addingTimeInterval(Double([2, 5, 11, 3, 17, 5][index % 6]) * 60)
            } else {
                time = time.addingTimeInterval(pulseStep)
            }
        }
        guard scenario != .staleValue else { return result }

        var half = calendar.dateInterval(of: .hour, for: windowStart)?.start ?? windowStart
        var step = 0
        while half <= now {
            let wave = Double(step % 5) - 2
            result.append(raw(.ringHRV, (asleep(half) ? 46 : 34) + 2 * wave, at: half, minutes: nil))
            if scenario != .batterySaverProfile {
                result.append(raw(.ringStress, (asleep(half) ? 18 : 40) + 3 * wave, at: half, minutes: nil))
                if step % 2 == 0 { result.append(raw(.oxygenSaturation, 96 + Double(step % 3), at: half, minutes: 60)) }
            }
            if !asleep(half) {
                result.append(raw(.steps, Double(150 + (step * 97) % 700), at: half, minutes: 15))
            }
            step += 1
            half = half.addingTimeInterval(30 * 60)
        }
        return result
    }

    static func normalise(_ raw: [RawObservation], now: Date) -> [HealthSample] {
        SyncCoordinator.plan(batch: SyncBatch(observations: raw), existing: [:], profiles: .constant(nil), importedAt: now).inserts
    }
}
