import XCTest

@MainActor
final class WindowRangerCLIRequestRouterTests: XCTestCase {
    private let workspaceID = UUID(uuidString: "97000000-0000-0000-0000-000000000001")!

    func testStatusAndWorkspaceNamesFollowPrivacyContract() throws {
        let router = makeRouter()

        let status = try response(from: router, operation: .status)
        XCTAssertEqual(
            status.result,
            .status(.init(isRunning: true, isPaused: false, accessibilityGranted: true))
        )

        let privateList = try response(
            from: router,
            operation: .listWorkspaces,
            payload: .init(includeNames: false)
        )
        guard case let .workspaces(privateWorkspaces) = privateList.result else {
            return XCTFail("Expected workspaces")
        }
        XCTAssertNil(privateWorkspaces.first?.name)

        let namedList = try response(
            from: router,
            operation: .listWorkspaces,
            payload: .init(includeNames: true)
        )
        guard case let .workspaces(namedWorkspaces) = namedList.result else {
            return XCTFail("Expected workspaces")
        }
        XCTAssertEqual(namedWorkspaces.first?.name, "Private Work")
    }

    func testControlsUseCanonicalCommandsAndMapFreeformLayout() throws {
        var commands: [WindowManagerCommand] = []
        let router = makeRouter { command, _ in
            commands.append(command)
            return .dispatched
        }

        _ = try response(
            from: router,
            operation: .activateWorkspace,
            payload: .init(workspaceKey: "W")
        )
        _ = try response(
            from: router,
            operation: .setLayout,
            payload: .init(layout: .freeform)
        )
        _ = try response(from: router, operation: .pause)
        _ = try response(from: router, operation: .resume)

        XCTAssertEqual(commands, [
            .switchWorkspace(workspaceID),
            .setLayout(.none),
            .setPauseMode(true),
            .setPauseMode(false),
        ])
    }

    func testAccessibilityBlocksWindowControls() throws {
        var dispatched = false
        let router = makeRouter(
            accessibilityGranted: false,
            dispatcher: { _, _ in
                dispatched = true
                return .dispatched
            }
        )

        let response = try response(
            from: router,
            operation: .activateWorkspace,
            payload: .init(workspaceID: workspaceID)
        )
        XCTAssertEqual(response.error?.code, .accessibilityRequired)
        XCTAssertFalse(dispatched)
    }

    func testRequestIDsMakeControlRetriesIdempotent() throws {
        var dispatchCount = 0
        let router = makeRouter { _, _ in
            dispatchCount += 1
            return .dispatched
        }
        let request = WindowRangerCLIRequestEnvelope(
            requestID: "same-request",
            operation: .pause
        )
        let data = try JSONEncoder().encode(request)

        let first = router.handle(data)
        let second = router.handle(data)

        XCTAssertEqual(first, second)
        XCTAssertEqual(dispatchCount, 1)
    }

    func testReusingRequestIDForDifferentBodyIsRejected() throws {
        let router = makeRouter()
        let first = WindowRangerCLIRequestEnvelope(requestID: "same-request", operation: .pause)
        let second = WindowRangerCLIRequestEnvelope(requestID: "same-request", operation: .resume)

        _ = router.handle(try JSONEncoder().encode(first))
        let response = try WindowRangerCLIProtocol.decodeResponse(
            from: router.handle(try JSONEncoder().encode(second))
        )

        XCTAssertEqual(response.error?.code, .conflict)
    }

    func testExpiredControlRequestIsRejectedBeforeDispatch() throws {
        var dispatched = false
        let router = WindowRangerCLIRequestRouter(
            snapshotProvider: { [workspaceID] in
                .init(
                    workspaces: [.init(id: workspaceID, name: "Private Work", key: "w")],
                    accessibilityGranted: true,
                    isPaused: false
                )
            },
            commandDispatcher: { _, _ in
                dispatched = true
                return .dispatched
            },
            uptimeNanoseconds: { 1_000 }
        )
        let request = WindowRangerCLIRequestEnvelope(
            requestID: "delayed-main-thread",
            deadlineUptimeNanoseconds: 999,
            operation: .pause
        )

        let response = try WindowRangerCLIProtocol.decodeResponse(
            from: router.handle(try JSONEncoder().encode(request))
        )

        XCTAssertEqual(response.error?.code, .timedOut)
        XCTAssertFalse(dispatched)
    }

