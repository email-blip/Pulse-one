import Foundation

public enum DashboardTileSize: String, Codable, CaseIterable, Sendable {
    /// 1×1
    case small
    /// 2×1
    case wide
    /// 2×2
    case large
}

/// One tile on the dashboard. The id is stable across releases ("metric.heart_rate", "sleep", "training").
public struct DashboardTile: Identifiable, Equatable, Hashable, Sendable, Codable {
    public let id: String
    public var size: DashboardTileSize
    public var isVisible: Bool

    public init(id: String, size: DashboardTileSize = .small, isVisible: Bool = true) {
        self.id = id
        self.size = size
        self.isVisible = isVisible
    }

    public static func metric(_ kind: SampleKind, size: DashboardTileSize = .small) -> DashboardTile {
        DashboardTile(id: "metric.\(kind.rawValue)", size: size)
    }
}

/// Order, size and visibility of the tiles, saved per profile.
public struct DashboardLayout: Equatable, Sendable, Codable {
    public let subjectID: UUID?
    public private(set) var tiles: [DashboardTile]

    public init(subjectID: UUID?, tiles: [DashboardTile]) {
        self.subjectID = subjectID
        var seen = Set<String>()
        self.tiles = tiles.filter { seen.insert($0.id).inserted }
    }

    public static func standard(subjectID: UUID?) -> DashboardLayout {
        DashboardLayout(subjectID: subjectID, tiles: [
            DashboardTile(id: "sleep", size: .wide),
            .metric(.restingHeartRate),
            .metric(.ringHRV),
            .metric(.heartRate, size: .wide),
            .metric(.oxygenSaturation),
            .metric(.ringStress),
            .metric(.steps, size: .wide),
            .metric(.activeEnergy),
            DashboardTile(id: "training"),
        ])
    }

    public var visibleTiles: [DashboardTile] { tiles.filter(\.isVisible) }

    /// Moves a tile to `index` in the full list (drag and drop and the accessible "move up/down").
    public mutating func move(id: String, to index: Int) {
        guard let from = tiles.firstIndex(where: { $0.id == id }) else { return }
        let tile = tiles.remove(at: from)
        tiles.insert(tile, at: min(max(0, index), tiles.count))
    }

    public mutating func setVisible(_ id: String, _ visible: Bool) {
        guard let index = tiles.firstIndex(where: { $0.id == id }) else { return }
        tiles[index].isVisible = visible
    }

    public mutating func resize(_ id: String, to size: DashboardTileSize) {
        guard let index = tiles.firstIndex(where: { $0.id == id }) else { return }
        tiles[index].size = size
    }

    /// Adds tiles a new device offers without touching the user's order.
    public mutating func appendMissing(_ newTiles: [DashboardTile]) {
        for tile in newTiles where !tiles.contains(where: { $0.id == tile.id }) {
            tiles.append(tile)
        }
    }
}
