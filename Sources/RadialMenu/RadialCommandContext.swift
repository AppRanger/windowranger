import CoreGraphics
import Foundation

enum RadialCommandCapability: Hashable, Sendable {
    case cycleWorkspace
    case previousWorkspace
    case setLayout
    case toggleFloating
    case moveFocusedWindow
    case resetCurrentWorkspace
    case focusDirection
    case moveWindowDirection
    case smartResize
    case moveWorkspaceToDisplay

    static let current: Set<RadialCommandCapability> = [
        .cycleWorkspace,
        .previousWorkspace,
        .setLayout,
        .toggleFloating,
        .moveFocusedWindow,
        .resetCurrentWorkspace,
        .focusDirection,
        .moveWindowDirection,
        .smartResize,
        .moveWorkspaceToDisplay,
    ]
}

enum RadialFocusedWindowLayoutState: String, Equatable, Sendable {
    case managed
    case explicitlyManaged = "explicitly-managed"
    case floating
    case automaticallyFloatingDialog = "automatic-dialog"
    case automaticallyFloatingSecondary = "automatic-secondary"
    case appRuleExcluded = "app-rule-excluded"
}

enum RadialFocusSource: String, Equatable, Sendable {
    case focusedManagedWindow = "focused-managed-window"
    case preservedManagedAnchor = "preserved-managed-anchor"
    case none
}

struct RadialFocusedWindowContext: Equatable, Sendable {
    let processIdentifier: pid_t
    let windowIdentifier: CGWindowID
    let workspaceID: UUID
    let frame: WindowFrame?
    let layoutState: RadialFocusedWindowLayoutState
    let isAutomaticallyFloatingDialog: Bool
    let isAppRuleExcluded: Bool
    let keepsOnAllWorkspaces: Bool
}

struct RadialWorkspaceOption: Equatable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let key: String
    let layout: WorkspaceLayout
    let homeDisplayIdentifier: String
}

struct RadialDisplayOption: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let isMain: Bool
}

struct RadialProfileOption: Equatable, Sendable, Identifiable {
    let id: UUID
    let name: String
}

struct RadialCommandContext: Equatable, Sendable {
    let focusedWindow: RadialFocusedWindowContext?
    let focusSource: RadialFocusSource
    let workspaceID: UUID
    let workspaceName: String
    let layout: WorkspaceLayout
    let displayIdentifier: String
    let displayName: String
    let displayBounds: CGRect
    let displayMode: MultiDisplayMode
    let focusFollowsMovedWindow: Bool
    let connectedDisplayIdentifiers: [String]
    let connectedDisplays: [RadialDisplayOption]
    let availableFocusDirections: Set<WindowDirection>
    let availableMoveDirections: Set<WindowDirection>
    let canSmartResize: Bool
    let workspaces: [RadialWorkspaceOption]
    let supportedCommands: Set<RadialCommandCapability>
    let validationToken: String
    var profiles: [RadialProfileOption] = []
    var activeProfileID: UUID? = nil
    var isProfileManuallyPinned = false
    var tiledPlacementPreviews: [TiledPlacementPreview] = []
    var freeformPlacementPreviews: [FreeformPlacementPreview] = []
    /// Global context that lives outside WorkspaceEngine (currently the profile catalogue and
    /// activation state). It is deliberately separate from `validationToken`: tiled placement
    /// commits must continue passing the engine-owned token unchanged.
    var externalValidationToken = ""

    var sessionValidationToken: String {
        externalValidationToken.isEmpty
            ? validationToken
            : "\(validationToken)|external:\(externalValidationToken)"
    }
}

/// The only durable item reference in the wheel definition. Providers own their dynamic child
/// actions, so a future command family can be added without changing the renderer or editor.
struct RadialTopLevelItemID: RawRepresentable, Codable, Hashable, Identifiable, Sendable {
    let rawValue: String
    var id: String { rawValue }

    init(rawValue: String) { self.rawValue = rawValue }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static let moveToSpace = Self(rawValue: "move-to-space")
    static let resize = Self(rawValue: "resize")
    static let goToSpace = Self(rawValue: "go-to-space")
    static let nextSpace = Self(rawValue: "next-space")
    static let previousSpace = Self(rawValue: "previous-space")
    static let profiles = Self(rawValue: "profiles")
    static let resetWindowsInSpace = Self(rawValue: "reset-windows-in-space")
    static let resetAllWindows = Self(rawValue: "reset-all-windows")
    static let layoutType = Self(rawValue: "layout-type")