    func testInvalidAndUnsupportedRequestsReturnSafeCodeOnlyErrors() throws {
        let router = makeRouter()
        let invalid = try WindowRangerCLIProtocol.decodeResponse(
            from: router.handle(Data(#"{"requestID":"safe-id","surprise":"private"}"#.utf8))
        )
        XCTAssertEqual(invalid.error?.code, .invalidRequest)

        let unsupportedRequest = WindowRangerCLIRequestEnvelope(
            protocolVersion: WindowRangerCLIProtocol.version + 1,
            requestID: "safe-id",
            deadlineUptimeNanoseconds: 1,
            operation: .status
        )
        let unsupported = try WindowRangerCLIProtocol.decodeResponse(
            from: router.handle(try JSONEncoder().encode(unsupportedRequest))
        )
        XCTAssertEqual(unsupported.error?.code, .unsupportedProtocolVersion)
    }

    func testActionUsesAsyncExecutorAndCarriesExecutionDeadline() async throws {
        let completed = expectation(description: "async action completed")
        var capturedDeadline: UInt64?
        var capturedArguments: [String: String]?
        let deadline = DispatchTime.now().uptimeNanoseconds + 500_000_000
        let router = WindowRangerCLIRequestRouter(
            snapshotProvider: { [workspaceID] in
                .init(
                    workspaces: [.init(id: workspaceID, name: "Private Work", key: "w")],
                    accessibilityGranted: true,
                    isPaused: false
                )
            },
            commandDispatcher: { _, _ in .dispatched },
            actionExecutor: { action, arguments, requestID, deadline, completion in
                XCTAssertEqual(action, "cycle-workspace")
                XCTAssertEqual(requestID, "async-action")
                capturedDeadline = deadline
                capturedArguments = arguments
                DispatchQueue.main.async { completion(nil) }
            },
            uptimeNanoseconds: { 1_000 }
        )
        let request = WindowRangerCLIRequestEnvelope(
            requestID: "async-action",
            deadlineUptimeNanoseconds: deadline,
            operation: .performAction,
            payload: .init(action: "cycle-workspace", arguments: ["offset": .number(1)])
        )

        router.handle(try JSONEncoder().encode(request)) { data in
            do {
                let response = try WindowRangerCLIProtocol.decodeResponse(from: data)
                XCTAssertEqual(response.result, .accepted)
            } catch {
                XCTFail("Could not decode action response: \(error)")
            }
            completed.fulfill()
        }

        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(capturedDeadline, deadline)
        XCTAssertEqual(capturedArguments, ["offset": "1"])
    }

    func testConcurrentActionRetriesCoalesceAndConflictingBodyIsRejected() throws {
        var executorCompletions: [(WindowRangerCLIErrorCode?) -> Void] = []
        var executionCount = 0
        let router = WindowRangerCLIRequestRouter(
            snapshotProvider: { [workspaceID] in
                .init(
                    workspaces: [.init(id: workspaceID, name: "Private Work", key: "w")],
                    accessibilityGranted: true,
                    isPaused: false
                )
            },
            commandDispatcher: { _, _ in .dispatched },
            actionExecutor: { _, _, _, _, completion in
                executionCount += 1
                executorCompletions.append(completion)
            }
        )
        let request = WindowRangerCLIRequestEnvelope(
            requestID: "concurrent-action",
            operation: .performAction,
            payload: .init(action: "cycle-workspace", arguments: ["offset": .number(1)])
        )
        let requestData = try JSONEncoder().encode(request)
        var responses: [Data] = []

        router.handle(requestData) { responses.append($0) }
        router.handle(requestData) { responses.append($0) }

        let conflict = WindowRangerCLIRequestEnvelope(
            requestID: "concurrent-action",
            deadlineUptimeNanoseconds: request.deadlineUptimeNanoseconds,
            operation: .performAction,
            payload: .init(action: "cycle-workspace", arguments: ["offset": .number(-1)])
        )
        router.handle(try JSONEncoder().encode(conflict)) { responses.append($0) }

        XCTAssertEqual(executionCount, 1)
        XCTAssertEqual(responses.count, 1)
        XCTAssertEqual(
            try WindowRangerCLIProtocol.decodeResponse(from: responses[0]).error?.code,
            .conflict
        )

        executorCompletions[0](nil)
        XCTAssertEqual(responses.count, 3)
        XCTAssertEqual(
            try WindowRangerCLIProtocol.decodeResponse(from: responses[1]).result,
            .accepted
        )
        XCTAssertEqual(responses[1], responses[2])
    }

    func testUnfinishedAsyncActionExpiresAndLateCompletionIsIgnored() async throws {
        let responseReceived = expectation(description: "deadline response")
        var actionCompletion: ((WindowRangerCLIErrorCode?) -> Void)?
        var responses: [Data] = []
        let router = WindowRangerCLIRequestRouter(
            snapshotProvider: { [workspaceID] in
                .init(
                    workspaces: [.init(id: workspaceID, name: "Private Work", key: "w")],
                    accessibilityGranted: true,
                    isPaused: false
                )
            },
            commandDispatcher: { _, _ in .dispatched },
            actionExecutor: { _, _, _, _, completion in actionCompletion = completion }
        )
        let request = WindowRangerCLIRequestEnvelope(
            requestID: "action-deadline",
            deadlineUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds + 20_000_000,
            operation: .performAction,
            payload: .init(action: "cycle-workspace", arguments: ["offset": .number(1)])
        )

        router.handle(try JSONEncoder().encode(request)) { data in
            responses.append(data)
            responseReceived.fulfill()
        }
        await fulfillment(of: [responseReceived], timeout: 1)
        XCTAssertEqual(responses.count, 1)
        XCTAssertEqual(
            try WindowRangerCLIProtocol.decodeResponse(from: responses[0]).error?.code,
            .timedOut
        )

        actionCompletion?(nil)
        XCTAssertEqual(responses.count, 1)
    }

    func testConfigurationApplyReturnsApplierConflictWithoutSuccess() throws {
        var applied = false
        let router = WindowRangerCLIRequestRouter(
            snapshotProvider: { [workspaceID] in
                .init(
                    workspaces: [.init(id: workspaceID, name: "Private Work", key: "w")],
                    accessibilityGranted: true,
                    isPaused: false
                )
            },
            commandDispatcher: { _, _ in .dispatched },
            configurationApplier: { _, revision in
                applied = true
                XCTAssertEqual(revision, "fnv1a64-0123456789abcdef")
                return .failure(.conflict)
            }
        )
        let request = WindowRangerCLIRequestEnvelope(
            requestID: "stale-config",
            operation: .applyConfiguration,
            payload: .init(
                configuration: .object(["schemaVersion": .number(1)]),
                expectedRevision: "fnv1a64-0123456789abcdef",
                confirmsReplacement: true
            )
        )
        let result = try WindowRangerCLIProtocol.decodeResponse(
            from: router.handle(try JSONEncoder().encode(request))
        )

        XCTAssertTrue(applied)
        XCTAssertEqual(result.error?.code, .conflict)
    }

    func testCloudReplacementNeverReachesExecutorWithoutExactConfirmation() throws {
        var executed = false
        let router = WindowRangerCLIRequestRouter(
            snapshotProvider: { [workspaceID] in
                .init(
                    workspaces: [.init(id: workspaceID, name: "Private Work", key: "w")],
                    accessibilityGranted: true,
                    isPaused: false
                )
            },
            commandDispatcher: { _, _ in .dispatched },
            actionExecutor: { _, _, _, _, completion in
                executed = true
                completion(nil)
            }
        )
        let request = WindowRangerCLIRequestEnvelope(
            requestID: "cloud-replacement",
            operation: .performAction,
            payload: .init(action: "replace-icloud-with-local", arguments: [:])
        )
        let response = try WindowRangerCLIProtocol.decodeResponse(
            from: router.handle(try JSONEncoder().encode(request))
        )

        XCTAssertFalse(executed)
        XCTAssertEqual(response.error?.code, .confirmationRequired)
    }

    private func makeRouter(
        accessibilityGranted: Bool = true,
        dispatcher: @escaping WindowRangerCLIRequestRouter.CommandDispatcher = { _, _ in .dispatched }
    ) -> WindowRangerCLIRequestRouter {
        WindowRangerCLIRequestRouter(
            snapshotProvider: { [workspaceID] in
                .init(
                    workspaces: [.init(id: workspaceID, name: "Private Work", key: "w")],
                    accessibilityGranted: accessibilityGranted,
                    isPaused: false
                )
            },
            commandDispatcher: dispatcher
        )
    }

    private func response(
        from router: WindowRangerCLIRequestRouter,
        operation: WindowRangerCLIOperation,
        payload: WindowRangerCLIRequestPayload? = nil,
        requestID: String = UUID().uuidString
    ) throws -> WindowRangerCLIResponseEnvelope {
        let request = WindowRangerCLIRequestEnvelope(
            requestID: requestID,
            operation: operation,
            payload: payload
        )
        return try WindowRangerCLIProtocol.decodeResponse(
            from: router.handle(try JSONEncoder().encode(request))
        )
    }
}
