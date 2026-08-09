import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let diagnostics = DiagnosticLogger.makeAppLogger()
    lazy var settingsStore = SettingsStore(diagnostics: diagnostics)
    lazy var settingsNavigation = SettingsNavigationModel()
    lazy var settingsWindowCoordinator = SettingsWindowCoordinator(diagnostics: diagnostics)
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
        focusFollowsMovedWindow: settingsStore.focusFollowsMovedWindow,
        automaticallyUnhideApplications: settingsStore.automaticallyUnhideApplications,
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
    private lazy var commandFeedbackPresenter: CommandFeedbackPresenting =
        CommandFeedbackOverlayController(diagnostics: diagnostics)
    private lazy var hotKeyManager = HotKeyManager(
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
    private var workspaceStatusBarController: WorkspaceStatusBarController?
    private var cancellables = Set<AnyCancellable>()
    private var preparedForTermination = false
    private var isShortcutRecording = false
    private var pendingMenuBarPresentationUpdate: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        }
        engine.onWorkspaceLayoutChanged = { [weak self] workspaceID, layout in
            self?.settingsStore.setLayout(layout, for: workspaceID)
        }
        engine.onWorkspaceLayoutConfigurationChanged = { [weak self] workspaceID, configuration in
            self?.settingsStore.setLayoutConfiguration(configuration, for: workspaceID)
        }
        engine.onCommandFeedback = { [weak self] request in
            self?.commandFeedbackPresenter.present(request)
        }
        engine.onWorkspaceDisplayAssignmentsChanged = { [weak self] assignments in
            self?.settingsStore.assignWorkspaces(assignments)
        }
        registerHotKeys()
        updateGlobeFnHoldActivation()
        engine.start()
        updateMenuBarPresentation()

        settingsStore.$workspaces
            .dropFirst()
            .filter { [weak self] _ in self?.settingsStore.isApplyingProfileActivation == false }
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] workspaces in
                guard let self else { return }
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
                self?.globeFnHoldActivationController.cancel(reason: "application-activated")
                self?.radialMenuTriggerController.cancel(reason: "application-activated")
                self?.engine.applicationActivated(processIdentifier: application.processIdentifier)
            }
            .store(in: &cancellables)

        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        workspaceNotifications.publisher(for: NSWorkspace.willSleepNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.globeFnHoldActivationController.cancel(reason: "system-will-sleep")
                self.radialMenuTriggerController.cancel(reason: "system-will-sleep")
                self.commandFeedbackPresenter.dismiss(reason: "system-will-sleep")
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
                self?.globeFnHoldActivationController.cancel(reason: "session-resigned-active")
                self?.radialMenuTriggerController.cancel(reason: "session-resigned-active")
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.commandFeedbackPresenter.screenParametersDidChange()
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

        settingsStore.$menuBarPresentationMode
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] mode in
                self?.scheduleMenuBarPresentationUpdate(mode)
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
                self.globeFnHoldActivationController.cancel(reason: "profile-transition")
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
        globeFnHoldActivationController.shutdown()
        radialMenuTriggerController.cancel(reason: "application-terminating")
        commandFeedbackPresenter.shutdown()
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
            radialMenuEnabled: settingsStore.radialMenuEnabled
        )
        settingsStore.setHotKeyRuntimeIssues(report.runtimeIssues)
    }

    func shortcutRecordingStateDidChange(_ isRecording: Bool) {
        guard isShortcutRecording != isRecording else { return }
        isShortcutRecording = isRecording
        if isRecording {
            globeFnHoldActivationController.cancel(reason: "shortcut-recording-began")
            radialMenuTriggerController.cancel(reason: "shortcut-recording-began")
            hotKeyManager.suspendRegistration()
            settingsStore.setHotKeyRuntimeIssues([])
        } else {
            registerHotKeys()
        }
        updateGlobeFnHoldActivation()
    }

    private func reconcileAfterWake(source: WakeReconciliationSource) {
        globeFnHoldActivationController.resumeAfterLifecycle(reason: source.rawValue)
        radialMenuTriggerController.cancel(reason: source.rawValue)
        commandFeedbackPresenter.dismiss(reason: source.rawValue)
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
        globeFnHoldActivationController.update(
            enabled: runtimeSettings.isEnabled,
            holdDelay: runtimeSettings.holdDelay
        )
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
                settingsNavigation: settingsNavigation,
                settingsWindowCoordinator: settingsWindowCoordinator,
                diagnostics: diagnostics,
                initialMode: settingsStore.menuBarPresentationMode
            )
        } else {
            workspaceStatusBarController?.setPresentationMode(
                settingsStore.menuBarPresentationMode
            )
        }
    }
}
