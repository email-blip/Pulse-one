import Foundation
import Testing
@testable import PulseCore

@Suite("TODAY layout")
struct TodayLayoutTests {
    @Test func standardHidesOnlyTheStressScore() {
        let layout = TodayLayout.standard
        #expect(Array(layout.visibleTiles.prefix(2)) == [.now, .ring])
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

    @Test func roundTripAndNewTilesGoToTheirDefaultPlace() {
        let old = TodayLayout(order: [.nutrition, .ring, .ring], hidden: [.ring])
        let restored = TodayLayout.decode(old.encoded())
        // The user's own order stays; new tiles go next to their default neighbour: "Jetzt dran" on top,
        // the evening note after nutrition, the companion after the ring. Nothing lands at the bottom out of place.
        #expect(Array(restored.order.prefix(5)) == [.now, .nutrition, .eveningNote, .ring, .companion])
        #expect(restored.order.count == TodayLayout.defaultOrder.count)
        #expect(!restored.isVisible(.ring))
        #expect(!restored.isVisible(.metric(.ringStress)))
        #expect(TodayLayout.decode(nil) == .standard)
        #expect(TodayLayout.decode(Data("kaputt".utf8)) == .standard)
    }

    @Test func companionTileCannotBeHidden() {
        var layout = TodayLayout.standard
        layout.setVisible(.companion, false)
        #expect(layout.isVisible(.companion))
        let stored = TodayLayout(order: TodayLayout.defaultOrder, hidden: [.companion, .coach])
        let restored = TodayLayout.decode(stored.encoded())
        #expect(restored.isVisible(.companion))
        #expect(!restored.isVisible(.coach))
    }

    @Test func layoutSavedBeforeTheNowTileGetsItOnTop() {
        let saved = TodayLayout(order: Array(TodayLayout.defaultOrder.filter { $0 != .now }.reversed()), hidden: [.coach])
        let restored = TodayLayout.decode(saved.encoded())
        #expect(restored.order.first == .now)
        #expect(restored.isVisible(.now))
        #expect(Array(restored.order.dropFirst()) == saved.order)
        #expect(!restored.isVisible(.coach))
    }
}
