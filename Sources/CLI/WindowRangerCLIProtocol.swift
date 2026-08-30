import Foundation

/// The stable schema shared by the bundled command-line client and its authenticated local
/// transport. This module has no process, filesystem, or window access: transport and command
/// routing must validate these values before doing any work.
enum WindowRangerCLIProtocol {
    static let version = 2
    static let configurationSchemaVersion = 1
    /// A complete profile library can legitimately be much larger than a single control request.
    /// Keep a hard ceiling so the same-user local socket can never become an unbounded allocator.
    static let maximumMessageBytes = 4 * 1_024 * 1_024
    static let maximumRequestIDLength = 64
    static let maximumWorkspaceKeyLength = 8
    /// Synced workspace names are bounded to 256 Unicode characters. Four bytes per scalar keeps
    /// every valid stored name representable while retaining a strict wire-size check.
    static let maximumWorkspaceNameLength = 1_024
    static let maximumWorkspaceCount = 128
    static let maximumActionNameLength = 64
    static let maximumActionArgumentCount = 16
    static let maximumJSONDepth = 64
    static let maximumJSONNodes = 100_000
    static let maximumJSONKeyLength = 256
    /// A request must reach the app's main actor before this window closes. It is deliberately
    /// shorter than the CLI transport timeout so a command cannot execute after the caller has
    /// already reported a timeout.
    static let requestExecutionWindowNanoseconds: UInt64 = 750_000_000

    static func decodeRequest(from data: Data) throws -> WindowRangerCLIRequestEnvelope {
        guard data.count <= maximumMessageBytes else {
            throw WindowRangerCLIValidationError.messageTooLarge
        }
        try validateRequestJSONShape(data)
        let request = try JSONDecoder().decode(WindowRangerCLIRequestEnvelope.self, from: data)
        try request.validate()
        return request
    }

    static func decodeResponse(from data: Data) throws -> WindowRangerCLIResponseEnvelope {
        guard data.count <= maximumMessageBytes else {
            throw WindowRangerCLIValidationError.messageTooLarge
        }
        try validateResponseJSONShape(data)
        let response = try JSONDecoder().decode(WindowRangerCLIResponseEnvelope.self, from: data)
        try response.validate()
        return response
    }

