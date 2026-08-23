import Carbon
import XCTest

final class KeyboardManipulationTests: XCTestCase {
    func testTwoArrowGestureMapsEveryCornerInEitherOrderWithoutFirstMove() {
        let cases: [(WindowDirection, WindowDirection, VisualPlacement)] = [
            (.up, .left, .topLeft),
            (.up, .right, .topRight),
            (.down, .left, .bottomLeft),
            (.down, .right, .bottomRight),
        ]

        for (first, second, expected) in cases {
            for (a, b) in [(first, second), (second, first)] {
                var machine = DirectionalMoveGestureStateMachine()
                XCTAssertEqual(machine.handle(.pressed(a, correlationID: "gesture")), [
                    .capture(correlationID: "gesture", firstDirection: a),
                ])
                XCTAssertEqual(machine.handle(.pressed(b, correlationID: "ignored-second-id")), [
                    .commitCorner(correlationID: "gesture", placement: expected),
                ])
                XCTAssertFalse(machine.isIdle)
                XCTAssertTrue(machine.handle(.released(a)).isEmpty)
                XCTAssertTrue(machine.handle(.released(b)).isEmpty)
                XCTAssertTrue(machine.isIdle)
            }
        }
    }

    func testTwoArrowGestureCommitsSingleOnReleaseOrMissingReleaseTimeoutExactlyOnce() {
        var released = DirectionalMoveGestureStateMachine()
        _ = released.handle(.pressed(.left, correlationID: "release"))
        XCTAssertEqual(released.handle(.released(.left)), [
            .commitSingle(correlationID: "release", direction: .left, reason: "key-release"),
        ])
        XCTAssertTrue(released.handle(.timeout(correlationID: "release")).isEmpty)
        XCTAssertTrue(released.isIdle)

        var timedOut = DirectionalMoveGestureStateMachine()
        _ = timedOut.handle(.pressed(.right, correlationID: "timeout"))
        XCTAssertEqual(timedOut.handle(.timeout(correlationID: "stale")), [])
        XCTAssertEqual(timedOut.handle(.timeout(correlationID: "timeout")), [
            .commitSingle(
                correlationID: "timeout",
                direction: .right,
                reason: "missing-release-timeout"
            ),
        ])
        XCTAssertTrue(timedOut.handle(.pressed(.right, correlationID: "repeat")).isEmpty)
        XCTAssertTrue(timedOut.handle(.released(.right)).isEmpty)
        XCTAssertTrue(timedOut.isIdle)
    }

    func testTwoArrowGestureIgnoresRepeatsAndCancelsInvalidPairsAndCompetingInput() {
        var repeated = DirectionalMoveGestureStateMachine()
        _ = repeated.handle(.pressed(.up, correlationID: "repeat"))
        XCTAssertTrue(repeated.handle(.pressed(.up, correlationID: "repeat-2")).isEmpty)
        XCTAssertEqual(repeated.handle(.pressed(.down, correlationID: "opposite")), [
            .cancel(correlationID: "repeat", reason: "same-axis-pair"),
        ])
        XCTAssertTrue(repeated.handle(.pressed(.left, correlationID: "blocked")).isEmpty)
        _ = repeated.handle(.released(.up))
        _ = repeated.handle(.released(.down))
        XCTAssertTrue(repeated.isIdle)

        var cancelled = DirectionalMoveGestureStateMachine()
        _ = cancelled.handle(.pressed(.left, correlationID: "cancel"))
        XCTAssertEqual(cancelled.handle(.cancel(reason: "escape", awaitRelease: true)), [
            .cancel(correlationID: "cancel", reason: "escape"),
        ])
        XCTAssertTrue(cancelled.handle(.pressed(.up, correlationID: "still-held")).isEmpty)
        _ = cancelled.handle(.released(.left))
        XCTAssertTrue(cancelled.isIdle)

        _ = cancelled.handle(.pressed(.right, correlationID: "reconfigured"))
        XCTAssertEqual(cancelled.handle(.cancel(reason: "reconfigured", awaitRelease: false)), [
            .cancel(correlationID: "reconfigured", reason: "reconfigured"),
        ])
        XCTAssertTrue(cancelled.isIdle)
    }

