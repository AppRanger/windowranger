import AppKit
import SwiftUI

struct MenuBarHighlightColor: Equatable, Sendable {
    static let `default` = MenuBarHighlightColor(red: 1, green: 1, blue: 1)

    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    init?(hex: String) {
        let normalized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard normalized.count == 6, let value = UInt32(normalized, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }

    @MainActor
    init?(nsColor: NSColor) {
        guard let color = nsColor.usingColorSpace(.sRGB) else { return nil }
        self.init(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent)
    }

    var hex: String {
        let redByte = UInt8((red * 255).rounded())
        let greenByte = UInt8((green * 255).rounded())
        let blueByte = UInt8((blue * 255).rounded())
        return String(format: "#%02X%02X%02X", redByte, greenByte, blueByte)
    }

    var color: Color { Color(red: red, green: green, blue: blue) }

    @MainActor
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }

    var usesDarkForeground: Bool {
        func linearized(_ component: Double) -> Double {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linearized(red)
            + 0.7152 * linearized(green)
            + 0.0722 * linearized(blue)
        return luminance > 0.45
    }

    var foregroundColor: Color { usesDarkForeground ? .black : .white }

    @MainActor
    var nsForegroundColor: NSColor { usesDarkForeground ? .black : .white }

    var contrastStrokeColor: Color {
        usesDarkForeground ? .black.opacity(0.28) : .white.opacity(0.30)
    }
}

enum MenuBarPresentationMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case compact
    case medium
    case full

    var id: String { rawValue }

    static func migrated(from storedValue: String?) -> MenuBarPresentationMode {
        switch storedValue {
        case MenuBarPresentationMode.compact.rawValue, "icon-only": .compact
        case MenuBarPresentationMode.medium.rawValue, "workspace-label": .medium
        case MenuBarPresentationMode.full.rawValue, "full-workspace-strip": .full
        default: .compact
        }
    }

    var title: String {
        switch self {
        case .compact: "Compact"
        case .medium: "Medium"
        case .full: "Full"
        }
    }

    var explanation: String {
        switch self {
        case .compact:
            "Shows a tiny active-workspace signal for every connected display. Every item opens the app menu."
        case .medium:
            "Shows one readable active-workspace chip per connected display. The chips are informational and open the app menu."
        case .full:
            "Shows display-grouped workspace actions. Only explicit workspace items switch; the remaining areas open the app menu."
        }
    }

    var primaryLabelDescriptor: MenuBarPrimaryLabelDescriptor {
        switch self {
        case .compact:
            MenuBarPrimaryLabelDescriptor(
                showsIcon: true,
                indicatorStyle: .compact,
                showsWorkspaceStrip: false
            )
        case .medium:
            MenuBarPrimaryLabelDescriptor(
                showsIcon: true,
                indicatorStyle: .medium,
                showsWorkspaceStrip: false
            )
        case .full:
            MenuBarPrimaryLabelDescriptor(
                showsIcon: true,
                indicatorStyle: .none,
                showsWorkspaceStrip: true
            )
        }
    }
}

enum MenuBarWorkspaceLabelMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case name
    case key

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: "Names"
        case .key: "Keys"
        }
    }
}

enum MenuBarPrimaryIndicatorStyle: Equatable, Sendable {
    case none
    case compact
    case medium
}

struct MenuBarPrimaryLabelDescriptor: Equatable, Sendable {
    let showsIcon: Bool
    let indicatorStyle: MenuBarPrimaryIndicatorStyle
    let showsWorkspaceStrip: Bool
}

enum MenuBarDisplayIconKind: String, Codable, Equatable, Sendable {
    case builtIn
    case external
    case combined

    var systemImage: String {
        switch self {
        case .builtIn: "laptopcomputer"
        case .external: "display"
        case .combined: "display.2"
        }
    }
}

extension MenuBarDisplayIconStyle {
    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .horizontalMonitor: "Horizontal Monitor"
        case .verticalMonitor: "Vertical Monitor"
        case .laptop: "Laptop"
        case .none: "None"
        }
    }

    var pickerSystemImage: String {
        switch self {
        case .automatic: "display.2"
        case .horizontalMonitor: "display"
        case .verticalMonitor: "rectangle.portrait"
        case .laptop: "laptopcomputer"
        case .none: "eye.slash"
        }
    }

    func systemImage(
        for kind: MenuBarDisplayIconKind,
        automaticSystemImage: String? = nil
    ) -> String? {
        switch self {
        case .automatic: automaticSystemImage ?? kind.systemImage
        case .horizontalMonitor: "display"
        case .verticalMonitor: "rectangle.portrait"
        case .laptop: "laptopcomputer"
        case .none: nil
        }
    }

    var reservedWidth: CGFloat {
        self == .none ? 0 : MenuBarVisualTokens.displayIconWidth
    }
}

struct MenuBarDisplayIconConfiguration: Equatable, Sendable {
    static let automatic = MenuBarDisplayIconConfiguration(stylesByDisplayIdentifier: [:])

    let stylesByDisplayIdentifier: [String: MenuBarDisplayIconStyle]

    func style(for display: MenuBarDisplayItem) -> MenuBarDisplayIconStyle {
        stylesByDisplayIdentifier[display.id] ?? .automatic
    }

    func systemImage(
        for display: MenuBarDisplayItem,
        automaticSystemImage: String? = nil
    ) -> String? {
        style(for: display).systemImage(
            for: display.iconKind,
            automaticSystemImage: automaticSystemImage
        )
    }

    func reservedWidth(for display: MenuBarDisplayItem) -> CGFloat {
        style(for: display).reservedWidth
    }
}

enum MenuBarProfileDisplayIconResolver {
    static func configuration(
        profile: WindowManagerProfile,
        roleBindings: [UUID: WorkspaceDisplayPin],
        displays: [DisplaySnapshot]
    ) -> MenuBarDisplayIconConfiguration {
        let resolved = profile.displayRoles.compactMap {
            role -> (String, MenuBarDisplayIconStyle)? in
            guard role.menuBarIconStyle != .automatic,
                  let pin = roleBindings[role.id],
                  let identifier = DisplayIdentityResolver.resolve(
                    pin,
                    among: displays
                  ).displayIdentifier
            else { return nil }
            return (identifier, role.menuBarIconStyle)
        }
        let resolvedByDisplay = Dictionary(grouping: resolved, by: \.0)
        let styles = resolvedByDisplay.reduce(into: [String: MenuBarDisplayIconStyle]()) {
            result,
            entry in
            // Two roles bound to one physical display are ambiguous. Do not let profile order
            // choose which cosmetic preference wins.
            guard entry.value.count == 1, let style = entry.value.first?.1 else { return }
            result[entry.key] = style
        }
        return MenuBarDisplayIconConfiguration(stylesByDisplayIdentifier: styles)
    }
}

struct MenuBarWorkspaceItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let compactName: String
    let key: String
    let isActive: Bool
    let isInteractionWorkspace: Bool

    func visibleLabel(mode: MenuBarWorkspaceLabelMode, compact: Bool = false) -> String {
        switch mode {
        case .name: compact ? compactName : name
        case .key: MenuBarWorkspaceLabelFormatter.key(key)
        }
    }

    var accessibilityLabel: String {
        var qualifiers: [String] = []
        if isActive { qualifiers.append("active") }
        if isInteractionWorkspace { qualifiers.append("interaction workspace") }
        return qualifiers.isEmpty
            ? "Workspace \(name)"
            : "Workspace \(name), \(qualifiers.joined(separator: ", "))"
    }
}

struct MenuBarDisplayItem: Identifiable, Equatable, Sendable {
    /// Runtime-only logical display identity. It is never persisted or exposed in diagnostics.
    let id: String
    let name: String
    let iconKind: MenuBarDisplayIconKind
    let isInteractionDisplay: Bool
    let activeWorkspaceID: UUID
    let activeWorkspaceName: String
    let activeWorkspaceCompactName: String
    let activeWorkspaceKey: String
    let workspaces: [MenuBarWorkspaceItem]

    func activeWorkspaceLabel(mode: MenuBarWorkspaceLabelMode, compact: Bool = false) -> String {
        switch mode {
        case .name: compact ? activeWorkspaceCompactName : activeWorkspaceName
        case .key: MenuBarWorkspaceLabelFormatter.key(activeWorkspaceKey)
        }
    }

    var accessibilityLabel: String {
        let interaction = isInteractionDisplay ? ", interaction display" : ""
        return "\(name)\(interaction), active workspace \(activeWorkspaceName)"
    }
}

struct MenuBarPresentationSnapshot: Equatable, Sendable {
    let mode: MenuBarPresentationMode
    let workspaceLabelMode: MenuBarWorkspaceLabelMode
    let displayMode: MultiDisplayMode
    let interactionWorkspaceID: UUID
    let displays: [MenuBarDisplayItem]

    var primaryAccessibilityLabel: String {
        let states = displays.map(\.accessibilityLabel).joined(separator: ". ")
        return "WindowRanger menu. \(states)."
    }