    static func isSafeRequestID(_ requestID: String) -> Bool {
        guard !requestID.isEmpty, requestID.utf8.count <= maximumRequestIDLength else { return false }
        return requestID.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || // 0-9
                ($0 >= 65 && $0 <= 90) || // A-Z
                ($0 >= 97 && $0 <= 122) || // a-z
                $0 == 45 || $0 == 46 || $0 == 95 // - . _
        }
    }

    static func isSafeWorkspaceKey(_ key: String) -> Bool {
        guard !key.isEmpty, key.utf8.count <= maximumWorkspaceKeyLength else { return false }
        return key.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) ||
                ($0 >= 65 && $0 <= 90) ||
                ($0 >= 97 && $0 <= 122) ||
                $0 == 45 || $0 == 95
        }
    }

    static func isSafeActionName(_ name: String) -> Bool {
        guard !name.isEmpty, name.utf8.count <= maximumActionNameLength else { return false }
        return name.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 122) || $0 == 45
        }
    }

    static func isSafeRevision(_ revision: String) -> Bool {
        guard (16...128).contains(revision.utf8.count) else { return false }
        return revision.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) ||
                ($0 >= 97 && $0 <= 122) || $0 == 45 || $0 == 95
        }
    }

    private static func validateRequestJSONShape(_ data: Data) throws {
        let envelope = try object(from: data)
        try requireOnlyKeys(envelope, ["protocolVersion", "requestID", "deadlineUptimeNanoseconds", "operation", "payload"])
        if let payload = envelope["payload"], !(payload is NSNull) {
            let object = try dictionary(payload)
            try requireOnlyKeys(object, [
                "workspaceID", "workspaceKey", "includeNames", "layout",
                "action", "arguments", "configuration", "expectedRevision",
                "confirmsReplacement",
            ])
        }
    }

    private static func validateResponseJSONShape(_ data: Data) throws {
        let envelope = try object(from: data)
        try requireOnlyKeys(envelope, ["protocolVersion", "requestID", "result", "error"])

        if let error = envelope["error"], !(error is NSNull) {
            try requireOnlyKeys(try dictionary(error), ["code"])
        }
        guard let result = envelope["result"], !(result is NSNull) else { return }
        let resultObject = try dictionary(result)
        guard let kind = resultObject["kind"] as? String else {
            throw WindowRangerCLIValidationError.invalidMessageSchema
        }
        switch kind {
        case "status":
            try requireOnlyKeys(resultObject, ["kind", "status"])
            try requireOnlyKeys(try dictionary(resultObject["status"]), ["isRunning", "isPaused", "accessibilityGranted"])
        case "capabilities":
            try requireOnlyKeys(resultObject, ["kind", "capabilities"])
            try requireOnlyKeys(try dictionary(resultObject["capabilities"]), [
                "protocolVersion", "configurationSchemaVersion", "operations",
                "supportsWorkspaceNames",
            ])
        case "actions":
            try requireOnlyKeys(resultObject, ["kind", "actions"])
            guard let actions = resultObject["actions"] as? [Any] else {
                throw WindowRangerCLIValidationError.invalidMessageSchema
            }
            for action in actions {
                try requireOnlyKeys(try dictionary(action), [
                    "name", "kind", "synopsis", "argumentNames", "requiresAccessibility",
                ])
            }
        case "configuration":
            try requireOnlyKeys(resultObject, ["kind", "configuration"])
            try requireOnlyKeys(
                try dictionary(resultObject["configuration"]),
                ["revision", "document"]
            )
        case "configuration_validation":
            try requireOnlyKeys(resultObject, ["kind", "configurationValidation"])
            try requireOnlyKeys(
                try dictionary(resultObject["configurationValidation"]),
                ["valid", "normalizedDocument"]
            )
        case "workspaces":
            try requireOnlyKeys(resultObject, ["kind", "workspaces"])
            guard let workspaces = resultObject["workspaces"] as? [Any] else {
                throw WindowRangerCLIValidationError.invalidMessageSchema
            }
            for workspace in workspaces {
                try requireOnlyKeys(try dictionary(workspace), ["id", "key", "name"])
            }
        case "accepted":
            try requireOnlyKeys(resultObject, ["kind"])
        default:
            throw WindowRangerCLIValidationError.invalidMessageSchema
        }
    }

    private static func object(from data: Data) throws -> [String: Any] {
        let value = try JSONSerialization.jsonObject(with: data, options: [])
        return try dictionary(value)
    }

    private static func dictionary(_ value: Any?) throws -> [String: Any] {
        guard let value, let dictionary = value as? [String: Any] else {
            throw WindowRangerCLIValidationError.invalidMessageSchema
        }
        return dictionary
    }

    private static func requireOnlyKeys(_ object: [String: Any], _ permitted: Set<String>) throws {
        guard Set(object.keys).isSubset(of: permitted) else {
            throw WindowRangerCLIValidationError.invalidMessageSchema
        }
    }
}

