import XCTest

final class WorkspaceSwitchFocusTests: XCTestCase {
    private let target = WindowKey(processIdentifier: 100, windowIdentifier: 1)
    private let fallback = WindowKey(processIdentifier: 200, windowIdentifier: 2)
    private let previous = WindowKey(processIdentifier: 300, windowIdentifier: 3)

    func testLastFocusedEligibleWindowOnDestinationDisplayIsPreferred() {
        let result = WorkspaceSwitchFocusPolicy.orderedTargets(
            preferred: target,
            candidates: [candidate(fallback), candidate(target)]
        )

        XCTAssertEqual(result, [target, fallback])
    }

    func testInvalidHistoryFallsBackToStableLocalOrder() {
        let result = WorkspaceSwitchFocusPolicy.orderedTargets(
            preferred: target,
            candidates: [
                candidate(fallback),
                candidate(target, isOnDestinationDisplay: false),
            ]
        )

        XCTAssertEqual(result, [fallback])
    }

    func testEmptyDestinationLeavesNoFocusTarget() {
        XCTAssertTrue(WorkspaceSwitchFocusPolicy.orderedTargets(
            preferred: target,
            candidates: []
        ).isEmpty)
    }

    func testIgnoredParkedDeferredAndNonFocusableWindowsAreExcluded() {
        let ignored = WindowKey(processIdentifier: 10, windowIdentifier: 10)
        let parked = WindowKey(processIdentifier: 11, windowIdentifier: 11)
        let deferred = WindowKey(processIdentifier: 12, windowIdentifier: 12)
        let nonFocusable = WindowKey(processIdentifier: 13, windowIdentifier: 13)
        let offDisplay = WindowKey(processIdentifier: 14, windowIdentifier: 14)
        let result = WorkspaceSwitchFocusPolicy.orderedTargets(
            preferred: nil,
            candidates: [
                candidate(ignored, isIgnored: true),
                candidate(parked, isVisible: false, isMeaningfullyVisible: false),
                candidate(deferred, isTemporarilyDeferred: true),
                candidate(nonFocusable, isFocusEligible: false),
                candidate(offDisplay, isOnDestinationDisplay: false),
            ]
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testFloatingDialogAndAppRuleExcludedWindowsRemainEligible() {
        // Layout participation is deliberately absent from the focus policy. These three keys
        // model explicit floating, automatic dialog, and app-rule-excluded windows respectively.
        let floating = WindowKey(processIdentifier: 10, windowIdentifier: 10)
        let dialog = WindowKey(processIdentifier: 11, windowIdentifier: 11)
        let appExcluded = WindowKey(processIdentifier: 12, windowIdentifier: 12)

        XCTAssertEqual(
            WorkspaceSwitchFocusPolicy.orderedTargets(
                preferred: nil,
                candidates: [candidate(floating), candidate(dialog), candidate(appExcluded)]
            ),
            [floating, dialog, appExcluded]
        )
    }

    func testKeepOnAllWindowIsOnlyUsedAfterNormalWorkspaceMembers() {
        let keepOnAll = WindowKey(processIdentifier: 10, windowIdentifier: 10)
        XCTAssertEqual(
            WorkspaceSwitchFocusPolicy.orderedTargets(
                preferred: keepOnAll,
                candidates: [
                    candidate(keepOnAll, belongsToWorkspace: false, keepsOnAllWorkspaces: true),
                    candidate(target),
                ]
            ),
            [target, keepOnAll]
        )
        XCTAssertEqual(
            WorkspaceSwitchFocusPolicy.orderedTargets(
                preferred: nil,
                candidates: [
                    candidate(keepOnAll, belongsToWorkspace: false, keepsOnAllWorkspaces: true),
                ]
            ),
            [keepOnAll]
        )
    }

    func testAlreadyActiveAppUsesExactWindowPathWithoutActivation() {
        let plan = WorkspaceEngine.exactWindowFocusPlan(applicationIsActive: true)
        XCTAssertFalse(plan.contains(.makeApplicationFrontmost))
        XCTAssertTrue(plan.contains(.focusApplicationWindow))
        XCTAssertTrue(plan.contains(.raiseWindow))
    }

    func testSameAppWrongWindowGetsBoundedExactRetryThenAdvances() {
        let wrongSameApp = WindowKey(processIdentifier: target.processIdentifier, windowIdentifier: 99)
        XCTAssertEqual(WorkspaceEngine.workspaceSwitchFocusVerificationDecision(
            expected: target,
            actual: wrongSameApp,
            previousFocus: previous,
            actualIsIgnored: false,
            applicationIsActive: true,
            exactAttempt: 0
        ), .retryExactTarget)
        XCTAssertEqual(WorkspaceEngine.workspaceSwitchFocusVerificationDecision(
            expected: target,
            actual: wrongSameApp,
            previousFocus: previous,
            actualIsIgnored: false,
            applicationIsActive: true,
            exactAttempt: 1
        ), .advanceToNextCandidate)
    }

    func testNilAXFocusSucceedsOnlyWithActiveAppAndExactWindowServerTarget() {
        XCTAssertEqual(WorkspaceEngine.workspaceSwitchFocusVerificationDecision(
            expected: target,
            actual: nil,
            previousFocus: previous,
            actualIsIgnored: false,
            applicationIsActive: true,
            windowServerTargetIsFrontmostNormalWindow: true,
            exactAttempt: 0
        ), .succeeded)
        XCTAssertEqual(WorkspaceEngine.workspaceSwitchFocusVerificationDecision(
            expected: target,
            actual: nil,
            previousFocus: previous,
            actualIsIgnored: false,
            applicationIsActive: true,
            windowServerTargetIsFrontmostNormalWindow: false,
            exactAttempt: 0
        ), .retryExactTarget)
        XCTAssertEqual(WorkspaceEngine.workspaceSwitchFocusVerificationDecision(
            expected: target,
            actual: nil,
            previousFocus: previous,
            actualIsIgnored: false,
            applicationIsActive: false,
            windowServerTargetIsFrontmostNormalWindow: true,
            exactAttempt: 0
        ), .advanceToNextCandidate)
    }

    func testWindowServerEvidenceDoesNotOverrideAnAXWindowMismatch() {
        let wrongSameApp = WindowKey(processIdentifier: target.processIdentifier, windowIdentifier: 99)
        XCTAssertEqual(WorkspaceEngine.focusCycleVerificationDecision(
            expected: target,
            actual: wrongSameApp,
            applicationIsActive: true,
            windowServerTargetIsFrontmostNormalWindow: true,
            exactAttempt: 0
        ), .retryExactTarget)
        XCTAssertEqual(WorkspaceEngine.focusCycleVerificationDecision(
            expected: target,
            actual: fallback,
            applicationIsActive: true,
            windowServerTargetIsFrontmostNormalWindow: true,
            exactAttempt: 0
        ), .abortForCompetingFocus)
    }

    func testStalePreviousDisplayFocusGetsOneRetryButGenuineCompetitionAborts() {
        XCTAssertEqual(WorkspaceEngine.workspaceSwitchFocusVerificationDecision(
            expected: target,
            actual: previous,
            previousFocus: previous,
            actualIsIgnored: false,
            applicationIsActive: false,
            exactAttempt: 0
        ), .retryExactTarget)
        XCTAssertEqual(WorkspaceEngine.workspaceSwitchFocusVerificationDecision(
            expected: target,
            actual: previous,
            previousFocus: previous,
            actualIsIgnored: false,
            applicationIsActive: true,
            exactAttempt: 1
        ), .abortForCompetingFocus)
        XCTAssertEqual(WorkspaceEngine.workspaceSwitchFocusVerificationDecision(
            expected: target,
            actual: fallback,
            previousFocus: previous,
            actualIsIgnored: false,
            applicationIsActive: true,
            exactAttempt: 0
        ), .abortForCompetingFocus)
    }

    func testFailedDestinationFocusSuppressesParkedSourceAfterNilTransition() {
        let suppressedWindows: Set<WindowKey> = [previous]

        XCTAssertTrue(WorkspaceSwitchFocusPolicy.shouldSuppressRetainedPreviousFocus(
            previousWindowIsVisible: false
        ))
        XCTAssertFalse(WorkspaceSwitchFocusPolicy.shouldSuppressRetainedPreviousFocus(
            previousWindowIsVisible: true
        ))
        XCTAssertFalse(WorkspaceEngine.staleParkedFocusObservationIsSuppressed(
            focusedWindow: nil,
            suppressedWindows: suppressedWindows
        ))
        XCTAssertTrue(WorkspaceEngine.staleParkedFocusObservationIsSuppressed(
            focusedWindow: previous,
            suppressedWindows: suppressedWindows
        ))
        XCTAssertFalse(WorkspaceEngine.staleParkedFocusObservationIsSuppressed(
            focusedWindow: fallback,
            suppressedWindows: suppressedWindows
        ))
    }

    func testLaterExplicitActivationReleasesParkedSourceSuppression() {
        let deadline = Date(timeIntervalSinceReferenceDate: 100)

        XCTAssertEqual(WorkspaceEngine.parkedFocusActivationDisposition(
            allowExplicitActivationAfter: deadline,
            now: Date(timeIntervalSinceReferenceDate: 99)
        ), .suppressStaleActivation)
        XCTAssertEqual(WorkspaceEngine.parkedFocusActivationDisposition(
            allowExplicitActivationAfter: deadline,
            now: deadline
        ), .acceptExplicitActivation)
        XCTAssertEqual(WorkspaceEngine.parkedFocusActivationDisposition(
            allowExplicitActivationAfter: nil,
            now: deadline
        ), .unaffected)
    }

    func testIgnoredFocusedPanelAlwaysAbortsReassertion() {
        XCTAssertEqual(WorkspaceEngine.workspaceSwitchFocusVerificationDecision(
            expected: target,
            actual: previous,
            previousFocus: previous,
            actualIsIgnored: true,
            applicationIsActive: true,
            exactAttempt: 0
        ), .abortForCompetingFocus)
    }

    func testRapidWorkspaceSwitchSupersedesOlderVerificationToken() {
        let old = FocusVerificationToken(generation: 7, correlationID: "old")
        let latest = FocusVerificationToken(generation: 8, correlationID: "latest")

        XCTAssertFalse(WorkspaceEngine.verificationIsCurrent(old, generation: latest.generation))
        XCTAssertTrue(WorkspaceEngine.verificationIsCurrent(latest, generation: latest.generation))
    }

    func testDisconnectedHomeUsesPhysicalMainFallbackAndReconnectRestoresHome() {
        let main = DisplaySnapshot(
            identifier: "main",
            bounds: CGRect(x: 0, y: 0, width: 1440, height: 900),
            isMain: true,
            name: "Main"
        )
        let external = DisplaySnapshot(
            identifier: "external",
            bounds: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
            isMain: false,
            name: "External"
        )

        XCTAssertEqual(
            WorkspaceSwitchDestinationPolicy.resolve(
                logicalHomeDisplayIdentifier: "external",
                displays: [main]
            ),
            WorkspaceSwitchDestination(
                logicalDisplayIdentifier: "external",
                physicalDisplayIdentifier: "main",
                usedDisconnectedHomeFallback: true
            )
        )
        XCTAssertEqual(
            WorkspaceSwitchDestinationPolicy.resolve(
                logicalHomeDisplayIdentifier: "external",
                displays: [main, external]
            ),
            WorkspaceSwitchDestination(
                logicalDisplayIdentifier: "external",
                physicalDisplayIdentifier: "external",
                usedDisconnectedHomeFallback: false
            )
        )
    }

    func testIndependentSwitchPreservesOtherDisplayActiveWorkspace() {
        let mainWorkspace = UUID()
        let oldExternalWorkspace = UUID()
        let targetExternalWorkspace = UUID()
        let active = ["main": mainWorkspace, "external": oldExternalWorkspace]

        let result = WorkspaceEngine.switchingIndependentWorkspace(
            targetExternalWorkspace,
            displayIdentifier: "external",
            in: active
        )

        XCTAssertEqual(result["main"], mainWorkspace)
        XCTAssertEqual(result["external"], targetExternalWorkspace)
    }

    func testUnifiedInteractionResolutionNeverFallsBackToMainWhenFocusedFrameIsExternal() {
        let displays = [
            DisplaySnapshot(
                identifier: "main",
                bounds: CGRect(x: 0, y: 0, width: 1440, height: 900),
                isMain: true,
                name: "Main"
            ),
            DisplaySnapshot(
                identifier: "external",
                bounds: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
                isMain: false,
                name: "External"
            ),
        ]
        let result = WorkspaceEngine.interactionDisplaySelection(
            focusedFrame: WindowFrame(
                position: CGPoint(x: -1500, y: 100),
                size: CGSize(width: 800, height: 600)
            ),
            mode: .unified,
            managedWorkspaceHomeDisplayIdentifier: nil,
            displays: displays
        )

        XCTAssertEqual(result.identifier, "external")
        XCTAssertEqual(result.reason, "focused-window-frame")
    }

    private func candidate(
        _ key: WindowKey,
        belongsToWorkspace: Bool = true,
        keepsOnAllWorkspaces: Bool = false,
        isVisible: Bool = true,
        isMeaningfullyVisible: Bool = true,
        isOnDestinationDisplay: Bool = true,
        isFocusEligible: Bool = true,
        isIgnored: Bool = false,
        isTemporarilyDeferred: Bool = false
    ) -> WorkspaceSwitchFocusCandidate<WindowKey> {
        WorkspaceSwitchFocusCandidate(
            key: key,
            belongsToWorkspace: belongsToWorkspace,
            keepsOnAllWorkspaces: keepsOnAllWorkspaces,
            isVisible: isVisible,
            isMeaningfullyVisible: isMeaningfullyVisible,
            isOnDestinationDisplay: isOnDestinationDisplay,
            isFocusEligible: isFocusEligible,
            isIgnored: isIgnored,
            isTemporarilyDeferred: isTemporarilyDeferred
        )
    }
}
