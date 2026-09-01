import AppKit
import ApplicationServices
import CoreGraphics
import Darwin

struct DisplaySnapshot: Equatable, Sendable, Identifiable {
    let identifier: String
    let bounds: CGRect
    let usableBounds: CGRect
    let isMain: Bool
    let isBuiltIn: Bool
    let name: String
    let fingerprint: DisplayFingerprint?

    var id: String { identifier }

    init(
        identifier: String,
        bounds: CGRect,
        usableBounds: CGRect? = nil,
        isMain: Bool,
        isBuiltIn: Bool = false,
        name: String,
        fingerprint: DisplayFingerprint? = nil
    ) {
        self.identifier = identifier
        self.bounds = bounds
        self.usableBounds = usableBounds ?? bounds
        self.isMain = isMain
        self.isBuiltIn = isBuiltIn
        self.name = name
        self.fingerprint = fingerprint
    }
}

enum DockEdge: String, Equatable, Sendable {
    case bottom
    case left
    case right
}

struct DockLayoutPreferences: Equatable, Sendable {
    let automaticallyHides: Bool
    let edge: DockEdge?
}

struct PersistedDisplayPlacement: Codable, Equatable, Sendable {
    let displayIdentifier: String
    let normalizedOrigin: CGPoint
}

struct ResolvedDisplayFrame: Equatable, Sendable {
    let frame: WindowFrame
    let usedFallbackDisplay: Bool
}

struct FocusFollowPlan: Equatable, Sendable {
    let displayIdentifier: String?
    let sourceWorkspaceID: UUID?
    let targetWorkspaceID: UUID
}

typealias AccordionOrientation = WorkspaceLayoutOrientation

enum FocusObservationDisposition: Equatable, Sendable {
    case unchanged
    case programmaticTarget
    case deferExternalChange
    case externalChange
}

enum ParkedFocusActivationDisposition: Equatable, Sendable {
    case unaffected
    case suppressStaleActivation
    case acceptExplicitActivation
}

enum ExactWindowFocusStep: Equatable, Sendable {
    case markWindowMain
    case focusWindowElement
    case focusApplicationWindow
    case makeApplicationFrontmost
    case raiseWindow
}

enum FocusCycleVerificationDecision: Equatable, Sendable {
    case succeeded
    case retryAppKitActivation
    case retryExactTarget
    case advanceToNextCandidate
    case abortForCompetingFocus
}

enum FocusCandidateAttemptPhase: String, Equatable, Sendable {
    case initial
    case appKitActivationFallback
    case exactRetry
    case exactRetryAfterAppKitActivation

    var exactAttempt: Int {
        switch self {
        case .exactRetry, .exactRetryAfterAppKitActivation: 1
        case .initial, .appKitActivationFallback: 0
        }
    }

    var appKitActivationAttempted: Bool {
        switch self {
        case .appKitActivationFallback, .exactRetryAfterAppKitActivation: true
        case .initial, .exactRetry: false
        }
    }

    var performsAppKitActivation: Bool { self == .appKitActivationFallback }

    var exactRetryPhase: FocusCandidateAttemptPhase {
        appKitActivationAttempted ? .exactRetryAfterAppKitActivation : .exactRetry
    }
}

enum KeyboardManipulationFocusDecision: String, Equatable, Sendable {
    case stable
    case reassertExactTarget = "reassert-exact-target"
    case failedAfterRetry = "failed-after-retry"
    case abortForCompetingFocus = "abort-for-competing-focus"
}

struct FocusVerificationToken: Equatable, Sendable {
    let generation: UInt64
    let correlationID: String
}

struct IgnoredWindowRemovalResult: Equatable, Sendable {
    let removedTrackedWindow: Bool
    let removedPendingAssignment: Bool
    let clearedLastFocusedWorkspaceIDs: Set<UUID>
    let removedTiledLayoutState: Bool
    let removedFullscreenState: Bool

    var changedManagedState: Bool {
        removedTrackedWindow ||
            removedPendingAssignment ||
            !clearedLastFocusedWorkspaceIDs.isEmpty ||
            removedTiledLayoutState ||
            removedFullscreenState
    }
}

struct WindowRefreshReport: Equatable, Sendable {
    let displays: [DisplaySnapshot]
    let topologySignature: String
    let requiredProcessIdentifiers: Set<pid_t>
    let successfullyEnumeratedProcessIdentifiers: Set<pid_t>
    let writeEligibleWindowKeys: Set<WindowKey>
    let deferredWindowKeys: Set<WindowKey>
    let retainedLayoutSlotWindowKeys: Set<WindowKey>
    let managedWindowCount: Int
}

enum StableLayoutSlotRetentionReason: String, Equatable, Sendable {
    case applicationEnumerationUnavailable = "application-enumeration-unavailable"
    case frameUnavailable = "frame-unavailable"
}

/// Layout membership and AX write eligibility deliberately differ while an existing participant
/// is temporarily unreadable. Authoritative lifecycle states still remove it immediately.
enum StableLayoutSlotPolicy {
    static func retentionReason(
        wasTracked: Bool,
        applicationEnumerationSucceeded: Bool,
        windowWasEnumerated: Bool,
        isCurrentlyIncludedInLayout: Bool,
        hasReadableFrame: Bool
    ) -> StableLayoutSlotRetentionReason? {
        guard wasTracked else { return nil }
        guard applicationEnumerationSucceeded else {
            return .applicationEnumerationUnavailable
        }
        guard windowWasEnumerated,
              isCurrentlyIncludedInLayout,
              !hasReadableFrame
        else { return nil }
        return .frameUnavailable
    }

    static func isAvailableForLayout(
        isWriteDeferred: Bool,
        retainsLayoutSlot: Bool,
        isExplicitlyEligible: Bool = true
    ) -> Bool {
        isExplicitlyEligible && (!isWriteDeferred || retainsLayoutSlot)
    }

    static func isAvailableForVisibilityLayout(
        isWriteDeferred: Bool,
        retainsLayoutSlot: Bool,
        isExcludedFromWorkspaceParticipation: Bool,
        isExplicitlyWriteEligible: Bool
    ) -> Bool {
        isAvailableForLayout(
            isWriteDeferred: isWriteDeferred,
            retainsLayoutSlot: retainsLayoutSlot,
            isExplicitlyEligible: !isExcludedFromWorkspaceParticipation &&
                (isExplicitlyWriteEligible || retainsLayoutSlot)
        )
    }

    static func transitions<Key: Hashable>(
        previous: Set<Key>,
        current: Set<Key>
    ) -> (entered: Set<Key>, released: Set<Key>) {
        (current.subtracting(previous), previous.subtracting(current))
    }
}

struct FullscreenObservationResolution: Equatable, Sendable {
    let isFullscreen: Bool
    let consecutiveAuthoritativeFalseObservations: Int
}

enum FullscreenSessionPolicy {
    static let quietBroadRefreshInterval: TimeInterval = 2

    /// Enter immediately, but require two authoritative false observations to leave. Unsupported
    /// or failed reads retain an existing session and are harmless for ordinary, never-fullscreen
    /// windows. This gives AppKit's fullscreen transition one settling interval without turning an
    /// AX timeout into permission for a frame write.
    static func resolve(
        observation: AXBooleanAttributeObservation,
        hadSession: Bool,
        consecutiveAuthoritativeFalseObservations: Int
    ) -> FullscreenObservationResolution {
        switch observation {
        case .trueValue:
            return FullscreenObservationResolution(
                isFullscreen: true,
                consecutiveAuthoritativeFalseObservations: 0
            )
        case .falseValue:
            guard hadSession, consecutiveAuthoritativeFalseObservations == 0 else {
                return FullscreenObservationResolution(
                    isFullscreen: false,
                    consecutiveAuthoritativeFalseObservations: 0
                )
            }
            return FullscreenObservationResolution(
                isFullscreen: true,
                consecutiveAuthoritativeFalseObservations: 1
            )
        case .unsupported, .unavailable:
            return FullscreenObservationResolution(
                isFullscreen: hadSession,
                consecutiveAuthoritativeFalseObservations: 0
            )
        }
    }

    static func shouldPerformBroadRefresh(
        hasForegroundGameSession: Bool,
        focusedGameObservation: AXBooleanAttributeObservation?,
        timeSinceBroadRefresh: TimeInterval
    ) -> Bool {
        guard hasForegroundGameSession else { return true }
        if focusedGameObservation == .falseValue { return true }
        return timeSinceBroadRefresh >= quietBroadRefreshInterval
    }

    static func allowsGeometryWrite(
        hasFullscreenSession: Bool,
        isTemporarilyDeferred: Bool
    ) -> Bool {
        !hasFullscreenSession && !isTemporarilyDeferred
    }
}

enum FullscreenGameMetadataPolicy {
    static func isGameModeEligible(bundle: Bundle?) -> Bool {
        isGameModeEligible(
            supportsGameMode: bundle?.object(forInfoDictionaryKey: "LSSupportsGameMode") as? Bool
        )
    }

    static func isGameModeEligible(supportsGameMode: Bool?) -> Bool {
        supportsGameMode == true
    }

    static func isDeclaredGame(bundle: Bundle?) -> Bool {
        isDeclaredGame(
            supportsGameMode: bundle?.object(forInfoDictionaryKey: "LSSupportsGameMode") as? Bool,
            supportsGameControllerMode: bundle?.object(forInfoDictionaryKey: "GCSupportsGameMode") as? Bool,
            applicationCategory: bundle?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
        )
    }

    static func isDeclaredGame(
        supportsGameMode: Bool?,
        supportsGameControllerMode: Bool?,
        applicationCategory: String?
    ) -> Bool {
        let normalizedCategory = applicationCategory?.lowercased()
        return supportsGameMode == true ||
            supportsGameControllerMode == true ||
            normalizedCategory == "public.app-category.games" ||
            normalizedCategory?.hasSuffix("-games") == true
    }
}

struct FullscreenGameSessionSnapshot: Equatable, Sendable {
    let processIdentifier: pid_t
    let windowIdentifier: CGWindowID
    let bundleIdentifier: String?
    let workspaceID: UUID
    let displayIdentifier: String
    let isGameModeEligible: Bool
}

/// Pure lifecycle rules for AX window snapshots. A successful `AXWindows` read is authoritative
/// for that process, so a missing window (including an inactive native tab that has closed) is
/// removed. An incomplete/failed read is not evidence of closure and retains prior state.
enum WindowEnumerationLifecycle {
    /// A locked or sleeping display session can transiently return a successful empty `AXWindows`
    /// list for every application. That is not evidence that every window closed. During a
    /// coordinated lifecycle transition, retain the known windows for the whole bounded recovery;
    /// while fully active, require one confirming global-empty snapshot before accepting it.
    static func shouldDeferGlobalEmptySnapshot(
        trackedWindowCount: Int,
        requiredProcessIdentifiers: Set<pid_t>,
        successfullyEnumeratedProcessIdentifiers: Set<pid_t>,
        enumeratedWindowCount: Int,
        isLifecycleTransitionActive: Bool,
        consecutiveGlobalEmptySnapshots: Int
    ) -> Bool {
        let isGlobalEmptySnapshot = trackedWindowCount > 0 &&
            !requiredProcessIdentifiers.isEmpty &&
            enumeratedWindowCount == 0 &&
            requiredProcessIdentifiers.isSubset(of: successfullyEnumeratedProcessIdentifiers)
        guard isGlobalEmptySnapshot else { return false }
        return isLifecycleTransitionActive || consecutiveGlobalEmptySnapshots == 0
    }

    static func removedTrackedWindowKeys(
        trackedWindowKeys: Set<WindowKey>,
        runningProcessIdentifiers: Set<pid_t>,
        successfullyEnumeratedProcessIdentifiers: Set<pid_t>,
        enumeratedWindowKeys: Set<WindowKey>
    ) -> Set<WindowKey> {
        Set(trackedWindowKeys.filter { key in
            !runningProcessIdentifiers.contains(key.processIdentifier) ||
                (successfullyEnumeratedProcessIdentifiers.contains(key.processIdentifier) &&
                    !enumeratedWindowKeys.contains(key))
        })
    }

    static func hasCurrentFullscreenObservation(
        sessionWindowKeys: Set<WindowKey>,
        enumeratedWindowKeys: Set<WindowKey>
    ) -> Bool {
        !sessionWindowKeys.isDisjoint(with: enumeratedWindowKeys)
    }

    static func diagnosticFocusKeyAfterEnumeration(
        previousKey: WindowKey?,
        observedKey: WindowKey?,
        ownProcessIdentifier: pid_t,
        removedWindowKeys: Set<WindowKey>
    ) -> WindowKey? {
        let retainedPreviousKey = previousKey.flatMap {
            removedWindowKeys.contains($0) ? nil : $0
        }
        guard let observedKey,
              observedKey.processIdentifier != ownProcessIdentifier,
              !removedWindowKeys.contains(observedKey)
        else { return retainedPreviousKey }
        return observedKey
    }

    static func pruning(
        _ trees: [TiledLayoutPartitionKey: TiledNode],
        removedWindowKeys: Set<WindowKey>
    ) -> [TiledLayoutPartitionKey: TiledNode] {
        guard !removedWindowKeys.isEmpty else { return trees }
        return trees.reduce(into: [:]) { result, entry in
            var tree: TiledNode? = entry.value
            for key in removedWindowKeys where tree?.contains(key) == true {
                tree = tree?.removing(key)
            }
            if let tree { result[entry.key] = tree }
        }
    }

    static func pruning(
        _ history: [UUID: WindowKey],
        removedWindowKeys: Set<WindowKey>
    ) -> [UUID: WindowKey] {
        history.filter { !removedWindowKeys.contains($0.value) }
    }
}

/// A screen lock or native fullscreen Space can make still-running applications lose their
/// Accessibility windows in stages. Preserve a coordinated collapse across multiple applications
/// while that lifecycle boundary is active, with a short grace period around otherwise fully active
/// transitions, while keeping a single application's successful absence authoritative immediately.
struct CoordinatedWindowEnumerationCollapseState {
    static let graceDuration: TimeInterval = 0.5

    private var deferralDeadline: Date?

    mutating func processIdentifiersToDefer(
        requiredProcessIdentifiers: Set<pid_t>,
        successfullyEnumeratedProcessIdentifiers: Set<pid_t>,
        enumeratedWindowProcessIdentifiers: Set<pid_t>,
        isLifecycleTransitionActive: Bool,
        hasCurrentFullscreenObservation: Bool = false,
        at now: Date = Date()
    ) -> Set<pid_t> {
        let successfullyEmptyProcessIdentifiers = requiredProcessIdentifiers
            .intersection(successfullyEnumeratedProcessIdentifiers)
            .subtracting(enumeratedWindowProcessIdentifiers)
        let isCoordinatedCollapse = requiredProcessIdentifiers.count >= 2 &&
            successfullyEmptyProcessIdentifiers.count >= 2 &&
            successfullyEmptyProcessIdentifiers.count * 2 >= requiredProcessIdentifiers.count

        guard isCoordinatedCollapse else {
            deferralDeadline = nil
            return []
        }
        if isLifecycleTransitionActive || hasCurrentFullscreenObservation {
            deferralDeadline = nil
            return successfullyEmptyProcessIdentifiers
        }
        if let deferralDeadline {
            guard now < deferralDeadline else {
                self.deferralDeadline = nil
                return []
            }
            return successfullyEmptyProcessIdentifiers
        }

        deferralDeadline = now.addingTimeInterval(Self.graceDuration)
        return successfullyEmptyProcessIdentifiers
    }
}

struct PostSleepWindowRecoveryUpdate: Equatable, Sendable {
    let protectedWindowKeys: Set<WindowKey>
    let newlyRecoveredWindowKeys: Set<WindowKey>
    let confirmedMissingWindowKeys: Set<WindowKey>
    let terminatedWindowKeys: Set<WindowKey>
    let authoritativeSuccessfullyEnumeratedProcessIdentifiers: Set<pid_t>
}

/// Keeps a persisted BSP partition intact while only some of its pre-sleep participants are
/// readable. Reconciling the tree against that partial participant set would otherwise remove the
/// protected leaves and make the temporary wake ordering permanent.
enum PostSleepTiledLayoutRecoveryPolicy {
    static func protectedParticipantKeys(
        in tree: TiledNode?,
        protectedWindowKeys: Set<WindowKey>
    ) -> Set<WindowKey> {
        guard let tree, !protectedWindowKeys.isEmpty else { return [] }
        return Set(tree.windowKeys).intersection(protectedWindowKeys)
    }

    static func shouldDeferPartition(
        tree: TiledNode?,
        protectedWindowKeys: Set<WindowKey>
    ) -> Bool {
        !protectedParticipantKeys(
            in: tree,
            protectedWindowKeys: protectedWindowKeys
        ).isEmpty
    }
}

/// Keeps pre-sleep window ownership fail-closed while Accessibility repopulates one application at
/// a time. A returning window releases only its exact key; it cannot make another application's
/// empty snapshot authoritative. Persistently missing keys are released only after the owning
/// process supplies two matching successful snapshots beyond a conservative wake grace period.
struct PostSleepWindowRecoveryState: Equatable, Sendable {
    static let missingWindowGraceInterval: TimeInterval = 15
    static let requiredStableSnapshotCount = 2

    private(set) var protectedWindowKeys = Set<WindowKey>()
    private var wakeStartedAt: Date?
    private var lastWindowKeysByProcess: [pid_t: Set<WindowKey>] = [:]
    private var stableSnapshotCountByProcess: [pid_t: Int] = [:]

    var isActive: Bool { !protectedWindowKeys.isEmpty }

    mutating func prepareForSleep(protecting windowKeys: Set<WindowKey>) {
        protectedWindowKeys.formUnion(windowKeys)
        wakeStartedAt = nil
        lastWindowKeysByProcess.removeAll()
        stableSnapshotCountByProcess.removeAll()
    }

    mutating func beginWake(at date: Date = Date()) {
        guard isActive, wakeStartedAt == nil else { return }
        wakeStartedAt = date
    }

    mutating func observe(
        runningProcessIdentifiers: Set<pid_t>,
        successfullyEnumeratedProcessIdentifiers: Set<pid_t>,
        enumeratedWindowKeys: Set<WindowKey>,
        at date: Date = Date()
    ) -> PostSleepWindowRecoveryUpdate {
        let newlyRecoveredWindowKeys = protectedWindowKeys.intersection(enumeratedWindowKeys)
        protectedWindowKeys.subtract(newlyRecoveredWindowKeys)

        let terminatedWindowKeys = Set(protectedWindowKeys.filter {
            !runningProcessIdentifiers.contains($0.processIdentifier)
        })
        protectedWindowKeys.subtract(terminatedWindowKeys)

        var confirmedMissingWindowKeys = Set<WindowKey>()
        let graceElapsed = wakeStartedAt.map {
            date.timeIntervalSince($0) >= Self.missingWindowGraceInterval
        } ?? false
        let protectedProcessIdentifiers = Set(protectedWindowKeys.map(\.processIdentifier))

        for processIdentifier in protectedProcessIdentifiers {
            guard graceElapsed,
                  successfullyEnumeratedProcessIdentifiers.contains(processIdentifier)
            else {
                lastWindowKeysByProcess.removeValue(forKey: processIdentifier)
                stableSnapshotCountByProcess.removeValue(forKey: processIdentifier)
                continue
            }

            let currentWindowKeys = Set(enumeratedWindowKeys.filter {
                $0.processIdentifier == processIdentifier
            })
            let stableSnapshotCount: Int
            if lastWindowKeysByProcess[processIdentifier] == currentWindowKeys {
                stableSnapshotCount = (stableSnapshotCountByProcess[processIdentifier] ?? 0) + 1
            } else {
                stableSnapshotCount = 1
            }
            lastWindowKeysByProcess[processIdentifier] = currentWindowKeys
            stableSnapshotCountByProcess[processIdentifier] = stableSnapshotCount

            guard stableSnapshotCount >= Self.requiredStableSnapshotCount else { continue }
            let missingWindowKeys = Set(protectedWindowKeys.filter {
                $0.processIdentifier == processIdentifier
            })
            confirmedMissingWindowKeys.formUnion(missingWindowKeys)
            protectedWindowKeys.subtract(missingWindowKeys)
        }

        let stillProtectedProcessIdentifiers = Set(protectedWindowKeys.map(\.processIdentifier))
        lastWindowKeysByProcess = lastWindowKeysByProcess.filter {
            stillProtectedProcessIdentifiers.contains($0.key)
        }
        stableSnapshotCountByProcess = stableSnapshotCountByProcess.filter {
            stillProtectedProcessIdentifiers.contains($0.key)
        }
        if protectedWindowKeys.isEmpty {
            wakeStartedAt = nil
            lastWindowKeysByProcess.removeAll()
            stableSnapshotCountByProcess.removeAll()
        }

        return PostSleepWindowRecoveryUpdate(
            protectedWindowKeys: protectedWindowKeys,
            newlyRecoveredWindowKeys: newlyRecoveredWindowKeys,
            confirmedMissingWindowKeys: confirmedMissingWindowKeys,
            terminatedWindowKeys: terminatedWindowKeys,
            authoritativeSuccessfullyEnumeratedProcessIdentifiers:
                successfullyEnumeratedProcessIdentifiers.subtracting(
                    Set(protectedWindowKeys.map(\.processIdentifier))
                )
        )
    }

    mutating func clear() {
        protectedWindowKeys.removeAll()
        wakeStartedAt = nil
        lastWindowKeysByProcess.removeAll()
        stableSnapshotCountByProcess.removeAll()
    }

    mutating func remove(_ key: WindowKey) {
        guard protectedWindowKeys.remove(key) != nil else { return }
        lastWindowKeysByProcess[key.processIdentifier]?.remove(key)
        let protectedProcessIdentifiers = Set(protectedWindowKeys.map(\.processIdentifier))
        lastWindowKeysByProcess = lastWindowKeysByProcess.filter {
            protectedProcessIdentifiers.contains($0.key)
        }
        stableSnapshotCountByProcess = stableSnapshotCountByProcess.filter {
            protectedProcessIdentifiers.contains($0.key)
        }
        if protectedWindowKeys.isEmpty {
            wakeStartedAt = nil
        }
    }
}

struct DropDownAppWindowHandoffCandidate {
    let key: WindowKey
    let bundleIdentifier: String?
}

/// A native tab switch can replace an application's AX window identifier while leaving the same
/// visible window and process in place. Quick App ownership may follow that replacement only when
/// the authoritative refresh leaves exactly one newly tracked eligible replacement for the
/// configured bundle and process. Other retained members of the same application group do not make
/// that exact one-for-one handoff ambiguous.
enum DropDownAppWindowHandoffPolicy {
    static func replacementWindowKey(
        sessionWindowKey: WindowKey,
        sessionBundleIdentifier: String,
        removedWindowKeys: Set<WindowKey>,
        newlyTrackedWindowKeys: Set<WindowKey>,
        availableWindows: [DropDownAppWindowHandoffCandidate]
    ) -> WindowKey? {
        guard removedWindowKeys.contains(sessionWindowKey) else { return nil }
        let matching = availableWindows.filter { candidate in
            candidate.key.processIdentifier == sessionWindowKey.processIdentifier &&
                newlyTrackedWindowKeys.contains(candidate.key) &&
                candidate.bundleIdentifier?.caseInsensitiveCompare(
                    sessionBundleIdentifier
                ) == .orderedSame
        }
        guard matching.count == 1, let replacement = matching.first else { return nil }
        return replacement.key
    }
}

enum DropDownAppLifecyclePolicy {
    static func shouldClearSessionForTopologyChange(
        topologyChanged: Bool,
        isLifecycleTransitionActive: Bool,
        deferredGlobalEmptySnapshot: Bool
    ) -> Bool {
        topologyChanged && !isLifecycleTransitionActive && !deferredGlobalEmptySnapshot
    }
}

enum DropDownAppConfigurationUpdatePolicy {
    static func shouldPreserveSession(
        previous: DropDownAppConfiguration?,
        next: DropDownAppConfiguration?
    ) -> Bool {
        guard let previous, let next else { return false }
        return previous.bundleIdentifier.caseInsensitiveCompare(next.bundleIdentifier) == .orderedSame
    }
}

struct DropDownAppStartupCandidate {
    let key: WindowKey
    let bundleIdentifier: String?
    let isMeaningfullyVisible: Bool
    let wasHiddenByWindowRanger: Bool
}

struct DropDownAppStartupSelection: Equatable {
    let windowKey: WindowKey
    let wasMeaningfullyVisible: Bool
    let wasHiddenByWindowRanger: Bool
}

enum QuickAppApplicationWindowPolicy {
    static func orderedWindowKeys(
        candidates: [WindowKey],
        existingOrder: [WindowKey] = [],
        requiredProcessIdentifier: pid_t? = nil
    ) -> [WindowKey]? {
        var seenCandidates = Set<WindowKey>()
        let candidates = candidates.filter { seenCandidates.insert($0).inserted }
        let processIdentifiers = Set(candidates.map(\.processIdentifier))
        guard !candidates.isEmpty,
              processIdentifiers.count == 1,
              requiredProcessIdentifier.map({ processIdentifiers == Set([$0]) }) ?? true
        else { return nil }
        var existingIndices = [WindowKey: Int]()
        for (index, key) in existingOrder.enumerated() where existingIndices[key] == nil {
            existingIndices[key] = index
        }
        return candidates.sorted { lhs, rhs in
            let leftIndex = existingIndices[lhs]
            let rightIndex = existingIndices[rhs]
            if leftIndex != rightIndex {
                return (leftIndex ?? Int.max) < (rightIndex ?? Int.max)
            }
            return lhs.windowIdentifier < rhs.windowIdentifier
        }
    }

    static func removing(
        _ key: WindowKey,
        from orderedWindowKeys: [WindowKey]
    ) -> [WindowKey] {
        orderedWindowKeys.filter { $0 != key }
    }

    static func presentedMembershipChanged(
        previousWindowKeys: [WindowKey],
        currentWindowKeys: [WindowKey],
        isPresented: Bool
    ) -> Bool {
        isPresented && previousWindowKeys != currentWindowKeys
    }

    static func cycleTarget(
        in orderedWindowKeys: [WindowKey],
        selectedWindowKey: WindowKey,
        offset: Int,
        wrapsWithinGroup: Bool
    ) -> WindowKey? {
        guard offset != 0,
              let currentIndex = orderedWindowKeys.firstIndex(of: selectedWindowKey)
        else { return nil }
        let nextIndex = currentIndex + (offset > 0 ? 1 : -1)
        if orderedWindowKeys.indices.contains(nextIndex) {
            return orderedWindowKeys[nextIndex]
        }
        guard wrapsWithinGroup else { return nil }
        return nextIndex < 0 ? orderedWindowKeys.last : orderedWindowKeys.first
    }
}

/// Startup claims every eligible window from one application process. A claimed application group
/// always begins hidden; launching WindowRanger must never present Shelf windows merely because the
/// application was visible before startup.
enum DropDownAppStartupPolicy {
    static func matchingCandidateCount(
        bundleIdentifier: String,
        candidates: [DropDownAppStartupCandidate]
    ) -> Int {
        candidates.filter {
            $0.bundleIdentifier?.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
        }.count
    }

    static func selection(
        bundleIdentifier: String,
        candidates: [DropDownAppStartupCandidate]
    ) -> DropDownAppStartupSelection? {
        let matching = candidates.filter {
            $0.bundleIdentifier?.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
        }
        guard matching.count == 1, let candidate = matching.first else { return nil }
        return DropDownAppStartupSelection(
            windowKey: candidate.key,
            wasMeaningfullyVisible: candidate.isMeaningfullyVisible,
            wasHiddenByWindowRanger: candidate.wasHiddenByWindowRanger
        )
    }

    /// A configured Shelf application owns all of its eligible windows when they come from one
    /// running application process. A second process remains ambiguous because one AppKit Hide
    /// request cannot truthfully govern both process lifecycles as one Shelf group.
    static func selections(
        bundleIdentifier: String,
        candidates: [DropDownAppStartupCandidate]
    ) -> [DropDownAppStartupSelection]? {
        var seen = Set<WindowKey>()
        let matching = candidates.filter {
            $0.bundleIdentifier?.caseInsensitiveCompare(bundleIdentifier) == .orderedSame &&
                seen.insert($0.key).inserted
        }
        guard !matching.isEmpty,
              Set(matching.map { $0.key.processIdentifier }).count == 1
        else { return nil }
        return matching.sorted { lhs, rhs in
            if lhs.key.processIdentifier != rhs.key.processIdentifier {
                return lhs.key.processIdentifier < rhs.key.processIdentifier
            }
            return lhs.key.windowIdentifier < rhs.key.windowIdentifier
        }.map {
            DropDownAppStartupSelection(
                windowKey: $0.key,
                wasMeaningfullyVisible: $0.isMeaningfullyVisible,
                wasHiddenByWindowRanger: $0.wasHiddenByWindowRanger
            )
        }
    }
}

struct PersistedDropDownAppSession: Codable, Equatable, Sendable {
    let windowKey: WindowKey
    let windowKeys: [WindowKey]
    let bundleIdentifier: String
    let displayIdentifier: String?
    let isApplicationHiddenByWindowRanger: Bool

    private enum CodingKeys: String, CodingKey {
        case windowKey
        case windowKeys
        case bundleIdentifier
        case displayIdentifier
        case isApplicationHiddenByWindowRanger
    }

    init(
        windowKey: WindowKey,
        windowKeys: [WindowKey]? = nil,
        bundleIdentifier: String,
        displayIdentifier: String?,
        isApplicationHiddenByWindowRanger: Bool
    ) {
        self.windowKey = windowKey
        self.windowKeys = Self.normalizedWindowKeys(
            primary: windowKey,
            candidates: windowKeys ?? [windowKey]
        )
        self.bundleIdentifier = bundleIdentifier
        self.displayIdentifier = displayIdentifier
        self.isApplicationHiddenByWindowRanger = isApplicationHiddenByWindowRanger
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        windowKey = try container.decode(WindowKey.self, forKey: .windowKey)
        windowKeys = Self.normalizedWindowKeys(
            primary: windowKey,
            candidates: try container.decodeIfPresent([WindowKey].self, forKey: .windowKeys)
                ?? [windowKey]
        )
        bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        displayIdentifier = try container.decodeIfPresent(String.self, forKey: .displayIdentifier)
        isApplicationHiddenByWindowRanger = try container.decodeIfPresent(
            Bool.self,
            forKey: .isApplicationHiddenByWindowRanger
        ) ?? false
    }

    private static func normalizedWindowKeys(
        primary: WindowKey,
        candidates: [WindowKey]
    ) -> [WindowKey] {
        var seen = Set<WindowKey>()
        return ([primary] + candidates).filter { seen.insert($0).inserted }
    }
}

enum DropDownAppHiddenSessionRecoveryPolicy {
    static func matches(
        _ persisted: PersistedDropDownAppSession?,
        windowKey: WindowKey,
        bundleIdentifier: String?,
        isStartup: Bool,
        isApplicationHidden: Bool
    ) -> Bool {
        guard isStartup,
              isApplicationHidden,
              let persisted,
              persisted.isApplicationHiddenByWindowRanger,
              persisted.windowKeys.contains(windowKey),
              let bundleIdentifier
        else { return false }
        return persisted.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
    }
}

enum DropDownAppVisibilityConfirmationDisposition: Equatable {
    case confirmed
    case retry
    case timedOut
}

enum DropDownAppVisibilityConfirmationPolicy {
    static let maximumAttempts = 10

    static func disposition(
        expectedHidden: Bool,
        observedHidden: Bool?,
        attempt: Int,
        maximumAttempts: Int = maximumAttempts
    ) -> DropDownAppVisibilityConfirmationDisposition {
        if observedHidden == expectedHidden { return .confirmed }
        return attempt < maximumAttempts ? .retry : .timedOut
    }
}

enum DropDownAppVisibilityRequestPolicy {
    static func wasDispatched(
        applicationMatched: Bool,
        appKitReturnValue _: Bool
    ) -> Bool {
        applicationMatched
    }
}

enum DropDownAppLaunchWatchdogDisposition: Equatable {
    case resolveToggle
    case retry(remainingAttempts: Int)
    case exhausted
}

enum DropDownAppLaunchWatchdogPolicy {
    static let activatesApplication = true
    static let initialDelay: TimeInterval = 0.2
    static let retryDelay: TimeInterval = 0.15
    static let maximumAttempts = 8

    static func disposition(
        availableWindowCount: Int,
        remainingAttempts: Int
    ) -> DropDownAppLaunchWatchdogDisposition {
        if availableWindowCount > 0 { return .resolveToggle }
        guard remainingAttempts > 1 else { return .exhausted }
        return .retry(remainingAttempts: remainingAttempts - 1)
    }
}

enum QuickAppTransitionPhase: Equatable, Sendable {
    case idle
    case launching(String)
    case showing(String)
    case hiding(String)
}

enum QuickAppSwitchRequestDisposition: Equatable, Sendable {
    case begin
    case cancelLaunchAndBegin
    case queueLatest
    case ignore
}

enum QuickAppTransitionPolicy {
    static func cycleOriginBundleIdentifier(
        selectedBundleIdentifier: String?,
        pendingBundleIdentifier: String?
    ) -> String? {
        pendingBundleIdentifier ?? selectedBundleIdentifier
    }

    static func switchDisposition(
        phase: QuickAppTransitionPhase,
        targetBundleKey: String
    ) -> QuickAppSwitchRequestDisposition {
        switch phase {
        case .idle:
            .begin
        case let .launching(activeBundleKey):
            activeBundleKey == targetBundleKey ? .ignore : .cancelLaunchAndBegin
        case .showing, .hiding:
            .queueLatest
        }
    }

    static func directShowDisposition(
        phase: QuickAppTransitionPhase,
        isPresented: Bool
    ) -> QuickAppSwitchRequestDisposition {
        if isPresented { return .ignore }
        return switch phase {
        case .idle:
            .begin
        case .hiding:
            .queueLatest
        case .launching, .showing:
            .ignore
        }
    }

    static func shouldCancelPendingLaunch(
        bundleIdentifier: String,
        previousConfigurations: [DropDownAppConfiguration],
        nextConfigurations: [DropDownAppConfiguration]
    ) -> Bool {
        let previous = previousConfigurations.first {
            $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
        }
        let next = nextConfigurations.first {
            $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
        }
        return next == nil || next != previous
    }

    static func shouldInvalidateAnimationForRebind(
        reboundBundleKey: String,
        phase: QuickAppTransitionPhase,
        sessionIsPresented: Bool
    ) -> Bool {
        if sessionIsPresented { return true }
        return switch phase {
        case let .showing(activeKey), let .hiding(activeKey):
            activeKey == reboundBundleKey
        case .idle, .launching:
            false
        }
    }
}

enum QuickAppApplicationSwitchActivationDisposition: Equatable, Sendable {
    case incoming
    case outgoing
    case unrelated
}

enum QuickAppApplicationSwitchPolicy {
    static func activationDisposition(
        activatedProcessIdentifier: pid_t,
        incomingProcessIdentifier: pid_t,
        outgoingProcessIdentifier: pid_t
    ) -> QuickAppApplicationSwitchActivationDisposition {
        if activatedProcessIdentifier == incomingProcessIdentifier { return .incoming }
        if activatedProcessIdentifier == outgoingProcessIdentifier { return .outgoing }
        return .unrelated
    }
}

/// A window that becomes an ignored companion surface must leave Quick App ownership without ever
/// receiving a recovery frame. Application visibility is separate from window geometry: if
/// WindowRanger hid the application, discarding the session requests an unhide and confirms it on
/// the existing bounded visibility path.
enum IgnoredQuickAppDiscardPolicy {
    static let performsFrameWrite = false

    static func transitionAfterDiscard(
        _ phase: QuickAppTransitionPhase,
        bundleKey: String
    ) -> QuickAppTransitionPhase {
        switch phase {
        case .idle:
            return .idle
        case let .launching(activeKey):
            return activeKey == bundleKey ? .idle : phase
        case let .showing(activeKey):
            return activeKey == bundleKey ? .idle : phase
        case let .hiding(activeKey):
            return activeKey == bundleKey ? .idle : phase
        }
    }

    static func shouldClearPendingSelection(
        pendingBundleIdentifier: String?,
        discardedBundleKey: String,
        interruptedTransition: Bool
    ) -> Bool {
        interruptedTransition ||
            pendingBundleIdentifier?.lowercased() == discardedBundleKey
    }

    static func shouldRequestApplicationUnhide(
        wasHiddenByWindowRanger: Bool,
        observedHidden: Bool?
    ) -> Bool {
        wasHiddenByWindowRanger || observedHidden == true
    }
}

/// Visibility-only debt left when an ignored companion surface had been used as a Quick App.
/// Deliberately carries no window key, frame, or restore geometry, so satisfying it cannot move the
/// ignored surface. A generation prevents an older confirmation chain from acting after ownership
/// has changed.
struct IgnoredQuickAppVisibilityRecovery: Codable, Equatable, Sendable {
    let generation: UInt64
    let processIdentifier: pid_t
    let bundleIdentifier: String
    var confirmationInFlight: Bool

    mutating func shouldRetain(
        after disposition: DropDownAppVisibilityConfirmationDisposition
    ) -> Bool {
        switch disposition {
        case .confirmed:
            return false
        case .retry:
            return true
        case .timedOut:
            confirmationInFlight = false
            return true
        }
    }
}

enum QuickAppInteractionPolicy {
    struct PresentedActivationDecision: Equatable {
        let selectsActivatedConfiguration: Bool
        let restacksPresentedGroup: Bool
    }

    static func presentedActivationDecision(
        activatedBundleIdentifier: String,
        selectedBundleIdentifier: String?
    ) -> PresentedActivationDecision {
        PresentedActivationDecision(
            selectsActivatedConfiguration: selectedBundleIdentifier.map {
                $0.caseInsensitiveCompare(activatedBundleIdentifier) != .orderedSame
            } ?? true,
            restacksPresentedGroup: true
        )
    }

    static func preservesPresentedShelfForActivation(
        activatedProcessIdentifier: pid_t,
        ownProcessIdentifier: pid_t,
        commandPalettePresented: Bool
    ) -> Bool {
        commandPalettePresented && activatedProcessIdentifier == ownProcessIdentifier
    }

    static func routesWindowCycleToShelf(
        shelfIsPresented: Bool,
        configuredAppCount: Int,
        transitionInProgress: Bool
    ) -> Bool {
        (shelfIsPresented || transitionInProgress) && configuredAppCount > 0
    }

    static func routesDirectionalFocusToShelf(
        shelfIsPresented: Bool,
        presentedWindowCount: Int,
        transitionInProgress: Bool
    ) -> Bool {
        (shelfIsPresented && presentedWindowCount > 0) || transitionInProgress
    }

    static func directionalFocusUsesShelfAxis(
        _ direction: WindowDirection,
        shelfDirection: DropDownAppDirection
    ) -> Bool {
        switch shelfDirection {
        case .top, .bottom:
            direction == .left || direction == .right
        case .left, .right:
            direction == .up || direction == .down
        }
    }

    static func restoresPresentedShelfFocus(
        shelfProcessIdentifier: pid_t,
        precedingProcessIdentifier: pid_t?
    ) -> Bool {
        shelfProcessIdentifier == precedingProcessIdentifier
    }

    static func activatesApplicationForLaunch(
        commandPalettePresented: Bool,
        applicationSwitchInProgress: Bool = false
    ) -> Bool {
        !commandPalettePresented && !applicationSwitchInProgress
    }

    static func focusesQuickAppAfterShow(commandPalettePresented: Bool) -> Bool {
        !commandPalettePresented
    }
}

enum WindowLayoutOverride: String, Codable, Equatable, Sendable {
    case automatic
    case floating
    case managed
}

enum WindowLayoutDecision: String, Equatable, Sendable {
    case appRuleExcluded = "app-rule-excluded"
    case explicitlyFloating = "explicitly-floating"
    case explicitlyManaged = "explicitly-managed"
    case automaticallyFloatingDialog = "automatically-floating-dialog"
    case automaticallyFloatingSecondary = "automatically-floating-secondary"
    case managedNormal = "managed-normal"

    var includesInLayout: Bool {
        self == .explicitlyManaged || self == .managedNormal
    }
}

struct PersistedWindowAssignment: Codable, Equatable, Sendable {
    let bundleIdentifier: String
    let workspaceID: UUID
    let restoreFrame: WindowFrame
    let displayPlacement: PersistedDisplayPlacement?
    let layoutOverride: WindowLayoutOverride
    let layoutOrder: Int?
    let layoutWeight: Double?

    var isFloating: Bool { layoutOverride == .floating }

    init(
        bundleIdentifier: String,
        workspaceID: UUID,
        restoreFrame: WindowFrame,
        displayPlacement: PersistedDisplayPlacement? = nil,
        isFloating: Bool = false,
        layoutOverride: WindowLayoutOverride? = nil,
        layoutOrder: Int? = nil,
        layoutWeight: Double? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.workspaceID = workspaceID
        self.restoreFrame = restoreFrame
        self.displayPlacement = displayPlacement
        self.layoutOverride = layoutOverride ?? (isFloating ? .floating : .automatic)
        self.layoutOrder = layoutOrder
        self.layoutWeight = layoutWeight
    }

    private enum CodingKeys: String, CodingKey {
        case bundleIdentifier, workspaceID, restoreFrame, displayPlacement, isFloating, layoutOverride
        case layoutOrder, layoutWeight
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        workspaceID = try container.decode(UUID.self, forKey: .workspaceID)
        restoreFrame = try container.decode(WindowFrame.self, forKey: .restoreFrame)
        displayPlacement = try container.decodeIfPresent(PersistedDisplayPlacement.self, forKey: .displayPlacement)
        layoutOverride = try container.decodeIfPresent(WindowLayoutOverride.self, forKey: .layoutOverride)
            ?? ((try container.decodeIfPresent(Bool.self, forKey: .isFloating) ?? false) ? .floating : .automatic)
        layoutOrder = try container.decodeIfPresent(Int.self, forKey: .layoutOrder)
        layoutWeight = try container.decodeIfPresent(Double.self, forKey: .layoutWeight)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
        try container.encode(workspaceID, forKey: .workspaceID)
        try container.encode(restoreFrame, forKey: .restoreFrame)
        try container.encodeIfPresent(displayPlacement, forKey: .displayPlacement)
        try container.encode(layoutOverride, forKey: .layoutOverride)
        try container.encodeIfPresent(layoutOrder, forKey: .layoutOrder)
        try container.encodeIfPresent(layoutWeight, forKey: .layoutWeight)
        // Retain the legacy field so an older build does not silently lose explicit floating
        // state if a user temporarily runs it during development.
        try container.encode(isFloating, forKey: .isFloating)
    }
}

enum FloatingToggleDecision: Equatable, Sendable {
    case setLayoutOverride(WindowLayoutOverride)
    case blockedByAppRule
    case blockedByFixedSizeWindow
    case blockedByProtectedDialog
}

enum FloatingToggleResult: Equatable, Sendable {
    case enabled
    case disabled
    case blockedByAppRule(String)
    case blockedByFixedSizeWindow
    case blockedByProtectedDialog

    var commandFeedbackMessage: String {
        switch self {
        case .enabled:
            "Window is floating"
        case .disabled:
            "Window returned to the workspace layout"
        case let .blockedByAppRule(appName):
            "\(appName) is excluded by an App Rule. That rule remains in control."
        case .blockedByFixedSizeWindow:
            "This window cannot be resized, so it must remain floating."
        case .blockedByProtectedDialog:
            "This dialog must remain floating at its application-chosen size."
        }
    }
}

enum WindowGeometryWriteMode: String, Equatable, Sendable {
    case frame
    case positionOnly = "position-only"
}

enum StartupInactiveWorkspaceSizingPolicy {
    static let messages = [
        "Arranging the furniture…",
        "Putting every window in its place…",
        "Straightening the desktop…",
        "Preparing your other workspaces…",
        "Asking the windows to form an orderly queue…",
    ]

    static func message(seed: Int) -> String {
        guard !messages.isEmpty else { return "Preparing your workspaces…" }
        return messages[abs(seed % messages.count)]
    }

    static func shouldResize(
        isEnabled: Bool,
        isWorkspaceActive: Bool,
        layout: WorkspaceLayout,
        includesInLayout: Bool,
        writeMode: WindowGeometryWriteMode,
        isWriteDeferred: Bool,
        hasFullscreenSession: Bool,
        isMeaningfullyVisible: Bool,
        currentSize: CGSize,
        targetSize: CGSize
    ) -> Bool {
        isEnabled &&
            !isWorkspaceActive &&
            layout != .none &&
            includesInLayout &&
            writeMode == .frame &&
            !isWriteDeferred &&
            !hasFullscreenSession &&
            !isMeaningfullyVisible &&
            (abs(currentSize.width - targetSize.width) >= 0.5 ||
                abs(currentSize.height - targetSize.height) >= 0.5)
    }
}

struct CommandFeedbackRequest: Equatable, Sendable {
    let message: String
    let preferredDisplayIdentifier: String?
    let correlationID: String?
}

enum MoveWorkspaceFocusDisposition: String, Equatable, Sendable {
    case sendOnly = "send-only"
    case follow = "follow"
    case unchangedVisible = "unchanged-visible"
}

struct PersistedWorkspaceState: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let windowServerSession: String
    let activeWorkspaceID: UUID
    let windows: [String: PersistedWindowAssignment]
    let activeWorkspaceIDsByDisplay: [String: UUID]?
    let profileID: UUID?
    let tiledTrees: [PersistedTiledTree]?
    let dropDownAppSession: PersistedDropDownAppSession?
    let dropDownAppSessions: [String: PersistedDropDownAppSession]?
    let ignoredQuickAppVisibilityRecoveries: [String: IgnoredQuickAppVisibilityRecovery]?

    init(
        version: Int,
        windowServerSession: String,
        activeWorkspaceID: UUID,
        windows: [String: PersistedWindowAssignment],
        activeWorkspaceIDsByDisplay: [String: UUID]? = nil,
        profileID: UUID? = nil,
        tiledTrees: [PersistedTiledTree]? = nil,
        dropDownAppSession: PersistedDropDownAppSession? = nil,
        dropDownAppSessions: [String: PersistedDropDownAppSession]? = nil,
        ignoredQuickAppVisibilityRecoveries: [String: IgnoredQuickAppVisibilityRecovery]? = nil
    ) {
        self.version = version
        self.windowServerSession = windowServerSession
        self.activeWorkspaceID = activeWorkspaceID
        self.windows = windows
        self.activeWorkspaceIDsByDisplay = activeWorkspaceIDsByDisplay
        self.profileID = profileID
        self.tiledTrees = tiledTrees
        self.dropDownAppSession = dropDownAppSession
        self.dropDownAppSessions = dropDownAppSessions
        self.ignoredQuickAppVisibilityRecoveries = ignoredQuickAppVisibilityRecoveries
    }

    func assignment(
        for windowIdentifier: CGWindowID,
        bundleIdentifier: String?,
        validWorkspaceIDs: Set<UUID>
    ) -> PersistedWindowAssignment? {
        guard let bundleIdentifier,
              let assignment = windows[String(windowIdentifier)],
              assignment.bundleIdentifier == bundleIdentifier,
              validWorkspaceIDs.contains(assignment.workspaceID)
        else { return nil }
        return assignment
    }
}

protocol WorkspaceStateFileAccess: Sendable {
    func fileExists(at url: URL) -> Bool
    func fileSize(at url: URL) throws -> Int
    func read(from url: URL) throws -> Data
    func write(_ data: Data, to url: URL) throws
}

struct LocalWorkspaceStateFileAccess: WorkspaceStateFileAccess {
    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func fileSize(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.intValue ?? 0
    }

    func read(from url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

final class WorkspaceStateStore {
    static let maximumStateFileBytes = 8 * 1_048_576

    let fileURL: URL
    private(set) var windowServerSession: String

    private let writeQueue = DispatchQueue(
        label: "\(ApplicationIdentity.bundleIdentifier).workspace-state"
    )
    private let stateLock = NSLock()
    private var lastScheduledState: PersistedWorkspaceState?
    private var pendingWriteStates: [PersistedWorkspaceState] = []
    private let sessionProvider: () -> String
    private let fileAccess: any WorkspaceStateFileAccess

    init(
        fileURL: URL = WorkspaceStateStore.defaultFileURL,
        sessionProvider: @escaping () -> String = WorkspaceStateStore.currentWindowServerSession,
        fileAccess: any WorkspaceStateFileAccess = LocalWorkspaceStateFileAccess()
    ) {
        self.fileURL = fileURL
        self.sessionProvider = sessionProvider
        self.fileAccess = fileAccess
        windowServerSession = sessionProvider()
    }

    enum SessionRefreshResult: Equatable {
        case unchanged
        case changed(previous: String, current: String)
        case unavailable
    }

    /// WindowServer can restart without terminating this process. Refresh only at a coordinated
    /// lifecycle boundary; an unavailable read is not evidence of a new session and therefore must
    /// not invalidate otherwise recoverable state.
    func refreshWindowServerSession() -> SessionRefreshResult {
        let current = sessionProvider()
        guard !current.isEmpty else { return .unavailable }
        guard current != windowServerSession else { return .unchanged }
        let previous = windowServerSession
        windowServerSession = current
        stateLock.lock()
        lastScheduledState = nil
        stateLock.unlock()
        return .changed(previous: previous, current: current)
    }

    func load() -> PersistedWorkspaceState? {
        guard !windowServerSession.isEmpty,
              fileAccess.fileExists(at: fileURL),
              let fileSize = try? fileAccess.fileSize(at: fileURL),
              fileSize <= Self.maximumStateFileBytes,
              let data = try? fileAccess.read(from: fileURL),
              data.count <= Self.maximumStateFileBytes,
              let state = try? JSONDecoder().decode(PersistedWorkspaceState.self, from: data),
              state.version == PersistedWorkspaceState.currentVersion,
              state.windowServerSession == windowServerSession
        else { return nil }
        stateLock.lock()
        lastScheduledState = state
        stateLock.unlock()
        return state
    }

    func save(_ state: PersistedWorkspaceState, waitForCompletion: Bool = false) {
        guard !state.windowServerSession.isEmpty,
              state.windowServerSession == windowServerSession
        else { return }

        let fileExists = fileAccess.fileExists(at: fileURL)
        stateLock.lock()
        let sameWriteIsPending = pendingWriteStates.contains(state)
        let isUnchanged = lastScheduledState == state && (fileExists || sameWriteIsPending)
        if !isUnchanged {
            lastScheduledState = state
            pendingWriteStates.append(state)
        }
        stateLock.unlock()

        if isUnchanged {
            if waitForCompletion { writeQueue.sync {} }
            return
        }

        let url = fileURL
        let fileAccess = fileAccess
        let work: @Sendable () -> Void = { [weak self] in
            var succeeded = false
            defer { self?.completeWrite(of: state, succeeded: succeeded) }
            do {
                let data = try JSONEncoder().encode(state)
                guard data.count <= Self.maximumStateFileBytes else { return }
                try fileAccess.write(data, to: url)
                succeeded = true
            } catch {
                // Recovery persistence is best effort, but a later identical state will retry.
            }
        }
        if waitForCompletion {
            writeQueue.sync(execute: work)
        } else {
            writeQueue.async(execute: work)
        }
    }

    private func completeWrite(of state: PersistedWorkspaceState, succeeded: Bool) {
        stateLock.lock()
        if let pendingIndex = pendingWriteStates.firstIndex(of: state) {
            pendingWriteStates.remove(at: pendingIndex)
        }
        if !succeeded,
           lastScheduledState == state,
           !pendingWriteStates.contains(state) {
            // A failed write must remain retryable on the next persistence tick.
            lastScheduledState = nil
        }
        stateLock.unlock()
    }

    func waitForWrites() {
        writeQueue.sync {}
    }

    static var defaultFileURL: URL {
        ApplicationIdentity.cacheDirectoryURL
            .appendingPathComponent("workspace-state.json", isDirectory: false)
    }

    /// Window IDs are exact only for the lifetime of WindowServer. A reboot is not a sufficient
    /// boundary because WindowServer can restart independently after logout or a graphics fault.
    static func currentWindowServerSession() -> String {
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var length = 0
        guard sysctl(&name, 4, nil, &length, nil, 0) == 0, length > 0 else { return "" }
        let capacity = length / MemoryLayout<kinfo_proc>.stride
        var processes = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
        guard sysctl(&name, 4, &processes, &length, nil, 0) == 0 else { return "" }

        for var process in processes.prefix(min(capacity, length / MemoryLayout<kinfo_proc>.stride)) {
            let command = withUnsafeBytes(of: &process.kp_proc.p_comm) { bytes in
                String(cString: bytes.baseAddress!.assumingMemoryBound(to: CChar.self))
            }
            guard command == "WindowServer" else { continue }
            let start = process.kp_proc.p_un.__p_starttime
            return "ws:\(process.kp_proc.p_pid):\(start.tv_sec).\(start.tv_usec)"
        }
        return ""
    }
}

struct WorkspaceEngineState: Equatable {
    let currentWorkspaceID: UUID
    let activeWorkspaceIDs: Set<UUID>
    let previousWorkspaceID: UUID?
    let managedWindowCount: Int
    let accessibilityGranted: Bool
    let profileID: UUID?
    let activeWorkspaceIDByDisplay: [String: UUID]
    let focusedWindowHighlightWorkspaceContexts:
        [WindowKey: FocusedWindowHighlightWorkspaceContext]

    init(
        currentWorkspaceID: UUID,
        activeWorkspaceIDs: Set<UUID>,
        previousWorkspaceID: UUID?,
        managedWindowCount: Int,
        accessibilityGranted: Bool,
        profileID: UUID? = nil,
        activeWorkspaceIDByDisplay: [String: UUID] = [:],
        focusedWindowHighlightWorkspaceContexts:
            [WindowKey: FocusedWindowHighlightWorkspaceContext] = [:]
    ) {
        self.currentWorkspaceID = currentWorkspaceID
        self.activeWorkspaceIDs = activeWorkspaceIDs
        self.previousWorkspaceID = previousWorkspaceID
        self.managedWindowCount = managedWindowCount
        self.accessibilityGranted = accessibilityGranted
        self.profileID = profileID
        self.activeWorkspaceIDByDisplay = activeWorkspaceIDByDisplay
        self.focusedWindowHighlightWorkspaceContexts =
            focusedWindowHighlightWorkspaceContexts
    }
}

struct WorkspaceEngineStateEmissionGate {
    private var lastScheduledState: WorkspaceEngineState?

    mutating func shouldSchedule(
        _ state: WorkspaceEngineState,
        force: Bool
    ) -> Bool {
        guard force || lastScheduledState != state else { return false }
        lastScheduledState = state
        return true
    }
}

/// Immutable derived lookups for the engine's active workspace and app-rule configuration.
/// Replacing the source arrays/maps replaces this value as one unit on the engine queue.
struct WorkspaceEngineLookupIndex {
    let validWorkspaceIDs: Set<UUID>

    private let workspacesByID: [UUID: WorkspaceDefinition]
    private let resolvedRulesByBundleIdentifier: [String: ResolvedAppRule]

    init(
        workspaces: [WorkspaceDefinition],
        appRulesByBundleIdentifier: [String: AppRule]
    ) {
        let workspaceIDs = Set(workspaces.map(\.id))
        validWorkspaceIDs = workspaceIDs

        var indexedWorkspaces: [UUID: WorkspaceDefinition] = [:]
        for workspace in workspaces where indexedWorkspaces[workspace.id] == nil {
            // Preserve the existing `first(where:)` behavior if malformed input repeats an ID.
            indexedWorkspaces[workspace.id] = workspace
        }
        workspacesByID = indexedWorkspaces

        resolvedRulesByBundleIdentifier = appRulesByBundleIdentifier.mapValues {
            $0.resolved(validWorkspaceIDs: workspaceIDs)
        }
    }

    func workspace(for workspaceID: UUID) -> WorkspaceDefinition? {
        workspacesByID[workspaceID]
    }

    func resolvedRule(forBundleIdentifier bundleIdentifier: String) -> ResolvedAppRule {
        resolvedRulesByBundleIdentifier[bundleIdentifier.lowercased()] ?? .none
    }
}

struct WindowAdmissionSupportRecord: Identifiable, Equatable, Sendable, Codable {
    let id: String
    let bundleIdentifier: String
    let disposition: String
    let reason: String
    let compatibilityProfileIdentifier: String?
    let role: String
    let subrole: String
    let windowLayer: String
    let isMinimized: Bool
    let isFullscreen: Bool
    let modalObservation: String
    let focusedObservation: String
    let mainObservation: String
    let fullscreenButton: String
    let minimizeButton: String
    let closeButton: String
    let zoomButton: String
    let defaultButton: String
    let cancelButton: String
    let nativeFilePanelIdentifierObservation: String
    let positionSettable: String
    let sizeSettable: String
}

struct WindowAdmissionSupportSnapshot: Equatable, Sendable, Codable {
    let schemaVersion: Int
    let records: [WindowAdmissionSupportRecord]

    init(records: [WindowAdmissionSupportRecord]) {
        schemaVersion = 4
        self.records = records
    }

    func encodedString() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

struct WorkspaceApplicationTarget: Equatable, Sendable {
    let workspaceID: UUID
    let bundleIdentifier: String?
    let processIdentifier: pid_t

    func matches(bundleIdentifier candidateBundleIdentifier: String?, processIdentifier: pid_t) -> Bool {
        if let bundleIdentifier = Self.normalizedBundleIdentifier(bundleIdentifier) {
            return Self.normalizedBundleIdentifier(candidateBundleIdentifier) == bundleIdentifier
        }
        return processIdentifier == self.processIdentifier
    }

    private static func normalizedBundleIdentifier(_ value: String?) -> String? {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized?.isEmpty == false ? normalized : nil
    }
}

enum WorkspacePreviewFocusCandidatePolicy {
    static func prioritizing(
        _ selectedWindowKey: WindowKey?,
        in candidates: [WindowKey]
    ) -> [WindowKey] {
        guard let selectedWindowKey,
              let selectedIndex = candidates.firstIndex(of: selectedWindowKey)
        else { return candidates }
        var result = candidates
        result.remove(at: selectedIndex)
        result.insert(selectedWindowKey, at: 0)
        return result
    }
}

struct WorkspaceApplicationSummary: Identifiable, Equatable, Sendable {
    let id: String
    let target: WorkspaceApplicationTarget
    let name: String
    let windowCount: Int
    let applicationURL: URL?
}

struct WorkspaceApplicationWindowCandidate: Equatable, Sendable {
    let key: WindowKey
    let workspaceID: UUID
    let bundleIdentifier: String?
    let processIdentifier: pid_t
    let name: String
    let applicationURL: URL?
    let layoutOrder: Int
}

enum WorkspaceApplicationSummaryPolicy {
    private enum GroupKey: Hashable {
        case bundleIdentifier(String)
        case processIdentifier(pid_t)

        var stableIdentifier: String {
            switch self {
            case let .bundleIdentifier(value): "bundle:\(value)"
            case let .processIdentifier(value): "process:\(value)"
            }
        }
    }

    static func summaries(
        workspaceID: UUID,
        candidates: [WorkspaceApplicationWindowCandidate],
        preferredWindow: WindowKey?
    ) -> [WorkspaceApplicationSummary] {
        let grouped = Dictionary(grouping: candidates.filter { $0.workspaceID == workspaceID }) {
            candidate -> GroupKey in
            if let bundleIdentifier = normalizedBundleIdentifier(candidate.bundleIdentifier) {
                return .bundleIdentifier(bundleIdentifier)
            }
            return .processIdentifier(candidate.processIdentifier)
        }
        return grouped.compactMap { groupKey, group -> WorkspaceApplicationSummary? in
            guard let representative = group.sorted(by: { lhs, rhs in
                if lhs.key == preferredWindow { return true }
                if rhs.key == preferredWindow { return false }
                if lhs.layoutOrder != rhs.layoutOrder { return lhs.layoutOrder < rhs.layoutOrder }
                if lhs.processIdentifier != rhs.processIdentifier {
                    return lhs.processIdentifier < rhs.processIdentifier
                }
                return lhs.key.windowIdentifier < rhs.key.windowIdentifier
            }).first else { return nil }
            return WorkspaceApplicationSummary(
                id: "\(workspaceID.uuidString)|\(groupKey.stableIdentifier)",
                target: WorkspaceApplicationTarget(
                    workspaceID: workspaceID,
                    bundleIdentifier: representative.bundleIdentifier,
                    processIdentifier: representative.processIdentifier
                ),
                name: representative.name,
                windowCount: group.count,
                applicationURL: representative.applicationURL
            )
        }.sorted { lhs, rhs in
            let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            return comparison == .orderedSame ? lhs.id < rhs.id : comparison == .orderedAscending
        }
    }

    private static func normalizedBundleIdentifier(_ value: String?) -> String? {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized?.isEmpty == false ? normalized : nil
    }
}

final class WorkspaceEngine {
    var onStateChanged: ((WorkspaceEngineState) -> Void)?
    var onWorkspacePreviewStateChanged: ((Set<UUID>) -> Void)?
    var onQuickAppSelectionChanged: ((String) -> Void)?
    var onWorkspaceLayoutChanged: ((UUID, WorkspaceLayout) -> Void)?
    var onWorkspaceLayoutConfigurationChanged: ((UUID, WorkspaceLayoutConfiguration) -> Void)?
    var onTiledPlacementCommitted: ((TiledPlacementUndoTransaction) -> Void)?
    var onFreeformPlacementCommitted: ((FreeformPlacementUndoTransaction) -> Void)?
    var onCommandFeedback: ((CommandFeedbackRequest) -> Void)?
    var onWorkspaceDisplayAssignmentsChanged: (([UUID: String]) -> Void)?
    var onFullscreenGameSessionChanged: ((FullscreenGameSessionSnapshot?) -> Void)?
    var onVerifiedFocusTarget: ((FocusedWindowHighlightTarget) -> Void)?
    var onTiledResizePreviewChanged: ((TiledResizePreviewEvent) -> Void)?

    private struct TrackedWindow {
        let key: WindowKey
        var element: AXUIElement
        var processIdentifier: pid_t
        var bundleIdentifier: String?
        var workspaceID: UUID
        var restoreFrame: WindowFrame
        var displayPlacement: PersistedDisplayPlacement?
        var layoutOverride: WindowLayoutOverride
        var workspaceRuleOverrideActive: Bool
        var admissionDecision: WindowAdmissionDecision
        var layoutOrder: Int
        var layoutWeight: Double
    }

    private struct FocusedWindowSnapshot {
        let key: WindowKey
        let element: AXUIElement
        let frame: WindowFrame?
    }

    private struct WorkspacePreviewStateMember: Equatable {
        let key: WindowKey
        let intendedFrame: CGRect
        let layoutOrder: Int
        let isLastFocused: Bool
    }

    private struct FullscreenWindowSession {
        let key: WindowKey
        var element: AXUIElement
        var processIdentifier: pid_t
        var bundleIdentifier: String?
        var workspaceID: UUID
        var displayIdentifier: String
        var frame: WindowFrame?
        var isDeclaredGame: Bool
        var isGameModeEligible: Bool
        let enteredAt: Date
    }

    private struct PendingQuickAppConfigurationUpdate {
        let configurations: [DropDownAppConfiguration]
        let presentation: QuickAppShelfPresentation
    }

    private struct SleepFocusContext {
        let windowKey: WindowKey?
        let workspaceID: UUID?
        let displayIdentifier: String?
    }

    private struct PositionChange {
        let window: TrackedWindow
        let position: CGPoint
    }

    private struct FrameChange {
        let window: TrackedWindow
        let frame: WindowFrame
    }

    private struct TiledPlacementCommitContext {
        let validationToken: String
        let createdAt: Date
        let focusedWindow: WindowKey
        let partition: TiledLayoutPartitionKey
        let participantKeys: Set<WindowKey>
        let originalTree: TiledNode
        let previews: [VisualPlacement: TiledPlacementPreview]
    }

    private struct FreeformPlacementCommitContext {
        let validationToken: String
        let createdAt: Date
        let focusedWindow: WindowKey
        let workspaceID: UUID
        let displayIdentifier: String
        let displayBounds: CGRect
        let originalFrame: WindowFrame
        let previews: [VisualPlacement: FreeformPlacementPreview]
    }

    private struct DirectionalMoveGestureContext {
        let identifier: String
        let createdAt: Date
        let firstDirection: WindowDirection
        let focusedWindow: WindowKey?
        let workspaceID: UUID?
        let displayIdentifier: String?
        let layout: WorkspaceLayout?
        let placement: TiledPlacementCommitContext?
    }

    private struct ManualTiledDragSession: Equatable {
        let focusedWindow: WindowKey
        let partition: TiledLayoutPartitionKey
        let candidateDestination: TiledDragDestination?
    }

    private struct ManualTiledMovePreviewSession {
        let token: UUID
        let focusedWindow: WindowKey
        let partition: TiledLayoutPartitionKey
        let participantKeys: Set<WindowKey>
        let originalTree: TiledNode
        let originalFrames: [WindowKey: WindowFrame]
        let configuration: WorkspaceLayoutConfiguration
        let layoutBounds: CGRect
        let topologySignature: String
        let profileID: UUID?
        var candidateDestination: TiledDragDestination?
        var proposedTree: TiledNode
        var proposedFrames: [WindowKey: WindowFrame]
    }

    private struct ManualTiledResizeSession {
        let token: UUID
        let focusedWindow: WindowKey
        let partition: TiledLayoutPartitionKey
        let participantKeys: Set<WindowKey>
        let originalTree: TiledNode
        let originalFrames: [WindowKey: WindowFrame]
        let configuration: WorkspaceLayoutConfiguration
        let layoutBounds: CGRect
        let topologySignature: String
        let profileID: UUID?
        let draggedEdges: TiledResizeDraggedEdges
        let anchorFrame: WindowFrame
        let anchorPointer: CGPoint
        var proposedTree: TiledNode
        var proposedFrames: [WindowKey: WindowFrame]
    }

    private struct DropDownAppSession {
        var windowKey: WindowKey
        var additionalWindowKeys: [WindowKey] = []
        let bundleIdentifier: String
        var direction: DropDownAppDirection
        var isAnimationEnabled: Bool
        var isPresented: Bool
        var isApplicationHiddenByWindowRanger: Bool
        var displayIdentifier: String?
        var previousFocusKey: WindowKey?

        var windowKeys: [WindowKey] {
            var seen = Set<WindowKey>()
            return ([windowKey] + additionalWindowKeys)
                .filter { seen.insert($0).inserted }
                .sorted { lhs, rhs in
                    if lhs.processIdentifier != rhs.processIdentifier {
                        return lhs.processIdentifier < rhs.processIdentifier
                    }
                    return lhs.windowIdentifier < rhs.windowIdentifier
                }
        }

        mutating func selectWindow(_ key: WindowKey) {
            guard windowKeys.contains(key), key != windowKey else { return }
            let previousPrimary = windowKey
            additionalWindowKeys.removeAll { $0 == key }
            additionalWindowKeys.insert(previousPrimary, at: 0)
            windowKey = key
        }

        mutating func synchronizeWindowKeys(_ keys: [WindowKey]) {
            var seen = Set<WindowKey>()
            let normalized = keys.filter { seen.insert($0).inserted }
            guard !normalized.isEmpty else {
                additionalWindowKeys = []
                return
            }
            if normalized.contains(windowKey) {
                additionalWindowKeys = normalized.filter { $0 != windowKey }
            } else {
                windowKey = normalized[0]
                additionalWindowKeys = Array(normalized.dropFirst())
            }
        }

        mutating func removeWindow(_ key: WindowKey) -> Bool {
            let remaining = QuickAppApplicationWindowPolicy.removing(key, from: windowKeys)
            guard !remaining.isEmpty else { return false }
            synchronizeWindowKeys(remaining)
            return true
        }
    }

    private struct PendingDropDownAppLaunch {
        let bundleIdentifier: String
        let displayName: String
        let generation: UInt64
    }

    private struct PendingQuickAppPresentationContext {
        let previousFocusKey: WindowKey?
    }

    private struct PendingQuickAppSelection {
        let bundleIdentifier: String
        let correlationID: String
    }

    private struct QuickAppApplicationSwitchHandoff {
        let outgoingBundleKey: String
        let incomingBundleKey: String
        let correlationID: String
    }

    private enum ManualTiledMoveReconciliation: Equatable {
        case none
        case dragInProgress
        case moved
    }

    private let queue = DispatchQueue(
        label: "\(ApplicationIdentity.bundleIdentifier).workspace-engine",
        qos: .userInitiated
    )
    private var timer: DispatchSourceTimer?
    private var workspaces: [WorkspaceDefinition] {
        didSet { rebuildWorkspaceEngineLookupIndex() }
    }
    private var currentProfileID: UUID?
    private var currentWorkspaceID: UUID
    private var previousWorkspaceID: UUID?
    private var previousWorkspaceIDByDisplay: [String: UUID] = [:]
    private var activeWorkspaceIDByDisplay: [String: UUID]
    private var displayMode: MultiDisplayMode
    private var workspaceDisplayAssignments: [UUID: String]
    private var appRulesByBundleIdentifier: [String: AppRule] {
        didSet { rebuildWorkspaceEngineLookupIndex() }
    }
    private var workspaceEngineLookupIndex = WorkspaceEngineLookupIndex(
        workspaces: [],
        appRulesByBundleIdentifier: [:]
    )
    private var quickAppConfigurations: [DropDownAppConfiguration]
    private var quickAppShelfPresentation: QuickAppShelfPresentation
    /// Exact ownership is retained per configured Quick App, including entries that are currently
    /// hidden while another shelf entry is presented. The computed legacy property below keeps
    /// the existing presentation code focused on the selected entry.
    private var quickAppSessions: [String: DropDownAppSession] = [:]
    private var dropDownAppConfiguration: DropDownAppConfiguration?
    private var dropDownAppSession: DropDownAppSession? {
        get {
            guard let bundleIdentifier = dropDownAppConfiguration?.bundleIdentifier else {
                return nil
            }
            return quickAppSessions[Self.normalizedBundleIdentifier(bundleIdentifier)]
        }
        set {
            guard let bundleIdentifier = dropDownAppConfiguration?.bundleIdentifier else {
                return
            }
            let key = Self.normalizedBundleIdentifier(bundleIdentifier)
            if let newValue {
                quickAppSessions[key] = newValue
            } else {
                quickAppSessions.removeValue(forKey: key)
            }
        }
    }
    private var isQuickAppShelfPresented: Bool {
        quickAppSessions.values.contains(where: \.isPresented)
    }
    private var dropDownAnimationGeneration: UInt64 = 0
    private var dropDownLaunchGeneration: UInt64 = 0
    private var pendingDropDownAppLaunch: PendingDropDownAppLaunch?
    private var pendingQuickAppPresentationContext: PendingQuickAppPresentationContext?
    private var pendingQuickAppSelection: PendingQuickAppSelection?
    private var pendingQuickAppHideAfterPresentation = false
    private var quickAppApplicationSwitchHandoff: QuickAppApplicationSwitchHandoff?
    private var quickAppTransition: QuickAppTransitionPhase = .idle
    private var quickAppNeighborVisibilityGeneration: [String: UInt64] = [:]
    private var ignoredQuickAppVisibilityRecoveryGeneration: UInt64 = 0
    private var ignoredQuickAppVisibilityRecoveries: [String: IgnoredQuickAppVisibilityRecovery] = [:]
    private var pendingPausedQuickAppConfigurationUpdate: PendingQuickAppConfigurationUpdate?
    private var quickAppTopologyChangedWhilePaused = false
    private var commandPalettePresented = false
    private var isWindowManagementPaused = false
    private var focusFollowsMovedWindow: Bool
    private var automaticallyUnhideApplications: Bool
    private var focusedWindowHighlightEnabled: Bool
    private var lastDisplays: [DisplaySnapshot] = []
    private var windows: [WindowKey: TrackedWindow] = [:]
    private var tiledTrees: [TiledLayoutPartitionKey: TiledNode]
    private var radialPlacementCommitContext: TiledPlacementCommitContext? = nil
    private var radialFreeformPlacementCommitContext: FreeformPlacementCommitContext? = nil
    private var directionalMoveGestureContext: DirectionalMoveGestureContext? = nil
    private var manualTiledDragSession: ManualTiledDragSession? = nil
    private var manualTiledMovePreviewSession: ManualTiledMovePreviewSession? = nil
    private var manualTiledResizeSession: ManualTiledResizeSession? = nil
    private var ignoredWindowKeys = Set<WindowKey>()
    private var admissionDecisionByWindow: [WindowKey: WindowAdmissionDecision] = [:]
    private var admissionMetadataByWindow: [WindowKey: WindowAdmissionMetadata] = [:]
    private var rejectedResizeRecoveryAttemptedWindowKeys = Set<WindowKey>()
    private var resizeRecoveryNeedsImmediateReflow = false
    private var lastKnownWindowLayer: [WindowKey: Int] = [:]
    private var lastFocusedWindow: [UUID: WindowKey] = [:]
    private var lastObservedFocusedWindow: WindowKey?
    private var lastDiagnosticFocusedWindow: FocusedWindowSnapshot?
    private var programmaticFocusTarget: WindowKey?
    private var programmaticFocusDeadline = Date.distantPast
    private var programmaticFocusCorrelationID: String?
    private var programmaticFocusGeneration: UInt64?
    private var radialPointerFocusProcessIdentifier: pid_t?
    private var radialPointerFocusDeadline = Date.distantPast
    private var radialPointerFocusGeneration: UInt64?
    private var focusActionGeneration: UInt64 = 0
    private let focusActionGenerationLock = NSLock()
    private let profileTransitionGenerationGate = ProfileTransitionGenerationGate()
    private var pendingFocusVerification: DispatchWorkItem?
    private var supersededProgrammaticActivationUntil: [pid_t: Date] = [:]
    private var focusCycleRejectedUntil: [WindowKey: Date] = [:]
    private var recentInteractionDisplayIdentifier: String?
    private var recentInteractionFocusTarget: WindowKey?
    private var recentInteractionDisplayDeadline = Date.distantPast
    private var staleParkedFocusSuppression: [WindowKey: Date] = [:]
    private var lastAutomaticUnhideAttemptByProcess: [pid_t: Date] = [:]
    private var lastBackgroundLayoutSignature: String?
    private var lastSolvedTiledFrames: [WindowKey: WindowFrame] = [:]
    private var temporarilyDeferredWindowKeys = Set<WindowKey>()
    private var retainedLayoutSlotWindowKeys = Set<WindowKey>()
    private var fullscreenSessions: [WindowKey: FullscreenWindowSession] = [:]
    private var fullscreenAuthoritativeFalseCounts: [WindowKey: Int] = [:]
    private var foregroundFullscreenGameSessionKey: WindowKey?
    private var lastEmittedFullscreenGameSession: FullscreenGameSessionSnapshot?
    private var stateEmissionGate = WorkspaceEngineStateEmissionGate()
    private var workspacePreviewObservationEnabled = false
    private var hasWorkspacePreviewStateBaseline = false
    private var workspacePreviewStateByWorkspace: [UUID: [WorkspacePreviewStateMember]] = [:]
    private var declaredGameByBundleIdentifier: [String: Bool] = [:]
    private var gameModeEligibilityByBundleIdentifier: [String: Bool] = [:]
    private var lastBroadWindowRefreshDate = Date.distantPast
    private var wakeReconciliationState = WakeReconciliationState()
    private var screenSessionLifecycleState = ScreenSessionLifecycleState()
    private var wakeReconciliationWorkItem: DispatchWorkItem?
    private var wakeAttemptIndex = 0
    private var wakePreviousTopologySignature: String?
    private var wakeReceivedAdditionalSignal = false
    private var preSleepFocusContext: SleepFocusContext?
    private var lastWakeCompletionDate = Date.distantPast
    private var lastWakeCompletedTopologySignature: String?
    private var consecutiveGlobalEmptySnapshots = 0
    private var coordinatedWindowEnumerationCollapseState =
        CoordinatedWindowEnumerationCollapseState()
    private var postSleepWindowRecoveryState = PostSleepWindowRecoveryState()
    private let stateStore: WorkspaceStateStore
    private let diagnostics: DiagnosticLogger
    private var windowServerSessionValidated = true
    private var pendingRestoredWindows: [String: PersistedWindowAssignment]
    private var pendingRestoredDropDownAppSessions: [String: PersistedDropDownAppSession]
    private let startupGraceDeadline = Date().addingTimeInterval(30)
    private let ownProcessIdentifier = ProcessInfo.processInfo.processIdentifier
    private let preSizeInactiveLayoutsOnStartup: Bool

    init(
        workspaces: [WorkspaceDefinition],
        profileID: UUID? = nil,
        displayMode: MultiDisplayMode = .unified,
        workspaceDisplayAssignments: [UUID: String] = [:],
        appRules: [AppRule] = [],
        dropDownApp: DropDownAppConfiguration? = nil,
        quickApps: [DropDownAppConfiguration] = [],
        quickAppShelfPresentation: QuickAppShelfPresentation = QuickAppShelfPresentation(),
        selectedQuickAppBundleIdentifier: String? = nil,
        focusFollowsMovedWindow: Bool = false,
        automaticallyUnhideApplications: Bool = false,
        focusedWindowHighlightEnabled: Bool = false,
        preSizeInactiveLayoutsOnStartup: Bool = false,
        stateStore: WorkspaceStateStore = WorkspaceStateStore(),
        diagnostics: DiagnosticLogger = .disabled
    ) {
        let initial = workspaces.isEmpty ? WorkspaceDefinition.defaults : workspaces
        self.workspaces = initial
        currentProfileID = profileID
        self.displayMode = displayMode
        self.workspaceDisplayAssignments = workspaceDisplayAssignments
        appRulesByBundleIdentifier = Self.indexedAppRules(appRules)
        workspaceEngineLookupIndex = WorkspaceEngineLookupIndex(
            workspaces: initial,
            appRulesByBundleIdentifier: appRulesByBundleIdentifier
        )
        quickAppConfigurations = QuickAppShelfPolicy.normalized(
            quickApps.isEmpty ? dropDownApp.map { [$0] } ?? [] : quickApps
        )
        self.quickAppShelfPresentation = quickAppShelfPresentation
        dropDownAppConfiguration = quickAppConfigurations.first(where: {
            $0.bundleIdentifier.caseInsensitiveCompare(
                selectedQuickAppBundleIdentifier ?? ""
            ) == .orderedSame
        }) ?? quickAppConfigurations.first
        self.focusFollowsMovedWindow = focusFollowsMovedWindow
        self.automaticallyUnhideApplications = automaticallyUnhideApplications
        self.focusedWindowHighlightEnabled = focusedWindowHighlightEnabled
        self.preSizeInactiveLayoutsOnStartup = preSizeInactiveLayoutsOnStartup
        self.stateStore = stateStore
        self.diagnostics = diagnostics
        let restoredState = stateStore.load()
        ignoredQuickAppVisibilityRecoveries = Self.restoredIgnoredQuickAppVisibilityRecoveries(
            restoredState?.ignoredQuickAppVisibilityRecoveries
        )
        ignoredQuickAppVisibilityRecoveryGeneration = ignoredQuickAppVisibilityRecoveries.values
            .map(\.generation)
            .max() ?? 0
        let restoredProfileMatches = restoredState.map {
            Self.persistedStateProfileMatches(
                persistedProfileID: $0.profileID,
                currentProfileID: profileID
            )
        } ?? false
        pendingRestoredWindows = restoredProfileMatches ? (restoredState?.windows ?? [:]) : [:]
        let persistedSessions = restoredProfileMatches
            ? (restoredState?.dropDownAppSessions
                ?? restoredState?.dropDownAppSession.map {
                    [Self.normalizedBundleIdentifier($0.bundleIdentifier): $0]
                }
                ?? [:])
            : [:]
        let configuredQuickAppBundleKeys = Set(quickAppConfigurations.map {
            Self.normalizedBundleIdentifier($0.bundleIdentifier)
        })
        pendingRestoredDropDownAppSessions = persistedSessions.filter {
            $0.value.isApplicationHiddenByWindowRanger &&
                configuredQuickAppBundleKeys.contains($0.key)
        }
        let validWorkspaceIDs = Set(initial.map(\.id))
        currentWorkspaceID = (restoredProfileMatches ? restoredState : nil)
            .map(\.activeWorkspaceID)
            .flatMap { validWorkspaceIDs.contains($0) ? $0 : nil }
            ?? initial[0].id
        activeWorkspaceIDByDisplay = restoredProfileMatches
            ? (restoredState?.activeWorkspaceIDsByDisplay ?? [:]) : [:]
        if restoredProfileMatches {
            tiledTrees = Dictionary(
                (restoredState?.tiledTrees ?? []).map { ($0.partition, $0.tree) },
                uniquingKeysWith: { first, _ in first }
            ).filter { validWorkspaceIDs.contains($0.key.workspaceID) }
        } else {
            tiledTrees = [:]
        }
    }

    static func persistedStateProfileMatches(
        persistedProfileID: UUID?,
        currentProfileID: UUID?
    ) -> Bool {
        persistedProfileID == nil || currentProfileID == nil || persistedProfileID == currentProfileID
    }

    func start() {
        logSessionHeader()
        _ = AccessibilityWindow.requestPermission()
        queue.async { [weak self] in
            guard let self else { return }
            self.refreshWindows(isStartup: true)
            self.diagnostics.log(
                category: "session",
                event: "startup-state-ready",
                fields: [
                    "display-mode": self.displayMode.rawValue,
                    "current-workspace": Self.shortIdentifier(self.currentWorkspaceID.uuidString),
                    "active-workspaces": self.diagnosticActiveWorkspaceMap(),
                ]
            )
            self.applyVisibility()
            self.preSizeInactiveWorkspaceLayoutsForStartup()
            self.lastBackgroundLayoutSignature = self.backgroundLayoutSignature(
                displays: Self.activeDisplays()
            )
            self.persistState(preservingPendingRestores: true)
            self.emitState()

            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 0.5, repeating: 0.75, leeway: .milliseconds(100))
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                guard !self.wakeReconciliationState.isSleeping,
                      !self.wakeReconciliationState.isPending,
                      self.windowServerSessionValidated
                else { return }
                let foregroundSession = self.foregroundFullscreenGameSessionKey.flatMap {
                    self.fullscreenSessions[$0]
                }
                let focusedGameObservation = foregroundSession.map {
                    AccessibilityWindow.fullscreenObservation(of: $0.element)
                }
                guard FullscreenSessionPolicy.shouldPerformBroadRefresh(
                    hasForegroundGameSession: foregroundSession != nil,
                    focusedGameObservation: focusedGameObservation,
                    timeSinceBroadRefresh: Date().timeIntervalSince(self.lastBroadWindowRefreshDate)
                ) else { return }
                self.refreshWindows(
                    followExternalFocus: !self.isWindowManagementPaused,
                    performAXWrites: !self.isWindowManagementPaused
                )
                self.persistState(preservingPendingRestores: Date() < self.startupGraceDeadline)
                self.emitState(force: self.commandPalettePresented)
            }
            self.timer = timer
            timer.resume()
        }
    }

    /// Suspends WindowRanger's input-independent management writes without changing layout intent.
    /// Resume first takes a read-only snapshot so tiled moves made during Pause are not learned as
    /// new tree structure, then applies the current workspace rules exactly once.
    func setWindowManagementPaused(_ paused: Bool) {
        queue.async { [weak self] in
            guard let self, self.isWindowManagementPaused != paused else { return }
            if paused {
                self.cancelManualTiledPreviewTransactions(reason: "pause-mode")
                self.isWindowManagementPaused = true
                self.dropDownAnimationGeneration &+= 1
                self.quickAppNeighborVisibilityGeneration.removeAll()
                self.cancelPendingDropDownAppLaunch()
                self.pendingQuickAppSelection = nil
                self.pendingQuickAppHideAfterPresentation = false
                self.quickAppApplicationSwitchHandoff = nil
                self.quickAppTransition = .idle
                self.directionalMoveGestureContext = nil
                self.manualTiledDragSession = nil
                self.invalidateFocusWorkForLifecycle()
                self.lastBackgroundLayoutSignature = nil
                self.diagnostics.log(
                    category: "pause-mode",
                    event: "window-management-paused"
                )
                return
            }

            let correlationID = "pause-resume-\(UUID().uuidString.prefix(6))"
            let report = self.refreshWindows(
                correlationID: correlationID,
                performAXWrites: false,
                observeFocus: true
            )
            self.isWindowManagementPaused = false
            if self.quickAppTopologyChangedWhilePaused {
                self.quickAppTopologyChangedWhilePaused = false
                self.restoreAndClearDropDownAppSession(reason: "paused-display-topology-changed")
            }
            for bundleKey in Array(self.quickAppSessions.keys) where
                self.quickAppSessions[bundleKey].map({ self.windows[$0.windowKey] == nil }) == true {
                self.restoreAndClearQuickAppSession(
                    bundleKey: bundleKey,
                    reason: "paused-window-removed"
                )
            }
            if let pendingUpdate = self.pendingPausedQuickAppConfigurationUpdate {
                self.pendingPausedQuickAppConfigurationUpdate = nil
                self.applyQuickAppConfigurations(
                    pendingUpdate.configurations,
                    presentation: pendingUpdate.presentation,
                    reconcileImmediately: false
                )
            }
            guard !self.wakeReconciliationState.isSleeping,
                  !self.wakeReconciliationState.isPending
            else {
                self.diagnostics.log(
                    category: "pause-mode",
                    event: "window-management-resumed",
                    correlation: correlationID,
                    fields: ["reconciled": "false"]
                )
                return
            }
            self.applyVisibility(
                displays: report.displays,
                correlationID: correlationID,
                eligibleWindowKeys: report.writeEligibleWindowKeys
            )
            if self.isQuickAppShelfPresented {
                self.reconcilePresentedQuickAppGroup(
                    correlationID: correlationID,
                    focusSelected: false
                )
            }
            self.lastBackgroundLayoutSignature = self.backgroundLayoutSignature(
                displays: report.displays
            )
            self.persistState(preservingPendingRestores: true)
            self.emitState()
            self.diagnostics.log(
                category: "pause-mode",
                event: "window-management-resumed",
                correlation: correlationID,
                fields: ["reconciled": "true"]
            )
        }
    }

    /// Captures only durable intent before sleep and invalidates every delayed focus/layout action.
    /// NSWorkspace posts this on its own notification center before the machine sleeps, so the
    /// synchronous queue hand-off gives persistence a bounded opportunity to finish.
    func prepareForSystemSleep() {
        queue.sync {
            cancelManualTiledPreviewTransactions(reason: "system-sleep")
            postSleepWindowRecoveryState.prepareForSleep(protecting: Set(windows.keys))
            restoreAndClearDropDownAppSession(reason: "system-sleep")
            let focused = interactionFocusedWindowSnapshot()
            let tracked = focused.flatMap { windows[$0.key] }
            let displays = Self.activeDisplays()
            preSleepFocusContext = SleepFocusContext(
                windowKey: focused?.key,
                workspaceID: tracked?.workspaceID,
                displayIdentifier: focused?.frame.flatMap {
                    Self.displayPlacement(for: $0, displays: displays)?.displayIdentifier
                } ?? tracked?.displayPlacement?.displayIdentifier
            )
            let generation = wakeReconciliationState.prepareForSleep()
            lastWakeCompletedTopologySignature = nil
            lastWakeCompletionDate = .distantPast
            wakeReconciliationWorkItem?.cancel()
            wakeReconciliationWorkItem = nil
            directionalMoveGestureContext = nil
            manualTiledDragSession = nil
            cancelPendingDropDownAppLaunch()
            invalidateFocusWorkForLifecycle()
            persistState(preservingPendingRestores: true, waitForCompletion: true)
            diagnostics.log(
                category: "lifecycle",
                event: "system-will-sleep",
                correlation: "wake-\(generation)",
                fields: [
                    "topology": Self.displayTopologySignature(displays),
                    "display-count": String(displays.count),
                    "focused-window": focused.map { Self.diagnosticWindowKey($0.key) } ?? "none",
                    "focused-workspace": tracked.map {
                        Self.shortIdentifier($0.workspaceID.uuidString)
                    } ?? "none",
                ]
            )
        }
    }

    /// Screen sleep and fast-user-switch/session lock do not end the WindowServer session. Keep
    /// exact window and Quick App ownership, but stop background discovery until a coordinated wake
    /// obtains a fresh Accessibility snapshot.
    func prepareForScreenSleep(source: ScreenSessionSuspensionSource) {
        queue.sync {
            cancelManualTiledPreviewTransactions(reason: source.rawValue)
            screenSessionLifecycleState.suspend(source)
            postSleepWindowRecoveryState.prepareForSleep(protecting: Set(windows.keys))
            if wakeReconciliationState.isSleeping {
                diagnostics.log(
                    category: "lifecycle",
                    event: "screen-session-suspension-coalesced",
                    fields: ["source": source.rawValue]
                )
                return
            }
            let focused = interactionFocusedWindowSnapshot()
            let tracked = focused.flatMap { windows[$0.key] }
            let displays = Self.activeDisplays()
            preSleepFocusContext = SleepFocusContext(
                windowKey: focused?.key,
                workspaceID: tracked?.workspaceID,
                displayIdentifier: focused?.frame.flatMap {
                    Self.displayPlacement(for: $0, displays: displays)?.displayIdentifier
                } ?? tracked?.displayPlacement?.displayIdentifier
            )
            let generation = wakeReconciliationState.prepareForSleep()
            lastWakeCompletedTopologySignature = nil
            lastWakeCompletionDate = .distantPast
            wakeReconciliationWorkItem?.cancel()
            wakeReconciliationWorkItem = nil
            directionalMoveGestureContext = nil
            manualTiledDragSession = nil
            dropDownAnimationGeneration &+= 1
            cancelPendingDropDownAppLaunch()
            pendingQuickAppSelection = nil
            pendingQuickAppHideAfterPresentation = false
            quickAppApplicationSwitchHandoff = nil
            quickAppTransition = .idle
            invalidateFocusWorkForLifecycle()
            persistState(preservingPendingRestores: true, waitForCompletion: true)
            diagnostics.log(
                category: "lifecycle",
                event: "screen-session-suspended",
                correlation: "wake-\(generation)",
                fields: [
                    "source": source.rawValue,
                    "topology": Self.displayTopologySignature(displays),
                    "display-count": String(displays.count),
                    "managed-window-count": String(windows.count),
                    "quick-app-session": dropDownAppSession == nil ? "none" : "retained",
                ]
            )
        }
    }

    /// Starts, or joins, a bounded wake reconciliation. Display identities are supplied only after
    /// SettingsStore has refreshed its portable monitor pins on the main actor.
    func requestWakeReconciliation(
        source: WakeReconciliationSource,
        workspaceDisplayAssignments: [UUID: String]
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.screenSessionLifecycleState.receive(source) else {
                self.diagnostics.log(
                    category: "lifecycle",
                    event: "wake-reconciliation-deferred",
                    fields: [
                        "source": source.rawValue,
                        "awaiting": self.screenSessionLifecycleState.suspensionSources
                            .map(\.rawValue)
                            .sorted()
                            .joined(separator: ","),
                    ]
                )
                return
            }
            self.postSleepWindowRecoveryState.beginWake()
            self.activeWorkspaceIDByDisplay = Self.remappedActiveWorkspaceDisplayIdentifiers(
                self.activeWorkspaceIDByDisplay,
                previousHomes: self.workspaceDisplayAssignments,
                currentHomes: workspaceDisplayAssignments
            )
            self.previousWorkspaceIDByDisplay = Self.remappedActiveWorkspaceDisplayIdentifiers(
                self.previousWorkspaceIDByDisplay,
                previousHomes: self.workspaceDisplayAssignments,
                currentHomes: workspaceDisplayAssignments
            )
            self.workspaceDisplayAssignments = workspaceDisplayAssignments
            let currentTopology = Self.displayTopologySignature(Self.activeDisplays())
            if !self.wakeReconciliationState.isPending,
               Date().timeIntervalSince(self.lastWakeCompletionDate) < 1.5,
               self.lastWakeCompletedTopologySignature == currentTopology {
                self.diagnostics.log(
                    category: "lifecycle",
                    event: "duplicate-wake-signal-ignored",
                    fields: [
                        "source": source.rawValue,
                        "topology": currentTopology,
                    ]
                )
                return
            }
            let request = self.wakeReconciliationState.request(source)
            let correlationID = "wake-\(request.generation)"
            if !request.shouldSchedule {
                self.wakeReceivedAdditionalSignal = true
                self.diagnostics.log(
                    category: "lifecycle",
                    event: "wake-signal-coalesced",
                    correlation: correlationID,
                    fields: [
                        "source": source.rawValue,
                        "sources": request.sources.map(\.rawValue).sorted().joined(separator: ","),
                    ]
                )
                return
            }

            self.wakeAttemptIndex = 0
            self.wakePreviousTopologySignature = Self.displayTopologySignature(
                self.lastDisplays.isEmpty ? Self.activeDisplays() : self.lastDisplays
            )
            self.wakeReceivedAdditionalSignal = false
            self.directionalMoveGestureContext = nil
            self.manualTiledDragSession = nil
            self.invalidateFocusWorkForLifecycle()
            self.lastBackgroundLayoutSignature = nil
            self.diagnostics.log(
                category: "lifecycle",
                event: "wake-reconciliation-requested",
                correlation: correlationID,
                fields: [
                    "source": source.rawValue,
                    "sources": request.sources.map(\.rawValue).sorted().joined(separator: ","),
                    "baseline-topology": self.wakePreviousTopologySignature ?? "none",
                ]
            )
            self.scheduleWakeReconciliationAttempt(
                generation: request.generation,
                afterMilliseconds: 80
            )
        }
    }

    func stopAndRestoreAllWindows() {
        queue.sync {
            cancelManualTiledPreviewTransactions(reason: "application-stop")
            timer?.cancel()
            timer = nil
            wakeReconciliationWorkItem?.cancel()
            wakeReconciliationWorkItem = nil
            directionalMoveGestureContext = nil
            manualTiledDragSession = nil
            dropDownAnimationGeneration &+= 1
            cancelPendingDropDownAppLaunch()
            restoreAndClearDropDownAppSession(
                reason: "application-stop",
                allowWhilePaused: true
            )
            attemptIgnoredQuickAppVisibilityRecoveryForShutdown()
            // Preserve workspace membership and original frames before the safety escape hatch
            // places every managed window on the main display.
            persistState(preservingPendingRestores: true, waitForCompletion: true)
            restoreManagedWindowsForQuit()
        }
    }

    func updateQuickAppConfigurations(
        _ configurations: [DropDownAppConfiguration],
        presentation: QuickAppShelfPresentation
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            guard !self.isWindowManagementPaused else {
                self.pendingPausedQuickAppConfigurationUpdate = PendingQuickAppConfigurationUpdate(
                    configurations: configurations,
                    presentation: presentation
                )
                return
            }
            self.applyQuickAppConfigurations(configurations, presentation: presentation)
        }
    }

    private func applyQuickAppConfigurations(
        _ configurations: [DropDownAppConfiguration],
        presentation: QuickAppShelfPresentation,
        reconcileImmediately: Bool = true
    ) {
        let normalizedShelf = QuickAppShelfPolicy.normalized(configurations)
        guard normalizedShelf != quickAppConfigurations
            || presentation != quickAppShelfPresentation else { return }
        let previousSelected = dropDownAppConfiguration
        let nextSelected = previousSelected.flatMap { previous in
                normalizedShelf.first(where: {
                    $0.bundleIdentifier.caseInsensitiveCompare(previous.bundleIdentifier) == .orderedSame
                })
            } ?? normalizedShelf.first
        let nextBundleKeys = Set(normalizedShelf.map {
            Self.normalizedBundleIdentifier($0.bundleIdentifier)
        })
        if let pendingLaunch = pendingDropDownAppLaunch {
            if QuickAppTransitionPolicy.shouldCancelPendingLaunch(
                bundleIdentifier: pendingLaunch.bundleIdentifier,
                previousConfigurations: quickAppConfigurations,
                nextConfigurations: normalizedShelf
            ) {
                cancelPendingDropDownAppLaunch()
            }
        }
        if let pendingSelection = pendingQuickAppSelection,
           !nextBundleKeys.contains(Self.normalizedBundleIdentifier(
               pendingSelection.bundleIdentifier
           )) {
            self.pendingQuickAppSelection = nil
        }
        let removedBundleKeys = Set(quickAppConfigurations.map {
            Self.normalizedBundleIdentifier($0.bundleIdentifier)
        }).subtracting(nextBundleKeys)
        for bundleKey in removedBundleKeys {
            restoreAndClearQuickAppSession(bundleKey: bundleKey, reason: "configuration-changed")
        }
        quickAppConfigurations = normalizedShelf
        quickAppShelfPresentation = presentation
        dropDownAppConfiguration = nextSelected
        for configuration in normalizedShelf {
            let bundleKey = Self.normalizedBundleIdentifier(configuration.bundleIdentifier)
            guard var session = quickAppSessions[bundleKey] else { continue }
            session.direction = configuration.direction
            session.isAnimationEnabled = configuration.isAnimationEnabled
            quickAppSessions[bundleKey] = session
        }
        if reconcileImmediately {
            if dropDownAppSession?.isPresented == true {
                reconcilePresentedQuickAppGroup(
                    correlationID: diagnostics.makeCorrelationID(),
                    focusSelected: false
                )
            } else if previousSelected?.bundleIdentifier.caseInsensitiveCompare(
                nextSelected?.bundleIdentifier ?? ""
            ) != .orderedSame {
                applyVisibility()
            }
        }
        if previousSelected?.bundleIdentifier.caseInsensitiveCompare(
            nextSelected?.bundleIdentifier ?? ""
        ) != .orderedSame, let nextSelected {
            onQuickAppSelectionChanged?(nextSelected.bundleIdentifier)
        }
        persistState(preservingPendingRestores: true)
        emitState()
    }

    func selectQuickApp(bundleIdentifier: String, correlationID: String? = nil) {
        let correlationID = correlationID ?? diagnostics.makeCorrelationID()
        queue.async { [weak self] in
            guard let self,
                  let selected = self.quickAppConfigurations.first(where: {
                      $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
                  })
            else { return }
            guard selected != self.dropDownAppConfiguration else {
                switch QuickAppTransitionPolicy.directShowDisposition(
                    phase: self.quickAppTransition,
                    isPresented: self.dropDownAppSession?.isPresented == true
                ) {
                case .begin:
                    break
                case .queueLatest:
                    self.pendingQuickAppSelection = PendingQuickAppSelection(
                        bundleIdentifier: selected.bundleIdentifier,
                        correlationID: correlationID
                    )
                    return
                case .ignore, .cancelLaunchAndBegin:
                    return
                }
                self.toggleDropDownAppInternal(
                    correlationID: correlationID,
                    allowsLaunchAttempt: true,
                    refreshBeforeResolving: true
                )
                return
            }
            self.switchQuickApp(to: selected, correlationID: correlationID)
        }
    }

    func cycleQuickApp(offset: Int, correlationID: String? = nil) {
        let correlationID = correlationID ?? diagnostics.makeCorrelationID()
        queue.async { [weak self] in
            self?.cycleQuickAppInternal(offset: offset, correlationID: correlationID)
        }
    }

    private func cycleQuickAppInternal(offset: Int, correlationID: String) {
        if focusNextWindowInSelectedQuickAppGroup(
            offset: offset,
            correlationID: correlationID
        ) {
            return
        }
        guard !quickAppConfigurations.isEmpty,
              let index = QuickAppShelfSelectionPolicy.index(
                  currentBundleIdentifier: QuickAppTransitionPolicy.cycleOriginBundleIdentifier(
                      selectedBundleIdentifier: dropDownAppConfiguration?.bundleIdentifier,
                      pendingBundleIdentifier: pendingQuickAppSelection?.bundleIdentifier
                  ),
                  offset: offset,
                  in: quickAppConfigurations
              )
        else { return }
        let target = quickAppConfigurations[index]
        if target == dropDownAppConfiguration,
           pendingQuickAppSelection == nil,
           dropDownAppSession?.isPresented == true {
            return
        }
        let targetKey = Self.normalizedBundleIdentifier(target.bundleIdentifier)
        if quickAppSessions[targetKey]?.isPresented == true,
           quickAppTransition == .idle {
            dropDownAppConfiguration = target
            onQuickAppSelectionChanged?(target.bundleIdentifier)
            reconcilePresentedQuickAppGroup(correlationID: correlationID, focusSelected: true)
            return
        }
        switchQuickApp(to: target, correlationID: correlationID)
    }

    private func focusNextWindowInSelectedQuickAppGroup(
        offset: Int,
        correlationID: String
    ) -> Bool {
        guard offset != 0,
              let configuration = dropDownAppConfiguration
        else { return false }
        let bundleKey = Self.normalizedBundleIdentifier(configuration.bundleIdentifier)
        guard var session = quickAppSessions[bundleKey],
              session.isPresented,
              session.windowKeys.count > 1,
              let targetKey = QuickAppApplicationWindowPolicy.cycleTarget(
                  in: session.windowKeys,
                  selectedWindowKey: session.windowKey,
                  offset: offset,
                  wrapsWithinGroup: quickAppConfigurations.count == 1
              )
        else { return false }
        guard let target = windows[targetKey] else { return false }
        let sourceKey = session.windowKey
        session.selectWindow(targetKey)
        quickAppSessions[bundleKey] = session
        _ = AXUIElementPerformAction(target.element, kAXRaiseAction as CFString)
        if QuickAppInteractionPolicy.focusesQuickAppAfterShow(
            commandPalettePresented: commandPalettePresented
        ) {
            focusManagedWindow(targetKey, tracked: target, correlationID: correlationID)
        }
        diagnostics.log(
            category: "focus-cycle",
            event: "routed-within-quick-app-window-group",
            correlation: correlationID,
            fields: [
                "bundle": configuration.bundleIdentifier,
                "source-window": Self.diagnosticWindowKey(sourceKey),
                "target-window": Self.diagnosticWindowKey(targetKey),
                "offset": String(offset),
            ]
        )
        persistState(preservingPendingRestores: true)
        return true
    }

    func commandPalettePresentationChanged(_ isPresented: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            self.commandPalettePresented = isPresented
            self.diagnostics.log(
                category: "command-palette",
                event: isPresented
                    ? "shelf-focus-preservation-began"
                    : "shelf-focus-preservation-ended"
            )
        }
    }

    func restoreFocusAfterCommandPalette(fallbackProcessIdentifier: pid_t?) {
        let correlationID = diagnostics.makeCorrelationID()
        queue.async { [weak self] in
            guard let self else { return }
            if let session = self.dropDownAppSession,
               session.isPresented,
               let target = self.windows[session.windowKey],
               QuickAppInteractionPolicy.restoresPresentedShelfFocus(
                   shelfProcessIdentifier: session.windowKey.processIdentifier,
                   precedingProcessIdentifier: fallbackProcessIdentifier
               ) {
                self.diagnostics.log(
                    category: "command-palette",
                    event: "presented-shelf-focus-restored",
                    correlation: correlationID,
                    fields: ["window": Self.diagnosticWindowKey(session.windowKey)]
                )
                self.focusManagedWindow(
                    session.windowKey,
                    tracked: target,
                    correlationID: correlationID
                )
                return
            }
            if let session = self.dropDownAppSession,
               session.isPresented {
                self.diagnostics.log(
                    category: "command-palette",
                    event: "presented-shelf-focus-restore-skipped",
                    correlation: correlationID,
                    fields: [
                        "reason": "preceding-application-different",
                        "window": Self.diagnosticWindowKey(session.windowKey),
                    ]
                )
            }
            guard let fallbackProcessIdentifier else { return }
            DispatchQueue.main.async {
                NSRunningApplication(processIdentifier: fallbackProcessIdentifier)?.activate(options: [])
            }
        }
    }

    private func switchQuickApp(
        to configuration: DropDownAppConfiguration,
        correlationID: String
    ) {
        let targetBundleKey = Self.normalizedBundleIdentifier(configuration.bundleIdentifier)
        if quickAppTransition == .idle,
           quickAppSessions[targetBundleKey]?.isPresented == true {
            pendingQuickAppSelection = nil
            dropDownAppConfiguration = configuration
            onQuickAppSelectionChanged?(configuration.bundleIdentifier)
            reconcilePresentedQuickAppGroup(
                correlationID: correlationID,
                focusSelected: true
            )
            return
        }
        switch QuickAppTransitionPolicy.switchDisposition(
            phase: quickAppTransition,
            targetBundleKey: targetBundleKey
        ) {
        case .begin:
            break
        case .cancelLaunchAndBegin:
            cancelPendingDropDownAppLaunch()
        case .queueLatest:
            pendingQuickAppSelection = PendingQuickAppSelection(
                bundleIdentifier: configuration.bundleIdentifier,
                correlationID: correlationID
            )
            return
        case .ignore:
            return
        }
        if isQuickAppShelfPresented,
           let outgoingSession = dropDownAppSession,
           outgoingSession.isPresented {
            let outgoingBundleKey = Self.normalizedBundleIdentifier(
                outgoingSession.bundleIdentifier
            )
            quickAppApplicationSwitchHandoff = QuickAppApplicationSwitchHandoff(
                outgoingBundleKey: outgoingBundleKey,
                incomingBundleKey: targetBundleKey,
                correlationID: correlationID
            )
            pendingQuickAppPresentationContext = PendingQuickAppPresentationContext(
                previousFocusKey: outgoingSession.previousFocusKey
            )
            dropDownAppConfiguration = configuration
            onQuickAppSelectionChanged?(configuration.bundleIdentifier)
            diagnostics.log(
                category: "drop-down-app",
                event: "application-switch-started",
                correlation: correlationID,
                fields: [
                    "outgoing-bundle": outgoingSession.bundleIdentifier,
                    "incoming-bundle": configuration.bundleIdentifier,
                    "ordering": "show-focus-hide",
                ]
            )
            toggleDropDownAppInternal(
                correlationID: correlationID,
                allowsLaunchAttempt: true,
                refreshBeforeResolving: true
            )
            return
        }
        dropDownAppConfiguration = configuration
        onQuickAppSelectionChanged?(configuration.bundleIdentifier)
        toggleDropDownAppInternal(
            correlationID: correlationID,
            allowsLaunchAttempt: true,
            refreshBeforeResolving: true
        )
    }

    func toggleDropDownApp(
        source _: WindowManagerCommandSource,
        correlationID: String? = nil
    ) {
        let correlationID = correlationID ?? diagnostics.makeCorrelationID()
        queue.async { [weak self] in
            guard let self else { return }
            guard self.quickAppTransition == .idle else {
                self.emitCommandFeedback(
                    "The Quick App is still changing.",
                    correlationID: correlationID
                )
                return
            }
            if let pending = self.pendingDropDownAppLaunch,
               pending.bundleIdentifier.caseInsensitiveCompare(
                   self.dropDownAppConfiguration?.bundleIdentifier ?? ""
               ) == .orderedSame {
                self.emitCommandFeedback(
                    "Launching \(pending.displayName).",
                    correlationID: correlationID
                )
                return
            }
            self.toggleDropDownAppInternal(
                correlationID: correlationID,
                allowsLaunchAttempt: true,
                refreshBeforeResolving: true
            )
        }
    }

    private func toggleDropDownAppInternal(
        correlationID: String,
        allowsLaunchAttempt: Bool,
        refreshBeforeResolving: Bool
    ) {
        cancelManualTiledPreviewTransactions(reason: "quick-app-shelf-command")
        guard let configuration = dropDownAppConfiguration else {
            emitCommandFeedback(
                "Choose a Quick App in Applications first.",
                correlationID: correlationID
            )
            return
        }
        if refreshBeforeResolving {
            refreshWindows(correlationID: correlationID)
        }
        if isQuickAppShelfPresented,
           quickAppApplicationSwitchHandoff == nil {
            hideDropDownApp(
                restorePreviousFocus: true,
                reason: "shortcut-toggle",
                correlationID: correlationID
            )
            return
        }

        let matching = availableDropDownAppWindows(for: configuration)
        let target: TrackedWindow
        if var session = dropDownAppSession,
           let existing = windows[session.windowKey],
           session.isApplicationHiddenByWindowRanger ||
            matching.contains(where: { $0.key == existing.key }) {
            if let owned = orderedQuickAppWindows(
                matching,
                existingOrder: session.windowKeys,
                requiredProcessIdentifier: existing.processIdentifier
            ) {
                session.synchronizeWindowKeys(owned.map(\.key))
                dropDownAppSession = session
            }
            target = windows[session.windowKey] ?? existing
        } else {
            if matching.isEmpty {
                if allowsLaunchAttempt {
                    launchQuickAppIfNeededForToggle(
                        configuration: configuration,
                        correlationID: correlationID
                    )
                } else {
                    emitCommandFeedback(
                        "Could not find a usable \(configuration.displayName) window yet.",
                        correlationID: correlationID
                    )
                }
                return
            }
            guard let owned = orderedQuickAppWindows(matching),
                  let primary = owned.first
            else {
                emitCommandFeedback(
                    "\(configuration.displayName) is running in more than one process, so its Shelf windows cannot be governed safely.",
                    correlationID: correlationID
                )
                return
            }
            target = primary
            dropDownAppSession = DropDownAppSession(
                windowKey: primary.key,
                additionalWindowKeys: Array(owned.dropFirst()).map(\.key),
                bundleIdentifier: configuration.bundleIdentifier,
                direction: configuration.direction,
                isAnimationEnabled: configuration.isAnimationEnabled,
                isPresented: false,
                isApplicationHiddenByWindowRanger: false,
                displayIdentifier: nil,
                previousFocusKey: nil
            )
        }
        showDropDownApp(
            target,
            configuration: configuration,
            correlationID: correlationID
        )
    }

    private func availableDropDownAppWindows(
        for configuration: DropDownAppConfiguration
    ) -> [TrackedWindow] {
        windows.values.filter {
            $0.bundleIdentifier?.caseInsensitiveCompare(configuration.bundleIdentifier) == .orderedSame &&
                !temporarilyDeferredWindowKeys.contains($0.key) &&
                fullscreenSessions[$0.key] == nil
        }
    }

    private func orderedQuickAppWindows(
        _ candidates: [TrackedWindow],
        existingOrder: [WindowKey] = [],
        requiredProcessIdentifier: pid_t? = nil
    ) -> [TrackedWindow]? {
        guard let orderedKeys = QuickAppApplicationWindowPolicy.orderedWindowKeys(
            candidates: candidates.map(\.key),
            existingOrder: existingOrder,
            requiredProcessIdentifier: requiredProcessIdentifier
        ) else { return nil }
        let byKey = Dictionary(uniqueKeysWithValues: candidates.map { ($0.key, $0) })
        return orderedKeys.compactMap { byKey[$0] }
    }

    /// Keep application-group ownership aligned with authoritative window discovery. New standard
    /// windows from the owned process join without disturbing their saved workspace state; closing
    /// one window removes only that exact member while another owned window remains.
    @discardableResult
    private func reconcileQuickAppSessionWindowSets(correlationID: String?) -> Bool {
        var presentedMembershipChanged = false
        for configuration in quickAppConfigurations {
            let bundleKey = Self.normalizedBundleIdentifier(configuration.bundleIdentifier)
            guard var session = quickAppSessions[bundleKey],
                  let primary = windows[session.windowKey]
            else { continue }
            let matching = availableDropDownAppWindows(for: configuration)
            guard let owned = orderedQuickAppWindows(
                matching,
                existingOrder: session.windowKeys,
                requiredProcessIdentifier: primary.processIdentifier
            ) else { continue }
            let previousKeys = session.windowKeys
            let nextKeys = owned.map(\.key)
            guard previousKeys != nextKeys else { continue }
            session.synchronizeWindowKeys(nextKeys)
            quickAppSessions[bundleKey] = session
            presentedMembershipChanged = presentedMembershipChanged || session.isPresented
            diagnostics.log(
                category: "drop-down-app",
                event: "application-window-group-updated",
                correlation: correlationID,
                fields: [
                    "bundle": configuration.bundleIdentifier,
                    "previous-window-count": String(previousKeys.count),
                    "window-count": String(nextKeys.count),
                    "added-window-count": String(Set(nextKeys).subtracting(previousKeys).count),
                    "removed-window-count": String(Set(previousKeys).subtracting(nextKeys).count),
                    "presented": String(session.isPresented),
                ]
            )
        }
        return presentedMembershipChanged
    }

    private func quickAppGroupTargets(
        for configuration: DropDownAppConfiguration
    ) -> [TrackedWindow]? {
        let bundleKey = Self.normalizedBundleIdentifier(configuration.bundleIdentifier)
        if var session = quickAppSessions[bundleKey],
           let exact = windows[session.windowKey],
           session.isPresented || session.isApplicationHiddenByWindowRanger {
            let retained = session.windowKeys.compactMap { windows[$0] }
            let available = availableDropDownAppWindows(for: configuration)
            if let owned = orderedQuickAppWindows(
                available,
                existingOrder: retained.map(\.key),
                requiredProcessIdentifier: exact.processIdentifier
            ) {
                session.synchronizeWindowKeys(owned.map(\.key))
                quickAppSessions[bundleKey] = session
                return owned
            }
            return retained.isEmpty ? nil : retained
        }
        let matching = availableDropDownAppWindows(for: configuration)
        guard let targets = orderedQuickAppWindows(matching),
              let target = targets.first,
              isDropDownApplicationHidden(
                processIdentifier: target.processIdentifier,
                bundleIdentifier: configuration.bundleIdentifier
              ) != true
        else { return nil }
        return targets
    }

    private func reconcilePresentedQuickAppGroup(
        correlationID: String?,
        focusSelected: Bool
    ) {
        guard !isWindowManagementPaused,
              let selected = dropDownAppConfiguration,
              dropDownAppSession?.isPresented == true
        else { return }
        let displays = Self.activeDisplays()
        guard let selectedSession = dropDownAppSession,
              let display = selectedSession.displayIdentifier.flatMap({ identifier in
                  displays.first { $0.identifier == identifier }
              }) ?? dropDownTargetDisplay(displays: displays)
        else { return }

        let targets = Dictionary(uniqueKeysWithValues: quickAppConfigurations.compactMap {
            configuration -> (String, [TrackedWindow])? in
            guard let targets = quickAppGroupTargets(for: configuration) else { return nil }
            return (Self.normalizedBundleIdentifier(configuration.bundleIdentifier), targets)
        })
        let desired = QuickAppShelfGroupPolicy.visibleConfigurations(
            selectedBundleIdentifier: selected.bundleIdentifier,
            configurations: quickAppConfigurations,
            availableBundleIdentifiers: Set(targets.keys),
            maximumCount: quickAppShelfPresentation.visibleCount
        )
        let desiredKeys = Set(desired.map {
            Self.normalizedBundleIdentifier($0.bundleIdentifier)
        })

        for (bundleKey, session) in Array(quickAppSessions)
        where session.isPresented
            && bundleKey != Self.normalizedBundleIdentifier(selected.bundleIdentifier)
            && !desiredKeys.contains(bundleKey) {
            beginHidingQuickAppNeighbor(
                bundleKey: bundleKey,
                session: session,
                reason: "group-membership-changed",
                correlationID: correlationID
            )
        }

        for configuration in desired {
            let bundleKey = Self.normalizedBundleIdentifier(configuration.bundleIdentifier)
            guard bundleKey != Self.normalizedBundleIdentifier(selected.bundleIdentifier),
                  let appTargets = targets[bundleKey],
                  quickAppSessions[bundleKey]?.isPresented != true
            else { continue }
            beginPresentingQuickAppNeighbor(
                configuration: configuration,
                targets: appTargets,
                display: display,
                correlationID: correlationID
            )
        }

        layoutPresentedQuickAppGroup(
            display: display,
            correlationID: correlationID,
            focusSelected: focusSelected
        )
    }

    private func restackPresentedQuickAppGroup(correlationID: String?) {
        guard let selectedSession = dropDownAppSession,
              selectedSession.isPresented
        else { return }
        let displays = Self.activeDisplays()
        guard let display = selectedSession.displayIdentifier.flatMap({ identifier in
            displays.first { $0.identifier == identifier }
        }) ?? dropDownTargetDisplay(displays: displays)
        else { return }
        layoutPresentedQuickAppGroup(
            display: display,
            correlationID: correlationID,
            focusSelected: false
        )
    }

    private func layoutPresentedQuickAppGroup(
        display: DisplaySnapshot,
        correlationID: String?,
        focusSelected: Bool
    ) {
        guard !isWindowManagementPaused,
              let selected = dropDownAppConfiguration,
              let selectedSession = dropDownAppSession,
              selectedSession.isPresented
        else { return }
        let presentedKeys = Set(quickAppSessions.compactMap { key, session in
            session.isPresented ? key : nil
        })
        let visible = QuickAppShelfGroupPolicy.visibleConfigurations(
            selectedBundleIdentifier: selected.bundleIdentifier,
            configurations: quickAppConfigurations,
            availableBundleIdentifiers: presentedKeys,
            maximumCount: quickAppShelfPresentation.visibleCount
        )
        let container = DropDownAppGeometry.presentedFrame(
            in: dropDownAppPresentationBounds(for: display),
            sizeFraction: quickAppShelfPresentation.heightFraction,
            direction: quickAppShelfPresentation.direction
        )
        let visibleTargets = visible.reduce(
            into: [(bundleKey: String, target: TrackedWindow)]()
        ) { result, configuration in
            let bundleKey = Self.normalizedBundleIdentifier(configuration.bundleIdentifier)
            guard let session = quickAppSessions[bundleKey] else { return }
            for key in session.windowKeys {
                if let target = windows[key] {
                    result.append((bundleKey: bundleKey, target: target))
                }
            }
        }
        let frames = DropDownAppGeometry.groupFrames(
            in: container,
            count: visibleTargets.count,
            style: quickAppShelfPresentation.layoutStyle,
            direction: quickAppShelfPresentation.direction
        )
        for (visibleTarget, frame) in zip(visibleTargets, frames) {
            guard var session = quickAppSessions[visibleTarget.bundleKey] else { continue }
            session.displayIdentifier = display.identifier
            session.direction = quickAppShelfPresentation.direction
            session.isAnimationEnabled = quickAppShelfPresentation.isAnimationEnabled
            quickAppSessions[visibleTarget.bundleKey] = session
            _ = setDropDownAppFrame(frame, target: visibleTarget.target)
        }
        let raiseTargets = visibleTargets.filter { visibleTarget in
            guard let session = quickAppSessions[visibleTarget.bundleKey] else { return false }
            return isDropDownApplicationHidden(
                processIdentifier: visibleTarget.target.processIdentifier,
                bundleIdentifier: session.bundleIdentifier
            ) == false
        }
        let raiseOrder = QuickAppShelfGroupPolicy.raiseOrder(
            visibleWindowKeys: raiseTargets.map { $0.target.key },
            selectedWindowKey: selectedSession.windowKey
        )
        for key in raiseOrder {
            guard let target = windows[key] else { continue }
            _ = AXUIElementPerformAction(target.element, kAXRaiseAction as CFString)
        }
        if let selectedTarget = windows[selectedSession.windowKey] {
            if focusSelected,
               QuickAppInteractionPolicy.focusesQuickAppAfterShow(
                commandPalettePresented: commandPalettePresented
               ) {
                focusManagedWindow(
                    selectedSession.windowKey,
                    tracked: selectedTarget,
                    correlationID: correlationID
                )
            }
        }
        diagnostics.log(
            category: "drop-down-app",
            event: "group-laid-out",
            correlation: correlationID,
            fields: [
                "style": quickAppShelfPresentation.layoutStyle.rawValue,
                "configured-visible-count": String(quickAppShelfPresentation.visibleCount),
                "presented-app-count": String(visible.count),
                "presented-count": String(visibleTargets.count),
                "raised-count": String(raiseOrder.count),
                "selected-bundle": selected.bundleIdentifier,
                "display": display.identifier,
            ]
        )
    }

    private func nextQuickAppNeighborVisibilityGeneration(bundleKey: String) -> UInt64 {
        let next = (quickAppNeighborVisibilityGeneration[bundleKey] ?? 0) &+ 1
        quickAppNeighborVisibilityGeneration[bundleKey] = next
        return next
    }

    private func beginPresentingQuickAppNeighbor(
        configuration: DropDownAppConfiguration,
        targets: [TrackedWindow],
        display: DisplaySnapshot,
        correlationID: String?
    ) {
        guard !isWindowManagementPaused else { return }
        guard let target = targets.first else { return }
        let bundleKey = Self.normalizedBundleIdentifier(configuration.bundleIdentifier)
        let generation = nextQuickAppNeighborVisibilityGeneration(bundleKey: bundleKey)
        let previous = quickAppSessions[bundleKey]
        var pendingSession = DropDownAppSession(
            windowKey: target.key,
            additionalWindowKeys: Array(targets.dropFirst()).map(\.key),
            bundleIdentifier: configuration.bundleIdentifier,
            direction: quickAppShelfPresentation.direction,
            isAnimationEnabled: quickAppShelfPresentation.isAnimationEnabled,
            isPresented: false,
            isApplicationHiddenByWindowRanger: previous?.isApplicationHiddenByWindowRanger == true,
            displayIdentifier: display.identifier,
            previousFocusKey: nil
        )
        quickAppSessions[bundleKey] = pendingSession
        let applicationIsHidden = isDropDownApplicationHidden(
            processIdentifier: target.processIdentifier,
            bundleIdentifier: configuration.bundleIdentifier
        ) == true
        if applicationIsHidden {
            // Stage all of the neighbour's exact windows while its application is still hidden.
            // The temporary presented marker includes them in the shared Shelf geometry only for
            // this write; confirmation still owns the actual presented state transition.
            pendingSession.isPresented = true
            quickAppSessions[bundleKey] = pendingSession
            layoutPresentedQuickAppGroup(
                display: display,
                correlationID: correlationID,
                focusSelected: false
            )
            pendingSession.isPresented = false
            quickAppSessions[bundleKey] = pendingSession
        }
        guard !applicationIsHidden || requestDropDownApplicationHidden(
            false,
            processIdentifier: target.processIdentifier,
            bundleIdentifier: configuration.bundleIdentifier
        ) else {
            diagnostics.log(
                category: "drop-down-app",
                event: "group-neighbor-show-failed",
                correlation: correlationID,
                fields: ["bundle": configuration.bundleIdentifier, "reason": "unhide-rejected"]
            )
            return
        }
        awaitQuickAppNeighborPresented(
            bundleKey: bundleKey,
            target: target,
            display: display,
            generation: generation,
            correlationID: correlationID,
            attempt: 0
        )
    }

    private func awaitQuickAppNeighborPresented(
        bundleKey: String,
        target: TrackedWindow,
        display: DisplaySnapshot,
        generation: UInt64,
        correlationID: String?,
        attempt: Int
    ) {
        guard !isWindowManagementPaused,
              quickAppNeighborVisibilityGeneration[bundleKey] == generation,
              var session = quickAppSessions[bundleKey],
              session.windowKey == target.key,
              windows[target.key] != nil
        else { return }
        let observed = isDropDownApplicationHidden(
            processIdentifier: target.processIdentifier,
            bundleIdentifier: session.bundleIdentifier
        )
        switch DropDownAppVisibilityConfirmationPolicy.disposition(
            expectedHidden: false,
            observedHidden: observed,
            attempt: attempt
        ) {
        case .confirmed:
            session.isPresented = true
            session.isApplicationHiddenByWindowRanger = false
            session.displayIdentifier = display.identifier
            quickAppSessions[bundleKey] = session
            layoutPresentedQuickAppGroup(
                display: display,
                correlationID: correlationID,
                focusSelected: false
            )
            persistState(preservingPendingRestores: true)
        case .timedOut:
            if session.isApplicationHiddenByWindowRanger {
                _ = requestDropDownApplicationHidden(
                    true,
                    processIdentifier: target.processIdentifier,
                    bundleIdentifier: session.bundleIdentifier
                )
            } else {
                quickAppSessions.removeValue(forKey: bundleKey)
            }
            diagnostics.log(
                category: "drop-down-app",
                event: "group-neighbor-show-failed",
                correlation: correlationID,
                fields: [
                    "bundle": session.bundleIdentifier,
                    "reason": "unhide-timeout",
                    "recovery": session.isApplicationHiddenByWindowRanger
                        ? "rehide-owned-application"
                        : "release-unowned-session",
                ]
            )
            persistState(preservingPendingRestores: true)
        case .retry:
            queue.asyncAfter(deadline: .now() + .milliseconds(75)) { [weak self] in
                self?.awaitQuickAppNeighborPresented(
                    bundleKey: bundleKey,
                    target: target,
                    display: display,
                    generation: generation,
                    correlationID: correlationID,
                    attempt: attempt + 1
                )
            }
        }
    }

    private func beginHidingQuickAppNeighbor(
        bundleKey: String,
        session: DropDownAppSession,
        reason: String,
        correlationID: String?
    ) {
        guard !isWindowManagementPaused,
              session.isPresented,
              let target = windows[session.windowKey]
        else { return }
        let generation = nextQuickAppNeighborVisibilityGeneration(bundleKey: bundleKey)
        var hiding = session
        hiding.isPresented = false
        hiding.isApplicationHiddenByWindowRanger = false
        quickAppSessions[bundleKey] = hiding
        guard requestDropDownApplicationHidden(
            true,
            processIdentifier: target.processIdentifier,
            bundleIdentifier: session.bundleIdentifier
        ) else {
            quickAppSessions[bundleKey] = session
            return
        }
        awaitQuickAppNeighborHidden(
            bundleKey: bundleKey,
            target: target,
            originalSession: session,
            reason: reason,
            generation: generation,
            correlationID: correlationID,
            attempt: 0
        )
    }

    private func awaitQuickAppNeighborHidden(
        bundleKey: String,
        target: TrackedWindow,
        originalSession: DropDownAppSession,
        reason: String,
        generation: UInt64,
        correlationID: String?,
        attempt: Int
    ) {
        guard !isWindowManagementPaused,
              quickAppNeighborVisibilityGeneration[bundleKey] == generation,
              quickAppSessions[bundleKey]?.windowKey == target.key,
              windows[target.key] != nil
        else { return }
        let observed = isDropDownApplicationHidden(
            processIdentifier: target.processIdentifier,
            bundleIdentifier: originalSession.bundleIdentifier
        )
        switch DropDownAppVisibilityConfirmationPolicy.disposition(
            expectedHidden: true,
            observedHidden: observed,
            attempt: attempt
        ) {
        case .confirmed:
            var hidden = originalSession
            hidden.isPresented = false
            hidden.isApplicationHiddenByWindowRanger = true
            quickAppSessions[bundleKey] = hidden
            diagnostics.log(
                category: "drop-down-app",
                event: "group-neighbor-hidden",
                correlation: correlationID,
                fields: ["bundle": originalSession.bundleIdentifier, "reason": reason]
            )
            if isQuickAppShelfPresented {
                reconcilePresentedQuickAppGroup(
                    correlationID: correlationID,
                    focusSelected: false
                )
            }
            persistState(preservingPendingRestores: true)
        case .timedOut:
            _ = requestDropDownApplicationHidden(
                false,
                processIdentifier: target.processIdentifier,
                bundleIdentifier: originalSession.bundleIdentifier
            )
            quickAppSessions[bundleKey] = originalSession
            if let displayID = originalSession.displayIdentifier,
               let display = Self.activeDisplays().first(where: { $0.identifier == displayID }) {
                layoutPresentedQuickAppGroup(
                    display: display,
                    correlationID: correlationID,
                    focusSelected: false
                )
            }
            diagnostics.log(
                category: "drop-down-app",
                event: "group-neighbor-hide-failed",
                correlation: correlationID,
                fields: ["bundle": originalSession.bundleIdentifier, "reason": "hide-timeout"]
            )
        case .retry:
            queue.asyncAfter(deadline: .now() + .milliseconds(75)) { [weak self] in
                self?.awaitQuickAppNeighborHidden(
                    bundleKey: bundleKey,
                    target: target,
                    originalSession: originalSession,
                    reason: reason,
                    generation: generation,
                    correlationID: correlationID,
                    attempt: attempt + 1
                )
            }
        }
    }

    private func launchQuickAppIfNeededForToggle(
        configuration: DropDownAppConfiguration,
        correlationID: String
    ) {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: configuration.bundleIdentifier
        ) else {
            emitCommandFeedback(
                "\(configuration.displayName) is not installed and cannot be launched.",
                correlationID: correlationID
            )
            diagnostics.log(
                category: "drop-down-app",
                event: "launch-missing-application",
                correlation: correlationID,
                fields: ["bundle": configuration.bundleIdentifier]
            )
            abandonQuickAppApplicationSwitchHandoff(
                reason: "launch-missing-application",
                correlationID: correlationID
            )
            continuePendingQuickAppSelectionIfPossible()
            return
        }

        dropDownLaunchGeneration &+= 1
        let generation = dropDownLaunchGeneration
        pendingDropDownAppLaunch = PendingDropDownAppLaunch(
            bundleIdentifier: configuration.bundleIdentifier,
            displayName: configuration.displayName,
            generation: generation
        )
        quickAppTransition = .launching(
            Self.normalizedBundleIdentifier(configuration.bundleIdentifier)
        )
        emitCommandFeedback(
            "Launching \(configuration.displayName).",
            correlationID: correlationID
        )
        let activatesApplication = QuickAppInteractionPolicy.activatesApplicationForLaunch(
            commandPalettePresented: commandPalettePresented,
            applicationSwitchInProgress: quickAppApplicationSwitchHandoff != nil
        )
        diagnostics.log(
            category: "drop-down-app",
            event: "launch-requested",
            correlation: correlationID,
            fields: [
                "bundle": configuration.bundleIdentifier,
                "activates-application": String(activatesApplication),
            ]
        )

        let launchConfiguration = NSWorkspace.OpenConfiguration()
        launchConfiguration.activates = activatesApplication
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: launchConfiguration
        ) { [weak self] _, error in
            self?.queue.async { [weak self] in
                guard let self else { return }
                guard self.pendingDropDownAppLaunch?.generation == generation else { return }
                if let error {
                    self.pendingDropDownAppLaunch = nil
                    self.quickAppTransition = .idle
                    let safeError = error as NSError
                    self.diagnostics.log(
                        category: "drop-down-app",
                        event: "launch-failed",
                        correlation: correlationID,
                        fields: [
                            "bundle": configuration.bundleIdentifier,
                            "error-domain": safeError.domain,
                            "error-code": String(safeError.code),
                        ]
                    )
                    self.emitCommandFeedback(
                        "Could not launch \(configuration.displayName).",
                        correlationID: correlationID
                    )
                    self.abandonQuickAppApplicationSwitchHandoff(
                        reason: "launch-failed",
                        correlationID: correlationID
                    )
                    self.continuePendingQuickAppSelectionIfPossible()
                    return
                }

                self.diagnostics.log(
                    category: "drop-down-app",
                    event: "launch-request-accepted",
                    correlation: correlationID,
                    fields: ["bundle": configuration.bundleIdentifier]
                )
                self.queue.asyncAfter(
                    deadline: .now() + DropDownAppLaunchWatchdogPolicy.initialDelay
                ) { [weak self] in
                    self?.awaitLaunchedQuickAppWindow(
                        configuration: configuration,
                        correlationID: correlationID,
                        generation: generation,
                        remainingAttempts: DropDownAppLaunchWatchdogPolicy.maximumAttempts
                    )
                }
            }
        }
    }

    private func awaitLaunchedQuickAppWindow(
        configuration: DropDownAppConfiguration,
        correlationID: String,
        generation: UInt64,
        remainingAttempts: Int
    ) {
        guard pendingDropDownAppLaunch?.generation == generation,
              dropDownAppConfiguration?.bundleIdentifier.caseInsensitiveCompare(
                  configuration.bundleIdentifier
              ) == .orderedSame
        else { return }

        refreshWindows(
            correlationID: correlationID,
            performAXWrites: false,
            observeFocus: false
        )
        let matching = availableDropDownAppWindows(for: configuration)
        switch DropDownAppLaunchWatchdogPolicy.disposition(
            availableWindowCount: matching.count,
            remainingAttempts: remainingAttempts
        ) {
        case .resolveToggle:
            pendingDropDownAppLaunch = nil
            quickAppTransition = .idle
            toggleDropDownAppInternal(
                correlationID: correlationID,
                allowsLaunchAttempt: false,
                refreshBeforeResolving: false
            )
        case let .retry(nextRemainingAttempts):
            diagnostics.log(
                category: "drop-down-app",
                event: "launch-window-watchdog-retry",
                correlation: correlationID,
                fields: [
                    "bundle": configuration.bundleIdentifier,
                    "remaining-attempts": String(nextRemainingAttempts),
                ]
            )
            queue.asyncAfter(
                deadline: .now() + DropDownAppLaunchWatchdogPolicy.retryDelay
            ) { [weak self] in
                self?.awaitLaunchedQuickAppWindow(
                    configuration: configuration,
                    correlationID: correlationID,
                    generation: generation,
                    remainingAttempts: nextRemainingAttempts
                )
            }
        case .exhausted:
            pendingDropDownAppLaunch = nil
            quickAppTransition = .idle
            emitCommandFeedback(
                "Could not find a usable \(configuration.displayName) window yet.",
                correlationID: correlationID
            )
            diagnostics.log(
                category: "drop-down-app",
                event: "launch-window-watchdog-exhausted",
                correlation: correlationID,
                fields: [
                    "bundle": configuration.bundleIdentifier,
                    "remaining-attempts": "0",
                ]
            )
            abandonQuickAppApplicationSwitchHandoff(
                reason: "launch-window-watchdog-exhausted",
                correlationID: correlationID
            )
            continuePendingQuickAppSelectionIfPossible()
        }
    }

    private func cancelPendingDropDownAppLaunch() {
        dropDownLaunchGeneration &+= 1
        pendingDropDownAppLaunch = nil
        pendingQuickAppPresentationContext = nil
        if case .launching = quickAppTransition {
            quickAppTransition = .idle
        }
    }

    private func continuePendingQuickAppSelectionIfPossible() {
        guard quickAppTransition == .idle,
              let pending = pendingQuickAppSelection
        else { return }
        pendingQuickAppSelection = nil
        guard let configuration = quickAppConfigurations.first(where: {
            $0.bundleIdentifier.caseInsensitiveCompare(pending.bundleIdentifier) == .orderedSame
        }) else { return }
        if configuration == dropDownAppConfiguration,
           dropDownAppSession?.isPresented == true {
            return
        }
        switchQuickApp(to: configuration, correlationID: pending.correlationID)
    }

    private func quickAppApplicationSwitchActivationDisposition(
        processIdentifier: pid_t
    ) -> QuickAppApplicationSwitchActivationDisposition? {
        guard let handoff = quickAppApplicationSwitchHandoff,
              let incoming = quickAppSessions[handoff.incomingBundleKey],
              let outgoing = quickAppSessions[handoff.outgoingBundleKey]
        else { return nil }
        return QuickAppApplicationSwitchPolicy.activationDisposition(
            activatedProcessIdentifier: processIdentifier,
            incomingProcessIdentifier: incoming.windowKey.processIdentifier,
            outgoingProcessIdentifier: outgoing.windowKey.processIdentifier
        )
    }

    private func completeQuickAppApplicationSwitchHandoff(
        continuePendingSelection: Bool = true
    ) {
        guard let handoff = quickAppApplicationSwitchHandoff,
              let incoming = quickAppSessions[handoff.incomingBundleKey],
              incoming.isPresented
        else { return }
        quickAppApplicationSwitchHandoff = nil
        if case let .showing(activeBundleKey) = quickAppTransition,
           activeBundleKey == handoff.incomingBundleKey {
            quickAppTransition = .idle
        }
        if let outgoing = quickAppSessions[handoff.outgoingBundleKey],
           outgoing.isPresented {
            beginHidingQuickAppNeighbor(
                bundleKey: handoff.outgoingBundleKey,
                session: outgoing,
                reason: "application-switch-activated",
                correlationID: handoff.correlationID
            )
        }
        diagnostics.log(
            category: "drop-down-app",
            event: "application-switch-completed",
            correlation: handoff.correlationID,
            fields: [
                "incoming-bundle": incoming.bundleIdentifier,
                "outgoing-hidden-after-activation": "true",
            ]
        )
        if continuePendingSelection {
            continuePendingQuickAppSelectionIfPossible()
        }
    }

    private func abandonQuickAppApplicationSwitchHandoff(
        reason: String,
        correlationID: String?
    ) {
        guard let handoff = quickAppApplicationSwitchHandoff else { return }
        quickAppApplicationSwitchHandoff = nil
        pendingQuickAppPresentationContext = nil
        pendingQuickAppHideAfterPresentation = false
        dropDownAnimationGeneration &+= 1
        if pendingDropDownAppLaunch.map({
            Self.normalizedBundleIdentifier($0.bundleIdentifier) == handoff.incomingBundleKey
        }) == true {
            dropDownLaunchGeneration &+= 1
            pendingDropDownAppLaunch = nil
        }
        if let incoming = quickAppSessions[handoff.incomingBundleKey],
           incoming.isApplicationHiddenByWindowRanger {
            _ = requestDropDownApplicationHidden(
                true,
                processIdentifier: incoming.windowKey.processIdentifier,
                bundleIdentifier: incoming.bundleIdentifier
            )
        }
        if let outgoing = quickAppConfigurations.first(where: {
            Self.normalizedBundleIdentifier($0.bundleIdentifier) == handoff.outgoingBundleKey
        }) {
            dropDownAppConfiguration = outgoing
            onQuickAppSelectionChanged?(outgoing.bundleIdentifier)
        }
        quickAppTransition = .idle
        diagnostics.log(
            category: "drop-down-app",
            event: "application-switch-abandoned",
            correlation: correlationID ?? handoff.correlationID,
            fields: ["reason": reason]
        )
    }

    func updateWorkspaces(_ definitions: [WorkspaceDefinition]) {
        guard !definitions.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            self.cancelManualTiledPreviewTransactions(reason: "workspace-configuration-changed")
            let validIDs = Set(definitions.map(\.id))
            let fallbackID = definitions[0].id
            let newLayouts = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0.layout) })
            let crossingManagedLayoutBoundary: Set<UUID> = Set(self.workspaces.compactMap { workspace -> UUID? in
                guard let newLayout = newLayouts[workspace.id],
                      (workspace.layout == .none) != (newLayout == .none)
                else { return nil }
                return workspace.id
            })
            self.captureCurrentFrames(for: crossingManagedLayoutBoundary, displays: Self.activeDisplays())
            self.directionalMoveGestureContext = nil
            self.workspaces = definitions

            if !validIDs.contains(self.currentWorkspaceID) {
                self.currentWorkspaceID = fallbackID
            }
            if let previous = self.previousWorkspaceID, !validIDs.contains(previous) {
                self.previousWorkspaceID = nil
            }
            for key in self.windows.keys where !validIDs.contains(self.windows[key]!.workspaceID) {
                self.windows[key]?.workspaceID = fallbackID
            }
            self.activeWorkspaceIDByDisplay = self.activeWorkspaceIDByDisplay.filter { validIDs.contains($0.value) }
            self.previousWorkspaceIDByDisplay = self.previousWorkspaceIDByDisplay.filter { validIDs.contains($0.value) }
            self.workspaceDisplayAssignments = self.workspaceDisplayAssignments.filter { validIDs.contains($0.key) }
            self.reconcileIndependentActiveWorkspaces(displays: Self.activeDisplays())
            self.applyVisibility()
            self.persistState(preservingPendingRestores: true)
            self.emitState()
        }
    }

    /// Applies a complete reusable profile in one serialized transition. Every currently managed
    /// window is first recovered to a meaningful visible frame, then re-routed into the destination
    /// profile without carrying workspace membership across profile identities. Deferred,
    /// minimized, full-screen, and ignored windows are never force-moved by this path.
    func transitionToProfile(_ request: ProfileActivationRequest) {
        let configuration = request.configuration
        guard !configuration.workspaces.isEmpty else { return }
        profileTransitionGenerationGate.register(request.generation)
        let correlationID = "profile-\(configuration.profileID.uuidString.prefix(8))-\(UUID().uuidString.prefix(6))"
        queue.async { [weak self] in
            guard let self else { return }
            guard self.isProfileTransitionGenerationCurrent(request.generation) else {
                self.logSupersededProfileTransition(request, correlationID: correlationID)
                return
            }
            let switchingProfile = self.currentProfileID != configuration.profileID
            self.cancelManualTiledPreviewTransactions(reason: "profile-transition")
            self.cancelPendingDropDownAppLaunch()
            self.pendingQuickAppSelection = nil
            self.pendingPausedQuickAppConfigurationUpdate = nil
            self.quickAppTopologyChangedWhilePaused = false
            self.restoreAndClearDropDownAppSession(
                reason: "profile-transition",
                allowWhilePaused: true
            )
            self.quickAppConfigurations = QuickAppShelfPolicy.normalized(configuration.quickApps)
            self.quickAppShelfPresentation = configuration.quickAppShelfPresentation
            self.dropDownAppConfiguration = self.quickAppConfigurations.first(where: {
                $0.bundleIdentifier.caseInsensitiveCompare(
                    configuration.selectedQuickAppBundleIdentifier ?? ""
                ) == .orderedSame
            }) ?? self.quickAppConfigurations.first
            self.directionalMoveGestureContext = nil
            self.invalidateFocusWorkForLifecycle()
            self.pendingFocusVerification?.cancel()
            self.pendingFocusVerification = nil
            self.refreshWindows(correlationID: correlationID)
            guard self.isProfileTransitionGenerationCurrent(request.generation) else {
                self.logSupersededProfileTransition(request, correlationID: correlationID)
                return
            }
            let focusedBefore = self.focusedWindowKey()
            let displays = Self.activeDisplays()
            let displayBounds = displays.map(\.bounds)
            var frameChanges: [FrameChange] = []
            var deferredCount = 0
            let transitionKeys = self.windows.keys.sorted {
                if $0.processIdentifier != $1.processIdentifier {
                    return $0.processIdentifier < $1.processIdentifier
                }
                return $0.windowIdentifier < $1.windowIdentifier
            }

            for key in transitionKeys {
                guard var tracked = self.windows[key] else { continue }
                let metadata = self.admissionMetadataByWindow[key]
                guard Self.profileTransitionShouldRecoverWindow(
                    disposition: self.admissionDecisionByWindow[key]?.disposition,
                    isTemporarilyDeferred: self.temporarilyDeferredWindowKeys.contains(key),
                    isMinimized: metadata?.isMinimized == true,
                    isFullscreen: metadata?.isFullscreen == true
                )
                else {
                    deferredCount += 1
                    continue
                }
                let currentFrame = AccessibilityWindow.frame(of: tracked.element)
                guard let safeFrame = Self.profileTransitionVisibleFrame(
                    currentFrame: currentFrame,
                    savedFrame: tracked.restoreFrame,
                    displayBounds: displayBounds
                ) else {
                    deferredCount += 1
                    continue
                }
                tracked.restoreFrame = safeFrame
                tracked.displayPlacement = Self.displayPlacement(for: safeFrame, displays: displays)
                self.windows[key] = tracked
                frameChanges.append(FrameChange(window: tracked, frame: safeFrame))
            }

            // Restore before changing membership so no window can remain parked solely because its
            // old profile disappeared. The frame writer skips windows already at the safe target.
            guard self.isProfileTransitionGenerationCurrent(request.generation) else {
                self.logSupersededProfileTransition(request, correlationID: correlationID)
                return
            }
            self.applyFrameChanges(frameChanges, correlationID: correlationID)

            guard self.isProfileTransitionGenerationCurrent(request.generation) else {
                self.logSupersededProfileTransition(request, correlationID: correlationID)
                return
            }

            let definitions = configuration.workspaces
            let validWorkspaceIDs = Set(definitions.map(\.id))
            let fallbackWorkspaceID = definitions[0].id
            let preferredCurrent = configuration.preferredCurrentWorkspaceID.flatMap {
                validWorkspaceIDs.contains($0) ? $0 : nil
            }
            self.currentProfileID = configuration.profileID
            self.workspaces = definitions
            self.displayMode = configuration.displayMode
            self.workspaceDisplayAssignments = configuration.workspaceDisplayAssignments.filter {
                validWorkspaceIDs.contains($0.key)
            }
            self.appRulesByBundleIdentifier = Self.indexedAppRules(configuration.appRules)
            self.currentWorkspaceID = preferredCurrent ?? fallbackWorkspaceID
            self.previousWorkspaceID = nil
            self.previousWorkspaceIDByDisplay.removeAll()
            self.activeWorkspaceIDByDisplay = configuration.displayMode == .independent
                ? configuration.preferredActiveWorkspaceIDByDisplay.filter {
                    validWorkspaceIDs.contains($0.value)
                }
                : [:]
            self.reconcileIndependentActiveWorkspaces(
                displays: displays,
                preferCurrentWorkspace: true
            )

            var reroutedCount = 0
            var nextLayoutOrderByWorkspace: [UUID: Int] = [:]
            if !switchingProfile {
                for tracked in self.windows.values {
                    nextLayoutOrderByWorkspace[tracked.workspaceID] = max(
                        nextLayoutOrderByWorkspace[tracked.workspaceID] ?? 0,
                        tracked.layoutOrder + 1
                    )
                }
            }
            for key in transitionKeys {
                guard var tracked = self.windows[key] else { continue }
                let rule = self.resolvedRule(for: tracked.bundleIdentifier)
                let displayIdentifier = tracked.displayPlacement?.displayIdentifier
                    ?? displays.first(where: \.isMain)?.identifier
                    ?? displays.first?.identifier
                let fallbackForDisplay = displayIdentifier.flatMap {
                    self.activeWorkspaceIDByDisplay[$0]
                } ?? self.currentWorkspaceID
                let destination = Self.profileTransitionWorkspaceID(
                    existingWorkspaceID: tracked.workspaceID,
                    preserveExistingMembership: !switchingProfile,
                    validWorkspaceIDs: validWorkspaceIDs,
                    assignedWorkspaceID: rule.assignedWorkspaceID,
                    activeDisplayWorkspaceID: fallbackForDisplay,
                    defaultWorkspaceID: fallbackWorkspaceID
                )
                if switchingProfile || tracked.workspaceID != destination {
                    tracked.workspaceID = destination
                    tracked.layoutOrder = nextLayoutOrderByWorkspace[destination] ?? 0
                    nextLayoutOrderByWorkspace[destination] = tracked.layoutOrder + 1
                    tracked.layoutWeight = 1
                    reroutedCount += 1
                }
                tracked.workspaceRuleOverrideActive = false
                self.windows[key] = tracked
            }

            self.pendingRestoredWindows.removeAll()
            if switchingProfile {
                self.lastFocusedWindow.removeAll()
                self.tiledTrees.removeAll()
                self.radialPlacementCommitContext = nil
                self.radialFreeformPlacementCommitContext = nil
                self.directionalMoveGestureContext = nil
            } else {
                self.lastFocusedWindow = self.lastFocusedWindow.filter {
                    validWorkspaceIDs.contains($0.key) && self.windows[$0.value] != nil
                }
            }
            self.applyVisibility(displays: displays, correlationID: correlationID)

            if let focusedBefore,
               let focusedTracked = self.windows[focusedBefore],
               !Self.shouldWindowBeVisible(
                   workspaceID: focusedTracked.workspaceID,
                   activeWorkspaceIDs: self.activeWorkspaceIDs,
                   rule: self.resolvedRule(for: focusedTracked.bundleIdentifier)
               ) {
                _ = AccessibilityWindow.clearFocus(of: focusedTracked.element)
                self.lastObservedFocusedWindow = nil
                self.recentInteractionFocusTarget = nil
            }

            self.lastBackgroundLayoutSignature = self.backgroundLayoutSignature(displays: displays)
            self.persistState(preservingPendingRestores: false, waitForCompletion: true)
            self.emitState()
            self.emitCommandFeedback("Profile: \(configuration.profileName)", correlationID: correlationID)
            self.diagnostics.log(
                category: "profile",
                event: "transition-completed",
                correlation: correlationID,
                fields: [
                    "profile": Self.shortIdentifier(configuration.profileID.uuidString),
                    "selection-reason": configuration.selectionReason.diagnosticValue,
                    "workspace-count": String(definitions.count),
                    "managed-window-count": String(self.windows.count),
                    "restored-frame-count": String(frameChanges.count),
                    "rerouted-window-count": String(reroutedCount),
                    "deferred-window-count": String(deferredCount),
                    "display-mode": configuration.displayMode.rawValue,
                    "active-workspaces": self.diagnosticActiveWorkspaceMap(),
                ]
            )
        }
    }

    private func isProfileTransitionGenerationCurrent(_ generation: UInt64) -> Bool {
        profileTransitionGenerationGate.isCurrent(generation)
    }

    private func logSupersededProfileTransition(
        _ request: ProfileActivationRequest,
        correlationID: String
    ) {
        diagnostics.log(
            category: "profile",
            event: "transition-superseded",
            correlation: correlationID,
            fields: [
                "profile": Self.shortIdentifier(request.configuration.profileID.uuidString),
                "generation": String(request.generation),
            ]
        )
    }

    static func profileTransitionShouldRecoverWindow(
        disposition: WindowAdmissionDisposition?,
        isTemporarilyDeferred: Bool,
        isMinimized: Bool,
        isFullscreen: Bool
    ) -> Bool {
        guard !isTemporarilyDeferred, !isMinimized, !isFullscreen else { return false }
        switch disposition {
        case .ignoredCompanionSurface, .ignoredTransientPopup, .temporarilyIneligible:
            return false
        case .managedNormal, .managedDialog, nil:
            return true
        }
    }

    static func profileTransitionWorkspaceID(
        existingWorkspaceID: UUID,
        preserveExistingMembership: Bool,
        validWorkspaceIDs: Set<UUID>,
        assignedWorkspaceID: UUID?,
        activeDisplayWorkspaceID: UUID?,
        defaultWorkspaceID: UUID
    ) -> UUID {
        if let assignedWorkspaceID, validWorkspaceIDs.contains(assignedWorkspaceID) {
            return assignedWorkspaceID
        }
        if preserveExistingMembership, validWorkspaceIDs.contains(existingWorkspaceID) {
            return existingWorkspaceID
        }
        if let activeDisplayWorkspaceID, validWorkspaceIDs.contains(activeDisplayWorkspaceID) {
            return activeDisplayWorkspaceID
        }
        return validWorkspaceIDs.contains(defaultWorkspaceID)
            ? defaultWorkspaceID : validWorkspaceIDs.first ?? defaultWorkspaceID
    }

    static func profileTransitionVisibleFrame(
        currentFrame: WindowFrame?,
        savedFrame: WindowFrame,
        displayBounds: [CGRect]
    ) -> WindowFrame? {
        guard let mainDisplayBounds = displayBounds.first,
              !mainDisplayBounds.isNull,
              !mainDisplayBounds.isEmpty
        else { return nil }
        let displays = displayBounds.enumerated().map { index, bounds in
            DisplaySnapshot(
                identifier: "transition-\(index)",
                bounds: bounds,
                isMain: index == 0,
                name: "Display"
            )
        }
        if let currentFrame, isMeaningfullyVisible(currentFrame, displays: displays) {
            return currentFrame
        }
        if isMeaningfullyVisible(savedFrame, displays: displays) {
            return savedFrame
        }
        return quitRecoveryFrame(
            savedFrame: savedFrame,
            currentFrame: currentFrame,
            mainDisplayBounds: mainDisplayBounds
        )
    }

    func updateDisplayConfiguration(
        mode: MultiDisplayMode,
        workspaceDisplayAssignments: [UUID: String]
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.displayMode != mode ||
                    self.workspaceDisplayAssignments != workspaceDisplayAssignments
            else { return }
            self.directionalMoveGestureContext = nil
            if self.wakeReconciliationState.isPending {
                self.displayMode = mode
                self.activeWorkspaceIDByDisplay = Self.remappedActiveWorkspaceDisplayIdentifiers(
                    self.activeWorkspaceIDByDisplay,
                    previousHomes: self.workspaceDisplayAssignments,
                    currentHomes: workspaceDisplayAssignments
                )
                self.previousWorkspaceIDByDisplay = Self.remappedActiveWorkspaceDisplayIdentifiers(
                    self.previousWorkspaceIDByDisplay,
                    previousHomes: self.workspaceDisplayAssignments,
                    currentHomes: workspaceDisplayAssignments
                )
                self.workspaceDisplayAssignments = workspaceDisplayAssignments
                self.wakeReceivedAdditionalSignal = true
                self.diagnostics.log(
                    category: "lifecycle",
                    event: "display-configuration-deferred-to-wake",
                    correlation: "wake-\(self.wakeReconciliationState.generation)",
                    fields: ["display-mode": mode.rawValue]
                )
                return
            }
            self.refreshWindows()
            self.displayMode = mode
            self.activeWorkspaceIDByDisplay = Self.remappedActiveWorkspaceDisplayIdentifiers(
                self.activeWorkspaceIDByDisplay,
                previousHomes: self.workspaceDisplayAssignments,
                currentHomes: workspaceDisplayAssignments
            )
            self.previousWorkspaceIDByDisplay = Self.remappedActiveWorkspaceDisplayIdentifiers(
                self.previousWorkspaceIDByDisplay,
                previousHomes: self.workspaceDisplayAssignments,
                currentHomes: workspaceDisplayAssignments
            )
            self.workspaceDisplayAssignments = workspaceDisplayAssignments
            self.reconcileIndependentActiveWorkspaces(
                displays: Self.activeDisplays(),
                preferCurrentWorkspace: true
            )
            self.applyVisibility()
            self.persistState(preservingPendingRestores: true)
            self.emitState()
        }
    }

    func updateAppRules(_ rules: [AppRule]) {
        queue.async { [weak self] in
            guard let self else { return }
            let previousRules = self.appRulesByBundleIdentifier
            let nextRules = Self.indexedAppRules(rules)
            let displays = Self.activeDisplays()

            let changedBundleIdentifiers = Set(previousRules.keys)
                .union(nextRules.keys)
                .filter { previousRules[$0] != nextRules[$0] }
                .sorted()
            for bundleIdentifier in changedBundleIdentifiers {
                let next = self.resolvedRule(for: bundleIdentifier, in: nextRules)
                self.diagnostics.log(
                    category: "app-rule",
                    event: "effective-policy-changed",
                    fields: [
                        "bundle": bundleIdentifier,
                        "keep-on-all": String(next.keepsOnAllWorkspaces),
                        "exclude-from-layout": String(next.excludesFromLayout),
                        "float-secondary-windows": String(next.floatsSecondaryWindows),
                        "assigned-workspace": next.assignedWorkspaceID
                            .map { Self.shortIdentifier($0.uuidString) } ?? "none",
                    ]
                )
            }

            for key in self.windows.keys {
                guard var tracked = self.windows[key],
                      !self.isDropDownAppWindow(key),
                      let bundleIdentifier = tracked.bundleIdentifier
                else { continue }
                let previous = self.resolvedRule(for: bundleIdentifier, in: previousRules)
                let next = self.resolvedRule(for: bundleIdentifier, in: nextRules)
                if previous != next,
                   (previous.excludesFromLayout != next.excludesFromLayout ||
                    previous.keepsOnAllWorkspaces != next.keepsOnAllWorkspaces ||
                    previous.floatsSecondaryWindows != next.floatsSecondaryWindows),
                   let frame = AccessibilityWindow.frame(of: tracked.element),
                   Self.isMeaningfullyVisible(frame, displays: displays) {
                    tracked.restoreFrame = frame
                    tracked.displayPlacement = Self.displayPlacement(for: frame, displays: displays)
                }
                if previous != next {
                    tracked.workspaceRuleOverrideActive = false
                }
                if previous != next, let assignedWorkspaceID = next.assignedWorkspaceID {
                    if tracked.workspaceID != assignedWorkspaceID {
                        tracked.layoutOrder = self.nextLayoutOrder(in: assignedWorkspaceID)
                        tracked.layoutWeight = 1
                    }
                    tracked.workspaceID = assignedWorkspaceID
                }
                self.windows[key] = tracked
            }

            self.appRulesByBundleIdentifier = nextRules
            self.applyVisibility(displays: displays)
            self.persistState(preservingPendingRestores: true)
            self.emitState()
        }
    }

    func updateFocusFollowsMovedWindow(_ enabled: Bool) {
        queue.async { [weak self] in self?.focusFollowsMovedWindow = enabled }
    }

    func updateAutomaticallyUnhideApplications(_ enabled: Bool) {
        queue.async { [weak self] in
            self?.automaticallyUnhideApplications = enabled
            if !enabled { self?.lastAutomaticUnhideAttemptByProcess.removeAll() }
        }
    }

    func updateFocusedWindowHighlight(enabled: Bool) {
        queue.async { [weak self] in
            guard let self, self.focusedWindowHighlightEnabled != enabled else { return }
            self.focusedWindowHighlightEnabled = enabled
            self.lastBackgroundLayoutSignature = nil
            let displays = Self.activeDisplays()
            self.reapplyPresentedDropDownAppFrameForFocusBorder(displays: displays)
            self.applyVisibility(displays: displays)
            self.persistState(preservingPendingRestores: true)
            self.emitState()
        }
    }

    func admissionSupportSnapshot(
        completion: @escaping ([WindowAdmissionSupportRecord]) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            for (key, tracked) in self.windows {
                guard let coreMetadata = self.admissionMetadataByWindow[key] else { continue }
                self.admissionMetadataByWindow[key] = AccessibilityWindow.admissionSupportMetadata(
                    of: tracked.element,
                    coreMetadata: coreMetadata
                )
            }
            let records = Self.admissionSupportRecords(
                decisions: self.admissionDecisionByWindow,
                metadata: self.admissionMetadataByWindow
            )
            DispatchQueue.main.async { completion(records) }
        }
    }

    /// Reads the existing managed-window membership without refreshing or moving windows. An app
    /// rule affects every window from a bundle, so split membership is deliberately ambiguous and
    /// resolves to no default rather than choosing one workspace arbitrarily.
    func appRuleDefaultWorkspaceID(
        forBundleIdentifier bundleIdentifier: String,
        completion: @escaping (UUID?) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            let workspaceIDs = self.windows.values.compactMap { tracked -> UUID? in
                guard tracked.bundleIdentifier?.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
                else { return nil }
                return tracked.workspaceID
            }
            let workspaceID = AppRuleDefaultWorkspacePolicy.resolve(
                applicationIsRunning: true,
                liveWorkspaceIDs: workspaceIDs
            )
            DispatchQueue.main.async { completion(workspaceID) }
        }
    }

    /// Creates a read-only support snapshot on the engine queue. It deliberately does not call
    /// refresh, admission, visibility, focus, or persistence paths, because copying diagnostics
    /// must never change the subject being diagnosed.
    func focusedWindowDiagnosticReport(now: Date = Date()) -> String {
        queue.sync {
            makeFocusedWindowDiagnosticReport(now: now)
        }
    }

    private func makeFocusedWindowDiagnosticReport(now: Date) -> String {
        let buildMode: String
        #if DEBUG
        buildMode = "Debug"
        #else
        buildMode = "Release"
        #endif
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "unknown"
        let base = (
            timestamp: now,
            appVersion: version,
            appBuild: build,
            buildMode: buildMode,
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            displaysHaveSeparateSpaces: NSScreen.screensHaveSeparateSpaces,
            session: Self.shortIdentifier(WorkspaceStateStore.currentWindowServerSession())
        )

        guard AXIsProcessTrusted() else {
            return FocusedWindowDiagnosticReport.render(FocusedWindowDiagnosticSnapshot(
                timestamp: base.timestamp,
                appVersion: base.appVersion,
                appBuild: base.appBuild,
                buildMode: base.buildMode,
                macOSVersion: base.macOSVersion,
                displaysHaveSeparateSpaces: base.displaysHaveSeparateSpaces,
                windowServerSession: base.session,
                targetStatus: "accessibility-unavailable",
                targetBundleIdentifier: .unavailable("Accessibility permission is not granted"),
                targetWindowIdentifier: .unavailable("Accessibility permission is not granted"),
                accessibility: [],
                management: [],
                relatedHistory: ""
            ))
        }
        let currentlyFocused = focusedWindowSnapshot().flatMap { snapshot in
            snapshot.key.processIdentifier == ownProcessIdentifier ? nil : snapshot
        }
        guard let focused = currentlyFocused ?? lastDiagnosticFocusedWindow
        else {
            return FocusedWindowDiagnosticReport.render(FocusedWindowDiagnosticSnapshot(
                timestamp: base.timestamp,
                appVersion: base.appVersion,
                appBuild: base.appBuild,
                buildMode: base.buildMode,
                macOSVersion: base.macOSVersion,
                displaysHaveSeparateSpaces: base.displaysHaveSeparateSpaces,
                windowServerSession: base.session,
                targetStatus: "no-target",
                targetBundleIdentifier: .unavailable("no externally focused window"),
                targetWindowIdentifier: .unavailable("no externally focused window"),
                accessibility: [],
                management: [],
                relatedHistory: ""
            ))
        }

        let key = focused.key
        let usedLastExternalAnchor = currentlyFocused == nil
        let tracked = windows[key]
        let cachedDecision = admissionDecisionByWindow[key] ?? tracked?.admissionDecision
        let cachedMetadata = admissionMetadataByWindow[key]
        let bundleIdentifier = tracked?.bundleIdentifier
            ?? cachedMetadata?.bundleIdentifier
            ?? NSRunningApplication(processIdentifier: key.processIdentifier)?.bundleIdentifier
        let targetStatus: String
        if NSRunningApplication(processIdentifier: key.processIdentifier) == nil {
            targetStatus = "stale"
        } else if temporarilyDeferredWindowKeys.contains(key) {
            targetStatus = "deferred"
        } else if ignoredWindowKeys.contains(key) || cachedDecision?.disposition.evictsTrackedWindow == true {
            targetStatus = "ignored"
        } else if tracked != nil {
            targetStatus = "managed"
        } else {
            targetStatus = "unmanaged"
        }

        let appElement = AXUIElementCreateApplication(key.processIdentifier)
        let observedFrame = Self.diagnosticFrameRead(of: focused.element)
        let displays = Self.activeDisplays()
        let actualFrame = AccessibilityWindow.frame(of: focused.element)
        let resolvedDisplayIndex = actualFrame.flatMap { frame in
            Self.displayPlacement(for: frame, displays: displays).flatMap { placement in
                displays.firstIndex(where: { $0.identifier == placement.displayIdentifier })
            }
        }
        let visibleFrame = resolvedDisplayIndex.map { displays[$0].usableBounds }

        var accessibility: [(String, DiagnosticReportValue)] = [
            ("ax-role", Self.diagnosticAttribute(focused.element, kAXRoleAttribute as CFString, as: String.self)),
            ("ax-subrole", Self.diagnosticAttribute(focused.element, kAXSubroleAttribute as CFString, as: String.self)),
            ("cg-window-layer", AccessibilityWindow.windowLayer(for: key.windowIdentifier).map { .value(String($0)) } ?? .unavailable("WindowServer read unavailable")),
            ("ax-focused", Self.diagnosticAttribute(focused.element, kAXFocusedAttribute as CFString, as: Bool.self)),
            ("ax-main", Self.diagnosticAttribute(focused.element, kAXMainAttribute as CFString, as: Bool.self)),
            ("ax-minimized", Self.diagnosticAttribute(focused.element, kAXMinimizedAttribute as CFString, as: Bool.self)),
            ("ax-fullscreen", Self.diagnosticAttribute(focused.element, "AXFullScreen" as CFString, as: Bool.self)),
            ("focused-settable", Self.diagnosticSettable(kAXFocusedAttribute as CFString, on: focused.element)),
            ("main-settable", Self.diagnosticSettable(kAXMainAttribute as CFString, on: focused.element)),
            ("app-focused-window-settable", Self.diagnosticSettable(kAXFocusedWindowAttribute as CFString, on: appElement)),
            ("raise-action-supported", Self.diagnosticAction(kAXRaiseAction as CFString, on: focused.element)),
            ("observed-frame", observedFrame),
            ("resolved-display", resolvedDisplayIndex.map { .value("display-\($0 + 1)") } ?? .unavailable("frame or display unavailable")),
            ("resolved-display-visible-frame", visibleFrame.map { .value(Self.diagnosticRect($0)) } ?? .unavailable("frame or display unavailable")),
        ]
        if accessibility.isEmpty { accessibility = [] }

        var management: [(String, DiagnosticReportValue)] = [
            ("capture-source", .value(usedLastExternalAnchor ? "last-external-focus" : "current-external-focus")),
            ("admission-disposition", cachedDecision.map { .value($0.disposition.rawValue) } ?? .unavailable("no cached admission decision")),
            ("admission-reason", cachedDecision.map { .value($0.reason.rawValue) } ?? .unavailable("no cached admission decision")),
            ("temporarily-deferred", .value(String(temporarilyDeferredWindowKeys.contains(key)))),
        ]
        if let tracked {
            let rule = resolvedRule(for: tracked.bundleIdentifier)
            let layout = workspaceLayout(for: tracked.workspaceID)
            let layoutDecision = Self.layoutDecision(
                layoutOverride: tracked.layoutOverride,
                admissionDecision: tracked.admissionDecision,
                rule: rule
            )
            let workspaceIndex = workspaces.firstIndex(where: { $0.id == tracked.workspaceID })
            let displayIndex = tracked.displayPlacement.flatMap { placement in
                displays.firstIndex(where: { $0.identifier == placement.displayIdentifier })
            }
            let treeParticipation = tiledTrees.contains { partition, tree in
                partition.workspaceID == tracked.workspaceID && tree.contains(key)
            }
            let shouldBeVisible = Self.shouldWindowBeVisible(
                workspaceID: tracked.workspaceID,
                activeWorkspaceIDs: activeWorkspaceIDs,
                rule: rule
            )
            let workspaceMembership: DiagnosticReportValue = workspaceIndex.map {
                .value("workspace-\($0 + 1)")
            } ?? .unavailable("workspace absent")
            let displayMembership: DiagnosticReportValue = displayIndex.map {
                .value("display-\($0 + 1)")
            } ?? .unavailable("no stored display placement")
            let expectedFrame: DiagnosticReportValue = lastSolvedTiledFrames[key].map {
                .value(Self.diagnosticFrame($0))
            } ?? .unavailable("no solved layout frame")
            let expectedFrameMatch: DiagnosticReportValue
            if let expected = lastSolvedTiledFrames[key], let actualFrame {
                expectedFrameMatch = .value(String(AccessibilityWindow.framesMatch(actualFrame, expected)))
            } else {
                expectedFrameMatch = .unavailable("expected or observed frame unavailable")
            }
            management.append(contentsOf: [
                ("workspace-membership", workspaceMembership),
                ("display-membership", displayMembership),
                ("expected-visible", .value(String(shouldBeVisible))),
                ("parking-state", .value(shouldBeVisible ? "not-expected-parked" : "expected-parked")),
                ("app-rule-assigned-workspace", .value(String(rule.assignedWorkspaceID != nil))),
                ("app-rule-keeps-on-all-workspaces", .value(String(rule.keepsOnAllWorkspaces))),
                ("app-rule-excludes-from-layout", .value(String(rule.excludesFromLayout))),
                ("app-rule-floats-secondary", .value(String(rule.floatsSecondaryWindows))),
                ("layout-override", .value(tracked.layoutOverride.rawValue)),
                ("layout", .value(layout.rawValue)),
                ("layout-decision", .value(layoutDecision.rawValue)),
                ("layout-eligible", .value(String(layoutDecision.includesInLayout))),
                ("tiled-tree-participation", .value(String(treeParticipation))),
                ("expected-frame", expectedFrame),
                ("expected-frame-matches-observed", expectedFrameMatch),
            ])
        } else {
            management.append(contentsOf: [
                ("workspace-membership", .unavailable("window is not managed")),
                ("display-membership", .unavailable("window is not managed")),
                ("parking-state", .unavailable("window is not managed")),
                ("layout-eligible", .unavailable("window is not managed")),
                ("tiled-tree-participation", .value("false")),
                ("expected-frame", .unavailable("window is not managed")),
                ("expected-frame-matches-observed", .unavailable("window is not managed")),
            ])
        }

        let token = Self.diagnosticWindowKey(key)
        return FocusedWindowDiagnosticReport.render(FocusedWindowDiagnosticSnapshot(
            timestamp: base.timestamp,
            appVersion: base.appVersion,
            appBuild: base.appBuild,
            buildMode: base.buildMode,
            macOSVersion: base.macOSVersion,
            displaysHaveSeparateSpaces: base.displaysHaveSeparateSpaces,
            windowServerSession: base.session,
            targetStatus: targetStatus,
            targetBundleIdentifier: bundleIdentifier.map(DiagnosticReportValue.value) ?? .unavailable("bundle identifier unavailable"),
            targetWindowIdentifier: .value(token),
            accessibility: accessibility,
            management: management,
            relatedHistory: diagnostics.relatedDiagnosticsText(windowToken: token)
        ))
    }

    private static func diagnosticAttribute<T>(
        _ element: AXUIElement,
        _ attribute: CFString,
        as type: T.Type
    ) -> DiagnosticReportValue {
        var raw: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &raw)
        switch result {
        case .success:
            guard let value = raw as? T else { return .failed("unexpected value type") }
            return .value(String(describing: value))
        case .attributeUnsupported, .noValue:
            return .unavailable("unsupported")
        default:
            return .failed("AXError \(result.rawValue)")
        }
    }

    private static func diagnosticSettable(
        _ attribute: CFString,
        on element: AXUIElement
    ) -> DiagnosticReportValue {
        var settable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(element, attribute, &settable)
        switch result {
        case .success: return .value(String(settable.boolValue))
        case .attributeUnsupported, .noValue: return .unavailable("unsupported")
        default: return .failed("AXError \(result.rawValue)")
        }
    }

    private static func diagnosticAction(
        _ action: CFString,
        on element: AXUIElement
    ) -> DiagnosticReportValue {
        var raw: CFArray?
        let result = AXUIElementCopyActionNames(element, &raw)
        switch result {
        case .success:
            let names = raw as? [String] ?? []
            return .value(String(names.contains(action as String)))
        case .actionUnsupported, .noValue: return .unavailable("unsupported")
        default: return .failed("AXError \(result.rawValue)")
        }
    }

    private static func diagnosticFrameRead(of element: AXUIElement) -> DiagnosticReportValue {
        let position = diagnosticAttribute(element, kAXPositionAttribute as CFString, as: AXValue.self)
        let size = diagnosticAttribute(element, kAXSizeAttribute as CFString, as: AXValue.self)
        guard case .value = position, case .value = size else {
            if case let .failed(reason) = position { return .failed("position \(reason)") }
            if case let .failed(reason) = size { return .failed("size \(reason)") }
            return .unavailable("position or size unsupported")
        }
        return AccessibilityWindow.frame(of: element)
            .map { .value(diagnosticFrame($0)) }
            ?? .failed("AXValue conversion failed")
    }

    func workspaceApplications(
        for workspaceID: UUID,
        completion: @escaping ([WorkspaceApplicationSummary]) -> Void
    ) {
        queue.async { [weak self] in
            guard let self,
                  self.workspaces.contains(where: { $0.id == workspaceID })
            else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let candidates = self.windows.compactMap { key, tracked -> WorkspaceApplicationWindowCandidate? in
                guard !self.isDropDownAppWindow(key),
                      tracked.workspaceID == workspaceID,
                      !self.ignoredWindowKeys.contains(key),
                      !self.temporarilyDeferredWindowKeys.contains(key),
                      !self.resolvedRule(for: tracked.bundleIdentifier).keepsOnAllWorkspaces,
                      let application = NSRunningApplication(
                        processIdentifier: tracked.processIdentifier
                      )
                else { return nil }
                return WorkspaceApplicationWindowCandidate(
                    key: key,
                    workspaceID: tracked.workspaceID,
                    bundleIdentifier: tracked.bundleIdentifier ?? application.bundleIdentifier,
                    processIdentifier: tracked.processIdentifier,
                    name: application.localizedName
                        ?? tracked.bundleIdentifier
                        ?? "Application",
                    applicationURL: application.bundleURL,
                    layoutOrder: tracked.layoutOrder
                )
            }
            let summaries = WorkspaceApplicationSummaryPolicy.summaries(
                workspaceID: workspaceID,
                candidates: candidates,
                preferredWindow: self.lastFocusedWindow[workspaceID]
            )
            DispatchQueue.main.async { completion(summaries) }
        }
    }

    /// Builds a read-only description for the reusable workspace preview. This reuses already
    /// tracked windows and never enumerates, unparks, focuses, or writes to an Accessibility
    /// element. Active windows contribute their current frame; inactive managed layouts use their
    /// last solved geometry so the preview does not mistake the parking coordinate for the desktop.
    func setWorkspacePreviewObservationEnabled(_ enabled: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            self.workspacePreviewObservationEnabled = enabled
            if !enabled {
                self.hasWorkspacePreviewStateBaseline = false
                self.workspacePreviewStateByWorkspace.removeAll()
            }
        }
    }

    /// Reconstructs the frames an inactive managed workspace will receive on activation. Preview
    /// descriptors use it without touching Accessibility; the optional startup preparation uses
    /// the same geometry before applying bounded parked-window size changes.
    static func inactiveWorkspaceLayoutFrames(
        layout: WorkspaceLayout,
        orderedWindowKeys: [WindowKey],
        weights: [CGFloat],
        layoutBounds: CGRect,
        layoutConfiguration: WorkspaceLayoutConfiguration?,
        existingTiledTree: TiledNode?,
        accordionFocusedIndex: Int?
    ) -> [WindowKey: WindowFrame] {
        guard !orderedWindowKeys.isEmpty else { return [:] }
        switch layout {
        case .none:
            return [:]
        case .tiled:
            let configuration = layoutConfiguration ?? .aeroSpaceUserDefaults
            guard let tree = TiledLayoutEngine.reconciled(
                existingTiledTree,
                windowKeys: orderedWindowKeys,
                weights: weights,
                orientation: configuration.orientation.resolved(for: layoutBounds)
            ), let frames = try? TiledLayoutEngine.frames(
                for: tree,
                in: layoutBounds,
                configuration: configuration
            ) else { return [:] }
            return frames
        case .accordion:
            let frames = layoutFrames(
                .accordion,
                count: orderedWindowKeys.count,
                in: layoutBounds,
                accordionFocusedIndex: accordionFocusedIndex,
                layoutConfiguration: layoutConfiguration
            )
            return Dictionary(uniqueKeysWithValues: zip(orderedWindowKeys, frames))
        }
    }

    /// After normal startup parking, gives inactive managed windows the size they will receive on
    /// first activation. Their current parked position is retained, so applications can re-render
    /// truthful preview pixels without presenting those windows or adding ongoing background work.
    @discardableResult
    private func preSizeInactiveWorkspaceLayoutsForStartup() -> Int {
        guard preSizeInactiveLayoutsOnStartup, !isWindowManagementPaused else { return 0 }
        let displays = Self.activeDisplays()
        guard !displays.isEmpty else { return 0 }

        var changes: [FrameChange] = []
        var intendedTiledFrames: [WindowKey: WindowFrame] = [:]
        for workspace in workspaces where !isWorkspaceActive(workspace.id) && workspace.layout != .none {
            let participants = windows.values.filter { tracked in
                let rule = resolvedRule(for: tracked.bundleIdentifier)
                return tracked.workspaceID == workspace.id &&
                    !isDropDownAppWindow(tracked.key) &&
                    !isExcludedFromWorkspaceParticipation(tracked) &&
                    !rule.keepsOnAllWorkspaces &&
                    StableLayoutSlotPolicy.isAvailableForLayout(
                        isWriteDeferred: temporarilyDeferredWindowKeys.contains(tracked.key),
                        retainsLayoutSlot: retainedLayoutSlotWindowKeys.contains(tracked.key),
                        isExplicitlyEligible: fullscreenSessions[tracked.key] == nil
                    ) &&
                    Self.shouldIncludeInLayout(
                        layoutOverride: tracked.layoutOverride,
                        admissionDecision: tracked.admissionDecision,
                        rule: rule
                    )
            }
            let grouped = Dictionary(grouping: participants) { tracked in
                Self.layoutDisplayIdentifier(
                    preferredDisplayIdentifier: tracked.displayPlacement?.displayIdentifier,
                    savedFrame: tracked.restoreFrame,
                    mode: displayMode,
                    workspaceHomeDisplayIdentifier: displayMode == .independent
                        ? workspaceHomeDisplayIdentifier(for: workspace.id, displays: displays)
                        : nil,
                    displays: displays
                ) ?? displays.first?.identifier ?? "main-display"
            }
            let configuration = workspace.layoutConfiguration
            for (displayIdentifier, displayWindows) in grouped {
                guard let display = displays.first(where: { $0.identifier == displayIdentifier })
                    ?? displays.first(where: \.isMain)
                    ?? displays.first
                else { continue }
                let ordered = displayWindows.sorted { lhs, rhs in
                    if lhs.layoutOrder != rhs.layoutOrder { return lhs.layoutOrder < rhs.layoutOrder }
                    if lhs.key.processIdentifier != rhs.key.processIdentifier {
                        return lhs.key.processIdentifier < rhs.key.processIdentifier
                    }
                    return lhs.key.windowIdentifier < rhs.key.windowIdentifier
                }
                let focusedIndex = lastFocusedWindow[workspace.id].flatMap { key in
                    ordered.firstIndex(where: { $0.key == key })
                }
                let rawBounds = workspace.layout == .accordion || configuration != nil
                    ? display.usableBounds
                    : display.bounds
                let partition = TiledLayoutPartitionKey(
                    workspaceID: workspace.id,
                    displayIdentifier: display.identifier
                )
                let frames = Self.inactiveWorkspaceLayoutFrames(
                    layout: workspace.layout,
                    orderedWindowKeys: ordered.map(\.key),
                    weights: ordered.map { CGFloat(Self.validLayoutWeight($0.layoutWeight)) },
                    layoutBounds: managedLayoutBounds(rawBounds),
                    layoutConfiguration: configuration,
                    existingTiledTree: workspace.layout == .tiled ? tiledTrees[partition] : nil,
                    accordionFocusedIndex: focusedIndex
                )
                for tracked in ordered {
                    guard let target = frames[tracked.key],
                          let current = AccessibilityWindow.frame(of: tracked.element),
                          StartupInactiveWorkspaceSizingPolicy.shouldResize(
                              isEnabled: preSizeInactiveLayoutsOnStartup,
                              isWorkspaceActive: false,
                              layout: workspace.layout,
                              includesInLayout: true,
                              writeMode: Self.geometryWriteMode(for: tracked.admissionDecision),
                              isWriteDeferred: temporarilyDeferredWindowKeys.contains(tracked.key),
                              hasFullscreenSession: fullscreenSessions[tracked.key] != nil,
                              isMeaningfullyVisible: Self.isMeaningfullyVisible(
                                  current,
                                  displays: displays
                              ),
                              currentSize: current.size,
                              targetSize: target.size
                          )
                    else { continue }
                    changes.append(FrameChange(
                        window: tracked,
                        frame: WindowFrame(position: current.position, size: target.size)
                    ))
                    if workspace.layout == .tiled {
                        intendedTiledFrames[tracked.key] = target
                    }
                }
            }
        }

        guard !changes.isEmpty else {
            diagnostics.log(
                category: "startup-layout-preparation",
                event: "skipped",
                fields: ["reason": "no-eligible-size-changes"]
            )
            return 0
        }

        let correlationID = diagnostics.makeCorrelationID()
        emitCommandFeedback(
            StartupInactiveWorkspaceSizingPolicy.message(seed: Int(ownProcessIdentifier)),
            correlationID: correlationID
        )
        diagnostics.log(
            category: "startup-layout-preparation",
            event: "started",
            correlation: correlationID,
            fields: ["window-count": String(changes.count)]
        )
        applyFrameChanges(changes, correlationID: correlationID)

        let escaped = changes.filter { change in
            guard let actual = AccessibilityWindow.frame(of: change.window.element) else { return false }
            return Self.isMeaningfullyVisible(actual, displays: displays)
        }
        if !escaped.isEmpty {
            let parkingPosition = parkingPosition(displays: displays)
            applyPositionChanges(
                escaped.map { PositionChange(window: $0.window, position: parkingPosition) },
                correlationID: correlationID
            )
        }

        let settledKeys = Set(changes.compactMap { change -> WindowKey? in
            guard let actual = AccessibilityWindow.frame(of: change.window.element),
                  !Self.isMeaningfullyVisible(actual, displays: displays),
                  Self.sizesMatch(actual.size, change.frame.size)
            else { return nil }
            return change.window.key
        })
        for (key, frame) in intendedTiledFrames where settledKeys.contains(key) {
            lastSolvedTiledFrames[key] = frame
        }
        diagnostics.log(
            category: "startup-layout-preparation",
            event: "completed",
            correlation: correlationID,
            fields: [
                "attempted-count": String(changes.count),
                "settled-count": String(settledKeys.count),
                "reparked-count": String(escaped.count),
            ]
        )
        return settledKeys.count
    }

    func workspacePreviewDescriptor(
        for workspaceID: UUID,
        workspaceName: String,
        completion: @escaping (WorkspacePreviewDescriptor) -> Void
    ) {
        queue.async { [weak self] in
            guard let self,
                  self.workspaces.contains(where: { $0.id == workspaceID })
            else {
                DispatchQueue.main.async {
                    completion(WorkspacePreviewDescriptor(
                        workspaceID: workspaceID,
                        name: workspaceName,
                        canvasFrame: CGRect(x: 0, y: 0, width: 1, height: 1),
                        items: []
                    ))
                }
                return
            }

            let displays = Self.activeDisplays()
            let homeDisplayIdentifier = self.workspaceHomeDisplayIdentifier(
                for: workspaceID,
                displays: displays
            )
            let trackedItems = self.windows.values.filter { tracked in
                guard !self.isDropDownAppWindow(tracked.key),
                      tracked.workspaceID == workspaceID,
                      !self.ignoredWindowKeys.contains(tracked.key),
                      !self.temporarilyDeferredWindowKeys.contains(tracked.key),
                      !self.resolvedRule(for: tracked.bundleIdentifier).keepsOnAllWorkspaces,
                      NSRunningApplication(processIdentifier: tracked.processIdentifier) != nil
                else { return false }
                return true
            }
            let layout = self.workspaceLayout(for: workspaceID)
            let isActive = self.isWorkspaceActive(workspaceID)
            var previewFrames: [WindowKey: WindowFrame] = [:]

            for tracked in trackedItems {
                if isActive,
                   let current = AccessibilityWindow.frame(of: tracked.element),
                   Self.isMeaningfullyVisible(current, displays: displays) {
                    previewFrames[tracked.key] = current
                } else if layout == .tiled,
                          let solved = self.lastSolvedTiledFrames[tracked.key] {
                    previewFrames[tracked.key] = solved
                } else {
                    previewFrames[tracked.key] = tracked.restoreFrame
                }
            }

            // Reconstruct inactive managed layouts from existing session metadata only. Tiled uses
            // the persisted session tree even before this process has activated the workspace;
            // Accordion uses the same deterministic solver as normal activation.
            if !isActive, layout != .none {
                let participants = trackedItems.filter {
                    Self.shouldIncludeInLayout(
                        layoutOverride: $0.layoutOverride,
                        admissionDecision: $0.admissionDecision,
                        rule: self.resolvedRule(for: $0.bundleIdentifier)
                    )
                }
                let grouped = Dictionary(grouping: participants) { tracked -> String in
                    Self.layoutDisplayIdentifier(
                        preferredDisplayIdentifier: tracked.displayPlacement?.displayIdentifier,
                        savedFrame: tracked.restoreFrame,
                        mode: self.displayMode,
                        workspaceHomeDisplayIdentifier: self.displayMode == .independent
                            ? self.workspaceHomeDisplayIdentifier(for: workspaceID, displays: displays)
                            : nil,
                        displays: displays
                    ) ?? displays.first?.identifier ?? "main-display"
                }
                let layoutConfiguration = self.workspaceLayoutConfiguration(for: workspaceID)
                for (displayIdentifier, windows) in grouped {
                    guard let display = displays.first(where: { $0.identifier == displayIdentifier })
                        ?? displays.first(where: \.isMain)
                        ?? displays.first
                    else { continue }
                    let ordered = windows.sorted { lhs, rhs in
                        if lhs.layoutOrder != rhs.layoutOrder { return lhs.layoutOrder < rhs.layoutOrder }
                        if lhs.processIdentifier != rhs.processIdentifier {
                            return lhs.processIdentifier < rhs.processIdentifier
                        }
                        return lhs.key.windowIdentifier < rhs.key.windowIdentifier
                    }
                    let focusedIndex = self.lastFocusedWindow[workspaceID].flatMap { key in
                        ordered.firstIndex(where: { $0.key == key })
                    }
                    let rawLayoutBounds = layout == .accordion || layoutConfiguration != nil
                        ? display.usableBounds
                        : display.bounds
                    let partition = TiledLayoutPartitionKey(
                        workspaceID: workspaceID,
                        displayIdentifier: display.identifier
                    )
                    let frames = Self.inactiveWorkspaceLayoutFrames(
                        layout: layout,
                        orderedWindowKeys: ordered.map(\.key),
                        weights: ordered.map { CGFloat(Self.validLayoutWeight($0.layoutWeight)) },
                        layoutBounds: self.managedLayoutBounds(rawLayoutBounds),
                        layoutConfiguration: layoutConfiguration,
                        existingTiledTree: layout == .tiled ? self.tiledTrees[partition] : nil,
                        accordionFocusedIndex: focusedIndex
                    )
                    for tracked in ordered {
                        guard let frame = frames[tracked.key] else { continue }
                        previewFrames[tracked.key] = frame
                    }
                }
            }

            let candidateItems = trackedItems.compactMap { tracked -> WorkspacePreviewItemDescriptor? in
                guard let application = NSRunningApplication(
                    processIdentifier: tracked.processIdentifier
                ), let frame = previewFrames[tracked.key] else { return nil }
                return WorkspacePreviewItemDescriptor(
                    key: tracked.key,
                    applicationTarget: WorkspaceApplicationTarget(
                        workspaceID: workspaceID,
                        bundleIdentifier: tracked.bundleIdentifier ?? application.bundleIdentifier,
                        processIdentifier: tracked.processIdentifier
                    ),
                    name: application.localizedName
                        ?? tracked.bundleIdentifier
                        ?? "Application",
                    applicationURL: application.bundleURL,
                    frame: CGRect(origin: frame.position, size: frame.size)
                )
            }.sorted { lhs, rhs in
                guard let lhsTracked = self.windows[lhs.key],
                      let rhsTracked = self.windows[rhs.key]
                else { return lhs.key.windowIdentifier < rhs.key.windowIdentifier }
                if lhsTracked.layoutOrder != rhsTracked.layoutOrder {
                    return lhsTracked.layoutOrder < rhsTracked.layoutOrder
                }
                return lhs.key.windowIdentifier < rhs.key.windowIdentifier
            }
            let canvasDisplay = WorkspacePreviewGeometry.canvasDisplay(
                homeDisplayIdentifier: homeDisplayIdentifier,
                displays: displays
            )
            let canvasFrame = WorkspacePreviewGeometry.canvasFrame(
                homeDisplayIdentifier: homeDisplayIdentifier,
                displays: displays,
                fallbackItemFrames: candidateItems.map(\.frame)
            )
            // A workspace preview represents its home screen, not the union of every connected
            // display. A window spanning the boundary is clipped naturally by the preview canvas;
            // windows wholly on another screen are omitted from this screen's preview and capture.
            let items = candidateItems.filter {
                WorkspacePreviewGeometry.intersectsCanvas($0.frame, canvasFrame: canvasFrame)
            }
            let descriptor = WorkspacePreviewDescriptor(
                workspaceID: workspaceID,
                name: workspaceName,
                canvasFrame: canvasFrame,
                displayIdentifier: canvasDisplay?.identifier,
                items: items
            )
            DispatchQueue.main.async { completion(descriptor) }
        }
    }

    func switchToWorkspace(_ id: UUID, correlationID: String? = nil) {
        let correlationID = correlationID ?? diagnostics.makeCorrelationID()
        queue.async { [weak self] in
            self?.activateWorkspace(
                id,
                selectedApplication: nil,
                selectedWindowKey: nil,
                correlationID: correlationID
            )
        }
    }

    func activateWorkspaceApplication(
        _ target: WorkspaceApplicationTarget,
        correlationID: String? = nil
    ) {
        let correlationID = correlationID ?? diagnostics.makeCorrelationID()
        queue.async { [weak self] in
            self?.activateWorkspace(
                target.workspaceID,
                selectedApplication: target,
                selectedWindowKey: nil,
                correlationID: correlationID
            )
        }
    }

    func activateWorkspacePreviewItem(
        _ item: WorkspacePreviewItemDescriptor,
        correlationID: String? = nil
    ) {
        let correlationID = correlationID ?? diagnostics.makeCorrelationID()
        queue.async { [weak self] in
            self?.activateWorkspace(
                item.applicationTarget.workspaceID,
                selectedApplication: item.applicationTarget,
                selectedWindowKey: item.key,
                correlationID: correlationID
            )
        }
    }

    private func activateWorkspace(
        _ id: UUID,
        selectedApplication: WorkspaceApplicationTarget?,
        selectedWindowKey: WindowKey?,
        correlationID: String
    ) {
        guard workspaces.contains(where: { $0.id == id }) else { return }
        cancelManualTiledPreviewTransactions(reason: "workspace-command")

        let rawFocusedBefore = focusedWindowSnapshot()
        refreshWindows(correlationID: correlationID)
        let displays = Self.activeDisplays()
        let interactionDisplay = interactionDisplayResolution(
            focused: interactionFocusedWindowSnapshot(rawFocusedBefore),
            displays: displays
        )
        if displayMode == .independent {
            switchIndependentDisplay(
                to: id,
                sourceInteractionDisplayIdentifier: interactionDisplay.identifier,
                previousFocusKey: rawFocusedBefore?.key,
                displays: displays,
                correlationID: correlationID,
                selectedApplication: selectedApplication,
                selectedWindowKey: selectedWindowKey
            )
            return
        }
        let alreadyActive = id == currentWorkspaceID
        guard !alreadyActive || selectedApplication != nil else { return }
        let sourceWorkspaceID = currentWorkspaceID
        let token = beginCorrelatedAction(
            correlationID: correlationID,
            interactionDisplayIdentifier: interactionDisplay.identifier,
            expectedFocusTarget: nil
        )
        logWorkspaceSwitchBegin(
            workspaceID: id,
            sourceWorkspaceID: sourceWorkspaceID,
            sourceInteractionDisplayIdentifier: interactionDisplay.identifier,
            destination: WorkspaceSwitchDestination(
                logicalDisplayIdentifier: interactionDisplay.identifier,
                physicalDisplayIdentifier: interactionDisplay.identifier,
                usedDisconnectedHomeFallback: false
            ),
            correlationID: correlationID,
            reason: alreadyActive
                ? "unified-workspace-already-active-selected-app"
                : "unified-interaction-display"
        )
        if !alreadyActive {
            previousWorkspaceID = sourceWorkspaceID
            currentWorkspaceID = id
            applyVisibilityTransition(from: sourceWorkspaceID, to: id, correlationID: correlationID)
            persistState(preservingPendingRestores: true)
            emitState()
        }
        focusWorkspaceAfterSwitch(
            workspaceID: id,
            destinationDisplayIdentifier: interactionDisplay.identifier,
            displays: displays,
            correlationID: correlationID,
            token: token,
            previousFocusKey: rawFocusedBefore?.key,
            selectedApplication: selectedApplication,
            selectedWindowKey: selectedWindowKey
        )
    }

    func switchToPreviousWorkspace(correlationID: String? = nil) {
        let correlationID = correlationID ?? diagnostics.makeCorrelationID()
        queue.async { [weak self] in
            guard let self else { return }
            self.cancelManualTiledPreviewTransactions(reason: "workspace-command")
            let rawFocusedBefore = self.focusedWindowSnapshot()
            self.refreshWindows(correlationID: correlationID)
            let displays = Self.activeDisplays()
            if self.displayMode == .independent {
                let displayIdentifier = self.interactionDisplayIdentifier()
                guard let previousWorkspaceID = self.previousWorkspaceIDByDisplay[displayIdentifier] else { return }
                let interactionDisplay = self.interactionDisplayResolution(
                    focused: self.interactionFocusedWindowSnapshot(rawFocusedBefore),
                    displays: displays
                )
                self.switchIndependentDisplay(
                    to: previousWorkspaceID,
                    sourceInteractionDisplayIdentifier: interactionDisplay.identifier,
                    previousFocusKey: rawFocusedBefore?.key,
                    displays: displays,
                    correlationID: correlationID
                )
                return
            }
            guard let previousWorkspaceID = self.previousWorkspaceID else { return }
            let oldCurrent = self.currentWorkspaceID
            let interactionDisplay = self.interactionDisplayResolution(
                focused: self.interactionFocusedWindowSnapshot(rawFocusedBefore),
                displays: displays
            )
            let token = self.beginCorrelatedAction(
                correlationID: correlationID,
                interactionDisplayIdentifier: interactionDisplay.identifier,
                expectedFocusTarget: nil
            )
            self.logWorkspaceSwitchBegin(
                workspaceID: previousWorkspaceID,
                sourceWorkspaceID: oldCurrent,
                sourceInteractionDisplayIdentifier: interactionDisplay.identifier,
                destination: WorkspaceSwitchDestination(
                    logicalDisplayIdentifier: interactionDisplay.identifier,
                    physicalDisplayIdentifier: interactionDisplay.identifier,
                    usedDisconnectedHomeFallback: false
                ),
                correlationID: correlationID,
                reason: "unified-previous-workspace"
            )
            self.currentWorkspaceID = previousWorkspaceID
            self.previousWorkspaceID = oldCurrent
            self.applyVisibilityTransition(
                from: oldCurrent,
                to: previousWorkspaceID,
                correlationID: correlationID
            )
            self.persistState(preservingPendingRestores: true)
            self.emitState()
            self.focusWorkspaceAfterSwitch(
                workspaceID: previousWorkspaceID,
                destinationDisplayIdentifier: interactionDisplay.identifier,
                displays: displays,
                correlationID: correlationID,
                token: token,
                previousFocusKey: rawFocusedBefore?.key
            )
        }
    }

    func cycleWorkspace(offset: Int, correlationID: String? = nil) {
        let correlationID = correlationID ?? diagnostics.makeCorrelationID()
        queue.async { [weak self] in
            guard let self else { return }
            self.cancelManualTiledPreviewTransactions(reason: "workspace-command")
            let rawFocusedBefore = self.focusedWindowSnapshot()
            self.refreshWindows(correlationID: correlationID)
            let displays = Self.activeDisplays()
            let candidates: [WorkspaceDefinition]
            let activeID: UUID
            if self.displayMode == .independent {
                let displayIdentifier = self.interactionDisplayIdentifier()
                candidates = self.workspaces.filter {
                    self.workspaceHomeDisplayIdentifier(for: $0.id) == displayIdentifier
                }
                activeID = self.activeWorkspaceIDByDisplay[displayIdentifier]
                    ?? candidates.first?.id
                    ?? self.currentWorkspaceID
            } else {
                candidates = self.workspaces
                activeID = self.currentWorkspaceID
            }
            guard !candidates.isEmpty,
                  let index = candidates.firstIndex(where: { $0.id == activeID })
            else { return }
            let count = candidates.count
            let destination = (index + offset % count + count) % count
            let id = candidates[destination].id
            if self.displayMode == .independent {
                let interactionDisplay = self.interactionDisplayResolution(
                    focused: self.interactionFocusedWindowSnapshot(rawFocusedBefore),
                    displays: displays
                )
                self.switchIndependentDisplay(
                    to: id,
                    sourceInteractionDisplayIdentifier: interactionDisplay.identifier,
                    previousFocusKey: rawFocusedBefore?.key,
                    displays: displays,
                    correlationID: correlationID
                )
                return
            }
            guard id != self.currentWorkspaceID else { return }
            let sourceWorkspaceID = self.currentWorkspaceID
            let interactionDisplay = self.interactionDisplayResolution(
                focused: self.interactionFocusedWindowSnapshot(rawFocusedBefore),
                displays: displays
            )
            let token = self.beginCorrelatedAction(
                correlationID: correlationID,
                interactionDisplayIdentifier: interactionDisplay.identifier,
                expectedFocusTarget: nil
            )
            self.logWorkspaceSwitchBegin(
                workspaceID: id,
                sourceWorkspaceID: sourceWorkspaceID,
                sourceInteractionDisplayIdentifier: interactionDisplay.identifier,
                destination: WorkspaceSwitchDestination(
                    logicalDisplayIdentifier: interactionDisplay.identifier,
                    physicalDisplayIdentifier: interactionDisplay.identifier,
                    usedDisconnectedHomeFallback: false
                ),
                correlationID: correlationID,
                reason: "unified-cycle-workspace"
            )
            self.previousWorkspaceID = sourceWorkspaceID
            self.currentWorkspaceID = id
            self.applyVisibilityTransition(from: sourceWorkspaceID, to: id, correlationID: correlationID)
            self.persistState(preservingPendingRestores: true)
            self.emitState()
            self.focusWorkspaceAfterSwitch(
                workspaceID: id,
                destinationDisplayIdentifier: interactionDisplay.identifier,
                displays: displays,
                correlationID: correlationID,
                token: token,
                previousFocusKey: rawFocusedBefore?.key
            )
        }
    }

    func cycleWindowFocus(offset: Int, correlationID: String? = nil) {
        let correlationID = correlationID ?? diagnostics.makeCorrelationID()
        queue.async { [weak self] in
            guard let self, offset != 0 else { return }
            if QuickAppInteractionPolicy.routesWindowCycleToShelf(
                shelfIsPresented: self.isQuickAppShelfPresented,
                configuredAppCount: self.quickAppConfigurations.count,
                transitionInProgress: self.quickAppTransition != .idle
            ) {
                self.diagnostics.log(
                    category: "focus-cycle",
                    event: "routed-to-quick-app-shelf",
                    correlation: correlationID,
                    fields: ["offset": String(offset)]
                )
                self.cycleQuickAppInternal(offset: offset, correlationID: correlationID)
                return
            }
            let rawFocusedBefore = self.focusedWindowSnapshot()
            self.refreshWindows(correlationID: correlationID)
            let focusedBefore = self.interactionFocusedWindowSnapshot(rawFocusedBefore)
            let focusContextKey = Self.interactionFocusContext(
                focused: focusedBefore?.key,
                recent: self.recentInteractionFocusTarget,
                recentIsValid: Date() < self.recentInteractionDisplayDeadline
            )
            let displays = Self.activeDisplays()
            let interactionDisplay = self.interactionDisplayResolution(
                focused: focusedBefore,
                displays: displays
            )
            let verificationToken = self.beginCorrelatedAction(
                correlationID: correlationID,
                interactionDisplayIdentifier: interactionDisplay.identifier,
                expectedFocusTarget: focusContextKey
            )
            self.diagnostics.log(
                category: "focus-cycle",
                event: "begin",
                correlation: correlationID,
                fields: [
                    "offset": String(offset),
                    "focused-window": focusedBefore.map { Self.diagnosticWindowKey($0.key) } ?? "none",
                    "focus-anchor-window": focusContextKey.map(Self.diagnosticWindowKey) ?? "none",
                    "interaction-display": Self.shortIdentifier(interactionDisplay.identifier),
                    "display-reason": interactionDisplay.reason,
                    "active-before": self.diagnosticActiveWorkspaceMap(),
                ]
            )
            let workspaceResolution = self.interactionWorkspaceResolution(
                focusedKey: focusContextKey,
                displayIdentifier: interactionDisplay.identifier
            )
            let workspaceID = workspaceResolution.workspaceID
            self.diagnostics.log(
                category: "interaction",
                event: "workspace-resolved",
                correlation: correlationID,
                fields: [
                    "workspace": Self.shortIdentifier(workspaceID.uuidString),
                    "reason": workspaceResolution.reason,
                    "display": Self.shortIdentifier(interactionDisplay.identifier),
                ]
            )
            guard self.isWorkspaceActive(workspaceID) else {
                self.diagnostics.log(
                    category: "focus-cycle",
                    event: "cancelled",
                    correlation: correlationID,
                    fields: ["reason": "workspace-inactive"]
                )
                return
            }

            let workspaceLayout = self.workspaceLayout(for: workspaceID)
            let now = Date()
            self.focusCycleRejectedUntil = self.focusCycleRejectedUntil.filter { $0.value > now }
            let candidates = self.windows.compactMap { key, tracked -> (WindowKey, TrackedWindow, WindowFrame, String)? in
                guard !self.isDropDownAppWindow(key),
                      !self.isExcludedFromWorkspaceParticipation(tracked)
                else { return nil }
                let rule = self.resolvedRule(for: tracked.bundleIdentifier)
                let workspaceMatches = tracked.workspaceID == workspaceID || rule.keepsOnAllWorkspaces
                let visible = Self.shouldWindowBeVisible(
                    workspaceID: tracked.workspaceID,
                    activeWorkspaceIDs: self.activeWorkspaceIDs,
                    rule: rule
                )
                let frame = AccessibilityWindow.frame(of: tracked.element)
                let meaningfullyVisible = frame.map { Self.isMeaningfullyVisible($0, displays: displays) } == true
                let displayIdentifier = frame.flatMap {
                    Self.displayPlacement(for: $0, displays: displays)?.displayIdentifier
                }
                let displayMatches = Self.focusCycleCandidateIsInScope(
                    candidateDisplayIdentifier: displayIdentifier,
                    interactionDisplayIdentifier: interactionDisplay.identifier
                )
                let capabilities = AccessibilityWindow.focusCapabilities(
                    of: tracked.element,
                    processIdentifier: tracked.processIdentifier,
                    windowIdentifier: key.windowIdentifier
                )
                let focusEligible = AccessibilityWindow.isEligibleFocusCycleCandidate(capabilities)
                let temporarilyRejected = self.focusCycleRejectedUntil[key].map { $0 > now } == true
                let included = workspaceMatches && visible && meaningfullyVisible && displayMatches &&
                    frame != nil && focusEligible && !temporarilyRejected
                self.diagnostics.log(
                    category: "focus-cycle",
                    event: "candidate",
                    correlation: correlationID,
                    fields: [
                        "window": Self.diagnosticWindowKey(key),
                        "bundle": tracked.bundleIdentifier ?? "unknown",
                        "workspace": Self.shortIdentifier(tracked.workspaceID.uuidString),
                        "display": displayIdentifier.map(Self.shortIdentifier) ?? "unknown",
                        "workspace-match": String(workspaceMatches),
                        "visible": String(visible),
                        "meaningfully-visible": String(meaningfullyVisible),
                        "display-match": String(displayMatches),
                        "layout-override": tracked.layoutOverride.rawValue,
                        "automatic-dialog": String(tracked.admissionDecision.automaticallyFloats),
                        "layout-decision": Self.layoutDecision(
                            layoutOverride: tracked.layoutOverride,
                            admissionDecision: tracked.admissionDecision,
                            rule: rule
                        ).rawValue,
                        "app-excluded": String(rule.excludesFromLayout),
                        "app-floats-secondary": String(rule.floatsSecondaryWindows),
                        "keep-on-all": String(rule.keepsOnAllWorkspaces),
                        "ax-role": capabilities.role ?? "unknown",
                        "ax-subrole": capabilities.subrole ?? "unknown",
                        "window-layer": capabilities.windowLayer.map(String.init) ?? "unknown",
                        "ax-focused": capabilities.isFocused.map(String.init) ?? "unknown",
                        "ax-main": capabilities.isMain.map(String.init) ?? "unknown",
                        "focused-settable": String(capabilities.focusedAttributeSettable),
                        "main-settable": String(capabilities.mainAttributeSettable),
                        "app-focused-window-settable": String(capabilities.applicationFocusedWindowAttributeSettable),
                        "raise-supported": String(capabilities.raiseActionSupported),
                        "focus-eligible": String(focusEligible),
                        "temporarily-rejected": String(temporarilyRejected),
                        "included": String(included),
                    ]
                )
                guard included, let frame, let displayIdentifier else { return nil }
                return (key, tracked, frame, displayIdentifier)
            }.sorted { lhs, rhs in
                if workspaceLayout == .none {
                    if lhs.2.position.y != rhs.2.position.y { return lhs.2.position.y < rhs.2.position.y }
                    if lhs.2.position.x != rhs.2.position.x { return lhs.2.position.x < rhs.2.position.x }
                }
                if lhs.0.processIdentifier != rhs.0.processIdentifier {
                    return lhs.0.processIdentifier < rhs.0.processIdentifier
                }
                return lhs.0.windowIdentifier < rhs.0.windowIdentifier
            }
            let orderedKeys = candidates.map(\.0)
            let attemptOrder = Self.focusCycleAttemptOrder(
                current: focusContextKey,
                orderedCandidates: orderedKeys,
                offset: offset
            )
            guard let targetKey = attemptOrder.first else {
                self.diagnostics.log(
                    category: "focus-cycle",
                    event: "cancelled",
                    correlation: correlationID,
                    fields: ["reason": "no-candidate"]
                )
                return
            }

            self.diagnostics.log(
                category: "focus-cycle",
                event: "target-chosen",
                correlation: correlationID,
                fields: [
                    "window": Self.diagnosticWindowKey(targetKey),
                    "ordered-candidates": orderedKeys.map(Self.diagnosticWindowKey).joined(separator: ","),
                    "attempt-order": attemptOrder.map(Self.diagnosticWindowKey).joined(separator: ","),
                    "workspace": Self.shortIdentifier(workspaceID.uuidString),
                    "display": Self.shortIdentifier(interactionDisplay.identifier),
                ]
            )
            self.attemptFocusCycleCandidate(
                attemptOrder: attemptOrder,
                candidateIndex: 0,
                phase: .initial,
                originalFocus: focusContextKey,
                workspaceID: workspaceID,
                interactionDisplayIdentifier: interactionDisplay.identifier,
                displays: displays,
                correlationID: correlationID,
                token: verificationToken
            )
        }
    }

    func focusWindow(_ direction: WindowDirection, correlationID: String? = nil) {
        let correlationID = correlationID ?? diagnostics.makeCorrelationID()
        queue.async { [weak self] in
            guard let self else { return }
            let rawFocusedBefore = self.focusedWindowSnapshot()
            self.refreshWindows(correlationID: correlationID)
            let presentedShelfWindowCount = self.quickAppSessions.values.reduce(into: 0) {
                if $1.isPresented { $0 += $1.windowKeys.count }
            }
            if QuickAppInteractionPolicy.routesDirectionalFocusToShelf(
                shelfIsPresented: self.isQuickAppShelfPresented,
                presentedWindowCount: presentedShelfWindowCount,
                transitionInProgress: self.quickAppTransition != .idle
            ) {
                self.focusPresentedQuickAppWindow(direction, correlationID: correlationID)
                return
            }
            guard let focused = self.interactionFocusedWindowSnapshot(rawFocusedBefore),
                  let sourceFrame = focused.frame ?? self.windows[focused.key].flatMap({
                      AccessibilityWindow.frame(of: $0.element)
                  })
            else {
                self.emitCommandFeedback("No managed window is available for directional focus.")
                return
            }
            let displays = Self.activeDisplays()
            let interactionDisplay = self.interactionDisplayResolution(focused: focused, displays: displays)
            let workspaceID = self.interactionWorkspaceResolution(
                focusedKey: focused.key,
                displayIdentifier: interactionDisplay.identifier
            ).workspaceID
            let candidates = self.directionalFocusCandidates(
                workspaceID: workspaceID,
                interactionDisplayIdentifier: interactionDisplay.identifier,
                displays: displays,
                correlationID: correlationID
            )
            let focusOrder = Self.wrappingDirectionalCandidateOrder(
                from: CGRect(origin: sourceFrame.position, size: sourceFrame.size),
                direction: direction,
                candidates: candidates.filter { $0.key != focused.key }
            )
            let order = focusOrder.candidates
            guard let target = order.first else {
                self.diagnostics.log(
                    category: "directional-focus",
                    event: "no-target",
                    correlation: correlationID,
                    fields: [
                        "direction": direction.rawValue,
                        "workspace": Self.shortIdentifier(workspaceID.uuidString),
                        "display": Self.shortIdentifier(interactionDisplay.identifier),
                    ]
                )
                self.emitCommandFeedback("No window to the \(direction.rawValue).")
                return
            }
            let token = self.beginCorrelatedAction(
                correlationID: correlationID,
                interactionDisplayIdentifier: interactionDisplay.identifier,
                expectedFocusTarget: target
            )
            self.diagnostics.log(
                category: "directional-focus",
                event: "target-chosen",
                correlation: correlationID,
                fields: [
                    "direction": direction.rawValue,
                    "source-window": Self.diagnosticWindowKey(focused.key),
                    "target-window": Self.diagnosticWindowKey(target),
                    "ordered-candidates": order.map(Self.diagnosticWindowKey).joined(separator: ","),
                    "wrapped": String(focusOrder.didWrap),
                    "workspace": Self.shortIdentifier(workspaceID.uuidString),
                    "display": Self.shortIdentifier(interactionDisplay.identifier),
                ]
            )
            self.attemptFocusCycleCandidate(
                attemptOrder: order,
                candidateIndex: 0,
                phase: .initial,
                originalFocus: focused.key,
                workspaceID: workspaceID,
                interactionDisplayIdentifier: interactionDisplay.identifier,
                displays: displays,
                correlationID: correlationID,
                token: token
            )
        }
    }

    /// While the Shelf is open it owns Navigate-arrow focus, just as an active workspace owns
    /// directional focus. Its layout-axis arrows wrap inside the visible group; perpendicular
    /// arrows remain contained instead of falling through to a managed window behind the Shelf.
    private func focusPresentedQuickAppWindow(
        _ direction: WindowDirection,
        correlationID: String
    ) {
        guard quickAppTransition == .idle else {
            diagnostics.log(
                category: "directional-focus",
                event: "shelf-contained",
                correlation: correlationID,
                fields: [
                    "direction": direction.rawValue,
                    "reason": "transition-in-progress",
                ]
            )
            return
        }
        guard QuickAppInteractionPolicy.directionalFocusUsesShelfAxis(
            direction,
            shelfDirection: quickAppShelfPresentation.direction
        ) else {
            diagnostics.log(
                category: "directional-focus",
                event: "shelf-contained",
                correlation: correlationID,
                fields: [
                    "direction": direction.rawValue,
                    "reason": "perpendicular-to-shelf-axis",
                ]
            )
            return
        }
        guard let selected = dropDownAppConfiguration else {
            diagnostics.log(
                category: "directional-focus",
                event: "shelf-contained",
                correlation: correlationID,
                fields: [
                    "direction": direction.rawValue,
                    "reason": "selection-unavailable",
                ]
            )
            return
        }
        let selectedBundleKey = Self.normalizedBundleIdentifier(selected.bundleIdentifier)
        guard let sourceSession = quickAppSessions[selectedBundleKey],
              sourceSession.isPresented,
              let sourceTarget = windows[sourceSession.windowKey],
              let sourceFrame = AccessibilityWindow.frame(of: sourceTarget.element)
        else {
            diagnostics.log(
                category: "directional-focus",
                event: "shelf-contained",
                correlation: correlationID,
                fields: [
                    "direction": direction.rawValue,
                    "reason": "selected-window-unavailable",
                ]
            )
            return
        }

        let presented = quickAppSessions.flatMap {
            bundleKey,
            session -> [(bundleKey: String, session: DropDownAppSession, candidate: DirectionalWindowCandidate<WindowKey>)] in
            guard session.isPresented else { return [] }
            return session.windowKeys.compactMap { key in
                guard key != sourceSession.windowKey,
                      let target = windows[key],
                      let frame = AccessibilityWindow.frame(of: target.element)
                else { return nil }
                return (
                    bundleKey,
                    session,
                    DirectionalWindowCandidate(
                        key: key,
                        frame: CGRect(origin: frame.position, size: frame.size)
                    )
                )
            }
        }.sorted { lhs, rhs in
            let leftOrder = quickAppConfigurations.firstIndex {
                Self.normalizedBundleIdentifier($0.bundleIdentifier) == lhs.bundleKey
            } ?? Int.max
            let rightOrder = quickAppConfigurations.firstIndex {
                Self.normalizedBundleIdentifier($0.bundleIdentifier) == rhs.bundleKey
            } ?? Int.max
            return leftOrder < rightOrder
        }
        let focusOrder = Self.wrappingDirectionalCandidateOrder(
            from: CGRect(origin: sourceFrame.position, size: sourceFrame.size),
            direction: direction,
            candidates: presented.map(\.candidate)
        )
        let order = focusOrder.candidates
        guard let targetKey = order.first,
              let targetEntry = presented.first(where: {
                  $0.candidate.key == targetKey
              }),
              let targetSession = quickAppSessions[targetEntry.bundleKey],
              let targetConfiguration = quickAppConfigurations.first(where: {
                  $0.bundleIdentifier.caseInsensitiveCompare(targetSession.bundleIdentifier) == .orderedSame
              })
        else {
            diagnostics.log(
                category: "directional-focus",
                event: "shelf-contained",
                correlation: correlationID,
                fields: [
                    "direction": direction.rawValue,
                    "reason": "no-shelf-target",
                    "source-window": Self.diagnosticWindowKey(sourceSession.windowKey),
                ]
            )
            return
        }

        var selectedTargetSession = targetSession
        selectedTargetSession.selectWindow(targetKey)
        quickAppSessions[targetEntry.bundleKey] = selectedTargetSession
        dropDownAppConfiguration = targetConfiguration
        onQuickAppSelectionChanged?(targetConfiguration.bundleIdentifier)
        diagnostics.log(
            category: "directional-focus",
            event: "routed-to-quick-app-shelf",
            correlation: correlationID,
            fields: [
                "direction": direction.rawValue,
                "source-window": Self.diagnosticWindowKey(sourceSession.windowKey),
                "target-window": Self.diagnosticWindowKey(targetKey),
                "wrapped": String(focusOrder.didWrap),
            ]
        )
        // Directional focus promotes a window that is already in the visible Shelf. Reconciliation
        // would rebuild the selected-centred group and move that target back to the first/centre
        // slot, making the reverse arrow impossible (most visibly with two windows). Keep the
        // current membership and frames fixed; ordered cycling remains responsible for rotating an
        // off-group app into view.
        guard let target = windows[targetKey] else { return }
        _ = AXUIElementPerformAction(target.element, kAXRaiseAction as CFString)
        if QuickAppInteractionPolicy.focusesQuickAppAfterShow(
            commandPalettePresented: commandPalettePresented
        ) {
            focusManagedWindow(
                targetKey,
                tracked: target,
                correlationID: correlationID
            )
        }
    }

    func beginDirectionalMoveGesture(
        identifier: String,
        firstDirection: WindowDirection,
        correlationID: String? = nil
    ) {
        let correlationID = correlationID ?? diagnostics.makeCorrelationID()
        queue.async { [weak self] in
            guard let self else { return }
            let displays = Self.activeDisplays()
            let focused = self.interactionFocusedWindowSnapshot(self.focusedWindowSnapshot())
            let interactionDisplay = self.interactionDisplayResolution(
                focused: focused,
                displays: displays
            )
            let workspaceID = self.interactionWorkspaceResolution(
                focusedKey: focused?.key,
                displayIdentifier: interactionDisplay.identifier
            ).workspaceID
            let workspace = self.workspaces.first(where: { $0.id == workspaceID })
            let placement = focused.flatMap { focused in
                self.makeTiledPlacementCommitContext(
                    validationToken: identifier,
                    createdAt: Date(),
                    focusedWindow: focused.key,
                    workspaceID: workspaceID,
                    displayIdentifier: interactionDisplay.identifier,
                    displays: displays,
                    correlationID: correlationID
                )
            }
            if let previous = self.directionalMoveGestureContext,
               previous.identifier != identifier {
                self.diagnostics.log(
                    category: "directional-chord",
                    event: "context-superseded",
                    correlation: correlationID,
                    fields: ["previous-gesture": String(previous.identifier.prefix(16))]
                )
            }
            self.directionalMoveGestureContext = DirectionalMoveGestureContext(
                identifier: identifier,
                createdAt: Date(),
                firstDirection: firstDirection,
                focusedWindow: focused?.key,
                workspaceID: workspace?.id,
                displayIdentifier: interactionDisplay.identifier,
                layout: workspace?.layout,
                placement: placement
            )
            self.diagnostics.log(
                category: "directional-chord",
                event: "context-captured",
                correlation: correlationID,
                fields: [
                    "gesture": String(identifier.prefix(16)),
                    "direction": firstDirection.rawValue,
                    "window": focused.map { Self.diagnosticWindowKey($0.key) } ?? "none",
                    "workspace": workspace.map { Self.shortIdentifier($0.id.uuidString) } ?? "none",
                    "display": Self.shortIdentifier(interactionDisplay.identifier),
                    "layout": workspace?.layout.rawValue ?? "none",
                    "corner-proposals": String(placement?.previews.count ?? 0),
                    "proposal-fingerprints": placement?.previews
                        .sorted { $0.key.rawValue < $1.key.rawValue }
                        .map { "\($0.key.rawValue)=\($0.value.fingerprint.prefix(16))" }
                        .joined(separator: ",") ?? "none",
                ]
            )
        }
    }

    func commitDirectionalMoveGesture(
        identifier: String,
        resolution: DirectionalMoveGestureResolution,
        correlationID: String? = nil
    ) {
        let correlationID = correlationID ?? diagnostics.makeCorrelationID()
        queue.async { [weak self] in
            guard let self else { return }
            guard let context = self.directionalMoveGestureContext,
                  context.identifier == identifier
            else {
                self.diagnostics.log(
                    category: "directional-chord",
                    event: "commit-rejected",
                    correlation: correlationID,
                    fields: [
                        "gesture": String(identifier.prefix(16)),
                        "reason": "missing-or-superseded-context",
                        "resolution": resolution.diagnosticValue,
                    ]
                )
                return
            }
            self.directionalMoveGestureContext = nil
            switch resolution {
            case let .single(direction):
                self.performMoveWindow(
                    direction,
                    expectedContext: context,
                    correlationID: correlationID
                )
            case let .corner(placement):
                guard context.layout == .tiled else {
                    self.emitCommandFeedback(
                        "Corner placement is available only in Tiled workspaces.",
                        correlationID: correlationID
                    )
                    self.diagnostics.log(
                        category: "directional-chord",
                        event: "commit-no-op",
                        correlation: correlationID,
                        fields: [
                            "placement": placement.rawValue,
                            "reason": "layout-not-tiled",
                            "layout": context.layout?.rawValue ?? "none",
                        ]
                    )
                    return
                }
                guard let placementContext = context.placement else {
                    self.emitCommandFeedback(
                        "This window cannot be placed in the Tiled layout.",
                        correlationID: correlationID
                    )
                    self.diagnostics.log(
                        category: "directional-chord",
                        event: "commit-no-op",
                        correlation: correlationID,
                        fields: ["placement": placement.rawValue, "reason": "no-valid-proposal"]
                    )
                    return
                }
                _ = self.commitTiledPlacement(
                    placementContext,
                    placement: placement,
                    maximumAge: 2,
                    diagnosticCategory: "directional-chord",
                    focusAction: "keyboard-corner-place",
                    feedback: "Placed window \(placement.title).",
                    correlationID: correlationID,
                    usesKeyboardFocusRetention: true
                )
            }
        }
    }

    func cancelDirectionalMoveGesture(
        identifier: String,
        reason: String,
        correlationID: String? = nil
    ) {
        let correlationID = correlationID ?? diagnostics.makeCorrelationID()
        queue.async { [weak self] in
            guard let self,
                  self.directionalMoveGestureContext?.identifier == identifier
            else { return }
            self.directionalMoveGestureContext = nil
            self.diagnostics.log(
                category: "directional-chord",
                event: "engine-context-cancelled",
                correlation: correlationID,
                fields: ["gesture": String(identifier.prefix(16)), "reason": reason]
            )
        }
    }

    private func rejectDirectionalMoveGesture(
        _ context: DirectionalMoveGestureContext,
        reason: String,
        correlationID: String
    ) {
        diagnostics.log(
            category: "directional-chord",
            event: "commit-rejected",
            correlation: correlationID,
            fields: [
                "gesture": String(context.identifier.prefix(16)),
                "reason": reason,
                "first-direction": context.firstDirection.rawValue,
            ]
        )
        emitCommandFeedback("Window move cancelled because its context changed.", correlationID: correlationID)
    }

    func moveWindow(_ direction: WindowDirection, correlationID: String? = nil) {
        let correlationID = correlationID ?? diagnostics.makeCorrelationID()
        queue.async { [weak self] in
            self?.performMoveWindow(direction, expectedContext: nil, correlationID: correlationID)
        }
    }

    private func performMoveWindow(
        _ direction: WindowDirection,
        expectedContext: DirectionalMoveGestureContext?,
        correlationID: String
    ) {
            if let expectedContext,
               Date().timeIntervalSince(expectedContext.createdAt) > 2 {
                rejectDirectionalMoveGesture(
                    expectedContext,
                    reason: "gesture-expired",
                    correlationID: correlationID
                )
                return
            }
            let rawFocusedBefore = focusedWindowSnapshot()
            refreshWindows(correlationID: correlationID)
            guard let focused = interactionFocusedWindowSnapshot(rawFocusedBefore),
                  let tracked = windows[focused.key]
            else {
                if let expectedContext {
                    rejectDirectionalMoveGesture(
                        expectedContext,
                        reason: "focused-window-unavailable",
                        correlationID: correlationID
                    )
                } else {
                    emitCommandFeedback("No managed window is available to reorder.")
                }
                return
            }
            let displays = Self.activeDisplays()
            let interactionDisplay = interactionDisplayResolution(focused: focused, displays: displays)
            let workspaceID = interactionWorkspaceResolution(
                focusedKey: focused.key,
                displayIdentifier: interactionDisplay.identifier
            ).workspaceID
            if let expectedContext,
               expectedContext.focusedWindow != focused.key ||
               expectedContext.workspaceID != workspaceID ||
               expectedContext.displayIdentifier != interactionDisplay.identifier ||
               expectedContext.layout != workspaceLayout(for: workspaceID) {
                rejectDirectionalMoveGesture(
                    expectedContext,
                    reason: "captured-context-changed",
                    correlationID: correlationID
                )
                return
            }
            guard let workspaceIndex = self.workspaces.firstIndex(where: { $0.id == workspaceID }),
                  self.workspaces[workspaceIndex].layout != .none,
                  Self.shouldIncludeInLayout(
                      layoutOverride: tracked.layoutOverride,
                      admissionDecision: tracked.admissionDecision,
                      rule: self.resolvedRule(for: tracked.bundleIdentifier)
                  ),
                  let display = displays.first(where: { $0.identifier == interactionDisplay.identifier })
            else {
                self.emitCommandFeedback("This window is not part of an ordered workspace layout.")
                return
            }
            let participants = self.orderedLayoutParticipants(
                workspaceID: workspaceID,
                displayIdentifier: interactionDisplay.identifier,
                displays: displays,
                correlationID: correlationID
            )
            guard participants.count > 1,
                  let sourceIndex = participants.firstIndex(of: focused.key)
            else {
                self.emitCommandFeedback("There is no other layout window to reorder.")
                return
            }
            let layout = self.workspaces[workspaceIndex].layout
            let configuration = self.workspaces[workspaceIndex].layoutConfiguration
                ?? .aeroSpaceUserDefaults
            let managedBounds = self.managedLayoutBounds(display.usableBounds)
            let orientation = configuration.orientation.resolved(for: managedBounds)
            let destinationKey: WindowKey
            var treeFingerprints: (before: String, after: String)?
            var tiledMoveStrategy: TiledDirectionalMoveStrategy?

            switch layout {
            case .none:
                // The earlier layout guard makes this unreachable, but keep the mutation boundary
                // explicit if another layout case is introduced later.
                self.emitCommandFeedback("Freeform has no window order to change.")
                return
            case .accordion:
                guard direction.axis == orientation else {
                    self.emitCommandFeedback(
                        "This \(orientation.rawValue) Accordion can only move windows \(orientation == .horizontal ? "left or right" : "up or down")."
                    )
                    return
                }
                guard let destinationIndex = Self.reorderDestinationIndex(
                    sourceIndex: sourceIndex,
                    count: participants.count,
                    direction: direction,
                    orientation: orientation
                ) else {
                    self.emitCommandFeedback("The window is already at that edge of the layout.")
                    return
                }
                for (index, key) in participants.enumerated() { self.windows[key]?.layoutOrder = index }
                destinationKey = participants[destinationIndex]
                let sourceOrder = self.windows[focused.key]?.layoutOrder ?? sourceIndex
                let destinationOrder = self.windows[destinationKey]?.layoutOrder ?? destinationIndex
                self.windows[focused.key]?.layoutOrder = destinationOrder
                self.windows[destinationKey]?.layoutOrder = sourceOrder
            case .tiled:
                let partition = TiledLayoutPartitionKey(
                    workspaceID: workspaceID,
                    displayIdentifier: interactionDisplay.identifier
                )
                let fallbackWeights = participants.map {
                    CGFloat(Self.validLayoutWeight(self.windows[$0]?.layoutWeight))
                }
                guard let currentTree = TiledLayoutEngine.reconciled(
                    self.tiledTrees[partition],
                    windowKeys: participants,
                    weights: fallbackWeights,
                    orientation: orientation
                ), let reordered = Self.directionallyReorderedTiledState(
                    tree: currentTree,
                    focusedWindow: focused.key,
                    direction: direction,
                    displayBounds: managedBounds,
                    configuration: configuration
                ) else {
                    self.emitCommandFeedback("The window is already at that edge of the Tiled layout.")
                    return
                }
                destinationKey = reordered.destinationWindow
                tiledMoveStrategy = reordered.strategy
                self.tiledTrees[partition] = reordered.tree
                for (index, key) in reordered.tree.windowKeys.enumerated() {
                    self.windows[key]?.layoutOrder = index
                    self.windows[key]?.layoutWeight = reordered.effectiveShares[key] ?? 1
                }
                treeFingerprints = (
                    TiledLayoutEngine.fingerprint(currentTree),
                    TiledLayoutEngine.fingerprint(reordered.tree)
                )
            }
            if self.workspaces[workspaceIndex].layoutConfiguration == nil {
                self.workspaces[workspaceIndex].layoutConfiguration = configuration
            }
            self.lastFocusedWindow[workspaceID] = focused.key
            let token = self.beginCorrelatedAction(
                correlationID: correlationID,
                interactionDisplayIdentifier: interactionDisplay.identifier,
                expectedFocusTarget: focused.key
            )
            self.prepareProgrammaticFocusIntent(focused.key, correlationID: correlationID, duration: 0.8)
            self.applyVisibleWindows(
                self.windows.values.filter { $0.workspaceID == workspaceID },
                displays: displays,
                correlationID: correlationID
            )
            self.lastBackgroundLayoutSignature = self.backgroundLayoutSignature(displays: displays)
            self.persistState(preservingPendingRestores: true)
            self.emitState()
            let updatedConfiguration = self.workspaces[workspaceIndex].layoutConfiguration
            DispatchQueue.main.async { [weak self] in
                if let updatedConfiguration {
                    self?.onWorkspaceLayoutConfigurationChanged?(workspaceID, updatedConfiguration)
                }
            }
            var diagnosticFields = [
                "direction": direction.rawValue,
                "window": Self.diagnosticWindowKey(focused.key),
                "swapped-with": Self.diagnosticWindowKey(destinationKey),
                "workspace": Self.shortIdentifier(workspaceID.uuidString),
                "display": Self.shortIdentifier(interactionDisplay.identifier),
                "layout": layout.rawValue,
            ]
            if let treeFingerprints {
                diagnosticFields["tree-before"] = treeFingerprints.before
                diagnosticFields["tree-after"] = treeFingerprints.after
            }
            if let tiledMoveStrategy {
                diagnosticFields["tree-move-strategy"] = tiledMoveStrategy.rawValue
            }
            self.diagnostics.log(
                category: "directional-move",
                event: "reordered",
                correlation: correlationID,
                fields: diagnosticFields
            )
            self.emitCommandFeedback("Moved window \(direction.rawValue) in the layout.")
            self.retainFocusAfterKeyboardManipulation(
                expected: focused.key,
                correlationID: correlationID,
                action: "directional-move",
                token: token
            )
    }

    func smartResize(by delta: Int, correlationID: String? = nil) {
        let correlationID = correlationID ?? diagnostics.makeCorrelationID()
        queue.async { [weak self] in
            guard let self, delta != 0 else { return }
            let rawFocusedBefore = self.focusedWindowSnapshot()
            self.refreshWindows(correlationID: correlationID)
            guard let focused = self.interactionFocusedWindowSnapshot(rawFocusedBefore),
                  let tracked = self.windows[focused.key]
            else {
                self.emitCommandFeedback("No managed window is available to resize.")
                return
            }
            let displays = Self.activeDisplays()
            let interactionDisplay = self.interactionDisplayResolution(focused: focused, displays: displays)
            let workspaceID = self.interactionWorkspaceResolution(
                focusedKey: focused.key,
                displayIdentifier: interactionDisplay.identifier
            ).workspaceID
            guard let workspaceIndex = self.workspaces.firstIndex(where: { $0.id == workspaceID }),
                  let display = displays.first(where: { $0.identifier == interactionDisplay.identifier }),
                  Self.shouldIncludeInLayout(
                      layoutOverride: tracked.layoutOverride,
                      admissionDecision: tracked.admissionDecision,
                      rule: self.resolvedRule(for: tracked.bundleIdentifier)
                  )
            else {
                self.emitCommandFeedback("Floating or rule-excluded windows keep their own size.")
                return
            }
            let layout = self.workspaces[workspaceIndex].layout
            var configuration = self.workspaces[workspaceIndex].layoutConfiguration
                ?? .aeroSpaceUserDefaults
            let participants = self.orderedLayoutParticipants(
                workspaceID: workspaceID,
                displayIdentifier: interactionDisplay.identifier,
                displays: displays,
                correlationID: correlationID
            )
            guard participants.count > 1,
                  let focusedIndex = participants.firstIndex(of: focused.key)
            else {
                self.emitCommandFeedback("Resize needs at least two layout windows.")
                return
            }
            let managedBounds = self.managedLayoutBounds(display.usableBounds)
            let layoutBounds = Self.insetLayoutBounds(managedBounds, gaps: configuration.gaps)
            let orientation = configuration.orientation.resolved(for: layoutBounds)
            let availableLength = Double(
                orientation == .horizontal ? layoutBounds.width : layoutBounds.height
            )
            let feedback: String
            switch layout {
            case .none:
                self.emitCommandFeedback("Freeform has no automatic split or padding to resize.")
                return
            case .accordion:
                guard let padding = Self.adjustedAccordionPadding(
                    current: configuration.accordionPadding,
                    delta: Double(delta),
                    availableLength: availableLength
                ) else {
                    self.emitCommandFeedback("Accordion padding is already at its limit.")
                    return
                }
                configuration.accordionPadding = padding
                self.workspaces[workspaceIndex].layoutConfiguration = configuration
                feedback = "Accordion padding: \(Int(padding.rounded())) pt"
            case .tiled:
                let fallbackWeights = participants.map {
                    Self.validLayoutWeight(self.windows[$0]?.layoutWeight)
                }
                let partition = TiledLayoutPartitionKey(
                    workspaceID: workspaceID,
                    displayIdentifier: interactionDisplay.identifier
                )
                guard let currentTree = TiledLayoutEngine.reconciled(
                    self.tiledTrees[partition],
                    windowKeys: participants,
                    weights: fallbackWeights.map { CGFloat($0) },
                    orientation: orientation
                ), let resized = Self.smartResizedTiledState(
                    tree: currentTree,
                    participants: participants,
                    focusedIndex: focusedIndex,
                    deltaPoints: Double(delta),
                    displayBounds: managedBounds,
                    configuration: configuration
                ) else {
                    self.emitCommandFeedback("That Tiled split is already at its safe limit.")
                    return
                }
                self.tiledTrees[partition] = resized.tree
                for (key, weight) in zip(participants, resized.weights) {
                    self.windows[key]?.layoutWeight = weight
                }
                if self.workspaces[workspaceIndex].layoutConfiguration == nil {
                    self.workspaces[workspaceIndex].layoutConfiguration = configuration
                }
                let percentage = Int((resized.weights[focusedIndex] * 100).rounded())
                feedback = "Focused Tiled share: \(percentage)%"
                self.diagnostics.log(
                    category: "smart-resize",
                    event: "tree-reweighted",
                    correlation: correlationID,
                    fields: [
                        "workspace": Self.shortIdentifier(workspaceID.uuidString),
                        "display": Self.shortIdentifier(interactionDisplay.identifier),
                        "window": Self.diagnosticWindowKey(focused.key),
                        "tree-before": TiledLayoutEngine.fingerprint(currentTree),
                        "tree-after": TiledLayoutEngine.fingerprint(resized.tree),
                    ]
                )
            }

            // Accordion geometry uses workspace focus history to choose its primary window. Record
            // the exact keyboard target before solving so a stale poll cannot promote a sibling.
            self.lastFocusedWindow[workspaceID] = focused.key
            let token = self.beginCorrelatedAction(
                correlationID: correlationID,
                interactionDisplayIdentifier: interactionDisplay.identifier,
                expectedFocusTarget: focused.key
            )
            self.prepareProgrammaticFocusIntent(focused.key, correlationID: correlationID, duration: 0.8)
            self.applyVisibleWindows(
                self.windows.values.filter { $0.workspaceID == workspaceID },
                displays: displays,
                correlationID: correlationID
            )
            self.lastBackgroundLayoutSignature = self.backgroundLayoutSignature(displays: displays)
            self.persistState(preservingPendingRestores: true)
            self.emitState()
            let updatedConfiguration = self.workspaces[workspaceIndex].layoutConfiguration
            DispatchQueue.main.async { [weak self] in
                if let updatedConfiguration {
                    self?.onWorkspaceLayoutConfigurationChanged?(workspaceID, updatedConfiguration)
                }
            }
            self.diagnostics.log(
                category: "smart-resize",
                event: "applied",
                correlation: correlationID,
                fields: [
                    "delta": String(delta),
                    "layout": layout.rawValue,
                    "orientation": orientation.rawValue,
                    "window": Self.diagnosticWindowKey(focused.key),
                    "workspace": Self.shortIdentifier(workspaceID.uuidString),
                    "display": Self.shortIdentifier(interactionDisplay.identifier),
                ]
            )
            self.emitCommandFeedback(feedback)
            self.retainFocusAfterKeyboardManipulation(
                expected: focused.key,
                correlationID: correlationID,
                action: "smart-resize",
                token: token
            )
        }
    }

    func moveCurrentWorkspaceToNextDisplay(correlationID: String? = nil) {
        moveCurrentWorkspace(toDisplayIdentifier: nil, correlationID: correlationID)
    }

    func moveCurrentWorkspace(
        toDisplayIdentifier requestedDisplayIdentifier: String?,
        correlationID: String? = nil
    ) {
        let correlationID = correlationID ?? diagnostics.makeCorrelationID()
        queue.async { [weak self] in
            guard let self else { return }
            guard self.displayMode == .independent else {
                self.emitCommandFeedback("Workspace display moves are available in Independent Displays mode.")
                return
            }
            let rawFocusedBefore = self.focusedWindowSnapshot()
            self.refreshWindows(correlationID: correlationID)
            let focused = self.interactionFocusedWindowSnapshot(rawFocusedBefore)
            let displays = Self.activeDisplays()
            guard displays.count > 1 else {
                self.emitCommandFeedback("Connect another display to move this workspace.")
                return
            }
            let sourceDisplay = self.interactionDisplayResolution(
                focused: focused,
                displays: displays
            )
            let workspaceID = self.interactionWorkspaceResolution(
                focusedKey: focused?.key,
                displayIdentifier: sourceDisplay.identifier
            ).workspaceID
            let destinationDisplay: DisplaySnapshot?
            if let requestedDisplayIdentifier {
                destinationDisplay = displays.first { $0.identifier == requestedDisplayIdentifier }
            } else if let sourceIndex = displays.firstIndex(where: {
                $0.identifier == sourceDisplay.identifier
            }) {
                destinationDisplay = displays[(sourceIndex + 1) % displays.count]
            } else {
                destinationDisplay = nil
            }
            guard let destinationDisplay,
                  destinationDisplay.identifier != sourceDisplay.identifier
            else {
                self.emitCommandFeedback("The destination display is not currently connected.")
                return
            }
            self.reconcileIndependentActiveWorkspaces(displays: displays)
            let homeByWorkspace = Dictionary(uniqueKeysWithValues: self.workspaces.map {
                ($0.id, self.workspaceHomeDisplayIdentifier(for: $0.id, displays: displays))
            })
            guard let plan = Self.workspaceDisplayMovePlan(
                workspaceIDs: self.workspaces.map(\.id),
                homeByWorkspace: homeByWorkspace,
                activeWorkspaceIDByDisplay: self.activeWorkspaceIDByDisplay,
                movingWorkspaceID: workspaceID,
                sourceDisplayIdentifier: sourceDisplay.identifier,
                destinationDisplayIdentifier: destinationDisplay.identifier
            ) else {
                self.emitCommandFeedback("Another workspace is needed to remain on the source display.")
                return
            }

            let focusKey = focused.flatMap { snapshot in
                self.windows[snapshot.key] != nil ? snapshot.key : nil
            }
            let token = self.beginCorrelatedAction(
                correlationID: correlationID,
                interactionDisplayIdentifier: destinationDisplay.identifier,
                expectedFocusTarget: focusKey
            )
            if let focusKey {
                self.prepareProgrammaticFocusIntent(focusKey, correlationID: correlationID, duration: 1.0)
            }
            self.captureCurrentFrames(
                for: [plan.movingWorkspaceID, plan.replacementWorkspaceID],
                displays: displays
            )
            for (changedWorkspaceID, displayIdentifier) in plan.changedAssignments {
                self.workspaceDisplayAssignments[changedWorkspaceID] = displayIdentifier
            }
            self.activeWorkspaceIDByDisplay = plan.activeWorkspaceIDByDisplay
            self.previousWorkspaceIDByDisplay[plan.sourceDisplayIdentifier] = plan.movingWorkspaceID
            self.previousWorkspaceIDByDisplay[plan.destinationDisplayIdentifier] = plan.replacementWorkspaceID
            self.previousWorkspaceID = plan.replacementWorkspaceID
            self.currentWorkspaceID = plan.movingWorkspaceID
            self.applyVisibleWindows(
                self.windows.values.filter {
                    $0.workspaceID == plan.movingWorkspaceID ||
                        $0.workspaceID == plan.replacementWorkspaceID
                },
                displays: displays,
                correlationID: correlationID
            )
            self.lastBackgroundLayoutSignature = self.backgroundLayoutSignature(displays: displays)
            self.persistState(preservingPendingRestores: true)
            self.emitState()
            self.diagnostics.log(
                category: "workspace-display-move",
                event: "complete",
                correlation: correlationID,
                fields: [
                    "workspace": Self.shortIdentifier(plan.movingWorkspaceID.uuidString),
                    "replacement-workspace": Self.shortIdentifier(plan.replacementWorkspaceID.uuidString),
                    "source-display": Self.shortIdentifier(plan.sourceDisplayIdentifier),
                    "destination-display": Self.shortIdentifier(plan.destinationDisplayIdentifier),
                    "active-after": self.diagnosticActiveWorkspaceMap(),
                    "focus-target": focusKey.map(Self.diagnosticWindowKey) ?? "none",
                ]
            )
            self.emitCommandFeedback("Moved workspace to \(destinationDisplay.name).")
            DispatchQueue.main.async { [weak self] in
                self?.onWorkspaceDisplayAssignmentsChanged?(plan.changedAssignments)
            }
            if let focusKey {
                self.verifyFocusAfterAction(
                    expected: focusKey,
                    correlationID: correlationID,
                    action: "workspace-display-move",
                    token: token,
                    mayRecoverNilFocus: true
                )
            }
        }
    }

    static func focusCycleCandidateIsInScope(
        candidateDisplayIdentifier: String?,
        interactionDisplayIdentifier: String?
    ) -> Bool {
        guard let interactionDisplayIdentifier else { return true }
        return candidateDisplayIdentifier == interactionDisplayIdentifier
    }

    func cycleWorkspaceLayout(offset: Int, correlationID: String? = nil) {
        let correlationID = correlationID ?? diagnostics.makeCorrelationID()
        queue.async { [weak self] in
            guard let self, offset != 0 else { return }
            self.cancelManualTiledPreviewTransactions(reason: "layout-command")
            let rawFocusedBefore = self.focusedWindowSnapshot()
            self.refreshWindows(correlationID: correlationID)
            let focusedBefore = self.interactionFocusedWindowSnapshot(rawFocusedBefore)
            let focusContextKey = Self.interactionFocusContext(
                focused: focusedBefore?.key,
                recent: self.recentInteractionFocusTarget,
                recentIsValid: Date() < self.recentInteractionDisplayDeadline
            )
            let displays = Self.activeDisplays()
            let interactionDisplay = self.interactionDisplayResolution(
                focused: focusedBefore,
                displays: displays
            )
            let workspaceID = self.interactionWorkspaceResolution(
                focusedKey: focusContextKey,
                displayIdentifier: interactionDisplay.identifier
            ).workspaceID
            guard let index = self.workspaces.firstIndex(where: { $0.id == workspaceID }) else { return }
            let nextLayout = self.workspaces[index].layout.cycled(by: offset)
            guard nextLayout != self.workspaces[index].layout else { return }
            let token = self.beginCorrelatedAction(
                correlationID: correlationID,
                interactionDisplayIdentifier: interactionDisplay.identifier,
                expectedFocusTarget: focusContextKey
            )
            if nextLayout == .none {
                self.captureCurrentFrames(for: [workspaceID], displays: displays)
            }
            if nextLayout != self.workspaces[index].layout,
               self.workspaces[index].layoutConfiguration == nil {
                self.workspaces[index].layoutConfiguration = .aeroSpaceUserDefaults
            }
            self.workspaces[index].layout = nextLayout
            if self.isWorkspaceActive(workspaceID) {
                if let focusContextKey, self.windows[focusContextKey] != nil {
                    self.prepareProgrammaticFocusIntent(
                        focusContextKey,
                        correlationID: correlationID,
                        duration: 0.7,
                        generation: token.generation
                    )
                }
                self.applyVisibleWindows(
                    self.windows.values.filter { $0.workspaceID == workspaceID },
                    displays: displays,
                    correlationID: correlationID
                )
            }
            self.lastBackgroundLayoutSignature = self.backgroundLayoutSignature(displays: displays)
            self.persistState(preservingPendingRestores: true)
            self.emitState()
            let updatedConfiguration = self.workspaces[index].layoutConfiguration
            DispatchQueue.main.async { [weak self] in
                self?.onWorkspaceLayoutChanged?(workspaceID, nextLayout)
                if let configuration = updatedConfiguration {
                    self?.onWorkspaceLayoutConfigurationChanged?(workspaceID, configuration)
                }
            }
            self.diagnostics.log(
                category: "layout-command",
                event: "cycle-complete",
                correlation: correlationID,
                fields: [
                    "layout": nextLayout.rawValue,
                    "workspace": Self.shortIdentifier(workspaceID.uuidString),
                    "display": Self.shortIdentifier(interactionDisplay.identifier),
                    "offset": String(offset),
                ]
            )
            self.emitCommandFeedback(
                "\(nextLayout.title) layout",
                correlationID: correlationID,
                preferredDisplayIdentifier: interactionDisplay.identifier
            )
            self.verifyFocusAfterAction(
                expected: focusContextKey,
                correlationID: correlationID,
                action: "cycle-layout",
                token: token,
                mayRecoverNilFocus: true
            )
        }
    }

    func setWorkspaceLayout(
        _ layout: WorkspaceLayout,
        cycleOrientationWhenAlreadySelected: Bool = false,
        correlationID: String? = nil
    ) {
        let correlationID = correlationID ?? diagnostics.makeCorrelationID()
        queue.async { [weak self] in
            guard let self else { return }
            self.cancelManualTiledPreviewTransactions(reason: "layout-command")
            let rawFocusedBefore = self.focusedWindowSnapshot()
            self.refreshWindows(correlationID: correlationID)
            let focusedBefore = self.interactionFocusedWindowSnapshot(rawFocusedBefore)
            let focusContextKey = Self.interactionFocusContext(
                focused: focusedBefore?.key,
                recent: self.recentInteractionFocusTarget,
                recentIsValid: Date() < self.recentInteractionDisplayDeadline
            )
            let displays = Self.activeDisplays()
            let interactionDisplay = self.interactionDisplayResolution(
                focused: focusedBefore,
                displays: displays
            )
            self.diagnostics.log(
                category: "layout-command",
                event: "begin",
                correlation: correlationID,
                fields: [
                    "requested-layout": layout.rawValue,
                    "focused-window": focusedBefore.map { Self.diagnosticWindowKey($0.key) } ?? "none",
                    "focus-anchor-window": focusContextKey.map(Self.diagnosticWindowKey) ?? "none",
                    "interaction-display": Self.shortIdentifier(interactionDisplay.identifier),
                    "display-reason": interactionDisplay.reason,
                    "active-before": self.diagnosticActiveWorkspaceMap(),
                ]
            )
            let workspaceResolution = self.interactionWorkspaceResolution(
                focusedKey: focusContextKey,
                displayIdentifier: interactionDisplay.identifier
            )
            let workspaceID = workspaceResolution.workspaceID
            guard let index = self.workspaces.firstIndex(where: { $0.id == workspaceID }) else {
                self.diagnostics.log(
                    category: "layout-command",
                    event: "cancelled",
                    correlation: correlationID,
                    fields: ["reason": "workspace-missing"]
                )
                return
            }
            let previousDefinition = self.workspaces[index]
            let previousLayout = previousDefinition.layout
            let automaticOrientation = displays
                .first(where: { $0.identifier == interactionDisplay.identifier })
                .map { WorkspaceLayoutOrientation.automatic.resolved(for: $0.usableBounds) }
                ?? .horizontal
            self.diagnostics.log(
                category: "interaction",
                event: "layout-target-resolved",
                correlation: correlationID,
                fields: [
                    "workspace": Self.shortIdentifier(workspaceID.uuidString),
                    "workspace-reason": workspaceResolution.reason,
                    "display": Self.shortIdentifier(interactionDisplay.identifier),
                    "previous-layout": previousLayout.rawValue,
                    "requested-layout": layout.rawValue,
                ]
            )
            let updatedDefinition = Self.layoutDefinitionAfterSelection(
                previousDefinition,
                targetLayout: layout,
                cycleOrientationWhenAlreadySelected: cycleOrientationWhenAlreadySelected,
                automaticOrientation: automaticOrientation
            )
            guard updatedDefinition != previousDefinition else {
                self.diagnostics.log(
                    category: "layout-command",
                    event: "unchanged",
                    correlation: correlationID,
                    fields: [
                        "reason": "layout-already-selected",
                        "layout": layout.rawValue,
                        "workspace": Self.shortIdentifier(workspaceID.uuidString),
                        "display": Self.shortIdentifier(interactionDisplay.identifier),
                    ]
                )
                self.emitCommandFeedback(
                    "\(layout.title) layout is already selected.",
                    correlationID: correlationID,
                    preferredDisplayIdentifier: interactionDisplay.identifier
                )
                return
            }
            let verificationToken = self.beginCorrelatedAction(
                correlationID: correlationID,
                interactionDisplayIdentifier: interactionDisplay.identifier,
                expectedFocusTarget: focusContextKey
            )
            if layout == .none, self.workspaces[index].layout != .none {
                self.captureCurrentFrames(for: [workspaceID], displays: displays)
            }
            self.workspaces[index] = updatedDefinition
            let updatedOrientation = updatedDefinition.layoutConfiguration?.orientation
                ?? WorkspaceLayoutConfiguration.aeroSpaceUserDefaults.orientation
            let resolvedUpdatedOrientation = updatedOrientation == .automatic
                ? automaticOrientation
                : updatedOrientation
            let repeatedTiledOrientationChange = previousLayout == .tiled &&
                previousDefinition.layoutConfiguration?.orientation != updatedDefinition.layoutConfiguration?.orientation
            let newlySelectedExplicitTiled = previousLayout != .tiled && updatedOrientation != .automatic
            // Automatic is resolved independently for each display during layout. Do not stamp the
            // interaction display's resolved direction onto every Unified-mode tree partition.
            if layout == .tiled, repeatedTiledOrientationChange || newlySelectedExplicitTiled {
                self.tiledTrees = TiledLayoutEngine.reorientedPartitions(
                    self.tiledTrees,
                    workspaceID: workspaceID,
                    orientation: resolvedUpdatedOrientation
                )
            }
            if self.isWorkspaceActive(workspaceID) {
                if let focusedKey = focusContextKey, self.windows[focusedKey] != nil {
                    self.prepareProgrammaticFocusIntent(
                        focusedKey,
                        correlationID: correlationID,
                        duration: 0.7
                    )
                }
                self.applyVisibleWindows(
                    self.windows.values.filter { $0.workspaceID == workspaceID },
                    displays: displays,
                    correlationID: correlationID
                )
            }
            self.lastBackgroundLayoutSignature = self.backgroundLayoutSignature(displays: displays)
            self.persistState(preservingPendingRestores: true)
            self.emitState()
            let updatedConfiguration = self.workspaces[index].layoutConfiguration
            DispatchQueue.main.async { [weak self] in
                self?.onWorkspaceLayoutChanged?(workspaceID, layout)
                if let configuration = updatedConfiguration {
                    self?.onWorkspaceLayoutConfigurationChanged?(workspaceID, configuration)
                }
            }
            self.diagnostics.log(
                category: "layout-command",
                event: "complete",
                correlation: correlationID,
                fields: [
                    "active-after": self.diagnosticActiveWorkspaceMap(),
                    "workspace": Self.shortIdentifier(workspaceID.uuidString),
                    "display": Self.shortIdentifier(interactionDisplay.identifier),
                    "orientation": resolvedUpdatedOrientation.rawValue,
                    "selection-mode": cycleOrientationWhenAlreadySelected
                        ? "direct-shortcut" : "direct-selection",
                ]
            )
            self.verifyFocusAfterAction(
                expected: focusContextKey,
                correlationID: correlationID,
                action: "set-layout",
                token: verificationToken,
                mayRecoverNilFocus: true
            )
        }
    }

    static func layoutDefinitionAfterSelection(
        _ definition: WorkspaceDefinition,
        targetLayout: WorkspaceLayout,
        cycleOrientationWhenAlreadySelected: Bool = false,
        automaticOrientation: WorkspaceLayoutOrientation = .horizontal
    ) -> WorkspaceDefinition {
        var updated = definition
        if definition.layout != targetLayout {
            updated.layout = targetLayout
            if updated.layoutConfiguration == nil {
                updated.layoutConfiguration = .aeroSpaceUserDefaults
            }
            return updated
        }
        guard cycleOrientationWhenAlreadySelected, targetLayout != .none else { return updated }
        let resolvedAutomatic = automaticOrientation == .automatic ? .horizontal : automaticOrientation
        var configuration = updated.layoutConfiguration ?? .aeroSpaceUserDefaults
        let visibleOrientation = configuration.orientation == .automatic
            ? resolvedAutomatic
            : configuration.orientation
        configuration.orientation = visibleOrientation == .horizontal ? .vertical : .horizontal
        updated.layoutConfiguration = configuration
        return updated
    }

    func toggleFocusedWindowFloating() {
        queue.async { [weak self] in
            guard let self else { return }
            self.refreshWindows()
            guard let focusedKey = self.focusedWindowKey(),
                  var tracked = self.windows[focusedKey]
            else { return }

            let rule = self.resolvedRule(for: tracked.bundleIdentifier)
            switch Self.floatingToggleDecision(
                currentOverride: tracked.layoutOverride,
                admissionDecision: tracked.admissionDecision,
                rule: rule
            ) {
            case .blockedByAppRule:
                let appName = tracked.bundleIdentifier
                    .flatMap { NSRunningApplication(processIdentifier: tracked.processIdentifier)?.localizedName ?? $0 }
                    ?? "This app"
                self.emitFloatingToggleResult(.blockedByAppRule(appName))
            case .blockedByFixedSizeWindow:
                self.emitFloatingToggleResult(.blockedByFixedSizeWindow)
            case .blockedByProtectedDialog:
                self.emitFloatingToggleResult(.blockedByProtectedDialog)
            case let .setLayoutOverride(layoutOverride):
                let displays = Self.activeDisplays()
                let willFloat = Self.layoutDecision(
                    layoutOverride: layoutOverride,
                    admissionDecision: tracked.admissionDecision,
                    rule: rule
                ).includesInLayout == false
                if willFloat,
                   let frame = AccessibilityWindow.frame(of: tracked.element),
                   Self.isMeaningfullyVisible(frame, displays: displays) {
                    tracked.restoreFrame = frame
                    tracked.displayPlacement = Self.displayPlacement(for: frame, displays: displays)
                }
                tracked.layoutOverride = layoutOverride
                self.windows[focusedKey] = tracked
                if self.isWorkspaceActive(tracked.workspaceID) {
                    self.applyVisibleWindows(
                        self.windows.values.filter { $0.workspaceID == tracked.workspaceID },
                        displays: displays
                    )
                }
                self.persistState(preservingPendingRestores: true)
                self.emitState()
                self.emitFloatingToggleResult(willFloat ? .enabled : .disabled)
            }
        }
    }

    func applicationActivated(
        processIdentifier: pid_t,
        radialInteractionCancellation: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            let previewProcessIdentifier = self.manualTiledMovePreviewSession?.focusedWindow
                .processIdentifier ?? self.manualTiledResizeSession?.focusedWindow.processIdentifier
            if let previewProcessIdentifier,
               previewProcessIdentifier != processIdentifier {
                self.cancelManualTiledPreviewTransactions(reason: "application-activated")
            }
            self.noteApplicationActivation(processIdentifier: processIdentifier)
            let shouldCancelRadialInteraction = Self.shouldCancelRadialInteractionForActivation(
                activatedProcessIdentifier: processIdentifier,
                expectedProcessIdentifier: self.radialPointerFocusProcessIdentifier,
                programmaticFocusDeadline: self.radialPointerFocusDeadline,
                now: Date(),
                verificationIsCurrent: self.radialPointerFocusGeneration.map(
                    self.isFocusActionGenerationCurrent
                ) ?? true
            )
            if !shouldCancelRadialInteraction {
                self.clearRadialPointerFocusIntent()
            }
            DispatchQueue.main.async {
                radialInteractionCancellation(shouldCancelRadialInteraction)
            }
            guard !self.isWindowManagementPaused else {
                self.diagnostics.log(
                    category: "pause-mode",
                    event: "application-activation-ignored",
                    fields: ["process": String(processIdentifier)]
                )
                return
            }
            let preservesPresentedShelf = QuickAppInteractionPolicy.preservesPresentedShelfForActivation(
                activatedProcessIdentifier: processIdentifier,
                ownProcessIdentifier: self.ownProcessIdentifier,
                commandPalettePresented: self.commandPalettePresented
            )
            let applicationSwitchActivation =
                self.quickAppApplicationSwitchActivationDisposition(
                    processIdentifier: processIdentifier
                )
            if applicationSwitchActivation == .incoming {
                self.completeQuickAppApplicationSwitchHandoff(
                    continuePendingSelection: false
                )
                self.queue.async { [weak self] in
                    self?.continuePendingQuickAppSelectionIfPossible()
                }
            } else if applicationSwitchActivation == .outgoing {
                self.diagnostics.log(
                    category: "drop-down-app",
                    event: "application-switch-outgoing-activation-preserved",
                    fields: ["process": String(processIdentifier)]
                )
            }
            let activationTargetsPresentedShelf = self.quickAppSessions.values.contains {
                $0.isPresented && $0.windowKey.processIdentifier == processIdentifier
            }
            let preservesShelf = preservesPresentedShelf ||
                activationTargetsPresentedShelf ||
                applicationSwitchActivation != nil
            if self.isQuickAppShelfPresented,
               !preservesShelf {
                self.hideDropDownApp(
                    restorePreviousFocus: false,
                    reason: "another-app-focused",
                    correlationID: nil
                )
            } else if case .showing = self.quickAppTransition,
                      let dropDownSession = self.dropDownAppSession,
                      dropDownSession.windowKey.processIdentifier != processIdentifier,
                      applicationSwitchActivation == nil {
                self.pendingQuickAppHideAfterPresentation = true
            }
            guard Self.shouldProcessApplicationActivation(
                processIdentifier: processIdentifier,
                ownProcessIdentifier: self.ownProcessIdentifier
            ) else {
                self.diagnostics.log(
                    category: "settings-window",
                    event: "app-owned-activation-ignored",
                    fields: ["reason": "excluded-from-managed-focus-observation"]
                )
                return
            }
            if let dropDownSession = self.quickAppSessions.values.first(where: {
                $0.isPresented && $0.windowKey.processIdentifier == processIdentifier
            }) {
                let decision = QuickAppInteractionPolicy.presentedActivationDecision(
                    activatedBundleIdentifier: dropDownSession.bundleIdentifier,
                    selectedBundleIdentifier: self.dropDownAppConfiguration?.bundleIdentifier
                )
                if let selected = self.quickAppConfigurations.first(where: {
                    $0.bundleIdentifier.caseInsensitiveCompare(
                        dropDownSession.bundleIdentifier
                    ) == .orderedSame
                }), decision.selectsActivatedConfiguration,
                   applicationSwitchActivation != .outgoing {
                    self.dropDownAppConfiguration = selected
                    self.onQuickAppSelectionChanged?(selected.bundleIdentifier)
                }
                if decision.restacksPresentedGroup {
                    self.restackPresentedQuickAppGroup(correlationID: nil)
                }
                self.diagnostics.log(
                    category: "drop-down-app",
                    event: "target-activation-observed",
                    fields: ["window": Self.diagnosticWindowKey(dropDownSession.windowKey)]
                )
            }
            let intendedTarget = self.programmaticFocusTarget
            let intendedCorrelationID = self.programmaticFocusCorrelationID
            let intendedGeneration = self.programmaticFocusGeneration
            let intendedTargetIsCurrent = Date() < self.programmaticFocusDeadline &&
                (intendedGeneration.map(self.isFocusActionGenerationCurrent) ?? true)
            self.refreshWindows()

            if let dropDownSession = self.quickAppSessions.values.first(where: {
                $0.isPresented && $0.windowKey.processIdentifier == processIdentifier
            }),
               intendedTarget != dropDownSession.windowKey {
                self.lastObservedFocusedWindow = dropDownSession.windowKey
                self.recentInteractionFocusTarget = nil
                self.recentInteractionDisplayDeadline = .distantPast
                return
            }

            let now = Date()
            self.supersededProgrammaticActivationUntil =
                self.supersededProgrammaticActivationUntil.filter { $0.value > now }
            if self.supersededProgrammaticActivationUntil[processIdentifier] != nil,
               intendedTarget?.processIdentifier != processIdentifier {
                self.diagnostics.log(
                    category: "focus-observation",
                    event: "superseded-activation-ignored",
                    correlation: intendedCorrelationID,
                    fields: [
                        "process": String(processIdentifier),
                        "reason": "newer-correlated-action",
                    ]
                )
                return
            }

            if let focusedWindow = self.focusedWindowKey() {
                switch Self.parkedFocusActivationDisposition(
                    allowExplicitActivationAfter: self.staleParkedFocusSuppression[focusedWindow],
                    now: Date()
                ) {
                case .suppressStaleActivation:
                    self.diagnostics.log(
                        category: "focus-observation",
                        event: "stale-activation-suppressed",
                        correlation: intendedCorrelationID,
                        fields: ["window": Self.diagnosticWindowKey(focusedWindow)]
                    )
                    return
                case .acceptExplicitActivation:
                    // A later explicit activation is genuine user intent and may use the normal
                    // external-focus workspace-follow behavior.
                    self.staleParkedFocusSuppression.removeValue(forKey: focusedWindow)
                case .unaffected:
                    break
                }
            }

            if let intendedTarget,
               intendedTarget.processIdentifier == processIdentifier,
               intendedTargetIsCurrent,
               let tracked = self.focusTargetWindow(intendedTarget) {
                if let competingFocus = self.focusedWindowKey(),
                   self.ignoredWindowKeys.contains(competingFocus) {
                    self.diagnostics.log(
                        category: "focus-observation",
                        event: "programmatic-activation-superseded",
                        correlation: intendedCorrelationID,
                        fields: [
                            "expected-window": Self.diagnosticWindowKey(intendedTarget),
                            "actual-window": Self.diagnosticWindowKey(competingFocus),
                            "reason": "ignored-popup-focused-before-reassert",
                        ]
                    )
                    self.clearProgrammaticFocusIntent()
                    return
                }
                if let competingFocus = self.focusedWindowKey(),
                   !Self.shouldReassertAfterActivation(
                        activatedProcessIdentifier: processIdentifier,
                        focusedProcessIdentifier: competingFocus.processIdentifier
                   ) {
                    self.diagnostics.log(
                        category: "focus-observation",
                        event: "programmatic-activation-superseded",
                        correlation: intendedCorrelationID,
                        fields: [
                            "expected-window": Self.diagnosticWindowKey(intendedTarget),
                            "actual-window": Self.diagnosticWindowKey(competingFocus),
                            "reason": "different-app-focused-before-reassert",
                        ]
                    )
                    self.clearProgrammaticFocusIntent()
                    return
                }
                self.diagnostics.log(
                    category: "focus-observation",
                    event: "application-activated",
                    correlation: intendedCorrelationID,
                    fields: [
                        "window": Self.diagnosticWindowKey(intendedTarget),
                        "classification": "programmatic-activation-before-exact-focus",
                        "expected-window": Self.diagnosticWindowKey(intendedTarget),
                    ]
                )
                self.programmaticFocusTarget = intendedTarget
                self.programmaticFocusDeadline = Date().addingTimeInterval(0.75)
                self.programmaticFocusCorrelationID = intendedCorrelationID
                self.programmaticFocusGeneration = intendedGeneration
                self.applyExactWindowFocus(
                    intendedTarget,
                    tracked: tracked,
                    correlationID: intendedCorrelationID,
                    event: "post-activation-exact-focus"
                )
                return
            }

            guard let focusedWindow = self.focusedWindowKey(),
                  focusedWindow.processIdentifier == processIdentifier
            else {
                self.diagnostics.log(
                    category: "focus-observation",
                    event: "application-activated-without-focused-window",
                    fields: ["process": String(processIdentifier)]
                )
                return
            }
            if Self.shouldIgnoreFocusObservation(
                focusedWindow: focusedWindow,
                ignoredWindowKeys: self.ignoredWindowKeys
            ) {
                // The popup belongs to the activated app, but it is intentionally outside all
                // workspace/focus state. Its admission record is sufficient diagnostics.
                return
            }

            // An explicit activation notification is stronger evidence than the polling edge. It
            // also catches Dock activation when the parked window was already the AX focused window.
            let correlationID = intendedCorrelationID
            let matchesIntent = intendedTarget == focusedWindow && intendedTargetIsCurrent
            self.diagnostics.log(
                category: "focus-observation",
                event: "application-activated",
                correlation: correlationID,
                fields: [
                    "window": Self.diagnosticWindowKey(focusedWindow),
                    "classification": matchesIntent ? "programmatic-intent" : "external-activation",
                    "expected-window": intendedTarget.map(Self.diagnosticWindowKey) ?? "none",
                ]
            )
            if !matchesIntent {
                self.clearProgrammaticFocusIntent()
            }
            self.lastObservedFocusedWindow = focusedWindow
            if !matchesIntent {
                self.recentInteractionDisplayIdentifier = nil
                self.recentInteractionFocusTarget = nil
                self.recentInteractionDisplayDeadline = .distantPast
            }
            self.followFocusedManagedWindow(focusedWindow, correlationID: correlationID)
        }
    }

    static func focusCycleTarget<T: Equatable>(
        current: T?,
        orderedCandidates: [T],
        offset: Int
    ) -> T? {
        guard !orderedCandidates.isEmpty else { return nil }
        guard let current,
              let currentIndex = orderedCandidates.firstIndex(of: current)
        else { return offset < 0 ? orderedCandidates.last : orderedCandidates.first }
        let count = orderedCandidates.count
        return orderedCandidates[(currentIndex + offset % count + count) % count]
    }

    static func interactionFocusContext<T>(
        focused: T?,
        recent: T?,
        recentIsValid: Bool
    ) -> T? {
        focused ?? (recentIsValid ? recent : nil)
    }

    static func layoutDecision(
        layoutOverride: WindowLayoutOverride,
        admissionDecision: WindowAdmissionDecision,
        rule: ResolvedAppRule
    ) -> WindowLayoutDecision {
        if rule.excludesFromLayout { return .appRuleExcluded }
        if geometryWriteMode(for: admissionDecision) == .positionOnly {
            return .automaticallyFloatingDialog
        }
        switch layoutOverride {
        case .floating:
            return .explicitlyFloating
        case .managed:
            return .explicitlyManaged
        case .automatic:
            if admissionDecision.automaticallyFloats {
                return .automaticallyFloatingDialog
            }
            if rule.floatsSecondaryWindows && admissionDecision.isSecondaryWindowCandidate {
                return .automaticallyFloatingSecondary
            }
            return .managedNormal
        }
    }

    static func floatingToggleDecision(
        currentOverride: WindowLayoutOverride,
        admissionDecision: WindowAdmissionDecision,
        rule: ResolvedAppRule
    ) -> FloatingToggleDecision {
        guard !rule.excludesFromLayout else { return .blockedByAppRule }
        guard geometryWriteMode(for: admissionDecision) != .positionOnly else {
            return admissionDecision.reason == .fixedSizeStandardWindow
                ? .blockedByFixedSizeWindow
                : .blockedByProtectedDialog
        }
        let currentlyIncluded = layoutDecision(
            layoutOverride: currentOverride,
            admissionDecision: admissionDecision,
            rule: rule
        ).includesInLayout
        return .setLayoutOverride(currentlyIncluded ? .floating : .managed)
    }

    static func restoredLayoutOverride(_ persistedOverride: WindowLayoutOverride?) -> WindowLayoutOverride {
        persistedOverride ?? .automatic
    }

    static func geometryWriteMode(
        for admissionDecision: WindowAdmissionDecision
    ) -> WindowGeometryWriteMode {
        switch admissionDecision.reason {
        case .fixedSizeStandardWindow, .nativeFilePanelIdentifier,
             .standardWindowWithDialogControls:
            .positionOnly
        default:
            .frame
        }
    }

    static func displayModeForWindowPlacement(
        configuredMode: MultiDisplayMode,
        rule: ResolvedAppRule
    ) -> MultiDisplayMode {
        rule.keepsOnAllWorkspaces ? .unified : configuredMode
    }

    func moveFocusedWindow(
        to workspaceID: UUID,
        followOverride: Bool? = nil,
        correlationID: String? = nil
    ) {
        let correlationID = correlationID ?? diagnostics.makeCorrelationID()
        queue.async { [weak self] in
            guard let self, self.workspaces.contains(where: { $0.id == workspaceID }) else { return }
            let rawFocusedBefore = self.focusedWindowSnapshot()
            self.refreshWindows(correlationID: correlationID)
            let focusedBefore = self.interactionFocusedWindowSnapshot(rawFocusedBefore)
            guard let focusedKey = focusedBefore?.key ?? self.focusedWindowKey(),
                  var tracked = self.windows[focusedKey]
            else { return }
            let displays = Self.activeDisplays()
            guard !displays.isEmpty else { return }
            let interactionDisplay = self.interactionDisplayResolution(
                focused: focusedBefore,
                displays: displays
            )
            let sourceWorkspaceID = tracked.workspaceID
            let rule = self.resolvedRule(for: tracked.bundleIdentifier)
            let disposition = Self.moveWorkspaceFocusDisposition(
                sourceWorkspaceID: sourceWorkspaceID,
                requestedWorkspaceID: workspaceID,
                keepsOnAllWorkspaces: rule.keepsOnAllWorkspaces,
                configuredFollow: self.focusFollowsMovedWindow,
                followOverride: followOverride
            )
            guard disposition != .unchangedVisible else {
                self.diagnostics.log(
                    category: "move-window",
                    event: "ignored",
                    correlation: correlationID,
                    fields: [
                        "window": Self.diagnosticWindowKey(focusedKey),
                        "reason": disposition.rawValue,
                        "source-workspace": Self.shortIdentifier(sourceWorkspaceID.uuidString),
                    ]
                )
                return
            }
            let effectiveWorkspaceID = workspaceID
            guard effectiveWorkspaceID != sourceWorkspaceID else { return }

            let replacementOrder: [WindowKey]
            if disposition == .sendOnly {
                let ordered = self.orderedMoveReplacementCandidates(
                    workspaceID: sourceWorkspaceID,
                    interactionDisplayIdentifier: interactionDisplay.identifier,
                    displays: displays,
                    correlationID: correlationID
                )
                replacementOrder = Self.moveReplacementFocusOrder(
                    movingWindow: focusedKey,
                    lastFocusedWindow: self.lastFocusedWindow[sourceWorkspaceID],
                    orderedCandidates: ordered
                )
            } else {
                replacementOrder = []
            }
            let expectedFocus = disposition == .follow ? focusedKey : replacementOrder.first
            let verificationToken = self.beginCorrelatedAction(
                correlationID: correlationID,
                interactionDisplayIdentifier: interactionDisplay.identifier,
                expectedFocusTarget: expectedFocus
            )

            let destinationDisplayIdentifier = self.displayMode == .independent
                ? self.workspaceHomeDisplayIdentifier(for: effectiveWorkspaceID, displays: displays)
                : interactionDisplay.identifier
            self.diagnostics.log(
                category: "move-window",
                event: "begin",
                correlation: correlationID,
                fields: [
                    "window": Self.diagnosticWindowKey(focusedKey),
                    "disposition": disposition.rawValue,
                    "source-workspace": Self.shortIdentifier(sourceWorkspaceID.uuidString),
                    "destination-workspace": Self.shortIdentifier(effectiveWorkspaceID.uuidString),
                    "source-display": Self.shortIdentifier(interactionDisplay.identifier),
                    "destination-display": Self.shortIdentifier(destinationDisplayIdentifier),
                    "replacement-order": replacementOrder.map(Self.diagnosticWindowKey).joined(separator: ","),
                ]
            )

            if let frame = AccessibilityWindow.frame(of: tracked.element), self.isWorkspaceActive(tracked.workspaceID) {
                if self.workspaceLayout(for: tracked.workspaceID) == .none ||
                    !Self.layoutDecision(
                        layoutOverride: tracked.layoutOverride,
                        admissionDecision: tracked.admissionDecision,
                        rule: rule
                    ).includesInLayout {
                    tracked.restoreFrame = frame
                    tracked.displayPlacement = Self.displayPlacement(for: frame, displays: displays)
                }
            }
            tracked.workspaceID = effectiveWorkspaceID
            tracked.workspaceRuleOverrideActive = Self.manualWorkspaceRuleOverrideIsActive(
                assignedWorkspaceID: rule.assignedWorkspaceID,
                requestedWorkspaceID: effectiveWorkspaceID
            )
            tracked.layoutOrder = self.nextLayoutOrder(in: effectiveWorkspaceID)
            tracked.layoutWeight = 1
            self.windows[focusedKey] = tracked
            if self.lastFocusedWindow[sourceWorkspaceID] == focusedKey {
                self.lastFocusedWindow.removeValue(forKey: sourceWorkspaceID)
            }

            if disposition == .follow {
                self.activateMovedWindowDestination(
                    sourceWorkspaceID: sourceWorkspaceID,
                    destinationWorkspaceID: effectiveWorkspaceID,
                    destinationDisplayIdentifier: destinationDisplayIdentifier,
                    displays: displays,
                    correlationID: correlationID
                )
                self.lastFocusedWindow[effectiveWorkspaceID] = focusedKey
                self.recentInteractionDisplayIdentifier = destinationDisplayIdentifier
                self.recentInteractionFocusTarget = focusedKey
                self.recentInteractionDisplayDeadline = Date().addingTimeInterval(1.75)
                self.attemptFocusCycleCandidate(
                    attemptOrder: [focusedKey],
                    candidateIndex: 0,
                    phase: .initial,
                    originalFocus: nil,
                    workspaceID: effectiveWorkspaceID,
                    interactionDisplayIdentifier: destinationDisplayIdentifier,
                    displays: displays,
                    correlationID: correlationID,
                    token: verificationToken
                )
            } else {
                self.staleParkedFocusSuppression[focusedKey] = Date().addingTimeInterval(1.5)
                if Self.shouldWindowBeVisible(
                    workspaceID: effectiveWorkspaceID,
                    activeWorkspaceIDs: self.activeWorkspaceIDs,
                    rule: rule
                ) {
                    self.applyVisibleWindows(
                        self.windows.values.filter { $0.workspaceID == effectiveWorkspaceID },
                        displays: displays,
                        correlationID: correlationID
                    )
                } else {
                    self.applyPositionChanges(
                        [PositionChange(window: tracked, position: self.parkingPosition(displays: displays))],
                        correlationID: correlationID
                    )
                }
                if self.isWorkspaceActive(sourceWorkspaceID),
                   self.workspaceLayout(for: sourceWorkspaceID) != .none {
                    self.applyVisibleWindows(
                        self.windows.values.filter { $0.workspaceID == sourceWorkspaceID },
                        displays: displays,
                        correlationID: correlationID
                    )
                }
                if !replacementOrder.isEmpty {
                    self.attemptFocusCycleCandidate(
                        attemptOrder: replacementOrder,
                        candidateIndex: 0,
                        phase: .initial,
                        originalFocus: nil,
                        workspaceID: sourceWorkspaceID,
                        interactionDisplayIdentifier: interactionDisplay.identifier,
                        displays: displays,
                        correlationID: correlationID,
                        token: verificationToken
                    )
                } else {
                    self.clearFocusStateAfterSendOnlyMove(
                        movingWindow: focusedKey,
                        tracked: tracked,
                        sourceWorkspaceID: sourceWorkspaceID,
                        interactionDisplayIdentifier: interactionDisplay.identifier,
                        correlationID: correlationID
                    )
                }
            }
            self.persistState(preservingPendingRestores: true)
            self.emitState()
            self.lastBackgroundLayoutSignature = self.backgroundLayoutSignature(displays: displays)
            self.diagnostics.log(
                category: "move-window",
                event: "complete",
                correlation: correlationID,
                fields: [
                    "disposition": disposition.rawValue,
                    "replacement": replacementOrder.first.map(Self.diagnosticWindowKey) ?? "none",
                    "active-after": self.diagnosticActiveWorkspaceMap(),
                ]
            )
        }
    }

    static func moveWorkspaceFocusDisposition(
        sourceWorkspaceID: UUID,
        requestedWorkspaceID: UUID,
        keepsOnAllWorkspaces: Bool,
        configuredFollow: Bool,
        followOverride: Bool?
    ) -> MoveWorkspaceFocusDisposition {
        if requestedWorkspaceID == sourceWorkspaceID || keepsOnAllWorkspaces {
            return .unchangedVisible
        }
        return (followOverride ?? configuredFollow) ? .follow : .sendOnly
    }

    static func manualWorkspaceRuleOverrideIsActive(
        assignedWorkspaceID: UUID?,
        requestedWorkspaceID: UUID
    ) -> Bool {
        assignedWorkspaceID.map { $0 != requestedWorkspaceID } ?? false
    }

    static func workspaceIDAfterRuleRefresh(
        currentWorkspaceID: UUID,
        assignedWorkspaceID: UUID?,
        manualOverrideActive: Bool
    ) -> UUID {
        guard !manualOverrideActive else { return currentWorkspaceID }
        return assignedWorkspaceID ?? currentWorkspaceID
    }

    static func moveReplacementFocusOrder<T: Equatable>(
        movingWindow: T,
        lastFocusedWindow: T?,
        orderedCandidates: [T]
    ) -> [T] {
        let anchor: T? = orderedCandidates.contains(movingWindow)
            ? movingWindow
            : lastFocusedWindow.flatMap { orderedCandidates.contains($0) ? $0 : nil }
        return focusCycleAttemptOrder(
            current: anchor,
            orderedCandidates: orderedCandidates,
            offset: 1
        ).filter { $0 != movingWindow }
    }

    static func moveReplacementCandidateIsEligible(
        workspaceMatches: Bool,
        visible: Bool,
        meaningfullyVisible: Bool,
        displayMatches: Bool,
        focusEligible: Bool
    ) -> Bool {
        workspaceMatches && visible && meaningfullyVisible && displayMatches && focusEligible
    }

    static func staleParkedFocusObservationIsSuppressed<T: Hashable>(
        focusedWindow: T?,
        suppressedWindows: Set<T>
    ) -> Bool {
        focusedWindow.map(suppressedWindows.contains) == true
    }

    static func parkedFocusActivationDisposition(
        allowExplicitActivationAfter: Date?,
        now: Date
    ) -> ParkedFocusActivationDisposition {
        guard let allowExplicitActivationAfter else { return .unaffected }
        return now < allowExplicitActivationAfter
            ? .suppressStaleActivation
            : .acceptExplicitActivation
    }

    static func directionalCandidateOrder<Key: Hashable>(
        from source: CGRect,
        direction: WindowDirection,
        candidates: [DirectionalWindowCandidate<Key>],
        prefersFarthestPrimaryDistance: Bool = false
    ) -> [Key] {
        let sourceCenter = CGPoint(x: source.midX, y: source.midY)
        return candidates.enumerated().compactMap { index, candidate -> (Key, Int, CGFloat, CGFloat, Int)? in
            let target = candidate.frame
            let targetCenter = CGPoint(x: target.midX, y: target.midY)
            let primaryDistance: CGFloat
            let orthogonalDistance: CGFloat
            let orthogonalGap: CGFloat
            switch direction {
            case .left:
                guard targetCenter.x < sourceCenter.x - 0.5 else { return nil }
                primaryDistance = sourceCenter.x - targetCenter.x
                orthogonalDistance = abs(targetCenter.y - sourceCenter.y)
                orthogonalGap = max(0, max(source.minY - target.maxY, target.minY - source.maxY))
            case .right:
                guard targetCenter.x > sourceCenter.x + 0.5 else { return nil }
                primaryDistance = targetCenter.x - sourceCenter.x
                orthogonalDistance = abs(targetCenter.y - sourceCenter.y)
                orthogonalGap = max(0, max(source.minY - target.maxY, target.minY - source.maxY))
            case .up:
                guard targetCenter.y < sourceCenter.y - 0.5 else { return nil }
                primaryDistance = sourceCenter.y - targetCenter.y
                orthogonalDistance = abs(targetCenter.x - sourceCenter.x)
                orthogonalGap = max(0, max(source.minX - target.maxX, target.minX - source.maxX))
            case .down:
                guard targetCenter.y > sourceCenter.y + 0.5 else { return nil }
                primaryDistance = targetCenter.y - sourceCenter.y
                orthogonalDistance = abs(targetCenter.x - sourceCenter.x)
                orthogonalGap = max(0, max(source.minX - target.maxX, target.minX - source.maxX))
            }
            return (candidate.key, orthogonalGap > 0 ? 1 : 0, primaryDistance, orthogonalDistance, index)
        }.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            if lhs.2 != rhs.2 {
                return prefersFarthestPrimaryDistance ? lhs.2 > rhs.2 : lhs.2 < rhs.2
            }
            if lhs.3 != rhs.3 { return lhs.3 < rhs.3 }
            return lhs.4 < rhs.4
        }.map(\.0)
    }

    /// Uses the nearest spatial neighbour normally. At an outer edge, continue from the opposite
    /// edge while retaining perpendicular-axis alignment as the first ranking criterion.
    static func wrappingDirectionalCandidateOrder<Key: Hashable>(
        from source: CGRect,
        direction: WindowDirection,
        candidates: [DirectionalWindowCandidate<Key>]
    ) -> (candidates: [Key], didWrap: Bool) {
        let direct = directionalCandidateOrder(
            from: source,
            direction: direction,
            candidates: candidates
        )
        guard direct.isEmpty else { return (direct, false) }
        let oppositeDirection: WindowDirection = switch direction {
        case .left: .right
        case .right: .left
        case .up: .down
        case .down: .up
        }
        let wrapped = directionalCandidateOrder(
            from: source,
            direction: oppositeDirection,
            candidates: candidates,
            prefersFarthestPrimaryDistance: true
        )
        return (wrapped, !wrapped.isEmpty)
    }

    static func availableShelfFocusDirections<Key: Hashable>(
        from source: CGRect,
        candidates: [DirectionalWindowCandidate<Key>],
        shelfDirection: DropDownAppDirection
    ) -> Set<WindowDirection> {
        Set(WindowDirection.allCases.filter { direction in
            QuickAppInteractionPolicy.directionalFocusUsesShelfAxis(
                direction,
                shelfDirection: shelfDirection
            ) && !wrappingDirectionalCandidateOrder(
                from: source,
                direction: direction,
                candidates: candidates
            ).candidates.isEmpty
        })
    }

    /// Changes only the focused leaf's nearest split. This keeps a nested top/bottom placement from
    /// also changing its outer left/right allocation while still updating fallback leaf shares.
    static func smartResizedTiledState(
        tree: TiledNode,
        participants: [WindowKey],
        focusedIndex: Int,
        deltaPoints: Double,
        displayBounds: CGRect,
        configuration: WorkspaceLayoutConfiguration
    ) -> (tree: TiledNode, weights: [Double])? {
        guard Set(participants).count == participants.count,
              participants.indices.contains(focusedIndex),
              Set(tree.windowKeys) == Set(participants)
        else { return nil }
        guard let resizedTree = TiledLayoutEngine.resizedNearestSplit(
            tree,
            focusedWindow: participants[focusedIndex],
            deltaPoints: deltaPoints,
            displayBounds: displayBounds,
            configuration: configuration
        ), let effectiveShares = TiledLayoutEngine.leafShares(resizedTree)
        else { return nil }
        return (
            resizedTree,
            participants.map { effectiveShares[$0] ?? 0 }
        )
    }

    /// First interprets one arrow structurally: when the focused leaf directly borders a sibling
    /// branch on that axis, exchange the leaf with that complete branch. Only when no such direct
    /// split boundary exists does the command fall back to exchanging the closest visual leaves.
    /// This preserves a compound sibling's topology while retaining useful movement through mixed-
    /// axis trees.
    static func directionallyReorderedTiledState(
        tree: TiledNode,
        focusedWindow: WindowKey,
        direction: WindowDirection,
        displayBounds: CGRect,
        configuration: WorkspaceLayoutConfiguration
    ) -> (
        tree: TiledNode,
        destinationWindow: WindowKey,
        effectiveShares: [WindowKey: Double],
        strategy: TiledDirectionalMoveStrategy
    )? {
        let participants = tree.windowKeys
        guard Set(participants).count == participants.count,
              participants.contains(focusedWindow),
              (try? TiledLayoutEngine.validated(tree, participants: Set(participants))) != nil,
              let frames = try? TiledLayoutEngine.frames(
                  for: tree,
                  in: displayBounds,
                  configuration: configuration
              ),
              let focusedFrame = frames[focusedWindow]
        else { return nil }
        let candidates = participants.compactMap { key -> DirectionalWindowCandidate<WindowKey>? in
            guard key != focusedWindow, let frame = frames[key] else { return nil }
            return DirectionalWindowCandidate(
                key: key,
                frame: CGRect(origin: frame.position, size: frame.size)
            )
        }
        let focusedRect = CGRect(origin: focusedFrame.position, size: focusedFrame.size)

        if let structural = TiledLayoutEngine.swappingFocusedLeafWithDirectSiblingBranch(
            focusedWindow,
            direction: direction,
            in: tree
        ), let effectiveShares = TiledLayoutEngine.leafShares(structural.tree) {
            let siblingCandidates = candidates.filter { structural.siblingWindowKeys.contains($0.key) }
            let representative = directionalCandidateOrder(
                from: focusedRect,
                direction: direction,
                candidates: siblingCandidates
            ).first ?? structural.siblingWindowKeys.first
            guard let representative else { return nil }
            return (structural.tree, representative, effectiveShares, .directSiblingBranch)
        }

        // Prefer a leaf that actually overlaps the focused leaf on the perpendicular axis. In a
        // nested tree, a full-height sibling can merely touch the focused column's edge and have a
        // closer centre than the true top/bottom neighbour; treating that corner contact as aligned
        // would move the window into the wrong branch.
        let axisAlignedCandidates = candidates.filter { candidate in
            switch direction {
            case .left, .right:
                return min(focusedRect.maxY, candidate.frame.maxY)
                    - max(focusedRect.minY, candidate.frame.minY) > 0.5
            case .up, .down:
                return min(focusedRect.maxX, candidate.frame.maxX)
                    - max(focusedRect.minX, candidate.frame.minX) > 0.5
            }
        }
        let selectionPool = axisAlignedCandidates.isEmpty ? candidates : axisAlignedCandidates
        guard let destination = directionalCandidateOrder(
            from: focusedRect,
            direction: direction,
            candidates: selectionPool
        ).first,
              let reordered = TiledLayoutEngine.swappingWindows(
                  focusedWindow,
                  destination,
                  in: tree
              ),
              let effectiveShares = TiledLayoutEngine.leafShares(reordered)
        else { return nil }
        return (reordered, destination, effectiveShares, .visualNeighbourLeaf)
    }

    static func adjustedAccordionPadding(
        current: Double,
        delta: Double,
        availableLength: Double
    ) -> Double? {
        guard current.isFinite, delta.isFinite, delta != 0, availableLength > 1 else { return nil }
        let adjusted = min(max(0, current + delta), min(800, (availableLength - 1) / 2))
        return abs(adjusted - current) > 0.000_001 ? adjusted : nil
    }

    static func reorderDestinationIndex(
        sourceIndex: Int,
        count: Int,
        direction: WindowDirection,
        orientation: WorkspaceLayoutOrientation
    ) -> Int? {
        guard count > 1,
              (0..<count).contains(sourceIndex),
              direction.axis == orientation
        else { return nil }
        let destination = sourceIndex + direction.orderOffset
        return (0..<count).contains(destination) ? destination : nil
    }

    private func orderedMoveReplacementCandidates(
        workspaceID: UUID,
        interactionDisplayIdentifier: String,
        displays: [DisplaySnapshot],
        correlationID: String
    ) -> [WindowKey] {
        let layout = workspaceLayout(for: workspaceID)
        let now = Date()
        focusCycleRejectedUntil = focusCycleRejectedUntil.filter { $0.value > now }
        return windows.compactMap { key, tracked -> (WindowKey, WindowFrame)? in
            guard !isDropDownAppWindow(key),
                  !isExcludedFromWorkspaceParticipation(tracked)
            else { return nil }
            let rule = resolvedRule(for: tracked.bundleIdentifier)
            let workspaceMatches = tracked.workspaceID == workspaceID || rule.keepsOnAllWorkspaces
            let visible = Self.shouldWindowBeVisible(
                workspaceID: tracked.workspaceID,
                activeWorkspaceIDs: activeWorkspaceIDs,
                rule: rule
            )
            let frame = AccessibilityWindow.frame(of: tracked.element)
            let meaningfullyVisible = frame.map { Self.isMeaningfullyVisible($0, displays: displays) } == true
            let displayIdentifier = frame.flatMap {
                Self.displayPlacement(for: $0, displays: displays)?.displayIdentifier
            }
            let displayMatches = Self.focusCycleCandidateIsInScope(
                candidateDisplayIdentifier: displayIdentifier,
                interactionDisplayIdentifier: interactionDisplayIdentifier
            )
            let capabilities = AccessibilityWindow.focusCapabilities(
                of: tracked.element,
                processIdentifier: tracked.processIdentifier,
                windowIdentifier: key.windowIdentifier
            )
            let focusEligible = AccessibilityWindow.isEligibleFocusCycleCandidate(capabilities) &&
                focusCycleRejectedUntil[key] == nil
            let eligible = Self.moveReplacementCandidateIsEligible(
                workspaceMatches: workspaceMatches,
                visible: visible,
                meaningfullyVisible: meaningfullyVisible,
                displayMatches: displayMatches,
                focusEligible: focusEligible
            )
            diagnostics.log(
                category: "move-window",
                event: "replacement-candidate",
                correlation: correlationID,
                fields: [
                    "window": Self.diagnosticWindowKey(key),
                    "workspace": Self.shortIdentifier(tracked.workspaceID.uuidString),
                    "display": displayIdentifier.map(Self.shortIdentifier) ?? "unknown",
                    "workspace-match": String(workspaceMatches),
                    "visible": String(visible),
                    "meaningfully-visible": String(meaningfullyVisible),
                    "display-match": String(displayMatches),
                    "focus-eligible": String(focusEligible),
                    "layout-decision": Self.layoutDecision(
                        layoutOverride: tracked.layoutOverride,
                        admissionDecision: tracked.admissionDecision,
                        rule: rule
                    ).rawValue,
                    "included": String(eligible),
                ]
            )
            guard eligible, let frame else { return nil }
            return (key, frame)
        }.sorted { lhs, rhs in
            if layout == .none {
                if lhs.1.position.y != rhs.1.position.y { return lhs.1.position.y < rhs.1.position.y }
                if lhs.1.position.x != rhs.1.position.x { return lhs.1.position.x < rhs.1.position.x }
            }
            if lhs.0.processIdentifier != rhs.0.processIdentifier {
                return lhs.0.processIdentifier < rhs.0.processIdentifier
            }
            return lhs.0.windowIdentifier < rhs.0.windowIdentifier
        }.map(\.0)
    }

    private func directionalFocusCandidates(
        workspaceID: UUID,
        interactionDisplayIdentifier: String,
        displays: [DisplaySnapshot],
        correlationID: String?
    ) -> [DirectionalWindowCandidate<WindowKey>] {
        windows.compactMap { key, tracked in
            guard !isDropDownAppWindow(key),
                  !isExcludedFromWorkspaceParticipation(tracked)
            else { return nil }
            let rule = resolvedRule(for: tracked.bundleIdentifier)
            let workspaceMatches = tracked.workspaceID == workspaceID || rule.keepsOnAllWorkspaces
            let visible = Self.shouldWindowBeVisible(
                workspaceID: tracked.workspaceID,
                activeWorkspaceIDs: activeWorkspaceIDs,
                rule: rule
            )
            guard let frame = AccessibilityWindow.frame(of: tracked.element) else { return nil }
            let meaningfullyVisible = Self.isMeaningfullyVisible(frame, displays: displays)
            let displayIdentifier = Self.displayPlacement(for: frame, displays: displays)?.displayIdentifier
            let displayMatches = displayIdentifier == interactionDisplayIdentifier
            let capabilities = AccessibilityWindow.focusCapabilities(
                of: tracked.element,
                processIdentifier: tracked.processIdentifier,
                windowIdentifier: key.windowIdentifier
            )
            let focusEligible = AccessibilityWindow.isEligibleFocusCycleCandidate(capabilities)
            let eligible = Self.moveReplacementCandidateIsEligible(
                workspaceMatches: workspaceMatches,
                visible: visible,
                meaningfullyVisible: meaningfullyVisible,
                displayMatches: displayMatches,
                focusEligible: focusEligible
            )
            if correlationID != nil {
                diagnostics.log(
                    category: "directional-focus",
                    event: "candidate",
                    correlation: correlationID,
                    fields: [
                        "window": Self.diagnosticWindowKey(key),
                        "workspace": Self.shortIdentifier(tracked.workspaceID.uuidString),
                        "display": displayIdentifier.map(Self.shortIdentifier) ?? "unknown",
                        "floating-state": Self.layoutDecision(
                            layoutOverride: tracked.layoutOverride,
                            admissionDecision: tracked.admissionDecision,
                            rule: rule
                        ).rawValue,
                        "included": String(eligible),
                    ]
                )
            }
            guard eligible else { return nil }
            return DirectionalWindowCandidate(
                key: key,
                frame: CGRect(origin: frame.position, size: frame.size)
            )
        }.sorted { lhs, rhs in
            let leftOrder = windows[lhs.key]?.layoutOrder ?? Int.max
            let rightOrder = windows[rhs.key]?.layoutOrder ?? Int.max
            if leftOrder != rightOrder { return leftOrder < rightOrder }
            if lhs.key.processIdentifier != rhs.key.processIdentifier {
                return lhs.key.processIdentifier < rhs.key.processIdentifier
            }
            return lhs.key.windowIdentifier < rhs.key.windowIdentifier
        }
    }

    /// Holds a position-only tiled drag in place while the pointer button is down, then moves the
    /// focused leaf to the directional destination under the release point. Returning true tells
    /// the refresh loop not to run its normal corrective layout pass during the active drag.
    private func reconcileManualTiledMove(
        focusedWindow: WindowKey,
        observedFrames: [WindowKey: WindowFrame],
        displays: [DisplaySnapshot],
        pointerLocation: CGPoint?,
        isLeftMouseButtonPressed: Bool,
        correlationID: String?
    ) -> ManualTiledMoveReconciliation {
        guard let tracked = windows[focusedWindow],
              let observedFrame = observedFrames[focusedWindow],
              isWorkspaceActive(tracked.workspaceID),
              workspaceLayout(for: tracked.workspaceID) == .tiled,
              fullscreenSessions[focusedWindow] == nil,
              !temporarilyDeferredWindowKeys.contains(focusedWindow),
              Self.shouldIncludeInLayout(
                  layoutOverride: tracked.layoutOverride,
                  admissionDecision: tracked.admissionDecision,
                  rule: resolvedRule(for: tracked.bundleIdentifier)
              ),
              let display = targetDisplay(
                  for: tracked,
                  workspaceID: tracked.workspaceID,
                  displays: displays,
                  correlationID: correlationID
              )
        else {
            manualTiledDragSession = nil
            return .none
        }

        let participants = orderedLayoutParticipants(
            workspaceID: tracked.workspaceID,
            displayIdentifier: display.identifier,
            displays: displays,
            correlationID: correlationID
        )
        let configuration = workspaceLayoutConfiguration(for: tracked.workspaceID)
            ?? .aeroSpaceUserDefaults
        let managedBounds = managedLayoutBounds(display.usableBounds)
        let partition = TiledLayoutPartitionKey(
            workspaceID: tracked.workspaceID,
            displayIdentifier: display.identifier
        )
        let previousDestination = manualTiledDragSession.flatMap { prior in
            prior.focusedWindow == focusedWindow && prior.partition == partition
                ? prior.candidateDestination
                : nil
        }
        guard participants.count > 1,
              participants.contains(focusedWindow),
              let currentTree = TiledLayoutEngine.reconciled(
                  tiledTrees[partition],
                  windowKeys: participants,
                  weights: participants.map {
                      CGFloat(Self.validLayoutWeight(windows[$0]?.layoutWeight))
                  },
                  orientation: configuration.orientation.resolved(for: managedBounds)
              ), let expectedFrames = try? TiledLayoutEngine.frames(
                  for: currentTree,
                  in: managedBounds,
                  configuration: configuration
              ), let expectedFocusedFrame = expectedFrames[focusedWindow],
              let lastSolvedFrame = lastSolvedTiledFrames[focusedWindow],
              AccessibilityWindow.framesMatch(lastSolvedFrame, expectedFocusedFrame),
              let drag = TiledLayoutEngine.observedDrag(
                  in: currentTree,
                  focusedWindow: focusedWindow,
                  observedFrame: observedFrame,
                  pointerLocation: pointerLocation,
                  expectedFrames: expectedFrames,
                  previousDestination: previousDestination
              )
        else {
            if !isLeftMouseButtonPressed {
                manualTiledDragSession = nil
            }
            return .none
        }

        let session = ManualTiledDragSession(
            focusedWindow: focusedWindow,
            partition: partition,
            candidateDestination: drag.destination
        )
        if isLeftMouseButtonPressed {
            if manualTiledDragSession != session {
                diagnostics.log(
                    category: "manual-move",
                    event: "drag-candidate",
                    correlation: correlationID,
                    fields: [
                        "workspace": Self.shortIdentifier(tracked.workspaceID.uuidString),
                        "display": Self.shortIdentifier(display.identifier),
                        "window": Self.diagnosticWindowKey(focusedWindow),
                        "target": drag.destination.map {
                            Self.diagnosticWindowKey($0.target)
                        } ?? "none",
                        "placement": drag.destination?.placement.rawValue ?? "none",
                    ]
                )
            }
            manualTiledDragSession = session
            return .dragInProgress
        }

        let priorSession = manualTiledDragSession
        manualTiledDragSession = nil
        let destination = drag.destination ?? (pointerLocation == nil &&
            priorSession?.focusedWindow == focusedWindow &&
            priorSession?.partition == partition
                ? priorSession?.candidateDestination
                : nil)
        guard let destination,
              participants.contains(destination.target),
              let movedTree = TiledLayoutEngine.movingWindow(
                  focusedWindow,
                  to: destination,
                  in: currentTree
              ), let movedFrames = try? TiledLayoutEngine.frames(
                  for: movedTree,
                  in: managedBounds,
                  configuration: configuration
              ), destination.placement == .swap ||
                TiledLayoutEngine.accommodatesMinimumWindowLength(movedFrames),
              let effectiveShares = TiledLayoutEngine.leafShares(movedTree)
        else { return .none }

        tiledTrees[partition] = movedTree
        for (index, key) in movedTree.windowKeys.enumerated() {
            windows[key]?.layoutOrder = index
            windows[key]?.layoutWeight = effectiveShares[key] ?? 1
        }
        lastFocusedWindow[tracked.workspaceID] = focusedWindow
        radialPlacementCommitContext = nil
        radialFreeformPlacementCommitContext = nil
        directionalMoveGestureContext = nil
        lastBackgroundLayoutSignature = nil
        diagnostics.log(
            category: "manual-move",
            event: "window-moved",
            correlation: correlationID,
            fields: [
                "workspace": Self.shortIdentifier(tracked.workspaceID.uuidString),
                "display": Self.shortIdentifier(display.identifier),
                "window": Self.diagnosticWindowKey(focusedWindow),
                "target": Self.diagnosticWindowKey(destination.target),
                "placement": destination.placement.rawValue,
                "tree-before": TiledLayoutEngine.fingerprint(currentTree),
                "tree-after": TiledLayoutEngine.fingerprint(movedTree),
            ]
        )
        return .moved
    }

    /// Pointer delivery is intentionally separate from the broad discovery timer. Tiled move and
    /// resize previews need to follow the gesture promptly, while discovery remains deliberately
    /// coarse to avoid continuously enumerating every application window.
    func tiledResizePointerDragged() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.manualTiledMovePreviewSession != nil {
                self.updateManualTiledMoveLandingPreview()
            } else if self.manualTiledResizeSession != nil {
                self.updateManualTiledResizePreview()
            } else {
                self.updateManualTiledMovePreview()
                if self.manualTiledMovePreviewSession == nil {
                    self.updateManualTiledResizePreview()
                }
            }
        }
    }

    func tiledResizePointerReleased() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.manualTiledMovePreviewSession != nil {
                self.commitManualTiledMovePreview()
            } else if self.manualTiledResizeSession != nil {
                self.commitManualTiledResizePreview()
            }
        }
    }

    private func commitManualTiledResizePreview() {
            guard var session = manualTiledResizeSession else { return }
            let correlationID = "manual-resize-\(session.token.uuidString.prefix(8))"

            // Capture the final pointer position because a throttled drag event can precede the
            // mouse-up by one render interval.
            updateManualTiledResizePreview(allowStartingSession: false)
            guard let updatedSession = manualTiledResizeSession else { return }
            session = updatedSession

            let displays = Self.activeDisplays()
            guard !isWindowManagementPaused,
                  !wakeReconciliationState.isSleeping,
                  !wakeReconciliationState.isPending,
                  windowServerSessionValidated,
                  currentProfileID == session.profileID,
                  Self.displayTopologySignature(displays) == session.topologySignature,
                  tiledTrees[session.partition] == session.originalTree,
                  let tracked = windows[session.focusedWindow],
                  isWorkspaceActive(tracked.workspaceID),
                  workspaceLayout(for: tracked.workspaceID) == .tiled,
                  fullscreenSessions[session.focusedWindow] == nil,
                  !isQuickAppShelfPresented,
                  let display = displays.first(where: {
                      $0.identifier == session.partition.displayIdentifier
                  })
            else {
                cancelManualTiledResizePreview(reason: "release-validation-failed")
                return
            }

            let currentConfiguration = workspaceLayoutConfiguration(for: tracked.workspaceID)
                ?? .aeroSpaceUserDefaults
            guard currentConfiguration == session.configuration,
                  managedLayoutBounds(display.usableBounds) == session.layoutBounds,
                  Self.shouldIncludeInLayout(
                      layoutOverride: tracked.layoutOverride,
                      admissionDecision: tracked.admissionDecision,
                      rule: resolvedRule(for: tracked.bundleIdentifier)
                  )
            else {
                cancelManualTiledResizePreview(reason: "layout-configuration-changed")
                return
            }

            let participants = orderedLayoutParticipants(
                workspaceID: tracked.workspaceID,
                displayIdentifier: display.identifier,
                displays: displays,
                correlationID: correlationID
            )
            guard Set(participants) == session.participantKeys,
                  let effectiveShares = TiledLayoutEngine.leafShares(session.proposedTree)
            else {
                cancelManualTiledResizePreview(reason: "participants-changed")
                return
            }

            manualTiledResizeSession = nil
            tiledTrees[session.partition] = session.proposedTree
            for key in participants {
                windows[key]?.layoutWeight = effectiveShares[key] ?? 1
            }
            radialPlacementCommitContext = nil
            radialFreeformPlacementCommitContext = nil
            directionalMoveGestureContext = nil
            manualTiledDragSession = nil

            let changes = participants.compactMap { key -> FrameChange? in
                guard let window = windows[key], let frame = session.proposedFrames[key] else {
                    return nil
                }
                lastSolvedTiledFrames[key] = frame
                return FrameChange(window: window, frame: frame)
            }
            applyFrameChanges(changes, correlationID: correlationID)
            lastBackgroundLayoutSignature = backgroundLayoutSignature(displays: displays)
            persistState(preservingPendingRestores: true)
            diagnostics.log(
                category: "manual-resize-preview",
                event: "committed",
                correlation: correlationID,
                fields: [
                    "workspace": Self.shortIdentifier(tracked.workspaceID.uuidString),
                    "display": Self.shortIdentifier(display.identifier),
                    "window": Self.diagnosticWindowKey(session.focusedWindow),
                    "window-count": String(participants.count),
                    "tree-before": TiledLayoutEngine.fingerprint(session.originalTree),
                    "tree-after": TiledLayoutEngine.fingerprint(session.proposedTree),
                ]
            )
            emitTiledResizePreviewEvent(
                .dismiss(token: session.token, reason: "committed")
            )
    }

    private func updateManualTiledMovePreview() {
        guard manualTiledMovePreviewSession == nil,
              manualTiledResizeSession == nil,
              !isWindowManagementPaused,
              !wakeReconciliationState.isSleeping,
              !wakeReconciliationState.isPending,
              windowServerSessionValidated,
              !isQuickAppShelfPresented,
              let focused = focusedWindowSnapshot(),
              let observedFrame = focused.frame,
              let tracked = windows[focused.key],
              isWorkspaceActive(tracked.workspaceID),
              workspaceLayout(for: tracked.workspaceID) == .tiled,
              fullscreenSessions[focused.key] == nil,
              !temporarilyDeferredWindowKeys.contains(focused.key),
              Self.shouldIncludeInLayout(
                  layoutOverride: tracked.layoutOverride,
                  admissionDecision: tracked.admissionDecision,
                  rule: resolvedRule(for: tracked.bundleIdentifier)
              )
        else { return }

        let displays = Self.activeDisplays()
        guard let display = targetDisplay(
            for: tracked,
            workspaceID: tracked.workspaceID,
            displays: displays,
            correlationID: nil
        ) else { return }
        let participants = orderedLayoutParticipants(
            workspaceID: tracked.workspaceID,
            displayIdentifier: display.identifier,
            displays: displays,
            correlationID: nil
        )
        let configuration = workspaceLayoutConfiguration(for: tracked.workspaceID)
            ?? .aeroSpaceUserDefaults
        let layoutBounds = managedLayoutBounds(display.usableBounds)
        let partition = TiledLayoutPartitionKey(
            workspaceID: tracked.workspaceID,
            displayIdentifier: display.identifier
        )
        guard participants.count > 1,
              participants.contains(focused.key),
              let originalTree = TiledLayoutEngine.reconciled(
                  tiledTrees[partition],
                  windowKeys: participants,
                  weights: participants.map {
                      CGFloat(Self.validLayoutWeight(windows[$0]?.layoutWeight))
                  },
                  orientation: configuration.orientation.resolved(for: layoutBounds)
              ),
              let originalFrames = try? TiledLayoutEngine.frames(
                  for: originalTree,
                  in: layoutBounds,
                  configuration: configuration
              ),
              let expectedFocusedFrame = originalFrames[focused.key],
              let lastSolvedFrame = lastSolvedTiledFrames[focused.key],
              AccessibilityWindow.framesMatch(lastSolvedFrame, expectedFocusedFrame),
              let pointer = CGEvent(source: nil)?.location,
              TiledManualDragClassifier.classify(
                  expectedFrame: expectedFocusedFrame,
                  observedFrame: observedFrame,
                  pointer: pointer
              ) == .move,
              TiledLayoutEngine.observedDrag(
                  in: originalTree,
                  focusedWindow: focused.key,
                  observedFrame: observedFrame,
                  pointerLocation: pointer,
                  expectedFrames: originalFrames,
                  requiresStableSize: false
              ) != nil
        else { return }

        let token = UUID()
        let session = ManualTiledMovePreviewSession(
            token: token,
            focusedWindow: focused.key,
            partition: partition,
            participantKeys: Set(participants),
            originalTree: originalTree,
            originalFrames: originalFrames,
            configuration: configuration,
            layoutBounds: layoutBounds,
            topologySignature: Self.displayTopologySignature(displays),
            profileID: currentProfileID,
            candidateDestination: nil,
            proposedTree: originalTree,
            proposedFrames: originalFrames
        )
        manualTiledMovePreviewSession = session
        manualTiledDragSession = nil
        let correlationID = "manual-move-\(token.uuidString.prefix(8))"
        diagnostics.log(
            category: "manual-move-preview",
            event: "started",
            correlation: correlationID,
            fields: [
                "workspace": Self.shortIdentifier(tracked.workspaceID.uuidString),
                "display": Self.shortIdentifier(display.identifier),
                "window": Self.diagnosticWindowKey(focused.key),
                "window-count": String(participants.count),
            ]
        )
        updateManualTiledMoveLandingPreview()
    }

    private func updateManualTiledMoveLandingPreview() {
        guard var session = manualTiledMovePreviewSession else { return }
        let correlationID = "manual-move-\(session.token.uuidString.prefix(8))"
        let displays = Self.activeDisplays()
        guard !isWindowManagementPaused,
              !wakeReconciliationState.isSleeping,
              !wakeReconciliationState.isPending,
              windowServerSessionValidated,
              !isQuickAppShelfPresented,
              currentProfileID == session.profileID,
              Self.displayTopologySignature(displays) == session.topologySignature,
              tiledTrees[session.partition] == session.originalTree,
              let tracked = windows[session.focusedWindow],
              isWorkspaceActive(tracked.workspaceID),
              workspaceLayout(for: tracked.workspaceID) == .tiled,
              fullscreenSessions[session.focusedWindow] == nil,
              !temporarilyDeferredWindowKeys.contains(session.focusedWindow),
              let display = displays.first(where: {
                  $0.identifier == session.partition.displayIdentifier
              }),
              (workspaceLayoutConfiguration(for: tracked.workspaceID)
                ?? .aeroSpaceUserDefaults) == session.configuration,
              managedLayoutBounds(display.usableBounds) == session.layoutBounds
        else {
            cancelManualTiledMovePreview(reason: "context-changed")
            return
        }
        let participants = orderedLayoutParticipants(
            workspaceID: tracked.workspaceID,
            displayIdentifier: display.identifier,
            displays: displays,
            correlationID: correlationID
        )
        guard Set(participants) == session.participantKeys,
              let pointer = CGEvent(source: nil)?.location
        else {
            cancelManualTiledMovePreview(reason: "participants-or-pointer-changed")
            return
        }

        let candidateDestination = TiledLayoutEngine.dragDestination(
            at: pointer,
            focusedWindow: session.focusedWindow,
            expectedFrames: session.originalFrames,
            previousDestination: session.candidateDestination
        )
        var destination = candidateDestination
        var proposedTree = candidateDestination.flatMap {
            TiledLayoutEngine.movingWindow(
                session.focusedWindow,
                to: $0,
                in: session.originalTree
            )
        } ?? session.originalTree
        guard var proposedFrames = try? TiledLayoutEngine.frames(
            for: proposedTree,
            in: session.layoutBounds,
            configuration: session.configuration
        ) else {
            cancelManualTiledMovePreview(reason: "proposal-invalid")
            return
        }
        if let candidate = destination, candidate.placement != .swap,
           !TiledLayoutEngine.accommodatesMinimumWindowLength(proposedFrames) {
            destination = nil
            proposedTree = session.originalTree
            proposedFrames = session.originalFrames
        }

        let destinationChanged = destination != session.candidateDestination
        session.candidateDestination = destination
        session.proposedTree = proposedTree
        session.proposedFrames = proposedFrames
        manualTiledMovePreviewSession = session
        if destinationChanged {
            if destination != nil, let landingFrame = proposedFrames[session.focusedWindow] {
                emitTiledResizePreviewEvent(.present(TiledResizePreviewPresentation(
                    token: session.token,
                    displayIdentifier: display.identifier,
                    layoutBounds: WindowFrame(
                        position: session.layoutBounds.origin,
                        size: session.layoutBounds.size
                    ),
                    frames: [session.focusedWindow: landingFrame],
                    transition: .animated,
                    role: .landing
                )))
            } else {
                emitTiledResizePreviewEvent(.dismiss(
                    token: session.token,
                    reason: "no-landing-target"
                ))
            }
            diagnostics.log(
                category: "manual-move-preview",
                event: "target-changed",
                correlation: correlationID,
                fields: [
                    "workspace": Self.shortIdentifier(tracked.workspaceID.uuidString),
                    "display": Self.shortIdentifier(display.identifier),
                    "window": Self.diagnosticWindowKey(session.focusedWindow),
                    "target": destination.map {
                        Self.diagnosticWindowKey($0.target)
                    } ?? "none",
                    "placement": destination?.placement.rawValue ?? "none",
                    "tree-proposed": TiledLayoutEngine.fingerprint(proposedTree),
                ]
            )
        }
    }

    private func commitManualTiledMovePreview() {
        guard var session = manualTiledMovePreviewSession else { return }
        updateManualTiledMoveLandingPreview()
        guard let updatedSession = manualTiledMovePreviewSession else { return }
        session = updatedSession
        let correlationID = "manual-move-\(session.token.uuidString.prefix(8))"
        let displays = Self.activeDisplays()
        guard !isWindowManagementPaused,
              !wakeReconciliationState.isSleeping,
              !wakeReconciliationState.isPending,
              windowServerSessionValidated,
              currentProfileID == session.profileID,
              Self.displayTopologySignature(displays) == session.topologySignature,
              tiledTrees[session.partition] == session.originalTree,
              let tracked = windows[session.focusedWindow],
              isWorkspaceActive(tracked.workspaceID),
              workspaceLayout(for: tracked.workspaceID) == .tiled,
              fullscreenSessions[session.focusedWindow] == nil,
              !isQuickAppShelfPresented,
              let display = displays.first(where: {
                  $0.identifier == session.partition.displayIdentifier
              }),
              (workspaceLayoutConfiguration(for: tracked.workspaceID)
                ?? .aeroSpaceUserDefaults) == session.configuration,
              managedLayoutBounds(display.usableBounds) == session.layoutBounds
        else {
            cancelManualTiledMovePreview(reason: "release-validation-failed")
            return
        }
        let participants = orderedLayoutParticipants(
            workspaceID: tracked.workspaceID,
            displayIdentifier: display.identifier,
            displays: displays,
            correlationID: correlationID
        )
        guard Set(participants) == session.participantKeys,
              let destination = session.candidateDestination,
              participants.contains(destination.target),
              session.proposedTree != session.originalTree,
              let effectiveShares = TiledLayoutEngine.leafShares(session.proposedTree)
        else {
            cancelManualTiledMovePreview(reason: "released-without-target")
            return
        }

        manualTiledMovePreviewSession = nil
        tiledTrees[session.partition] = session.proposedTree
        for (index, key) in session.proposedTree.windowKeys.enumerated() {
            windows[key]?.layoutOrder = index
            windows[key]?.layoutWeight = effectiveShares[key] ?? 1
        }
        lastFocusedWindow[tracked.workspaceID] = session.focusedWindow
        radialPlacementCommitContext = nil
        radialFreeformPlacementCommitContext = nil
        directionalMoveGestureContext = nil
        manualTiledDragSession = nil
        let changes = participants.compactMap { key -> FrameChange? in
            guard let window = windows[key], let frame = session.proposedFrames[key] else {
                return nil
            }
            lastSolvedTiledFrames[key] = frame
            return FrameChange(window: window, frame: frame)
        }
        applyFrameChanges(changes, correlationID: correlationID)
        lastBackgroundLayoutSignature = backgroundLayoutSignature(displays: displays)
        persistState(preservingPendingRestores: true)
        diagnostics.log(
            category: "manual-move-preview",
            event: "committed",
            correlation: correlationID,
            fields: [
                "workspace": Self.shortIdentifier(tracked.workspaceID.uuidString),
                "display": Self.shortIdentifier(display.identifier),
                "window": Self.diagnosticWindowKey(session.focusedWindow),
                "target": Self.diagnosticWindowKey(destination.target),
                "placement": destination.placement.rawValue,
                "window-count": String(participants.count),
                "tree-before": TiledLayoutEngine.fingerprint(session.originalTree),
                "tree-after": TiledLayoutEngine.fingerprint(session.proposedTree),
            ]
        )
        emitTiledResizePreviewEvent(.dismiss(token: session.token, reason: "committed"))
    }

    private func cancelManualTiledMovePreview(reason: String) {
        guard let session = manualTiledMovePreviewSession else { return }
        manualTiledMovePreviewSession = nil
        lastBackgroundLayoutSignature = nil
        let correlationID = "manual-move-\(session.token.uuidString.prefix(8))"
        restoreManualTiledParticipants(
            session.participantKeys,
            frames: session.originalFrames,
            correlationID: correlationID
        )
        diagnostics.log(
            category: "manual-move-preview",
            event: "cancelled",
            correlation: correlationID,
            fields: ["reason": reason]
        )
        emitTiledResizePreviewEvent(.dismiss(token: session.token, reason: reason))
    }

    func cancelTiledResizePreview(reason: String) {
        queue.async { [weak self] in
            self?.cancelManualTiledPreviewTransactions(reason: reason)
        }
    }

    private func updateManualTiledResizePreview(allowStartingSession: Bool = true) {
        if let existingSession = manualTiledResizeSession {
            updateConcealedManualTiledResizePreview(existingSession)
            return
        }
        guard !isWindowManagementPaused,
              !wakeReconciliationState.isSleeping,
              !wakeReconciliationState.isPending,
              windowServerSessionValidated,
              !isQuickAppShelfPresented,
              let focused = focusedWindowSnapshot(),
              let observedFrame = focused.frame,
              let tracked = windows[focused.key],
              isWorkspaceActive(tracked.workspaceID),
              workspaceLayout(for: tracked.workspaceID) == .tiled,
              fullscreenSessions[focused.key] == nil,
              !temporarilyDeferredWindowKeys.contains(focused.key),
              Self.shouldIncludeInLayout(
                  layoutOverride: tracked.layoutOverride,
                  admissionDecision: tracked.admissionDecision,
                  rule: resolvedRule(for: tracked.bundleIdentifier)
              )
        else {
            return
        }

        let displays = Self.activeDisplays()
        guard let display = targetDisplay(
            for: tracked,
            workspaceID: tracked.workspaceID,
            displays: displays,
            correlationID: nil
        ) else {
            return
        }
        let topologySignature = Self.displayTopologySignature(displays)
        let participants = orderedLayoutParticipants(
            workspaceID: tracked.workspaceID,
            displayIdentifier: display.identifier,
            displays: displays,
            correlationID: nil
        )
        let configuration = workspaceLayoutConfiguration(for: tracked.workspaceID)
            ?? .aeroSpaceUserDefaults
        let layoutBounds = managedLayoutBounds(display.usableBounds)
        let partition = TiledLayoutPartitionKey(
            workspaceID: tracked.workspaceID,
            displayIdentifier: display.identifier
        )

        guard allowStartingSession, participants.count > 1, participants.contains(focused.key),
              let originalTree = TiledLayoutEngine.reconciled(
                  tiledTrees[partition],
                  windowKeys: participants,
                  weights: participants.map {
                      CGFloat(Self.validLayoutWeight(windows[$0]?.layoutWeight))
                  },
                  orientation: configuration.orientation.resolved(for: layoutBounds)
              )
        else { return }

        guard let originalFrames = try? TiledLayoutEngine.frames(
            for: originalTree,
            in: layoutBounds,
            configuration: configuration
        ), let expectedFocusedFrame = originalFrames[focused.key],
              let lastSolvedFrame = lastSolvedTiledFrames[focused.key],
              AccessibilityWindow.framesMatch(lastSolvedFrame, expectedFocusedFrame)
        else {
            return
        }

        guard let pointer = CGEvent(source: nil)?.location else { return }
        guard case let .resize(draggedEdges) = TiledManualDragClassifier.classify(
            expectedFrame: expectedFocusedFrame,
            observedFrame: observedFrame,
            pointer: pointer
        ) else { return }

        let proposedTree = TiledLayoutEngine.resizedToMatchObservedFrame(
            originalTree,
            focusedWindow: focused.key,
            observedFrame: observedFrame,
            displayBounds: layoutBounds,
            configuration: configuration
        ) ?? originalTree
        guard proposedTree != originalTree else { return }
        guard let proposedFrames = try? TiledLayoutEngine.frames(
            for: proposedTree,
            in: layoutBounds,
            configuration: configuration
        ) else {
            return
        }

        let token = UUID()
        let session = ManualTiledResizeSession(
            token: token,
            focusedWindow: focused.key,
            partition: partition,
            participantKeys: Set(participants),
            originalTree: originalTree,
            originalFrames: originalFrames,
            configuration: configuration,
            layoutBounds: layoutBounds,
            topologySignature: topologySignature,
            profileID: currentProfileID,
            draggedEdges: draggedEdges,
            anchorFrame: observedFrame,
            anchorPointer: pointer,
            proposedTree: proposedTree,
            proposedFrames: proposedFrames
        )
        manualTiledResizeSession = session
        manualTiledDragSession = nil
        let presentation = TiledResizePreviewPresentation(
            token: token,
            displayIdentifier: display.identifier,
            layoutBounds: WindowFrame(position: layoutBounds.origin, size: layoutBounds.size),
            frames: proposedFrames,
            transition: .immediate,
            role: .layout
        )
        emitTiledResizePreviewEvent(.present(presentation))
        guard concealManualTiledResizeParticipants(
            session,
            correlationID: "manual-resize-\(token.uuidString.prefix(8))"
        ) else {
            cancelManualTiledResizePreview(reason: "participant-concealment-failed")
            return
        }
        diagnostics.log(
            category: "manual-resize-preview",
            event: "started",
            correlation: "manual-resize-\(token.uuidString.prefix(8))",
            fields: [
                "workspace": Self.shortIdentifier(tracked.workspaceID.uuidString),
                "display": Self.shortIdentifier(display.identifier),
                "window": Self.diagnosticWindowKey(focused.key),
                "window-count": String(participants.count),
                "tree-proposed": TiledLayoutEngine.fingerprint(proposedTree),
            ]
        )
    }

    private func updateConcealedManualTiledResizePreview(
        _ session: ManualTiledResizeSession
    ) {
        let correlationID = "manual-resize-\(session.token.uuidString.prefix(8))"
        let displays = Self.activeDisplays()
        guard !isWindowManagementPaused,
              !wakeReconciliationState.isSleeping,
              !wakeReconciliationState.isPending,
              windowServerSessionValidated,
              !isQuickAppShelfPresented,
              currentProfileID == session.profileID,
              Self.displayTopologySignature(displays) == session.topologySignature,
              tiledTrees[session.partition] == session.originalTree,
              let tracked = windows[session.focusedWindow],
              isWorkspaceActive(tracked.workspaceID),
              workspaceLayout(for: tracked.workspaceID) == .tiled,
              fullscreenSessions[session.focusedWindow] == nil,
              !temporarilyDeferredWindowKeys.contains(session.focusedWindow),
              let display = displays.first(where: {
                  $0.identifier == session.partition.displayIdentifier
              }),
              (workspaceLayoutConfiguration(for: tracked.workspaceID)
                ?? .aeroSpaceUserDefaults) == session.configuration,
              managedLayoutBounds(display.usableBounds) == session.layoutBounds
        else {
            cancelManualTiledResizePreview(reason: "context-changed")
            return
        }

        let participants = orderedLayoutParticipants(
            workspaceID: tracked.workspaceID,
            displayIdentifier: display.identifier,
            displays: displays,
            correlationID: correlationID
        )
        guard Set(participants) == session.participantKeys,
              let pointer = CGEvent(source: nil)?.location,
              let observedFrame = session.draggedEdges.projectedFrame(
                  from: session.anchorFrame,
                  anchorPointer: session.anchorPointer,
                  pointer: pointer
              )
        else {
            cancelManualTiledResizePreview(reason: "participants-or-pointer-changed")
            return
        }

        let proposedTree = TiledLayoutEngine.resizedToMatchObservedFrame(
            session.originalTree,
            focusedWindow: session.focusedWindow,
            observedFrame: observedFrame,
            displayBounds: session.layoutBounds,
            configuration: session.configuration
        ) ?? session.originalTree
        guard let proposedFrames = try? TiledLayoutEngine.frames(
            for: proposedTree,
            in: session.layoutBounds,
            configuration: session.configuration
        ) else {
            cancelManualTiledResizePreview(reason: "proposal-invalid")
            return
        }

        var updated = session
        updated.proposedTree = proposedTree
        updated.proposedFrames = proposedFrames
        manualTiledResizeSession = updated

        let presentation = TiledResizePreviewPresentation(
            token: session.token,
            displayIdentifier: display.identifier,
            layoutBounds: WindowFrame(
                position: session.layoutBounds.origin,
                size: session.layoutBounds.size
            ),
            frames: proposedFrames,
            transition: .immediate,
            role: .layout
        )
        emitTiledResizePreviewEvent(.present(presentation))
        guard concealManualTiledResizeParticipants(updated, correlationID: correlationID) else {
            cancelManualTiledResizePreview(reason: "participant-concealment-failed")
            return
        }
        diagnostics.log(
            category: "manual-resize-preview",
            event: "updated",
            correlation: correlationID,
            fields: [
                "workspace": Self.shortIdentifier(tracked.workspaceID.uuidString),
                "display": Self.shortIdentifier(display.identifier),
                "window": Self.diagnosticWindowKey(session.focusedWindow),
                "window-count": String(participants.count),
                "tree-proposed": TiledLayoutEngine.fingerprint(proposedTree),
            ]
        )
    }

    private func concealManualTiledResizeParticipants(
        _ session: ManualTiledResizeSession,
        correlationID: String
    ) -> Bool {
        concealManualTiledParticipants(
            session.participantKeys,
            diagnosticCategory: "manual-resize-preview",
            correlationID: correlationID
        )
    }

    private func concealManualTiledParticipants(
        _ participantKeys: Set<WindowKey>,
        diagnosticCategory: String,
        correlationID: String
    ) -> Bool {
        let targets = participantKeys.compactMap { windows[$0] }
        guard targets.count == participantKeys.count else { return false }
        let parkingPosition = parkingPosition()
        var allSucceeded = true
        for (processIdentifier, applicationTargets) in Dictionary(
            grouping: targets,
            by: \.processIdentifier
        ) {
            AccessibilityWindow.withoutPositionAnimations(for: processIdentifier) {
                for target in applicationTargets {
                    let succeeded = AccessibilityWindow.setPositionIfNeeded(
                        parkingPosition,
                        of: target.element
                    )
                    allSucceeded = allSucceeded && succeeded
                    diagnostics.log(
                        category: diagnosticCategory,
                        event: "participant-concealed",
                        correlation: correlationID,
                        fields: [
                            "window": Self.diagnosticWindowKey(target.key),
                            "success": String(succeeded),
                        ]
                    )
                }
            }
        }
        return allSucceeded
    }

    private func restoreManualTiledResizeParticipants(
        _ session: ManualTiledResizeSession,
        frames: [WindowKey: WindowFrame],
        correlationID: String
    ) {
        restoreManualTiledParticipants(
            session.participantKeys,
            frames: frames,
            correlationID: correlationID
        )
    }

    private func restoreManualTiledParticipants(
        _ participantKeys: Set<WindowKey>,
        frames: [WindowKey: WindowFrame],
        correlationID: String
    ) {
        let changes = participantKeys.compactMap { key -> FrameChange? in
            guard let tracked = windows[key], let frame = frames[key] else { return nil }
            return FrameChange(window: tracked, frame: frame)
        }
        applyFrameChanges(changes, correlationID: correlationID)
    }

    private func cancelManualTiledPreviewTransactions(reason: String) {
        cancelManualTiledMovePreview(reason: reason)
        cancelManualTiledResizePreview(reason: reason)
    }

    private func cancelManualTiledResizePreview(reason: String) {
        guard let session = manualTiledResizeSession else { return }
        manualTiledResizeSession = nil
        lastBackgroundLayoutSignature = nil
        let correlationID = "manual-resize-\(session.token.uuidString.prefix(8))"
        restoreManualTiledResizeParticipants(
            session,
            frames: session.originalFrames,
            correlationID: correlationID
        )
        diagnostics.log(
            category: "manual-resize-preview",
            event: "cancelled",
            correlation: correlationID,
            fields: ["reason": reason]
        )
        emitTiledResizePreviewEvent(.dismiss(token: session.token, reason: reason))
    }

    private func emitTiledResizePreviewEvent(_ event: TiledResizePreviewEvent) {
        DispatchQueue.main.async { [weak self] in
            self?.onTiledResizePreviewChanged?(event)
        }
    }

    /// A normal refresh sees an externally resized tiled window before the background layout pass.
    /// Convert a focused window's moved internal edge into tree ratios first, so that pass resizes
    /// its neighbours around the user's divider rather than restoring the previous geometry.
    private func reconcileManualTiledResize(
        focusedWindow: WindowKey,
        observedFrames: [WindowKey: WindowFrame],
        displays: [DisplaySnapshot],
        correlationID: String?
    ) {
        guard let tracked = windows[focusedWindow],
              let observedFrame = observedFrames[focusedWindow],
              isWorkspaceActive(tracked.workspaceID),
              workspaceLayout(for: tracked.workspaceID) == .tiled,
              fullscreenSessions[focusedWindow] == nil,
              !temporarilyDeferredWindowKeys.contains(focusedWindow),
              Self.shouldIncludeInLayout(
                  layoutOverride: tracked.layoutOverride,
                  admissionDecision: tracked.admissionDecision,
                  rule: resolvedRule(for: tracked.bundleIdentifier)
              ),
              let display = targetDisplay(
                  for: tracked,
                  workspaceID: tracked.workspaceID,
                  displays: displays,
                  correlationID: correlationID
              )
        else { return }

        let participants = orderedLayoutParticipants(
            workspaceID: tracked.workspaceID,
            displayIdentifier: display.identifier,
            displays: displays,
            correlationID: correlationID
        )
        guard participants.count > 1, participants.contains(focusedWindow) else { return }

        let configuration = workspaceLayoutConfiguration(for: tracked.workspaceID)
            ?? .aeroSpaceUserDefaults
        let managedBounds = managedLayoutBounds(display.usableBounds)
        let partition = TiledLayoutPartitionKey(
            workspaceID: tracked.workspaceID,
            displayIdentifier: display.identifier
        )
        guard let currentTree = TiledLayoutEngine.reconciled(
            tiledTrees[partition],
            windowKeys: participants,
            weights: participants.map {
                CGFloat(Self.validLayoutWeight(windows[$0]?.layoutWeight))
            },
            orientation: configuration.orientation.resolved(for: managedBounds)
        ), let expectedFrames = try? TiledLayoutEngine.frames(
            for: currentTree,
            in: managedBounds,
            configuration: configuration
        ), let expectedFocusedFrame = expectedFrames[focusedWindow],
              let lastSolvedFrame = lastSolvedTiledFrames[focusedWindow],
              AccessibilityWindow.framesMatch(lastSolvedFrame, expectedFocusedFrame),
              let resizedTree = TiledLayoutEngine.resizedToMatchObservedFrame(
                  currentTree,
                  focusedWindow: focusedWindow,
                  observedFrame: observedFrame,
                  displayBounds: managedBounds,
                  configuration: configuration
              ), let effectiveShares = TiledLayoutEngine.leafShares(resizedTree)
        else { return }

        tiledTrees[partition] = resizedTree
        for key in participants {
            windows[key]?.layoutWeight = effectiveShares[key] ?? 1
        }
        radialPlacementCommitContext = nil
        radialFreeformPlacementCommitContext = nil
        directionalMoveGestureContext = nil
        lastBackgroundLayoutSignature = nil
        diagnostics.log(
            category: "manual-resize",
            event: "tree-reweighted",
            correlation: correlationID,
            fields: [
                "workspace": Self.shortIdentifier(tracked.workspaceID.uuidString),
                "display": Self.shortIdentifier(display.identifier),
                "window": Self.diagnosticWindowKey(focusedWindow),
                "observed-frame": Self.diagnosticFrame(observedFrame),
                "tree-before": TiledLayoutEngine.fingerprint(currentTree),
                "tree-after": TiledLayoutEngine.fingerprint(resizedTree),
            ]
        )
    }

    private func orderedLayoutParticipants(
        workspaceID: UUID,
        displayIdentifier: String,
        displays: [DisplaySnapshot],
        correlationID: String?
    ) -> [WindowKey] {
        windows.values.filter { tracked in
            guard !isDropDownAppWindow(tracked.key),
                  !isExcludedFromWorkspaceParticipation(tracked),
                  tracked.workspaceID == workspaceID,
                  StableLayoutSlotPolicy.isAvailableForLayout(
                      isWriteDeferred: temporarilyDeferredWindowKeys.contains(tracked.key),
                      retainsLayoutSlot: retainedLayoutSlotWindowKeys.contains(tracked.key),
                      isExplicitlyEligible: fullscreenSessions[tracked.key] == nil
                  ),
                  Self.shouldIncludeInLayout(
                      layoutOverride: tracked.layoutOverride,
                      admissionDecision: tracked.admissionDecision,
                      rule: resolvedRule(for: tracked.bundleIdentifier)
                  )
            else { return false }
            return targetDisplay(
                for: tracked,
                workspaceID: workspaceID,
                displays: displays,
                correlationID: correlationID
            )?.identifier == displayIdentifier
        }.sorted { lhs, rhs in
            if lhs.layoutOrder != rhs.layoutOrder { return lhs.layoutOrder < rhs.layoutOrder }
            if lhs.key.processIdentifier != rhs.key.processIdentifier {
                return lhs.key.processIdentifier < rhs.key.processIdentifier
            }
            return lhs.key.windowIdentifier < rhs.key.windowIdentifier
        }.map(\.key)
    }

    private func activateMovedWindowDestination(
        sourceWorkspaceID: UUID,
        destinationWorkspaceID: UUID,
        destinationDisplayIdentifier: String,
        displays: [DisplaySnapshot],
        correlationID: String
    ) {
        if displayMode == .unified {
            let displacedWorkspaceID = currentWorkspaceID
            previousWorkspaceID = displacedWorkspaceID
            currentWorkspaceID = destinationWorkspaceID
            if displacedWorkspaceID != destinationWorkspaceID {
                applyVisibilityTransition(
                    from: displacedWorkspaceID,
                    to: destinationWorkspaceID,
                    correlationID: correlationID
                )
            } else {
                applyVisibleWindows(
                    windows.values.filter { $0.workspaceID == destinationWorkspaceID },
                    displays: displays,
                    correlationID: correlationID
                )
            }
            return
        }

        let displacedWorkspaceID = activeWorkspaceIDByDisplay[destinationDisplayIdentifier]
        if let displacedWorkspaceID, displacedWorkspaceID != destinationWorkspaceID {
            previousWorkspaceIDByDisplay[destinationDisplayIdentifier] = displacedWorkspaceID
            previousWorkspaceID = displacedWorkspaceID
        }
        activeWorkspaceIDByDisplay = Self.switchingIndependentWorkspace(
            destinationWorkspaceID,
            displayIdentifier: destinationDisplayIdentifier,
            in: activeWorkspaceIDByDisplay
        )
        currentWorkspaceID = destinationWorkspaceID
        if let displacedWorkspaceID, displacedWorkspaceID != destinationWorkspaceID {
            applyVisibilityTransition(
                from: displacedWorkspaceID,
                to: destinationWorkspaceID,
                correlationID: correlationID
            )
        } else {
            applyVisibleWindows(
                windows.values.filter { $0.workspaceID == destinationWorkspaceID },
                displays: displays,
                correlationID: correlationID
            )
        }
        if sourceWorkspaceID != displacedWorkspaceID,
           isWorkspaceActive(sourceWorkspaceID),
           workspaceLayout(for: sourceWorkspaceID) != .none {
            applyVisibleWindows(
                windows.values.filter { $0.workspaceID == sourceWorkspaceID },
                displays: displays,
                correlationID: correlationID
            )
        }
    }

    private func clearFocusStateAfterSendOnlyMove(
        movingWindow: WindowKey,
        tracked: TrackedWindow,
        sourceWorkspaceID: UUID,
        interactionDisplayIdentifier: String,
        correlationID: String
    ) {
        lastFocusedWindow = lastFocusedWindow.filter { $0.value != movingWindow }
        if lastObservedFocusedWindow == movingWindow { lastObservedFocusedWindow = nil }
        if programmaticFocusTarget == movingWindow { clearProgrammaticFocusIntent() }
        recentInteractionFocusTarget = nil
        recentInteractionDisplayIdentifier = interactionDisplayIdentifier
        recentInteractionDisplayDeadline = Date().addingTimeInterval(1.75)
        let clearResult = AccessibilityWindow.clearFocus(of: tracked.element)
        diagnostics.log(
            category: "move-window",
            event: "focus-neutralized",
            correlation: correlationID,
            fields: [
                "window": Self.diagnosticWindowKey(movingWindow),
                "source-workspace": Self.shortIdentifier(sourceWorkspaceID.uuidString),
                "source-display": Self.shortIdentifier(interactionDisplayIdentifier),
                "replacement": "none",
                "focused-clear-result": clearResult.focused.map { String($0.rawValue) } ?? "unsupported",
                "main-clear-result": clearResult.main.map { String($0.rawValue) } ?? "unsupported",
            ]
        )
    }

    /// Returns a read-only command snapshot for contextual UI. This deliberately does not call
    private func makeTiledPlacementCommitContext(
        validationToken: String,
        createdAt: Date,
        focusedWindow: WindowKey,
        workspaceID: UUID,
        displayIdentifier: String,
        displays: [DisplaySnapshot],
        correlationID: String?
    ) -> TiledPlacementCommitContext? {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }),
              workspace.layout == .tiled,
              let display = displays.first(where: { $0.identifier == displayIdentifier }),
              let tracked = windows[focusedWindow],
              tracked.workspaceID == workspaceID,
              Self.shouldIncludeInLayout(
                  layoutOverride: tracked.layoutOverride,
                  admissionDecision: tracked.admissionDecision,
                  rule: resolvedRule(for: tracked.bundleIdentifier)
              )
        else { return nil }
        let participants = orderedLayoutParticipants(
            workspaceID: workspaceID,
            displayIdentifier: displayIdentifier,
            displays: displays,
            correlationID: correlationID
        )
        guard participants.count > 1, participants.contains(focusedWindow) else { return nil }
        let configuration = workspace.layoutConfiguration ?? .aeroSpaceUserDefaults
        let managedBounds = managedLayoutBounds(display.usableBounds)
        let partition = TiledLayoutPartitionKey(
            workspaceID: workspaceID,
            displayIdentifier: displayIdentifier
        )
        guard let tree = TiledLayoutEngine.reconciled(
            tiledTrees[partition],
            windowKeys: participants,
            weights: participants.map {
                CGFloat(Self.validLayoutWeight(windows[$0]?.layoutWeight))
            },
            orientation: configuration.orientation.resolved(for: managedBounds)
        ) else { return nil }
        let previews = Dictionary(
            uniqueKeysWithValues: VisualPlacement.compassOrder.compactMap { placement in
                (try? TiledLayoutEngine.placing(
                    focusedWindow,
                    at: placement,
                    in: tree,
                    bounds: managedBounds,
                    configuration: configuration
                )).map { (placement, $0) }
            }
        )
        guard !previews.isEmpty else { return nil }
        return TiledPlacementCommitContext(
            validationToken: validationToken,
            createdAt: createdAt,
            focusedWindow: focusedWindow,
            partition: partition,
            participantKeys: Set(participants),
            originalTree: tree,
            previews: previews
        )
    }

    private func makeFreeformPlacementCommitContext(
        validationToken: String,
        createdAt: Date,
        focusedWindow: WindowKey,
        workspaceID: UUID,
        displayIdentifier: String,
        displays: [DisplaySnapshot]
    ) -> FreeformPlacementCommitContext? {
        guard workspaceLayout(for: workspaceID) == .none,
              let display = displays.first(where: { $0.identifier == displayIdentifier }),
              let tracked = windows[focusedWindow],
              tracked.workspaceID == workspaceID,
              let originalFrame = AccessibilityWindow.frame(of: tracked.element),
              FullscreenSessionPolicy.allowsGeometryWrite(
                  hasFullscreenSession: fullscreenSessions[focusedWindow] != nil,
                  isTemporarilyDeferred: temporarilyDeferredWindowKeys.contains(focusedWindow)
              ),
              Self.shouldIncludeInLayout(
                  layoutOverride: tracked.layoutOverride,
                  admissionDecision: tracked.admissionDecision,
                  rule: resolvedRule(for: tracked.bundleIdentifier)
              )
        else { return nil }
        let previews = Dictionary(
            uniqueKeysWithValues: VisualPlacement.compassOrder.compactMap { placement in
                FreeformPlacementEngine.preview(
                    focusedWindow: focusedWindow,
                    displayIdentifier: displayIdentifier,
                    originalFrame: originalFrame,
                    placement: placement,
                    displayBounds: display.usableBounds
                ).map { (placement, $0) }
            }
        )
        guard !previews.isEmpty else { return nil }
        return FreeformPlacementCommitContext(
            validationToken: validationToken,
            createdAt: createdAt,
            focusedWindow: focusedWindow,
            workspaceID: workspaceID,
            displayIdentifier: displayIdentifier,
            displayBounds: display.usableBounds,
            originalFrame: originalFrame,
            previews: previews
        )
    }

    /// `refreshWindows`: merely previewing the wheel must never trigger discovery-driven layout or
    /// visibility writes. The normal engine poll remains responsible for keeping tracking current.
    func radialCommandContext(
        focusingWindowAt pointerLocation: CGPoint? = nil,
        completion: @escaping (RadialCommandContext) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            if let pointerLocation,
               self.focusPointerWindowForRadialMenu(
                   at: pointerLocation,
                   completion: completion
               ) {
                return
            }
            let displays = Self.activeDisplays()
            let rawFocused = self.focusedWindowSnapshot()
            let focused = self.interactionFocusedWindowSnapshot(rawFocused)
            let interactionDisplay = self.interactionDisplayResolution(
                focused: focused,
                displays: displays
            )
            let workspaceResolution = self.interactionWorkspaceResolution(
                focusedKey: focused?.key,
                displayIdentifier: interactionDisplay.identifier
            )
            let workspaceID = workspaceResolution.workspaceID
            let workspace = self.workspaces.first(where: { $0.id == workspaceID })
                ?? self.workspaces[0]

            let focusSource: RadialFocusSource
            if let rawFocused, self.ignoredWindowKeys.contains(rawFocused.key), focused?.key != nil {
                focusSource = .preservedManagedAnchor
            } else if let focused, self.windows[focused.key] != nil {
                focusSource = .focusedManagedWindow
            } else {
                focusSource = .none
            }

            let focusedWindow: RadialFocusedWindowContext? = focused.flatMap { snapshot in
                guard let tracked = self.windows[snapshot.key],
                      self.isWorkspaceActive(tracked.workspaceID)
                else { return nil }
                let rule = self.resolvedRule(for: tracked.bundleIdentifier)
                let decision = Self.layoutDecision(
                    layoutOverride: tracked.layoutOverride,
                    admissionDecision: tracked.admissionDecision,
                    rule: rule
                )
                let state: RadialFocusedWindowLayoutState = switch decision {
                case .appRuleExcluded: .appRuleExcluded
                case .explicitlyFloating: .floating
                case .explicitlyManaged: .explicitlyManaged
                case .automaticallyFloatingDialog: .automaticallyFloatingDialog
                case .automaticallyFloatingSecondary: .automaticallyFloatingSecondary
                case .managedNormal: .managed
                }
                return RadialFocusedWindowContext(
                    processIdentifier: tracked.key.processIdentifier,
                    windowIdentifier: tracked.key.windowIdentifier,
                    workspaceID: tracked.workspaceID,
                    frame: snapshot.frame ?? AccessibilityWindow.frame(of: tracked.element),
                    layoutState: state,
                    isAutomaticallyFloatingDialog: tracked.admissionDecision.automaticallyFloats,
                    isAppRuleExcluded: rule.excludesFromLayout,
                    keepsOnAllWorkspaces: rule.keepsOnAllWorkspaces
                )
            }

            let options = self.workspaces.map { definition in
                RadialWorkspaceOption(
                    id: definition.id,
                    name: definition.name,
                    key: definition.key,
                    layout: definition.layout,
                    homeDisplayIdentifier: self.workspaceHomeDisplayIdentifier(
                        for: definition.id,
                        displays: displays
                    )
                )
            }
            let display = displays.first(where: { $0.identifier == interactionDisplay.identifier })
                ?? displays.first
                ?? DisplaySnapshot(
                    identifier: interactionDisplay.identifier,
                    bounds: .zero,
                    isMain: true,
                    name: "Display"
                )
            let focusedKey = focused.map(\.key)
            let availableFocusDirections: Set<WindowDirection>
            if self.isQuickAppShelfPresented || self.quickAppTransition != .idle {
                let selectedBundleKey = self.dropDownAppConfiguration.map {
                    Self.normalizedBundleIdentifier($0.bundleIdentifier)
                }
                if self.quickAppTransition == .idle,
                   let selectedBundleKey,
                   let selectedSession = self.quickAppSessions[selectedBundleKey],
                   selectedSession.isPresented,
                   let selectedTarget = self.windows[selectedSession.windowKey],
                   let selectedFrame = AccessibilityWindow.frame(of: selectedTarget.element) {
                    let shelfCandidates = self.quickAppSessions.values.reduce(
                        into: [DirectionalWindowCandidate<WindowKey>]()
                    ) { result, session in
                        guard session.isPresented else { return }
                        for key in session.windowKeys {
                            guard key != selectedSession.windowKey,
                                  let target = self.windows[key],
                                  let frame = AccessibilityWindow.frame(of: target.element)
                            else { continue }
                            result.append(DirectionalWindowCandidate(
                                key: key,
                                frame: CGRect(origin: frame.position, size: frame.size)
                            ))
                        }
                    }
                    availableFocusDirections = Self.availableShelfFocusDirections(
                        from: CGRect(origin: selectedFrame.position, size: selectedFrame.size),
                        candidates: shelfCandidates,
                        shelfDirection: self.quickAppShelfPresentation.direction
                    )
                } else {
                    availableFocusDirections = []
                }
            } else {
                let focusCandidates = self.directionalFocusCandidates(
                    workspaceID: workspace.id,
                    interactionDisplayIdentifier: interactionDisplay.identifier,
                    displays: displays,
                    correlationID: nil
                )
                let focusedFrame = focusedWindow?.frame.map {
                    CGRect(origin: $0.position, size: $0.size)
                }
                availableFocusDirections = focusedFrame.map { sourceFrame in
                    Set(WindowDirection.allCases.filter { direction in
                        !Self.wrappingDirectionalCandidateOrder(
                            from: sourceFrame,
                            direction: direction,
                            candidates: focusCandidates.filter { Optional($0.key) != focusedKey }
                        ).candidates.isEmpty
                    })
                } ?? []
            }
            let layoutParticipants = self.orderedLayoutParticipants(
                workspaceID: workspace.id,
                displayIdentifier: interactionDisplay.identifier,
                displays: displays,
                correlationID: nil
            )
            let participantIndex = focusedKey.flatMap { layoutParticipants.firstIndex(of: $0) }
            let managedBounds = self.managedLayoutBounds(display.usableBounds)
            let resolvedOrientation = (workspace.layoutConfiguration?.orientation ?? .automatic)
                .resolved(for: managedBounds)
            var availableMoveDirections = Set<WindowDirection>()
            if workspace.layout != .none,
               let participantIndex,
               layoutParticipants.count > 1 {
                if participantIndex > 0 {
                    availableMoveDirections.insert(resolvedOrientation == .horizontal ? .left : .up)
                }
                if participantIndex < layoutParticipants.count - 1 {
                    availableMoveDirections.insert(resolvedOrientation == .horizontal ? .right : .down)
                }
            }
            let canSmartResize = workspace.layout != .none &&
                participantIndex != nil && layoutParticipants.count > 1
            let layoutConfiguration = workspace.layoutConfiguration ?? .aeroSpaceUserDefaults
            let partition = TiledLayoutPartitionKey(
                workspaceID: workspace.id,
                displayIdentifier: interactionDisplay.identifier
            )
            let tiledTree = workspace.layout == .tiled ? TiledLayoutEngine.reconciled(
                self.tiledTrees[partition],
                windowKeys: layoutParticipants,
                weights: layoutParticipants.map {
                    CGFloat(Self.validLayoutWeight(self.windows[$0]?.layoutWeight))
                },
                orientation: layoutConfiguration.orientation.resolved(for: managedBounds)
            ) : nil
            let tiledTreeFingerprint = tiledTree.map(TiledLayoutEngine.fingerprint) ?? "none"
            let focusedToken = focusedWindow.map {
                "\($0.processIdentifier):\($0.windowIdentifier):\($0.layoutState.rawValue):\($0.workspaceID.uuidString)"
            } ?? "none"
            let activeToken = self.activeWorkspaceIDByDisplay
                .map { "\($0.key)=\($0.value.uuidString)" }
                .sorted()
                .joined(separator: ",")
            let token = [
                focusedToken,
                workspace.id.uuidString,
                workspace.layout.rawValue,
                interactionDisplay.identifier,
                self.displayMode.rawValue,
                String(self.focusFollowsMovedWindow),
                availableFocusDirections.map(\.rawValue).sorted().joined(separator: ","),
                availableMoveDirections.map(\.rawValue).sorted().joined(separator: ","),
                String(canSmartResize),
                tiledTreeFingerprint,
                activeToken,
                displays.map(\.identifier).sorted().joined(separator: ","),
            ].joined(separator: "|")

            let placementContext = focusedKey.flatMap { focusedKey in
                self.makeTiledPlacementCommitContext(
                    validationToken: token,
                    createdAt: Date(),
                    focusedWindow: focusedKey,
                    workspaceID: workspace.id,
                    displayIdentifier: interactionDisplay.identifier,
                    displays: displays,
                    correlationID: nil
                )
            }
            let tiledPlacementPreviews = VisualPlacement.compassOrder.compactMap {
                placementContext?.previews[$0]
            }
            self.radialPlacementCommitContext = placementContext
            let freeformPlacementContext = focusedKey.flatMap { focusedKey in
                self.makeFreeformPlacementCommitContext(
                    validationToken: token,
                    createdAt: Date(),
                    focusedWindow: focusedKey,
                    workspaceID: workspace.id,
                    displayIdentifier: interactionDisplay.identifier,
                    displays: displays
                )
            }
            let freeformPlacementPreviews = VisualPlacement.compassOrder.compactMap {
                freeformPlacementContext?.previews[$0]
            }
            self.radialFreeformPlacementCommitContext = freeformPlacementContext

            let context = RadialCommandContext(
                focusedWindow: focusedWindow,
                focusSource: focusedWindow == nil ? .none : focusSource,
                workspaceID: workspace.id,
                workspaceName: workspace.name,
                layout: workspace.layout,
                displayIdentifier: interactionDisplay.identifier,
                displayName: display.name,
                displayBounds: display.usableBounds,
                displayMode: self.displayMode,
                focusFollowsMovedWindow: self.focusFollowsMovedWindow,
                connectedDisplayIdentifiers: displays.map(\.identifier),
                connectedDisplays: displays.map {
                    RadialDisplayOption(id: $0.identifier, name: $0.name, isMain: $0.isMain)
                },
                availableFocusDirections: availableFocusDirections,
                availableMoveDirections: availableMoveDirections,
                canSmartResize: canSmartResize,
                workspaces: options,
                supportedCommands: RadialCommandCapability.current,
                validationToken: token,
                tiledPlacementPreviews: tiledPlacementPreviews,
                freeformPlacementPreviews: freeformPlacementPreviews
            )
            DispatchQueue.main.async { completion(context) }
        }
    }

    /// Opening the wheel is explicit pointer intent. Resolve the actual frontmost WindowServer
    /// surface first, focus only an eligible tracked window, then capture a fresh context after the
    /// exact-focus pipeline has had its bounded observation window. Returning true means capture
    /// has been deferred and the supplied completion will be called by that continuation.
    private func focusPointerWindowForRadialMenu(
        at pointerLocation: CGPoint,
        completion: @escaping (RadialCommandContext) -> Void
    ) -> Bool {
        guard let orderedWindows = AccessibilityWindow.onScreenPointerOrder() else { return false }
        let displays = Self.activeDisplays()
        let eligibleKeys = Set(windows.compactMap { key, tracked -> WindowKey? in
            guard key.processIdentifier != ownProcessIdentifier,
                  !isDropDownAppWindow(key),
                  !isExcludedFromWorkspaceParticipation(tracked),
                  !ignoredWindowKeys.contains(key),
                  staleParkedFocusSuppression[key] == nil,
                  Self.shouldWindowBeVisible(
                      workspaceID: tracked.workspaceID,
                      activeWorkspaceIDs: activeWorkspaceIDs,
                      rule: resolvedRule(for: tracked.bundleIdentifier)
                  ),
                  let frame = AccessibilityWindow.frame(of: tracked.element),
                  Self.isMeaningfullyVisible(frame, displays: displays)
            else { return nil }
            let capabilities = AccessibilityWindow.focusCapabilities(
                of: tracked.element,
                processIdentifier: tracked.processIdentifier,
                windowIdentifier: key.windowIdentifier
            )
            return AccessibilityWindow.isEligibleFocusCycleCandidate(capabilities) ? key : nil
        })
        guard let target = AccessibilityWindow.pointerTargetWindow(
            at: pointerLocation,
            in: orderedWindows,
            eligibleWindowKeys: eligibleKeys
        ), let tracked = windows[target]
        else { return false }

        let current = interactionFocusedWindowSnapshot()?.key
        guard current != target else {
            diagnostics.log(
                category: "radial-menu",
                event: "pointer-focus-kept",
                fields: ["window": Self.diagnosticWindowKey(target), "reason": "already-focused"]
            )
            return false
        }

        let correlationID = diagnostics.makeCorrelationID()
        let displayIdentifier = Self.displayPlacement(
            for: AccessibilityWindow.frame(of: tracked.element) ?? tracked.restoreFrame,
            displays: displays
        )?.displayIdentifier ?? interactionDisplayIdentifier()
        let token = beginCorrelatedAction(
            correlationID: correlationID,
            interactionDisplayIdentifier: displayIdentifier,
            expectedFocusTarget: target
        )
        radialPointerFocusProcessIdentifier = target.processIdentifier
        radialPointerFocusDeadline = Date().addingTimeInterval(1.25)
        radialPointerFocusGeneration = token.generation
        staleParkedFocusSuppression.removeValue(forKey: target)
        diagnostics.log(
            category: "radial-menu",
            event: "pointer-focus-requested",
            correlation: correlationID,
            fields: [
                "window": Self.diagnosticWindowKey(target),
                "display": Self.shortIdentifier(displayIdentifier),
                "prior-window": current.map(Self.diagnosticWindowKey) ?? "none",
            ]
        )
        focusManagedWindow(
            target,
            tracked: tracked,
            correlationID: correlationID,
            token: token,
            allowImmediateAppKitCompatibilityFallback: true
        )
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let observed = self.interactionFocusedWindowSnapshot()?.key
            self.diagnostics.log(
                category: "radial-menu",
                event: "pointer-focus-observed",
                correlation: correlationID,
                fields: [
                    "expected-window": Self.diagnosticWindowKey(target),
                    "actual-window": observed.map(Self.diagnosticWindowKey) ?? "none",
                    "confirmed": String(observed == target),
                ]
            )
            self.radialCommandContext(completion: completion)
        }
        queue.asyncAfter(deadline: .now() + .milliseconds(220), execute: workItem)
        return true
    }

    /// Resolves the Settings utility destination without refreshing discovery or applying AX
    /// writes. A pointer-local menu invocation can nominate a connected physical display; keyboard
    /// invocation uses the same focused/recent interaction chain as other commands.
    func settingsSurfaceContext(
        preferredDisplayIdentifier: String? = nil,
        completion: @escaping (SettingsSurfaceContext) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            let displays = Self.activeDisplays()
            let rawFocused = self.focusedWindowSnapshot()
            let focused = self.interactionFocusedWindowSnapshot(rawFocused)
            let preferredIsConnected = preferredDisplayIdentifier.map { preferred in
                displays.contains(where: { $0.identifier == preferred })
            } == true
            let displayResolution: (identifier: String, reason: String)
            if preferredIsConnected, let preferredDisplayIdentifier {
                displayResolution = (preferredDisplayIdentifier, "pointer-local-settings-action")
            } else {
                displayResolution = self.interactionDisplayResolution(
                    focused: focused,
                    displays: displays
                )
            }
            // A pointer-local menu action intentionally targets that display. Do not let a focused
            // window on another display override its active workspace in Independent mode.
            let focusedWorkspaceID = preferredIsConnected
                ? nil
                : focused.flatMap { snapshot in
                    self.windows[snapshot.key].flatMap { tracked in
                        self.isWorkspaceActive(tracked.workspaceID) ? tracked.workspaceID : nil
                    }
                }
            let workspaceResolution = Self.settingsWorkspaceSelection(
                displayMode: self.displayMode,
                destinationDisplayIdentifier: displayResolution.identifier,
                focusedWorkspaceID: focusedWorkspaceID,
                currentWorkspaceID: self.currentWorkspaceID,
                activeWorkspaceIDByDisplay: self.activeWorkspaceIDByDisplay
            )
            let context = SettingsSurfaceContext(
                workspaceID: workspaceResolution.workspaceID,
                displayIdentifier: displayResolution.identifier,
                displayMode: self.displayMode,
                resolutionReason: "\(displayResolution.reason);\(workspaceResolution.reason)"
            )
            DispatchQueue.main.async { completion(context) }
        }
    }

    static func settingsWorkspaceSelection(
        displayMode: MultiDisplayMode,
        destinationDisplayIdentifier: String,
        focusedWorkspaceID: UUID?,
        currentWorkspaceID: UUID,
        activeWorkspaceIDByDisplay: [String: UUID]
    ) -> (workspaceID: UUID, reason: String) {
        if let focusedWorkspaceID {
            return (focusedWorkspaceID, "focused-managed-window")
        }
        if displayMode == .independent,
           let active = activeWorkspaceIDByDisplay[destinationDisplayIdentifier] {
            return (active, "independent-active-workspace-for-display")
        }
        return (
            currentWorkspaceID,
            displayMode == .unified ? "unified-current-workspace" : "current-workspace-fallback"
        )
    }

    func restoreAllWindows() {
        queue.async { [weak self] in
            guard let self else { return }
            self.refreshWindows()
            self.reapplyWorkspaceRules(to: self.windows.keys.filter { !self.isDropDownAppWindow($0) })
            self.applyVisibleWindows(self.windows.values, displays: Self.activeDisplays())
            self.persistState(preservingPendingRestores: true)
            self.emitState()
        }
    }

    /// A workspace-local safety repair. Unlike the global recovery button, this keeps display
    /// affinity in Unified mode and is restricted to the interaction display's active workspace in
    /// Independent Displays mode.
    func resetCurrentWorkspace(correlationID: String? = nil) {
        let correlationID = correlationID ?? diagnostics.makeCorrelationID()
        queue.async { [weak self] in
            guard let self else { return }
            let rawFocusedBefore = self.focusedWindowSnapshot()
            self.refreshWindows(correlationID: correlationID)
            let focusedBefore = self.interactionFocusedWindowSnapshot(rawFocusedBefore)
            let focusContextKey = Self.interactionFocusContext(
                focused: focusedBefore?.key,
                recent: self.recentInteractionFocusTarget,
                recentIsValid: Date() < self.recentInteractionDisplayDeadline
            )
            let displays = Self.activeDisplays()
            guard !displays.isEmpty else { return }
            let interactionDisplay = self.interactionDisplayResolution(
                focused: focusedBefore,
                displays: displays
            )
            let workspaceResolution = self.interactionWorkspaceResolution(
                focusedKey: focusContextKey,
                displayIdentifier: interactionDisplay.identifier
            )
            let workspaceID = workspaceResolution.workspaceID
            guard self.isWorkspaceActive(workspaceID) else { return }
            let initialTargetKeys = self.windows.values
                .filter { $0.workspaceID == workspaceID && !self.isDropDownAppWindow($0.key) }
                .map(\.key)
            let reroutedByRules = self.reapplyWorkspaceRules(to: initialTargetKeys)
            let resetFocusContextKey = focusContextKey.flatMap { key in
                self.windows[key]?.workspaceID == workspaceID ? key : nil
            }
            let verificationToken = self.beginCorrelatedAction(
                correlationID: correlationID,
                interactionDisplayIdentifier: interactionDisplay.identifier,
                expectedFocusTarget: resetFocusContextKey
            )

            self.diagnostics.log(
                category: "workspace-reset",
                event: "begin",
                correlation: correlationID,
                fields: [
                    "workspace": Self.shortIdentifier(workspaceID.uuidString),
                    "display": Self.shortIdentifier(interactionDisplay.identifier),
                    "display-mode": self.displayMode.rawValue,
                    "focused-window": resetFocusContextKey.map(Self.diagnosticWindowKey) ?? "none",
                    "rules-rerouted-windows": String(reroutedByRules),
                ]
            )

            let targetKeys = initialTargetKeys.filter {
                self.windows[$0]?.workspaceID == workspaceID
            }
            var repairs: [FrameChange] = []
            for key in targetKeys {
                guard var tracked = self.windows[key] else { continue }
                let resetDisplayIdentifier = Self.resetTargetDisplayIdentifier(
                    mode: self.displayMode,
                    interactionDisplayIdentifier: interactionDisplay.identifier,
                    preferredDisplayIdentifier: tracked.displayPlacement?.displayIdentifier,
                    savedFrame: tracked.restoreFrame,
                    displays: displays
                )
                let targetDisplay = resetDisplayIdentifier.flatMap { identifier in
                    displays.first { $0.identifier == identifier }
                }
                guard let targetDisplay else { continue }
                let safeFrame = Self.quitRecoveryFrame(
                    savedFrame: tracked.restoreFrame,
                    currentFrame: AccessibilityWindow.frame(of: tracked.element),
                    mainDisplayBounds: targetDisplay.usableBounds
                )
                tracked.restoreFrame = safeFrame
                tracked.displayPlacement = Self.displayPlacement(for: safeFrame, displays: displays)
                self.windows[key] = tracked
                self.pendingRestoredWindows.removeValue(forKey: String(key.windowIdentifier))
                self.focusCycleRejectedUntil.removeValue(forKey: key)
                repairs.append(FrameChange(window: tracked, frame: safeFrame))
            }

            self.pendingFocusVerification?.cancel()
            self.pendingFocusVerification = nil
            self.lastBackgroundLayoutSignature = nil
            self.tiledTrees = self.tiledTrees.filter { partition, _ in
                if partition.workspaceID != workspaceID { return true }
                return self.displayMode == .independent &&
                    partition.displayIdentifier != interactionDisplay.identifier
            }
            self.applyFrameChanges(repairs, correlationID: correlationID)
            if let resetFocusContextKey, self.windows[resetFocusContextKey] != nil {
                self.prepareProgrammaticFocusIntent(
                    resetFocusContextKey,
                    correlationID: correlationID,
                    duration: 0.8
                )
            }
            if reroutedByRules > 0 {
                self.applyVisibility(displays: displays, correlationID: correlationID)
            } else {
                self.applyVisibleWindows(
                    self.windows.values.filter { $0.workspaceID == workspaceID },
                    displays: displays,
                    correlationID: correlationID
                )
            }
            self.lastBackgroundLayoutSignature = self.backgroundLayoutSignature(displays: displays)
            self.persistState(preservingPendingRestores: true)
            self.emitState()
            self.diagnostics.log(
                category: "workspace-reset",
                event: "complete",
                correlation: correlationID,
                fields: [
                    "workspace": Self.shortIdentifier(workspaceID.uuidString),
                    "display": Self.shortIdentifier(interactionDisplay.identifier),
                    "window-count": String(repairs.count),
                ]
            )
            self.verifyFocusAfterAction(
                expected: resetFocusContextKey,
                correlationID: correlationID,
                action: "reset-workspace",
                token: verificationToken,
                mayRecoverNilFocus: true
            )
        }
    }

    /// Commits a preview produced by `radialCommandContext`. The preview itself is pure and makes
    /// no AX calls; this method is the single validation and frame-write boundary.
    func placeFocusedTiledWindow(
        at placement: VisualPlacement,
        validationToken: String,
        correlationID: String? = nil
    ) {
        let correlationID = correlationID ?? diagnostics.makeCorrelationID()
        queue.async { [weak self] in
            guard let self else { return }
            guard let commit = self.radialPlacementCommitContext,
                  commit.validationToken == validationToken,
                  Date().timeIntervalSince(commit.createdAt) <= 30
            else {
                self.diagnostics.log(
                    category: "radial-menu",
                    event: "placement-rejected",
                    correlation: correlationID,
                    fields: ["placement": placement.rawValue, "reason": "stale-context"]
                )
                return
            }
            self.radialPlacementCommitContext = nil
            _ = self.commitTiledPlacement(
                commit,
                placement: placement,
                maximumAge: 30,
                diagnosticCategory: "radial-menu",
                focusAction: "radial-place",
                feedback: "Place: \(placement.title)",
                correlationID: correlationID,
                usesKeyboardFocusRetention: false
            )
        }
    }

    /// Commits one pure Freeform frame proposal. The command changes only the focused window's
    /// stored and live frame; it never creates or mutates Tiled layout state.
    func placeFocusedFreeformWindow(
        at placement: VisualPlacement,
        validationToken: String,
        correlationID: String? = nil
    ) {
        let correlationID = correlationID ?? diagnostics.makeCorrelationID()
        queue.async { [weak self] in
            guard let self else { return }
            guard let commit = self.radialFreeformPlacementCommitContext,
                  commit.validationToken == validationToken,
                  Date().timeIntervalSince(commit.createdAt) <= 30,
                  let preview = commit.previews[placement]
            else {
                self.diagnostics.log(
                    category: "radial-menu",
                    event: "freeform-placement-rejected",
                    correlation: correlationID,
                    fields: ["placement": placement.rawValue, "reason": "stale-context"]
                )
                return
            }
            self.radialFreeformPlacementCommitContext = nil
            let displays = Self.activeDisplays()
            guard self.isWorkspaceActive(commit.workspaceID),
                  self.workspaceLayout(for: commit.workspaceID) == .none,
                  self.interactionFocusedWindowSnapshot()?.key == commit.focusedWindow,
                  let display = displays.first(where: { $0.identifier == commit.displayIdentifier }),
                  display.usableBounds == commit.displayBounds,
                  var tracked = self.windows[commit.focusedWindow],
                  tracked.workspaceID == commit.workspaceID,
                  FullscreenSessionPolicy.allowsGeometryWrite(
                      hasFullscreenSession: self.fullscreenSessions[commit.focusedWindow] != nil,
                      isTemporarilyDeferred: self.temporarilyDeferredWindowKeys.contains(commit.focusedWindow)
                  ),
                  let currentFrame = AccessibilityWindow.frame(of: tracked.element),
                  AccessibilityWindow.framesMatch(currentFrame, commit.originalFrame)
            else {
                self.diagnostics.log(
                    category: "radial-menu",
                    event: "freeform-placement-rejected",
                    correlation: correlationID,
                    fields: ["placement": placement.rawValue, "reason": "runtime-context-changed"]
                )
                return
            }

            let focusToken = self.beginCorrelatedAction(
                correlationID: correlationID,
                interactionDisplayIdentifier: commit.displayIdentifier,
                expectedFocusTarget: commit.focusedWindow
            )
            self.prepareProgrammaticFocusIntent(commit.focusedWindow, correlationID: correlationID, duration: 0.8)
            self.applyFrameChanges(
                [FrameChange(window: tracked, frame: preview.targetFrame)],
                correlationID: correlationID
            )
            guard let appliedFrame = AccessibilityWindow.frame(of: tracked.element),
                  AccessibilityWindow.framesMatch(appliedFrame, preview.targetFrame)
            else {
                self.diagnostics.log(
                    category: "radial-menu",
                    event: "freeform-placement-rejected",
                    correlation: correlationID,
                    fields: ["placement": placement.rawValue, "reason": "frame-write-not-retained"]
                )
                self.emitCommandFeedback("Place was not accepted by this window.", correlationID: correlationID)
                return
            }
            tracked.restoreFrame = appliedFrame
            tracked.displayPlacement = Self.displayPlacement(for: appliedFrame, displays: displays)
            self.windows[tracked.key] = tracked
            self.lastFocusedWindow[commit.workspaceID] = commit.focusedWindow
            self.persistState(preservingPendingRestores: true)
            self.emitState()
            self.emitCommandFeedback("Place: \(placement.title)", correlationID: correlationID)
            self.diagnostics.log(
                category: "radial-menu",
                event: "freeform-placement-committed",
                correlation: correlationID,
                fields: [
                    "placement": placement.rawValue,
                    "workspace": Self.shortIdentifier(commit.workspaceID.uuidString),
                    "display": Self.shortIdentifier(commit.displayIdentifier),
                    "window": Self.diagnosticWindowKey(commit.focusedWindow),
                    "from-frame": Self.diagnosticFrame(commit.originalFrame),
                    "to-frame": Self.diagnosticFrame(appliedFrame),
                ]
            )
            if !AccessibilityWindow.framesMatch(commit.originalFrame, appliedFrame) {
                let transaction = FreeformPlacementUndoTransaction(
                    focusedWindow: commit.focusedWindow,
                    workspaceID: commit.workspaceID,
                    displayIdentifier: commit.displayIdentifier,
                    beforeFrame: commit.originalFrame,
                    afterFrame: appliedFrame,
                    actionName: "Place Window \(placement.title)"
                )
                DispatchQueue.main.async { [weak self] in
                    self?.onFreeformPlacementCommitted?(transaction)
                }
            }
            self.verifyFocusAfterAction(
                expected: commit.focusedWindow,
                correlationID: correlationID,
                action: "radial-freeform-place",
                token: focusToken,
                mayRecoverNilFocus: true
            )
        }
    }

    func applyFreeformPlacementHistory(
        _ transaction: FreeformPlacementUndoTransaction,
        direction: FreeformPlacementHistoryDirection,
        correlationID: String? = nil
    ) -> Bool {
        let correlationID = correlationID ?? diagnostics.makeCorrelationID()
        return queue.sync { () -> Bool in
            let displays = Self.activeDisplays()
            guard isWorkspaceActive(transaction.workspaceID),
                  workspaceLayout(for: transaction.workspaceID) == .none,
                  var tracked = windows[transaction.focusedWindow],
                  tracked.workspaceID == transaction.workspaceID,
                  FullscreenSessionPolicy.allowsGeometryWrite(
                      hasFullscreenSession: fullscreenSessions[transaction.focusedWindow] != nil,
                      isTemporarilyDeferred: temporarilyDeferredWindowKeys.contains(transaction.focusedWindow)
                  ),
                  displays.contains(where: { $0.identifier == transaction.displayIdentifier }),
                  let currentFrame = AccessibilityWindow.frame(of: tracked.element),
                  AccessibilityWindow.framesMatch(currentFrame, transaction.expectedFrame(for: direction))
            else {
                diagnostics.log(
                    category: "freeform-placement-history",
                    event: "rejected",
                    correlation: correlationID,
                    fields: ["direction": direction.rawValue, "reason": "context-or-frame-changed"]
                )
                return false
            }
            let target = transaction.targetFrame(for: direction)
            applyFrameChanges([FrameChange(window: tracked, frame: target)], correlationID: correlationID)
            guard let applied = AccessibilityWindow.frame(of: tracked.element),
                  AccessibilityWindow.framesMatch(applied, target)
            else { return false }
            tracked.restoreFrame = applied
            tracked.displayPlacement = Self.displayPlacement(for: applied, displays: displays)
            windows[tracked.key] = tracked
            persistState(preservingPendingRestores: true)
            emitState()
            emitCommandFeedback(
                direction == .undo
                    ? "Undid \(transaction.actionName.lowercased())."
                    : "Redid \(transaction.actionName.lowercased()).",
                correlationID: correlationID
            )
            diagnostics.log(
                category: "freeform-placement-history",
                event: "applied",
                correlation: correlationID,
                fields: ["direction": direction.rawValue, "window": Self.diagnosticWindowKey(tracked.key)]
            )
            return true
        }
    }

    /// The sole frame-writing boundary for radial and keyboard compass placement. Both inputs
    /// carry a pure proposal produced by `makeTiledPlacementCommitContext`; this method validates
    /// that captured identity before replacing the tree and applying one normal layout pass.
    @discardableResult
    private func commitTiledPlacement(
        _ commit: TiledPlacementCommitContext,
        placement: VisualPlacement,
        maximumAge: TimeInterval,
        diagnosticCategory: String,
        focusAction: String,
        feedback: String,
        correlationID: String,
        usesKeyboardFocusRetention: Bool
    ) -> Bool {
        guard Date().timeIntervalSince(commit.createdAt) <= maximumAge,
              let preview = commit.previews[placement]
        else {
            diagnostics.log(
                category: diagnosticCategory,
                event: "placement-rejected",
                correlation: correlationID,
                fields: ["placement": placement.rawValue, "reason": "stale-context"]
            )
            return false
        }
        let displays = Self.activeDisplays()
        guard displays.contains(where: { $0.identifier == commit.partition.displayIdentifier }),
              isWorkspaceActive(commit.partition.workspaceID),
              workspaceLayout(for: commit.partition.workspaceID) == .tiled,
              interactionFocusedWindowSnapshot()?.key == commit.focusedWindow
        else {
            diagnostics.log(
                category: diagnosticCategory,
                event: "placement-rejected",
                correlation: correlationID,
                fields: ["placement": placement.rawValue, "reason": "runtime-context-changed"]
            )
            if usesKeyboardFocusRetention {
                emitCommandFeedback(
                    "Corner placement cancelled because its context changed.",
                    correlationID: correlationID
                )
            }
            return false
        }
        let participants = orderedLayoutParticipants(
            workspaceID: commit.partition.workspaceID,
            displayIdentifier: commit.partition.displayIdentifier,
            displays: displays,
            correlationID: correlationID
        )
        let participantKeys = Set(participants)
        guard participantKeys == commit.participantKeys else {
            diagnostics.log(
                category: diagnosticCategory,
                event: "placement-rejected",
                correlation: correlationID,
                fields: ["placement": placement.rawValue, "reason": "participant-set-changed"]
            )
            if usesKeyboardFocusRetention {
                emitCommandFeedback(
                    "Corner placement cancelled because the Tiled windows changed.",
                    correlationID: correlationID
                )
            }
            return false
        }

        guard let display = displays.first(where: {
            $0.identifier == commit.partition.displayIdentifier
        }), let workspace = workspaces.first(where: {
            $0.id == commit.partition.workspaceID
        }) else {
            diagnostics.log(
                category: diagnosticCategory,
                event: "placement-rejected",
                correlation: correlationID,
                fields: ["placement": placement.rawValue, "reason": "partition-unavailable"]
            )
            return false
        }
        let configuration = workspace.layoutConfiguration ?? .aeroSpaceUserDefaults
        let managedBounds = managedLayoutBounds(display.usableBounds)
        guard let currentTree = TiledLayoutEngine.reconciled(
            tiledTrees[commit.partition],
            windowKeys: participants,
            weights: participants.map {
                CGFloat(Self.validLayoutWeight(windows[$0]?.layoutWeight))
            },
            orientation: configuration.orientation.resolved(for: managedBounds)
        ), currentTree == commit.originalTree else {
            diagnostics.log(
                category: diagnosticCategory,
                event: "placement-rejected",
                correlation: correlationID,
                fields: ["placement": placement.rawValue, "reason": "tree-changed"]
            )
            if usesKeyboardFocusRetention {
                emitCommandFeedback(
                    "Corner placement cancelled because the Tiled layout changed.",
                    correlationID: correlationID
                )
            }
            return false
        }
        guard (try? TiledLayoutEngine.validated(
            preview.proposedTree,
            participants: participantKeys
        )) != nil else {
            diagnostics.log(
                category: diagnosticCategory,
                event: "placement-rejected",
                correlation: correlationID,
                fields: ["placement": placement.rawValue, "reason": "invalid-proposal"]
            )
            return false
        }

        let previousFingerprint = TiledLayoutEngine.fingerprint(currentTree)
        let focusToken = beginCorrelatedAction(
            correlationID: correlationID,
            interactionDisplayIdentifier: commit.partition.displayIdentifier,
            expectedFocusTarget: commit.focusedWindow
        )
        prepareProgrammaticFocusIntent(commit.focusedWindow, correlationID: correlationID, duration: 0.8)
        tiledTrees[commit.partition] = preview.proposedTree
        let effectiveShares = TiledLayoutEngine.leafShares(preview.proposedTree) ?? [:]
        for (index, key) in preview.proposedTree.windowKeys.enumerated() {
            windows[key]?.layoutOrder = index
            windows[key]?.layoutWeight = effectiveShares[key] ?? 1
        }
        lastFocusedWindow[commit.partition.workspaceID] = commit.focusedWindow
        lastBackgroundLayoutSignature = nil
        let affectedWindows = windows.values.filter { tracked in
            guard tracked.workspaceID == commit.partition.workspaceID else { return false }
            return targetDisplay(
                for: tracked,
                workspaceID: commit.partition.workspaceID,
                displays: displays,
                correlationID: correlationID
            )?.identifier == commit.partition.displayIdentifier
        }
        applyVisibleWindows(
            affectedWindows,
            displays: displays,
            correlationID: correlationID
        )
        lastBackgroundLayoutSignature = backgroundLayoutSignature(displays: displays)
        persistState(preservingPendingRestores: true)
        emitState()
        emitCommandFeedback(feedback, correlationID: correlationID)
        diagnostics.log(
            category: diagnosticCategory,
            event: "placement-committed",
            correlation: correlationID,
            fields: [
                "placement": placement.rawValue,
                "workspace": Self.shortIdentifier(commit.partition.workspaceID.uuidString),
                "display": Self.shortIdentifier(commit.partition.displayIdentifier),
                "window": Self.diagnosticWindowKey(commit.focusedWindow),
                "tree-before": String(previousFingerprint.prefix(96)),
                "tree-after": String(preview.fingerprint.prefix(96)),
                "window-count": String(participantKeys.count),
            ]
        )
        if commit.originalTree != preview.proposedTree {
            let transaction = TiledPlacementUndoTransaction(
                partition: commit.partition,
                focusedWindow: commit.focusedWindow,
                participantKeys: commit.participantKeys,
                beforeTree: commit.originalTree,
                afterTree: preview.proposedTree,
                actionName: "Place Window \(placement.title)"
            )
            DispatchQueue.main.async { [weak self] in
                self?.onTiledPlacementCommitted?(transaction)
            }
        }
        if usesKeyboardFocusRetention {
            retainFocusAfterKeyboardManipulation(
                expected: commit.focusedWindow,
                correlationID: correlationID,
                action: focusAction,
                token: focusToken
            )
        } else {
            verifyFocusAfterAction(
                expected: commit.focusedWindow,
                correlationID: correlationID,
                action: focusAction,
                token: focusToken,
                mayRecoverNilFocus: true
            )
        }
        return true
    }

    /// Applies one NSUndoManager-owned placement history step. The caller is an app-owned menu
    /// action on the main thread; the synchronous queue hop lets UndoManager register the inverse
    /// only after the exact tree/participant validation has succeeded.
    func applyTiledPlacementHistory(
        _ transaction: TiledPlacementUndoTransaction,
        direction: TiledPlacementHistoryDirection,
        correlationID: String? = nil
    ) -> Bool {
        let correlationID = correlationID ?? diagnostics.makeCorrelationID()
        return queue.sync { () -> Bool in
            let displays = Self.activeDisplays()
            guard displays.contains(where: {
                $0.identifier == transaction.partition.displayIdentifier
            }), isWorkspaceActive(transaction.partition.workspaceID),
            workspaceLayout(for: transaction.partition.workspaceID) == .tiled
            else {
                diagnostics.log(
                    category: "tiled-placement-history",
                    event: "rejected",
                    correlation: correlationID,
                    fields: ["direction": direction.rawValue, "reason": "inactive-partition"]
                )
                return false
            }
            let participants = orderedLayoutParticipants(
                workspaceID: transaction.partition.workspaceID,
                displayIdentifier: transaction.partition.displayIdentifier,
                displays: displays,
                correlationID: correlationID
            )
            let participantKeys = Set(participants)
            guard let currentTree = tiledTrees[transaction.partition],
                  let targetTree = TiledLayoutEngine.historyTarget(
                      currentTree: currentTree,
                      currentParticipants: participantKeys,
                      transaction: transaction,
                      direction: direction
                  )
            else {
                diagnostics.log(
                    category: "tiled-placement-history",
                    event: "rejected",
                    correlation: correlationID,
                    fields: ["direction": direction.rawValue, "reason": "tree-or-membership-changed"]
                )
                return false
            }

            let focusTarget = interactionFocusedWindowSnapshot().flatMap { snapshot in
                participantKeys.contains(snapshot.key) ? snapshot.key : nil
            }
            let focusToken = focusTarget.map { key in
                beginCorrelatedAction(
                    correlationID: correlationID,
                    interactionDisplayIdentifier: transaction.partition.displayIdentifier,
                    expectedFocusTarget: key
                )
            }
            if let focusTarget {
                prepareProgrammaticFocusIntent(focusTarget, correlationID: correlationID, duration: 0.8)
                lastFocusedWindow[transaction.partition.workspaceID] = focusTarget
            }

            tiledTrees[transaction.partition] = targetTree
            let effectiveShares = TiledLayoutEngine.leafShares(targetTree) ?? [:]
            for (index, key) in targetTree.windowKeys.enumerated() {
                windows[key]?.layoutOrder = index
                windows[key]?.layoutWeight = effectiveShares[key] ?? 1
            }
            lastBackgroundLayoutSignature = nil
            let affectedWindows = windows.values.filter { tracked in
                guard tracked.workspaceID == transaction.partition.workspaceID else { return false }
                return targetDisplay(
                    for: tracked,
                    workspaceID: transaction.partition.workspaceID,
                    displays: displays,
                    correlationID: correlationID
                )?.identifier == transaction.partition.displayIdentifier
            }
            applyVisibleWindows(
                affectedWindows,
                displays: displays,
                correlationID: correlationID
            )
            lastBackgroundLayoutSignature = backgroundLayoutSignature(displays: displays)
            persistState(preservingPendingRestores: true)
            emitState()
            emitCommandFeedback(
                direction == .undo
                    ? "Undid \(transaction.actionName.lowercased())."
                    : "Redid \(transaction.actionName.lowercased()).",
                correlationID: correlationID
            )
            diagnostics.log(
                category: "tiled-placement-history",
                event: "applied",
                correlation: correlationID,
                fields: [
                    "direction": direction.rawValue,
                    "workspace": Self.shortIdentifier(transaction.partition.workspaceID.uuidString),
                    "display": Self.shortIdentifier(transaction.partition.displayIdentifier),
                    "tree": String(TiledLayoutEngine.fingerprint(targetTree).prefix(96)),
                ]
            )
            if let focusTarget, let focusToken {
                retainFocusAfterKeyboardManipulation(
                    expected: focusTarget,
                    correlationID: correlationID,
                    action: "tiled-placement-\(direction.rawValue)",
                    token: focusToken
                )
            }
            return true
        }
    }

    private func scheduleWakeReconciliationAttempt(
        generation: UInt64,
        afterMilliseconds delay: Int
    ) {
        wakeReconciliationWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.performWakeReconciliationAttempt(generation: generation)
        }
        wakeReconciliationWorkItem = workItem
        queue.asyncAfter(deadline: .now() + .milliseconds(delay), execute: workItem)
    }

    private func performWakeReconciliationAttempt(generation: UInt64) {
        guard wakeReconciliationState.isCurrent(generation) else { return }
        wakeReconciliationWorkItem = nil
        let correlationID = "wake-\(generation)"
        let sessionResult = stateStore.refreshWindowServerSession()
        let sessionAvailable: Bool
        switch sessionResult {
        case .unchanged:
            sessionAvailable = true
            windowServerSessionValidated = true
        case let .changed(previous, current):
            sessionAvailable = true
            windowServerSessionValidated = true
            clearWindowServerBoundStateAfterSessionChange()
            diagnostics.log(
                category: "lifecycle",
                event: "window-server-session-changed",
                correlation: correlationID,
                fields: [
                    "previous-session": Self.shortIdentifier(previous),
                    "current-session": Self.shortIdentifier(current),
                    "stale-window-state-retained": "false",
                ]
            )
        case .unavailable:
            sessionAvailable = false
            windowServerSessionValidated = false
        }

        let receivedAdditionalSignal = wakeReceivedAdditionalSignal
        wakeReceivedAdditionalSignal = false
        let report = refreshWindows(
            correlationID: correlationID,
            performAXWrites: false,
            observeFocus: false
        )
        let attempt = WakeReconciliationAttempt(
            attemptIndex: wakeAttemptIndex,
            previousTopologySignature: wakePreviousTopologySignature,
            currentTopologySignature: report.topologySignature,
            connectedDisplayCount: report.displays.count,
            requiredProcessIdentifiers: report.requiredProcessIdentifiers,
            successfullyEnumeratedProcessIdentifiers: report.successfullyEnumeratedProcessIdentifiers,
            receivedAdditionalLifecycleSignal: receivedAdditionalSignal,
            windowServerSessionAvailable: sessionAvailable
        )
        let decision = WakeReconciliationPolicy.decision(for: attempt)
        diagnostics.log(
            category: "lifecycle",
            event: "wake-reconciliation-attempt",
            correlation: correlationID,
            fields: [
                "attempt": String(wakeAttemptIndex + 1),
                "topology": report.topologySignature,
                "display-count": String(report.displays.count),
                "managed-window-count": String(report.managedWindowCount),
                "write-eligible-count": String(report.writeEligibleWindowKeys.count),
                "deferred-window-count": String(report.deferredWindowKeys.count),
                "required-process-count": String(report.requiredProcessIdentifiers.count),
                "enumerated-process-count": String(report.successfullyEnumeratedProcessIdentifiers.count),
                "session-available": String(sessionAvailable),
                "decision": String(describing: decision),
            ]
        )

        guard wakeReconciliationState.isCurrent(generation) else { return }
        switch decision {
        case .complete:
            finishWakeReconciliation(
                report: report,
                generation: generation,
                degradedReason: nil
            )
        case let .completeDegraded(reason):
            finishWakeReconciliation(
                report: report,
                generation: generation,
                degradedReason: reason
            )
        case let .retry(delay, reason):
            diagnostics.log(
                category: "lifecycle",
                event: "wake-reconciliation-retry-scheduled",
                correlation: correlationID,
                fields: [
                    "reason": reason,
                    "delay-ms": String(delay),
                ]
            )
            wakeAttemptIndex += 1
            wakePreviousTopologySignature = report.topologySignature
            scheduleWakeReconciliationAttempt(
                generation: generation,
                afterMilliseconds: delay
            )
        }
    }

    private func finishWakeReconciliation(
        report: WindowRefreshReport,
        generation: UInt64,
        degradedReason: String?
    ) {
        guard wakeReconciliationState.isCurrent(generation) else { return }
        let correlationID = "wake-\(generation)"

        if isWindowManagementPaused {
            persistState(preservingPendingRestores: true)
            emitState()
            completeWakeReconciliation(
                report: report,
                generation: generation,
                degradedReason: degradedReason,
                layoutApplyCount: 0,
                recordLayoutSignature: false
            )
            diagnostics.log(
                category: "pause-mode",
                event: "wake-writes-suppressed",
                correlation: correlationID
            )
            return
        }

        // Visibility and layout start from the final fresh snapshot. Deferred windows remain
        // tracked for a later successful enumeration but receive no AX writes now. Split frames
        // are verified separately because AX write success does not prove that an app retained them.
        var expectedLayoutFrames: [WindowKey: WindowFrame] = [:]
        if windowServerSessionValidated {
            expectedLayoutFrames = applyVisibility(
                displays: report.displays,
                correlationID: correlationID,
                eligibleWindowKeys: report.writeEligibleWindowKeys
            )
            reconcileDropDownAppSessionAfterWake(
                displays: report.displays,
                eligibleWindowKeys: report.writeEligibleWindowKeys,
                correlationID: correlationID
            )
            restoreFocusAfterWake(
                eligibleWindowKeys: report.writeEligibleWindowKeys,
                displays: report.displays,
                correlationID: correlationID
            )
            persistState(preservingPendingRestores: true)
        }
        emitState()

        guard windowServerSessionValidated, !expectedLayoutFrames.isEmpty else {
            completeWakeReconciliation(
                report: report,
                generation: generation,
                degradedReason: degradedReason,
                layoutApplyCount: windowServerSessionValidated ? 1 : 0,
                recordLayoutSignature: windowServerSessionValidated
            )
            return
        }

        scheduleWakeLayoutVerification(
            report: report,
            expectedFrames: expectedLayoutFrames,
            generation: generation,
            degradedReason: degradedReason,
            verificationAttemptIndex: 0,
            layoutApplyCount: 1
        )
    }

    private func scheduleWakeLayoutVerification(
        report: WindowRefreshReport,
        expectedFrames: [WindowKey: WindowFrame],
        generation: UInt64,
        degradedReason: String?,
        verificationAttemptIndex: Int,
        layoutApplyCount: Int
    ) {
        let delays = WakeLayoutVerificationPolicy.verificationDelaysMilliseconds
        let delay = delays[min(verificationAttemptIndex, delays.count - 1)]
        wakeReconciliationWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.verifyWakeLayout(
                report: report,
                expectedFrames: expectedFrames,
                generation: generation,
                degradedReason: degradedReason,
                verificationAttemptIndex: verificationAttemptIndex,
                layoutApplyCount: layoutApplyCount
            )
        }
        wakeReconciliationWorkItem = workItem
        queue.asyncAfter(deadline: .now() + .milliseconds(delay), execute: workItem)
    }

    private func verifyWakeLayout(
        report: WindowRefreshReport,
        expectedFrames: [WindowKey: WindowFrame],
        generation: UInt64,
        degradedReason: String?,
        verificationAttemptIndex: Int,
        layoutApplyCount: Int
    ) {
        guard wakeReconciliationState.isCurrent(generation) else { return }
        wakeReconciliationWorkItem = nil
        let correlationID = "wake-\(generation)"
        if isWindowManagementPaused {
            completeWakeReconciliation(
                report: report,
                generation: generation,
                degradedReason: degradedReason,
                layoutApplyCount: layoutApplyCount,
                recordLayoutSignature: false
            )
            diagnostics.log(
                category: "pause-mode",
                event: "wake-verification-suppressed",
                correlation: correlationID
            )
            return
        }

        // A signal arriving after the layout solve invalidates its display snapshot. Start a fresh
        // readiness attempt in the same generation instead of verifying obsolete geometry.
        if wakeReceivedAdditionalSignal {
            wakeAttemptIndex = 0
            wakePreviousTopologySignature = report.topologySignature
            diagnostics.log(
                category: "lifecycle",
                event: "wake-layout-verification-superseded",
                correlation: correlationID,
                fields: ["reason": "new-lifecycle-signal"]
            )
            scheduleWakeReconciliationAttempt(generation: generation, afterMilliseconds: 0)
            return
        }

        let stillEligibleExpectedFrames = expectedFrames.filter { key, _ in
            guard let tracked = windows[key],
                  isWorkspaceActive(tracked.workspaceID),
                  workspaceLayout(for: tracked.workspaceID) != .none,
                  Self.shouldIncludeInLayout(
                    layoutOverride: tracked.layoutOverride,
                    admissionDecision: tracked.admissionDecision,
                    rule: resolvedRule(for: tracked.bundleIdentifier)
                  )
            else { return false }
            return FullscreenSessionPolicy.allowsGeometryWrite(
                hasFullscreenSession: fullscreenSessions[key] != nil,
                isTemporarilyDeferred: temporarilyDeferredWindowKeys.contains(key)
            )
        }
        let observedFrames = Dictionary(uniqueKeysWithValues: stillEligibleExpectedFrames.keys.compactMap {
            key -> (WindowKey, WindowFrame)? in
            guard let tracked = windows[key],
                  let frame = AccessibilityWindow.frame(of: tracked.element)
            else { return nil }
            return (key, frame)
        })
        let mismatchedKeys = WakeLayoutVerificationPolicy.mismatchedWindowKeys(
            expectedFrames: stillEligibleExpectedFrames,
            observedFrames: observedFrames
        )
        diagnostics.log(
            category: "lifecycle",
            event: "wake-layout-verification",
            correlation: correlationID,
            fields: [
                "attempt": String(verificationAttemptIndex + 1),
                "target-count": String(stillEligibleExpectedFrames.count),
                "mismatch-count": String(mismatchedKeys.count),
            ]
        )

        guard !mismatchedKeys.isEmpty else {
            completeWakeReconciliation(
                report: report,
                generation: generation,
                degradedReason: degradedReason,
                layoutApplyCount: layoutApplyCount,
                recordLayoutSignature: true
            )
            return
        }

        let nextAttempt = verificationAttemptIndex + 1
        guard nextAttempt < WakeLayoutVerificationPolicy.verificationDelaysMilliseconds.count else {
            for key in mismatchedKeys {
                diagnostics.log(
                    category: "lifecycle",
                    event: "wake-layout-frame-mismatch",
                    correlation: correlationID,
                    fields: [
                        "window": Self.diagnosticWindowKey(key),
                        "expected-frame": stillEligibleExpectedFrames[key]
                            .map(Self.diagnosticFrame) ?? "unknown",
                        "observed-frame": observedFrames[key]
                            .map(Self.diagnosticFrame) ?? "unavailable",
                    ]
                )
            }
            let reason = [degradedReason, "layout-frame-mismatch"]
                .compactMap { $0 }
                .joined(separator: ",")
            completeWakeReconciliation(
                report: report,
                generation: generation,
                degradedReason: reason,
                layoutApplyCount: layoutApplyCount,
                recordLayoutSignature: false
            )
            return
        }

        let retryChanges = mismatchedKeys.compactMap { key -> FrameChange? in
            guard let tracked = windows[key], let frame = stillEligibleExpectedFrames[key] else {
                return nil
            }
            return FrameChange(window: tracked, frame: frame)
        }
        applyFrameChanges(retryChanges, correlationID: correlationID)
        diagnostics.log(
            category: "lifecycle",
            event: "wake-layout-retry-scheduled",
            correlation: correlationID,
            fields: [
                "delay-ms": String(
                    WakeLayoutVerificationPolicy.verificationDelaysMilliseconds[nextAttempt]
                ),
                "window-count": String(retryChanges.count),
            ]
        )
        scheduleWakeLayoutVerification(
            report: report,
            expectedFrames: stillEligibleExpectedFrames,
            generation: generation,
            degradedReason: degradedReason,
            verificationAttemptIndex: nextAttempt,
            layoutApplyCount: layoutApplyCount + 1
        )
    }

    private func completeWakeReconciliation(
        report: WindowRefreshReport,
        generation: UInt64,
        degradedReason: String?,
        layoutApplyCount: Int,
        recordLayoutSignature: Bool
    ) {
        guard wakeReconciliationState.isCurrent(generation) else { return }
        let correlationID = "wake-\(generation)"
        if recordLayoutSignature {
            lastBackgroundLayoutSignature = backgroundLayoutSignature(displays: report.displays)
        } else {
            lastBackgroundLayoutSignature = nil
        }
        _ = wakeReconciliationState.complete(generation: generation)
        wakeReconciliationWorkItem = nil
        if degradedReason == nil {
            lastWakeCompletionDate = Date()
            lastWakeCompletedTopologySignature = report.topologySignature
        } else {
            lastWakeCompletionDate = .distantPast
            lastWakeCompletedTopologySignature = nil
        }
        diagnostics.log(
            category: "lifecycle",
            event: "wake-reconciliation-complete",
            correlation: correlationID,
            fields: [
                "result": degradedReason == nil ? "complete" : "degraded",
                "reason": degradedReason ?? "ready",
                "active-workspaces": diagnosticActiveWorkspaceMap(),
                "deferred-window-count": String(report.deferredWindowKeys.count),
                "layout-apply-count": String(layoutApplyCount),
            ]
        )
    }

    private func restoreFocusAfterWake(
        eligibleWindowKeys: Set<WindowKey>,
        displays: [DisplaySnapshot],
        correlationID: String
    ) {
        let rawFocus = focusedWindowSnapshot()
        let currentManagedFocus = rawFocus.flatMap { snapshot -> WindowKey? in
            guard let tracked = windows[snapshot.key],
                  !isExcludedFromWorkspaceParticipation(tracked)
            else { return nil }
            return snapshot.key
        }
        let currentFocusIsUnmanaged = rawFocus.map {
            guard let tracked = windows[$0.key] else { return true }
            return ignoredWindowKeys.contains($0.key) ||
                isExcludedFromWorkspaceParticipation(tracked)
        } ?? false
        let targetDisplayIdentifier: String? = {
            if let preferred = preSleepFocusContext?.displayIdentifier,
               displays.contains(where: { $0.identifier == preferred }) {
                return preferred
            }
            return displays.first(where: \.isMain)?.identifier ?? displays.first?.identifier
        }()

        let ordered = windows.values
            .filter {
                Self.shouldIncludeInWakeFocusRecovery(
                    isWriteEligible: eligibleWindowKeys.contains($0.key),
                    isExcludedFromWorkspaceParticipation:
                        isExcludedFromWorkspaceParticipation($0)
                )
            }
            .sorted { lhs, rhs in
                if lhs.layoutOrder != rhs.layoutOrder { return lhs.layoutOrder < rhs.layoutOrder }
                return lhs.key.windowIdentifier < rhs.key.windowIdentifier
            }
        let candidates: [WakeFocusCandidate<WindowKey>] = ordered.map { tracked in
            let rule = resolvedRule(for: tracked.bundleIdentifier)
            let frame = AccessibilityWindow.frame(of: tracked.element)
            let displayIdentifier = frame.flatMap {
                Self.displayPlacement(for: $0, displays: displays)?.displayIdentifier
            }
            let capabilities = AccessibilityWindow.focusCapabilities(
                of: tracked.element,
                processIdentifier: tracked.processIdentifier,
                windowIdentifier: tracked.key.windowIdentifier
            )
            return WakeFocusCandidate(
                key: tracked.key,
                isActiveWorkspace: Self.shouldWindowBeVisible(
                    workspaceID: tracked.workspaceID,
                    activeWorkspaceIDs: activeWorkspaceIDs,
                    rule: rule
                ),
                isMeaningfullyVisible: frame.map {
                    Self.isMeaningfullyVisible($0, displays: displays)
                } ?? false,
                isOnInteractionDisplay: targetDisplayIdentifier == nil ||
                    displayIdentifier == targetDisplayIdentifier,
                isFocusEligible: AccessibilityWindow.isEligibleFocusCycleCandidate(capabilities)
            )
        }
        let replacement = WakeFocusPolicy.replacement(
            currentManagedFocus: currentManagedFocus,
            currentFocusIsUnmanaged: currentFocusIsUnmanaged,
            preSleepFocus: preSleepFocusContext?.windowKey,
            orderedCandidates: candidates
        )
        guard let replacement, let tracked = windows[replacement] else {
            diagnostics.log(
                category: "lifecycle",
                event: "wake-focus-preserved",
                correlation: correlationID,
                fields: [
                    "current-window": rawFocus.map { Self.diagnosticWindowKey($0.key) } ?? "none",
                    "reason": currentFocusIsUnmanaged ? "user-or-unmanaged-focus" : "valid-or-no-local-candidate",
                ]
            )
            preSleepFocusContext = nil
            return
        }

        focusManagedWindow(replacement, tracked: tracked, correlationID: correlationID)
        lastObservedFocusedWindow = replacement
        lastFocusedWindow[tracked.workspaceID] = replacement
        diagnostics.log(
            category: "lifecycle",
            event: "wake-focus-restored",
            correlation: correlationID,
            fields: [
                "window": Self.diagnosticWindowKey(replacement),
                "workspace": Self.shortIdentifier(tracked.workspaceID.uuidString),
                "display": targetDisplayIdentifier.map(Self.shortIdentifier) ?? "none",
            ]
        )
        preSleepFocusContext = nil
    }

    private func reconcileDropDownAppSessionAfterWake(
        displays: [DisplaySnapshot],
        eligibleWindowKeys: Set<WindowKey>,
        correlationID: String
    ) {
        for bundleIdentifier in Array(quickAppSessions.keys) {
            reconcileQuickAppSessionAfterWake(
                bundleIdentifier: bundleIdentifier,
                displays: displays,
                eligibleWindowKeys: eligibleWindowKeys,
                correlationID: correlationID
            )
        }
        if let selected = dropDownAppSession,
           selected.isPresented,
           quickAppSessions.values
               .filter(\.isPresented)
               .allSatisfy({ session in
                   session.windowKeys.allSatisfy(eligibleWindowKeys.contains)
               }),
           let display = selected.displayIdentifier.flatMap({ identifier in
               displays.first { $0.identifier == identifier }
           }) ?? dropDownTargetDisplay(displays: displays) {
            layoutPresentedQuickAppGroup(
                display: display,
                correlationID: correlationID,
                focusSelected: false
            )
        }
    }

    private func reconcileQuickAppSessionAfterWake(
        bundleIdentifier: String,
        displays: [DisplaySnapshot],
        eligibleWindowKeys: Set<WindowKey>,
        correlationID: String
    ) {
        guard var session = quickAppSessions[bundleIdentifier],
              let configuration = quickAppConfigurations.first(where: {
                  Self.normalizedBundleIdentifier($0.bundleIdentifier) == bundleIdentifier
              }),
              let target = windows[session.windowKey]
        else { return }

        dropDownAnimationGeneration &+= 1
        let geometryWriteSucceeded: Bool
        if session.isPresented {
            guard session.windowKeys.allSatisfy(eligibleWindowKeys.contains) else { return }
            guard let display = session.displayIdentifier.flatMap({ identifier in
                      displays.first { $0.identifier == identifier }
                  }) ?? dropDownTargetDisplay(displays: displays)
            else { return }
            session.displayIdentifier = display.identifier
            quickAppSessions[bundleIdentifier] = session
            geometryWriteSucceeded = setDropDownAppFrame(
                DropDownAppGeometry.presentedFrame(
                    in: dropDownAppPresentationBounds(for: display),
                    sizeFraction: configuration.heightFraction,
                    direction: session.direction
                ),
                target: target
            )
        } else {
            geometryWriteSucceeded = requestDropDownApplicationHidden(
                true,
                processIdentifier: target.processIdentifier,
                bundleIdentifier: session.bundleIdentifier
            )
            session.isApplicationHiddenByWindowRanger = geometryWriteSucceeded
            quickAppSessions[bundleIdentifier] = session
        }

        diagnostics.log(
            category: "drop-down-app",
            event: "wake-session-restored",
            correlation: correlationID,
            fields: [
                "window": Self.diagnosticWindowKey(target.key),
                "presented": String(session.isPresented),
                "display": session.displayIdentifier ?? "none",
                "geometry-write": String(geometryWriteSucceeded),
                "hidden-state": session.isPresented
                    ? "visible"
                    : session.isApplicationHiddenByWindowRanger ? "application-hidden" : "unverified",
            ]
        )
    }

    private func invalidateFocusWorkForLifecycle() {
        _ = advanceFocusActionGeneration()
        pendingFocusVerification?.cancel()
        pendingFocusVerification = nil
        clearProgrammaticFocusIntent()
        supersededProgrammaticActivationUntil.removeAll()
        recentInteractionFocusTarget = nil
        recentInteractionDisplayIdentifier = nil
        recentInteractionDisplayDeadline = .distantPast
    }

    private func clearWindowServerBoundStateAfterSessionChange() {
        cancelManualTiledPreviewTransactions(reason: "window-server-session-changed")
        windows.removeAll()
        pendingRestoredWindows.removeAll()
        ignoredWindowKeys.removeAll()
        admissionDecisionByWindow.removeAll()
        admissionMetadataByWindow.removeAll()
        rejectedResizeRecoveryAttemptedWindowKeys.removeAll()
        resizeRecoveryNeedsImmediateReflow = false
        lastKnownWindowLayer.removeAll()
        lastFocusedWindow.removeAll()
        lastObservedFocusedWindow = nil
        lastDiagnosticFocusedWindow = nil
        temporarilyDeferredWindowKeys.removeAll()
        retainedLayoutSlotWindowKeys.removeAll()
        fullscreenSessions.removeAll()
        fullscreenAuthoritativeFalseCounts.removeAll()
        foregroundFullscreenGameSessionKey = nil
        emitFullscreenGameSessionIfNeeded()
        focusCycleRejectedUntil.removeAll()
        staleParkedFocusSuppression.removeAll()
        lastAutomaticUnhideAttemptByProcess.removeAll()
        postSleepWindowRecoveryState.clear()
        pendingRestoredDropDownAppSessions.removeAll()
        tiledTrees.removeAll()
        lastSolvedTiledFrames.removeAll()
        radialPlacementCommitContext = nil
        radialFreeformPlacementCommitContext = nil
        directionalMoveGestureContext = nil
        manualTiledDragSession = nil
        invalidateFocusWorkForLifecycle()
    }

    @discardableResult
    private func refreshWindows(
        isStartup: Bool = false,
        followExternalFocus: Bool = false,
        correlationID: String? = nil,
        performAXWrites: Bool = true,
        observeFocus: Bool = true
    ) -> WindowRefreshReport {
        let performAXWrites = performAXWrites && !isWindowManagementPaused
        lastBroadWindowRefreshDate = Date()
        reconcileIgnoredQuickAppVisibilityRecoveries(correlationID: correlationID)
        let displays = Self.activeDisplays()
        let topologySignature = Self.displayTopologySignature(displays)
        if wakeReconciliationState.isSleeping {
            let deferredWindowKeys = Set(windows.keys)
            temporarilyDeferredWindowKeys = deferredWindowKeys
            let retained = Set(windows.values.compactMap { tracked in
                isManagedLayoutParticipant(tracked) ? tracked.key : nil
            })
            retainedLayoutSlotWindowKeys = retained
            return WindowRefreshReport(
                displays: displays,
                topologySignature: topologySignature,
                requiredProcessIdentifiers: Set(windows.keys.map(\.processIdentifier)),
                successfullyEnumeratedProcessIdentifiers: [],
                writeEligibleWindowKeys: [],
                deferredWindowKeys: deferredWindowKeys,
                retainedLayoutSlotWindowKeys: retained,
                managedWindowCount: windows.count
            )
        }
        let displayBounds = displays.map(\.bounds)
        let topologyChanged = displays != lastDisplays
        lastDisplays = displays
        guard AXIsProcessTrusted() else {
            let required = Set(windows.keys.map(\.processIdentifier))
            let retained = Set(windows.values.compactMap { tracked in
                isManagedLayoutParticipant(tracked) ? tracked.key : nil
            })
            temporarilyDeferredWindowKeys = Set(windows.keys)
            retainedLayoutSlotWindowKeys = retained
            return WindowRefreshReport(
                displays: displays,
                topologySignature: topologySignature,
                requiredProcessIdentifiers: required,
                successfullyEnumeratedProcessIdentifiers: [],
                writeEligibleWindowKeys: [],
                deferredWindowKeys: Set(windows.keys),
                retainedLayoutSlotWindowKeys: retained,
                managedWindowCount: windows.count
            )
        }
        if topologyChanged,
           let recentInteractionDisplayIdentifier,
           !displays.contains(where: { $0.identifier == recentInteractionDisplayIdentifier }) {
            self.recentInteractionDisplayIdentifier = nil
            recentInteractionFocusTarget = nil
            recentInteractionDisplayDeadline = .distantPast
        }
        reconcileIndependentActiveWorkspaces(displays: displays)
        let validWorkspaceIDs = Set(workspaces.map(\.id))
        let runningApplications = NSWorkspace.shared.runningApplications.filter {
            Self.shouldDiscoverApplication(
                processIdentifier: $0.processIdentifier,
                ownProcessIdentifier: ownProcessIdentifier,
                isRegularApplication: $0.activationPolicy == .regular,
                isTerminated: $0.isTerminated
            )
        }
        let runningProcessIdentifiers = Set(runningApplications.map(\.processIdentifier))
        let requiredProcessIdentifiers = Set(windows.keys.map(\.processIdentifier))
            .intersection(runningProcessIdentifiers)
        let trackedWindowKeysBeforeEnumeration = Set(windows.keys)
        let visibleWindowLayers = AccessibilityWindow.visibleWindowLayers()
        var successfullyEnumeratedProcesses = Set<pid_t>()
        var enumeratedWindowKeys = Set<WindowKey>()
        var writeEligibleWindowKeys = Set<WindowKey>()
        var deferredWindowKeys = Set<WindowKey>()
        var retainedLayoutSlotReasons: [WindowKey: StableLayoutSlotRetentionReason] = [:]
        var observedFrames: [WindowKey: WindowFrame] = [:]
        var evictedIgnoredManagedState = false

        for app in runningApplications {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            guard let appWindows = AccessibilityWindow.copyAttribute(
                appElement,
                kAXWindowsAttribute as CFString,
                as: [AXUIElement].self
            ) else { continue }
            successfullyEnumeratedProcesses.insert(app.processIdentifier)

            for element in appWindows {
                guard let key = AccessibilityWindow.identifier(for: element, processIdentifier: app.processIdentifier)
                else { continue }
                enumeratedWindowKeys.insert(key)

                let visibleLayer = visibleWindowLayers?[key.windowIdentifier]
                let directlyResolvedLayer: Int?
                if visibleLayer == nil,
                   lastKnownWindowLayer[key] == nil,
                   AccessibilityWindow.mayNeedDirectLayerResolutionForCompatibility(app.bundleIdentifier) {
                    // Upgrade recovery: an old build may already have parked a popup outside the
                    // visible WindowServer list. Resolve only allowlisted apps individually once;
                    // nil remains genuinely unknown and is admitted conservatively.
                    directlyResolvedLayer = AccessibilityWindow.windowLayer(for: key.windowIdentifier)
                } else {
                    directlyResolvedLayer = nil
                }
                let observedLayer = visibleLayer ?? directlyResolvedLayer
                if let observedLayer {
                    lastKnownWindowLayer[key] = observedLayer
                }
                let effectiveLayer = observedLayer ?? lastKnownWindowLayer[key]
                let fullscreenObservation = AccessibilityWindow.fullscreenObservation(of: element)
                let fullscreenResolution = FullscreenSessionPolicy.resolve(
                    observation: fullscreenObservation,
                    hadSession: fullscreenSessions[key] != nil,
                    consecutiveAuthoritativeFalseObservations:
                        fullscreenAuthoritativeFalseCounts[key] ?? 0
                )
                if fullscreenResolution.consecutiveAuthoritativeFalseObservations == 0 {
                    fullscreenAuthoritativeFalseCounts.removeValue(forKey: key)
                } else {
                    fullscreenAuthoritativeFalseCounts[key] =
                        fullscreenResolution.consecutiveAuthoritativeFalseObservations
                }
                let coreAdmissionMetadata = AccessibilityWindow.admissionMetadata(
                    of: element,
                    bundleIdentifier: app.bundleIdentifier,
                    windowLayer: effectiveLayer,
                    fullscreenObservation: fullscreenObservation,
                    effectiveFullscreen: fullscreenResolution.isFullscreen
                )
                let retainedAdmissionMetadata = coreAdmissionMetadata.retainingSupportEvidence(
                    from: admissionMetadataByWindow[key]
                )
                let collectsCompatibilitySupportMetadata = AccessibilityWindow
                    .shouldCollectSupportMetadataForCompatibility(coreAdmissionMetadata)
                let collectsFixedSizeSupportMetadata = AccessibilityWindow
                    .shouldCollectFixedSizeSupportMetadata(
                        coreMetadata: coreAdmissionMetadata,
                        retainedMetadata: retainedAdmissionMetadata
                    )
                let collectsStandardDialogSupportMetadata = AccessibilityWindow
                    .shouldCollectStandardWindowDialogSupportMetadata(
                        coreMetadata: coreAdmissionMetadata,
                        retainedMetadata: retainedAdmissionMetadata
                    )
                let collectsSupportMetadata = collectsCompatibilitySupportMetadata ||
                    collectsFixedSizeSupportMetadata ||
                    collectsStandardDialogSupportMetadata
                let admissionMetadata = collectsSupportMetadata
                    ? AccessibilityWindow.admissionSupportMetadata(
                        of: element,
                        coreMetadata: coreAdmissionMetadata
                    )
                    : retainedAdmissionMetadata
                let genericAdmissionDecision = AccessibilityWindow.admissionDecision(for: admissionMetadata)
                let admissionDecision = rejectedResizeRecoveryAttemptedWindowKeys.contains(key)
                    ? AccessibilityWindow.fixedSizeDecisionAfterRejectedResize(admissionMetadata)
                        ?? genericAdmissionDecision
                    : genericAdmissionDecision
                let previousAdmissionDecision = admissionDecisionByWindow[key]
                var recordedAdmissionMetadata = admissionMetadata
                if previousAdmissionDecision != admissionDecision,
                   !admissionDecision.disposition.admitsNewWindow,
                   admissionDecision.reason != .minimized,
                   admissionDecision.reason != .fullscreen {
                    // Ignored or unsupported surfaces are not retained as managed windows, so this
                    // transition is the only safe opportunity to capture their fixture evidence.
                    recordedAdmissionMetadata = AccessibilityWindow.admissionSupportMetadata(
                        of: element,
                        coreMetadata: admissionMetadata
                    )
                }
                let observedFrame = AccessibilityWindow.frame(of: element)
                if let observedFrame {
                    observedFrames[key] = observedFrame
                }
                if let tracked = windows[key],
                   isManagedLayoutParticipant(tracked),
                   Self.shouldIncludeInLayout(
                       layoutOverride: tracked.layoutOverride,
                       admissionDecision: admissionDecision,
                       rule: resolvedRule(for: tracked.bundleIdentifier)
                   ),
                   let reason = StableLayoutSlotPolicy.retentionReason(
                       wasTracked: true,
                       applicationEnumerationSucceeded: true,
                       windowWasEnumerated: true,
                       isCurrentlyIncludedInLayout: true,
                       hasReadableFrame: observedFrame != nil
                   ) {
                    retainedLayoutSlotReasons[key] = reason
                }
                reconcileFullscreenSession(
                    key: key,
                    element: element,
                    application: app,
                    metadata: admissionMetadata,
                    observedFrame: observedFrame,
                    displays: displays,
                    correlationID: correlationID
                )
                recordAdmissionDecision(
                    admissionDecision,
                    metadata: recordedAdmissionMetadata,
                    key: key,
                    layerSource: visibleLayer != nil
                        ? "window-server-batch"
                        : directlyResolvedLayer != nil
                            ? "window-server-direct"
                            : effectiveLayer != nil ? "cached" : "unknown",
                    correlationID: correlationID
                )

                if admissionDecision.disposition.evictsTrackedWindow {
                    ignoredWindowKeys.insert(key)
                    let removal = evictIgnoredWindow(
                        key,
                        bundleIdentifier: app.bundleIdentifier,
                        decision: admissionDecision,
                        metadata: recordedAdmissionMetadata,
                        correlationID: correlationID
                    )
                    evictedIgnoredManagedState = evictedIgnoredManagedState || removal.changedManagedState
                    continue
                }
                ignoredWindowKeys.remove(key)

                let candidateBundleKey = Self.normalizedBundleIdentifier(app.bundleIdentifier ?? "")
                let isConfiguredQuickApp = quickAppConfigurations.contains {
                    Self.normalizedBundleIdentifier($0.bundleIdentifier) == candidateBundleKey
                }
                let isPersistedHiddenQuickApp = DropDownAppHiddenSessionRecoveryPolicy.matches(
                    isConfiguredQuickApp ? pendingRestoredDropDownAppSessions[candidateBundleKey] : nil,
                    windowKey: key,
                    bundleIdentifier: app.bundleIdentifier,
                    isStartup: isStartup,
                    isApplicationHidden: app.isHidden
                )

                // Temporarily unusual AX objects retain existing state. The one exception is an
                // exact Quick App window whose WindowServer-bound state says WindowRanger hid its
                // application; admit it only far enough to recover that hidden session.
                guard admissionDecision.disposition.admitsNewWindow || isPersistedHiddenQuickApp,
                      let frame = observedFrame
                else {
                    if windows[key] != nil { deferredWindowKeys.insert(key) }
                    continue
                }
                if isPersistedHiddenQuickApp {
                    deferredWindowKeys.insert(key)
                } else if WakeWindowRecoveryPolicy.isWriteEligible(
                    wasFreshlyEnumerated: true,
                    disposition: admissionDecision.disposition
                ) {
                    writeEligibleWindowKeys.insert(key)
                }

                if var tracked = windows[key] {
                    tracked.element = element
                    tracked.processIdentifier = app.processIdentifier
                    tracked.bundleIdentifier = app.bundleIdentifier
                    let previousAdmissionDecision = tracked.admissionDecision
                    tracked.admissionDecision = admissionDecision
                    let rule = resolvedRule(for: tracked.bundleIdentifier)
                    tracked.workspaceID = Self.workspaceIDAfterRuleRefresh(
                        currentWorkspaceID: tracked.workspaceID,
                        assignedWorkspaceID: rule.assignedWorkspaceID,
                        manualOverrideActive: tracked.workspaceRuleOverrideActive
                    )
                    let layoutDecision = Self.layoutDecision(
                        layoutOverride: tracked.layoutOverride,
                        admissionDecision: tracked.admissionDecision,
                        rule: rule
                    )
                    if !isDropDownAppWindow(key),
                       !isExcludedFromWorkspaceParticipation(tracked),
                       isWorkspaceActive(tracked.workspaceID),
                       (workspaceLayout(for: tracked.workspaceID) == .none ||
                        !layoutDecision.includesInLayout ||
                        previousAdmissionDecision.automaticallyFloats != admissionDecision.automaticallyFloats),
                       Self.recoveryPosition(for: frame, displayBounds: displayBounds) == frame.position,
                       !topologyChanged,
                       let actualPlacement = Self.displayPlacement(for: frame, displays: displays) {
                        let preferredDisplayIsMissing = tracked.displayPlacement.map {
                            placement in !displays.contains { $0.identifier == placement.displayIdentifier }
                        } ?? false
                        let independentHome = displayMode == .independent && !rule.keepsOnAllWorkspaces
                            ? workspaceHomeDisplayIdentifier(for: tracked.workspaceID, displays: displays)
                            : nil
                        if !preferredDisplayIsMissing,
                           independentHome == nil || actualPlacement.displayIdentifier == independentHome {
                            tracked.restoreFrame = frame
                            tracked.displayPlacement = actualPlacement
                        }
                    }
                    windows[key] = tracked
                } else {
                    let remembered = pendingRestoredWindows[String(key.windowIdentifier)].flatMap { assignment in
                        guard let bundleIdentifier = app.bundleIdentifier,
                              assignment.bundleIdentifier == bundleIdentifier,
                              validWorkspaceIDs.contains(assignment.workspaceID)
                        else { return nil as PersistedWindowAssignment? }
                        return assignment
                    }
                    if remembered != nil {
                        pendingRestoredWindows.removeValue(forKey: String(key.windowIdentifier))
                    }

                    var desiredFrame = remembered?.restoreFrame ?? frame
                    var placement = remembered?.displayPlacement
                        ?? Self.displayPlacement(for: desiredFrame, displays: displays)
                    if remembered == nil,
                       Self.recoveryPosition(for: desiredFrame, displayBounds: displayBounds) != desiredFrame.position {
                        desiredFrame = WindowFrame(
                            position: Self.recoveryPosition(for: desiredFrame, displayBounds: displayBounds),
                            size: desiredFrame.size
                        )
                        placement = Self.displayPlacement(for: desiredFrame, displays: displays)
                    }
                    let fallbackWorkspaceID = remembered?.workspaceID ?? Self.initialWorkspaceID(
                        for: placement?.displayIdentifier,
                        mode: displayMode,
                        currentWorkspaceID: currentWorkspaceID,
                        activeWorkspaceIDByDisplay: activeWorkspaceIDByDisplay
                    )
                    let rule = resolvedRule(for: app.bundleIdentifier)
                    let workspaceID = Self.routedWorkspaceID(
                        fallbackWorkspaceID: fallbackWorkspaceID,
                        rule: rule
                    )
                    let tracked = TrackedWindow(
                        key: key,
                        element: element,
                        processIdentifier: app.processIdentifier,
                        bundleIdentifier: app.bundleIdentifier,
                        workspaceID: workspaceID,
                        restoreFrame: desiredFrame,
                        displayPlacement: placement,
                        layoutOverride: Self.restoredLayoutOverride(remembered?.layoutOverride),
                        workspaceRuleOverrideActive: false,
                        admissionDecision: admissionDecision,
                        layoutOrder: remembered?.layoutOrder ?? self.nextLayoutOrder(in: workspaceID),
                        layoutWeight: Self.validLayoutWeight(remembered?.layoutWeight)
                    )
                    windows[key] = tracked

                    if isPersistedHiddenQuickApp { continue }

                    let layoutDecision = Self.layoutDecision(
                        layoutOverride: tracked.layoutOverride,
                        admissionDecision: tracked.admissionDecision,
                        rule: rule
                    )
                    if performAXWrites, Self.shouldWindowBeVisible(
                        workspaceID: workspaceID,
                        activeWorkspaceIDs: activeWorkspaceIDs,
                        rule: rule
                    ), workspaceLayout(for: workspaceID) == .none ||
                        !layoutDecision.includesInLayout ||
                        !isWorkspaceActive(workspaceID) {
                        applyVisibleWindows(
                            [tracked],
                            displays: displays,
                            correlationID: correlationID
                        )
                    } else if performAXWrites,
                              !isWorkspaceActive(workspaceID) && !rule.keepsOnAllWorkspaces {
                        applyPositionChanges(
                            [PositionChange(window: tracked, position: parkingPosition(displays: displays))],
                            correlationID: correlationID
                        )
                    }
                }
            }
        }

        let wasPostSleepWindowRecoveryActive = postSleepWindowRecoveryState.isActive
        let postSleepRecoveryUpdate = postSleepWindowRecoveryState.observe(
            runningProcessIdentifiers: runningProcessIdentifiers,
            successfullyEnumeratedProcessIdentifiers: successfullyEnumeratedProcesses,
            enumeratedWindowKeys: enumeratedWindowKeys
        )
        successfullyEnumeratedProcesses = postSleepRecoveryUpdate
            .authoritativeSuccessfullyEnumeratedProcessIdentifiers
        deferredWindowKeys.formUnion(postSleepRecoveryUpdate.protectedWindowKeys)
        writeEligibleWindowKeys.subtract(postSleepRecoveryUpdate.protectedWindowKeys)
        if !postSleepRecoveryUpdate.newlyRecoveredWindowKeys.isEmpty ||
            !postSleepRecoveryUpdate.confirmedMissingWindowKeys.isEmpty ||
            !postSleepRecoveryUpdate.terminatedWindowKeys.isEmpty {
            diagnostics.log(
                category: "window-lifecycle",
                event: "post-sleep-window-recovery-progress",
                correlation: correlationID,
                fields: [
                    "protected-window-count": String(
                        postSleepRecoveryUpdate.protectedWindowKeys.count
                    ),
                    "protected-process-count": String(Set(
                        postSleepRecoveryUpdate.protectedWindowKeys.map(\.processIdentifier)
                    ).count),
                    "recovered-window-count": String(
                        postSleepRecoveryUpdate.newlyRecoveredWindowKeys.count
                    ),
                    "confirmed-missing-window-count": String(
                        postSleepRecoveryUpdate.confirmedMissingWindowKeys.count
                    ),
                    "terminated-window-count": String(
                        postSleepRecoveryUpdate.terminatedWindowKeys.count
                    ),
                ]
            )
        }

        let lifecycleTransitionActive = screenSessionLifecycleState.isSuspended ||
            wakeReconciliationState.isSleeping ||
            wakeReconciliationState.isPending ||
            wasPostSleepWindowRecoveryActive ||
            postSleepWindowRecoveryState.isActive
        let hasCurrentFullscreenObservation = WindowEnumerationLifecycle
            .hasCurrentFullscreenObservation(
                sessionWindowKeys: Set(fullscreenSessions.keys),
                enumeratedWindowKeys: enumeratedWindowKeys
            )
        let coordinatedEmptyProcessIdentifiers =
            coordinatedWindowEnumerationCollapseState.processIdentifiersToDefer(
                requiredProcessIdentifiers: requiredProcessIdentifiers,
                successfullyEnumeratedProcessIdentifiers: successfullyEnumeratedProcesses,
                enumeratedWindowProcessIdentifiers: Set(
                    enumeratedWindowKeys.map(\.processIdentifier)
                ),
                isLifecycleTransitionActive: lifecycleTransitionActive,
                hasCurrentFullscreenObservation: hasCurrentFullscreenObservation
            )
        let deferredGlobalEmptySnapshot = WindowEnumerationLifecycle
            .shouldDeferGlobalEmptySnapshot(
                trackedWindowCount: trackedWindowKeysBeforeEnumeration.count,
                requiredProcessIdentifiers: requiredProcessIdentifiers,
                successfullyEnumeratedProcessIdentifiers: successfullyEnumeratedProcesses,
                enumeratedWindowCount: enumeratedWindowKeys.count,
                isLifecycleTransitionActive: lifecycleTransitionActive,
                consecutiveGlobalEmptySnapshots: consecutiveGlobalEmptySnapshots
            )
        let isGlobalEmptySnapshot = trackedWindowKeysBeforeEnumeration.count > 0 &&
            !requiredProcessIdentifiers.isEmpty &&
            enumeratedWindowKeys.isEmpty &&
            requiredProcessIdentifiers.isSubset(of: successfullyEnumeratedProcesses)
        if isGlobalEmptySnapshot {
            consecutiveGlobalEmptySnapshots += 1
        } else {
            consecutiveGlobalEmptySnapshots = 0
        }
        if !coordinatedEmptyProcessIdentifiers.isEmpty {
            successfullyEnumeratedProcesses.subtract(coordinatedEmptyProcessIdentifiers)
            diagnostics.log(
                category: "window-lifecycle",
                event: "coordinated-enumeration-collapse-deferred",
                correlation: correlationID,
                fields: [
                    "deferred-process-count": String(
                        coordinatedEmptyProcessIdentifiers.count
                    ),
                    "required-process-count": String(requiredProcessIdentifiers.count),
                    "lifecycle-transition": String(lifecycleTransitionActive),
                    "fullscreen-observed": String(hasCurrentFullscreenObservation),
                    "grace-milliseconds": String(Int(
                        CoordinatedWindowEnumerationCollapseState.graceDuration * 1_000
                    )),
                ]
            )
        }
        if deferredGlobalEmptySnapshot {
            successfullyEnumeratedProcesses.subtract(requiredProcessIdentifiers)
            deferredWindowKeys.formUnion(trackedWindowKeysBeforeEnumeration)
            writeEligibleWindowKeys.subtract(trackedWindowKeysBeforeEnumeration)
            diagnostics.log(
                category: "window-lifecycle",
                event: "global-empty-snapshot-deferred",
                correlation: correlationID,
                fields: [
                    "tracked-window-count": String(trackedWindowKeysBeforeEnumeration.count),
                    "required-process-count": String(requiredProcessIdentifiers.count),
                    "lifecycle-transition": String(lifecycleTransitionActive),
                    "consecutive-count": String(consecutiveGlobalEmptySnapshots),
                ]
            )
        }

        let deferredProcessIdentifiers = requiredProcessIdentifiers
            .subtracting(successfullyEnumeratedProcesses)
        for key in windows.keys where deferredProcessIdentifiers.contains(key.processIdentifier) {
            deferredWindowKeys.insert(key)
            if let tracked = windows[key],
               isManagedLayoutParticipant(tracked),
               let reason = StableLayoutSlotPolicy.retentionReason(
                   wasTracked: true,
                   applicationEnumerationSucceeded: false,
                   windowWasEnumerated: false,
                   isCurrentlyIncludedInLayout: true,
                   hasReadableFrame: false
               ) {
                retainedLayoutSlotReasons[key] = reason
            }
        }

        if !quickAppSessions.isEmpty,
           DropDownAppLifecyclePolicy.shouldClearSessionForTopologyChange(
               topologyChanged: topologyChanged,
               isLifecycleTransitionActive: lifecycleTransitionActive,
               deferredGlobalEmptySnapshot: deferredGlobalEmptySnapshot
           ) {
            if isWindowManagementPaused {
                quickAppTopologyChangedWhilePaused = true
            } else {
                restoreAndClearDropDownAppSession(reason: "display-topology-changed")
            }
        }

        if performAXWrites,
           quickAppSessions.values.contains(where: {
               !$0.windowKeys.allSatisfy {
                   !postSleepRecoveryUpdate.newlyRecoveredWindowKeys.contains($0)
               }
           }) {
            reconcileDropDownAppSessionAfterWake(
                displays: displays,
                eligibleWindowKeys: writeEligibleWindowKeys,
                correlationID: correlationID ?? "post-sleep-recovery"
            )
        }

        // A single timed-out AXWindows request must not make us forget parked windows: once lost,
        // there would be no element left to restore on quit. A successful per-process snapshot is
        // authoritative, though, including for native tabs: a prior ID absent from that snapshot
        // must leave every managed collection rather than surviving as a ghost layout slot.
        let removedTrackedWindowKeys = WindowEnumerationLifecycle.removedTrackedWindowKeys(
            trackedWindowKeys: Set(windows.keys),
            runningProcessIdentifiers: runningProcessIdentifiers,
            successfullyEnumeratedProcessIdentifiers: successfullyEnumeratedProcesses,
            enumeratedWindowKeys: enumeratedWindowKeys
        )
        let removedTrackedWindows = windows.filter { removedTrackedWindowKeys.contains($0.key) }
        var presentedQuickAppMembershipRemoved = false
        if !removedTrackedWindowKeys.isEmpty {
            let sessionBundleKeys = Array(quickAppSessions.keys)
            let newlyTrackedWindowKeys = Set(windows.keys).subtracting(
                trackedWindowKeysBeforeEnumeration
            )
            var reboundBundleKeys = Set<String>()
            for bundleKey in sessionBundleKeys {
                if let session = quickAppSessions[bundleKey] {
                    let removedOwnedKeys = session.windowKeys.filter {
                        removedTrackedWindowKeys.contains($0)
                    }
                    if removedOwnedKeys.count == 1,
                       rebindDropDownAppSessionIfNeeded(
                           bundleIdentifier: bundleKey,
                           sessionWindowKey: removedOwnedKeys[0],
                           removedWindowKeys: removedTrackedWindowKeys,
                           newlyTrackedWindowKeys: newlyTrackedWindowKeys,
                           displays: displays,
                           performAXWrites: performAXWrites,
                           correlationID: correlationID
                       ) {
                        reboundBundleKeys.insert(bundleKey)
                    }
                }
                if var session = quickAppSessions[bundleKey] {
                    let previousKeys = session.windowKeys
                    let retainedKeys = session.windowKeys.filter {
                        !removedTrackedWindowKeys.contains($0)
                    }
                    if !retainedKeys.isEmpty {
                        session.synchronizeWindowKeys(retainedKeys)
                        quickAppSessions[bundleKey] = session
                        let membershipChanged = QuickAppApplicationWindowPolicy
                            .presentedMembershipChanged(
                                previousWindowKeys: previousKeys,
                                currentWindowKeys: session.windowKeys,
                                isPresented: session.isPresented
                            )
                        presentedQuickAppMembershipRemoved =
                            presentedQuickAppMembershipRemoved || membershipChanged
                        if previousKeys != session.windowKeys {
                            diagnostics.log(
                                category: "drop-down-app",
                                event: "application-window-group-updated",
                                correlation: correlationID,
                                fields: [
                                    "bundle": session.bundleIdentifier,
                                    "previous-window-count": String(previousKeys.count),
                                    "window-count": String(session.windowKeys.count),
                                    "added-window-count": "0",
                                    "removed-window-count": String(
                                        Set(previousKeys).subtracting(session.windowKeys).count
                                    ),
                                    "presented": String(session.isPresented),
                                ]
                            )
                        }
                        continue
                    }
                }
            }
            for (bundleKey, session) in Array(quickAppSessions) where
                removedTrackedWindowKeys.contains(session.windowKey) &&
                !reboundBundleKeys.contains(bundleKey) {
                restoreAndClearQuickAppSession(bundleKey: bundleKey, reason: "window-removed")
            }
            windows = windows.filter { !removedTrackedWindowKeys.contains($0.key) }
            lastFocusedWindow = WindowEnumerationLifecycle.pruning(
                lastFocusedWindow,
                removedWindowKeys: removedTrackedWindowKeys
            )
            tiledTrees = WindowEnumerationLifecycle.pruning(
                tiledTrees,
                removedWindowKeys: removedTrackedWindowKeys
            )
            lastSolvedTiledFrames = lastSolvedTiledFrames.filter {
                !removedTrackedWindowKeys.contains($0.key)
            }
            focusCycleRejectedUntil = focusCycleRejectedUntil.filter {
                !removedTrackedWindowKeys.contains($0.key)
            }
            staleParkedFocusSuppression = staleParkedFocusSuppression.filter {
                !removedTrackedWindowKeys.contains($0.key)
            }
            if radialPlacementCommitContext.map({
                !$0.participantKeys.isDisjoint(with: removedTrackedWindowKeys)
            }) == true {
                radialPlacementCommitContext = nil
            }
            if radialFreeformPlacementCommitContext.map({
                removedTrackedWindowKeys.contains($0.focusedWindow)
            }) == true {
                radialFreeformPlacementCommitContext = nil
            }
            if let gestureContext = directionalMoveGestureContext {
                let removedFocus = gestureContext.focusedWindow.map {
                    removedTrackedWindowKeys.contains($0)
                } ?? false
                let removedParticipant = gestureContext.placement.map {
                    !$0.participantKeys.isDisjoint(with: removedTrackedWindowKeys)
                } ?? false
                if removedFocus || removedParticipant {
                    directionalMoveGestureContext = nil
                }
            }

            let removedFocusState = [
                lastObservedFocusedWindow,
                programmaticFocusTarget,
                recentInteractionFocusTarget,
                preSleepFocusContext?.windowKey,
            ].compactMap { $0 }.contains { removedTrackedWindowKeys.contains($0) }
            if removedFocusState {
                _ = advanceFocusActionGeneration()
                pendingFocusVerification?.cancel()
                pendingFocusVerification = nil
                clearProgrammaticFocusIntent()
            }
            if lastObservedFocusedWindow.map(removedTrackedWindowKeys.contains) == true {
                lastObservedFocusedWindow = nil
            }
            if recentInteractionFocusTarget.map(removedTrackedWindowKeys.contains) == true {
                recentInteractionFocusTarget = nil
                recentInteractionDisplayIdentifier = nil
                recentInteractionDisplayDeadline = .distantPast
            }
            if let preSleepWindowKey = preSleepFocusContext?.windowKey,
               removedTrackedWindowKeys.contains(preSleepWindowKey) {
                preSleepFocusContext = nil
            }

            for (key, tracked) in removedTrackedWindows
            where successfullyEnumeratedProcesses.contains(key.processIdentifier) {
                let persistedKey = String(key.windowIdentifier)
                if let pending = pendingRestoredWindows[persistedKey],
                   let bundleIdentifier = tracked.bundleIdentifier,
                   pending.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame {
                    pendingRestoredWindows.removeValue(forKey: persistedKey)
                }
                diagnostics.log(
                    category: "window-lifecycle",
                    event: "enumeration-evicted",
                    correlation: correlationID,
                    fields: [
                        "window": Self.diagnosticWindowKey(key),
                        "bundle": tracked.bundleIdentifier ?? "unknown",
                        "reason": "absent-from-successful-axwindows-snapshot",
                        "frame-write": "false",
                    ]
                )
            }
        }
        let presentedQuickAppMembershipReconciled = reconcileQuickAppSessionWindowSets(
            correlationID: correlationID
        )
        let presentedQuickAppMembershipChanged = presentedQuickAppMembershipRemoved ||
            presentedQuickAppMembershipReconciled
        if performAXWrites, presentedQuickAppMembershipChanged {
            reconcilePresentedQuickAppGroup(
                correlationID: correlationID,
                focusSelected: false
            )
        }
        let shouldRetainDiscoveryState: (WindowKey) -> Bool = { key in
            runningProcessIdentifiers.contains(key.processIdentifier) &&
                (!successfullyEnumeratedProcesses.contains(key.processIdentifier) || enumeratedWindowKeys.contains(key))
        }
        ignoredWindowKeys = ignoredWindowKeys.filter(shouldRetainDiscoveryState)
        admissionDecisionByWindow = admissionDecisionByWindow.filter { shouldRetainDiscoveryState($0.key) }
        admissionMetadataByWindow = admissionMetadataByWindow.filter { shouldRetainDiscoveryState($0.key) }
        rejectedResizeRecoveryAttemptedWindowKeys = rejectedResizeRecoveryAttemptedWindowKeys.filter(
            shouldRetainDiscoveryState
        )
        lastKnownWindowLayer = lastKnownWindowLayer.filter { shouldRetainDiscoveryState($0.key) }
        staleParkedFocusSuppression = staleParkedFocusSuppression.filter {
            shouldRetainDiscoveryState($0.key)
        }
        let expiredFullscreenSessionKeys = Set(fullscreenSessions.keys.filter {
            !shouldRetainDiscoveryState($0)
        })
        if !expiredFullscreenSessionKeys.isEmpty {
            fullscreenSessions = fullscreenSessions.filter { !expiredFullscreenSessionKeys.contains($0.key) }
            fullscreenAuthoritativeFalseCounts = fullscreenAuthoritativeFalseCounts.filter {
                !expiredFullscreenSessionKeys.contains($0.key)
            }
            if foregroundFullscreenGameSessionKey.map(expiredFullscreenSessionKeys.contains) == true {
                foregroundFullscreenGameSessionKey = nil
            }
        }
        writeEligibleWindowKeys = writeEligibleWindowKeys.intersection(windows.keys)
        deferredWindowKeys = deferredWindowKeys.intersection(windows.keys)
        retainedLayoutSlotReasons = retainedLayoutSlotReasons.filter {
            windows[$0.key] != nil && deferredWindowKeys.contains($0.key)
        }
        temporarilyDeferredWindowKeys = deferredWindowKeys
        updateRetainedLayoutSlots(retainedLayoutSlotReasons, correlationID: correlationID)

        if isStartup {
            prepareDropDownAppSessionForStartup(
                observedFrames: observedFrames,
                displays: displays,
                performAXWrites: performAXWrites,
                correlationID: correlationID
            )
        }

        let focusedSnapshot = observeFocus ? focusedWindowSnapshot() : nil
        let previousDiagnosticFocusKey = lastDiagnosticFocusedWindow?.key
        let nextDiagnosticFocusKey = WindowEnumerationLifecycle.diagnosticFocusKeyAfterEnumeration(
            previousKey: previousDiagnosticFocusKey,
            observedKey: focusedSnapshot?.key,
            ownProcessIdentifier: ownProcessIdentifier,
            removedWindowKeys: removedTrackedWindowKeys
        )
        if let focusedSnapshot, nextDiagnosticFocusKey == focusedSnapshot.key {
            lastDiagnosticFocusedWindow = focusedSnapshot
        } else if nextDiagnosticFocusKey == nil {
            lastDiagnosticFocusedWindow = nil
        }
        let focused = focusedSnapshot?.key
        if observeFocus {
            reconcileForegroundFullscreenGameSession(focusedWindow: focused)
        } else if let foregroundFullscreenGameSessionKey,
                  fullscreenSessions[foregroundFullscreenGameSessionKey]?.isDeclaredGame != true {
            self.foregroundFullscreenGameSessionKey = nil
        }
        emitFullscreenGameSessionIfNeeded()
        if observeFocus, let focused,
           staleParkedFocusSuppression[focused] == nil,
           let tracked = windows[focused],
           !isExcludedFromWorkspaceParticipation(tracked) {
            lastFocusedWindow[tracked.workspaceID] = focused
        }

        if let resizeSession = manualTiledResizeSession,
           isStartup || topologyChanged || lifecycleTransitionActive ||
            !resizeSession.participantKeys.isSubset(of: Set(windows.keys)) {
            cancelManualTiledResizePreview(reason: topologyChanged
                ? "display-topology-changed"
                : lifecycleTransitionActive ? "lifecycle-transition" : "participants-changed")
        }
        if let moveSession = manualTiledMovePreviewSession,
           isStartup || topologyChanged || lifecycleTransitionActive ||
            !moveSession.participantKeys.isSubset(of: Set(windows.keys)) {
            cancelManualTiledMovePreview(reason: topologyChanged
                ? "display-topology-changed"
                : lifecycleTransitionActive ? "lifecycle-transition" : "participants-changed")
        }

        var manualTiledDragInProgress = manualTiledMovePreviewSession != nil
        if manualTiledResizeSession == nil, manualTiledMovePreviewSession == nil,
           performAXWrites, !isStartup, !topologyChanged, !lifecycleTransitionActive, let focused,
           !isDropDownAppWindow(focused),
           let focusedTracked = windows[focused],
           !isExcludedFromWorkspaceParticipation(focusedTracked) {
            let isLeftMouseButtonPressed = CGEventSource.buttonState(
                .combinedSessionState,
                button: .left
            )
            let moveReconciliation = reconcileManualTiledMove(
                focusedWindow: focused,
                observedFrames: observedFrames,
                displays: displays,
                pointerLocation: CGEvent(source: nil)?.location,
                isLeftMouseButtonPressed: isLeftMouseButtonPressed,
                correlationID: correlationID
            )
            manualTiledDragInProgress = moveReconciliation == .dragInProgress ||
                (isLeftMouseButtonPressed && workspaceLayout(for: focusedTracked.workspaceID) == .tiled)
            if moveReconciliation == .none, !isLeftMouseButtonPressed {
                reconcileManualTiledResize(
                    focusedWindow: focused,
                    observedFrames: observedFrames,
                    displays: displays,
                    correlationID: correlationID
                )
            }
        } else if manualTiledResizeSession == nil, manualTiledMovePreviewSession == nil,
                    (isStartup || topologyChanged || lifecycleTransitionActive || focused == nil) {
            manualTiledDragSession = nil
        }

        let manualTiledInteractionInProgress = manualTiledDragInProgress ||
            manualTiledMovePreviewSession != nil ||
            manualTiledResizeSession != nil

        let layoutSignatureBeforeApply = backgroundLayoutSignature(
            displays: displays,
            observedFrames: observedFrames
        )
        var didAttemptBackgroundVisibilityApplication = false
        if performAXWrites, topologyChanged, !isStartup {
            applyVisibility(displays: displays, correlationID: correlationID)
            didAttemptBackgroundVisibilityApplication = true
        } else if performAXWrites, !manualTiledInteractionInProgress, Self.shouldApplyBackgroundLayout(
            previousSignature: lastBackgroundLayoutSignature,
            currentSignature: layoutSignatureBeforeApply,
            isStartup: isStartup
        ) {
            applyVisibility(displays: displays, correlationID: correlationID)
            didAttemptBackgroundVisibilityApplication = true
        }
        if performAXWrites, !manualTiledInteractionInProgress, resizeRecoveryNeedsImmediateReflow {
            resizeRecoveryNeedsImmediateReflow = false
            applyVisibility(displays: displays, correlationID: correlationID)
            didAttemptBackgroundVisibilityApplication = true
        }
        if performAXWrites, !manualTiledInteractionInProgress {
            lastBackgroundLayoutSignature = Self.settledBackgroundLayoutSignature(
                observedSignature: layoutSignatureBeforeApply,
                didApplyVisibility: didAttemptBackgroundVisibilityApplication
            ) {
                backgroundLayoutSignature(displays: displays)
            }
        }

        if observeFocus {
            observeFocusedWindow(
                focused,
                isStartup: isStartup,
                allowWorkspaceFollowing: followExternalFocus,
                observationCorrelationID: correlationID
            )
        }

        if evictedIgnoredManagedState || !removedTrackedWindowKeys.isEmpty {
            // Flush any stale assignment removed during admission without waiting for the next
            // timer tick. This performs no AX writes and never restores or moves the removed object.
            persistState(preservingPendingRestores: true)
        }

        if !isStartup, Date() >= startupGraceDeadline {
            pendingRestoredWindows.removeAll()
        }

        emitWorkspacePreviewStateChangesIfNeeded(
            observedFrames: observedFrames,
            displays: displays
        )

        return WindowRefreshReport(
            displays: displays,
            topologySignature: topologySignature,
            requiredProcessIdentifiers: requiredProcessIdentifiers,
            successfullyEnumeratedProcessIdentifiers: successfullyEnumeratedProcesses,
            writeEligibleWindowKeys: writeEligibleWindowKeys,
            deferredWindowKeys: deferredWindowKeys,
            retainedLayoutSlotWindowKeys: retainedLayoutSlotWindowKeys,
            managedWindowCount: windows.count
        )
    }

    /// Reuses the engine's existing broad refresh while Workspaces Settings is visible. This adds
    /// no timer or AX enumeration: it compares only the tracked identities and intended geometry
    /// already read by `refreshWindows`, then reports the exact workspaces whose preview is stale.
    private func emitWorkspacePreviewStateChangesIfNeeded(
        observedFrames: [WindowKey: WindowFrame],
        displays: [DisplaySnapshot]
    ) {
        guard workspacePreviewObservationEnabled else { return }
        var nextState: [UUID: [WorkspacePreviewStateMember]] = [:]
        for tracked in windows.values {
            guard !isDropDownAppWindow(tracked.key),
                  !ignoredWindowKeys.contains(tracked.key),
                  !temporarilyDeferredWindowKeys.contains(tracked.key),
                  !resolvedRule(for: tracked.bundleIdentifier).keepsOnAllWorkspaces
            else { continue }
            let layout = workspaceLayout(for: tracked.workspaceID)
            let intendedFrame: WindowFrame
            if isWorkspaceActive(tracked.workspaceID),
               let observed = observedFrames[tracked.key],
               Self.isMeaningfullyVisible(observed, displays: displays) {
                intendedFrame = observed
            } else if layout == .tiled,
                      let solved = lastSolvedTiledFrames[tracked.key] {
                intendedFrame = solved
            } else {
                intendedFrame = tracked.restoreFrame
            }
            nextState[tracked.workspaceID, default: []].append(
                WorkspacePreviewStateMember(
                    key: tracked.key,
                    intendedFrame: CGRect(
                        origin: intendedFrame.position,
                        size: intendedFrame.size
                    ),
                    layoutOrder: tracked.layoutOrder,
                    isLastFocused: lastFocusedWindow[tracked.workspaceID] == tracked.key
                )
            )
        }
        for workspaceID in nextState.keys {
            nextState[workspaceID]?.sort {
                if $0.key.processIdentifier != $1.key.processIdentifier {
                    return $0.key.processIdentifier < $1.key.processIdentifier
                }
                return $0.key.windowIdentifier < $1.key.windowIdentifier
            }
        }
        guard hasWorkspacePreviewStateBaseline else {
            hasWorkspacePreviewStateBaseline = true
            workspacePreviewStateByWorkspace = nextState
            let initialWorkspaceIDs = Set(nextState.keys)
            if !initialWorkspaceIDs.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    self?.onWorkspacePreviewStateChanged?(initialWorkspaceIDs)
                }
            }
            return
        }
        let allWorkspaceIDs = Set(workspacePreviewStateByWorkspace.keys)
            .union(nextState.keys)
        let changedWorkspaceIDs = Set(allWorkspaceIDs.filter {
            workspacePreviewStateByWorkspace[$0] != nextState[$0]
        })
        workspacePreviewStateByWorkspace = nextState
        guard !changedWorkspaceIDs.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onWorkspacePreviewStateChanged?(changedWorkspaceIDs)
        }
    }

    private func reconcileFullscreenSession(
        key: WindowKey,
        element: AXUIElement,
        application: NSRunningApplication,
        metadata: WindowAdmissionMetadata,
        observedFrame: WindowFrame?,
        displays: [DisplaySnapshot],
        correlationID: String?
    ) {
        guard metadata.isFullscreen else {
            if let previous = fullscreenSessions.removeValue(forKey: key) {
                fullscreenAuthoritativeFalseCounts.removeValue(forKey: key)
                if foregroundFullscreenGameSessionKey == key {
                    foregroundFullscreenGameSessionKey = nil
                }
                diagnostics.log(
                    category: "fullscreen-session",
                    event: "exited",
                    correlation: correlationID,
                    fields: [
                        "window": Self.diagnosticWindowKey(key),
                        "bundle": previous.bundleIdentifier ?? "unknown",
                        "workspace": Self.shortIdentifier(previous.workspaceID.uuidString),
                        "display": Self.shortIdentifier(previous.displayIdentifier),
                        "declared-game": String(previous.isDeclaredGame),
                        "frame-write": "false",
                    ]
                )
            }
            return
        }

        let previous = fullscreenSessions[key]
        let placement = observedFrame.flatMap { Self.displayPlacement(for: $0, displays: displays) }
        let displayIdentifier = placement?.displayIdentifier
            ?? previous?.displayIdentifier
            ?? windows[key]?.displayPlacement?.displayIdentifier
            ?? displays.first(where: \.isMain)?.identifier
            ?? displays.first?.identifier
            ?? "main-display"
        let workspaceID = windows[key]?.workspaceID
            ?? previous?.workspaceID
            ?? Self.initialWorkspaceID(
                for: displayIdentifier,
                mode: displayMode,
                currentWorkspaceID: currentWorkspaceID,
                activeWorkspaceIDByDisplay: activeWorkspaceIDByDisplay
            )
        let declaredGame = previous?.isDeclaredGame == true || isDeclaredGame(application)
        let gameModeEligible = previous?.isGameModeEligible == true || isGameModeEligible(application)
        let session = FullscreenWindowSession(
            key: key,
            element: element,
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            workspaceID: workspaceID,
            displayIdentifier: displayIdentifier,
            frame: observedFrame ?? previous?.frame,
            isDeclaredGame: declaredGame,
            isGameModeEligible: gameModeEligible,
            enteredAt: previous?.enteredAt ?? Date()
        )
        fullscreenSessions[key] = session
        if previous == nil {
            diagnostics.log(
                category: "fullscreen-session",
                event: "entered",
                correlation: correlationID,
                fields: [
                    "window": Self.diagnosticWindowKey(key),
                    "bundle": application.bundleIdentifier ?? "unknown",
                    "workspace": Self.shortIdentifier(workspaceID.uuidString),
                    "display": Self.shortIdentifier(displayIdentifier),
                    "declared-game": String(declaredGame),
                    "fullscreen-observation": metadata.fullscreenObservation.rawValue,
                    "frame-write": "false",
                ]
            )
        }
    }

    private func isDeclaredGame(_ application: NSRunningApplication) -> Bool {
        let cacheKey = application.bundleIdentifier?.lowercased()
            ?? application.bundleURL?.standardizedFileURL.path.lowercased()
            ?? "pid:\(application.processIdentifier)"
        if let cached = declaredGameByBundleIdentifier[cacheKey] { return cached }
        let bundle = application.bundleURL.flatMap { Bundle(url: $0) }
        let declared = FullscreenGameMetadataPolicy.isDeclaredGame(bundle: bundle)
        declaredGameByBundleIdentifier[cacheKey] = declared
        return declared
    }

    private func isGameModeEligible(_ application: NSRunningApplication) -> Bool {
        let cacheKey = application.bundleIdentifier?.lowercased()
            ?? application.bundleURL?.standardizedFileURL.path.lowercased()
            ?? "pid:\(application.processIdentifier)"
        if let cached = gameModeEligibilityByBundleIdentifier[cacheKey] { return cached }
        let bundle = application.bundleURL.flatMap { Bundle(url: $0) }
        let eligible = FullscreenGameMetadataPolicy.isGameModeEligible(bundle: bundle)
        gameModeEligibilityByBundleIdentifier[cacheKey] = eligible
        return eligible
    }

    private func reconcileForegroundFullscreenGameSession(focusedWindow: WindowKey?) {
        if let focusedWindow,
           let session = fullscreenSessions[focusedWindow],
           session.isDeclaredGame {
            foregroundFullscreenGameSessionKey = focusedWindow
            lastFocusedWindow[session.workspaceID] = focusedWindow
            return
        }

        guard let currentKey = foregroundFullscreenGameSessionKey,
              fullscreenSessions[currentKey]?.isDeclaredGame == true
        else {
            foregroundFullscreenGameSessionKey = nil
            return
        }
        guard let focusedWindow else {
            // Game Overlay and fullscreen transitions can temporarily remove the system-wide AX
            // focused window. Keep the session until a genuine regular application activates.
            return
        }
        if windows[focusedWindow] != nil || fullscreenSessions[focusedWindow] != nil {
            foregroundFullscreenGameSessionKey = nil
            return
        }
        let focusedApplication = NSRunningApplication(
            processIdentifier: focusedWindow.processIdentifier
        )
        if focusedWindow.processIdentifier != ownProcessIdentifier,
           focusedApplication?.activationPolicy == .regular {
            foregroundFullscreenGameSessionKey = nil
        }
    }

    private func noteApplicationActivation(processIdentifier: pid_t) {
        if let session = fullscreenSessions.values
            .filter({ $0.processIdentifier == processIdentifier && $0.isDeclaredGame })
            .sorted(by: { $0.enteredAt > $1.enteredAt })
            .first {
            foregroundFullscreenGameSessionKey = session.key
            lastFocusedWindow[session.workspaceID] = session.key
            emitFullscreenGameSessionIfNeeded()
            return
        }
        guard processIdentifier != ownProcessIdentifier else { return }
        if NSRunningApplication(processIdentifier: processIdentifier)?.activationPolicy == .regular,
           windows.keys.contains(where: { $0.processIdentifier == processIdentifier }) {
            foregroundFullscreenGameSessionKey = nil
            emitFullscreenGameSessionIfNeeded()
        }
    }

    private func emitFullscreenGameSessionIfNeeded() {
        let snapshot = foregroundFullscreenGameSessionKey.flatMap { key -> FullscreenGameSessionSnapshot? in
            guard let session = fullscreenSessions[key], session.isDeclaredGame else { return nil }
            return FullscreenGameSessionSnapshot(
                processIdentifier: session.processIdentifier,
                windowIdentifier: session.key.windowIdentifier,
                bundleIdentifier: session.bundleIdentifier,
                workspaceID: session.workspaceID,
                displayIdentifier: session.displayIdentifier,
                isGameModeEligible: session.isGameModeEligible
            )
        }
        guard snapshot != lastEmittedFullscreenGameSession else { return }
        lastEmittedFullscreenGameSession = snapshot
        DispatchQueue.main.async { [weak self] in
            self?.onFullscreenGameSessionChanged?(snapshot)
        }
    }

    static func shouldLogAdmissionDecisionChange(
        previous: WindowAdmissionDecision?,
        current: WindowAdmissionDecision
    ) -> Bool {
        previous != current
    }

    static func admissionDiagnosticFields(
        decision: WindowAdmissionDecision,
        metadata: WindowAdmissionMetadata,
        key: WindowKey,
        layerSource: String
    ) -> [String: String] {
        [
            "window": diagnosticWindowKey(key),
            "bundle": metadata.bundleIdentifier ?? "unknown",
            "ax-role": metadata.role ?? "unknown",
            "ax-subrole": metadata.subrole ?? "unknown",
            "window-layer": metadata.windowLayer.map(String.init) ?? "unknown",
            "layer-source": layerSource,
            "ax-modal": metadata.modalObservation.rawValue,
            "ax-focused": metadata.focusedObservation.rawValue,
            "ax-main": metadata.mainObservation.rawValue,
            "fullscreen-button": metadata.fullscreenButton.rawValue,
            "minimize-button": metadata.minimizeButton.rawValue,
            "is-fullscreen": String(metadata.isFullscreen),
            "fullscreen-observation": metadata.fullscreenObservation.rawValue,
            "is-minimized": String(metadata.isMinimized),
            "close-button": metadata.closeButton.rawValue,
            "zoom-button": metadata.zoomButton.rawValue,
            "default-button": metadata.defaultButton.rawValue,
            "cancel-button": metadata.cancelButton.rawValue,
            "native-file-panel-identifier":
                metadata.nativeFilePanelIdentifierObservation.rawValue,
            "position-settable": metadata.positionSettable.rawValue,
            "size-settable": metadata.sizeSettable.rawValue,
            "disposition": decision.disposition.rawValue,
            "reason": decision.reason.rawValue,
            "compatibility-profile": decision.compatibilityProfileIdentifier ?? "none",
            "automatic-floating": String(decision.automaticallyFloats),
        ]
    }

    static func admissionSupportRecords(
        decisions: [WindowKey: WindowAdmissionDecision],
        metadata: [WindowKey: WindowAdmissionMetadata]
    ) -> [WindowAdmissionSupportRecord] {
        decisions.compactMap { key, decision in
            guard let metadata = metadata[key] else { return nil }
            return WindowAdmissionSupportRecord(
                id: diagnosticWindowKey(key),
                bundleIdentifier: metadata.bundleIdentifier ?? "unknown",
                disposition: decision.disposition.rawValue,
                reason: decision.reason.rawValue,
                compatibilityProfileIdentifier: decision.compatibilityProfileIdentifier,
                role: metadata.role ?? "unknown",
                subrole: metadata.subrole ?? "unknown",
                windowLayer: metadata.windowLayer.map(String.init) ?? "unknown",
                isMinimized: metadata.isMinimized,
                isFullscreen: metadata.isFullscreen,
                modalObservation: metadata.modalObservation.rawValue,
                focusedObservation: metadata.focusedObservation.rawValue,
                mainObservation: metadata.mainObservation.rawValue,
                fullscreenButton: metadata.fullscreenButton.rawValue,
                minimizeButton: metadata.minimizeButton.rawValue,
                closeButton: metadata.closeButton.rawValue,
                zoomButton: metadata.zoomButton.rawValue,
                defaultButton: metadata.defaultButton.rawValue,
                cancelButton: metadata.cancelButton.rawValue,
                nativeFilePanelIdentifierObservation:
                    metadata.nativeFilePanelIdentifierObservation.rawValue,
                positionSettable: metadata.positionSettable.rawValue,
                sizeSettable: metadata.sizeSettable.rawValue
            )
        }
        .sorted {
            ($0.bundleIdentifier, $0.disposition, $0.id) <
                ($1.bundleIdentifier, $1.disposition, $1.id)
        }
    }

    private func recordAdmissionDecision(
        _ decision: WindowAdmissionDecision,
        metadata: WindowAdmissionMetadata,
        key: WindowKey,
        layerSource: String,
        correlationID: String?
    ) {
        let previous = admissionDecisionByWindow[key]
        admissionDecisionByWindow[key] = decision
        admissionMetadataByWindow[key] = metadata
        guard Self.shouldLogAdmissionDecisionChange(previous: previous, current: decision) else { return }
        diagnostics.log(
            category: "window-admission",
            event: previous == nil ? "classified" : "classification-changed",
            correlation: correlationID,
            fields: Self.admissionDiagnosticFields(
                decision: decision,
                metadata: metadata,
                key: key,
                layerSource: layerSource
            )
        )
    }

    private func updateRetainedLayoutSlots(
        _ reasons: [WindowKey: StableLayoutSlotRetentionReason],
        correlationID: String?
    ) {
        let next = Set(reasons.keys)
        let transitions = StableLayoutSlotPolicy.transitions(
            previous: retainedLayoutSlotWindowKeys,
            current: next
        )
        let sortKeys: (WindowKey, WindowKey) -> Bool = { lhs, rhs in
            if lhs.processIdentifier != rhs.processIdentifier {
                return lhs.processIdentifier < rhs.processIdentifier
            }
            return lhs.windowIdentifier < rhs.windowIdentifier
        }
        for key in transitions.entered.sorted(by: sortKeys) {
            guard let tracked = windows[key], let reason = reasons[key] else { continue }
            diagnostics.log(
                category: "window-lifecycle",
                event: "layout-slot-retained",
                correlation: correlationID,
                fields: [
                    "window": Self.diagnosticWindowKey(key),
                    "bundle": tracked.bundleIdentifier ?? "unknown",
                    "workspace": Self.shortIdentifier(tracked.workspaceID.uuidString),
                    "layout": workspaceLayout(for: tracked.workspaceID).rawValue,
                    "reason": reason.rawValue,
                    "frame-write": "false",
                ]
            )
        }
        for key in transitions.released.sorted(by: sortKeys) {
            guard let tracked = windows[key] else { continue }
            diagnostics.log(
                category: "window-lifecycle",
                event: "layout-slot-released",
                correlation: correlationID,
                fields: [
                    "window": Self.diagnosticWindowKey(key),
                    "bundle": tracked.bundleIdentifier ?? "unknown",
                    "workspace": Self.shortIdentifier(tracked.workspaceID.uuidString),
                    "reason": "authoritative-state-observed",
                ]
            )
        }
        retainedLayoutSlotWindowKeys = next
    }

    @discardableResult
    private func evictIgnoredWindow(
        _ key: WindowKey,
        bundleIdentifier: String?,
        decision: WindowAdmissionDecision,
        metadata: WindowAdmissionMetadata,
        correlationID: String?
    ) -> IgnoredWindowRemovalResult {
        discardIgnoredQuickAppSessions(for: key, correlationID: correlationID)
        let removal = Self.removeIgnoredWindowState(
            key,
            bundleIdentifier: bundleIdentifier,
            trackedWindows: &windows,
            pendingRestoredWindows: &pendingRestoredWindows,
            lastFocusedWindow: &lastFocusedWindow,
            tiledTrees: &tiledTrees,
            fullscreenSessions: &fullscreenSessions,
            fullscreenAuthoritativeFalseCounts: &fullscreenAuthoritativeFalseCounts
        )

        if lastObservedFocusedWindow == key {
            lastObservedFocusedWindow = nil
        }
        if lastDiagnosticFocusedWindow?.key == key {
            lastDiagnosticFocusedWindow = nil
        }
        if programmaticFocusTarget == key {
            _ = advanceFocusActionGeneration()
            pendingFocusVerification?.cancel()
            pendingFocusVerification = nil
            clearProgrammaticFocusIntent()
        }
        if recentInteractionFocusTarget == key {
            recentInteractionFocusTarget = nil
            recentInteractionDisplayIdentifier = nil
            recentInteractionDisplayDeadline = .distantPast
        }
        if preSleepFocusContext?.windowKey == key {
            preSleepFocusContext = nil
        }
        if radialPlacementCommitContext.map({
            $0.focusedWindow == key || $0.participantKeys.contains(key)
        }) == true {
            radialPlacementCommitContext = nil
        }
        if radialFreeformPlacementCommitContext?.focusedWindow == key {
            radialFreeformPlacementCommitContext = nil
        }
        if let gestureContext = directionalMoveGestureContext,
           gestureContext.focusedWindow == key ||
            gestureContext.placement?.participantKeys.contains(key) == true {
            directionalMoveGestureContext = nil
        }
        if let dragSession = manualTiledDragSession,
           dragSession.focusedWindow == key || dragSession.candidateDestination?.target == key {
            manualTiledDragSession = nil
        }
        if manualTiledMovePreviewSession?.participantKeys.contains(key) == true {
            cancelManualTiledMovePreview(reason: "participant-removed")
        }
        if manualTiledResizeSession?.participantKeys.contains(key) == true {
            cancelManualTiledResizePreview(reason: "participant-removed")
        }
        for bundleKey in Array(quickAppSessions.keys) {
            guard var session = quickAppSessions[bundleKey] else { continue }
            if session.previousFocusKey == key {
                session.previousFocusKey = nil
                quickAppSessions[bundleKey] = session
            }
        }
        postSleepWindowRecoveryState.remove(key)
        if foregroundFullscreenGameSessionKey == key {
            foregroundFullscreenGameSessionKey = nil
        }
        focusCycleRejectedUntil.removeValue(forKey: key)
        staleParkedFocusSuppression.removeValue(forKey: key)
        lastSolvedTiledFrames.removeValue(forKey: key)
        temporarilyDeferredWindowKeys.remove(key)

        if removal.changedManagedState {
            diagnostics.log(
                category: "window-admission",
                event: "ignored-window-evicted",
                correlation: correlationID,
                fields: [
                    "window": Self.diagnosticWindowKey(key),
                    "bundle": bundleIdentifier ?? "unknown",
                    "ax-role": metadata.role ?? "unknown",
                    "ax-subrole": metadata.subrole ?? "unknown",
                    "window-layer": metadata.windowLayer.map(String.init) ?? "unknown",
                    "disposition": decision.disposition.rawValue,
                    "reason": decision.reason.rawValue,
                    "tracked-removed": String(removal.removedTrackedWindow),
                    "pending-assignment-removed": String(removal.removedPendingAssignment),
                    "last-focused-workspaces-cleared": String(removal.clearedLastFocusedWorkspaceIDs.count),
                    "tiled-layout-state-removed": String(removal.removedTiledLayoutState),
                    "fullscreen-state-removed": String(removal.removedFullscreenState),
                    "frame-write": "false",
                ]
            )
        }
        return removal
    }

    static func removeIgnoredWindowState<Tracked, FullscreenSession>(
        _ key: WindowKey,
        bundleIdentifier: String?,
        trackedWindows: inout [WindowKey: Tracked],
        pendingRestoredWindows: inout [String: PersistedWindowAssignment],
        lastFocusedWindow: inout [UUID: WindowKey],
        tiledTrees: inout [TiledLayoutPartitionKey: TiledNode],
        fullscreenSessions: inout [WindowKey: FullscreenSession],
        fullscreenAuthoritativeFalseCounts: inout [WindowKey: Int]
    ) -> IgnoredWindowRemovalResult {
        let removedTrackedWindow = trackedWindows.removeValue(forKey: key) != nil
        let persistedKey = String(key.windowIdentifier)
        let removedPendingAssignment: Bool
        if let assignment = pendingRestoredWindows[persistedKey],
           let bundleIdentifier,
           assignment.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame {
            pendingRestoredWindows.removeValue(forKey: persistedKey)
            removedPendingAssignment = true
        } else {
            removedPendingAssignment = false
        }
        let clearedLastFocusedWorkspaceIDs = Set(lastFocusedWindow.compactMap { workspaceID, windowKey in
            windowKey == key ? workspaceID : nil
        })
        lastFocusedWindow = lastFocusedWindow.filter { $0.value != key }
        let prunedTiledTrees = WindowEnumerationLifecycle.pruning(
            tiledTrees,
            removedWindowKeys: [key]
        )
        let removedTiledLayoutState = prunedTiledTrees != tiledTrees
        tiledTrees = prunedTiledTrees
        let removedFullscreenSession = fullscreenSessions.removeValue(forKey: key) != nil
        let removedFullscreenObservation = fullscreenAuthoritativeFalseCounts.removeValue(forKey: key) != nil
        return IgnoredWindowRemovalResult(
            removedTrackedWindow: removedTrackedWindow,
            removedPendingAssignment: removedPendingAssignment,
            clearedLastFocusedWorkspaceIDs: clearedLastFocusedWorkspaceIDs,
            removedTiledLayoutState: removedTiledLayoutState,
            removedFullscreenState: removedFullscreenSession || removedFullscreenObservation
        )
    }

    private var activeWorkspaceIDs: Set<UUID> {
        displayMode == .unified
            ? [currentWorkspaceID]
            : Set(activeWorkspaceIDByDisplay.values)
    }

    static func shouldApplyBackgroundLayout(
        previousSignature: String?,
        currentSignature: String,
        isStartup: Bool
    ) -> Bool {
        !isStartup && previousSignature != currentSignature
    }

    static func backgroundLayoutFrame(
        for key: WindowKey,
        observedFrames: [WindowKey: WindowFrame]?,
        readFrame: () -> WindowFrame?
    ) -> WindowFrame? {
        observedFrames?[key] ?? readFrame()
    }

    static func settledBackgroundLayoutSignature(
        observedSignature: String,
        didApplyVisibility: Bool,
        readPostWriteSignature: () -> String
    ) -> String {
        didApplyVisibility ? readPostWriteSignature() : observedSignature
    }

    private func backgroundLayoutSignature(
        displays: [DisplaySnapshot],
        observedFrames: [WindowKey: WindowFrame]? = nil
    ) -> String {
        let fullActiveMap: String
        if displayMode == .unified {
            fullActiveMap = "all:\(currentWorkspaceID.uuidString)"
        } else {
            fullActiveMap = activeWorkspaceIDByDisplay
                .map { "\($0.key):\($0.value.uuidString)" }
                .sorted()
                .joined(separator: ",")
        }
        var parts = [
            "mode=\(displayMode.rawValue)",
            "active=\(fullActiveMap)",
            "focused-window-highlight=\(focusedWindowHighlightEnabled)",
        ]
        parts.append(contentsOf: displays.sorted { $0.identifier < $1.identifier }.map {
            "display=\($0.identifier)|\(Self.diagnosticRect($0.bounds))|\(Self.diagnosticRect($0.usableBounds))|\($0.isMain)"
        })
        parts.append(contentsOf: workspaces.sorted { $0.id.uuidString < $1.id.uuidString }.map {
            let primary = $0.layout == .accordion
                ? lastFocusedWindow[$0.id].map(Self.diagnosticWindowKey) ?? "none"
                : "irrelevant"
            let geometry = $0.layoutConfiguration.map { configuration in
                let gaps = configuration.gaps
                return "v1,\(configuration.orientation.rawValue),\(configuration.accordionPadding),\(gaps.innerHorizontal),\(gaps.innerVertical),\(gaps.outerTop),\(gaps.outerRight),\(gaps.outerBottom),\(gaps.outerLeft)"
            } ?? "legacy"
            return "workspace=\($0.id.uuidString)|\($0.layout.rawValue)|\(workspaceHomeDisplayIdentifier(for: $0.id, displays: displays))|\(primary)|\(geometry)"
        })
        let orderedWindows = windows.values.sorted {
            if $0.key.processIdentifier != $1.key.processIdentifier {
                return $0.key.processIdentifier < $1.key.processIdentifier
            }
            return $0.key.windowIdentifier < $1.key.windowIdentifier
        }
        parts.append(contentsOf: orderedWindows.compactMap { tracked in
            guard let visibility = Self.backgroundApplicationVisibilityMarker(
                isApplicationHidden: isExcludedFromWorkspaceParticipation(tracked),
                isDropDownAppWindow: isDropDownAppWindow(tracked.key)
            ) else { return nil }
            return "application-visibility=\(Self.diagnosticWindowKey(tracked.key))|\(visibility)"
        })
        parts.append(contentsOf: orderedWindows.compactMap { tracked in
            guard !isDropDownAppWindow(tracked.key),
                  !isExcludedFromWorkspaceParticipation(tracked)
            else { return nil }
            let rule = resolvedRule(for: tracked.bundleIdentifier)
            guard Self.shouldWindowBeVisible(
                workspaceID: tracked.workspaceID,
                activeWorkspaceIDs: activeWorkspaceIDs,
                rule: rule
            ) else { return nil }
            let currentFrame = Self.backgroundLayoutFrame(
                for: tracked.key,
                observedFrames: observedFrames
            ) {
                AccessibilityWindow.frame(of: tracked.element)
            }
                .map(Self.diagnosticFrame) ?? "unknown"
            return [
                "window=\(Self.diagnosticWindowKey(tracked.key))",
                tracked.workspaceID.uuidString,
                tracked.displayPlacement?.displayIdentifier ?? "none",
                currentFrame,
                Self.diagnosticFrame(tracked.restoreFrame),
                tracked.layoutOverride.rawValue,
                tracked.admissionDecision.disposition.rawValue,
                WakeWindowRecoveryPolicy.geometryFreshnessMarker(
                    wasFreshlyEnumerated: !temporarilyDeferredWindowKeys.contains(tracked.key)
                ),
                String(tracked.layoutOrder),
                String(tracked.layoutWeight),
                Self.layoutDecision(
                    layoutOverride: tracked.layoutOverride,
                    admissionDecision: tracked.admissionDecision,
                    rule: rule
                ).rawValue,
                String(rule.keepsOnAllWorkspaces),
                String(rule.floatsSecondaryWindows),
            ].joined(separator: "|")
        })
        return parts.joined(separator: "\n")
    }

    private func isWorkspaceActive(_ workspaceID: UUID) -> Bool {
        activeWorkspaceIDs.contains(workspaceID)
    }

    private func interactionWorkspaceID() -> UUID {
        if let focusedKey = interactionFocusedWindowSnapshot()?.key,
           let tracked = windows[focusedKey],
           isWorkspaceActive(tracked.workspaceID) {
            return tracked.workspaceID
        }
        if displayMode == .independent {
            let displayIdentifier = interactionDisplayIdentifier()
            return activeWorkspaceIDByDisplay[displayIdentifier] ?? currentWorkspaceID
        }
        return currentWorkspaceID
    }

    private func workspaceHomeDisplayIdentifier(
        for workspaceID: UUID,
        displays: [DisplaySnapshot]? = nil
    ) -> String {
        if let assigned = workspaceDisplayAssignments[workspaceID] { return assigned }
        let displays = displays ?? Self.activeDisplays()
        return displays.first(where: \.isMain)?.identifier
            ?? displays.first?.identifier
            ?? "main-display"
    }

    private func reconcileIndependentActiveWorkspaces(
        displays: [DisplaySnapshot],
        preferCurrentWorkspace: Bool = false
    ) {
        guard displayMode == .independent else { return }
        let displayByWorkspace = Dictionary(uniqueKeysWithValues: workspaces.map {
            ($0.id, workspaceHomeDisplayIdentifier(for: $0.id, displays: displays))
        })
        activeWorkspaceIDByDisplay = Self.reconciledIndependentActiveWorkspaces(
            workspaceIDs: workspaces.map(\.id),
            displayByWorkspace: displayByWorkspace,
            existing: activeWorkspaceIDByDisplay,
            preferredWorkspaceID: preferCurrentWorkspace ? currentWorkspaceID : nil
        )
    }

    static func reconciledIndependentActiveWorkspaces(
        workspaceIDs: [UUID],
        displayByWorkspace: [UUID: String],
        existing: [String: UUID],
        preferredWorkspaceID: UUID? = nil
    ) -> [String: UUID] {
        let validIDs = Set(workspaceIDs)
        var result = existing.filter { displayIdentifier, workspaceID in
            validIDs.contains(workspaceID) && displayByWorkspace[workspaceID] == displayIdentifier
        }
        let grouped = Dictionary(grouping: workspaceIDs, by: { displayByWorkspace[$0] ?? "main-display" })
        for (displayIdentifier, assignedWorkspaces) in grouped where result[displayIdentifier] == nil {
            result[displayIdentifier] = assignedWorkspaces.first
        }
        if let preferredWorkspaceID,
           validIDs.contains(preferredWorkspaceID),
           let displayIdentifier = displayByWorkspace[preferredWorkspaceID] {
            result[displayIdentifier] = preferredWorkspaceID
        }
        return result
    }

    static func remappedActiveWorkspaceDisplayIdentifiers(
        _ existing: [String: UUID],
        previousHomes: [UUID: String],
        currentHomes: [UUID: String]
    ) -> [String: UUID] {
        var result = existing
        for (displayIdentifier, workspaceID) in existing {
            guard previousHomes[workspaceID] == displayIdentifier,
                  let currentIdentifier = currentHomes[workspaceID],
                  currentIdentifier != displayIdentifier
            else { continue }
            result.removeValue(forKey: displayIdentifier)
            if result[currentIdentifier] == nil {
                result[currentIdentifier] = workspaceID
            }
        }
        return result
    }

    static func switchingIndependentWorkspace(
        _ workspaceID: UUID,
        displayIdentifier: String,
        in activeByDisplay: [String: UUID]
    ) -> [String: UUID] {
        var result = activeByDisplay.filter { $0.value != workspaceID }
        result[displayIdentifier] = workspaceID
        return result
    }

    static func workspaceDisplayMovePlan(
        workspaceIDs: [UUID],
        homeByWorkspace: [UUID: String],
        activeWorkspaceIDByDisplay: [String: UUID],
        movingWorkspaceID: UUID,
        sourceDisplayIdentifier: String,
        destinationDisplayIdentifier: String
    ) -> WorkspaceDisplayMovePlan? {
        guard sourceDisplayIdentifier != destinationDisplayIdentifier,
              workspaceIDs.contains(movingWorkspaceID),
              activeWorkspaceIDByDisplay[sourceDisplayIdentifier] == movingWorkspaceID
        else { return nil }

        let activeElsewhere = Set(activeWorkspaceIDByDisplay.compactMap { display, workspace in
            display == sourceDisplayIdentifier || display == destinationDisplayIdentifier
                ? nil : workspace
        })
        let displaced = activeWorkspaceIDByDisplay[destinationDisplayIdentifier].flatMap {
            $0 == movingWorkspaceID ? nil : $0
        }
        let replacement = displaced ?? workspaceIDs.first { workspaceID in
            workspaceID != movingWorkspaceID &&
                homeByWorkspace[workspaceID] == sourceDisplayIdentifier &&
                !activeElsewhere.contains(workspaceID)
        }
        guard let replacement else { return nil }

        var assignments: [UUID: String] = [
            movingWorkspaceID: destinationDisplayIdentifier,
        ]
        if homeByWorkspace[replacement] != sourceDisplayIdentifier {
            assignments[replacement] = sourceDisplayIdentifier
        }
        var active = activeWorkspaceIDByDisplay.filter {
            $0.value != movingWorkspaceID && $0.value != replacement
        }
        active[sourceDisplayIdentifier] = replacement
        active[destinationDisplayIdentifier] = movingWorkspaceID
        return WorkspaceDisplayMovePlan(
            movingWorkspaceID: movingWorkspaceID,
            replacementWorkspaceID: replacement,
            sourceDisplayIdentifier: sourceDisplayIdentifier,
            destinationDisplayIdentifier: destinationDisplayIdentifier,
            changedAssignments: assignments,
            activeWorkspaceIDByDisplay: active
        )
    }

    static func initialWorkspaceID(
        for displayIdentifier: String?,
        mode: MultiDisplayMode,
        currentWorkspaceID: UUID,
        activeWorkspaceIDByDisplay: [String: UUID]
    ) -> UUID {
        guard mode == .independent,
              let displayIdentifier,
              let displayWorkspace = activeWorkspaceIDByDisplay[displayIdentifier]
        else { return currentWorkspaceID }
        return displayWorkspace
    }

    static func routedWorkspaceID(
        fallbackWorkspaceID: UUID,
        rule: ResolvedAppRule
    ) -> UUID {
        rule.assignedWorkspaceID ?? fallbackWorkspaceID
    }

    static func shouldWindowBeVisible(
        workspaceID: UUID,
        activeWorkspaceIDs: Set<UUID>,
        rule: ResolvedAppRule
    ) -> Bool {
        rule.keepsOnAllWorkspaces || activeWorkspaceIDs.contains(workspaceID)
    }

    static func shouldIncludeInLayout(rule: ResolvedAppRule) -> Bool {
        !rule.excludesFromLayout
    }

    static func shouldIncludeInLayout(
        isFloating: Bool,
        rule: ResolvedAppRule
    ) -> Bool {
        !isFloating && !rule.excludesFromLayout
    }

    static func shouldIncludeInLayout(
        layoutOverride: WindowLayoutOverride,
        admissionDecision: WindowAdmissionDecision,
        rule: ResolvedAppRule
    ) -> Bool {
        layoutDecision(
            layoutOverride: layoutOverride,
            admissionDecision: admissionDecision,
            rule: rule
        ).includesInLayout
    }

    static func focusFollowPlan(
        focusedWorkspaceID: UUID,
        mode: MultiDisplayMode,
        currentWorkspaceID: UUID,
        activeWorkspaceIDByDisplay: [String: UUID],
        homeDisplayIdentifier: String?
    ) -> FocusFollowPlan? {
        switch mode {
        case .unified:
            guard focusedWorkspaceID != currentWorkspaceID else { return nil }
            return FocusFollowPlan(
                displayIdentifier: nil,
                sourceWorkspaceID: currentWorkspaceID,
                targetWorkspaceID: focusedWorkspaceID
            )
        case .independent:
            guard let homeDisplayIdentifier else { return nil }
            let source = activeWorkspaceIDByDisplay[homeDisplayIdentifier]
            guard source != focusedWorkspaceID else { return nil }
            return FocusFollowPlan(
                displayIdentifier: homeDisplayIdentifier,
                sourceWorkspaceID: source,
                targetWorkspaceID: focusedWorkspaceID
            )
        }
    }

    static func focusObservationDisposition<T: Equatable>(
        focusedWindow: T?,
        lastObservedFocusedWindow: T?,
        programmaticFocusTarget: T?,
        programmaticGraceActive: Bool
    ) -> FocusObservationDisposition {
        if let programmaticFocusTarget, focusedWindow == programmaticFocusTarget {
            return .programmaticTarget
        }
        if programmaticFocusTarget != nil, programmaticGraceActive {
            return .deferExternalChange
        }
        return focusedWindow == lastObservedFocusedWindow ? .unchanged : .externalChange
    }

    static func shouldIgnoreFocusObservation(
        focusedWindow: WindowKey?,
        ignoredWindowKeys: Set<WindowKey>
    ) -> Bool {
        focusedWindow.map(ignoredWindowKeys.contains) == true
    }

    static func shouldPreserveInteractionFocusAnchor(
        focusedWindow: WindowKey?,
        ownProcessIdentifier: pid_t,
        ignoredWindowKeys: Set<WindowKey>,
        commandPalettePresented: Bool = false
    ) -> Bool {
        guard let focusedWindow else { return commandPalettePresented }
        return focusedWindow.processIdentifier == ownProcessIdentifier ||
            ignoredWindowKeys.contains(focusedWindow)
    }

    static func exactWindowFocusPlan(applicationIsActive: Bool) -> [ExactWindowFocusStep] {
        applicationIsActive
            ? [.markWindowMain, .focusWindowElement, .focusApplicationWindow, .raiseWindow]
            : [
                .markWindowMain,
                .raiseWindow,
                .makeApplicationFrontmost,
                .markWindowMain,
                .focusWindowElement,
                .focusApplicationWindow,
                .raiseWindow,
            ]
    }

    static func shouldUseAppKitActivationFallback(
        accessibilityFrontmostResult: AXError
    ) -> Bool {
        accessibilityFrontmostResult != .success
    }

    static func focusCycleAttemptOrder<T: Equatable>(
        current: T?,
        orderedCandidates: [T],
        offset: Int
    ) -> [T] {
        guard !orderedCandidates.isEmpty, offset != 0 else { return [] }
        let direction = offset < 0 ? -1 : 1
        let count = orderedCandidates.count
        let initialIndex: Int
        if let current, let currentIndex = orderedCandidates.firstIndex(of: current) {
            initialIndex = (currentIndex + offset % count + count) % count
        } else {
            initialIndex = direction < 0 ? count - 1 : 0
        }

        var result: [T] = []
        for step in 0..<count {
            let index = (initialIndex + step * direction + count * (step + 1)) % count
            let candidate = orderedCandidates[index]
            if candidate != current {
                result.append(candidate)
            }
        }
        return result
    }

    static func focusCycleVerificationDecision(
        expected: WindowKey,
        actual: WindowKey?,
        previousFocus: WindowKey? = nil,
        applicationIsActive: Bool,
        windowServerTargetIsFrontmostNormalWindow: Bool = false,
        appKitActivationAttempted: Bool = false,
        exactAttempt: Int,
        maximumExactAttempts: Int = 1
    ) -> FocusCycleVerificationDecision {
        if actual == expected { return .succeeded }
        if actual == nil,
           applicationIsActive,
           windowServerTargetIsFrontmostNormalWindow {
            return .succeeded
        }
        if let actual, actual == previousFocus, actual != expected {
            if !applicationIsActive && !appKitActivationAttempted {
                return .retryAppKitActivation
            }
            if applicationIsActive, exactAttempt < maximumExactAttempts {
                return .retryExactTarget
            }
            return .abortForCompetingFocus
        }
        if let actual, actual.processIdentifier != expected.processIdentifier {
            return .abortForCompetingFocus
        }
        if !applicationIsActive {
            return appKitActivationAttempted
                ? .advanceToNextCandidate
                : .retryAppKitActivation
        }
        return exactAttempt < maximumExactAttempts
            ? .retryExactTarget
            : .advanceToNextCandidate
    }

    static func workspaceSwitchFocusVerificationDecision(
        expected: WindowKey,
        actual: WindowKey?,
        previousFocus: WindowKey?,
        actualIsIgnored: Bool,
        applicationIsActive: Bool,
        windowServerTargetIsFrontmostNormalWindow: Bool = false,
        appKitActivationAttempted: Bool = false,
        exactAttempt: Int,
        maximumExactAttempts: Int = 1
    ) -> FocusCycleVerificationDecision {
        if actualIsIgnored { return .abortForCompetingFocus }
        return focusCycleVerificationDecision(
            expected: expected,
            actual: actual,
            previousFocus: previousFocus,
            applicationIsActive: applicationIsActive,
            windowServerTargetIsFrontmostNormalWindow: windowServerTargetIsFrontmostNormalWindow,
            appKitActivationAttempted: appKitActivationAttempted,
            exactAttempt: exactAttempt,
            maximumExactAttempts: maximumExactAttempts
        )
    }

    static func shouldReassertAfterActivation(
        activatedProcessIdentifier: pid_t,
        focusedProcessIdentifier: pid_t?
    ) -> Bool {
        focusedProcessIdentifier == nil || focusedProcessIdentifier == activatedProcessIdentifier
    }

    static func verificationIsCurrent(
        _ token: FocusVerificationToken,
        generation: UInt64
    ) -> Bool {
        token.generation == generation
    }

    static func shouldRecoverNilFocus(
        hasExpectedWindow: Bool,
        hasActualWindow: Bool,
        applicationIsActive: Bool,
        verificationIsCurrent: Bool
    ) -> Bool {
        hasExpectedWindow && !hasActualWindow && applicationIsActive && verificationIsCurrent
    }

    static func keyboardManipulationFocusDecision(
        expected: WindowKey,
        actual: WindowKey?,
        actualIsIgnored: Bool,
        expectedApplicationIsActive: Bool,
        recoveryAttempt: Int,
        maximumRecoveryAttempts: Int = 1
    ) -> KeyboardManipulationFocusDecision {
        if actual == expected { return .stable }
        guard !actualIsIgnored, expectedApplicationIsActive else {
            return .abortForCompetingFocus
        }
        if let actual, actual.processIdentifier != expected.processIdentifier {
            return .abortForCompetingFocus
        }
        return recoveryAttempt < maximumRecoveryAttempts
            ? .reassertExactTarget
            : .failedAfterRetry
    }

    private func observeFocusedWindow(
        _ focusedWindow: WindowKey?,
        isStartup: Bool,
        allowWorkspaceFollowing: Bool,
        observationCorrelationID: String? = nil
    ) {
        if Self.staleParkedFocusObservationIsSuppressed(
            focusedWindow: focusedWindow,
            suppressedWindows: Set(staleParkedFocusSuppression.keys)
        ) {
            // Polling can continue to report the just-parked AX window even after its focused/main
            // flags were cleared. Never interpret that stale observation as user intent.
            return
        }
        if let focusedWindow, !staleParkedFocusSuppression.isEmpty {
            staleParkedFocusSuppression = staleParkedFocusSuppression.filter { $0.key == focusedWindow }
        }
        if Self.shouldPreserveInteractionFocusAnchor(
            focusedWindow: focusedWindow,
            ownProcessIdentifier: ownProcessIdentifier,
            ignoredWindowKeys: ignoredWindowKeys,
            commandPalettePresented: commandPalettePresented
        ) {
            // WindowRanger's own palette/settings surfaces and ignored popups must not consume the
            // external managed anchor. The palette deliberately becomes key while it is open; the
            // captured command target still needs to validate against that preserved anchor.
            return
        }
        if isStartup {
            lastObservedFocusedWindow = focusedWindow
            diagnostics.log(
                category: "focus-observation",
                event: "startup-baseline",
                fields: ["window": focusedWindow.map(Self.diagnosticWindowKey) ?? "none"]
            )
            return
        }

        let correlationID = programmaticFocusCorrelationID ?? observationCorrelationID
        let graceActive = Date() < programmaticFocusDeadline
        let disposition = Self.focusObservationDisposition(
            focusedWindow: focusedWindow,
            lastObservedFocusedWindow: lastObservedFocusedWindow,
            programmaticFocusTarget: programmaticFocusTarget,
            programmaticGraceActive: graceActive
        )
        if disposition != .unchanged || correlationID != nil {
            diagnostics.log(
                category: "focus-observation",
                event: "poll",
                correlation: correlationID,
                fields: [
                    "window": focusedWindow.map(Self.diagnosticWindowKey) ?? "none",
                    "previous-window": lastObservedFocusedWindow.map(Self.diagnosticWindowKey) ?? "none",
                    "expected-window": programmaticFocusTarget.map(Self.diagnosticWindowKey) ?? "none",
                    "classification": String(describing: disposition),
                    "grace-active": String(graceActive),
                    "following-enabled": String(allowWorkspaceFollowing),
                ]
            )
        }
        if disposition == .programmaticTarget {
            lastObservedFocusedWindow = focusedWindow
            clearProgrammaticFocusIntent()
            return
        }
        if disposition == .deferExternalChange {
            // Do not consume a different external focus change during our short activation grace
            // period. If it persists, the next poll after the deadline will still observe it.
            diagnostics.log(
                category: "focus-observation",
                event: "competing-focus-deferred",
                correlation: correlationID,
                fields: ["window": focusedWindow.map(Self.diagnosticWindowKey) ?? "none"]
            )
            return
        }
        if programmaticFocusTarget != nil, disposition == .externalChange {
            diagnostics.log(
                category: "focus-observation",
                event: "unexpected-focus-after-intent",
                correlation: correlationID,
                fields: [
                    "expected-window": programmaticFocusTarget.map(Self.diagnosticWindowKey) ?? "none",
                    "actual-window": focusedWindow.map(Self.diagnosticWindowKey) ?? "none",
                ]
            )
        }
        clearProgrammaticFocusIntent()

        if disposition == .externalChange, focusedWindow != nil {
            recentInteractionDisplayIdentifier = nil
            recentInteractionFocusTarget = nil
            recentInteractionDisplayDeadline = .distantPast
        }

        guard allowWorkspaceFollowing else {
            lastObservedFocusedWindow = focusedWindow
            return
        }
        guard disposition == .externalChange else { return }
        lastObservedFocusedWindow = focusedWindow
        recentInteractionDisplayIdentifier = nil
        recentInteractionFocusTarget = nil
        recentInteractionDisplayDeadline = .distantPast
        guard let focusedWindow else { return }
        followFocusedManagedWindow(focusedWindow, correlationID: correlationID)
    }

    private func followFocusedManagedWindow(
        _ focusedWindow: WindowKey,
        correlationID: String? = nil
    ) {
        guard staleParkedFocusSuppression[focusedWindow] == nil else {
            diagnostics.log(
                category: "focus-follow",
                event: "ignored",
                correlation: correlationID,
                fields: [
                    "reason": "stale-parked-window-suppression",
                    "window": Self.diagnosticWindowKey(focusedWindow),
                ]
            )
            return
        }
        guard let tracked = windows[focusedWindow] else {
            diagnostics.log(
                category: "focus-follow",
                event: "ignored",
                correlation: correlationID,
                fields: ["reason": "unmanaged-window", "window": Self.diagnosticWindowKey(focusedWindow)]
            )
            return
        }
        guard !isExcludedFromWorkspaceParticipation(tracked) else {
            diagnostics.log(
                category: "focus-follow",
                event: "ignored",
                correlation: correlationID,
                fields: [
                    "reason": "application-hidden",
                    "window": Self.diagnosticWindowKey(focusedWindow),
                ]
            )
            return
        }

        let rule = resolvedRule(for: tracked.bundleIdentifier)
        guard !rule.keepsOnAllWorkspaces else {
            diagnostics.log(
                category: "focus-follow",
                event: "ignored",
                correlation: correlationID,
                fields: ["reason": "keep-on-all-workspaces", "window": Self.diagnosticWindowKey(focusedWindow)]
            )
            return
        }

        let homeDisplay = displayMode == .independent
            ? workspaceHomeDisplayIdentifier(for: tracked.workspaceID)
            : nil
        guard let plan = Self.focusFollowPlan(
            focusedWorkspaceID: tracked.workspaceID,
            mode: displayMode,
            currentWorkspaceID: currentWorkspaceID,
            activeWorkspaceIDByDisplay: activeWorkspaceIDByDisplay,
            homeDisplayIdentifier: homeDisplay
        ) else {
            diagnostics.log(
                category: "focus-follow",
                event: "ignored",
                correlation: correlationID,
                fields: [
                    "reason": "workspace-already-active-or-no-home",
                    "window": Self.diagnosticWindowKey(focusedWindow),
                    "workspace": Self.shortIdentifier(tracked.workspaceID.uuidString),
                ]
            )
            return
        }

        diagnostics.log(
            category: "focus-follow",
            event: "workspace-switch-planned",
            correlation: correlationID,
            fields: [
                "window": Self.diagnosticWindowKey(focusedWindow),
                "source-workspace": plan.sourceWorkspaceID.map { Self.shortIdentifier($0.uuidString) } ?? "none",
                "target-workspace": Self.shortIdentifier(plan.targetWorkspaceID.uuidString),
                "display": plan.displayIdentifier.map(Self.shortIdentifier) ?? "all",
                "active-before": diagnosticActiveWorkspaceMap(),
            ]
        )

        previousWorkspaceID = plan.sourceWorkspaceID
        currentWorkspaceID = plan.targetWorkspaceID
        if let displayIdentifier = plan.displayIdentifier {
            if let source = plan.sourceWorkspaceID {
                previousWorkspaceIDByDisplay[displayIdentifier] = source
            }
            activeWorkspaceIDByDisplay = Self.switchingIndependentWorkspace(
                plan.targetWorkspaceID,
                displayIdentifier: displayIdentifier,
                in: activeWorkspaceIDByDisplay
            )
        }

        if let source = plan.sourceWorkspaceID {
            applyVisibilityTransition(
                from: source,
                to: plan.targetWorkspaceID,
                correlationID: correlationID
            )
        } else {
            applyVisibleWindows(
                windows.values.filter { $0.workspaceID == plan.targetWorkspaceID },
                displays: Self.activeDisplays(),
                correlationID: correlationID
            )
        }
        persistState(preservingPendingRestores: true)
        emitState()
        diagnostics.log(
            category: "focus-follow",
            event: "workspace-switch-complete",
            correlation: correlationID,
            fields: ["active-after": diagnosticActiveWorkspaceMap()]
        )
    }

    private func switchIndependentDisplay(
        to workspaceID: UUID,
        sourceInteractionDisplayIdentifier: String,
        previousFocusKey: WindowKey?,
        displays: [DisplaySnapshot],
        correlationID: String,
        selectedApplication: WorkspaceApplicationTarget? = nil,
        selectedWindowKey: WindowKey? = nil
    ) {
        reconcileIndependentActiveWorkspaces(displays: displays)
        let logicalDisplayIdentifier = workspaceHomeDisplayIdentifier(
            for: workspaceID,
            displays: displays
        )
        guard let destination = WorkspaceSwitchDestinationPolicy.resolve(
            logicalHomeDisplayIdentifier: logicalDisplayIdentifier,
            displays: displays
        ) else {
            diagnostics.log(
                category: "workspace-switch-focus",
                event: "cancelled",
                correlation: correlationID,
                fields: [
                    "workspace": Self.shortIdentifier(workspaceID.uuidString),
                    "reason": "no-connected-display",
                ]
            )
            return
        }
        let sourceWorkspaceID = activeWorkspaceIDByDisplay[destination.logicalDisplayIdentifier]
        let token = beginCorrelatedAction(
            correlationID: correlationID,
            interactionDisplayIdentifier: destination.physicalDisplayIdentifier,
            expectedFocusTarget: nil
        )
        logWorkspaceSwitchBegin(
            workspaceID: workspaceID,
            sourceWorkspaceID: sourceWorkspaceID,
            sourceInteractionDisplayIdentifier: sourceInteractionDisplayIdentifier,
            destination: destination,
            correlationID: correlationID,
            reason: sourceWorkspaceID == workspaceID
                ? "independent-workspace-already-active"
                : "independent-workspace-home"
        )

        if sourceWorkspaceID != workspaceID {
            if let sourceWorkspaceID {
                previousWorkspaceIDByDisplay[destination.logicalDisplayIdentifier] = sourceWorkspaceID
                previousWorkspaceID = sourceWorkspaceID
            }
            activeWorkspaceIDByDisplay = Self.switchingIndependentWorkspace(
                workspaceID,
                displayIdentifier: destination.logicalDisplayIdentifier,
                in: activeWorkspaceIDByDisplay
            )
        }
        currentWorkspaceID = workspaceID

        if sourceWorkspaceID != workspaceID {
            if let sourceWorkspaceID {
                applyVisibilityTransition(
                    from: sourceWorkspaceID,
                    to: workspaceID,
                    correlationID: correlationID
                )
            } else {
                applyVisibleWindows(
                    windows.values.filter { $0.workspaceID == workspaceID },
                    displays: displays,
                    correlationID: correlationID
                )
            }
        }
        persistState(preservingPendingRestores: true)
        emitState()
        focusWorkspaceAfterSwitch(
            workspaceID: workspaceID,
            destinationDisplayIdentifier: destination.physicalDisplayIdentifier,
            displays: displays,
            correlationID: correlationID,
            token: token,
            previousFocusKey: previousFocusKey,
            selectedApplication: selectedApplication,
            selectedWindowKey: selectedWindowKey
        )
    }

    private func interactionDisplayIdentifier() -> String {
        let displays = Self.activeDisplays()
        if let focusedKey = interactionFocusedWindowSnapshot()?.key, let tracked = windows[focusedKey] {
            if resolvedRule(for: tracked.bundleIdentifier).keepsOnAllWorkspaces,
               let frame = AccessibilityWindow.frame(of: tracked.element),
               let displayIdentifier = Self.displayPlacement(for: frame, displays: displays)?.displayIdentifier {
                return displayIdentifier
            }
            return workspaceHomeDisplayIdentifier(for: tracked.workspaceID, displays: displays)
        }
        return displays.first(where: \.isMain)?.identifier
            ?? displays.first?.identifier
            ?? "main-display"
    }

    private func focusedWindowSnapshot() -> FocusedWindowSnapshot? {
        let system = AXUIElementCreateSystemWide()
        guard let focusedApp = AccessibilityWindow.copyAttribute(
            system,
            kAXFocusedApplicationAttribute as CFString,
            as: AXUIElement.self
        ),
        let focusedWindow = AccessibilityWindow.copyAttribute(
            focusedApp,
            kAXFocusedWindowAttribute as CFString,
            as: AXUIElement.self
        ) else { return nil }

        var processIdentifier: pid_t = 0
        AXUIElementGetPid(focusedApp, &processIdentifier)
        guard let key = AccessibilityWindow.identifier(
            for: focusedWindow,
            processIdentifier: processIdentifier
        ) else { return nil }
        return FocusedWindowSnapshot(
            key: key,
            element: focusedWindow,
            frame: AccessibilityWindow.frame(of: focusedWindow)
        )
    }

    /// An ignored popup must not become the interaction anchor. Preserve the most recent managed
    /// anchor instead, so clicking a pet cannot redirect the next display-local command.
    private func interactionFocusedWindowSnapshot(
        _ rawFocusedWindow: FocusedWindowSnapshot? = nil
    ) -> FocusedWindowSnapshot? {
        let rawFocusedWindow = rawFocusedWindow ?? focusedWindowSnapshot()
        guard let rawFocusedWindow else {
            guard commandPalettePresented else { return nil }
            return preservedInteractionFocusSnapshot()
        }
        let unusableAnchor = rawFocusedWindow.key.processIdentifier == ownProcessIdentifier ||
            ignoredWindowKeys.contains(rawFocusedWindow.key) ||
            isDropDownAppWindow(rawFocusedWindow.key) ||
            windows[rawFocusedWindow.key].map(isExcludedFromWorkspaceParticipation) == true ||
            staleParkedFocusSuppression[rawFocusedWindow.key] != nil
        guard unusableAnchor else { return rawFocusedWindow }

        return preservedInteractionFocusSnapshot()
    }

    private func preservedInteractionFocusSnapshot() -> FocusedWindowSnapshot? {
        let fallbackKeys = [recentInteractionFocusTarget, lastObservedFocusedWindow].compactMap { $0 }
        for key in fallbackKeys {
            guard !isDropDownAppWindow(key),
                  staleParkedFocusSuppression[key] == nil,
                  let tracked = windows[key],
                  !isExcludedFromWorkspaceParticipation(tracked)
            else { continue }
            return FocusedWindowSnapshot(
                key: key,
                element: tracked.element,
                frame: AccessibilityWindow.frame(of: tracked.element)
            )
        }
        return nil
    }

    private func interactionDisplayResolution(
        focused: FocusedWindowSnapshot?,
        displays: [DisplaySnapshot]
    ) -> (identifier: String, reason: String) {
        let managedWorkspaceHome: String?
        if let key = focused?.key, let tracked = windows[key] {
            managedWorkspaceHome = workspaceHomeDisplayIdentifier(
                for: tracked.workspaceID,
                displays: displays
            )
        } else {
            managedWorkspaceHome = nil
        }
        return Self.interactionDisplaySelection(
            focusedFrame: focused?.frame,
            mode: displayMode,
            managedWorkspaceHomeDisplayIdentifier: managedWorkspaceHome,
            recentInteractionDisplayIdentifier: Date() < recentInteractionDisplayDeadline
                ? recentInteractionDisplayIdentifier
                : nil,
            displays: displays
        )
    }

    /// Resolves the same display that the next keyboard command will act upon. Passive overlays
    /// use this instead of the pointer display so their location never contradicts command scope.
    func currentInteractionDisplayIdentifier() -> String {
        let displays = Self.activeDisplays()
        return interactionDisplayResolution(
            focused: interactionFocusedWindowSnapshot(),
            displays: displays
        ).identifier
    }

    /// Returns only the live Shelf presentation facts needed by the passive Shortcut Guide.
    /// Reading on the engine queue keeps presentation changes and display ownership coherent.
    func currentShortcutGuideShelfContext() -> ShortcutGuideShelfRuntimeContext? {
        queue.sync {
            guard let session = dropDownAppSession, session.isPresented else { return nil }
            return ShortcutGuideShelfRuntimeContext(
                direction: quickAppShelfPresentation.direction,
                displayIdentifier: session.displayIdentifier
            )
        }
    }

    static func interactionDisplaySelection(
        focusedFrame: WindowFrame?,
        mode: MultiDisplayMode,
        managedWorkspaceHomeDisplayIdentifier: String?,
        recentInteractionDisplayIdentifier: String? = nil,
        displays: [DisplaySnapshot]
    ) -> (identifier: String, reason: String) {
        if let focusedFrame,
           let placement = displayPlacement(for: focusedFrame, displays: displays) {
            return (placement.displayIdentifier, "focused-window-frame")
        }
        if mode == .independent, let managedWorkspaceHomeDisplayIdentifier {
            if displays.contains(where: { $0.identifier == managedWorkspaceHomeDisplayIdentifier }) {
                return (managedWorkspaceHomeDisplayIdentifier, "independent-workspace-home-no-frame")
            }
            if let main = displays.first(where: \.isMain) {
                return (main.identifier, "independent-home-disconnected-main-fallback")
            }
            if let first = displays.first {
                return (first.identifier, "independent-home-disconnected-first-fallback")
            }
        }
        if let recentInteractionDisplayIdentifier,
           displays.contains(where: { $0.identifier == recentInteractionDisplayIdentifier }) {
            return (recentInteractionDisplayIdentifier, "recent-action-display-no-focused-frame")
        }
        if let main = displays.first(where: \.isMain) {
            return (main.identifier, "main-display-fallback-no-focused-frame")
        }
        if let first = displays.first {
            return (first.identifier, "first-display-fallback")
        }
        return ("main-display", "sentinel-no-active-displays")
    }

    static func shouldDiscoverApplication(
        processIdentifier: pid_t,
        ownProcessIdentifier: pid_t,
        isRegularApplication: Bool,
        isTerminated: Bool
    ) -> Bool {
        processIdentifier != ownProcessIdentifier && isRegularApplication && !isTerminated
    }

    static func shouldProcessApplicationActivation(
        processIdentifier: pid_t,
        ownProcessIdentifier: pid_t
    ) -> Bool {
        processIdentifier != ownProcessIdentifier
    }

    /// Application activation normally cancels an in-flight Placement Wheel gesture. The one safe
    /// exception is the activation WindowRanger itself just requested to target the pointer window
    /// for that same gesture. The target, deadline, and focus generation must all still agree; any
    /// external or stale activation continues to cancel immediately.
    static func shouldCancelRadialInteractionForActivation(
        activatedProcessIdentifier: pid_t,
        expectedProcessIdentifier: pid_t?,
        programmaticFocusDeadline: Date,
        now: Date,
        verificationIsCurrent: Bool
    ) -> Bool {
        guard let expectedProcessIdentifier,
              activatedProcessIdentifier == expectedProcessIdentifier,
              now < programmaticFocusDeadline,
              verificationIsCurrent
        else { return true }
        return false
    }

    func radialPointerFocusPresentationFinished() {
        queue.async { [weak self] in
            self?.clearRadialPointerFocusIntent()
        }
    }

    @discardableResult
    private func beginCorrelatedAction(
        correlationID: String,
        interactionDisplayIdentifier: String,
        expectedFocusTarget: WindowKey?
    ) -> FocusVerificationToken {
        let now = Date()
        supersededProgrammaticActivationUntil = supersededProgrammaticActivationUntil.filter {
            $0.value > now
        }
        if let previousTarget = programmaticFocusTarget,
           previousTarget != expectedFocusTarget {
            supersededProgrammaticActivationUntil[previousTarget.processIdentifier] =
                now.addingTimeInterval(0.9)
        }
        clearProgrammaticFocusIntent()
        let generation = advanceFocusActionGeneration()
        pendingFocusVerification?.cancel()
        pendingFocusVerification = nil
        recentInteractionDisplayIdentifier = interactionDisplayIdentifier
        recentInteractionFocusTarget = expectedFocusTarget
        recentInteractionDisplayDeadline = Date().addingTimeInterval(1.75)
        return FocusVerificationToken(
            generation: generation,
            correlationID: correlationID
        )
    }

    private func advanceFocusActionGeneration() -> UInt64 {
        focusActionGenerationLock.lock()
        focusActionGeneration &+= 1
        let generation = focusActionGeneration
        focusActionGenerationLock.unlock()
        return generation
    }

    private func currentFocusActionGeneration() -> UInt64 {
        focusActionGenerationLock.lock()
        let generation = focusActionGeneration
        focusActionGenerationLock.unlock()
        return generation
    }

    private func isFocusActionGenerationCurrent(_ generation: UInt64) -> Bool {
        currentFocusActionGeneration() == generation
    }

    private func clearProgrammaticFocusIntent() {
        programmaticFocusTarget = nil
        programmaticFocusDeadline = .distantPast
        programmaticFocusCorrelationID = nil
        programmaticFocusGeneration = nil
    }

    private func clearRadialPointerFocusIntent() {
        radialPointerFocusProcessIdentifier = nil
        radialPointerFocusDeadline = .distantPast
        radialPointerFocusGeneration = nil
    }

    private func interactionWorkspaceResolution(
        focusedKey: WindowKey?,
        displayIdentifier: String
    ) -> (workspaceID: UUID, reason: String) {
        if let focusedKey,
           let tracked = windows[focusedKey],
           isWorkspaceActive(tracked.workspaceID) {
            return (tracked.workspaceID, "focused-managed-window")
        }
        if displayMode == .independent,
           let active = activeWorkspaceIDByDisplay[displayIdentifier] {
            return (active, "independent-active-workspace-for-display")
        }
        return (
            currentWorkspaceID,
            displayMode == .unified ? "unified-current-workspace" : "current-workspace-fallback"
        )
    }

    private func focusedWindowKey() -> WindowKey? {
        focusedWindowSnapshot()?.key
    }

    private func showDropDownApp(
        _ target: TrackedWindow,
        configuration: DropDownAppConfiguration,
        correlationID: String
    ) {
        let displays = Self.activeDisplays()
        guard let display = dropDownTargetDisplay(displays: displays) else {
            emitCommandFeedback("No display is available for the Quick App.", correlationID: correlationID)
            abandonQuickAppApplicationSwitchHandoff(
                reason: "no-display",
                correlationID: correlationID
            )
            pendingQuickAppPresentationContext = nil
            pendingQuickAppHideAfterPresentation = false
            quickAppTransition = .idle
            continuePendingQuickAppSelectionIfPossible()
            return
        }
        quickAppTransition = .showing(
            Self.normalizedBundleIdentifier(configuration.bundleIdentifier)
        )
        let previousFocus: WindowKey?
        if let pendingContext = pendingQuickAppPresentationContext {
            previousFocus = pendingContext.previousFocusKey == target.key
                ? nil : pendingContext.previousFocusKey
            pendingQuickAppPresentationContext = nil
        } else {
            let focusedKey = interactionFocusedWindowSnapshot()?.key
            previousFocus = focusedKey == target.key ? nil : focusedKey
        }
        let presentationBounds = dropDownAppPresentationBounds(for: display)
        let presented = DropDownAppGeometry.presentedFrame(
            in: presentationBounds,
            sizeFraction: configuration.heightFraction,
            direction: configuration.direction
        )
        let ownedTargets = (dropDownAppSession?.windowKeys ?? [target.key]).compactMap {
            windows[$0]
        }
        let ownsMultipleWindows = ownedTargets.count > 1
        let ownedPresentedFrames = DropDownAppGeometry.groupFrames(
            in: presented,
            count: ownedTargets.count,
            style: quickAppShelfPresentation.layoutStyle,
            direction: quickAppShelfPresentation.direction
        )
        let targetPresented = zip(ownedTargets, ownedPresentedFrames)
            .first(where: { $0.0.key == target.key })?.1 ?? presented
        let targetRetracted = DropDownAppGeometry.retractedFrame(
            for: targetPresented,
            in: presentationBounds,
            direction: configuration.direction
        )
        dropDownAnimationGeneration &+= 1
        let generation = dropDownAnimationGeneration
        let wasHiddenByWindowRanger = dropDownAppSession.map {
            $0.windowKey == target.key && $0.isApplicationHiddenByWindowRanger
        } == true
        let applicationWasHidden = isDropDownApplicationHidden(
            processIdentifier: target.processIdentifier,
            bundleIdentifier: configuration.bundleIdentifier
        ) == true
        if ownsMultipleWindows {
            // App visibility is application-wide, so stage every owned window inside the Shelf
            // before unhiding. This prevents sibling windows flashing at their workspace frames.
            for (ownedTarget, frame) in zip(ownedTargets, ownedPresentedFrames) {
                _ = setDropDownAppFrame(frame, target: ownedTarget)
            }
        } else {
            let initialFrame = configuration.isAnimationEnabled ? targetRetracted : targetPresented
            _ = setDropDownAppFrame(initialFrame, target: target)
        }
        let shouldUnhideApplication = wasHiddenByWindowRanger || applicationWasHidden
        let unhideRequestAccepted = !shouldUnhideApplication || requestDropDownApplicationHidden(
            false,
            processIdentifier: target.processIdentifier,
            bundleIdentifier: configuration.bundleIdentifier
        )
        guard unhideRequestAccepted else {
            diagnostics.log(
                category: "drop-down-app",
                event: "show-failed",
                correlation: correlationID,
                fields: [
                    "window": Self.diagnosticWindowKey(target.key),
                    "reason": "application-unhide-request-rejected",
                    "application-hidden-observed": isDropDownApplicationHidden(
                        processIdentifier: target.processIdentifier,
                        bundleIdentifier: configuration.bundleIdentifier
                    )
                        .map(String.init) ?? "unavailable",
                ]
            )
            abandonQuickAppApplicationSwitchHandoff(
                reason: "application-unhide-request-rejected",
                correlationID: correlationID
            )
            pendingQuickAppHideAfterPresentation = false
            quickAppTransition = .idle
            continuePendingQuickAppSelectionIfPossible()
            return
        }

        if shouldUnhideApplication,
           isDropDownApplicationHidden(
               processIdentifier: target.processIdentifier,
               bundleIdentifier: configuration.bundleIdentifier
           ) != false {
            awaitDropDownAppUnhidden(
                target,
                configuration: configuration,
                display: display,
                presented: targetPresented,
                retracted: targetRetracted,
                previousFocus: previousFocus,
                generation: generation,
                correlationID: correlationID,
                attempt: 0
            )
            return
        }
        completeDropDownAppShow(
            target,
            configuration: configuration,
            display: display,
            presented: targetPresented,
            retracted: targetRetracted,
            previousFocus: previousFocus,
            generation: generation,
            correlationID: correlationID,
            unhideConfirmationAttempts: 0
        )
    }

    private func awaitDropDownAppUnhidden(
        _ target: TrackedWindow,
        configuration: DropDownAppConfiguration,
        display: DisplaySnapshot,
        presented: WindowFrame,
        retracted: WindowFrame,
        previousFocus: WindowKey?,
        generation: UInt64,
        correlationID: String,
        attempt: Int
    ) {
        guard dropDownAnimationGeneration == generation,
              dropDownAppSession?.windowKey == target.key,
              windows[target.key] != nil
        else { return }
        let observedHidden = isDropDownApplicationHidden(
            processIdentifier: target.processIdentifier,
            bundleIdentifier: configuration.bundleIdentifier
        )
        switch DropDownAppVisibilityConfirmationPolicy.disposition(
            expectedHidden: false,
            observedHidden: observedHidden,
            attempt: attempt
        ) {
        case .confirmed:
            completeDropDownAppShow(
                target,
                configuration: configuration,
                display: display,
                presented: presented,
                retracted: retracted,
                previousFocus: previousFocus,
                generation: generation,
                correlationID: correlationID,
                unhideConfirmationAttempts: attempt
            )
            return
        case .timedOut:
            _ = requestDropDownApplicationHidden(
                true,
                processIdentifier: target.processIdentifier,
                bundleIdentifier: configuration.bundleIdentifier
            )
            diagnostics.log(
                category: "drop-down-app",
                event: "show-failed",
                correlation: correlationID,
                fields: [
                    "window": Self.diagnosticWindowKey(target.key),
                    "reason": "application-unhide-confirmation-timeout",
                    "confirmation-attempts": String(attempt),
                    "application-hidden-observed": observedHidden.map(String.init) ?? "unavailable",
                ]
            )
            abandonQuickAppApplicationSwitchHandoff(
                reason: "application-unhide-confirmation-timeout",
                correlationID: correlationID
            )
            pendingQuickAppHideAfterPresentation = false
            quickAppTransition = .idle
            continuePendingQuickAppSelectionIfPossible()
            return
        case .retry:
            break
        }
        queue.asyncAfter(deadline: .now() + .milliseconds(75)) { [weak self] in
            self?.awaitDropDownAppUnhidden(
                target,
                configuration: configuration,
                display: display,
                presented: presented,
                retracted: retracted,
                previousFocus: previousFocus,
                generation: generation,
                correlationID: correlationID,
                attempt: attempt + 1
            )
        }
    }

    private func completeDropDownAppShow(
        _ target: TrackedWindow,
        configuration: DropDownAppConfiguration,
        display: DisplaySnapshot,
        presented: WindowFrame,
        retracted: WindowFrame,
        previousFocus: WindowKey?,
        generation: UInt64,
        correlationID: String,
        unhideConfirmationAttempts: Int
    ) {
        guard dropDownAnimationGeneration == generation,
              dropDownAppSession?.windowKey == target.key,
              windows[target.key] != nil
        else { return }
        let ownedWindowKeys = dropDownAppSession?.windowKeys ?? [target.key]
        dropDownAppSession = DropDownAppSession(
            windowKey: target.key,
            additionalWindowKeys: ownedWindowKeys.filter { $0 != target.key },
            bundleIdentifier: configuration.bundleIdentifier,
            direction: configuration.direction,
            isAnimationEnabled: configuration.isAnimationEnabled,
            isPresented: true,
            isApplicationHiddenByWindowRanger: false,
            displayIdentifier: display.identifier,
            previousFocusKey: previousFocus
        )
        emitState()
        let incomingBundleKey = Self.normalizedBundleIdentifier(configuration.bundleIdentifier)
        let isApplicationSwitchHandoff = quickAppApplicationSwitchHandoff?.incomingBundleKey ==
            incomingBundleKey
        quickAppTransition = isApplicationSwitchHandoff
            ? .showing(incomingBundleKey)
            : .idle
        let shouldAnimate = configuration.isAnimationEnabled && ownedWindowKeys.count == 1
        if shouldAnimate {
            // Some applications defer hidden-window frame changes until restore. Reassert the
            // collapsed edge frame after unhiding before the first intentional animation step.
            _ = setDropDownAppFrame(retracted, target: target)
            animateDropDownApp(
                target,
                frames: DropDownAppGeometry.animationFrames(from: retracted, to: presented),
                generation: generation
            ) { [weak self] in
                self?.logDropDownAppShown(
                    target,
                    display: display,
                    configuration: configuration,
                    requestedFrame: presented,
                    correlationID: correlationID,
                    unhideConfirmationAttempts: unhideConfirmationAttempts
                )
                if isApplicationSwitchHandoff {
                    self?.restackPresentedQuickAppGroup(correlationID: correlationID)
                } else {
                    self?.reconcilePresentedQuickAppGroup(
                        correlationID: correlationID,
                        focusSelected: false
                    )
                }
            }
        } else {
            if ownedWindowKeys.count == 1 {
                _ = setDropDownAppFrame(presented, target: target)
            }
            logDropDownAppShown(
                target,
                display: display,
                configuration: configuration,
                requestedFrame: presented,
                correlationID: correlationID,
                unhideConfirmationAttempts: unhideConfirmationAttempts
            )
            if isApplicationSwitchHandoff {
                restackPresentedQuickAppGroup(correlationID: correlationID)
            } else {
                reconcilePresentedQuickAppGroup(
                    correlationID: correlationID,
                    focusSelected: false
                )
            }
        }
        if pendingQuickAppHideAfterPresentation {
            pendingQuickAppHideAfterPresentation = false
            hideDropDownApp(
                restorePreviousFocus: false,
                reason: "another-app-focused-during-show",
                correlationID: correlationID
            )
            return
        }
        if pendingQuickAppSelection != nil,
           !isApplicationSwitchHandoff {
            continuePendingQuickAppSelectionIfPossible()
            if quickAppTransition != .idle { return }
        }
        let focusesAfterShow = QuickAppInteractionPolicy.focusesQuickAppAfterShow(
            commandPalettePresented: commandPalettePresented
        )
        if focusesAfterShow {
            let applicationWasAlreadyActive = NSRunningApplication(
                processIdentifier: target.processIdentifier
            )?.isActive == true
            focusManagedWindow(target.key, tracked: target, correlationID: correlationID)
            if isApplicationSwitchHandoff,
               applicationWasAlreadyActive {
                completeQuickAppApplicationSwitchHandoff()
            }
        } else {
            diagnostics.log(
                category: "command-palette",
                event: "shelf-preview-focus-retained",
                correlation: correlationID,
                fields: ["window": Self.diagnosticWindowKey(target.key)]
            )
            if isApplicationSwitchHandoff {
                completeQuickAppApplicationSwitchHandoff()
            }
        }
        persistState(preservingPendingRestores: true)
    }

    private func logDropDownAppShown(
        _ target: TrackedWindow,
        display: DisplaySnapshot,
        configuration: DropDownAppConfiguration,
        requestedFrame: WindowFrame,
        correlationID: String,
        unhideConfirmationAttempts: Int
    ) {
        let observedFrame = AccessibilityWindow.frame(of: target.element)
        diagnostics.log(
            category: "drop-down-app",
            event: "shown",
            correlation: correlationID,
            fields: [
                "window": Self.diagnosticWindowKey(target.key),
                "display": display.identifier,
                "size-percent": String(Int((configuration.heightFraction * 100).rounded())),
                "direction": configuration.direction.rawValue,
                "animated": String(configuration.isAnimationEnabled),
                "unhide-confirmation-attempts": String(unhideConfirmationAttempts),
                "requested-frame": Self.diagnosticFrame(requestedFrame),
                "observed-frame": observedFrame.map(Self.diagnosticFrame) ?? "unavailable",
                "frame-matched": String(observedFrame.map {
                    AccessibilityWindow.framesMatch($0, requestedFrame)
                } == true),
                "application-hidden-observed": isDropDownApplicationHidden(
                    processIdentifier: target.processIdentifier,
                    bundleIdentifier: configuration.bundleIdentifier
                )
                    .map(String.init) ?? "unavailable",
            ]
        )
    }

    private func hideDropDownApp(
        restorePreviousFocus: Bool,
        reason: String,
        correlationID: String?
    ) {
        if quickAppApplicationSwitchHandoff != nil,
           dropDownAppSession?.isPresented != true {
            abandonQuickAppApplicationSwitchHandoff(
                reason: "dismissed-before-incoming-presentation",
                correlationID: correlationID
            )
        }
        quickAppApplicationSwitchHandoff = nil
        guard var session = dropDownAppSession,
              session.isPresented,
              let target = windows[session.windowKey]
        else { return }
        let selectedBundleKey = Self.normalizedBundleIdentifier(session.bundleIdentifier)
        for (bundleKey, neighbor) in Array(quickAppSessions)
        where bundleKey != selectedBundleKey && neighbor.isPresented {
            beginHidingQuickAppNeighbor(
                bundleKey: bundleKey,
                session: neighbor,
                reason: reason,
                correlationID: correlationID
            )
        }
        quickAppTransition = .hiding(
            Self.normalizedBundleIdentifier(session.bundleIdentifier)
        )
        session.isPresented = false
        session.isApplicationHiddenByWindowRanger = false
        dropDownAppSession = session
        emitState()
        dropDownAnimationGeneration &+= 1
        let generation = dropDownAnimationGeneration
        let displays = Self.activeDisplays()
        let current = AccessibilityWindow.frame(of: target.element)
        let display = session.displayIdentifier.flatMap { identifier in
            displays.first { $0.identifier == identifier }
        } ?? dropDownTargetDisplay(displays: displays)
        if let current, let display {
            let retracted = DropDownAppGeometry.retractedFrame(
                for: current,
                in: display.usableBounds,
                direction: session.direction
            )
            if session.isAnimationEnabled {
                animateDropDownApp(
                    target,
                    frames: DropDownAppGeometry.animationFrames(from: current, to: retracted),
                    generation: generation,
                    completion: { [weak self] in
                        self?.finishDropDownAppHide(
                            target,
                            session: session,
                            generation: generation,
                            restorePreviousFocus: restorePreviousFocus,
                            reason: reason,
                            correlationID: correlationID
                        )
                    }
                )
            } else {
                finishDropDownAppHide(
                    target,
                    session: session,
                    generation: generation,
                    restorePreviousFocus: restorePreviousFocus,
                    reason: reason,
                    correlationID: correlationID
                )
            }
        } else {
            finishDropDownAppHide(
                target,
                session: session,
                generation: generation,
                restorePreviousFocus: restorePreviousFocus,
                reason: reason,
                correlationID: correlationID
            )
        }
    }

    private func finishDropDownAppHide(
        _ target: TrackedWindow,
        session: DropDownAppSession,
        generation: UInt64,
        restorePreviousFocus: Bool,
        reason: String,
        correlationID: String?
    ) {
        guard dropDownAnimationGeneration == generation,
              dropDownAppSession?.windowKey == target.key,
              dropDownAppSession?.isPresented == false,
              windows[target.key] != nil
        else { return }

        guard requestDropDownApplicationHidden(
            true,
            processIdentifier: target.processIdentifier,
            bundleIdentifier: session.bundleIdentifier
        ) else {
            completeDropDownAppHide(
                target,
                session: session,
                generation: generation,
                restorePreviousFocus: restorePreviousFocus,
                reason: reason,
                correlationID: correlationID,
                hideSucceeded: false,
                confirmationAttempts: 0,
                failureReason: "application-hide-request-rejected"
            )
            return
        }
        if isDropDownApplicationHidden(
            processIdentifier: target.processIdentifier,
            bundleIdentifier: session.bundleIdentifier
        ) != true {
            awaitDropDownAppHidden(
                target,
                session: session,
                generation: generation,
                restorePreviousFocus: restorePreviousFocus,
                reason: reason,
                correlationID: correlationID,
                attempt: 0
            )
            return
        }
        completeDropDownAppHide(
            target,
            session: session,
            generation: generation,
            restorePreviousFocus: restorePreviousFocus,
            reason: reason,
            correlationID: correlationID,
            hideSucceeded: true,
            confirmationAttempts: 0,
            failureReason: nil
        )
    }

    private func awaitDropDownAppHidden(
        _ target: TrackedWindow,
        session: DropDownAppSession,
        generation: UInt64,
        restorePreviousFocus: Bool,
        reason: String,
        correlationID: String?,
        attempt: Int
    ) {
        guard dropDownAnimationGeneration == generation,
              dropDownAppSession?.windowKey == target.key,
              dropDownAppSession?.isPresented == false,
              windows[target.key] != nil
        else { return }
        switch DropDownAppVisibilityConfirmationPolicy.disposition(
            expectedHidden: true,
            observedHidden: isDropDownApplicationHidden(
                processIdentifier: target.processIdentifier,
                bundleIdentifier: session.bundleIdentifier
            ),
            attempt: attempt
        ) {
        case .confirmed:
            completeDropDownAppHide(
                target,
                session: session,
                generation: generation,
                restorePreviousFocus: restorePreviousFocus,
                reason: reason,
                correlationID: correlationID,
                hideSucceeded: true,
                confirmationAttempts: attempt,
                failureReason: nil
            )
        case .timedOut:
            _ = requestDropDownApplicationHidden(
                false,
                processIdentifier: target.processIdentifier,
                bundleIdentifier: session.bundleIdentifier
            )
            completeDropDownAppHide(
                target,
                session: session,
                generation: generation,
                restorePreviousFocus: restorePreviousFocus,
                reason: reason,
                correlationID: correlationID,
                hideSucceeded: false,
                confirmationAttempts: attempt,
                failureReason: "application-hide-confirmation-timeout"
            )
        case .retry:
            queue.asyncAfter(deadline: .now() + .milliseconds(75)) { [weak self] in
                self?.awaitDropDownAppHidden(
                    target,
                    session: session,
                    generation: generation,
                    restorePreviousFocus: restorePreviousFocus,
                    reason: reason,
                    correlationID: correlationID,
                    attempt: attempt + 1
                )
            }
        }
    }

    private func completeDropDownAppHide(
        _ target: TrackedWindow,
        session: DropDownAppSession,
        generation: UInt64,
        restorePreviousFocus: Bool,
        reason: String,
        correlationID: String?,
        hideSucceeded: Bool,
        confirmationAttempts: Int,
        failureReason: String?
    ) {
        guard dropDownAnimationGeneration == generation,
              dropDownAppSession?.windowKey == target.key,
              dropDownAppSession?.isPresented == false,
              windows[target.key] != nil
        else { return }

        if hideSucceeded {
            var hiddenSession = session
            hiddenSession.isPresented = false
            hiddenSession.isApplicationHiddenByWindowRanger = true
            dropDownAppSession = hiddenSession
        } else {
            var restoredSession = session
            restoredSession.isPresented = true
            restoredSession.isApplicationHiddenByWindowRanger = false
            dropDownAppSession = restoredSession
            emitState()
            if let configuration = dropDownAppConfiguration,
               let display = session.displayIdentifier.flatMap({ identifier in
                   Self.activeDisplays().first { $0.identifier == identifier }
                }) ?? dropDownTargetDisplay(displays: Self.activeDisplays()) {
                _ = setDropDownAppFrame(
                    DropDownAppGeometry.presentedFrame(
                        in: dropDownAppPresentationBounds(for: display),
                        sizeFraction: configuration.heightFraction,
                        direction: session.direction
                    ),
                    target: target
                )
            }
        }
        if restorePreviousFocus,
           let previousFocusKey = session.previousFocusKey,
           let previous = windows[previousFocusKey] {
            focusManagedWindow(previousFocusKey, tracked: previous, correlationID: correlationID)
        } else {
            clearProgrammaticFocusIntent()
        }
        diagnostics.log(
            category: "drop-down-app",
            event: hideSucceeded ? "hidden" : "hide-failed",
            correlation: correlationID,
            fields: [
                "window": Self.diagnosticWindowKey(target.key),
                "reason": reason,
                "failure-reason": failureReason ?? "none",
                "hide-confirmation-attempts": String(confirmationAttempts),
                "restored-previous-focus": String(restorePreviousFocus),
                "hidden-state": hideSucceeded ? "application-hidden" : "visible",
                "application-hidden-observed": isDropDownApplicationHidden(
                    processIdentifier: target.processIdentifier,
                    bundleIdentifier: session.bundleIdentifier
                )
                    .map(String.init) ?? "unavailable",
                "observed-frame": AccessibilityWindow.frame(of: target.element)
                    .map(Self.diagnosticFrame) ?? "unavailable",
            ]
        )
        persistState(preservingPendingRestores: true)
        quickAppTransition = .idle
        if hideSucceeded {
            continuePendingQuickAppSelectionIfPossible()
        } else {
            // A failed hide leaves the current exact session presented. Never carry a stale
            // selection into a later, unrelated hide completion.
            pendingQuickAppSelection = nil
            reconcilePresentedQuickAppGroup(
                correlationID: correlationID,
                focusSelected: false
            )
        }
    }

    private func animateDropDownApp(
        _ target: TrackedWindow,
        frames: [WindowFrame],
        generation: UInt64,
        completion: (() -> Void)? = nil
    ) {
        guard !frames.isEmpty else {
            completion?()
            return
        }
        let interval = DropDownAppGeometry.animationDuration / Double(frames.count)
        for (index, frame) in frames.enumerated() {
            queue.asyncAfter(deadline: .now() + (interval * Double(index + 1))) { [weak self] in
                guard let self,
                      self.dropDownAnimationGeneration == generation,
                      self.windows[target.key] != nil
                else { return }
                _ = self.setDropDownAppFrame(frame, target: target)
                if index == frames.count - 1 { completion?() }
            }
        }
    }

    @discardableResult
    private func setDropDownAppFrame(_ frame: WindowFrame, target: TrackedWindow) -> Bool {
        guard !isWindowManagementPaused else { return false }
        var succeeded = false
        AccessibilityWindow.withoutPositionAnimations(for: target.processIdentifier) {
            let current = self.windows[target.key] ?? target
            if Self.geometryWriteMode(for: current.admissionDecision) == .positionOnly {
                succeeded = AccessibilityWindow.setPositionIfNeeded(frame.position, of: current.element)
            } else {
                let frameResult = AccessibilityWindow.setFrameResult(frame, of: current.element)
                succeeded = frameResult == .succeeded
                if frameResult == .initialSizeRejected,
                   let recovered = self.recoverRejectedResize(
                    FrameChange(window: current, frame: frame),
                    correlationID: nil,
                    source: "quick-app"
                   ) {
                    succeeded = recovered
                }
            }
        }
        return succeeded
    }

    private func dropDownRunningApplication(
        processIdentifier: pid_t,
        bundleIdentifier: String
    ) -> NSRunningApplication? {
        guard let application = NSRunningApplication(processIdentifier: processIdentifier),
              let observedBundleIdentifier = application.bundleIdentifier,
              observedBundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
        else { return nil }
        return application
    }

    private func isDropDownApplicationHidden(
        processIdentifier: pid_t,
        bundleIdentifier: String
    ) -> Bool? {
        dropDownRunningApplication(
            processIdentifier: processIdentifier,
            bundleIdentifier: bundleIdentifier
        )?.isHidden
    }

    @discardableResult
    private func requestDropDownApplicationHidden(
        _ hidden: Bool,
        processIdentifier: pid_t,
        bundleIdentifier: String,
        allowWhilePaused: Bool = false
    ) -> Bool {
        guard !isWindowManagementPaused || allowWhilePaused else { return false }
        guard let application = dropDownRunningApplication(
            processIdentifier: processIdentifier,
            bundleIdentifier: bundleIdentifier
        ) else { return false }
        if application.isHidden == hidden { return true }
        // Ghostty can return false from Hide/Unhide and publish the requested AppKit state moments
        // later. Finding the exact bundle/process makes the request dispatchable; the bounded
        // observed-state confirmation remains the only success postcondition.
        let appKitReturnValue = hidden ? application.hide() : application.unhide()
        return DropDownAppVisibilityRequestPolicy.wasDispatched(
            applicationMatched: true,
            appKitReturnValue: appKitReturnValue
        )
    }

    /// Releases Quick App ownership for a newly ignored surface. This deliberately restores only
    /// application visibility; it never calls the Quick App frame boundary for the companion
    /// window that central admission has just rejected.
    private func discardIgnoredQuickAppSessions(
        for key: WindowKey,
        correlationID: String?
    ) {
        let matchingBundleKeys = quickAppSessions.compactMap { bundleKey, session in
            session.windowKeys.contains(key) ? bundleKey : nil
        }
        guard !matchingBundleKeys.isEmpty else { return }

        dropDownAnimationGeneration &+= 1
        for bundleKey in matchingBundleKeys {
            guard var session = quickAppSessions[bundleKey] else { continue }
            if session.removeWindow(key) {
                quickAppSessions[bundleKey] = session
                diagnostics.log(
                    category: "drop-down-app",
                    event: "ignored-window-removed-from-application-group",
                    correlation: correlationID,
                    fields: [
                        "window": Self.diagnosticWindowKey(key),
                        "bundle": bundleKey,
                        "remaining-window-count": String(session.windowKeys.count),
                        "application-unhide": "not-requested",
                        "frame-write": "false",
                    ]
                )
                if session.isPresented {
                    reconcilePresentedQuickAppGroup(
                        correlationID: correlationID,
                        focusSelected: false
                    )
                }
                continue
            }
            let phaseBeforeDiscard = quickAppTransition
            let transitionAfterDiscard = IgnoredQuickAppDiscardPolicy.transitionAfterDiscard(
                phaseBeforeDiscard,
                bundleKey: bundleKey
            )
            let interruptedTransition = transitionAfterDiscard != phaseBeforeDiscard
            quickAppTransition = transitionAfterDiscard

            if pendingDropDownAppLaunch.map({
                Self.normalizedBundleIdentifier($0.bundleIdentifier) == bundleKey
            }) == true {
                cancelPendingDropDownAppLaunch()
            }
            if IgnoredQuickAppDiscardPolicy.shouldClearPendingSelection(
                pendingBundleIdentifier: pendingQuickAppSelection.map {
                    Self.normalizedBundleIdentifier($0.bundleIdentifier)
                },
                discardedBundleKey: bundleKey,
                interruptedTransition: interruptedTransition
            ) {
                pendingQuickAppSelection = nil
            }
            pendingQuickAppHideAfterPresentation = false
            if quickAppApplicationSwitchHandoff.map({
                $0.incomingBundleKey == bundleKey || $0.outgoingBundleKey == bundleKey
            }) == true {
                quickAppApplicationSwitchHandoff = nil
            }

            _ = nextQuickAppNeighborVisibilityGeneration(bundleKey: bundleKey)
            quickAppSessions.removeValue(forKey: bundleKey)
            quickAppNeighborVisibilityGeneration.removeValue(forKey: bundleKey)

            let observedHidden = isDropDownApplicationHidden(
                processIdentifier: key.processIdentifier,
                bundleIdentifier: session.bundleIdentifier
            )
            let shouldUnhide = IgnoredQuickAppDiscardPolicy.shouldRequestApplicationUnhide(
                wasHiddenByWindowRanger: session.isApplicationHiddenByWindowRanger,
                observedHidden: observedHidden
            )
            ignoredQuickAppVisibilityRecoveryGeneration &+= 1
            let recoveryGeneration = ignoredQuickAppVisibilityRecoveryGeneration
            if shouldUnhide {
                ignoredQuickAppVisibilityRecoveries[bundleKey] = IgnoredQuickAppVisibilityRecovery(
                    generation: recoveryGeneration,
                    processIdentifier: key.processIdentifier,
                    bundleIdentifier: session.bundleIdentifier,
                    confirmationInFlight: true
                )
            } else {
                ignoredQuickAppVisibilityRecoveries.removeValue(forKey: bundleKey)
            }
            let unhideRequested = shouldUnhide
                ? requestDropDownApplicationHidden(
                    false,
                    processIdentifier: key.processIdentifier,
                    bundleIdentifier: session.bundleIdentifier,
                    allowWhilePaused: true
                )
                : nil
            diagnostics.log(
                category: "drop-down-app",
                event: "ignored-session-discarded",
                correlation: correlationID,
                fields: [
                    "window": Self.diagnosticWindowKey(key),
                    "bundle": bundleKey,
                    "transition-reset": String(interruptedTransition),
                    "application-unhide": unhideRequested.map(String.init) ?? "not-requested",
                    "frame-write": "false",
                ]
            )
            if shouldUnhide {
                confirmIgnoredQuickAppApplicationVisible(
                    bundleKey: bundleKey,
                    generation: recoveryGeneration,
                    processIdentifier: key.processIdentifier,
                    bundleIdentifier: session.bundleIdentifier,
                    correlationID: correlationID,
                    attempt: 0
                )
            }
        }
    }

    private func reconcileIgnoredQuickAppVisibilityRecoveries(correlationID: String?) {
        for bundleKey in Array(ignoredQuickAppVisibilityRecoveries.keys) {
            guard var recovery = ignoredQuickAppVisibilityRecoveries[bundleKey] else { continue }
            if quickAppSessions[bundleKey] != nil {
                ignoredQuickAppVisibilityRecoveries.removeValue(forKey: bundleKey)
                diagnostics.log(
                    category: "drop-down-app",
                    event: "ignored-session-visibility-recovery-superseded",
                    correlation: correlationID,
                    fields: ["bundle": bundleKey, "frame-write": "false"]
                )
                continue
            }
            guard dropDownRunningApplication(
                processIdentifier: recovery.processIdentifier,
                bundleIdentifier: recovery.bundleIdentifier
            ) != nil else {
                ignoredQuickAppVisibilityRecoveries.removeValue(forKey: bundleKey)
                continue
            }
            guard !recovery.confirmationInFlight else { continue }
            recovery.confirmationInFlight = true
            ignoredQuickAppVisibilityRecoveries[bundleKey] = recovery
            confirmIgnoredQuickAppApplicationVisible(
                bundleKey: bundleKey,
                generation: recovery.generation,
                processIdentifier: recovery.processIdentifier,
                bundleIdentifier: recovery.bundleIdentifier,
                correlationID: correlationID,
                attempt: 0
            )
        }
    }

    static func restoredIgnoredQuickAppVisibilityRecoveries(
        _ persisted: [String: IgnoredQuickAppVisibilityRecovery]?
    ) -> [String: IgnoredQuickAppVisibilityRecovery] {
        (persisted ?? [:]).reduce(into: [:]) { result, pair in
            let bundleKey = normalizedBundleIdentifier(pair.value.bundleIdentifier)
            guard pair.key == bundleKey,
                  pair.value.processIdentifier > 0,
                  AccessibilityWindow.shouldReadAccessibilityIdentifierForCompatibility(
                    pair.value.bundleIdentifier
                  )
            else { return }
            result[bundleKey] = IgnoredQuickAppVisibilityRecovery(
                generation: pair.value.generation,
                processIdentifier: pair.value.processIdentifier,
                bundleIdentifier: pair.value.bundleIdentifier,
                confirmationInFlight: false
            )
        }
    }

    private func attemptIgnoredQuickAppVisibilityRecoveryForShutdown() {
        for bundleKey in Array(ignoredQuickAppVisibilityRecoveries.keys) {
            guard var recovery = ignoredQuickAppVisibilityRecoveries[bundleKey] else { continue }
            if quickAppSessions[bundleKey] != nil {
                ignoredQuickAppVisibilityRecoveries.removeValue(forKey: bundleKey)
                continue
            }
            guard dropDownRunningApplication(
                processIdentifier: recovery.processIdentifier,
                bundleIdentifier: recovery.bundleIdentifier
            ) != nil else {
                ignoredQuickAppVisibilityRecoveries.removeValue(forKey: bundleKey)
                continue
            }
            _ = requestDropDownApplicationHidden(
                false,
                processIdentifier: recovery.processIdentifier,
                bundleIdentifier: recovery.bundleIdentifier,
                allowWhilePaused: true
            )
            if isDropDownApplicationHidden(
                processIdentifier: recovery.processIdentifier,
                bundleIdentifier: recovery.bundleIdentifier
            ) == false {
                ignoredQuickAppVisibilityRecoveries.removeValue(forKey: bundleKey)
            } else {
                recovery.confirmationInFlight = false
                ignoredQuickAppVisibilityRecoveries[bundleKey] = recovery
            }
        }
    }

    private func confirmIgnoredQuickAppApplicationVisible(
        bundleKey: String,
        generation: UInt64,
        processIdentifier: pid_t,
        bundleIdentifier: String,
        correlationID: String?,
        attempt: Int
    ) {
        guard var recovery = ignoredQuickAppVisibilityRecoveries[bundleKey],
              recovery.generation == generation,
              recovery.processIdentifier == processIdentifier,
              recovery.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
        else { return }
        guard quickAppSessions[bundleKey] == nil else {
            ignoredQuickAppVisibilityRecoveries.removeValue(forKey: bundleKey)
            diagnostics.log(
                category: "drop-down-app",
                event: "ignored-session-visibility-recovery-superseded",
                correlation: correlationID,
                fields: ["bundle": bundleKey, "frame-write": "false"]
            )
            return
        }
        guard dropDownRunningApplication(
            processIdentifier: processIdentifier,
            bundleIdentifier: bundleIdentifier
        ) != nil else {
            ignoredQuickAppVisibilityRecoveries.removeValue(forKey: bundleKey)
            return
        }
        let disposition = DropDownAppVisibilityConfirmationPolicy.disposition(
            expectedHidden: false,
            observedHidden: isDropDownApplicationHidden(
                processIdentifier: processIdentifier,
                bundleIdentifier: bundleIdentifier
            ),
            attempt: attempt
        )
        switch disposition {
        case .confirmed:
            _ = recovery.shouldRetain(after: disposition)
            ignoredQuickAppVisibilityRecoveries.removeValue(forKey: bundleKey)
            diagnostics.log(
                category: "drop-down-app",
                event: "ignored-session-application-visible",
                correlation: correlationID,
                fields: ["bundle": bundleIdentifier, "frame-write": "false"]
            )
        case .timedOut:
            if recovery.shouldRetain(after: disposition) {
                ignoredQuickAppVisibilityRecoveries[bundleKey] = recovery
            }
            diagnostics.log(
                category: "drop-down-app",
                event: "ignored-session-application-unhide-timeout",
                correlation: correlationID,
                fields: [
                    "bundle": bundleIdentifier,
                    "recovery-retained": "true",
                    "frame-write": "false",
                ]
            )
        case .retry:
            _ = requestDropDownApplicationHidden(
                false,
                processIdentifier: processIdentifier,
                bundleIdentifier: bundleIdentifier,
                allowWhilePaused: true
            )
            queue.asyncAfter(deadline: .now() + .milliseconds(75)) { [weak self] in
                self?.confirmIgnoredQuickAppApplicationVisible(
                    bundleKey: bundleKey,
                    generation: generation,
                    processIdentifier: processIdentifier,
                    bundleIdentifier: bundleIdentifier,
                    correlationID: correlationID,
                    attempt: attempt + 1
                )
            }
        }
    }

    private func restoreAndClearQuickAppSession(
        bundleKey: String,
        reason: String,
        allowWhilePaused: Bool = false
    ) {
        guard !isWindowManagementPaused || allowWhilePaused else { return }
        _ = nextQuickAppNeighborVisibilityGeneration(bundleKey: bundleKey)
        if pendingQuickAppSelection.map({
            Self.normalizedBundleIdentifier($0.bundleIdentifier) == bundleKey
        }) == true {
            pendingQuickAppSelection = nil
        }
        pendingQuickAppHideAfterPresentation = false
        if quickAppApplicationSwitchHandoff.map({
            $0.incomingBundleKey == bundleKey || $0.outgoingBundleKey == bundleKey
        }) == true {
            quickAppApplicationSwitchHandoff = nil
        }
        switch quickAppTransition {
        case let .launching(activeKey) where activeKey == bundleKey,
             let .showing(activeKey) where activeKey == bundleKey,
             let .hiding(activeKey) where activeKey == bundleKey:
            quickAppTransition = .idle
        default:
            break
        }
        guard let session = quickAppSessions[bundleKey] else { return }
        dropDownAnimationGeneration &+= 1
        var frameWriteSucceeded: Bool?
        var unhideSucceeded: Bool?
        let targets = session.windowKeys.compactMap { windows[$0] }
        for target in targets {
            let succeeded = setDropDownAppFrame(target.restoreFrame, target: target)
            frameWriteSucceeded = (frameWriteSucceeded ?? true) && succeeded
        }
        if session.isApplicationHiddenByWindowRanger {
            unhideSucceeded = requestDropDownApplicationHidden(
                false,
                processIdentifier: session.windowKey.processIdentifier,
                bundleIdentifier: session.bundleIdentifier,
                allowWhilePaused: allowWhilePaused
            )
            if unhideSucceeded == true {
                for target in targets {
                    let succeeded = setDropDownAppFrame(target.restoreFrame, target: target)
                    frameWriteSucceeded = (frameWriteSucceeded ?? true) && succeeded
                }
            }
        }
        let unhideConfirmed = !session.isApplicationHiddenByWindowRanger ||
            isDropDownApplicationHidden(
                processIdentifier: session.windowKey.processIdentifier,
                bundleIdentifier: session.bundleIdentifier
            ) == false
        guard unhideConfirmed else {
            diagnostics.log(
                category: "drop-down-app",
                event: "session-retained",
                fields: [
                    "reason": reason,
                    "bundle": bundleKey,
                    "application-unhide": unhideSucceeded.map(String.init) ?? "not-requested",
                ]
            )
            return
        }
        quickAppSessions.removeValue(forKey: bundleKey)
        quickAppNeighborVisibilityGeneration.removeValue(forKey: bundleKey)
        diagnostics.log(
            category: "drop-down-app",
            event: "session-cleared",
            fields: [
                "reason": reason,
                "bundle": bundleKey,
                "window-count": String(targets.count),
                "frame-write": frameWriteSucceeded.map(String.init) ?? "not-requested",
                "application-unhide": unhideSucceeded.map(String.init) ?? "not-requested",
            ]
        )
    }

    private func restoreAndClearDropDownAppSession(
        reason: String,
        allowWhilePaused: Bool = false
    ) {
        guard !isWindowManagementPaused || allowWhilePaused else { return }
        guard !quickAppSessions.isEmpty else {
            pendingRestoredDropDownAppSessions.removeAll()
            pendingQuickAppSelection = nil
            pendingQuickAppHideAfterPresentation = false
            quickAppApplicationSwitchHandoff = nil
            quickAppTransition = .idle
            return
        }
        for bundleKey in Array(quickAppSessions.keys) {
            restoreAndClearQuickAppSession(
                bundleKey: bundleKey,
                reason: reason,
                allowWhilePaused: allowWhilePaused
            )
        }
        pendingRestoredDropDownAppSessions.removeAll()
        pendingQuickAppSelection = nil
        pendingQuickAppHideAfterPresentation = false
        quickAppApplicationSwitchHandoff = nil
        quickAppTransition = .idle
    }

    private func prepareDropDownAppSessionForStartup(
        observedFrames: [WindowKey: WindowFrame],
        displays: [DisplaySnapshot],
        performAXWrites: Bool,
        correlationID: String?
    ) {
        let persistedSessions = pendingRestoredDropDownAppSessions
        defer { pendingRestoredDropDownAppSessions.removeAll() }

        // Every configured entry whose eligible windows belong to one process begins hidden and
        // outside ordinary layout. Persisted ownership can recover an already hidden application;
        // externally hidden applications and cross-process window sets remain untouched.
        for configuration in quickAppConfigurations {
            let bundleKey = Self.normalizedBundleIdentifier(configuration.bundleIdentifier)
            let persistedHiddenSession = persistedSessions[bundleKey]
            guard quickAppSessions[bundleKey] == nil else {
                continue
            }
            let candidates: [DropDownAppStartupCandidate] = windows.compactMap {
                key, tracked -> DropDownAppStartupCandidate? in
                let applicationHidden = isDropDownApplicationHidden(
                    processIdentifier: tracked.processIdentifier,
                    bundleIdentifier: configuration.bundleIdentifier
                ) == true
                let wasHiddenByWindowRanger = DropDownAppHiddenSessionRecoveryPolicy.matches(
                    persistedHiddenSession,
                    windowKey: key,
                    bundleIdentifier: tracked.bundleIdentifier,
                    isStartup: true,
                    isApplicationHidden: applicationHidden
                )
                guard !applicationHidden || wasHiddenByWindowRanger else { return nil }
                guard (!temporarilyDeferredWindowKeys.contains(key) || wasHiddenByWindowRanger),
                      fullscreenSessions[key] == nil
                else { return nil }
                let observedFrame = observedFrames[key]
                return DropDownAppStartupCandidate(
                    key: key,
                    bundleIdentifier: tracked.bundleIdentifier,
                    isMeaningfullyVisible: observedFrame.map {
                        Self.isMeaningfullyVisible($0, displays: displays)
                    } == true,
                    wasHiddenByWindowRanger: wasHiddenByWindowRanger
                )
            }
            let matchingCandidateCount = DropDownAppStartupPolicy.matchingCandidateCount(
                bundleIdentifier: configuration.bundleIdentifier,
                candidates: candidates
            )
            guard var selections = DropDownAppStartupPolicy.selections(
                bundleIdentifier: configuration.bundleIdentifier,
                candidates: candidates
            ) else {
                if matchingCandidateCount > 0 {
                    diagnostics.log(
                        category: "drop-down-app",
                        event: "startup-session-multiple-processes",
                        correlation: correlationID,
                        fields: [
                            "bundle": configuration.bundleIdentifier,
                            "window-count": String(matchingCandidateCount),
                        ]
                    )
                }
                continue
            }
            if let persistedPrimary = persistedHiddenSession?.windowKey,
               let persistedIndex = selections.firstIndex(where: {
                   $0.windowKey == persistedPrimary
               }) {
                selections.swapAt(0, persistedIndex)
            }
            guard let selection = selections.first,
                  let target = windows[selection.windowKey]
            else { continue }

            dropDownAnimationGeneration &+= 1
            var session = DropDownAppSession(
                windowKey: target.key,
                additionalWindowKeys: Array(selections.dropFirst()).map(\.windowKey),
                bundleIdentifier: configuration.bundleIdentifier,
                direction: configuration.direction,
                isAnimationEnabled: configuration.isAnimationEnabled,
                isPresented: false,
                isApplicationHiddenByWindowRanger: selections.allSatisfy(\.wasHiddenByWindowRanger),
                displayIdentifier: persistedHiddenSession?.displayIdentifier,
                previousFocusKey: nil
            )

            var hideRequestDispatched: Bool?
            if performAXWrites, !session.isApplicationHiddenByWindowRanger {
                hideRequestDispatched = requestDropDownApplicationHidden(
                    true,
                    processIdentifier: target.processIdentifier,
                    bundleIdentifier: configuration.bundleIdentifier
                )
                session.isApplicationHiddenByWindowRanger = hideRequestDispatched == true
            }
            quickAppSessions[bundleKey] = session

            diagnostics.log(
                category: "drop-down-app",
                event: "startup-session-prepared",
                correlation: correlationID,
                fields: [
                    "window": Self.diagnosticWindowKey(target.key),
                    "window-count": String(session.windowKeys.count),
                    "bundle": configuration.bundleIdentifier,
                    "presented": "false",
                    "pre-launch-visible": String(selection.wasMeaningfullyVisible),
                    "display": session.displayIdentifier ?? "none",
                    "hide-request": hideRequestDispatched.map(String.init) ?? "not-requested",
                    "hidden-state": session.isApplicationHiddenByWindowRanger
                        ? "application-hidden" : "unverified",
                    "application-hidden-observed": isDropDownApplicationHidden(
                        processIdentifier: target.processIdentifier,
                        bundleIdentifier: configuration.bundleIdentifier
                    )
                        .map(String.init) ?? "unavailable",
                ]
            )
        }
    }

    @discardableResult
    private func rebindDropDownAppSessionIfNeeded(
        bundleIdentifier: String,
        sessionWindowKey: WindowKey? = nil,
        removedWindowKeys: Set<WindowKey>,
        newlyTrackedWindowKeys: Set<WindowKey>,
        displays: [DisplaySnapshot],
        performAXWrites: Bool,
        correlationID: String?
    ) -> Bool {
        guard var session = quickAppSessions[bundleIdentifier],
              let configuration = quickAppConfigurations.first(where: {
                  Self.normalizedBundleIdentifier($0.bundleIdentifier) == bundleIdentifier
              })
        else { return false }
        let previousKey = sessionWindowKey ?? session.windowKey
        guard session.windowKeys.contains(previousKey),
              let previous = windows[previousKey],
              let replacementKey = DropDownAppWindowHandoffPolicy.replacementWindowKey(
                sessionWindowKey: previousKey,
                sessionBundleIdentifier: session.bundleIdentifier,
                removedWindowKeys: removedWindowKeys,
                newlyTrackedWindowKeys: newlyTrackedWindowKeys,
                availableWindows: windows.compactMap { key, tracked in
                    guard !removedWindowKeys.contains(key),
                          !temporarilyDeferredWindowKeys.contains(key),
                          fullscreenSessions[key] == nil
                    else { return nil }
                    return DropDownAppWindowHandoffCandidate(
                        key: key,
                        bundleIdentifier: tracked.bundleIdentifier
                    )
                }
              ),
              var replacement = windows[replacementKey]
        else { return false }

        // The replacement AX element is new, but its durable local ownership belongs to the same
        // visible native window. Do not let the currently presented Quick App geometry become its
        // restore frame or assign the tab to whichever workspace happened to be active.
        replacement.workspaceID = previous.workspaceID
        replacement.restoreFrame = previous.restoreFrame
        replacement.displayPlacement = previous.displayPlacement
        replacement.layoutOverride = previous.layoutOverride
        replacement.workspaceRuleOverrideActive = previous.workspaceRuleOverrideActive
        replacement.layoutOrder = previous.layoutOrder
        replacement.layoutWeight = previous.layoutWeight
        windows[replacementKey] = replacement

        if session.windowKey == previousKey {
            session.windowKey = replacementKey
        } else {
            session.additionalWindowKeys = session.additionalWindowKeys.map {
                $0 == previousKey ? replacementKey : $0
            }
        }
        let interruptedTransition: Bool
        switch quickAppTransition {
        case let .showing(activeKey) where activeKey == bundleIdentifier:
            interruptedTransition = true
            if pendingQuickAppSelection == nil {
                pendingQuickAppSelection = PendingQuickAppSelection(
                    bundleIdentifier: configuration.bundleIdentifier,
                    correlationID: correlationID ?? diagnostics.makeCorrelationID()
                )
            }
        case let .hiding(activeKey) where activeKey == bundleIdentifier:
            interruptedTransition = true
        default:
            interruptedTransition = false
        }
        if QuickAppTransitionPolicy.shouldInvalidateAnimationForRebind(
            reboundBundleKey: bundleIdentifier,
            phase: quickAppTransition,
            sessionIsPresented: session.isPresented
        ) {
            dropDownAnimationGeneration &+= 1
        }
        quickAppSessions[bundleIdentifier] = session

        lastFocusedWindow = lastFocusedWindow.mapValues { $0 == previousKey ? replacementKey : $0 }
        if lastObservedFocusedWindow == previousKey { lastObservedFocusedWindow = replacementKey }
        if programmaticFocusTarget == previousKey { programmaticFocusTarget = replacementKey }
        if recentInteractionFocusTarget == previousKey { recentInteractionFocusTarget = replacementKey }

        var geometryWriteSucceeded: Bool?
        if performAXWrites {
            if session.isPresented,
               let display = session.displayIdentifier.flatMap({ identifier in
                   displays.first { $0.identifier == identifier }
               }) ?? dropDownTargetDisplay(displays: displays) {
                let presented = DropDownAppGeometry.presentedFrame(
                    in: dropDownAppPresentationBounds(for: display),
                    sizeFraction: configuration.heightFraction,
                    direction: session.direction
                )
                geometryWriteSucceeded = setDropDownAppFrame(
                    presented,
                    target: replacement
                )
            } else if !session.isPresented {
                geometryWriteSucceeded = requestDropDownApplicationHidden(
                    true,
                    processIdentifier: replacement.processIdentifier,
                    bundleIdentifier: session.bundleIdentifier
                )
                session.isApplicationHiddenByWindowRanger = geometryWriteSucceeded == true
                quickAppSessions[bundleIdentifier] = session
            }
        }

        diagnostics.log(
            category: "drop-down-app",
            event: "native-tab-session-rebound",
            correlation: correlationID,
            fields: [
                "previous-window": Self.diagnosticWindowKey(previousKey),
                "replacement-window": Self.diagnosticWindowKey(replacementKey),
                "bundle": session.bundleIdentifier,
                "presented": String(session.isPresented),
                "geometry-write": geometryWriteSucceeded.map(String.init) ?? "not-requested",
                "hidden-state": session.isPresented
                    ? "visible"
                    : session.isApplicationHiddenByWindowRanger ? "application-hidden" : "unverified",
            ]
        )
        if session.isPresented,
           let display = session.displayIdentifier.flatMap({ identifier in
               displays.first { $0.identifier == identifier }
           }) ?? dropDownTargetDisplay(displays: displays) {
            layoutPresentedQuickAppGroup(
                display: display,
                correlationID: correlationID,
                focusSelected: false
            )
        }
        if interruptedTransition {
            quickAppTransition = .idle
            continuePendingQuickAppSelectionIfPossible()
        }
        return true
    }

    private func dropDownTargetDisplay(displays: [DisplaySnapshot]) -> DisplaySnapshot? {
        let pointer = CGEvent(source: nil)?.location
        if let pointer, let pointerDisplay = displays.first(where: { $0.bounds.contains(pointer) }) {
            return pointerDisplay
        }
        let interactionDisplayIdentifier = interactionDisplayResolution(
            focused: interactionFocusedWindowSnapshot(),
            displays: displays
        ).identifier
        return displays.first(where: { $0.identifier == interactionDisplayIdentifier })
            ?? displays.first(where: \.isMain)
            ?? displays.first
    }

    private func dropDownAppPresentationBounds(for display: DisplaySnapshot) -> CGRect {
        DropDownAppGeometry.presentationBounds(
            in: display.usableBounds,
            focusedWindowHighlightEnabled: focusedWindowHighlightEnabled
        )
    }

    private func reapplyPresentedDropDownAppFrameForFocusBorder(
        displays: [DisplaySnapshot]
    ) {
        guard var session = dropDownAppSession,
              session.isPresented,
              let target = windows[session.windowKey],
              let display = session.displayIdentifier.flatMap({ identifier in
                  displays.first { $0.identifier == identifier }
              }) ?? dropDownTargetDisplay(displays: displays)
        else { return }

        dropDownAnimationGeneration &+= 1
        session.displayIdentifier = display.identifier
        dropDownAppSession = session
        reconcilePresentedQuickAppGroup(correlationID: nil, focusSelected: false)
        let requestedFrame = AccessibilityWindow.frame(of: target.element)
        diagnostics.log(
            category: "drop-down-app",
            event: "focus-border-geometry-updated",
            fields: [
                "window": Self.diagnosticWindowKey(target.key),
                "focus-border-enabled": String(focusedWindowHighlightEnabled),
                "requested-frame": requestedFrame.map(Self.diagnosticFrame) ?? "unavailable",
                "geometry-write": "group-reconciled",
            ]
        )
    }

    private func isDropDownAppWindow(_ key: WindowKey) -> Bool {
        quickAppSessions.values.contains { $0.windowKeys.contains(key) }
    }

    /// Hiding an application is distinct from closing it or failing to enumerate its AX windows:
    /// retain the tracked window and its workspace assignment, but never let an externally hidden
    /// regular application consume layout space, receive focus, or receive geometry writes. Quick
    /// App windows retain their exact hidden-session ownership and are governed by the shelf path.
    private func isExcludedFromWorkspaceParticipation(_ tracked: TrackedWindow) -> Bool {
        Self.isExcludedFromWorkspaceParticipation(
            isApplicationHidden: NSRunningApplication(
                processIdentifier: tracked.processIdentifier
            )?.isHidden == true,
            isDropDownAppWindow: isDropDownAppWindow(tracked.key)
        )
    }

    static func isExcludedFromWorkspaceParticipation(
        isApplicationHidden: Bool,
        isDropDownAppWindow: Bool
    ) -> Bool {
        isApplicationHidden && !isDropDownAppWindow
    }

    static func backgroundApplicationVisibilityMarker(
        isApplicationHidden: Bool,
        isDropDownAppWindow: Bool
    ) -> String? {
        guard !isDropDownAppWindow else { return nil }
        return isApplicationHidden ? "hidden" : "visible"
    }

    static func shouldIncludeInWakeFocusRecovery(
        isWriteEligible: Bool,
        isExcludedFromWorkspaceParticipation: Bool
    ) -> Bool {
        isWriteEligible && !isExcludedFromWorkspaceParticipation
    }

    @discardableResult
    private func applyVisibility(
        displays: [DisplaySnapshot]? = nil,
        correlationID: String? = nil,
        eligibleWindowKeys: Set<WindowKey>? = nil
    ) -> [WindowKey: WindowFrame] {
        guard !isWindowManagementPaused else { return [:] }
        let displays = displays ?? Self.activeDisplays()
        let parkingPosition = parkingPosition(displays: displays)
        let activeWorkspaceIDs = activeWorkspaceIDs
        let isEligible: (TrackedWindow) -> Bool = { tracked in
            StableLayoutSlotPolicy.isAvailableForVisibilityLayout(
                isWriteDeferred: self.temporarilyDeferredWindowKeys.contains(tracked.key),
                retainsLayoutSlot: self.retainedLayoutSlotWindowKeys.contains(tracked.key),
                isExcludedFromWorkspaceParticipation: self.isExcludedFromWorkspaceParticipation(tracked),
                isExplicitlyWriteEligible: eligibleWindowKeys == nil ||
                    eligibleWindowKeys!.contains(tracked.key)
            )
        }

        // Restore first, then hide. This ordering is intentional: it minimizes the interval in
        // which neither workspace is visible and matches the low-flicker ordering used by AeroSpork.
        var visibleWindows: [TrackedWindow] = []
        var hiddenWindows: [TrackedWindow] = []
        for tracked in windows.values {
            guard isEligible(tracked), !isDropDownAppWindow(tracked.key) else { continue }
            let isVisible = Self.shouldWindowBeVisible(
                workspaceID: tracked.workspaceID,
                activeWorkspaceIDs: activeWorkspaceIDs,
                rule: resolvedRule(for: tracked.bundleIdentifier)
            )
            if isVisible {
                visibleWindows.append(tracked)
            } else {
                hiddenWindows.append(tracked)
            }
        }

        let expectedLayoutFrames = applyVisibleWindows(
            visibleWindows,
            displays: displays,
            correlationID: correlationID
        )
        applyPositionChanges(
            hiddenWindows.map { PositionChange(window: $0, position: parkingPosition) },
            correlationID: correlationID
        )
        let hiddenQuickAppChanges = quickAppSessions.values.flatMap { session -> [PositionChange] in
            guard !session.isPresented else { return [] }
            return session.windowKeys.compactMap { key in
                guard let target = windows[key], isEligible(target) else { return nil }
                return PositionChange(window: target, position: parkingPosition)
            }
        }
        if !hiddenQuickAppChanges.isEmpty {
            applyPositionChanges(hiddenQuickAppChanges, correlationID: correlationID)
        }
        return expectedLayoutFrames
    }

    private func applyVisibilityTransition(
        from sourceWorkspaceID: UUID,
        to targetWorkspaceID: UUID,
        correlationID: String? = nil
    ) {
        let displays = Self.activeDisplays()
        let parkingPosition = parkingPosition(displays: displays)

        // Only the two workspaces participating in the switch can need a visibility change.
        // Destination first reduces the blank/flicker interval; unrelated parked workspaces get
        // no AX traffic at all.
        applyVisibleWindows(
            windows.values.filter {
                $0.workspaceID == targetWorkspaceID &&
                    !isDropDownAppWindow($0.key) &&
                    !isExcludedFromWorkspaceParticipation($0)
            },
            displays: displays,
            correlationID: correlationID
        )
        applyPositionChanges(windows.values
            .filter {
                $0.workspaceID == sourceWorkspaceID &&
                    !isDropDownAppWindow($0.key) &&
                    !isExcludedFromWorkspaceParticipation($0) &&
                    !resolvedRule(for: $0.bundleIdentifier).keepsOnAllWorkspaces
            }
            .map { PositionChange(window: $0, position: parkingPosition) },
            correlationID: correlationID
        )
    }

    @discardableResult
    private func applyVisibleWindows<S: Sequence>(
        _ trackedWindows: S,
        displays: [DisplaySnapshot],
        correlationID: String? = nil
    ) -> [WindowKey: WindowFrame] where S.Element == TrackedWindow {
        var positionChanges: [PositionChange] = []
        var frameChanges: [FrameChange] = []
        var expectedLayoutFrames: [WindowKey: WindowFrame] = [:]
        let layoutAvailableWindows = trackedWindows.filter {
            !isDropDownAppWindow($0.key) &&
            !isExcludedFromWorkspaceParticipation($0) &&
            StableLayoutSlotPolicy.isAvailableForLayout(
                isWriteDeferred: temporarilyDeferredWindowKeys.contains($0.key),
                retainsLayoutSlot: retainedLayoutSlotWindowKeys.contains($0.key),
                isExplicitlyEligible: fullscreenSessions[$0.key] == nil
            )
        }
        let windowsByWorkspace = Dictionary(grouping: Array(layoutAvailableWindows), by: \.workspaceID)

        for (workspaceID, workspaceWindows) in windowsByWorkspace {
            let layout = isWorkspaceActive(workspaceID) ? workspaceLayout(for: workspaceID) : .none
            let layoutWindows = workspaceWindows.filter {
                Self.shouldIncludeInLayout(
                    layoutOverride: $0.layoutOverride,
                    admissionDecision: $0.admissionDecision,
                    rule: resolvedRule(for: $0.bundleIdentifier)
                )
            }
            let stationaryWindows = layout == .none
                ? workspaceWindows
                : workspaceWindows.filter {
                    !Self.shouldIncludeInLayout(
                        layoutOverride: $0.layoutOverride,
                        admissionDecision: $0.admissionDecision,
                        rule: resolvedRule(for: $0.bundleIdentifier)
                    )
                }
            if layout == .tiled {
                for tracked in stationaryWindows {
                    lastSolvedTiledFrames.removeValue(forKey: tracked.key)
                }
            } else {
                for tracked in workspaceWindows {
                    lastSolvedTiledFrames.removeValue(forKey: tracked.key)
                }
            }

            for tracked in stationaryWindows {
                let rule = resolvedRule(for: tracked.bundleIdentifier)
                let forcedDisplay = displayMode == .independent && !rule.keepsOnAllWorkspaces
                    ? workspaceHomeDisplayIdentifier(for: tracked.workspaceID, displays: displays)
                    : nil
                let resolved = Self.resolveDisplayFrame(
                    savedFrame: tracked.restoreFrame,
                    placement: tracked.displayPlacement,
                    displays: displays,
                    forcedDisplayIdentifier: forcedDisplay
                ).frame
                if Self.geometryWriteMode(for: tracked.admissionDecision) == .positionOnly ||
                    Self.sizesMatch(resolved.size, tracked.restoreFrame.size) {
                    positionChanges.append(PositionChange(window: tracked, position: resolved.position))
                } else {
                    frameChanges.append(FrameChange(window: tracked, frame: resolved))
                }
            }
            if layout == .none {
                continue
            }

            let groupedByDisplay = Dictionary(grouping: layoutWindows) {
                targetDisplay(
                    for: $0,
                    workspaceID: workspaceID,
                    displays: displays,
                    correlationID: correlationID
                )?.identifier
                    ?? displays.first?.identifier
                    ?? "main-display"
            }
            for (displayIdentifier, displayWindows) in groupedByDisplay {
                guard let display = displays.first(where: { $0.identifier == displayIdentifier })
                    ?? displays.first(where: \.isMain)
                    ?? displays.first
                else { continue }
                let primaryKey = lastFocusedWindow[workspaceID].flatMap { lastFocused in
                    displayWindows.contains(where: { $0.key == lastFocused }) ? lastFocused : nil
                } ?? focusedWindowKey().flatMap { focused in
                    displayWindows.contains(where: { $0.key == focused }) ? focused : nil
                }
                let ordered = displayWindows.sorted { lhs, rhs in
                    if lhs.layoutOrder != rhs.layoutOrder {
                        return lhs.layoutOrder < rhs.layoutOrder
                    }
                    if lhs.key.processIdentifier != rhs.key.processIdentifier {
                        return lhs.key.processIdentifier < rhs.key.processIdentifier
                    }
                    return lhs.key.windowIdentifier < rhs.key.windowIdentifier
                }
                let accordionFocusedIndex = primaryKey.flatMap { key in
                    ordered.firstIndex(where: { $0.key == key })
                }
                let layoutConfiguration = self.workspaceLayoutConfiguration(for: workspaceID)
                let rawLayoutBounds = layout == .accordion || layoutConfiguration != nil
                    ? display.usableBounds
                    : display.bounds
                let layoutBounds = managedLayoutBounds(rawLayoutBounds)
                if layout == .tiled {
                    let configuration = layoutConfiguration ?? .aeroSpaceUserDefaults
                    let partition = TiledLayoutPartitionKey(
                        workspaceID: workspaceID,
                        displayIdentifier: display.identifier
                    )
                    let existingTree = tiledTrees[partition]
                    let protectedWindowKeys = postSleepWindowRecoveryState.protectedWindowKeys
                    if PostSleepTiledLayoutRecoveryPolicy.shouldDeferPartition(
                        tree: existingTree,
                        protectedWindowKeys: protectedWindowKeys
                    ) {
                        let protectedParticipantKeys = PostSleepTiledLayoutRecoveryPolicy
                            .protectedParticipantKeys(
                                in: existingTree,
                                protectedWindowKeys: protectedWindowKeys
                            )
                        diagnostics.log(
                            category: "layout",
                            event: "display-deferred",
                            correlation: correlationID,
                            fields: [
                                "workspace": Self.shortIdentifier(workspaceID.uuidString),
                                "display": Self.shortIdentifier(display.identifier),
                                "layout": layout.rawValue,
                                "reason": "post-sleep-partial-bsp-tree",
                                "protected-participant-count": String(
                                    protectedParticipantKeys.count
                                ),
                                "tree-window-count": String(existingTree?.windowKeys.count ?? 0),
                            ]
                        )
                        continue
                    }
                    if let tree = TiledLayoutEngine.reconciled(
                        existingTree,
                        windowKeys: ordered.map(\.key),
                        weights: ordered.map { CGFloat(Self.validLayoutWeight($0.layoutWeight)) },
                        orientation: configuration.orientation.resolved(for: layoutBounds)
                    ), let frames = try? TiledLayoutEngine.frames(
                        for: tree,
                        in: layoutBounds,
                        configuration: configuration
                    ) {
                        tiledTrees[partition] = tree
                        for tracked in ordered {
                            guard let frame = frames[tracked.key] else { continue }
                            lastSolvedTiledFrames[tracked.key] = frame
                            expectedLayoutFrames[tracked.key] = frame
                            frameChanges.append(FrameChange(window: tracked, frame: frame))
                        }
                    }
                } else {
                    let frames = Self.layoutFrames(
                        layout,
                        count: ordered.count,
                        in: layoutBounds,
                        accordionFocusedIndex: accordionFocusedIndex,
                        tiledWeights: ordered.map { CGFloat(Self.validLayoutWeight($0.layoutWeight)) },
                        layoutConfiguration: layoutConfiguration
                    )
                    for (tracked, frame) in zip(ordered, frames) {
                        expectedLayoutFrames[tracked.key] = frame
                        frameChanges.append(FrameChange(window: tracked, frame: frame))
                    }
                }
                diagnostics.log(
                    category: "layout",
                    event: "display-solved",
                    correlation: correlationID,
                    fields: [
                        "workspace": Self.shortIdentifier(workspaceID.uuidString),
                        "display": Self.shortIdentifier(display.identifier),
                        "layout": layout.rawValue,
                        "window-count": String(ordered.count),
                        "focused-window": primaryKey.map(Self.diagnosticWindowKey) ?? "none",
                        "bounds": Self.diagnosticRect(layoutBounds),
                    ]
                )
            }
        }
        applyFrameChanges(frameChanges, correlationID: correlationID)
        applyPositionChanges(positionChanges, correlationID: correlationID)
        return expectedLayoutFrames
    }

    private func workspaceLayout(for workspaceID: UUID) -> WorkspaceLayout {
        workspaceEngineLookupIndex.workspace(for: workspaceID)?.layout ?? .none
    }

    private func isManagedLayoutParticipant(_ tracked: TrackedWindow) -> Bool {
        workspaceLayout(for: tracked.workspaceID) != .none &&
            !isDropDownAppWindow(tracked.key) &&
            !isExcludedFromWorkspaceParticipation(tracked) &&
            Self.shouldIncludeInLayout(
                layoutOverride: tracked.layoutOverride,
                admissionDecision: tracked.admissionDecision,
                rule: resolvedRule(for: tracked.bundleIdentifier)
            )
    }

    private func managedLayoutBounds(_ bounds: CGRect) -> CGRect {
        FocusedWindowHighlightPolicy.reservingScreenEdgeClearance(
            in: bounds,
            enabled: focusedWindowHighlightEnabled
        )
    }

    private func workspaceLayoutConfiguration(
        for workspaceID: UUID
    ) -> WorkspaceLayoutConfiguration? {
        workspaceEngineLookupIndex.workspace(for: workspaceID)?.layoutConfiguration
    }

    private func nextLayoutOrder(in workspaceID: UUID) -> Int {
        (windows.values
            .filter { $0.workspaceID == workspaceID }
            .map(\.layoutOrder)
            .max() ?? -1) + 1
    }

    static func validLayoutWeight(_ value: Double?) -> Double {
        guard let value, value.isFinite, value > 0 else { return 1 }
        return min(value, 1000)
    }

    private static func normalizedBundleIdentifier(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func indexedAppRules(_ rules: [AppRule]) -> [String: AppRule] {
        var indexed: [String: AppRule] = [:]
        for rule in rules where !rule.bundleIdentifier.isEmpty {
            let key = rule.bundleIdentifier.lowercased()
            if indexed[key] == nil { indexed[key] = rule }
        }
        return indexed
    }

    private func resolvedRule(
        for bundleIdentifier: String?,
        in rules: [String: AppRule]? = nil
    ) -> ResolvedAppRule {
        guard let bundleIdentifier else { return .none }
        if let rules {
            return rules[bundleIdentifier.lowercased()]?.resolved(
                validWorkspaceIDs: workspaceEngineLookupIndex.validWorkspaceIDs
            ) ?? .none
        }
        return workspaceEngineLookupIndex.resolvedRule(
            forBundleIdentifier: bundleIdentifier
        )
    }

    private func rebuildWorkspaceEngineLookupIndex() {
        workspaceEngineLookupIndex = WorkspaceEngineLookupIndex(
            workspaces: workspaces,
            appRulesByBundleIdentifier: appRulesByBundleIdentifier
        )
    }

    @discardableResult
    private func reapplyWorkspaceRules(to keys: [WindowKey]) -> Int {
        var reroutedCount = 0
        for key in keys {
            guard var tracked = windows[key] else { continue }
            let sourceWorkspaceID = tracked.workspaceID
            let assignedWorkspaceID = resolvedRule(for: tracked.bundleIdentifier).assignedWorkspaceID
            tracked.workspaceRuleOverrideActive = false
            if let assignedWorkspaceID, assignedWorkspaceID != sourceWorkspaceID {
                tracked.workspaceID = assignedWorkspaceID
                tracked.layoutOrder = nextLayoutOrder(in: assignedWorkspaceID)
                tracked.layoutWeight = 1
                if lastFocusedWindow[sourceWorkspaceID] == key {
                    lastFocusedWindow.removeValue(forKey: sourceWorkspaceID)
                }
                reroutedCount += 1
            }
            windows[key] = tracked
        }
        return reroutedCount
    }

    private func captureCurrentFrames(
        for workspaceIDs: Set<UUID>,
        displays: [DisplaySnapshot]
    ) {
        guard !workspaceIDs.isEmpty else { return }
        for key in windows.keys {
            guard var tracked = windows[key],
                  !isDropDownAppWindow(key),
                  !isExcludedFromWorkspaceParticipation(tracked),
                  FullscreenSessionPolicy.allowsGeometryWrite(
                    hasFullscreenSession: fullscreenSessions[key] != nil,
                    isTemporarilyDeferred: temporarilyDeferredWindowKeys.contains(key)
                  ),
                  workspaceIDs.contains(tracked.workspaceID),
                  isWorkspaceActive(tracked.workspaceID),
                  let frame = AccessibilityWindow.frame(of: tracked.element),
                  Self.isMeaningfullyVisible(frame, displays: displays)
            else { continue }
            tracked.restoreFrame = frame
            tracked.displayPlacement = Self.displayPlacement(for: frame, displays: displays)
            windows[key] = tracked
        }
    }

    private func targetDisplay(
        for tracked: TrackedWindow,
        workspaceID: UUID,
        displays: [DisplaySnapshot],
        correlationID: String? = nil
    ) -> DisplaySnapshot? {
        let effectiveMode = Self.displayModeForWindowPlacement(
            configuredMode: displayMode,
            rule: resolvedRule(for: tracked.bundleIdentifier)
        )
        let home = effectiveMode == .independent
            ? workspaceHomeDisplayIdentifier(for: workspaceID, displays: displays)
            : nil
        guard let identifier = Self.layoutDisplayIdentifier(
            preferredDisplayIdentifier: tracked.displayPlacement?.displayIdentifier,
            savedFrame: tracked.restoreFrame,
            mode: effectiveMode,
            workspaceHomeDisplayIdentifier: home,
            displays: displays
        ) else {
            diagnostics.log(
                category: "display-resolution",
                event: "failed",
                correlation: correlationID,
                fields: [
                    "window": Self.diagnosticWindowKey(tracked.key),
                    "workspace": Self.shortIdentifier(workspaceID.uuidString),
                    "reason": "no-active-display",
                ]
            )
            return nil
        }
        let preferred = tracked.displayPlacement?.displayIdentifier
        let fallbackReason: String
        if effectiveMode == .independent, home != nil, identifier == home {
            fallbackReason = "independent-workspace-home"
        } else if preferred == identifier {
            fallbackReason = "saved-display-affinity"
        } else if displays.first(where: \.isMain)?.identifier == identifier {
            fallbackReason = "main-display-fallback"
        } else {
            fallbackReason = "best-frame-intersection"
        }
        diagnostics.log(
            category: "display-resolution",
            event: "window-target",
            correlation: correlationID,
            fields: [
                "window": Self.diagnosticWindowKey(tracked.key),
                "workspace": Self.shortIdentifier(workspaceID.uuidString),
                "preferred-display": preferred.map(Self.shortIdentifier) ?? "none",
                "workspace-home": home.map(Self.shortIdentifier) ?? "none",
                "resolved-display": Self.shortIdentifier(identifier),
                "reason": fallbackReason,
                "mode": effectiveMode.rawValue,
            ]
        )
        return displays.first(where: { $0.identifier == identifier })
    }

    static func layoutDisplayIdentifier(
        preferredDisplayIdentifier: String?,
        savedFrame: WindowFrame,
        mode: MultiDisplayMode,
        workspaceHomeDisplayIdentifier: String?,
        displays: [DisplaySnapshot]
    ) -> String? {
        guard let main = displays.first(where: \.isMain) ?? displays.first else { return nil }
        if mode == .independent {
            guard let workspaceHomeDisplayIdentifier else { return main.identifier }
            return displays.contains(where: { $0.identifier == workspaceHomeDisplayIdentifier })
                ? workspaceHomeDisplayIdentifier
                : main.identifier
        }
        if let preferredDisplayIdentifier,
           displays.contains(where: { $0.identifier == preferredDisplayIdentifier }) {
            return preferredDisplayIdentifier
        }
        return bestDisplay(for: savedFrame, displays: displays)?.identifier ?? main.identifier
    }

    static func resetTargetDisplayIdentifier(
        mode: MultiDisplayMode,
        interactionDisplayIdentifier: String,
        preferredDisplayIdentifier: String?,
        savedFrame: WindowFrame,
        displays: [DisplaySnapshot]
    ) -> String? {
        guard let main = displays.first(where: \.isMain) ?? displays.first else { return nil }
        if mode == .independent {
            return displays.contains(where: { $0.identifier == interactionDisplayIdentifier })
                ? interactionDisplayIdentifier
                : main.identifier
        }
        return layoutDisplayIdentifier(
            preferredDisplayIdentifier: preferredDisplayIdentifier,
            savedFrame: savedFrame,
            mode: .unified,
            workspaceHomeDisplayIdentifier: nil,
            displays: displays
        )
    }

    static func layoutFrames(
        _ layout: WorkspaceLayout,
        count: Int,
        in displayBounds: CGRect,
        gap: CGFloat = 8,
        accordionFocusedIndex: Int? = nil,
        accordionPadding: CGFloat = 250,
        accordionOrientation: AccordionOrientation = .automatic,
        tiledWeights: [CGFloat]? = nil,
        layoutConfiguration: WorkspaceLayoutConfiguration? = nil
    ) -> [WindowFrame] {
        guard count > 0 else { return [] }
        guard layout != .none else { return [] }

        func frame(_ rect: CGRect) -> WindowFrame {
            WindowFrame(
                position: CGPoint(x: rect.minX.rounded(), y: rect.minY.rounded()),
                size: CGSize(width: max(1, rect.width.rounded()), height: max(1, rect.height.rounded()))
            )
        }

        switch layout {
        case .none:
            return []
        case .tiled:
            if let configuration = layoutConfiguration?.clamped() {
                return flatTiledFrames(
                    count: count,
                    in: displayBounds,
                    configuration: configuration,
                    weights: tiledWeights,
                    frame: frame
                )
            }
            let insetBounds = displayBounds.insetBy(dx: gap, dy: gap)
            let bounds = insetBounds.width > 0 && insetBounds.height > 0 ? insetBounds : displayBounds
            if count == 1 { return [frame(bounds)] }
            let aspect = max(0.5, bounds.width / max(1, bounds.height))
            let columns = min(count, max(1, Int(ceil(sqrt(CGFloat(count) * aspect)))))
            let rows = Int(ceil(CGFloat(count) / CGFloat(columns)))
            let cellWidth = max(1, (bounds.width - gap * CGFloat(columns - 1)) / CGFloat(columns))
            let cellHeight = max(1, (bounds.height - gap * CGFloat(rows - 1)) / CGFloat(rows))
            return (0..<count).map { index in
                let column = index % columns
                let row = index / columns
                return frame(CGRect(
                    x: bounds.minX + CGFloat(column) * (cellWidth + gap),
                    y: bounds.minY + CGFloat(row) * (cellHeight + gap),
                    width: cellWidth,
                    height: cellHeight
                ))
            }
        case .accordion:
            // AeroSpace's accordion is an overlapping stack, not a master/secondary split.
            // Its inner gap setting is deliberately absent here: accordion-padding alone reveals
            // the neighbouring windows. WindowRanger's built-in values are 250 points and automatic
            // orientation (horizontal on wide displays, vertical on tall displays).
            let configuration = layoutConfiguration?.clamped()
            let effectiveBounds = configuration.map {
                insetLayoutBounds(displayBounds, gaps: $0.gaps)
            } ?? displayBounds
            if count == 1 { return [frame(effectiveBounds)] }

            let focusedIndex = min(max(accordionFocusedIndex ?? 0, 0), count - 1)
            let resolvedOrientation = (configuration?.orientation ?? accordionOrientation)
                .resolved(for: effectiveBounds)
            let availableLength = resolvedOrientation == .horizontal
                ? effectiveBounds.width
                : effectiveBounds.height
            // Preserve the configured padding unless a very small display would otherwise produce
            // a zero/negative frame for the two-padding neighbour case.
            let configuredPadding = CGFloat(configuration?.accordionPadding ?? Double(accordionPadding))
            let padding = min(max(0, configuredPadding), max(0, (availableLength - 1) / 2))

            return (0..<count).map { index in
                let leadingPadding: CGFloat
                let trailingPadding: CGFloat
                switch index {
                case 0:
                    leadingPadding = 0
                    trailingPadding = padding
                case count - 1:
                    leadingPadding = padding
                    trailingPadding = 0
                case focusedIndex - 1:
                    leadingPadding = 0
                    trailingPadding = 2 * padding
                case focusedIndex + 1:
                    leadingPadding = 2 * padding
                    trailingPadding = 0
                default:
                    leadingPadding = padding
                    trailingPadding = padding
                }

                switch resolvedOrientation {
                case .horizontal:
                    return frame(CGRect(
                        x: effectiveBounds.minX + leadingPadding,
                        y: effectiveBounds.minY,
                        width: effectiveBounds.width - leadingPadding - trailingPadding,
                        height: effectiveBounds.height
                    ))
                case .vertical:
                    return frame(CGRect(
                        x: effectiveBounds.minX,
                        y: effectiveBounds.minY + leadingPadding,
                        width: effectiveBounds.width,
                        height: effectiveBounds.height - leadingPadding - trailingPadding
                    ))
                case .automatic:
                    preconditionFailure("Automatic accordion orientation must be resolved")
                }
            }
        }
    }

    private static func flatTiledFrames(
        count: Int,
        in displayBounds: CGRect,
        configuration: WorkspaceLayoutConfiguration,
        weights: [CGFloat]?,
        frame: (CGRect) -> WindowFrame
    ) -> [WindowFrame] {
        let bounds = insetLayoutBounds(displayBounds, gaps: configuration.gaps)
        let orientation = configuration.orientation.resolved(for: bounds)
        let rawGap = orientation == .horizontal
            ? CGFloat(configuration.gaps.innerHorizontal)
            : CGFloat(configuration.gaps.innerVertical)
        let totalLength = orientation == .horizontal ? bounds.width : bounds.height
        let gap = min(max(0, rawGap), count > 1 ? max(0, (totalLength - 1) / CGFloat(count - 1)) : 0)
        let available = max(1, totalLength - gap * CGFloat(max(0, count - 1)))
        let effectiveWeights: [CGFloat]
        if let weights, weights.count == count {
            let sanitized = weights.map { $0.isFinite && $0 > 0 ? $0 : 1 }
            let sum = sanitized.reduce(0, +)
            effectiveWeights = sum > 0 ? sanitized.map { $0 / sum } : Array(repeating: 1 / CGFloat(count), count: count)
        } else {
            effectiveWeights = Array(repeating: 1 / CGFloat(count), count: count)
        }
        let cumulative = effectiveWeights.reduce(into: [CGFloat.zero]) { partial, weight in
            partial.append(partial.last! + weight)
        }

        return (0..<count).map { index in
            let segmentStart = (available * cumulative[index]).rounded()
            let segmentEnd = (available * cumulative[index + 1]).rounded()
            let length = max(1, segmentEnd - segmentStart)
            switch orientation {
            case .horizontal:
                return frame(CGRect(
                    x: bounds.minX + segmentStart + gap * CGFloat(index),
                    y: bounds.minY,
                    width: length,
                    height: bounds.height
                ))
            case .vertical:
                return frame(CGRect(
                    x: bounds.minX,
                    y: bounds.minY + segmentStart + gap * CGFloat(index),
                    width: bounds.width,
                    height: length
                ))
            case .automatic:
                preconditionFailure("Automatic tiled orientation must be resolved")
            }
        }
    }

    private static func insetLayoutBounds(
        _ bounds: CGRect,
        gaps: WorkspaceLayoutGaps
    ) -> CGRect {
        let gaps = gaps.clamped()
        let left = min(CGFloat(gaps.outerLeft), max(0, bounds.width - 1))
        let right = min(CGFloat(gaps.outerRight), max(0, bounds.width - left - 1))
        let top = min(CGFloat(gaps.outerTop), max(0, bounds.height - 1))
        let bottom = min(CGFloat(gaps.outerBottom), max(0, bounds.height - top - 1))
        return CGRect(
            x: bounds.minX + left,
            y: bounds.minY + top,
            width: max(1, bounds.width - left - right),
            height: max(1, bounds.height - top - bottom)
        )
    }

    private func applyPositionChanges(
        _ changes: [PositionChange],
        correlationID: String? = nil
    ) {
        guard !isWindowManagementPaused else { return }
        let eligibleChanges = changes.filter {
            !isExcludedFromWorkspaceParticipation($0.window) &&
                FullscreenSessionPolicy.allowsGeometryWrite(
                hasFullscreenSession: fullscreenSessions[$0.window.key] != nil,
                isTemporarilyDeferred: temporarilyDeferredWindowKeys.contains($0.window.key)
            )
        }
        let changesByApplication = Dictionary(grouping: eligibleChanges, by: { $0.window.processIdentifier })
        for (processIdentifier, applicationChanges) in changesByApplication {
            AccessibilityWindow.withoutPositionAnimations(for: processIdentifier) {
                for change in applicationChanges {
                    let succeeded = AccessibilityWindow.setPositionIfNeeded(
                        change.position,
                        of: change.window.element
                    )
                    diagnostics.log(
                        category: "window-frame",
                        event: "position-applied",
                        correlation: correlationID,
                        fields: [
                            "window": Self.diagnosticWindowKey(change.window.key),
                            "position": Self.diagnosticPoint(change.position),
                            "success": String(succeeded),
                        ]
                    )
                }
            }
        }
    }

    private func applyFrameChanges(
        _ changes: [FrameChange],
        correlationID: String? = nil
    ) {
        guard !isWindowManagementPaused else { return }
        let effectiveChanges = changes.compactMap { change -> (FrameChange, WindowFrame?)? in
            guard !isExcludedFromWorkspaceParticipation(change.window),
                  FullscreenSessionPolicy.allowsGeometryWrite(
                hasFullscreenSession: fullscreenSessions[change.window.key] != nil,
                isTemporarilyDeferred: temporarilyDeferredWindowKeys.contains(change.window.key)
            )
            else { return nil }
            let current = AccessibilityWindow.frame(of: change.window.element)
            if let current, AccessibilityWindow.framesMatch(current, change.frame) {
                diagnostics.log(
                    category: "window-frame",
                    event: "frame-skipped-unchanged",
                    correlation: correlationID,
                    fields: [
                        "window": Self.diagnosticWindowKey(change.window.key),
                        "frame": Self.diagnosticFrame(current),
                    ]
                )
                return nil
            }
            return (change, current)
        }
        let changesByApplication = Dictionary(grouping: effectiveChanges, by: { $0.0.window.processIdentifier })
        for (processIdentifier, applicationChanges) in changesByApplication {
            AccessibilityWindow.withoutPositionAnimations(for: processIdentifier) {
                for (change, current) in applicationChanges {
                    let succeeded: Bool
                    var writeMode = Self.geometryWriteMode(for: change.window.admissionDecision)
                    if writeMode == .positionOnly ||
                        (current.map { Self.sizesMatch($0.size, change.frame.size) } ?? false) {
                        succeeded = AccessibilityWindow.setPositionIfNeeded(
                            change.frame.position,
                            of: change.window.element
                        )
                    } else {
                        let frameResult = AccessibilityWindow.setFrameResult(
                            change.frame,
                            of: change.window.element
                        )
                        if frameResult == .initialSizeRejected,
                           let recovered = self.recoverRejectedResize(
                            change,
                            correlationID: correlationID,
                            source: "frame-application"
                           ) {
                            succeeded = recovered
                            writeMode = .positionOnly
                        } else {
                            succeeded = frameResult == .succeeded
                        }
                    }
                    diagnostics.log(
                        category: "window-frame",
                        event: "frame-applied",
                        correlation: correlationID,
                        fields: [
                            "window": Self.diagnosticWindowKey(change.window.key),
                            "from-frame": current.map(Self.diagnosticFrame) ?? "unknown",
                            "to-frame": Self.diagnosticFrame(change.frame),
                            "success": String(succeeded),
                            "write-mode": writeMode.rawValue,
                        ]
                    )
                }
            }
        }
    }

    /// When the initial size write rejects a normal standard window, re-probe once, classify that
    /// exact surface as fixed-size, and immediately complete the requested move without resizing.
    /// This prevents an unavailable discovery probe from leaving a window parked while it consumes
    /// a layout slot.
    private func recoverRejectedResize(
        _ change: FrameChange,
        correlationID: String?,
        source: String
    ) -> Bool? {
        let cached = admissionMetadataByWindow[change.window.key]
        let coreMetadata = AccessibilityWindow.admissionMetadata(
            of: change.window.element,
            bundleIdentifier: change.window.bundleIdentifier,
            windowLayer: cached?.windowLayer ?? lastKnownWindowLayer[change.window.key]
        )
        guard AccessibilityWindow.shouldCollectFixedSizeStandardWindowEvidence(coreMetadata) else {
            return nil
        }
        guard rejectedResizeRecoveryAttemptedWindowKeys.insert(change.window.key).inserted else {
            return nil
        }
        let supportMetadata = AccessibilityWindow.admissionSupportMetadata(
            of: change.window.element,
            coreMetadata: coreMetadata
        )
        guard let decision = AccessibilityWindow.fixedSizeDecisionAfterRejectedResize(supportMetadata)
        else { return nil }

        recordAdmissionDecision(
            decision,
            metadata: supportMetadata,
            key: change.window.key,
            layerSource: "resize-rejection",
            correlationID: correlationID
        )
        if var tracked = windows[change.window.key] {
            tracked.admissionDecision = decision
            windows[change.window.key] = tracked
        }
        resizeRecoveryNeedsImmediateReflow = true
        let moved = AccessibilityWindow.setPositionIfNeeded(
            change.frame.position,
            of: change.window.element
        )
        diagnostics.log(
            category: "window-frame",
            event: "resize-rejection-recovered",
            correlation: correlationID,
            fields: [
                "window": Self.diagnosticWindowKey(change.window.key),
                "source": source,
                "position": Self.diagnosticPoint(change.frame.position),
                "position-success": String(moved),
                "position-settable": supportMetadata.positionSettable.rawValue,
                "size-settable": supportMetadata.sizeSettable.rawValue,
            ]
        )
        return moved
    }

    private static func sizesMatch(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        abs(lhs.width - rhs.width) < 0.5 && abs(lhs.height - rhs.height) < 0.5
    }

    private func restoreManagedWindowsForQuit() {
        let mainDisplayBounds = CGDisplayBounds(CGMainDisplayID())
        guard !mainDisplayBounds.isNull, !mainDisplayBounds.isEmpty else { return }

        var pending = windows.values.compactMap { tracked -> FrameChange? in
            guard !isExcludedFromWorkspaceParticipation(tracked),
                  FullscreenSessionPolicy.allowsGeometryWrite(
                hasFullscreenSession: fullscreenSessions[tracked.key] != nil,
                isTemporarilyDeferred: temporarilyDeferredWindowKeys.contains(tracked.key)
            )
            else { return nil }
            return FrameChange(
                window: tracked,
                frame: Self.quitRecoveryFrame(
                    savedFrame: tracked.restoreFrame,
                    currentFrame: AccessibilityWindow.frame(of: tracked.element),
                    mainDisplayBounds: mainDisplayBounds
                )
            )
        }

        // AX writes are synchronous, but a few apps immediately reapply their own frame. Verify
        // and retry a small bounded number of times while the app is still fully alive.
        for attempt in 0..<3 where !pending.isEmpty {
            let changesByApplication = Dictionary(grouping: pending, by: { $0.window.processIdentifier })
            for (processIdentifier, applicationChanges) in changesByApplication {
                AccessibilityWindow.withoutPositionAnimations(for: processIdentifier) {
                    for change in applicationChanges {
                        let current = self.windows[change.window.key] ?? change.window
                        guard !self.isExcludedFromWorkspaceParticipation(current) else { continue }
                        if Self.geometryWriteMode(for: current.admissionDecision) == .positionOnly {
                            AccessibilityWindow.setPositionIfNeeded(
                                change.frame.position,
                                of: current.element
                            )
                        } else {
                            let result = AccessibilityWindow.setFrameResult(
                                change.frame,
                                of: current.element
                            )
                            if result == .initialSizeRejected {
                                _ = self.recoverRejectedResize(
                                    FrameChange(window: current, frame: change.frame),
                                    correlationID: nil,
                                    source: "quit-recovery"
                                )
                            }
                        }
                    }
                }
            }

            pending = pending.filter { change in
                let current = self.windows[change.window.key] ?? change.window
                guard !isExcludedFromWorkspaceParticipation(current) else { return false }
                guard let actual = AccessibilityWindow.frame(of: current.element) else { return true }
                if Self.geometryWriteMode(for: current.admissionDecision) == .positionOnly {
                    return !AccessibilityWindow.positionsMatch(actual.position, change.frame.position)
                }
                return !AccessibilityWindow.framesMatch(actual, change.frame)
            }
            if attempt < 2, !pending.isEmpty {
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
    }

    private func parkingPosition(displays: [DisplaySnapshot]? = nil) -> CGPoint {
        let bounds = (displays ?? Self.activeDisplays()).map(\.bounds)
        let union = bounds.reduce(CGRect.null) { $0.union($1) }
        guard !union.isNull else { return CGPoint(x: 1, y: 1) }
        return CGPoint(x: union.maxX - 1, y: union.maxY - 1)
    }

    static func activeDisplays() -> [DisplaySnapshot] {
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetActiveDisplayList(displayCount, &displays, &displayCount)
        let active = Array(displays.prefix(Int(displayCount)))
        let mainDisplay = CGMainDisplayID()
        let dockPreferences = currentDockLayoutPreferences()
        let screensByDisplayID: [CGDirectDisplayID: NSScreen] = Dictionary(
            uniqueKeysWithValues: NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, NSScreen)? in
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else { return nil }
            return (number.uint32Value, screen)
        })
        let sorted = active.sorted { lhs, rhs in
            if (lhs == mainDisplay) != (rhs == mainDisplay) { return lhs == mainDisplay }
            let left = CGDisplayBounds(lhs)
            let right = CGDisplayBounds(rhs)
            if left.minX != right.minX { return left.minX < right.minX }
            return left.minY < right.minY
        }
        return sorted.enumerated().map { index, displayID in
            let identifier: String
            if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
                identifier = CFUUIDCreateString(nil, uuid) as String
            } else {
                identifier = "session-display-\(displayID)"
            }
            let screen = screensByDisplayID[displayID]
            let bounds = CGDisplayBounds(displayID)
            let vendor = validDisplayIdentityNumber(CGDisplayVendorNumber(displayID))
            let model = validDisplayIdentityNumber(CGDisplayModelNumber(displayID))
            let serial = validDisplayIdentityNumber(CGDisplaySerialNumber(displayID)).map(String.init)
            let name = screen?.localizedName
                ?? (displayID == mainDisplay ? "Main Display" : "Display \(index + 1)")
            return DisplaySnapshot(
                identifier: identifier,
                bounds: bounds,
                usableBounds: usableDisplayBounds(
                    displayID,
                    mainDisplayID: mainDisplay,
                    dockPreferences: dockPreferences
                ),
                isMain: displayID == mainDisplay,
                isBuiltIn: CGDisplayIsBuiltin(displayID) != 0,
                name: name,
                fingerprint: DisplayFingerprint(
                    displayUUID: identifier.hasPrefix("session-display-") ? nil : identifier,
                    vendorID: vendor,
                    modelID: model,
                    serialNumber: serial,
                    displayName: name,
                    widthPoints: Int(bounds.width.rounded()),
                    heightPoints: Int(bounds.height.rounded())
                )
            )
        }
    }

    static func displayTopologySignature(_ displays: [DisplaySnapshot]) -> String {
        displays.sorted { $0.identifier < $1.identifier }.map { display in
            [
                display.identifier,
                String(format: "%.0f", display.bounds.minX),
                String(format: "%.0f", display.bounds.minY),
                String(format: "%.0f", display.bounds.width),
                String(format: "%.0f", display.bounds.height),
                display.isMain ? "main" : "secondary",
            ].joined(separator: ":")
        }.joined(separator: "|")
    }

    private static func validDisplayIdentityNumber(_ value: UInt32) -> UInt32? {
        value == 0 || value == UInt32.max ? nil : value
    }

    private static func usableDisplayBounds(
        _ displayID: CGDirectDisplayID,
        mainDisplayID: CGDirectDisplayID,
        dockPreferences: DockLayoutPreferences
    ) -> CGRect? {
        func screen(for identifier: CGDirectDisplayID) -> NSScreen? {
            NSScreen.screens.first { screen in
                (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
                    == identifier
            }
        }
        guard let targetScreen = screen(for: displayID),
              let mainScreen = screen(for: mainDisplayID)
        else { return nil }
        let visibleFrame = usableCocoaBounds(
            screenFrame: targetScreen.frame,
            visibleFrame: targetScreen.visibleFrame,
            dockPreferences: dockPreferences
        )
        return accessibilityBounds(
            forCocoaBounds: visibleFrame,
            mainScreenTop: mainScreen.frame.maxY
        )
    }

    static func usableCocoaBounds(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        dockPreferences: DockLayoutPreferences
    ) -> CGRect {
        guard dockPreferences.automaticallyHides, let edge = dockPreferences.edge else {
            return visibleFrame
        }
        let constrained = visibleFrame.intersection(screenFrame)
        guard !constrained.isNull, constrained.width > 0, constrained.height > 0 else {
            return visibleFrame
        }

        var adjusted = constrained
        switch edge {
        case .bottom:
            adjusted.origin.y = screenFrame.minY
            adjusted.size.height = constrained.maxY - screenFrame.minY
        case .left:
            adjusted.origin.x = screenFrame.minX
            adjusted.size.width = constrained.maxX - screenFrame.minX
        case .right:
            adjusted.size.width = screenFrame.maxX - constrained.minX
        }
        return adjusted
    }

    private static func currentDockLayoutPreferences() -> DockLayoutPreferences {
        let applicationID = "com.apple.dock" as CFString
        let automaticallyHides = (
            CFPreferencesCopyValue(
                "autohide" as CFString,
                applicationID,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            ) as? NSNumber
        )?.boolValue ?? false
        let edge = (
            CFPreferencesCopyValue(
                "orientation" as CFString,
                applicationID,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            ) as? String
        ).flatMap(DockEdge.init(rawValue:))
        return DockLayoutPreferences(automaticallyHides: automaticallyHides, edge: edge)
    }

    static func accessibilityBounds(forCocoaBounds bounds: CGRect, mainScreenTop: CGFloat) -> CGRect {
        CGRect(
            x: bounds.minX,
            y: mainScreenTop - bounds.maxY,
            width: bounds.width,
            height: bounds.height
        )
    }

    static func displayPlacement(
        for frame: WindowFrame,
        displays: [DisplaySnapshot]
    ) -> PersistedDisplayPlacement? {
        guard let display = bestDisplay(for: frame, displays: displays),
              display.bounds.width > 0,
              display.bounds.height > 0
        else { return nil }
        return PersistedDisplayPlacement(
            displayIdentifier: display.identifier,
            normalizedOrigin: CGPoint(
                x: (frame.position.x - display.bounds.minX) / display.bounds.width,
                y: (frame.position.y - display.bounds.minY) / display.bounds.height
            )
        )
    }

    static func resolveDisplayFrame(
        savedFrame: WindowFrame,
        placement: PersistedDisplayPlacement?,
        displays: [DisplaySnapshot],
        forcedDisplayIdentifier: String? = nil
    ) -> ResolvedDisplayFrame {
        guard let main = displays.first(where: \.isMain) ?? displays.first else {
            return ResolvedDisplayFrame(frame: savedFrame, usedFallbackDisplay: false)
        }

        let preferredIdentifier = forcedDisplayIdentifier ?? placement?.displayIdentifier
        let preferred = preferredIdentifier.flatMap { identifier in
            displays.first { $0.identifier == identifier }
        }
        let target = preferred ?? (preferredIdentifier == nil ? bestDisplay(for: savedFrame, displays: displays) : nil) ?? main
        let usedFallback = preferredIdentifier != nil && preferred == nil

        let candidateNormalizedOrigin: CGPoint
        if let placement,
           placement.normalizedOrigin.x.isFinite,
           placement.normalizedOrigin.y.isFinite {
            candidateNormalizedOrigin = placement.normalizedOrigin
        } else if let source = bestDisplay(for: savedFrame, displays: displays),
                  source.bounds.width > 0,
                  source.bounds.height > 0 {
            candidateNormalizedOrigin = CGPoint(
                x: (savedFrame.position.x - source.bounds.minX) / source.bounds.width,
                y: (savedFrame.position.y - source.bounds.minY) / source.bounds.height
            )
        } else {
            candidateNormalizedOrigin = CGPoint(x: 0.25, y: 0.25)
        }
        let normalizedOrigin = candidateNormalizedOrigin.x.isFinite && candidateNormalizedOrigin.y.isFinite
            ? candidateNormalizedOrigin
            : CGPoint(x: 0.25, y: 0.25)

        let validWidth = savedFrame.size.width.isFinite && savedFrame.size.width > 0
            ? savedFrame.size.width : min(800, target.bounds.width)
        let validHeight = savedFrame.size.height.isFinite && savedFrame.size.height > 0
            ? savedFrame.size.height : min(600, target.bounds.height)
        let size = CGSize(
            width: min(validWidth, target.bounds.width),
            height: min(validHeight, target.bounds.height)
        )
        let proposed = CGPoint(
            x: target.bounds.minX + normalizedOrigin.x * target.bounds.width,
            y: target.bounds.minY + normalizedOrigin.y * target.bounds.height
        )
        let position = CGPoint(
            x: min(max(proposed.x, target.bounds.minX), target.bounds.maxX - size.width),
            y: min(max(proposed.y, target.bounds.minY), target.bounds.maxY - size.height)
        )
        return ResolvedDisplayFrame(
            frame: WindowFrame(position: position, size: size),
            usedFallbackDisplay: usedFallback
        )
    }

    private static func bestDisplay(
        for frame: WindowFrame,
        displays: [DisplaySnapshot]
    ) -> DisplaySnapshot? {
        guard !displays.isEmpty else { return nil }
        let windowRect = CGRect(origin: frame.position, size: frame.size)
        let intersections = displays.map { display in
            let intersection = display.bounds.intersection(windowRect)
            return (display, intersection.isNull ? CGFloat.zero : intersection.width * intersection.height)
        }
        if let best = intersections.max(by: { $0.1 < $1.1 }), best.1 > 0 {
            return best.0
        }
        return displays.min { lhs, rhs in
            let lhsDistance = hypot(lhs.bounds.midX - windowRect.midX, lhs.bounds.midY - windowRect.midY)
            let rhsDistance = hypot(rhs.bounds.midX - windowRect.midX, rhs.bounds.midY - windowRect.midY)
            return lhsDistance < rhsDistance
        }
    }

    private func persistState(
        preservingPendingRestores: Bool,
        waitForCompletion: Bool = false
    ) {
        var persistedWindows: [String: PersistedWindowAssignment] = [:]
        let validWorkspaceIDs = Set(workspaces.map(\.id))

        for (key, tracked) in windows {
            guard let bundleIdentifier = tracked.bundleIdentifier,
                  validWorkspaceIDs.contains(tracked.workspaceID)
            else { continue }
            persistedWindows[String(key.windowIdentifier)] = PersistedWindowAssignment(
                bundleIdentifier: bundleIdentifier,
                workspaceID: tracked.workspaceID,
                restoreFrame: tracked.restoreFrame,
                displayPlacement: tracked.displayPlacement,
                layoutOverride: tracked.layoutOverride,
                layoutOrder: tracked.layoutOrder,
                layoutWeight: tracked.layoutWeight
            )
        }

        if preservingPendingRestores {
            for (windowID, assignment) in pendingRestoredWindows
            where persistedWindows[windowID] == nil && validWorkspaceIDs.contains(assignment.workspaceID) {
                persistedWindows[windowID] = assignment
            }
        }

        stateStore.save(
            PersistedWorkspaceState(
                version: PersistedWorkspaceState.currentVersion,
                windowServerSession: stateStore.windowServerSession,
                activeWorkspaceID: currentWorkspaceID,
                windows: persistedWindows,
                activeWorkspaceIDsByDisplay: activeWorkspaceIDByDisplay.isEmpty
                    ? nil : activeWorkspaceIDByDisplay,
                profileID: currentProfileID,
                tiledTrees: tiledTrees.keys.sorted {
                    if $0.workspaceID != $1.workspaceID {
                        return $0.workspaceID.uuidString < $1.workspaceID.uuidString
                    }
                    return $0.displayIdentifier < $1.displayIdentifier
                }.compactMap { partition in
                    tiledTrees[partition].map { PersistedTiledTree(partition: partition, tree: $0) }
                },
                dropDownAppSession: dropDownAppSession.flatMap { session in
                    guard session.isApplicationHiddenByWindowRanger else { return nil }
                    return PersistedDropDownAppSession(
                        windowKey: session.windowKey,
                        windowKeys: session.windowKeys,
                        bundleIdentifier: session.bundleIdentifier,
                        displayIdentifier: session.displayIdentifier,
                        isApplicationHiddenByWindowRanger: true
                    )
                },
                dropDownAppSessions: quickAppSessions.reduce(into: [:]) { result, pair in
                    guard pair.value.isApplicationHiddenByWindowRanger else { return }
                    result[pair.key] = PersistedDropDownAppSession(
                        windowKey: pair.value.windowKey,
                        windowKeys: pair.value.windowKeys,
                        bundleIdentifier: pair.value.bundleIdentifier,
                        displayIdentifier: pair.value.displayIdentifier,
                        isApplicationHiddenByWindowRanger: true
                    )
                },
                ignoredQuickAppVisibilityRecoveries: ignoredQuickAppVisibilityRecoveries.isEmpty
                    ? nil
                    : ignoredQuickAppVisibilityRecoveries.mapValues { recovery in
                        IgnoredQuickAppVisibilityRecovery(
                            generation: recovery.generation,
                            processIdentifier: recovery.processIdentifier,
                            bundleIdentifier: recovery.bundleIdentifier,
                            confirmationInFlight: false
                        )
                    }
            ),
            waitForCompletion: waitForCompletion
        )
    }

    static func isMeaningfullyVisible(
        _ frame: WindowFrame,
        displays: [DisplaySnapshot]
    ) -> Bool {
        let windowRect = CGRect(origin: frame.position, size: frame.size)
        let visibleArea = displays
            .map { $0.bounds.intersection(windowRect) }
            .filter { !$0.isNull }
            .map { $0.width * $0.height }
            .reduce(0, +)
        let meaningfulVisibleArea = min(CGFloat(4_096), max(1, frame.size.width * frame.size.height * 0.01))
        return visibleArea >= meaningfulVisibleArea
    }

    /// Returns the saved position when a meaningful part of the window is still visible. A frame
    /// inherited from a crashed or force-stopped previous session can instead be the one-pixel
    /// parking coordinate; in that case recovery centers it on the main display without resizing.
    static func recoveryPosition(for frame: WindowFrame, displayBounds: [CGRect]) -> CGPoint {
        guard let mainDisplay = displayBounds.first else { return frame.position }
        let windowRect = CGRect(origin: frame.position, size: frame.size)
        let visibleArea = displayBounds
            .map { $0.intersection(windowRect) }
            .filter { !$0.isNull }
            .map { $0.width * $0.height }
            .reduce(0, +)
        let meaningfulVisibleArea = min(CGFloat(4_096), max(1, frame.size.width * frame.size.height * 0.01))
        guard visibleArea < meaningfulVisibleArea else { return frame.position }

        let x = frame.size.width <= mainDisplay.width
            ? mainDisplay.midX - frame.size.width / 2
            : mainDisplay.minX
        let y = frame.size.height <= mainDisplay.height
            ? mainDisplay.midY - frame.size.height / 2
            : mainDisplay.minY
        return CGPoint(x: x, y: y)
    }

    /// Produces a complete, finite frame wholly inside the main display. Quit recovery deliberately
    /// ignores which monitor the saved frame belonged to: quitting is the user's safety escape hatch.
    static func quitRecoveryFrame(
        savedFrame: WindowFrame,
        currentFrame: WindowFrame?,
        mainDisplayBounds: CGRect
    ) -> WindowFrame {
        let safeBounds = mainDisplayBounds.insetBy(dx: 12, dy: 12)
        let availableBounds = safeBounds.isEmpty ? mainDisplayBounds : safeBounds

        func validSize(_ size: CGSize) -> Bool {
            size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
        }
        func validPosition(_ position: CGPoint) -> Bool {
            position.x.isFinite && position.y.isFinite
        }

        let fallbackSize = CGSize(
            width: min(800, availableBounds.width),
            height: min(600, availableBounds.height)
        )
        let preferredSize = validSize(savedFrame.size)
            ? savedFrame.size
            : (currentFrame.map(\.size).flatMap { validSize($0) ? $0 : nil } ?? fallbackSize)
        let size = CGSize(
            width: min(preferredSize.width, availableBounds.width),
            height: min(preferredSize.height, availableBounds.height)
        )

        let centeredPosition = CGPoint(
            x: availableBounds.midX - size.width / 2,
            y: availableBounds.midY - size.height / 2
        )
        let preferredPosition = validPosition(savedFrame.position)
            ? savedFrame.position
            : (currentFrame.map(\.position).flatMap { validPosition($0) ? $0 : nil } ?? centeredPosition)
        let position = CGPoint(
            x: min(max(preferredPosition.x, availableBounds.minX), availableBounds.maxX - size.width),
            y: min(max(preferredPosition.y, availableBounds.minY), availableBounds.maxY - size.height)
        )
        return WindowFrame(position: position, size: size)
    }

    private func logWorkspaceSwitchBegin(
        workspaceID: UUID,
        sourceWorkspaceID: UUID?,
        sourceInteractionDisplayIdentifier: String,
        destination: WorkspaceSwitchDestination,
        correlationID: String,
        reason: String
    ) {
        diagnostics.log(
            category: "workspace-switch-focus",
            event: "begin",
            correlation: correlationID,
            fields: [
                "workspace": Self.shortIdentifier(workspaceID.uuidString),
                "source-workspace": sourceWorkspaceID.map { Self.shortIdentifier($0.uuidString) } ?? "none",
                "source-interaction-display": Self.shortIdentifier(sourceInteractionDisplayIdentifier),
                "logical-destination-display": Self.shortIdentifier(destination.logicalDisplayIdentifier),
                "physical-destination-display": Self.shortIdentifier(destination.physicalDisplayIdentifier),
                "disconnected-home-fallback": String(destination.usedDisconnectedHomeFallback),
                "resolution-reason": reason,
                "active-before": diagnosticActiveWorkspaceMap(),
            ]
        )
    }

    private func focusWorkspaceAfterSwitch(
        workspaceID: UUID,
        destinationDisplayIdentifier: String,
        displays: [DisplaySnapshot],
        correlationID: String,
        token: FocusVerificationToken,
        previousFocusKey: WindowKey?,
        selectedApplication: WorkspaceApplicationTarget? = nil,
        selectedWindowKey: WindowKey? = nil
    ) {
        guard isFocusActionGenerationCurrent(token.generation) else {
            diagnostics.log(
                category: "workspace-switch-focus",
                event: "superseded",
                correlation: correlationID,
                fields: ["stage": "candidate-resolution"]
            )
            return
        }
        if let selectedWindowKey,
           let selectedSession = fullscreenSessions[selectedWindowKey],
           selectedSession.workspaceID == workspaceID,
           selectedSession.displayIdentifier == destinationDisplayIdentifier,
           selectedApplication?.matches(
            bundleIdentifier: selectedSession.bundleIdentifier,
            processIdentifier: selectedSession.processIdentifier
           ) != false {
            focusFullscreenSessionAfterSwitch(
                selectedSession,
                workspaceID: workspaceID,
                destinationDisplayIdentifier: destinationDisplayIdentifier,
                correlationID: correlationID,
                token: token
            )
            return
        }
        if selectedWindowKey == nil,
           let preferredKey = lastFocusedWindow[workspaceID],
           let preferredSession = fullscreenSessions[preferredKey],
           preferredSession.workspaceID == workspaceID,
           preferredSession.displayIdentifier == destinationDisplayIdentifier,
           selectedApplication?.matches(
            bundleIdentifier: preferredSession.bundleIdentifier,
            processIdentifier: preferredSession.processIdentifier
           ) != false {
            focusFullscreenSessionAfterSwitch(
                preferredSession,
                workspaceID: workspaceID,
                destinationDisplayIdentifier: destinationDisplayIdentifier,
                correlationID: correlationID,
                token: token
            )
            return
        }
        let unfilteredAttemptOrder = orderedWorkspaceSwitchFocusCandidates(
            workspaceID: workspaceID,
            destinationDisplayIdentifier: destinationDisplayIdentifier,
            displays: displays,
            correlationID: correlationID
        )
        let applicationAttemptOrder = selectedApplication.map { selectedApplication in
            unfilteredAttemptOrder.filter { key in
                guard let tracked = windows[key] else { return false }
                return selectedApplication.matches(
                    bundleIdentifier: tracked.bundleIdentifier,
                    processIdentifier: tracked.processIdentifier
                )
            }
        } ?? unfilteredAttemptOrder
        let attemptOrder = WorkspacePreviewFocusCandidatePolicy.prioritizing(
            selectedWindowKey,
            in: applicationAttemptOrder
        )
        guard let target = attemptOrder.first else {
            if let fallbackSession = fullscreenSessions.values
                .filter({
                    $0.workspaceID == workspaceID &&
                        $0.displayIdentifier == destinationDisplayIdentifier &&
                        selectedApplication?.matches(
                            bundleIdentifier: $0.bundleIdentifier,
                            processIdentifier: $0.processIdentifier
                        ) != false
                })
                .sorted(by: { $0.enteredAt > $1.enteredAt })
                .first {
                focusFullscreenSessionAfterSwitch(
                    fallbackSession,
                    workspaceID: workspaceID,
                    destinationDisplayIdentifier: destinationDisplayIdentifier,
                    correlationID: correlationID,
                    token: token
                )
                return
            }
            lastFocusedWindow.removeValue(forKey: workspaceID)
            recentInteractionFocusTarget = nil
            recentInteractionDisplayIdentifier = destinationDisplayIdentifier
            recentInteractionDisplayDeadline = Date().addingTimeInterval(1.75)
            suppressParkedPreviousFocusAfterWorkspaceSwitch(
                previousFocusKey,
                correlationID: correlationID,
                reason: "no-destination-candidate"
            )
            diagnostics.log(
                category: "workspace-switch-focus",
                event: "no-candidate",
                correlation: correlationID,
                fields: [
                    "workspace": Self.shortIdentifier(workspaceID.uuidString),
                    "display": Self.shortIdentifier(destinationDisplayIdentifier),
                    "selected-application": selectedApplication?.bundleIdentifier
                        ?? selectedApplication.map { String($0.processIdentifier) }
                        ?? "none",
                    "result": "neutral-no-focus-steal",
                    "active-after": diagnosticActiveWorkspaceMap(),
                ]
            )
            return
        }

        diagnostics.log(
            category: "workspace-switch-focus",
            event: "target-chosen",
            correlation: correlationID,
            fields: [
                "window": Self.diagnosticWindowKey(target),
                "workspace": Self.shortIdentifier(workspaceID.uuidString),
                "display": Self.shortIdentifier(destinationDisplayIdentifier),
                "preferred-history": lastFocusedWindow[workspaceID].map(Self.diagnosticWindowKey) ?? "none",
                "attempt-order": attemptOrder.map(Self.diagnosticWindowKey).joined(separator: ","),
                "selected-application": selectedApplication?.bundleIdentifier
                    ?? selectedApplication.map { String($0.processIdentifier) }
                    ?? "none",
                "active-after": diagnosticActiveWorkspaceMap(),
            ]
        )
        attemptWorkspaceSwitchFocusCandidate(
            attemptOrder: attemptOrder,
            candidateIndex: 0,
            phase: .initial,
            previousFocusKey: previousFocusKey,
            workspaceID: workspaceID,
            destinationDisplayIdentifier: destinationDisplayIdentifier,
            displays: displays,
            correlationID: correlationID,
            token: token
        )
    }

    private func focusFullscreenSessionAfterSwitch(
        _ session: FullscreenWindowSession,
        workspaceID: UUID,
        destinationDisplayIdentifier: String,
        correlationID: String,
        token: FocusVerificationToken
    ) {
        guard let focusTarget = focusTargetWindow(session.key) else { return }
        staleParkedFocusSuppression.removeValue(forKey: session.key)
        lastFocusedWindow[workspaceID] = session.key
        recentInteractionFocusTarget = session.key
        recentInteractionDisplayIdentifier = destinationDisplayIdentifier
        recentInteractionDisplayDeadline = Date().addingTimeInterval(1.75)
        diagnostics.log(
            category: "workspace-switch-focus",
            event: "fullscreen-session-target-chosen",
            correlation: correlationID,
            fields: [
                "window": Self.diagnosticWindowKey(session.key),
                "workspace": Self.shortIdentifier(workspaceID.uuidString),
                "display": Self.shortIdentifier(destinationDisplayIdentifier),
                "declared-game": String(session.isDeclaredGame),
                "geometry-write": "false",
            ]
        )
        focusManagedWindow(
            session.key,
            tracked: focusTarget,
            correlationID: correlationID,
            token: token
        )
        persistState(preservingPendingRestores: true)
        emitState()
    }

    private func orderedWorkspaceSwitchFocusCandidates(
        workspaceID: UUID,
        destinationDisplayIdentifier: String,
        displays: [DisplaySnapshot],
        correlationID: String
    ) -> [WindowKey] {
        let layout = workspaceLayout(for: workspaceID)
        let now = Date()
        focusCycleRejectedUntil = focusCycleRejectedUntil.filter { $0.value > now }
        let candidates: [(WorkspaceSwitchFocusCandidate<WindowKey>, WindowFrame)] = windows.compactMap {
            key, tracked in
            guard !isDropDownAppWindow(key),
                  !isExcludedFromWorkspaceParticipation(tracked)
            else { return nil }
            let rule = resolvedRule(for: tracked.bundleIdentifier)
            let frame = AccessibilityWindow.frame(of: tracked.element)
            let actualDisplayIdentifier = frame.flatMap {
                Self.displayPlacement(for: $0, displays: displays)?.displayIdentifier
            }
            let capabilities = AccessibilityWindow.focusCapabilities(
                of: tracked.element,
                processIdentifier: tracked.processIdentifier,
                windowIdentifier: key.windowIdentifier
            )
            let candidate = WorkspaceSwitchFocusCandidate(
                key: key,
                belongsToWorkspace: tracked.workspaceID == workspaceID,
                keepsOnAllWorkspaces: rule.keepsOnAllWorkspaces,
                isVisible: Self.shouldWindowBeVisible(
                    workspaceID: tracked.workspaceID,
                    activeWorkspaceIDs: activeWorkspaceIDs,
                    rule: rule
                ),
                isMeaningfullyVisible: frame.map {
                    Self.isMeaningfullyVisible($0, displays: displays)
                } ?? false,
                isOnDestinationDisplay: actualDisplayIdentifier == destinationDisplayIdentifier,
                isFocusEligible: AccessibilityWindow.isEligibleFocusCycleCandidate(capabilities) &&
                    focusCycleRejectedUntil[key] == nil,
                isIgnored: ignoredWindowKeys.contains(key),
                isTemporarilyDeferred: temporarilyDeferredWindowKeys.contains(key)
            )
            diagnostics.log(
                category: "workspace-switch-focus",
                event: "candidate",
                correlation: correlationID,
                fields: [
                    "window": Self.diagnosticWindowKey(key),
                    "bundle": tracked.bundleIdentifier ?? "unknown",
                    "workspace": Self.shortIdentifier(tracked.workspaceID.uuidString),
                    "display": actualDisplayIdentifier.map(Self.shortIdentifier) ?? "unknown",
                    "destination-display": Self.shortIdentifier(destinationDisplayIdentifier),
                    "workspace-member": String(candidate.belongsToWorkspace),
                    "keep-on-all": String(candidate.keepsOnAllWorkspaces),
                    "visible": String(candidate.isVisible),
                    "meaningfully-visible": String(candidate.isMeaningfullyVisible),
                    "display-match": String(candidate.isOnDestinationDisplay),
                    "focus-eligible": String(candidate.isFocusEligible),
                    "ignored": String(candidate.isIgnored),
                    "temporarily-deferred": String(candidate.isTemporarilyDeferred),
                    "layout-decision": Self.layoutDecision(
                        layoutOverride: tracked.layoutOverride,
                        admissionDecision: tracked.admissionDecision,
                        rule: rule
                    ).rawValue,
                    "included": String(candidate.isEligible &&
                        (candidate.belongsToWorkspace || candidate.keepsOnAllWorkspaces)),
                    "rejection": Self.workspaceSwitchCandidateRejectionReason(candidate),
                ]
            )
            guard let frame else { return nil }
            return (candidate, frame)
        }.sorted { lhs, rhs in
            if layout == .none {
                if lhs.1.position.y != rhs.1.position.y { return lhs.1.position.y < rhs.1.position.y }
                if lhs.1.position.x != rhs.1.position.x { return lhs.1.position.x < rhs.1.position.x }
            }
            if lhs.0.key.processIdentifier != rhs.0.key.processIdentifier {
                return lhs.0.key.processIdentifier < rhs.0.key.processIdentifier
            }
            return lhs.0.key.windowIdentifier < rhs.0.key.windowIdentifier
        }
        return WorkspaceSwitchFocusPolicy.orderedTargets(
            preferred: lastFocusedWindow[workspaceID],
            candidates: candidates.map(\.0)
        )
    }

    private static func workspaceSwitchCandidateRejectionReason<Key>(
        _ candidate: WorkspaceSwitchFocusCandidate<Key>
    ) -> String where Key: Hashable & Sendable {
        if candidate.isIgnored { return "ignored-window" }
        if candidate.isTemporarilyDeferred { return "temporarily-ineligible" }
        if !candidate.belongsToWorkspace && !candidate.keepsOnAllWorkspaces {
            return "different-workspace"
        }
        if !candidate.isVisible { return "parked-or-inactive-workspace" }
        if !candidate.isMeaningfullyVisible { return "not-meaningfully-visible" }
        if !candidate.isOnDestinationDisplay { return "cross-display-rejected" }
        if !candidate.isFocusEligible { return "not-focus-capable" }
        return "none"
    }

    private func attemptWorkspaceSwitchFocusCandidate(
        attemptOrder: [WindowKey],
        candidateIndex: Int,
        phase: FocusCandidateAttemptPhase = .initial,
        previousFocusKey: WindowKey?,
        workspaceID: UUID,
        destinationDisplayIdentifier: String,
        displays: [DisplaySnapshot],
        correlationID: String,
        token: FocusVerificationToken
    ) {
        guard isFocusActionGenerationCurrent(token.generation) else {
            diagnostics.log(
                category: "workspace-switch-focus",
                event: "superseded",
                correlation: correlationID,
                fields: ["stage": "focus-attempt"]
            )
            return
        }
        guard candidateIndex < attemptOrder.count else {
            lastFocusedWindow.removeValue(forKey: workspaceID)
            recentInteractionFocusTarget = nil
            recentInteractionDisplayIdentifier = destinationDisplayIdentifier
            recentInteractionDisplayDeadline = Date().addingTimeInterval(1.75)
            clearProgrammaticFocusIntent()
            suppressParkedPreviousFocusAfterWorkspaceSwitch(
                previousFocusKey,
                correlationID: correlationID,
                reason: "destination-focus-failed"
            )
            diagnostics.log(
                category: "workspace-switch-focus",
                event: "exhausted-candidates",
                correlation: correlationID,
                fields: [
                    "workspace": Self.shortIdentifier(workspaceID.uuidString),
                    "display": Self.shortIdentifier(destinationDisplayIdentifier),
                    "attempted": attemptOrder.map(Self.diagnosticWindowKey).joined(separator: ","),
                    "result": "neutral-no-focus-steal",
                ]
            )
            return
        }

        let targetKey = attemptOrder[candidateIndex]
        guard let target = windows[targetKey] else {
            attemptWorkspaceSwitchFocusCandidate(
                attemptOrder: attemptOrder,
                candidateIndex: candidateIndex + 1,
                phase: .initial,
                previousFocusKey: previousFocusKey,
                workspaceID: workspaceID,
                destinationDisplayIdentifier: destinationDisplayIdentifier,
                displays: displays,
                correlationID: correlationID,
                token: token
            )
            return
        }

        if phase == .initial {
            // Re-entering a workspace is fresh user intent for its chosen target, so an older
            // parked-focus suppression must not survive this explicit switch.
            staleParkedFocusSuppression.removeValue(forKey: targetKey)
            let rule = resolvedRule(for: target.bundleIdentifier)
            if target.workspaceID == workspaceID && !rule.keepsOnAllWorkspaces {
                lastFocusedWindow[workspaceID] = targetKey
            }
            recentInteractionFocusTarget = targetKey
            recentInteractionDisplayIdentifier = destinationDisplayIdentifier
            recentInteractionDisplayDeadline = Date().addingTimeInterval(1.75)
            if target.workspaceID == workspaceID, workspaceLayout(for: workspaceID) == .accordion {
                applyVisibleWindows(
                    windows.values.filter { $0.workspaceID == workspaceID },
                    displays: displays,
                    correlationID: correlationID
                )
            }
        }
        diagnostics.log(
            category: "workspace-switch-focus",
            event: "candidate-attempt",
            correlation: correlationID,
            fields: [
                "window": Self.diagnosticWindowKey(targetKey),
                "candidate-index": String(candidateIndex),
                "phase": phase.rawValue,
                "display": Self.shortIdentifier(destinationDisplayIdentifier),
            ]
        )
        if phase.performsAppKitActivation {
            activateManagedApplicationWithAppKit(
                targetKey,
                tracked: target,
                correlationID: correlationID,
                token: token,
                event: "workspace-switch-observed-activation-fallback"
            )
        } else if phase == .initial {
            focusManagedWindow(
                targetKey,
                tracked: target,
                correlationID: correlationID,
                token: token,
                allowImmediateAppKitCompatibilityFallback: false
            )
            lastBackgroundLayoutSignature = backgroundLayoutSignature(displays: displays)
            persistState(preservingPendingRestores: true)
            emitState()
        } else {
            prepareProgrammaticFocusIntent(
                targetKey,
                correlationID: correlationID,
                duration: 0.65,
                generation: token.generation
            )
            applyExactWindowFocus(
                targetKey,
                tracked: target,
                correlationID: correlationID,
                event: "workspace-switch-bounded-exact-retry"
            )
        }

        pendingFocusVerification?.cancel()
        let delay: DispatchTimeInterval = phase.exactAttempt == 0
            ? .milliseconds(220)
            : .milliseconds(120)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isFocusActionGenerationCurrent(token.generation) else { return }
            let actual = self.focusedWindowKey()
            let applicationIsActive = NSRunningApplication(
                processIdentifier: targetKey.processIdentifier
            )?.isActive == true
            let windowServerFrontmostWindow =
                AccessibilityWindow.frontmostOnScreenNormalWindowIdentifier(
                    for: targetKey.processIdentifier
                )
            let actualIsIgnored = Self.shouldIgnoreFocusObservation(
                focusedWindow: actual,
                ignoredWindowKeys: self.ignoredWindowKeys
            )
            // AX can continue reporting the pre-switch window until activation settles. That one
            // identity is stale evidence rather than a new competing user action; all other
            // cross-app focus changes still abort immediately.
            let decision = Self.workspaceSwitchFocusVerificationDecision(
                expected: targetKey,
                actual: actual,
                previousFocus: previousFocusKey,
                actualIsIgnored: actualIsIgnored,
                applicationIsActive: applicationIsActive,
                windowServerTargetIsFrontmostNormalWindow:
                    windowServerFrontmostWindow == targetKey.windowIdentifier,
                appKitActivationAttempted: phase.appKitActivationAttempted,
                exactAttempt: phase.exactAttempt,
                maximumExactAttempts: 1
            )
            self.diagnostics.log(
                category: "workspace-switch-focus",
                event: "focus-verified",
                correlation: correlationID,
                fields: [
                    "expected-window": Self.diagnosticWindowKey(targetKey),
                    "actual-window": actual.map(Self.diagnosticWindowKey) ?? "none",
                    "previous-window": previousFocusKey.map(Self.diagnosticWindowKey) ?? "none",
                    "application-active": String(applicationIsActive),
                    "windowserver-frontmost-window": windowServerFrontmostWindow.map(String.init) ?? "none",
                    "windowserver-target-match": String(
                        windowServerFrontmostWindow == targetKey.windowIdentifier
                    ),
                    "actual-window-ignored": String(actualIsIgnored),
                    "phase": phase.rawValue,
                    "decision": String(describing: decision),
                    "display": Self.shortIdentifier(destinationDisplayIdentifier),
                ]
            )

            switch decision {
            case .succeeded:
                self.lastObservedFocusedWindow = targetKey
                self.emitVerifiedFocusHighlightTarget(
                    target,
                    correlationID: correlationID
                )
                self.diagnostics.log(
                    category: "workspace-switch-focus",
                    event: "complete",
                    correlation: correlationID,
                    fields: [
                        "window": Self.diagnosticWindowKey(targetKey),
                        "workspace": Self.shortIdentifier(workspaceID.uuidString),
                        "display": Self.shortIdentifier(destinationDisplayIdentifier),
                        "active-after": self.diagnosticActiveWorkspaceMap(),
                    ]
                )
            case .retryAppKitActivation:
                self.attemptWorkspaceSwitchFocusCandidate(
                    attemptOrder: attemptOrder,
                    candidateIndex: candidateIndex,
                    phase: .appKitActivationFallback,
                    previousFocusKey: previousFocusKey,
                    workspaceID: workspaceID,
                    destinationDisplayIdentifier: destinationDisplayIdentifier,
                    displays: displays,
                    correlationID: correlationID,
                    token: token
                )
            case .retryExactTarget:
                self.attemptWorkspaceSwitchFocusCandidate(
                    attemptOrder: attemptOrder,
                    candidateIndex: candidateIndex,
                    phase: phase.exactRetryPhase,
                    previousFocusKey: previousFocusKey,
                    workspaceID: workspaceID,
                    destinationDisplayIdentifier: destinationDisplayIdentifier,
                    displays: displays,
                    correlationID: correlationID,
                    token: token
                )
            case .advanceToNextCandidate:
                self.focusCycleRejectedUntil[targetKey] = Date().addingTimeInterval(5)
                self.attemptWorkspaceSwitchFocusCandidate(
                    attemptOrder: attemptOrder,
                    candidateIndex: candidateIndex + 1,
                    phase: .initial,
                    previousFocusKey: previousFocusKey,
                    workspaceID: workspaceID,
                    destinationDisplayIdentifier: destinationDisplayIdentifier,
                    displays: displays,
                    correlationID: correlationID,
                    token: token
                )
            case .abortForCompetingFocus:
                self.clearProgrammaticFocusIntent()
                self.recentInteractionFocusTarget = nil
                if actual == previousFocusKey {
                    self.suppressParkedPreviousFocusAfterWorkspaceSwitch(
                        previousFocusKey,
                        correlationID: correlationID,
                        reason: "previous-focus-retained-after-retry"
                    )
                }
                self.diagnostics.log(
                    category: "workspace-switch-focus",
                    event: "aborted-for-competing-focus",
                    correlation: correlationID,
                    fields: [
                        "expected-window": Self.diagnosticWindowKey(targetKey),
                        "actual-window": actual.map(Self.diagnosticWindowKey) ?? "none",
                    ]
                )
            }
        }
        pendingFocusVerification = workItem
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func suppressParkedPreviousFocusAfterWorkspaceSwitch(
        _ previousFocusKey: WindowKey?,
        correlationID: String,
        reason: String
    ) {
        guard let previousFocusKey,
              let previousWindow = windows[previousFocusKey]
        else { return }
        let rule = resolvedRule(for: previousWindow.bundleIdentifier)
        let previousWindowIsVisible = Self.shouldWindowBeVisible(
            workspaceID: previousWindow.workspaceID,
            activeWorkspaceIDs: activeWorkspaceIDs,
            rule: rule
        )
        guard WorkspaceSwitchFocusPolicy.shouldSuppressRetainedPreviousFocus(
            previousWindowIsVisible: previousWindowIsVisible
        ) else { return }

        staleParkedFocusSuppression[previousFocusKey] = Date().addingTimeInterval(1.5)
        diagnostics.log(
            category: "workspace-switch-focus",
            event: "stale-source-focus-suppression-armed",
            correlation: correlationID,
            fields: [
                "window": Self.diagnosticWindowKey(previousFocusKey),
                "reason": reason,
            ]
        )
    }

    private func attemptFocusCycleCandidate(
        attemptOrder: [WindowKey],
        candidateIndex: Int,
        phase: FocusCandidateAttemptPhase = .initial,
        originalFocus: WindowKey?,
        workspaceID: UUID,
        interactionDisplayIdentifier: String,
        displays: [DisplaySnapshot],
        correlationID: String,
        token: FocusVerificationToken
    ) {
        guard isFocusActionGenerationCurrent(token.generation) else { return }
        guard candidateIndex < attemptOrder.count else {
            diagnostics.log(
                category: "focus-cycle",
                event: "exhausted-candidates",
                correlation: correlationID,
                fields: [
                    "workspace": Self.shortIdentifier(workspaceID.uuidString),
                    "display": Self.shortIdentifier(interactionDisplayIdentifier),
                    "attempted": attemptOrder.map(Self.diagnosticWindowKey).joined(separator: ","),
                ]
            )
            if let originalFocus, let original = windows[originalFocus] {
                lastFocusedWindow[workspaceID] = originalFocus
                recentInteractionFocusTarget = originalFocus
                recentInteractionDisplayIdentifier = interactionDisplayIdentifier
                recentInteractionDisplayDeadline = Date().addingTimeInterval(1.75)
                diagnostics.log(
                    category: "focus-cycle",
                    event: "restore-original-focus",
                    correlation: correlationID,
                    fields: ["window": Self.diagnosticWindowKey(originalFocus)]
                )
                focusManagedWindow(
                    originalFocus,
                    tracked: original,
                    correlationID: correlationID,
                    token: token
                )
            }
            return
        }

        let targetKey = attemptOrder[candidateIndex]
        guard let target = windows[targetKey] else {
            attemptFocusCycleCandidate(
                attemptOrder: attemptOrder,
                candidateIndex: candidateIndex + 1,
                phase: .initial,
                originalFocus: originalFocus,
                workspaceID: workspaceID,
                interactionDisplayIdentifier: interactionDisplayIdentifier,
                displays: displays,
                correlationID: correlationID,
                token: token
            )
            return
        }

        if phase == .initial {
            currentWorkspaceID = workspaceID
            lastFocusedWindow[workspaceID] = targetKey
            recentInteractionFocusTarget = targetKey
            recentInteractionDisplayIdentifier = interactionDisplayIdentifier
            recentInteractionDisplayDeadline = Date().addingTimeInterval(1.75)
            if workspaceLayout(for: workspaceID) == .accordion {
                applyVisibleWindows(
                    windows.values.filter { $0.workspaceID == workspaceID },
                    displays: displays,
                    correlationID: correlationID
                )
            }
        }
        diagnostics.log(
            category: "focus-cycle",
            event: "candidate-attempt",
            correlation: correlationID,
            fields: [
                "window": Self.diagnosticWindowKey(targetKey),
                "candidate-index": String(candidateIndex),
                "phase": phase.rawValue,
                "display": Self.shortIdentifier(interactionDisplayIdentifier),
            ]
        )
        if phase.performsAppKitActivation {
            activateManagedApplicationWithAppKit(
                targetKey,
                tracked: target,
                correlationID: correlationID,
                token: token,
                event: "focus-cycle-observed-activation-fallback"
            )
        } else if phase == .initial {
            focusManagedWindow(
                targetKey,
                tracked: target,
                correlationID: correlationID,
                token: token,
                allowImmediateAppKitCompatibilityFallback: false
            )
            lastBackgroundLayoutSignature = backgroundLayoutSignature(displays: displays)
            persistState(preservingPendingRestores: true)
            emitState()
        } else {
            prepareProgrammaticFocusIntent(
                targetKey,
                correlationID: correlationID,
                duration: 0.65,
                generation: token.generation
            )
            applyExactWindowFocus(
                targetKey,
                tracked: target,
                correlationID: correlationID,
                event: "verified-mismatch-bounded-retry"
            )
        }

        pendingFocusVerification?.cancel()
        let delay: DispatchTimeInterval = phase.exactAttempt == 0
            ? .milliseconds(220)
            : .milliseconds(120)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.isFocusActionGenerationCurrent(token.generation)
            else { return }
            let actual = self.focusedWindowKey()
            let applicationIsActive = NSRunningApplication(
                processIdentifier: targetKey.processIdentifier
            )?.isActive == true
            let windowServerFrontmostWindow =
                AccessibilityWindow.frontmostOnScreenNormalWindowIdentifier(
                    for: targetKey.processIdentifier
                )
            let actualIsIgnored = Self.shouldIgnoreFocusObservation(
                focusedWindow: actual,
                ignoredWindowKeys: self.ignoredWindowKeys
            )
            let decision: FocusCycleVerificationDecision = actualIsIgnored
                ? .abortForCompetingFocus
                : Self.focusCycleVerificationDecision(
                    expected: targetKey,
                    actual: actual,
                    previousFocus: originalFocus,
                    applicationIsActive: applicationIsActive,
                    windowServerTargetIsFrontmostNormalWindow:
                        windowServerFrontmostWindow == targetKey.windowIdentifier,
                    appKitActivationAttempted: phase.appKitActivationAttempted,
                    exactAttempt: phase.exactAttempt,
                    maximumExactAttempts: 1
                )
            self.diagnostics.log(
                category: "focus-verification",
                event: "cycle-target-verified",
                correlation: correlationID,
                fields: [
                    "expected-window": Self.diagnosticWindowKey(targetKey),
                    "actual-window": actual.map(Self.diagnosticWindowKey) ?? "none",
                    "application-active": String(applicationIsActive),
                    "windowserver-frontmost-window": windowServerFrontmostWindow.map(String.init) ?? "none",
                    "windowserver-target-match": String(
                        windowServerFrontmostWindow == targetKey.windowIdentifier
                    ),
                    "actual-window-ignored": String(actualIsIgnored),
                    "phase": phase.rawValue,
                    "decision": String(describing: decision),
                ]
            )

            switch decision {
            case .succeeded:
                self.lastObservedFocusedWindow = targetKey
                self.emitVerifiedFocusHighlightTarget(
                    target,
                    correlationID: correlationID
                )
                self.diagnostics.log(
                    category: "focus-cycle",
                    event: "complete",
                    correlation: correlationID,
                    fields: [
                        "window": Self.diagnosticWindowKey(targetKey),
                        "active-after": self.diagnosticActiveWorkspaceMap(),
                    ]
                )
            case .retryAppKitActivation:
                self.attemptFocusCycleCandidate(
                    attemptOrder: attemptOrder,
                    candidateIndex: candidateIndex,
                    phase: .appKitActivationFallback,
                    originalFocus: originalFocus,
                    workspaceID: workspaceID,
                    interactionDisplayIdentifier: interactionDisplayIdentifier,
                    displays: displays,
                    correlationID: correlationID,
                    token: token
                )
            case .retryExactTarget:
                self.attemptFocusCycleCandidate(
                    attemptOrder: attemptOrder,
                    candidateIndex: candidateIndex,
                    phase: phase.exactRetryPhase,
                    originalFocus: originalFocus,
                    workspaceID: workspaceID,
                    interactionDisplayIdentifier: interactionDisplayIdentifier,
                    displays: displays,
                    correlationID: correlationID,
                    token: token
                )
            case .advanceToNextCandidate:
                self.focusCycleRejectedUntil[targetKey] = Date().addingTimeInterval(5)
                self.diagnostics.log(
                    category: "focus-cycle",
                    event: "candidate-rejected-after-verification",
                    correlation: correlationID,
                    fields: [
                        "window": Self.diagnosticWindowKey(targetKey),
                        "reason": "exact-window-did-not-become-focused",
                        "next-candidate-index": String(candidateIndex + 1),
                    ]
                )
                self.attemptFocusCycleCandidate(
                    attemptOrder: attemptOrder,
                    candidateIndex: candidateIndex + 1,
                    phase: .initial,
                    originalFocus: originalFocus,
                    workspaceID: workspaceID,
                    interactionDisplayIdentifier: interactionDisplayIdentifier,
                    displays: displays,
                    correlationID: correlationID,
                    token: token
                )
            case .abortForCompetingFocus:
                self.clearProgrammaticFocusIntent()
                self.recentInteractionFocusTarget = nil
                self.recentInteractionDisplayIdentifier = nil
                self.recentInteractionDisplayDeadline = .distantPast
                self.diagnostics.log(
                    category: "focus-cycle",
                    event: "aborted-for-competing-focus",
                    correlation: correlationID,
                    fields: [
                        "expected-window": Self.diagnosticWindowKey(targetKey),
                        "actual-window": actual.map(Self.diagnosticWindowKey) ?? "none",
                    ]
                )
            }
        }
        pendingFocusVerification = workItem
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func focusTargetWindow(_ key: WindowKey) -> TrackedWindow? {
        if let tracked = windows[key] { return tracked }
        guard let session = fullscreenSessions[key] else { return nil }
        let fallbackFrame = session.frame ?? WindowFrame(position: .zero, size: CGSize(width: 1, height: 1))
        return TrackedWindow(
            key: key,
            element: session.element,
            processIdentifier: session.processIdentifier,
            bundleIdentifier: session.bundleIdentifier,
            workspaceID: session.workspaceID,
            restoreFrame: fallbackFrame,
            displayPlacement: nil,
            layoutOverride: .automatic,
            workspaceRuleOverrideActive: false,
            admissionDecision: WindowAdmissionDecision(
                disposition: .temporarilyIneligible,
                reason: .fullscreen
            ),
            layoutOrder: 0,
            layoutWeight: 1
        )
    }

    private func focusManagedWindow(
        _ key: WindowKey,
        tracked: TrackedWindow,
        correlationID: String? = nil,
        token: FocusVerificationToken? = nil,
        allowImmediateAppKitCompatibilityFallback: Bool = true
    ) {
        guard !isExcludedFromWorkspaceParticipation(tracked) else {
            diagnostics.log(
                category: "focus-action",
                event: "skipped",
                correlation: correlationID,
                fields: [
                    "window": Self.diagnosticWindowKey(key),
                    "reason": "application-hidden-externally",
                ]
            )
            return
        }
        prepareProgrammaticFocusIntent(
            key,
            correlationID: correlationID,
            duration: 1.25,
            generation: token?.generation
        )
        let application = NSRunningApplication(processIdentifier: key.processIdentifier)
        let isActive = application?.isActive == true
        let now = Date()
        let unhideDecision = ApplicationUnhidePolicy.decision(
            enabled: automaticallyUnhideApplications,
            isHidden: application?.isHidden == true,
            lastAttempt: lastAutomaticUnhideAttemptByProcess[key.processIdentifier],
            now: now
        )
        if unhideDecision == .attempt {
            lastAutomaticUnhideAttemptByProcess[key.processIdentifier] = now
        }
        let plan = Self.exactWindowFocusPlan(applicationIsActive: isActive)
        diagnostics.log(
            category: "focus-action",
            event: "plan",
            correlation: correlationID,
            fields: [
                "window": Self.diagnosticWindowKey(key),
                "application-active": String(isActive),
                "automatic-unhide": unhideDecision.rawValue,
                "steps": plan.map { String(describing: $0) }.joined(separator: ","),
            ]
        )

        if isActive || application == nil {
            if unhideDecision == .attempt, let application {
                DispatchQueue.main.async { [weak self, weak application] in
                    let success = application?.unhide() == true
                    self?.diagnostics.log(
                        category: "application-visibility",
                        event: "automatic-unhide",
                        correlation: correlationID,
                        fields: [
                            "process": String(key.processIdentifier),
                            "success": String(success),
                            "activation-needed": "false",
                        ]
                    )
                }
            }
            applyExactWindowFocus(
                key,
                tracked: tracked,
                correlationID: correlationID,
                event: isActive ? "active-app-exact-focus" : "missing-app-exact-focus"
            )
            return
        }

        // Making an application frontmost chooses an application, not a specific window. Prepare
        // and raise the exact target first, then use the public application-level AXFrontmost
        // attribute. Candidate-verification callers disable the immediate compatibility fallback
        // and may request AppKit activation once only after observing that the app stayed inactive.
        // One-shot callers without candidate advancement retain the AX-error fallback. Reassert the
        // exact target from the activation notification so another same-app window cannot win.
        applyExactWindowFocus(
            key,
            tracked: tracked,
            correlationID: correlationID,
            event: "pre-activation-exact-focus"
        )

        DispatchQueue.main.async { [weak self, weak application] in
            if let generation = token?.generation,
               self?.isFocusActionGenerationCurrent(generation) != true {
                self?.diagnostics.log(
                    category: "focus-action",
                    event: "application-activation-superseded",
                    correlation: correlationID,
                    fields: [
                        "window": Self.diagnosticWindowKey(key),
                        "generation": String(generation),
                    ]
                )
                return
            }
            let unhidden = unhideDecision == .attempt ? application?.unhide() == true : false
            let applicationElement = AXUIElementCreateApplication(key.processIdentifier)
            let accessibilityFrontmostResult = AXUIElementSetAttributeValue(
                applicationElement,
                kAXFrontmostAttribute as CFString,
                true as CFTypeRef
            )
            let appKitFallbackAttempted = allowImmediateAppKitCompatibilityFallback &&
                Self.shouldUseAppKitActivationFallback(
                    accessibilityFrontmostResult: accessibilityFrontmostResult
                )
            let appKitFallbackSucceeded = appKitFallbackAttempted
                ? application?.activate() == true
                : false
            let requestAccepted = accessibilityFrontmostResult == .success || appKitFallbackSucceeded
            self?.diagnostics.log(
                category: "focus-action",
                event: "application-activation-requested",
                correlation: correlationID,
                fields: [
                    "window": Self.diagnosticWindowKey(key),
                    "request-accepted": String(requestAccepted),
                    "automatic-unhide": unhideDecision.rawValue,
                    "unhide-success": String(unhidden),
                    "accessibility-frontmost-result": String(accessibilityFrontmostResult.rawValue),
                    "immediate-appkit-compatibility-fallback-allowed": String(
                        allowImmediateAppKitCompatibilityFallback
                    ),
                    "appkit-fallback-attempted": String(appKitFallbackAttempted),
                    "appkit-fallback-success": String(appKitFallbackSucceeded),
                    "activation-outcome": "pending-observation",
                    "ordering": "exact-window-before-frontmost-then-reassert",
                ]
            )
        }
    }

    private func activateManagedApplicationWithAppKit(
        _ key: WindowKey,
        tracked: TrackedWindow,
        correlationID: String?,
        token: FocusVerificationToken,
        event: String
    ) {
        prepareProgrammaticFocusIntent(
            key,
            correlationID: correlationID,
            duration: 1.25,
            generation: token.generation
        )
        applyExactWindowFocus(
            key,
            tracked: tracked,
            correlationID: correlationID,
            event: "\(event)-exact-window"
        )
        let application = NSRunningApplication(processIdentifier: key.processIdentifier)
        DispatchQueue.main.async { [weak self, weak application] in
            guard let self, self.isFocusActionGenerationCurrent(token.generation) else { return }
            guard application?.isActive != true else {
                self.diagnostics.log(
                    category: "focus-action",
                    event: event,
                    correlation: correlationID,
                    fields: [
                        "window": Self.diagnosticWindowKey(key),
                        "result": "skipped-already-active",
                    ]
                )
                return
            }
            let requestAccepted = application?.activate() == true
            self.diagnostics.log(
                category: "focus-action",
                event: event,
                correlation: correlationID,
                fields: [
                    "window": Self.diagnosticWindowKey(key),
                    "request-accepted": String(requestAccepted),
                    "activation-outcome": "pending-observation",
                ]
            )
        }
    }

    private func prepareProgrammaticFocusIntent(
        _ key: WindowKey,
        correlationID: String?,
        duration: TimeInterval,
        generation: UInt64? = nil
    ) {
        programmaticFocusTarget = key
        programmaticFocusDeadline = Date().addingTimeInterval(duration)
        programmaticFocusCorrelationID = correlationID
        programmaticFocusGeneration = generation
    }

    private func applyExactWindowFocus(
        _ key: WindowKey,
        tracked: TrackedWindow,
        correlationID: String?,
        event: String
    ) {
        let applicationElement = AXUIElementCreateApplication(key.processIdentifier)
        let capabilities = AccessibilityWindow.focusCapabilities(
            of: tracked.element,
            processIdentifier: tracked.processIdentifier,
            windowIdentifier: key.windowIdentifier
        )
        let mainResult: AXError? = capabilities.mainAttributeSettable
            ? AXUIElementSetAttributeValue(
                tracked.element,
                kAXMainAttribute as CFString,
                true as CFTypeRef
            )
            : nil
        let elementFocusResult: AXError? = capabilities.focusedAttributeSettable
            ? AXUIElementSetAttributeValue(
                tracked.element,
                kAXFocusedAttribute as CFString,
                true as CFTypeRef
            )
            : nil
        let applicationFocusResult: AXError? = capabilities.applicationFocusedWindowAttributeSettable
            ? AXUIElementSetAttributeValue(
                applicationElement,
                kAXFocusedWindowAttribute as CFString,
                tracked.element
            )
            : nil
        let raiseResult = AXUIElementPerformAction(tracked.element, kAXRaiseAction as CFString)
        diagnostics.log(
            category: "focus-action",
            event: event,
            correlation: correlationID,
            fields: [
                "window": Self.diagnosticWindowKey(key),
                "workspace": Self.shortIdentifier(tracked.workspaceID.uuidString),
                "ax-role": capabilities.role ?? "unknown",
                "ax-subrole": capabilities.subrole ?? "unknown",
                "window-layer": capabilities.windowLayer.map(String.init) ?? "unknown",
                "was-focused": capabilities.isFocused.map(String.init) ?? "unknown",
                "was-main": capabilities.isMain.map(String.init) ?? "unknown",
                "main-settable": String(capabilities.mainAttributeSettable),
                "focused-settable": String(capabilities.focusedAttributeSettable),
                "app-focused-window-settable": String(capabilities.applicationFocusedWindowAttributeSettable),
                "raise-supported": String(capabilities.raiseActionSupported),
                "main-result": mainResult.map { String($0.rawValue) } ?? "unsupported",
                "element-focus-result": elementFocusResult.map { String($0.rawValue) } ?? "unsupported",
                "application-focus-result": applicationFocusResult.map { String($0.rawValue) } ?? "unsupported",
                "raise-result": String(raiseResult.rawValue),
            ]
        )
    }

    private func verifyFocusAfterAction(
        expected: WindowKey?,
        correlationID: String,
        action: String,
        token: FocusVerificationToken,
        mayRecoverNilFocus: Bool,
        delay: DispatchTimeInterval = .milliseconds(180)
    ) {
        pendingFocusVerification?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.isFocusActionGenerationCurrent(token.generation)
            else { return }
            let actual = self.focusedWindowKey()
            let applicationIsActive = expected.flatMap {
                NSRunningApplication(processIdentifier: $0.processIdentifier)?.isActive
            } == true
            if mayRecoverNilFocus,
               Self.shouldRecoverNilFocus(
                    hasExpectedWindow: expected != nil,
                    hasActualWindow: actual != nil,
                    applicationIsActive: applicationIsActive,
                    verificationIsCurrent: true
               ),
               let expected,
               let tracked = self.windows[expected] {
                self.diagnostics.log(
                    category: "focus-verification",
                    event: "nil-focus-recovery",
                    correlation: correlationID,
                    fields: [
                        "action": action,
                        "expected-window": Self.diagnosticWindowKey(expected),
                        "reason": "active-app-lost-focus-after-our-action",
                    ]
                )
                self.programmaticFocusTarget = expected
                self.programmaticFocusDeadline = Date().addingTimeInterval(0.6)
                self.programmaticFocusCorrelationID = correlationID
                self.programmaticFocusGeneration = token.generation
                self.applyExactWindowFocus(
                    expected,
                    tracked: tracked,
                    correlationID: correlationID,
                    event: "nil-focus-reasserted"
                )
                self.verifyFocusAfterAction(
                    expected: expected,
                    correlationID: correlationID,
                    action: action,
                    token: token,
                    mayRecoverNilFocus: false,
                    delay: .milliseconds(140)
                )
                return
            }
            let changed = expected != nil && actual != expected
            self.diagnostics.log(
                category: "focus-verification",
                event: changed ? "unexpected-focus-change" : "focus-stable",
                correlation: correlationID,
                fields: [
                    "action": action,
                    "expected-window": expected.map(Self.diagnosticWindowKey) ?? "none",
                    "actual-window": actual.map(Self.diagnosticWindowKey) ?? "none",
                ]
            )
        }
        pendingFocusVerification = workItem
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func retainFocusAfterKeyboardManipulation(
        expected: WindowKey,
        correlationID: String,
        action: String,
        token: FocusVerificationToken
    ) {
        guard isFocusActionGenerationCurrent(token.generation),
              let tracked = windows[expected]
        else { return }

        let applicationIsActive = NSRunningApplication(
            processIdentifier: expected.processIdentifier
        )?.isActive == true
        diagnostics.log(
            category: "keyboard-manipulation-focus",
            event: applicationIsActive ? "post-layout-reassert" : "post-layout-reassert-skipped",
            correlation: correlationID,
            fields: [
                "action": action,
                "expected-window": Self.diagnosticWindowKey(expected),
                "application-active": String(applicationIsActive),
                "generation": String(token.generation),
            ]
        )
        guard applicationIsActive else {
            if programmaticFocusGeneration == token.generation {
                clearProgrammaticFocusIntent()
            }
            return
        }

        // AX frame writes can make a sibling window main/focused even though the keyboard command
        // started from this exact window. Reassert after the synchronous geometry writes without
        // activating an application, then verify once after AppKit/AX has settled.
        prepareProgrammaticFocusIntent(
            expected,
            correlationID: correlationID,
            duration: 0.75,
            generation: token.generation
        )
        applyExactWindowFocus(
            expected,
            tracked: tracked,
            correlationID: correlationID,
            event: "keyboard-manipulation-post-layout-exact-focus"
        )
        verifyKeyboardManipulationFocus(
            expected: expected,
            correlationID: correlationID,
            action: action,
            token: token,
            recoveryAttempt: 0
        )
    }

    private func verifyKeyboardManipulationFocus(
        expected: WindowKey,
        correlationID: String,
        action: String,
        token: FocusVerificationToken,
        recoveryAttempt: Int,
        delay: DispatchTimeInterval = .milliseconds(120)
    ) {
        pendingFocusVerification?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.isFocusActionGenerationCurrent(token.generation)
            else { return }

            let actual = self.focusedWindowKey()
            let applicationIsActive = NSRunningApplication(
                processIdentifier: expected.processIdentifier
            )?.isActive == true
            let actualIsIgnored = Self.shouldIgnoreFocusObservation(
                focusedWindow: actual,
                ignoredWindowKeys: self.ignoredWindowKeys
            )
            let decision = Self.keyboardManipulationFocusDecision(
                expected: expected,
                actual: actual,
                actualIsIgnored: actualIsIgnored,
                expectedApplicationIsActive: applicationIsActive,
                recoveryAttempt: recoveryAttempt
            )
            self.diagnostics.log(
                category: "keyboard-manipulation-focus",
                event: "verified",
                correlation: correlationID,
                fields: [
                    "action": action,
                    "expected-window": Self.diagnosticWindowKey(expected),
                    "actual-window": actual.map(Self.diagnosticWindowKey) ?? "none",
                    "application-active": String(applicationIsActive),
                    "actual-window-ignored": String(actualIsIgnored),
                    "recovery-attempt": String(recoveryAttempt),
                    "decision": decision.rawValue,
                    "generation": String(token.generation),
                ]
            )

            switch decision {
            case .stable:
                if self.programmaticFocusGeneration == token.generation {
                    self.clearProgrammaticFocusIntent()
                }
            case .reassertExactTarget:
                guard let tracked = self.windows[expected] else {
                    self.diagnostics.log(
                        category: "keyboard-manipulation-focus",
                        event: "reassert-skipped",
                        correlation: correlationID,
                        fields: [
                            "action": action,
                            "expected-window": Self.diagnosticWindowKey(expected),
                            "reason": "target-no-longer-managed",
                        ]
                    )
                    if self.programmaticFocusGeneration == token.generation {
                        self.clearProgrammaticFocusIntent()
                    }
                    return
                }
                self.prepareProgrammaticFocusIntent(
                    expected,
                    correlationID: correlationID,
                    duration: 0.6,
                    generation: token.generation
                )
                self.applyExactWindowFocus(
                    expected,
                    tracked: tracked,
                    correlationID: correlationID,
                    event: "keyboard-manipulation-bounded-exact-retry"
                )
                self.verifyKeyboardManipulationFocus(
                    expected: expected,
                    correlationID: correlationID,
                    action: action,
                    token: token,
                    recoveryAttempt: recoveryAttempt + 1,
                    delay: .milliseconds(140)
                )
            case .failedAfterRetry, .abortForCompetingFocus:
                if self.programmaticFocusGeneration == token.generation {
                    self.clearProgrammaticFocusIntent()
                }
            }
        }
        pendingFocusVerification = workItem
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func logSessionHeader() {
        guard diagnostics.isVerbose else { return }
        let displays = Self.activeDisplays()
        diagnostics.log(
            category: "session",
            event: "started",
            fields: [
                "build": diagnostics.buildMode.rawValue,
                "process": String(ownProcessIdentifier),
                "display-mode": displayMode.rawValue,
                "current-workspace": Self.shortIdentifier(currentWorkspaceID.uuidString),
                "active-workspaces": diagnosticActiveWorkspaceMap(),
                "focus-following": "enabled",
                "focus-follows-moved-window": String(focusFollowsMovedWindow),
                "automatically-unhide-applications": String(automaticallyUnhideApplications),
                "workspace-count": String(workspaces.count),
                "display-count": String(displays.count),
                "displays-have-separate-spaces": Self.displaysHaveSeparateSpacesDiagnosticValue(
                    NSScreen.screensHaveSeparateSpaces
                ),
            ]
        )
        for display in displays {
            diagnostics.log(
                category: "session",
                event: "display-topology",
                fields: [
                    "display": Self.shortIdentifier(display.identifier),
                    "main": String(display.isMain),
                    "bounds": Self.diagnosticRect(display.bounds),
                    "usable-bounds": Self.diagnosticRect(display.usableBounds),
                ]
            )
        }
        for workspace in workspaces {
            diagnostics.log(
                category: "session",
                event: "workspace-settings",
                fields: [
                    "workspace": Self.shortIdentifier(workspace.id.uuidString),
                    "workspace-name": workspace.name,
                    "layout": workspace.layout.rawValue,
                    "layout-geometry": workspace.layoutConfiguration == nil ? "legacy" : "v1",
                    "layout-orientation": workspace.layoutConfiguration?.orientation.rawValue ?? "legacy-automatic",
                    "accordion-padding": workspace.layoutConfiguration.map { String($0.accordionPadding) } ?? "legacy-250",
                    "home-display": Self.shortIdentifier(
                        workspaceHomeDisplayIdentifier(for: workspace.id, displays: displays)
                    ),
                ]
            )
        }
    }

    static func displaysHaveSeparateSpacesDiagnosticValue(_ enabled: Bool) -> String {
        String(enabled)
    }

    private func diagnosticActiveWorkspaceMap() -> String {
        if displayMode == .unified {
            return "all:\(Self.shortIdentifier(currentWorkspaceID.uuidString))"
        }
        return activeWorkspaceIDByDisplay
            .map { "\(Self.shortIdentifier($0.key)):\(Self.shortIdentifier($0.value.uuidString))" }
            .sorted()
            .joined(separator: ",")
    }

    private static func shortIdentifier(_ value: String) -> String {
        guard value.count > 16 else { return value }
        return "\(value.prefix(6))-\(value.suffix(6))"
    }

    private static func diagnosticWindowKey(_ key: WindowKey) -> String {
        "\(key.processIdentifier):\(key.windowIdentifier)"
    }

    private static func diagnosticPoint(_ point: CGPoint) -> String {
        String(format: "%.1f,%.1f", point.x, point.y)
    }

    private static func diagnosticFrame(_ frame: WindowFrame) -> String {
        "\(diagnosticPoint(frame.position));\(String(format: "%.1fx%.1f", frame.size.width, frame.size.height))"
    }

    private static func diagnosticRect(_ rect: CGRect) -> String {
        String(
            format: "%.1f,%.1f;%.1fx%.1f",
            rect.minX,
            rect.minY,
            rect.width,
            rect.height
        )
    }

    private func emitState(force: Bool = true) {
        let windowCountByWorkspace = Dictionary(grouping: windows.values, by: \.workspaceID)
            .mapValues(\.count)
        let layoutByWorkspace = Dictionary(
            uniqueKeysWithValues: workspaces.map { ($0.id, $0.layout) }
        )
        let highlightContexts = Dictionary(uniqueKeysWithValues: windows.values.compactMap {
            tracked -> (WindowKey, FocusedWindowHighlightWorkspaceContext)? in
            guard let layout = layoutByWorkspace[tracked.workspaceID] else { return nil }
            return (
                tracked.key,
                FocusedWindowHighlightWorkspaceContext(
                    layout: layout,
                    windowCount: windowCountByWorkspace[tracked.workspaceID] ?? 0
                )
            )
        })
        let state = WorkspaceEngineState(
            currentWorkspaceID: currentWorkspaceID,
            activeWorkspaceIDs: activeWorkspaceIDs,
            previousWorkspaceID: previousWorkspaceID,
            managedWindowCount: windows.count,
            accessibilityGranted: AXIsProcessTrusted(),
            profileID: currentProfileID,
            activeWorkspaceIDByDisplay: displayMode == .independent
                ? activeWorkspaceIDByDisplay : [:],
            focusedWindowHighlightWorkspaceContexts: highlightContexts
        )
        guard stateEmissionGate.shouldSchedule(state, force: force) else { return }
        DispatchQueue.main.async { [weak self] in self?.onStateChanged?(state) }
    }

    private func emitFloatingToggleResult(_ result: FloatingToggleResult) {
        emitCommandFeedback(result.commandFeedbackMessage)
    }

    private func emitVerifiedFocusHighlightTarget(
        _ window: TrackedWindow,
        correlationID: String
    ) {
        guard focusedWindowHighlightEnabled,
              let frame = AccessibilityWindow.frame(of: window.element)
        else { return }
        let target = FocusedWindowHighlightTarget(
            key: window.key,
            frame: frame,
            fullscreenObservation: AccessibilityWindow.fullscreenObservation(of: window.element),
            bundleIdentifier: window.bundleIdentifier,
            observationSource: .verifiedFocusTransaction
        )
        diagnostics.log(
            category: "focused-window-highlight",
            event: "verified-target-forwarded",
            correlation: correlationID,
            fields: ["window": Self.diagnosticWindowKey(window.key)]
        )
        DispatchQueue.main.async { [weak self] in self?.onVerifiedFocusTarget?(target) }
    }

    private func emitCommandFeedback(
        _ message: String,
        correlationID: String? = nil,
        preferredDisplayIdentifier: String? = nil
    ) {
        let displays = Self.activeDisplays()
        let recentDisplay = Date() < recentInteractionDisplayDeadline
            ? recentInteractionDisplayIdentifier
            : nil
        let resolvedDisplay = preferredDisplayIdentifier
            ?? recentDisplay.flatMap { recent in
                displays.contains(where: { $0.identifier == recent }) ? recent : nil
            }
            ?? interactionDisplayResolution(
                focused: interactionFocusedWindowSnapshot(),
                displays: displays
            ).identifier
        let request = CommandFeedbackRequest(
            message: message,
            preferredDisplayIdentifier: resolvedDisplay,
            correlationID: correlationID ?? programmaticFocusCorrelationID
        )
        DispatchQueue.main.async { [weak self] in self?.onCommandFeedback?(request) }
    }
}
