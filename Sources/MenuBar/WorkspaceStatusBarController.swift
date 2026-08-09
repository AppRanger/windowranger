import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarStateModel: ObservableObject {
    @Published private(set) var currentWorkspaceName: String
    @Published private(set) var activeWorkspaceNames: [String]
    @Published private(set) var workspaceItems: [MenuBarWorkspaceItem]

    private var state: WorkspaceEngineState
    private var workspaceDefinitions: [WorkspaceDefinition]
    private var displayMode: MultiDisplayMode
    private var connectedDisplays: [DisplaySnapshot]
    private var workspaceDisplayAssignments: [UUID: String]

    init(
        workspaces: [WorkspaceDefinition],
        displayMode: MultiDisplayMode = .unified,
        connectedDisplays: [DisplaySnapshot] = [],
        workspaceDisplayAssignments: [UUID: String] = [:]
    ) {
        let initial = workspaces.isEmpty ? WorkspaceDefinition.defaults : workspaces
        workspaceDefinitions = initial
        self.displayMode = displayMode
        self.connectedDisplays = connectedDisplays
        self.workspaceDisplayAssignments = workspaceDisplayAssignments
        state = WorkspaceEngineState(
            currentWorkspaceID: initial[0].id,
            activeWorkspaceIDs: [initial[0].id],
            previousWorkspaceID: nil,
            managedWindowCount: 0,
            accessibilityGranted: false
        )
        currentWorkspaceName = initial[0].name
        activeWorkspaceNames = [initial[0].name]
        workspaceItems = initial.map {
            MenuBarWorkspaceItem(
                id: $0.id,
                name: $0.name,
                compactName: MenuBarWorkspaceLabelFormatter.compact($0.name),
                isActive: $0.id == initial[0].id,
                isInteractionWorkspace: $0.id == initial[0].id
            )
        }
    }

    func update(
        state: WorkspaceEngineState,
        workspaces: [WorkspaceDefinition],
        displayMode: MultiDisplayMode? = nil,
        connectedDisplays: [DisplaySnapshot]? = nil,
        workspaceDisplayAssignments: [UUID: String]? = nil
    ) {
        self.state = state
        workspaceDefinitions = workspaces.isEmpty ? WorkspaceDefinition.defaults : workspaces
        if let displayMode { self.displayMode = displayMode }
        if let connectedDisplays { self.connectedDisplays = connectedDisplays }
        if let workspaceDisplayAssignments {
            self.workspaceDisplayAssignments = workspaceDisplayAssignments
        }
        rebuildLabels()
    }

    func updateConfiguration(
        workspaces: [WorkspaceDefinition],
        displayMode: MultiDisplayMode,
        connectedDisplays: [DisplaySnapshot],
        workspaceDisplayAssignments: [UUID: String]
    ) {
        workspaceDefinitions = workspaces.isEmpty ? WorkspaceDefinition.defaults : workspaces
        self.displayMode = displayMode
        self.connectedDisplays = connectedDisplays
        self.workspaceDisplayAssignments = workspaceDisplayAssignments
        rebuildLabels()
    }

    func presentation(for mode: MenuBarPresentationMode) -> MenuBarPresentationSnapshot {
        MenuBarPresentationResolver.resolve(
            mode: mode,
            displayMode: displayMode,
            state: state,
            workspaces: workspaceDefinitions,
            connectedDisplays: connectedDisplays,
            workspaceDisplayAssignments: workspaceDisplayAssignments
        )
    }

    var accessibilityLabel: String {
        let active = activeWorkspaceNames.joined(separator: ", ")
        if activeWorkspaceNames.count > 1 {
            return "WindowManager menu. Interaction workspace \(currentWorkspaceName). Active workspaces \(active)."
        }
        return "WindowManager menu. Current workspace \(currentWorkspaceName)."
    }

    private func rebuildLabels() {
        currentWorkspaceName = workspaceDefinitions.first(where: { $0.id == state.currentWorkspaceID })?.name
            ?? workspaceDefinitions.first?.name
            ?? "—"
        activeWorkspaceNames = workspaceDefinitions.compactMap { workspace in
            state.activeWorkspaceIDs.contains(workspace.id) ? workspace.name : nil
        }
        if activeWorkspaceNames.isEmpty { activeWorkspaceNames = [currentWorkspaceName] }
        workspaceItems = workspaceDefinitions.map { workspace in
            MenuBarWorkspaceItem(
                id: workspace.id,
                name: workspace.name,
                compactName: MenuBarWorkspaceLabelFormatter.compact(workspace.name),
                isActive: state.activeWorkspaceIDs.contains(workspace.id),
                isInteractionWorkspace: workspace.id == state.currentWorkspaceID
            )
        }
    }
}