    static let allKnown: [Self] = [
        .moveToSpace, .resize, .goToSpace, .nextSpace, .previousSpace,
        .profiles, .resetWindowsInSpace, .resetAllWindows, .layoutType,
    ]
}

struct RadialWheelDefinition: Codable, Equatable, Sendable {
    static let currentVersion = 2

    var version: Int
    var items: [RadialTopLevelItemID]
    var unresolvedItemIDs: [String]

    init(
        version: Int = currentVersion,
        items: [RadialTopLevelItemID],
        unresolvedItemIDs: [String] = []
    ) {
        self.version = version
        self.items = items
        self.unresolvedItemIDs = unresolvedItemIDs
    }

    static let builtInDefault = Self(items: RadialTopLevelItemID.allKnown)
    static let minimalFallback = Self(items: [.goToSpace, .nextSpace, .previousSpace, .layoutType])
    static let spatial = Self(items: [.resize])

    var hasUnresolvedReferences: Bool {
        version != Self.currentVersion || !unresolvedItemIDs.isEmpty ||
            Set(items).count != items.count || items.contains { !RadialCommandCatalogue.knownItemIDs.contains($0) }
    }

    func repaired() -> Self {
        var seen = Set<RadialTopLevelItemID>()
        var repairedItems: [RadialTopLevelItemID] = []
        for item in items {
            guard RadialCommandCatalogue.knownItemIDs.contains(item), seen.insert(item).inserted else { continue }
            repairedItems.append(item)
        }
        return repairedItems.isEmpty ? .minimalFallback : Self(items: repairedItems)
    }

    mutating func add(_ item: RadialTopLevelItemID) -> Bool {
        guard RadialCommandCatalogue.knownItemIDs.contains(item), !items.contains(item) else { return false }
        items.append(item)
        version = Self.currentVersion
        unresolvedItemIDs = []
        return true
    }

    mutating func removeItem(id: RadialTopLevelItemID) -> Bool {
        guard let index = items.firstIndex(of: id) else { return false }
        items.remove(at: index)
        return true
    }

    mutating func moveItem(id: RadialTopLevelItemID, offset: Int) -> Bool {
        guard let index = items.firstIndex(of: id), !items.isEmpty else { return false }
        let destination = min(max(index + offset, 0), items.count - 1)
        guard destination != index else { return false }
        let item = items.remove(at: index)
        items.insert(item, at: destination)
        return true
    }

    private enum CodingKeys: String, CodingKey { case version, items, unresolvedItemIDs }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = (try? values.decode(Int.self, forKey: .version)) ?? 1
        if decodedVersion >= Self.currentVersion,
           let decodedItems = try? values.decode([RadialTopLevelItemID].self, forKey: .items) {
            version = decodedVersion
            items = decodedItems
            unresolvedItemIDs = (try? values.decode([String].self, forKey: .unresolvedItemIDs)) ?? []
            return
        }

