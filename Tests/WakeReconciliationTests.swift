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

    func testScreenSleepSuspendsLifecycleUntilASelectedWakeSignal() {
        var state = WakeReconciliationState()

        _ = state.prepareForSleep()
        XCTAssertTrue(state.isSleeping)
        XCTAssertFalse(state.isPending)

        let wake = state.request(.screensWake)
        XCTAssertFalse(state.isSleeping)
        XCTAssertTrue(wake.shouldSchedule)
        XCTAssertTrue(state.isPending)
    }

    func testDisplayWakeWaitsForSessionActivationBeforeRecovery() {
        var state = ScreenSessionLifecycleState()
        state.suspend(.screensSleep)
        state.suspend(.sessionResignedActive)

        XCTAssertFalse(state.receive(.screensWake))
        XCTAssertEqual(state.suspensionSources, [.sessionResignedActive])
        XCTAssertTrue(state.receive(.sessionBecameActive))
        XCTAssertFalse(state.isSuspended)
    }

    func testSessionActivationWaitsForDisplayWakeWhenBothWereSuspended() {
        var state = ScreenSessionLifecycleState()
        state.suspend(.screensSleep)
        state.suspend(.sessionResignedActive)

        XCTAssertFalse(state.receive(.sessionBecameActive))
        XCTAssertEqual(state.suspensionSources, [.screensSleep])
        XCTAssertTrue(state.receive(.screensWake))
    }

    func testFirstGlobalEmptySnapshotDefersRatherThanEvictingEveryTrackedWindow() {
        XCTAssertTrue(WindowEnumerationLifecycle.shouldDeferGlobalEmptySnapshot(
            trackedWindowCount: 13,
            requiredProcessIdentifiers: [10, 11, 12],
            successfullyEnumeratedProcessIdentifiers: [10, 11, 12],
            enumeratedWindowCount: 0,
            isLifecycleTransitionActive: false,
            consecutiveGlobalEmptySnapshots: 0
        ))
    }

    func testGlobalEmptySnapshotRemainsDeferredThroughoutWakeReconciliation() {
        XCTAssertTrue(WindowEnumerationLifecycle.shouldDeferGlobalEmptySnapshot(
            trackedWindowCount: 13,
            requiredProcessIdentifiers: [10, 11, 12],
            successfullyEnumeratedProcessIdentifiers: [10, 11, 12],
            enumeratedWindowCount: 0,
            isLifecycleTransitionActive: true,
            consecutiveGlobalEmptySnapshots: 3
        ))
    }

    func testConfirmedGlobalEmptySnapshotIsAuthoritativeWhileFullyActive() {
        XCTAssertFalse(WindowEnumerationLifecycle.shouldDeferGlobalEmptySnapshot(
            trackedWindowCount: 2,
            requiredProcessIdentifiers: [10, 11],
            successfullyEnumeratedProcessIdentifiers: [10, 11],
            enumeratedWindowCount: 0,
            isLifecycleTransitionActive: false,
            consecutiveGlobalEmptySnapshots: 1
        ))

        let first = WindowKey(processIdentifier: 10, windowIdentifier: 100)
        let second = WindowKey(processIdentifier: 11, windowIdentifier: 101)
        XCTAssertEqual(WindowEnumerationLifecycle.removedTrackedWindowKeys(
            trackedWindowKeys: [first, second],
            runningProcessIdentifiers: [10, 11],
            successfullyEnumeratedProcessIdentifiers: [10, 11],
            enumeratedWindowKeys: []
        ), [first, second])
    }

    func testPartialOrFailedEnumerationDoesNotTriggerGlobalEmptyDeferral() {
        XCTAssertFalse(WindowEnumerationLifecycle.shouldDeferGlobalEmptySnapshot(
            trackedWindowCount: 2,
            requiredProcessIdentifiers: [10, 11],
            successfullyEnumeratedProcessIdentifiers: [10],
            enumeratedWindowCount: 0,
            isLifecycleTransitionActive: false,
            consecutiveGlobalEmptySnapshots: 0
        ))
        XCTAssertFalse(WindowEnumerationLifecycle.shouldDeferGlobalEmptySnapshot(
            trackedWindowCount: 2,
            requiredProcessIdentifiers: [10, 11],
            successfullyEnumeratedProcessIdentifiers: [10, 11],
            enumeratedWindowCount: 1,
            isLifecycleTransitionActive: true,
            consecutiveGlobalEmptySnapshots: 0
        ))
    }

    func testOneReturningApplicationDoesNotReleaseOtherPreSleepWindows() {
        let start = Date(timeIntervalSince1970: 1_000)
        let first = WindowKey(processIdentifier: 10, windowIdentifier: 100)
        let second = WindowKey(processIdentifier: 11, windowIdentifier: 101)
        let quickApp = WindowKey(processIdentifier: 12, windowIdentifier: 102)
        var state = PostSleepWindowRecoveryState()
        state.prepareForSleep(protecting: [first, second, quickApp])
        state.beginWake(at: start)

        let empty = state.observe(
            runningProcessIdentifiers: [10, 11, 12],
            successfullyEnumeratedProcessIdentifiers: [10, 11, 12],
            enumeratedWindowKeys: [],
            at: start.addingTimeInterval(1)
        )
        XCTAssertEqual(empty.protectedWindowKeys, [first, second, quickApp])
        XCTAssertEqual(empty.authoritativeSuccessfullyEnumeratedProcessIdentifiers, [])

        let partial = state.observe(
            runningProcessIdentifiers: [10, 11, 12],
            successfullyEnumeratedProcessIdentifiers: [10, 11, 12],
            enumeratedWindowKeys: [first],
            at: start.addingTimeInterval(3)
        )
        XCTAssertEqual(partial.newlyRecoveredWindowKeys, [first])
        XCTAssertEqual(partial.protectedWindowKeys, [second, quickApp])
        XCTAssertEqual(
            partial.authoritativeSuccessfullyEnumeratedProcessIdentifiers,
            [10]
        )
        XCTAssertEqual(WindowEnumerationLifecycle.removedTrackedWindowKeys(
            trackedWindowKeys: [first, second, quickApp],
            runningProcessIdentifiers: [10, 11, 12],
            successfullyEnumeratedProcessIdentifiers:
                partial.authoritativeSuccessfullyEnumeratedProcessIdentifiers,
            enumeratedWindowKeys: [first]
        ), [])

        let recovered = state.observe(
            runningProcessIdentifiers: [10, 11, 12],
            successfullyEnumeratedProcessIdentifiers: [10, 11, 12],
            enumeratedWindowKeys: [first, second, quickApp],
            at: start.addingTimeInterval(10)
        )
        XCTAssertEqual(recovered.newlyRecoveredWindowKeys, [second, quickApp])
        XCTAssertFalse(state.isActive)
        XCTAssertEqual(
            recovered.authoritativeSuccessfullyEnumeratedProcessIdentifiers,
            [10, 11, 12]
        )
    }

    func testPartialPostSleepReturnDefersOriginalTiledPartition() {
        let left = WindowKey(processIdentifier: 10, windowIdentifier: 100)
        let topRight = WindowKey(processIdentifier: 11, windowIdentifier: 101)
        let bottomRight = WindowKey(processIdentifier: 12, windowIdentifier: 102)
        let tree = tiledRecoveryTree(left: left, topRight: topRight, bottomRight: bottomRight)
        let fingerprint = TiledLayoutEngine.fingerprint(tree)

        XCTAssertEqual(
            PostSleepTiledLayoutRecoveryPolicy.protectedParticipantKeys(
                in: tree,
                protectedWindowKeys: [topRight, bottomRight]
            ),
            [topRight, bottomRight]
        )
        XCTAssertTrue(PostSleepTiledLayoutRecoveryPolicy.shouldDeferPartition(
            tree: tree,
            protectedWindowKeys: [topRight, bottomRight]
        ))
        XCTAssertEqual(TiledLayoutEngine.fingerprint(tree), fingerprint)
    }

    func testCompletePostSleepReturnReusesExactTiledTree() throws {
        let left = WindowKey(processIdentifier: 10, windowIdentifier: 100)
        let topRight = WindowKey(processIdentifier: 11, windowIdentifier: 101)
        let bottomRight = WindowKey(processIdentifier: 12, windowIdentifier: 102)
        let tree = tiledRecoveryTree(left: left, topRight: topRight, bottomRight: bottomRight)

        XCTAssertFalse(PostSleepTiledLayoutRecoveryPolicy.shouldDeferPartition(
            tree: tree,
            protectedWindowKeys: []
        ))
        XCTAssertEqual(
            try XCTUnwrap(TiledLayoutEngine.reconciled(
                tree,
                windowKeys: [left, topRight, bottomRight],
                weights: nil,
                orientation: .horizontal
            )),
            tree
        )
    }

    func testProtectedWindowInAnotherTiledPartitionDoesNotBlockThisPartition() {
        let left = WindowKey(processIdentifier: 10, windowIdentifier: 100)
        let topRight = WindowKey(processIdentifier: 11, windowIdentifier: 101)
        let bottomRight = WindowKey(processIdentifier: 12, windowIdentifier: 102)
        let unrelated = WindowKey(processIdentifier: 13, windowIdentifier: 103)
        let tree = tiledRecoveryTree(left: left, topRight: topRight, bottomRight: bottomRight)

        XCTAssertFalse(PostSleepTiledLayoutRecoveryPolicy.shouldDeferPartition(
            tree: tree,
            protectedWindowKeys: [unrelated]
        ))
    }

    func testAuthoritativeRemovalPrunesThenReleasesTiledPartition() throws {
        let workspaceID = UUID()
        let left = WindowKey(processIdentifier: 10, windowIdentifier: 100)
        let closed = WindowKey(processIdentifier: 11, windowIdentifier: 101)
        let bottomRight = WindowKey(processIdentifier: 12, windowIdentifier: 102)
        let partition = TiledLayoutPartitionKey(
            workspaceID: workspaceID,
            displayIdentifier: "external"
        )
        let tree = tiledRecoveryTree(left: left, topRight: closed, bottomRight: bottomRight)
        let pruned = try XCTUnwrap(WindowEnumerationLifecycle.pruning(
            [partition: tree],
            removedWindowKeys: [closed]
        )[partition])

        XCTAssertFalse(PostSleepTiledLayoutRecoveryPolicy.shouldDeferPartition(
            tree: pruned,
            protectedWindowKeys: []
        ))
        XCTAssertEqual(
            try XCTUnwrap(TiledLayoutEngine.reconciled(
                pruned,
                windowKeys: [left, bottomRight],
                weights: nil,
                orientation: .horizontal
            )),
            pruned
        )
    }

    func testPersistentlyMissingWindowNeedsTwoStableSnapshotsAfterWakeGrace() {
        let start = Date(timeIntervalSince1970: 2_000)
        let missing = WindowKey(processIdentifier: 42, windowIdentifier: 100)
        var state = PostSleepWindowRecoveryState()
        state.prepareForSleep(protecting: [missing])
        state.beginWake(at: start)

        let firstConfirmation = state.observe(
            runningProcessIdentifiers: [42],
            successfullyEnumeratedProcessIdentifiers: [42],
            enumeratedWindowKeys: [],
            at: start.addingTimeInterval(
                PostSleepWindowRecoveryState.missingWindowGraceInterval
            )
        )
        XCTAssertEqual(firstConfirmation.protectedWindowKeys, [missing])
        XCTAssertEqual(firstConfirmation.confirmedMissingWindowKeys, [])
        XCTAssertEqual(firstConfirmation.authoritativeSuccessfullyEnumeratedProcessIdentifiers, [])

        let secondConfirmation = state.observe(
            runningProcessIdentifiers: [42],
            successfullyEnumeratedProcessIdentifiers: [42],
            enumeratedWindowKeys: [],
            at: start.addingTimeInterval(
                PostSleepWindowRecoveryState.missingWindowGraceInterval + 1
            )
        )
        XCTAssertEqual(secondConfirmation.confirmedMissingWindowKeys, [missing])
        XCTAssertEqual(
            secondConfirmation.authoritativeSuccessfullyEnumeratedProcessIdentifiers,
            [42]
        )
        XCTAssertFalse(state.isActive)
        XCTAssertEqual(WindowEnumerationLifecycle.removedTrackedWindowKeys(
            trackedWindowKeys: [missing],
            runningProcessIdentifiers: [42],
            successfullyEnumeratedProcessIdentifiers:
                secondConfirmation.authoritativeSuccessfullyEnumeratedProcessIdentifiers,
            enumeratedWindowKeys: []
        ), [missing])
    }

    func testDifferentWindowFromSameProcessDoesNotReleaseProtectedKeyDuringGrace() {
        let start = Date(timeIntervalSince1970: 2_500)
        let protected = WindowKey(processIdentifier: 42, windowIdentifier: 100)
        let transient = WindowKey(processIdentifier: 42, windowIdentifier: 101)
        var state = PostSleepWindowRecoveryState()
        state.prepareForSleep(protecting: [protected])
        state.beginWake(at: start)

        let update = state.observe(
            runningProcessIdentifiers: [42],
            successfullyEnumeratedProcessIdentifiers: [42],
            enumeratedWindowKeys: [transient],
            at: start.addingTimeInterval(3)
        )

        XCTAssertEqual(update.protectedWindowKeys, [protected])
        XCTAssertEqual(update.newlyRecoveredWindowKeys, [])
        XCTAssertEqual(update.authoritativeSuccessfullyEnumeratedProcessIdentifiers, [])
        XCTAssertTrue(state.isActive)
    }

    func testFailedEnumerationResetsMissingWindowConfirmation() {
        let start = Date(timeIntervalSince1970: 3_000)
        let missing = WindowKey(processIdentifier: 42, windowIdentifier: 100)
        var state = PostSleepWindowRecoveryState()
        state.prepareForSleep(protecting: [missing])
        state.beginWake(at: start)
        let grace = PostSleepWindowRecoveryState.missingWindowGraceInterval

        _ = state.observe(
            runningProcessIdentifiers: [42],
            successfullyEnumeratedProcessIdentifiers: [42],
            enumeratedWindowKeys: [],
            at: start.addingTimeInterval(grace)
        )
        _ = state.observe(
            runningProcessIdentifiers: [42],
            successfullyEnumeratedProcessIdentifiers: [],
            enumeratedWindowKeys: [],
            at: start.addingTimeInterval(grace + 1)
        )
        let restartedConfirmation = state.observe(
            runningProcessIdentifiers: [42],
            successfullyEnumeratedProcessIdentifiers: [42],
            enumeratedWindowKeys: [],
            at: start.addingTimeInterval(grace + 2)
        )

        XCTAssertEqual(restartedConfirmation.protectedWindowKeys, [missing])
        XCTAssertEqual(restartedConfirmation.confirmedMissingWindowKeys, [])
        XCTAssertTrue(state.isActive)
    }

    func testTerminatedApplicationReleasesItsProtectedWindowsImmediately() {
        let missing = WindowKey(processIdentifier: 42, windowIdentifier: 100)
        var state = PostSleepWindowRecoveryState()
        state.prepareForSleep(protecting: [missing])
        state.beginWake(at: Date(timeIntervalSince1970: 4_000))

        let update = state.observe(
            runningProcessIdentifiers: [],
            successfullyEnumeratedProcessIdentifiers: [],
            enumeratedWindowKeys: [],
            at: Date(timeIntervalSince1970: 4_001)
        )

        XCTAssertEqual(update.terminatedWindowKeys, [missing])
        XCTAssertFalse(state.isActive)
        XCTAssertEqual(WindowEnumerationLifecycle.removedTrackedWindowKeys(
            trackedWindowKeys: [missing],
            runningProcessIdentifiers: [],
            successfullyEnumeratedProcessIdentifiers: [],
            enumeratedWindowKeys: []
        ), [missing])
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

    func testGameModeProfileEligibilityRequiresExplicitLaunchServicesOptIn() {
        XCTAssertTrue(FullscreenGameMetadataPolicy.isGameModeEligible(
            supportsGameMode: true
        ))
        XCTAssertFalse(FullscreenGameMetadataPolicy.isGameModeEligible(
            supportsGameMode: false
        ))
        XCTAssertFalse(FullscreenGameMetadataPolicy.isGameModeEligible(
            supportsGameMode: nil
        ))

        XCTAssertTrue(FullscreenGameMetadataPolicy.isDeclaredGame(
            supportsGameMode: nil,
            supportsGameControllerMode: true,
            applicationCategory: nil
        ))
        XCTAssertFalse(FullscreenGameMetadataPolicy.isGameModeEligible(
            supportsGameMode: nil
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

    private func tiledRecoveryTree(
        left: WindowKey,
        topRight: WindowKey,
        bottomRight: WindowKey
    ) -> TiledNode {
        .split(
            axis: .horizontal,
            ratio: 0.53,
            first: .window(left),
            second: .split(
                axis: .vertical,
                ratio: 0.5,
                first: .window(topRight),
                second: .window(bottomRight)
            )
        )
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