enum CommandFeedbackPresentationTransition: String, Equatable, Sendable {
    case show
    case update
}

struct CommandFeedbackPresentationState: Equatable, Sendable {
    private(set) var generation: UInt64 = 0
    private(set) var isPresented = false

    mutating func present() -> CommandFeedbackPresentationTransition {
        generation &+= 1
        let transition: CommandFeedbackPresentationTransition = isPresented ? .update : .show
        isPresented = true
        return transition
    }

    mutating func dismiss(ifCurrent expectedGeneration: UInt64? = nil) -> Bool {
        if let expectedGeneration, expectedGeneration != generation { return false }
        guard isPresented else { return false }
        isPresented = false
        return true
    }
}

struct CommandFeedbackDisplayDescriptor: Equatable, Sendable {
    let identifier: String
    let visibleFrame: CGRect
    let isMain: Bool
}

struct CommandFeedbackPlacement: Equatable, Sendable {
    let displayIdentifier: String
    let panelFrame: CGRect
    let resolutionReason: String
}

enum CommandFeedbackGeometry {
    static func placement(
        preferredDisplayIdentifier: String?,
        panelSize: CGSize,
        displays: [CommandFeedbackDisplayDescriptor],
        edgeInset: CGFloat = 12
    ) -> CommandFeedbackPlacement? {
        guard !displays.isEmpty else { return nil }
        let preferred = preferredDisplayIdentifier.flatMap { identifier in
            displays.first(where: { $0.identifier == identifier })
        }
        let display = preferred
            ?? displays.first(where: \.isMain)
            ?? displays.first
        guard let display else { return nil }

        let safeBounds = display.visibleFrame.insetBy(dx: edgeInset, dy: edgeInset)
        let availableBounds = safeBounds.width > 0 && safeBounds.height > 0
            ? safeBounds
            : display.visibleFrame
        let size = CGSize(
            width: min(panelSize.width, max(1, availableBounds.width)),
            height: min(panelSize.height, max(1, availableBounds.height))
        )
        let centeredOrigin = CGPoint(
            x: display.visibleFrame.midX - size.width / 2,
            y: display.visibleFrame.midY - size.height / 2
        )
        let maximumX = max(availableBounds.minX, availableBounds.maxX - size.width)
        let maximumY = max(availableBounds.minY, availableBounds.maxY - size.height)
        let origin = CGPoint(
            x: min(max(centeredOrigin.x, availableBounds.minX), maximumX),
            y: min(max(centeredOrigin.y, availableBounds.minY), maximumY)
        )
        let reason: String
        if preferred != nil {
            reason = "preferred-connected-display"
        } else if preferredDisplayIdentifier != nil, display.isMain {
            reason = "preferred-disconnected-main-fallback"
        } else if preferredDisplayIdentifier != nil {
            reason = "preferred-disconnected-first-fallback"
        } else if display.isMain {
            reason = "main-display-fallback"
        } else {
            reason = "first-display-fallback"
        }
        return CommandFeedbackPlacement(
            displayIdentifier: display.identifier,
            panelFrame: CGRect(origin: origin, size: size),
            resolutionReason: reason
        )
    }
}

struct CommandFeedbackPanelPolicy: Equatable, Sendable {
    let canBecomeKey: Bool
    let canBecomeMain: Bool
    let ignoresMouseEvents: Bool
    let participatesInWindowCycle: Bool

    static let nonActivating = CommandFeedbackPanelPolicy(
        canBecomeKey: false,
        canBecomeMain: false,
        ignoresMouseEvents: true,
        participatesInWindowCycle: false
    )
}

@MainActor
protocol CommandFeedbackPresenting: AnyObject {
    func present(_ request: CommandFeedbackRequest)
    func dismiss(reason: String)
    func screenParametersDidChange()
    func shutdown()
}

