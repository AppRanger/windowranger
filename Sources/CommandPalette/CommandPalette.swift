import AppKit
import Carbon.HIToolbox
import SwiftUI

enum CommandPaletteSection: String, CaseIterable, Equatable, Sendable {
    case suggested
    case window
    case workspace
    case layout
    case profiles
    case application

    var title: String {
        switch self {
        case .suggested: "Suggested"
        case .window: "Window"
        case .workspace: "Workspace"
        case .layout: "Layout"
        case .profiles: "Profiles"
        case .application: "WindowRanger"
        }
    }
}

enum CommandPaletteDestination: Hashable, Sendable {
    case command(WindowManagerCommand)
    case settings
}

struct CommandPaletteEntry: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String
    let shortcut: String?
    let systemImage: String
    let section: CommandPaletteSection
    let destination: CommandPaletteDestination
    let searchTerms: [String]
}

enum CommandPaletteIndex {
    static func entries(
        context: RadialCommandContext,
        query: String,
        hotKeyConfiguration: HotKeyConfiguration,
        isPauseModeEnabled: Bool = false
    ) -> [CommandPaletteEntry] {
        if isPauseModeEnabled {
            return filtered(
                [pauseModeEntry(isPaused: true)],
                query: query
            )
        }
        var entries = contextualEntries(
            context: context,
            hotKeyConfiguration: hotKeyConfiguration
        )
        entries.append(pauseModeEntry(isPaused: false))
        entries.append(CommandPaletteEntry(
            id: "application:settings",
            title: "Open Settings",
            detail: "WindowRanger",
            shortcut: "⌘ ,",
            systemImage: "gearshape",
            section: .application,
            destination: .settings,
            searchTerms: ["preferences", "configuration", "shortcuts"]
        ))

        entries = CommandPaletteSection.allCases.flatMap { section in
            entries.filter { $0.section == section }
        }

        return filtered(entries, query: query)
    }