    func testDirectionalMoveShortcutFamilyRequiresMatchingConflictFreeBindings() throws {
        let defaults = HotKeyConfiguration()
        let defaultReport = ShortcutConflictModel.evaluate(configuration: defaults, workspaces: [])
        let family = try XCTUnwrap(try? DirectionalMoveChordFamily.resolve(
            configuration: defaults,
            report: defaultReport
        ).get())
        XCTAssertEqual(family.modifiers, UInt32(optionKey | cmdKey))
        XCTAssertEqual(family.direction(for: 126), .up)
        XCTAssertEqual(family.direction(for: 124), .right)

        var remapped = defaults
        XCTAssertNil(remapped.setModifierMask(UInt32(controlKey | shiftKey), for: .arrange))
        let remappedFamily = try XCTUnwrap(try? DirectionalMoveChordFamily.resolve(
            configuration: remapped,
            report: ShortcutConflictModel.evaluate(configuration: remapped, workspaces: [])
        ).get())
        XCTAssertEqual(remappedFamily.modifiers, UInt32(controlKey | shiftKey))

        var duplicate = defaults
        duplicate.setKeyCode(defaults.keyCode(for: .moveLeft), for: .moveRight)
        let duplicateReport = ShortcutConflictModel.evaluate(configuration: duplicate, workspaces: [])
        XCTAssertEqual(
            DirectionalMoveChordFamily.resolve(configuration: duplicate, report: duplicateReport),
            .failure(.shortcutConflict)
        )
    }

    func testHotKeyManagerDefersSingleAndDispatchesOneCompositeCorner() {
        var commands: [WindowManagerCommand] = []
        let scheduler = TestDirectionalMoveScheduler()
        let monitor = TestDirectionalMoveMonitor()
        let manager = HotKeyManager(
            dispatcher: WindowManagerCommandDispatcher { command, _ in commands.append(command) },
            registrationService: TestDirectionalMoveRegistrationService(),
            directionalGestureScheduler: scheduler,
            directionalGestureMonitor: monitor,
            installsEventHandler: false
        )
        let report = manager.register(workspaces: [], radialMenuEnabled: false)
        XCTAssertTrue(report.runtimeIssues.isEmpty)

        manager.handleDirectionalMoveHotKey(
            direction: .up,
            eventKind: UInt32(kEventHotKeyPressed)
        )
        XCTAssertEqual(commands.count, 1)
        guard case let .beginDirectionalMoveGesture(identifier, .up) = commands[0] else {
            return XCTFail("First press must only capture the gesture")
        }
        XCTAssertEqual(scheduler.latestDelay, HotKeyManager.directionalMoveChordWindow)
        manager.handleDirectionalMoveHotKey(
            direction: .right,
            eventKind: UInt32(kEventHotKeyPressed)
        )
        XCTAssertEqual(commands.count, 2)
        XCTAssertEqual(commands[1], .commitDirectionalMoveGesture(identifier, .corner(.topRight)))
        XCTAssertTrue(scheduler.latestTask?.isCancelled == true)
        XCTAssertEqual(monitor.stopCount, 1)
    }

