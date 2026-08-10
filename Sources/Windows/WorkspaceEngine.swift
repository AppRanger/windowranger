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
    case activateApplication
    case raiseWindow
}

enum FocusCycleVerificationDecision: Equatable, Sendable {
    case succeeded
    case retryExactTarget
    case advanceToNextCandidate
    case abortForCompetingFocus
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

    var changedManagedState: Bool {
        removedTrackedWindow || removedPendingAssignment || !clearedLastFocusedWorkspaceIDs.isEmpty
    }
}

struct WindowRefreshReport: Equatable, Sendable {
    let displays: [DisplaySnapshot]
    let topologySignature: String
    let requiredProcessIdentifiers: Set<pid_t>
    let successfullyEnumeratedProcessIdentifiers: Set<pid_t>
    let writeEligibleWindowKeys: Set<WindowKey>
    let deferredWindowKeys: Set<WindowKey>
    let managedWindowCount: Int
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
}

/// Pure lifecycle rules for AX window snapshots. A successful `AXWindows` read is authoritative
/// for that process, so a missing window (including an inactive native tab that has closed) is
/// removed. An incomplete/failed read is not evidence of closure and retains prior state.
enum WindowEnumerationLifecycle {
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
}

enum FloatingToggleResult: Equatable, Sendable {
    case enabled
    case disabled
    case blockedByAppRule(String)

