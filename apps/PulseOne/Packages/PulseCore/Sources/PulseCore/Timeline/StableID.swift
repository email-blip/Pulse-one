import Foundation

/// Deterministic UUIDs from a text key, so the same ring night or segment always gets the same id
/// across syncs and app launches. Not cryptographic; two independent 64-bit FNV-1a hashes.
public enum StableID {
    public static func uuid(_ key: String) -> UUID {
        let bytes = Array(key.utf8)
        let a = fnv1a(bytes, seed: 0xcbf2_9ce4_8422_2325)
        let b = fnv1a(bytes, seed: 0x8422_2325_cbf2_9ce4)
        var raw = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            raw[i] = UInt8((a >> (8 * UInt64(i))) & 0xFF)
            raw[8 + i] = UInt8((b >> (8 * UInt64(i))) & 0xFF)
        }
        raw[6] = (raw[6] & 0x0F) | 0x50 // version 5 layout (name based)
        raw[8] = (raw[8] & 0x3F) | 0x80 // RFC 4122 variant
        return UUID(uuid: (raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7],
                           raw[8], raw[9], raw[10], raw[11], raw[12], raw[13], raw[14], raw[15]))
    }

    static func fnv1a(_ bytes: [UInt8], seed: UInt64) -> UInt64 {
        var hash = seed
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}