    func testHotKeyManagerSingleReleaseTimeoutAndCompetingInputAreDeterministic() {
        var commands: [WindowManagerCommand] = []
        let scheduler = TestDirectionalMoveScheduler()
        let monitor = TestDirectionalMoveMonitor()
        let manager = HotKeyManager(
            dispatcher: WindowManagerCommandDispatcher { command, _ in commands.append(command) },
            registrationService: TestDirectionalMoveRegistrationService(),
            directionalGestureScheduler: scheduler,
            directionalGestureMonitor: monitor,
            installsEventHandler: false
        )
        _ = manager.register(workspaces: [], radialMenuEnabled: false)

        manager.handleDirectionalMoveHotKey(direction: .left, eventKind: UInt32(kEventHotKeyPressed))
        guard case let .beginDirectionalMoveGesture(releaseID, .left) = commands.last else {
            return XCTFail("Expected release gesture capture")
        }
        manager.handleDirectionalMoveHotKey(direction: .left, eventKind: UInt32(kEventHotKeyReleased))
        XCTAssertEqual(commands.last, .commitDirectionalMoveGesture(releaseID, .single(.left)))

        manager.handleDirectionalMoveHotKey(direction: .down, eventKind: UInt32(kEventHotKeyPressed))
        guard case let .beginDirectionalMoveGesture(timeoutID, .down) = commands.last else {
            return XCTFail("Expected timeout gesture capture")
        }
        scheduler.fireLatest()
        XCTAssertEqual(commands.last, .commitDirectionalMoveGesture(timeoutID, .single(.down)))
        manager.handleDirectionalMoveHotKey(direction: .down, eventKind: UInt32(kEventHotKeyReleased))

        manager.handleDirectionalMoveHotKey(direction: .up, eventKind: UInt32(kEventHotKeyPressed))
        guard case let .beginDirectionalMoveGesture(cancelID, .up) = commands.last else {
            return XCTFail("Expected cancellable gesture capture")
        }
        monitor.send(.keyDown(
            keyCode: 0,
            modifiers: UInt32(controlKey | optionKey),
            isRepeat: false
        ))
        XCTAssertEqual(
            commands.last,
            .cancelDirectionalMoveGesture(cancelID, reason: "competing-key")
        )

        manager.handleDirectionalMoveHotKey(direction: .up, eventKind: UInt32(kEventHotKeyReleased))
        manager.handleDirectionalMoveHotKey(direction: .right, eventKind: UInt32(kEventHotKeyPressed))
        guard case let .beginDirectionalMoveGesture(modifierID, .right) = commands.last else {
            return XCTFail("Expected modifier-cancellable gesture capture")
        }
        monitor.send(.modifiersChanged(
            modifiers: UInt32(controlKey | optionKey | shiftKey),
            functionDown: false
        ))
        XCTAssertEqual(
            commands.last,
            .cancelDirectionalMoveGesture(modifierID, reason: "modifier-changed")
        )
    }

    func testDirectionalMoveGestureFailsClosedWithoutMonitorOrCompleteRegistration() {
        var commands: [WindowManagerCommand] = []
        let unavailableMonitor = TestDirectionalMoveMonitor(canStart: false)
        let manager = HotKeyManager(
            dispatcher: WindowManagerCommandDispatcher { command, _ in commands.append(command) },
            registrationService: TestDirectionalMoveRegistrationService(),
            directionalGestureScheduler: TestDirectionalMoveScheduler(),
            directionalGestureMonitor: unavailableMonitor,
            installsEventHandler: false
        )
        var runtimeIssue: String?
        manager.directionalMoveGestureRuntimeIssueChanged = { runtimeIssue = $0 }
        _ = manager.register(workspaces: [], radialMenuEnabled: false)
        XCTAssertTrue(manager.directionalMoveCornerGestureEnabled)
        manager.handleDirectionalMoveHotKey(direction: .left, eventKind: UInt32(kEventHotKeyPressed))
        XCTAssertEqual(commands, [.moveWindowDirection(.left)])
        XCTAssertTrue(runtimeIssue?.contains("Single-arrow Reorder shortcuts still work") == true)

        commands.removeAll()
        let partial = HotKeyManager(
            dispatcher: WindowManagerCommandDispatcher { command, _ in commands.append(command) },
            registrationService: TestDirectionalMoveRegistrationService(failingKeyCode: 124),
            directionalGestureScheduler: TestDirectionalMoveScheduler(),
            directionalGestureMonitor: TestDirectionalMoveMonitor(),
            installsEventHandler: false
        )
        let report = partial.register(workspaces: [], radialMenuEnabled: false)
        XCTAssertTrue(report.runtimeIssues.contains { $0.owner.configurableAction == .moveRight })
        XCTAssertFalse(partial.directionalMoveCornerGestureEnabled)
        partial.handleDirectionalMoveHotKey(direction: .left, eventKind: UInt32(kEventHotKeyPressed))
        partial.handleDirectionalMoveHotKey(direction: .left, eventKind: UInt32(kEventHotKeyReleased))
        XCTAssertEqual(commands, [.moveWindowDirection(.left)])
    }

