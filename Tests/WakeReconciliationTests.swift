import ApplicationServices
import XCTest

final class WakeReconciliationTests: XCTestCase {
    func testOrdinaryWakeCompletesFromFreshSnapshotWithoutRetry() {
        XCTAssertEqual(
            decision(
                previousTopology: "main",
                currentTopology: "main",
                requiredProcesses: [10],
                enumeratedProcesses: [10]
            ),
            .complete
        )
    }

    func testDisplayDisconnectAndReconnectWaitForStableTopology() {
        XCTAssertEqual(
            decision(previousTopology: "main|external", currentTopology: "main"),
            .retry(afterMilliseconds: 180, reason: "topology-changed")
        )
        XCTAssertEqual(
            decision(
                attempt: 1,
                previousTopology: "main",
                currentTopology: "main"
            ),
            .complete
        )
        XCTAssertEqual(
            decision(previousTopology: "main", currentTopology: "main|external"),
            .retry(afterMilliseconds: 180, reason: "topology-changed")
        )
    }

    func testIndependentTwoDisplayActiveMapSurvivesDisconnect() {
        let mainWorkspace = UUID()
        let externalWorkspace = UUID()
        let homes = [mainWorkspace: "main", externalWorkspace: "external"]
        let existing = ["main": mainWorkspace, "external": externalWorkspace]

        let reconciled = WorkspaceEngine.reconciledIndependentActiveWorkspaces(
            workspaceIDs: [mainWorkspace, externalWorkspace],
            displayByWorkspace: homes,
            existing: existing
        )

        XCTAssertEqual(reconciled, existing)
    }

    func testReconnectedMonitorRuntimeIdentifierRetainsItsPreviouslyActiveWorkspace() {
        let mainWorkspace = UUID()
        let selectedExternalWorkspace = UUID()
        let inactiveExternalWorkspace = UUID()
        let remapped = WorkspaceEngine.remappedActiveWorkspaceDisplayIdentifiers(
            ["main": mainWorkspace, "external-old": selectedExternalWorkspace],
            previousHomes: [
                mainWorkspace: "main",
                selectedExternalWorkspace: "external-old",
                inactiveExternalWorkspace: "external-old",
            ],
            currentHomes: [
                mainWorkspace: "main",
                selectedExternalWorkspace: "external-new",
                inactiveExternalWorkspace: "external-new",
            ]
        )

        XCTAssertEqual(remapped["main"], mainWorkspace)
        XCTAssertEqual(remapped["external-new"], selectedExternalWorkspace)
        XCTAssertNil(remapped["external-old"])
    }

    func testUnifiedAffinityFallsBackAndReturnsWithoutChangingPlacement() {
        let main = display("main", x: 0, isMain: true)
        let external = display("external", x: -1600)
        let placement = PersistedDisplayPlacement(
            displayIdentifier: "external",
            normalizedOrigin: CGPoint(x: 0.2, y: 0.25)
        )
        let saved = WindowFrame(
            position: CGPoint(x: -1280, y: 250),
            size: CGSize(width: 700, height: 500)
        )

        let absent = WorkspaceEngine.resolveDisplayFrame(
            savedFrame: saved,
            placement: placement,
            displays: [main]
        )
        let returned = WorkspaceEngine.resolveDisplayFrame(
            savedFrame: saved,
            placement: placement,
            displays: [main, external]
        )

        XCTAssertTrue(absent.usedFallbackDisplay)
        XCTAssertGreaterThanOrEqual(absent.frame.position.x, 0)
        XCTAssertFalse(returned.usedFallbackDisplay)
        XCTAssertLessThan(returned.frame.position.x, 0)
        XCTAssertEqual(placement.displayIdentifier, "external")
    }