    var primaryTooltip: String {
        let states = displays.map { "\($0.name): \($0.activeWorkspaceName)" }
            .joined(separator: " · ")
        return "WindowRanger — \(states)"
    }

    func replacingMode(_ mode: MenuBarPresentationMode) -> MenuBarPresentationSnapshot {
        MenuBarPresentationSnapshot(
            mode: mode,
            workspaceLabelMode: workspaceLabelMode,
            displayMode: displayMode,
            interactionWorkspaceID: interactionWorkspaceID,
            displays: displays
        )
    }
}

enum MenuBarInteractionAction: Equatable, Sendable {
    case openMenu
    case switchWorkspace(workspaceID: UUID, displayIdentifier: String)
}

enum MenuBarHitTarget: Equatable, Sendable {
    case primary
    case displayIndicator(String)
    case workspace(workspaceID: UUID, displayIdentifier: String)
}

enum MenuBarInteractionRouter {
    static func action(for target: MenuBarHitTarget) -> MenuBarInteractionAction {
        switch target {
        case .primary, .displayIndicator:
            .openMenu
        case let .workspace(workspaceID, displayIdentifier):
            .switchWorkspace(
                workspaceID: workspaceID,
                displayIdentifier: displayIdentifier
            )
        }
    }
}

enum MenuBarWorkspaceLabelFormatter {
    static func compact(_ name: String, maximumCharacters: Int = 3) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "—" }
        guard trimmed.count > maximumCharacters else { return trimmed }
        let retained = max(1, maximumCharacters - 1)
        return String(trimmed.prefix(retained)) + "…"
    }

    static func key(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "—" : trimmed.uppercased()
    }
}

enum MenuBarCompactDisplayLayout: Equatable, Sendable {
    case keyInsideIcon
    case inlineLabel
}

struct MenuBarCompactDisplayPresentation: Equatable, Sendable {
    let layout: MenuBarCompactDisplayLayout
    let systemImage: String?
    let label: String

    static func resolve(
        display: MenuBarDisplayItem,
        workspaceLabelMode: MenuBarWorkspaceLabelMode,
        displayIconConfiguration: MenuBarDisplayIconConfiguration
    ) -> MenuBarCompactDisplayPresentation {
        let systemImage = displayIconConfiguration.systemImage(
            for: display,
            automaticSystemImage: display.iconKind == .combined ? "display.2" : "display"
        )
        let label: String
        switch workspaceLabelMode {
        case .name:
            label = MenuBarWorkspaceLabelFormatter.compact(
                display.activeWorkspaceName,
                maximumCharacters: 5
            )
        case .key:
            label = display.activeWorkspaceLabel(mode: .key)
        }
        return MenuBarCompactDisplayPresentation(
            layout: workspaceLabelMode == .key && systemImage != nil
                ? .keyInsideIcon
                : .inlineLabel,
            systemImage: systemImage,
            label: label
        )
    }
}

struct MenuBarCompactKeyOverlayMetrics: Equatable, Sendable {
    let iconPointSize: CGFloat
    let labelPointSize: CGFloat
    let labelWidth: CGFloat
    let labelOffsetX: CGFloat
    let labelOffsetY: CGFloat
    let componentWidth: CGFloat

    static func resolve(
        systemImage: String,
        labelCharacterCount: Int
    ) -> MenuBarCompactKeyOverlayMetrics {
        let isMultiCharacter = labelCharacterCount > 1

        switch systemImage {
        case "rectangle.portrait":
            return MenuBarCompactKeyOverlayMetrics(
                iconPointSize: 16.5,
                labelPointSize: isMultiCharacter ? 5.25 : 6.25,
                labelWidth: 6.5,
                labelOffsetX: 0,
                labelOffsetY: -0.5,
                componentWidth: 24
            )
        case "laptopcomputer":
            return MenuBarCompactKeyOverlayMetrics(
                iconPointSize: 17,
                labelPointSize: isMultiCharacter ? 5.75 : 7,
                labelWidth: 8,
                labelOffsetX: 0,
                labelOffsetY: -1.25,
                componentWidth: 24
            )
        case "display.2":
            return MenuBarCompactKeyOverlayMetrics(
                iconPointSize: 16,
                labelPointSize: isMultiCharacter ? 5.5 : 6.5,
                labelWidth: 7.5,
                labelOffsetX: 4,
                labelOffsetY: 0.5,
                componentWidth: 26
            )
        default:
            return MenuBarCompactKeyOverlayMetrics(
                iconPointSize: 16.5,
                labelPointSize: isMultiCharacter ? 6 : 7.5,
                labelWidth: 9,
                labelOffsetX: 0,
                labelOffsetY: -1.5,
                componentWidth: 24
            )
        }
    }
}

enum MenuBarPresentationResolver {
    static func resolve(
        mode: MenuBarPresentationMode,
        workspaceLabelMode: MenuBarWorkspaceLabelMode = .name,
        displayMode: MultiDisplayMode,
        state: WorkspaceEngineState,
        workspaces: [WorkspaceDefinition],
        connectedDisplays: [DisplaySnapshot],
        workspaceDisplayAssignments: [UUID: String]
    ) -> MenuBarPresentationSnapshot {
        let definitions = workspaces.isEmpty ? WorkspaceDefinition.defaults : workspaces
        let orderedDisplays = ordered(connectedDisplays)
        if displayMode == .unified {
            return unifiedSnapshot(
                mode: mode,
                workspaceLabelMode: workspaceLabelMode,
                state: state,
                workspaces: definitions
            )
        }

        let fallbackDisplayIdentifier = orderedDisplays.first(where: \.isMain)?.identifier
            ?? orderedDisplays.first?.identifier
            ?? "connected-display"
        let currentAssignedDisplay = workspaceDisplayAssignments[state.currentWorkspaceID]
        let interactionDisplayIdentifier = orderedDisplays.first(where: {
            state.activeWorkspaceIDByDisplay[$0.identifier] == state.currentWorkspaceID
        })?.identifier
            ?? currentAssignedDisplay.flatMap { assigned in
                orderedDisplays.contains(where: { $0.identifier == assigned }) ? assigned : nil
            }
            ?? fallbackDisplayIdentifier

        let effectiveDisplayForWorkspace: [UUID: String] = Dictionary(
            uniqueKeysWithValues: definitions.map { workspace in
                let assigned = workspaceDisplayAssignments[workspace.id]
                let connected = assigned.flatMap { candidate in
                    orderedDisplays.contains(where: { $0.identifier == candidate }) ? candidate : nil
                }
                return (workspace.id, connected ?? fallbackDisplayIdentifier)
            }
        )

        let displayItems: [MenuBarDisplayItem]
        if orderedDisplays.isEmpty {
            let activeID = definitions.contains(where: { $0.id == state.currentWorkspaceID })
                ? state.currentWorkspaceID : definitions[0].id
            displayItems = [makeDisplayItem(
                identifier: fallbackDisplayIdentifier,
                name: "Display",
                iconKind: .external,
                isInteraction: true,
                activeWorkspaceID: activeID,
                workspaceDefinitions: definitions,
                interactionWorkspaceID: state.currentWorkspaceID
            )]
        } else {
            displayItems = orderedDisplays.map { display in
                var assigned = definitions.filter {
                    effectiveDisplayForWorkspace[$0.id] == display.identifier
                }
                let mappedActive = state.activeWorkspaceIDByDisplay[display.identifier]
                let activeID = mappedActive
                    ?? (display.identifier == interactionDisplayIdentifier
                        ? state.currentWorkspaceID
                        : assigned.first(where: { state.activeWorkspaceIDs.contains($0.id) })?.id)
                    ?? assigned.first?.id
                    ?? state.currentWorkspaceID
                if let activeDefinition = definitions.first(where: { $0.id == activeID }),
                   !assigned.contains(where: { $0.id == activeID }) {
                    assigned.append(activeDefinition)
                }
                if assigned.isEmpty { assigned = [definitions[0]] }
                return makeDisplayItem(
                    identifier: display.identifier,
                    name: safeDisplayName(display.name, isBuiltIn: display.isBuiltIn),
                    iconKind: display.isBuiltIn ? .builtIn : .external,
                    isInteraction: display.identifier == interactionDisplayIdentifier,
                    activeWorkspaceID: activeID,
                    workspaceDefinitions: assigned,
                    interactionWorkspaceID: state.currentWorkspaceID
                )
            }
        }

        return MenuBarPresentationSnapshot(
            mode: mode,
            workspaceLabelMode: workspaceLabelMode,
            displayMode: .independent,
            interactionWorkspaceID: state.currentWorkspaceID,
            displays: displayItems
        )
    }

