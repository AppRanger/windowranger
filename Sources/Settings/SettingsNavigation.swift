import Combine
import Foundation

enum SettingsCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case general
    case profiles
    case workspaces
    case displays
    case layouts
    case appRules
    case shortcuts
    case radialMenu
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .profiles: "Profiles"
        case .workspaces: "Workspaces"
        case .displays: "Displays"
        case .layouts: "Layouts"
        case .appRules: "App Rules"
        case .shortcuts: "Shortcuts"
        case .radialMenu: "Command Wheel"
        case .diagnostics: "Diagnostics"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .profiles: "person.crop.rectangle.stack"
        case .workspaces: "square.grid.3x3"
        case .displays: "display.2"
        case .layouts: "rectangle.3.group"
        case .appRules: "app.badge.checkmark"
        case .shortcuts: "keyboard"
        case .radialMenu: "circle.hexagongrid"
        case .diagnostics: "waveform.path.ecg"
        }
    }

    /// Displays and Layouts were separate destinations before workspace configuration was
    /// consolidated. Keep their raw values decodable for saved selection/deep links, but route
    /// both to the single Workspaces inspector.
    var canonicalDestination: SettingsCategory {
        switch self {
        case .displays, .layouts: .workspaces
        default: self
        }
    }
}

struct SettingsSearchEntry: Identifiable, Equatable, Sendable {
    let id: String
    let category: SettingsCategory
    let title: String
    let description: String
    let synonyms: [String]
    let debugOnly: Bool
    let workspaceID: UUID?

    init(
        id: String,
        category: SettingsCategory,
        title: String,
        description: String,
        synonyms: [String] = [],
        debugOnly: Bool = false,
        workspaceID: UUID? = nil
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.description = description
        self.synonyms = synonyms
        self.debugOnly = debugOnly
        self.workspaceID = workspaceID
    }

    func matches(_ query: String) -> Bool {
        let tokens = query
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !tokens.isEmpty else { return true }
        let haystack = ([title, description, category.title] + synonyms)
            .joined(separator: " ")
            .lowercased()
        let words = haystack
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        return tokens.allSatisfy { token in
            words.contains { word in word == token || word.hasPrefix(token) }
        }
    }
}