@MainActor
final class CommandFeedbackOverlayController: CommandFeedbackPresenting {
    static let panelSize = CGSize(width: 360, height: 72)
    static let dismissalDelay: TimeInterval = 2.4

    private let diagnostics: DiagnosticLogger
    private var state = CommandFeedbackPresentationState()
    private var panel: CommandFeedbackPanel?
    private var label: NSTextField?
    private var dismissalWorkItem: DispatchWorkItem?
    private var lastRequest: CommandFeedbackRequest?
    private var currentDisplayIdentifier: String?
    private var currentCorrelationID: String?
    private var lastAnnouncementDate = Date.distantPast
    private var lastAnnouncedMessage: String?

    init(diagnostics: DiagnosticLogger = .disabled) {
        self.diagnostics = diagnostics
    }

    func present(_ request: CommandFeedbackRequest) {
        guard !request.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let placement = CommandFeedbackGeometry.placement(
                  preferredDisplayIdentifier: request.preferredDisplayIdentifier,
                  panelSize: Self.panelSize,
                  displays: activeDisplayDescriptors()
              )
        else { return }

        let transition = state.present()
        let generation = state.generation
        let panel = ensurePanel()
        label?.stringValue = request.message
        panel.setFrame(placement.panelFrame, display: false)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        dismissalWorkItem?.cancel()
        let dismissal = DispatchWorkItem { [weak self] in
            self?.dismissIfCurrent(generation: generation, reason: "timeout")
        }
        dismissalWorkItem = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dismissalDelay, execute: dismissal)

