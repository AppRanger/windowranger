import Foundation

@MainActor
final class WindowRangerCLIRequestRouter {
    struct Snapshot {
        let workspaces: [WorkspaceDefinition]
        let accessibilityGranted: Bool
        let isPaused: Bool
    }

    typealias SnapshotProvider = () -> Snapshot
    typealias CommandDispatcher = (WindowManagerCommand, String) -> WindowManagerCommandDispatchResult
    typealias ActionExecutor = (
        String,
        [String: String],
        String,
        UInt64,
        @escaping (WindowRangerCLIErrorCode?) -> Void
    ) -> Void
    typealias ConfigurationProvider = () -> Result<WindowRangerCLIConfigurationSnapshot, WindowRangerCLIErrorCode>
    typealias ConfigurationValidator = (WindowRangerCLIJSONValue) -> Result<WindowRangerCLIJSONValue, WindowRangerCLIErrorCode>
    typealias ConfigurationApplier = (
        WindowRangerCLIJSONValue,
        String
    ) -> Result<WindowRangerCLIConfigurationSnapshot, WindowRangerCLIErrorCode>

    private struct CachedResponse {
        let request: Data
        let response: Data
    }

    private struct InFlightRequest {
        let request: Data
        var completions: [(Data) -> Void]
    }

    private static let maximumCachedResponses = 128
    private let snapshotProvider: SnapshotProvider
    private let commandDispatcher: CommandDispatcher
    private let actionExecutor: ActionExecutor
    private let configurationProvider: ConfigurationProvider
    private let configurationValidator: ConfigurationValidator
    private let configurationApplier: ConfigurationApplier
    private let uptimeNanoseconds: () -> UInt64
    private var cachedResponses: [String: CachedResponse] = [:]
    private var cachedRequestOrder: [String] = []
    private var inFlightRequests: [String: InFlightRequest] = [:]

    init(
        snapshotProvider: @escaping SnapshotProvider,
        commandDispatcher: @escaping CommandDispatcher,
        actionExecutor: @escaping ActionExecutor = { _, _, _, _, completion in completion(.unavailable) },
        configurationProvider: @escaping ConfigurationProvider = { .failure(.unavailable) },
        configurationValidator: @escaping ConfigurationValidator = { _ in .failure(.unavailable) },
        configurationApplier: @escaping ConfigurationApplier = { _, _ in .failure(.unavailable) },
        uptimeNanoseconds: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    ) {
        self.snapshotProvider = snapshotProvider
        self.commandDispatcher = commandDispatcher
        self.actionExecutor = actionExecutor
        self.configurationProvider = configurationProvider
        self.configurationValidator = configurationValidator
        self.configurationApplier = configurationApplier
        self.uptimeNanoseconds = uptimeNanoseconds
    }

    func handle(_ data: Data) -> Data {
        var response = Data()
        handle(data) { response = $0 }
        return response
    }

    func handle(_ data: Data, completion: @escaping (Data) -> Void) {
        let request: WindowRangerCLIRequestEnvelope
        do {
            request = try WindowRangerCLIProtocol.decodeRequest(from: data)
        } catch {
            let code: WindowRangerCLIErrorCode
            if let validationError = error as? WindowRangerCLIValidationError,
               case .incompatibleProtocolVersion = validationError {
                code = .unsupportedProtocolVersion
            } else {
                code = .invalidRequest
            }
            completion(encodedError(
                requestID: safeRequestID(in: data) ?? "invalid-request",
                code: code
            ))
            return
        }

        if let cached = cachedResponses[request.requestID] {
            completion(cached.request == data
                ? cached.response
                : encodedError(requestID: request.requestID, code: .conflict))
            return
        }
        if var inFlight = inFlightRequests[request.requestID] {
            guard inFlight.request == data else {
                completion(encodedError(requestID: request.requestID, code: .conflict))
                return
            }
            inFlight.completions.append(completion)
            inFlightRequests[request.requestID] = inFlight
            return
        }

        guard request.deadlineUptimeNanoseconds > uptimeNanoseconds() else {
            let response = encodedError(requestID: request.requestID, code: .timedOut)
            remember(request: data, response: response, requestID: request.requestID)
            completion(response)
            return
        }

        if request.operation == .performAction {
            inFlightRequests[request.requestID] = InFlightRequest(
                request: data,
                completions: [completion]
            )
            DispatchQueue.main.asyncAfter(
                deadline: DispatchTime(uptimeNanoseconds: request.deadlineUptimeNanoseconds)
            ) { [weak self] in
                guard let self, self.inFlightRequests[request.requestID] != nil else { return }
                self.finishInFlight(
                    request: data,
                    response: self.encodedError(
                        requestID: request.requestID,
                        code: .timedOut
                    ),
                    requestID: request.requestID
                )
            }
            routeAction(request) { [weak self] response in
                guard let self else { return }
                self.finishInFlight(
                    request: data,
                    response: response,
                    requestID: request.requestID
                )
            }
            return
        }

        let response = route(request)
        remember(request: data, response: response, requestID: request.requestID)
        completion(response)
    }