enum SettingsCatalog {
    static let entries: [SettingsSearchEntry] = [
        SettingsSearchEntry(id: "accessibility", category: .general, title: "Accessibility permission", description: "Allow WindowRanger to discover, move, resize, and focus windows.", synonyms: ["privacy", "grant access", "TCC"]),
        SettingsSearchEntry(id: "launch-at-login", category: .general, title: "Open at login", description: "Start WindowRanger automatically after signing in.", synonyms: ["startup", "login item"]),
        SettingsSearchEntry(id: "icloud", category: .general, title: "iCloud settings sync", description: "Sync named profile definitions and global preferences without syncing this Mac's active profile or monitor bindings.", synonyms: ["cloud", "sync", "local profile"]),
        SettingsSearchEntry(id: "menu-bar-presentation", category: .general, title: "Menu bar presentation", description: "Choose Compact, Medium, or Full display-aware workspace status.", synonyms: ["status item", "tray", "workspace indicator", "notch", "menu icon", "monitor chips", "full workspace strip"]),
        SettingsSearchEntry(id: "menu-bar-highlight", category: .general, title: "Menu bar highlight colour", description: "Choose the colour used to identify active workspaces and displays.", synonyms: ["accent", "color", "colour", "selected workspace", "status item"]),
        SettingsSearchEntry(id: "recovery", category: .general, title: "Bring windows back on screen", description: "Recover managed windows that were left parked or outside a connected display.", synonyms: ["rescue", "restore", "offscreen"]),
        SettingsSearchEntry(id: "focus-follows-move", category: .general, title: "Focus follows moved window", description: "Choose whether sending a window also opens its destination workspace and focuses it there.", synonyms: ["move and follow", "send only", "workspace move focus"]),
        SettingsSearchEntry(id: "auto-unhide-apps", category: .general, title: "Automatically unhide applications", description: "Opt in to unhiding a hidden app when WindowRanger explicitly focuses one of its managed windows.", synonyms: ["hidden apps", "compatibility", "CFG-13"]),
        SettingsSearchEntry(id: "profiles-current", category: .profiles, title: "Current profile", description: "Select a reusable configuration manually or return control to automatic profile selection.", synonyms: ["active profile", "manual pin", "automatic selection", "PRF-01", "PRF-08"]),
        SettingsSearchEntry(id: "profiles-manage", category: .profiles, title: "Create and manage profiles", description: "Create from the current reusable configuration, duplicate, rename, or safely delete profiles.", synonyms: ["clone", "copy", "named setup", "PRF-01"]),
        SettingsSearchEntry(id: "profiles-transfer", category: .profiles, title: "Export or import profiles", description: "Move reusable profile definitions with a previewed portable JSON file without transferring this Mac's monitor bindings or active selection.", synonyms: ["backup", "restore", "share", "JSON", "portable configuration"]),
        SettingsSearchEntry(id: "profiles-triggers", category: .profiles, title: "Automatic profile triggers", description: "Choose this Mac's default, exact display mappings, and docked or undocked profiles.", synonyms: ["dock", "topology", "automatic selection", "manual override", "PRF-02", "PRF-06"]),
        SettingsSearchEntry(id: "profiles-display-roles", category: .profiles, title: "Display role bindings", description: "Bind synced abstract display roles to this Mac's conservative monitor identities.", synonyms: ["monitor fingerprint", "local display", "primary display", "PRF-04", "PRF-05"]),
        SettingsSearchEntry(id: "workspace-names", category: .workspaces, title: "Workspace names and keys", description: "Add, remove, rename, reorder, and assign shortcut keys to virtual workspaces.", synonyms: ["spaces", "virtual desktops"]),
        SettingsSearchEntry(id: "workspace-defaults", category: .workspaces, title: SettingsCopy.restoreWindowManagerDefaultsTitle, description: "Restore WindowRanger's built-in workspace names, order, keys, and layout choices.", synonyms: ["built-in defaults", "reset workspaces", "factory settings"]),
        SettingsSearchEntry(id: "display-mode", category: .workspaces, title: "Unified or Independent Displays", description: "Choose whether workspace switching affects every display or one display at a time.", synonyms: ["monitor", "screen", "multi-display"]),
        SettingsSearchEntry(id: "display-home", category: .workspaces, title: "Workspace display role", description: "Choose the synced abstract display role that owns each workspace in Independent Displays mode.", synonyms: ["monitor assignment", "pin workspace", "home display"]),
        SettingsSearchEntry(id: "display-fingerprint", category: .profiles, title: "Stable local monitor identity", description: "Bind abstract display roles on this Mac using UUID and conservative hardware fingerprints.", synonyms: ["monitor fingerprint", "serial", "vendor", "model", "MON-06"]),
        SettingsSearchEntry(id: "workspace-layout", category: .workspaces, title: "Per-workspace layout", description: "Choose Freeform, Tiled, or Accordion independently for every workspace.", synonyms: ["none", "manual frames", "no automatic layout", "tile", "stack", "accordion"]),
        SettingsSearchEntry(id: "layout-orientation", category: .workspaces, title: "Workspace layout orientation", description: "Use automatic, horizontal, or vertical window direction per workspace.", synonyms: ["portrait", "landscape", "row", "column"]),
        SettingsSearchEntry(id: "layout-gaps", category: .workspaces, title: "Inner gaps and outer screen padding", description: "Set spacing between Tiled windows and around display edges per workspace.", synonyms: ["margin", "inset", "spacing"]),
        SettingsSearchEntry(id: "accordion-padding", category: .workspaces, title: "Accordion visible edge padding", description: "Choose how much of neighbouring Accordion windows remains visible.", synonyms: ["overlap", "stack"]),
        SettingsSearchEntry(id: "workspace-reset-settings", category: .workspaces, title: "Reset this workspace", description: "Restore Freeform and WindowRanger's built-in layout geometry while preserving workspace identity and display home.", synonyms: ["built-in defaults", "layout reset", "undo"]),
        SettingsSearchEntry(id: "reset-workspace", category: .workspaces, title: "Bring active workspace windows back on screen", description: "Recover its managed windows, clear transient positioning state, and reapply its layout.", synonyms: ["repair", "recover", "offscreen", "KEY-12"]),
        SettingsSearchEntry(id: "app-assignment", category: .appRules, title: "Always open on workspace", description: "Route windows from a selected app to a chosen workspace.", synonyms: ["application routing"]),
        SettingsSearchEntry(id: "app-keep-all", category: .appRules, title: "Keep app on all workspaces", description: "Keep an app visible while switching workspaces.", synonyms: ["sticky", "every workspace"]),
        SettingsSearchEntry(id: "app-exclude-layout", category: .appRules, title: "Exclude app from layouts", description: "Keep an app out of Tiled and Accordion geometry.", synonyms: ["float app", "ignore layout"]),
        SettingsSearchEntry(id: "app-float-secondary", category: .appRules, title: "Float secondary windows", description: "Keep conservatively detected dialogs and secondary windows from distorting layouts for a selected app.", synonyms: ["dialog", "sheet", "panel", "APP-05"]),
        SettingsSearchEntry(id: "app-rule-pause", category: .appRules, title: "Pause an application rule", description: "Temporarily stop a rule without deleting its saved actions.", synonyms: ["disable", "resume", "enabled", "BST-RUL-02"]),
        SettingsSearchEntry(id: "app-rule-undo", category: .appRules, title: "Undo an application rule change", description: "Rule edits apply to managed windows immediately and can be reversed with Command-Z.", synonyms: ["revert", "bulk move", "routing", "BST-RUL-04"]),
        SettingsSearchEntry(id: "workspace-shortcuts", category: .workspaces, title: "Workspace shortcuts", description: "Edit each workspace key and review its derived switching and window-moving key bindings.", synonyms: ["hotkeys", "keyboard", "switch to", "move window to"]),
        SettingsSearchEntry(id: "shortcut-recorder", category: .shortcuts, title: "Record and reset shortcuts", description: "Rebind global WindowRanger commands with conflict feedback or restore their defaults.", synonyms: ["customize hotkeys", "keyboard recorder", "key binding", "BST-UX-02"]),
        SettingsSearchEntry(id: "shortcut-conflicts", category: .shortcuts, title: "Repair shortcut conflicts", description: "Identify every command sharing a shortcut or failing macOS registration, then record a replacement or safely reset custom bindings.", synonyms: ["registration failed", "hotkey unavailable", "duplicate shortcut", "REL-01"]),
        SettingsSearchEntry(id: "focus-shortcuts", category: .shortcuts, title: "Focus shortcuts", description: "Review previous and next window bindings.", synonyms: ["cycle windows"]),
        SettingsSearchEntry(id: "directional-focus", category: .shortcuts, title: "Directional window focus", description: "Focus the nearest eligible window left, down, up, or right on the interaction display.", synonyms: ["Option H J K L", "KEY-06"]),
        SettingsSearchEntry(id: "directional-move", category: .shortcuts, title: "Directional layout reorder", description: "Use one direction to reorder, or two perpendicular directions within 200 ms to place a Tiled window at that corner.", synonyms: ["Control Option arrows", "two arrow", "corner placement", "top right", "BSP", "KEY-07", "LAY-16"]),
        SettingsSearchEntry(id: "smart-resize", category: .shortcuts, title: "Smart layout resize", description: "Adjust the focused Tiled share or the current Accordion padding in safe 50-point steps.", synonyms: ["Control Option minus equal", "KEY-08"]),
        SettingsSearchEntry(id: "move-workspace-display", category: .shortcuts, title: "Move workspace to another display", description: "Reassign the active Independent Displays workspace and keep both displays in a valid active state.", synonyms: ["Option Shift Tab", "monitor", "KEY-09", "MON-05"]),
        SettingsSearchEntry(id: "layout-shortcuts", category: .shortcuts, title: "Layout shortcuts", description: "Review Tiled, Accordion, Freeform, and per-window Floating commands.", synonyms: ["none", "manual frames", "tile", "float", "cycle layout"]),
        SettingsSearchEntry(id: "radial-enabled", category: .radialMenu, title: "Enable contextual command wheel", description: "Show a compact command wheel built from the current window, workspace, layout, and display.", synonyms: ["radial menu", "wheel", "Loop", "Snap Wheel"]),
        SettingsSearchEntry(id: "radial-shortcut", category: .radialMenu, title: "Command wheel shortcut", description: "Record a conflict-checked global chord for the command wheel.", synonyms: ["trigger", "hotkey", "Control Option Space", "radial menu", "snap wheel"]),
        SettingsSearchEntry(id: "radial-activation", category: .radialMenu, title: "Press or hold activation", description: "Toggle the wheel with a press, or hold past a configurable delay and release to commit.", synonyms: ["Loop", "trigger timeout", "hold to show", "release"]),
        SettingsSearchEntry(id: "radial-globe-fn", category: .radialMenu, title: "Hold Globe or Fn to show Command Wheel", description: "Optionally use a deliberate Globe/Fn hold while preserving the Mac's normal quick-tap action.", synonyms: ["emoji", "function key", "hardware trigger", "Loop", "quick tap"]),
        SettingsSearchEntry(id: "radial-editor", category: .radialMenu, title: "Command wheel items", description: "Add, hide, and reorder contextual top-level items; their outer-ring commands are generated automatically.", synonyms: ["slots", "outer ring", "submenu", "customize", "undo", "repair", "reset"]),
        SettingsSearchEntry(id: "radial-item-move", category: .radialMenu, title: "Move to Space", description: "Send the focused window to a generated destination, with Option for one-shot Move and Follow.", synonyms: ["command wheel", "send window", "follow window"]),
        SettingsSearchEntry(id: "radial-item-resize", category: .radialMenu, title: "Resize or Place", description: "Generate truthful layout-aware resize or Tiled placement choices for the focused window.", synonyms: ["command wheel", "compass", "tiled preview"]),
        SettingsSearchEntry(id: "radial-item-go", category: .radialMenu, title: "Go to Space", description: "Generate valid workspace destinations in stable user order.", synonyms: ["command wheel", "switch workspace"]),
        SettingsSearchEntry(id: "radial-item-next", category: .radialMenu, title: "Next Space", description: "Move to the next valid workspace from the command wheel.", synonyms: ["cycle workspace"]),
        SettingsSearchEntry(id: "radial-item-previous", category: .radialMenu, title: "Previous Space", description: "Move to the previous valid workspace from the command wheel.", synonyms: ["cycle workspace"]),
        SettingsSearchEntry(id: "radial-item-profiles", category: .radialMenu, title: "Profiles", description: "Select a generated reusable profile or Resume Automatic when relevant.", synonyms: ["command wheel", "configuration profile"]),
        SettingsSearchEntry(id: "radial-item-reset-space", category: .radialMenu, title: "Reset Windows in Space", description: "Bring the current workspace's managed windows safely back into view.", synonyms: ["command wheel", "recover windows"]),
        SettingsSearchEntry(id: "radial-item-reset-all", category: .radialMenu, title: "Reset All Windows", description: "Use the broad established recovery command with an unmistakable scope.", synonyms: ["command wheel", "recover every workspace"]),
        SettingsSearchEntry(id: "radial-item-layout", category: .radialMenu, title: "Layout Type", description: "Cycle or select Freeform, Tiled, and Accordion for the current workspace.", synonyms: ["command wheel", "layout mode"]),
        SettingsSearchEntry(id: "diagnostics-copy", category: .diagnostics, title: "Copy recent diagnostics", description: "Copy a bounded privacy-safe Debug diagnostic excerpt.", synonyms: ["logs", "debug"], debugOnly: true),
        SettingsSearchEntry(id: "diagnostics-reveal", category: .diagnostics, title: "Reveal diagnostics file", description: "Show the rotating Debug JSON Lines file in Finder.", synonyms: ["logs", "JSONL"], debugOnly: true),
        SettingsSearchEntry(id: "diagnostics-admission", category: .diagnostics, title: "Window admission classifications", description: "Inspect privacy-safe reasons windows are managed, floated, deferred, or ignored.", synonyms: ["rejected windows", "unmanaged", "popup", "dialog", "REL-06"], debugOnly: true),
    ]

