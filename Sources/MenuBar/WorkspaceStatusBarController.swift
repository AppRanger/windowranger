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
                key: $0.key,
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

    func presentation(
        for mode: MenuBarPresentationMode,
        workspaceLabelMode: MenuBarWorkspaceLabelMode = .name
    ) -> MenuBarPresentationSnapshot {
        MenuBarPresentationResolver.resolve(
            mode: mode,
            workspaceLabelMode: workspaceLabelMode,
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
            return "WindowRanger menu. Interaction workspace \(currentWorkspaceName). Active workspaces \(active)."
        }
        return "WindowRanger menu. Current workspace \(currentWorkspaceName)."
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
                key: workspace.key,
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
enum CommandFeedbackSurfaceFactory {
    static func make(frame: CGRect) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: frame)
            glass.style = .regular
            glass.setAccessibilityElement(false)
            updatePillShape(glass)
            return glass
        }

        let material = NSVisualEffectView(frame: frame)
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.masksToBounds = true
        material.setAccessibilityElement(false)
        updatePillShape(material)
        return material
    }

    static func updatePillShape(_ surface: NSView) {
        let cornerRadius = max(0, surface.bounds.height / 2)
        if #available(macOS 26.0, *), let glass = surface as? NSGlassEffectView {
            glass.cornerRadius = cornerRadius
        } else {
            surface.layer?.cornerRadius = cornerRadius
        }
    }

    static func installContent(_ content: NSView, in surface: NSView) {
        content.frame = surface.bounds
        content.autoresizingMask = [.width, .height]
        if #available(macOS 26.0, *), let glass = surface as? NSGlassEffectView {
            glass.contentView = content
        } else {
            surface.addSubview(content)
        }
    }
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
        if let surface = panel.contentView {
            CommandFeedbackSurfaceFactory.updatePillShape(surface)
        }
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
        if let surface = panel?.contentView {
            CommandFeedbackSurfaceFactory.updatePillShape(surface)
        }
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

        let background = CommandFeedbackSurfaceFactory.make(
            frame: CGRect(origin: .zero, size: Self.panelSize)
        )
        let content = NSView(frame: background.bounds)
        content.setAccessibilityElement(false)
        CommandFeedbackSurfaceFactory.installContent(content, in: background)

        let label = NSTextField(labelWithString: "")
        label.maximumNumberOfLines = 3
        label.alignment = .center
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .labelColor
        label.lineBreakMode = .byWordWrapping
        label.refusesFirstResponder = true
        label.setAccessibilityElement(false)
        label.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            label.topAnchor.constraint(greaterThanOrEqualTo: content.topAnchor, constant: 12),
            label.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor),
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

enum VerboseDiagnosticsMenuEntry: Equatable {
    case separator
    case header
    case copyRecent
    case revealFile(isEnabled: Bool)
}

enum FocusedWindowSupportMenuPolicy {
    static func isVisible(modifierFlags: NSEvent.ModifierFlags) -> Bool {
        modifierFlags.contains(.option)
    }
}

enum VerboseDiagnosticsMenuPolicy {
    static func entries(
        buildSupportsVerboseDiagnostics: Bool,
        modifierFlags: NSEvent.ModifierFlags,
        diagnosticFileAvailable: Bool
    ) -> [VerboseDiagnosticsMenuEntry] {
        guard buildSupportsVerboseDiagnostics, modifierFlags.contains(.option) else { return [] }
        return [
            .separator,
            .header,
            .copyRecent,
            .revealFile(isEnabled: diagnosticFileAvailable),
        ]
    }
}

struct MenuBarApplicationShelfGeometry {
    static func frame(
        anchor: CGRect,
        contentSize: CGSize,
        visibleFrame: CGRect,
        gap: CGFloat = 6,
        edgeInset: CGFloat = 8
    ) -> CGRect {
        let maximumX = max(visibleFrame.minX + edgeInset, visibleFrame.maxX - edgeInset - contentSize.width)
        let proposedX = anchor.midX - contentSize.width / 2
        let x = min(max(proposedX, visibleFrame.minX + edgeInset), maximumX)
        let minimumY = visibleFrame.minY + edgeInset
        let proposedY = anchor.minY - gap - contentSize.height
        let maximumY = max(minimumY, visibleFrame.maxY - edgeInset - contentSize.height)
        let y = min(max(proposedY, minimumY), maximumY)
        return CGRect(origin: CGPoint(x: x, y: y), size: contentSize)
    }
}