    private func route(_ request: WindowRangerCLIRequestEnvelope) -> Data {
        let snapshot = snapshotProvider()
        switch request.operation {
        case .status:
            return encodedResult(
                requestID: request.requestID,
                result: .status(.init(
                    isRunning: true,
                    isPaused: snapshot.isPaused,
                    accessibilityGranted: snapshot.accessibilityGranted
                ))
            )
        case .capabilities:
            return encodedResult(
                requestID: request.requestID,
                result: .capabilities(.init())
            )
        case .listActions:
            return encodedResult(
                requestID: request.requestID,
                result: .actions(WindowRangerCLICommandCatalog.actions)
            )
        case .performAction:
            return encodedError(requestID: request.requestID, code: .internalError)
        case .getConfiguration:
            switch configurationProvider() {
            case let .success(configuration):
                return encodedResult(requestID: request.requestID, result: .configuration(configuration))
            case let .failure(error):
                return encodedError(requestID: request.requestID, code: error)
            }
        case .validateConfiguration:
            guard let configuration = request.payload?.configuration else {
                return encodedError(requestID: request.requestID, code: .invalidRequest)
            }
            switch configurationValidator(configuration) {
            case let .success(normalized):
                return encodedResult(
                    requestID: request.requestID,
                    result: .configurationValidation(.init(valid: true, normalizedDocument: normalized))
                )
            case let .failure(error):
                return encodedError(requestID: request.requestID, code: error)
            }
        case .applyConfiguration:
            guard let configuration = request.payload?.configuration,
                  let expectedRevision = request.payload?.expectedRevision,
                  request.payload?.confirmsReplacement == true
            else { return encodedError(requestID: request.requestID, code: .invalidRequest) }
            switch configurationApplier(configuration, expectedRevision) {
            case let .success(updated):
                return encodedResult(requestID: request.requestID, result: .configuration(updated))
            case let .failure(error):
                return encodedError(requestID: request.requestID, code: error)
            }
        case .listWorkspaces:
            guard snapshot.workspaces.count <= WindowRangerCLIProtocol.maximumWorkspaceCount else {
                return encodedError(requestID: request.requestID, code: .internalError)
            }
            let includeNames = request.payload?.includeNames == true
            return encodedResult(
                requestID: request.requestID,
                result: .workspaces(snapshot.workspaces.map {
                    WindowRangerCLIWorkspaceSummary(
                        id: $0.id,
                        key: $0.key,
                        name: includeNames ? $0.name : nil
                    )
                })
            )
        case .activateWorkspace:
            guard snapshot.accessibilityGranted else {
                return encodedError(requestID: request.requestID, code: .accessibilityRequired)
            }
            guard let workspace = resolveWorkspace(request.payload, in: snapshot.workspaces) else {
                return encodedError(requestID: request.requestID, code: .notFound)
            }
            return dispatch(
                .switchWorkspace(workspace.id),
                requestID: request.requestID
            )
        case .setLayout:
            guard snapshot.accessibilityGranted else {
                return encodedError(requestID: request.requestID, code: .accessibilityRequired)
            }
            guard let layout = request.payload?.layout else {
                return encodedError(requestID: request.requestID, code: .invalidRequest)
            }
            return dispatch(.setLayout(appLayout(layout)), requestID: request.requestID)
        case .pause:
            return dispatch(.setPauseMode(true), requestID: request.requestID)
        case .resume:
            return dispatch(.setPauseMode(false), requestID: request.requestID)
        }
    }