    static func availableCategories(includeDebug: Bool) -> [SettingsCategory] {
        SettingsCategory.allCases.filter {
            $0 != .displays && $0 != .layouts && (includeDebug || $0 != .diagnostics)
        }
    }

    static func search(
        _ query: String,
        includeDebug: Bool,
        workspaces: [WorkspaceDefinition] = []
    ) -> [SettingsSearchEntry] {
        let staticMatches = entries.filter { entry in
            (includeDebug || !entry.debugOnly) && entry.matches(query)
        }
        let workspaceMatches = workspaces.map { workspace in
            SettingsSearchEntry(
                id: "workspace-\(workspace.id.uuidString)",
                category: .workspaces,
                title: workspace.name,
                description: "Workspace key \(workspace.key.uppercased()) · \(workspace.layout.title) layout.",
                synonyms: ["workspace", "space", workspace.key, workspace.layout.title],
                workspaceID: workspace.id
            )
        }.filter { $0.matches(query) }
        return staticMatches + workspaceMatches
    }
}

/// Centralizes customer-facing Settings terminology so historical implementation names cannot
/// leak into labels, search, accessibility, or future confirmation copy.
enum SettingsCopy {
    static let restoreWindowManagerDefaultsTitle = "Restore WindowRanger Defaults"
}

