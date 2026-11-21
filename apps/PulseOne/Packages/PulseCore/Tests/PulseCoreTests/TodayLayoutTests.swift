import Foundation
import Testing
@testable import PulseCore

@Suite("TODAY layout")
struct TodayLayoutTests {
    @Test func standardHidesOnlyTheStressScore() {
        let layout = TodayLayout.standard
        #expect(layout.visibleTiles.first == .ring)
        #expect(!layout.isVisible(.metric(.ringStress)))
        #expect(layout.isVisible(.metric(.ringHRV)))
        #expect(layout.visibleTiles.count == TodayLayout.defaultOrder.count - 1)
    }

    @Test func moveFollowsOnMoveSemantics() {
        var layout = TodayLayout(order: [.ring, .coach, .nutrition], hidden: [])
        layout.move(fromOffsets: [0], toOffset: 3)
        #expect(layout.order == [.coach, .nutrition, .ring])
        layout.move(fromOffsets: [2], toOffset: 0)
        #expect(layout.order == [.ring, .coach, .nutrition])
        layout.move(fromOffsets: [0, 1], toOffset: 3)
        #expect(layout.order == [.nutrition, .ring, .coach])
    }

    @Test func visibilityToggles() {
        var layout = TodayLayout.standard
        layout.setVisible(.coach, false)
        #expect(!layout.visibleTiles.contains(.coach))
        layout.setVisible(.metric(.ringStress), true)
        #expect(layout.visibleTiles.contains(.metric(.ringStress)))
    }

    @Test func roundTripAndNewTilesAreAppended() {
        let old = TodayLayout(order: [.nutrition, .ring, .ring], hidden: [.ring])
        let restored = TodayLayout.decode(old.encoded())
        #expect(restored.order.prefix(2) == [.nutrition, .ring])
        #expect(restored.order.count == TodayLayout.defaultOrder.count)
        #expect(!restored.isVisible(.ring))
        #expect(!restored.isVisible(.metric(.ringStress)))
        #expect(TodayLayout.decode(nil) == .standard)
        #expect(TodayLayout.decode(Data("kaputt".utf8)) == .standard)
    }
}
