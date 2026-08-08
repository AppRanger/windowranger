import AppKit
import Combine

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
final class WorkspaceStatusBarController: NSObject {
    static var verboseDiagnosticsMenuEnabled: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private let workspaceStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let engine: WorkspaceEngine
    private let stateModel: MenuBarStateModel
    private var isInvalidated = false

    init(
        engine: WorkspaceEngine,
        stateModel: MenuBarStateModel
    ) {
        self.engine = engine
        self.stateModel = stateModel
        super.init()
        workspaceStatusItem.autosaveName = "com.chris.WindowManager.workspace-strip"
        rebuild()
    }

    func rebuild() {
        guard !isInvalidated else { return }
        guard let statusButton = workspaceStatusItem.button else { return }
        statusButton.subviews.forEach { $0.removeFromSuperview() }
        statusButton.title = ""
        statusButton.image = nil
        statusButton.target = nil
        statusButton.action = nil
        let snapshot = stateModel.presentation(for: .full)
        let availableWidth = MenuBarPressurePolicy.defaultBudget(
            for: NSScreen.main?.visibleFrame.width
        )
        let strip = MenuBarFullStripView(
            snapshot: snapshot,
            availableWidth: availableWidth
        ) { [weak self] target in
            self?.handle(target)
        }
        let layout = strip.layout
        let overflow = layout.overflowSummary.map { " \($0)" } ?? ""
        statusButton.toolTip = "WindowManager workspaces — use the separate app icon to open the menu.\(overflow)"
        statusButton.setAccessibilityLabel("WindowManager workspace buttons")
        statusButton.addSubview(strip)
        NSLayoutConstraint.activate([
            strip.leadingAnchor.constraint(equalTo: statusButton.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: statusButton.trailingAnchor),
            strip.centerYAnchor.constraint(equalTo: statusButton.centerYAnchor),
        ])
        strip.layoutSubtreeIfNeeded()
        workspaceStatusItem.length = max(28, strip.fittingSize.width)
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        NSStatusBar.system.removeStatusItem(workspaceStatusItem)
    }

    private func handle(_ target: MenuBarHitTarget) {
        guard case let .switchWorkspace(workspaceID, _) = MenuBarInteractionRouter.action(
            for: target
        ) else { return }
        engine.switchToWorkspace(workspaceID)
    }

    deinit {
        if !isInvalidated {
            NSStatusBar.system.removeStatusItem(workspaceStatusItem)
        }
    }
}
