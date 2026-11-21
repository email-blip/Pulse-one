import Foundation

/// Released models and their list prices in USD per million tokens (Anthropic price table, checked
/// 2026-11-20; spec §4). The app shows the real cost from `usage` after every run.
public struct ClaudeModel: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    public let displayName: String
    public let inputPerMillion: Double
    public let outputPerMillion: Double
    public let cacheReadPerMillion: Double

    public static let opus = ClaudeModel(id: "claude-opus-5-5", displayName: "Claude Opus 5.5",
                                         inputPerMillion: 4, outputPerMillion: 20, cacheReadPerMillion: 0.2)
    public static let sonnet = ClaudeModel(id: "claude-sonnet-5-5", displayName: "Claude Sonnet 5.5",
                                           inputPerMillion: 2, outputPerMillion: 10, cacheReadPerMillion: 0.1)
    public static let haiku = ClaudeModel(id: "claude-haiku-5-5", displayName: "Claude Haiku 5.5",
                                          inputPerMillion: 0.1, outputPerMillion: 0.5, cacheReadPerMillion: 0.01)

    /// Default per spec §2: Opus 5.5.
    public static let standard = opus
    public static let all = [opus, sonnet, haiku]

    public static func model(id: String) -> ClaudeModel { all.first { $0.id == id } ?? standard }

    /// Short note for the model picker.
    public var note: String {
        switch id {
        case Self.opus.id: "gründlichste Auswertung (Vorgabe)"
        case Self.sonnet.id: "etwa halbe Kosten"
        default: "sehr günstig, für kurze Fragen"
        }
    }
}

public struct CostEstimate: Sendable, Equatable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let usd: Double

    /// "ca. 0,16 $" – German formatting for the preview.
    public var text: String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = usd < 0.01 ? 3 : 2
        return "ca. " + (f.string(from: NSNumber(value: usd)) ?? "\(usd)") + " $"
    }
}

/// Token counts the API reported for one call.
public struct TokenUsage: Codable, Sendable, Equatable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheCreationInputTokens: Int
    public var cacheReadInputTokens: Int

    public init(inputTokens: Int = 0, outputTokens: Int = 0, cacheCreationInputTokens: Int = 0, cacheReadInputTokens: Int = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try c.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        outputTokens = try c.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        cacheCreationInputTokens = try c.decodeIfPresent(Int.self, forKey: .cacheCreationInputTokens) ?? 0
        cacheReadInputTokens = try c.decodeIfPresent(Int.self, forKey: .cacheReadInputTokens) ?? 0
    }

    public static func + (a: TokenUsage, b: TokenUsage) -> TokenUsage {
        TokenUsage(inputTokens: a.inputTokens + b.inputTokens, outputTokens: a.outputTokens + b.outputTokens,
                   cacheCreationInputTokens: a.cacheCreationInputTokens + b.cacheCreationInputTokens,
                   cacheReadInputTokens: a.cacheReadInputTokens + b.cacheReadInputTokens)
    }
}

public enum CostEstimator {
    /// Rough rule: about three characters per token for German JSON. Only for the preview; the real
    /// count comes back in `usage`.
    public static func tokens(forCharacters count: Int) -> Int { max(1, count / 3) }

    public static func estimate(inputCharacters: Int, expectedOutputTokens: Int, model: ClaudeModel) -> CostEstimate {
        let input = tokens(forCharacters: inputCharacters)
        let usd = Double(input) * model.inputPerMillion / 1_000_000
            + Double(expectedOutputTokens) * model.outputPerMillion / 1_000_000
        return CostEstimate(inputTokens: input, outputTokens: expectedOutputTokens, usd: usd)
    }

    /// Real cost: cache writes cost 1.25× input, cache reads the reduced rate.
    public static func cost(of usage: TokenUsage, model: ClaudeModel) -> Double {
        (Double(usage.inputTokens) * model.inputPerMillion
            + Double(usage.cacheCreationInputTokens) * model.inputPerMillion * 1.25
            + Double(usage.cacheReadInputTokens) * model.cacheReadPerMillion
            + Double(usage.outputTokens) * model.outputPerMillion) / 1_000_000
    }
}

/// Monthly money budget (spec §2 "Kostenkontrolle"): warning at 80 %, stop at 100 %.
public struct SpendingBudget: Sendable, Equatable {
    public enum Status: Equatable, Sendable { case ok, warning, exhausted }

    public let limitUSD: Double
    public let spentUSD: Double

    public init(limitUSD: Double, spentUSD: Double) {
        self.limitUSD = limitUSD
        self.spentUSD = spentUSD
    }

    public var status: Status {
        guard limitUSD > 0 else { return .exhausted }
        if spentUSD >= limitUSD { return .exhausted }
        return spentUSD >= limitUSD * 0.8 ? .warning : .ok
    }

    /// A run is allowed only if its estimate still fits.
    public func allows(_ estimate: CostEstimate) -> Bool {
        status != .exhausted && spentUSD + estimate.usd <= limitUSD
    }

    public var remainingUSD: Double { max(0, limitUSD - spentUSD) }
}

/// Monthly data budget of the "glass messenger" (creative lab idea 1): at most N sends to Claude.
public struct SendBudget: Sendable, Equatable {
    public let maxSends: Int
    public let used: Int

    public init(maxSends: Int, used: Int) {
        self.maxSends = maxSends
        self.used = used
    }

    public var remaining: Int { max(0, maxSends - used) }
    public var allowsSend: Bool { remaining > 0 }
}
