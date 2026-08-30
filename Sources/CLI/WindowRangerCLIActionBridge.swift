import AppKit
import Foundation

/// Resolves CLI action requests against the same live context that powers the command palette.
///
/// The CLI deliberately receives action names and scalar arguments, rather than a caller-built
/// `WindowManagerCommand`: bundle identifiers, display identifiers, placement tokens, and focused
/// window identity are all derived here from a freshly captured engine context. This keeps a local
/// automation client from replaying a stale menu decision against a different desktop.
@MainActor
final class WindowRangerCLIActionBridge {
    typealias Completion = (WindowRangerCLIErrorCode?) -> Void
    typealias SettingsOpener = (SettingsCategory?) -> Void

    private let engine: WorkspaceEngine
    private let dispatcher: WindowManagerCommandDispatcher
    private let contextEnricher: (RadialCommandContext) -> RadialCommandContext
    private let accessibilityGranted: () -> Bool
    private let openSettings: SettingsOpener
    private let requestAccessibility: () -> Bool
    private let openScreenRecordingSettings: () -> Void
    private let openLoginItemsSettings: () -> Void
    private let restartOnboarding: () -> Void
    private let checkForUpdates: () -> Bool
    private let setICloudSyncEnabled: (Bool) -> Bool
    private let replaceICloudWithLocal: () -> Bool

    init(
        engine: WorkspaceEngine,
        dispatcher: WindowManagerCommandDispatcher,
        contextEnricher: @escaping (RadialCommandContext) -> RadialCommandContext,
        accessibilityGranted: @escaping () -> Bool = { AXIsProcessTrusted() },
        openSettings: @escaping SettingsOpener = { _ in },
        requestAccessibility: @escaping () -> Bool = { AccessibilityWindow.requestPermission() },
        openScreenRecordingSettings: @escaping () -> Void = {},
        openLoginItemsSettings: @escaping () -> Void = {},
        restartOnboarding: @escaping () -> Void = {},
        checkForUpdates: @escaping () -> Bool = { false },
        setICloudSyncEnabled: @escaping (Bool) -> Bool = { _ in false },
        replaceICloudWithLocal: @escaping () -> Bool = { false }
    ) {
        self.engine = engine
        self.dispatcher = dispatcher
        self.contextEnricher = contextEnricher
        self.accessibilityGranted = accessibilityGranted
        self.openSettings = openSettings
        self.requestAccessibility = requestAccessibility
        self.openScreenRecordingSettings = openScreenRecordingSettings
        self.openLoginItemsSettings = openLoginItemsSettings
        self.restartOnboarding = restartOnboarding
        self.checkForUpdates = checkForUpdates
        self.setICloudSyncEnabled = setICloudSyncEnabled
        self.replaceICloudWithLocal = replaceICloudWithLocal
    }

    /// Completes with `nil` when the operation was accepted. Engine mutations are intentionally
    /// asynchronous after dispatch, matching hotkeys and the command palette.
    func perform(
        action: String,
        arguments: [String: String],
        requestID: String,
        deadlineUptimeNanoseconds: UInt64,
        completion: @escaping Completion
    ) {
        guard DispatchTime.now().uptimeNanoseconds < deadlineUptimeNanoseconds else {
            completion(.timedOut)
            return
        }
        guard WindowRangerCLICommandCatalog.actionConfirmationIsSatisfied(
            action: action,
            arguments: arguments
        ) else {
            completion(.confirmationRequired)
            return
        }
        switch action {
        case "open-settings":
            let category = arguments["category"].flatMap { SettingsCategory(rawValue: $0) }
            guard arguments["category"] == nil || category != nil else {
                completion(.invalidRequest)
                return
            }
            openSettings(category)
            completion(nil)
        case "request-accessibility":
            _ = requestAccessibility()
            completion(nil)
        case "open-screen-recording-settings":
            openScreenRecordingSettings()
            completion(nil)
        case "open-login-items-settings":
            openLoginItemsSettings()
            completion(nil)
        case "restart-onboarding":
            restartOnboarding()
            completion(nil)
        case "check-for-updates":
            completion(checkForUpdates() ? nil : .unavailable)
        case "enable-icloud-sync":
            completion(setICloudSyncEnabled(true) ? nil : .unavailable)
        case "disable-icloud-sync":
            completion(setICloudSyncEnabled(false) ? nil : .unavailable)
        case "replace-icloud-with-local":
            completion(replaceICloudWithLocal() ? nil : .unavailable)
        case "pause":
            dispatch(.setPauseMode(true), requestID: requestID, completion: completion)
        case "resume":
            dispatch(.setPauseMode(false), requestID: requestID, completion: completion)
        default:
            performWindowRangerAction(
                action: action,
                arguments: arguments,
                requestID: requestID,
                deadlineUptimeNanoseconds: deadlineUptimeNanoseconds,
                completion: completion
            )
        }
    }

