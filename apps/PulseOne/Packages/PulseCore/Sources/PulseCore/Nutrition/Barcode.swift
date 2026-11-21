import Foundation

/// GTIN barcodes on food packages: EAN-8, UPC-A (12), EAN-13, GTIN-14.
public enum Barcode {
    /// Digits only, or nil when the code is not a valid GTIN (length or check digit).
    public static func normalized(_ raw: String) -> String? {
        let digits = raw.filter { !$0.isWhitespace && $0 != "-" }
        guard [8, 12, 13, 14].contains(digits.count), digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return hasValidCheckDigit(digits) ? digits : nil
    }

    /// GS1 mod-10: from the right (excluding the check digit) weights alternate 3, 1, 3, ...
    public static func hasValidCheckDigit(_ digits: String) -> Bool {
        let values = digits.compactMap { $0.wholeNumberValue }
        guard values.count == digits.count, let check = values.last else { return false }
        var sum = 0
        for (offset, value) in values.dropLast().reversed().enumerated() {
            sum += value * (offset.isMultiple(of: 2) ? 3 : 1)
        }
        return (10 - sum % 10) % 10 == check
    }
}
