import Foundation

/// One block on TODAY. Metric tiles are per sample kind, so a new ring or sensor adds tiles
/// by capability without a layout change.
public enum TodayTile: Hashable, Codable, Sendable, Identifiable {
    /// "Jetzt dran": the one next step of the day (`NowPlanner`).
    case now
    case ring
    case appleHealth
    case coach
    case companion
    case metric(SampleKind)
    case nutrition
    case eveningNote

    public var id: String {
        switch self {
        case .now: "now"
        case .ring: "ring"
        case .appleHealth: "health"
        case .coach: "coach"
        case .companion: "companion"
        case .metric(let kind): "metric.\(kind.rawValue)"
        case .nutrition: "nutrition"
        case .eveningNote: "eveningNote"
        }
    }

    public var title: String {
        switch self {
        case .now: "Jetzt dran"
        case .ring: "Ring"
        case .appleHealth: "Apple Health verbinden"
        case .coach: "Coach"
        case .companion: "Begleiter"
        case .metric(let kind): kind.title
        case .nutrition: "Ernährung"
        case .eveningNote: "Abendnotiz"
        }
    }
}

/// Order and visibility of the TODAY tiles, chosen by the user. Stored as JSON; tiles added by a
/// later version are inserted at their default position, right after the nearest tile that comes before
/// them in `defaultOrder` (visible unless listed in `defaultHidden`); unknown ones are dropped.
public struct TodayLayout: Codable, Equatable, Sendable {
    public private(set) var order: [TodayTile]
    public private(set) var hidden: Set<TodayTile>

    public static let metricKinds: [SampleKind] = [.restingHeartRate, .heartRateVariability, .ringHRV, .sleepDuration,
                                                   .steps, .oxygenSaturation, .heartRate, .activeEnergy,
                                                   .respiratoryRate, .ringStress]

    public static let defaultOrder: [TodayTile] = [.now, .ring, .companion, .appleHealth, .coach] + metricKinds.map(TodayTile.metric)
        + [.nutrition, .eveningNote]

    /// The ring's stress score is a vendor scale; it appears only when the user switches it on.
    public static let defaultHidden: Set<TodayTile> = [.metric(.ringStress)]

    /// Tiles that are the only way into a module stay visible: the companion tile is the only entry to
    /// the alarm settings, and an alarm that keeps ringing must stay reachable.
    public static let alwaysVisible: Set<TodayTile> = [.companion]

    public static func canHide(_ tile: TodayTile) -> Bool { !alwaysVisible.contains(tile) }

    public static let standard = TodayLayout(order: defaultOrder, hidden: defaultHidden)

    public init(order: [TodayTile], hidden: Set<TodayTile>) {
        self.order = order
        self.hidden = hidden
    }

    /// Keeps the user's order, drops tiles this version does not know, inserts new ones at their default
    /// position (after the nearest earlier default tile the user has, or first when there is none).
    public func normalized() -> TodayLayout {
        var seen = Set<TodayTile>()
        var order = self.order.filter { Self.defaultOrder.contains($0) && seen.insert($0).inserted }
        var hidden = self.hidden.intersection(Self.defaultOrder).subtracting(Self.alwaysVisible)
        for (index, tile) in Self.defaultOrder.enumerated() where !seen.contains(tile) {
            let predecessor = Self.defaultOrder[..<index].last { order.contains($0) }
            let position = predecessor.flatMap { order.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            order.insert(tile, at: position)
            seen.insert(tile)
            if Self.defaultHidden.contains(tile) { hidden.insert(tile) }
        }
        return TodayLayout(order: order, hidden: hidden)
    }

    public var visibleTiles: [TodayTile] { order.filter { !hidden.contains($0) } }

    public func isVisible(_ tile: TodayTile) -> Bool { !hidden.contains(tile) }

    public mutating func setVisible(_ tile: TodayTile, _ visible: Bool) {
        if visible || !Self.canHide(tile) { hidden.remove(tile) } else { hidden.insert(tile) }
    }

    /// Same semantics as SwiftUI's `onMove`: `destination` is the index before which the items land.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().filter { order.indices.contains($0) }.map { order[$0] }
        let before = source.filter { $0 < destination }.count
        var rest = order
        for index in source.sorted(by: >) where rest.indices.contains(index) { rest.remove(at: index) }
        let target = min(max(destination - before, 0), rest.count)
        rest.insert(contentsOf: moving, at: target)
        order = rest
    }

    public static func decode(_ data: Data?) -> TodayLayout {
        guard let data, let layout = try? JSONDecoder().decode(TodayLayout.self, from: data) else { return .standard }
        return layout.normalized()
    }

    public func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }
}
