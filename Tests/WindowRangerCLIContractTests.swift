import XCTest

final class WindowRangerCLIContractTests: XCTestCase {
    private let workspaceID = UUID(uuidString: "97000000-0000-0000-0000-000000000001")!

    func testRequestAndResponseRoundTripThroughBoundedJSON() throws {
        let request = WindowRangerCLIRequestEnvelope(
            requestID: "request-001",
            operation: .setLayout,
            payload: .init(layout: .accordion)
        )
        let requestData = try JSONEncoder().encode(request)
        XCTAssertEqual(try WindowRangerCLIProtocol.decodeRequest(from: requestData), request)

        let response = WindowRangerCLIResponseEnvelope(
            requestID: "request-001",
            result: .workspaces([.init(id: workspaceID, key: "w")])
        )
        let responseData = try JSONEncoder().encode(response)
        XCTAssertEqual(try WindowRangerCLIProtocol.decodeResponse(from: responseData), response)
    }

    func testActionAndConfigurationPayloadsRoundTripThroughStrictSchema() throws {
        let action = WindowRangerCLIRequestEnvelope(
            requestID: "action-001",
            operation: .performAction,
            payload: .init(
                action: "move-workspace-to-display",
                arguments: ["display-id": .string("display-1")]
            )
        )
        XCTAssertEqual(
            try WindowRangerCLIProtocol.decodeRequest(from: JSONEncoder().encode(action)),
            action
        )

        let document: WindowRangerCLIJSONValue = .object([
            "schemaVersion": .number(1),
            "settings": .object(["iCloudSyncEnabled": .bool(false)]),
        ])
        let apply = WindowRangerCLIRequestEnvelope(
            requestID: "config-001",
            operation: .applyConfiguration,
            payload: .init(
                configuration: document,
                expectedRevision: "fnv1a64-0123456789abcdef",
                confirmsReplacement: true
            )
        )
        XCTAssertEqual(
            try WindowRangerCLIProtocol.decodeRequest(from: JSONEncoder().encode(apply)),
            apply
        )

        let response = WindowRangerCLIResponseEnvelope(
            requestID: "config-001",
            result: .configuration(.init(
                revision: "fnv1a64-fedcba9876543210",
                document: document
            ))
        )
        XCTAssertEqual(
            try WindowRangerCLIProtocol.decodeResponse(from: JSONEncoder().encode(response)),
            response
        )
    }

    func testConfigurationApplyRequiresRevisionAndExplicitReplacement() {
        let document = WindowRangerCLIJSONValue.object(["schemaVersion": .number(1)])
        XCTAssertThrowsError(try WindowRangerCLIRequestEnvelope(
            requestID: "config-001",
            operation: .applyConfiguration,
            payload: .init(
                configuration: document,
                expectedRevision: "fnv1a64-0123456789abcdef"
            )
        ).validate())
        XCTAssertThrowsError(try WindowRangerCLIRequestEnvelope(
            requestID: "config-002",
            operation: .applyConfiguration,
            payload: .init(configuration: document, confirmsReplacement: true)
        ).validate())
    }

    func testRequestValidationRejectsUnsupportedOrAmbiguousPayloads() {
        XCTAssertThrowsError(try WindowRangerCLIRequestEnvelope(
            protocolVersion: WindowRangerCLIProtocol.version + 1,
            requestID: "request-001",
            operation: .status
        ).validate())

        let unknownField = Data(#"{"protocolVersion":2,"requestID":"request-001","deadlineUptimeNanoseconds":1,"operation":"status","surprise":true}"#.utf8)
        XCTAssertThrowsError(try WindowRangerCLIProtocol.decodeRequest(from: unknownField)) { error in
            XCTAssertEqual(error as? WindowRangerCLIValidationError, .invalidMessageSchema)
        }
        XCTAssertThrowsError(try WindowRangerCLIRequestEnvelope(
            requestID: "request-001",
            operation: .setLayout,
            payload: .init(workspaceID: workspaceID, layout: .tiled)
        ).validate())
        XCTAssertThrowsError(try WindowRangerCLIRequestEnvelope(
            requestID: "request-001",
            operation: .pause,
            payload: .init()
        ).validate())
        XCTAssertThrowsError(try WindowRangerCLIRequestEnvelope(
            requestID: "bad request id",
            operation: .status
        ).validate())
    }

    func testBoundedDecodingRejectsOversizedMessagesAndWorkspaceLists() throws {
        let oversized = Data(repeating: 65, count: WindowRangerCLIProtocol.maximumMessageBytes + 1)
        XCTAssertThrowsError(try WindowRangerCLIProtocol.decodeRequest(from: oversized)) { error in
            XCTAssertEqual(error as? WindowRangerCLIValidationError, .messageTooLarge)
        }

        let workspaces = (0...WindowRangerCLIProtocol.maximumWorkspaceCount).map {
            WindowRangerCLIWorkspaceSummary(id: UUID(), key: "w\($0)")
        }
        XCTAssertThrowsError(try WindowRangerCLIResponseEnvelope(
            requestID: "request-001",
            result: .workspaces(workspaces)
        ).validate())
    }

    func testWorkspaceNamesAreExcludedUnlessExplicitlyRequested() {
        XCTAssertNil(WindowRangerCLIWorkspaceSummary(id: workspaceID, key: "w").name)
        XCTAssertEqual(
            WindowRangerCLIWorkspaceSummary(id: workspaceID, key: "w", name: "Private Work").name,
            "Private Work"
        )
    }

    func testAgentSkillIsDeterministicAndContainsNoUserWorkspaceData() {
        let first = WindowRangerCLIAgentSkill.content()
        let second = WindowRangerCLIAgentSkill.content()

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.hasPrefix("---\nname: windowranger-cli\n"))
        XCTAssertTrue(first.contains("`windowranger workspaces --json`"))
        XCTAssertTrue(first.contains("`windowranger workspaces --names --json`"))
        XCTAssertFalse(first.contains("Private Work"))
    }

    func testCatalogCapabilitiesAndSkillStayInLockstep() {
        let operations = WindowRangerCLICommandCatalog.operations
        XCTAssertEqual(operations, WindowRangerCLIOperation.allCases)
        XCTAssertEqual(Set(operations).count, operations.count)

        let skill = WindowRangerCLIAgentSkill.content()
        for operation in operations {
            XCTAssertNotNil(WindowRangerCLICommandCatalog.descriptor(for: operation))
            XCTAssertTrue(skill.contains("### `\(operation.rawValue)`"))
        }
        XCTAssertEqual(WindowRangerCLICapabilities().operations, operations)
    }

    func testDestructiveCloudActionsRequireTheirExactConfirmationToken() {
        for (action, confirmation) in WindowRangerCLICommandCatalog.requiredActionConfirmations {
            let descriptor = WindowRangerCLICommandCatalog.action(named: action)
            XCTAssertTrue(descriptor?.argumentNames.contains("confirmation") == true)
            XCTAssertFalse(WindowRangerCLICommandCatalog.actionConfirmationIsSatisfied(
                action: action,
                arguments: [:]
            ))
            XCTAssertFalse(WindowRangerCLICommandCatalog.actionConfirmationIsSatisfied(
                action: action,
                arguments: ["confirmation": "yes"]
            ))
            XCTAssertTrue(WindowRangerCLICommandCatalog.actionConfirmationIsSatisfied(
                action: action,
                arguments: ["confirmation": confirmation]
            ))
        }
    }
}
