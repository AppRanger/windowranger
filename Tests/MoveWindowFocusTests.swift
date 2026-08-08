import XCTest

final class MoveWindowFocusTests: XCTestCase {
    private let source = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    private let destination = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    private let other = UUID(uuidString: "20000000-0000-0000-0000-000000000003")!

    func testOneRemainingSourceWindowBecomesReplacement() {
        XCTAssertEqual(
            WorkspaceEngine.moveReplacementFocusOrder(
                movingWindow: "moving",
                lastFocusedWindow: "moving",
                orderedCandidates: ["moving", "remaining"]
            ),
            ["remaining"]
        )
    }

    func testMultipleReplacementCandidatesPreserveCycleOrderAndWrap() {
        XCTAssertEqual(
            WorkspaceEngine.moveReplacementFocusOrder(
                movingWindow: "moving",
                lastFocusedWindow: "moving",
                orderedCandidates: ["after", "last", "moving"]
            ),
            ["after", "last"]
        )
    }

    func testNoRemainingCandidateLeavesNeutralReplacementPlan() {
        XCTAssertTrue(WorkspaceEngine.moveReplacementFocusOrder(
            movingWindow: "moving",
            lastFocusedWindow: "moving",
            orderedCandidates: ["moving"]
        ).isEmpty)
    }

    func testFloatingWindowIsEligibleReplacementBecauseLayoutParticipationIsIrrelevant() {
        XCTAssertTrue(WorkspaceEngine.moveReplacementCandidateIsEligible(
            workspaceMatches: true,
            visible: true,
            meaningfullyVisible: true,
            displayMatches: true,
            focusEligible: true
        ))
    }

    func testIgnoredOrNonFocusablePanelCannotBecomeReplacement() {
        XCTAssertFalse(WorkspaceEngine.moveReplacementCandidateIsEligible(
            workspaceMatches: true,
            visible: true,
            meaningfullyVisible: true,
            displayMatches: true,
            focusEligible: false
        ))
    }

    func testKeepOnAllWindowDoesNotTriggerMoveFocusBehavior() {
        XCTAssertEqual(disposition(keepsOnAll: true), .unchangedVisible)
    }

    func testAssignedWorkspaceRuleBlocksContradictoryManualMove() {
        XCTAssertEqual(WorkspaceEngine.moveWorkspaceFocusDisposition(
            sourceWorkspaceID: source,
            requestedWorkspaceID: destination,
            assignedWorkspaceID: other,
            keepsOnAllWorkspaces: false,
            configuredFollow: false,
            followOverride: nil
        ), .blockedByAppRule)
    }

    func testSendOnlyIsMigrationSafeDefault() {
        XCTAssertEqual(disposition(), .sendOnly)
    }

    func testConfiguredFollowAndOneShotFollowSelectFollowDisposition() {
        XCTAssertEqual(disposition(configuredFollow: true), .follow)
        XCTAssertEqual(disposition(followOverride: true), .follow)
    }

    func testUnifiedMoveKeepsActualExternalInteractionDisplay() {
        let displays = [
            DisplaySnapshot(
                identifier: "main",
                bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                isMain: true,
                name: "Main"
            ),
            DisplaySnapshot(
                identifier: "external",
                bounds: CGRect(x: -1600, y: 0, width: 1600, height: 1000),
                isMain: false,
                name: "External"
            ),
        ]
        let resolution = WorkspaceEngine.interactionDisplaySelection(
            focusedFrame: WindowFrame(
                position: CGPoint(x: -1200, y: 100),
                size: CGSize(width: 800, height: 600)
            ),
            mode: .unified,
            managedWorkspaceHomeDisplayIdentifier: nil,
            displays: displays
        )

        XCTAssertEqual(resolution.identifier, "external")
        XCTAssertEqual(resolution.reason, "focused-window-frame")
    }

    func testIndependentDestinationSwitchPreservesOtherDisplaysAndPreventsDuplicates() {
        let active = ["source-display": source, "destination-display": other, "third-display": destination]
        let switched = WorkspaceEngine.switchingIndependentWorkspace(
            destination,
            displayIdentifier: "destination-display",
            in: active
        )

        XCTAssertEqual(switched["source-display"], source)
        XCTAssertEqual(switched["destination-display"], destination)
        XCTAssertNil(switched["third-display"])
    }

    func testSendOnlySuppressionConsumesParkedFocusButNotReplacementFocus() {
        XCTAssertTrue(WorkspaceEngine.sendOnlyFocusObservationIsSuppressed(
            focusedWindow: "moving",
            suppressedWindows: ["moving"]
        ))
        XCTAssertFalse(WorkspaceEngine.sendOnlyFocusObservationIsSuppressed(
            focusedWindow: "replacement",
            suppressedWindows: ["moving"]
        ))
    }

    func testRapidConsecutiveMovesChooseEachActionLocalSuccessor() {
        let first = WorkspaceEngine.moveReplacementFocusOrder(
            movingWindow: "one",
            lastFocusedWindow: "one",
            orderedCandidates: ["one", "two", "three"]
        )
        let second = WorkspaceEngine.moveReplacementFocusOrder(
            movingWindow: "two",
            lastFocusedWindow: "two",
            orderedCandidates: ["two", "three"]
        )

        XCTAssertEqual(first.first, "two")
        XCTAssertEqual(second.first, "three")
    }

    @MainActor
    func testFocusFollowsMovedWindowSettingDefaultsOffAndPersists() {
        let suite = "WindowManagerTests.MoveFocus.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let initial = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] }
        )
        XCTAssertFalse(initial.focusFollowsMovedWindow)
        initial.focusFollowsMovedWindow = true

        let restored = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] }
        )
        XCTAssertTrue(restored.focusFollowsMovedWindow)
    }

    private func disposition(
        keepsOnAll: Bool = false,
        configuredFollow: Bool = false,
        followOverride: Bool? = nil
    ) -> MoveWorkspaceFocusDisposition {
        WorkspaceEngine.moveWorkspaceFocusDisposition(
            sourceWorkspaceID: source,
            requestedWorkspaceID: destination,
            assignedWorkspaceID: nil,
            keepsOnAllWorkspaces: keepsOnAll,
            configuredFollow: configuredFollow,
            followOverride: followOverride
        )
    }
}