        let legacy = (try? values.decode([LegacyRadialWheelDefinitionItem].self, forKey: .items)) ?? []
        let migrated = Self.migrateLegacy(legacy)
        version = Self.currentVersion
        items = migrated.items
        unresolvedItemIDs = migrated.unresolved
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(Self.currentVersion, forKey: .version)
        try values.encode(items, forKey: .items)
        if !unresolvedItemIDs.isEmpty {
            try values.encode(unresolvedItemIDs, forKey: .unresolvedItemIDs)
        }
    }

    private static func migrateLegacy(
        _ legacy: [LegacyRadialWheelDefinitionItem]
    ) -> (items: [RadialTopLevelItemID], unresolved: [String]) {
        let legacyIDs = Set(legacy.map(\.id))
        let oldDefaultMarkers: Set<String> = ["group.workspace", "group.layout", "group.resize", "group.move-window"]
        if oldDefaultMarkers.isSubset(of: legacyIDs) {
            return (builtInDefault.items, [])
        }

        var result: [RadialTopLevelItemID] = []
        var unresolved: [String] = []
        func add(_ item: RadialTopLevelItemID) {
            if !result.contains(item) { result.append(item) }
        }
        for item in legacy {
            var recognized = true
            switch item.id {
            case "group.move-window": add(.moveToSpace)
            case "group.resize": add(.resize)
            case "group.layout": add(.layoutType)
            case "group.workspace":
                add(.goToSpace); add(.nextSpace); add(.previousSpace); add(.resetWindowsInSpace)
            case "direct.reset-workspace": add(.resetWindowsInSpace)
            case "direct.floating": add(.resize)
            default:
                recognized = false
                let commands = ([item.command].compactMap { $0 } + item.children)
                for command in commands {
                    switch command {
                    case "window.move", "window.move-and-follow": add(.moveToSpace); recognized = true
                    case "resize.smaller", "resize.larger", "window.toggle-floating": add(.resize); recognized = true
                    case "layout.freeform", "layout.tiled", "layout.accordion": add(.layoutType); recognized = true
                    case "workspace.next": add(.nextSpace); recognized = true
                    case "workspace.previous", "workspace.back-and-forth": add(.previousSpace); recognized = true
                    case "workspace.reset": add(.resetWindowsInSpace); recognized = true
                    default: break
                    }
                }
            }
            if !recognized { unresolved.append(item.id) }
        }
        return (result.isEmpty ? minimalFallback.items : result, unresolved)
    }
}

private struct LegacyRadialWheelDefinitionItem: Decodable {
    let id: String
    let command: String?
    let children: [String]

    private enum CodingKeys: String, CodingKey { case id, command, children }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? values.decode(String.self, forKey: .id)) ?? ""
        command = try? values.decode(String.self, forKey: .command)
        children = (try? values.decode([String].self, forKey: .children)) ?? []
    }
}

struct RadialCommandMetadata: Equatable, Identifiable, Sendable {
    let reference: RadialTopLevelItemID
    let title: String
    let systemImage: String
    var id: String { reference.rawValue }
}

enum RadialMenuChildGeometry: String, Equatable, Sendable {
    case equalCircle = "equal-circle"
    case compass
}

struct RadialMenuItem: Equatable, Identifiable, Sendable {
    let id: String
    let definitionID: String
    let label: String
    let detail: String?
    let systemImage: String
    let command: WindowManagerCommand?
    let alternateCommand: WindowManagerCommand?
    let children: [RadialMenuItem]
    let childGeometry: RadialMenuChildGeometry
    let isCurrent: Bool
    let placementPreview: TiledPlacementPreview?
    let freeformPlacementPreview: FreeformPlacementPreview?

    var isGroup: Bool { !children.isEmpty }
    var isSubmenu: Bool { !children.isEmpty }
}

struct RadialMenuModel: Equatable, Sendable {
    let title: String
    let subtitle: String
    let stateNote: String?
    let items: [RadialMenuItem]
    let validationToken: String
    let definitionVersion: Int
    let usedFallbackDefinition: Bool
    let omittedDefinitionItemIDs: [String]
}

enum RadialCommandCatalogue {
    enum SymbolName {
        static let moveToSpace = "windowranger.move-to-space"
        static let placeWindow = "windowranger.place-window"
        static let goToSpace = "windowranger.go-to-space"
        static let resetWindowsInSpace = "windowranger.reset-windows-in-space"
    }

    static let knownItemIDs = Set(RadialTopLevelItemID.allKnown)
    static let allMetadata = RadialTopLevelItemID.allKnown.compactMap(metadata)

    static func availableMetadata(excluding references: [RadialTopLevelItemID]) -> [RadialCommandMetadata] {
        let existing = Set(references)
        return allMetadata.filter { !existing.contains($0.reference) }
    }

    /// Representative symbols for the non-interactive Settings preview. Runtime children still
    /// come exclusively from providers and the captured context; this never becomes saved data.
    static func previewChildSystemImages(for reference: RadialTopLevelItemID) -> [String] {
        switch reference {
        case .moveToSpace, .goToSpace: ["1.square", "2.square", "3.square", "4.square"]
        case .resize: VisualPlacement.compassOrder.map(\.systemImage)
        case .profiles: ["1.circle", "2.circle", "arrow.triangle.2.circlepath"]
        case .layoutType: WorkspaceLayout.allCases.map(\.systemImage)
        default: []
        }
    }

