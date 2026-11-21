import Foundation

// Local "night researcher" (I1): looks for associations between daily behaviour and the following night in
// the person's own data. Only descriptive associations, never causes. Runs on device, nothing leaves it.
//
// Daily table columns (key = start of the day in the calendar's time zone):
// - "steps":            daily step total (one source per hour, `DailySeries`).
// - "active_energy":    daily active energy (kcal).
// - "training_minutes": merged training time in minutes; 0 on days with steps but no training record.
// - "sleep_hours":      sleep duration in hours, assigned to the day the sleep ENDS (the night before that day).
// - "night_resting_hr": lowest hourly mean heart rate between 00:00 and 06:00 of that day (needs ≥ 3 hours).
// - "hrv":              daily mean HRV of ONE kind: ring HRV or Apple SDNN, whichever has more days
//                       (ring wins a tie). Never mixed within one table.
// - "spo2":             daily mean SpO₂ (%).
//
// Statistics: Spearman rank correlation (average ranks for ties), lag 0 and 1 day, two-sided p-value from
// Student's t with n − 2 degrees of freedom (exact via the regularized incomplete beta function, continued
// fraction as in Numerical Recipes; log-gamma via Lanczos), Benjamini–Hochberg over all tests run.

public enum NightResearcher {
    public static let columns = ["steps", "active_energy", "training_minutes", "sleep_hours", "night_resting_hr", "hrv", "spo2"]
    static let causes = ["steps", "active_energy", "training_minutes", "sleep_hours"]
    static let effects = ["night_resting_hr", "hrv", "sleep_hours"]

    /// Human-readable German name of a table column.
    public static func columnTitle(_ column: String) -> String {
        switch column {
        case "steps": "Schritte"
        case "active_energy": "Aktive Energie"
        case "training_minutes": "Trainingsminuten"
        case "sleep_hours": "Schlafdauer"
        case "night_resting_hr": "Ruhepuls in der Nacht"
        case "hrv": "HRV"
        case "spo2": "Sauerstoffsättigung"
        default: column
        }
    }

    // MARK: Daily table

    public static func dailyTable(_ samples: [HealthSample], calendar: Calendar) -> [Date: [String: Double]] {
        let usable = samples.filter { $0.quality.usableForAnalysis }
        var table: [Date: [String: Double]] = [:]
        func put(_ column: String, _ day: Date, _ value: Double) {
            table[day, default: [:]][column] = value
        }

        for daily in DailySeries.build(usable, kind: .steps, calendar: calendar) { put("steps", daily.day, daily.value) }
        for daily in DailySeries.build(usable, kind: .activeEnergy, calendar: calendar) { put("active_energy", daily.day, daily.value) }
        for daily in DailySeries.build(usable, kind: .trainingDuration, calendar: calendar) {
            put("training_minutes", daily.day, daily.value / 60)
        }
        for daily in DailySeries.build(usable, kind: .oxygenSaturation, calendar: calendar) { put("spo2", daily.day, daily.value) }

        // Sleep belongs to the day it ends on.
        let policy = SourcePolicy()
        let sleepByDay = Dictionary(grouping: usable.filter { $0.kind == .sleepDuration }) { calendar.startOfDay(for: $0.end) }
        for (day, group) in sleepByDay {
            if let daily = DailySeries.value(for: group, day: day, kind: .sleepDuration, calendar: calendar, policy: policy),
               daily.value > 0 {
                put("sleep_hours", day, daily.value / 3_600)
            }
        }

        // HRV: one kind only, the one with more days (ring preferred on a tie).
        let ring = DailySeries.build(usable, kind: .ringHRV, calendar: calendar)
        let apple = DailySeries.build(usable, kind: .heartRateVariability, calendar: calendar)
        for daily in (ring.count >= apple.count ? ring : apple) { put("hrv", daily.day, daily.value) }

        // Night resting heart rate: lowest hourly mean between 00:00 and 06:00.
        let night = usable.filter { $0.kind == .heartRate && calendar.component(.hour, from: $0.start) < 6 }
        let nightByDay = Dictionary(grouping: night) { calendar.startOfDay(for: $0.start) }
        let restPolicy = SourcePolicy(context: .rest)
        for (day, group) in nightByDay {
            let points = DataSourceResolver.resolvePoints(group, policy: restPolicy)
            let byHour = Dictionary(grouping: points) { calendar.component(.hour, from: $0.start) }
            guard byHour.count >= 3 else { continue }
            let means = byHour.values.map { hour in hour.reduce(0) { $0 + $1.value } / Double(hour.count) }
            if let lowest = means.min() { put("night_resting_hr", day, lowest) }
        }

        // Training: a day with steps but no training record counts as 0 minutes.
        for (day, row) in table where row["steps"] != nil && row["training_minutes"] == nil {
            put("training_minutes", day, 0)
        }
        return table
    }

    // MARK: Scan