    private static func filtered(
        _ entries: [CommandPaletteEntry],
        query: String
    ) -> [CommandPaletteEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return entries }
        return entries.enumerated().compactMap { offset, entry -> (Int, Int, CommandPaletteEntry)? in
            guard let score = matchScore(entry, needle: needle) else { return nil }
            return (score, offset, entry)
        }
        .sorted {
            if $0.0 != $1.0 { return $0.0 > $1.0 }
            return $0.1 < $1.1
        }
        .prefix(40)
        .map(\.2)
    }

    private static func pauseModeEntry(isPaused: Bool) -> CommandPaletteEntry {
        CommandPaletteEntry(
            id: isPaused ? "application:resume" : "application:pause",
            title: isPaused ? "Resume WindowRanger" : "Pause WindowRanger",
            detail: isPaused
                ? "Resume shortcuts and reconcile managed windows"
                : "Temporarily stop shortcuts and window management",
            shortcut: nil,
            systemImage: isPaused ? "play.circle" : "pause.circle",
            section: .application,
            destination: .command(.setPauseMode(!isPaused)),
            searchTerms: isPaused
                ? ["unpause", "continue", "start", "hotkeys"]
                : ["stop", "suspend", "freeze", "hotkeys"]
        )
    }

    static func spatialPlacementActions(in context: RadialCommandContext) -> [RadialMenuItem] {
        RadialCommandCatalogue.resolveSpatialPlacement(context: context)?.children ?? []
    }

    static func hasSpatialPlacementActions(in context: RadialCommandContext) -> Bool {
        !spatialPlacementActions(in: context).isEmpty
    }

    static func contains(
        _ destination: CommandPaletteDestination,
        context: RadialCommandContext,
        hotKeyConfiguration: HotKeyConfiguration,
        isPauseModeEnabled: Bool = false
    ) -> Bool {
        entries(
            context: context,
            query: "",
            hotKeyConfiguration: hotKeyConfiguration,
            isPauseModeEnabled: isPauseModeEnabled
        )
            .contains { $0.destination == destination }
    }

    private static func contextualEntries(
        context: RadialCommandContext,
        hotKeyConfiguration: HotKeyConfiguration
    ) -> [CommandPaletteEntry] {
        var entries: [CommandPaletteEntry] = []
        var includedCommands = Set<WindowManagerCommand>()

        for reference in RadialTopLevelItemID.allKnown {
            guard let item = RadialCommandCatalogue.resolve(reference, context: context) else { continue }
            append(
                item,
                reference: reference,
                context: context,
                hotKeyConfiguration: hotKeyConfiguration,
                to: &entries,
                includedCommands: &includedCommands
            )
        }

        for action in ConfigurableHotKeyAction.allCases {
            guard action != .commandWheel,
                  let command = action.command,
                  !includedCommands.contains(command),
                  isAvailable(action, context: context)
            else { continue }
            entries.append(CommandPaletteEntry(
                id: "shortcut:\(action.rawValue)",
                title: action.title,
                detail: detail(for: action, context: context),
                shortcut: hotKeyConfiguration.optionalChord(for: action)?.title,
                systemImage: systemImage(for: action),
                section: section(for: action),
                destination: .command(command),
                searchTerms: searchTerms(for: action)
            ))
            includedCommands.insert(command)
        }

        appendCurrentApplicationEntries(context: context, to: &entries)

        if !context.quickApps.isEmpty {
            for app in context.quickApps {
                let bundle = app.bundleIdentifier
                let command = WindowManagerCommand.selectQuickApp(bundle)
                guard includedCommands.insert(command).inserted else { continue }
                entries.append(CommandPaletteEntry(
                    id: "quick-app:\(bundle)",
                    title: "Show \(app.displayName)",
                    detail: "Quick App · \(context.workspaceName)",
                    shortcut: nil,
                    systemImage: "rectangle.bottomthird.inset.filled",
                    section: .application,
                    destination: .command(command),
                    searchTerms: ["quick app", "shelf", "show", bundle]
                ))
            }
            if context.quickApps.count > 1 {
                for (offset, title, terms) in [
                    (-1, "Previous Quick App", ["quick app", "shelf", "previous", "cycle"]),
                    (1, "Next Quick App", ["quick app", "shelf", "next", "cycle"]),
                ] {
                    let command = WindowManagerCommand.cycleQuickApp(offset)
                    guard includedCommands.insert(command).inserted else { continue }
                    entries.append(CommandPaletteEntry(
                        id: "quick-app-cycle:\(offset)",
                        title: title,
                        detail: "Quick App Shelf",
                        shortcut: nil,
                        systemImage: offset < 0 ? "chevron.left" : "chevron.right",
                        section: .application,
                        destination: .command(command),
                        searchTerms: terms
                    ))
                }
            }
        }

        return entries
    }

    private static func appendCurrentApplicationEntries(
        context: RadialCommandContext,
        to entries: inout [CommandPaletteEntry]
    ) {
        guard let application = context.currentApplication,
              let activeProfileID = context.activeProfileID
        else { return }
        let bundleIdentifier = application.bundleIdentifier
        let normalizedBundleIdentifier = bundleIdentifier.lowercased()
        let hasApplicationRule = context.applicationRuleBundleIdentifiers.contains(normalizedBundleIdentifier)
        let isInQuickAppShelf = context.quickApps.contains {
            $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
        }

        if !hasApplicationRule {
            let command = WindowManagerCommand.addCurrentApplication(
                bundleIdentifier, displayName: application.displayName,
                workspaceID: context.workspaceID, profileID: activeProfileID
            )
            entries.append(CommandPaletteEntry(
                id: "current-application:applications:\(normalizedBundleIdentifier)",
                title: isInQuickAppShelf
                    ? "Move \(application.displayName) to Applications"
                    : "Add \(application.displayName) to Applications",
                detail: isInQuickAppShelf
                    ? "Remove from App Shelf · \(context.workspaceName)"
                    : "Application rule · \(context.workspaceName)",
                shortcut: nil, systemImage: "app.badge", section: .application,
                destination: .command(command),
                searchTerms: ["current app", "application", "applications", "settings", "rule", "add", "move", bundleIdentifier]
            ))
        }

        if QuickAppShelfPolicy.isEligible(bundleIdentifier: bundleIdentifier),
           !isInQuickAppShelf,
           context.quickApps.count < QuickAppShelfPolicy.maximumCount {
            let command = WindowManagerCommand.addCurrentApplicationToQuickAppShelf(
                bundleIdentifier, displayName: application.displayName, profileID: activeProfileID
            )
            entries.append(CommandPaletteEntry(
                id: "current-application:quick-app-shelf:\(normalizedBundleIdentifier)",
                title: hasApplicationRule
                    ? "Move \(application.displayName) to App Shelf"
                    : "Add \(application.displayName) to App Shelf",
                detail: hasApplicationRule
                    ? "Remove its application rule · App Shelf"
                    : "Quick access from every workspace",
                shortcut: nil, systemImage: "rectangle.bottomthird.inset.filled", section: .application,
                destination: .command(command),
                searchTerms: ["current app", "quick app", "app shelf", "shelf", "add", "move", bundleIdentifier]
            ))
        }
    }

    private static func append(
        _ item: RadialMenuItem,
        reference: RadialTopLevelItemID,
        context: RadialCommandContext,
        hotKeyConfiguration: HotKeyConfiguration,
        to entries: inout [CommandPaletteEntry],
        includedCommands: inout Set<WindowManagerCommand>
    ) {
        if let command = item.command {
            appendEntry(
                item: item,
                command: command,
                title: title(for: item, reference: reference, isChild: false, alternate: false),
                reference: reference,
                context: context,
                hotKeyConfiguration: hotKeyConfiguration,
                suffix: "primary",
                to: &entries,
                includedCommands: &includedCommands
            )
        }
        for child in item.children {
            if let command = child.command {
                appendEntry(
                    item: child,
                    command: command,
                    title: title(for: child, reference: reference, isChild: true, alternate: false),
                    reference: reference,
                    context: context,
                    hotKeyConfiguration: hotKeyConfiguration,
                    suffix: "primary",
                    to: &entries,
                    includedCommands: &includedCommands
                )
            }
            if let alternate = child.alternateCommand {
                appendEntry(
                    item: child,
                    command: alternate,
                    title: title(for: child, reference: reference, isChild: true, alternate: true),
                    reference: reference,
                    context: context,
                    hotKeyConfiguration: hotKeyConfiguration,
                    suffix: "alternate",
                    to: &entries,
                    includedCommands: &includedCommands
                )
            }
        }
    }

    private static func appendEntry(
        item: RadialMenuItem,
        command: WindowManagerCommand,
        title: String,
        reference: RadialTopLevelItemID,
        context: RadialCommandContext,
        hotKeyConfiguration: HotKeyConfiguration,
        suffix: String,
        to entries: inout [CommandPaletteEntry],
        includedCommands: inout Set<WindowManagerCommand>
    ) {
        guard includedCommands.insert(command).inserted else { return }
        entries.append(CommandPaletteEntry(
            id: "context:\(reference.rawValue):\(item.id):\(suffix)",
            title: title,
            detail: item.detail ?? detail(for: reference, context: context),
            shortcut: shortcut(
                for: command,
                context: context,
                hotKeyConfiguration: hotKeyConfiguration
            ),
            systemImage: item.systemImage,
            section: section(for: reference),
            destination: .command(command),
            searchTerms: [reference.rawValue, item.label, item.detail ?? ""]
        ))
    }

    private static func matchScore(_ entry: CommandPaletteEntry, needle: String) -> Int? {
        let title = entry.title.lowercased()
        let words = needle.split(whereSeparator: \.isWhitespace).map(String.init)
        let haystack = ([entry.title, entry.detail, entry.section.title] + entry.searchTerms)
            .joined(separator: " ")
            .lowercased()
        guard words.allSatisfy({ haystack.contains($0) }) else { return nil }
        if title == needle { return 500 }
        if title.hasPrefix(needle) { return 400 }
        if title.contains(needle) { return 300 }
        return 200
    }

    private static func title(
        for item: RadialMenuItem,
        reference: RadialTopLevelItemID,
        isChild: Bool,
        alternate: Bool
    ) -> String {
        guard isChild else {
            if reference == .layoutType { return "Cycle Layout" }
            return item.label
        }
        switch reference {
        case .moveToSpace:
            return alternate ? "Move and Follow to \(item.label)" : "Move to \(item.label)"
        case .goToSpace: return "Go to \(item.label)"
        case .profiles:
            return item.id == "profile-resume-automatic"
                ? item.label
                : "Use \(item.label) Profile"
        case .layoutType: return "Use \(item.label) Layout"
        case .resize:
            return item.label.hasPrefix("Place ") ? item.label : "Place Window \(item.label)"
        default: return item.label
        }
    }

    private static func section(for reference: RadialTopLevelItemID) -> CommandPaletteSection {
        switch reference {
        case .moveToSpace, .resize: .window
        case .goToSpace, .nextSpace, .previousSpace, .resetWindowsInSpace, .resetAllWindows: .workspace
        case .layoutType: .layout
        case .profiles: .profiles
        default: .suggested
        }
    }

    private static func detail(for reference: RadialTopLevelItemID, context: RadialCommandContext) -> String {
        switch section(for: reference) {
        case .window: "Focused window · \(context.workspaceName)"
        case .workspace: "\(context.workspaceName) · \(context.displayName)"
        case .layout: "\(context.layout.title) · \(context.workspaceName)"
        case .profiles: "Profile"
        case .application, .suggested: "Command"
        }
    }

    private static func shortcut(
        for command: WindowManagerCommand,
        context: RadialCommandContext,
        hotKeyConfiguration: HotKeyConfiguration
    ) -> String? {
        if let action = ConfigurableHotKeyAction.allCases.first(where: { $0.command == command }) {
            return hotKeyConfiguration.optionalChord(for: action)?.title
        }
        switch command {
        case let .setLayout(layout):
            let action: ConfigurableHotKeyAction? = switch layout {
            case .accordion: .selectAccordion
            case .tiled: .selectTiled
            case .none: nil
            }
            return action.flatMap { hotKeyConfiguration.optionalChord(for: $0)?.title }
        case let .switchWorkspace(id):
            return context.workspaces.first(where: { $0.id == id }).flatMap {
                workspaceShortcut(
                    $0.key,
                    modifiers: hotKeyConfiguration.modifierMask(for: .navigate)
                )
            }
        case let .moveFocusedWindow(id):
            return context.workspaces.first(where: { $0.id == id }).flatMap {
                workspaceShortcut(
                    $0.key,
                    modifiers: hotKeyConfiguration.modifierMask(for: .arrange)
                )
            }
        default: return nil
        }
    }

    private static func workspaceShortcut(_ key: String, modifiers: UInt32) -> String? {
        guard let keyCode = HotKeyManager.keyCodes[key.lowercased()] else { return nil }
        return HotKeyChord(keyCode: keyCode, modifiers: modifiers).title
    }

    private static func isAvailable(
        _ action: ConfigurableHotKeyAction,
        context: RadialCommandContext
    ) -> Bool {
        switch action {
        case .toggleFloating: context.focusedWindow != nil
        case .focusLeft: context.availableFocusDirections.contains(.left)
        case .focusDown: context.availableFocusDirections.contains(.down)
        case .focusUp: context.availableFocusDirections.contains(.up)
        case .focusRight: context.availableFocusDirections.contains(.right)
        case .moveLeft: context.availableMoveDirections.contains(.left)
        case .moveDown: context.availableMoveDirections.contains(.down)
        case .moveUp: context.availableMoveDirections.contains(.up)
        case .moveRight: context.availableMoveDirections.contains(.right)
        case .resizeSmaller, .resizeLarger: context.canSmartResize
        case .moveWorkspaceToNextDisplay:
            context.displayMode == .independent && context.connectedDisplayIdentifiers.count > 1
        case .commandWheel: false
        default: true
        }
    }

    private static func section(for action: ConfigurableHotKeyAction) -> CommandPaletteSection {
        switch action {
        case .previousWorkspace, .nextWorkspace, .backAndForthWorkspace,
             .moveWorkspaceToNextDisplay: .workspace
        case .selectAccordion, .selectTiled: .layout
        case .toggleDropDownApp: .application
        case .commandWheel: .suggested
        default: .window
        }
    }

    private static func detail(
        for action: ConfigurableHotKeyAction,
        context: RadialCommandContext
    ) -> String {
        switch section(for: action) {
        case .workspace: "\(context.workspaceName) · \(context.displayName)"
        case .layout: "\(context.layout.title) · \(context.workspaceName)"
        case .window: "Focused window · \(context.workspaceName)"
        case .application: "WindowRanger"
        case .profiles: "Profile"
        case .suggested: "Command"
        }
    }

    private static func systemImage(for action: ConfigurableHotKeyAction) -> String {
        switch action {
        case .previousWorkspace: "arrow.left"
        case .nextWorkspace: "arrow.right"
        case .backAndForthWorkspace: "arrow.left.arrow.right"
        case .previousWindow: "chevron.left"
        case .nextWindow: "chevron.right"
        case .selectAccordion: WorkspaceLayout.accordion.systemImage
        case .selectTiled: WorkspaceLayout.tiled.systemImage
        case .toggleFloating: "macwindow"
        case .toggleDropDownApp: "rectangle.bottomthird.inset.filled"
        case .focusLeft: "arrow.left.to.line"
        case .focusDown: "arrow.down.to.line"
        case .focusUp: "arrow.up.to.line"
        case .focusRight: "arrow.right.to.line"
        case .moveLeft: "arrow.left"
        case .moveDown: "arrow.down"
        case .moveUp: "arrow.up"
        case .moveRight: "arrow.right"
        case .resizeSmaller: "minus.magnifyingglass"
        case .resizeLarger: "plus.magnifyingglass"
        case .moveWorkspaceToNextDisplay: "rectangle.on.rectangle"
        case .commandWheel: "circle.hexagongrid"
        }
    }

    private static func searchTerms(for action: ConfigurableHotKeyAction) -> [String] {
        switch action {
        case .toggleDropDownApp: ["quick app", "dropdown", "quake"]
        case .previousWindow, .nextWindow: ["cycle", "focus"]
        case .focusLeft, .focusDown, .focusUp, .focusRight: ["navigate", "direction"]
        case .moveLeft, .moveDown, .moveUp, .moveRight: ["reorder", "position"]
        case .resizeSmaller, .resizeLarger: ["size", "layout"]
        case .moveWorkspaceToNextDisplay: ["monitor", "screen"]
        default: [action.rawValue]
        }
    }
}