    private func routeAction(
        _ request: WindowRangerCLIRequestEnvelope,
        completion: @escaping (Data) -> Void
    ) {
        let snapshot = snapshotProvider()
        guard let action = request.payload?.action,
              let descriptor = WindowRangerCLICommandCatalog.action(named: action),
              let arguments = stringArguments(request.payload?.arguments ?? [:]),
              Set(arguments.keys).isSubset(of: Set(descriptor.argumentNames))
        else {
            completion(encodedError(requestID: request.requestID, code: .invalidRequest))
            return
        }
        guard WindowRangerCLICommandCatalog.actionConfirmationIsSatisfied(
            action: action,
            arguments: arguments
        ) else {
            completion(encodedError(requestID: request.requestID, code: .confirmationRequired))
            return
        }
        if descriptor.requiresAccessibility, !snapshot.accessibilityGranted {
            completion(encodedError(requestID: request.requestID, code: .accessibilityRequired))
            return
        }
        actionExecutor(
            action,
            arguments,
            request.requestID,
            request.deadlineUptimeNanoseconds
        ) { [weak self] error in
            guard let self else { return }
            if let error {
                completion(self.encodedError(requestID: request.requestID, code: error))
            } else {
                completion(self.encodedResult(requestID: request.requestID, result: .accepted))
            }
        }
    }

    private func dispatch(_ command: WindowManagerCommand, requestID: String) -> Data {
        switch commandDispatcher(command, requestID) {
        case .dispatched:
            encodedResult(requestID: requestID, result: .accepted)
        case .rejectedReentrant:
            encodedError(requestID: requestID, code: .conflict)
        }
    }

    private func resolveWorkspace(
        _ payload: WindowRangerCLIRequestPayload?,
        in workspaces: [WorkspaceDefinition]
    ) -> WorkspaceDefinition? {
        if let id = payload?.workspaceID {
            return workspaces.first { $0.id == id }
        }
        if let key = payload?.workspaceKey {
            return workspaces.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }
        }
        return nil
    }

    private func appLayout(_ layout: WindowRangerCLIWorkspaceLayout) -> WorkspaceLayout {
        switch layout {
        case .freeform: .none
        case .tiled: .tiled
        case .accordion: .accordion
        }
    }

    private func stringArguments(
        _ arguments: [String: WindowRangerCLIJSONValue]
    ) -> [String: String]? {
        var result: [String: String] = [:]
        for (key, value) in arguments {
            switch value {
            case let .string(string): result[key] = string
            case let .number(number):
                result[key] = number.rounded() == number
                    ? String(format: "%.0f", number)
                    : String(number)
            case let .bool(boolean): result[key] = boolean ? "true" : "false"
            case .null, .array, .object: return nil
            }
        }
        return result
    }

    private func remember(request: Data, response: Data, requestID: String) {
        cachedResponses[requestID] = CachedResponse(request: request, response: response)
        cachedRequestOrder.append(requestID)
        while cachedRequestOrder.count > Self.maximumCachedResponses {
            cachedResponses.removeValue(forKey: cachedRequestOrder.removeFirst())
        }
    }

    private func finishInFlight(request: Data, response: Data, requestID: String) {
        guard let inFlight = inFlightRequests.removeValue(forKey: requestID),
              inFlight.request == request else { return }
        remember(request: request, response: response, requestID: requestID)
        for completion in inFlight.completions { completion(response) }
    }

    private func safeRequestID(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let requestID = object["requestID"] as? String,
              WindowRangerCLIProtocol.isSafeRequestID(requestID) else { return nil }
        return requestID
    }

    private func encodedResult(
        requestID: String,
        result: WindowRangerCLIResponsePayload
    ) -> Data {
        let response = WindowRangerCLIResponseEnvelope(requestID: requestID, result: result)
        guard (try? response.validate()) != nil else {
            return encode(.init(requestID: requestID, error: .init(code: .internalError)))
        }
        return encode(response)
    }

    private func encodedError(requestID: String, code: WindowRangerCLIErrorCode) -> Data {
        encode(.init(requestID: requestID, error: .init(code: code)))
    }

    private func encode(_ response: WindowRangerCLIResponseEnvelope) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(response)) ?? Data()
    }
}