        lastRequest = request
        currentDisplayIdentifier = placement.displayIdentifier
        currentCorrelationID = request.correlationID ?? diagnostics.makeCorrelationID()
        diagnostics.log(
            category: "command-feedback",
            event: transition.rawValue,
            correlation: currentCorrelationID,
            fields: [
                "requested-display": short(request.preferredDisplayIdentifier),
                "resolved-display": short(placement.displayIdentifier),
                "display-resolution": placement.resolutionReason,
                "generation": String(generation),
                "reduce-motion": String(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion),
                "non-activating": "true",
            ]
        )
        announceForVoiceOverIfNeeded(request.message)
    }

    func dismiss(reason: String) {
        dismissalWorkItem?.cancel()
        dismissalWorkItem = nil
        guard state.dismiss() else { return }
        completeDismissal(reason: reason, generation: state.generation)
    }

    func screenParametersDidChange() {
        guard state.isPresented, let request = lastRequest,
              let placement = CommandFeedbackGeometry.placement(
                  preferredDisplayIdentifier: request.preferredDisplayIdentifier,
                  panelSize: Self.panelSize,
                  displays: activeDisplayDescriptors()
              )
        else { return }
        let previousDisplay = currentDisplayIdentifier
        currentDisplayIdentifier = placement.displayIdentifier
        panel?.setFrame(placement.panelFrame, display: true)
        if previousDisplay != placement.displayIdentifier {
            diagnostics.log(
                category: "command-feedback",
                event: "display-reconciled",
                correlation: currentCorrelationID,
                fields: [
                    "previous-display": short(previousDisplay),
                    "resolved-display": short(placement.displayIdentifier),
                    "display-resolution": placement.resolutionReason,
                ]
            )
        }
    }

    func shutdown() {
        dismissalWorkItem?.cancel()
        dismissalWorkItem = nil
        if state.dismiss() {
            diagnostics.log(
                category: "command-feedback",
                event: "dismiss",
                correlation: currentCorrelationID,
                fields: ["reason": "application-terminating"]
            )
        }
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        label = nil
        lastRequest = nil
        currentDisplayIdentifier = nil
        currentCorrelationID = nil
    }

    private func dismissIfCurrent(generation: UInt64, reason: String) {
        guard state.dismiss(ifCurrent: generation) else { return }
        dismissalWorkItem = nil
        completeDismissal(reason: reason, generation: generation)
    }

    private func completeDismissal(reason: String, generation: UInt64) {
        diagnostics.log(
            category: "command-feedback",
            event: "dismiss",
            correlation: currentCorrelationID,
            fields: [
                "reason": reason,
                "resolved-display": short(currentDisplayIdentifier),
                "generation": String(generation),
            ]
        )
        let panel = panel
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduceMotion {
            panel?.orderOut(nil)
        } else {
            NSAnimationContext.runAnimationGroup { animation in
                animation.duration = 0.12
                panel?.animator().alphaValue = 0
            } completionHandler: { [weak self, weak panel] in
                Task { @MainActor in
                    guard let self, !self.state.isPresented, self.state.generation == generation else { return }
                    panel?.orderOut(nil)
                    panel?.alphaValue = 1
                }
            }
        }
        lastRequest = nil
        currentDisplayIdentifier = nil
        currentCorrelationID = nil
    }

    private func ensurePanel() -> CommandFeedbackPanel {
        if let panel { return panel }
        let panel = CommandFeedbackPanel(
            contentRect: CGRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isFloatingPanel = true
        panel.ignoresMouseEvents = CommandFeedbackPanelPolicy.nonActivating.ignoresMouseEvents
        panel.isMovable = false
        panel.isExcludedFromWindowsMenu = true
        panel.setAccessibilityElement(false)

        let background = NSVisualEffectView(frame: CGRect(origin: .zero, size: Self.panelSize))
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true
        background.setAccessibilityElement(false)

        let label = NSTextField(labelWithString: "")
        label.maximumNumberOfLines = 3
        label.alignment = .center
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .labelColor
        label.lineBreakMode = .byWordWrapping
        label.refusesFirstResponder = true
        label.setAccessibilityElement(false)
        label.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -18),
            label.topAnchor.constraint(greaterThanOrEqualTo: background.topAnchor, constant: 12),
            label.bottomAnchor.constraint(lessThanOrEqualTo: background.bottomAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: background.centerYAnchor),
        ])
        panel.contentView = background
        self.panel = panel
        self.label = label
        return panel
    }

    private func announceForVoiceOverIfNeeded(_ message: String) {
        guard NSWorkspace.shared.isVoiceOverEnabled else { return }
        let now = Date()
        guard message != lastAnnouncedMessage || now.timeIntervalSince(lastAnnouncementDate) >= 0.45 else {
            return
        }
        lastAnnouncementDate = now
        lastAnnouncedMessage = message
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue,
            ]
        )
    }

    private func activeDisplayDescriptors() -> [CommandFeedbackDisplayDescriptor] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let displayID = CGDirectDisplayID(number.uint32Value)
            let identifier: String
            if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
                identifier = CFUUIDCreateString(nil, uuid) as String
            } else {
                identifier = "session-display-\(displayID)"
            }
            return CommandFeedbackDisplayDescriptor(
                identifier: identifier,
                visibleFrame: screen.visibleFrame,
                isMain: displayID == CGMainDisplayID()
            )
        }
    }

    private func short(_ value: String?) -> String {
        value.map { String($0.prefix(12)) } ?? "none"
    }
}

private final class CommandFeedbackPanel: NSPanel {
    override var canBecomeKey: Bool { CommandFeedbackPanelPolicy.nonActivating.canBecomeKey }
    override var canBecomeMain: Bool { CommandFeedbackPanelPolicy.nonActivating.canBecomeMain }
}

@MainActor
final class WorkspaceStatusBarController: NSObject, NSMenuDelegate {
    static var verboseDiagnosticsMenuEnabled: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let appMenu = NSMenu()
    private let engine: WorkspaceEngine
    private let stateModel: MenuBarStateModel
    private let settingsStore: SettingsStore
    private let settingsCommandRequestRouter: SettingsCommandRequestRouter
    private let diagnostics: DiagnosticLogger
    private let tiledPlacementUndoManager: UndoManager?
    private var presentationMode: MenuBarPresentationMode
    private var highlightColor: MenuBarHighlightColor
    private var contentView: MenuBarStatusContentView?
    private var lastSnapshot: MenuBarPresentationSnapshot?
    private var isInvalidated = false

