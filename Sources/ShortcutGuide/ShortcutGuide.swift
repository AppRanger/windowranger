import AppKit
import Carbon
import SwiftUI

/// Device-local presentation choices for the passive shortcut guide.
enum ShortcutGuideSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large

    var id: String { rawValue }
    static let defaultValue: Self = .medium

    var title: String { rawValue.capitalized }

    var panelSize: CGSize {
        switch self {
        case .small: CGSize(width: 680, height: 190)
        case .medium: CGSize(width: 920, height: 230)
        case .large: CGSize(width: 1_200, height: 286)
        }
    }

    func panelSize(for content: ShortcutGuideContent) -> CGSize {
        ShortcutGuideLayoutMetrics(size: self, content: content).panelSize
    }
}

enum ShortcutGuidePosition: String, Codable, CaseIterable, Identifiable, Sendable {
    case topLeading, topCenter, topTrailing
    case centerLeading, center, centerTrailing
    case bottomLeading, bottomCenter, bottomTrailing

    var id: String { rawValue }
    static let defaultValue: Self = .bottomCenter

    var title: String {
        switch self {
        case .topLeading: "Top Left"
        case .topCenter: "Top Centre"
        case .topTrailing: "Top Right"
        case .centerLeading: "Centre Left"
        case .center: "Centre"
        case .centerTrailing: "Centre Right"
        case .bottomLeading: "Bottom Left"
        case .bottomCenter: "Bottom Centre"
        case .bottomTrailing: "Bottom Right"
        }
    }

    var horizontal: Horizontal {
        switch self {
        case .topLeading, .centerLeading, .bottomLeading: .leading
        case .topTrailing, .centerTrailing, .bottomTrailing: .trailing
        case .topCenter, .center, .bottomCenter: .center
        }
    }

    var vertical: Vertical {
        switch self {
        case .topLeading, .topCenter, .topTrailing: .top
        case .bottomLeading, .bottomCenter, .bottomTrailing: .bottom
        case .centerLeading, .center, .centerTrailing: .center
        }
    }

    enum Horizontal: Sendable { case leading, center, trailing }
    enum Vertical: Sendable { case top, center, bottom }
}

enum ShortcutGuideModifierResolver {
    /// Matches only the two advertised modifier families. Caps Lock is harmless, while every
    /// other extra modifier makes the family ambiguous and therefore deliberately hidden.
    static func resolve(carbonModifiers: UInt32, configuration: HotKeyConfiguration) -> ShortcutFamily? {
        let supported = UInt32(controlKey | optionKey | shiftKey | cmdKey)
        let modifiers = carbonModifiers & supported
        for family in ShortcutFamily.allCases where modifiers == configuration.modifierMask(for: family) {
            return family
        }
        return nil
    }

    static func resolve(carbonModifiers: UInt32) -> ShortcutFamily? {
        resolve(carbonModifiers: carbonModifiers, configuration: HotKeyConfiguration())
    }

    static func resolve(_ modifiers: NSEvent.ModifierFlags, configuration: HotKeyConfiguration) -> ShortcutFamily? {
        guard !modifiers.contains(.function) else { return nil }
        return resolve(carbonModifiers: HotKeyManager.carbonModifiers(from: modifiers), configuration: configuration)
    }

    static func resolve(_ modifiers: NSEvent.ModifierFlags) -> ShortcutFamily? {
        resolve(modifiers, configuration: HotKeyConfiguration())
    }
}

struct ShortcutGuideObservationGeneration: Equatable, Sendable {
    private(set) var value: UInt64 = 0

    mutating func advance() -> UInt64 {
        value &+= 1
        return value
    }

    func accepts(_ candidate: UInt64) -> Bool { candidate == value }
}

struct ShortcutGuideAction: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case workspaceSwitch(UUID)
        case workspaceMove(UUID)
        case global(ConfigurableHotKeyAction)
    }

    let id: String
    let kind: Kind
    let title: String
    let keyLabel: String
    let isDirectional: Bool
}

struct ShortcutGuideContent: Equatable, Sendable {
    let family: ShortcutFamily
    let modifierLabel: String
    let primaryActions: [ShortcutGuideAction]
    let secondaryActions: [ShortcutGuideAction]