enum CommandPalettePlacementNavigation {
    static func placement(for item: RadialMenuItem) -> VisualPlacement? {
        item.placementPreview?.placement ?? item.freeformPlacementPreview?.placement
    }

    static func initialPlacement(
        in actions: [RadialMenuItem],
        preferred: VisualPlacement = .right
    ) -> VisualPlacement? {
        let placements = actions.compactMap(placement(for:))
        return placements.contains(preferred) ? preferred : placements.first
    }

    static func moved(
        from current: VisualPlacement?,
        offset: Int,
        in actions: [RadialMenuItem]
    ) -> VisualPlacement? {
        let placements = actions.compactMap(placement(for:))
        guard !placements.isEmpty else { return nil }
        guard let current,
              let index = placements.firstIndex(of: current)
        else {
            return offset >= 0 ? placements.first : placements.last
        }
        let next = (index + offset % placements.count + placements.count) % placements.count
        return placements[next]
    }

    static func item(
        for placement: VisualPlacement?,
        in actions: [RadialMenuItem]
    ) -> RadialMenuItem? {
        guard let placement else { return nil }
        return actions.first { self.placement(for: $0) == placement }
    }
}

enum CommandPaletteQuickAction: Equatable, Sendable {
    case workspaceLayout
    case placement
}

enum CommandPaletteQuickActionNavigation {
    static func availableActions(
        supportsLayoutSelection: Bool,
        supportsPlacement: Bool,
        isSearchEmpty: Bool = true
    ) -> [CommandPaletteQuickAction] {
        guard isSearchEmpty else { return [] }
        var actions: [CommandPaletteQuickAction] = []
        if supportsLayoutSelection {
            actions.append(.workspaceLayout)
        }
        if supportsPlacement {
            actions.append(.placement)
        }
        return actions
    }

    static func actionEnteringFromTopResult(
        selectedIndex: Int,
        resultCount: Int,
        actions: [CommandPaletteQuickAction]
    ) -> CommandPaletteQuickAction? {
        guard selectedIndex == 0, resultCount > 0 else { return nil }
        return actions.last
    }

    static func moved(
        from current: CommandPaletteQuickAction,
        offset: Int,
        in actions: [CommandPaletteQuickAction]
    ) -> CommandPaletteQuickAction? {
        guard let currentIndex = actions.firstIndex(of: current) else {
            return offset >= 0 ? actions.first : actions.last
        }
        let nextIndex = currentIndex + offset
        guard actions.indices.contains(nextIndex) else { return nil }
        return actions[nextIndex]
    }
}

enum CommandPaletteLayoutNavigation {
    static func moved(
        from current: WorkspaceLayout,
        offset: Int
    ) -> WorkspaceLayout {
        current.cycled(by: offset)
    }
}

enum CommandPaletteSelectionRevalidation {
    static func destination(
        _ requested: CommandPaletteDestination,
        original: RadialCommandContext,
        current: RadialCommandContext,
        hotKeyConfiguration: HotKeyConfiguration,
        isPauseModeEnabled: Bool = false,
        allowsInlineLayoutRefresh: Bool
    ) -> CommandPaletteDestination? {
        if current.sessionValidationToken == original.sessionValidationToken {
            if CommandPaletteIndex.contains(
                requested,
                context: current,
                hotKeyConfiguration: hotKeyConfiguration,
                isPauseModeEnabled: isPauseModeEnabled
            ) {
                return requested
            }
        }
        guard allowsInlineLayoutRefresh,
              preservesInteractionTarget(from: original, to: current)
        else { return nil }

        let refreshed = switch requested {
        case let .command(.placeFreeformWindow(placement, _)):
            CommandPaletteDestination.command(
                .placeFreeformWindow(placement, validationToken: current.validationToken)
            )
        case let .command(.placeTiledWindow(placement, _)):
            CommandPaletteDestination.command(
                .placeTiledWindow(placement, validationToken: current.validationToken)
            )
        default:
            requested
        }
        return CommandPaletteIndex.contains(
            refreshed,
            context: current,
            hotKeyConfiguration: hotKeyConfiguration,
            isPauseModeEnabled: isPauseModeEnabled
        ) ? refreshed : nil
    }

