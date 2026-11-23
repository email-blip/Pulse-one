import Foundation
import Testing
@testable import PulseCore

@Suite("Dashboard and timeline (team 03)")
struct DashboardTimelineTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        return calendar
    }

    func point(_ kind: SampleKind = .heartRate, _ value: Double, at offset: TimeInterval, duration: TimeInterval = 0,
               received: TimeInterval? = nil) -> MeasurementPoint {
        let at = t0.addingTimeInterval(offset)
        return MeasurementPoint(id: UUID(), subjectID: nil, deviceID: "R03", source: .colmiRing, kind: kind, value: value,
                                unit: kind.canonicalUnit, method: .deviceHistory, measuredAt: at,
                                measuredUntil: at.addingTimeInterval(duration),
                                receivedAt: t0.addingTimeInterval(received ?? offset), importedAt: t0.addingTimeInterval(received ?? offset),
                                quality: .valid, originalReference: "slot-\(Int(offset))")
    }

    // MARK: Tracks

    @Test func originalPointsUpToTwoDaysAggregatedAbove() {
        func span(_ days: Double) -> DateInterval { DateInterval(start: t0, duration: days * 86_400) }
        #expect(TimelineQuery.resolution(for: span(1)) == .original)
        #expect(TimelineQuery.resolution(for: span(2)) == .original)
        #expect(TimelineQuery.resolution(for: span(7)) == .hourly)
        #expect(TimelineQuery.resolution(for: span(365)) == .daily)
        #expect(TimelineResolution.original.trackLabel(cumulative: false) == nil)
        #expect(TimelineResolution.daily.trackLabel(cumulative: true) == "Tagessumme")
    }

    @Test func gapSplitsTheLineAndIsNeverZero() {
        // Pulse every 5 min, then two hours without values, then again.
        let before = (0..<6).map { point(60 + Double($0), at: Double($0) * 300) }
        let after = (0..<3).map { point(70, at: 9000 + Double($0) * 300) }
        let window = DateInterval(start: t0, end: t0.addingTimeInterval(12_000))
        let values = TrackSeries.values(before + after, kind: .heartRate, in: window, resolution: .original, calendar: calendar)
        #expect(values.count == 9)
        #expect(Set(values.prefix(6).map(\.run)) == [0])
        #expect(Set(values.suffix(3).map(\.run)) == [1])
        #expect(!values.contains { $0.value == 0 })
        let gaps = TrackSeries.gaps(in: values)
        #expect(gaps == [DateInterval(start: t0.addingTimeInterval(1500), end: t0.addingTimeInterval(9000))])
    }

    @Test func aggregationIsMarkedAndKeepsEmptyBucketsEmpty() {
        let morning = (0..<4).map { point(60 + Double($0) * 2, at: Double($0) * 600) }   // 60, 62, 64, 66 within one hour
        let later = [point(80, at: 3 * 3600 + 60)]
        let window = DateInterval(start: t0.addingTimeInterval(-3600), end: t0.addingTimeInterval(5 * 3600))
        let values = TrackSeries.values(morning + later, kind: .heartRate, in: window, resolution: .hourly, calendar: calendar)
        #expect(values.allSatisfy(\.isAggregated))
        #expect(values.count == 2)
        #expect(values[0].value == 63)
        #expect(values[0].low == 60 && values[0].high == 66)
        #expect(values[0].count == 4)
        #expect(values[1].run == values[0].run + 1)
    }

    @Test func cumulativeKindsAreSummedPerBucket() {
        let steps = [point(.steps, 500, at: 0, duration: 900), point(.steps, 700, at: 900, duration: 900)]
        let window = DateInterval(start: t0.addingTimeInterval(-86_400), end: t0.addingTimeInterval(86_400))
        let values = TrackSeries.values(steps, kind: .steps, in: window, resolution: .daily, calendar: calendar)
        #expect(values.count == 1)
        #expect(values[0].value == 1200)
    }

    @Test func cursorPicksOriginalPointWithItsOwnTimeAndNothingInAGap() {
        let points = [point(61, at: 0), point(64, at: 300), point(70, at: 9000)]
        let picked = TrackSeries.pick(at: t0.addingTimeInterval(320), in: points, kind: .heartRate)
        #expect(picked?.value == 64)
        #expect(picked?.measuredAt == t0.addingTimeInterval(300))
        #expect(TrackSeries.pick(at: t0.addingTimeInterval(4500), in: points, kind: .heartRate) == nil)
    }

    @Test func cursorInsideAnIntervalPicksThatInterval() {
        let steps = [point(.steps, 500, at: 0, duration: 900), point(.steps, 700, at: 900, duration: 900)]
        #expect(TrackSeries.pick(at: t0.addingTimeInterval(1000), in: steps, kind: .steps)?.value == 700)
    }

    @Test func stepMovesToTheNextOriginalPoint() {
        let points = [point(61, at: 0), point(64, at: 300), point(70, at: 9000)]
        #expect(TrackSeries.step(from: t0.addingTimeInterval(10), in: points, forward: true)?.value == 64)
        #expect(TrackSeries.step(from: t0.addingTimeInterval(300), in: points, forward: false)?.value == 61)
        #expect(TrackSeries.step(from: t0.addingTimeInterval(9000), in: points, forward: true) == nil)
    }

    @Test func sliceFindsTheWindowInAYearOfPoints() {
        let year = (0..<(365 * 48)).map { point(60, at: Double($0) * 1800) }
        let window = DateInterval(start: t0.addingTimeInterval(100 * 86_400), end: t0.addingTimeInterval(101 * 86_400))
        let slice = TrackSeries.slice(year, in: window)
        #expect(slice.count == 49)
        #expect(slice.first?.measuredAt == window.start)
        #expect(slice.last?.measuredAt == window.end)
        #expect(TrackSeries.slice(year, in: DateInterval(start: t0.addingTimeInterval(-500), end: t0.addingTimeInterval(-100))).isEmpty)
    }

    @Test func yDomainKeepsSmallSwingsCalm() {
        let values = [69.0, 71].enumerated().map { TrackValue(id: "\($0.offset)", start: t0, end: t0, value: $0.element,
                                                                low: $0.element, high: $0.element, count: 1, isAggregated: false, run: 0) }
        let domain = TrackSeries.yDomain(for: values, kind: .heartRate)
        #expect(domain.upperBound - domain.lowerBound >= 20)
        let spo2 = [TrackValue(id: "a", start: t0, end: t0, value: 99, low: 99, high: 99, count: 1, isAggregated: false, run: 0)]
        #expect(TrackSeries.yDomain(for: spo2, kind: .oxygenSaturation).upperBound == 100)
    }

    @Test func onlyJustMeasuredValuesLandAsNew() {
        let now = t0.addingTimeInterval(3600)
        let live = point(66, at: 3590, received: 3595)
        let history = point(62, at: 600, received: 3595)   // synced just now, measured an hour ago
        let arrivals = LiveArrival.arrivals(known: [], current: [live, history], now: now)
        #expect(arrivals.map(\.id) == [live.id])
        #expect(LiveArrival.arrivals(known: [live.id], current: [live], now: now).isEmpty)
    }

    // MARK: Dashboard

    @Test func gridKeepsOrderAndPairsSmallTiles() {
        let tiles = [DashboardTile(id: "a"), DashboardTile(id: "b", size: .wide), DashboardTile(id: "c"),
                     DashboardTile(id: "d"), DashboardTile(id: "e", size: .large), DashboardTile(id: "f")]
        let rows = DashboardGrid.rows(tiles).map { $0.map(\.id) }
        #expect(rows == [["a"], ["b"], ["c", "d"], ["e"], ["f"]])
    }

    @Test func layoutSurvivesSaveAndRestorePerProfile() {
        let me = UUID()
        var layout = DashboardLayout.standard(subjectID: me)
        layout.move(id: "sleep", to: 3)
        layout.setVisible("metric.spo2", false)
        layout.resize("metric.heart_rate", to: .large)
        let restored = DashboardLayout.restore(layout.encoded(), subjectID: me)
        #expect(restored.tiles == layout.tiles)
        #expect(DashboardLayout.storageKey(subjectID: me) != DashboardLayout.storageKey(subjectID: UUID()))
        #expect(DashboardLayout.storageKey(subjectID: me, namespace: "uitest").contains("uitest"))
        #expect(DashboardLayout.restore(nil, subjectID: me) == .standard(subjectID: me))
        #expect(DashboardLayout.restore(Data("kaputt".utf8), subjectID: me) == .standard(subjectID: me))
    }

    @Test func restoreAppendsNewTilesWithoutTouchingTheOrder() {
        let me = UUID()
        let old = DashboardLayout(subjectID: me, tiles: [DashboardTile(id: "training"), DashboardTile(id: "sleep")])
        let restored = DashboardLayout.restore(old.encoded(), subjectID: me)
        #expect(restored.tiles.prefix(2).map(\.id) == ["training", "sleep"])
        #expect(restored.tiles.count == DashboardLayout.standard(subjectID: me).tiles.count)
    }

    @Test func accessibleStepSkipsHiddenTiles() {
        var layout = DashboardLayout(subjectID: nil, tiles: [DashboardTile(id: "a"), DashboardTile(id: "b", isVisible: false),
                                                             DashboardTile(id: "c")])
        layout.step(id: "a", by: 1)
        #expect(layout.visibleTiles.map(\.id) == ["c", "a"])
        layout.step(id: "a", by: 1)   // already last: nothing happens
        #expect(layout.visibleTiles.map(\.id) == ["c", "a"])
    }

    @Test func tileKindTitleAndTrack() {
        #expect(DashboardTile.metric(.ringHRV).metricKind == .ringHRV)
        #expect(DashboardTile.metric(.ringHRV).track == .hrv)
        #expect(DashboardTile(id: "sleep").metricKind == nil)
        #expect(DashboardTile(id: "sleep").track == .sleepPhases)
        #expect(DashboardTile.metric(.oxygenSaturation).title == "SpO₂")
    }

    @Test func tileShowsNewestValueWithItsTimeAndRealPointsOnly() throws {
        let points = (0..<12).map { point(60 + Double($0), at: Double($0) * 300) } + [point(80, at: 3 * 3600)]
        let now = t0.addingTimeInterval(3 * 3600 + 120)
        let reading = try #require(TileSummary.reading(kind: .heartRate, points: points, now: now, calendar: calendar))
        #expect(reading.value == 80)
        #expect(reading.at == t0.addingTimeInterval(3 * 3600))
        #expect(reading.spark.count == 13)
        #expect(reading.spark.last?.run != reading.spark.first?.run)   // the gap breaks the mini line
        #expect(!reading.isOld)
        #expect(reading.reference.contains("·"))
    }

    @Test func cumulativeTileShowsTheDayTotalSoFar() throws {
        let start = calendar.startOfDay(for: t0).addingTimeInterval(8 * 3600)
        let offset = start.timeIntervalSince(t0)
        let points = [point(.steps, 1000, at: offset, duration: 900), point(.steps, 500, at: offset + 3600, duration: 900)]
        let reading = try #require(TileSummary.reading(kind: .steps, points: points, now: start.addingTimeInterval(7200),
                                                       calendar: calendar))
        #expect(reading.value == 1500)
        #expect(reading.reference.hasPrefix("HEUTE · BIS"))
    }

    @Test func referenceSaysTodayYesterdayAndNight() {
        let now = calendar.startOfDay(for: t0).addingTimeInterval(14 * 3600)
        let morning = calendar.startOfDay(for: t0).addingTimeInterval(7 * 3600)
        #expect(TileSummary.reference(for: morning, now: now, calendar: calendar) == "HEUTE · 07:00")
        #expect(TileSummary.reference(for: morning, now: now, night: true, calendar: calendar) == "NACHT · 07:00")
        #expect(TileSummary.reference(for: morning.addingTimeInterval(-86_400), now: now, calendar: calendar) == "GESTERN · 07:00")
        #expect(TileSummary.duration(7 * 3600 + 12 * 60) == "7 h 12 min")
        #expect(TileSummary.duration(45 * 60) == "45 min")
    }

    @Test func thinKeepsEdgesOfRuns() {
        let points = (0..<400).map { SparkPoint(at: t0.addingTimeInterval(Double($0) * 60), value: Double($0), run: $0 < 200 ? 0 : 1) }
        let thinned = TileSummary.thin(points, limit: 50)
        #expect(thinned.count < 120)
        #expect(thinned.first == points.first && thinned.last == points.last)
        #expect(thinned.contains(points[199]) && thinned.contains(points[200]))
    }

    // MARK: Hypnogram

    @Test func hypnogramKeepsUnknownApartAndGapsEmpty() {
        let night = UUID()
        func segment(_ phase: SleepPhase, _ from: Double, _ to: Double, code: Int) -> SleepSegment {
            SleepSegment(subjectID: nil, sessionID: night, rawCode: code, phase: phase, start: t0.addingTimeInterval(from * 60),
                         end: t0.addingTimeInterval(to * 60), source: .colmiRing, deviceID: "R03", firmware: "3.00.10")
        }
        let segments = [segment(.light, 0, 30, code: 2), segment(.deep, 30, 75, code: 3), segment(.unknown, 90, 100, code: 9)]
        #expect(Hypnogram.lanes.last == .unknown)
        #expect(Hypnogram.segment(at: t0.addingTimeInterval(40 * 60), in: segments)?.phase == .deep)
        #expect(Hypnogram.segment(at: t0.addingTimeInterval(80 * 60), in: segments) == nil)
        #expect(Hypnogram.segment(at: t0.addingTimeInterval(95 * 60), in: segments)?.rawCode == 9)
        #expect(Hypnogram.nights(segments).count == 1)
        let text = Hypnogram.describe(segments[1], calendar: calendar)
        #expect(text.hasPrefix("Tief · "))
        #expect(text.hasSuffix("45 min"))
    }
}