enum MenuBarApplicationShelfTiming {
    static let dwell: TimeInterval = 0.45
    static let dismissalGrace: TimeInterval = 0.22
    static let hoverRestorationDelay: TimeInterval = 0.08
}

@MainActor
enum MenuBarApplicationShelfSurfaceFactory {
    static let cornerRadius: CGFloat = 12

    static func make(frame: CGRect) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: frame)
            glass.style = .regular
            glass.cornerRadius = cornerRadius
            glass.setAccessibilityElement(false)
            return glass
        }

        let material = NSVisualEffectView(frame: frame)
        material.material = .menu
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = cornerRadius
        material.layer?.masksToBounds = true
        material.setAccessibilityElement(false)
        return material
    }

    static func installContent(_ content: NSView, in surface: NSView) {
        content.frame = surface.bounds
        content.autoresizingMask = [.width, .height]
        if #available(macOS 26.0, *), let glass = surface as? NSGlassEffectView {
            glass.contentView = content
        } else {
            surface.addSubview(content)
        }
    }
}

@MainActor
private final class MenuBarApplicationShelfPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class MenuBarApplicationShelfRow: NSButton {
    let application: WorkspaceApplicationSummary
    private var hoverTrackingArea: NSTrackingArea?

    init(application: WorkspaceApplicationSummary, image: NSImage?) {
        self.application = application
        super.init(frame: .zero)
        target = self
        action = #selector(selected)
        isBordered = false
        bezelStyle = .regularSquare
        focusRingType = .none
        alignment = .left
        imagePosition = .imageLeading
        imageScaling = .scaleProportionallyDown
        self.image = image
        wantsLayer = true
        layer?.cornerRadius = 6
        translatesAutoresizingMaskIntoConstraints = false

        let title = NSMutableAttributedString(
            string: application.name,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        if application.windowCount > 1 {
            title.append(NSAttributedString(
                string: "  \(application.windowCount)",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 10, weight: .regular),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            ))
        }
        attributedTitle = title
        toolTip = application.windowCount == 1
            ? application.name
            : "\(application.name) — \(application.windowCount) windows"
        setAccessibilityLabel(application.name)
        setAccessibilityHelp(
            "Switches to the workspace and focuses \(application.name)."
        )
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    var onSelect: ((WorkspaceApplicationSummary) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.10).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @objc private func selected() {
        onSelect?(application)
    }
}

@MainActor
final class MenuBarApplicationShelfContentView: NSView {
    private let header = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
    private let stack = NSStackView()
    private var hoverTrackingArea: NSTrackingArea?
    private var contentSize = CGSize(width: 240, height: 80)

    override var intrinsicContentSize: NSSize { contentSize }
    var onHoverChanged: ((Bool) -> Void)?
    var usesVerticalScroller: Bool { scrollView.hasVerticalScroller }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.textColor = .secondaryLabelColor
        header.lineBreakMode = .byTruncatingTail
        header.translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .none
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stack

        addSubview(header)
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            header.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            header.heightAnchor.constraint(equalToConstant: 18),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 3),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configure(
        workspaceName: String,
        applications: [WorkspaceApplicationSummary],
        imageProvider: (WorkspaceApplicationSummary) -> NSImage?,
        onSelect: @escaping (WorkspaceApplicationSummary) -> Void
    ) {
        header.stringValue = workspaceName
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        if applications.isEmpty {
            let empty = NSTextField(labelWithString: "No apps in this workspace")
            empty.font = .systemFont(ofSize: 11)
            empty.textColor = .secondaryLabelColor
            empty.alignment = .center
            empty.translatesAutoresizingMaskIntoConstraints = false
            // Both anchors must share a view hierarchy before AppKit can activate the width
            // constraint. Activating first raises NSGenericException when an empty shelf opens.
            stack.addArrangedSubview(empty)
            NSLayoutConstraint.activate([
                empty.widthAnchor.constraint(equalTo: stack.widthAnchor),
                empty.heightAnchor.constraint(equalToConstant: 34),
            ])
        } else {
            for application in applications {
                let row = MenuBarApplicationShelfRow(
                    application: application,
                    image: imageProvider(application)
                )
                row.onSelect = onSelect
                stack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
        }
        scrollView.hasVerticalScroller = applications.count > 8
        let rowCount = max(1, applications.count)
        let bodyHeight = min(CGFloat(rowCount) * 32, 256)
        contentSize = CGSize(width: 240, height: 36 + bodyHeight)
        frame.size = contentSize
        invalidateIntrinsicContentSize()
        layoutSubtreeIfNeeded()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }
}

@MainActor
private final class MenuBarApplicationShelfController {
    private let panel: MenuBarApplicationShelfPanel
    private let surface: NSView
    private let contentView: MenuBarApplicationShelfContentView
    private(set) var workspaceID: UUID?