    static func preview(
        mode: MenuBarPresentationMode,
        workspaceLabelMode: MenuBarWorkspaceLabelMode = .name,
        displayMode: MultiDisplayMode,
        workspaces: [WorkspaceDefinition],
        connectedDisplays: [DisplaySnapshot],
        workspaceDisplayAssignments: [UUID: String]
    ) -> MenuBarPresentationSnapshot {
        let definitions = workspaces.isEmpty ? WorkspaceDefinition.defaults : workspaces
        let displays = connectedDisplays.isEmpty
            ? [
                DisplaySnapshot(
                    identifier: "preview-built-in",
                    bounds: CGRect(x: 0, y: 0, width: 1_512, height: 982),
                    isMain: true,
                    isBuiltIn: true,
                    name: "Built-in Display"
                ),
                DisplaySnapshot(
                    identifier: "preview-external",
                    bounds: CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080),
                    isMain: false,
                    name: "External Display"
                ),
            ]
            : connectedDisplays
        var assignments = workspaceDisplayAssignments
        if displayMode == .independent, connectedDisplays.isEmpty, definitions.count > 1 {
            for (index, workspace) in definitions.enumerated() {
                assignments[workspace.id] = index < max(1, definitions.count / 2)
                    ? "preview-built-in" : "preview-external"
            }
        }
        var activeByDisplay: [String: UUID] = [:]
        for display in ordered(displays) {
            let active = definitions.first(where: { assignments[$0.id] == display.identifier })?.id
            if let active { activeByDisplay[display.identifier] = active }
        }
        let interactionID = activeByDisplay[ordered(displays).last?.identifier ?? ""]
            ?? definitions[0].id
        return resolve(
            mode: mode,
            workspaceLabelMode: workspaceLabelMode,
            displayMode: displayMode,
            state: WorkspaceEngineState(
                currentWorkspaceID: interactionID,
                activeWorkspaceIDs: Set(activeByDisplay.values).union([interactionID]),
                previousWorkspaceID: nil,
                managedWindowCount: 0,
                accessibilityGranted: false,
                activeWorkspaceIDByDisplay: activeByDisplay
            ),
            workspaces: definitions,
            connectedDisplays: displays,
            workspaceDisplayAssignments: assignments
        )
    }

    private static func unifiedSnapshot(
        mode: MenuBarPresentationMode,
        workspaceLabelMode: MenuBarWorkspaceLabelMode,
        state: WorkspaceEngineState,
        workspaces: [WorkspaceDefinition]
    ) -> MenuBarPresentationSnapshot {
        let activeID = workspaces.contains(where: { $0.id == state.currentWorkspaceID })
            ? state.currentWorkspaceID : workspaces[0].id
        let display = makeDisplayItem(
            identifier: "combined-displays",
            name: "All Displays",
            iconKind: .combined,
            isInteraction: true,
            activeWorkspaceID: activeID,
            workspaceDefinitions: workspaces,
            interactionWorkspaceID: activeID
        )
        return MenuBarPresentationSnapshot(
            mode: mode,
            workspaceLabelMode: workspaceLabelMode,
            displayMode: .unified,
            interactionWorkspaceID: activeID,
            displays: [display]
        )
    }

    private static func makeDisplayItem(
        identifier: String,
        name: String,
        iconKind: MenuBarDisplayIconKind,
        isInteraction: Bool,
        activeWorkspaceID: UUID,
        workspaceDefinitions: [WorkspaceDefinition],
        interactionWorkspaceID: UUID
    ) -> MenuBarDisplayItem {
        let activeDefinition = workspaceDefinitions.first(where: { $0.id == activeWorkspaceID })
            ?? workspaceDefinitions[0]
        let items = workspaceDefinitions.map { workspace in
            MenuBarWorkspaceItem(
                id: workspace.id,
                name: workspace.name,
                compactName: MenuBarWorkspaceLabelFormatter.compact(workspace.name),
                key: workspace.key,
                isActive: workspace.id == activeDefinition.id,
                isInteractionWorkspace: isInteraction && workspace.id == interactionWorkspaceID
            )
        }
        return MenuBarDisplayItem(
            id: identifier,
            name: name,
            iconKind: iconKind,
            isInteractionDisplay: isInteraction,
            activeWorkspaceID: activeDefinition.id,
            activeWorkspaceName: activeDefinition.name,
            activeWorkspaceCompactName: MenuBarWorkspaceLabelFormatter.compact(activeDefinition.name),
            activeWorkspaceKey: activeDefinition.key,
            workspaces: items
        )
    }

    private static func ordered(_ displays: [DisplaySnapshot]) -> [DisplaySnapshot] {
        displays.sorted { lhs, rhs in
            if lhs.isMain != rhs.isMain { return lhs.isMain }
            if lhs.bounds.minX != rhs.bounds.minX { return lhs.bounds.minX < rhs.bounds.minX }
            if lhs.bounds.minY != rhs.bounds.minY { return lhs.bounds.minY < rhs.bounds.minY }
            if lhs.name != rhs.name { return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending }
            return lhs.identifier < rhs.identifier
        }
    }

    private static func safeDisplayName(_ name: String, isBuiltIn: Bool) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return isBuiltIn ? "Built-in Display" : "External Display"
    }
}

enum MenuBarFullStripLabelStyle: Equatable, Sendable {
    case full
    case compact
}

struct MenuBarFullStripDisplayGroup: Identifiable, Equatable, Sendable {
    let display: MenuBarDisplayItem
    let visibleWorkspaces: [MenuBarWorkspaceItem]
    let hiddenWorkspaces: [MenuBarWorkspaceItem]

    var id: String { display.id }
}

struct MenuBarFullStripLayout: Equatable, Sendable {
    let groups: [MenuBarFullStripDisplayGroup]
    let labelStyle: MenuBarFullStripLabelStyle
    let estimatedWidth: CGFloat

    var hiddenWorkspaceCount: Int {
        groups.reduce(0) { $0 + $1.hiddenWorkspaces.count }
    }

    var overflowSummary: String? {
        guard hiddenWorkspaceCount > 0 else { return nil }
        let names = groups.flatMap { group in
            group.hiddenWorkspaces.map { "\(group.display.name): \($0.name)" }
        }
        return "\(hiddenWorkspaceCount) more workspace\(hiddenWorkspaceCount == 1 ? "" : "s"): \(names.joined(separator: ", "))"
    }
}

enum MenuBarPressurePolicy {
    static let defaultAvailableWidth: CGFloat = 520

    static func layout(
        displays: [MenuBarDisplayItem],
        availableWidth: CGFloat,
        workspaceLabelMode: MenuBarWorkspaceLabelMode = .name,
        displayIconConfiguration: MenuBarDisplayIconConfiguration = .automatic
    ) -> MenuBarFullStripLayout {
        let budget = max(120, availableWidth)
        let fullGroups = displays.map {
            MenuBarFullStripDisplayGroup(
                display: $0,
                visibleWorkspaces: $0.workspaces,
                hiddenWorkspaces: []
            )
        }
        let fullWidth = estimatedWidth(
            groups: fullGroups,
            style: .full,
            hasOverflow: false,
            workspaceLabelMode: workspaceLabelMode,
            displayIconConfiguration: displayIconConfiguration
        )
        if fullWidth <= budget {
            return MenuBarFullStripLayout(
                groups: fullGroups,
                labelStyle: .full,
                estimatedWidth: fullWidth
            )
        }

        let compactWidth = estimatedWidth(
            groups: fullGroups,
            style: .compact,
            hasOverflow: false,
            workspaceLabelMode: workspaceLabelMode,
            displayIconConfiguration: displayIconConfiguration
        )
        if compactWidth <= budget {
            return MenuBarFullStripLayout(
                groups: fullGroups,
                labelStyle: .compact,
                estimatedWidth: compactWidth
            )
        }

        var visibleByDisplay = Dictionary(uniqueKeysWithValues: displays.map { display in
            let active = display.workspaces.filter(\.isActive)
            return (display.id, active.isEmpty ? Array(display.workspaces.prefix(1)) : active)
        })
        let optional = displays.flatMap { display in
            display.workspaces.filter { workspace in
                !(visibleByDisplay[display.id] ?? []).contains(where: { $0.id == workspace.id })
            }.map { (display.id, $0) }
        }
        for (displayID, workspace) in optional {
            var proposed = visibleByDisplay
            proposed[displayID, default: []].append(workspace)
            let proposedGroups = makeGroups(displays: displays, visibleByDisplay: proposed)
            if estimatedWidth(
                groups: proposedGroups,
                style: .compact,
                hasOverflow: true,
                workspaceLabelMode: workspaceLabelMode,
                displayIconConfiguration: displayIconConfiguration
            ) <= budget {
                visibleByDisplay = proposed
            }
        }
        let reducedGroups = makeGroups(displays: displays, visibleByDisplay: visibleByDisplay)
        return MenuBarFullStripLayout(
            groups: reducedGroups,
            labelStyle: .compact,
            estimatedWidth: estimatedWidth(
                groups: reducedGroups,
                style: .compact,
                hasOverflow: reducedGroups.contains { !$0.hiddenWorkspaces.isEmpty },
                workspaceLabelMode: workspaceLabelMode,
                displayIconConfiguration: displayIconConfiguration
            )
        )
    }