    init(
        family: ShortcutFamily,
        primaryActions: [ShortcutGuideAction],
        secondaryActions: [ShortcutGuideAction],
        modifierLabel: String? = nil
    ) {
        self.family = family
        self.primaryActions = primaryActions
        self.secondaryActions = secondaryActions
        self.modifierLabel = modifierLabel ?? Self.label(for: family.defaultModifiers)
    }

    static func label(for modifiers: UInt32) -> String {
        HotKeyChord(keyCode: 0, modifiers: modifiers).keyCaps.dropLast().joined(separator: " + ")
    }

    var hasActions: Bool { !primaryActions.isEmpty || !secondaryActions.isEmpty }
}

struct ShortcutGuidePresentationGroups: Equatable, Sendable {
    let regularSecondaryActions: [ShortcutGuideAction]
    let clusteredDirectionalActions: [ShortcutGuideAction]

    init(actions: [ShortcutGuideAction]) {
        let directional = actions.filter(\.isDirectional)
        let directionalKinds = directional.compactMap { action -> ConfigurableHotKeyAction? in
            guard case let .global(value) = action.kind else { return nil }
            return value
        }
        let hasFocus = directionalKinds.contains {
            [.focusLeft, .focusDown, .focusUp, .focusRight].contains($0)
        }
        let hasMove = directionalKinds.contains {
            [.moveLeft, .moveDown, .moveUp, .moveRight].contains($0)
        }
        if hasFocus && hasMove {
            regularSecondaryActions = actions
            clusteredDirectionalActions = []
        } else {
            regularSecondaryActions = actions.filter { !$0.isDirectional }
            clusteredDirectionalActions = directional
        }
    }
}

enum ShortcutGuideActionGroupKind: String, Equatable, Sendable {
    case switchWorkspace
    case supporting
    case cycleWindows
    case arrangeWindow
    case chooseLayout
    case moveWorkspace
    case focusWindow
    case reorderWindow
    case other

    var title: String? {
        switch self {
        case .switchWorkspace: "Switch Workspace"
        case .supporting: nil
        case .cycleWindows: "Cycle Windows in Order"
        case .arrangeWindow: "Arrange Window"
        case .chooseLayout: "Choose Layout"
        case .moveWorkspace: "Move Workspace"
        case .focusWindow: "Focus Window"
        case .reorderWindow: "Reorder Window"
        case .other: "More"
        }
    }
}

struct ShortcutGuideActionGroup: Identifiable, Equatable, Sendable {
    let kind: ShortcutGuideActionGroupKind
    let actions: [ShortcutGuideAction]

    var id: ShortcutGuideActionGroupKind { kind }
    var title: String? { kind.title }
}

enum ShortcutGuideActionGroupBuilder {
    static func build(
        family: ShortcutFamily,
        actions: [ShortcutGuideAction]
    ) -> [ShortcutGuideActionGroup] {
        let regularActions = ShortcutGuidePresentationGroups(actions: actions).regularSecondaryActions
        let order: [ShortcutGuideActionGroupKind] = switch family {
        case .navigate: [
            .switchWorkspace, .supporting, .cycleWindows,
            .focusWindow, .reorderWindow, .other,
        ]
        case .arrange: [
            .arrangeWindow, .chooseLayout, .moveWorkspace,
            .reorderWindow, .focusWindow, .other,
        ]
        }
        let grouped = Dictionary(grouping: regularActions) { action in
            groupKind(for: action, family: family)
        }
        return order.compactMap { kind in
            guard let actions = grouped[kind], !actions.isEmpty else { return nil }
            return ShortcutGuideActionGroup(kind: kind, actions: actions)
        }
    }

    private static func groupKind(
        for action: ShortcutGuideAction,
        family: ShortcutFamily
    ) -> ShortcutGuideActionGroupKind {
        guard case let .global(value) = action.kind else { return .other }
        if [.focusLeft, .focusDown, .focusUp, .focusRight].contains(value) {
            return .focusWindow
        }
        if [.moveLeft, .moveDown, .moveUp, .moveRight].contains(value) {
            return .reorderWindow
        }
        switch family {
        case .navigate:
            return switch value {
            case .previousWorkspace, .nextWorkspace, .backAndForthWorkspace: .switchWorkspace
            case .commandWheel, .toggleDropDownApp: .supporting
            case .previousWindow, .nextWindow: .cycleWindows
            default: .other
            }
        case .arrange:
            return switch value {
            case .toggleFloating, .resizeSmaller, .resizeLarger: .arrangeWindow
            case .selectAccordion, .selectTiled: .chooseLayout
            case .moveWorkspaceToNextDisplay: .moveWorkspace
            default: .other
            }
        }
    }
}

