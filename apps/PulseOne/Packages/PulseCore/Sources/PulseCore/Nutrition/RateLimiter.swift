import Foundation

/// Sliding-window limiter so the app stays inside the free API limits (NUTRITION-SPEC §4).
public struct SlidingWindowLimiter: Sendable {
    public let limit: Int
    public let window: TimeInterval
    private var stamps: [Date] = []

    public init(limit: Int, window: TimeInterval) {
        self.limit = limit
        self.window = window
    }

    /// Records a request and returns true if it is allowed now.
    public mutating func tryAcquire(now: Date) -> Bool {
        stamps.removeAll { now.timeIntervalSince($0) >= window }
        guard stamps.count < limit else { return false }
        stamps.append(now)
        return true
    }

    /// Seconds until the next request would be allowed (0 if allowed now).
    public func retryAfter(now: Date) -> TimeInterval {
        let live = stamps.filter { now.timeIntervalSince($0) < window }
        guard live.count >= limit, let oldest = live.min() else { return 0 }
        return max(0, window - now.timeIntervalSince(oldest))
    }
}
