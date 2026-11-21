import Foundation

/// Small statistics used by the analysis layer (Claude intelligence spec §3). Pure functions only, so
/// every number Claude may cite can be recomputed and tested locally.
public enum IntelligenceStats {
    public static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// Linear-interpolated quantile (type 7, the common spreadsheet definition).
    public static func quantile(_ values: [Double], _ q: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let position = min(max(q, 0), 1) * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        let fraction = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }

    public static func median(_ values: [Double]) -> Double? { quantile(values, 0.5) }

    /// Sample standard deviation; nil below two values.
    public static func standardDeviation(_ values: [Double]) -> Double? {
        guard values.count >= 2, let m = mean(values) else { return nil }
        let squares = values.reduce(0) { $0 + ($1 - m) * ($1 - m) }
        return (squares / Double(values.count - 1)).squareRoot()
    }

    /// Ranks starting at 1; tied values share the average rank.
    public static func ranks(_ values: [Double]) -> [Double] {
        let order = values.indices.sorted { values[$0] < values[$1] }
        var result = [Double](repeating: 0, count: values.count)
        var i = 0
        while i < order.count {
            var j = i
            while j + 1 < order.count, values[order[j + 1]] == values[order[i]] { j += 1 }
            let rank = Double(i + j) / 2 + 1
            for k in i...j { result[order[k]] = rank }
            i = j + 1
        }
        return result
    }

    public static func pearson(_ a: [Double], _ b: [Double]) -> Double? {
        guard a.count == b.count, a.count >= 3, let ma = mean(a), let mb = mean(b) else { return nil }
        var sab = 0.0, saa = 0.0, sbb = 0.0
        for (x, y) in zip(a, b) {
            sab += (x - ma) * (y - mb)
            saa += (x - ma) * (x - ma)
            sbb += (y - mb) * (y - mb)
        }
        guard saa > 0, sbb > 0 else { return nil }
        return sab / (saa * sbb).squareRoot()
    }

    /// Spearman rank correlation; nil when fewer than three pairs or one side is constant.
    public static func spearman(_ a: [Double], _ b: [Double]) -> Double? {
        guard a.count == b.count, a.count >= 3 else { return nil }
        return pearson(ranks(a), ranks(b))
    }

    /// Rounds to a fixed number of decimals, the precision a fact is shown and sent with.
    public static func rounded(_ value: Double, decimals: Int) -> Double {
        let factor = pow(10, Double(decimals))
        return (value * factor).rounded() / factor
    }
}