    init(
        engine: WorkspaceEngine,
        stateModel: MenuBarStateModel,
        settingsStore: SettingsStore,
        settingsCommandRequestRouter: SettingsCommandRequestRouter,
        diagnostics: DiagnosticLogger,
        tiledPlacementUndoManager: UndoManager? = nil,
        initialMode: MenuBarPresentationMode,
        initialHighlightColor: MenuBarHighlightColor = .default
    ) {
        self.engine = engine
        self.stateModel = stateModel
        self.settingsStore = settingsStore
        self.settingsCommandRequestRouter = settingsCommandRequestRouter
        self.diagnostics = diagnostics
        self.tiledPlacementUndoManager = tiledPlacementUndoManager
        presentationMode = initialMode
        highlightColor = initialHighlightColor
        super.init()
        statusItem.autosaveName = "com.chris.WindowManager.primary-status"
        appMenu.autoenablesItems = false
        appMenu.delegate = self
        statusItem.menu = appMenu
        rebuildMenu()
        rebuild(force: true)
    }

    func setPresentationMode(_ mode: MenuBarPresentationMode) {
        guard !isInvalidated else { return }
        guard presentationMode != mode else {
            rebuild()
            return
        }
        presentationMode = mode
        rebuild(force: true)
    }

    func setHighlightColor(_ color: MenuBarHighlightColor) {
        guard !isInvalidated, highlightColor != color else { return }
        highlightColor = color
        rebuild(force: true)
    }