/// A bounded JSON tree keeps the helper independent of the app's internal model while allowing a
/// complete, versioned configuration document to cross the authenticated local bridge.
enum WindowRangerCLIJSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([WindowRangerCLIJSONValue])
    case object([String: WindowRangerCLIJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([WindowRangerCLIJSONValue].self) { self = .array(value) }
        else if let value = try? container.decode([String: WindowRangerCLIJSONValue].self) { self = .object(value) }
        else { throw WindowRangerCLIValidationError.invalidMessageSchema }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    func validate() throws {
        var nodes = 0
        try validate(depth: 0, nodes: &nodes)
    }

    private func validate(depth: Int, nodes: inout Int) throws {
        guard depth <= WindowRangerCLIProtocol.maximumJSONDepth,
              nodes < WindowRangerCLIProtocol.maximumJSONNodes else {
            throw WindowRangerCLIValidationError.invalidOperationPayload
        }
        nodes += 1
        switch self {
        case let .number(value):
            guard value.isFinite else { throw WindowRangerCLIValidationError.invalidOperationPayload }
        case let .array(values):
            for value in values { try value.validate(depth: depth + 1, nodes: &nodes) }
        case let .object(values):
            for (key, value) in values {
                guard !key.isEmpty,
                      key.utf8.count <= WindowRangerCLIProtocol.maximumJSONKeyLength else {
                    throw WindowRangerCLIValidationError.invalidOperationPayload
                }
                try value.validate(depth: depth + 1, nodes: &nodes)
            }
        case .null, .bool, .string:
            break
        }
    }

    /// Returns false when the candidate contains a field which the canonical decoded model does
    /// not know. Swift's synthesized `Decodable` normally ignores unknown keys; complete settings
    /// replacement must fail closed instead of silently dropping a misspelled preference.
    func containsNoUnknownFields(comparedTo canonical: WindowRangerCLIJSONValue) -> Bool {
        switch (self, canonical) {
        case let (.object(candidate), .object(known)):
            return candidate.allSatisfy { key, value in
                guard let knownValue = known[key] else { return false }
                return value.containsNoUnknownFields(comparedTo: knownValue)
            }
        case let (.array(candidate), .array(known)):
            guard candidate.count == known.count else { return false }
            return zip(candidate, known).allSatisfy {
                $0.containsNoUnknownFields(comparedTo: $1)
            }
        case (.null, .null), (.bool, .bool), (.number, .number), (.string, .string):
            return true
        default:
            return false
        }
    }
}

enum WindowRangerCLIValidationError: Error, Equatable, Sendable {
    case messageTooLarge
    case incompatibleProtocolVersion(Int)
    case invalidRequestID
    case invalidOperationPayload
    case invalidMessageSchema
    case invalidResponseEnvelope
    case invalidWorkspaceSummary
}

enum WindowRangerCLIOperation: String, Codable, CaseIterable, Sendable {
    case status
    case capabilities
    case listActions = "list_actions"
    case performAction = "perform_action"
    case getConfiguration = "get_configuration"
    case validateConfiguration = "validate_configuration"
    case applyConfiguration = "apply_configuration"
    case listWorkspaces = "list_workspaces"
    case activateWorkspace = "activate_workspace"
    case setLayout = "set_layout"
    case pause
    case resume
}

/// Wire-level layout names stay independent of the app model so the bundled helper only needs
/// the small public protocol module. `freeform` is the user-facing spelling; the app maps it to
/// its internal `.none` layout.
enum WindowRangerCLIWorkspaceLayout: String, Codable, CaseIterable, Sendable {
    case freeform
    case tiled
    case accordion
}

/// A fixed-field request payload keeps the operation boundary explicit. Configuration is the only
/// intentionally open JSON field and is decoded into the app's strict versioned model before use.
struct WindowRangerCLIRequestPayload: Codable, Equatable, Sendable {
    var workspaceID: UUID?
    var workspaceKey: String?
    var includeNames: Bool?
    var layout: WindowRangerCLIWorkspaceLayout?
    var action: String?
    var arguments: [String: WindowRangerCLIJSONValue]?
    var configuration: WindowRangerCLIJSONValue?
    var expectedRevision: String?
    var confirmsReplacement: Bool?

    init(
        workspaceID: UUID? = nil,
        workspaceKey: String? = nil,
        includeNames: Bool? = nil,
        layout: WindowRangerCLIWorkspaceLayout? = nil,
        action: String? = nil,
        arguments: [String: WindowRangerCLIJSONValue]? = nil,
        configuration: WindowRangerCLIJSONValue? = nil,
        expectedRevision: String? = nil,
        confirmsReplacement: Bool? = nil
    ) {
        self.workspaceID = workspaceID
        self.workspaceKey = workspaceKey
        self.includeNames = includeNames
        self.layout = layout
        self.action = action
        self.arguments = arguments
        self.configuration = configuration
        self.expectedRevision = expectedRevision
        self.confirmsReplacement = confirmsReplacement
    }

    var hasWorkspaceTarget: Bool {
        workspaceID != nil || workspaceKey != nil
    }
}

struct WindowRangerCLIRequestEnvelope: Codable, Equatable, Sendable {
    let protocolVersion: Int
    let requestID: String
    let deadlineUptimeNanoseconds: UInt64
    let operation: WindowRangerCLIOperation
    let payload: WindowRangerCLIRequestPayload?

    init(
        protocolVersion: Int = WindowRangerCLIProtocol.version,
        requestID: String,
        deadlineUptimeNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds + WindowRangerCLIProtocol.requestExecutionWindowNanoseconds,
        operation: WindowRangerCLIOperation,
        payload: WindowRangerCLIRequestPayload? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.requestID = requestID
        self.deadlineUptimeNanoseconds = deadlineUptimeNanoseconds
        self.operation = operation
        self.payload = payload
    }

    func validate() throws {
        guard protocolVersion == WindowRangerCLIProtocol.version else {
            throw WindowRangerCLIValidationError.incompatibleProtocolVersion(protocolVersion)
        }
        guard WindowRangerCLIProtocol.isSafeRequestID(requestID) else {
            throw WindowRangerCLIValidationError.invalidRequestID
        }
        guard deadlineUptimeNanoseconds > 0 else {
            throw WindowRangerCLIValidationError.invalidOperationPayload
        }

        let value = payload ?? WindowRangerCLIRequestPayload()
        let hasExactlyOneTarget = (value.workspaceID != nil) != (value.workspaceKey != nil)
        if let key = value.workspaceKey, !WindowRangerCLIProtocol.isSafeWorkspaceKey(key) {
            throw WindowRangerCLIValidationError.invalidOperationPayload
        }

        if let arguments = value.arguments {
            guard arguments.count <= WindowRangerCLIProtocol.maximumActionArgumentCount else {
                throw WindowRangerCLIValidationError.invalidOperationPayload
            }
            for (name, argument) in arguments {
                guard WindowRangerCLIProtocol.isSafeActionName(name) else {
                    throw WindowRangerCLIValidationError.invalidOperationPayload
                }
                try argument.validate()
            }
        }
        try value.configuration?.validate()
        if let revision = value.expectedRevision,
           !WindowRangerCLIProtocol.isSafeRevision(revision) {
            throw WindowRangerCLIValidationError.invalidOperationPayload
        }

        let hasConfigurationFields = value.configuration != nil || value.expectedRevision != nil ||
            value.confirmsReplacement != nil
        let hasActionFields = value.action != nil || value.arguments != nil
        let hasLegacyFields = value.workspaceID != nil || value.workspaceKey != nil ||
            value.includeNames != nil || value.layout != nil

        switch operation {
        case .status, .capabilities, .listActions, .getConfiguration, .pause, .resume:
            guard payload == nil else { throw WindowRangerCLIValidationError.invalidOperationPayload }
        case .performAction:
            guard let action = value.action,
                  WindowRangerCLIProtocol.isSafeActionName(action),
                  !hasLegacyFields, !hasConfigurationFields,
                  value.arguments != nil
            else { throw WindowRangerCLIValidationError.invalidOperationPayload }
        case .validateConfiguration:
            guard value.configuration != nil, !hasLegacyFields, !hasActionFields,
                  value.expectedRevision == nil, value.confirmsReplacement == nil
            else { throw WindowRangerCLIValidationError.invalidOperationPayload }
        case .applyConfiguration:
            guard value.configuration != nil, !hasLegacyFields, !hasActionFields,
                  value.expectedRevision != nil, value.confirmsReplacement == true
            else { throw WindowRangerCLIValidationError.invalidOperationPayload }
        case .listWorkspaces:
            guard value.workspaceID == nil, value.workspaceKey == nil, value.layout == nil,
                  !hasActionFields, !hasConfigurationFields else {
                throw WindowRangerCLIValidationError.invalidOperationPayload
            }
        case .activateWorkspace:
            guard hasExactlyOneTarget, value.includeNames == nil, value.layout == nil,
                  !hasActionFields, !hasConfigurationFields else {
                throw WindowRangerCLIValidationError.invalidOperationPayload
            }
        case .setLayout:
            guard value.workspaceID == nil, value.workspaceKey == nil,
                  value.includeNames == nil, value.layout != nil,
                  !hasActionFields, !hasConfigurationFields
            else {
                throw WindowRangerCLIValidationError.invalidOperationPayload
            }
        }
    }
}

enum WindowRangerCLIErrorCode: String, Codable, Error, Sendable {
    case invalidRequest = "invalid_request"
    case unsupportedProtocolVersion = "unsupported_protocol_version"
    case unavailable
    case unauthorized
    case accessibilityRequired = "accessibility_required"
    case notFound = "not_found"
    case conflict
    case staleState = "stale_state"
    case confirmationRequired = "confirmation_required"
    case timedOut = "timed_out"
    case cancelled
    case internalError = "internal_error"
}

/// Errors are intentionally code-only. A transport may log private diagnostics locally, but it
/// must not return titles, paths, process information, or other user data through this envelope.
struct WindowRangerCLIError: Codable, Equatable, Sendable {
    let code: WindowRangerCLIErrorCode

    init(code: WindowRangerCLIErrorCode) {
        self.code = code
    }
}

struct WindowRangerCLIStatus: Codable, Equatable, Sendable {
    let isRunning: Bool
    let isPaused: Bool
    let accessibilityGranted: Bool
}

struct WindowRangerCLICapabilities: Codable, Equatable, Sendable {
    let protocolVersion: Int
    let configurationSchemaVersion: Int
    let operations: [WindowRangerCLIOperation]
    let supportsWorkspaceNames: Bool

    init(
        protocolVersion: Int = WindowRangerCLIProtocol.version,
        configurationSchemaVersion: Int = WindowRangerCLIProtocol.configurationSchemaVersion,
        operations: [WindowRangerCLIOperation] = WindowRangerCLICommandCatalog.operations,
        supportsWorkspaceNames: Bool = true
    ) {
        self.protocolVersion = protocolVersion
        self.configurationSchemaVersion = configurationSchemaVersion
        self.operations = operations
        self.supportsWorkspaceNames = supportsWorkspaceNames
    }
}

struct WindowRangerCLIActionDescriptor: Codable, Equatable, Sendable {
    let name: String
    let kind: WindowRangerCLICommandKind
    let synopsis: String
    let argumentNames: [String]
    let requiresAccessibility: Bool

    func validate() throws {
        guard WindowRangerCLIProtocol.isSafeActionName(name),
              argumentNames.count <= WindowRangerCLIProtocol.maximumActionArgumentCount,
              argumentNames.allSatisfy(WindowRangerCLIProtocol.isSafeActionName)
        else { throw WindowRangerCLIValidationError.invalidResponseEnvelope }
    }
}

struct WindowRangerCLIConfigurationSnapshot: Codable, Equatable, Sendable {
    let revision: String
    let document: WindowRangerCLIJSONValue

    func validate() throws {
        guard WindowRangerCLIProtocol.isSafeRevision(revision) else {
            throw WindowRangerCLIValidationError.invalidResponseEnvelope
        }
        try document.validate()
    }
}

struct WindowRangerCLIConfigurationValidation: Codable, Equatable, Sendable {
    let valid: Bool
    let normalizedDocument: WindowRangerCLIJSONValue?

    func validate() throws {
        guard valid == (normalizedDocument != nil) else {
            throw WindowRangerCLIValidationError.invalidResponseEnvelope
        }
        try normalizedDocument?.validate()
    }
}

/// Workspace names are opt-in because they are user-created text. The default initializer keeps
/// the result safe for agents and plugin logs, while callers must explicitly request the name.
struct WindowRangerCLIWorkspaceSummary: Codable, Equatable, Sendable {
    let id: UUID
    let key: String
    let name: String?

    init(id: UUID, key: String, name: String? = nil) {
        self.id = id
        self.key = key
        self.name = name
    }

    func validate() throws {
        guard (key.isEmpty || WindowRangerCLIProtocol.isSafeWorkspaceKey(key)),
              name?.utf8.count ?? 0 <= WindowRangerCLIProtocol.maximumWorkspaceNameLength
        else {
            throw WindowRangerCLIValidationError.invalidWorkspaceSummary
        }
    }
}

enum WindowRangerCLIResponsePayload: Codable, Equatable, Sendable {
    case status(WindowRangerCLIStatus)
    case capabilities(WindowRangerCLICapabilities)
    case actions([WindowRangerCLIActionDescriptor])
    case configuration(WindowRangerCLIConfigurationSnapshot)
    case configurationValidation(WindowRangerCLIConfigurationValidation)
    case workspaces([WindowRangerCLIWorkspaceSummary])
    case accepted

    private enum CodingKeys: String, CodingKey {
        case kind
        case status
        case capabilities
        case actions
        case configuration
        case configurationValidation
        case workspaces
    }

    private enum Kind: String, Codable {
        case status
        case capabilities
        case actions
        case configuration
        case configurationValidation = "configuration_validation"
        case workspaces
        case accepted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .status:
            self = .status(try container.decode(WindowRangerCLIStatus.self, forKey: .status))
        case .capabilities:
            self = .capabilities(try container.decode(WindowRangerCLICapabilities.self, forKey: .capabilities))
        case .actions:
            self = .actions(try container.decode([WindowRangerCLIActionDescriptor].self, forKey: .actions))
        case .configuration:
            self = .configuration(try container.decode(WindowRangerCLIConfigurationSnapshot.self, forKey: .configuration))
        case .configurationValidation:
            self = .configurationValidation(
                try container.decode(WindowRangerCLIConfigurationValidation.self, forKey: .configurationValidation)
            )
        case .workspaces:
            self = .workspaces(try container.decode([WindowRangerCLIWorkspaceSummary].self, forKey: .workspaces))
        case .accepted:
            self = .accepted
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .status(value):
            try container.encode(Kind.status, forKey: .kind)
            try container.encode(value, forKey: .status)
        case let .capabilities(value):
            try container.encode(Kind.capabilities, forKey: .kind)
            try container.encode(value, forKey: .capabilities)
        case let .actions(value):
            try container.encode(Kind.actions, forKey: .kind)
            try container.encode(value, forKey: .actions)
        case let .configuration(value):
            try container.encode(Kind.configuration, forKey: .kind)
            try container.encode(value, forKey: .configuration)
        case let .configurationValidation(value):
            try container.encode(Kind.configurationValidation, forKey: .kind)
            try container.encode(value, forKey: .configurationValidation)
        case let .workspaces(value):
            try container.encode(Kind.workspaces, forKey: .kind)
            try container.encode(value, forKey: .workspaces)
        case .accepted:
            try container.encode(Kind.accepted, forKey: .kind)
        }
    }

    func validate() throws {
        switch self {
        case let .capabilities(capabilities):
            guard capabilities.protocolVersion == WindowRangerCLIProtocol.version,
                  capabilities.configurationSchemaVersion == WindowRangerCLIProtocol.configurationSchemaVersion,
                  capabilities.operations == WindowRangerCLICommandCatalog.operations
            else {
                throw WindowRangerCLIValidationError.invalidResponseEnvelope
            }
        case let .actions(actions):
            guard actions == WindowRangerCLICommandCatalog.actions else {
                throw WindowRangerCLIValidationError.invalidResponseEnvelope
            }
            try actions.forEach { try $0.validate() }
        case let .configuration(configuration):
            try configuration.validate()
        case let .configurationValidation(validation):
            try validation.validate()
        case let .workspaces(workspaces):
            guard workspaces.count <= WindowRangerCLIProtocol.maximumWorkspaceCount else {
                throw WindowRangerCLIValidationError.invalidResponseEnvelope
            }
            try workspaces.forEach { try $0.validate() }
        case .status, .accepted:
            break
        }
    }
}

struct WindowRangerCLIResponseEnvelope: Codable, Equatable, Sendable {
    let protocolVersion: Int
    let requestID: String
    let result: WindowRangerCLIResponsePayload?
    let error: WindowRangerCLIError?

    init(
        protocolVersion: Int = WindowRangerCLIProtocol.version,
        requestID: String,
        result: WindowRangerCLIResponsePayload? = nil,
        error: WindowRangerCLIError? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.requestID = requestID
        self.result = result
        self.error = error
    }

    func validate() throws {
        guard protocolVersion == WindowRangerCLIProtocol.version else {
            throw WindowRangerCLIValidationError.incompatibleProtocolVersion(protocolVersion)
        }
        guard WindowRangerCLIProtocol.isSafeRequestID(requestID) else {
            throw WindowRangerCLIValidationError.invalidRequestID
        }
        guard (result != nil) != (error != nil) else {
            throw WindowRangerCLIValidationError.invalidResponseEnvelope
        }
        try result?.validate()
    }
}
