import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let diagnostics = DiagnosticLogger.makeAppLogger()
    lazy var settingsStore = SettingsStore(diagnostics: diagnostics)
    lazy var settingsNavigation = SettingsNavigationModel()
    lazy var settingsWindowCoordinator = SettingsWindowCoordinator(diagnostics: diagnostics)
    lazy var settingsCommandRequestRouter = SettingsCommandRequestRouter()
    lazy var menuBarState = MenuBarStateModel(
        workspaces: settingsStore.workspaces,
        displayMode: settingsStore.multiDisplayMode,
        connectedDisplays: settingsStore.connectedDisplays,
        workspaceDisplayAssignments: settingsStore.workspaceDisplayAssignments
    )
    lazy var engine = WorkspaceEngine(
        workspaces: settingsStore.workspaces,
        profileID: settingsStore.activeProfileID,
        displayMode: settingsStore.multiDisplayMode,
        workspaceDisplayAssignments: settingsStore.workspaceDisplayHomesForEngine,
        appRules: settingsStore.appRules,
        dropDownApp: settingsStore.dropDownApp,
        focusFollowsMovedWindow: settingsStore.focusFollowsMovedWindow,
        automaticallyUnhideApplications: settingsStore.automaticallyUnhideApplications,
        focusedWindowHighlightEnabled: settingsStore.focusedWindowHighlightEnabled,
        diagnostics: diagnostics
    )
    private lazy var commandDispatcher = WindowManagerCommandDispatcher(
        engine: engine,
        diagnostics: diagnostics,
        selectProfile: { [weak self] profileID, _ in
            Task { @MainActor [weak self] in self?.settingsStore.selectProfile(profileID) }
        },
        resumeAutomaticProfileSelection: { [weak self] _ in
            Task { @MainActor [weak self] in self?.settingsStore.resumeAutomaticProfileSelection() }
        }
    )
    private lazy var radialMenuController = RadialMenuController(
        engine: engine,
        dispatcher: commandDispatcher,
        diagnostics: diagnostics,
        definitionProvider: { [weak self] in
            self?.settingsStore.radialWheelDefinition ?? .builtInDefault
        },
        contextEnricher: { [weak self] context in
            guard let self else { return context }
            var enriched = context
            enriched.profiles = self.settingsStore.profiles.map {
                RadialProfileOption(id: $0.id, name: $0.name)
            }
            enriched.activeProfileID = self.settingsStore.activeProfileID
            enriched.isProfileManuallyPinned = self.settingsStore.manualPinnedProfileID != nil
            enriched.externalValidationToken = [
                "active=\(self.settingsStore.activeProfileID.uuidString)",
                "pinned=\(self.settingsStore.manualPinnedProfileID?.uuidString ?? "none")",
                self.settingsStore.profiles.map { "\($0.id.uuidString)=\($0.name)" }.joined(separator: ","),
            ].joined(separator: "|")
            return enriched
        }
    )
    private lazy var radialMenuTriggerController = RadialMenuTriggerController(
        menuController: radialMenuController,
        diagnostics: diagnostics
    )
    private lazy var globeFnHoldActivationController: GlobeFnHoldActivationController = {
        let controller = GlobeFnHoldActivationController(
            radialTrigger: radialMenuTriggerController,
            diagnostics: diagnostics
        )
        controller.runtimeIssueChanged = { [weak self] issue in
            self?.settingsStore.setGlobeFnRuntimeIssue(issue)
        }
        return controller
    }()
    private lazy var workspaceSwipeController: WorkspaceSwipeController = {
        let controller = WorkspaceSwipeController(
            dispatcher: commandDispatcher,
            diagnostics: diagnostics
        )
        controller.runtimeIssueChanged = { [weak self] issue in
            self?.settingsStore.setWorkspaceSwipeRuntimeIssue(issue)
        }
        return controller
    }()
    private lazy var commandFeedbackPresenter: CommandFeedbackPresenting =
        CommandFeedbackOverlayController(diagnostics: diagnostics)
    private lazy var focusedWindowHighlightPresenter: FocusedWindowHighlightPresenting =
        FocusedWindowHighlightController(diagnostics: diagnostics)
    private lazy var hotKeyManager: HotKeyManager = {
        let manager = HotKeyManager(
            dispatcher: commandDispatcher,
            diagnostics: diagnostics,
            radialMenuTrigger: { [weak self] event in
                guard let self else { return }
                self.globeFnHoldActivationController.ordinaryShortcutWillBegin()
                self.radialMenuTriggerController.handle(
                    event,
                    style: self.settingsStore.radialMenuActivationStyle,
                    holdDelay: self.settingsStore.radialMenuHoldDelay
                )
            }
        )
        manager.directionalMoveGestureRuntimeIssueChanged = { [weak self] issue in
            self?.settingsStore.setDirectionalMoveGestureRuntimeIssue(issue)
        }
        return manager
    }()
    private var workspaceStatusBarController: WorkspaceStatusBarController?
    private var cancellables = Set<AnyCancellable>()
    private var preparedForTermination = false
    private var isShortcutRecording = false
    private var fullscreenGameSession: FullscreenGameSessionSnapshot?
    private var isForegroundDeclaredGameApplication = false
    private var pendingMenuBarPresentationUpdate: DispatchWorkItem?
    private var pendingMenuBarWorkspaceLabelUpdate: DispatchWorkItem?
    private var pendingMenuBarDisplayIconUpdate: DispatchWorkItem?
    private var pendingMenuBarHighlightUpdate: DispatchWorkItem?
    private let tiledPlacementUndoManager = UndoManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        ApplicationIdentityMigration.perform()
        NSApp.setActivationPolicy(.accessory)
        guard settingsStore.workspaces.first != nil else { return }

        engine.onStateChanged = { [weak self] state in
            guard let self else { return }
            self.menuBarState.update(
                state: state,
                workspaces: self.settingsStore.workspaces,
                displayMode: self.settingsStore.multiDisplayMode,
                connectedDisplays: self.settingsStore.connectedDisplays,
                workspaceDisplayAssignments: self.settingsStore.workspaceDisplayAssignments
            )
            self.workspaceStatusBarController?.rebuild()
            self.settingsWindowCoordinator.workspaceStateDidChange(state)
            self.radialMenuController.contextDidPossiblyChange()
            self.settingsStore.recordActiveWorkspaceState(state)
            self.focusedWindowHighlightPresenter.updateWorkspaceContexts(
                state.focusedWindowHighlightWorkspaceContexts
            )
        }
        engine.onWorkspaceLayoutChanged = { [weak self] workspaceID, layout in
            self?.settingsStore.setLayout(layout, for: workspaceID)
        }
        engine.onWorkspaceLayoutConfigurationChanged = { [weak self] workspaceID, configuration in
            self?.settingsStore.setLayoutConfiguration(configuration, for: workspaceID)
        }
        engine.onTiledPlacementCommitted = { [weak self] transaction in
            self?.registerTiledPlacementHistory(transaction, direction: .undo)
        }
        engine.onFreeformPlacementCommitted = { [weak self] transaction in
            self?.registerFreeformPlacementHistory(transaction, direction: .undo)
        }
        engine.onCommandFeedback = { [weak self] request in
            guard let self else { return }
            if let gameSession = self.fullscreenGameSession,
               request.preferredDisplayIdentifier == nil ||
                request.preferredDisplayIdentifier == gameSession.displayIdentifier {
                self.diagnostics.log(
                    category: "fullscreen-session",
                    event: "command-feedback-suppressed",
                    correlation: request.correlationID,
                    fields: ["display": gameSession.displayIdentifier]
                )
                return
            }
            self.commandFeedbackPresenter.present(request)
        }
        engine.onVerifiedFocusTarget = { [weak self] target in
            self?.focusedWindowHighlightPresenter.updateVerifiedFocusTarget(target)
        }
        engine.onFullscreenGameSessionChanged = { [weak self] session in
            guard let self, self.fullscreenGameSession != session else { return }
            self.fullscreenGameSession = session
            self.focusedWindowHighlightPresenter.setSuppressed(
                session != nil,
                reason: session == nil ? "fullscreen-game-ended" : "fullscreen-game-session"
            )
            self.workspaceSwipeController.setSuppressed(
                session != nil,
                reason: "fullscreen-game-session"
            )
            if session != nil {
                self.hotKeyManager.cancelDirectionalMoveGesture(reason: "fullscreen-game-session")
                self.globeFnHoldActivationController.cancel(reason: "fullscreen-game-session")
                self.radialMenuTriggerController.cancel(reason: "fullscreen-game-session")
                self.commandFeedbackPresenter.dismiss(reason: "fullscreen-game-session")
            }
            self.registerHotKeys()
            self.updateGlobeFnHoldActivation()
        }
        engine.onWorkspaceDisplayAssignmentsChanged = { [weak self] assignments in
            self?.settingsStore.assignWorkspaces(assignments)
        }
        if let frontmostApplication = NSWorkspace.shared.frontmostApplication {
            updateForegroundDeclaredGameInputProtection(for: frontmostApplication)
        }
        registerHotKeys()
        updateGlobeFnHoldActivation()
        updateWorkspaceSwipeActivation()
        engine.start()
        updateMenuBarPresentation()
        focusedWindowHighlightPresenter.update(
            enabled: settingsStore.focusedWindowHighlightEnabled,
            color: settingsStore.focusedWindowHighlightColor.nsColor,
            filters: FocusedWindowHighlightFilters(
                tiledWorkspacesOnly: settingsStore.focusedWindowHighlightTiledOnly,
                multipleWindowsOnly: settingsStore.focusedWindowHighlightMultipleWindowsOnly
            )
        )
        focusedWindowHighlightPresenter.updateCornerRadiusOverrides(
            settingsStore.focusedWindowHighlightCornerRadiusOverrides
        )

        settingsStore.$workspaces
            .dropFirst()
            .filter { [weak self] _ in self?.settingsStore.isApplyingProfileActivation == false }
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] workspaces in
                guard let self else { return }
                self.clearTiledPlacementHistory()
                self.engine.updateWorkspaces(workspaces)
                self.registerHotKeys()
                self.menuBarState.updateConfiguration(
                    workspaces: workspaces,
                    displayMode: self.settingsStore.multiDisplayMode,
                    connectedDisplays: self.settingsStore.connectedDisplays,
                    workspaceDisplayAssignments: self.settingsStore.workspaceDisplayAssignments
                )
                self.workspaceStatusBarController?.rebuild()
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .compactMap { notification in
                notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            }
            .sink { [weak self] application in
                guard let self else { return }
                self.updateForegroundDeclaredGameInputProtection(for: application)
                self.hotKeyManager.cancelDirectionalMoveGesture(reason: "application-activated")
                self.workspaceSwipeController.cancel(reason: "application-activated")
                self.engine.applicationActivated(
                    processIdentifier: application.processIdentifier
                ) { [weak self] shouldCancelRadialInteraction in
                    guard let self, shouldCancelRadialInteraction else { return }
                    self.globeFnHoldActivationController.cancel(reason: "application-activated")
                    self.radialMenuTriggerController.cancel(reason: "application-activated")
                }
            }
            .store(in: &cancellables)

        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        workspaceNotifications.publisher(for: NSWorkspace.willSleepNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.clearTiledPlacementHistory()
                self.hotKeyManager.cancelDirectionalMoveGesture(reason: "system-will-sleep")
                self.globeFnHoldActivationController.cancel(reason: "system-will-sleep")
                self.workspaceSwipeController.setSuppressed(true, reason: "system-sleep")
                self.radialMenuTriggerController.cancel(reason: "system-will-sleep")
                self.commandFeedbackPresenter.dismiss(reason: "system-will-sleep")
                self.focusedWindowHighlightPresenter.setSuppressed(
                    true,
                    reason: "system-will-sleep"
                )
                self.engine.prepareForSystemSleep()
            }
            .store(in: &cancellables)

        workspaceNotifications.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reconcileAfterWake(source: .systemWake)
            }
            .store(in: &cancellables)

        workspaceNotifications.publisher(for: NSWorkspace.screensDidWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reconcileAfterWake(source: .screensWake)
            }
            .store(in: &cancellables)

        workspaceNotifications.publisher(for: NSWorkspace.sessionDidBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reconcileAfterWake(source: .sessionBecameActive)
            }
            .store(in: &cancellables)

        workspaceNotifications.publisher(for: NSWorkspace.sessionDidResignActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.hotKeyManager.cancelDirectionalMoveGesture(reason: "session-resigned-active")
                self?.globeFnHoldActivationController.cancel(reason: "session-resigned-active")
                self?.workspaceSwipeController.setSuppressed(true, reason: "session-inactive")
                self?.radialMenuTriggerController.cancel(reason: "session-resigned-active")
                self?.focusedWindowHighlightPresenter.setSuppressed(
                    true,
                    reason: "session-resigned-active"
                )
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.hotKeyManager.cancelDirectionalMoveGesture(reason: "display-configuration-changed")
                self?.workspaceSwipeController.cancel(reason: "display-configuration-changed")
                self?.commandFeedbackPresenter.screenParametersDidChange()
                self?.focusedWindowHighlightPresenter.screenParametersDidChange()
                self?.settingsWindowCoordinator.screenParametersDidChange()
                self?.reconcileAfterWake(source: .displayConfigurationChanged)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            settingsStore.$multiDisplayMode.removeDuplicates(),
            settingsStore.$workspaceDisplayHomesForEngine.removeDuplicates()
        )
        .dropFirst()
        .filter { [weak self] _ in self?.settingsStore.isApplyingProfileActivation == false }
        .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
        .sink { [weak self] configuration in
            guard let self else { return }
            self.clearTiledPlacementHistory()
            let (mode, workspaceDisplayHomes) = configuration
            self.engine.updateDisplayConfiguration(
                mode: mode,
                workspaceDisplayAssignments: workspaceDisplayHomes
            )
        }
        .store(in: &cancellables)

        Publishers.CombineLatest3(
            settingsStore.$multiDisplayMode.removeDuplicates(),
            settingsStore.$connectedDisplays.removeDuplicates(),
            settingsStore.$workspaceDisplayAssignments.removeDuplicates()
        )
        .dropFirst()
        .debounce(for: .milliseconds(40), scheduler: RunLoop.main)
        .sink { [weak self] mode, displays, assignments in
            guard let self else { return }
            self.menuBarState.updateConfiguration(
                workspaces: self.settingsStore.workspaces,
                displayMode: mode,
                connectedDisplays: displays,
                workspaceDisplayAssignments: assignments
            )
            self.workspaceStatusBarController?.rebuild()
        }
        .store(in: &cancellables)

        settingsStore.$appRules
            .dropFirst()
            .filter { [weak self] _ in self?.settingsStore.isApplyingProfileActivation == false }
            .removeDuplicates()
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] rules in
                self?.engine.updateAppRules(rules)
            }
            .store(in: &cancellables)

        settingsStore.$radialMenuEnabled
        .removeDuplicates()
        .dropFirst()
        .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
        .sink { [weak self] enabled in
            guard let self else { return }
            if !enabled {
                self.globeFnHoldActivationController.cancel(reason: "wheel-disabled")
                self.radialMenuTriggerController.cancel(reason: "wheel-disabled")
            }
            self.registerHotKeys()
            self.updateGlobeFnHoldActivation(radialMenuEnabled: enabled)
        }
        .store(in: &cancellables)

        settingsStore.$dropDownApp
            .dropFirst()
            .filter { [weak self] _ in self?.settingsStore.isApplyingProfileActivation == false }
            .removeDuplicates()
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] configuration in
                self?.engine.updateDropDownAppConfiguration(configuration)
            }
            .store(in: &cancellables)

        settingsStore.$radialMenuGlobeFnHoldEnabled
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] enabled in
                // @Published delivers in willSet. Use the emitted value rather than rereading the
                // store synchronously, otherwise switching this option on observes the old false
                // value and never installs the event monitor.
                self?.updateGlobeFnHoldActivation(globeFnEnabled: enabled)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            settingsStore.$workspaceSwipeEnabled.removeDuplicates(),
            settingsStore.$workspaceSwipeFingerCount.removeDuplicates()
        )
        .dropFirst()
        .sink { [weak self] enabled, fingerCount in
            self?.updateWorkspaceSwipeActivation(
                enabled: enabled,
                fingerCount: fingerCount
            )
        }
        .store(in: &cancellables)

        settingsStore.$radialMenuHoldDelay
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] delay in
                guard let self else { return }
                self.globeFnHoldActivationController.cancel(reason: "hold-delay-changed")
                self.radialMenuTriggerController.cancel(reason: "hold-delay-changed")
                self.updateGlobeFnHoldActivation(holdDelay: delay)
            }
            .store(in: &cancellables)

        settingsStore.$radialWheelDefinition
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.globeFnHoldActivationController.cancel(reason: "wheel-definition-changed")
                self?.radialMenuTriggerController.cancel(reason: "wheel-definition-changed")
            }
            .store(in: &cancellables)

        settingsStore.$radialMenuActivationStyle
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.globeFnHoldActivationController.cancel(reason: "wheel-activation-style-changed")
                self?.radialMenuTriggerController.cancel(reason: "wheel-activation-style-changed")
            }
            .store(in: &cancellables)

        settingsStore.$focusFollowsMovedWindow
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.engine.updateFocusFollowsMovedWindow(enabled)
            }
            .store(in: &cancellables)

        settingsStore.$automaticallyUnhideApplications
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.engine.updateAutomaticallyUnhideApplications(enabled)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest4(
            settingsStore.$focusedWindowHighlightEnabled.removeDuplicates(),
            settingsStore.$focusedWindowHighlightColor.removeDuplicates(),
            settingsStore.$focusedWindowHighlightTiledOnly.removeDuplicates(),
            settingsStore.$focusedWindowHighlightMultipleWindowsOnly.removeDuplicates()
        )
        .dropFirst()
        .sink { [weak self] enabled, color, tiledOnly, multipleWindowsOnly in
            self?.engine.updateFocusedWindowHighlight(enabled: enabled)
            self?.focusedWindowHighlightPresenter.update(
                enabled: enabled,
                color: color.nsColor,
                filters: FocusedWindowHighlightFilters(
                    tiledWorkspacesOnly: tiledOnly,
                    multipleWindowsOnly: multipleWindowsOnly
                )
            )
        }
        .store(in: &cancellables)

        settingsStore.$focusedWindowHighlightCornerRadiusOverrides
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] overrides in
                self?.focusedWindowHighlightPresenter.updateCornerRadiusOverrides(overrides)
            }
            .store(in: &cancellables)

        settingsStore.$menuBarPresentationMode
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] mode in
                self?.scheduleMenuBarPresentationUpdate(mode)
            }
            .store(in: &cancellables)

        settingsStore.$menuBarWorkspaceLabelMode
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] mode in
                self?.scheduleMenuBarWorkspaceLabelUpdate(mode)
            }
            .store(in: &cancellables)

        let menuBarDisplayIconChanges: [AnyPublisher<Void, Never>] = [
            settingsStore.$profiles
                .removeDuplicates()
                .dropFirst()
                .map { _ in () }
                .eraseToAnyPublisher(),
            settingsStore.$activeProfileID
                .removeDuplicates()
                .dropFirst()
                .map { _ in () }
                .eraseToAnyPublisher(),
            settingsStore.$localProfileState
                .map(\.roleBindings)
                .removeDuplicates()
                .dropFirst()
                .map { _ in () }
                .eraseToAnyPublisher(),
            settingsStore.$connectedDisplays
                .removeDuplicates()
                .dropFirst()
                .map { _ in () }
                .eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(menuBarDisplayIconChanges)
            .sink { [weak self] _ in
                self?.scheduleMenuBarDisplayIconUpdate()
            }
            .store(in: &cancellables)

        settingsStore.$menuBarHighlightColor
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] color in
                self?.scheduleMenuBarHighlightUpdate(color)
            }
            .store(in: &cancellables)

        settingsStore.$hotKeyConfiguration
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.globeFnHoldActivationController.cancel(reason: "shortcut-configuration-changed")
                self.radialMenuTriggerController.cancel(reason: "shortcut-configuration-changed")
                self.registerHotKeys()
            }
            .store(in: &cancellables)

        settingsStore.$profileActivationRequest
            .dropFirst()
            .compactMap { $0 }
            .sink { [weak self] request in
                guard let self else { return }
                self.clearTiledPlacementHistory()
                self.hotKeyManager.cancelDirectionalMoveGesture(reason: "profile-transition")
                self.globeFnHoldActivationController.cancel(reason: "profile-transition")
                self.workspaceSwipeController.cancel(reason: "profile-transition")
                self.radialMenuTriggerController.cancel(reason: "profile-transition")
                self.commandFeedbackPresenter.dismiss(reason: "profile-transition")
                self.engine.transitionToProfile(request)
                self.registerHotKeys()
                self.menuBarState.updateConfiguration(
                    workspaces: self.settingsStore.workspaces,
                    displayMode: self.settingsStore.multiDisplayMode,
                    connectedDisplays: self.settingsStore.connectedDisplays,
                    workspaceDisplayAssignments: self.settingsStore.workspaceDisplayAssignments
                )
                self.workspaceStatusBarController?.rebuild()
            }
            .store(in: &cancellables)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        prepareForTerminationIfNeeded()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        prepareForTerminationIfNeeded()
    }

    private func prepareForTerminationIfNeeded() {
        guard !preparedForTermination else { return }
        preparedForTermination = true
        pendingMenuBarPresentationUpdate?.cancel()
        pendingMenuBarPresentationUpdate = nil
        pendingMenuBarWorkspaceLabelUpdate?.cancel()
        pendingMenuBarWorkspaceLabelUpdate = nil
        pendingMenuBarDisplayIconUpdate?.cancel()
        pendingMenuBarDisplayIconUpdate = nil
        pendingMenuBarHighlightUpdate?.cancel()
        pendingMenuBarHighlightUpdate = nil
        tiledPlacementUndoManager.removeAllActions()
        hotKeyManager.cancelDirectionalMoveGesture(reason: "application-terminating")
        globeFnHoldActivationController.shutdown()
        workspaceSwipeController.shutdown()
        radialMenuTriggerController.cancel(reason: "application-terminating")
        commandFeedbackPresenter.shutdown()
        focusedWindowHighlightPresenter.shutdown()
        settingsWindowCoordinator.shutdown()
        workspaceStatusBarController?.invalidate()
        workspaceStatusBarController = nil
        engine.stopAndRestoreAllWindows()
    }

    private func registerHotKeys() {
        guard !isShortcutRecording else { return }
        let report = hotKeyManager.register(
            workspaces: settingsStore.workspaces,
            hotKeyConfiguration: settingsStore.hotKeyConfiguration,
            radialMenuEnabled: settingsStore.radialMenuEnabled,
            scope: fullscreenGameSession == nil ? .all : .workspaceNavigationOnly
        )
        settingsStore.setHotKeyRuntimeIssues(report.runtimeIssues)
    }

    func shortcutRecordingStateDidChange(_ isRecording: Bool) {
        guard isShortcutRecording != isRecording else { return }
        isShortcutRecording = isRecording
        if isRecording {
            hotKeyManager.cancelDirectionalMoveGesture(reason: "shortcut-recording-began")
            globeFnHoldActivationController.cancel(reason: "shortcut-recording-began")
            workspaceSwipeController.setSuppressed(true, reason: "shortcut-recording")
            radialMenuTriggerController.cancel(reason: "shortcut-recording-began")
            hotKeyManager.suspendRegistration()
            settingsStore.setHotKeyRuntimeIssues([])
        } else {
            registerHotKeys()
            workspaceSwipeController.setSuppressed(false, reason: "shortcut-recording")
        }
        updateGlobeFnHoldActivation()
    }

    private func reconcileAfterWake(source: WakeReconciliationSource) {
        hotKeyManager.cancelDirectionalMoveGesture(reason: source.rawValue)
        globeFnHoldActivationController.resumeAfterLifecycle(reason: source.rawValue)
        switch source {
        case .systemWake, .screensWake:
            workspaceSwipeController.setSuppressed(false, reason: "system-sleep")
        case .sessionBecameActive:
            workspaceSwipeController.setSuppressed(false, reason: "system-sleep")
            workspaceSwipeController.setSuppressed(false, reason: "session-inactive")
        case .displayConfigurationChanged:
            workspaceSwipeController.cancel(reason: source.rawValue)
        }
        radialMenuTriggerController.cancel(reason: source.rawValue)
        commandFeedbackPresenter.dismiss(reason: source.rawValue)
        focusedWindowHighlightPresenter.setSuppressed(
            fullscreenGameSession != nil,
            reason: source.rawValue
        )
        // Monitor pins/fingerprints must resolve before the engine reconciles workspace homes.
        settingsStore.refreshConnectedDisplays()
        engine.requestWakeReconciliation(
            source: source,
            workspaceDisplayAssignments: settingsStore.workspaceDisplayHomesForEngine
        )
    }

    private func updateGlobeFnHoldActivation(
        radialMenuEnabled: Bool? = nil,
        globeFnEnabled: Bool? = nil,
        holdDelay: TimeInterval? = nil
    ) {
        let runtimeSettings = GlobeFnRuntimeSettings(
            radialMenuEnabled: radialMenuEnabled ?? settingsStore.radialMenuEnabled,
            globeFnEnabled: globeFnEnabled ?? settingsStore.radialMenuGlobeFnHoldEnabled,
            isShortcutRecording: isShortcutRecording,
            holdDelay: holdDelay ?? settingsStore.radialMenuHoldDelay
        )
        let inputMonitoringSuppressed = ForegroundGameInputProtectionPolicy
            .shouldSuppressOptionalInputMonitors(
                isDeclaredGameApplicationActive: isForegroundDeclaredGameApplication,
                hasNativeFullscreenGameSession: fullscreenGameSession != nil
            )
        globeFnHoldActivationController.update(
            enabled: runtimeSettings.isEnabled && !inputMonitoringSuppressed,
            holdDelay: runtimeSettings.holdDelay
        )
    }

    private func updateWorkspaceSwipeActivation(
        enabled: Bool? = nil,
        fingerCount: WorkspaceSwipeFingerCount? = nil
    ) {
        workspaceSwipeController.update(
            enabled: enabled ?? settingsStore.workspaceSwipeEnabled,
            fingerCount: fingerCount ?? settingsStore.workspaceSwipeFingerCount
        )
        workspaceSwipeController.setSuppressed(
            fullscreenGameSession != nil,
            reason: "fullscreen-game-session"
        )
        workspaceSwipeController.setSuppressed(
            isForegroundDeclaredGameApplication,
            reason: "foreground-declared-game"
        )
        workspaceSwipeController.setSuppressed(
            isShortcutRecording,
            reason: "shortcut-recording"
        )
    }

    private func updateForegroundDeclaredGameInputProtection(
        for application: NSRunningApplication
    ) {
        let bundle = application.bundleURL.flatMap { Bundle(url: $0) }
        let isDeclaredGame = FullscreenGameMetadataPolicy.isDeclaredGame(bundle: bundle)
        guard isForegroundDeclaredGameApplication != isDeclaredGame else { return }
        isForegroundDeclaredGameApplication = isDeclaredGame

        let reason = isDeclaredGame ? "foreground-declared-game" : "foreground-declared-game-ended"
        diagnostics.log(
            category: "input-protection",
            event: isDeclaredGame ? "foreground-game-started" : "foreground-game-ended",
            fields: [
                "bundle": application.bundleIdentifier ?? "unknown",
                "active-input-filter": "false",
            ]
        )
        if isDeclaredGame {
            globeFnHoldActivationController.cancel(reason: reason)
            radialMenuTriggerController.cancel(reason: reason)
            commandFeedbackPresenter.dismiss(reason: reason)
        }
        updateGlobeFnHoldActivation()
        updateWorkspaceSwipeActivation()
    }

    private func scheduleMenuBarPresentationUpdate(_ mode: MenuBarPresentationMode) {
        // A segmented Picker publishes while SwiftUI is updating its view hierarchy. Coalescing on
        // the next main-loop turn avoids re-entrant view publication and guarantees rapid changes
        // finish on the newest requested presentation without removing the NSStatusItem.
        pendingMenuBarPresentationUpdate?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingMenuBarPresentationUpdate = nil
            self.workspaceStatusBarController?.setPresentationMode(mode)
        }
        pendingMenuBarPresentationUpdate = work
        DispatchQueue.main.async(execute: work)
    }

    private func scheduleMenuBarHighlightUpdate(_ color: MenuBarHighlightColor) {
        pendingMenuBarHighlightUpdate?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingMenuBarHighlightUpdate = nil
            self.workspaceStatusBarController?.setHighlightColor(color)
        }
        pendingMenuBarHighlightUpdate = work
        DispatchQueue.main.async(execute: work)
    }

    private func scheduleMenuBarWorkspaceLabelUpdate(_ mode: MenuBarWorkspaceLabelMode) {
        pendingMenuBarWorkspaceLabelUpdate?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingMenuBarWorkspaceLabelUpdate = nil
            self.workspaceStatusBarController?.setWorkspaceLabelMode(mode)
        }
        pendingMenuBarWorkspaceLabelUpdate = work
        DispatchQueue.main.async(execute: work)
    }

    private func scheduleMenuBarDisplayIconUpdate() {
        pendingMenuBarDisplayIconUpdate?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingMenuBarDisplayIconUpdate = nil
            // @Published sends from willSet. Resolve only after this deferred work runs so all
            // contributing profile, binding, and display properties contain their committed values.
            self.workspaceStatusBarController?.setDisplayIconConfiguration(
                self.settingsStore.menuBarDisplayIconConfiguration
            )
        }
        pendingMenuBarDisplayIconUpdate = work
        DispatchQueue.main.async(execute: work)
    }

    private func updateMenuBarPresentation() {
        menuBarState.updateConfiguration(
            workspaces: settingsStore.workspaces,
            displayMode: settingsStore.multiDisplayMode,
            connectedDisplays: settingsStore.connectedDisplays,
            workspaceDisplayAssignments: settingsStore.workspaceDisplayAssignments
        )
        if workspaceStatusBarController == nil {
            workspaceStatusBarController = WorkspaceStatusBarController(
                engine: engine,
                stateModel: menuBarState,
                settingsStore: settingsStore,
                settingsCommandRequestRouter: settingsCommandRequestRouter,
                diagnostics: diagnostics,
                tiledPlacementUndoManager: tiledPlacementUndoManager,
                initialMode: settingsStore.menuBarPresentationMode,
                initialWorkspaceLabelMode: settingsStore.menuBarWorkspaceLabelMode,
                initialDisplayIconConfiguration: settingsStore.menuBarDisplayIconConfiguration,
                initialHighlightColor: settingsStore.menuBarHighlightColor
            )
        } else {
            workspaceStatusBarController?.setPresentationMode(
                settingsStore.menuBarPresentationMode
            )
            workspaceStatusBarController?.setWorkspaceLabelMode(
                settingsStore.menuBarWorkspaceLabelMode
            )
            workspaceStatusBarController?.setDisplayIconConfiguration(
                settingsStore.menuBarDisplayIconConfiguration
            )
            workspaceStatusBarController?.setHighlightColor(
                settingsStore.menuBarHighlightColor
            )
        }
    }

    private func registerTiledPlacementHistory(
        _ transaction: TiledPlacementUndoTransaction,
        direction: TiledPlacementHistoryDirection
    ) {
        tiledPlacementUndoManager.registerUndo(withTarget: self) { target in
            guard target.engine.applyTiledPlacementHistory(
                transaction,
                direction: direction
            ) else {
                target.workspaceStatusBarController?.rebuild()
                return
            }
            target.registerTiledPlacementHistory(
                transaction,
                direction: direction == .undo ? .redo : .undo
            )
        }
        tiledPlacementUndoManager.setActionName(transaction.actionName)
        workspaceStatusBarController?.rebuild()
    }

    private func registerFreeformPlacementHistory(
        _ transaction: FreeformPlacementUndoTransaction,
        direction: FreeformPlacementHistoryDirection
    ) {
        tiledPlacementUndoManager.registerUndo(withTarget: self) { target in
            guard target.engine.applyFreeformPlacementHistory(
                transaction,
                direction: direction
            ) else {
                target.workspaceStatusBarController?.rebuild()
                return
            }
            target.registerFreeformPlacementHistory(
                transaction,
                direction: direction == .undo ? .redo : .undo
            )
        }
        tiledPlacementUndoManager.setActionName(transaction.actionName)
        workspaceStatusBarController?.rebuild()
    }

    private func clearTiledPlacementHistory() {
        guard tiledPlacementUndoManager.canUndo || tiledPlacementUndoManager.canRedo else { return }
        tiledPlacementUndoManager.removeAllActions()
        workspaceStatusBarController?.rebuild()
    }
}