    static func metadata(for reference: RadialTopLevelItemID) -> RadialCommandMetadata? {
        switch reference {
        case .moveToSpace: .init(
            reference: reference,
            title: "Move to Space",
            systemImage: SymbolName.moveToSpace
        )
        case .resize: .init(reference: reference, title: "Resize", systemImage: SymbolName.placeWindow)
        case .goToSpace: .init(reference: reference, title: "Go to Space", systemImage: SymbolName.goToSpace)
        case .nextSpace: .init(reference: reference, title: "Next Space", systemImage: "arrow.right")
        case .previousSpace: .init(reference: reference, title: "Previous Space", systemImage: "arrow.left")
        case .profiles: .init(reference: reference, title: "Profiles", systemImage: "rectangle.stack.badge.person.crop")
        case .resetWindowsInSpace: .init(
            reference: reference,
            title: "Reset Windows in Space",
            systemImage: SymbolName.resetWindowsInSpace
        )
        case .resetAllWindows: .init(reference: reference, title: "Reset All Windows", systemImage: "arrow.trianglehead.2.counterclockwise")
        case .layoutType: .init(reference: reference, title: "Layout Type", systemImage: "rectangle.split.3x1")
        default: nil
        }
    }

    static func resolve(_ reference: RadialTopLevelItemID, context: RadialCommandContext) -> RadialMenuItem? {
        guard let metadata = metadata(for: reference) else { return nil }
        func item(
            _ id: String,
            _ label: String,
            _ image: String,
            _ command: WindowManagerCommand?,
            detail: String? = nil,
            alternate: WindowManagerCommand? = nil,
            children: [RadialMenuItem] = [],
            geometry: RadialMenuChildGeometry = .equalCircle,
            current: Bool = false,
            preview: TiledPlacementPreview? = nil,
            freeformPreview: FreeformPlacementPreview? = nil
        ) -> RadialMenuItem {
            RadialMenuItem(
                id: id,
                definitionID: reference.rawValue,
                label: label,
                detail: detail,
                systemImage: image,
                command: command,
                alternateCommand: alternate,
                children: children,
                childGeometry: geometry,
                isCurrent: current,
                placementPreview: preview,
                freeformPlacementPreview: freeformPreview
            )
        }
        let participatesInLayout = context.focusedWindow.map {
            !$0.isAppRuleExcluded && ($0.layoutState == .managed || $0.layoutState == .explicitlyManaged)
        } ?? false

        switch reference {
        case .moveToSpace:
            guard context.supportedCommands.contains(.moveFocusedWindow),
                  let window = context.focusedWindow,
                  !window.keepsOnAllWorkspaces
            else { return nil }
            let children = context.workspaces.compactMap { workspace -> RadialMenuItem? in
                guard workspace.id != window.workspaceID,
                      context.displayMode == .unified ||
                        workspace.homeDisplayIdentifier == context.displayIdentifier
                else { return nil }
                return item(
                    "move-space-\(workspace.id.uuidString)", workspace.name,
                    workspaceSystemImage(for: workspace), .moveFocusedWindow(workspace.id),
                    alternate: .moveFocusedWindowAndFollow(workspace.id)
                )
            }
            guard !children.isEmpty else { return nil }
            return item(reference.rawValue, metadata.title, metadata.systemImage, nil, children: children)
        case .resize:
            guard let window = context.focusedWindow,
                  !window.isAppRuleExcluded,
                  context.supportedCommands.contains(.toggleFloating)
            else { return nil }
            switch window.layoutState {
            case .floating:
                return item(reference.rawValue, "Return to Layout", "rectangle.grid.2x2", .toggleFloating)
            case .automaticallyFloatingDialog, .automaticallyFloatingSecondary:
                return item(reference.rawValue, "Include in Layout", "rectangle.grid.2x2", .toggleFloating)
            case .managed, .explicitlyManaged:
                if context.layout == .none, participatesInLayout {
                    let children = context.freeformPlacementPreviews.map { preview in
                        item(
                            "freeform-place-\(preview.placement.rawValue)", preview.placement.title,
                            preview.placement.systemImage,
                            .placeFreeformWindow(
                                preview.placement,
                                validationToken: context.validationToken
                            ),
                            freeformPreview: preview
                        )
                    }
                    guard !children.isEmpty else { return nil }
                    return item(
                        reference.rawValue, "Place Window", metadata.systemImage, nil,
                        children: children, geometry: .compass
                    )
                }
                if context.layout == .tiled, participatesInLayout {
                    let children = context.tiledPlacementPreviews.map { preview in
                        item(
                            "place-\(preview.placement.rawValue)", preview.placement.title,
                            preview.placement.systemImage,
                            .placeTiledWindow(preview.placement, validationToken: context.validationToken),
                            preview: preview
                        )
                    }
                    guard !children.isEmpty else { return nil }
                    return item(
                        reference.rawValue, "Place Window", metadata.systemImage, nil,
                        children: children, geometry: .compass
                    )
                }
                if context.layout == .accordion, participatesInLayout,
                   context.supportedCommands.contains(.smartResize), context.canSmartResize {
                    return item(reference.rawValue, metadata.title, metadata.systemImage, nil, children: [
                        item("resize-smaller", "Smaller", "minus", .smartResize(-50)),
                        item("resize-larger", "Larger", "plus", .smartResize(50)),
                    ])
                }
                return nil
            case .appRuleExcluded:
                return nil
            }
        case .goToSpace:
            guard context.supportedCommands.contains(.cycleWorkspace), !context.workspaces.isEmpty else { return nil }
            let children = context.workspaces.compactMap { workspace -> RadialMenuItem? in
                guard workspace.id != context.workspaceID else { return nil }
                return item(
                    "go-space-\(workspace.id.uuidString)",
                    workspace.name,
                    workspaceSystemImage(for: workspace),
                    .switchWorkspace(workspace.id)
                )
            }
            guard !children.isEmpty else { return nil }
            return item(
                reference.rawValue,
                metadata.title,
                metadata.systemImage,
                nil,
                detail: "\(context.workspaceName) active",
                children: children
            )
        case .nextSpace:
            guard context.supportedCommands.contains(.cycleWorkspace) else { return nil }
            return item(reference.rawValue, metadata.title, metadata.systemImage, .cycleWorkspace(1))
        case .previousSpace:
            guard context.supportedCommands.contains(.cycleWorkspace) else { return nil }
            return item(reference.rawValue, metadata.title, metadata.systemImage, .cycleWorkspace(-1))
        case .profiles:
            guard !context.profiles.isEmpty else { return nil }
            let activeName = context.profiles.first { $0.id == context.activeProfileID }?.name
            var children = context.profiles.enumerated().compactMap { position, profile -> RadialMenuItem? in
                guard profile.id != context.activeProfileID else { return nil }
                return item(
                    "profile-\(profile.id.uuidString)",
                    profile.name,
                    profileSystemImage(at: position),
                    .selectProfile(profile.id)
                )
            }
            if context.isProfileManuallyPinned {
                children.append(item(
                    "profile-resume-automatic", "Resume Automatic", "arrow.triangle.2.circlepath",
                    .resumeAutomaticProfileSelection
                ))
            }
            guard !children.isEmpty else { return nil }
            return item(
                reference.rawValue,
                metadata.title,
                metadata.systemImage,
                nil,
                detail: activeName.map { "\($0) active" },
                children: children
            )
        case .resetWindowsInSpace:
            guard context.supportedCommands.contains(.resetCurrentWorkspace) else { return nil }
            return item(reference.rawValue, metadata.title, metadata.systemImage, .resetCurrentWorkspace)
        case .resetAllWindows:
            guard context.supportedCommands.contains(.resetCurrentWorkspace) else { return nil }
            return item(reference.rawValue, metadata.title, metadata.systemImage, .resetAllWindows)
        case .layoutType:
            guard context.supportedCommands.contains(.setLayout) else { return nil }
            let children = WorkspaceLayout.allCases.map { layout in
                let current = layout == context.layout
                return item(
                    "layout-\(layout.rawValue)",
                    layout.title,
                    layout.systemImage,
                    .setLayout(layout),
                    detail: current ? "Current layout · select to reapply" : nil,
                    current: current
                )
            }
            return item(
                reference.rawValue,
                metadata.title,
                context.layout.systemImage,
                .cycleLayout(1),
                children: children
            )
        default:
            return nil
        }
    }