/// Keeps the normal key map low and wide, then adds rows only when a valid configuration would
/// otherwise clip actions. Supported workspace keys can substantially outnumber the default four.
struct ShortcutGuideLayoutMetrics: Equatable, Sendable {
    let workspaceKeycapSide: CGFloat
    let secondaryKeycapSide: CGFloat
    let primaryColumnCount: Int
    let primaryRowCount: Int
    let secondaryColumnCount: Int
    let secondaryRowCount: Int
    let showsPrimaryBand: Bool
    let panelSize: CGSize

    init(size: ShortcutGuideSize, content: ShortcutGuideContent) {
        let groups = ShortcutGuidePresentationGroups(actions: content.secondaryActions)
        workspaceKeycapSide = switch size {
        case .small: 42
        case .medium: 58
        case .large: 78
        }
        secondaryKeycapSide = switch size {
        case .small: 24
        case .medium: 30
        case .large: 38
        }
        showsPrimaryBand = !content.primaryActions.isEmpty || !groups.clusteredDirectionalActions.isEmpty

        let directionalReserve = groups.clusteredDirectionalActions.isEmpty
            ? 0
            : secondaryKeycapSide * 3 + 34
        let primaryWidth = max(1, size.panelSize.width - 32 - directionalReserve)
        let primaryCapacity = max(1, Int(primaryWidth / (workspaceKeycapSide + 8)))
        primaryColumnCount = min(max(1, content.primaryActions.count), primaryCapacity)
        primaryRowCount = content.primaryActions.isEmpty
            ? 0
            : Int(ceil(Double(content.primaryActions.count) / Double(primaryColumnCount)))

        let secondaryCapacity: Int = switch size {
        case .small: 7
        case .medium: 8
        case .large: 9
        }
        secondaryColumnCount = min(max(1, groups.regularSecondaryActions.count), secondaryCapacity)
        secondaryRowCount = groups.regularSecondaryActions.isEmpty
            ? 0
            : Int(ceil(Double(groups.regularSecondaryActions.count) / Double(secondaryColumnCount)))

        let emptySecondaryReduction: CGFloat = switch size {
        case .small: 46
        case .medium: 56
        case .large: 68
        }
        let baselineHeight = content.secondaryActions.isEmpty
            ? size.panelSize.height - emptySecondaryReduction
            : size.panelSize.height
        let primaryExtra = CGFloat(max(0, primaryRowCount - 1)) * (workspaceKeycapSide + 25)
        let secondaryExtra = CGFloat(max(0, secondaryRowCount - 1)) * (secondaryKeycapSide + 10)
        panelSize = CGSize(
            width: size.panelSize.width,
            height: baselineHeight + primaryExtra + secondaryExtra
        )
    }
}

enum ShortcutGuideDisplayChoice {
    static func resolve(
        preferredIdentifier: String?,
        pointerIdentifier: String?,
        availableIdentifiers: Set<String>
    ) -> String? {
        if let preferredIdentifier, availableIdentifiers.contains(preferredIdentifier) {
            return preferredIdentifier
        }
        if let pointerIdentifier, availableIdentifiers.contains(pointerIdentifier) {
            return pointerIdentifier
        }
        return nil
    }
}