    public static func scan(_ table: [Date: [String: Double]], calendar: Calendar, minimumDays: Int = 21) -> [ResearchFinding] {
        struct Candidate {
            let cause: String
            let effect: String
            let lag: Int
            let rho: Double
            let n: Int
            let p: Double
        }
        let days = table.keys.sorted()
        var candidates: [Candidate] = []
        for lag in [0, 1] {
            for cause in causes {
                for effect in effects where effect != cause {
                    var xs: [Double] = []
                    var ys: [Double] = []
                    for day in days {
                        guard let x = table[day]?[cause],
                              let effectDay = calendar.date(byAdding: .day, value: lag, to: day),
                              let y = table[calendar.startOfDay(for: effectDay)]?[effect] else { continue }
                        xs.append(x)
                        ys.append(y)
                    }
                    let n = xs.count
                    guard n >= max(minimumDays, 4), let rho = spearman(xs, ys) else { continue }
                    candidates.append(Candidate(cause: cause, effect: effect, lag: lag, rho: rho, n: n,
                                                p: pValue(rho: rho, n: n)))
                }
            }
        }
        let adjusted = benjaminiHochberg(candidates.map(\.p))
        var findings: [ResearchFinding] = []
        for (index, candidate) in candidates.enumerated() {
            let adjustedP = adjusted[index]
            guard adjustedP <= 0.1, abs(candidate.rho) >= 0.3 else { continue }
            let label: EvidenceLabel = candidate.n >= 42 && adjustedP <= 0.05 ? .b : .c
            findings.append(ResearchFinding(
                cause: candidate.cause, effect: candidate.effect, lagDays: candidate.lag,
                correlation: candidate.rho, sampleDays: candidate.n, adjustedP: adjustedP,
                sentence: sentence(cause: candidate.cause, effect: candidate.effect, lag: candidate.lag,
                                   rho: candidate.rho, days: candidate.n),
                label: label))
        }
        findings.sort { lhs, rhs in
            abs(lhs.correlation) == abs(rhs.correlation) ? lhs.id < rhs.id : abs(lhs.correlation) > abs(rhs.correlation)
        }
        return Array(findings.prefix(5))
    }

    // MARK: Sentence

    static func sentence(cause: String, effect: String, lag: Int, rho: Double, days: Int) -> String {
        let causePhrase: String
        switch cause {
        case "steps": causePhrase = "An Tagen mit mehr Schritten"
        case "active_energy": causePhrase = "An Tagen mit mehr aktiver Energie"
        case "training_minutes": causePhrase = "An Tagen mit mehr Trainingsminuten"
        case "sleep_hours": causePhrase = "Nach Nächten mit mehr Schlaf"
        default: causePhrase = "An Tagen mit mehr \(columnTitle(cause))"
        }
        let afterSleep = cause == "sleep_hours"
        let effectPhrase: String
        switch effect {
        case "night_resting_hr":
            if afterSleep {
                effectPhrase = lag == 0 ? "dein Ruhepuls in derselben Nacht" : "dein Ruhepuls in der Nacht darauf"
            } else {
                effectPhrase = lag == 0 ? "dein Ruhepuls in der Nacht davor" : "dein Ruhepuls in der Nacht danach"
            }
        case "hrv":
            if afterSleep {
                effectPhrase = lag == 0 ? "deine HRV am selben Tag" : "deine HRV am Tag darauf"
            } else {
                effectPhrase = lag == 0 ? "deine HRV am selben Tag" : "deine HRV am Folgetag"
            }
        case "sleep_hours":
            effectPhrase = lag == 0 ? "deine Schlafdauer in der Nacht davor" : "deine Schlafdauer in der Nacht danach"
        default:
            effectPhrase = lag == 0 ? "\(columnTitle(effect)) am selben Tag" : "\(columnTitle(effect)) am Folgetag"
        }
        let direction: String
        if effect == "sleep_hours" {
            direction = rho > 0 ? "eher länger" : "eher kürzer"
        } else {
            direction = rho > 0 ? "eher höher" : "eher niedriger"
        }
        return "\(causePhrase) lag \(effectPhrase) \(direction) (ρ = \(formatRho(rho)), \(days) Tage). "
            + "Das ist ein Zusammenhang, kein Beweis."
    }

    /// "−0,42" / "0,42" (German decimal comma, typographic minus).
    static func formatRho(_ rho: Double) -> String {
        let rounded = (rho * 100).rounded() / 100
        let text = String(format: "%.2f", abs(rounded)).replacingOccurrences(of: ".", with: ",")
        return rounded < 0 ? "\u{2212}" + text : text
    }

    // MARK: Statistics

    /// Ranks starting at 1; tied values get the average of their ranks.
    static func ranks(_ values: [Double]) -> [Double] {
        let order = values.indices.sorted { values[$0] < values[$1] }
        var result = [Double](repeating: 0, count: values.count)
        var position = 0
        while position < order.count {
            var end = position
            while end + 1 < order.count && values[order[end + 1]] == values[order[position]] { end += 1 }
            let averageRank = Double(position + end) / 2 + 1
            for k in position...end { result[order[k]] = averageRank }
            position = end + 1
        }
        return result
    }