@MainActor
final class SettingsNavigationModel: ObservableObject {
    private static let selectedCategoryKey = "settings.selectedCategory.v1"

    @Published private(set) var selectedCategory: SettingsCategory {
        didSet { defaults.set(selectedCategory.rawValue, forKey: Self.selectedCategoryKey) }
    }
    @Published var searchText = ""
    @Published var highlightedSettingID: String?
    @Published private(set) var requestedWorkspaceID: UUID?

    private let defaults: UserDefaults
    let includeDebug: Bool

    init(defaults: UserDefaults = .standard, includeDebug: Bool = SettingsNavigationModel.currentBuildIncludesDebug) {
        self.defaults = defaults
        self.includeDebug = includeDebug
        let available = SettingsCatalog.availableCategories(includeDebug: includeDebug)
        let restored = defaults.string(forKey: Self.selectedCategoryKey)
            .flatMap(SettingsCategory.init(rawValue:))
        selectedCategory = Self.resolvedSelection(restored, available: available)
        requestedWorkspaceID = nil
        defaults.set(selectedCategory.rawValue, forKey: Self.selectedCategoryKey)
    }

    var availableCategories: [SettingsCategory] {
        SettingsCatalog.availableCategories(includeDebug: includeDebug)
    }

    var searchResults: [SettingsSearchEntry] {
        SettingsCatalog.search(searchText, includeDebug: includeDebug)
    }

