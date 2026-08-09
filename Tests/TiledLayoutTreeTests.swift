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

    func testExplicitWorkspaceOrientationReorientsTreeWithoutChangingTopologyRatiosOrFocusIdentity() throws {
        let tree = TiledNode.split(
            axis: .horizontal,
            ratio: 0.62,
            first: .split(
                axis: .vertical,
                ratio: 0.37,
                first: .window(a),
                second: .window(b)
            ),
            second: .window(c)
        )

        let vertical = try XCTUnwrap(TiledLayoutEngine.reoriented(tree, orientation: .vertical))
        XCTAssertEqual(
            vertical,
            .split(
                axis: .vertical,
                ratio: 0.62,
                first: .split(
                    axis: .vertical,
                    ratio: 0.37,
                    first: .window(a),
                    second: .window(b)
                ),
                second: .window(c)
            )
        )
        XCTAssertEqual(vertical.windowKeys, tree.windowKeys)
        XCTAssertTrue(vertical.contains(c), "The focused window identity must survive orientation changes")
        XCTAssertNoThrow(try TiledLayoutEngine.validated(vertical, participants: [a, b, c]))

        let horizontal = try XCTUnwrap(TiledLayoutEngine.reoriented(vertical, orientation: .horizontal))
        guard case let .split(rootAxis, rootRatio, first, second) = horizontal,
              case let .split(childAxis, childRatio, _, _) = first
        else { return XCTFail("Reorientation must retain the tree structure") }
        XCTAssertEqual(rootAxis, .horizontal)
        XCTAssertEqual(childAxis, .horizontal)
        XCTAssertEqual(rootRatio, 0.62)
        XCTAssertEqual(childRatio, 0.37)
        XCTAssertEqual(second, .window(c))
    }

    func testWorkspaceTreeReorientationIsScopedAndSurvivesNormalReconciliation() throws {
        let selectedWorkspace = UUID(uuidString: "30000000-0000-0000-0000-000000000011")!
        let otherWorkspace = UUID(uuidString: "30000000-0000-0000-0000-000000000012")!
        let selectedMain = TiledLayoutPartitionKey(
            workspaceID: selectedWorkspace,
            displayIdentifier: "main"
        )
        let selectedExternal = TiledLayoutPartitionKey(
            workspaceID: selectedWorkspace,
            displayIdentifier: "external"
        )
        let unrelated = TiledLayoutPartitionKey(
            workspaceID: otherWorkspace,
            displayIdentifier: "main"
        )
        let tree = TiledNode.split(
            axis: .horizontal,
            ratio: 0.4,
            first: .window(a),
            second: .window(b)
        )
        let trees = [selectedMain: tree, selectedExternal: tree, unrelated: tree]

        let reoriented = TiledLayoutEngine.reorientedPartitions(
            trees,
            workspaceID: selectedWorkspace,
            orientation: .vertical
        )

        XCTAssertEqual(reoriented[unrelated], tree)
        for partition in [selectedMain, selectedExternal] {
            let changed = try XCTUnwrap(reoriented[partition])
            XCTAssertEqual(
                TiledLayoutEngine.reconciled(
                    changed,
                    windowKeys: [a, b],
                    weights: [1, 1],
                    orientation: .vertical
                ),
                changed,
                "The authoritative oriented tree must win after the production reconciliation step"
            )
        }
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

    func testThreeEqualColumnsMiddleToTopRightMatchesApprovedKeyboardPlacement() throws {
        let before = try XCTUnwrap(TiledLayoutEngine.flatTree(
            windowKeys: [a, b, c],
            orientation: .horizontal
        ))
        let bounds = CGRect(x: 0, y: 0, width: 1_200, height: 800)
        let preview = try TiledLayoutEngine.placing(
            b,
            at: .topRight,
            in: before,
            bounds: bounds,
            configuration: configuration()
        )

        guard case let .split(axis, ratio, first, second) = preview.proposedTree,
              case let .split(rightAxis, rightRatio, upper, lower) = second
        else { return XCTFail("Top Right must preserve the left column and create a right branch") }
        XCTAssertEqual(axis, .horizontal)
        XCTAssertEqual(ratio, 1.0 / 3.0, accuracy: 0.000_001)
        XCTAssertEqual(first, .window(a))
        XCTAssertEqual(rightAxis, .vertical)
        XCTAssertEqual(rightRatio, 0.5)
        XCTAssertEqual(upper, .window(b))
        XCTAssertEqual(lower, .window(c))
        XCTAssertEqual(preview.proposedTree.windowKeys, [a, b, c])

        let focusedFrame = try XCTUnwrap(preview.frames[b]).rect
        let formerRightFrame = try XCTUnwrap(preview.frames[c]).rect
        XCTAssertEqual(focusedFrame.maxX, bounds.maxX)
        XCTAssertEqual(focusedFrame.minY, bounds.minY)
        XCTAssertEqual(formerRightFrame.maxX, bounds.maxX)
        XCTAssertEqual(formerRightFrame.maxY, bounds.maxY)
        XCTAssertEqual(focusedFrame.maxY, formerRightFrame.minY)
    }

    func testKeyboardCornerMappingAndPlacementCoversAllFourDestinations() throws {
        let tree = try XCTUnwrap(TiledLayoutEngine.flatTree(
            windowKeys: [a, b, c],
            orientation: .horizontal
        ))
        let bounds = CGRect(x: -900, y: 24, width: 1_800, height: 1_000)
        let cases: [(WindowDirection, WindowDirection, VisualPlacement)] = [
            (.up, .left, .topLeft),
            (.up, .right, .topRight),
            (.down, .left, .bottomLeft),
            (.down, .right, .bottomRight),
        ]
        for (vertical, horizontal, placement) in cases {
            XCTAssertEqual(VisualPlacement.corner(vertical, horizontal), placement)
            XCTAssertEqual(VisualPlacement.corner(horizontal, vertical), placement)
            let preview = try TiledLayoutEngine.placing(
                b,
                at: placement,
                in: tree,
                bounds: bounds,
                configuration: configuration()
            )
            let frame = try XCTUnwrap(preview.frames[b]).rect
            if horizontal == .left {
                XCTAssertEqual(frame.minX, bounds.minX)
            } else {
                XCTAssertEqual(frame.maxX, bounds.maxX)
            }
            if vertical == .up {
                XCTAssertEqual(frame.minY, bounds.minY)
            } else {
                XCTAssertEqual(frame.maxY, bounds.maxY)
            }
            XCTAssertEqual(Set(preview.proposedTree.windowKeys), [a, b, c])
        }
        XCTAssertNil(VisualPlacement.corner(.left, .right))
        XCTAssertNil(VisualPlacement.corner(.up, .down))
        XCTAssertNil(VisualPlacement.corner(.left, .left))
    }

    func testPlacementHistoryUndoRedoRequiresExactTreeAndParticipantIdentity() throws {
        let before = try XCTUnwrap(TiledLayoutEngine.flatTree(
            windowKeys: [a, b, c],
            orientation: .horizontal
        ))
        let preview = try TiledLayoutEngine.placing(
            b,
            at: .topRight,
            in: before,
            bounds: CGRect(x: 0, y: 0, width: 1_200, height: 800),
            configuration: configuration()
        )
        let transaction = TiledPlacementUndoTransaction(
            partition: TiledLayoutPartitionKey(workspaceID: UUID(), displayIdentifier: "external"),
            focusedWindow: b,
            participantKeys: [a, b, c],
            beforeTree: before,
            afterTree: preview.proposedTree,
            actionName: "Place Window Top Right"
        )

        XCTAssertEqual(
            TiledLayoutEngine.historyTarget(
                currentTree: preview.proposedTree,
                currentParticipants: [a, b, c],
                transaction: transaction,
                direction: .undo
            ),
            before
        )
        XCTAssertEqual(
            TiledLayoutEngine.historyTarget(
                currentTree: before,
                currentParticipants: [a, b, c],
                transaction: transaction,
                direction: .redo
            ),
            preview.proposedTree
        )
        XCTAssertNil(TiledLayoutEngine.historyTarget(
            currentTree: before,
            currentParticipants: [a, b, c],
            transaction: transaction,
            direction: .undo
        ))
        XCTAssertNil(TiledLayoutEngine.historyTarget(
            currentTree: preview.proposedTree,
            currentParticipants: [a, b],
            transaction: transaction,
            direction: .undo
        ))
    }

    func testCornerPlacementKeepsUnrelatedNestedSubtreeTopologyAndRatios() throws {
        let untouched = TiledNode.split(
            axis: .vertical,
            ratio: 0.63,
            first: .window(a),
            second: .window(d)
        )
        let before = TiledNode.split(
            axis: .horizontal,
            ratio: 0.41,
            first: untouched,
            second: .split(
                axis: .horizontal,
                ratio: 0.52,
                first: .window(b),
                second: .window(c)
            )
        )
        let preview = try TiledLayoutEngine.placing(
            b,
            at: .bottomRight,
            in: before,
            bounds: CGRect(x: 0, y: 0, width: 1_600, height: 1_000),
            configuration: configuration()
        )

        guard case let .split(axis, ratio, first, _) = preview.proposedTree else {
            return XCTFail("Outer structure should remain")
        }
        XCTAssertEqual(axis, .horizontal)
        XCTAssertEqual(ratio, 0.41)
        XCTAssertEqual(first, untouched)
        XCTAssertEqual(Set(preview.proposedTree.windowKeys), [a, b, c, d])
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

    func testDirectionalMoveSwapsAuthoritativeLeavesAndActuallyChangesFrames() throws {
        // Matches the live trace's two-window, wide-display Tiled topology.
        let bounds = CGRect(x: 0, y: 30, width: 3_360, height: 1_388)
        let tree = TiledNode.split(
            axis: .horizontal,
            ratio: 0.5,
            first: .window(a),
            second: .window(b)
        )
        let before = try rects(tree, bounds: bounds, configuration: configuration())
        let moved = try XCTUnwrap(WorkspaceEngine.directionallyReorderedTiledState(
            tree: tree,
            focusedWindow: a,
            direction: .right,
            displayBounds: bounds,
            configuration: configuration()
        ))
        let after = try rects(moved.tree, bounds: bounds, configuration: configuration())

        XCTAssertEqual(moved.destinationWindow, b)
        XCTAssertEqual(moved.tree.windowKeys, [b, a])
        XCTAssertEqual(after[a], before[b])
        XCTAssertEqual(after[b], before[a])
        XCTAssertNotEqual(after, before)
        XCTAssertEqual(moved.effectiveShares[a], 0.5)
        XCTAssertEqual(moved.effectiveShares[b], 0.5)
    }

    func testDirectionalMoveRepeatsInBothDirectionsAndNoOpsAtBoundary() throws {
        let bounds = CGRect(x: 0, y: 0, width: 1_000, height: 600)
        let original = TiledNode.split(
            axis: .horizontal,
            ratio: 0.35,
            first: .window(a),
            second: .window(b)
        )
        let movedRight = try XCTUnwrap(WorkspaceEngine.directionallyReorderedTiledState(
            tree: original,
            focusedWindow: a,
            direction: .right,
            displayBounds: bounds,
            configuration: configuration()
        ))
        XCTAssertNil(WorkspaceEngine.directionallyReorderedTiledState(
            tree: movedRight.tree,
            focusedWindow: a,
            direction: .right,
            displayBounds: bounds,
            configuration: configuration()
        ))
        let movedLeft = try XCTUnwrap(WorkspaceEngine.directionallyReorderedTiledState(
            tree: movedRight.tree,
            focusedWindow: a,
            direction: .left,
            displayBounds: bounds,
            configuration: configuration()
        ))
        XCTAssertEqual(movedLeft.tree, original)
        XCTAssertNil(WorkspaceEngine.directionallyReorderedTiledState(
            tree: movedLeft.tree,
            focusedWindow: a,
            direction: .left,
            displayBounds: bounds,
            configuration: configuration()
        ))
    }

    func testDirectionalMoveUsesNestedVerticalNeighbourWithoutFlatteningTree() throws {
        let bounds = CGRect(x: 0, y: 0, width: 1_200, height: 900)
        let tree = TiledNode.split(
            axis: .horizontal,
            ratio: 0.6,
            first: .window(a),
            second: .split(
                axis: .vertical,
                ratio: 0.4,
                first: .window(b),
                second: .window(c)
            )
        )
        let moved = try XCTUnwrap(WorkspaceEngine.directionallyReorderedTiledState(
            tree: tree,
            focusedWindow: b,
            direction: .down,
            displayBounds: bounds,
            configuration: configuration()
        ))

        XCTAssertEqual(moved.destinationWindow, c)
        XCTAssertEqual(moved.tree.windowKeys, [a, c, b])
        guard case let .split(rootAxis, rootRatio, first, second) = moved.tree,
              case let .split(nestedAxis, nestedRatio, nestedFirst, nestedSecond) = second
        else { return XCTFail("Directional movement must preserve the placement topology") }
        XCTAssertEqual(rootAxis, .horizontal)
        XCTAssertEqual(rootRatio, 0.6)
        XCTAssertEqual(first, .window(a))
        XCTAssertEqual(nestedAxis, .vertical)
        XCTAssertEqual(nestedRatio, 0.4)
        XCTAssertEqual(nestedFirst, .window(c))
        XCTAssertEqual(nestedSecond, .window(b))
    }

    func testDirectionalMoveLeftSwapsSelectedRightLeafWithWholeCompoundSibling() throws {
        let left = TiledNode.split(
            axis: .vertical,
            ratio: 0.37,
            first: .window(a),
            second: .window(b)
        )
        let tree = TiledNode.split(
            axis: .horizontal,
            ratio: 0.62,
            first: left,
            second: .window(c)
        )

        let moved = try XCTUnwrap(WorkspaceEngine.directionallyReorderedTiledState(
            tree: tree,
            focusedWindow: c,
            direction: .left,
            displayBounds: CGRect(x: 0, y: 0, width: 1_200, height: 900),
            configuration: configuration()
        ))

        XCTAssertEqual(moved.strategy, .directSiblingBranch)
        guard case let .split(axis, ratio, first, second) = moved.tree else {
            return XCTFail("The direct split must remain intact")
        }
        XCTAssertEqual(axis, .horizontal)
        XCTAssertEqual(ratio, 0.62)
        XCTAssertEqual(first, .window(c))
        XCTAssertEqual(second, left, "The compound sibling must move as one intact branch")
    }

    func testDirectionalMoveRightMirrorsWholeCompoundSiblingSwap() throws {
        let right = TiledNode.split(
            axis: .vertical,
            ratio: 0.41,
            first: .window(a),
            second: .window(b)
        )
        let tree = TiledNode.split(
            axis: .horizontal,
            ratio: 0.46,
            first: .window(c),
            second: right
        )

        let moved = try XCTUnwrap(WorkspaceEngine.directionallyReorderedTiledState(
            tree: tree,
            focusedWindow: c,
            direction: .right,
            displayBounds: CGRect(x: 0, y: 0, width: 1_200, height: 900),
            configuration: configuration()
        ))

        XCTAssertEqual(moved.strategy, .directSiblingBranch)
        XCTAssertEqual(
            moved.tree,
            .split(axis: .horizontal, ratio: 0.46, first: right, second: .window(c))
        )
    }

    func testDirectionalBranchSwapCanOccurInsideUnrelatedAncestor() throws {
        let sibling = TiledNode.split(
            axis: .vertical,
            ratio: 0.33,
            first: .window(a),
            second: .window(b)
        )
        let inner = TiledNode.split(
            axis: .horizontal,
            ratio: 0.58,
            first: sibling,
            second: .window(c)
        )
        let tree = TiledNode.split(
            axis: .vertical,
            ratio: 0.72,
            first: .window(d),
            second: inner
        )

        let moved = try XCTUnwrap(WorkspaceEngine.directionallyReorderedTiledState(
            tree: tree,
            focusedWindow: c,
            direction: .left,
            displayBounds: CGRect(x: 0, y: 0, width: 1_400, height: 1_000),
            configuration: configuration()
        ))

        XCTAssertEqual(moved.strategy, .directSiblingBranch)
        XCTAssertEqual(
            moved.tree,
            .split(
                axis: .vertical,
                ratio: 0.72,
                first: .window(d),
                second: .split(
                    axis: .horizontal,
                    ratio: 0.58,
                    first: .window(c),
                    second: sibling
                )
            )
        )
    }

    func testDirectionalMoveUpSwapsSelectedBottomLeafWithWholeCompoundSibling() throws {
        let top = TiledNode.split(
            axis: .horizontal,
            ratio: 0.44,
            first: .window(a),
            second: .window(b)
        )
        let tree = TiledNode.split(
            axis: .vertical,
            ratio: 0.57,
            first: top,
            second: .window(c)
        )

        let moved = try XCTUnwrap(WorkspaceEngine.directionallyReorderedTiledState(
            tree: tree,
            focusedWindow: c,
            direction: .up,
            displayBounds: CGRect(x: 0, y: 0, width: 1_200, height: 900),
            configuration: configuration()
        ))

        XCTAssertEqual(moved.strategy, .directSiblingBranch)
        XCTAssertEqual(
            moved.tree,
            .split(axis: .vertical, ratio: 0.57, first: .window(c), second: top)
        )
    }

    func testDirectionalMoveFallsBackToVisualLeafWhenNoDirectAxisBoundaryExists() throws {
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

        let moved = try XCTUnwrap(WorkspaceEngine.directionallyReorderedTiledState(
            tree: tree,
            focusedWindow: b,
            direction: .left,
            displayBounds: CGRect(x: 0, y: 0, width: 1_200, height: 900),
            configuration: configuration()
        ))

        XCTAssertEqual(moved.strategy, .visualNeighbourLeaf)
        XCTAssertEqual(
            moved.tree,
            .split(
                axis: .horizontal,
                ratio: 0.5,
                first: .window(b),
                second: .split(
                    axis: .vertical,
                    ratio: 0.5,
                    first: .window(a),
                    second: .window(c)
                )
            )
        )
    }

    func testLeafSwapRejectsMissingDuplicateOrInvalidParticipants() {
        let tree = TiledNode.split(
            axis: .horizontal,
            ratio: 0.5,
            first: .window(a),
            second: .window(b)
        )
        XCTAssertNil(TiledLayoutEngine.swappingWindows(a, a, in: tree))
        XCTAssertNil(TiledLayoutEngine.swappingWindows(a, c, in: tree))
        let duplicate = TiledNode.split(
            axis: .horizontal,
            ratio: 0.5,
            first: .window(a),
            second: .window(a)
        )
        XCTAssertNil(TiledLayoutEngine.swappingWindows(a, b, in: duplicate))
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