    static func defaultBudget(for screenWidth: CGFloat?) -> CGFloat {
        guard let screenWidth else { return defaultAvailableWidth }
        return min(680, max(260, screenWidth * 0.38))
    }

    private static func makeGroups(
        displays: [MenuBarDisplayItem],
        visibleByDisplay: [String: [MenuBarWorkspaceItem]]
    ) -> [MenuBarFullStripDisplayGroup] {
        displays.map { display in
            let ids = Set((visibleByDisplay[display.id] ?? []).map(\.id))
            return MenuBarFullStripDisplayGroup(
                display: display,
                visibleWorkspaces: display.workspaces.filter { ids.contains($0.id) },
                hiddenWorkspaces: display.workspaces.filter { !ids.contains($0.id) }
            )
        }
    }

    private static func estimatedWidth(
        groups: [MenuBarFullStripDisplayGroup],
        style: MenuBarFullStripLabelStyle,
        hasOverflow: Bool,
        workspaceLabelMode: MenuBarWorkspaceLabelMode,
        displayIconConfiguration: MenuBarDisplayIconConfiguration
    ) -> CGFloat {
        let groupWidths = groups.map { group -> CGFloat in
            let workspaces = group.visibleWorkspaces.reduce(CGFloat(0)) { result, workspace in
                result + workspaceWidth(
                    workspace,
                    style: style,
                    workspaceLabelMode: workspaceLabelMode
                ) + MenuBarVisualTokens.workspaceSpacing
            }
            let style = displayIconConfiguration.style(for: group.display)
            let iconGap = style == .none ? 0 : MenuBarVisualTokens.displayWorkspaceGap
            return displayIconConfiguration.reservedWidth(for: group.display) + iconGap + workspaces
        }
        let dividers = CGFloat(max(0, groups.count - 1)) * MenuBarVisualTokens.groupDividerWidth
        let overflow = hasOverflow ? MenuBarVisualTokens.overflowWidth : 0
        return groupWidths.reduce(0, +) + dividers + overflow + 8
    }

    private static func workspaceWidth(
        _ workspace: MenuBarWorkspaceItem,
        style: MenuBarFullStripLabelStyle,
        workspaceLabelMode: MenuBarWorkspaceLabelMode
    ) -> CGFloat {
        let label = workspace.visibleLabel(
            mode: workspaceLabelMode,
            compact: style == .compact
        )
        let measured = CGFloat(label.count) * 6.3 + 12
        return min(MenuBarVisualTokens.maximumWorkspaceButtonWidth, max(22, measured))
    }
}

enum MenuBarStatusItemCompositionPolicy {
    static func usesDisplayGroups(
        for _: MenuBarPresentationMode,
        operatingSystemVersion: OperatingSystemVersion
    ) -> Bool {
        operatingSystemVersion.majorVersion >= 27
    }
}

enum MenuBarStatusItemActivationPolicy {
    static func opensMenu(
        eventType: NSEvent.EventType?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        eventType == nil
            || modifierFlags.contains(.control)
            || eventType == .rightMouseDown
            || eventType == .rightMouseUp
    }

    static func action(
        for mode: MenuBarPresentationMode,
        eventType: NSEvent.EventType?,
        modifierFlags: NSEvent.ModifierFlags,
        pointerTarget: MenuBarHitTarget?
    ) -> MenuBarInteractionAction {
        guard !opensMenu(eventType: eventType, modifierFlags: modifierFlags),
              mode == .full,
              let pointerTarget
        else { return .openMenu }
        return MenuBarInteractionRouter.action(for: pointerTarget)
    }
}

/// Detached status menus must not begin their own tracking loop from inside the status button's
/// mouse-down action. Waiting for mouse-up lets AppKit finish the button interaction first.
enum MenuBarStatusItemControlEventPolicy {
    static let actionEvents: NSEvent.EventTypeMask = [.leftMouseUp, .rightMouseUp]
}

struct MenuBarMenuPresentationRequestGate {
    private(set) var isPending = false

    mutating func request() -> Bool {
        guard !isPending else { return false }
        isPending = true
        return true
    }

    mutating func consume() -> Bool {
        guard isPending else { return false }
        isPending = false
        return true
    }

    @discardableResult
    mutating func cancel() -> Bool {
        let wasPending = isPending
        isPending = false
        return wasPending
    }
}

struct MenuBarDisplayGroupStatusItem: Equatable, Sendable {
    let mode: MenuBarPresentationMode
    let group: MenuBarFullStripDisplayGroup
    let labelStyle: MenuBarFullStripLabelStyle
    let overflowCount: Int
    let overflowSummary: String?
}

enum MenuBarDisplayGroupStatusItemPlanner {
    static func groups(
        for snapshot: MenuBarPresentationSnapshot,
        availableWidth: CGFloat,
        displayIconConfiguration: MenuBarDisplayIconConfiguration = .automatic
    ) -> [MenuBarDisplayGroupStatusItem] {
        guard snapshot.mode == .full else {
            return snapshot.displays.map { display in
                MenuBarDisplayGroupStatusItem(
                    mode: snapshot.mode,
                    group: MenuBarFullStripDisplayGroup(
                        display: display,
                        visibleWorkspaces: display.workspaces.filter(\.isActive),
                        hiddenWorkspaces: []
                    ),
                    labelStyle: .full,
                    overflowCount: 0,
                    overflowSummary: nil
                )
            }
        }
        let layout = MenuBarPressurePolicy.layout(
            displays: snapshot.displays,
            availableWidth: availableWidth,
            workspaceLabelMode: snapshot.workspaceLabelMode,
            displayIconConfiguration: displayIconConfiguration
        )
        return layout.groups.enumerated().map { index, group in
            let carriesOverflow = index == layout.groups.count - 1
            return MenuBarDisplayGroupStatusItem(
                mode: snapshot.mode,
                group: group,
                labelStyle: layout.labelStyle,
                overflowCount: carriesOverflow ? layout.hiddenWorkspaceCount : 0,
                overflowSummary: carriesOverflow ? layout.overflowSummary : nil
            )
        }
    }

    /// AppKit inserts successively created status items at the left edge of the status area.
    /// Retained positional slots therefore receive the logical plan in reverse order.
    static func configurationOrder(
        for logicalGroups: [MenuBarDisplayGroupStatusItem]
    ) -> [MenuBarDisplayGroupStatusItem] {
        Array(logicalGroups.reversed())
    }
}

struct MenuBarScreenSpaceTarget: Equatable {
    let frame: CGRect
    let hitTarget: MenuBarHitTarget
}

enum MenuBarScreenSpaceTargetResolver {
    static func target(
        at pointer: CGPoint,
        among targets: [MenuBarScreenSpaceTarget]
    ) -> MenuBarHitTarget? {
        // The owning status-item button already proves the vertical hit. Comparing only screen X
        // follows the macOS 27-validated Stats approach and avoids relying on a remote menu-bar
        // window's vertical coordinate conversion.
        targets.first(where: {
            pointer.x >= $0.frame.minX && pointer.x < $0.frame.maxX
        })?.hitTarget
    }
}

struct MenuBarWorkspaceHoverState: Equatable {
    private(set) var target: MenuBarHitTarget?

    @discardableResult
    mutating func update(
        pointer: CGPoint?,
        among targets: [MenuBarScreenSpaceTarget]
    ) -> Bool {
        let resolved = pointer.flatMap {
            MenuBarScreenSpaceTargetResolver.target(at: $0, among: targets)
        }
        let nextTarget: MenuBarHitTarget?
        if case .workspace = resolved {
            nextTarget = resolved
        } else {
            nextTarget = nil
        }
        guard nextTarget != target else { return false }
        target = nextTarget
        return true
    }
}

struct MenuBarWorkspaceTrackingRegion: Equatable {
    let frame: CGRect
    let hitTarget: MenuBarHitTarget
}

enum MenuBarVisualTokens {
    static let componentHeight: CGFloat = 18
    static let appGlyphWidth: CGFloat = 20
    static let mediumAppGlyphWidth: CGFloat = 24
    static let fullPrimaryReservedWidth: CGFloat = 34
    static let displayIconWidth: CGFloat = 18
    static let workspaceSpacing: CGFloat = 2
    static let displayWorkspaceGap: CGFloat = 4
    static let groupDividerWidth: CGFloat = 9
    static let overflowWidth: CGFloat = 32
    static let maximumWorkspaceButtonWidth: CGFloat = 72
    static let compactCornerRadius: CGFloat = 4
    static let chipCornerRadius: CGFloat = 5
    static let separatorHeight: CGFloat = 14
}

/// Renders one logical display inside a single standard status-item button. Compact and Medium are
/// informational; Full additionally supplies visual segment geometry that the controller resolves
/// against `NSEvent.mouseLocation` when the parent action fires. Pointer ownership stays with that
/// parent button on macOS 27 in every mode.
@MainActor
final class MenuBarDisplayGroupContentView: NSView {
    private var contentSize = CGSize(width: 1, height: MenuBarVisualTokens.componentHeight)
    private var workspaceSegments: [MenuBarWorkspaceSegmentView] = []
    private var hoverState = MenuBarWorkspaceHoverState()
    private(set) var mode: MenuBarPresentationMode = .full