    static func defersFocusRestoration(
        for destination: CommandPaletteDestination
    ) -> Bool {
        switch destination {
        case .command(.placeFreeformWindow), .command(.placeTiledWindow):
            true
        default:
            false
        }
    }

    static func preservesInteractionTarget(
        from original: RadialCommandContext,
        to current: RadialCommandContext
    ) -> Bool {
        guard original.workspaceID == current.workspaceID,
              original.layout == current.layout,
              original.displayIdentifier == current.displayIdentifier,
              original.displayMode == current.displayMode,
              Set(original.connectedDisplayIdentifiers) == Set(current.connectedDisplayIdentifiers),
              original.activeProfileID == current.activeProfileID,
              original.externalValidationToken == current.externalValidationToken
        else { return false }

        switch (original.focusedWindow, current.focusedWindow) {
        case (nil, nil):
            return true
        case let (original?, current?):
            return original.processIdentifier == current.processIdentifier &&
                original.windowIdentifier == current.windowIdentifier &&
                original.workspaceID == current.workspaceID &&
                original.layoutState == current.layoutState &&
                original.isAutomaticallyFloatingDialog == current.isAutomaticallyFloatingDialog &&
                original.isAppRuleExcluded == current.isAppRuleExcluded &&
                original.keepsOnAllWorkspaces == current.keepsOnAllWorkspaces
        default:
            return false
        }
    }
}

@MainActor
final class CommandPalettePresentationModel: ObservableObject {
    @Published private(set) var context: RadialCommandContext

    init(context: RadialCommandContext) {
        self.context = context
    }

    func update(context: RadialCommandContext) {
        self.context = context
    }
}

@MainActor
final class CommandPaletteController: NSObject, NSWindowDelegate {
    static let panelSize = CGSize(width: 620, height: 526)
    static let placementHaloHorizontalOverflow: CGFloat = 200
    static let placementHaloVerticalOverflow: CGFloat = 0
    static let expandedPanelSize = CGSize(
        width: panelSize.width + placementHaloHorizontalOverflow,
        height: panelSize.height + placementHaloVerticalOverflow
    )

    private let engine: WorkspaceEngine
    private let dispatcher: WindowManagerCommandDispatcher
    private let diagnostics: DiagnosticLogger
    private let contextEnricher: @MainActor (RadialCommandContext) -> RadialCommandContext
    private let hotKeyConfigurationProvider: () -> HotKeyConfiguration
    private let isPauseModeEnabledProvider: () -> Bool
    private let openSettings: () -> Void
    private var panel: CommandPalettePanel?
    private var presentationModel: CommandPalettePresentationModel?
    private var context: RadialCommandContext?
    private var pendingInlineLayout: (workspaceID: UUID, layout: WorkspaceLayout)?
    private var allowsInlineContextRefresh = false
    private var previousApplication: NSRunningApplication?
    private var requestGeneration: UInt64 = 0
    private var isClosing = false

    init(
        engine: WorkspaceEngine,
        dispatcher: WindowManagerCommandDispatcher,
        diagnostics: DiagnosticLogger = .disabled,
        contextEnricher: @escaping @MainActor (RadialCommandContext) -> RadialCommandContext = { $0 },
        hotKeyConfigurationProvider: @escaping () -> HotKeyConfiguration,
        isPauseModeEnabledProvider: @escaping () -> Bool = { false },
        openSettings: @escaping () -> Void
    ) {
        self.engine = engine
        self.dispatcher = dispatcher
        self.diagnostics = diagnostics
        self.contextEnricher = contextEnricher
        self.hotKeyConfigurationProvider = hotKeyConfigurationProvider
        self.isPauseModeEnabledProvider = isPauseModeEnabledProvider
        self.openSettings = openSettings
        super.init()
    }

    var isPresented: Bool { panel?.isVisible == true }

    func toggle() {
        if isPresented {
            dismiss(reason: "trigger-toggled", restorePreviousApplication: true)
            return
        }
        requestGeneration &+= 1
        let generation = requestGeneration
        let priorApplication = NSWorkspace.shared.frontmostApplication
        engine.radialCommandContext { [weak self] context in
            guard let self, generation == self.requestGeneration else { return }
            let context = self.contextEnricher(context)
            guard !CommandPaletteIndex.entries(
                context: context,
                query: "",
                hotKeyConfiguration: self.hotKeyConfigurationProvider(),
                isPauseModeEnabled: self.isPauseModeEnabledProvider()
            ).isEmpty else { return }
            self.present(context, previousApplication: priorApplication)
        }
    }

    func dismiss(reason: String, restorePreviousApplication: Bool = false) {
        requestGeneration &+= 1
        guard panel != nil else { return }
        closePanel(reason: reason, restorePreviousApplication: restorePreviousApplication)
    }

    func contextDidPossiblyChange() {
        guard isPresented, let original = context else { return }
        engine.radialCommandContext { [weak self] current in
            guard let self, self.isPresented else { return }
            let current = self.contextEnricher(current)
            guard current.sessionValidationToken != original.sessionValidationToken else { return }
            if current.sessionValidationToken == self.context?.sessionValidationToken { return }
            if let pending = self.pendingInlineLayout,
               current.workspaceID == pending.workspaceID {
                if current.layout == pending.layout {
                    self.pendingInlineLayout = nil
                }
                self.context = current
                self.presentationModel?.update(context: current)
                self.diagnostics.log(
                    category: "command-palette",
                    event: "inline-layout-context-refreshed",
                    fields: [
                        "workspace": String(current.workspaceID.uuidString.prefix(6)),
                        "layout": current.layout.rawValue,
                    ]
                )
                return
            }
            if self.allowsInlineContextRefresh,
               CommandPaletteSelectionRevalidation.preservesInteractionTarget(
                   from: original,
                   to: current
               ) {
                self.context = current
                self.presentationModel?.update(context: current)
                self.diagnostics.log(
                    category: "command-palette",
                    event: "inline-layout-context-refreshed",
                    fields: [
                        "workspace": String(current.workspaceID.uuidString.prefix(6)),
                        "layout": current.layout.rawValue,
                        "phase": "settled",
                    ]
                )
                return
            }
            self.dismiss(reason: "context-changed")
        }
    }

    func shutdown() {
        dismiss(reason: "application-terminating")
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !isClosing else { return }
        dismiss(reason: "resigned-key")
    }

