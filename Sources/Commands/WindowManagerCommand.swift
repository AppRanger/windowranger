import Foundation

enum WindowManagerCommand: Hashable, Sendable {
    case switchWorkspace(UUID)
    case moveFocusedWindow(UUID)
    case moveFocusedWindowAndFollow(UUID)
    case cycleWorkspace(Int)
    case cycleWindow(Int)
    case cycleLayout(Int)
    case setLayout(WorkspaceLayout)
    case selectLayoutFromShortcut(WorkspaceLayout)
    case toggleFloating
    case toggleDropDownApp
    case selectQuickApp(String)
    case cycleQuickApp(Int)
    case addCurrentApplication(String, displayName: String, workspaceID: UUID, profileID: UUID)
    case addCurrentApplicationToQuickAppShelf(String, displayName: String, profileID: UUID)
    case previousWorkspace
    case resetCurrentWorkspace
    case resetAllWindows
    case focusDirection(WindowDirection)
    case moveWindowDirection(WindowDirection)
    case beginDirectionalMoveGesture(String, WindowDirection)
    case commitDirectionalMoveGesture(String, DirectionalMoveGestureResolution)
    case cancelDirectionalMoveGesture(String, reason: String)
    case smartResize(Int)
    case moveCurrentWorkspaceToNextDisplay
    case moveCurrentWorkspaceToDisplay(String)
    case placeTiledWindow(VisualPlacement, validationToken: String)
    case placeFreeformWindow(VisualPlacement, validationToken: String)
    case selectProfile(UUID)
    case resumeAutomaticProfileSelection
    case setPauseMode(Bool)

    var diagnosticFields: [String: String] {
        switch self {
        case let .switchWorkspace(id):
            ["action": "switch-workspace", "workspace": id.uuidString]
        case let .moveFocusedWindow(id):
            ["action": "move-window", "workspace": id.uuidString]
        case let .moveFocusedWindowAndFollow(id):
            ["action": "move-window-and-follow", "workspace": id.uuidString]
        case let .cycleWorkspace(offset):
            ["action": "cycle-workspace", "offset": String(offset)]
        case let .cycleWindow(offset):
            ["action": "cycle-window", "offset": String(offset)]
        case let .cycleLayout(offset):
            ["action": "cycle-layout", "offset": String(offset)]
        case let .setLayout(layout):
            ["action": "set-layout", "layout": layout.rawValue]
        case let .selectLayoutFromShortcut(layout):
            ["action": "select-layout-shortcut", "layout": layout.rawValue]
        case .toggleFloating:
            ["action": "toggle-floating"]
        case .toggleDropDownApp:
            ["action": "toggle-drop-down-app"]
        case let .selectQuickApp(bundleIdentifier):
            ["action": "select-quick-app", "bundle": bundleIdentifier]
        case let .cycleQuickApp(offset):
            ["action": "cycle-quick-app", "offset": String(offset)]
        case let .addCurrentApplication(bundleIdentifier, _, workspaceID, profileID):
            ["action": "add-current-application", "bundle": bundleIdentifier,
             "workspace": workspaceID.uuidString, "profile": profileID.uuidString]
        case let .addCurrentApplicationToQuickAppShelf(bundleIdentifier, _, profileID):
            ["action": "add-current-application-to-quick-app-shelf", "bundle": bundleIdentifier,
             "profile": profileID.uuidString]
        case .previousWorkspace:
            ["action": "previous-workspace"]
        case .resetCurrentWorkspace:
            ["action": "reset-current-workspace"]
        case .resetAllWindows:
            ["action": "reset-all-windows"]
        case let .focusDirection(direction):
            ["action": "focus-direction", "direction": direction.rawValue]
        case let .moveWindowDirection(direction):
            ["action": "move-window-direction", "direction": direction.rawValue]
        case let .beginDirectionalMoveGesture(identifier, direction):
            [
                "action": "begin-directional-move-gesture",
                "gesture": String(identifier.prefix(16)),
                "direction": direction.rawValue,
            ]
        case let .commitDirectionalMoveGesture(identifier, resolution):
            [
                "action": "commit-directional-move-gesture",
                "gesture": String(identifier.prefix(16)),
                "resolution": resolution.diagnosticValue,
            ]
        case let .cancelDirectionalMoveGesture(identifier, reason):
            [
                "action": "cancel-directional-move-gesture",
                "gesture": String(identifier.prefix(16)),
                "reason": reason,
            ]
        case let .smartResize(delta):
            ["action": "smart-resize", "delta": String(delta)]
        case .moveCurrentWorkspaceToNextDisplay:
            ["action": "move-workspace-to-next-display"]
        case let .moveCurrentWorkspaceToDisplay(identifier):
            ["action": "move-workspace-to-display", "display": identifier]
        case let .placeTiledWindow(placement, validationToken):
            [
                "action": "place-tiled-window",
                "placement": placement.rawValue,
                "validation-token": String(validationToken.prefix(16)),
            ]
        case let .placeFreeformWindow(placement, validationToken):
            [
                "action": "place-freeform-window",
                "placement": placement.rawValue,
                "validation-token": String(validationToken.prefix(16)),
            ]
        case let .selectProfile(id):
            ["action": "select-profile", "profile": id.uuidString]
        case .resumeAutomaticProfileSelection:
            ["action": "resume-automatic-profile-selection"]
        case let .setPauseMode(isPaused):
            ["action": isPaused ? "pause-window-ranger" : "resume-window-ranger"]
        }
    }
}

