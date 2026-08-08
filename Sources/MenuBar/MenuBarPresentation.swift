import AppKit
import SwiftUI

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
            "Shows the app symbol and a tiny active-workspace signal for every connected display. The entire item opens the app menu."
        case .medium:
            "Shows the app symbol and one readable active-workspace chip per connected display. The chips are informational and open the app menu."
        case .full:
            "Keeps a separate app-menu item and adds display-grouped workspace buttons. Only explicit workspace buttons switch workspaces."
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

struct MenuBarWorkspaceItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let compactName: String
    let isActive: Bool
    let isInteractionWorkspace: Bool

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
    let workspaces: [MenuBarWorkspaceItem]

    var accessibilityLabel: String {
        let interaction = isInteractionDisplay ? ", interaction display" : ""
        return "\(name)\(interaction), active workspace \(activeWorkspaceName)"
    }
}

struct MenuBarPresentationSnapshot: Equatable, Sendable {
    let mode: MenuBarPresentationMode
    let displayMode: MultiDisplayMode
    let interactionWorkspaceID: UUID
    let displays: [MenuBarDisplayItem]

    var primaryAccessibilityLabel: String {
        let states = displays.map(\.accessibilityLabel).joined(separator: ". ")
        return "WindowManager menu. \(states)."
    }

    var primaryTooltip: String {
        let states = displays.map { "\($0.name): \($0.activeWorkspaceName)" }
            .joined(separator: " · ")
        return "WindowManager — \(states)"
    }