    /// The pointer-facing spatial surface is deliberately narrower than the searchable command
    /// catalogue. It exposes only the generated Freeform or Tiled placement proposals; layout
    /// switching, floating toggles, and Accordion resize remain ordinary palette commands.
    static func resolveSpatialPlacement(context: RadialCommandContext) -> RadialMenuItem? {
        guard let resolved = resolve(.resize, context: context) else { return nil }
        let placementChildren: [(VisualPlacement, RadialMenuItem)] = resolved.children.compactMap { child in
            guard let placement = child.placementPreview?.placement ?? child.freeformPlacementPreview?.placement,
                  let command = child.command
            else { return nil }
            switch command {
            case .placeTiledWindow, .placeFreeformWindow:
                return (placement, child)
            default:
                return nil
            }
        }
        let childrenByPlacement = Dictionary(uniqueKeysWithValues: placementChildren)
        let children = VisualPlacement.compassOrder.compactMap { childrenByPlacement[$0] }
        guard !children.isEmpty else { return nil }
        return RadialMenuItem(
            id: RadialTopLevelItemID.resize.rawValue,
            definitionID: RadialTopLevelItemID.resize.rawValue,
            label: "Place Window",
            detail: nil,
            systemImage: SymbolName.placeWindow,
            command: nil,
            alternateCommand: nil,
            children: children,
            childGeometry: .compass,
            isCurrent: false,
            placementPreview: nil,
            freeformPlacementPreview: nil
        )
    }