    var isPresented: Bool { panel.isVisible }
    var onHoverChanged: ((Bool) -> Void)? {
        didSet { contentView.onHoverChanged = onHoverChanged }
    }

    init() {
        panel = MenuBarApplicationShelfPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        contentView = MenuBarApplicationShelfContentView(frame: .zero)
        surface = MenuBarApplicationShelfSurfaceFactory.make(frame: .zero)
        MenuBarApplicationShelfSurfaceFactory.installContent(contentView, in: surface)
        panel.contentView = surface
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.animationBehavior = .utilityWindow
    }

    func present(
        workspaceID: UUID,
        workspaceName: String,
        applications: [WorkspaceApplicationSummary],
        anchorFrame: CGRect,
        onSelect: @escaping (WorkspaceApplicationSummary) -> Void
    ) {
        contentView.configure(
            workspaceName: workspaceName,
            applications: applications,
            imageProvider: Self.applicationIcon,
            onSelect: onSelect
        )
        let screen = NSScreen.screens.first(where: { $0.frame.contains(anchorFrame.center) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }
        let frame = MenuBarApplicationShelfGeometry.frame(
            anchor: anchorFrame,
            contentSize: contentView.intrinsicContentSize,
            visibleFrame: screen.visibleFrame
        )
        self.workspaceID = workspaceID
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func dismiss() {
        panel.orderOut(nil)
        workspaceID = nil
    }

    private static func applicationIcon(_ application: WorkspaceApplicationSummary) -> NSImage? {
        let source = NSRunningApplication(
            processIdentifier: application.target.processIdentifier
        )?.icon ?? application.applicationURL.map {
            NSWorkspace.shared.icon(forFile: $0.path)
        }
        guard let source, let image = source.copy() as? NSImage else { return nil }
        image.size = NSSize(width: 18, height: 18)
        return image
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

@MainActor
private final class MenuBarDisplayGroupHoverTracker: NSResponder {
    private weak var button: NSStatusBarButton?
    private weak var contentView: MenuBarDisplayGroupContentView?
    private var trackingAreas: [NSTrackingArea] = []
    private var pointerIsOverWorkspace = false
    private var currentTarget: MenuBarHitTarget?
    private let onHoverChanged: (MenuBarHitTarget?, CGRect?) -> Void

    init(onHoverChanged: @escaping (MenuBarHitTarget?, CGRect?) -> Void) {
        self.onHoverChanged = onHoverChanged
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configure(
        button: NSStatusBarButton,
        contentView: MenuBarDisplayGroupContentView
    ) {
        removeTrackingAreas()
        self.button = button
        self.contentView = contentView
        button.layoutSubtreeIfNeeded()
        contentView.layoutSubtreeIfNeeded()
        for region in contentView.workspaceTrackingRegions(in: button) where !region.frame.isEmpty {
            let area = NSTrackingArea(
                rect: region.frame,
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self,
                userInfo: nil
            )
            button.addTrackingArea(area)
            trackingAreas.append(area)
        }
        if pointerIsOverWorkspace {
            refreshHover()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        refreshHover()
    }

    override func mouseExited(with event: NSEvent) {
        refreshHover()
    }

    @discardableResult
    func refreshCurrentPointer() -> Bool {
        refreshHover()
        return pointerIsOverWorkspace
    }

    func invalidate() {
        removeTrackingAreas()
        contentView?.clearHover()
        pointerIsOverWorkspace = false
        currentTarget = nil
        button = nil
        contentView = nil
    }

    private func refreshHover() {
        guard let contentView else { return }
        let targets = contentView.screenSpaceTargets()
        let target = contentView.updateHover(at: NSEvent.mouseLocation)
        pointerIsOverWorkspace = target != nil
        guard target != currentTarget else { return }
        currentTarget = target
        let frame = target.flatMap { target in
            targets.first(where: { $0.hitTarget == target })?.frame
        }
        onHoverChanged(target, frame)
    }

    private func removeTrackingAreas() {
        guard let button else {
            trackingAreas.removeAll()
            return
        }
        trackingAreas.forEach { button.removeTrackingArea($0) }
        trackingAreas.removeAll()
    }
}

@MainActor
private struct ManagedDisplayGroupStatusItem {
    let statusItem: NSStatusItem
    var contentView: MenuBarDisplayGroupContentView?
    var hoverTracker: MenuBarDisplayGroupHoverTracker?
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

    static func verboseDiagnosticsMenuEntries(
        modifierFlags: NSEvent.ModifierFlags,
        diagnosticFileAvailable: Bool
    ) -> [VerboseDiagnosticsMenuEntry] {
        VerboseDiagnosticsMenuPolicy.entries(
            buildSupportsVerboseDiagnostics: verboseDiagnosticsMenuEnabled,
            modifierFlags: modifierFlags,
            diagnosticFileAvailable: diagnosticFileAvailable
        )
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
    private var workspaceLabelMode: MenuBarWorkspaceLabelMode
    private var displayIconConfiguration: MenuBarDisplayIconConfiguration
    private var highlightColor: MenuBarHighlightColor
    private var displayGroupStatusItems: [ManagedDisplayGroupStatusItem] = []
    private var displayGroupContentByButton: [ObjectIdentifier: MenuBarDisplayGroupContentView] = [:]
    private var hostView: MenuBarStatusHostView?
    private var contentView: MenuBarStatusContentView?
    private var lastSnapshot: MenuBarPresentationSnapshot?
    private var focusedWindowDiagnosticReport: String?
    private var supportSectionVisibleForCurrentOpen = false
    private var isPresentingMenu = false
    private var isInvalidated = false
    private var shelfGeneration: UInt64 = 0
    private var pendingShelfTarget: MenuBarHitTarget?
    private var pendingShelfAnchorFrame: CGRect?
    private var pendingShelfApplications: [WorkspaceApplicationSummary]?
    private var shelfDwellElapsed = false
    private var shelfDwellWorkItem: DispatchWorkItem?
    private var shelfDismissWorkItem: DispatchWorkItem?
    private var shelfHoverRestorationWorkItem: DispatchWorkItem?
    private lazy var applicationShelfController: MenuBarApplicationShelfController = {
        let controller = MenuBarApplicationShelfController()
        controller.onHoverChanged = { [weak self] hovered in
            self?.applicationShelfHoverChanged(hovered)
        }
        return controller
    }()

    init(
        engine: WorkspaceEngine,
        stateModel: MenuBarStateModel,
        settingsStore: SettingsStore,
        settingsCommandRequestRouter: SettingsCommandRequestRouter,
        diagnostics: DiagnosticLogger,
        tiledPlacementUndoManager: UndoManager? = nil,
        initialMode: MenuBarPresentationMode,
        initialWorkspaceLabelMode: MenuBarWorkspaceLabelMode = .name,
        initialDisplayIconConfiguration: MenuBarDisplayIconConfiguration = .automatic,
        initialHighlightColor: MenuBarHighlightColor = .default
    ) {
        self.engine = engine
        self.stateModel = stateModel
        self.settingsStore = settingsStore
        self.settingsCommandRequestRouter = settingsCommandRequestRouter
        self.diagnostics = diagnostics
        self.tiledPlacementUndoManager = tiledPlacementUndoManager
        presentationMode = initialMode
        workspaceLabelMode = initialWorkspaceLabelMode
        displayIconConfiguration = initialDisplayIconConfiguration
        highlightColor = initialHighlightColor
        super.init()
        statusItem.autosaveName = "\(ApplicationIdentity.bundleIdentifier).primary-status"
        appMenu.autoenablesItems = false
        appMenu.delegate = self
        // An assigned NSStatusItem menu owns every click. The custom host keeps workspace buttons
        // interactive and presents this same menu explicitly for the primary area and right-click.
        statusItem.menu = nil
        rebuildMenu()
        rebuild(force: true)
    }

    func setPresentationMode(_ mode: MenuBarPresentationMode) {
        guard !isInvalidated else { return }
        guard presentationMode != mode else {
            rebuild()
            return
        }
        dismissApplicationShelf()
        presentationMode = mode
        rebuild(force: true)
    }

    func setWorkspaceLabelMode(_ mode: MenuBarWorkspaceLabelMode) {
        guard !isInvalidated, workspaceLabelMode != mode else { return }
        workspaceLabelMode = mode
        rebuild(force: true)
    }

    func setDisplayIconConfiguration(_ configuration: MenuBarDisplayIconConfiguration) {
        guard !isInvalidated, displayIconConfiguration != configuration else { return }
        displayIconConfiguration = configuration
        rebuild(force: true)
    }

    func setHighlightColor(_ color: MenuBarHighlightColor) {
        guard !isInvalidated, highlightColor != color else { return }
        highlightColor = color
        rebuild(force: true)
    }

    func rebuild(force: Bool = false) {
        guard !isInvalidated else { return }
        let snapshot = stateModel.presentation(
            for: presentationMode,
            workspaceLabelMode: workspaceLabelMode
        )
        guard force || snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot

        let availableWidth = MenuBarPressurePolicy.defaultBudget(
            for: NSScreen.main?.visibleFrame.width
        )
        let usesDisplayGroups = MenuBarStatusItemCompositionPolicy.usesDisplayGroups(
            for: presentationMode,
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersion
        )
        if usesDisplayGroups {
            rebuildDisplayGroupStatusItems(snapshot: snapshot, availableWidth: availableWidth)
        } else {
            rebuildSingleStatusItem(snapshot: snapshot, availableWidth: availableWidth)
        }
    }

    private func rebuildSingleStatusItem(
        snapshot: MenuBarPresentationSnapshot,
        availableWidth: CGFloat
    ) {
        if snapshot.mode != .full {
            dismissApplicationShelf()
        }
        removeDisplayGroupStatusItems()
        statusItem.isVisible = true
        statusItem.button?.target = nil
        statusItem.button?.action = nil

        let workspaceAction: (MenuBarHitTarget) -> Void = { [weak self] target in
            self?.handle(target)
        }
        let menuAction: () -> Void = { [weak self] in
            self?.presentMenu()
        }
        let workspaceHoverAction: (MenuBarHitTarget?, CGRect?) -> Void = { [weak self] target, frame in
            self?.workspaceHoverChanged(target, anchorFrame: frame)
        }
        let content: MenuBarStatusContentView
        if let existing = contentView {
            existing.configure(
                snapshot: snapshot,
                availableWidth: availableWidth,
                highlightColor: highlightColor,
                displayIconConfiguration: displayIconConfiguration,
                workspaceAction: workspaceAction,
                menuAction: menuAction,
                workspaceHoverAction: workspaceHoverAction
            )
            content = existing
        } else {
            content = MenuBarStatusContentView(
                snapshot: snapshot,
                availableWidth: availableWidth,
                highlightColor: highlightColor,
                displayIconConfiguration: displayIconConfiguration,
                workspaceAction: workspaceAction,
                menuAction: menuAction,
                workspaceHoverAction: workspaceHoverAction
            )
            contentView = content
        }

        let host: MenuBarStatusHostView
        if let existing = hostView {
            host = existing
        } else {
            host = MenuBarStatusHostView(
                contentView: content,
                menuAction: menuAction
            )
            hostView = host
            statusItem.view = host
        }
        let width = max(24, content.intrinsicContentSize.width)
        statusItem.length = width
        host.toolTip = snapshot.primaryTooltip
        host.configure(
            menuAction: menuAction,
            accessibilityLabel: snapshot.primaryAccessibilityLabel,
            accessibilityHelp: presentationMode == .full
                ? "Opens the WindowRanger menu. Only the labelled workspace buttons switch workspaces."
                : "Opens the WindowRanger menu."
        )
        host.frame.size.width = width
        content.layoutSubtreeIfNeeded()
    }

    private func rebuildDisplayGroupStatusItems(
        snapshot: MenuBarPresentationSnapshot,
        availableWidth: CGFloat
    ) {
        if snapshot.mode != .full {
            dismissApplicationShelf()
        }
        statusItem.view = nil
        hostView = nil
        contentView?.removeFromSuperview()
        contentView = nil

        statusItem.button?.target = nil
        statusItem.button?.action = nil
        statusItem.isVisible = false
        let plannedGroups = MenuBarDisplayGroupStatusItemPlanner.groups(
            for: snapshot,
            availableWidth: availableWidth,
            displayIconConfiguration: displayIconConfiguration
        )
        resizeDisplayGroupStatusItems(to: plannedGroups.count)
        // NSStatusBar inserts newly created items at the left edge. Configuring the retained slots
        // in reverse logical order keeps the display/workspace sequence readable left to right.
        let configurationOrder = MenuBarDisplayGroupStatusItemPlanner.configurationOrder(
            for: plannedGroups
        )
        displayGroupContentByButton.removeAll(keepingCapacity: true)
        for index in displayGroupStatusItems.indices {
            configureDisplayGroupStatusItem(
                at: index,
                from: configurationOrder[index],
                snapshot: snapshot
            )
        }
    }

    private func resizeDisplayGroupStatusItems(to count: Int) {
        if displayGroupStatusItems.count != count {
            dismissApplicationShelf()
        }
        while displayGroupStatusItems.count > count {
            let removed = displayGroupStatusItems.removeLast()
            removed.hoverTracker?.invalidate()
            removed.statusItem.button?.target = nil
            removed.statusItem.button?.action = nil
            NSStatusBar.system.removeStatusItem(removed.statusItem)
        }
        while displayGroupStatusItems.count < count {
            let slot = displayGroupStatusItems.count
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            // Keep the established autosave identity so a user's grouped Full-mode placement also
            // applies when Compact or Medium reuses these same physical display-group slots.
            item.autosaveName = "\(ApplicationIdentity.bundleIdentifier).full-display-group-\(slot)"
            displayGroupStatusItems.append(ManagedDisplayGroupStatusItem(
                statusItem: item,
                contentView: nil,
                hoverTracker: nil
            ))
        }
    }

    private func configureDisplayGroupStatusItem(
        at index: Int,
        from plan: MenuBarDisplayGroupStatusItem,
        snapshot: MenuBarPresentationSnapshot
    ) {
        let managed = displayGroupStatusItems[index]
        guard let button = managed.statusItem.button else { return }
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        button.image = nil
        button.imagePosition = .noImage
        button.contentTintColor = .labelColor
        button.target = self
        button.action = #selector(displayGroupStatusButtonActivated(_:))
        _ = button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        let content: MenuBarDisplayGroupContentView
        if let existing = managed.contentView {
            existing.configure(
                plan: plan,
                workspaceLabelMode: snapshot.workspaceLabelMode,
                highlightColor: highlightColor,
                displayIconConfiguration: displayIconConfiguration
            )
            content = existing
        } else {
            content = MenuBarDisplayGroupContentView(
                plan: plan,
                workspaceLabelMode: snapshot.workspaceLabelMode,
                highlightColor: highlightColor,
                displayIconConfiguration: displayIconConfiguration
            )
            button.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                content.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            ])
        }
        managed.statusItem.length = max(24, content.intrinsicContentSize.width)
        button.layoutSubtreeIfNeeded()
        let hoverTracker: MenuBarDisplayGroupHoverTracker?
        if plan.mode == .full {
            let tracker = managed.hoverTracker ?? MenuBarDisplayGroupHoverTracker {
                [weak self] target, frame in
                self?.workspaceHoverChanged(target, anchorFrame: frame)
            }
            tracker.configure(button: button, contentView: content)
            hoverTracker = tracker
        } else {
            managed.hoverTracker?.invalidate()
            hoverTracker = nil
        }
        button.toolTip = plan.group.display.accessibilityLabel
        if plan.mode == .full {
            let workspaceNames = plan.group.visibleWorkspaces.map(\.name).joined(separator: ", ")
            button.setAccessibilityLabel(
                "\(plan.group.display.accessibilityLabel). Workspaces: \(workspaceNames)."
            )
            button.setAccessibilityHelp(
                "A primary pointer click switches the selected workspace. VoiceOver and secondary clicks open the WindowRanger menu."
            )
        } else {
            button.setAccessibilityLabel(
                "WindowRanger menu. \(plan.group.display.accessibilityLabel)."
            )
            button.setAccessibilityHelp("Opens the WindowRanger menu.")
        }
        displayGroupStatusItems[index].contentView = content
        displayGroupStatusItems[index].hoverTracker = hoverTracker
        displayGroupContentByButton[ObjectIdentifier(button)] = content
    }

    private func removeDisplayGroupStatusItems() {
        for managed in displayGroupStatusItems {
            managed.hoverTracker?.invalidate()
            managed.statusItem.button?.target = nil
            managed.statusItem.button?.action = nil
            NSStatusBar.system.removeStatusItem(managed.statusItem)
        }
        displayGroupStatusItems.removeAll()
        displayGroupContentByButton.removeAll()
    }

    private func workspaceHoverChanged(
        _ target: MenuBarHitTarget?,
        anchorFrame: CGRect?
    ) {
        guard case let .workspace(workspaceID, _) = target,
              let target,
              let anchorFrame
        else {
            cancelPendingShelfPresentation()
            if applicationShelfController.isPresented {
                scheduleApplicationShelfDismissal()
            }
            return
        }

        shelfHoverRestorationWorkItem?.cancel()
        shelfHoverRestorationWorkItem = nil
        shelfDismissWorkItem?.cancel()
        shelfDismissWorkItem = nil
        if applicationShelfController.isPresented,
           applicationShelfController.workspaceID == workspaceID {
            return
        }
        if pendingShelfTarget == target { return }

        applicationShelfController.dismiss()
        cancelPendingShelfPresentation()
        shelfGeneration &+= 1
        let generation = shelfGeneration
        pendingShelfTarget = target
        pendingShelfAnchorFrame = anchorFrame
        pendingShelfApplications = nil
        shelfDwellElapsed = false

        engine.workspaceApplications(for: workspaceID) { [weak self] applications in
            guard let self,
                  self.shelfGeneration == generation,
                  self.pendingShelfTarget == target
            else { return }
            self.pendingShelfApplications = applications
            self.presentApplicationShelfIfReady(generation: generation)
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  self.shelfGeneration == generation,
                  self.pendingShelfTarget == target
            else { return }
            self.shelfDwellElapsed = true
            self.presentApplicationShelfIfReady(generation: generation)
        }
        shelfDwellWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + MenuBarApplicationShelfTiming.dwell,
            execute: work
        )
    }

    private func presentApplicationShelfIfReady(generation: UInt64) {
        guard shelfGeneration == generation,
              shelfDwellElapsed,
              let applications = pendingShelfApplications,
              let anchorFrame = pendingShelfAnchorFrame,
              case let .workspace(workspaceID, _) = pendingShelfTarget
        else { return }
        let workspaceName = stateModel.workspaceItems.first(where: { $0.id == workspaceID })?.name
            ?? "Workspace"
        applicationShelfController.present(
            workspaceID: workspaceID,
            workspaceName: workspaceName,
            applications: applications,
            anchorFrame: anchorFrame
        ) { [weak self] application in
            self?.activateWorkspaceApplication(application)
        }
    }

    private func activateWorkspaceApplication(_ application: WorkspaceApplicationSummary) {
        dismissApplicationShelf()
        engine.activateWorkspaceApplication(application.target)
    }

    private func applicationShelfHoverChanged(_ hovered: Bool) {
        if hovered {
            shelfHoverRestorationWorkItem?.cancel()
            shelfHoverRestorationWorkItem = nil
            shelfDismissWorkItem?.cancel()
            shelfDismissWorkItem = nil
        } else {
            scheduleApplicationShelfDismissal()
            scheduleWorkspaceHoverRestoration()
        }
    }

    private func scheduleWorkspaceHoverRestoration() {
        shelfHoverRestorationWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.applicationShelfController.isPresented else { return }
            self.shelfHoverRestorationWorkItem = nil
            let restored = self.displayGroupStatusItems.contains {
                $0.hoverTracker?.refreshCurrentPointer() == true
            }
            if restored {
                self.shelfDismissWorkItem?.cancel()
                self.shelfDismissWorkItem = nil
            }
        }
        shelfHoverRestorationWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + MenuBarApplicationShelfTiming.hoverRestorationDelay,
            execute: work
        )
    }

    private func scheduleApplicationShelfDismissal() {
        shelfDismissWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.dismissApplicationShelf()
        }
        shelfDismissWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + MenuBarApplicationShelfTiming.dismissalGrace,
            execute: work
        )
    }

