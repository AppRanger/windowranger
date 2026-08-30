import AppKit
import Darwin
import Foundation

private enum ExitCode: Int32 {
    case success = 0
    case failure = 1
    case usage = 2
    case unavailable = 3
    case permission = 4
    case rejected = 5
    case timedOut = 6
}

private enum CommandLineError: Error, LocalizedError {
    case usage(String)
    case appBundleUnavailable
    case mismatchedResponse
    case service(WindowRangerCLIErrorCode)

    var errorDescription: String? {
        switch self {
        case let .usage(message): message
        case .appBundleUnavailable: "The bundled WindowRanger app could not be found. Reinstall WindowRanger and add the command again."
        case .mismatchedResponse: "WindowRanger returned an invalid command response."
        case let .service(code): "WindowRanger rejected the command: \(code.rawValue)."
        }
    }
}

private enum HumanOutputMode {
    case standard
    case configApply
}

private struct ParsedCommand {
    let request: WindowRangerCLIRequestEnvelope?
    let json: Bool
    let skillOutput: String?
    let forceSkillOutput: Bool
    let printsSkill: Bool
    let printsHelp: Bool
    let printsVersion: Bool
    let outputMode: HumanOutputMode
}

private enum WindowRangerCommandLine {
    static func main() {
        do {
            let parsed = try parse(Array(CommandLine.arguments.dropFirst()))
            if parsed.printsHelp {
                print(help)
                return
            }
            if parsed.printsVersion {
                print("windowranger \(appVersion)")
                return
            }
            if parsed.printsSkill {
                try outputSkill(to: parsed.skillOutput, force: parsed.forceSkillOutput)
                return
            }
            guard let request = parsed.request else {
                throw CommandLineError.usage("No command was provided.")
            }
            let responseData = try send(request)
            let response = try WindowRangerCLIProtocol.decodeResponse(from: responseData)
            guard response.requestID == request.requestID else {
                throw CommandLineError.mismatchedResponse
            }
            if parsed.json {
                write(responseData, to: .standardOutput, endingWithNewline: true)
                if let serviceError = response.error {
                    Darwin.exit(exitCode(for: CommandLineError.service(serviceError.code)).rawValue)
                }
            } else {
                try printHumanResponse(response, mode: parsed.outputMode)
            }
        } catch {
            write(error.localizedDescription + "\n", to: .standardError)
            if case CommandLineError.usage = error {
                write("Run 'windowranger help' for usage.\n", to: .standardError)
            }
            Darwin.exit(exitCode(for: error).rawValue)
        }
    }