    private func performWindowRangerAction(
        action: String,
        arguments: [String: String],
        requestID: String,
        deadlineUptimeNanoseconds: UInt64,
        completion: @escaping Completion
    ) {
        guard accessibilityGranted() else {
            completion(.accessibilityRequired)
            return
        }
        engine.radialCommandContext { [weak self] rawContext in
            guard let self else {
                completion(.unavailable)
                return
            }
            guard DispatchTime.now().uptimeNanoseconds < deadlineUptimeNanoseconds else {
                completion(.timedOut)
                return
            }
            let context = self.contextEnricher(rawContext)
            guard let command = self.command(
                action: action,
                arguments: arguments,
                context: context
            ) else {
                completion(.invalidRequest)
                return
            }
            self.dispatch(command, requestID: requestID, completion: completion)
        }
    }

    private func dispatch(
        _ command: WindowManagerCommand,
        requestID: String,
        completion: Completion
    ) {
        switch dispatcher.dispatch(command, source: .cli, correlationID: requestID) {
        case .dispatched:
            completion(nil)
        case .rejectedReentrant:
            completion(.conflict)
        }
    }

    private func command(
        action: String,
        arguments: [String: String],
        context: RadialCommandContext
    ) -> WindowManagerCommand? {
        switch action {
        case "switch-workspace":
            return resolveWorkspace(arguments, context: context).map(WindowManagerCommand.switchWorkspace)
        case "move-window":
            return validMoveDestination(arguments, context: context).map(WindowManagerCommand.moveFocusedWindow)
        case "move-window-and-follow":
            return validMoveDestination(arguments, context: context).map(WindowManagerCommand.moveFocusedWindowAndFollow)
        case "cycle-workspace":
            return integer("offset", in: arguments, range: -100...100).map(WindowManagerCommand.cycleWorkspace)
        case "cycle-window":
            return integer("offset", in: arguments, range: -100...100).map(WindowManagerCommand.cycleWindow)
        case "cycle-layout":
            return integer("offset", in: arguments, range: -100...100).map(WindowManagerCommand.cycleLayout)
        case "set-layout":
            guard context.supportedCommands.contains(.setLayout) else { return nil }
            return arguments["layout"].flatMap { workspaceLayout($0) }.map(WindowManagerCommand.setLayout)
        case "select-layout":
            guard context.supportedCommands.contains(.setLayout) else { return nil }
            return arguments["layout"].flatMap { workspaceLayout($0) }.map(WindowManagerCommand.selectLayoutFromShortcut)
        case "toggle-floating":
            return context.focusedWindow == nil ? nil : .toggleFloating
        case "toggle-drop-down-app":
            return .toggleDropDownApp
        case "select-quick-app":
            guard let requested = arguments["bundle-id"],
                  let app = context.quickApps.first(where: {
                      $0.bundleIdentifier.caseInsensitiveCompare(requested) == .orderedSame
                  })
            else { return nil }
            return .selectQuickApp(app.bundleIdentifier)
        case "cycle-quick-app":
            return integer("offset", in: arguments, range: -100...100).map(WindowManagerCommand.cycleQuickApp)
        case "add-current-app-rule":
            guard let current = currentApplication(in: context),
                  !current.hasRule,
                  let profileID = context.activeProfileID
            else { return nil }
            return .addCurrentApplication(
                current.application.bundleIdentifier,
                displayName: current.application.displayName,
                workspaceID: context.workspaceID,
                profileID: profileID,
                expectedMembership: current.membership
            )
        case "remove-current-app-rule":
            guard let current = currentApplication(in: context), current.hasRule,
                  let profileID = context.activeProfileID
            else { return nil }
            return .removeCurrentApplication(
                current.application.bundleIdentifier,
                profileID: profileID,
                expectedMembership: current.membership
            )
        case "add-current-app-to-shelf":
            guard let current = currentApplication(in: context),
                  !current.inShelf,
                  context.quickApps.count < QuickAppShelfPolicy.maximumCount,
                  QuickAppShelfPolicy.isEligible(bundleIdentifier: current.application.bundleIdentifier),
                  let profileID = context.activeProfileID
            else { return nil }
            return .addCurrentApplicationToQuickAppShelf(
                current.application.bundleIdentifier,
                displayName: current.application.displayName,
                profileID: profileID,
                expectedMembership: current.membership
            )
        case "previous-workspace":
            return .previousWorkspace
        case "reset-current-workspace":
            return .resetCurrentWorkspace
        case "bring-windows-back-on-screen":
            return .resetAllWindows
        case "focus-direction":
            guard let direction = arguments["direction"].flatMap({ WindowDirection(rawValue: $0) }),
                  context.availableFocusDirections.contains(direction)
            else { return nil }
            return .focusDirection(direction)
        case "move-window-direction":
            guard let direction = arguments["direction"].flatMap({ WindowDirection(rawValue: $0) }),
                  context.availableMoveDirections.contains(direction)
            else { return nil }
            return .moveWindowDirection(direction)
        case "smart-resize":
            guard context.canSmartResize,
                  let amount = integer("amount", in: arguments, range: -1_000...1_000), amount != 0
            else { return nil }
            return .smartResize(amount)
        case "move-workspace-to-next-display":
            guard context.supportedCommands.contains(.moveWorkspaceToDisplay),
                  context.connectedDisplayIdentifiers.count > 1
            else { return nil }
            return .moveCurrentWorkspaceToNextDisplay
        case "move-workspace-to-display":
            guard let displayID = arguments["display-id"],
                  context.supportedCommands.contains(.moveWorkspaceToDisplay),
                  context.connectedDisplayIdentifiers.contains(displayID)
            else { return nil }
            return .moveCurrentWorkspaceToDisplay(displayID)
        case "place-window":
            guard let placement = arguments["placement"].flatMap({ VisualPlacement(rawValue: $0) }),
                  context.focusedWindow != nil
            else { return nil }
            switch context.layout {
            case .tiled:
                guard context.tiledPlacementPreviews.contains(where: { $0.placement == placement }) else {
                    return nil
                }
                return .placeTiledWindow(placement, validationToken: context.validationToken)
            case .none:
                guard context.freeformPlacementPreviews.contains(where: { $0.placement == placement }) else {
                    return nil
                }
                return .placeFreeformWindow(placement, validationToken: context.validationToken)
            case .accordion:
                return nil
            }
        case "select-profile":
            guard let profileID = arguments["profile-id"].flatMap({ UUID(uuidString: $0) }),
                  context.profiles.contains(where: { $0.id == profileID })
            else { return nil }
            return .selectProfile(profileID)
        case "resume-automatic-profile-selection":
            return context.isProfileManuallyPinned ? .resumeAutomaticProfileSelection : nil
        default:
            return nil
        }
    }