    func select(_ category: SettingsCategory, highlightedSettingID: String? = nil) {
        let destination = category.canonicalDestination
        guard availableCategories.contains(destination) else {
            let fallback = Self.resolvedSelection(nil, available: availableCategories)
            if selectedCategory != fallback { selectedCategory = fallback }
            if self.highlightedSettingID != nil { self.highlightedSettingID = nil }
            if requestedWorkspaceID != nil { requestedWorkspaceID = nil }
            return
        }
        if selectedCategory != destination { selectedCategory = destination }
        if self.highlightedSettingID != highlightedSettingID {
            self.highlightedSettingID = highlightedSettingID
        }
        if destination != .workspaces, requestedWorkspaceID != nil {
            requestedWorkspaceID = nil
        }
    }

    func select(_ result: SettingsSearchEntry) {
        if requestedWorkspaceID != result.workspaceID {
            requestedWorkspaceID = result.workspaceID
        }
        select(result.category, highlightedSettingID: result.id)
    }

    func selectWorkspace(_ workspaceID: UUID) {
        if requestedWorkspaceID != workspaceID { requestedWorkspaceID = workspaceID }
        select(.workspaces)
    }

    func validateSelection() {
        guard availableCategories.contains(selectedCategory) else {
            let fallback = Self.resolvedSelection(nil, available: availableCategories)
            if selectedCategory != fallback { selectedCategory = fallback }
            if highlightedSettingID != nil { highlightedSettingID = nil }
            if requestedWorkspaceID != nil { requestedWorkspaceID = nil }
            return
        }
    }

    static func resolvedSelection(
        _ requested: SettingsCategory?,
        available: [SettingsCategory]
    ) -> SettingsCategory {
        if let requested {
            let destination = requested.canonicalDestination
            if available.contains(destination) { return destination }
        }
        if available.contains(.general) { return .general }
        return available.first ?? .general
    }

    nonisolated static var currentBuildIncludesDebug: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}