    private static func parse(_ rawArguments: [String]) throws -> ParsedCommand {
        var arguments = rawArguments
        let json = arguments.contains("--json")
        arguments.removeAll { $0 == "--json" }
        guard let command = arguments.first else {
            return ParsedCommand(
                request: nil,
                json: json,
                skillOutput: nil,
                forceSkillOutput: false,
                printsSkill: false,
                printsHelp: true,
                printsVersion: false,
                outputMode: .standard
            )
        }
        let values = Array(arguments.dropFirst())
        let requestID = "cli-\(UUID().uuidString.lowercased())"

        func request(
            _ operation: WindowRangerCLIOperation,
            payload: WindowRangerCLIRequestPayload? = nil,
            outputMode: HumanOutputMode = .standard
        ) throws -> ParsedCommand {
            let envelope = WindowRangerCLIRequestEnvelope(
                requestID: requestID,
                operation: operation,
                payload: payload
            )
            try envelope.validate()
            return ParsedCommand(
                request: envelope,
                json: json,
                skillOutput: nil,
                forceSkillOutput: false,
                printsSkill: false,
                printsHelp: false,
                printsVersion: false,
                outputMode: outputMode
            )
        }

        switch command {
        case "help", "--help", "-h":
            guard values.isEmpty else { throw CommandLineError.usage("help does not accept arguments.") }
            return ParsedCommand(
                request: nil,
                json: json,
                skillOutput: nil,
                forceSkillOutput: false,
                printsSkill: false,
                printsHelp: true,
                printsVersion: false,
                outputMode: .standard
            )
        case "version", "--version", "-v":
            guard values.isEmpty else { throw CommandLineError.usage("version does not accept arguments.") }
            return ParsedCommand(
                request: nil,
                json: json,
                skillOutput: nil,
                forceSkillOutput: false,
                printsSkill: false,
                printsHelp: false,
                printsVersion: true,
                outputMode: .standard
            )
        case "actions":
            guard values.isEmpty else { throw CommandLineError.usage("actions does not accept arguments.") }
            return try request(.listActions)
        case "status":
            guard values.isEmpty else { throw CommandLineError.usage("status does not accept arguments.") }
            return try request(.status)
        case "capabilities":
            guard values.isEmpty else { throw CommandLineError.usage("capabilities does not accept arguments.") }
            return try request(.capabilities)
        case "workspaces":
            let unknown = values.filter { $0 != "--names" }
            guard unknown.isEmpty, values.filter({ $0 == "--names" }).count <= 1 else {
                throw CommandLineError.usage("Usage: windowranger workspaces [--names] [--json]")
            }
            return try request(.listWorkspaces, payload: .init(includeNames: values.contains("--names")))
        case "workspace":
            guard values.count == 1, let target = values.first else {
                throw CommandLineError.usage("Usage: windowranger workspace <id-or-key> [--json]")
            }
            if let id = UUID(uuidString: target) {
                return try request(.activateWorkspace, payload: .init(workspaceID: id))
            }
            return try request(.activateWorkspace, payload: .init(workspaceKey: target))
        case "layout":
            guard values.count == 1, let value = values.first,
                  let layout = WindowRangerCLIWorkspaceLayout(rawValue: value) else {
                throw CommandLineError.usage("Usage: windowranger layout <freeform|tiled|accordion> [--json]")
            }
            return try request(.setLayout, payload: .init(layout: layout))
        case "pause":
            guard values.isEmpty else { throw CommandLineError.usage("pause does not accept arguments.") }
            return try request(.pause)
        case "resume":
            guard values.isEmpty else { throw CommandLineError.usage("resume does not accept arguments.") }
            return try request(.resume)
        case "action":
            guard let action = values.first else {
                throw CommandLineError.usage("Usage: windowranger action <name> [--args <json>] [--json]")
            }
            var remaining = Array(values.dropFirst())
            var arguments: [String: WindowRangerCLIJSONValue]?
            while !remaining.isEmpty {
                let current = remaining.removeFirst()
                switch current {
                case "--args":
                    guard arguments == nil, let json = remaining.first else {
                        throw CommandLineError.usage("Usage: windowranger action <name> [--args <json>] [--json]")
                    }
                    remaining.removeFirst()
                    arguments = try parseActionArguments(json)
                default:
                    throw CommandLineError.usage("Unknown option '\(current)' for action. Usage: windowranger action <name> [--args <json>] [--json]")
                }
            }
            return try request(
                .performAction,
                payload: .init(
                    action: action,
                    arguments: arguments ?? [:]
                )
            )
        case "config":
            guard let configAction = values.first else {
                throw CommandLineError.usage("Usage: windowranger config <get|validate|apply> ...")
            }
            switch configAction {
            case "get":
                guard values.count == 1 else {
                    throw CommandLineError.usage("Usage: windowranger config get [--json]")
                }
                return try request(.getConfiguration)
            case "validate":
                guard values.count == 2 else {
                    throw CommandLineError.usage("Usage: windowranger config validate <file|-> [--json]")
                }
                let source = values[1]
                let (configuration, _) = try decodeConfigurationInput(from: source, allowRawDocument: true)
                return try request(
                    .validateConfiguration,
                    payload: .init(
                        configuration: configuration
                    )
                )
            case "apply":
                guard values.count >= 2 else {
                    throw CommandLineError.usage("Usage: windowranger config apply <file|-> --replace [--json]")
                }
                var source: String?
                var sawReplace = false
                for value in values.dropFirst() {
                    if value == "--replace" {
                        if sawReplace {
                            throw CommandLineError.usage("Usage: windowranger config apply <file|-> --replace [--json]")
                        }
                        sawReplace = true
                    } else if source == nil {
                        source = value
                    } else {
                        throw CommandLineError.usage("Usage: windowranger config apply <file|-> --replace [--json]")
                    }
                }
                guard sawReplace, let applySource = source else {
                    throw CommandLineError.usage("Usage: windowranger config apply <file|-> --replace [--json]")
                }
                let (configuration, snapshot) = try decodeConfigurationInput(from: applySource, allowRawDocument: false)
                guard let snapshot else {
                    throw CommandLineError.usage("Config apply requires a snapshot JSON document with revision and document.")
                }
                return try request(
                    .applyConfiguration,
                    payload: .init(
                        configuration: configuration,
                        expectedRevision: snapshot.revision,
                        confirmsReplacement: true
                    ),
                    outputMode: .configApply
                )
            default:
                throw CommandLineError.usage("Usage: windowranger config <get|validate|apply> ...")
            }
        case "skill":
            guard !json else { throw CommandLineError.usage("skill does not use --json.") }
            var output: String?
            let force = values.contains("--force")
            let skillValues = values.filter { $0 != "--force" }
            guard values.filter({ $0 == "--force" }).count <= 1 else {
                throw CommandLineError.usage("--force may be supplied only once.")
            }
            if skillValues.isEmpty, !force {
                output = nil
            } else if skillValues.count == 2, skillValues[0] == "--output" {
                output = skillValues[1]
            } else {
                throw CommandLineError.usage("Usage: windowranger skill [--output <directory-or-SKILL.md> [--force]]")
            }
            return ParsedCommand(
                request: nil,
                json: false,
                skillOutput: output,
                forceSkillOutput: force,
                printsSkill: true,
                printsHelp: false,
                printsVersion: false,
                outputMode: .standard
            )
        default:
            throw CommandLineError.usage("Unknown command '\(command)'.")
        }
    }