    private func resolveWorkspace(
        _ arguments: [String: String],
        context: RadialCommandContext
    ) -> UUID? {
        let requestedID = arguments["workspace-id"].flatMap { UUID(uuidString: $0) }
        let requestedKey = arguments["workspace-key"]
        guard (requestedID != nil) != (requestedKey != nil) else { return nil }
        if let requestedID {
            return context.workspaces.first(where: { $0.id == requestedID })?.id
        }
        return context.workspaces.first {
            $0.key.caseInsensitiveCompare(requestedKey ?? "") == .orderedSame
        }?.id
    }

    private func validMoveDestination(
        _ arguments: [String: String],
        context: RadialCommandContext
    ) -> UUID? {
        guard context.supportedCommands.contains(.moveFocusedWindow),
              let focusedWindow = context.focusedWindow,
              !focusedWindow.keepsOnAllWorkspaces,
              let destinationID = resolveWorkspace(arguments, context: context),
              destinationID != focusedWindow.workspaceID,
              let destination = context.workspaces.first(where: { $0.id == destinationID }),
              context.displayMode != .unified || destination.homeDisplayIdentifier == context.displayIdentifier
        else { return nil }
        return destinationID
    }

    private func workspaceLayout(_ rawValue: String) -> WorkspaceLayout? {
        switch rawValue {
        case "freeform": WorkspaceLayout.none
        case "tiled": .tiled
        case "accordion": .accordion
        default: nil
        }
    }

    private func integer(
        _ key: String,
        in arguments: [String: String],
        range: ClosedRange<Int>
    ) -> Int? {
        guard let rawValue = arguments[key],
              let value = Int(rawValue), range.contains(value)
        else { return nil }
        return value
    }

    private func currentApplication(
        in context: RadialCommandContext
    ) -> (application: RadialApplicationOption, hasRule: Bool, inShelf: Bool, membership: CurrentApplicationConfigurationMembership)? {
        guard let application = context.currentApplication else { return nil }
        let normalized = application.bundleIdentifier.lowercased()
        let hasRule = context.applicationRuleBundleIdentifiers.contains(normalized)
        let inShelf = context.quickApps.contains {
            $0.bundleIdentifier.caseInsensitiveCompare(application.bundleIdentifier) == .orderedSame
        }
        let membership: CurrentApplicationConfigurationMembership = hasRule
            ? .appRule
            : inShelf ? .quickAppShelf : .none
        return (application, hasRule, inShelf, membership)
    }
}