    private static func workspaceSystemImage(for workspace: RadialWorkspaceOption) -> String {
        let key = workspace.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard key.count == 1,
              key.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) })
        else { return "square.grid.2x2" }
        return "\(key).square"
    }

    private static func profileSystemImage(at position: Int) -> String {
        guard (0..<9).contains(position) else { return "rectangle.stack.person.crop" }
        return "\(position + 1).circle"
    }
}

enum RadialCommandContextBuilder {
    static func build(
        from context: RadialCommandContext,
        definition: RadialWheelDefinition = .builtInDefault
    ) -> RadialMenuModel {
        let structurallyUsable = definition.version == RadialWheelDefinition.currentVersion &&
            !definition.items.isEmpty && !definition.hasUnresolvedReferences
        let effective = structurallyUsable ? definition : definition.repaired()
        var seen = Set<RadialTopLevelItemID>()
        var resolved: [RadialMenuItem] = []
        var omitted: [String] = []
        let isSpatialPlacementDefinition = effective == .spatial
        for reference in effective.items where seen.insert(reference).inserted {
            let candidate = isSpatialPlacementDefinition && reference == .resize
                ? RadialCommandCatalogue.resolveSpatialPlacement(context: context)
                : RadialCommandCatalogue.resolve(reference, context: context)
            guard let item = candidate,
                  item.command != nil || !item.children.isEmpty
            else {
                omitted.append(reference.rawValue)
                continue
            }
            if isSpatialPlacementDefinition {
                resolved.append(contentsOf: item.children)
            } else {
                resolved.append(item)
            }
        }

        var note: String?
        if let window = context.focusedWindow {
            if window.isAppRuleExcluded || window.layoutState == .appRuleExcluded {
                note = "Layout controlled by App Rule"
            } else if window.keepsOnAllWorkspaces {
                note = "Visible on every workspace"
            } else if window.layoutState == .automaticallyFloatingDialog {
                note = "Dialog floats automatically"
            } else if window.layoutState == .automaticallyFloatingSecondary {
                note = "Secondary window floats by App Rule"
            }
        }
        return RadialMenuModel(
            title: context.workspaceName,
            subtitle: "\(context.layout.title) · \(context.displayName)",
            stateNote: note,
            items: resolved,
            validationToken: context.sessionValidationToken,
            definitionVersion: effective.version,
            usedFallbackDefinition: !structurallyUsable,
            omittedDefinitionItemIDs: omitted
        )
    }
}

extension WorkspaceLayout {
    var systemImage: String {
        switch self {
        case .none: "macwindow"
        case .tiled: "rectangle.grid.2x2"
        case .accordion: "rectangle.split.3x1"
        }
    }
}