enum WindowManagerCommandSource: String, Sendable {
    case hotkey
    case commandPalette = "command-palette"
    case radialMenu = "radial-menu"
    case workspaceSwipe = "workspace-swipe"
}

enum WindowManagerCommandDispatchResult: Equatable, Sendable {
    case dispatched
    case rejectedReentrant
}

/// The one mutation gateway used by both keyboard shortcuts and contextual UI. Keeping the
/// operation switch here means a visual command cannot quietly diverge from its keyboard twin.
final class WindowManagerCommandDispatcher {
    typealias Executor = (WindowManagerCommand, String) -> Void

    private let executor: Executor
    private let diagnostics: DiagnosticLogger
    private let lock = NSLock()
    private var activeCorrelations = Set<String>()

    convenience init(
        engine: WorkspaceEngine,
        diagnostics: DiagnosticLogger = .disabled,
        selectProfile: @escaping (UUID, String) -> Void = { _, _ in },
        resumeAutomaticProfileSelection: @escaping (String) -> Void = { _ in },
        addCurrentApplication: @escaping (String, String, UUID, UUID, String) -> Void = {
            _, _, _, _, _ in
        },
        addCurrentApplicationToQuickAppShelf: @escaping (String, String, UUID, String) -> Void = {
            _, _, _, _ in
        },
        setPauseMode: @escaping (Bool, String) -> Void = { _, _ in }
    ) {
        self.init(diagnostics: diagnostics) { [weak engine] command, correlationID in
            switch command {
            case let .switchWorkspace(id):
                engine?.switchToWorkspace(id, correlationID: correlationID)
            case let .moveFocusedWindow(id):
                engine?.moveFocusedWindow(to: id, correlationID: correlationID)
            case let .moveFocusedWindowAndFollow(id):
                engine?.moveFocusedWindow(to: id, followOverride: true, correlationID: correlationID)
            case let .cycleWorkspace(offset):
                engine?.cycleWorkspace(offset: offset, correlationID: correlationID)
            case let .cycleWindow(offset): engine?.cycleWindowFocus(offset: offset, correlationID: correlationID)
            case let .cycleLayout(offset):
                engine?.cycleWorkspaceLayout(offset: offset, correlationID: correlationID)
            case let .setLayout(layout): engine?.setWorkspaceLayout(layout, correlationID: correlationID)
            case let .selectLayoutFromShortcut(layout):
                engine?.setWorkspaceLayout(
                    layout,
                    cycleOrientationWhenAlreadySelected: true,
                    correlationID: correlationID
                )
            case .toggleFloating: engine?.toggleFocusedWindowFloating()
            case .toggleDropDownApp:
                engine?.toggleDropDownApp(correlationID: correlationID)
            case let .selectQuickApp(bundleIdentifier):
                engine?.selectQuickApp(bundleIdentifier: bundleIdentifier, correlationID: correlationID)
            case let .cycleQuickApp(offset):
                engine?.cycleQuickApp(offset: offset, correlationID: correlationID)
            case let .addCurrentApplication(bundleIdentifier, displayName, workspaceID, profileID):
                addCurrentApplication(bundleIdentifier, displayName, workspaceID, profileID, correlationID)
            case let .addCurrentApplicationToQuickAppShelf(bundleIdentifier, displayName, profileID):
                addCurrentApplicationToQuickAppShelf(bundleIdentifier, displayName, profileID, correlationID)
            case .previousWorkspace:
                engine?.switchToPreviousWorkspace(correlationID: correlationID)
            case .resetCurrentWorkspace: engine?.resetCurrentWorkspace(correlationID: correlationID)
            case .resetAllWindows: engine?.restoreAllWindows()
            case let .focusDirection(direction):
                engine?.focusWindow(direction, correlationID: correlationID)
            case let .moveWindowDirection(direction):
                engine?.moveWindow(direction, correlationID: correlationID)
            case let .beginDirectionalMoveGesture(identifier, direction):
                engine?.beginDirectionalMoveGesture(
                    identifier: identifier,
                    firstDirection: direction,
                    correlationID: correlationID
                )
            case let .commitDirectionalMoveGesture(identifier, resolution):
                engine?.commitDirectionalMoveGesture(
                    identifier: identifier,
                    resolution: resolution,
                    correlationID: correlationID
                )
            case let .cancelDirectionalMoveGesture(identifier, reason):
                engine?.cancelDirectionalMoveGesture(
                    identifier: identifier,
                    reason: reason,
                    correlationID: correlationID
                )
            case let .smartResize(delta):
                engine?.smartResize(by: delta, correlationID: correlationID)
            case .moveCurrentWorkspaceToNextDisplay:
                engine?.moveCurrentWorkspaceToNextDisplay(correlationID: correlationID)
            case let .moveCurrentWorkspaceToDisplay(identifier):
                engine?.moveCurrentWorkspace(
                    toDisplayIdentifier: identifier,
                    correlationID: correlationID
                )
            case let .placeTiledWindow(placement, validationToken):
                engine?.placeFocusedTiledWindow(
                    at: placement,
                    validationToken: validationToken,
                    correlationID: correlationID
                )
            case let .placeFreeformWindow(placement, validationToken):
                engine?.placeFocusedFreeformWindow(
                    at: placement,
                    validationToken: validationToken,
                    correlationID: correlationID
                )
            case let .selectProfile(id):
                selectProfile(id, correlationID)
            case .resumeAutomaticProfileSelection:
                resumeAutomaticProfileSelection(correlationID)
            case let .setPauseMode(isPaused):
                setPauseMode(isPaused, correlationID)
            }
        }
    }

    init(diagnostics: DiagnosticLogger = .disabled, executor: @escaping Executor) {
        self.diagnostics = diagnostics
        self.executor = executor
    }

    @discardableResult
    func dispatch(
        _ command: WindowManagerCommand,
        source: WindowManagerCommandSource,
        correlationID: String? = nil
    ) -> WindowManagerCommandDispatchResult {
        let correlationID = correlationID ?? diagnostics.makeCorrelationID()
        lock.lock()
        let inserted = activeCorrelations.insert(correlationID).inserted
        lock.unlock()
        guard inserted else {
            diagnostics.log(
                category: "command",
                event: "reentrant-rejected",
                correlation: correlationID,
                fields: command.diagnosticFields.merging(["source": source.rawValue]) { _, new in new }
            )
            return .rejectedReentrant
        }

        defer {
            lock.lock()
            activeCorrelations.remove(correlationID)
            lock.unlock()
        }
        diagnostics.log(
            category: "command",
            event: "dispatch",
            correlation: correlationID,
            fields: command.diagnosticFields.merging(["source": source.rawValue]) { _, new in new }
        )
        executor(command, correlationID)
        return .dispatched
    }
}