enum ShortcutGuideContentBuilder {
    static func build(
        family: ShortcutFamily,
        workspaces: [WorkspaceDefinition],
        configuration: HotKeyConfiguration,
        runtimeIssues: [HotKeyRuntimeIssue],
        conflictReport: ShortcutConfigurationReport? = nil
    ) -> ShortcutGuideContent? {
        let report = conflictReport ?? ShortcutConflictModel.evaluate(
            configuration: configuration,
            workspaces: workspaces
        )
        let blockedOwners = Set(runtimeIssues.map { $0.owner.id })
        let workspaceByID = Dictionary(uniqueKeysWithValues: workspaces.map { ($0.id, $0) })
        var primary: [ShortcutGuideAction] = []
        var secondary: [ShortcutGuideAction] = []

        for binding in report.eligibleBindings where binding.chord.modifiers == configuration.modifierMask(for: family) {
            guard !blockedOwners.contains(binding.owner.id) else { continue }
            switch binding.owner.kind {
            case .workspaceSwitch:
                guard family == .navigate,
                      let id = binding.owner.workspaceID,
                      let workspace = workspaceByID[id] else { continue }
                primary.append(ShortcutGuideAction(
                    id: binding.owner.id,
                    kind: .workspaceSwitch(id),
                    title: workspace.name,
                    keyLabel: HotKeyChord.keyLabel(for: binding.chord.keyCode),
                    isDirectional: false
                ))
            case .workspaceMove:
                guard family == .arrange,
                      let id = binding.owner.workspaceID,
                      let workspace = workspaceByID[id] else { continue }
                primary.append(ShortcutGuideAction(
                    id: binding.owner.id,
                    kind: .workspaceMove(id),
                    title: workspace.name,
                    keyLabel: HotKeyChord.keyLabel(for: binding.chord.keyCode),
                    isDirectional: false
                ))
            case .globalCommand, .commandWheel:
                guard let action = binding.owner.configurableAction else { continue }
                secondary.append(ShortcutGuideAction(
                    id: binding.owner.id,
                    kind: .global(action),
                    title: conciseTitle(action),
                    keyLabel: HotKeyChord.keyLabel(for: binding.chord.keyCode),
                    isDirectional: isDirectional(action)
                ))
            }
        }

        primary.sort { $0.keyLabel.localizedStandardCompare($1.keyLabel) == .orderedAscending }
        secondary.sort { lhs, rhs in
            guard case let .global(lhsAction) = lhs.kind,
                  case let .global(rhsAction) = rhs.kind else {
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            return displayOrder(lhsAction) < displayOrder(rhsAction)
        }
        let content = ShortcutGuideContent(
            family: family,
            primaryActions: primary,
            secondaryActions: secondary,
            modifierLabel: ShortcutGuideContent.label(for: configuration.modifierMask(for: family))
        )
        return content.hasActions ? content : nil
    }

    private static func conciseTitle(_ action: ConfigurableHotKeyAction) -> String {
        switch action {
        case .previousWorkspace: "Previous Workspace"
        case .nextWorkspace: "Next Workspace"
        case .backAndForthWorkspace: "Last Workspace"
        case .previousWindow: "Previous"
        case .nextWindow: "Next"
        case .selectAccordion: "Accordion"
        case .selectTiled: "Tiled"
        case .toggleFloating: "Floating"
        case .toggleDropDownApp: "Quick App"
        case .resizeSmaller: "Smaller"
        case .resizeLarger: "Larger"
        case .moveWorkspaceToNextDisplay: "Next Display"
        case .commandWheel: "Commands"
        default: action.title
        }
    }

    private static func isDirectional(_ action: ConfigurableHotKeyAction) -> Bool {
        [.focusLeft, .focusDown, .focusUp, .focusRight, .moveLeft, .moveDown, .moveUp, .moveRight].contains(action)
    }

    private static func displayOrder(_ action: ConfigurableHotKeyAction) -> Int {
        switch action {
        case .previousWorkspace: 0
        case .nextWorkspace: 1
        case .backAndForthWorkspace: 2
        case .commandWheel: 3
        case .toggleFloating: 4
        case .toggleDropDownApp: 5
        case .resizeSmaller: 7
        case .resizeLarger: 8
        default:
            100 + (ConfigurableHotKeyAction.allCases.firstIndex(of: action) ?? 0)
        }
    }
}

struct ShortcutGuideGeometry {
    static func frame(
        panelSize: CGSize,
        visibleFrame: CGRect,
        position: ShortcutGuidePosition,
        margin: CGFloat = 24
    ) -> CGRect {
        let size = CGSize(width: min(panelSize.width, visibleFrame.width), height: min(panelSize.height, visibleFrame.height))
        let x: CGFloat = switch position.horizontal {
        case .leading: visibleFrame.minX + margin
        case .center: visibleFrame.midX - size.width / 2
        case .trailing: visibleFrame.maxX - size.width - margin
        }
        let y: CGFloat = switch position.vertical {
        case .top: visibleFrame.maxY - size.height - margin
        case .center: visibleFrame.midY - size.height / 2
        case .bottom: visibleFrame.minY + margin
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: size).clamped(to: visibleFrame.insetBy(dx: min(margin, visibleFrame.width / 2), dy: min(margin, visibleFrame.height / 2)))
    }
}

private extension CGRect {
    func clamped(to bounds: CGRect) -> CGRect {
        CGRect(
            x: min(max(minX, bounds.minX), max(bounds.minX, bounds.maxX - width)),
            y: min(max(minY, bounds.minY), max(bounds.minY, bounds.maxY - height)),
            width: min(width, bounds.width),
            height: min(height, bounds.height)
        )
    }
}

protocol ShortcutGuideEventMonitoring: AnyObject {
    @discardableResult func addGlobalFlagsChanged(_ handler: @escaping (NSEvent.ModifierFlags) -> Void) -> Any?
    @discardableResult func addLocalFlagsChanged(_ handler: @escaping (NSEvent) -> NSEvent?) -> Any?
    func removeMonitor(_ monitor: Any)
}

final class AppKitShortcutGuideEventMonitor: ShortcutGuideEventMonitoring {
    func addGlobalFlagsChanged(_ handler: @escaping (NSEvent.ModifierFlags) -> Void) -> Any? {
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { handler($0.modifierFlags) }
    }