    func rebuild(force: Bool = false) {
        guard !isInvalidated else { return }
        guard let statusButton = statusItem.button else { return }
        let snapshot = stateModel.presentation(for: presentationMode)
        guard force || snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot

        statusButton.title = ""
        statusButton.image = nil
        statusButton.target = nil
        statusButton.action = nil
        statusButton.tag = 0

        let availableWidth = MenuBarPressurePolicy.defaultBudget(
            for: NSScreen.main?.visibleFrame.width
        )
        let workspaceAction: (MenuBarHitTarget) -> Void = { [weak self] target in
            self?.handle(target)
        }
        let content: MenuBarStatusContentView
        if let existing = contentView {
            existing.configure(
                snapshot: snapshot,
                availableWidth: availableWidth,
                highlightColor: highlightColor,
                workspaceAction: workspaceAction
            )
            content = existing
        } else {
            content = MenuBarStatusContentView(
                snapshot: snapshot,
                availableWidth: availableWidth,
                highlightColor: highlightColor,
                workspaceAction: workspaceAction
            )
            contentView = content
            statusButton.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: statusButton.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: statusButton.trailingAnchor),
                content.centerYAnchor.constraint(equalTo: statusButton.centerYAnchor),
            ])
        }
        let width = max(24, content.intrinsicContentSize.width)
        statusItem.length = width
        statusButton.toolTip = snapshot.primaryTooltip
        statusButton.setAccessibilityLabel(snapshot.primaryAccessibilityLabel)
        statusButton.setAccessibilityHelp(
            presentationMode == .full
                ? "Opens the WindowManager menu. Only the labelled workspace buttons switch workspaces."
                : "Opens the WindowManager menu."
        )
        content.layoutSubtreeIfNeeded()
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        appMenu.delegate = nil
        statusItem.menu = nil
        contentView?.removeFromSuperview()
        contentView = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func handle(_ target: MenuBarHitTarget) {
        switch MenuBarInteractionRouter.action(for: target) {
        case .openMenu:
            statusItem.button?.performClick(nil)
        case let .switchWorkspace(workspaceID, _):
            engine.switchToWorkspace(workspaceID)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        appMenu.removeAllItems()

        let profile = disabledMenuItem(title: "Profile: \(settingsStore.activeProfile.name)")
        profile.image = symbol("person.crop.rectangle.stack")
        appMenu.addItem(profile)
        appMenu.addItem(disabledMenuItem(title: settingsStore.activeProfileSelectionReason.title))

        let switchProfile = NSMenuItem(title: "Switch Profile", action: nil, keyEquivalent: "")
        switchProfile.image = symbol("arrow.triangle.2.circlepath")
        let profilesMenu = NSMenu(title: "Switch Profile")
        profilesMenu.autoenablesItems = false
        for candidate in settingsStore.profiles {
            let item = actionMenuItem(
                title: candidate.name,
                action: #selector(selectProfile(_:))
            )
            item.representedObject = candidate.id.uuidString
            item.state = candidate.id == settingsStore.activeProfileID ? .on : .off
            profilesMenu.addItem(item)
        }
        switchProfile.submenu = profilesMenu
        appMenu.addItem(switchProfile)

        if settingsStore.manualPinnedProfileID != nil {
            let resume = actionMenuItem(
                title: "Resume Automatic",
                action: #selector(resumeAutomaticProfileSelection)
            )
            resume.image = symbol("arrow.triangle.2.circlepath")
            appMenu.addItem(resume)
        }

        if presentationMode == .full {
            let snapshot = stateModel.presentation(for: .full)
            let layout = MenuBarPressurePolicy.layout(
                displays: snapshot.displays,
                availableWidth: MenuBarPressurePolicy.defaultBudget(
                    for: NSScreen.main?.visibleFrame.width
                )
            )
            if let overflowSummary = layout.overflowSummary {
                appMenu.addItem(disabledMenuItem(title: "Menu bar overflow: \(overflowSummary)"))
            }
        }

        appMenu.addItem(.separator())
        let settings = actionMenuItem(
            title: "Settings…",
            action: #selector(openSettingsFromStatusMenu)
        )
        settings.image = symbol("gearshape")
        appMenu.addItem(settings)

        if let tiledPlacementUndoManager,
           tiledPlacementUndoManager.canUndo || tiledPlacementUndoManager.canRedo {
            appMenu.addItem(.separator())
            if tiledPlacementUndoManager.canUndo {
                let undo = actionMenuItem(
                    title: tiledPlacementUndoManager.undoMenuItemTitle,
                    action: #selector(undoTiledPlacement)
                )
                undo.image = symbol("arrow.uturn.backward")
                appMenu.addItem(undo)
            }
            if tiledPlacementUndoManager.canRedo {
                let redo = actionMenuItem(
                    title: tiledPlacementUndoManager.redoMenuItemTitle,
                    action: #selector(redoTiledPlacement)
                )
                redo.image = symbol("arrow.uturn.forward")
                appMenu.addItem(redo)
            }
        }

        #if DEBUG
        appMenu.addItem(.separator())
        appMenu.addItem(disabledMenuItem(title: "WindowManager Debug"))
        appMenu.addItem(actionMenuItem(
            title: "Copy Recent Diagnostics",
            action: #selector(copyRecentDiagnostics)
        ))
        let reveal = actionMenuItem(
            title: "Reveal Diagnostics File",
            action: #selector(revealDiagnosticsFile)
        )
        reveal.isEnabled = diagnostics.fileURL != nil
        appMenu.addItem(reveal)
        #endif

        appMenu.addItem(.separator())
        let quit = actionMenuItem(
            title: "Quit WindowManager",
            action: #selector(quitWindowManager)
        )
        quit.keyEquivalent = "q"
        quit.keyEquivalentModifierMask = [.command]
        appMenu.addItem(quit)
    }

    private func actionMenuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = true
        return item
    }

    private func disabledMenuItem(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    @objc private func openSettingsFromStatusMenu() {
        settingsCommandRequestRouter.prepare(SettingsCommandRequest(
            category: nil,
            preferPointerDisplay: true
        ))
        appMenu.cancelTracking()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard SettingsMenuCommandDispatcher.performSettingsCommand(in: NSApp.mainMenu) else {
                self.settingsCommandRequestRouter.cancelPendingRequest()
                self.diagnostics.log(
                    category: "settings-window",
                    event: "main-menu-command-unavailable",
                    fields: ["route": "status-menu-native-item"]
                )
                return
            }
        }
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let profileID = UUID(uuidString: raw)
        else { return }
        settingsStore.selectProfile(profileID)
    }

    @objc private func resumeAutomaticProfileSelection() {
        settingsStore.resumeAutomaticProfileSelection()
    }

    @objc private func undoTiledPlacement() {
        tiledPlacementUndoManager?.undo()
        rebuildMenu()
    }

    @objc private func redoTiledPlacement() {
        tiledPlacementUndoManager?.redo()
        rebuildMenu()
    }

    #if DEBUG
    @objc private func copyRecentDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics.recentDiagnosticsText(), forType: .string)
    }

    @objc private func revealDiagnosticsFile() {
        guard let fileURL = diagnostics.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }
    #endif

    @objc private func quitWindowManager() {
        NSApp.terminate(nil)
    }

    deinit {
        if !isInvalidated {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }
}