    override var intrinsicContentSize: NSSize { contentSize }

    init(
        plan: MenuBarDisplayGroupStatusItem,
        workspaceLabelMode: MenuBarWorkspaceLabelMode,
        highlightColor: MenuBarHighlightColor,
        displayIconConfiguration: MenuBarDisplayIconConfiguration = .automatic
    ) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        configure(
            plan: plan,
            workspaceLabelMode: workspaceLabelMode,
            highlightColor: highlightColor,
            displayIconConfiguration: displayIconConfiguration
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// The standard `NSStatusBarButton` is the only pointer target. In particular, none of the
    /// visual workspace segments participates in macOS 27's broken nested status-item hit testing.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(
        plan: MenuBarDisplayGroupStatusItem,
        workspaceLabelMode: MenuBarWorkspaceLabelMode,
        highlightColor: MenuBarHighlightColor,
        displayIconConfiguration: MenuBarDisplayIconConfiguration = .automatic
    ) {
        mode = plan.mode
        clearHover()
        subviews.forEach { $0.removeFromSuperview() }
        workspaceSegments.removeAll(keepingCapacity: true)

        if plan.mode != .full {
            configureInformationalContent(
                plan: plan,
                workspaceLabelMode: workspaceLabelMode,
                highlightColor: highlightColor,
                displayIconConfiguration: displayIconConfiguration
            )
            return
        }

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = MenuBarVisualTokens.workspaceSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false

        let display = plan.group.display
        if let systemImage = displayIconConfiguration.systemImage(for: display) {
            let icon = NSImageView()
            icon.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
            icon.contentTintColor = display.isInteractionDisplay ? .labelColor : .secondaryLabelColor
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11.5, weight: .medium)
            icon.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                icon.widthAnchor.constraint(equalToConstant: MenuBarVisualTokens.displayIconWidth),
                icon.heightAnchor.constraint(equalToConstant: MenuBarVisualTokens.componentHeight),
            ])
            stack.addArrangedSubview(icon)
            stack.setCustomSpacing(MenuBarVisualTokens.displayWorkspaceGap, after: icon)
        }

        for workspace in plan.group.visibleWorkspaces {
            let segment = MenuBarWorkspaceSegmentView(
                workspace: workspace,
                display: display,
                labelStyle: plan.labelStyle,
                workspaceLabelMode: workspaceLabelMode,
                highlightColor: highlightColor
            )
            workspaceSegments.append(segment)
            stack.addArrangedSubview(segment)
        }

        if plan.overflowCount > 0 {
            let overflow = NSTextField(labelWithString: "+\(plan.overflowCount)")
            overflow.font = .systemFont(ofSize: 9.5, weight: .medium)
            overflow.textColor = .secondaryLabelColor
            overflow.alignment = .center
            overflow.toolTip = plan.overflowSummary
            overflow.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                overflow.widthAnchor.constraint(greaterThanOrEqualToConstant: 22),
                overflow.heightAnchor.constraint(equalToConstant: MenuBarVisualTokens.componentHeight),
            ])
            stack.addArrangedSubview(overflow)
        }

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: MenuBarVisualTokens.componentHeight),
        ])
        stack.layoutSubtreeIfNeeded()
        contentSize = CGSize(
            width: ceil(stack.fittingSize.width + 6),
            height: MenuBarVisualTokens.componentHeight
        )
        frame.size = contentSize
        invalidateIntrinsicContentSize()
        setAccessibilityElement(false)
    }

    private func configureInformationalContent(
        plan: MenuBarDisplayGroupStatusItem,
        workspaceLabelMode: MenuBarWorkspaceLabelMode,
        highlightColor: MenuBarHighlightColor,
        displayIconConfiguration: MenuBarDisplayIconConfiguration
    ) {
        let content = NSHostingView(rootView: MenuBarInformationalDisplayStatusView(
            mode: plan.mode,
            display: plan.group.display,
            workspaceLabelMode: workspaceLabelMode,
            highlightColor: highlightColor,
            displayIconConfiguration: displayIconConfiguration
        ))
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: MenuBarVisualTokens.componentHeight),
        ])
        content.layoutSubtreeIfNeeded()
        contentSize = CGSize(
            width: ceil(content.fittingSize.width + 6),
            height: MenuBarVisualTokens.componentHeight
        )
        frame.size = contentSize
        invalidateIntrinsicContentSize()
        setAccessibilityElement(false)
    }

    func screenSpaceTargets() -> [MenuBarScreenSpaceTarget] {
        workspaceSegments.compactMap { segment in
            guard let window = segment.window else { return nil }
            let windowFrame = segment.convert(segment.bounds, to: nil)
            return MenuBarScreenSpaceTarget(
                frame: window.convertToScreen(windowFrame),
                hitTarget: segment.hitTarget
            )
        }
    }

    func workspaceTrackingRegions(in view: NSView) -> [MenuBarWorkspaceTrackingRegion] {
        workspaceSegments.map { segment in
            MenuBarWorkspaceTrackingRegion(
                frame: segment.convert(segment.bounds, to: view),
                hitTarget: segment.hitTarget
            )
        }
    }

    @discardableResult
    func updateHover(at pointer: CGPoint?) -> MenuBarHitTarget? {
        let changed = hoverState.update(pointer: pointer, among: screenSpaceTargets())
        if changed {
            workspaceSegments.forEach { segment in
                segment.setHovered(segment.hitTarget == hoverState.target)
            }
        }
        return hoverState.target
    }

    func clearHover() {
        guard hoverState.target != nil else { return }
        _ = hoverState.update(pointer: nil, among: [])
        workspaceSegments.forEach { $0.setHovered(false) }
    }
}

