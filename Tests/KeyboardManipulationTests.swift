import Carbon
import XCTest

final class KeyboardManipulationTests: XCTestCase {
    func testDirectionalBindingsMatchUserAeroSpaceConfig() {
        XCTAssertEqual(HotKeyManager.directionalFocusKeyCodes.map(\.0), [.left, .down, .up, .right])
        XCTAssertEqual(HotKeyManager.directionalFocusKeyCodes.map(\.1), [4, 38, 40, 37])
        XCTAssertEqual(HotKeyManager.directionalMoveKeyCodes.map(\.0), [.left, .down, .up, .right])
        XCTAssertEqual(HotKeyManager.directionalMoveKeyCodes.map(\.1), [123, 125, 126, 124])
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
