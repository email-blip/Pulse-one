import Foundation
import Testing
@testable import PulseCore

@Suite("Live measurement phases")
struct LiveMeasurementTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    @Test func startIsOnlyRequestedUntilTheRingAnswers() {
        var m = LiveMeasurement()
        m.handle(.start(t0))
        #expect(m.phase == .requested(at: t0))
        #expect(m.phase.title == "Messung angefordert")
        #expect(m.phase.value == nil)
    }

    @Test func noAnswerFailsAfterResponseTimeout() {
        var m = LiveMeasurement(responseTimeout: 10)
        m.handle(.start(t0))
        m.handle(.tick(at(9)))
        #expect(m.phase.isActive)
        m.handle(.tick(at(10)))
        #expect(m.phase == .failed(.noResponse, at: at(10)))
        #expect(!m.phase.isActive)
    }

    @Test func zeroAnswerMeansRunningWithoutValue() {
        var m = LiveMeasurement()
        m.handle(.start(t0))
        m.handle(.ringValue(0, at(2)))
        #expect(m.phase == .running(since: at(2)))
        #expect(m.phase.title == "Messung läuft")
        m.handle(.ringValue(0, at(4)))
        #expect(m.phase == .running(since: at(2)))
    }

    @Test func onlyZerosFailAfterValueTimeout() {
        var m = LiveMeasurement(valueTimeout: 30)
        m.handle(.start(t0))
        m.handle(.ringValue(0, at(2)))
        m.handle(.tick(at(31)))
        #expect(m.phase.isActive)
        m.handle(.tick(at(32)))
        #expect(m.phase == .failed(.noValidValue, at: at(32)))
    }

    @Test func validValueIsShownWithTime() {
        var m = LiveMeasurement()
        m.handle(.start(t0))
        m.handle(.ringValue(0, at(2)))
        m.handle(.ringValue(68, at(7)))
        #expect(m.phase == .receiving(value: 68, at: at(7), since: at(2)))
        #expect(m.phase.value?.bpm == 68)
        // A later zero does not erase the last valid value.
        m.handle(.ringValue(0, at(8)))
        #expect(m.phase.value?.bpm == 68)
        m.handle(.ringValue(70, at(9)))
        #expect(m.phase.value?.bpm == 70)
    }

    @Test func implausibleValueIsNotAMeasurement() {
        var m = LiveMeasurement()
        m.handle(.start(t0))
        m.handle(.ringValue(255, at(1)))
        #expect(m.phase == .running(since: at(1)))
    }

    @Test func endsAfterMaxDurationKeepingTheValue() {
        var m = LiveMeasurement(maxDuration: 60)
        m.handle(.start(t0))
        m.handle(.ringValue(66, at(5)))
        m.handle(.tick(at(59)))
        #expect(m.phase.isActive)
        m.handle(.tick(at(60)))
        #expect(m.phase == .finished(value: 66, at: at(5)))
    }

    @Test func ringErrorFails() {
        var m = LiveMeasurement()
        m.handle(.start(t0))
        m.handle(.ringError(code: 2, at(1)))
        #expect(m.phase == .failed(.ringError(code: 2), at: at(1)))
        #expect(m.phase.detail.contains("Code 2"))
    }

    @Test func disconnectWhileMeasuringIsReported() {
        var m = LiveMeasurement()
        m.handle(.start(t0))
        m.handle(.disconnected(at(3)))
        #expect(m.phase == .connectionLost(at: at(3)))
    }

    @Test func userStopWithoutValueReturnsToIdle() {
        var m = LiveMeasurement()
        m.handle(.start(t0))
        m.handle(.stop(at(1)))
        #expect(m.phase == .idle)
    }

    @Test func eventsAfterTheEndChangeNothing() {
        var m = LiveMeasurement()
        m.handle(.start(t0))
        m.handle(.ringError(code: 1, at(1)))
        m.handle(.ringValue(70, at(2)))
        m.handle(.disconnected(at(3)))
        #expect(m.phase == .failed(.ringError(code: 1), at: at(1)))
    }
}

@Suite("Bluetooth diagnostic trace")
struct BLETraceTests {
    @Test func shortensCharacteristicUUIDs() {
        #expect(BLETrace.shortUUID("6E400003-B5A3-F393-E0A9-E50E24DCCA9E") == "6E400003")
        #expect(BLETrace.shortUUID("2A26") == "2A26")
    }

    @Test func hidesRingSuffixAndIdentifiers() {
        #expect(BLETrace.redactedName("R03_9903") == "R03_xxxx")
        #expect(BLETrace.redactedName(nil) == "unbekannt")
        let text = BLETrace.redactIdentifiers("peripheral 12345678-1234-1234-1234-1234567890AB connected")
        #expect(text == "peripheral <id> connected")
    }

    @Test func reportListsEntriesRelativeToStart() {
        var trace = BLETrace()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        trace.add(.sent, channel: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E", "690101", at: t0)
        trace.add(.received, channel: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E", "69010000", at: t0.addingTimeInterval(1.5))
        let report = trace.report(appVersion: "0.1.0 (5)", systemVersion: "18.0", deviceName: "R03_9903",
                                  firmware: "RY03_3.00.21_241028")
        #expect(report.contains("R03_xxxx"))
        #expect(!report.contains("9903"))
        #expect(report.contains("RY03_3.00.21_241028"))
        #expect(report.contains("TX       6E400002   690101"))
        #expect(report.contains("1.500  RX"))
    }

    @Test func staysBounded() {
        var trace = BLETrace()
        for i in 0..<(BLETrace.capacity + 5) { trace.add(.event, "e\(i)") }
        #expect(trace.entries.count == BLETrace.capacity)
        #expect(trace.dropped == 5)
        #expect(trace.entries.first?.text == "e5")
    }
}