    func addLocalFlagsChanged(_ handler: @escaping (NSEvent) -> NSEvent?) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: handler)
    }

    func removeMonitor(_ monitor: Any) { NSEvent.removeMonitor(monitor) }
}

/// Owns paired monitors and always returns local events unmodified. Presentation stays injected so
/// this seam can be tested without requesting Accessibility or observing a real desktop.
final class ShortcutGuideModifierMonitor {
    private let events: ShortcutGuideEventMonitoring
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var handler: ((ShortcutFamily?) -> Void)?
    private var configuration = HotKeyConfiguration()

    init(events: ShortcutGuideEventMonitoring = AppKitShortcutGuideEventMonitor()) { self.events = events }

    var isRunning: Bool { globalMonitor != nil && localMonitor != nil }

    @discardableResult
    func start(
        configuration: HotKeyConfiguration,
        handler: @escaping (ShortcutFamily?) -> Void
    ) -> Bool {
        stop()
        self.configuration = configuration
        self.handler = handler
        globalMonitor = events.addGlobalFlagsChanged { [weak self] modifiers in
            guard let self else { return }
            self.handler?(ShortcutGuideModifierResolver.resolve(modifiers, configuration: self.configuration))
        }
        localMonitor = events.addLocalFlagsChanged { [weak self] event in
            guard let self else { return event }
            self.handler?(ShortcutGuideModifierResolver.resolve(event.modifierFlags, configuration: self.configuration))
            return event
        }
        guard isRunning else {
            stop()
            return false
        }
        return true
    }

    @discardableResult
    func start(handler: @escaping (ShortcutFamily?) -> Void) -> Bool {
        start(configuration: HotKeyConfiguration(), handler: handler)
    }

    func stop() {
        if let globalMonitor { events.removeMonitor(globalMonitor) }
        if let localMonitor { events.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        handler?(nil)
        handler = nil
    }
}

struct ShortcutGuidePanelPolicy: Equatable, Sendable {
    let canBecomeKey: Bool
    let canBecomeMain: Bool
    let ignoresMouseEvents: Bool
    let participatesInWindowCycle: Bool

    static let passive = ShortcutGuidePanelPolicy(
        canBecomeKey: false,
        canBecomeMain: false,
        ignoresMouseEvents: true,
        participatesInWindowCycle: false
    )
}

private final class ShortcutGuidePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ShortcutGuidePanelController {
    private var panel: ShortcutGuidePanel?
    private var presentedContent: ShortcutGuideContent?
    private var presentedSize: ShortcutGuideSize?
    private var presentedPosition: ShortcutGuidePosition?

    var isVisible: Bool { panel?.isVisible == true }
    var panelForTesting: NSPanel { makePanelIfNeeded() }

