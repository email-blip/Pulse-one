import Foundation

/// Colmi ring models that community projects (colmi_r02_client, Gadgetbridge "yawell")
/// report as sharing one BLE protocol. These are claims, not facts: every model counts
/// as unverified until a real ring answered. R03 is the owner's ring; R09 is ordered.
public struct ColmiModel: Equatable, Sendable {
    public let name: String
    public let hasTemperature: Bool

    static let known: [String: Bool] = [
        "R02": false, "R03": false, "R05": true, "R06": false,
        "R09": true, "R10": false, "R12": false
    ]

    /// Detects a model from the advertised BLE name, e.g. "R03_1A2B" or "COLMI R09".
    /// Returns nil for anything that does not look like a Colmi ring.
    public static func detect(advertisedName: String?) -> ColmiModel? {
        guard let name = advertisedName?.uppercased(), !name.isEmpty else { return nil }
        let pattern = /(?:^|[^A-Z0-9])R(0[2-9]|1[0-2])(?:[^0-9]|$)/
        guard let match = name.firstMatch(of: pattern) else { return nil }
        let key = "R" + match.1
        return ColmiModel(name: key, hasTemperature: known[key] ?? false)
    }

    /// True when this model is listed by the community sources at all.
    public var isKnown: Bool { Self.known[name] != nil }
}

/// Firmware versions confirmed on a real ring by us: connection, battery and live heart rate
/// delivered real values in PULSE ONE (R03 test 2026-11-21, docs/colmi-protokoll.md).
public enum TestedFirmware {
    public static let versions: Set<String> = ["RY03_3.00.28_250401"]

    public static func isTested(_ version: String?) -> Bool {
        guard let version else { return false }
        return versions.contains(version)
    }
}
