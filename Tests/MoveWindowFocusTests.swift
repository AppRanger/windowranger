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

    func testExternallyHiddenRegularApplicationIsExcludedFromParticipation() {
        XCTAssertTrue(WorkspaceEngine.isExcludedFromWorkspaceParticipation(
            isApplicationHidden: true,
            isDropDownAppWindow: false
        ))
        XCTAssertFalse(WorkspaceEngine.isExcludedFromWorkspaceParticipation(
            isApplicationHidden: false,
            isDropDownAppWindow: false
        ))
    }

    func testHiddenQuickAppRetainsItsExactHiddenSessionOwnership() {
        XCTAssertFalse(WorkspaceEngine.isExcludedFromWorkspaceParticipation(
            isApplicationHidden: true,
            isDropDownAppWindow: true
        ))
    }

    func testExternalHideAndUnhideChangeBackgroundLayoutSignature() {
        let hidden = WorkspaceEngine.backgroundApplicationVisibilityMarker(
            isApplicationHidden: true,
            isDropDownAppWindow: false
        )
        let visible = WorkspaceEngine.backgroundApplicationVisibilityMarker(
            isApplicationHidden: false,
            isDropDownAppWindow: false
        )

        XCTAssertEqual(hidden, "hidden")
        XCTAssertEqual(visible, "visible")
        XCTAssertNotEqual(hidden, visible)
        XCTAssertTrue(WorkspaceEngine.shouldApplyBackgroundLayout(
            previousSignature: "window|application-visibility=hidden",
            currentSignature: "window|application-visibility=visible",
            isStartup: false
        ))
    }

    func testQuickAppVisibilityIsNotPartOfOrdinaryApplicationSignature() {
        XCTAssertNil(WorkspaceEngine.backgroundApplicationVisibilityMarker(
            isApplicationHidden: true,
            isDropDownAppWindow: true
        ))
        XCTAssertNil(WorkspaceEngine.backgroundApplicationVisibilityMarker(
            isApplicationHidden: false,
            isDropDownAppWindow: true
        ))
    }

    func testBackgroundLayoutUsesEnumeratedFrameWithoutAnotherAccessibilityRead() {
        let key = WindowKey(processIdentifier: 42, windowIdentifier: 7)
        let observedFrame = WindowFrame(
            position: CGPoint(x: 100, y: 200),
            size: CGSize(width: 800, height: 600)
        )
        var fallbackReadCount = 0

        let result = WorkspaceEngine.backgroundLayoutFrame(
            for: key,
            observedFrames: [key: observedFrame]
        ) {
            fallbackReadCount += 1
            return nil
        }

        XCTAssertEqual(result, observedFrame)
        XCTAssertEqual(fallbackReadCount, 0)
    }

    func testBackgroundLayoutRetriesFrameWhenEnumerationHadNoReadableFrame() {
        let key = WindowKey(processIdentifier: 42, windowIdentifier: 7)
        let recoveredFrame = WindowFrame(
            position: CGPoint(x: 120, y: 240),
            size: CGSize(width: 640, height: 480)
        )
        var fallbackReadCount = 0

        let result = WorkspaceEngine.backgroundLayoutFrame(
            for: key,
            observedFrames: [:]
        ) {
            fallbackReadCount += 1
            return recoveredFrame
        }

        XCTAssertEqual(result, recoveredFrame)
        XCTAssertEqual(fallbackReadCount, 1)
    }

    func testBackgroundLayoutRereadsOnlyAfterApplyingGeometry() {
        var postWriteReadCount = 0
        let unchanged = WorkspaceEngine.settledBackgroundLayoutSignature(
            observedSignature: "enumerated",
            didApplyVisibility: false
        ) {
            postWriteReadCount += 1
            return "post-write"
        }
        XCTAssertEqual(unchanged, "enumerated")
        XCTAssertEqual(postWriteReadCount, 0)

        let changed = WorkspaceEngine.settledBackgroundLayoutSignature(
            observedSignature: "enumerated",
            didApplyVisibility: true
        ) {
            postWriteReadCount += 1
            return "post-write"
        }
        XCTAssertEqual(changed, "post-write")
        XCTAssertEqual(postWriteReadCount, 1)
    }

    func testHiddenRegularApplicationCannotBecomeWakeFocusOrQuitGeometryTarget() {
        let excluded = WorkspaceEngine.isExcludedFromWorkspaceParticipation(
            isApplicationHidden: true,
            isDropDownAppWindow: false
        )
        XCTAssertTrue(excluded)
        XCTAssertFalse(WorkspaceEngine.shouldIncludeInWakeFocusRecovery(
            isWriteEligible: true,
            isExcludedFromWorkspaceParticipation: excluded
        ))

        let unhidden = WorkspaceEngine.isExcludedFromWorkspaceParticipation(
            isApplicationHidden: false,
            isDropDownAppWindow: false
        )
        XCTAssertFalse(unhidden)
        XCTAssertTrue(WorkspaceEngine.shouldIncludeInWakeFocusRecovery(
            isWriteEligible: true,
            isExcludedFromWorkspaceParticipation: unhidden
        ))
    }

    func testKeepOnAllWindowDoesNotTriggerMoveFocusBehavior() {
        XCTAssertEqual(disposition(keepsOnAll: true), .unchangedVisible)
    }

    func testAssignedWorkspaceRuleAllowsContradictoryManualMove() {
        XCTAssertEqual(WorkspaceEngine.moveWorkspaceFocusDisposition(
            sourceWorkspaceID: source,
            requestedWorkspaceID: destination,
            keepsOnAllWorkspaces: false,
            configuredFollow: false,
            followOverride: nil
        ), .sendOnly)
        XCTAssertTrue(WorkspaceEngine.manualWorkspaceRuleOverrideIsActive(
            assignedWorkspaceID: other,
            requestedWorkspaceID: destination
        ))
    }

    func testMovingBackToRuleWorkspaceClearsManualOverride() {
        XCTAssertFalse(WorkspaceEngine.manualWorkspaceRuleOverrideIsActive(
            assignedWorkspaceID: destination,
            requestedWorkspaceID: destination
        ))
    }

    func testRefreshPreservesManualWorkspaceOverrideButAppliesRuleWithoutOne() {
        XCTAssertEqual(WorkspaceEngine.workspaceIDAfterRuleRefresh(
            currentWorkspaceID: destination,
            assignedWorkspaceID: other,
            manualOverrideActive: true
        ), destination)
        XCTAssertEqual(WorkspaceEngine.workspaceIDAfterRuleRefresh(
            currentWorkspaceID: destination,
            assignedWorkspaceID: other,
            manualOverrideActive: false
        ), other)
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
        XCTAssertTrue(WorkspaceEngine.staleParkedFocusObservationIsSuppressed(
            focusedWindow: "moving",
            suppressedWindows: ["moving"]
        ))
        XCTAssertFalse(WorkspaceEngine.staleParkedFocusObservationIsSuppressed(
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
        let suite = "WindowRangerTests.MoveFocus.\(UUID().uuidString)"
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
            keepsOnAllWorkspaces: keepsOnAll,
            configuredFollow: configuredFollow,
            followOverride: followOverride
        )
    }
}