    func testDirectionalFocusPrefersAxisAlignedCandidate() {
        let source = CGRect(x: 400, y: 400, width: 200, height: 200)
        let candidates = [
            DirectionalWindowCandidate(key: "near-diagonal", frame: CGRect(x: 610, y: 50, width: 200, height: 200)),
            DirectionalWindowCandidate(key: "aligned", frame: CGRect(x: 900, y: 420, width: 200, height: 200)),
        ]

        XCTAssertEqual(
            WorkspaceEngine.directionalCandidateOrder(from: source, direction: .right, candidates: candidates),
            ["aligned", "near-diagonal"]
        )
    }

    func testDirectionalFocusUsesAccessibilityCoordinateUpAndDown() {
        let source = CGRect(x: 400, y: 400, width: 200, height: 200)
        let candidates = [
            DirectionalWindowCandidate(key: "up", frame: CGRect(x: 410, y: 100, width: 200, height: 200)),
            DirectionalWindowCandidate(key: "down", frame: CGRect(x: 410, y: 800, width: 200, height: 200)),
        ]

        XCTAssertEqual(WorkspaceEngine.directionalCandidateOrder(
            from: source,
            direction: .up,
            candidates: candidates
        ), ["up"])
        XCTAssertEqual(WorkspaceEngine.directionalCandidateOrder(
            from: source,
            direction: .down,
            candidates: candidates
        ), ["down"])
    }

    func testDirectionalFocusWrapsToTheOppositeEdgeAfterDirectCandidatesEnd() {
        let source = CGRect(x: 0, y: 400, width: 200, height: 200)
        let candidates = [
            DirectionalWindowCandidate(
                key: "near-right",
                frame: CGRect(x: 300, y: 420, width: 200, height: 200)
            ),
            DirectionalWindowCandidate(
                key: "far-right-aligned",
                frame: CGRect(x: 900, y: 410, width: 200, height: 200)
            ),
            DirectionalWindowCandidate(
                key: "far-right-diagonal",
                frame: CGRect(x: 1_100, y: 900, width: 200, height: 200)
            ),
        ]

        let wrapped = WorkspaceEngine.wrappingDirectionalCandidateOrder(
            from: source,
            direction: .left,
            candidates: candidates
        )
        XCTAssertTrue(wrapped.didWrap)
        XCTAssertEqual(wrapped.candidates.first, "far-right-aligned")

        let direct = WorkspaceEngine.wrappingDirectionalCandidateOrder(
            from: source,
            direction: .right,
            candidates: candidates
        )
        XCTAssertFalse(direct.didWrap)
        XCTAssertEqual(direct.candidates.first, "near-right")
    }

    func testDirectionalFocusWrapsVerticallyAndNotAcrossAnUnrelatedAxis() {
        let source = CGRect(x: 400, y: 0, width: 200, height: 200)
        let below = DirectionalWindowCandidate(
            key: "bottom",
            frame: CGRect(x: 420, y: 900, width: 200, height: 200)
        )
        let wrappedUp = WorkspaceEngine.wrappingDirectionalCandidateOrder(
            from: source,
            direction: .up,
            candidates: [below]
        )
        XCTAssertTrue(wrappedUp.didWrap)
        XCTAssertEqual(wrappedUp.candidates, ["bottom"])

        let sameColumn = DirectionalWindowCandidate(
            key: "below-only",
            frame: CGRect(x: 400, y: 900, width: 200, height: 200)
        )
        XCTAssertTrue(WorkspaceEngine.wrappingDirectionalCandidateOrder(
            from: source,
            direction: .left,
            candidates: [sameColumn]
        ).candidates.isEmpty)
    }

