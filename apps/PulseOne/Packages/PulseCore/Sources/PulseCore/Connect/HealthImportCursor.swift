import Foundation

/// The Apple Health sync position: one archived `HKQueryAnchor` per type, plus a format number.
///
/// Format 1 (until 2026-11-20) had no marker. Format 2 stores wrist temperature as absolute skin
/// temperature and keeps the HealthKit app/device in `originDetail` (Codex review P1-003 F1/F2, R2-1).
/// A format-1 cursor starts the import again from the initial window (so recent rows gain their
/// `originDetail`) and lets `HealthImportMigration` retype the old rows in place. A format newer than
/// this app knows is never migrated or dropped: its anchors are kept and its number is kept on write.
public struct HealthImportCursor: Equatable, Sendable {
    public static let currentFormat = 2
    static let formatKey = "_format"

    public private(set) var anchors: [String: String]
    public let format: Int

    public init(anchors: [String: String] = [:], format: Int = HealthImportCursor.currentFormat) {
        self.anchors = anchors
        self.format = format
    }

    /// Reads a stored cursor. Nothing stored (or unreadable) = a fresh cursor of the current format.
    public static func decode(_ text: String?) -> HealthImportCursor {
        guard let data = text?.data(using: .utf8),
              var map = try? JSONDecoder().decode([String: String].self, from: data) else {
            return HealthImportCursor()
        }
        let format = map.removeValue(forKey: formatKey).flatMap(Int.init) ?? 1
        // Format 1: re-read the initial window once; its rows are retyped by the migration, not deleted.
        if format < currentFormat { return HealthImportCursor(anchors: [:], format: format) }
        return HealthImportCursor(anchors: map, format: format)
    }

    /// True only for a known older format. An unknown newer format is left alone (`isUnknownFormat`).
    public var needsMigration: Bool { format < Self.currentFormat }

    /// Written by a newer app version (e.g. after installing an older TestFlight build again).
    public var isUnknownFormat: Bool { format > Self.currentFormat }

    public subscript(type: String) -> String? {
        get { anchors[type] }
        set { anchors[type] = newValue }
    }

    /// Written in the current format, or in the newer one it was read in, so a later app version
    /// still sees its own marker.
    public func encode() -> String? {
        var map = anchors
        map[Self.formatKey] = String(max(format, Self.currentFormat))
        guard let data = try? JSONEncoder().encode(map) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