@MainActor
private final class MenuBarWorkspaceHoverOverlay: NSView {
    init(contrastColor: NSColor) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = MenuBarVisualTokens.compactCornerRadius
        layer?.backgroundColor = contrastColor.withAlphaComponent(0.10).cgColor
        layer?.borderColor = contrastColor.withAlphaComponent(0.42).cgColor
        layer?.borderWidth = 0.75
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func setHovered(_ hovered: Bool) {
        isHidden = !hovered
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
private final class MenuBarWorkspaceSegmentView: NSView {
    let hitTarget: MenuBarHitTarget
    private let hoverOverlay: MenuBarWorkspaceHoverOverlay

    init(
        workspace: MenuBarWorkspaceItem,
        display: MenuBarDisplayItem,
        labelStyle: MenuBarFullStripLabelStyle,
        workspaceLabelMode: MenuBarWorkspaceLabelMode,
        highlightColor: MenuBarHighlightColor
    ) {
        hitTarget = .workspace(
            workspaceID: workspace.id,
            displayIdentifier: display.id
        )
        let hoverContrastColor = workspace.isInteractionWorkspace
            ? highlightColor.nsForegroundColor : NSColor.labelColor
        hoverOverlay = MenuBarWorkspaceHoverOverlay(contrastColor: hoverContrastColor)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = MenuBarVisualTokens.compactCornerRadius

        addSubview(hoverOverlay)

        let label = NSTextField(labelWithString: workspace.visibleLabel(
            mode: workspaceLabelMode,
            compact: labelStyle == .compact
        ))
        label.font = .systemFont(
            ofSize: 11,
            weight: workspace.isInteractionWorkspace
                ? .semibold : (workspace.isActive ? .medium : .regular)
        )
        label.textColor = workspace.isInteractionWorkspace
            ? highlightColor.nsForegroundColor : .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        if workspace.isInteractionWorkspace {
            layer?.backgroundColor = highlightColor.nsColor.cgColor
            layer?.borderColor = (highlightColor.usesDarkForeground
                ? NSColor.black.withAlphaComponent(0.28)
                : NSColor.white.withAlphaComponent(0.30)).cgColor
            layer?.borderWidth = 0.5
        } else if workspace.isActive {
            layer?.backgroundColor = highlightColor.nsColor.withAlphaComponent(0.14).cgColor
            layer?.borderColor = highlightColor.nsColor.withAlphaComponent(0.72).cgColor
            layer?.borderWidth = 1
        } else {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.09).cgColor
        }

        NSLayoutConstraint.activate([
            hoverOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            hoverOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            hoverOverlay.topAnchor.constraint(equalTo: topAnchor),
            hoverOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 22),
            widthAnchor.constraint(lessThanOrEqualToConstant: MenuBarVisualTokens.maximumWorkspaceButtonWidth),
            heightAnchor.constraint(equalToConstant: MenuBarVisualTokens.componentHeight),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func setHovered(_ hovered: Bool) {
        hoverOverlay.setHovered(hovered)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct MenuBarPrimaryStatusView: View {
    let snapshot: MenuBarPresentationSnapshot
    var highlightColor: MenuBarHighlightColor = .default
    var displayIconConfiguration: MenuBarDisplayIconConfiguration = .automatic

    var body: some View {
        HStack(spacing: snapshot.mode == .compact ? 4 : 5) {
            appGlyph
            if snapshot.mode != .full {
                separator
                ForEach(snapshot.displays) { display in
                    switch snapshot.mode {
                    case .compact:
                        CompactDisplaySignal(
                            display: display,
                            workspaceLabelMode: snapshot.workspaceLabelMode,
                            highlightColor: highlightColor,
                            displayIconConfiguration: displayIconConfiguration
                        )
                    case .medium:
                        MediumDisplayChip(
                            display: display,
                            workspaceLabelMode: snapshot.workspaceLabelMode,
                            highlightColor: highlightColor,
                            displayIconConfiguration: displayIconConfiguration
                        )
                    case .full:
                        EmptyView()
                    }
                }
            }
        }
        .frame(height: MenuBarVisualTokens.componentHeight)
        .fixedSize(horizontal: true, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.primaryAccessibilityLabel)
        .help(snapshot.primaryTooltip)
    }

    private var appGlyph: some View {
        Image(systemName: snapshot.mode == .full ? "rectangle.split.2x2" : "rectangle.on.rectangle")
            .font(.system(size: snapshot.mode == .full ? 13 : 12.5, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .frame(
                width: snapshot.mode == .medium
                    ? MenuBarVisualTokens.mediumAppGlyphWidth
                    : MenuBarVisualTokens.appGlyphWidth,
                height: MenuBarVisualTokens.componentHeight
            )
            .background {
                if snapshot.mode == .medium {
                    RoundedRectangle(cornerRadius: MenuBarVisualTokens.compactCornerRadius)
                        .fill(.primary.opacity(0.10))
                }
            }
    }

    private var separator: some View {
        Rectangle()
            .fill(.primary.opacity(0.22))
            .frame(width: 0.5, height: MenuBarVisualTokens.separatorHeight)
    }
}

private struct MenuBarInformationalDisplayStatusView: View {
    let mode: MenuBarPresentationMode
    let display: MenuBarDisplayItem
    let workspaceLabelMode: MenuBarWorkspaceLabelMode
    let highlightColor: MenuBarHighlightColor
    let displayIconConfiguration: MenuBarDisplayIconConfiguration

    var body: some View {
        Group {
            switch mode {
            case .compact:
                CompactDisplaySignal(
                    display: display,
                    workspaceLabelMode: workspaceLabelMode,
                    highlightColor: highlightColor,
                    displayIconConfiguration: displayIconConfiguration
                )
            case .medium:
                MediumDisplayChip(
                    display: display,
                    workspaceLabelMode: workspaceLabelMode,
                    highlightColor: highlightColor,
                    displayIconConfiguration: displayIconConfiguration
                )
            case .full:
                EmptyView()
            }
        }
        .frame(height: MenuBarVisualTokens.componentHeight)
        .fixedSize(horizontal: true, vertical: true)
    }
}

private struct CompactDisplaySignal: View {
    let display: MenuBarDisplayItem
    let workspaceLabelMode: MenuBarWorkspaceLabelMode
    let highlightColor: MenuBarHighlightColor
    let displayIconConfiguration: MenuBarDisplayIconConfiguration

    var body: some View {
        Group {
            switch presentation.layout {
            case .keyInsideIcon:
                keyInsideIcon
            case .inlineLabel:
                inlineLabel
            }
        }
        .frame(height: MenuBarVisualTokens.componentHeight)
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(signalColor)
        .accessibilityHidden(true)
        .help(display.accessibilityLabel)
    }

    private var keyInsideIcon: some View {
        ZStack {
            if let systemImage = presentation.systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: keyOverlayMetrics.iconPointSize, weight: .medium))
            }
            Text(presentation.label)
                .font(.system(size: keyOverlayMetrics.labelPointSize, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(width: keyOverlayMetrics.labelWidth)
                .offset(
                    x: keyOverlayMetrics.labelOffsetX,
                    y: keyOverlayMetrics.labelOffsetY
                )
        }
        .frame(
            width: keyOverlayMetrics.componentWidth,
            height: MenuBarVisualTokens.componentHeight
        )
    }

    private var inlineLabel: some View {
        HStack(spacing: 3) {
            if let systemImage = presentation.systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11.5, weight: .semibold))
            }
            Text(presentation.label)
                .font(.system(
                    size: 10,
                    weight: display.isInteractionDisplay ? .semibold : .medium
                ))
                .lineLimit(1)
                .truncationMode(.tail)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var presentation: MenuBarCompactDisplayPresentation {
        MenuBarCompactDisplayPresentation.resolve(
            display: display,
            workspaceLabelMode: workspaceLabelMode,
            displayIconConfiguration: displayIconConfiguration
        )
    }

    private var keyOverlayMetrics: MenuBarCompactKeyOverlayMetrics {
        MenuBarCompactKeyOverlayMetrics.resolve(
            systemImage: presentation.systemImage ?? "display",
            labelCharacterCount: presentation.label.count
        )
    }

    private var signalColor: Color {
        display.isInteractionDisplay
            ? highlightColor.color
            : Color.primary.opacity(0.62)
    }
}

private struct MediumDisplayChip: View {
    let display: MenuBarDisplayItem
    let workspaceLabelMode: MenuBarWorkspaceLabelMode
    let highlightColor: MenuBarHighlightColor
    let displayIconConfiguration: MenuBarDisplayIconConfiguration

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage = displayIconConfiguration.systemImage(for: display) {
                Image(systemName: systemImage)
                    .font(.system(size: 11.5, weight: .semibold))
            }
            Text(display.activeWorkspaceLabel(mode: workspaceLabelMode))
                .font(.system(size: 11.5, weight: display.isInteractionDisplay ? .semibold : .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 70)
        }
        .foregroundStyle(display.isInteractionDisplay ? highlightColor.foregroundColor : Color.primary)
        .padding(.horizontal, 6)
        .frame(height: MenuBarVisualTokens.componentHeight)
        .background(
            RoundedRectangle(cornerRadius: MenuBarVisualTokens.chipCornerRadius)
                .fill(display.isInteractionDisplay
                    ? highlightColor.color
                    : Color.primary.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MenuBarVisualTokens.chipCornerRadius)
                .stroke(
                    display.isInteractionDisplay
                        ? highlightColor.contrastStrokeColor
                        : Color.primary.opacity(0.12),
                    lineWidth: 0.5
                )
        )
        .accessibilityHidden(true)
        .help(display.accessibilityLabel)
    }
}

struct MenuBarSettingsPreview: View {
    let snapshot: MenuBarPresentationSnapshot
    var highlightColor: MenuBarHighlightColor = .default
    var displayIconConfiguration: MenuBarDisplayIconConfiguration = .automatic

    var body: some View {
        Group {
            if MenuBarStatusItemCompositionPolicy.usesDisplayGroups(
                for: snapshot.mode,
                operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersion
            ) {
                HStack(spacing: 6) {
                    ForEach(displayGroupPlans, id: \.group.display.id) { plan in
                        MenuBarDisplayGroupContentRepresentable(
                            plan: plan,
                            workspaceLabelMode: snapshot.workspaceLabelMode,
                            highlightColor: highlightColor,
                            displayIconConfiguration: displayIconConfiguration
                        )
                        .fixedSize()
                    }
                }
            } else {
                MenuBarStatusContentRepresentable(
                    snapshot: snapshot,
                    availableWidth: MenuBarPressurePolicy.defaultAvailableWidth,
                    highlightColor: highlightColor,
                    displayIconConfiguration: displayIconConfiguration
                )
            }
        }
        .fixedSize()
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.white.opacity(0.08), lineWidth: 0.5)
                )
        )
        .accessibilityLabel("\(snapshot.mode.title) menu bar preview")
    }

    private var displayGroupPlans: [MenuBarDisplayGroupStatusItem] {
        MenuBarDisplayGroupStatusItemPlanner.groups(
            for: snapshot,
            availableWidth: MenuBarPressurePolicy.defaultAvailableWidth,
            displayIconConfiguration: displayIconConfiguration
        )
    }
}

/// Settings embeds the exact per-display content used by each standard macOS 27 status item. This
/// keeps preview composition, display order, icon choices, workspace labels, and pressure behavior
/// on the production path instead of maintaining a visually similar SwiftUI-only copy.
struct MenuBarDisplayGroupContentRepresentable: NSViewRepresentable {
    let plan: MenuBarDisplayGroupStatusItem
    let workspaceLabelMode: MenuBarWorkspaceLabelMode
    let highlightColor: MenuBarHighlightColor
    var displayIconConfiguration: MenuBarDisplayIconConfiguration = .automatic

    func makeNSView(context: Context) -> MenuBarDisplayGroupContentView {
        MenuBarDisplayGroupContentView(
            plan: plan,
            workspaceLabelMode: workspaceLabelMode,
            highlightColor: highlightColor,
            displayIconConfiguration: displayIconConfiguration
        )
    }