    func testDirectionalFocusHasNoCrossDisplayFallback() {
        XCTAssertFalse(WorkspaceEngine.moveReplacementCandidateIsEligible(
            workspaceMatches: true,
            visible: true,
            meaningfullyVisible: true,
            displayMatches: false,
            focusEligible: true
        ))
    }

    func testWeightedTiledGeometryUsesFocusedShare() {
        let frames = WorkspaceEngine.layoutFrames(
            .tiled,
            count: 2,
            in: CGRect(x: 0, y: 0, width: 1000, height: 800),
            tiledWeights: [0.7, 0.3],
            layoutConfiguration: .aeroSpaceUserDefaults
        )

        XCTAssertGreaterThan(frames[0].size.width, frames[1].size.width)
        XCTAssertEqual(frames[1].position.x - (frames[0].position.x + frames[0].size.width), 5)
    }

    func testSmartResizeChangesOnlyFocusedWindowsNearestSplit() throws {
        let a = WindowKey(processIdentifier: 1, windowIdentifier: 11)
        let b = WindowKey(processIdentifier: 2, windowIdentifier: 22)
        let c = WindowKey(processIdentifier: 3, windowIdentifier: 33)
        let tree = TiledNode.split(
            axis: .horizontal,
            ratio: 0.5,
            first: .window(a),
            second: .split(
                axis: .vertical,
                ratio: 0.5,
                first: .window(b),
                second: .window(c)
            )
        )

        let resized = try XCTUnwrap(WorkspaceEngine.smartResizedTiledState(
            tree: tree,
            participants: [a, b, c],
            focusedIndex: 1,
            deltaPoints: 100,
            displayBounds: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            configuration: .aeroSpaceUserDefaults
        ))

        XCTAssertEqual(resized.tree.windowKeys, tree.windowKeys)
        XCTAssertEqual(resized.weights.reduce(0, +), 1, accuracy: 0.000_001)
        XCTAssertGreaterThan(resized.weights[1], 0.25)
        guard case let .split(rootAxis, rootRatio, _, second) = resized.tree,
              case let .split(nestedAxis, nestedRatio, _, _) = second
        else { return XCTFail("Resize must preserve the placed tree topology") }
        XCTAssertEqual(rootAxis, .horizontal)
        XCTAssertEqual(nestedAxis, .vertical)
        XCTAssertEqual(rootRatio, 0.5)
        XCTAssertNotEqual(nestedRatio, 0.5)

        let beforeFrames = try TiledLayoutEngine.frames(
            for: tree,
            in: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            configuration: .aeroSpaceUserDefaults
        )
        let afterFrames = try TiledLayoutEngine.frames(
            for: resized.tree,
            in: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            configuration: .aeroSpaceUserDefaults
        )
        XCTAssertEqual(beforeFrames[b]?.size.width, afterFrames[b]?.size.width)
        XCTAssertGreaterThan(try XCTUnwrap(afterFrames[b]?.size.height), try XCTUnwrap(beforeFrames[b]?.size.height))
        XCTAssertEqual(beforeFrames[a], afterFrames[a])
    }

    func testSmartResizeTreeNoOpsAtEffectiveSplitLimit() {
        let a = WindowKey(processIdentifier: 1, windowIdentifier: 11)
        let b = WindowKey(processIdentifier: 2, windowIdentifier: 22)
        let tree = TiledNode.split(
            axis: .horizontal,
            // With two windows over 1,000 points, the 120-point safety floor caps the
            // focused share at 0.88 before the tree's broader 0.9 ratio clamp applies.
            ratio: 0.88,
            first: .window(a),
            second: .window(b)
        )

        XCTAssertNil(WorkspaceEngine.smartResizedTiledState(
            tree: tree,
            participants: [a, b],
            focusedIndex: 0,
            deltaPoints: 50,
            displayBounds: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            configuration: .aeroSpaceUserDefaults
        ))
    }