    private func present(
        _ context: RadialCommandContext,
        previousApplication: NSRunningApplication?
    ) {
        closePanel(reason: "replaced", restorePreviousApplication: false)
        let configuration = hotKeyConfigurationProvider()
        let panel = CommandPalettePanel(
            contentRect: CGRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.level = .floating
        panel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.setAccessibilitySubrole(.dialog)
        let presentationModel = CommandPalettePresentationModel(context: context)
        let isPauseModeEnabled = isPauseModeEnabledProvider()
        panel.contentView = NSHostingView(rootView: CommandPaletteView(
            presentationModel: presentationModel,
            hotKeyConfiguration: configuration,
            isPauseModeEnabled: isPauseModeEnabled,
            choose: { [weak self] destination in self?.activate(destination) },
            changeLayout: { [weak self] layout in self?.changeLayout(layout) },
            placementHaloPresentationChanged: { [weak self] isPresented in
                self?.setPlacementHaloPresented(isPresented)
            },
            dismiss: { [weak self] in
                self?.dismiss(reason: "escape", restorePreviousApplication: true)
            }
        ))

        let screen = screen(for: context.displayIdentifier) ?? NSScreen.main
        if let visibleFrame = screen?.visibleFrame {
            panel.setFrameOrigin(CGPoint(
                x: visibleFrame.midX - Self.panelSize.width / 2,
                y: visibleFrame.maxY - Self.panelSize.height - 84
            ))
        } else {
            panel.center()
        }

        self.context = context
        self.presentationModel = presentationModel
        self.previousApplication = previousApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            ? nil
            : previousApplication
        self.panel = panel
        engine.commandPalettePresentationChanged(true)
        diagnostics.log(
            category: "command-palette",
            event: "opened",
            fields: [
                "workspace": String(context.workspaceID.uuidString.prefix(6)),
                "display": String(context.displayIdentifier.prefix(6)),
                "layout": context.layout.rawValue,
                "focus-source": context.focusSource.rawValue,
                "spatial-placement-actions": String(
                    CommandPaletteIndex.spatialPlacementActions(in: context).count
                ),
                "tiled-placement-actions": String(context.tiledPlacementPreviews.count),
                "freeform-placement-actions": String(context.freeformPlacementPreviews.count),
            ]
        )
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func activate(_ destination: CommandPaletteDestination) {
        guard let original = context else { return }
        let destinationName = switch destination {
        case .settings: "settings"
        case .command: "command"
        }
        diagnostics.log(
            category: "command-palette",
            event: "selection-requested",
            fields: ["destination": destinationName]
        )
        let allowsInlineLayoutRefresh = allowsInlineContextRefresh
        let defersFocusRestoration = CommandPaletteSelectionRevalidation.defersFocusRestoration(
            for: destination
        )
        let fallbackProcessIdentifier = previousApplication?.processIdentifier
        if defersFocusRestoration {
            validateAndDispatch(
                destination,
                original: original,
                allowsInlineLayoutRefresh: allowsInlineLayoutRefresh,
                dismissAfterDispatch: true,
                completion: { [weak self] in
                    self?.engine.restoreFocusAfterCommandPalette(
                        fallbackProcessIdentifier: fallbackProcessIdentifier
                    )
                }
            )
            return
        }
        closePanel(
            reason: "selection",
            restorePreviousApplication: true
        )
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch destination {
            case .settings:
                self.openSettings()
            case .command:
                self.validateAndDispatch(
                    destination,
                    original: original,
                    allowsInlineLayoutRefresh: allowsInlineLayoutRefresh
                )
            }
        }
    }

    private func changeLayout(_ layout: WorkspaceLayout) {
        guard isPresented,
              let original = context,
              original.layout != layout,
              original.supportedCommands.contains(.setLayout)
        else { return }
        engine.radialCommandContext { [weak self] current in
            guard let self, self.isPresented else { return }
            let current = self.contextEnricher(current)
            guard current.workspaceID == original.workspaceID,
                  current.supportedCommands.contains(.setLayout)
            else {
                self.dismiss(reason: "inline-layout-context-changed")
                return
            }
            let correlationID = self.diagnostics.makeCorrelationID()
            self.pendingInlineLayout = (current.workspaceID, layout)
            self.diagnostics.log(
                category: "command-palette",
                event: "inline-layout-requested",
                correlation: correlationID,
                fields: [
                    "workspace": String(current.workspaceID.uuidString.prefix(6)),
                    "previous-layout": current.layout.rawValue,
                    "requested-layout": layout.rawValue,
                ]
            )
            let result = self.dispatcher.dispatch(
                .setLayout(layout),
                source: .commandPalette,
                correlationID: correlationID
            )
            if result == .rejectedReentrant {
                self.pendingInlineLayout = nil
                self.presentationModel?.update(context: current)
            } else {
                self.allowsInlineContextRefresh = true
            }
        }
    }

    private func validateAndDispatch(
        _ destination: CommandPaletteDestination,
        original: RadialCommandContext,
        allowsInlineLayoutRefresh: Bool = false,
        dismissAfterDispatch: Bool = false,
        completion: @escaping () -> Void = {}
    ) {
        engine.radialCommandContext { [weak self] current in
            guard let self else { return }
            defer {
                if dismissAfterDispatch {
                    self.closePanel(reason: "selection", restorePreviousApplication: false)
                }
                completion()
            }
            let current = self.contextEnricher(current)
            guard let validatedDestination = CommandPaletteSelectionRevalidation.destination(
                      destination,
                      original: original,
                      current: current,
                      hotKeyConfiguration: self.hotKeyConfigurationProvider(),
                      isPauseModeEnabled: self.isPauseModeEnabledProvider(),
                      allowsInlineLayoutRefresh: allowsInlineLayoutRefresh
                  ),
                  case let .command(command) = validatedDestination
            else {
                self.diagnostics.log(
                    category: "command-palette",
                    event: "selection-rejected",
                    fields: ["reason": "stale-context"]
                )
                return
            }
            if current.sessionValidationToken != original.sessionValidationToken {
                self.diagnostics.log(
                    category: "command-palette",
                    event: "selection-revalidated",
                    fields: ["reason": "accepted-inline-layout-refresh"]
                )
            }
            let correlationID = self.diagnostics.makeCorrelationID()
            self.diagnostics.log(
                category: "command-palette",
                event: "selection-committed",
                correlation: correlationID,
                fields: command.diagnosticFields
            )
            self.dispatcher.dispatch(command, source: .commandPalette, correlationID: correlationID)
        }
    }

    private func closePanel(reason: String, restorePreviousApplication: Bool) {
        guard let panel else { return }
        isClosing = true
        panel.orderOut(nil)
        panel.delegate = nil
        self.panel = nil
        presentationModel = nil
        context = nil
        pendingInlineLayout = nil
        allowsInlineContextRefresh = false
        let application = previousApplication
        previousApplication = nil
        engine.commandPalettePresentationChanged(false)
        isClosing = false
        diagnostics.log(
            category: "command-palette",
            event: "dismissed",
            fields: ["reason": reason]
        )
        if restorePreviousApplication {
            engine.restoreFocusAfterCommandPalette(
                fallbackProcessIdentifier: application?.processIdentifier
            )
        }
    }

    private func setPlacementHaloPresented(_ isPresented: Bool) {
        guard let panel else { return }
        let targetSize = isPresented ? Self.expandedPanelSize : Self.panelSize
        if isPresented {
            panel.hasShadow = false
        }
        if panel.frame.size != targetSize {
            panel.setFrame(
                CGRect(origin: panel.frame.origin, size: targetSize),
                display: true,
                animate: false
            )
        }
        if !isPresented {
            panel.hasShadow = true
        }
        panel.invalidateShadow()
        diagnostics.log(
            category: "command-palette",
            event: isPresented ? "placement-halo-opened" : "placement-halo-closed",
            fields: ["placement-actions": String(context.map {
                CommandPaletteIndex.spatialPlacementActions(in: $0).count
            } ?? 0)]
        )
    }

    private func screen(for displayIdentifier: String) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber,
            let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
            else { return false }
            return (CFUUIDCreateString(nil, uuid) as String) == displayIdentifier
        }
    }
}