    func updateNSView(_ nsView: MenuBarDisplayGroupContentView, context: Context) {
        nsView.configure(
            plan: plan,
            workspaceLabelMode: workspaceLabelMode,
            highlightColor: highlightColor,
            displayIconConfiguration: displayIconConfiguration
        )
    }
}

/// The shared content used by Settings preview and the single-item compatibility path. macOS 27
/// renders separate display-group status items instead; the underlying planning and visual tokens
/// remain common.
struct MenuBarStatusContentRepresentable: NSViewRepresentable {
    let snapshot: MenuBarPresentationSnapshot
    let availableWidth: CGFloat
    var highlightColor: MenuBarHighlightColor = .default
    var displayIconConfiguration: MenuBarDisplayIconConfiguration = .automatic

    func makeNSView(context: Context) -> MenuBarStatusContentView {
        MenuBarStatusContentView(
            snapshot: snapshot,
            availableWidth: availableWidth,
            highlightColor: highlightColor,
            displayIconConfiguration: displayIconConfiguration,
            workspaceAction: nil
        )
    }

    func updateNSView(_ nsView: MenuBarStatusContentView, context: Context) {
        nsView.configure(
            snapshot: snapshot,
            availableWidth: availableWidth,
            highlightColor: highlightColor,
            displayIconConfiguration: displayIconConfiguration,
            workspaceAction: nil
        )
    }
}

/// Owns the status item's pointer and accessibility contract without assigning `NSStatusItem.menu`.
/// AppKit documents that an assigned menu takes ownership of every status-item click. Keeping the
/// menu detached lets concrete workspace buttons receive primary clicks on every supported macOS,
/// while this host handles the remaining primary area and accessibility press as the app-menu
/// target. Workspace buttons forward secondary and Control-clicks to the same menu action.
@MainActor
final class MenuBarStatusHostView: NSView {
    private let contentView: MenuBarStatusContentView
    private let selectionSurface = NSVisualEffectView()
    private var menuAction: (() -> Void)?
    private(set) var isMenuPresented = false

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: contentView.intrinsicContentSize.width,
            height: NSStatusBar.system.thickness
        )
    }

    init(
        contentView: MenuBarStatusContentView,
        menuAction: (() -> Void)?
    ) {
        self.contentView = contentView
        self.menuAction = menuAction
        super.init(frame: .zero)

        selectionSurface.material = .selection
        selectionSurface.blendingMode = .withinWindow
        selectionSurface.state = .active
        selectionSurface.isHidden = true
        selectionSurface.wantsLayer = true
        selectionSurface.layer?.cornerRadius = MenuBarVisualTokens.chipCornerRadius
        selectionSurface.layer?.masksToBounds = true
        selectionSurface.translatesAutoresizingMaskIntoConstraints = false

        addSubview(selectionSurface)
        addSubview(contentView)
        NSLayoutConstraint.activate([
            selectionSurface.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            selectionSurface.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            selectionSurface.centerYAnchor.constraint(equalTo: centerYAnchor),
            selectionSurface.heightAnchor.constraint(equalToConstant: MenuBarVisualTokens.componentHeight),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        menuAction?()
    }

    override func rightMouseDown(with event: NSEvent) {
        menuAction?()
    }

    override func accessibilityPerformPress() -> Bool {
        menuAction?()
        return true
    }

    func configure(
        menuAction: (() -> Void)?,
        accessibilityLabel: String,
        accessibilityHelp: String
    ) {
        self.menuAction = menuAction
        setAccessibilityLabel(accessibilityLabel)
        setAccessibilityHelp(accessibilityHelp)
        frame.size = intrinsicContentSize
        invalidateIntrinsicContentSize()
    }

    func setMenuPresented(_ presented: Bool) {
        guard isMenuPresented != presented else { return }
        isMenuPresented = presented
        selectionSurface.isHidden = !presented
    }
}

@MainActor
final class MenuBarStatusContentView: NSView {
    private var contentSize = CGSize(
        width: MenuBarVisualTokens.appGlyphWidth,
        height: MenuBarVisualTokens.componentHeight
    )
    private var fullStrip: MenuBarFullStripView?

    override var intrinsicContentSize: NSSize { contentSize }

    init(
        snapshot: MenuBarPresentationSnapshot,
        availableWidth: CGFloat,
        highlightColor: MenuBarHighlightColor = .default,
        displayIconConfiguration: MenuBarDisplayIconConfiguration = .automatic,
        workspaceAction: ((MenuBarHitTarget) -> Void)?,
        menuAction: (() -> Void)? = nil,
        workspaceHoverAction: ((MenuBarHitTarget?, CGRect?) -> Void)? = nil
    ) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        configure(
            snapshot: snapshot,
            availableWidth: availableWidth,
            highlightColor: highlightColor,
            displayIconConfiguration: displayIconConfiguration,
            workspaceAction: workspaceAction,
            menuAction: menuAction,
            workspaceHoverAction: workspaceHoverAction
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configure(
        snapshot: MenuBarPresentationSnapshot,
        availableWidth: CGFloat,
        highlightColor: MenuBarHighlightColor = .default,
        displayIconConfiguration: MenuBarDisplayIconConfiguration = .automatic,
        workspaceAction: ((MenuBarHitTarget) -> Void)?,
        menuAction: (() -> Void)? = nil,
        workspaceHoverAction: ((MenuBarHitTarget?, CGRect?) -> Void)? = nil
    ) {
        subviews.forEach { $0.removeFromSuperview() }
        fullStrip = nil

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false

        let primary = NSHostingView(rootView: MenuBarPrimaryStatusView(
            snapshot: snapshot,
            highlightColor: highlightColor,
            displayIconConfiguration: displayIconConfiguration
        ))
        primary.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(primary)

        if snapshot.mode == .full {
            let divider = NSBox()
            divider.boxType = .separator
            divider.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                divider.widthAnchor.constraint(equalToConstant: 1),
                divider.heightAnchor.constraint(equalToConstant: MenuBarVisualTokens.separatorHeight),
            ])
            stack.addArrangedSubview(divider)

            let strip = MenuBarFullStripView(
                snapshot: snapshot,
                availableWidth: max(120, availableWidth - MenuBarVisualTokens.fullPrimaryReservedWidth),
                highlightColor: highlightColor,
                displayIconConfiguration: displayIconConfiguration,
                workspaceAction: workspaceAction,
                menuAction: menuAction,
                workspaceHoverAction: workspaceHoverAction
            )
            fullStrip = strip
            stack.addArrangedSubview(strip)
        }

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: MenuBarVisualTokens.componentHeight),
        ])
        stack.layoutSubtreeIfNeeded()
        contentSize = CGSize(
            width: ceil(stack.fittingSize.width),
            height: MenuBarVisualTokens.componentHeight
        )
        frame.size = contentSize
        invalidateIntrinsicContentSize()
        setAccessibilityElement(false)
    }

    /// All non-workspace content deliberately falls through to `MenuBarStatusHostView`, whose
    /// primary action opens the app menu. Only a concrete Full-mode workspace button captures a
    /// primary click.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard fullStrip != nil, let candidate = super.hitTest(point) else { return nil }
        var view: NSView? = candidate
        while let current = view, current !== self {
            if current is MenuBarWorkspaceButton { return current }
            view = current.superview
        }
        return nil
    }

}

struct MenuBarFullStripRepresentable: NSViewRepresentable {
    let snapshot: MenuBarPresentationSnapshot
    let availableWidth: CGFloat
    var highlightColor: MenuBarHighlightColor = .default
    var displayIconConfiguration: MenuBarDisplayIconConfiguration = .automatic

    func makeNSView(context: Context) -> MenuBarFullStripView {
        MenuBarFullStripView(
            snapshot: snapshot,
            availableWidth: availableWidth,
            highlightColor: highlightColor,
            displayIconConfiguration: displayIconConfiguration,
            workspaceAction: nil
        )
    }

    func updateNSView(_ nsView: MenuBarFullStripView, context: Context) {
        nsView.configure(
            snapshot: snapshot,
            availableWidth: availableWidth,
            highlightColor: highlightColor,
            displayIconConfiguration: displayIconConfiguration,
            workspaceAction: nil
        )
    }
}

@MainActor
final class MenuBarFullStripView: NSView {
    private(set) var layout: MenuBarFullStripLayout
    private var workspaceAction: ((MenuBarHitTarget) -> Void)?
    private var menuAction: (() -> Void)?
    private var workspaceHoverAction: ((MenuBarHitTarget?, CGRect?) -> Void)?
    private var contentSize = CGSize(width: 1, height: MenuBarVisualTokens.componentHeight)

    override var intrinsicContentSize: NSSize { contentSize }