    func testAccordionSmartResizeAdjustsPaddingWithinBounds() {
        XCTAssertEqual(WorkspaceEngine.adjustedAccordionPadding(
            current: 250,
            delta: 50,
            availableLength: 1200
        ), 300)
        XCTAssertEqual(WorkspaceEngine.adjustedAccordionPadding(
            current: 0,
            delta: -50,
            availableLength: 1200
        ), nil)
    }

    func testDirectionalReorderOnlyUsesLayoutOrientationAndExistingNeighbour() {
        XCTAssertEqual(WorkspaceEngine.reorderDestinationIndex(
            sourceIndex: 1,
            count: 3,
            direction: .left,
            orientation: .horizontal
        ), 0)
        XCTAssertNil(WorkspaceEngine.reorderDestinationIndex(
            sourceIndex: 1,
            count: 3,
            direction: .up,
            orientation: .horizontal
        ))
        XCTAssertNil(WorkspaceEngine.reorderDestinationIndex(
            sourceIndex: 0,
            count: 3,
            direction: .left,
            orientation: .horizontal
        ))
    }

    func testLayoutOrderAndWeightPersistAcrossWindowSessionRestart() throws {
        let assignment = PersistedWindowAssignment(
            bundleIdentifier: "com.example.Editor",
            workspaceID: UUID(),
            restoreFrame: WindowFrame(position: .zero, size: CGSize(width: 800, height: 600)),
            layoutOrder: 7,
            layoutWeight: 0.625
        )
        let restored = try JSONDecoder().decode(
            PersistedWindowAssignment.self,
            from: JSONEncoder().encode(assignment)
        )

        XCTAssertEqual(restored.layoutOrder, 7)
        XCTAssertEqual(restored.layoutWeight, 0.625)
    }

    func testLegacyWindowAssignmentMigratesToSafeOrderAndWeightDefaults() throws {
        let workspaceID = UUID()
        let json = """
        {"bundleIdentifier":"com.example.Editor","workspaceID":"\(workspaceID.uuidString)","restoreFrame":{"position":[0,0],"size":[800,600]},"layoutOverride":"automatic"}
        """
        // CGPoint's JSON shape is platform-defined, so verify migration through a round trip with
        // the new optional fields removed rather than hard-coding that shape.
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(PersistedWindowAssignment(
                bundleIdentifier: "com.example.Editor",
                workspaceID: workspaceID,
                restoreFrame: WindowFrame(position: .zero, size: CGSize(width: 800, height: 600))
            ))) as? [String: Any]
        )
        object.removeValue(forKey: "layoutOrder")
        object.removeValue(forKey: "layoutWeight")
        let restored = try JSONDecoder().decode(
            PersistedWindowAssignment.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertNil(restored.layoutOrder)
        XCTAssertNil(restored.layoutWeight)
        XCTAssertEqual(WorkspaceEngine.validLayoutWeight(restored.layoutWeight), 1)
        XCTAssertFalse(json.isEmpty)
    }

    func testKeyboardManipulationFocusStaysOnExactWindow() {
        let expected = WindowKey(processIdentifier: 100, windowIdentifier: 1)

        XCTAssertEqual(WorkspaceEngine.keyboardManipulationFocusDecision(
            expected: expected,
            actual: expected,
            actualIsIgnored: false,
            expectedApplicationIsActive: true,
            recoveryAttempt: 0
        ), .stable)
    }

    func testKeyboardManipulationReassertsNilAndSameAppSiblingFocus() {
        let expected = WindowKey(processIdentifier: 100, windowIdentifier: 1)
        let sibling = WindowKey(processIdentifier: 100, windowIdentifier: 2)

        for actual in [WindowKey?.none, sibling] {
            XCTAssertEqual(WorkspaceEngine.keyboardManipulationFocusDecision(
                expected: expected,
                actual: actual,
                actualIsIgnored: false,
                expectedApplicationIsActive: true,
                recoveryAttempt: 0
            ), .reassertExactTarget)
        }
    }

    func testKeyboardManipulationDoesNotOverrideCompetingOrIgnoredFocus() {
        let expected = WindowKey(processIdentifier: 100, windowIdentifier: 1)
        let otherApplication = WindowKey(processIdentifier: 200, windowIdentifier: 1)
        let ignoredSameAppPanel = WindowKey(processIdentifier: 100, windowIdentifier: 99)

        XCTAssertEqual(WorkspaceEngine.keyboardManipulationFocusDecision(
            expected: expected,
            actual: otherApplication,
            actualIsIgnored: false,
            expectedApplicationIsActive: false,
            recoveryAttempt: 0
        ), .abortForCompetingFocus)
        XCTAssertEqual(WorkspaceEngine.keyboardManipulationFocusDecision(
            expected: expected,
            actual: ignoredSameAppPanel,
            actualIsIgnored: true,
            expectedApplicationIsActive: true,
            recoveryAttempt: 0
        ), .abortForCompetingFocus)
    }

    func testKeyboardManipulationRetryIsBounded() {
        let expected = WindowKey(processIdentifier: 100, windowIdentifier: 1)
        let sibling = WindowKey(processIdentifier: 100, windowIdentifier: 2)

        XCTAssertEqual(WorkspaceEngine.keyboardManipulationFocusDecision(
            expected: expected,
            actual: sibling,
            actualIsIgnored: false,
            expectedApplicationIsActive: true,
            recoveryAttempt: 1
        ), .failedAfterRetry)
    }

    func testNewKeyboardManipulationSupersedesPreviousVerification() {
        let previous = FocusVerificationToken(generation: 40, correlationID: "move")
        let latestGeneration: UInt64 = 41

        XCTAssertFalse(WorkspaceEngine.verificationIsCurrent(
            previous,
            generation: latestGeneration
        ))
    }
}

