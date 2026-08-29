import Foundation

enum WindowRangerCLICommandKind: String, Codable, Sendable {
    case query
    case control
}

struct WindowRangerCLICommandDescriptor: Equatable, Sendable {
    let operation: WindowRangerCLIOperation
    let kind: WindowRangerCLICommandKind
    let synopsis: String
    let agentGuidance: String
    let examplePayload: WindowRangerCLIRequestPayload?
}

/// This is the sole public-operation allowlist. Capabilities and the generated agent skill derive
/// from it; contract tests keep the CLI parser and local service aligned with the same operations.
enum WindowRangerCLICommandCatalog {
    static let requiredActionConfirmations: [String: String] = [
        "enable-icloud-sync": "enable-icloud-sync",
        "replace-icloud-with-local": "replace-icloud-with-local",
    ]

    static let commands: [WindowRangerCLICommandDescriptor] = [
        .init(
            operation: .status,
            kind: .query,
            synopsis: "Read safe runtime status.",
            agentGuidance: "Use this before a control operation when the app may be unavailable.",
            examplePayload: nil
        ),
        .init(
            operation: .capabilities,
            kind: .query,
            synopsis: "Read the protocol version and supported operations.",
            agentGuidance: "Check capabilities instead of assuming a newer operation exists.",
            examplePayload: nil
        ),
        .init(
            operation: .listActions,
            kind: .query,
            synopsis: "List every stable user-facing action and its arguments.",
            agentGuidance: "Use the returned names and arguments exactly; do not infer hidden actions.",
            examplePayload: nil
        ),
        .init(
            operation: .performAction,
            kind: .control,
            synopsis: "Perform one named runtime or system action.",
            agentGuidance: "Inspect actions first and obtain explicit authority for actions with external effects.",
            examplePayload: .init(action: "cycle-workspace", arguments: ["offset": .number(1)])
        ),
        .init(
            operation: .getConfiguration,
            kind: .query,
            synopsis: "Read the complete versioned WindowRanger configuration and revision.",
            agentGuidance: "Configuration contains private profile names, app identifiers, and local display bindings; minimize retention.",
            examplePayload: nil
        ),
        .init(
            operation: .validateConfiguration,
            kind: .query,
            synopsis: "Validate and normalize a complete configuration without applying it.",
            agentGuidance: "Validate before applying a human-edited document.",
            examplePayload: nil
        ),
        .init(
            operation: .applyConfiguration,
            kind: .control,
            synopsis: "Replace the complete configuration if its revision is still current.",
            agentGuidance: "This is destructive replacement. Preserve the revision, validate first, and obtain explicit authority immediately before applying.",
            examplePayload: nil
        ),
        .init(
            operation: .listWorkspaces,
            kind: .query,
            synopsis: "List workspace IDs and keys; names are opt-in.",
            agentGuidance: "Keep includeNames false unless a human explicitly needs a name.",
            examplePayload: .init(includeNames: false)
        ),
        .init(
            operation: .activateWorkspace,
            kind: .control,
            synopsis: "Activate a workspace by exactly one stable ID or key.",
            agentGuidance: "Never guess a target. Use an ID or key returned by list_workspaces.",
            examplePayload: .init(workspaceKey: "1")
        ),
        .init(
            operation: .setLayout,
            kind: .control,
            synopsis: "Set `freeform`, `tiled`, or `accordion` layout for the current interaction workspace.",
            agentGuidance: "This intentionally follows the app's current workspace. Use activate_workspace first when needed.",
            examplePayload: .init(layout: .tiled)
        ),
        .init(
            operation: .pause,
            kind: .control,
            synopsis: "Pause WindowRanger window-management writes.",
            agentGuidance: "Treat pause as a runtime action; it is not persisted configuration.",
            examplePayload: nil
        ),
        .init(
            operation: .resume,
            kind: .control,
            synopsis: "Resume WindowRanger window-management writes.",
            agentGuidance: "Resume only after the caller is ready for one fresh reconciliation.",
            examplePayload: nil
        ),
    ]

    static let operations = commands.map(\.operation)

