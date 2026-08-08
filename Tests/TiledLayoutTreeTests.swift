import CoreGraphics
import XCTest

final class TiledLayoutTreeTests: XCTestCase {
    private let a = WindowKey(processIdentifier: 10, windowIdentifier: 101)
    private let b = WindowKey(processIdentifier: 11, windowIdentifier: 102)
    private let c = WindowKey(processIdentifier: 12, windowIdentifier: 103)
    private let d = WindowKey(processIdentifier: 13, windowIdentifier: 104)

    func testFlatConversionPreservesOneTwoAndWeightedManyWindowGeometry() throws {
        let bounds = CGRect(x: 0, y: 0, width: 1_000, height: 600)
        let configuration = configuration()

        let one = try XCTUnwrap(TiledLayoutEngine.flatTree(
            windowKeys: [a],
            orientation: .horizontal
        ))
        XCTAssertEqual(try rects(one, bounds: bounds, configuration: configuration)[a], bounds)

        let two = try XCTUnwrap(TiledLayoutEngine.flatTree(
            windowKeys: [a, b],
            weights: [1, 1],
            orientation: .horizontal
        ))
        let twoFrames = try rects(two, bounds: bounds, configuration: configuration)
        XCTAssertEqual(twoFrames[a], CGRect(x: 0, y: 0, width: 500, height: 600))
        XCTAssertEqual(twoFrames[b], CGRect(x: 500, y: 0, width: 500, height: 600))

        let many = try XCTUnwrap(TiledLayoutEngine.flatTree(
            windowKeys: [a, b, c],
            weights: [2, 3, 5],
            orientation: .horizontal
        ))
        let manyFrames = try rects(many, bounds: bounds, configuration: configuration)
        XCTAssertEqual(manyFrames[a], CGRect(x: 0, y: 0, width: 200, height: 600))
        XCTAssertEqual(manyFrames[b], CGRect(x: 200, y: 0, width: 300, height: 600))
        XCTAssertEqual(manyFrames[c], CGRect(x: 500, y: 0, width: 500, height: 600))
    }

    func testVerticalGeometryAppliesInnerGapsAndOuterPaddingExactlyOnce() throws {
        let tree = try XCTUnwrap(TiledLayoutEngine.flatTree(
            windowKeys: [a, b],
            orientation: .vertical
        ))
        let frames = try rects(
            tree,
            bounds: CGRect(x: -1_200, y: 20, width: 800, height: 1_000),
            configuration: WorkspaceLayoutConfiguration(
                orientation: .vertical,
                accordionPadding: 250,
                gaps: WorkspaceLayoutGaps(
                    innerHorizontal: 7,
                    innerVertical: 20,
                    outerTop: 30,
                    outerRight: 40,
                    outerBottom: 50,
                    outerLeft: 60
                )
            )
        )
        XCTAssertEqual(frames[a], CGRect(x: -1_140, y: 50, width: 700, height: 450))
        XCTAssertEqual(frames[b], CGRect(x: -1_140, y: 520, width: 700, height: 450))
    }

    func testValidationRejectsDuplicatesParticipantMismatchAndInvalidRatios() {
        let duplicate = TiledNode.split(
            axis: .horizontal,
            ratio: 0.5,
            first: .window(a),
            second: .window(a)
        )
        XCTAssertThrowsError(try TiledLayoutEngine.validated(duplicate, participants: [a])) {
            XCTAssertEqual($0 as? TiledLayoutError, .duplicateWindow)
        }

        XCTAssertThrowsError(try TiledLayoutEngine.validated(.window(a), participants: [a, b])) {
            XCTAssertEqual($0 as? TiledLayoutError, .participantMismatch)
        }

        let invalidRatio = TiledNode.split(
            axis: .vertical,
            ratio: 1,
            first: .window(a),
            second: .window(b)
        )
        XCTAssertThrowsError(try TiledLayoutEngine.validated(invalidRatio, participants: [a, b])) {
            XCTAssertEqual($0 as? TiledLayoutError, .invalidRatio)
        }
    }

    func testEveryEdgePlacementTouchesTheRequestedUsableDisplayEdge() throws {
        let bounds = CGRect(x: -1_920, y: 24, width: 1_920, height: 1_056)
        let tree = try XCTUnwrap(TiledLayoutEngine.flatTree(
            windowKeys: [a, b, c],
            orientation: .horizontal
        ))

        for placement in [VisualPlacement.left, .right, .top, .bottom] {
            let preview = try TiledLayoutEngine.placing(
                b,
                at: placement,
                in: tree,
                bounds: bounds,
                configuration: configuration()
            )
            XCTAssertEqual(Set(preview.proposedTree.windowKeys), [a, b, c])
            let frame = try XCTUnwrap(preview.frames[b]).rect
            switch placement {
            case .left: XCTAssertEqual(frame.minX, bounds.minX)
            case .right: XCTAssertEqual(frame.maxX, bounds.maxX)
            case .top: XCTAssertEqual(frame.minY, bounds.minY)
            case .bottom: XCTAssertEqual(frame.maxY, bounds.maxY)
            default: XCTFail("Unexpected placement")
            }
        }
    }

