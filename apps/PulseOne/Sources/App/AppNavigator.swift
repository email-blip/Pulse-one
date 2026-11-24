import Foundation
import Observation
import PulseCore

/// Cross-tab navigation: Dashboard tiles, ROOK's evidence and "Warum?" open the Verlauf at a place.
@MainActor
@Observable
final class AppNavigator {
    var tab: AppTab
    /// Where the Verlauf tab opens next; `request` changes on every open so the screen rebuilds there.
    private(set) var timelineFocus: TimelineFocus?
    private(set) var timelineRequest = 0
    /// The "Mehr" area (Begleiter, analyses, Sprechstunde) shown as a sheet from the dashboard.
    var showMore: Bool
    /// The profile sheet (profile, ring, devices), opened from the top right of every tab.
    var showProfile: Bool

    /// True while a sheet covers the tabs: their own content then stays out of the accessibility tree (the
    /// profile sheet's ring orb and ROOK's orb below it both carry the identifier "orb").
    var coveredBySheet: Bool { showProfile || showMore }

    init(tab: AppTab, showMore: Bool = false, showProfile: Bool = false) {
        self.tab = tab
        self.showMore = showMore
        self.showProfile = showProfile
    }

    func openTimeline(_ focus: TimelineFocus?) {
        timelineFocus = focus
        timelineRequest += 1
        showMore = false
        tab = .timeline
    }

    /// The shared contract form (ROOK's "Warum?" hands over a `TimelineState`).
    func openTimeline(state: TimelineState) {
        let track = state.tracks.first ?? .heartRate
        openTimeline(TimelineFocus(track: track, cursor: state.cursor ?? state.selected?.measuredAt, window: state.visible))
    }
}