    static let actions: [WindowRangerCLIActionDescriptor] = [
        action("switch-workspace", "Switch to a workspace.", ["workspace-id", "workspace-key"]),
        action("move-window", "Move the focused window to a workspace.", ["workspace-id", "workspace-key"]),
        action("move-window-and-follow", "Move the focused window and follow it.", ["workspace-id", "workspace-key"]),
        action("cycle-workspace", "Cycle workspaces by an offset.", ["offset"]),
        action("cycle-window", "Cycle focused windows by an offset.", ["offset"]),
        action("cycle-layout", "Cycle the active workspace layout by an offset.", ["offset"]),
        action("set-layout", "Set the active workspace layout.", ["layout"]),
        action("select-layout", "Select a layout, cycling orientation when already selected.", ["layout"]),
        action("toggle-floating", "Toggle the focused window between managed and floating."),
        action("toggle-drop-down-app", "Show or hide the Quick App Shelf."),
        action("select-quick-app", "Select a Quick App Shelf application.", ["bundle-id"]),
        action("cycle-quick-app", "Cycle the selected Quick App by an offset.", ["offset"]),
        action("add-current-app-rule", "Pin the focused application to the active workspace."),
        action("remove-current-app-rule", "Remove the focused application rule."),
        action("add-current-app-to-shelf", "Add the focused application to the Quick App Shelf."),
        action("previous-workspace", "Return to the previous workspace."),
        action("reset-current-workspace", "Reset the active workspace layout."),
        action("bring-windows-back-on-screen", "Recover all managed windows onto connected displays."),
        action("focus-direction", "Focus a window in one direction.", ["direction"]),
        action("move-window-direction", "Move the focused window in one direction.", ["direction"]),
        action("place-window", "Place the focused window in one visual region.", ["placement"]),
        action("smart-resize", "Grow or shrink the focused window.", ["amount"]),
        action("move-workspace-to-next-display", "Move the active workspace to the next display."),
        action("move-workspace-to-display", "Move the active workspace to a display.", ["display-id"]),
        action("select-profile", "Activate and pin a profile.", ["profile-id"]),
        action("resume-automatic-profile-selection", "Resume automatic profile selection."),
        action("pause", "Pause WindowRanger window-management writes.", requiresAccessibility: false),
        action("resume", "Resume WindowRanger window-management writes.", requiresAccessibility: false),
        action("open-settings", "Open WindowRanger Settings.", ["category"], requiresAccessibility: false),
        action("request-accessibility", "Ask macOS for Accessibility permission.", requiresAccessibility: false),
        action("open-screen-recording-settings", "Open Screen Recording privacy settings.", requiresAccessibility: false),
        action("open-login-items-settings", "Open Login Items settings.", requiresAccessibility: false),
        action("restart-onboarding", "Restart and present the setup wizard.", requiresAccessibility: false),
        action("check-for-updates", "Ask the configured updater to check now.", requiresAccessibility: false),
        action(
            "enable-icloud-sync",
            "Enable iCloud sync and safely check for an existing cloud configuration. Requires confirmation=enable-icloud-sync.",
            ["confirmation"],
            requiresAccessibility: false
        ),
        action("disable-icloud-sync", "Disable iCloud sync without deleting either copy.", requiresAccessibility: false),
        action(
            "replace-icloud-with-local",
            "Destructively replace iCloud settings with this Mac's copy. Requires confirmation=replace-icloud-with-local.",
            ["confirmation"],
            requiresAccessibility: false
        ),
    ]

    static func descriptor(for operation: WindowRangerCLIOperation) -> WindowRangerCLICommandDescriptor? {
        commands.first { $0.operation == operation }
    }

    static func action(named name: String) -> WindowRangerCLIActionDescriptor? {
        actions.first { $0.name == name }
    }

    static func actionConfirmationIsSatisfied(
        action name: String,
        arguments: [String: String]
    ) -> Bool {
        guard let expected = requiredActionConfirmations[name] else { return true }
        return arguments["confirmation"] == expected
    }

    private static func action(
        _ name: String,
        _ synopsis: String,
        _ argumentNames: [String] = [],
        requiresAccessibility: Bool = true
    ) -> WindowRangerCLIActionDescriptor {
        .init(
            name: name,
            kind: .control,
            synopsis: synopsis,
            argumentNames: argumentNames,
            requiresAccessibility: requiresAccessibility
        )
    }
}