    func testCornerPlacementPreservesUntouchedSubtreeAndMovesFocusedWindowLocally() throws {
        let before = TiledNode.split(
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
        let preview = try TiledLayoutEngine.placing(
            c,
            at: .topLeft,
            in: before,
            bounds: CGRect(x: 0, y: 0, width: 1_200, height: 800),
            configuration: configuration()
        )
        let expected = TiledNode.split(
            axis: .horizontal,
            ratio: 0.5,
            first: .split(
                axis: .vertical,
                ratio: 0.5,
                first: .window(c),
                second: .window(a)
            ),
            second: .window(b)
        )

        XCTAssertEqual(preview.proposedTree, expected)
        XCTAssertEqual(preview.proposedTree.windowKeys, [c, a, b])
        XCTAssertEqual(try XCTUnwrap(preview.frames[c]).rect.minX, 0)
        XCTAssertEqual(try XCTUnwrap(preview.frames[c]).rect.minY, 0)
    }

    func testOneAndTwoWindowCornerPlacementsAreHonestAndDeterministic() throws {
        let bounds = CGRect(x: 0, y: 0, width: 900, height: 600)
        let one = TiledNode.window(a)
        let onePreview = try TiledLayoutEngine.placing(
            a,
            at: .bottomRight,
            in: one,
            bounds: bounds,
            configuration: configuration()
        )
        XCTAssertEqual(onePreview.proposedTree, one)
        XCTAssertEqual(onePreview.frames[a]?.rect, bounds)

        let two = TiledNode.split(
            axis: .horizontal,
            ratio: 0.5,
            first: .window(a),
            second: .window(b)
        )
        let twoPreview = try TiledLayoutEngine.placing(
            b,
            at: .topLeft,
            in: two,
            bounds: bounds,
            configuration: configuration()
        )
        let focusedFrame = try XCTUnwrap(twoPreview.frames[b]).rect
        XCTAssertEqual(focusedFrame.minX, bounds.minX)
        XCTAssertEqual(focusedFrame.maxX, bounds.maxX)
        XCTAssertEqual(focusedFrame.minY, bounds.minY)
        XCTAssertEqual(focusedFrame.height, bounds.height / 2)
    }

    func testReconciliationRemovesStaleLeavesAndAppendsNewParticipantsOnce() throws {
        let old = TiledNode.split(
            axis: .horizontal,
            ratio: 0.4,
            first: .window(a),
            second: .split(
                axis: .vertical,
                ratio: 0.6,
                first: .window(b),
                second: .window(c)
            )
        )
        let reconciled = try XCTUnwrap(TiledLayoutEngine.reconciled(
            old,
            windowKeys: [a, c, d],
            weights: nil,
            orientation: .vertical
        ))
        XCTAssertEqual(Set(reconciled.windowKeys), [a, c, d])
        XCTAssertEqual(reconciled.windowKeys.filter { $0 == d }.count, 1)
        XCTAssertNoThrow(try TiledLayoutEngine.validated(reconciled, participants: [a, c, d]))
    }

    func testNearestSplitResizeMakesNestedTopBottomWindowOnlyTaller() throws {
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
        let beforeFrames = try TiledLayoutEngine.frames(
            for: tree,
            in: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            configuration: configuration()
        )
        let resized = try XCTUnwrap(TiledLayoutEngine.resizedNearestSplit(
            tree,
            focusedWindow: b,
            deltaPoints: 100,
            displayBounds: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            configuration: configuration()
        ))
        let afterFrames = try TiledLayoutEngine.frames(
            for: resized,
            in: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            configuration: configuration()
        )

        XCTAssertEqual(resized.windowKeys, [a, b, c])
        XCTAssertEqual(beforeFrames[a], afterFrames[a])
        XCTAssertEqual(beforeFrames[b]?.size.width, afterFrames[b]?.size.width)
        XCTAssertGreaterThan(try XCTUnwrap(afterFrames[b]?.size.height), try XCTUnwrap(beforeFrames[b]?.size.height))
        XCTAssertEqual(beforeFrames[c]?.size.width, afterFrames[c]?.size.width)
        XCTAssertLessThan(try XCTUnwrap(afterFrames[c]?.size.height), try XCTUnwrap(beforeFrames[c]?.size.height))
        guard case let .split(rootAxis, rootRatio, _, second) = resized,
              case let .split(nestedAxis, nestedRatio, _, _) = second
        else { return XCTFail("Resize must preserve the placement tree") }
        XCTAssertEqual(rootAxis, .horizontal)
        XCTAssertEqual(rootRatio, 0.5)
        XCTAssertEqual(nestedAxis, .vertical)
        XCTAssertEqual(nestedRatio, 0.625, accuracy: 0.000_001)
    }

    func testNearestSplitResizeMakesLeftRightWindowOnlyWider() throws {
        let tree = TiledNode.split(
            axis: .horizontal,
            ratio: 0.5,
            first: .window(a),
            second: .window(b)
        )
        let bounds = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let beforeFrames = try TiledLayoutEngine.frames(
            for: tree,
            in: bounds,
            configuration: configuration()
        )
        let resized = try XCTUnwrap(TiledLayoutEngine.resizedNearestSplit(
            tree,
            focusedWindow: a,
            deltaPoints: 100,
            displayBounds: bounds,
            configuration: configuration()
        ))
        let afterFrames = try TiledLayoutEngine.frames(
            for: resized,
            in: bounds,
            configuration: configuration()
        )

        XCTAssertGreaterThan(try XCTUnwrap(afterFrames[a]?.size.width), try XCTUnwrap(beforeFrames[a]?.size.width))
        XCTAssertEqual(beforeFrames[a]?.size.height, afterFrames[a]?.size.height)
        XCTAssertLessThan(try XCTUnwrap(afterFrames[b]?.size.width), try XCTUnwrap(beforeFrames[b]?.size.width))
        XCTAssertEqual(beforeFrames[b]?.size.height, afterFrames[b]?.size.height)
    }

    func testNearestSplitAtLimitDoesNotFallBackToOuterAxis() {
        let tree = TiledNode.split(
            axis: .horizontal,
            ratio: 0.5,
            first: .window(a),
            second: .split(
                axis: .vertical,
                ratio: 0.85,
                first: .window(b),
                second: .window(c)
            )
        )

        XCTAssertNil(TiledLayoutEngine.resizedNearestSplit(
            tree,
            focusedWindow: b,
            deltaPoints: 50,
            displayBounds: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            configuration: configuration()
        ))
    }

    func testNearestSplitResizeRejectsMissingWindowAndStopsAtSafeLimit() {
        let tree = TiledNode.split(
            axis: .horizontal,
            ratio: 0.88,
            first: .window(a),
            second: .window(b)
        )
        XCTAssertNil(TiledLayoutEngine.resizedNearestSplit(
            tree,
            focusedWindow: c,
            deltaPoints: 50,
            displayBounds: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            configuration: configuration()
        ))
        XCTAssertNil(TiledLayoutEngine.resizedNearestSplit(
            tree,
            focusedWindow: a,
            deltaPoints: 50,
            displayBounds: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            configuration: configuration()
        ))
    }

    func testPreviewIsPureDataAndCodingRoundTripRetainsSessionPartition() throws {
        let tree = try XCTUnwrap(TiledLayoutEngine.flatTree(
            windowKeys: [a, b, c],
            orientation: .horizontal
        ))
        let preview = try TiledLayoutEngine.placing(
            b,
            at: .right,
            in: tree,
            bounds: CGRect(x: 0, y: 0, width: 1_200, height: 800),
            configuration: configuration()
        )
        XCTAssertEqual(preview.fingerprint, TiledLayoutEngine.fingerprint(preview.proposedTree))
        XCTAssertEqual(Set(preview.frames.keys), [a, b, c])

        let partition = TiledLayoutPartitionKey(
            workspaceID: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
            displayIdentifier: "external"
        )
        let persisted = PersistedTiledTree(partition: partition, tree: preview.proposedTree)
        let restored = try JSONDecoder().decode(
            PersistedTiledTree.self,
            from: JSONEncoder().encode(persisted)
        )
        XCTAssertEqual(restored, persisted)
    }

    func testWorkspaceStateStoreKeepsTreeOnlyWithinMatchingWindowServerSession() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WindowManagerTiledTreeTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspaceID = UUID(uuidString: "30000000-0000-0000-0000-000000000002")!
        let partition = TiledLayoutPartitionKey(
            workspaceID: workspaceID,
            displayIdentifier: "external"
        )
        let tree = TiledNode.split(
            axis: .horizontal,
            ratio: 0.5,
            first: .window(a),
            second: .window(b)
        )
        let state = PersistedWorkspaceState(
            version: PersistedWorkspaceState.currentVersion,
            windowServerSession: "same-session",
            activeWorkspaceID: workspaceID,
            windows: [:],
            tiledTrees: [PersistedTiledTree(partition: partition, tree: tree)]
        )

        WorkspaceStateStore(fileURL: fileURL) { "same-session" }
            .save(state, waitForCompletion: true)
        XCTAssertEqual(
            WorkspaceStateStore(fileURL: fileURL) { "same-session" }.load()?.tiledTrees,
            state.tiledTrees
        )
        XCTAssertNil(WorkspaceStateStore(fileURL: fileURL) { "different-session" }.load())
    }

    private func configuration() -> WorkspaceLayoutConfiguration {
        WorkspaceLayoutConfiguration(
            orientation: .automatic,
            accordionPadding: 250,
            gaps: WorkspaceLayoutGaps(
                innerHorizontal: 0,
                innerVertical: 0,
                outerTop: 0,
                outerRight: 0,
                outerBottom: 0,
                outerLeft: 0
            )
        )
    }

    private func rects(
        _ tree: TiledNode,
        bounds: CGRect,
        configuration: WorkspaceLayoutConfiguration
    ) throws -> [WindowKey: CGRect] {
        try TiledLayoutEngine.frames(for: tree, in: bounds, configuration: configuration)
            .mapValues(\.rect)
    }
}

private extension WindowFrame {
    var rect: CGRect { CGRect(origin: position, size: size) }
}