    private func cancelPendingShelfPresentation() {
        shelfGeneration &+= 1
        shelfDwellWorkItem?.cancel()
        shelfDwellWorkItem = nil
        pendingShelfTarget = nil
        pendingShelfAnchorFrame = nil
        pendingShelfApplications = nil
        shelfDwellElapsed = false
    }

    private func dismissApplicationShelf() {
        shelfHoverRestorationWorkItem?.cancel()
        shelfHoverRestorationWorkItem = nil
        shelfDismissWorkItem?.cancel()
        shelfDismissWorkItem = nil
        cancelPendingShelfPresentation()
        applicationShelfController.dismiss()
    }

    @objc private func displayGroupStatusButtonActivated(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let content = displayGroupContentByButton[ObjectIdentifier(sender)]
        let pointerTarget = content.flatMap { content in
            MenuBarScreenSpaceTargetResolver.target(
                at: NSEvent.mouseLocation,
                among: content.screenSpaceTargets()
            )
        }
        switch MenuBarStatusItemActivationPolicy.action(
            for: content?.mode ?? presentationMode,
            eventType: event?.type,
            modifierFlags: NSEvent.modifierFlags,
            pointerTarget: pointerTarget
        ) {
        case .openMenu:
            presentMenu(relativeTo: sender)
        case let .switchWorkspace(workspaceID, displayIdentifier):
            handle(.workspace(
                workspaceID: workspaceID,
                displayIdentifier: displayIdentifier
            ), menuAnchor: sender)
        }
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        dismissApplicationShelf()
        appMenu.delegate = nil
        statusItem.menu = nil
        statusItem.view = nil
        statusItem.button?.target = nil
        statusItem.button?.action = nil
        hostView = nil
        contentView?.removeFromSuperview()
        contentView = nil
        removeDisplayGroupStatusItems()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func handle(_ target: MenuBarHitTarget, menuAnchor: NSView? = nil) {
        dismissApplicationShelf()
        switch MenuBarInteractionRouter.action(for: target) {
        case .openMenu:
            presentMenu(relativeTo: menuAnchor)
        case let .switchWorkspace(workspaceID, _):
            engine.switchToWorkspace(workspaceID)
        }
    }

    private func presentMenu(relativeTo requestedAnchor: NSView? = nil) {
        dismissApplicationShelf()
        let anchor = requestedAnchor ?? hostView ?? statusItem.button
        guard !isInvalidated, !isPresentingMenu, let anchor else { return }
        isPresentingMenu = true
        hostView?.setMenuPresented(true)
        (anchor as? NSButton)?.highlight(true)
        defer {
            hostView?.setMenuPresented(false)
            (anchor as? NSButton)?.highlight(false)
            isPresentingMenu = false
        }
        _ = appMenu.popUp(
            positioning: nil,
            at: NSPoint(x: anchor.bounds.minX, y: anchor.bounds.minY),
            in: anchor
        )
    }

    func menuWillOpen(_ menu: NSMenu) {
        let modifierFlags = NSEvent.modifierFlags
        supportSectionVisibleForCurrentOpen = FocusedWindowSupportMenuPolicy.isVisible(
            modifierFlags: modifierFlags
        )
        focusedWindowDiagnosticReport = supportSectionVisibleForCurrentOpen
            ? engine.focusedWindowDiagnosticReport()
            : nil
        rebuildMenu()
    }

    func menuDidClose(_ menu: NSMenu) {
        supportSectionVisibleForCurrentOpen = false
        focusedWindowDiagnosticReport = nil
        hostView?.setMenuPresented(false)
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
            let snapshot = stateModel.presentation(
                for: .full,
                workspaceLabelMode: workspaceLabelMode
            )
            let layout = MenuBarPressurePolicy.layout(
                displays: snapshot.displays,
                availableWidth: MenuBarPressurePolicy.defaultBudget(
                    for: NSScreen.main?.visibleFrame.width
                ),
                workspaceLabelMode: workspaceLabelMode,
                displayIconConfiguration: displayIconConfiguration
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

        let supportSectionVisible = supportSectionVisibleForCurrentOpen
        if supportSectionVisible {
            appMenu.addItem(.separator())
            appMenu.addItem(disabledMenuItem(title: "WindowRanger Support"))
            appMenu.addItem(actionMenuItem(
                title: "Copy Focused Window Diagnostic Report",
                action: #selector(copyFocusedWindowDiagnosticReport)
            ))
        }

        #if DEBUG
        for entry in Self.verboseDiagnosticsMenuEntries(
            modifierFlags: NSEvent.modifierFlags,
            diagnosticFileAvailable: diagnostics.fileURL != nil
        ) {
            switch entry {
            case .separator:
                if !supportSectionVisible { appMenu.addItem(.separator()) }
            case .header:
                if !supportSectionVisible {
                    appMenu.addItem(disabledMenuItem(title: "WindowRanger Debug"))
                }
            case .copyRecent:
                appMenu.addItem(actionMenuItem(
                    title: "Copy Recent Diagnostics",
                    action: #selector(copyRecentDiagnostics)
                ))
            case let .revealFile(isEnabled):
                let reveal = actionMenuItem(
                    title: "Reveal Diagnostics File",
                    action: #selector(revealDiagnosticsFile)
                )
                reveal.isEnabled = isEnabled
                appMenu.addItem(reveal)
            }
        }
        #endif

        appMenu.addItem(.separator())
        let quit = actionMenuItem(
            title: "Quit WindowRanger",
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

    @objc private func copyFocusedWindowDiagnosticReport() {
        guard let focusedWindowDiagnosticReport else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(focusedWindowDiagnosticReport, forType: .string)
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