    func present(
        _ content: ShortcutGuideContent,
        size: ShortcutGuideSize,
        position: ShortcutGuidePosition,
        preferredDisplayIdentifier: String? = nil,
        reducedMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
        pointerLocation: CGPoint = NSEvent.mouseLocation,
        screens: [NSScreen] = NSScreen.screens
    ) {
        let panel = makePanelIfNeeded()
        let pointerScreen = screen(for: pointerLocation, screens: screens)
        let identifiers = Dictionary(uniqueKeysWithValues: screens.compactMap { screen in
            displayIdentifier(for: screen).map { ($0, screen) }
        })
        let selectedIdentifier = ShortcutGuideDisplayChoice.resolve(
            preferredIdentifier: preferredDisplayIdentifier,
            pointerIdentifier: pointerScreen.flatMap(displayIdentifier(for:)),
            availableIdentifiers: Set(identifiers.keys)
        )
        guard let screen = selectedIdentifier.flatMap({ identifiers[$0] })
            ?? pointerScreen
            ?? NSScreen.main
            ?? screens.first else { return }
        let panelSize = size.panelSize(for: content)
        let frame = ShortcutGuideGeometry.frame(
            panelSize: panelSize,
            visibleFrame: screen.visibleFrame,
            position: position
        )
        if panel.isVisible,
           presentedContent == content,
           presentedSize == size,
           presentedPosition == position,
           panel.frame == frame {
            return
        }
        panel.setFrame(frame, display: false)
        panel.contentView = NSHostingView(rootView: ShortcutGuideView(content: content, size: size))
        presentedContent = content
        presentedSize = size
        presentedPosition = position
        if reducedMotion {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        } else {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.08
                panel.animator().alphaValue = 1
            }
        }
    }

    func dismiss() {
        guard let panel else { return }
        panel.orderOut(nil)
        panel.alphaValue = 1
        presentedContent = nil
        presentedSize = nil
        presentedPosition = nil
    }

    func stop() { dismiss() }

    private func makePanelIfNeeded() -> ShortcutGuidePanel {
        if let panel { return panel }
        let panel = ShortcutGuidePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = ShortcutGuidePanelPolicy.passive.ignoresMouseEvents
        panel.level = .statusBar
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        self.panel = panel
        return panel
    }

    private func screen(for point: CGPoint, screens: [NSScreen]) -> NSScreen? {
        screens.first(where: { $0.frame.contains(point) })
    }

    private func displayIdentifier(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber,
        let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}

struct ShortcutGuideView: View {
    let content: ShortcutGuideContent
    let size: ShortcutGuideSize
    let surfaceStyle: ShortcutGuideSurfaceStyle

    init(
        content: ShortcutGuideContent,
        size: ShortcutGuideSize = .defaultValue,
        surfaceStyle: ShortcutGuideSurfaceStyle = .automatic
    ) {
        self.content = content
        self.size = size
        self.surfaceStyle = surfaceStyle
    }

    private var regularSecondaryActions: [ShortcutGuideAction] {
        presentationGroups.regularSecondaryActions
    }

    private var clusteredDirectionalActions: [ShortcutGuideAction] {
        presentationGroups.clusteredDirectionalActions
    }

    private var presentationGroups: ShortcutGuidePresentationGroups {
        ShortcutGuidePresentationGroups(actions: content.secondaryActions)
    }

    private var actionGroups: [ShortcutGuideActionGroup] {
        ShortcutGuideActionGroupBuilder.build(
            family: content.family,
            actions: content.secondaryActions
        )
    }

    private var layoutMetrics: ShortcutGuideLayoutMetrics {
        ShortcutGuideLayoutMetrics(size: size, content: content)
    }

    private var workspaceKeycapSide: CGFloat {
        layoutMetrics.workspaceKeycapSide
    }

    private var secondaryKeycapSide: CGFloat {
        layoutMetrics.secondaryKeycapSide
    }

    private var headerFontSize: CGFloat {
        switch size {
        case .small: 12
        case .medium: 14
        case .large: 17
        }
    }

    private var actionFontSize: CGFloat {
        switch size {
        case .small: 11
        case .medium: 12
        case .large: 14
        }
    }

    private var groupTitleFontSize: CGFloat {
        switch size {
        case .small: 8
        case .medium: 9
        case .large: 11
        }
    }