    init(
        snapshot: MenuBarPresentationSnapshot,
        availableWidth: CGFloat,
        highlightColor: MenuBarHighlightColor = .default,
        displayIconConfiguration: MenuBarDisplayIconConfiguration = .automatic,
        workspaceAction: ((MenuBarHitTarget) -> Void)?,
        menuAction: (() -> Void)? = nil,
        workspaceHoverAction: ((MenuBarHitTarget?, CGRect?) -> Void)? = nil
    ) {
        layout = MenuBarPressurePolicy.layout(
            displays: snapshot.displays,
            availableWidth: availableWidth,
            workspaceLabelMode: snapshot.workspaceLabelMode,
            displayIconConfiguration: displayIconConfiguration
        )
        self.workspaceAction = workspaceAction
        self.menuAction = menuAction
        self.workspaceHoverAction = workspaceHoverAction
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        configure(
            snapshot: snapshot,
            availableWidth: availableWidth,
            highlightColor: highlightColor,
            displayIconConfiguration: displayIconConfiguration,
            workspaceAction: workspaceAction,
            menuAction: menuAction,
            workspaceHoverAction: workspaceHoverAction
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// Display icons, dividers, gaps, and group backgrounds are informational. Returning only an
    /// explicit workspace button prevents a transparent AppKit subview from stealing the primary
    /// menu click or accidentally routing it through a stale workspace target.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let candidate = super.hitTest(point) else { return nil }
        var view: NSView? = candidate
        while let current = view, current !== self {
            if current is MenuBarWorkspaceButton { return current }
            view = current.superview
        }
        return nil
    }

    func configure(
        snapshot: MenuBarPresentationSnapshot,
        availableWidth: CGFloat,
        highlightColor: MenuBarHighlightColor = .default,
        displayIconConfiguration: MenuBarDisplayIconConfiguration = .automatic,
        workspaceAction: ((MenuBarHitTarget) -> Void)?,
        menuAction: (() -> Void)? = nil,
        workspaceHoverAction: ((MenuBarHitTarget?, CGRect?) -> Void)? = nil
    ) {
        self.workspaceAction = workspaceAction
        self.menuAction = menuAction
        self.workspaceHoverAction = workspaceHoverAction
        layout = MenuBarPressurePolicy.layout(
            displays: snapshot.displays,
            availableWidth: availableWidth,
            workspaceLabelMode: snapshot.workspaceLabelMode,
            displayIconConfiguration: displayIconConfiguration
        )
        subviews.forEach { $0.removeFromSuperview() }

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        for (index, group) in layout.groups.enumerated() {
            if index > 0 { stack.addArrangedSubview(makeDivider()) }
            stack.addArrangedSubview(makeDisplayGroup(
                group,
                workspaceLabelMode: snapshot.workspaceLabelMode,
                highlightColor: highlightColor,
                displayIconConfiguration: displayIconConfiguration
            ))
        }
        if layout.hiddenWorkspaceCount > 0 {
            let overflow = NSTextField(labelWithString: "+\(layout.hiddenWorkspaceCount)")
            overflow.font = .systemFont(ofSize: 9.5, weight: .medium)
            overflow.textColor = .secondaryLabelColor
            overflow.alignment = .center
            overflow.toolTip = layout.overflowSummary
            overflow.setAccessibilityLabel(layout.overflowSummary ?? "Hidden workspaces")
            stack.addArrangedSubview(overflow)
        }

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: MenuBarVisualTokens.componentHeight),
        ])
        stack.layoutSubtreeIfNeeded()
        contentSize = CGSize(
            width: ceil(stack.fittingSize.width + 6),
            height: MenuBarVisualTokens.componentHeight
        )
        frame.size = contentSize
        invalidateIntrinsicContentSize()
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("WindowRanger display workspace strip")
    }

    private func makeDisplayGroup(
        _ group: MenuBarFullStripDisplayGroup,
        workspaceLabelMode: MenuBarWorkspaceLabelMode,
        highlightColor: MenuBarHighlightColor,
        displayIconConfiguration: MenuBarDisplayIconConfiguration
    ) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = MenuBarVisualTokens.workspaceSpacing

        if let systemImage = displayIconConfiguration.systemImage(for: group.display) {
            let icon = NSImageView()
            icon.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
            icon.contentTintColor = group.display.isInteractionDisplay
                ? .labelColor : .secondaryLabelColor
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11.5, weight: .medium)
            icon.toolTip = group.display.accessibilityLabel
            icon.setAccessibilityLabel(group.display.accessibilityLabel)
            icon.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                icon.widthAnchor.constraint(equalToConstant: MenuBarVisualTokens.displayIconWidth),
                icon.heightAnchor.constraint(equalToConstant: MenuBarVisualTokens.componentHeight),
            ])
            stack.addArrangedSubview(icon)
            stack.setCustomSpacing(MenuBarVisualTokens.displayWorkspaceGap, after: icon)
        }

        for workspace in group.visibleWorkspaces {
            let button = MenuBarWorkspaceButton(
                workspace: workspace,
                display: group.display,
                labelStyle: layout.labelStyle,
                workspaceLabelMode: workspaceLabelMode,
                highlightColor: highlightColor
            )
            button.onClick = { [weak self] in
                self?.workspaceAction?(.workspace(
                    workspaceID: workspace.id,
                    displayIdentifier: group.display.id
                ))
            }
            button.onMenu = { [weak self] in
                self?.menuAction?()
            }
            button.onHover = { [weak self] target, frame in
                self?.workspaceHoverAction?(target, frame)
            }
            stack.addArrangedSubview(button)
        }
        stack.setAccessibilityLabel(group.display.accessibilityLabel)
        return stack
    }

    private func makeDivider() -> NSView {
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.heightAnchor.constraint(equalToConstant: MenuBarVisualTokens.separatorHeight),
        ])
        return divider
    }
}

private final class MenuBarWorkspaceButton: NSButton {
    let hitTarget: MenuBarHitTarget
    var onClick: (() -> Void)?
    var onMenu: (() -> Void)?
    var onHover: ((MenuBarHitTarget?, CGRect?) -> Void)?
    private let hoverOverlay: MenuBarWorkspaceHoverOverlay
    private var hoverTrackingArea: NSTrackingArea?

    init(
        workspace: MenuBarWorkspaceItem,
        display: MenuBarDisplayItem,
        labelStyle: MenuBarFullStripLabelStyle,
        workspaceLabelMode: MenuBarWorkspaceLabelMode = .name,
        highlightColor: MenuBarHighlightColor = .default
    ) {
        hitTarget = .workspace(
            workspaceID: workspace.id,
            displayIdentifier: display.id
        )
        let hoverContrastColor = workspace.isInteractionWorkspace
            ? highlightColor.nsForegroundColor : NSColor.labelColor
        hoverOverlay = MenuBarWorkspaceHoverOverlay(contrastColor: hoverContrastColor)
        super.init(frame: .zero)
        title = workspace.visibleLabel(
            mode: workspaceLabelMode,
            compact: labelStyle == .compact
        )
        target = self
        action = #selector(clicked)
        isBordered = false
        bezelStyle = .regularSquare
        font = .systemFont(
            ofSize: 11,
            weight: workspace.isInteractionWorkspace ? .semibold : (workspace.isActive ? .medium : .regular)
        )
        contentTintColor = workspace.isInteractionWorkspace
            ? highlightColor.nsForegroundColor : .labelColor
        toolTip = "\(display.name) — workspace \(workspace.name)"
        setAccessibilityLabel("\(workspace.accessibilityLabel), \(display.name)")
        setAccessibilityHelp("Switches \(display.name) to workspace \(workspace.name)")
        focusRingType = .none
        cell?.lineBreakMode = .byTruncatingTail
        wantsLayer = true
        layer?.cornerRadius = MenuBarVisualTokens.compactCornerRadius
        if workspace.isInteractionWorkspace {
            layer?.backgroundColor = highlightColor.nsColor.cgColor
            layer?.borderColor = (highlightColor.usesDarkForeground
                ? NSColor.black.withAlphaComponent(0.28)
                : NSColor.white.withAlphaComponent(0.30)).cgColor
            layer?.borderWidth = 0.5
        } else if workspace.isActive {
            layer?.backgroundColor = highlightColor.nsColor.withAlphaComponent(0.14).cgColor
            layer?.borderColor = highlightColor.nsColor.withAlphaComponent(0.72).cgColor
            layer?.borderWidth = 1
        } else {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.09).cgColor
        }
        addSubview(hoverOverlay)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hoverOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            hoverOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            hoverOverlay.topAnchor.constraint(equalTo: topAnchor),
            hoverOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 22),
            widthAnchor.constraint(lessThanOrEqualToConstant: MenuBarVisualTokens.maximumWorkspaceButtonWidth),
            heightAnchor.constraint(equalToConstant: MenuBarVisualTokens.componentHeight),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
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
        hoverOverlay.setHovered(true)
        onHover?(hitTarget, screenFrame())
    }

    override func mouseExited(with event: NSEvent) {
        hoverOverlay.setHovered(false)
        onHover?(nil, nil)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onMenu?()
            return
        }
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        onMenu?()
    }

    private func screenFrame() -> CGRect? {
        guard let window else { return nil }
        return window.convertToScreen(convert(bounds, to: nil))
    }

    @objc private func clicked() { onClick?() }
}
