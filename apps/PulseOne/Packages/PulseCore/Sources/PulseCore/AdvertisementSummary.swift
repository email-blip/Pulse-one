import Foundation

/// Describes what a ring advertises before connecting. AccessorySetupKit can only find an accessory by an
/// advertised service UUID or Bluetooth company identifier, so these values must be known from a real scan
/// before the ring setup can move to AccessorySetupKit (TN3115, iOS 26 relaunch rule).
public enum AdvertisementSummary {
    /// Company identifier from manufacturer data: the first two bytes, little endian, as 4 hex digits.
    public static func companyIdentifier(_ manufacturerData: [UInt8]?) -> String? {
        guard let data = manufacturerData, data.count >= 2 else { return nil }
        return String(format: "%04X", UInt16(data[0]) | UInt16(data[1]) << 8)
    }

    public static func describe(name: String, serviceUUIDs: [String], manufacturerData: [UInt8]?) -> String {
        var parts = ["Werbung \(name)"]
        parts.append("Dienste: " + (serviceUUIDs.isEmpty ? "keine" : serviceUUIDs.sorted().joined(separator: ", ")))
        if let data = manufacturerData, !data.isEmpty {
            parts.append("Hersteller-ID: \(companyIdentifier(data) ?? "?")")
            parts.append("Herstellerdaten: " + data.map { String(format: "%02X", $0) }.joined(separator: " "))
        } else {
            parts.append("keine Herstellerdaten")
        }
        return parts.joined(separator: " · ")
    }
}