    var commandFeedbackMessage: String {
        switch self {
        case .enabled:
            "Window is floating"
        case .disabled:
            "Window returned to the workspace layout"
        case let .blockedByAppRule(appName):
            "\(appName) is excluded by an App Rule. That rule remains in control."
        }
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

    init(
        version: Int,
        windowServerSession: String,
        activeWorkspaceID: UUID,
        windows: [String: PersistedWindowAssignment],
        activeWorkspaceIDsByDisplay: [String: UUID]? = nil,
        profileID: UUID? = nil,
        tiledTrees: [PersistedTiledTree]? = nil
    ) {
        self.version = version
        self.windowServerSession = windowServerSession
        self.activeWorkspaceID = activeWorkspaceID
        self.windows = windows
        self.activeWorkspaceIDsByDisplay = activeWorkspaceIDsByDisplay
        self.profileID = profileID
        self.tiledTrees = tiledTrees
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

    private let writeQueue = DispatchQueue(label: "com.windowranger.WindowRanger.workspace-state")
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
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return caches
            .appendingPathComponent("com.windowranger.WindowRanger", isDirectory: true)
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

struct WindowAdmissionSupportRecord: Identifiable, Equatable, Sendable {
    let id: String
    let bundleIdentifier: String
    let disposition: String
    let reason: String
    let role: String
    let subrole: String
    let windowLayer: String
}

final class WorkspaceEngine {
    var onStateChanged: ((WorkspaceEngineState) -> Void)?
    var onWorkspaceLayoutChanged: ((UUID, WorkspaceLayout) -> Void)?
    var onWorkspaceLayoutConfigurationChanged: ((UUID, WorkspaceLayoutConfiguration) -> Void)?
    var onTiledPlacementCommitted: ((TiledPlacementUndoTransaction) -> Void)?
    var onCommandFeedback: ((CommandFeedbackRequest) -> Void)?
    var onWorkspaceDisplayAssignmentsChanged: (([UUID: String]) -> Void)?
    var onFullscreenGameSessionChanged: ((FullscreenGameSessionSnapshot?) -> Void)?

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

    private struct FullscreenWindowSession {
        let key: WindowKey
        var element: AXUIElement
        var processIdentifier: pid_t
        var bundleIdentifier: String?
        var workspaceID: UUID
        var displayIdentifier: String
        var frame: WindowFrame?
        var isDeclaredGame: Bool
        let enteredAt: Date
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
        let candidateTarget: WindowKey?
    }

    private enum ManualTiledMoveReconciliation: Equatable {
        case none
        case dragInProgress
        case swapped
    }

    private let queue = DispatchQueue(label: "com.windowranger.WindowRanger.workspace-engine", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var workspaces: [WorkspaceDefinition]
    private var currentProfileID: UUID?
    private var currentWorkspaceID: UUID
    private var previousWorkspaceID: UUID?
    private var previousWorkspaceIDByDisplay: [String: UUID] = [:]
    private var activeWorkspaceIDByDisplay: [String: UUID]
    private var displayMode: MultiDisplayMode
    private var workspaceDisplayAssignments: [UUID: String]
    private var appRulesByBundleIdentifier: [String: AppRule]
    private var focusFollowsMovedWindow: Bool
    private var automaticallyUnhideApplications: Bool
    private var focusedWindowHighlightEnabled: Bool
    private var lastDisplays: [DisplaySnapshot] = []
    private var windows: [WindowKey: TrackedWindow] = [:]
    private var tiledTrees: [TiledLayoutPartitionKey: TiledNode]
    private var radialPlacementCommitContext: TiledPlacementCommitContext? = nil
    private var directionalMoveGestureContext: DirectionalMoveGestureContext? = nil
    private var manualTiledDragSession: ManualTiledDragSession? = nil
    private var ignoredWindowKeys = Set<WindowKey>()
    private var admissionDecisionByWindow: [WindowKey: WindowAdmissionDecision] = [:]
    private var admissionMetadataByWindow: [WindowKey: WindowAdmissionMetadata] = [:]
    private var lastKnownWindowLayer: [WindowKey: Int] = [:]
    private var lastFocusedWindow: [UUID: WindowKey] = [:]
    private var lastObservedFocusedWindow: WindowKey?
    private var lastDiagnosticFocusedWindow: FocusedWindowSnapshot?
    private var programmaticFocusTarget: WindowKey?
    private var programmaticFocusDeadline = Date.distantPast
    private var programmaticFocusCorrelationID: String?
    private var programmaticFocusGeneration: UInt64?
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
    private var fullscreenSessions: [WindowKey: FullscreenWindowSession] = [:]
    private var fullscreenAuthoritativeFalseCounts: [WindowKey: Int] = [:]
    private var foregroundFullscreenGameSessionKey: WindowKey?
    private var lastEmittedFullscreenGameSession: FullscreenGameSessionSnapshot?
    private var declaredGameByBundleIdentifier: [String: Bool] = [:]
    private var lastBroadWindowRefreshDate = Date.distantPast
    private var wakeReconciliationState = WakeReconciliationState()
    private var wakeReconciliationWorkItem: DispatchWorkItem?
    private var wakeAttemptIndex = 0
    private var wakePreviousTopologySignature: String?
    private var wakeReceivedAdditionalSignal = false
    private var preSleepFocusContext: SleepFocusContext?
    private var lastWakeCompletionDate = Date.distantPast
    private var lastWakeCompletedTopologySignature: String?
    private let stateStore: WorkspaceStateStore
    private let diagnostics: DiagnosticLogger
    private var windowServerSessionValidated = true
    private var pendingRestoredWindows: [String: PersistedWindowAssignment]
    private let startupGraceDeadline = Date().addingTimeInterval(30)
    private let ownProcessIdentifier = ProcessInfo.processInfo.processIdentifier

    init(
        workspaces: [WorkspaceDefinition],
        profileID: UUID? = nil,
        displayMode: MultiDisplayMode = .unified,
        workspaceDisplayAssignments: [UUID: String] = [:],
        appRules: [AppRule] = [],
        focusFollowsMovedWindow: Bool = false,
        automaticallyUnhideApplications: Bool = false,
        focusedWindowHighlightEnabled: Bool = false,
        stateStore: WorkspaceStateStore = WorkspaceStateStore(),
        diagnostics: DiagnosticLogger = .disabled
    ) {
        let initial = workspaces.isEmpty ? WorkspaceDefinition.defaults : workspaces
        self.workspaces = initial
        currentProfileID = profileID
        self.displayMode = displayMode
        self.workspaceDisplayAssignments = workspaceDisplayAssignments
        appRulesByBundleIdentifier = Self.indexedAppRules(appRules)
        self.focusFollowsMovedWindow = focusFollowsMovedWindow
        self.automaticallyUnhideApplications = automaticallyUnhideApplications
        self.focusedWindowHighlightEnabled = focusedWindowHighlightEnabled
        self.stateStore = stateStore
        self.diagnostics = diagnostics
        let restoredState = stateStore.load()
        let restoredProfileMatches = restoredState.map {
            Self.persistedStateProfileMatches(
                persistedProfileID: $0.profileID,
                currentProfileID: profileID
            )
        } ?? false
        pendingRestoredWindows = restoredProfileMatches ? (restoredState?.windows ?? [:]) : [:]
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
                self.refreshWindows(followExternalFocus: true)
                self.persistState(preservingPendingRestores: Date() < self.startupGraceDeadline)
                self.emitState()
            }
            self.timer = timer
            timer.resume()
        }
    }

    /// Captures only durable intent before sleep and invalidates every delayed focus/layout action.
    /// NSWorkspace posts this on its own notification center before the machine sleeps, so the
    /// synchronous queue hand-off gives persistence a bounded opportunity to finish.
    func prepareForSystemSleep() {
        queue.sync {
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

    /// Starts, or joins, a bounded wake reconciliation. Display identities are supplied only after
    /// SettingsStore has refreshed its portable monitor pins on the main actor.
    func requestWakeReconciliation(
        source: WakeReconciliationSource,
        workspaceDisplayAssignments: [UUID: String]
    ) {
        queue.async { [weak self] in
            guard let self else { return }
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
            timer?.cancel()
            timer = nil
            wakeReconciliationWorkItem?.cancel()
            wakeReconciliationWorkItem = nil
            directionalMoveGestureContext = nil
            manualTiledDragSession = nil
            // Preserve workspace membership and original frames before the safety escape hatch
            // places every managed window on the main display.
            persistState(preservingPendingRestores: true, waitForCompletion: true)
            restoreManagedWindowsForQuit()
        }
    }

    func updateWorkspaces(_ definitions: [WorkspaceDefinition]) {
        guard !definitions.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
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
        case .ignoredTransientPopup, .temporarilyIneligible:
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
            self.applyVisibility(displays: Self.activeDisplays())
            self.persistState(preservingPendingRestores: true)
            self.emitState()
        }
    }

    func admissionSupportSnapshot(
        completion: @escaping ([WindowAdmissionSupportRecord]) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }
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
            session: Self.shortIdentifier(WorkspaceStateStore.currentWindowServerSession())
        )

        guard AXIsProcessTrusted() else {
            return FocusedWindowDiagnosticReport.render(FocusedWindowDiagnosticSnapshot(
                timestamp: base.timestamp,
                appVersion: base.appVersion,
                appBuild: base.appBuild,
                buildMode: base.buildMode,
                macOSVersion: base.macOSVersion,
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
        } else if ignoredWindowKeys.contains(key) || cachedDecision?.disposition == .ignoredTransientPopup {
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

    func switchToWorkspace(_ id: UUID, correlationID: String? = nil) {
        let correlationID = correlationID ?? diagnostics.makeCorrelationID()
        queue.async { [weak self] in
            guard let self,
                  self.workspaces.contains(where: { $0.id == id })
            else { return }

            let rawFocusedBefore = self.focusedWindowSnapshot()
            self.refreshWindows(correlationID: correlationID)
            let displays = Self.activeDisplays()
            let interactionDisplay = self.interactionDisplayResolution(
                focused: self.interactionFocusedWindowSnapshot(rawFocusedBefore),
                displays: displays
            )
            if self.displayMode == .independent {
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
                reason: "unified-interaction-display"
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

    func switchToPreviousWorkspace(correlationID: String? = nil) {
        let correlationID = correlationID ?? diagnostics.makeCorrelationID()
        queue.async { [weak self] in
            guard let self else { return }
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
                exactAttempt: 0,
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
            let order = Self.directionalCandidateOrder(
                from: CGRect(origin: sourceFrame.position, size: sourceFrame.size),
                direction: direction,
                candidates: candidates.filter { $0.key != focused.key }
            )
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
                    "workspace": Self.shortIdentifier(workspaceID.uuidString),
                    "display": Self.shortIdentifier(interactionDisplay.identifier),
                ]
            )
            self.attemptFocusCycleCandidate(
                attemptOrder: order,
                candidateIndex: 0,
                exactAttempt: 0,
                originalFocus: focused.key,
                workspaceID: workspaceID,
                interactionDisplayIdentifier: interactionDisplay.identifier,
                displays: displays,
                correlationID: correlationID,
                token: token
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

    func applicationActivated(processIdentifier: pid_t) {
        queue.async { [weak self] in
            guard let self else { return }
            self.noteApplicationActivation(processIdentifier: processIdentifier)
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
            let intendedTarget = self.programmaticFocusTarget
            let intendedCorrelationID = self.programmaticFocusCorrelationID
            let intendedGeneration = self.programmaticFocusGeneration
            let intendedTargetIsCurrent = Date() < self.programmaticFocusDeadline &&
                (intendedGeneration.map(self.isFocusActionGenerationCurrent) ?? true)
            self.refreshWindows()

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
                    exactAttempt: 0,
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
                        exactAttempt: 0,
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
        candidates: [DirectionalWindowCandidate<Key>]
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
            if lhs.2 != rhs.2 { return lhs.2 < rhs.2 }
            if lhs.3 != rhs.3 { return lhs.3 < rhs.3 }
            return lhs.4 < rhs.4
        }.map(\.0)
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

    /// Holds a position-only tiled drag in place while the pointer button is down, then swaps the
    /// focused leaf with the tile under the release point. Returning true tells the refresh loop
    /// not to run its normal corrective layout pass during the active drag.
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
                  expectedFrames: expectedFrames
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
            candidateTarget: drag.swapTarget
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
                        "target": drag.swapTarget.map(Self.diagnosticWindowKey) ?? "none",
                    ]
                )
            }
            manualTiledDragSession = session
            return .dragInProgress
        }

        let priorSession = manualTiledDragSession
        manualTiledDragSession = nil
        let target = drag.swapTarget ?? (pointerLocation == nil &&
            priorSession?.focusedWindow == focusedWindow &&
            priorSession?.partition == partition
                ? priorSession?.candidateTarget
                : nil)
        guard let target,
              participants.contains(target),
              let swappedTree = TiledLayoutEngine.swappingWindows(
                  focusedWindow,
                  target,
                  in: currentTree
              ), let effectiveShares = TiledLayoutEngine.leafShares(swappedTree)
        else { return .none }

        tiledTrees[partition] = swappedTree
        for (index, key) in swappedTree.windowKeys.enumerated() {
            windows[key]?.layoutOrder = index
            windows[key]?.layoutWeight = effectiveShares[key] ?? 1
        }
        lastFocusedWindow[tracked.workspaceID] = focusedWindow
        radialPlacementCommitContext = nil
        directionalMoveGestureContext = nil
        lastBackgroundLayoutSignature = nil
        diagnostics.log(
            category: "manual-move",
            event: "windows-swapped",
            correlation: correlationID,
            fields: [
                "workspace": Self.shortIdentifier(tracked.workspaceID.uuidString),
                "display": Self.shortIdentifier(display.identifier),
                "window": Self.diagnosticWindowKey(focusedWindow),
                "swapped-with": Self.diagnosticWindowKey(target),
                "tree-before": TiledLayoutEngine.fingerprint(currentTree),
                "tree-after": TiledLayoutEngine.fingerprint(swappedTree),
            ]
        )
        return .swapped
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
            guard tracked.workspaceID == workspaceID,
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

    /// `refreshWindows`: merely previewing the wheel must never trigger discovery-driven layout or
    /// visibility writes. The normal engine poll remains responsible for keeping tracking current.
    func radialCommandContext(completion: @escaping (RadialCommandContext) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
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
            let focusCandidates = self.directionalFocusCandidates(
                workspaceID: workspace.id,
                interactionDisplayIdentifier: interactionDisplay.identifier,
                displays: displays,
                correlationID: nil
            )
            let focusedKey = focused.map(\.key)
            let focusedFrame = focusedWindow?.frame.map { CGRect(origin: $0.position, size: $0.size) }
            let availableFocusDirections: Set<WindowDirection> = focusedFrame.map { sourceFrame in
                Set(WindowDirection.allCases.filter { direction in
                    !Self.directionalCandidateOrder(
                        from: sourceFrame,
                        direction: direction,
                        candidates: focusCandidates.filter { Optional($0.key) != focusedKey }
                    ).isEmpty
                })
            } ?? []
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
                tiledPlacementPreviews: tiledPlacementPreviews
            )
            DispatchQueue.main.async { completion(context) }
        }
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
            self.reapplyWorkspaceRules(to: Array(self.windows.keys))
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
                .filter { $0.workspaceID == workspaceID }
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
        let currentManagedFocus = rawFocus.flatMap { windows[$0.key] != nil ? $0.key : nil }
        let currentFocusIsUnmanaged = rawFocus.map {
            windows[$0.key] == nil || ignoredWindowKeys.contains($0.key)
        } ?? false
        let targetDisplayIdentifier: String? = {
            if let preferred = preSleepFocusContext?.displayIdentifier,
               displays.contains(where: { $0.identifier == preferred }) {
                return preferred
            }
            return displays.first(where: \.isMain)?.identifier ?? displays.first?.identifier
        }()

        let ordered = windows.values
            .filter { eligibleWindowKeys.contains($0.key) }
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
        windows.removeAll()
        pendingRestoredWindows.removeAll()
        ignoredWindowKeys.removeAll()
        admissionDecisionByWindow.removeAll()
        admissionMetadataByWindow.removeAll()
        lastKnownWindowLayer.removeAll()
        lastFocusedWindow.removeAll()
        lastObservedFocusedWindow = nil
        lastDiagnosticFocusedWindow = nil
        temporarilyDeferredWindowKeys.removeAll()
        fullscreenSessions.removeAll()
        fullscreenAuthoritativeFalseCounts.removeAll()
        foregroundFullscreenGameSessionKey = nil
        emitFullscreenGameSessionIfNeeded()
        focusCycleRejectedUntil.removeAll()
        staleParkedFocusSuppression.removeAll()
        lastAutomaticUnhideAttemptByProcess.removeAll()
        tiledTrees.removeAll()
        lastSolvedTiledFrames.removeAll()
        radialPlacementCommitContext = nil
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
        lastBroadWindowRefreshDate = Date()
        let displays = Self.activeDisplays()
        let topologySignature = Self.displayTopologySignature(displays)
        let displayBounds = displays.map(\.bounds)
        let topologyChanged = displays != lastDisplays
        lastDisplays = displays
        guard AXIsProcessTrusted() else {
            let required = Set(windows.keys.map(\.processIdentifier))
            temporarilyDeferredWindowKeys = Set(windows.keys)
            return WindowRefreshReport(
                displays: displays,
                topologySignature: topologySignature,
                requiredProcessIdentifiers: required,
                successfullyEnumeratedProcessIdentifiers: [],
                writeEligibleWindowKeys: [],
                deferredWindowKeys: Set(windows.keys),
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
        let visibleWindowLayers = AccessibilityWindow.visibleWindowLayers()
        var successfullyEnumeratedProcesses = Set<pid_t>()
        var enumeratedWindowKeys = Set<WindowKey>()
        var writeEligibleWindowKeys = Set<WindowKey>()
        var deferredWindowKeys = Set<WindowKey>()
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
                   AccessibilityWindow.hasVerifiedTransientNonNormalLayers(app.bundleIdentifier) {
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
                let admissionMetadata = AccessibilityWindow.admissionMetadata(
                    of: element,
                    bundleIdentifier: app.bundleIdentifier,
                    windowLayer: effectiveLayer,
                    fullscreenObservation: fullscreenObservation,
                    effectiveFullscreen: fullscreenResolution.isFullscreen
                )
                let admissionDecision = AccessibilityWindow.admissionDecision(for: admissionMetadata)
                let observedFrame = AccessibilityWindow.frame(of: element)
                if let observedFrame {
                    observedFrames[key] = observedFrame
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
                    metadata: admissionMetadata,
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
                        metadata: admissionMetadata,
                        correlationID: correlationID
                    )
                    evictedIgnoredManagedState = evictedIgnoredManagedState || removal.changedManagedState
                    continue
                }
                ignoredWindowKeys.remove(key)

                // Minimized or temporarily unusual AX objects retain existing state, matching the
                // prior behaviour, but are not newly admitted until they become manageable again.
                guard admissionDecision.disposition.admitsNewWindow,
                      let frame = observedFrame
                else {
                    if windows[key] != nil { deferredWindowKeys.insert(key) }
                    continue
                }
                if WakeWindowRecoveryPolicy.isWriteEligible(
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
                    if isWorkspaceActive(tracked.workspaceID),
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

        let deferredProcessIdentifiers = requiredProcessIdentifiers
            .subtracting(successfullyEnumeratedProcesses)
        for key in windows.keys where deferredProcessIdentifiers.contains(key.processIdentifier) {
            deferredWindowKeys.insert(key)
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
        if !removedTrackedWindowKeys.isEmpty {
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
        let shouldRetainDiscoveryState: (WindowKey) -> Bool = { key in
            runningProcessIdentifiers.contains(key.processIdentifier) &&
                (!successfullyEnumeratedProcesses.contains(key.processIdentifier) || enumeratedWindowKeys.contains(key))
        }
        ignoredWindowKeys = ignoredWindowKeys.filter(shouldRetainDiscoveryState)
        admissionDecisionByWindow = admissionDecisionByWindow.filter { shouldRetainDiscoveryState($0.key) }
        admissionMetadataByWindow = admissionMetadataByWindow.filter { shouldRetainDiscoveryState($0.key) }
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
        temporarilyDeferredWindowKeys = deferredWindowKeys

        let focusedSnapshot = observeFocus ? focusedWindowSnapshot() : nil
        if let focusedSnapshot,
           focusedSnapshot.key.processIdentifier != ownProcessIdentifier {
            lastDiagnosticFocusedWindow = focusedSnapshot
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
           let tracked = windows[focused] {
            lastFocusedWindow[tracked.workspaceID] = focused
        }

        var manualTiledDragInProgress = false
        if performAXWrites, !isStartup, !topologyChanged, let focused {
            let moveReconciliation = reconcileManualTiledMove(
                focusedWindow: focused,
                observedFrames: observedFrames,
                displays: displays,
                pointerLocation: CGEvent(source: nil)?.location,
                isLeftMouseButtonPressed: CGEventSource.buttonState(
                    .combinedSessionState,
                    button: .left
                ),
                correlationID: correlationID
            )
            manualTiledDragInProgress = moveReconciliation == .dragInProgress
            if moveReconciliation == .none {
                reconcileManualTiledResize(
                    focusedWindow: focused,
                    observedFrames: observedFrames,
                    displays: displays,
                    correlationID: correlationID
                )
            }
        } else if isStartup || topologyChanged || focused == nil {
            manualTiledDragSession = nil
        }

        let layoutSignatureBeforeApply = backgroundLayoutSignature(displays: displays)
        if performAXWrites, topologyChanged, !isStartup {
            applyVisibility(displays: displays, correlationID: correlationID)
        } else if performAXWrites, !manualTiledDragInProgress, Self.shouldApplyBackgroundLayout(
            previousSignature: lastBackgroundLayoutSignature,
            currentSignature: layoutSignatureBeforeApply,
            isStartup: isStartup
        ) {
            let visibleManagedWindows = windows.values.filter {
                !temporarilyDeferredWindowKeys.contains($0.key) &&
                Self.shouldWindowBeVisible(
                    workspaceID: $0.workspaceID,
                    activeWorkspaceIDs: activeWorkspaceIDs,
                    rule: resolvedRule(for: $0.bundleIdentifier)
                )
            }
            if !visibleManagedWindows.isEmpty {
                applyVisibleWindows(
                    visibleManagedWindows,
                    displays: displays,
                    correlationID: correlationID
                )
            }
        }
        if performAXWrites, !manualTiledDragInProgress {
            lastBackgroundLayoutSignature = backgroundLayoutSignature(displays: displays)
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

        return WindowRefreshReport(
            displays: displays,
            topologySignature: topologySignature,
            requiredProcessIdentifiers: requiredProcessIdentifiers,
            successfullyEnumeratedProcessIdentifiers: successfullyEnumeratedProcesses,
            writeEligibleWindowKeys: writeEligibleWindowKeys,
            deferredWindowKeys: deferredWindowKeys,
            managedWindowCount: windows.count
        )
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
        let session = FullscreenWindowSession(
            key: key,
            element: element,
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            workspaceID: workspaceID,
            displayIdentifier: displayIdentifier,
            frame: observedFrame ?? previous?.frame,
            isDeclaredGame: declaredGame,
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
                displayIdentifier: session.displayIdentifier
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
            "fullscreen-button": metadata.fullscreenButton.rawValue,
            "is-fullscreen": String(metadata.isFullscreen),
            "fullscreen-observation": metadata.fullscreenObservation.rawValue,
            "is-minimized": String(metadata.isMinimized),
            "close-button": metadata.closeButton.rawValue,
            "disposition": decision.disposition.rawValue,
            "reason": decision.reason.rawValue,
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
                role: metadata.role ?? "unknown",
                subrole: metadata.subrole ?? "unknown",
                windowLayer: metadata.windowLayer.map(String.init) ?? "unknown"
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

    @discardableResult
    private func evictIgnoredWindow(
        _ key: WindowKey,
        bundleIdentifier: String?,
        decision: WindowAdmissionDecision,
        metadata: WindowAdmissionMetadata,
        correlationID: String?
    ) -> IgnoredWindowRemovalResult {
        let removal = Self.removeIgnoredWindowState(
            key,
            bundleIdentifier: bundleIdentifier,
            trackedWindows: &windows,
            pendingRestoredWindows: &pendingRestoredWindows,
            lastFocusedWindow: &lastFocusedWindow
        )

        if lastObservedFocusedWindow == key {
            lastObservedFocusedWindow = nil
        }
        if programmaticFocusTarget == key {
            _ = advanceFocusActionGeneration()
            pendingFocusVerification?.cancel()
            pendingFocusVerification = nil
            clearProgrammaticFocusIntent()
        }
        if recentInteractionFocusTarget == key {
            recentInteractionFocusTarget = nil
        }
        focusCycleRejectedUntil.removeValue(forKey: key)
        staleParkedFocusSuppression.removeValue(forKey: key)
        lastSolvedTiledFrames.removeValue(forKey: key)

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
                    "frame-write": "false",
                ]
            )
        }
        return removal
    }

    static func removeIgnoredWindowState<Tracked>(
        _ key: WindowKey,
        bundleIdentifier: String?,
        trackedWindows: inout [WindowKey: Tracked],
        pendingRestoredWindows: inout [String: PersistedWindowAssignment],
        lastFocusedWindow: inout [UUID: WindowKey]
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
        return IgnoredWindowRemovalResult(
            removedTrackedWindow: removedTrackedWindow,
            removedPendingAssignment: removedPendingAssignment,
            clearedLastFocusedWorkspaceIDs: clearedLastFocusedWorkspaceIDs
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

    private func backgroundLayoutSignature(displays: [DisplaySnapshot]) -> String {
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
        parts.append(contentsOf: windows.values.sorted {
            if $0.key.processIdentifier != $1.key.processIdentifier {
                return $0.key.processIdentifier < $1.key.processIdentifier
            }
            return $0.key.windowIdentifier < $1.key.windowIdentifier
        }.compactMap { tracked in
            let rule = resolvedRule(for: tracked.bundleIdentifier)
            guard Self.shouldWindowBeVisible(
                workspaceID: tracked.workspaceID,
                activeWorkspaceIDs: activeWorkspaceIDs,
                rule: rule
            ) else { return nil }
            let currentFrame = AccessibilityWindow.frame(of: tracked.element)
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

    static func exactWindowFocusPlan(applicationIsActive: Bool) -> [ExactWindowFocusStep] {
        applicationIsActive
            ? [.markWindowMain, .focusWindowElement, .focusApplicationWindow, .raiseWindow]
            : [
                .markWindowMain,
                .raiseWindow,
                .activateApplication,
                .markWindowMain,
                .focusWindowElement,
                .focusApplicationWindow,
                .raiseWindow,
            ]
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
        applicationIsActive: Bool,
        exactAttempt: Int,
        maximumExactAttempts: Int = 1
    ) -> FocusCycleVerificationDecision {
        if actual == expected { return .succeeded }
        if let actual, actual.processIdentifier != expected.processIdentifier {
            return .abortForCompetingFocus
        }
        if !applicationIsActive, actual == nil {
            return .advanceToNextCandidate
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
        exactAttempt: Int,
        maximumExactAttempts: Int = 1
    ) -> FocusCycleVerificationDecision {
        if actualIsIgnored { return .abortForCompetingFocus }
        if actual == previousFocus, actual != expected, exactAttempt == 0 {
            return .retryExactTarget
        }
        return focusCycleVerificationDecision(
            expected: expected,
            actual: actual,
            applicationIsActive: applicationIsActive,
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
        if Self.shouldIgnoreFocusObservation(
            focusedWindow: focusedWindow,
            ignoredWindowKeys: ignoredWindowKeys
        ) {
            // Admission already emitted one privacy-safe record. Do not consume or repeatedly log
            // focus on an ignored popup, and do not clear the last managed interaction anchor.
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
        correlationID: String
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
            previousFocusKey: previousFocusKey
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
        guard let rawFocusedWindow else { return nil }
        let unusableAnchor = rawFocusedWindow.key.processIdentifier == ownProcessIdentifier ||
            ignoredWindowKeys.contains(rawFocusedWindow.key) ||
            staleParkedFocusSuppression[rawFocusedWindow.key] != nil
        guard unusableAnchor else { return rawFocusedWindow }

        let fallbackKeys = [recentInteractionFocusTarget, lastObservedFocusedWindow].compactMap { $0 }
        for key in fallbackKeys {
            guard staleParkedFocusSuppression[key] == nil, let tracked = windows[key] else { continue }
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

    @discardableResult
    private func applyVisibility(
        displays: [DisplaySnapshot]? = nil,
        correlationID: String? = nil,
        eligibleWindowKeys: Set<WindowKey>? = nil
    ) -> [WindowKey: WindowFrame] {
        let displays = displays ?? Self.activeDisplays()
        let parkingPosition = parkingPosition(displays: displays)
        let activeWorkspaceIDs = activeWorkspaceIDs
        let isEligible: (TrackedWindow) -> Bool = { tracked in
            !self.temporarilyDeferredWindowKeys.contains(tracked.key) &&
                (eligibleWindowKeys == nil || eligibleWindowKeys!.contains(tracked.key))
        }

        // Restore first, then hide. This ordering is intentional: it minimizes the interval in
        // which neither workspace is visible and matches the low-flicker ordering used by AeroSpork.
        let expectedLayoutFrames = applyVisibleWindows(
            windows.values.filter {
                isEligible($0) &&
                Self.shouldWindowBeVisible(
                    workspaceID: $0.workspaceID,
                    activeWorkspaceIDs: activeWorkspaceIDs,
                    rule: resolvedRule(for: $0.bundleIdentifier)
                )
            },
            displays: displays,
            correlationID: correlationID
        )
        applyPositionChanges(windows.values
            .filter {
                isEligible($0) &&
                !Self.shouldWindowBeVisible(
                    workspaceID: $0.workspaceID,
                    activeWorkspaceIDs: activeWorkspaceIDs,
                    rule: resolvedRule(for: $0.bundleIdentifier)
                )
            }
            .map { PositionChange(window: $0, position: parkingPosition) },
            correlationID: correlationID
        )
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
            windows.values.filter { $0.workspaceID == targetWorkspaceID },
            displays: displays,
            correlationID: correlationID
        )
        applyPositionChanges(windows.values
            .filter {
                $0.workspaceID == sourceWorkspaceID &&
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
        let writeEligibleWindows = trackedWindows.filter {
            FullscreenSessionPolicy.allowsGeometryWrite(
                hasFullscreenSession: fullscreenSessions[$0.key] != nil,
                isTemporarilyDeferred: temporarilyDeferredWindowKeys.contains($0.key)
            )
        }
        let windowsByWorkspace = Dictionary(grouping: Array(writeEligibleWindows), by: \.workspaceID)

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
                if Self.sizesMatch(resolved.size, tracked.restoreFrame.size) {
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
                    if let tree = TiledLayoutEngine.reconciled(
                        tiledTrees[partition],
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
        workspaces.first(where: { $0.id == workspaceID })?.layout ?? .none
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
        workspaces.first(where: { $0.id == workspaceID })?.layoutConfiguration
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
        let rule = (rules ?? appRulesByBundleIdentifier)[bundleIdentifier.lowercased()]
        return rule?.resolved(validWorkspaceIDs: Set(workspaces.map(\.id))) ?? .none
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
        let eligibleChanges = changes.filter {
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
        let effectiveChanges = changes.compactMap { change -> (FrameChange, WindowFrame?)? in
            guard FullscreenSessionPolicy.allowsGeometryWrite(
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
                    if let current, Self.sizesMatch(current.size, change.frame.size) {
                        succeeded = AccessibilityWindow.setPositionIfNeeded(
                            change.frame.position,
                            of: change.window.element
                        )
                    } else {
                        succeeded = AccessibilityWindow.setFrame(change.frame, of: change.window.element)
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
                        ]
                    )
                }
            }
        }
    }

    private static func sizesMatch(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        abs(lhs.width - rhs.width) < 0.5 && abs(lhs.height - rhs.height) < 0.5
    }

    private func restoreManagedWindowsForQuit() {
        let mainDisplayBounds = CGDisplayBounds(CGMainDisplayID())
        guard !mainDisplayBounds.isNull, !mainDisplayBounds.isEmpty else { return }

        var pending = windows.values.compactMap { tracked -> FrameChange? in
            guard FullscreenSessionPolicy.allowsGeometryWrite(
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
                        AccessibilityWindow.setFrame(change.frame, of: change.window.element)
                    }
                }
            }

            pending = pending.filter { change in
                guard let actual = AccessibilityWindow.frame(of: change.window.element) else { return true }
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
        previousFocusKey: WindowKey?
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
        if let preferredKey = lastFocusedWindow[workspaceID],
           let preferredSession = fullscreenSessions[preferredKey],
           preferredSession.workspaceID == workspaceID,
           preferredSession.displayIdentifier == destinationDisplayIdentifier {
            focusFullscreenSessionAfterSwitch(
                preferredSession,
                workspaceID: workspaceID,
                destinationDisplayIdentifier: destinationDisplayIdentifier,
                correlationID: correlationID,
                token: token
            )
            return
        }
        let attemptOrder = orderedWorkspaceSwitchFocusCandidates(
            workspaceID: workspaceID,
            destinationDisplayIdentifier: destinationDisplayIdentifier,
            displays: displays,
            correlationID: correlationID
        )
        guard let target = attemptOrder.first else {
            if let fallbackSession = fullscreenSessions.values
                .filter({
                    $0.workspaceID == workspaceID &&
                        $0.displayIdentifier == destinationDisplayIdentifier
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
                "active-after": diagnosticActiveWorkspaceMap(),
            ]
        )
        attemptWorkspaceSwitchFocusCandidate(
            attemptOrder: attemptOrder,
            candidateIndex: 0,
            exactAttempt: 0,
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
        exactAttempt: Int,
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
                exactAttempt: 0,
                previousFocusKey: previousFocusKey,
                workspaceID: workspaceID,
                destinationDisplayIdentifier: destinationDisplayIdentifier,
                displays: displays,
                correlationID: correlationID,
                token: token
            )
            return
        }

        if exactAttempt == 0 {
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
                "exact-attempt": String(exactAttempt),
                "display": Self.shortIdentifier(destinationDisplayIdentifier),
            ]
        )
        if exactAttempt == 0 {
            focusManagedWindow(
                targetKey,
                tracked: target,
                correlationID: correlationID,
                token: token
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
        let delay: DispatchTimeInterval = exactAttempt == 0 ? .milliseconds(220) : .milliseconds(120)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isFocusActionGenerationCurrent(token.generation) else { return }
            let actual = self.focusedWindowKey()
            let applicationIsActive = NSRunningApplication(
                processIdentifier: targetKey.processIdentifier
            )?.isActive == true
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
                exactAttempt: exactAttempt,
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
                    "actual-window-ignored": String(actualIsIgnored),
                    "exact-attempt": String(exactAttempt),
                    "decision": String(describing: decision),
                    "display": Self.shortIdentifier(destinationDisplayIdentifier),
                ]
            )

            switch decision {
            case .succeeded:
                self.lastObservedFocusedWindow = targetKey
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
            case .retryExactTarget:
                self.attemptWorkspaceSwitchFocusCandidate(
                    attemptOrder: attemptOrder,
                    candidateIndex: candidateIndex,
                    exactAttempt: exactAttempt + 1,
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
                    exactAttempt: 0,
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
        exactAttempt: Int,
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
                exactAttempt: 0,
                originalFocus: originalFocus,
                workspaceID: workspaceID,
                interactionDisplayIdentifier: interactionDisplayIdentifier,
                displays: displays,
                correlationID: correlationID,
                token: token
            )
            return
        }

        if exactAttempt == 0 {
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
                "exact-attempt": String(exactAttempt),
                "display": Self.shortIdentifier(interactionDisplayIdentifier),
            ]
        )
        if exactAttempt == 0 {
            focusManagedWindow(
                targetKey,
                tracked: target,
                correlationID: correlationID,
                token: token
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
        let delay: DispatchTimeInterval = exactAttempt == 0 ? .milliseconds(220) : .milliseconds(120)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.isFocusActionGenerationCurrent(token.generation)
            else { return }
            let actual = self.focusedWindowKey()
            let applicationIsActive = NSRunningApplication(
                processIdentifier: targetKey.processIdentifier
            )?.isActive == true
            let actualIsIgnored = Self.shouldIgnoreFocusObservation(
                focusedWindow: actual,
                ignoredWindowKeys: self.ignoredWindowKeys
            )
            let decision: FocusCycleVerificationDecision = actualIsIgnored
                ? .abortForCompetingFocus
                : Self.focusCycleVerificationDecision(
                    expected: targetKey,
                    actual: actual,
                    applicationIsActive: applicationIsActive,
                    exactAttempt: exactAttempt,
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
                    "actual-window-ignored": String(actualIsIgnored),
                    "exact-attempt": String(exactAttempt),
                    "decision": String(describing: decision),
                ]
            )

            switch decision {
            case .succeeded:
                self.lastObservedFocusedWindow = targetKey
                self.diagnostics.log(
                    category: "focus-cycle",
                    event: "complete",
                    correlation: correlationID,
                    fields: [
                        "window": Self.diagnosticWindowKey(targetKey),
                        "active-after": self.diagnosticActiveWorkspaceMap(),
                    ]
                )
            case .retryExactTarget:
                self.attemptFocusCycleCandidate(
                    attemptOrder: attemptOrder,
                    candidateIndex: candidateIndex,
                    exactAttempt: exactAttempt + 1,
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
                    exactAttempt: 0,
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
        token: FocusVerificationToken? = nil
    ) {
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

        // App activation chooses an application, not a specific window. Prepare and raise the
        // exact target first (the ordering used by AeroSpace), then reassert it again from the
        // activation notification. This prevents activation from making another same-app window
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
            let activated = application?.activate() == true
            self?.diagnostics.log(
                category: "focus-action",
                event: "application-activate",
                correlation: correlationID,
                fields: [
                    "window": Self.diagnosticWindowKey(key),
                    "success": String(activated),
                    "automatic-unhide": unhideDecision.rawValue,
                    "unhide-success": String(unhidden),
                    "ordering": "exact-window-before-activate-then-reassert",
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

    private func emitState() {
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
        DispatchQueue.main.async { [weak self] in self?.onStateChanged?(state) }
    }

    private func emitFloatingToggleResult(_ result: FloatingToggleResult) {
        emitCommandFeedback(result.commandFeedbackMessage)
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
