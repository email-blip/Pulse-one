import Foundation

/// Why a check-in stays on the phone instead of going to Claude. Every reason is visible in the history.
public enum CheckInLocalReason: String, Codable, Sendable {
    /// Automatic sending is switched off, or no data category is released for Claude.
    case noConsent
    case testMode
    case dailyLimit
    case budget
    case nothingNew
    case stale
    case noFacts
}

public enum CheckInRoute: Equatable, Sendable {
    case claude
    case local(CheckInLocalReason)
}

/// One decision for "may this check-in call Claude?" (Codex P1-005: consent, budget, nothing new → no call).
public enum CheckInGate {
    public struct Conditions: Sendable {
        public var sendingEnabled: Bool
        public var consentedCategories: Int
        public var testMode: Bool
        public var claudeCallsToday: Int
        public var maxClaudeCallsPerDay: Int
        /// A budget or key problem reported by the analysis engine, e.g. "Monatsbudget erreicht".
        public var budgetBlocker: String?
        public var fingerprint: String
        public var lastFingerprint: String?
        public var stale: Bool
        public var hasFacts: Bool

        public init(sendingEnabled: Bool, consentedCategories: Int, testMode: Bool, claudeCallsToday: Int,
                    maxClaudeCallsPerDay: Int, budgetBlocker: String?, fingerprint: String, lastFingerprint: String?,
                    stale: Bool, hasFacts: Bool) {
            self.sendingEnabled = sendingEnabled
            self.consentedCategories = consentedCategories
            self.testMode = testMode
            self.claudeCallsToday = claudeCallsToday
            self.maxClaudeCallsPerDay = maxClaudeCallsPerDay
            self.budgetBlocker = budgetBlocker
            self.fingerprint = fingerprint
            self.lastFingerprint = lastFingerprint
            self.stale = stale
            self.hasFacts = hasFacts
        }
    }

    public static func route(_ c: Conditions) -> CheckInRoute {
        guard c.sendingEnabled, c.consentedCategories > 0 else { return .local(.noConsent) }
        guard !c.testMode else { return .local(.testMode) }
        guard !c.stale else { return .local(.stale) }
        guard c.hasFacts else { return .local(.noFacts) }
        guard c.lastFingerprint != c.fingerprint else { return .local(.nothingNew) }
        guard c.claudeCallsToday < c.maxClaudeCallsPerDay else { return .local(.dailyLimit) }
        guard c.budgetBlocker == nil else { return .local(.budget) }
        return .claude
    }

    /// Combines the local message with Claude's answer. A provider error (nil) keeps the local message;
    /// local warning signs always win over a calmer answer.
    public static func merge(local: CheckInMessage, claude: CheckInMessage?) -> (message: CheckInMessage, fromClaude: Bool) {
        guard var answer = claude else { return (local, false) }
        answer.urgency = max(answer.urgency, local.urgency)
        return (answer, true)
    }
}