private final class TestDirectionalMoveRegistrationService: GlobalHotKeyRegistrationService {
    private let failingKeyCode: UInt32?

    init(failingKeyCode: UInt32? = nil) {
        self.failingKeyCode = failingKeyCode
    }

    func register(
        chord: HotKeyChord,
        identifier _: UInt32
    ) -> Result<HotKeyRegistrationToken, HotKeyRegistrationFailure> {
        if chord.keyCode == failingKeyCode {
            return .failure(HotKeyRegistrationFailure(status: OSStatus(eventHotKeyExistsErr)))
        }
        return .success(HotKeyRegistrationToken())
    }

    func unregister(_: HotKeyRegistrationToken) -> OSStatus { noErr }
}

private final class TestDirectionalMoveScheduledTask: DirectionalMoveGestureScheduledTask {
    private let action: () -> Void
    private(set) var isCancelled = false

    init(action: @escaping () -> Void) { self.action = action }
    func cancel() { isCancelled = true }
    func fire() {
        guard !isCancelled else { return }
        action()
    }
}

private final class TestDirectionalMoveScheduler: DirectionalMoveGestureScheduling {
    private(set) var latestTask: TestDirectionalMoveScheduledTask?
    private(set) var latestDelay: TimeInterval?

    func schedule(
        after delay: TimeInterval,
        action: @escaping () -> Void
    ) -> DirectionalMoveGestureScheduledTask {
        let task = TestDirectionalMoveScheduledTask(action: action)
        latestDelay = delay
        latestTask = task
        return task
    }

    func fireLatest() { latestTask?.fire() }
}

private final class TestDirectionalMoveMonitor: DirectionalMoveGestureMonitoring {
    private let canStart: Bool
    private var handler: ((DirectionalMoveObservedInput) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(canStart: Bool = true) {
        self.canStart = canStart
    }

    func start(handler: @escaping (DirectionalMoveObservedInput) -> Void) -> Bool {
        guard canStart else { return false }
        self.handler = handler
        startCount += 1
        return true
    }

    func stop() {
        if handler != nil { stopCount += 1 }
        handler = nil
    }

    func send(_ input: DirectionalMoveObservedInput) { handler?(input) }
}