    private var groupSpacing: CGFloat {
        switch size {
        case .small: 4
        case .medium: 5
        case .large: 7
        }
    }

    private var contentPadding: CGFloat {
        switch size {
        case .small: 12
        case .medium: 14
        case .large: 16
        }
    }

    private var sectionSpacing: CGFloat {
        switch size {
        case .small: 6
        case .medium: 8
        case .large: 10
        }
    }

    private var directionalColumnWidth: CGFloat {
        switch size {
        case .small: 132
        case .medium: 154
        case .large: 176
        }
    }

    var body: some View {
        ZStack {
            if surfaceStyle == .snapshot {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.white.opacity(0.14), lineWidth: 1)
                    }
            } else {
                ShortcutGuideGlassSurface(style: surfaceStyle)
            }
            VStack(alignment: .leading, spacing: sectionSpacing) {
                HStack(spacing: 8) {
                    Text(content.modifierLabel)
                        .font(.system(size: headerFontSize, weight: .bold))
                        .foregroundStyle(.blue)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(content.family.title)
                        .font(.system(size: headerFontSize, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                if layoutMetrics.showsPrimaryBand {
                    HStack(alignment: .top, spacing: 14) {
                        if !content.primaryActions.isEmpty {
                            VStack(alignment: .leading, spacing: groupSpacing) {
                                groupTitle(primaryGroupTitle)
                                LazyVGrid(
                                    columns: Array(
                                        repeating: GridItem(.flexible(), spacing: 8),
                                        count: layoutMetrics.primaryColumnCount
                                    ),
                                    spacing: 8
                                ) {
                                    ForEach(content.primaryActions) { action in
                                        VStack(spacing: 5) {
                                            ShortcutGuideKeycap(
                                                label: action.keyLabel,
                                                side: workspaceKeycapSide
                                            )
                                            Text(workspaceTitle(for: action))
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.68)
                                                .font(.system(size: actionFontSize, weight: .medium))
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if !content.primaryActions.isEmpty, !clusteredDirectionalActions.isEmpty {
                            Divider()
                                .overlay(.white.opacity(0.16))
                                .frame(height: workspaceKeycapSide + 34)
                        }
                        if !clusteredDirectionalActions.isEmpty {
                            VStack(spacing: groupSpacing) {
                                directionalCluster
                                Text(directionalGroupTitle)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                    .font(.system(size: actionFontSize, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: directionalColumnWidth)
                            .frame(minHeight: workspaceKeycapSide + 34, alignment: .center)
                        }
                    }
                }
                if !regularSecondaryActions.isEmpty {
                    Divider().overlay(.white.opacity(0.18))
                    if layoutMetrics.secondaryRowCount > 1 {
                        denseSecondaryGrid
                    } else {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(Array(actionGroups.enumerated()), id: \.element.id) { index, group in
                                if index > 0 {
                                    Divider()
                                        .overlay(.white.opacity(0.16))
                                }
                                actionGroup(group)
                            }
                        }
                    }
                }
            }
            .padding(contentPadding)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityHidden(true)
    }

    private func workspaceTitle(for action: ShortcutGuideAction) -> String {
        action.title.caseInsensitiveCompare(action.keyLabel) == .orderedSame
            ? "Workspace \(action.title)"
            : action.title
    }

    private var primaryGroupTitle: String {
        switch content.family {
        case .navigate: "Workspaces"
        case .arrange: "Move Window to Workspace"
        }
    }

    private var directionalGroupTitle: String {
        switch content.family {
        case .navigate: "Focus by direction"
        case .arrange: "Reorder by direction"
        }
    }

    private func groupTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .font(.system(size: groupTitleFontSize, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private func actionGroup(_ group: ShortcutGuideActionGroup) -> some View {
        VStack(alignment: .center, spacing: groupSpacing) {
            if let title = group.title {
                groupTitle(displayTitle(for: group.kind, fallback: title))
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Color.clear
                    .frame(height: groupTitleFontSize + 2)
                    .accessibilityHidden(true)
            }
            HStack(spacing: groupSpacing) {
                ForEach(group.actions) { action in
                    HStack(spacing: groupSpacing) {
                        ShortcutGuideKeycap(
                            label: action.keyLabel,
                            compact: true,
                            side: secondaryKeycapSide
                        )
                        Text(displayTitle(for: action))
                            .lineLimit(2)
                            .minimumScaleFactor(0.62)
                            .font(.system(size: actionFontSize, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func displayTitle(
        for kind: ShortcutGuideActionGroupKind,
        fallback: String
    ) -> String {
        if size == .small, kind == .cycleWindows { return "Cycle Windows" }
        return fallback
    }

    private func displayTitle(for action: ShortcutGuideAction) -> String {
        guard size == .small, case let .global(value) = action.kind else { return action.title }
        return switch value {
        case .previousWorkspace: "Previous"
        case .nextWorkspace: "Next"
        case .backAndForthWorkspace: "Last"
        default: action.title
        }
    }

    private var denseSecondaryGrid: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 11),
                count: layoutMetrics.secondaryColumnCount
            ),
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(regularSecondaryActions) { action in
                HStack(spacing: 5) {
                    ShortcutGuideKeycap(
                        label: action.keyLabel,
                        compact: true,
                        side: secondaryKeycapSide
                    )
                    Text(action.title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .font(.system(size: actionFontSize, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func directionalAction(_ candidate: ConfigurableHotKeyAction) -> ShortcutGuideAction? {
        clusteredDirectionalActions.first { action in
            guard case let .global(value) = action.kind else { return false }
            return value == candidate
        }
    }

    @ViewBuilder
    private var directionalCluster: some View {
        let usesFocusActions = clusteredDirectionalActions.contains { action in
            guard case let .global(value) = action.kind else { return false }
            return [.focusLeft, .focusDown, .focusUp, .focusRight].contains(value)
        }
        let left = directionalAction(usesFocusActions ? .focusLeft : .moveLeft)
        let down = directionalAction(usesFocusActions ? .focusDown : .moveDown)
        let up = directionalAction(usesFocusActions ? .focusUp : .moveUp)
        let right = directionalAction(usesFocusActions ? .focusRight : .moveRight)
        VStack(spacing: 4) {
            directionalKeycap(up)
            HStack(spacing: 4) {
                directionalKeycap(left)
                directionalKeycap(down)
                directionalKeycap(right)
            }
        }
    }

    @ViewBuilder
    private func directionalKeycap(_ action: ShortcutGuideAction?) -> some View {
        if let action {
            ShortcutGuideKeycap(
                label: action.keyLabel,
                compact: true,
                side: secondaryKeycapSide
            )
        } else {
            Color.clear.frame(width: secondaryKeycapSide, height: secondaryKeycapSide)
        }
    }
}

private struct ShortcutGuideKeycap: View {
    let label: String
    var compact = false
    var side: CGFloat?

    var body: some View {
        Group {
            if let side, !compact {
                labelView.frame(width: side, height: side)
            } else if let side {
                labelView.frame(minWidth: side, minHeight: side)
            } else {
                labelView.frame(
                    minWidth: compact ? 22 : 28,
                    minHeight: compact ? 20 : 26
                )
            }
        }
        .padding(.horizontal, horizontalPadding)
        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 1))
    }

    private var horizontalPadding: CGFloat {
        if compact, label.caseInsensitiveCompare("Space") == .orderedSame { return 8 }
        return side == nil ? (compact ? 3 : 5) : 0
    }

    private var labelView: some View {
        Text(label)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .font(.system(
                size: side.map { max(compact ? 11 : 13, $0 * 0.38) } ?? (compact ? 11 : 13),
                weight: .bold,
                design: .rounded
            ))
            .foregroundStyle(.primary)
    }
}

enum ShortcutGuideSurfaceStyle: Equatable {
    case automatic
    case fallback
    case snapshot
}

private struct ShortcutGuideGlassSurface: NSViewRepresentable {
    let style: ShortcutGuideSurfaceStyle

    func makeNSView(context: Context) -> NSView {
        if style == .automatic, #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = 18
            glass.setAccessibilityElement(false)
            return glass
        }
        let visual = NSVisualEffectView()
        visual.material = .hudWindow
        visual.blendingMode = .behindWindow
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 18
        visual.layer?.masksToBounds = true
        visual.setAccessibilityElement(false)
        return visual
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