private final class CommandPalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct CommandPaletteView: View {
    @ObservedObject private var presentationModel: CommandPalettePresentationModel
    let hotKeyConfiguration: HotKeyConfiguration
    let isPauseModeEnabled: Bool
    let choose: (CommandPaletteDestination) -> Void
    let changeLayout: (WorkspaceLayout) -> Void
    let placementHaloPresentationChanged: (Bool) -> Void
    let dismiss: () -> Void

    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var selectedLayout: WorkspaceLayout
    @State private var keyboardFocusedQuickAction: CommandPaletteQuickAction? = nil
    @State private var isPlacementHaloPresented: Bool
    @State private var selectedPlacement: VisualPlacement?
    @State private var isPlacementHaloKeyboardFocused = false
    private let focusesSearchOnAppear: Bool
    @FocusState private var searchFocused: Bool

    init(
        context: RadialCommandContext,
        hotKeyConfiguration: HotKeyConfiguration,
        isPauseModeEnabled: Bool = false,
        initiallyShowsPlacementHalo: Bool = false,
        initialPlacementHaloSelection: VisualPlacement? = nil,
        initiallyKeyboardFocusesPlacementHalo: Bool = false,
        focusesSearchOnAppear: Bool = true,
        choose: @escaping (CommandPaletteDestination) -> Void,
        changeLayout: @escaping (WorkspaceLayout) -> Void = { _ in },
        placementHaloPresentationChanged: @escaping (Bool) -> Void,
        dismiss: @escaping () -> Void
    ) {
        self.init(
            presentationModel: CommandPalettePresentationModel(context: context),
            hotKeyConfiguration: hotKeyConfiguration,
            isPauseModeEnabled: isPauseModeEnabled,
            initiallyShowsPlacementHalo: initiallyShowsPlacementHalo,
            initialPlacementHaloSelection: initialPlacementHaloSelection,
            initiallyKeyboardFocusesPlacementHalo: initiallyKeyboardFocusesPlacementHalo,
            focusesSearchOnAppear: focusesSearchOnAppear,
            choose: choose,
            changeLayout: changeLayout,
            placementHaloPresentationChanged: placementHaloPresentationChanged,
            dismiss: dismiss
        )
    }

    init(
        presentationModel: CommandPalettePresentationModel,
        hotKeyConfiguration: HotKeyConfiguration,
        isPauseModeEnabled: Bool = false,
        initiallyShowsPlacementHalo: Bool = false,
        initialPlacementHaloSelection: VisualPlacement? = nil,
        initiallyKeyboardFocusesPlacementHalo: Bool = false,
        focusesSearchOnAppear: Bool = true,
        choose: @escaping (CommandPaletteDestination) -> Void,
        changeLayout: @escaping (WorkspaceLayout) -> Void = { _ in },
        placementHaloPresentationChanged: @escaping (Bool) -> Void,
        dismiss: @escaping () -> Void
    ) {
        _presentationModel = ObservedObject(wrappedValue: presentationModel)
        self.hotKeyConfiguration = hotKeyConfiguration
        self.isPauseModeEnabled = isPauseModeEnabled
        self.choose = choose
        self.changeLayout = changeLayout
        self.placementHaloPresentationChanged = placementHaloPresentationChanged
        self.dismiss = dismiss
        _selectedLayout = State(initialValue: presentationModel.context.layout)
        _isPlacementHaloPresented = State(initialValue: initiallyShowsPlacementHalo)
        _selectedPlacement = State(initialValue: initialPlacementHaloSelection)
        _isPlacementHaloKeyboardFocused = State(
            initialValue: initiallyShowsPlacementHalo && initiallyKeyboardFocusesPlacementHalo
        )
        self.focusesSearchOnAppear = focusesSearchOnAppear
    }

    private var context: RadialCommandContext { presentationModel.context }

    private var entries: [CommandPaletteEntry] {
        CommandPaletteIndex.entries(
            context: context,
            query: query,
            hotKeyConfiguration: hotKeyConfiguration,
            isPauseModeEnabled: isPauseModeEnabled
        )
    }

    private var placementActions: [RadialMenuItem] {
        CommandPaletteIndex.spatialPlacementActions(in: context)
    }

    private var availableQuickActions: [CommandPaletteQuickAction] {
        CommandPaletteQuickActionNavigation.availableActions(
            supportsLayoutSelection: !isPauseModeEnabled && context.supportedCommands.contains(.setLayout),
            supportsPlacement: !isPauseModeEnabled && !placementActions.isEmpty,
            isSearchEmpty: query.isEmpty
        )
    }