enum RadialMenuGeometry {
    enum Ring: String, Equatable, Sendable { case inner, outer }

    struct Selection: Equatable, Sendable {
        let ring: Ring
        let index: Int
    }

    struct PointerState: Equatable, Sendable {
        private(set) var selection: Selection?

        mutating func update(
            point: CGPoint,
            center: CGPoint,
            innerItemCount: Int,
            outerItemCount: Int,
            activeGroupIndex: Int?,
            outerGeometry: RadialMenuChildGeometry = .equalCircle
        ) -> Selection? {
            let dx = point.x - center.x
            let dy = point.y - center.y
            let distance = hypot(dx, dy)
            guard distance >= centerDeadZone, distance <= outerRadius else {
                selection = nil
                return nil
            }

            let prior = selection
            let prefersInner = prior?.ring == .inner && distance <= innerOuterRadius + ringHysteresis
            let prefersOuter = prior?.ring == .outer && distance >= outerInnerRadius - ringHysteresis
            if distance <= innerOuterRadius || prefersInner {
                guard let index = hystereticItemIndex(
                    for: point,
                    center: center,
                    itemCount: innerItemCount,
                    previousIndex: prior?.ring == .inner ? prior?.index : nil
                ) else {
                    selection = nil
                    return nil
                }
                selection = Selection(ring: .inner, index: index)
                return selection
            }
            if (distance >= outerInnerRadius || prefersOuter), let activeGroupIndex,
               let index = outerItemIndex(
                    for: point,
                    center: center,
                    parentIndex: activeGroupIndex,
                    parentCount: innerItemCount,
                    childCount: outerItemCount,
                    previousIndex: prior?.ring == .outer ? prior?.index : nil,
                    geometry: outerGeometry
               ) {
                selection = Selection(ring: .outer, index: index)
                return selection
            }
            selection = nil
            return nil
        }

        mutating func reset() { selection = nil }
    }

    static let centerDeadZone: CGFloat = 58
    static let innerOuterRadius: CGFloat = 132
    static let outerInnerRadius: CGFloat = 144
    static let outerRadius: CGFloat = 210
    static let innerItemRadius: CGFloat = 95
    static let outerItemRadius: CGFloat = 177
    static let ringHysteresis: CGFloat = 9
    static let angularHysteresis: CGFloat = 0.075

    static func clampedCenter(
        preferred: CGPoint,
        panelSize: CGSize,
        within visibleFrame: CGRect,
        margin: CGFloat = 12
    ) -> CGPoint {
        let halfWidth = panelSize.width / 2
        let halfHeight = panelSize.height / 2
        let minimumX = visibleFrame.minX + halfWidth + margin
        let maximumX = visibleFrame.maxX - halfWidth - margin
        let minimumY = visibleFrame.minY + halfHeight + margin
        let maximumY = visibleFrame.maxY - halfHeight - margin
        return CGPoint(
            x: minimumX <= maximumX ? min(max(preferred.x, minimumX), maximumX) : visibleFrame.midX,
            y: minimumY <= maximumY ? min(max(preferred.y, minimumY), maximumY) : visibleFrame.midY
        )
    }

    /// Converts an Accessibility top-left-origin window frame to an AppKit global-screen center.
    /// AppKit and AX share global X, while Y is mirrored around the main screen's top edge even
    /// when the target window is on a display above, below, or to the left of the main display.
    static func appKitCenter(for frame: WindowFrame, mainScreenTop: CGFloat) -> CGPoint {
        CGPoint(
            x: frame.position.x + frame.size.width / 2,
            y: mainScreenTop - frame.position.y - frame.size.height / 2
        )
    }

    static func itemIndex(
        for point: CGPoint,
        center: CGPoint,
        itemCount: Int,
        deadZoneRadius: CGFloat,
        outerRadius: CGFloat
    ) -> Int? {
        guard itemCount > 0 else { return nil }
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = hypot(dx, dy)
        guard distance >= deadZoneRadius, distance <= outerRadius else { return nil }
        var angle = atan2(dy, dx) + (.pi / 2)
        if angle < 0 { angle += .pi * 2 }
        let segment = (.pi * 2) / CGFloat(itemCount)
        return min(itemCount - 1, Int((angle + segment / 2).truncatingRemainder(dividingBy: .pi * 2) / segment))
    }

