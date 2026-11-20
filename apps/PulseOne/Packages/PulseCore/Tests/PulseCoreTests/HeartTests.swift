import Foundation
import simd
import Testing
@testable import PulseCore

@Suite("Heartbeat curve")
struct HeartbeatTests {
    @Test func periodFollowsBPMAndIsClamped() {
        #expect(Heartbeat.period(bpm: 60) == 1.0)
        #expect(Heartbeat.period(bpm: 120) == 0.5)
        #expect(Heartbeat.period(bpm: 5) == 2.0)      // clamped to 30 bpm
        #expect(Heartbeat.period(bpm: 400) == 60.0 / 220)
    }

    @Test func phaseWraps() {
        #expect(Heartbeat.phase(at: 2.25, period: 1) == 0.25)
        #expect(Heartbeat.phase(at: 0, period: 0) == 0)
    }

    @Test func atriaContractBeforeVentricles() {
        let early = Heartbeat.contraction(phase: 0.06)
        #expect(early.atria > 0.9)
        #expect(early.ventricles == 0)
        let systole = Heartbeat.contraction(phase: 0.22)
        #expect(systole.ventricles > 0.9)
        let rest = Heartbeat.contraction(phase: 0.8)
        #expect(rest.atria == 0 && rest.ventricles == 0)
    }

    @Test(arguments: stride(from: 0.0, to: 1.0, by: 0.01).map { $0 })
    func valuesStayInRange(phase: Double) {
        let c = Heartbeat.contraction(phase: phase)
        #expect((0...1).contains(c.atria) && (0...1).contains(c.ventricles))
        let i = Heartbeat.idle(phase: phase)
        #expect(i.ventricles <= 0.15)
    }
}

@Suite("Heart geometry")
struct HeartGeometryTests {
    @Test func allPartsAreValidMeshes() {
        let parts = HeartGeometry.make(detail: 24)
        #expect(Set(parts.keys) == Set(HeartGeometry.Part.allCases))
        for (_, mesh) in parts {
            #expect(mesh.triangleCount > 50)
            #expect(mesh.positions.count == mesh.normals.count)
            #expect(mesh.indices.allSatisfy { Int($0) < mesh.positions.count })
            #expect(mesh.positions.allSatisfy { !$0.x.isNaN && !$0.y.isNaN && !$0.z.isNaN })
            #expect(mesh.normals.allSatisfy { abs(simd_length($0) - 1) < 0.01 })
        }
    }

    @Test func heartIsAboutUnitSizedAndApexPointsDown() {
        let v = HeartGeometry.make(detail: 24)[.ventricles]!
        let b = v.bounds
        #expect(b.max.y - b.min.y > 0.7 && b.max.y - b.min.y < 1.3)
        #expect(b.min.y < -0.4)                          // apex below the base
        // Apex tilted sideways: the lowest vertices sit further left than the base.
        let sorted = v.positions.sorted { $0.y < $1.y }
        let n = sorted.count / 10
        let bottomX = sorted.prefix(n).map(\.x).reduce(0, +) / Float(n)
        let topX = sorted.suffix(n).map(\.x).reduce(0, +) / Float(n)
        #expect(bottomX < topX)
    }

    @Test func vesselsLeaveTheTopOfTheHeart() throws {
        let parts = HeartGeometry.make(detail: 24)
        let vessels = try #require(parts[.vessels])
        let atria = try #require(parts[.atria])
        #expect(vessels.bounds.max.y > atria.bounds.max.y + 0.2)
    }
}

@Suite("Heart sound")
struct HeartSoundTests {
    @Test func beatHasTwoThumpsAndNoClipping() {
        let samples = HeartSound.beat(gap: 0.3, sampleRate: 8_000)
        #expect(samples.count >= Int(0.3 * 8_000))
        #expect(samples.allSatisfy { abs($0) <= 1 })
        #expect(abs(samples.first ?? 1) < 0.01)            // soft start, no click
        let lubPeak = samples.prefix(800).map { abs($0) }.max() ?? 0
        let dubPeak = samples.suffix(from: 2_400).map { abs($0) }.max() ?? 0
        #expect(lubPeak > 0.3 && dubPeak > 0.2)
    }
}
