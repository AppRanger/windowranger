import Foundation

/// Produces a static, reviewable skill document. It deliberately takes no runtime state, so it
/// cannot leak workspace names, window content, paths, profiles, or diagnostics into agent files.
enum WindowRangerCLIAgentSkill {
    static let fileName = "SKILL.md"

    static func content(catalog: [WindowRangerCLICommandDescriptor] = WindowRangerCLICommandCatalog.commands) -> String {
        var lines = [
            "---",
            "name: windowranger-cli",
            "description: Query, control, or configure the local WindowRanger app, including workspaces, windows, profiles, displays, shortcuts, appearance, sync, and app settings.",
            "---",
            "",
            "# WindowRanger CLI",
            "",
            "Use the bundled `windowranger` command. Add `--json` for stable, versioned output intended for tools and agents.",
            "",
            "## Safety",
            "",
            "- Start with `windowranger capabilities --json` when compatibility is uncertain.",
            "- Treat workspace IDs and keys returned by the app as exact targets. Never infer a target from a name.",
            "- Workspace names are private user text and are omitted by default. Use `windowranger workspaces --names --json` only when the human's request needs them.",
            "- `config get` intentionally returns private profile names, app bundle identifiers, shortcut choices, and local display bindings. Read it only when the task needs configuration, minimize retention, and never publish it.",
            "- `config apply` replaces the complete configuration and can change login-item, updater, onboarding, and already-enabled iCloud settings. It requires the revision returned by `config get`. Validate the edited snapshot first and obtain explicit human authority immediately before applying it.",
            "- Enabling iCloud is deliberately separate from configuration replacement because joining can pull a different cloud library. Use the `enable-icloud-sync` action only with `confirmation=enable-icloud-sync`, then fetch a fresh configuration snapshot.",
            "- Replacing the cloud copy is destructive. The `replace-icloud-with-local` action requires `confirmation=replace-icloud-with-local` as well as explicit human authority.",
            "- Use `actions --json` as the authoritative runtime catalogue. Operations such as requesting permissions or checking for updates have external effects and require explicit authority.",
            "- Do not send window titles, document names, paths, or screen contents.",
            "- Stop on a non-zero exit or an error response. Do not blindly retry a control command.",
            "",
            "## Commands",
            "",
        ]

        for descriptor in catalog {
            lines.append("### `\(descriptor.operation.rawValue)` — \(descriptor.kind.rawValue)")
            lines.append("")
            lines.append(descriptor.synopsis)
            lines.append("")
            lines.append(descriptor.agentGuidance)
            lines.append("")
            lines.append("`\(commandExample(for: descriptor.operation))`")
            lines.append("")
        }

        lines.append("JSON responses use protocol version `\(WindowRangerCLIProtocol.version)` and contain a request ID plus exactly one of `result` or `error`. Errors are code-only by design.")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func commandExample(for operation: WindowRangerCLIOperation) -> String {
        switch operation {
        case .status: "windowranger status --json"
        case .capabilities: "windowranger capabilities --json"
        case .listActions: "windowranger actions --json"
        case .performAction: "windowranger action <name> [--args '<json-object>'] --json"
        case .getConfiguration: "windowranger config get > windowranger-config.json"
        case .validateConfiguration: "windowranger config validate <snapshot-file> --json"
        case .applyConfiguration: "windowranger config apply <snapshot-file> --replace --json"
        case .listWorkspaces: "windowranger workspaces --json"
        case .activateWorkspace: "windowranger workspace <id-or-key> --json"
        case .setLayout: "windowranger layout <freeform|tiled|accordion> --json"
        case .pause: "windowranger pause --json"
        case .resume: "windowranger resume --json"
        }
    }
}