    func replacingMode(_ mode: MenuBarPresentationMode) -> MenuBarPresentationSnapshot {
        MenuBarPresentationSnapshot(
            mode: mode,
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
}

enum MenuBarPresentationResolver {
    static func resolve(
        mode: MenuBarPresentationMode,
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
            displayMode: .independent,
            interactionWorkspaceID: state.currentWorkspaceID,
            displays: displayItems
        )
    }

    static func preview(
        mode: MenuBarPresentationMode,
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
        availableWidth: CGFloat
    ) -> MenuBarFullStripLayout {
        let budget = max(120, availableWidth)
        let fullGroups = displays.map {
            MenuBarFullStripDisplayGroup(
                display: $0,
                visibleWorkspaces: $0.workspaces,
                hiddenWorkspaces: []
            )
        }
        let fullWidth = estimatedWidth(groups: fullGroups, style: .full, hasOverflow: false)
        if fullWidth <= budget {
            return MenuBarFullStripLayout(
                groups: fullGroups,
                labelStyle: .full,
                estimatedWidth: fullWidth
            )
        }

        let compactWidth = estimatedWidth(groups: fullGroups, style: .compact, hasOverflow: false)
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
            if estimatedWidth(groups: proposedGroups, style: .compact, hasOverflow: true) <= budget {
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
                hasOverflow: reducedGroups.contains { !$0.hiddenWorkspaces.isEmpty }
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
        hasOverflow: Bool
    ) -> CGFloat {
        let groupWidths = groups.map { group -> CGFloat in
            let workspaces = group.visibleWorkspaces.reduce(CGFloat(0)) { result, workspace in
                result + workspaceWidth(workspace, style: style) + MenuBarVisualTokens.workspaceSpacing
            }
            return MenuBarVisualTokens.displayIconWidth + MenuBarVisualTokens.displayWorkspaceGap + workspaces
        }
        let dividers = CGFloat(max(0, groups.count - 1)) * MenuBarVisualTokens.groupDividerWidth
        let overflow = hasOverflow ? MenuBarVisualTokens.overflowWidth : 0
        return groupWidths.reduce(0, +) + dividers + overflow + 8
    }

    private static func workspaceWidth(
        _ workspace: MenuBarWorkspaceItem,
        style: MenuBarFullStripLabelStyle
    ) -> CGFloat {
        let label = style == .full ? workspace.name : workspace.compactName
        let measured = CGFloat(label.count) * 6.3 + 12
        return min(MenuBarVisualTokens.maximumWorkspaceButtonWidth, max(22, measured))
    }
}

enum MenuBarVisualTokens {
    static let componentHeight: CGFloat = 18
    static let appGlyphWidth: CGFloat = 18
    static let displayIconWidth: CGFloat = 16
    static let workspaceSpacing: CGFloat = 2
    static let displayWorkspaceGap: CGFloat = 3
    static let groupDividerWidth: CGFloat = 9
    static let overflowWidth: CGFloat = 32
    static let maximumWorkspaceButtonWidth: CGFloat = 72
    static let compactCornerRadius: CGFloat = 4
    static let chipCornerRadius: CGFloat = 5
    static let separatorHeight: CGFloat = 12
}

struct MenuBarPrimaryStatusView: View {
    let snapshot: MenuBarPresentationSnapshot

    var body: some View {
        HStack(spacing: snapshot.mode == .compact ? 4 : 5) {
            appGlyph
            if snapshot.mode != .full {
                separator
                ForEach(snapshot.displays) { display in
                    switch snapshot.mode {
                    case .compact:
                        CompactDisplaySignal(display: display)
                    case .medium:
                        MediumDisplayChip(display: display)
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
        Image(systemName: "rectangle.on.rectangle")
            .font(.system(size: 11.5, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .frame(
                width: MenuBarVisualTokens.appGlyphWidth,
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

private struct CompactDisplaySignal: View {
    let display: MenuBarDisplayItem

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                Image(systemName: display.iconKind.systemImage)
                    .font(.system(size: 8.5, weight: .medium))
                Text(display.activeWorkspaceCompactName)
                    .font(.system(size: 10, weight: display.isInteractionDisplay ? .semibold : .medium))
                    .lineLimit(1)
                    .frame(maxWidth: 28)
            }
            Circle()
                .fill(display.isInteractionDisplay ? Color.accentColor : Color.primary.opacity(0.38))
                .frame(
                    width: display.isInteractionDisplay ? 3.5 : 3,
                    height: display.isInteractionDisplay ? 3.5 : 3
                )
        }
        .foregroundStyle(display.isInteractionDisplay ? .primary : .secondary)
        .accessibilityHidden(true)
        .help(display.accessibilityLabel)
    }
}

private struct MediumDisplayChip: View {
    let display: MenuBarDisplayItem

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: display.iconKind.systemImage)
                .font(.system(size: 9.5, weight: .semibold))
            Text(display.activeWorkspaceName)
                .font(.system(size: 10.5, weight: display.isInteractionDisplay ? .semibold : .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 70)
        }
        .foregroundStyle(display.isInteractionDisplay ? Color.white : Color.primary)
        .padding(.horizontal, 6)
        .frame(height: MenuBarVisualTokens.componentHeight)
        .background(
            RoundedRectangle(cornerRadius: MenuBarVisualTokens.chipCornerRadius)
                .fill(display.isInteractionDisplay
                    ? Color.accentColor.opacity(0.82)
                    : Color.primary.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MenuBarVisualTokens.chipCornerRadius)
                .stroke(Color.primary.opacity(display.isInteractionDisplay ? 0.10 : 0.12), lineWidth: 0.5)
        )
        .accessibilityHidden(true)
        .help(display.accessibilityLabel)
    }
}

struct MenuBarSettingsPreview: View {
    let snapshot: MenuBarPresentationSnapshot

    var body: some View {
        Group {
            if snapshot.mode == .full {
                MenuBarFullStripRepresentable(
                    snapshot: snapshot,
                    availableWidth: MenuBarPressurePolicy.defaultAvailableWidth
                )
                .fixedSize()
            } else {
                MenuBarPrimaryStatusView(snapshot: snapshot)
            }
        }
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
}

struct MenuBarFullStripRepresentable: NSViewRepresentable {
    let snapshot: MenuBarPresentationSnapshot
    let availableWidth: CGFloat

    func makeNSView(context: Context) -> MenuBarFullStripView {
        MenuBarFullStripView(
            snapshot: snapshot,
            availableWidth: availableWidth,
            workspaceAction: nil
        )
    }

    func updateNSView(_ nsView: MenuBarFullStripView, context: Context) {
        nsView.configure(
            snapshot: snapshot,
            availableWidth: availableWidth,
            workspaceAction: nil
        )
    }
}

@MainActor
final class MenuBarFullStripView: NSView {
    private(set) var layout: MenuBarFullStripLayout
    private var workspaceAction: ((MenuBarHitTarget) -> Void)?

    init(
        snapshot: MenuBarPresentationSnapshot,
        availableWidth: CGFloat,
        workspaceAction: ((MenuBarHitTarget) -> Void)?
    ) {
        layout = MenuBarPressurePolicy.layout(
            displays: snapshot.displays,
            availableWidth: availableWidth
        )
        self.workspaceAction = workspaceAction
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        configure(snapshot: snapshot, availableWidth: availableWidth, workspaceAction: workspaceAction)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configure(
        snapshot: MenuBarPresentationSnapshot,
        availableWidth: CGFloat,
        workspaceAction: ((MenuBarHitTarget) -> Void)?
    ) {
        self.workspaceAction = workspaceAction
        layout = MenuBarPressurePolicy.layout(
            displays: snapshot.displays,
            availableWidth: availableWidth
        )
        subviews.forEach { $0.removeFromSuperview() }

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        for (index, group) in layout.groups.enumerated() {
            if index > 0 { stack.addArrangedSubview(makeDivider()) }
            stack.addArrangedSubview(makeDisplayGroup(group))
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
        frame.size = CGSize(width: ceil(stack.fittingSize.width + 6), height: MenuBarVisualTokens.componentHeight)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("WindowManager display workspace strip")
    }

    private func makeDisplayGroup(_ group: MenuBarFullStripDisplayGroup) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = MenuBarVisualTokens.workspaceSpacing

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: group.display.iconKind.systemImage, accessibilityDescription: nil)
        icon.contentTintColor = group.display.isInteractionDisplay
            ? .controlAccentColor : .secondaryLabelColor
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        icon.toolTip = group.display.accessibilityLabel
        icon.setAccessibilityLabel(group.display.accessibilityLabel)
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: MenuBarVisualTokens.displayIconWidth),
            icon.heightAnchor.constraint(equalToConstant: MenuBarVisualTokens.componentHeight),
        ])
        stack.addArrangedSubview(icon)

        for workspace in group.visibleWorkspaces {
            let button = MenuBarWorkspaceButton(
                workspace: workspace,
                display: group.display,
                labelStyle: layout.labelStyle
            )
            button.onClick = { [weak self] in
                self?.workspaceAction?(.workspace(
                    workspaceID: workspace.id,
                    displayIdentifier: group.display.id
                ))
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
    var onClick: (() -> Void)?

    init(
        workspace: MenuBarWorkspaceItem,
        display: MenuBarDisplayItem,
        labelStyle: MenuBarFullStripLabelStyle
    ) {
        super.init(frame: .zero)
        title = labelStyle == .full ? workspace.name : workspace.compactName
        target = self
        action = #selector(clicked)
        isBordered = false
        bezelStyle = .regularSquare
        font = .systemFont(
            ofSize: 10.5,
            weight: workspace.isInteractionWorkspace ? .semibold : (workspace.isActive ? .medium : .regular)
        )
        contentTintColor = workspace.isInteractionWorkspace ? .white : .labelColor
        toolTip = "\(display.name) — workspace \(workspace.name)"
        setAccessibilityLabel("\(workspace.accessibilityLabel), \(display.name)")
        setAccessibilityHelp("Switches \(display.name) to workspace \(workspace.name)")
        focusRingType = .none
        cell?.lineBreakMode = .byTruncatingTail
        wantsLayer = true
        layer?.cornerRadius = MenuBarVisualTokens.compactCornerRadius
        if workspace.isInteractionWorkspace {
            layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        } else if workspace.isActive {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
            layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.72).cgColor
            layer?.borderWidth = 1
        } else {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.055).cgColor
        }
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: 22),
            widthAnchor.constraint(lessThanOrEqualToConstant: MenuBarVisualTokens.maximumWorkspaceButtonWidth),
            heightAnchor.constraint(equalToConstant: MenuBarVisualTokens.componentHeight),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    @objc private func clicked() { onClick?() }
}