    private static func send(_ request: WindowRangerCLIRequestEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let appURL = try enclosingAppURL()
        let client = CLIIPCClient(
            // SecCodeCopyPath returns a bundle's root rather than its main executable. The code
            // identifier, Team ID and dynamic signature checks still bind this exact location to
            // the trusted running WindowRanger app.
            peerPolicy: .windowRangerApp(bundleURL: appURL),
            timeout: 1
        )

        func sendAttempt() throws -> Data {
            let timedRequest = WindowRangerCLIRequestEnvelope(
                protocolVersion: request.protocolVersion,
                requestID: request.requestID,
                deadlineUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds +
                    WindowRangerCLIProtocol.requestExecutionWindowNanoseconds,
                operation: request.operation,
                payload: request.payload
            )
            return try client.send(encoder.encode(timedRequest))
        }

        do {
            return try sendAttempt()
        } catch CLIIPCTransportError.unavailable {
            launch(appURL)
        }

        let deadline = Date().addingTimeInterval(CLIIPCTransport.defaultTimeout)
        repeat {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            do {
                return try sendAttempt()
            } catch CLIIPCTransportError.unavailable {
                continue
            }
        } while Date() < deadline
        throw CLIIPCTransportError.timedOut
    }

    private static func enclosingAppURL() throws -> URL {
        let rawExecutable = URL(fileURLWithPath: CommandLine.arguments[0], relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let appURL = rawExecutable
            .deletingLastPathComponent() // Helpers
            .deletingLastPathComponent() // Contents
            .deletingLastPathComponent() // WindowRanger.app
        guard appURL.pathExtension == "app",
              FileManager.default.fileExists(atPath: appURL.path) else {
            throw CommandLineError.appBundleUnavailable
        }
        return appURL
    }

    private static func launch(_ appURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in }
    }