    /// Spearman's rho (Pearson correlation of average ranks). Nil when fewer than 3 pairs or a constant series.
    static func spearman(_ x: [Double], _ y: [Double]) -> Double? {
        guard x.count == y.count, x.count >= 3 else { return nil }
        let rx = ranks(x)
        let ry = ranks(y)
        let n = Double(x.count)
        let meanX = rx.reduce(0, +) / n
        let meanY = ry.reduce(0, +) / n
        var covariance = 0.0
        var varianceX = 0.0
        var varianceY = 0.0
        for i in rx.indices {
            let dx = rx[i] - meanX
            let dy = ry[i] - meanY
            covariance += dx * dy
            varianceX += dx * dx
            varianceY += dy * dy
        }
        guard varianceX > 0, varianceY > 0 else { return nil }
        return min(max(covariance / (varianceX * varianceY).squareRoot(), -1), 1)
    }

    /// Two-sided p-value of a correlation via t = rho·√((n−2)/(1−rho²)) and Student's t with n−2 df.
    static func pValue(rho: Double, n: Int) -> Double {
        let df = Double(n - 2)
        guard df > 0 else { return 1 }
        let r2 = rho * rho
        guard r2 < 1 else { return 0 }
        let t = abs(rho) * (df / (1 - r2)).squareRoot()
        return studentTwoSidedP(t: t, df: df)
    }

    /// P(|T| ≥ t) for Student's t with `df` degrees of freedom = I_{df/(df+t²)}(df/2, 1/2).
    static func studentTwoSidedP(t: Double, df: Double) -> Double {
        let x = df / (df + t * t)
        return min(max(regularizedIncompleteBeta(a: df / 2, b: 0.5, x: x), 0), 1)
    }

    static func regularizedIncompleteBeta(a: Double, b: Double, x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        let logFront = logGamma(a + b) - logGamma(a) - logGamma(b) + a * log(x) + b * log(1 - x)
        let front = exp(logFront)
        if x < (a + 1) / (a + b + 2) {
            return front * betaContinuedFraction(a: a, b: b, x: x) / a
        }
        return 1 - front * betaContinuedFraction(a: b, b: a, x: 1 - x) / b
    }

    /// Lentz's continued fraction for the incomplete beta function (Numerical Recipes `betacf`).
    static func betaContinuedFraction(a: Double, b: Double, x: Double) -> Double {
        let tiny = 1e-300
        let qab = a + b
        let qap = a + 1
        let qam = a - 1
        var c = 1.0
        var d = 1 - qab * x / qap
        if abs(d) < tiny { d = tiny }
        d = 1 / d
        var h = d
        for m in 1...300 {
            let mm = Double(m)
            let m2 = 2 * mm
            var aa = mm * (b - mm) * x / ((qam + m2) * (a + m2))
            d = 1 + aa * d
            if abs(d) < tiny { d = tiny }
            c = 1 + aa / c
            if abs(c) < tiny { c = tiny }
            d = 1 / d
            h *= d * c
            aa = -(a + mm) * (qab + mm) * x / ((a + m2) * (qap + m2))
            d = 1 + aa * d
            if abs(d) < tiny { d = tiny }
            c = 1 + aa / c
            if abs(c) < tiny { c = tiny }
            d = 1 / d
            let delta = d * c
            h *= delta
            if abs(delta - 1) < 3e-14 { break }
        }
        return h
    }

    /// ln Γ(x) for x > 0 (Lanczos approximation, g = 7, 9 coefficients).
    static func logGamma(_ x: Double) -> Double {
        let coefficients: [Double] = [
            0.99999999999980993, 676.5203681218851, -1259.1392167224028, 771.32342877765313,
            -176.61502916214059, 12.507343278686905, -0.13857109526572012, 9.9843695780195716e-6,
            1.5056327351493116e-7
        ]
        if x < 0.5 {
            return log(Double.pi / abs(sin(Double.pi * x))) - logGamma(1 - x)
        }
        let z = x - 1
        var sum = coefficients[0]
        for i in 1..<coefficients.count { sum += coefficients[i] / (z + Double(i)) }
        let t = z + 7.5
        return 0.5 * log(2 * Double.pi) + (z + 0.5) * log(t) - t + log(sum)
    }

    /// Benjamini–Hochberg adjusted p-values, returned in the input order (capped at 1, monotone).
    static func benjaminiHochberg(_ pValues: [Double]) -> [Double] {
        let m = pValues.count
        guard m > 0 else { return [] }
        let order = pValues.indices.sorted { pValues[$0] < pValues[$1] }
        var adjusted = [Double](repeating: 1, count: m)
        var running = 1.0
        for rank in stride(from: m, through: 1, by: -1) {
            let index = order[rank - 1]
            running = min(running, pValues[index] * Double(m) / Double(rank))
            adjusted[index] = min(running, 1)
        }
        return adjusted
    }
}