    static func hystereticItemIndex(
        for point: CGPoint,
        center: CGPoint,
        itemCount: Int,
        previousIndex: Int?
    ) -> Int? {
        guard let proposed = itemIndex(
            for: point,
            center: center,
            itemCount: itemCount,
            deadZoneRadius: 0,
            outerRadius: .greatestFiniteMagnitude
        ) else { return nil }
        guard let previousIndex,
              previousIndex != proposed,
              (0..<itemCount).contains(previousIndex)
        else { return proposed }
        let angle = atan2(point.y - center.y, point.x - center.x)
        let previousAngle = CGFloat(previousIndex) * (.pi * 2 / CGFloat(itemCount)) - .pi / 2
        let halfSegment = .pi / CGFloat(itemCount)
        return angularDistance(angle, previousAngle) <= halfSegment + angularHysteresis
            ? previousIndex
            : proposed
    }

    static func itemAngle(index: Int, count: Int) -> CGFloat {
        guard count > 0 else { return -.pi / 2 }
        return CGFloat(index) * (.pi * 2 / CGFloat(count)) - .pi / 2
    }

    static func itemCenter(index: Int, count: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
        guard count > 0 else { return center }
        let angle = itemAngle(index: index, count: count)
        return CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }

    static func outerItemAngles(
        parentIndex: Int,
        parentCount: Int,
        childCount: Int,
        geometry: RadialMenuChildGeometry = .equalCircle
    ) -> [CGFloat] {
        guard parentCount > 0, childCount > 0 else { return [] }
        // Dynamic children always consume an equal 360-degree partition. Compass providers supply
        // their children in semantic clockwise order, so the same pure geometry retains meaning.
        // `parentIndex` remains in the API because selection correlation records the owning wedge.
        _ = parentIndex
        _ = geometry
        let fullCircle = CGFloat.pi * 2
        let angleStep = fullCircle / CGFloat(childCount)
        let startingAngle = -CGFloat.pi / 2
        return (0..<childCount).map { index -> CGFloat in
            CGFloat(index) * angleStep + startingAngle
        }
    }

    static func outerItemCenter(
        index: Int,
        parentIndex: Int,
        parentCount: Int,
        childCount: Int,
        center: CGPoint,
        radius: CGFloat = outerItemRadius,
        geometry: RadialMenuChildGeometry = .equalCircle
    ) -> CGPoint {
        let angles = outerItemAngles(
            parentIndex: parentIndex,
            parentCount: parentCount,
            childCount: childCount,
            geometry: geometry
        )
        guard angles.indices.contains(index) else { return center }
        return CGPoint(
            x: center.x + cos(angles[index]) * radius,
            y: center.y + sin(angles[index]) * radius
        )
    }

    static func outerItemIndex(
        for point: CGPoint,
        center: CGPoint,
        parentIndex: Int,
        parentCount: Int,
        childCount: Int,
        previousIndex: Int? = nil,
        geometry: RadialMenuChildGeometry = .equalCircle
    ) -> Int? {
        let angles = outerItemAngles(
            parentIndex: parentIndex,
            parentCount: parentCount,
            childCount: childCount,
            geometry: geometry
        )
        guard !angles.isEmpty else { return nil }
        let pointerAngle = atan2(point.y - center.y, point.x - center.x)
        let ranked = angles.enumerated().map { ($0.offset, angularDistance(pointerAngle, $0.element)) }
            .sorted { $0.1 < $1.1 }
        guard let closest = ranked.first else { return nil }
        let spacing = .pi * 2 / CGFloat(childCount)
        let acceptance = spacing / 2
        guard closest.1 <= acceptance else { return nil }
        if let previousIndex, previousIndex != closest.0, angles.indices.contains(previousIndex),
           angularDistance(pointerAngle, angles[previousIndex]) <= acceptance + angularHysteresis {
            return previousIndex
        }
        return closest.0
    }

    private static func angularDistance(_ lhs: CGFloat, _ rhs: CGFloat) -> CGFloat {
        let raw = abs(lhs - rhs).truncatingRemainder(dividingBy: .pi * 2)
        return min(raw, .pi * 2 - raw)
    }
}
