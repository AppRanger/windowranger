import Foundation

/// Lifecycle signals that can describe the same physical wake/topology transition. They are
/// deliberately coalesced so NSWorkspace wake, screen wake, session activation, and AppKit display
/// notifications cannot each start a separate recovery pass.
enum WakeReconciliationSource: String, CaseIterable, Equatable, Sendable {
    case systemWake = "system-wake"
    case screensWake = "screens-wake"
    case sessionBecameActive = "session-became-active"
    case displayConfigurationChanged = "display-configuration-changed"
}

struct WakeReconciliationRequest: Equatable, Sendable {
    let generation: UInt64
    let shouldSchedule: Bool
    let sources: Set<WakeReconciliationSource>
}

/// Small value-state coordinator used by WorkspaceEngine and deterministic unit tests. Generation
/// tokens make all pre-sleep and superseded work harmless, while duplicate lifecycle notifications
/// join the currently pending reconciliation instead of creating another sequence of AX writes.
struct WakeReconciliationState: Equatable, Sendable {
    private(set) var generation: UInt64 = 0
    private(set) var isSleeping = false
    private(set) var isPending = false
    private(set) var sources = Set<WakeReconciliationSource>()

    mutating func prepareForSleep() -> UInt64 {
        generation &+= 1
        isSleeping = true
        isPending = false
        sources.removeAll()
        return generation
    }

    mutating func request(_ source: WakeReconciliationSource) -> WakeReconciliationRequest {
        isSleeping = false
        sources.insert(source)
        if isPending {
            return WakeReconciliationRequest(
                generation: generation,
                shouldSchedule: false,
                sources: sources
            )
        }
        generation &+= 1
        isPending = true
        return WakeReconciliationRequest(
            generation: generation,
            shouldSchedule: true,
            sources: sources
        )
    }

    mutating func complete(generation expectedGeneration: UInt64) -> Bool {
        guard isPending, generation == expectedGeneration else { return false }
        isPending = false
        sources.removeAll()
        return true
    }

    func isCurrent(_ expectedGeneration: UInt64) -> Bool {
        isPending && !isSleeping && generation == expectedGeneration
    }
}

struct WakeReconciliationAttempt: Equatable, Sendable {
    let attemptIndex: Int
    let previousTopologySignature: String?
    let currentTopologySignature: String
    let connectedDisplayCount: Int
    let requiredProcessIdentifiers: Set<Int32>
    let successfullyEnumeratedProcessIdentifiers: Set<Int32>
    let receivedAdditionalLifecycleSignal: Bool
    let windowServerSessionAvailable: Bool
}

enum WakeReconciliationDecision: Equatable, Sendable {
    case complete
    case retry(afterMilliseconds: Int, reason: String)
    case completeDegraded(reason: String)
}

enum WakeReconciliationPolicy {
    static let maximumAttempts = 3
    static let retryDelaysMilliseconds = [180, 420]

    /// Completion is evidence-driven rather than a blind wake delay. A changed topology must be
    /// observed twice, and every still-running process that owned a tracked window must provide a
    /// fresh AXWindows snapshot. The final attempt degrades safely by leaving deferred windows
    /// untouched instead of starting an unbounded poll/write storm.
    static func decision(for attempt: WakeReconciliationAttempt) -> WakeReconciliationDecision {
        let missingProcesses = attempt.requiredProcessIdentifiers
            .subtracting(attempt.successfullyEnumeratedProcessIdentifiers)
        let topologyIsStable = attempt.previousTopologySignature == nil ||
            attempt.previousTopologySignature == attempt.currentTopologySignature
        let ready = attempt.connectedDisplayCount > 0 &&
            topologyIsStable &&
            missingProcesses.isEmpty &&
            attempt.windowServerSessionAvailable &&
            !attempt.receivedAdditionalLifecycleSignal

        if ready { return .complete }
        if attempt.attemptIndex + 1 >= maximumAttempts {
            var reasons: [String] = []
            if attempt.connectedDisplayCount == 0 { reasons.append("no-connected-display") }
            if !topologyIsStable { reasons.append("topology-not-stable") }
            if !missingProcesses.isEmpty { reasons.append("ax-enumeration-deferred") }
            if !attempt.windowServerSessionAvailable { reasons.append("window-server-session-unavailable") }
            if attempt.receivedAdditionalLifecycleSignal { reasons.append("new-lifecycle-signal") }
            return .completeDegraded(reason: reasons.joined(separator: ","))
        }

        let delay = retryDelaysMilliseconds[min(attempt.attemptIndex, retryDelaysMilliseconds.count - 1)]
        var reasons: [String] = []
        if attempt.connectedDisplayCount == 0 { reasons.append("no-connected-display") }
        if !topologyIsStable { reasons.append("topology-changed") }
        if !missingProcesses.isEmpty { reasons.append("ax-enumeration-deferred") }
        if !attempt.windowServerSessionAvailable { reasons.append("window-server-session-unavailable") }
        if attempt.receivedAdditionalLifecycleSignal { reasons.append("new-lifecycle-signal") }
        return .retry(afterMilliseconds: delay, reason: reasons.joined(separator: ","))
    }
}

struct WakeFocusCandidate<Key: Hashable & Sendable>: Equatable, Sendable {
    let key: Key
    let isActiveWorkspace: Bool
    let isMeaningfullyVisible: Bool
    let isOnInteractionDisplay: Bool
    let isFocusEligible: Bool
}

enum WakeFocusPolicy {
    /// A valid currently focused window is never disturbed. Recovery only chooses the prior local
    /// focus (then local stable order) when focus is nil or still attached to a parked managed
    /// window. Callers treat an unmanaged current focus as a genuine user choice and do nothing.
    static func replacement<Key: Hashable & Sendable>(
        currentManagedFocus: Key?,
        currentFocusIsUnmanaged: Bool,
        preSleepFocus: Key?,
        orderedCandidates: [WakeFocusCandidate<Key>]
    ) -> Key? {
        let eligible = orderedCandidates.filter {
            $0.isActiveWorkspace && $0.isMeaningfullyVisible &&
                $0.isOnInteractionDisplay && $0.isFocusEligible
        }
        if let currentManagedFocus, eligible.contains(where: { $0.key == currentManagedFocus }) {
            return nil
        }
        if currentFocusIsUnmanaged { return nil }
        if let preSleepFocus, eligible.contains(where: { $0.key == preSleepFocus }) {
            return preSleepFocus
        }
        return eligible.first?.key
    }
}

enum WakeWindowRecoveryPolicy {
    static func isWriteEligible(
        wasFreshlyEnumerated: Bool,
        disposition: WindowAdmissionDisposition
    ) -> Bool {
        wasFreshlyEnumerated && disposition.admitsNewWindow
    }

    static func geometryFreshnessMarker(wasFreshlyEnumerated: Bool) -> String {
        wasFreshlyEnumerated ? "fresh" : "deferred"
    }
}