    private static func printHumanResponse(
        _ response: WindowRangerCLIResponseEnvelope,
        mode: HumanOutputMode
    ) throws {
        if let error = response.error {
            throw CommandLineError.service(error.code)
        }
        guard let result = response.result else { throw CommandLineError.mismatchedResponse }
        switch result {
        case let .actions(actions):
            for action in actions {
                let args = action.argumentNames.isEmpty ? "" : " (" + action.argumentNames.joined(separator: ", ") + ")"
                let scope = action.requiresAccessibility ? "requires accessibility" : "system"
                print("\(action.name)\(args) — \(scope)")
                print("  \(action.synopsis)")
            }
        case let .configuration(configuration):
            if mode == .configApply {
                print("Applied configuration snapshot revision \(configuration.revision).")
            } else {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let text = String(data: try encoder.encode(configuration), encoding: .utf8) ?? "<invalid configuration payload>"
                print(text)
            }
        case let .configurationValidation(validation):
            print(validation.valid ? "Configuration is valid." : "Configuration is invalid.")
            if let normalizedDocument = validation.normalizedDocument {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let data = try? encoder.encode(normalizedDocument),
                   let text = String(data: data, encoding: .utf8) {
                    print("Normalized document:")
                    print(text)
                }
            }
        case let .status(status):
            print(status.isPaused ? "WindowRanger is paused." : "WindowRanger is running.")
            print("Accessibility: \(status.accessibilityGranted ? "granted" : "required")")
        case let .capabilities(capabilities):
            print("Protocol: \(capabilities.protocolVersion)")
            print("Commands: \(capabilities.operations.map(\.rawValue).joined(separator: ", "))")
        case let .workspaces(workspaces):
            for workspace in workspaces {
                let name = workspace.name.map { "  \(terminalSafe($0))" } ?? ""
                let key = workspace.key.isEmpty ? "—" : workspace.key
                print("\(key)\(name)  \(workspace.id.uuidString.lowercased())")
            }
        case .accepted:
            print("Done.")
        }
    }

    private static func parseActionArguments(_ raw: String) throws -> [String: WindowRangerCLIJSONValue] {
        let data = raw.data(using: .utf8) ?? Data()
        guard !data.isEmpty else {
            throw CommandLineError.usage("action --args requires a JSON object.")
        }
        guard data.count <= WindowRangerCLIProtocol.maximumMessageBytes else {
            throw CommandLineError.usage("action --args exceeds the maximum input size.")
        }
        guard (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) != nil else {
            throw CommandLineError.usage("action --args requires a JSON object.")
        }
        do {
            return try JSONDecoder().decode([String: WindowRangerCLIJSONValue].self, from: data)
        } catch {
            throw CommandLineError.usage("action --args requires a JSON object.")
        }
    }

    private static func decodeConfigurationInput(
        from source: String,
        allowRawDocument: Bool
    ) throws -> (configuration: WindowRangerCLIJSONValue, snapshot: WindowRangerCLIConfigurationSnapshot?) {
        let data = try readCommandInput(from: source)
        guard data.count <= WindowRangerCLIProtocol.maximumMessageBytes else {
            throw CommandLineError.usage("Configuration input exceeds the maximum input size.")
        }
        guard (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) != nil else {
            throw CommandLineError.usage("Configuration must be a JSON object.")
        }
        let decodedDocument: [String: WindowRangerCLIJSONValue]
        do {
            decodedDocument = try JSONDecoder().decode([String: WindowRangerCLIJSONValue].self, from: data)
        } catch {
            throw CommandLineError.usage("Configuration must be a JSON object.")
        }
        if let snapshot = try? JSONDecoder().decode(WindowRangerCLIConfigurationSnapshot.self, from: data) {
            return (snapshot.document, snapshot)
        }
        guard allowRawDocument else {
            throw CommandLineError.usage("Config apply requires a snapshot JSON document with revision and document.")
        }
        return (.object(decodedDocument), nil)
    }

