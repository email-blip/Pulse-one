import Foundation

/// The single device inside Apple Health that wrote a sample (Codex review P1-003 R2-2).
///
/// Format: `bundle|model|device`. `device` is a stable hash of `HKDevice.localIdentifier`, so two
/// iPhones of the same model with the same app stay apart, while no serial number or device name is
/// stored. Without a local identifier the device part is `unbekannt`: it is never guessed from the
/// model, and such samples are flagged as unknown origin wherever they are added up.
public enum HealthOrigin {
    public static let unknown = "unbekannt"

    public static func detail(bundle: String, model: String?, localIdentifier: String?) -> String {
        let device = localIdentifier.flatMap { $0.isEmpty ? nil : "dev-" + stableHash($0) } ?? unknown
        return [bundle, model.flatMap { $0.isEmpty ? nil : $0 } ?? unknown, device].joined(separator: "|")
    }

    /// True when the detail names one device. False for nil (rows from before `originDetail`), for the
    /// two-part format of the first R1 patch, and for a missing local identifier.
    public static func identifiesDevice(_ detail: String?) -> Bool {
        guard let parts = detail?.split(separator: "|", omittingEmptySubsequences: false), parts.count == 3 else {
            return false
        }
        return parts[2] != Substring(unknown)
    }

    /// FNV-1a, 64 bit, as 16 hex digits. Deterministic across launches and devices (unlike `hashValue`).
    /// It only shortens and hides the identifier; it is not meant as cryptographic protection.
    static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }
}