    private var canvasSize: CGSize {
        isPlacementHaloPresented
            ? CommandPaletteController.expandedPanelSize
            : CommandPaletteController.panelSize
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            paletteSurface
            if isPlacementHaloPresented {
                CommandPalettePlacementHaloView(
                    actions: placementActions,
                    selectedPlacement: $selectedPlacement,
                    isKeyboardFocused: isPlacementHaloKeyboardFocused,
                    choose: { item in
                        guard let command = item.command else { return }
                        choose(.command(command))
                    },
                    collapse: { setPlacementHaloPresented(false) }
                )
                .frame(
                    width: CommandPalettePlacementHaloView.diameter,
                    height: CommandPalettePlacementHaloView.diameter
                )
                .position(
                    x: CommandPaletteController.panelSize.width + 25,
                    y: canvasSize.height - CommandPaletteController.panelSize.height
                        + placementHaloAnchorYOffset
                )
                .transition(.scale(scale: 0.92).combined(with: .opacity))
                .zIndex(2)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .bottomLeading)
        .animation(.easeOut(duration: 0.12), value: isPlacementHaloPresented)
        .task {
            guard focusesSearchOnAppear else { return }
            await Task.yield()
            searchFocused = true
        }
        .onChange(of: query) {
            selectedIndex = 0
            keyboardFocusedQuickAction = nil
            if !query.isEmpty, isPlacementHaloPresented {
                setPlacementHaloPresented(false)
            }
        }
        .onChange(of: context.layout) {
            selectedLayout = context.layout
        }
        .onChange(of: placementActions.isEmpty) {
            revalidateQuickActionFocus()
        }
        .onChange(of: entries.count) {
            selectedIndex = min(selectedIndex, max(entries.count - 1, 0))
        }
        .onKeyPress(.downArrow) {
            if isPlacementHaloKeyboardFocused {
                movePlacementSelection(1)
                return .handled
            }
            if keyboardFocusedQuickAction != nil {
                moveQuickActionFocus(1)
                return .handled
            }
            guard !entries.isEmpty else { return .handled }
            selectedIndex = min(selectedIndex + 1, entries.count - 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            if isPlacementHaloKeyboardFocused {
                movePlacementSelection(-1)
                return .handled
            }
            if keyboardFocusedQuickAction != nil {
                moveQuickActionFocus(-1)
                return .handled
            }
            guard !entries.isEmpty else { return .handled }
            if let quickAction = CommandPaletteQuickActionNavigation.actionEnteringFromTopResult(
                selectedIndex: selectedIndex,
                resultCount: entries.count,
                actions: availableQuickActions
            ) {
                enterQuickActions(at: quickAction)
                return .handled
            }
            selectedIndex = max(selectedIndex - 1, 0)
            return .handled
        }
        .onKeyPress(.escape) {
            if isPlacementHaloPresented {
                setPlacementHaloPresented(false)
            } else if keyboardFocusedQuickAction != nil {
                leaveQuickActions()
            } else {
                dismiss()
            }
            return .handled
        }
        .onKeyPress(.leftArrow) {
            if isPlacementHaloKeyboardFocused {
                movePlacementSelection(-1)
                return .handled
            }
            if let keyboardFocusedQuickAction {
                if keyboardFocusedQuickAction == .workspaceLayout {
                    moveLayoutSelection(-1)
                }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.rightArrow) {
            if isPlacementHaloKeyboardFocused {
                movePlacementSelection(1)
                return .handled
            }
            if let keyboardFocusedQuickAction {
                if keyboardFocusedQuickAction == .workspaceLayout {
                    moveLayoutSelection(1)
                }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.tab, phases: .down) { press in
            guard !isPlacementHaloKeyboardFocused else { return .handled }
            cycleQuickActionFocus(press.modifiers.contains(.shift) ? -1 : 1)
            return .handled
        }
    }

    private var paletteSurface: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Type a WindowRanger command", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18))
                    .focused($searchFocused)
                    .onSubmit { activateSelection() }
            }
            .padding(.horizontal, 18)
            .frame(height: 58)

            Divider().opacity(0.45)

            if !availableQuickActions.isEmpty {
                quickActionsSurface
                Divider().opacity(0.35)
            }

            if entries.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                if shouldShowHeader(at: index) {
                                    Text(entry.section.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .textCase(.uppercase)
                                        .padding(.horizontal, 12)
                                        .padding(.top, index == 0 ? 10 : 16)
                                        .padding(.bottom, 4)
                                }
                                Button { choose(entry.destination) } label: {
                                    HStack(spacing: 12) {
                                        RadialMenuSymbol(
                                            systemImage: entry.systemImage,
                                            size: 16,
                                            weight: .semibold
                                        )
                                        .frame(width: 22)
                                        .foregroundStyle(
                                            isCommandListKeyboardFocused && index == selectedIndex
                                                ? .primary
                                                : .secondary
                                        )
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(entry.title).lineLimit(1)
                                            Text(entry.detail)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        if let shortcut = entry.shortcut {
                                            Text(shortcut)
                                                .font(.caption.weight(.medium).monospaced())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .frame(height: 44)
                                    .background(
                                        isCommandListKeyboardFocused && index == selectedIndex
                                            ? Color.accentColor.opacity(0.2)
                                            : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .focusable(false)
                                .id(entry.id)
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: selectedIndex) {
                        guard entries.indices.contains(selectedIndex) else { return }
                        proxy.scrollTo(entries[selectedIndex].id, anchor: .center)
                    }
                }
            }
        }
        .frame(width: CommandPaletteController.panelSize.width, height: CommandPaletteController.panelSize.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
    }

    private var quickActionsSurface: some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Text("Quick actions")
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                Text("·")
                Text(context.workspaceName)
                Text("·")
                Text(context.displayName)
                Spacer(minLength: 8)
                Text(keyboardHint)
                    .font(.caption2.monospaced())
                    .lineLimit(1)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(height: 18)

            if availableQuickActions.contains(.workspaceLayout) {
                workspaceLayoutQuickAction
            }
            if availableQuickActions.contains(.placement) {
                placementQuickAction
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick actions")
    }

    private var workspaceLayoutQuickAction: some View {
        HStack(spacing: 10) {
            Label("Workspace layout", systemImage: "rectangle.3.group")
                .font(.caption.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 8)
            Picker(
                "Workspace layout",
                selection: Binding(
                    get: { selectedLayout },
                    set: { selectLayout($0) }
                )
            ) {
                ForEach(WorkspaceLayout.allCases) { layout in
                    Label(layout.title, systemImage: layout.systemImage)
                        .tag(layout)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .focusable(false)
            .frame(width: 350)
            .accessibilityLabel("Current workspace layout")
            .accessibilityHint("Choose Freeform, Tiled, or Accordion")
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(
            keyboardFocusedQuickAction == .workspaceLayout
                ? Color.accentColor.opacity(0.11)
                : Color.primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    keyboardFocusedQuickAction == .workspaceLayout
                        ? Color.accentColor.opacity(0.9)
                        : Color.primary.opacity(0.08),
                    lineWidth: keyboardFocusedQuickAction == .workspaceLayout ? 2 : 1
                )
        }
    }

    private var placementQuickAction: some View {
        Button {
            keyboardFocusedQuickAction = nil
            setPlacementHaloPresented(!isPlacementHaloPresented)
        } label: {
            HStack(spacing: 10) {
                RadialMenuSymbol(
                    systemImage: RadialCommandCatalogue.SymbolName.placeWindow,
                    size: 15,
                    weight: .semibold
                )
                .frame(width: 18, height: 18)
                Text("Place focused window")
                    .font(.caption.weight(.medium))
                Spacer()
                Image(systemName: "return")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .contentShape(Rectangle())
            .background(
                keyboardFocusedQuickAction == .placement
                    ? Color.accentColor.opacity(0.11)
                    : Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        keyboardFocusedQuickAction == .placement
                            ? Color.accentColor.opacity(0.9)
                            : Color.primary.opacity(0.08),
                        lineWidth: keyboardFocusedQuickAction == .placement ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("Show window placements")
        .accessibilityLabel(isPlacementHaloPresented
            ? "Hide window placements"
            : "Place focused window")
        .accessibilityHint("Opens the available placements for the focused window")
    }

    private func setPlacementHaloPresented(
        _ isPresented: Bool,
        keyboardFocused: Bool = false
    ) {
        guard !isPresented || !placementActions.isEmpty else { return }
        if isPlacementHaloPresented != isPresented {
            placementHaloPresentationChanged(isPresented)
        }
        isPlacementHaloPresented = isPresented
        isPlacementHaloKeyboardFocused = isPresented && keyboardFocused
        if !isPresented {
            selectedPlacement = nil
        }
        searchFocused = true
    }

    private func enterPlacementHaloFromKeyboard() {
        keyboardFocusedQuickAction = nil
        selectedPlacement = CommandPalettePlacementNavigation.initialPlacement(in: placementActions)
        setPlacementHaloPresented(true, keyboardFocused: true)
    }

    private func enterQuickActions(fromEnd: Bool = false) {
        guard !availableQuickActions.isEmpty else { return }
        if isPlacementHaloPresented {
            setPlacementHaloPresented(false)
        }
        selectedLayout = context.layout
        keyboardFocusedQuickAction = fromEnd
            ? availableQuickActions.last
            : availableQuickActions.first
        searchFocused = true
    }

    private func enterQuickActions(at action: CommandPaletteQuickAction) {
        guard availableQuickActions.contains(action) else { return }
        if isPlacementHaloPresented {
            setPlacementHaloPresented(false)
        }
        selectedLayout = context.layout
        keyboardFocusedQuickAction = action
        searchFocused = true
    }

    private func leaveQuickActions() {
        keyboardFocusedQuickAction = nil
        selectedIndex = 0
        searchFocused = true
    }

    private func cycleQuickActionFocus(_ offset: Int) {
        guard !availableQuickActions.isEmpty else { return }
        guard let keyboardFocusedQuickAction else {
            enterQuickActions(fromEnd: offset < 0)
            return
        }
        if let next = CommandPaletteQuickActionNavigation.moved(
            from: keyboardFocusedQuickAction,
            offset: offset,
            in: availableQuickActions
        ) {
            self.keyboardFocusedQuickAction = next
        } else {
            leaveQuickActions()
        }
    }

    private func moveQuickActionFocus(_ offset: Int) {
        guard let keyboardFocusedQuickAction else { return }
        if let next = CommandPaletteQuickActionNavigation.moved(
            from: keyboardFocusedQuickAction,
            offset: offset,
            in: availableQuickActions
        ) {
            self.keyboardFocusedQuickAction = next
        } else if offset > 0 {
            leaveQuickActions()
        }
    }

    private func revalidateQuickActionFocus() {
        if let keyboardFocusedQuickAction,
           !availableQuickActions.contains(keyboardFocusedQuickAction) {
            self.keyboardFocusedQuickAction = availableQuickActions.first
        }
        if placementActions.isEmpty, isPlacementHaloPresented {
            setPlacementHaloPresented(false)
        }
    }

    private func moveLayoutSelection(_ offset: Int) {
        selectLayout(CommandPaletteLayoutNavigation.moved(from: selectedLayout, offset: offset))
    }

    private func selectLayout(_ layout: WorkspaceLayout) {
        guard selectedLayout != layout else { return }
        if isPlacementHaloPresented {
            setPlacementHaloPresented(false)
        }
        selectedLayout = layout
        changeLayout(layout)
    }

    private func movePlacementSelection(_ offset: Int) {
        selectedPlacement = CommandPalettePlacementNavigation.moved(
            from: selectedPlacement,
            offset: offset,
            in: placementActions
        )
    }

    private func activateSelection() {
        if let keyboardFocusedQuickAction {
            switch keyboardFocusedQuickAction {
            case .workspaceLayout:
                leaveQuickActions()
            case .placement:
                enterPlacementHaloFromKeyboard()
            }
            return
        }
        if isPlacementHaloKeyboardFocused,
           let item = CommandPalettePlacementNavigation.item(
               for: selectedPlacement,
               in: placementActions
           ),
           let command = item.command {
            choose(.command(command))
            return
        }
        guard entries.indices.contains(selectedIndex) else { return }
        choose(entries[selectedIndex].destination)
    }

    private func shouldShowHeader(at index: Int) -> Bool {
        guard entries.indices.contains(index) else { return false }
        return index == 0 || entries[index - 1].section != entries[index].section
    }

    private var keyboardHint: String {
        if isPlacementHaloKeyboardFocused {
            return "←↑↓→ Move   ↩ Place   esc Back"
        }
        switch keyboardFocusedQuickAction {
        case .workspaceLayout:
            return "↑↓ Action   ←→ Change   ↩ Back   esc Back"
        case .placement:
            return "↑↓ Action   ↩ Open   esc Back"
        case nil:
            if selectedIndex == 0, !availableQuickActions.isEmpty {
                return "↑ Actions   ↓ Select   ↩ Run   esc Close"
            }
            return "↑↓ Select   ↩ Run   esc Close"
        }
    }

    private var isCommandListKeyboardFocused: Bool {
        keyboardFocusedQuickAction == nil && !isPlacementHaloKeyboardFocused
    }

    private var placementHaloAnchorYOffset: CGFloat {
        availableQuickActions.contains(.workspaceLayout) ? 151 : 111
    }
}

struct CommandPalettePlacementHaloView: View {
    static let diameter: CGFloat = 152

    let actions: [RadialMenuItem]
    @Binding var selectedPlacement: VisualPlacement?
    let isKeyboardFocused: Bool
    let choose: (RadialMenuItem) -> Void
    let collapse: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    init(
        actions: [RadialMenuItem],
        selectedPlacement: Binding<VisualPlacement?>,
        isKeyboardFocused: Bool,
        choose: @escaping (RadialMenuItem) -> Void,
        collapse: @escaping () -> Void
    ) {
        self.actions = actions
        _selectedPlacement = selectedPlacement
        self.isKeyboardFocused = isKeyboardFocused
        self.choose = choose
        self.collapse = collapse
    }

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Circle().stroke(
                            Color.primary.opacity(contrast == .increased ? 0.52 : 0.16),
                            lineWidth: contrast == .increased ? 2 : 1
                        )
                    }
                    .shadow(
                        color: .black.opacity(colorScheme == .dark ? 0.42 : 0.22),
                        radius: 18,
                        y: 8
                    )
                    .frame(width: 140, height: 140)

                ForEach(Array(actions.enumerated()), id: \.element.id) { index, item in
                    let placement = placement(for: item)
                    let isHovered = placement == selectedPlacement
                    let segment = CommandPalettePlacementSegmentShape(
                        index: index,
                        count: actions.count,
                        innerRadius: 31,
                        outerRadius: 69,
                        gapRadians: 0.012
                    )
                    segment
                        .fill(isHovered
                            ? Color.accentColor.opacity(0.72)
                            : Color.primary.opacity(0.035))
                        .overlay {
                            segment.stroke(
                                Color.primary.opacity(contrast == .increased ? 0.5 : 0.12),
                                lineWidth: contrast == .increased ? 2 : 1
                            )
                        }
                        .contentShape(segment)
                        .onTapGesture { choose(item) }
                        .onHover { hovering in
                            if hovering {
                                selectedPlacement = placement
                            } else if !isKeyboardFocused, selectedPlacement == placement {
                                selectedPlacement = nil
                            }
                        }
                        .help(placementLabel(for: item))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Place window \(placementLabel(for: item))")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { choose(item) }

                    let itemCenter = RadialMenuGeometry.itemCenter(
                        index: index,
                        count: actions.count,
                        center: center,
                        radius: 51
                    )
                    RadialMenuSymbol(systemImage: item.systemImage, size: 14, weight: .semibold)
                        .foregroundStyle(isHovered ? Color.white : Color.primary)
                        .frame(width: 24, height: 24)
                        .allowsHitTesting(false)
                        .position(itemCenter)
                }

                Button(action: collapse) {
                    RadialMenuSymbol(
                        systemImage: RadialCommandCatalogue.SymbolName.placeWindow,
                        size: 16,
                        weight: .semibold
                    )
                    .frame(width: 42, height: 42)
                    .background(.regularMaterial, in: Circle())
                    .overlay(Circle().stroke(Color.primary.opacity(0.18), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Hide window placements")
                .accessibilityLabel("Hide window placements")

                if let hoveredItem = actions.first(where: { placement(for: $0) == selectedPlacement }) {
                    Text(placementLabel(for: hoveredItem))
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.primary.opacity(0.14), lineWidth: 1)
                        }
                        .fixedSize()
                        .position(x: 190, y: 76)
                        .allowsHitTesting(false)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Window placements")
    }

    private func placement(for item: RadialMenuItem) -> VisualPlacement? {
        CommandPalettePlacementNavigation.placement(for: item)
    }

    private func placementLabel(for item: RadialMenuItem) -> String {
        guard item.freeformPlacementPreview != nil, let placement = placement(for: item) else {
            return item.label
        }
        return switch placement {
        case .top: "Top Half"
        case .left: "Left Half"
        case .right: "Right Half"
        case .bottom: "Bottom Half"
        default: placement.title
        }
    }
}

private struct CommandPalettePlacementSegmentShape: Shape {
    let index: Int
    let count: Int
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let gapRadians: CGFloat

    func path(in rect: CGRect) -> Path {
        guard count > 0 else { return Path() }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let span = CGFloat.pi * 2 / CGFloat(count)
        let middle = CGFloat(index) * span - .pi / 2
        let start = middle - span / 2 + gapRadians
        let end = middle + span / 2 - gapRadians
        var path = Path()
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: .radians(start),
            endAngle: .radians(end),
            clockwise: false
        )
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: .radians(end),
            endAngle: .radians(start),
            clockwise: true
        )
        path.closeSubpath()
        return path
    }
}