    func testWindowServerSessionChangeInvalidatesExactStateAndAcceptsNewSession() {
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WakeSession-\(UUID().uuidString)")
            .appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: stateURL.deletingLastPathComponent()) }
        var session = "old"
        let store = WorkspaceStateStore(fileURL: stateURL) { session }

        XCTAssertEqual(store.refreshWindowServerSession(), .unchanged)
        session = "new"
        XCTAssertEqual(
            store.refreshWindowServerSession(),
            .changed(previous: "old", current: "new")
        )
        XCTAssertEqual(store.windowServerSession, "new")

        let workspace = WorkspaceDefinition.defaults[0].id
        store.save(PersistedWorkspaceState(
            version: PersistedWorkspaceState.currentVersion,
            windowServerSession: "new",
            activeWorkspaceID: workspace,
            windows: [:]
        ), waitForCompletion: true)
        XCTAssertNotNil(store.load())
    }

    func testUnavailableWindowServerSessionDoesNotDiscardKnownSession() {
        var session = "known"
        let store = WorkspaceStateStore { session }
        session = ""

        XCTAssertEqual(store.refreshWindowServerSession(), .unavailable)
        XCTAssertEqual(store.windowServerSession, "known")
    }

    func testDisappearedApplicationDoesNotBlockWakeReadiness() {
        XCTAssertEqual(
            decision(requiredProcesses: [], enumeratedProcesses: []),
            .complete
        )
    }

    func testDuplicateWakeEventsCoalesceIntoOneGeneration() {
        var state = WakeReconciliationState()
        let sleepGeneration = state.prepareForSleep()
        let first = state.request(.systemWake)
        let duplicate = state.request(.screensWake)

        XCTAssertGreaterThan(first.generation, sleepGeneration)
        XCTAssertTrue(first.shouldSchedule)
        XCTAssertFalse(duplicate.shouldSchedule)
        XCTAssertEqual(duplicate.generation, first.generation)
        XCTAssertEqual(duplicate.sources, [.systemWake, .screensWake])
        XCTAssertTrue(state.complete(generation: first.generation))
        XCTAssertFalse(state.isPending)
    }

    func testSleepSupersedesAStaleWakeGeneration() {
        var state = WakeReconciliationState()
        let stale = state.request(.displayConfigurationChanged)
        let sleepGeneration = state.prepareForSleep()

        XCTAssertGreaterThan(sleepGeneration, stale.generation)
        XCTAssertFalse(state.isCurrent(stale.generation))
        XCTAssertFalse(state.complete(generation: stale.generation))
    }

    func testDelayedAXEnumerationRetriesThenCompletes() {
        XCTAssertEqual(
            decision(requiredProcesses: [42], enumeratedProcesses: []),
            .retry(afterMilliseconds: 180, reason: "ax-enumeration-deferred")
        )
        XCTAssertEqual(
            decision(
                attempt: 1,
                requiredProcesses: [42],
                enumeratedProcesses: [42]
            ),
            .complete
        )
        XCTAssertNotEqual(
            WakeWindowRecoveryPolicy.geometryFreshnessMarker(wasFreshlyEnumerated: false),
            WakeWindowRecoveryPolicy.geometryFreshnessMarker(wasFreshlyEnumerated: true)
        )
        XCTAssertTrue(WorkspaceEngine.shouldApplyBackgroundLayout(
            previousSignature: "window|deferred",
            currentSignature: "window|fresh",
            isStartup: false
        ))
    }

    func testFinalRetryDegradesWithoutPermanentPollingStorm() {
        XCTAssertEqual(WakeReconciliationPolicy.maximumAttempts, 3)
        XCTAssertEqual(WakeReconciliationPolicy.retryDelaysMilliseconds, [180, 420])
        XCTAssertEqual(
            decision(
                attempt: 2,
                requiredProcesses: [42],
                enumeratedProcesses: []
            ),
            .completeDegraded(reason: "ax-enumeration-deferred")
        )
    }

    func testAdditionalLifecycleSignalForcesFreshSnapshotBeforeCompletion() {
        XCTAssertEqual(
            decision(receivedAdditionalSignal: true),
            .retry(afterMilliseconds: 180, reason: "new-lifecycle-signal")
        )
    }

    func testWakeLayoutVerificationDetectsMissingAndMismatchedFrames() {
        let expected = WindowFrame(
            position: CGPoint(x: 10, y: 20),
            size: CGSize(width: 800, height: 600)
        )
        let closeEnough = WindowFrame(
            position: CGPoint(x: 10.5, y: 19.5),
            size: CGSize(width: 800.5, height: 599.5)
        )
        let wrong = WindowFrame(
            position: CGPoint(x: 10, y: 60),
            size: CGSize(width: 800, height: 560)
        )

        XCTAssertEqual(
            WakeLayoutVerificationPolicy.mismatchedWindowKeys(
                expectedFrames: ["retained": expected, "wrong": expected, "missing": expected],
                observedFrames: ["retained": closeEnough, "wrong": wrong]
            ),
            ["wrong", "missing"]
        )
    }

    func testWakeLayoutVerificationIsBounded() {
        XCTAssertEqual(
            WakeLayoutVerificationPolicy.verificationDelaysMilliseconds,
            [120, 300, 650]
        )
    }

    func testUnavailableWindowServerSessionRetriesBoundedly() {
        XCTAssertEqual(
            decision(sessionAvailable: false),
            .retry(afterMilliseconds: 180, reason: "window-server-session-unavailable")
        )
    }

    func testFloatingKeepOnAllAndDialogRemainRecoverableButIgnoredAndTemporaryWindowsDoNot() {
        let normal = WindowAdmissionDecision(disposition: .managedNormal, reason: .normalWindow)
        let dialog = WindowAdmissionDecision(disposition: .managedDialog, reason: .sheetRole)
        let ignored = WindowAdmissionDecision(
            disposition: .ignoredTransientPopup,
            reason: .verifiedBundleNonNormalLayer
        )
        let temporary = WindowAdmissionDecision(disposition: .temporarilyIneligible, reason: .minimized)
        let keepRule = ResolvedAppRule(
            assignedWorkspaceID: nil,
            keepsOnAllWorkspaces: true,
            excludesFromLayout: false
        )

        XCTAssertTrue(WakeWindowRecoveryPolicy.isWriteEligible(
            wasFreshlyEnumerated: true,
            disposition: normal.disposition
        ))
        XCTAssertTrue(WakeWindowRecoveryPolicy.isWriteEligible(
            wasFreshlyEnumerated: true,
            disposition: dialog.disposition
        ))
        XCTAssertFalse(WakeWindowRecoveryPolicy.isWriteEligible(
            wasFreshlyEnumerated: true,
            disposition: ignored.disposition
        ))
        XCTAssertFalse(WakeWindowRecoveryPolicy.isWriteEligible(
            wasFreshlyEnumerated: true,
            disposition: temporary.disposition
        ))
        XCTAssertFalse(WorkspaceEngine.layoutDecision(
            layoutOverride: .floating,
            admissionDecision: normal,
            rule: .none
        ).includesInLayout)
        XCTAssertFalse(WorkspaceEngine.layoutDecision(
            layoutOverride: .automatic,
            admissionDecision: dialog,
            rule: .none
        ).includesInLayout)
        XCTAssertTrue(WorkspaceEngine.shouldWindowBeVisible(
            workspaceID: UUID(),
            activeWorkspaceIDs: [],
            rule: keepRule
        ))
    }

    func testMinimizedAndFullscreenWindowsAreTemporarilyIneligible() {
        let minimized = AccessibilityWindow.admissionDecision(for: WindowAdmissionMetadata(
            bundleIdentifier: "com.example.Editor",
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            windowLayer: 0,
            isMinimized: true
        ))
        let fullscreen = AccessibilityWindow.admissionDecision(for: WindowAdmissionMetadata(
            bundleIdentifier: "com.example.Editor",
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            windowLayer: 0,
            isMinimized: false,
            isFullscreen: true
        ))

        XCTAssertEqual(minimized, WindowAdmissionDecision(
            disposition: .temporarilyIneligible,
            reason: .minimized
        ))
        XCTAssertEqual(fullscreen, WindowAdmissionDecision(
            disposition: .temporarilyIneligible,
            reason: .fullscreen
        ))
    }

    func testFullscreenObservationLatchesAcrossFailuresAndRequiresTwoFalseReadsToExit() {
        XCTAssertEqual(
            FullscreenSessionPolicy.resolve(
                observation: .trueValue,
                hadSession: false,
                consecutiveAuthoritativeFalseObservations: 0
            ),
            FullscreenObservationResolution(
                isFullscreen: true,
                consecutiveAuthoritativeFalseObservations: 0
            )
        )
        XCTAssertEqual(
            FullscreenSessionPolicy.resolve(
                observation: .unavailable,
                hadSession: true,
                consecutiveAuthoritativeFalseObservations: 0
            ),
            FullscreenObservationResolution(
                isFullscreen: true,
                consecutiveAuthoritativeFalseObservations: 0
            )
        )
        XCTAssertFalse(FullscreenSessionPolicy.resolve(
            observation: .unsupported,
            hadSession: false,
            consecutiveAuthoritativeFalseObservations: 0
        ).isFullscreen)

        let settling = FullscreenSessionPolicy.resolve(
            observation: .falseValue,
            hadSession: true,
            consecutiveAuthoritativeFalseObservations: 0
        )
        XCTAssertTrue(settling.isFullscreen)
        XCTAssertEqual(settling.consecutiveAuthoritativeFalseObservations, 1)
        XCTAssertFalse(FullscreenSessionPolicy.resolve(
            observation: .falseValue,
            hadSession: true,
            consecutiveAuthoritativeFalseObservations: 1
        ).isFullscreen)
    }

    func testFullscreenGameQuietModeStillChecksExitAndRunsPeriodicBroadDiscovery() {
        XCTAssertTrue(FullscreenSessionPolicy.shouldPerformBroadRefresh(
            hasForegroundGameSession: false,
            focusedGameObservation: nil,
            timeSinceBroadRefresh: 0
        ))
        XCTAssertFalse(FullscreenSessionPolicy.shouldPerformBroadRefresh(
            hasForegroundGameSession: true,
            focusedGameObservation: .trueValue,
            timeSinceBroadRefresh: 0.75
        ))
        XCTAssertTrue(FullscreenSessionPolicy.shouldPerformBroadRefresh(
            hasForegroundGameSession: true,
            focusedGameObservation: .falseValue,
            timeSinceBroadRefresh: 0.75
        ))
        XCTAssertTrue(FullscreenSessionPolicy.shouldPerformBroadRefresh(
            hasForegroundGameSession: true,
            focusedGameObservation: .unavailable,
            timeSinceBroadRefresh: FullscreenSessionPolicy.quietBroadRefreshInterval
        ))
    }

    func testFullscreenSessionAlwaysBlocksGeometryWrites() {
        XCTAssertTrue(FullscreenSessionPolicy.allowsGeometryWrite(
            hasFullscreenSession: false,
            isTemporarilyDeferred: false
        ))
        XCTAssertFalse(FullscreenSessionPolicy.allowsGeometryWrite(
            hasFullscreenSession: true,
            isTemporarilyDeferred: false
        ))
        XCTAssertFalse(FullscreenSessionPolicy.allowsGeometryWrite(
            hasFullscreenSession: false,
            isTemporarilyDeferred: true
        ))
    }

    func testDeclaredGameMetadataUsesSupportedPublicBundleSignals() {
        XCTAssertTrue(FullscreenGameMetadataPolicy.isDeclaredGame(
            supportsGameMode: true,
            supportsGameControllerMode: nil,
            applicationCategory: nil
        ))
        XCTAssertTrue(FullscreenGameMetadataPolicy.isDeclaredGame(
            supportsGameMode: nil,
            supportsGameControllerMode: nil,
            applicationCategory: "PUBLIC.APP-CATEGORY.GAMES"
        ))
        XCTAssertTrue(FullscreenGameMetadataPolicy.isDeclaredGame(
            supportsGameMode: nil,
            supportsGameControllerMode: nil,
            applicationCategory: "public.app-category.role-playing-games"
        ))
        XCTAssertFalse(FullscreenGameMetadataPolicy.isDeclaredGame(
            supportsGameMode: false,
            supportsGameControllerMode: false,
            applicationCategory: "public.app-category.productivity"
        ))
    }

    func testWakeFocusRestoresPriorVisibleLocalWindowAndNeverParkedOrOtherDisplay() {
        let candidates = [
            WakeFocusCandidate(
                key: "parked",
                isActiveWorkspace: false,
                isMeaningfullyVisible: false,
                isOnInteractionDisplay: true,
                isFocusEligible: true
            ),
            WakeFocusCandidate(
                key: "other-display",
                isActiveWorkspace: true,
                isMeaningfullyVisible: true,
                isOnInteractionDisplay: false,
                isFocusEligible: true
            ),
            WakeFocusCandidate(
                key: "prior-local",
                isActiveWorkspace: true,
                isMeaningfullyVisible: true,
                isOnInteractionDisplay: true,
                isFocusEligible: true
            ),
        ]

        XCTAssertEqual(WakeFocusPolicy.replacement(
            currentManagedFocus: "parked",
            currentFocusIsUnmanaged: false,
            preSleepFocus: "prior-local",
            orderedCandidates: candidates
        ), "prior-local")
    }

    func testWakeFocusPreservesValidOrGenuineUnmanagedUserFocus() {
        let candidates = [WakeFocusCandidate(
            key: "visible",
            isActiveWorkspace: true,
            isMeaningfullyVisible: true,
            isOnInteractionDisplay: true,
            isFocusEligible: true
        )]

        XCTAssertNil(WakeFocusPolicy.replacement(
            currentManagedFocus: "visible",
            currentFocusIsUnmanaged: false,
            preSleepFocus: "visible",
            orderedCandidates: candidates
        ))
        XCTAssertNil(WakeFocusPolicy.replacement(
            currentManagedFocus: nil,
            currentFocusIsUnmanaged: true,
            preSleepFocus: "visible",
            orderedCandidates: candidates
        ))
    }

    func testTopologySignatureChangesForGeometryMainRoleAndReconnect() {
        let main = display("main", x: 0, isMain: true)
        let external = display("external", x: -1600)
        let mainOnly = WorkspaceEngine.displayTopologySignature([main])
        let docked = WorkspaceEngine.displayTopologySignature([main, external])

        XCTAssertNotEqual(mainOnly, docked)
        XCTAssertEqual(docked, WorkspaceEngine.displayTopologySignature([external, main]))
    }

    func testWakeAdmissionDiagnosticsRemainPrivacySafeAndIncludeDeferralMetadata() {
        let key = WindowKey(processIdentifier: 7, windowIdentifier: 9)
        let metadata = WindowAdmissionMetadata(
            bundleIdentifier: "com.example.Editor",
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            windowLayer: 0,
            isMinimized: false,
            isFullscreen: true
        )
        let fields = WorkspaceEngine.admissionDiagnosticFields(
            decision: AccessibilityWindow.admissionDecision(for: metadata),
            metadata: metadata,
            key: key,
            layerSource: "test"
        )

        XCTAssertEqual(fields["is-fullscreen"], "true")
        XCTAssertEqual(fields["fullscreen-observation"], "true")
        XCTAssertEqual(fields["is-minimized"], "false")
        XCTAssertNil(fields["title"])
        XCTAssertNil(fields["path"])
    }

    private func decision(
        attempt: Int = 0,
        previousTopology: String? = "main",
        currentTopology: String = "main",
        displayCount: Int = 1,
        requiredProcesses: Set<Int32> = [],
        enumeratedProcesses: Set<Int32> = [],
        receivedAdditionalSignal: Bool = false,
        sessionAvailable: Bool = true
    ) -> WakeReconciliationDecision {
        WakeReconciliationPolicy.decision(for: WakeReconciliationAttempt(
            attemptIndex: attempt,
            previousTopologySignature: previousTopology,
            currentTopologySignature: currentTopology,
            connectedDisplayCount: displayCount,
            requiredProcessIdentifiers: requiredProcesses,
            successfullyEnumeratedProcessIdentifiers: enumeratedProcesses,
            receivedAdditionalLifecycleSignal: receivedAdditionalSignal,
            windowServerSessionAvailable: sessionAvailable
        ))
    }

    private func display(_ identifier: String, x: CGFloat, isMain: Bool = false) -> DisplaySnapshot {
        DisplaySnapshot(
            identifier: identifier,
            bounds: CGRect(x: x, y: 0, width: 1600, height: 1000),
            isMain: isMain,
            name: identifier
        )
    }
}