    private static func readCommandInput(from source: String) throws -> Data {
        if source == "-" {
            let data = try FileHandle.standardInput.read(
                upToCount: WindowRangerCLIProtocol.maximumMessageBytes + 1
            ) ?? Data()
            guard !data.isEmpty else {
                throw CommandLineError.usage("No input was provided.")
            }
            return data
        }
        let url = URL(fileURLWithPath: source)
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true,
              let size = values.fileSize,
              size <= WindowRangerCLIProtocol.maximumMessageBytes else {
            throw CommandLineError.usage("Configuration input exceeds the maximum input size.")
        }
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private static func outputSkill(to rawPath: String?, force: Bool) throws {
        let content = WindowRangerCLIAgentSkill.content()
        guard let rawPath else {
            print(content, terminator: "")
            return
        }
        let destination = try WindowRangerCLISkillWriter.write(
            content: content,
            to: rawPath,
            force: force
        )
        print(destination.path)
    }

    private static func terminalSafe(_ value: String) -> String {
        let controls = CharacterSet.controlCharacters.union(.illegalCharacters)
        return String(value.unicodeScalars.map { controls.contains($0) ? " " : Character($0) })
    }

    private static func exitCode(for error: Error) -> ExitCode {
        switch error {
        case is CommandLineError:
            if case CommandLineError.usage = error { return .usage }
            if case let CommandLineError.service(code) = error {
                switch code {
                case .accessibilityRequired, .unauthorized: return .permission
                case .notFound, .conflict, .staleState, .confirmationRequired: return .rejected
                case .timedOut: return .timedOut
                case .unavailable: return .unavailable
                default: return .failure
                }
            }
            return .failure
        case CLIIPCTransportError.unavailable: return .unavailable
        case CLIIPCTransportError.timedOut: return .timedOut
        case CLIIPCTransportError.peerSignatureRejected,
             CLIIPCTransportError.peerPathRejected,
             CLIIPCTransportError.peerUserMismatch: return .permission
        default: return .failure
        }
    }

    private static func write(_ string: String, to handle: FileHandle, endingWithNewline: Bool = false) {
        write(Data((string + (endingWithNewline ? "\n" : "")).utf8), to: handle)
    }

    private static func write(_ data: Data, to handle: FileHandle, endingWithNewline: Bool = false) {
        handle.write(data)
        if endingWithNewline { handle.write(Data("\n".utf8)) }
    }

    private static var appVersion: String {
        guard let bundle = try? Bundle(url: enclosingAppURL()) else { return "unknown" }
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    private static let help = """
    Usage: windowranger <command> [options]

      actions [--json]                         List every stable action name
      action <name> [--args <json>] [--json]   Execute an action by name
      config get [--json]                      Print full configuration snapshot
      config validate <file|-> [--json]        Validate a full configuration document
      config apply <file|-> --replace [--json] Replace configuration by snapshot revision
      status [--json]                         Show runtime and permission status
      capabilities [--json]                   Show the versioned command surface
      workspaces [--names] [--json]           List workspace IDs and keys
      workspace <id-or-key> [--json]           Switch to one workspace
      layout <freeform|tiled|accordion> [--json]
                                                Change the current workspace layout
      pause [--json]                           Pause window-management writes
      resume [--json]                          Resume window-management writes
      skill [--output <directory-or-SKILL.md> [--force]]
                                                Print or safely write an agent skill
      version                                   Show the bundled app version

    Workspace names are omitted unless --names is explicitly supplied.
    """
}

WindowRangerCommandLine.main()
