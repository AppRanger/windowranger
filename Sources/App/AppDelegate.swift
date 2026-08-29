import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let diagnostics = DiagnosticLogger.makeAppLogger()
    lazy var settingsStore = SettingsStore(diagnostics: diagnostics)
    lazy var workspacePreviewRepository = WorkspacePreviewRepository(
        isEnabled: settingsStore.workspacePreviewThumbnailsEnabled
    )
    lazy var settingsNavigation = SettingsNavigationModel()
    lazy var updateController = UpdateController()
    lazy var settingsWindowCoordinator = SettingsWindowCoordinator(diagnostics: diagnostics)
    lazy var settingsCommandRequestRouter = SettingsCommandRequestRouter()
    private lazy var onboardingWindowController = OnboardingWindowController(
        settingsStore: settingsStore,
        diagnostics: diagnostics
    )
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
        quickApps: settingsStore.quickApps,
        quickAppShelfPresentation: settingsStore.quickAppShelfPresentation,
        selectedQuickAppBundleIdentifier: settingsStore.selectedQuickAppBundleIdentifier,
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
        },
        addCurrentApplication: { [weak self] bundleIdentifier, displayName, workspaceID, profileID, expectedMembership, _ in
            Task { @MainActor [weak self] in
                self?.settingsStore.addCurrentApplicationRule(
                    bundleIdentifier: bundleIdentifier,
                    displayName: displayName,
                    defaultWorkspaceID: workspaceID,
                    expectedActiveProfileID: profileID,
                    expectedMembership: expectedMembership
                )
            }
        },
        removeCurrentApplication: { [weak self] bundleIdentifier, profileID, expectedMembership, _ in
            Task { @MainActor [weak self] in
                self?.settingsStore.removeCurrentApplicationRule(
                    bundleIdentifier: bundleIdentifier,
                    expectedActiveProfileID: profileID,
                    expectedMembership: expectedMembership
                )
            }
        },
        addCurrentApplicationToQuickAppShelf: { [weak self] bundleIdentifier, displayName, profileID, expectedMembership, _ in
            Task { @MainActor [weak self] in
                self?.settingsStore.addCurrentApplicationToQuickAppShelf(
                    bundleIdentifier: bundleIdentifier,
                    displayName: displayName,
                    expectedActiveProfileID: profileID,
                    expectedMembership: expectedMembership
                )
            }
        },
        setPauseMode: { [weak self] isPaused, correlationID in
            Task { @MainActor [weak self] in
                self?.setPauseMode(isPaused, source: "command-palette", correlationID: correlationID)
            }
        }
    )
    private lazy var commandPaletteController = CommandPaletteController(
        engine: engine,
        dispatcher: commandDispatcher,
        diagnostics: diagnostics,
        contextEnricher: { [weak self] context in
            self?.enrichedCommandContext(context) ?? context
        },
        hotKeyConfigurationProvider: { [weak self] in
            self?.settingsStore.hotKeyConfiguration ?? HotKeyConfiguration()
        },
        positionProvider: { [weak self] in
            self?.settingsStore.commandPalettePosition ?? .defaultValue
        },
        isPauseModeEnabledProvider: { [weak self] in
            self?.isPauseModeEnabled ?? false
        },
        openSettings: { [weak self] in
            guard let self else { return }
            self.settingsCommandRequestRouter.prepare(.applicationMenuDefault)
            if !SettingsMenuCommandDispatcher.performSettingsCommand(in: NSApp.mainMenu) {
                self.settingsCommandRequestRouter.cancelPendingRequest()
            }
        }
    )
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
    private lazy var shortcutGuideController = ShortcutGuidePanelController()
    private lazy var shortcutGuideModifierMonitor = ShortcutGuideModifierMonitor()
    private lazy var focusedWindowHighlightPresenter: FocusedWindowHighlightPresenting =
        FocusedWindowHighlightController(diagnostics: diagnostics)
    private lazy var tiledResizePreviewPresenter: TiledResizePreviewPresenting =
        TiledResizePreviewController(diagnostics: diagnostics)
    private lazy var tiledResizePointerMonitor = TiledResizePointerMonitor(
        onDragged: { [weak self] in self?.engine.tiledResizePointerDragged() },
        onReleased: { [weak self] in self?.engine.tiledResizePointerReleased() }
    )
    private lazy var hotKeyManager: HotKeyManager = {
        let manager = HotKeyManager(
            dispatcher: commandDispatcher,
            diagnostics: diagnostics,
            radialMenuTrigger: { [weak self] event in
                guard let self else { return }
                switch event {
                case .pressed:
                    self.shortcutGuideController.dismiss()
                    self.commandPaletteController.toggle()
                case .released:
                    break
                case .escape:
                    self.commandPaletteController.dismiss(
                        reason: "escape",
                        restorePreviousApplication: true
                    )
                }
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
    private var isPauseModeEnabled = false
    private var pendingPausedProfileActivationRequest: ProfileActivationRequest?
    private var fullscreenGameSession: FullscreenGameSessionSnapshot?
    private var isForegroundDeclaredGameApplication = false
    private var shortcutGuideObservationGeneration = ShortcutGuideObservationGeneration()
    private var activeShortcutGuideModifierFamily: ShortcutFamily?
    private var presentedShortcutGuideShelfContext: ShortcutGuideShelfRuntimeContext?
    private var pendingMenuBarPresentationUpdate: DispatchWorkItem?
    private var pendingMenuBarWorkspaceLabelUpdate: DispatchWorkItem?
    private var pendingMenuBarDisplayIconUpdate: DispatchWorkItem?
    private var pendingMenuBarHighlightUpdate: DispatchWorkItem?
    private var screenLockNotificationsRegistered = false
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
            self.commandPaletteController.contextDidPossiblyChange()
            self.settingsStore.recordActiveWorkspaceState(state)
            self.focusedWindowHighlightPresenter.updateWorkspaceContexts(
                state.focusedWindowHighlightWorkspaceContexts
            )
            self.refreshShortcutGuideForShelfTransitionIfNeeded()
        }
        engine.onWorkspacePreviewStateChanged = { [weak self] workspaceIDs in
            self?.workspacePreviewRepository.invalidate(workspaceIDs: workspaceIDs)
        }
        engine.onQuickAppSelectionChanged = { [weak self] bundleIdentifier in
            Task { @MainActor [weak self] in
                self?.settingsStore.recordSelectedQuickApp(bundleIdentifier: bundleIdentifier)
            }
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
            guard !self.isPauseModeEnabled else {
                self.diagnostics.log(
                    category: "pause-mode",
                    event: "command-feedback-suppressed",
                    correlation: request.correlationID
                )
                return
            }
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
        engine.onTiledResizePreviewChanged = { [weak self] event in
            guard let self else { return }
            switch event {
            case let .present(presentation):
                self.focusedWindowHighlightPresenter.setSuppressed(
                    true,
                    reason: "tiled-resize-preview"
                )
                self.tiledResizePreviewPresenter.present(presentation)
            case let .dismiss(token, reason):
                if self.tiledResizePreviewPresenter.dismiss(token: token, reason: reason) {
                    self.focusedWindowHighlightPresenter.setSuppressed(
                        self.fullscreenGameSession != nil || self.isPauseModeEnabled,
                        reason: "tiled-resize-preview-ended"
                    )
                }
            }
        }
        engine.onFullscreenGameSessionChanged = { [weak self] session in
            guard let self, self.fullscreenGameSession != session else { return }
            self.fullscreenGameSession = session
            self.settingsStore.setGameModeActive(session?.isGameModeEligible == true)
            self.focusedWindowHighlightPresenter.setSuppressed(
                session != nil || self.isPauseModeEnabled,
                reason: session == nil ? "fullscreen-game-ended" : "fullscreen-game-session"
            )
            self.workspaceSwipeController.setSuppressed(
                session != nil,
                reason: "fullscreen-game-session"
            )
            if session != nil, !self.isPauseModeEnabled {
                self.hotKeyManager.cancelDirectionalMoveGesture(reason: "fullscreen-game-session")
                self.commandPaletteController.dismiss(reason: "fullscreen-game-session")
                self.commandFeedbackPresenter.dismiss(reason: "fullscreen-game-session")
            }
            self.registerHotKeys(source: "fullscreen-game-session")
            self.updateShortcutGuideActivation()
        }
        engine.onWorkspaceDisplayAssignmentsChanged = { [weak self] assignments in
            self?.settingsStore.assignWorkspaces(assignments)
        }
        if let frontmostApplication = NSWorkspace.shared.frontmostApplication {
            updateForegroundDeclaredGameInputProtection(for: frontmostApplication)
        }
        registerHotKeys(source: "application-startup")
        updateWorkspaceSwipeActivation()
        updateShortcutGuideActivation()
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
                self.registerHotKeys(source: "workspace-settings-changed", workspaces: workspaces)
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
                self.workspaceStatusBarController?.applicationActivated()
                self.engine.applicationActivated(processIdentifier: application.processIdentifier)
            }
            .store(in: &cancellables)

        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        registerScreenLockNotifications()
        workspaceNotifications.publisher(for: NSWorkspace.willSleepNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.clearTiledPlacementHistory()
                self.hotKeyManager.cancelDirectionalMoveGesture(reason: "system-will-sleep")
                self.workspaceSwipeController.setSuppressed(true, reason: "system-sleep")
                self.commandPaletteController.dismiss(reason: "system-will-sleep")
                self.commandFeedbackPresenter.dismiss(reason: "system-will-sleep")
                self.stopShortcutGuideObservation()
                self.focusedWindowHighlightPresenter.setSuppressed(
                    true,
                    reason: "system-will-sleep"
                )
                self.workspacePreviewRepository.purge()
                self.engine.prepareForSystemSleep()
            }
            .store(in: &cancellables)

        workspaceNotifications.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reconcileAfterWake(source: .systemWake)
            }
            .store(in: &cancellables)

        workspaceNotifications.publisher(for: NSWorkspace.screensDidSleepNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.hotKeyManager.cancelDirectionalMoveGesture(reason: "screens-did-sleep")
                self.workspaceSwipeController.setSuppressed(true, reason: "screen-sleep")
                self.commandPaletteController.dismiss(reason: "screens-did-sleep")
                self.commandFeedbackPresenter.dismiss(reason: "screens-did-sleep")
                self.stopShortcutGuideObservation()
                self.focusedWindowHighlightPresenter.setSuppressed(
                    true,
                    reason: "screens-did-sleep"
                )
                self.workspacePreviewRepository.purge()
                self.engine.prepareForScreenSleep(source: .screensSleep)
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
                self?.workspaceSwipeController.setSuppressed(true, reason: "session-inactive")
                self?.commandPaletteController.dismiss(reason: "session-resigned-active")
                self?.stopShortcutGuideObservation()
                self?.focusedWindowHighlightPresenter.setSuppressed(
                    true,
                    reason: "session-resigned-active"
                )
                self?.workspacePreviewRepository.purge()
                self?.engine.prepareForScreenSleep(source: .sessionResignedActive)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.hotKeyManager.cancelDirectionalMoveGesture(reason: "display-configuration-changed")
                self?.workspaceSwipeController.cancel(reason: "display-configuration-changed")
                self?.commandFeedbackPresenter.screenParametersDidChange()
                self?.focusedWindowHighlightPresenter.screenParametersDidChange()
                if let self,
                   self.tiledResizePreviewPresenter.screenParametersDidChange() {
                    self.focusedWindowHighlightPresenter.setSuppressed(
                        self.fullscreenGameSession != nil || self.isPauseModeEnabled,
                        reason: "tiled-resize-preview-display-change"
                    )
                }
                self?.engine.cancelTiledResizePreview(reason: "display-configuration-changed")
                self?.settingsWindowCoordinator.screenParametersDidChange()
                self?.commandPaletteController.dismiss(reason: "display-configuration-changed")
                self?.stopShortcutGuideObservation()
                self?.workspacePreviewRepository.purge()
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
                self.commandPaletteController.dismiss(reason: "palette-disabled")
            }
            self.registerHotKeys(source: "command-palette-setting-changed")
        }
        .store(in: &cancellables)

        settingsStore.$shortcutGuideEnabled
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.updateShortcutGuideActivation()
            }
            .store(in: &cancellables)

        settingsStore.$workspacePreviewThumbnailsEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                self.workspacePreviewRepository.isEnabled = enabled
                if enabled {
                    self.workspacePreviewRepository.refreshAuthorization()
                } else {
                    self.workspacePreviewRepository.purgeImages()
                }
                self.workspaceStatusBarController?.rebuild()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.workspacePreviewRepository.refreshAuthorization()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            settingsStore.$shortcutGuideSize.removeDuplicates(),
            settingsStore.$shortcutGuidePosition.removeDuplicates()
        )
        .dropFirst()
        .sink { [weak self] _ in
            self?.shortcutGuideController.dismiss()
        }
        .store(in: &cancellables)

        Publishers.CombineLatest(
            settingsStore.$quickApps,
            settingsStore.$quickAppShelfPresentation
            )
            .dropFirst()
            .filter { [weak self] _ in self?.settingsStore.isApplyingProfileActivation == false }
            .removeDuplicates { previous, next in
                previous.0 == next.0 && previous.1 == next.1
            }
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] configurations, presentation in
                self?.engine.updateQuickAppConfigurations(
                    configurations,
                    presentation: presentation
                )
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
                self.commandPaletteController.dismiss(reason: "shortcut-configuration-changed")
                self.registerHotKeys(source: "shortcut-configuration-changed")
                // The guide's passive flag monitor resolves exact modifier families.
                self.stopShortcutGuideObservation()
                self.updateShortcutGuideActivation()
            }
            .store(in: &cancellables)

        settingsStore.$profileActivationRequest
            .dropFirst()
            .compactMap { $0 }
            .sink { [weak self] request in
                self?.handleProfileActivationRequest(request)
            }
            .store(in: &cancellables)

        // Install every Settings/profile subscriber before discovery can publish a foreground
        // full-screen game session. Otherwise an immediate startup session could advance the
        // active profile while the engine misses its generated transition request.
        tiledResizePointerMonitor.start()
        engine.start()
        onboardingWindowController.presentIfNeeded()
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
        unregisterScreenLockNotifications()
        tiledPlacementUndoManager.removeAllActions()
        hotKeyManager.cancelDirectionalMoveGesture(reason: "application-terminating")
        workspaceSwipeController.shutdown()
        commandPaletteController.shutdown()
        commandFeedbackPresenter.shutdown()
        tiledResizePointerMonitor.shutdown()
        tiledResizePreviewPresenter.shutdown()
        stopShortcutGuideObservation()
        focusedWindowHighlightPresenter.shutdown()
        onboardingWindowController.shutdown()
        settingsWindowCoordinator.shutdown()
        workspaceStatusBarController?.invalidate()
        workspaceStatusBarController = nil
        workspacePreviewRepository.purge()
        engine.stopAndRestoreAllWindows()
    }

    private func registerHotKeys(
        source: String,
        workspaces: [WorkspaceDefinition]? = nil
    ) {
        guard !isShortcutRecording else {
            diagnostics.log(
                category: "hotkey",
                event: "registration-deferred",
                fields: ["source": source, "reason": "shortcut-recording"]
            )
            return
        }
        let registrationWorkspaces = workspaces ?? settingsStore.workspaces
        let scope: HotKeyRegistrationScope = if isPauseModeEnabled {
            .commandPaletteOnly
        } else if fullscreenGameSession != nil {
            .workspaceNavigationOnly
        } else {
            .all
        }
        let report = hotKeyManager.register(
            workspaces: registrationWorkspaces,
            hotKeyConfiguration: settingsStore.hotKeyConfiguration,
            radialMenuEnabled: isPauseModeEnabled || settingsStore.radialMenuEnabled,
            scope: scope,
            forceCommandPaletteEscapeHatch: isPauseModeEnabled,
            diagnosticSource: source
        )
        settingsStore.setHotKeyRuntimeIssues(report.runtimeIssues)
    }

    private func registerScreenLockNotifications() {
        guard !screenLockNotificationsRegistered else { return }
        screenLockNotificationsRegistered = true
        let center = DistributedNotificationCenter.default()
        center.addObserver(
            self,
            selector: #selector(screenDidLock(_:)),
            name: ScreenLockLifecycleNotifications.locked,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        center.addObserver(
            self,
            selector: #selector(screenDidUnlock(_:)),
            name: ScreenLockLifecycleNotifications.unlocked,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    private func unregisterScreenLockNotifications() {
        guard screenLockNotificationsRegistered else { return }
        screenLockNotificationsRegistered = false
        DistributedNotificationCenter.default().removeObserver(
            self,
            name: ScreenLockLifecycleNotifications.locked,
            object: nil
        )
        DistributedNotificationCenter.default().removeObserver(
            self,
            name: ScreenLockLifecycleNotifications.unlocked,
            object: nil
        )
    }

    @objc private func screenDidLock(_ notification: Notification) {
        hotKeyManager.cancelDirectionalMoveGesture(reason: "screen-locked")
        workspaceSwipeController.setSuppressed(true, reason: "session-inactive")
        commandPaletteController.dismiss(reason: "screen-locked")
        commandFeedbackPresenter.dismiss(reason: "screen-locked")
        stopShortcutGuideObservation()
        focusedWindowHighlightPresenter.setSuppressed(true, reason: "screen-locked")
        workspacePreviewRepository.purge()
        engine.prepareForScreenSleep(source: .screenLocked)
    }

    @objc private func screenDidUnlock(_ notification: Notification) {
        reconcileAfterWake(source: .screenUnlocked)
    }

    private func updateShortcutGuideActivation() {
        guard settingsStore.shortcutGuideEnabled else {
            stopShortcutGuideObservation()
            settingsStore.setShortcutGuideRuntimeIssue(nil)
            diagnostics.log(
                category: "shortcut-guide",
                event: "observation-stopped",
                fields: ["reason": "disabled"]
            )
            return
        }
        guard !preparedForTermination,
              !isShortcutRecording,
              !isPauseModeEnabled,
              fullscreenGameSession == nil,
              !isForegroundDeclaredGameApplication else {
            stopShortcutGuideObservation()
            diagnostics.log(
                category: "shortcut-guide",
                event: "observation-stopped",
                fields: [
                    "reason": preparedForTermination ? "termination"
                        : isShortcutRecording ? "shortcut-recording"
                        : isPauseModeEnabled ? "pause-mode"
                        : fullscreenGameSession != nil ? "fullscreen-game"
                        : "declared-game",
                ]
            )
            return
        }
        guard !shortcutGuideModifierMonitor.isRunning else {
            settingsStore.setShortcutGuideRuntimeIssue(nil)
            diagnostics.log(
                category: "shortcut-guide",
                event: "observation-retained"
            )
            return
        }

        let generation = shortcutGuideObservationGeneration.advance()
        let started = shortcutGuideModifierMonitor.start(configuration: settingsStore.hotKeyConfiguration) { [weak self] family in
            Task { @MainActor [weak self] in
                guard let self,
                      self.shortcutGuideObservationGeneration.accepts(generation) else { return }
                self.shortcutGuideModifierFamilyDidChange(family)
            }
        }
        let issue = started
            ? nil
            : "WindowRanger could not observe modifier changes. Check Accessibility permission, then turn the Shortcut Guide off and on again."
        settingsStore.setShortcutGuideRuntimeIssue(issue)
        diagnostics.log(
            category: "shortcut-guide",
            event: started ? "modifier-monitor-started" : "modifier-monitor-unavailable"
        )
    }

    private func stopShortcutGuideObservation() {
        _ = shortcutGuideObservationGeneration.advance()
        activeShortcutGuideModifierFamily = nil
        presentedShortcutGuideShelfContext = nil
        shortcutGuideModifierMonitor.stop()
        shortcutGuideController.stop()
    }

    private func refreshShortcutGuideForShelfTransitionIfNeeded() {
        guard let family = activeShortcutGuideModifierFamily else { return }
        let shelfContext = engine.currentShortcutGuideShelfContext()
        guard shelfContext != presentedShortcutGuideShelfContext else { return }
        shortcutGuideModifierFamilyDidChange(family)
    }

    private func shortcutGuideModifierFamilyDidChange(
        _ family: ShortcutFamily?
    ) {
        activeShortcutGuideModifierFamily = family
        if family == nil {
            presentedShortcutGuideShelfContext = nil
        }
        diagnostics.log(
            category: "shortcut-guide",
            event: "modifier-family-changed",
            fields: ["family": family?.rawValue ?? "none"]
        )
        guard settingsStore.shortcutGuideEnabled,
              !isShortcutRecording,
              !isPauseModeEnabled,
              fullscreenGameSession == nil,
              !isForegroundDeclaredGameApplication,
              let family else {
            shortcutGuideController.dismiss()
            return
        }
        let conflicts = ShortcutConflictModel.evaluate(
            configuration: settingsStore.hotKeyConfiguration,
            workspaces: settingsStore.workspaces,
            includeCommandWheel: settingsStore.radialMenuEnabled
        )
        guard let baseContent = ShortcutGuideContentBuilder.build(
            family: family,
            workspaces: settingsStore.workspaces,
            configuration: settingsStore.hotKeyConfiguration,
            runtimeIssues: settingsStore.hotKeyRuntimeIssues,
            conflictReport: conflicts
        ) else {
            shortcutGuideController.dismiss()
            diagnostics.log(
                category: "shortcut-guide",
                event: "content-unavailable",
                fields: ["family": family.rawValue]
            )
            return
        }
        let shelfContext = engine.currentShortcutGuideShelfContext()
        presentedShortcutGuideShelfContext = shelfContext
        let content: ShortcutGuideContent
        if let shelfContext {
            guard let contextualContent = ShortcutGuideShelfPresentationPolicy.contextualContent(
                from: baseContent,
                direction: shelfContext.direction
            ) else {
                shortcutGuideController.dismiss()
                diagnostics.log(
                    category: "shortcut-guide",
                    event: "shelf-content-unavailable",
                    fields: ["family": family.rawValue]
                )
                return
            }
            content = contextualContent
        } else {
            content = baseContent
        }
        let displayIdentifier = shelfContext?.displayIdentifier
            ?? engine.currentInteractionDisplayIdentifier()
        let size = shelfContext.map { _ in
            ShortcutGuideShelfPresentationPolicy.compactSize(
                for: settingsStore.shortcutGuideSize
            )
        } ?? settingsStore.shortcutGuideSize
        let position = shelfContext.map {
            ShortcutGuideShelfPresentationPolicy.position(opposite: $0.direction)
        } ?? settingsStore.shortcutGuidePosition
        shortcutGuideController.present(
            content,
            size: size,
            position: position,
            preferredDisplayIdentifier: displayIdentifier
        )
        diagnostics.log(
            category: "shortcut-guide",
            event: "presentation-requested",
            fields: [
                "family": family.rawValue,
                "context": shelfContext == nil ? "workspace" : "quick-app-shelf",
                "primary-actions": String(content.primaryActions.count),
                "secondary-actions": String(content.secondaryActions.count),
                "display": String(displayIdentifier.prefix(12)),
                "panel-visible": String(shortcutGuideController.isVisible),
            ]
        )
    }

    private func enrichedCommandContext(
        _ context: RadialCommandContext
    ) -> RadialCommandContext {
        var enriched = context
        enriched.profiles = settingsStore.profiles.map {
            RadialProfileOption(id: $0.id, name: $0.name)
        }
        enriched.activeProfileID = settingsStore.activeProfileID
        enriched.isProfileManuallyPinned = settingsStore.manualPinnedProfileID != nil
        if let processIdentifier = context.focusedWindow?.processIdentifier,
           let application = NSRunningApplication(processIdentifier: processIdentifier),
           application.activationPolicy == .regular,
           let bundleIdentifier = application.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !bundleIdentifier.isEmpty,
           bundleIdentifier.caseInsensitiveCompare(Bundle.main.bundleIdentifier ?? "") != .orderedSame {
            let displayName = application.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
            enriched.currentApplication = RadialApplicationOption(
                bundleIdentifier: bundleIdentifier,
                displayName: displayName.flatMap { $0.isEmpty ? nil : $0 } ?? bundleIdentifier
            )
        } else {
            enriched.currentApplication = nil
        }
        enriched.applicationRuleBundleIdentifiers = Set(settingsStore.appRules.map { $0.bundleIdentifier.lowercased() })
        enriched.externalValidationToken = [
            "active=\(settingsStore.activeProfileID.uuidString)",
            "pinned=\(settingsStore.manualPinnedProfileID?.uuidString ?? "none")",
            "paused=\(isPauseModeEnabled)",
            "current-app=\(enriched.currentApplication?.bundleIdentifier.lowercased() ?? "none")",
            "app-rules=\(enriched.applicationRuleBundleIdentifiers.sorted().joined(separator: ","))",
            "quick-apps=\(settingsStore.quickApps.map { $0.bundleIdentifier.lowercased() }.joined(separator: ","))",
            settingsStore.profiles.map { "\($0.id.uuidString)=\($0.name)" }.joined(separator: ","),
        ].joined(separator: "|")
        enriched.quickApps = settingsStore.quickApps
        return enriched
    }

    func shortcutRecordingStateDidChange(_ isRecording: Bool) {
        guard isShortcutRecording != isRecording else { return }
        isShortcutRecording = isRecording
        if isRecording {
            hotKeyManager.cancelDirectionalMoveGesture(reason: "shortcut-recording-began")
            workspaceSwipeController.setSuppressed(true, reason: "shortcut-recording")
            commandPaletteController.dismiss(reason: "shortcut-recording-began")
            stopShortcutGuideObservation()
            hotKeyManager.suspendRegistration()
            settingsStore.setHotKeyRuntimeIssues([])
        } else {
            registerHotKeys(source: "shortcut-recording-ended")
            workspaceSwipeController.setSuppressed(false, reason: "shortcut-recording")
            updateShortcutGuideActivation()
        }
    }

    private func setPauseMode(
        _ isPaused: Bool,
        source: String,
        correlationID: String? = nil
    ) {
        guard isPauseModeEnabled != isPaused else { return }
        isPauseModeEnabled = isPaused
        if isPaused {
            engine.setWindowManagementPaused(true)
            hotKeyManager.cancelDirectionalMoveGesture(reason: "pause-mode")
            workspaceSwipeController.setSuppressed(true, reason: "pause-mode")
            commandFeedbackPresenter.dismiss(reason: "pause-mode")
            stopShortcutGuideObservation()
            focusedWindowHighlightPresenter.setSuppressed(true, reason: "pause-mode")
        } else if let pendingRequest = pendingPausedProfileActivationRequest {
            pendingPausedProfileActivationRequest = nil
            // Keep the engine write gate closed while the newest profile transition updates its
            // logical configuration, then let Resume reconcile that destination once. Reversing
            // this order would briefly snap the stale profile before applying the pending one.
            handleProfileActivationRequest(pendingRequest)
            engine.setWindowManagementPaused(false)
        } else {
            engine.setWindowManagementPaused(false)
            workspaceSwipeController.setSuppressed(false, reason: "pause-mode")
        }

        if !isPaused {
            workspaceSwipeController.setSuppressed(false, reason: "pause-mode")
            focusedWindowHighlightPresenter.setSuppressed(
                fullscreenGameSession != nil,
                reason: "pause-mode-ended"
            )
            updateWorkspaceSwipeActivation()
        }
        registerHotKeys(source: "pause-mode-changed")
        updateShortcutGuideActivation()
        commandPaletteController.contextDidPossiblyChange()
        workspaceStatusBarController?.rebuild()
        diagnostics.log(
            category: "pause-mode",
            event: isPaused ? "enabled" : "disabled",
            correlation: correlationID,
            fields: [
                "source": source,
                "pending-profile": String(pendingPausedProfileActivationRequest != nil),
            ]
        )
    }

    private func handleProfileActivationRequest(_ request: ProfileActivationRequest) {
        if isPauseModeEnabled {
            pendingPausedProfileActivationRequest = request
            diagnostics.log(
                category: "pause-mode",
                event: "profile-transition-deferred",
                fields: [
                    "profile": String(request.configuration.profileID.uuidString.prefix(8)),
                    "generation": String(request.generation),
                ]
            )
            menuBarState.updateConfiguration(
                workspaces: settingsStore.workspaces,
                displayMode: settingsStore.multiDisplayMode,
                connectedDisplays: settingsStore.connectedDisplays,
                workspaceDisplayAssignments: settingsStore.workspaceDisplayAssignments
            )
            workspaceStatusBarController?.rebuild()
            return
        }
        clearTiledPlacementHistory()
        workspacePreviewRepository.purge()
        hotKeyManager.cancelDirectionalMoveGesture(reason: "profile-transition")
        workspaceSwipeController.cancel(reason: "profile-transition")
        commandPaletteController.dismiss(reason: "profile-transition")
        commandFeedbackPresenter.dismiss(reason: "profile-transition")
        shortcutGuideController.dismiss()
        engine.transitionToProfile(request)
        registerHotKeys(
            source: "profile-activation",
            workspaces: request.configuration.workspaces
        )
        menuBarState.updateConfiguration(
            workspaces: settingsStore.workspaces,
            displayMode: settingsStore.multiDisplayMode,
            connectedDisplays: settingsStore.connectedDisplays,
            workspaceDisplayAssignments: settingsStore.workspaceDisplayAssignments
        )
        workspaceStatusBarController?.rebuild()
    }

    func restartOnboardingFromSettings() {
        OnboardingRestartHandoff.perform(
            dismissSettings: settingsWindowCoordinator.dismissForExternalPresentation,
            schedulePresentation: { action in
                DispatchQueue.main.async {
                    action()
                }
            },
            presentOnboarding: { [weak self] in
                self?.onboardingWindowController.presentFromBeginning()
            }
        )
    }

    private func reconcileAfterWake(source: WakeReconciliationSource) {
        hotKeyManager.cancelDirectionalMoveGesture(reason: source.rawValue)
        switch source {
        case .systemWake, .screensWake:
            workspaceSwipeController.setSuppressed(false, reason: "system-sleep")
            workspaceSwipeController.setSuppressed(false, reason: "screen-sleep")
        case .sessionBecameActive, .screenUnlocked:
            workspaceSwipeController.setSuppressed(false, reason: "system-sleep")
            workspaceSwipeController.setSuppressed(false, reason: "session-inactive")
        case .displayConfigurationChanged:
            workspaceSwipeController.cancel(reason: source.rawValue)
        }
        commandPaletteController.dismiss(reason: source.rawValue)
        commandFeedbackPresenter.dismiss(reason: source.rawValue)
        updateShortcutGuideActivation()
        focusedWindowHighlightPresenter.setSuppressed(
            fullscreenGameSession != nil || isPauseModeEnabled,
            reason: source.rawValue
        )
        // Monitor pins/fingerprints must resolve before the engine reconciles workspace homes.
        settingsStore.refreshConnectedDisplays()
        engine.requestWakeReconciliation(
            source: source,
            workspaceDisplayAssignments: settingsStore.workspaceDisplayHomesForEngine
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
        workspaceSwipeController.setSuppressed(
            isPauseModeEnabled,
            reason: "pause-mode"
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
            commandPaletteController.dismiss(reason: reason)
            commandFeedbackPresenter.dismiss(reason: reason)
        }
        updateWorkspaceSwipeActivation()
        updateShortcutGuideActivation()
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
                workspacePreviewRepository: workspacePreviewRepository,
                settingsCommandRequestRouter: settingsCommandRequestRouter,
                updateController: updateController,
                diagnostics: diagnostics,
                tiledPlacementUndoManager: tiledPlacementUndoManager,
                initialMode: settingsStore.menuBarPresentationMode,
                initialWorkspaceLabelMode: settingsStore.menuBarWorkspaceLabelMode,
                initialDisplayIconConfiguration: settingsStore.menuBarDisplayIconConfiguration,
                initialHighlightColor: settingsStore.menuBarHighlightColor,
                isPauseModeEnabled: { [weak self] in
                    self?.isPauseModeEnabled ?? false
                },
                setPauseMode: { [weak self] isPaused in
                    self?.setPauseMode(isPaused, source: "menu-bar")
                }
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
