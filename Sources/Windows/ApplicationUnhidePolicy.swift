import Foundation

enum ApplicationUnhideDecision: String, Equatable, Sendable {
    case disabled
    case alreadyVisible = "already-visible"
    case throttled
    case attempt
}

enum ApplicationUnhidePolicy {
    static let defaultMinimumInterval: TimeInterval = 2

    static func decision(
        enabled: Bool,
        isHidden: Bool,
        lastAttempt: Date?,
        now: Date,
        minimumInterval: TimeInterval = defaultMinimumInterval
    ) -> ApplicationUnhideDecision {
        guard enabled else { return .disabled }
        guard isHidden else { return .alreadyVisible }
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < minimumInterval {
            return .throttled
        }
        return .attempt
    }
}
