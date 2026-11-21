import Foundation

/// One block on TODAY. Metric tiles are per sample kind, so a new ring or sensor adds tiles
/// by capability without a layout change.
public enum TodayTile: Hashable, Codable, Sendable, Identifiable {
    case ring
    case appleHealth
    case coach
    case metric(SampleKind)
    case nutrition
    case eveningNote

    public var id: String {
        switch self {
        case .ring: "ring"
        case .appleHealth: "health"
        case .coach: "coach"
        case .metric(let kind): "metric.\(kind.rawValue)"
        case .nutrition: "nutrition"
        case .eveningNote: "eveningNote"
        }
    }

    public var title: String {
        switch self {
        case .ring: "Ring"
        case .appleHealth: "Apple Health verbinden"
        case .coach: "Coach"
        case .metric(let kind): kind.title
        case .nutrition: "Ernährung"
        case .eveningNote: "Abendnotiz"
        }
    }
}

/// Order and visibility of the TODAY tiles, chosen by the user. Stored as JSON; tiles added by a
/// later version are appended (visible unless listed in `defaultHidden`), unknown ones dropped.
public struct TodayLayout: Codable, Equatable, Sendable {
    public private(set) var order: [TodayTile]
    public private(set) var hidden: Set<TodayTile>

    public static let metricKinds: [SampleKind] = [.restingHeartRate, .heartRateVariability, .ringHRV, .sleepDuration,
                                                   .steps, .oxygenSaturation, .heartRate, .activeEnergy,
                                                   .respiratoryRate, .ringStress]

    public static let defaultOrder: [TodayTile] = [.ring, .appleHealth, .coach] + metricKinds.map(TodayTile.metric)
        + [.nutrition, .eveningNote]

    /// The ring's stress score is a vendor scale; it appears only when the user switches it on.
    public static let defaultHidden: Set<TodayTile> = [.metric(.ringStress)]

    public static let standard = TodayLayout(order: defaultOrder, hidden: defaultHidden)

    public init(order: [TodayTile], hidden: Set<TodayTile>) {
        self.order = order
        self.hidden = hidden
    }

    /// Keeps the user's order, drops tiles this version does not know, appends new ones.
    public func normalized() -> TodayLayout {
        var seen = Set<TodayTile>()
        var order = self.order.filter { Self.defaultOrder.contains($0) && seen.insert($0).inserted }
        var hidden = self.hidden.intersection(Self.defaultOrder)
        for tile in Self.defaultOrder where !seen.contains(tile) {
            order.append(tile)
            if Self.defaultHidden.contains(tile) { hidden.insert(tile) }
        }
        return TodayLayout(order: order, hidden: hidden)
    }

    public var visibleTiles: [TodayTile] { order.filter { !hidden.contains($0) } }

    public func isVisible(_ tile: TodayTile) -> Bool { !hidden.contains(tile) }

    public mutating func setVisible(_ tile: TodayTile, _ visible: Bool) {
        if visible { hidden.remove(tile) } else { hidden.insert(tile) }
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
