import AppKit
import Carbon
import Combine
import SwiftUI
import XCTest

final class RadialMenuAndSettingsTests: XCTestCase {
    private let workspaceA = WorkspaceDefinition(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
        name: "Code",
        key: "c",
        layout: .tiled
    )
    private let workspaceB = WorkspaceDefinition(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
        name: "Comms",
        key: "m",
        layout: .accordion
    )
    private let workspaceC = WorkspaceDefinition(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
        name: "Browse",
        key: "b",
        layout: .none
    )

    func testNoFocusedWindowShowsOnlyTruthfulWorkspaceAndLayoutItems() {
        let menu = RadialCommandContextBuilder.build(from: context(window: nil))

        XCTAssertEqual(menu.items.map(\.id), [
            RadialTopLevelItemID.goToSpace.rawValue,
            RadialTopLevelItemID.nextSpace.rawValue,
            RadialTopLevelItemID.previousSpace.rawValue,
            RadialTopLevelItemID.resetWindowsInSpace.rawValue,
            RadialTopLevelItemID.resetAllWindows.rawValue,
            RadialTopLevelItemID.layoutType.rawValue,
        ])
        XCTAssertFalse(menu.items.contains { $0.id == RadialTopLevelItemID.moveToSpace.rawValue })
        XCTAssertFalse(menu.items.contains { $0.id == RadialTopLevelItemID.resize.rawValue })
    }

    func testLayoutTypeHasPrimaryCycleAndThreeGeneratedChildrenWithCurrentState() {
        for layout in WorkspaceLayout.allCases {
            let menu = RadialCommandContextBuilder.build(from: context(layout: layout, window: nil))
            let item = try! XCTUnwrap(menu.items.first { $0.id == RadialTopLevelItemID.layoutType.rawValue })
            XCTAssertEqual(item.command, .cycleLayout(1))
            XCTAssertEqual(item.children.map(\.command), WorkspaceLayout.allCases.map { .setLayout($0) })
            XCTAssertEqual(item.children.filter(\.isCurrent).count, 1)
            XCTAssertTrue(item.children.first(where: { $0.command == .setLayout(.none) })?.label.contains("Freeform") == true)
        }
    }

    func testTiledManagedWindowGetsCompassPlacementPreviewChildren() {
        let menu = RadialCommandContextBuilder.build(from: context(window: window(.managed)))
        let place = try! XCTUnwrap(menu.items.first { $0.id == RadialTopLevelItemID.resize.rawValue })

        XCTAssertEqual(place.label, "Place")
        XCTAssertEqual(place.childGeometry, .compass)
        XCTAssertEqual(place.children.compactMap { $0.placementPreview?.placement }, VisualPlacement.compassOrder)
        XCTAssertTrue(place.children.allSatisfy { $0.command != nil && $0.placementPreview != nil })
    }

    func testFreeformOmitsResizeWithoutChangingLayoutType() {
        let menu = RadialCommandContextBuilder.build(from: context(layout: .none, window: window(.managed)))
        XCTAssertFalse(menu.items.contains { $0.id == RadialTopLevelItemID.resize.rawValue })
        XCTAssertTrue(menu.items.contains { $0.id == RadialTopLevelItemID.moveToSpace.rawValue })
    }

    func testAccordionResizeUsesOnlyTruthfulSizeActions() {
        let menu = RadialCommandContextBuilder.build(from: context(
            layout: .accordion,
            window: window(.managed),
            canSmartResize: true
        ))
        let resize = try! XCTUnwrap(menu.items.first { $0.id == RadialTopLevelItemID.resize.rawValue })
        XCTAssertEqual(Set(resize.children.compactMap(\.command)), [.smartResize(-50), .smartResize(50)])
        XCTAssertTrue(resize.children.allSatisfy { $0.placementPreview == nil })
    }

    func testFloatingAndAutomaticDialogExposeOnlyReturnOverride() {
        for state in [
            RadialFocusedWindowLayoutState.floating,
            .automaticallyFloatingDialog,
            .automaticallyFloatingSecondary,
        ] {
            let menu = RadialCommandContextBuilder.build(from: context(window: window(state)))
            let item = try! XCTUnwrap(menu.items.first { $0.id == RadialTopLevelItemID.resize.rawValue })
            XCTAssertEqual(item.command, .toggleFloating)
            XCTAssertTrue(item.children.isEmpty)
        }
    }

    func testAppRuleExcludedAndKeepOnAllPrecedenceRemovesContradictoryItems() {
        let excluded = RadialCommandContextBuilder.build(from: context(
            window: window(.appRuleExcluded, appRuleExcluded: true)
        ))
        XCTAssertFalse(excluded.items.contains { $0.id == RadialTopLevelItemID.resize.rawValue })
        XCTAssertEqual(excluded.stateNote, "Layout controlled by App Rule")

        let everywhere = RadialCommandContextBuilder.build(from: context(
            window: window(.managed, keepsOnAll: true)
        ))
        XCTAssertFalse(everywhere.items.contains { $0.id == RadialTopLevelItemID.moveToSpace.rawValue })
        XCTAssertEqual(everywhere.stateNote, "Visible on every workspace")
    }

    func testMoveToSpaceGeneratesPrimarySendAndOptionFollowFromOneChild() {
        let menu = RadialCommandContextBuilder.build(from: context(mode: .unified, window: window(.managed)))
        let move = try! XCTUnwrap(menu.items.first { $0.id == RadialTopLevelItemID.moveToSpace.rawValue })
        let comms = try! XCTUnwrap(move.children.first { $0.label == workspaceB.name })

        XCTAssertEqual(comms.command, .moveFocusedWindow(workspaceB.id))
        XCTAssertEqual(comms.alternateCommand, .moveFocusedWindowAndFollow(workspaceB.id))
        XCTAssertEqual(move.children.map(\.label), [workspaceB.name, workspaceC.name])
    }

    func testIndependentMoveDestinationsStayOnInteractionDisplay() {
        let menu = RadialCommandContextBuilder.build(from: context(
            mode: .independent,
            window: window(.managed)
        ))
        let move = try! XCTUnwrap(menu.items.first { $0.id == RadialTopLevelItemID.moveToSpace.rawValue })
        XCTAssertEqual(move.children.map(\.label), [workspaceC.name])
        XCTAssertEqual(move.children.first?.alternateCommand, .moveFocusedWindowAndFollow(workspaceC.id))
    }

    func testProfilesAreGeneratedInStableOrderAndResumeOnlyWhenPinned() {
        let first = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        let second = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        var value = context(window: nil)
        value.profiles = [.init(id: first, name: "Laptop"), .init(id: second, name: "Studio")]
        value.activeProfileID = first
        value.isProfileManuallyPinned = true

        let profiles = try! XCTUnwrap(RadialCommandContextBuilder.build(from: value).items.first {
            $0.id == RadialTopLevelItemID.profiles.rawValue
        })
        XCTAssertEqual(profiles.label, "Profiles · Laptop active")
        XCTAssertEqual(profiles.children.map(\.label), ["Studio", "Resume Automatic"])
        XCTAssertEqual(profiles.children[0].command, .selectProfile(second))
        XCTAssertEqual(profiles.children[1].command, .resumeAutomaticProfileSelection)
    }

    func testIgnoredPanelContextCannotBecomeAWindowActionTarget() {
        let menu = RadialCommandContextBuilder.build(from: context(window: nil, focusSource: .preservedManagedAnchor))
        XCTAssertFalse(menu.items.contains { $0.id == RadialTopLevelItemID.moveToSpace.rawValue })
        XCTAssertFalse(menu.items.contains { $0.id == RadialTopLevelItemID.resize.rawValue })
        XCTAssertTrue(menu.omittedDefinitionItemIDs.contains(RadialTopLevelItemID.moveToSpace.rawValue))
        XCTAssertTrue(menu.omittedDefinitionItemIDs.contains(RadialTopLevelItemID.resize.rawValue))
    }

    func testCurrentAeroSpaceDerivedBindingsLeaveDefaultWheelChordUnused() {
        let configuration = HotKeyConfiguration()
        XCTAssertEqual(
            configuration.chord(for: .commandWheel),
            HotKeyChord(keyCode: 49, modifiers: UInt32(controlKey | optionKey))
        )
        XCTAssertNil(HotKeyManager.configurableShortcutConflict(
            action: .commandWheel,
            chord: configuration.chord(for: .commandWheel),
            configuration: configuration,
            workspaces: WorkspaceDefinition.defaults
        ))
    }

    func testEdgeClampingKeepsWholePanelInsideVisibleDisplay() {
        let frame = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let center = RadialMenuGeometry.clampedCenter(
            preferred: CGPoint(x: -1920, y: 1080),
            panelSize: CGSize(width: 620, height: 620),
            within: frame
        )
        XCTAssertEqual(center.x, frame.minX + 310 + 12, accuracy: 0.001)
        XCTAssertEqual(center.y, frame.maxY - 310 - 12, accuracy: 0.001)
    }

    func testFocusedWindowCenterConvertsAXCoordinatesAcrossExternalDisplays() {
        let frame = WindowFrame(
            position: CGPoint(x: -1_600, y: -340),
            size: CGSize(width: 800, height: 600)
        )
        let center = RadialMenuGeometry.appKitCenter(for: frame, mainScreenTop: 1_080)
        XCTAssertEqual(center.x, -1_200, accuracy: 0.001)
        XCTAssertEqual(center.y, 1_120, accuracy: 0.001)
    }

    func testRadialHitTestingHasNeutralDeadZoneAndDirectionalSegments() {
        let center = CGPoint(x: 190, y: 190)
        XCTAssertNil(RadialMenuGeometry.itemIndex(
            for: center,
            center: center,
            itemCount: 4,
            deadZoneRadius: 65,
            outerRadius: 172
        ))
        XCTAssertEqual(RadialMenuGeometry.itemIndex(
            for: CGPoint(x: 190, y: 50),
            center: center,
            itemCount: 4,
            deadZoneRadius: 65,
            outerRadius: 172
        ), 0)
        XCTAssertNil(RadialMenuGeometry.itemIndex(
            for: CGPoint(x: 190, y: 0),
            center: center,
            itemCount: 4,
            deadZoneRadius: 65,
            outerRadius: 172
        ))
    }

    func testTwoRingGeometryUsesStableCenterHysteresisAndFullCircleChildren() {
        let center = CGPoint(x: 310, y: 310)
        var state = RadialMenuGeometry.PointerState()
        XCTAssertNil(state.update(
            point: center,
            center: center,
            innerItemCount: 6,
            outerItemCount: 4,
            activeGroupIndex: nil
        ))
        XCTAssertEqual(state.update(
            point: CGPoint(
                x: 310,
                y: 310 - (RadialMenuGeometry.centerDeadZone + RadialMenuGeometry.innerOuterRadius) / 2
            ),
            center: center,
            innerItemCount: 6,
            outerItemCount: 4,
            activeGroupIndex: nil
        ), .init(ring: .inner, index: 0))
        XCTAssertEqual(state.update(
            point: CGPoint(
                x: 310,
                y: 310 - RadialMenuGeometry.innerOuterRadius - RadialMenuGeometry.ringHysteresis + 1
            ),
            center: center,
            innerItemCount: 6,
            outerItemCount: 4,
            activeGroupIndex: 0
        )?.ring, .inner, "The ring boundary keeps the prior inner selection inside hysteresis")
        XCTAssertEqual(state.update(
            point: CGPoint(
                x: 310,
                y: 310 - (RadialMenuGeometry.outerInnerRadius + RadialMenuGeometry.outerRadius) / 2
            ),
            center: center,
            innerItemCount: 6,
            outerItemCount: 4,
            activeGroupIndex: 0
        ), .init(ring: .outer, index: 0))
        for count in 1...12 {
            let angles = RadialMenuGeometry.outerItemAngles(
                parentIndex: 4,
                parentCount: 9,
                childCount: count
            )
            XCTAssertEqual(angles.count, count)
            if count > 1 {
                XCTAssertEqual(angles[1] - angles[0], .pi * 2 / CGFloat(count), accuracy: 0.000_001)
            }
        }
    }

    func testWheelDefinitionCodingStableOrderAndUnknownItemRepair() throws {
        let unknown = RadialTopLevelItemID(rawValue: "future-item")
        let definition = RadialWheelDefinition(items: [.layoutType, unknown, .nextSpace, .layoutType])
        let restored = try JSONDecoder().decode(RadialWheelDefinition.self, from: JSONEncoder().encode(definition))
        XCTAssertEqual(restored.items, definition.items)
        XCTAssertTrue(restored.hasUnresolvedReferences)
        XCTAssertEqual(restored.repaired().items, [.layoutType, .nextSpace])
    }

    func testEmptyDefinitionUsesSafeFallback() {
        let empty = RadialWheelDefinition(items: [])
        let menu = RadialCommandContextBuilder.build(from: context(window: nil), definition: empty)

        XCTAssertTrue(menu.usedFallbackDefinition)
        XCTAssertTrue(menu.items.contains { $0.id == RadialTopLevelItemID.layoutType.rawValue })
    }

    func testDefinitionEditorAddRemoveAndReorderingArePure() {
        var definition = RadialWheelDefinition(items: [])
        XCTAssertTrue(definition.add(.layoutType))
        XCTAssertTrue(definition.add(.goToSpace))
        XCTAssertFalse(definition.add(.layoutType))
        XCTAssertTrue(definition.moveItem(id: .goToSpace, offset: -1))
        XCTAssertEqual(definition.items, [.goToSpace, .layoutType])
        XCTAssertTrue(definition.removeItem(id: .layoutType))
        XCTAssertEqual(definition.items, [.goToSpace])
    }

    func testLegacyOneLevelDefaultMigratesOnceToNineProviderItems() throws {
        let json = #"{"version":1,"items":[{"id":"group.workspace","kind":"group","label":"Workspace","icon":"square.grid.2x2","children":["workspace.previous","workspace.next"]},{"id":"group.layout","kind":"group","label":"Layout","icon":"rectangle.3.group","children":["layout.freeform","layout.tiled"]},{"id":"group.resize","kind":"group","label":"Resize","icon":"arrow.up.left.and.arrow.down.right","children":["resize.smaller"]},{"id":"group.move-window","kind":"group","label":"Move","icon":"arrowshape.turn.up.right","children":["window.move"]}]}"#
        let migrated = try JSONDecoder().decode(RadialWheelDefinition.self, from: Data(json.utf8))
        XCTAssertEqual(migrated.version, RadialWheelDefinition.currentVersion)
        XCTAssertEqual(migrated.items, RadialTopLevelItemID.allKnown)
        XCTAssertFalse(migrated.hasUnresolvedReferences)
    }

    @MainActor
    func testSettingsStorePersistsLegacyWheelMigrationAsVersionTwoImmediately() throws {
        let defaults = isolatedDefaults()
        defaults.set(false, forKey: "iCloudSyncEnabled")
        let legacy = #"{"version":1,"items":[{"id":"group.workspace","kind":"group","label":"Workspace","icon":"square.grid.2x2","children":["workspace.previous","workspace.next"]},{"id":"group.layout","kind":"group","label":"Layout","icon":"rectangle.3.group","children":["layout.freeform","layout.tiled"]},{"id":"group.resize","kind":"group","label":"Resize","icon":"arrow.up.left.and.arrow.down.right","children":["resize.smaller"]},{"id":"group.move-window","kind":"group","label":"Move","icon":"arrowshape.turn.up.right","children":["window.move"]}]}"#
        defaults.set(Data(legacy.utf8), forKey: "radialWheelDefinition.v1")

        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] }
        )
        XCTAssertEqual(store.radialWheelDefinition, .builtInDefault)
        let saved = try XCTUnwrap(defaults.data(forKey: "radialWheelDefinition.v1"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        XCTAssertEqual(object["version"] as? Int, RadialWheelDefinition.currentVersion)
        XCTAssertEqual((object["items"] as? [String])?.count, RadialTopLevelItemID.allKnown.count)
    }

    @MainActor
    func testPresentationKeyboardTraversesInnerAndOuterWithoutThirdLevel() {
        let menu = RadialCommandContextBuilder.build(from: context(
            window: window(.managed),
            availableFocusDirections: [.left, .right]
        ))
        let presentation = RadialMenuPresentationModel(menu: menu)
        presentation.moveSelection(1)
        XCTAssertEqual(presentation.selectedInnerIndex, 0)
        presentation.enterSelectedGroup()
        XCTAssertEqual(presentation.activeGroupIndex, 0)
        XCTAssertEqual(presentation.selectedOuterIndex, 0)
        presentation.moveSelection(1)
        XCTAssertEqual(presentation.selectedOuterIndex, 1)
        presentation.returnInward()
        XCTAssertEqual(presentation.selectedInnerIndex, 0)
        XCTAssertNil(presentation.activeGroupIndex)
    }

    func testPureInteractionStateIgnoresStaleDwellAndTraversesOnlyTwoRings() {
        var state = RadialMenuInteractionState()
        let childCounts = [3, 0, 2]

        XCTAssertEqual(
            state.selectPointer(.init(ring: .inner, index: 0), childCounts: childCounts),
            [.scheduleGroupDwell(0)]
        )
        XCTAssertEqual(state.selectedInnerIndex, 0)
        XCTAssertNil(state.activeGroupIndex)

        _ = state.selectPointer(.init(ring: .inner, index: 1), childCounts: childCounts)
        _ = state.dwellElapsed(for: 0, childCounts: childCounts)
        XCTAssertNil(state.activeGroupIndex, "A stale dwell cannot reopen a group after selection changed")

        _ = state.selectPointer(.init(ring: .inner, index: 2), childCounts: childCounts)
        _ = state.dwellElapsed(for: 2, childCounts: childCounts)
        XCTAssertEqual(state.activeGroupIndex, 2)
        _ = state.selectPointer(.init(ring: .outer, index: 1), childCounts: childCounts)
        XCTAssertEqual(state.selectedOuterIndex, 1)
        _ = state.returnInward()
        XCTAssertEqual(state.selectedInnerIndex, 2)
        XCTAssertNil(state.activeGroupIndex)
        XCTAssertNil(state.selectedOuterIndex)
    }

    @MainActor
    func testDirectPlusSubmenuClickCommitsPrimaryWhileSubmenuOnlyClickOpensChildren() {
        let menu = RadialCommandContextBuilder.build(from: context(window: window(.managed)))
        let presentation = RadialMenuPresentationModel(menu: menu)
        var commits: [WindowManagerCommand] = []
        var disclosures: [(String, String)] = []
        presentation.commitItem = { item, alternate in
            commits.append(alternate ? (item.alternateCommand ?? item.command!) : item.command!)
        }
        presentation.groupDisclosed = { disclosures.append(($0.definitionID, $1)) }

        let layout = try! XCTUnwrap(menu.items.first { $0.id == RadialTopLevelItemID.layoutType.rawValue })
        presentation.activate(layout)
        XCTAssertEqual(commits, [.cycleLayout(1)])

        let move = try! XCTUnwrap(menu.items.first { $0.id == RadialTopLevelItemID.moveToSpace.rawValue })
        presentation.activate(move)
        XCTAssertEqual(commits, [.cycleLayout(1)])
        XCTAssertEqual(presentation.activeGroupIndex, menu.items.firstIndex { $0.id == move.id })
        XCTAssertEqual(presentation.selectedOuterIndex, 0)
        XCTAssertEqual(disclosures.map(\.0), [RadialTopLevelItemID.moveToSpace.rawValue])
        XCTAssertEqual(disclosures.map(\.1), ["click"])
    }

    @MainActor
    func testHoldModeDeliberateOutwardMotionDisclosesGroupWithoutWaitingForDwell() {
        let menu = RadialCommandContextBuilder.build(
            from: context(window: window(.managed)),
            definition: RadialWheelDefinition(items: [.moveToSpace, .nextSpace])
        )
        let presentation = RadialMenuPresentationModel(menu: menu, activationStyle: .holdToShow)
        let center = CGPoint(x: 310, y: 310)

        presentation.pointerMoved(
            to: CGPoint(x: 310, y: 310 - RadialMenuGeometry.innerItemRadius),
            center: center
        )
        XCTAssertEqual(presentation.selectedInnerIndex, 0)
        XCTAssertNil(presentation.activeGroupIndex)
        presentation.pointerMoved(
            to: CGPoint(x: 310, y: 310 - RadialMenuGeometry.outerItemRadius),
            center: center
        )
        XCTAssertEqual(presentation.activeGroupIndex, 0)
        XCTAssertEqual(presentation.selectedOuterIndex, 0)
    }

    func testGoToSpaceOmitsCurrentNoOpAndMarksItOnTheParent() {
        let go = try! XCTUnwrap(RadialCommandContextBuilder.build(from: context(window: nil)).items.first {
            $0.id == RadialTopLevelItemID.goToSpace.rawValue
        })
        XCTAssertEqual(go.label, "Go to Space · Code active")
        XCTAssertFalse(go.children.contains { $0.command == .switchWorkspace(workspaceA.id) })
        XCTAssertTrue(go.children.allSatisfy { $0.command != nil })
    }

    func testProfileStateInvalidatesWheelSessionWithoutChangingEnginePlacementToken() {
        var original = context(window: window(.managed))
        original.externalValidationToken = "active=one|pinned=none"
        var changed = original
        changed.externalValidationToken = "active=two|pinned=two"

        XCTAssertEqual(original.validationToken, changed.validationToken)
        XCTAssertNotEqual(original.sessionValidationToken, changed.sessionValidationToken)
        let place = RadialCommandContextBuilder.build(from: original).items
            .first { $0.id == RadialTopLevelItemID.resize.rawValue }?.children.first
        guard case let .placeTiledWindow(_, validationToken)? = place?.command else {
            return XCTFail("Expected a tiled placement command")
        }
        XCTAssertEqual(validationToken, original.validationToken)
        XCTAssertEqual(
            RadialCommandContextBuilder.build(from: original).validationToken,
            original.sessionValidationToken
        )
    }

    func testPressAndHoldTriggerSemanticsAndStaleGeneration() {
        var press = RadialMenuTriggerStateMachine()
        XCTAssertEqual(press.handle(.pressed, style: .pressToToggle, holdDelay: 0.2), [.toggle])
        XCTAssertEqual(press.handle(.released, style: .pressToToggle, holdDelay: 0.2), [])

        var hold = RadialMenuTriggerStateMachine()
        let start = hold.handle(.pressed, style: .holdToShow, holdDelay: 0.01)
        XCTAssertEqual(start, [
            .captureContext(generation: 1),
            .scheduleThreshold(generation: 1, delay: RadialMenuHoldDelay.permittedRange.lowerBound),
        ])
        XCTAssertEqual(hold.contextCaptured(generation: 1, hasRelevantActions: true), [])
        XCTAssertEqual(hold.thresholdElapsed(generation: 1), [.presentCaptured(generation: 1)])
        XCTAssertEqual(hold.thresholdElapsed(generation: 0), [])
        XCTAssertEqual(
            hold.handle(.released, style: .holdToShow, holdDelay: 0.2),
            [.commitHighlightedOrDismiss(generation: 1)]
        )

        var early = RadialMenuTriggerStateMachine()
        _ = early.handle(.pressed, style: .holdToShow, holdDelay: 0.2)
        XCTAssertEqual(
            early.handle(.released, style: .holdToShow, holdDelay: 0.2),
            [.cancelThreshold(reason: "released-before-presentation")]
        )
    }

    func testGlobeFnQuickTapPassesThroughWithoutOpeningOrSuppressingNativeAction() {
        var state = GlobeFnGestureStateMachine()
        XCTAssertEqual(
            state.handle(
                .functionChanged(isDown: true, otherModifiersDown: false),
                holdDelay: 0.2
            ),
            [.scheduleThreshold(generation: 1, delay: 0.2)]
        )
        XCTAssertEqual(
            state.handle(
                .functionChanged(isDown: false, otherModifiersDown: false),
                holdDelay: 0.2
            ),
            [.cancelThreshold(reason: "quick-tap")]
        )
        XCTAssertEqual(
            state.handle(.nativeGlobeKey(isDown: true), holdDelay: 0.2),
            []
        )
        XCTAssertEqual(
            state.handle(.nativeGlobeKey(isDown: false), holdDelay: 0.2),
            []
        )
        XCTAssertEqual(state.phaseName, "idle")
    }

    func testGlobeFnThresholdOrderingAndReleaseCommitAreDeterministic() {
        var below = GlobeFnGestureStateMachine()
        _ = below.handle(
            .functionChanged(isDown: true, otherModifiersDown: false),
            holdDelay: 0.2
        )
        XCTAssertEqual(
            below.handle(
                .functionChanged(isDown: false, otherModifiersDown: false),
                holdDelay: 0.2
            ),
            [.cancelThreshold(reason: "quick-tap")]
        )
        XCTAssertEqual(below.handle(.thresholdElapsed(generation: 1), holdDelay: 0.2), [])

        var exact = GlobeFnGestureStateMachine()
        _ = exact.handle(
            .functionChanged(isDown: true, otherModifiersDown: false),
            holdDelay: 0.2
        )
        XCTAssertEqual(
            exact.handle(.thresholdElapsed(generation: 1), holdDelay: 0.2),
            [.activateHold(generation: 1)]
        )
        XCTAssertEqual(
            exact.handle(
                .functionChanged(isDown: false, otherModifiersDown: false),
                holdDelay: 0.2
            ),
            [
                .releaseHold(generation: 1),
                .scheduleSuppressionExpiry(
                    generation: 1,
                    delay: GlobeFnGestureStateMachine.nativeSuppressionWindow
                ),
            ]
        )
        XCTAssertEqual(
            exact.handle(.nativeGlobeKey(isDown: true), holdDelay: 0.2),
            [.suppressCurrentEvent]
        )
        XCTAssertEqual(
            exact.handle(.nativeGlobeKey(isDown: false), holdDelay: 0.2),
            [.suppressCurrentEvent]
        )
        XCTAssertEqual(exact.phaseName, "idle")
    }

    func testGlobeFnChordAndModifierOrderingNeverActivateTheWheel() {
        for input in [
            GlobeFnCompetingInput.key,
            .escape,
            .mouseButton,
            .systemDefined,
            .modifier,
        ] {
            var state = GlobeFnGestureStateMachine()
            _ = state.handle(
                .functionChanged(isDown: true, otherModifiersDown: false),
                holdDelay: 0.2
            )
            XCTAssertEqual(
                state.handle(.competingInput(input), holdDelay: 0.2),
                [.cancelThreshold(reason: "competing-\(input.rawValue)")]
            )
            XCTAssertEqual(state.handle(.thresholdElapsed(generation: 1), holdDelay: 0.2), [])
            XCTAssertEqual(
                state.handle(
                    .functionChanged(isDown: false, otherModifiersDown: false),
                    holdDelay: 0.2
                ),
                []
            )
        }

        var modifierFirst = GlobeFnGestureStateMachine()
        XCTAssertEqual(
            modifierFirst.handle(
                .functionChanged(isDown: true, otherModifiersDown: true),
                holdDelay: 0.2
            ),
            []
        )
        XCTAssertEqual(
            modifierFirst.handle(.thresholdElapsed(generation: 1), holdDelay: 0.2),
            []
        )
    }

    func testGlobeFnCompetingInputAfterActivationCancelsWithoutCommit() {
        var state = GlobeFnGestureStateMachine()
        _ = state.handle(
            .functionChanged(isDown: true, otherModifiersDown: false),
            holdDelay: 0.2
        )
        _ = state.handle(.thresholdElapsed(generation: 1), holdDelay: 0.2)
        XCTAssertEqual(
            state.handle(.competingInput(.key), holdDelay: 0.2),
            [
                .cancelThreshold(reason: "competing-key"),
                .cancelHold(reason: "competing-key"),
            ]
        )
        XCTAssertEqual(
            state.handle(
                .functionChanged(isDown: false, otherModifiersDown: false),
                holdDelay: 0.2
            ),
            []
        )
        XCTAssertEqual(state.handle(.nativeGlobeKey(isDown: true), holdDelay: 0.2), [])
    }

    func testGlobeFnNormalizerIgnoresDuplicateFlagsAndRecognizesEveryChordClass() {
        var normalizer = GlobeFnEventNormalizer()
        XCTAssertEqual(
            normalizer.normalize(.flagsChanged(functionDown: true, otherModifiersDown: false)),
            .functionChanged(isDown: true, otherModifiersDown: false)
        )
        XCTAssertNil(
            normalizer.normalize(.flagsChanged(functionDown: true, otherModifiersDown: false))
        )
        XCTAssertEqual(
            normalizer.normalize(.flagsChanged(functionDown: true, otherModifiersDown: true)),
            .competingInput(.modifier)
        )
        XCTAssertEqual(
            normalizer.normalize(.keyChanged(isDown: true, keyCode: 123, isRepeat: false)),
            .competingInput(.key)
        )
        XCTAssertEqual(
            normalizer.normalize(.keyChanged(isDown: true, keyCode: 53, isRepeat: false)),
            .competingInput(.escape)
        )
        XCTAssertEqual(normalizer.normalize(.mouseButtonDown), .competingInput(.mouseButton))
        XCTAssertEqual(normalizer.normalize(.systemDefined), .competingInput(.systemDefined))
        XCTAssertEqual(
            normalizer.normalize(.keyChanged(
                isDown: true,
                keyCode: GlobeFnEventNormalizer.nativeGlobeActionKeyCode,
                isRepeat: false
            )),
            .nativeGlobeKey(isDown: true)
        )
    }

    func testGlobeFnLifecycleCancellationAndRapidGesturesCannotCommitStaleGeneration() {
        var state = GlobeFnGestureStateMachine()
        _ = state.handle(
            .functionChanged(isDown: true, otherModifiersDown: false),
            holdDelay: 0.2
        )
        XCTAssertEqual(
            state.handle(.cancel(reason: "system-will-sleep"), holdDelay: 0.2),
            [.cancelThreshold(reason: "system-will-sleep")]
        )
        XCTAssertEqual(state.handle(.thresholdElapsed(generation: 1), holdDelay: 0.2), [])

        _ = state.handle(
            .functionChanged(isDown: true, otherModifiersDown: false),
            holdDelay: 0.2
        )
        XCTAssertEqual(state.latestGeneration, 2)
        XCTAssertEqual(state.handle(.thresholdElapsed(generation: 1), holdDelay: 0.2), [])
        XCTAssertEqual(
            state.handle(.thresholdElapsed(generation: 2), holdDelay: 0.2),
            [.activateHold(generation: 2)]
        )
        XCTAssertEqual(
            state.handle(.cancel(reason: "profile-transition"), holdDelay: 0.2),
            [
                .cancelThreshold(reason: "profile-transition"),
                .cancelHold(reason: "profile-transition"),
            ]
        )
    }

    @MainActor
    func testGlobeFnRuntimeUsesInjectedSchedulerAndExistingHoldPipeline() {
        let radial = TestGlobeFnRadialTrigger()
        let scheduler = TestGlobeFnScheduler()
        let monitor = TestGlobeFnEventMonitor()
        let controller = GlobeFnHoldActivationController(
            radialTrigger: radial,
            scheduler: scheduler,
            monitorFactory: { eventHandler, interruptionHandler in
                monitor.eventHandler = eventHandler
                monitor.interruptionHandler = interruptionHandler
                return monitor
            }
        )

        controller.update(enabled: true, holdDelay: 0.2)
        XCTAssertEqual(monitor.startCount, 1)
        XCTAssertFalse(monitor.send(.flagsChanged(functionDown: true, otherModifiersDown: false)))
        XCTAssertEqual(scheduler.pendingCount, 2)
        scheduler.runNext()
        XCTAssertEqual(radial.beginRecognizedHoldCount, 1)

        XCTAssertFalse(monitor.send(.flagsChanged(functionDown: false, otherModifiersDown: false)))
        XCTAssertEqual(radial.events, [.released])
        XCTAssertTrue(monitor.send(.keyChanged(
            isDown: true,
            keyCode: GlobeFnEventNormalizer.nativeGlobeActionKeyCode,
            isRepeat: false
        )))
        XCTAssertTrue(monitor.send(.keyChanged(
            isDown: false,
            keyCode: GlobeFnEventNormalizer.nativeGlobeActionKeyCode,
            isRepeat: false
        )))
        XCTAssertEqual(radial.cancelReasons, [])
    }

    @MainActor
    func testPublishedGlobeFnEnableUsesEmittedWillSetValue() {
        final class Probe: ObservableObject {
            @Published var globeFnEnabled = false
        }

        let probe = Probe()
        let radial = TestGlobeFnRadialTrigger()
        let monitor = TestGlobeFnEventMonitor()
        let controller = GlobeFnHoldActivationController(
            radialTrigger: radial,
            scheduler: TestGlobeFnScheduler(),
            monitorFactory: { eventHandler, interruptionHandler in
                monitor.eventHandler = eventHandler
                monitor.interruptionHandler = interruptionHandler
                return monitor
            }
        )
        var resolved: [GlobeFnRuntimeSettings] = []
        var cancellable: AnyCancellable? = probe.$globeFnEnabled
            .dropFirst()
            .sink { emittedValue in
                // During this callback @Published's source property still contains its old value.
                XCTAssertFalse(probe.globeFnEnabled)
                let settings = GlobeFnRuntimeSettings(
                    radialMenuEnabled: true,
                    globeFnEnabled: emittedValue,
                    isShortcutRecording: false,
                    holdDelay: 0.2
                )
                resolved.append(settings)
                controller.update(enabled: settings.isEnabled, holdDelay: settings.holdDelay)
            }

        probe.globeFnEnabled = true

        XCTAssertEqual(resolved, [GlobeFnRuntimeSettings(
            radialMenuEnabled: true,
            globeFnEnabled: true,
            isShortcutRecording: false,
            holdDelay: 0.2
        )])
        XCTAssertEqual(monitor.startCount, 1, "The live enable transition must install the monitor")
        withExtendedLifetime(cancellable) {}
        cancellable = nil
    }

    @MainActor
    func testGlobeFnRuntimeQuickTapChordAndOrdinaryShortcutNeverOpen() {
        let radial = TestGlobeFnRadialTrigger()
        let scheduler = TestGlobeFnScheduler()
        let monitor = TestGlobeFnEventMonitor()
        let controller = GlobeFnHoldActivationController(
            radialTrigger: radial,
            scheduler: scheduler,
            monitorFactory: { eventHandler, interruptionHandler in
                monitor.eventHandler = eventHandler
                monitor.interruptionHandler = interruptionHandler
                return monitor
            }
        )
        controller.update(enabled: true, holdDelay: 0.2)

        _ = monitor.send(.flagsChanged(functionDown: true, otherModifiersDown: false))
        _ = monitor.send(.flagsChanged(functionDown: false, otherModifiersDown: false))
        scheduler.runAll()
        XCTAssertEqual(radial.beginRecognizedHoldCount, 0)
        XCTAssertFalse(monitor.send(.keyChanged(
            isDown: true,
            keyCode: GlobeFnEventNormalizer.nativeGlobeActionKeyCode,
            isRepeat: false
        )))

        _ = monitor.send(.flagsChanged(functionDown: true, otherModifiersDown: false))
        _ = monitor.send(.keyChanged(isDown: true, keyCode: 123, isRepeat: false))
        scheduler.runAll()
        XCTAssertEqual(radial.beginRecognizedHoldCount, 0)
        _ = monitor.send(.flagsChanged(functionDown: false, otherModifiersDown: false))

        _ = monitor.send(.flagsChanged(functionDown: true, otherModifiersDown: false))
        controller.ordinaryShortcutWillBegin()
        scheduler.runAll()
        XCTAssertEqual(radial.beginRecognizedHoldCount, 0)
    }

    @MainActor
    func testGlobeFnRuntimeCancellationMonitorRetryAndDisabledSettingAreSafe() {
        let radial = TestGlobeFnRadialTrigger()
        let scheduler = TestGlobeFnScheduler()
        let firstMonitor = TestGlobeFnEventMonitor(startResults: [false])
        let secondMonitor = TestGlobeFnEventMonitor(startResults: [true])
        var monitors = [firstMonitor, secondMonitor]
        let controller = GlobeFnHoldActivationController(
            radialTrigger: radial,
            scheduler: scheduler,
            monitorFactory: { eventHandler, interruptionHandler in
                let monitor = monitors.removeFirst()
                monitor.eventHandler = eventHandler
                monitor.interruptionHandler = interruptionHandler
                return monitor
            }
        )
        var issues: [String?] = []
        controller.runtimeIssueChanged = { issues.append($0) }

        controller.update(enabled: true, holdDelay: 0.2)
        XCTAssertNotNil(issues.last!)
        controller.retryMonitor(reason: "wake")
        XCTAssertNil(issues.last!)

        _ = secondMonitor.send(.flagsChanged(functionDown: true, otherModifiersDown: false))
        scheduler.runNext()
        XCTAssertEqual(radial.beginRecognizedHoldCount, 1)
        controller.cancel(reason: "system-will-sleep")
        XCTAssertEqual(radial.cancelReasons.last, "globe-fn-system-will-sleep")

        secondMonitor.reenableResult = true
        secondMonitor.interrupt(.timedOut)
        XCTAssertEqual(secondMonitor.reenableCount, 1)
        XCTAssertNil(issues.last!)

        secondMonitor.reenableResult = false
        secondMonitor.interrupt(.disabledByUserInput)
        XCTAssertEqual(secondMonitor.reenableCount, 2)
        XCTAssertNotNil(issues.last!)

        controller.update(enabled: false, holdDelay: 0.2)
        XCTAssertGreaterThanOrEqual(secondMonitor.stopCount, 1)
        XCTAssertFalse(controller.receive(.flagsChanged(
            functionDown: true,
            otherModifiersDown: false
        )))
    }

    @MainActor
    func testGlobeFnRuntimeSafetyTimeoutCancelsMissingKeyboardRelease() {
        let radial = TestGlobeFnRadialTrigger()
        let scheduler = TestGlobeFnScheduler()
        let monitor = TestGlobeFnEventMonitor()
        let controller = GlobeFnHoldActivationController(
            radialTrigger: radial,
            scheduler: scheduler,
            monitorFactory: { handler, interruption in
                monitor.eventHandler = handler
                monitor.interruptionHandler = interruption
                return monitor
            }
        )

        controller.update(enabled: true, holdDelay: 0.2)
        _ = monitor.send(.flagsChanged(functionDown: true, otherModifiersDown: false))
        XCTAssertEqual(scheduler.pendingDelays, [0.2, 10])

        scheduler.runNext()
        XCTAssertEqual(radial.beginRecognizedHoldCount, 1)
        scheduler.runNext()

        XCTAssertEqual(radial.cancelReasons, ["globe-fn-gesture-safety-timeout"])
        XCTAssertFalse(
            monitor.send(.flagsChanged(functionDown: false, otherModifiersDown: false))
        )
        XCTAssertFalse(radial.events.contains(.released))
    }

    @MainActor
    func testGlobeFnDiagnosticsRecordOnlyDeduplicatedSafeStateReasons() {
        let radial = TestGlobeFnRadialTrigger()
        let scheduler = TestGlobeFnScheduler()
        let monitor = TestGlobeFnEventMonitor()
        let sink = MemoryDiagnosticSink()
        let controller = GlobeFnHoldActivationController(
            radialTrigger: radial,
            scheduler: scheduler,
            diagnostics: DiagnosticLogger(
                buildMode: .debug,
                sink: sink,
                sessionIdentifier: "fn-test"
            ),
            monitorFactory: { handler, interruption in
                monitor.eventHandler = handler
                monitor.interruptionHandler = interruption
                return monitor
            }
        )

        controller.cancel(reason: "idle-refresh")
        XCTAssertTrue(sink.text.isEmpty)
        controller.update(enabled: true, holdDelay: 0.2)
        _ = monitor.send(.flagsChanged(functionDown: true, otherModifiersDown: false))
        _ = monitor.send(.keyChanged(isDown: true, keyCode: 123, isRepeat: false))

        XCTAssertTrue(sink.text.contains("globe-fn-trigger"))
        XCTAssertTrue(sink.text.contains("configuration-updated"))
        XCTAssertTrue(sink.text.contains("monitor-installed"))
        XCTAssertTrue(sink.text.contains("monitor-awaiting-fn-transition"))
        XCTAssertTrue(sink.text.contains("fn-transition-observed"))
        XCTAssertTrue(sink.text.contains("hold-not-accepted"))
        XCTAssertTrue(sink.text.contains("competing-key"))
        XCTAssertFalse(sink.text.localizedCaseInsensitiveContains("keycode"))
        XCTAssertFalse(sink.text.localizedCaseInsensitiveContains("key-code"))
        XCTAssertFalse(sink.text.localizedCaseInsensitiveContains("window-title"))
    }

    func testCarbonPressReleaseRoutingDoesNotRunOrdinaryCommandsTwice() {
        XCTAssertTrue(HotKeyManager.shouldDispatchCommand(forEventKind: UInt32(kEventHotKeyPressed)))
        XCTAssertFalse(HotKeyManager.shouldDispatchCommand(forEventKind: UInt32(kEventHotKeyReleased)))
        XCTAssertEqual(
            HotKeyManager.radialTriggerInput(forEventKind: UInt32(kEventHotKeyPressed)),
            .pressed
        )
        XCTAssertEqual(
            HotKeyManager.radialTriggerInput(forEventKind: UInt32(kEventHotKeyReleased)),
            .released
        )
        XCTAssertNil(HotKeyManager.radialTriggerInput(forEventKind: 999))
    }

    func testSessionCommitsAtMostOnceAndCancelNeverCommits() {
        var committed = RadialMenuSessionState()
        XCTAssertTrue(committed.commit())
        XCTAssertFalse(committed.commit())
        XCTAssertTrue(committed.hasCommitted)

        var cancelled = RadialMenuSessionState()
        cancelled.dismiss()
        XCTAssertFalse(cancelled.commit())
        XCTAssertFalse(cancelled.hasCommitted)
    }

    func testSharedDispatcherRejectsSameCorrelationReentrancy() {
        var results: [WindowManagerCommandDispatchResult] = []
        var dispatcher: WindowManagerCommandDispatcher!
        dispatcher = WindowManagerCommandDispatcher { _, correlation in
            results.append(dispatcher.dispatch(
                .cycleWorkspace(1),
                source: .radialMenu,
                correlationID: correlation
            ))
        }

        let outer = dispatcher.dispatch(
            .cycleWorkspace(1),
            source: .hotkey,
            correlationID: "same-action"
        )
        XCTAssertEqual(outer, .dispatched)
        XCTAssertEqual(results, [.rejectedReentrant])
    }

    @MainActor
    func testSettingsSelectionRestoresAndFallsBackWhenDebugPaneDisappears() {
        let suite = "WindowRangerTests.SettingsNavigation.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let debug = SettingsNavigationModel(defaults: defaults, includeDebug: true)
        debug.select(.diagnostics)
        XCTAssertEqual(debug.selectedCategory, .diagnostics)

        let release = SettingsNavigationModel(defaults: defaults, includeDebug: false)
        XCTAssertEqual(release.selectedCategory, .general)
        XCTAssertFalse(release.availableCategories.contains(.diagnostics))
    }

    @MainActor
    func testSettingsFirstOpenWaitsForSceneThenSurfacesOnRequestedDisplay() {
        let displays = settingsDisplays()
        var activationCount = 0
        var openCount = 0
        let coordinator = SettingsWindowCoordinator(
            displayProvider: { displays },
            applicationActivator: { activationCount += 1 }
        )
        let surface = TestSettingsWindowSurface(
            frame: CGRect(x: 100, y: 100, width: 600, height: 480)
        )
        let context = SettingsSurfaceContext(
            workspaceID: workspaceB.id,
            displayIdentifier: "external",
            displayMode: .independent,
            resolutionReason: "test"
        )

        let result = coordinator.requestOpen(context: context) {
            openCount += 1
            return true
        }
        XCTAssertEqual(result, .sceneRequested)
        XCTAssertEqual(openCount, 1)
        XCTAssertTrue(surface.surfacedFrames.isEmpty)

        coordinator.attach(surface: surface)

        XCTAssertEqual(activationCount, 1)
        XCTAssertEqual(surface.constraintCount, 2)
        XCTAssertEqual(surface.prepareCount, 1)
        XCTAssertEqual(surface.surfacedFrames.count, 1)
        XCTAssertEqual(surface.surfacedFrames[0].size, SettingsWindowMetrics.minimumSize)
        XCTAssertEqual(coordinator.assignedContext, context)
        XCTAssertTrue(displays[1].visibleFrame.contains(surface.surfacedFrames[0].midpoint))
    }

    @MainActor
    func testSettingsAppKitHostUsesStableExplicitResizeConstraints() {
        let hostingView = NSHostingView(
            rootView: Text("Tall Settings content")
                .frame(minWidth: 1_800, minHeight: 1_200)
        )
        hostingView.sizingOptions = [.minSize, .maxSize, .intrinsicContentSize]
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 900, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        let coordinator = SettingsWindowCoordinator(
            diagnostics: .disabled,
            displayProvider: { [] },
            applicationActivator: {}
        )

        coordinator.attach(window: window)

        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertEqual(window.contentMinSize, SettingsWindowMetrics.minimumSize)
        XCTAssertEqual(hostingView.sizingOptions, [.intrinsicContentSize])
        XCTAssertGreaterThan(window.contentMaxSize.width, 10_000)
        XCTAssertGreaterThan(window.contentMaxSize.height, 10_000)
        XCTAssertGreaterThanOrEqual(window.contentLayoutRect.width, SettingsWindowMetrics.minimumSize.width)
        XCTAssertGreaterThanOrEqual(window.contentLayoutRect.height, SettingsWindowMetrics.minimumSize.height)
        window.close()
    }

    func testSettingsBuildIdentityMakesVersionBuildAndSourceVisible() {
        let identity = SettingsBuildIdentity(
            version: "0.1.0",
            build: "7",
            commit: "abc123def456-dirty",
            isDebugBuild: true
        )

        XCTAssertEqual(identity.versionText, "Version 0.1.0 (7)")
        XCTAssertEqual(identity.sourceText, "Dev · abc123def456-dirty")
        XCTAssertEqual(
            identity.accessibilityText,
            "Version 0.1.0 (7), Dev, abc123def456-dirty"
        )
    }

    @MainActor
    func testSettingsReopenReassignsExistingWindowToNewWorkspaceAndDisplay() {
        let displays = settingsDisplays()
        var activationCount = 0
        let coordinator = SettingsWindowCoordinator(
            displayProvider: { displays },
            applicationActivator: { activationCount += 1 }
        )
        let surface = TestSettingsWindowSurface(
            frame: CGRect(x: 100, y: 100, width: 900, height: 640)
        )
        coordinator.attach(surface: surface)
        XCTAssertEqual(coordinator.requestOpen(
            context: SettingsSurfaceContext(
                workspaceID: workspaceA.id,
                displayIdentifier: "main",
                displayMode: .independent,
                resolutionReason: "first"
            ),
            openSettings: { XCTFail("An attached Settings scene must be resurfaced directly"); return false }
        ), .resurfacedExistingWindow)
        surface.frame = surface.surfacedFrames.last!

        let reopened = SettingsSurfaceContext(
            workspaceID: workspaceB.id,
            displayIdentifier: "external",
            displayMode: .independent,
            resolutionReason: "reopen"
        )
        XCTAssertEqual(coordinator.requestOpen(
            context: reopened,
            openSettings: { XCTFail("Reopen must not request a duplicate scene"); return false }
        ), .resurfacedExistingWindow)

        XCTAssertEqual(activationCount, 2)
        XCTAssertEqual(surface.surfacedFrames.count, 2)
        XCTAssertTrue(displays[1].visibleFrame.contains(surface.surfacedFrames[1].midpoint))
        XCTAssertEqual(coordinator.assignedContext, reopened)
    }

    @MainActor
    func testSettingsVirtualWorkspaceVisibilityDoesNotActivateOnReturn() {
        let displays = settingsDisplays()
        var activationCount = 0
        let coordinator = SettingsWindowCoordinator(
            displayProvider: { displays },
            applicationActivator: { activationCount += 1 }
        )
        let surface = TestSettingsWindowSurface(
            frame: CGRect(x: -1600, y: 100, width: 900, height: 640)
        )
        coordinator.attach(surface: surface)
        coordinator.requestOpen(
            context: SettingsSurfaceContext(
                workspaceID: workspaceB.id,
                displayIdentifier: "external",
                displayMode: .independent,
                resolutionReason: "test"
            ),
            openSettings: { true }
        )

        coordinator.workspaceStateDidChange(WorkspaceEngineState(
            currentWorkspaceID: workspaceA.id,
            activeWorkspaceIDs: [workspaceA.id],
            previousWorkspaceID: workspaceB.id,
            managedWindowCount: 0,
            accessibilityGranted: true,
            activeWorkspaceIDByDisplay: ["external": workspaceA.id]
        ))
        XCTAssertEqual(surface.hideCount, 1)
        XCTAssertTrue(coordinator.isHiddenForWorkspace)

        coordinator.workspaceStateDidChange(WorkspaceEngineState(
            currentWorkspaceID: workspaceB.id,
            activeWorkspaceIDs: [workspaceB.id],
            previousWorkspaceID: workspaceA.id,
            managedWindowCount: 0,
            accessibilityGranted: true,
            activeWorkspaceIDByDisplay: ["external": workspaceB.id]
        ))
        XCTAssertEqual(surface.nonactivatingSurfaceFrames.count, 1)
        XCTAssertEqual(activationCount, 1, "Returning to the workspace must not steal focus")
        XCTAssertFalse(coordinator.isHiddenForWorkspace)
    }

    @MainActor
    func testSettingsRapidFirstOpenCoalescesAndSurfacesLatestContextOnce() {
        let displays = settingsDisplays()
        var sceneRequestCount = 0
        let coordinator = SettingsWindowCoordinator(
            displayProvider: { displays },
            applicationActivator: {}
        )
        let first = SettingsSurfaceContext(
            workspaceID: workspaceA.id,
            displayIdentifier: "main",
            displayMode: .independent,
            resolutionReason: "first"
        )
        let latest = SettingsSurfaceContext(
            workspaceID: workspaceB.id,
            displayIdentifier: "external",
            displayMode: .independent,
            resolutionReason: "latest"
        )

        XCTAssertEqual(coordinator.requestOpen(context: first) {
            sceneRequestCount += 1
            return true
        }, .sceneRequested)
        XCTAssertEqual(coordinator.requestOpen(context: latest) {
            sceneRequestCount += 1
            return true
        }, .coalescedPendingScene)
        XCTAssertEqual(sceneRequestCount, 1)

        let surface = TestSettingsWindowSurface(
            frame: CGRect(x: 100, y: 100, width: 900, height: 640)
        )
        coordinator.attach(surface: surface)
        XCTAssertEqual(surface.surfacedFrames.count, 1)
        XCTAssertEqual(coordinator.assignedContext, latest)
        XCTAssertTrue(displays[1].visibleFrame.contains(surface.surfacedFrames[0].midpoint))
    }

    @MainActor
    func testSettingsUnavailableSceneActionClearsRequestAndCanRetry() {
        let displays = settingsDisplays()
        let coordinator = SettingsWindowCoordinator(
            displayProvider: { displays },
            applicationActivator: {}
        )
        let context = SettingsSurfaceContext(
            workspaceID: workspaceB.id,
            displayIdentifier: "external",
            displayMode: .independent,
            resolutionReason: "test"
        )

        XCTAssertEqual(
            coordinator.requestOpen(context: context, openSettings: { false }),
            .sceneActionUnavailable
        )
        let surface = TestSettingsWindowSurface(
            frame: CGRect(x: 100, y: 100, width: 900, height: 640)
        )
        coordinator.attach(surface: surface)
        XCTAssertTrue(surface.surfacedFrames.isEmpty)

        XCTAssertEqual(
            coordinator.requestOpen(context: context, openSettings: { true }),
            .resurfacedExistingWindow
        )
        XCTAssertEqual(surface.surfacedFrames.count, 1)
    }

    @MainActor
    func testSettingsLinkPreparationIsRaceSafeWhenSceneAttachesLater() {
        let displays = settingsDisplays()
        let coordinator = SettingsWindowCoordinator(
            displayProvider: { displays },
            applicationActivator: {}
        )
        let context = SettingsSurfaceContext(
            workspaceID: workspaceB.id,
            displayIdentifier: "external",
            displayMode: .independent,
            resolutionReason: "status-menu-settings-link"
        )

        XCTAssertEqual(coordinator.prepareOpen(context: context), .preparedForSettingsLink)
        let surface = TestSettingsWindowSurface(
            frame: CGRect(x: 100, y: 100, width: 900, height: 640)
        )
        coordinator.attach(surface: surface)

        XCTAssertEqual(coordinator.assignedContext, context)
        XCTAssertEqual(surface.surfacedFrames.count, 1)
        XCTAssertTrue(displays[1].visibleFrame.contains(surface.surfacedFrames[0].midpoint))
    }

    @MainActor
    func testSettingsCommandRequestRouterConsumesStatusContextExactlyOnce() {
        let router = SettingsCommandRequestRouter()
        let statusRequest = SettingsCommandRequest(
            category: .radialMenu,
            preferPointerDisplay: true
        )

        router.prepare(statusRequest)
        XCTAssertEqual(router.consume(), statusRequest)
        XCTAssertEqual(router.consume(), .applicationMenuDefault)

        router.prepare(statusRequest)
        router.cancelPendingRequest()
        XCTAssertEqual(router.consume(), .applicationMenuDefault)
    }

    @MainActor
    func testSettingsMenuCommandDispatcherPerformsNestedNativeCommandCommaItem() {
        let target = TestSettingsMenuCommandTarget()
        let root = NSMenu(title: "Application")
        root.autoenablesItems = false
        let applicationItem = NSMenuItem(title: "WindowRanger", action: nil, keyEquivalent: "")
        let applicationMenu = NSMenu(title: "WindowRanger")
        applicationMenu.autoenablesItems = false
        let decoy = NSMenuItem(title: "Decoy", action: nil, keyEquivalent: ",")
        decoy.keyEquivalentModifierMask = []
        applicationMenu.addItem(decoy)
        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(TestSettingsMenuCommandTarget.openSettings(_:)),
            keyEquivalent: ","
        )
        settings.keyEquivalentModifierMask = [.command]
        settings.target = target
        settings.isEnabled = true
        applicationMenu.addItem(settings)
        applicationItem.submenu = applicationMenu
        root.addItem(applicationItem)

        XCTAssertTrue(SettingsMenuCommandDispatcher.performSettingsCommand(in: root))
        XCTAssertEqual(target.invocationCount, 1)
        XCTAssertFalse(SettingsMenuCommandDispatcher.performSettingsCommand(in: nil))
    }

    func testSettingsPlacementCentersAcrossDisplaysAndClampsOnSameDisplay() {
        let displays = settingsDisplays()
        let crossing = SettingsWindowGeometry.placement(
            currentFrame: CGRect(x: 120, y: 120, width: 900, height: 640),
            requestedDisplayIdentifier: "external",
            displays: displays
        )
        XCTAssertEqual(crossing?.displayIdentifier, "external")
        XCTAssertEqual(crossing?.resolutionReason, "requested-display-centered")
        XCTAssertEqual(crossing?.frame.size, CGSize(width: 900, height: 640))
        XCTAssertTrue(displays[1].visibleFrame.contains(try! XCTUnwrap(crossing).frame.midpoint))

        let clamped = SettingsWindowGeometry.placement(
            currentFrame: CGRect(x: -2300, y: -300, width: 900, height: 640),
            requestedDisplayIdentifier: "external",
            displays: displays
        )
        let clampedFrame = try! XCTUnwrap(clamped).frame
        XCTAssertGreaterThanOrEqual(clampedFrame.minX, displays[1].visibleFrame.minX + 18)
        XCTAssertGreaterThanOrEqual(clampedFrame.minY, displays[1].visibleFrame.minY + 18)
    }

    func testSettingsPlacementPreservesLargerFramesAndFitsSmallDisplays() {
        XCTAssertEqual(
            SettingsWindowMetrics.constrainedFrameSize(
                currentSize: CGSize(width: 1400, height: 820),
                availableSize: CGSize(width: 1600, height: 900)
            ),
            CGSize(width: 1400, height: 820)
        )
        XCTAssertEqual(
            SettingsWindowMetrics.constrainedFrameSize(
                currentSize: CGSize(width: 800, height: 500),
                availableSize: CGSize(width: 1000, height: 620)
            ),
            CGSize(width: 800, height: 560)
        )
    }

    func testIndependentSettingsPointerRoutingUsesTargetDisplaysActiveWorkspace() {
        let resolved = WorkspaceEngine.settingsWorkspaceSelection(
            displayMode: .independent,
            destinationDisplayIdentifier: "external",
            focusedWorkspaceID: nil,
            currentWorkspaceID: workspaceA.id,
            activeWorkspaceIDByDisplay: ["main": workspaceA.id, "external": workspaceB.id]
        )
        XCTAssertEqual(resolved.workspaceID, workspaceB.id)
        XCTAssertEqual(resolved.reason, "independent-active-workspace-for-display")

        let unified = WorkspaceEngine.settingsWorkspaceSelection(
            displayMode: .unified,
            destinationDisplayIdentifier: "external",
            focusedWorkspaceID: nil,
            currentWorkspaceID: workspaceC.id,
            activeWorkspaceIDByDisplay: [:]
        )
        XCTAssertEqual(unified.workspaceID, workspaceC.id)
        XCTAssertEqual(unified.reason, "unified-current-workspace")
    }

    func testAppOwnedSettingsCannotEnterDiscoveryLayoutOrPersistenceLifecycle() {
        XCTAssertFalse(WorkspaceEngine.shouldDiscoverApplication(
            processIdentifier: 42,
            ownProcessIdentifier: 42,
            isRegularApplication: true,
            isTerminated: false
        ))
        XCTAssertFalse(WorkspaceEngine.shouldProcessApplicationActivation(
            processIdentifier: 42,
            ownProcessIdentifier: 42
        ))
        XCTAssertTrue(WorkspaceEngine.shouldDiscoverApplication(
            processIdentifier: 43,
            ownProcessIdentifier: 42,
            isRegularApplication: true,
            isTerminated: false
        ))
    }

    @MainActor
    func testSettingsSearchIndexesSynonymsAndRoutesToExactPane() {
        let model = SettingsNavigationModel(defaults: isolatedDefaults(), includeDebug: false)
        model.searchText = "snap wheel trigger"
        let result = try! XCTUnwrap(model.searchResults.first)
        XCTAssertEqual(result.category, .radialMenu)
        model.select(result)
        XCTAssertEqual(model.selectedCategory, .radialMenu)
        XCTAssertEqual(model.highlightedSettingID, "radial-shortcut")
    }

    @MainActor
    func testSettingsRepeatedSelectionDoesNotRepublishUnchangedNavigationState() {
        let model = SettingsNavigationModel(defaults: isolatedDefaults(), includeDebug: false)
        model.select(.profiles)
        var publicationCount = 0
        let observation = model.objectWillChange.sink { publicationCount += 1 }

        model.select(.profiles)
        XCTAssertEqual(publicationCount, 0)

        model.select(.workspaces)
        XCTAssertEqual(publicationCount, 1)

        withExtendedLifetime(observation) {}
    }

    @MainActor
    func testLegacyDisplayAndLayoutDestinationsMigrateToWorkspaces() {
        for legacy in [SettingsCategory.displays, .layouts] {
            let defaults = isolatedDefaults()
            defaults.set(legacy.rawValue, forKey: "settings.selectedCategory.v1")
            let model = SettingsNavigationModel(defaults: defaults, includeDebug: false)

            XCTAssertEqual(model.selectedCategory, .workspaces)
            XCTAssertEqual(defaults.string(forKey: "settings.selectedCategory.v1"), "workspaces")
            model.select(legacy)
            XCTAssertEqual(model.selectedCategory, .workspaces)
        }
        let available = SettingsCatalog.availableCategories(includeDebug: false)
        XCTAssertTrue(available.contains(.workspaces))
        XCTAssertFalse(available.contains(.displays))
        XCTAssertFalse(available.contains(.layouts))
    }

    func testWorkspaceSearchRoutesConfigurationAndDynamicIdentityToWorkspaces() {
        for query in [
            "Independent Displays", "home display", "orientation", "inner gaps",
            "accordion padding", "reset this workspace", "workspace shortcuts",
        ] {
            XCTAssertEqual(
                SettingsCatalog.search(query, includeDebug: false).first?.category,
                .workspaces,
                "Expected Workspaces routing for \(query)"
            )
        }

        let dynamic = SettingsCatalog.search(
            "Writing",
            includeDebug: false,
            workspaces: [WorkspaceDefinition(name: "Writing", key: "w", layout: .accordion)]
        ).first { $0.workspaceID != nil }
        XCTAssertEqual(dynamic?.title, "Writing")
        XCTAssertEqual(dynamic?.category, .workspaces)
        XCTAssertNotNil(dynamic?.workspaceID)
    }

    func testTwoArrowTiledPlacementSearchRoutesToShortcuts() {
        let result = SettingsCatalog.search("top right BSP", includeDebug: false).first
        XCTAssertEqual(result?.id, "directional-move")
        XCTAssertEqual(result?.category, .shortcuts)
    }

    func testWorkspaceSelectionSurvivesReorderAndChoosesNearestAfterDelete() {
        let ids = [workspaceA.id, workspaceB.id, workspaceC.id]
        XCTAssertEqual(
            WorkspaceSettingsSelectionPolicy.reconciled(
                current: workspaceB.id,
                preferred: nil,
                workspaceIDs: [workspaceC.id, workspaceB.id, workspaceA.id]
            ),
            workspaceB.id
        )
        XCTAssertEqual(
            WorkspaceSettingsSelectionPolicy.selectionAfterDeleting(workspaceB.id, from: ids),
            workspaceC.id
        )
        XCTAssertEqual(
            WorkspaceSettingsSelectionPolicy.reconciled(
                current: workspaceB.id,
                preferred: workspaceC.id,
                workspaceIDs: ids
            ),
            workspaceC.id
        )
        XCTAssertEqual(
            WorkspaceSettingsSelectionPolicy.reconciled(
                current: UUID(),
                preferred: UUID(),
                workspaceIDs: ids
            ),
            workspaceA.id
        )
    }

    @MainActor
    func testWorkspaceDeepLinkTracksExactSelectionAndClearsStaleWorkspaceFocus() {
        let model = SettingsNavigationModel(defaults: isolatedDefaults(), includeDebug: false)
        let workspace = WorkspaceDefinition(name: "Writing", key: "w", layout: .accordion)
        let result = try! XCTUnwrap(SettingsCatalog.search(
            "Writing",
            includeDebug: false,
            workspaces: [workspace]
        ).first { $0.workspaceID == workspace.id })

        model.select(result)
        XCTAssertEqual(model.selectedCategory, .workspaces)
        XCTAssertEqual(model.requestedWorkspaceID, workspace.id)

        model.select(.shortcuts)
        XCTAssertEqual(model.selectedCategory, .shortcuts)
        XCTAssertNil(model.requestedWorkspaceID)
    }

    func testWorkspaceRowAccessibilityExposesFullIdentityAndOwnership() {
        let workspace = WorkspaceDefinition(name: "Long-form Writing", key: "w", layout: .accordion)
        XCTAssertEqual(
            WorkspaceSettingsAccessibility.rowLabel(
                workspace: workspace,
                displayRoleName: "Studio Display"
            ),
            "Long-form Writing, Home Display Studio Display, Accordion layout, workspace key W"
        )
    }

    func testWorkspaceInspectorShowsOnlyLayoutSpecificControls() {
        XCTAssertEqual(
            WorkspaceInspectorControlVisibility(layout: .none),
            WorkspaceInspectorControlVisibility(
                showsFreeformExplanation: true,
                showsOrientation: false,
                showsTiledGeometry: false,
                showsAccordionPadding: false
            )
        )
        XCTAssertEqual(
            WorkspaceInspectorControlVisibility(layout: .tiled),
            WorkspaceInspectorControlVisibility(
                showsFreeformExplanation: false,
                showsOrientation: true,
                showsTiledGeometry: true,
                showsAccordionPadding: false
            )
        )
        XCTAssertEqual(
            WorkspaceInspectorControlVisibility(layout: .accordion),
            WorkspaceInspectorControlVisibility(
                showsFreeformExplanation: false,
                showsOrientation: true,
                showsTiledGeometry: false,
                showsAccordionPadding: true
            )
        )
    }

    func testWorkspaceSettingsWindowHasRoomForSidebarListAndInspector() {
        XCTAssertEqual(SettingsWindowMetrics.minimumSize, CGSize(width: 760, height: 560))
        XCTAssertEqual(SettingsWindowMetrics.defaultSize, CGSize(width: 1280, height: 780))
        XCTAssertGreaterThan(SettingsWindowMetrics.defaultSize.width, SettingsWindowMetrics.minimumSize.width)
        XCTAssertGreaterThan(SettingsWindowMetrics.defaultSize.height, SettingsWindowMetrics.minimumSize.height)
        XCTAssertEqual(SettingsDetailLayout.resolve(availableWidth: 899), .compact)
        XCTAssertEqual(SettingsDetailLayout.resolve(availableWidth: 900), .wide)
        XCTAssertEqual(SettingsDetailLayout.resolve(availableWidth: 1_200), .wide)
    }

    @MainActor
    func testWorkspaceInspectorBindingsRemainScopedToTheirWorkspaceAfterAddingAndSwitching() {
        let defaults = isolatedDefaults()
        defaults.set(false, forKey: "iCloudSyncEnabled")
        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] }
        )
        store.workspaces = [workspaceA, workspaceB]

        let nameA = WorkspaceSettingsFieldBindings.name(store: store, workspaceID: workspaceA.id)
        let keyA = WorkspaceSettingsFieldBindings.key(store: store, workspaceID: workspaceA.id)
        let layoutA = WorkspaceSettingsFieldBindings.layout(store: store, workspaceID: workspaceA.id)
        let addedID = store.addWorkspace()
        let nameAdded = WorkspaceSettingsFieldBindings.name(store: store, workspaceID: addedID)
        let keyAdded = WorkspaceSettingsFieldBindings.key(store: store, workspaceID: addedID)

        XCTAssertEqual(nameA.wrappedValue, workspaceA.name)
        XCTAssertEqual(keyA.wrappedValue, workspaceA.key.uppercased())
        XCTAssertEqual(layoutA.wrappedValue, workspaceA.layout)
        XCTAssertEqual(nameAdded.wrappedValue, store.workspaces.first { $0.id == addedID }?.name)
        XCTAssertEqual(keyAdded.wrappedValue, store.workspaces.first { $0.id == addedID }?.key.uppercased())

        nameAdded.wrappedValue = "Added"
        keyAdded.wrappedValue = "z"
        layoutA.wrappedValue = .accordion

        XCTAssertEqual(store.workspaces.first { $0.id == workspaceA.id }?.name, workspaceA.name)
        XCTAssertEqual(store.workspaces.first { $0.id == workspaceA.id }?.key, workspaceA.key)
        XCTAssertEqual(store.workspaces.first { $0.id == workspaceA.id }?.layout, .accordion)
        XCTAssertEqual(store.workspaces.first { $0.id == addedID }?.name, "Added")
        XCTAssertEqual(store.workspaces.first { $0.id == addedID }?.key, "z")
    }

    @MainActor
    func testWorkspaceIdentitySettersRejectCrossWorkspaceClashes() {
        let defaults = isolatedDefaults()
        defaults.set(false, forKey: "iCloudSyncEnabled")
        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] }
        )
        store.workspaces = [workspaceA, workspaceB]

        store.setWorkspaceName("  COMMS  ", for: workspaceA.id)
        store.setWorkspaceKey("M", for: workspaceA.id)

        XCTAssertEqual(store.workspaces.first { $0.id == workspaceA.id }?.name, workspaceA.name)
        XCTAssertEqual(store.workspaces.first { $0.id == workspaceA.id }?.key, workspaceA.key)
        XCTAssertEqual(Set(store.workspaces.map {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }).count, store.workspaces.count)
        XCTAssertEqual(Set(store.workspaces.map { $0.key.lowercased() }).count, store.workspaces.count)
    }

    @MainActor
    func testWorkspaceAddDuplicateReorderAndDeletePreserveReusableConfiguration() {
        let defaults = isolatedDefaults()
        defaults.set(false, forKey: "iCloudSyncEnabled")
        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] }
        )
        store.workspaces = [workspaceA, workspaceB, workspaceC]
        let roleID = store.activeProfile.displayRoles[0].id
        store.assignWorkspace(workspaceB.id, toRole: roleID)

        let duplicateID = try! XCTUnwrap(store.duplicateWorkspace(id: workspaceB.id))
        let duplicate = try! XCTUnwrap(store.workspaces.first { $0.id == duplicateID })
        XCTAssertEqual(duplicate.layout, workspaceB.layout)
        XCTAssertEqual(duplicate.layoutConfiguration, workspaceB.layoutConfiguration)
        XCTAssertNotEqual(duplicate.name.lowercased(), workspaceB.name.lowercased())
        XCTAssertNotEqual(duplicate.key.lowercased(), workspaceB.key.lowercased())
        XCTAssertEqual(store.roleID(for: duplicateID), roleID)

        store.moveWorkspace(id: duplicateID, before: workspaceA.id)
        XCTAssertEqual(store.workspaces.first?.id, duplicateID)
        store.moveWorkspaces(fromOffsets: IndexSet(integer: 0), toOffset: store.workspaces.count)
        XCTAssertEqual(store.workspaces.last?.id, duplicateID)

        store.removeWorkspace(id: duplicateID)
        XCTAssertFalse(store.workspaces.contains { $0.id == duplicateID })
        let addedID = store.addWorkspace()
        let added = try! XCTUnwrap(store.workspaces.first { $0.id == addedID })
        XCTAssertFalse(added.name.isEmpty)
        XCTAssertFalse(added.key.isEmpty)
        XCTAssertEqual(Set(store.workspaces.map { $0.name.lowercased() }).count, store.workspaces.count)
        XCTAssertEqual(Set(store.workspaces.map { $0.key.lowercased() }).count, store.workspaces.count)
    }

    @MainActor
    func testWorkspaceHomeLayoutAndResetPersistInProfileWithNativeUndo() {
        let defaults = isolatedDefaults()
        defaults.set(false, forKey: "iCloudSyncEnabled")
        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] }
        )
        store.workspaces = [workspaceA, workspaceB]
        let secondRole = store.addDisplayRole(name: "Studio Display")
        store.assignWorkspace(workspaceB.id, toRole: secondRole)
        store.setLayout(.accordion, for: workspaceB.id)
        var configuration = store.layoutConfiguration(for: workspaceB.id)
        configuration.orientation = .vertical
        configuration.accordionPadding = 175
        store.setLayoutConfiguration(configuration, for: workspaceB.id)

        XCTAssertEqual(store.roleID(for: workspaceB.id), secondRole)
        XCTAssertEqual(store.activeProfile.workspaceRoleAssignments[workspaceB.id], secondRole)
        XCTAssertEqual(store.activeProfile.workspaces.first { $0.id == workspaceB.id }?.layout, .accordion)

        let undo = UndoManager()
        store.resetWorkspaceSettings(workspaceB.id, undoManager: undo)
        let reset = try! XCTUnwrap(store.workspaces.first { $0.id == workspaceB.id })
        XCTAssertEqual(reset.layout, .none)
        XCTAssertEqual(reset.layoutConfiguration, .aeroSpaceUserDefaults)
        XCTAssertEqual(reset.name, workspaceB.name)
        XCTAssertEqual(reset.key, workspaceB.key)
        XCTAssertEqual(store.roleID(for: workspaceB.id), secondRole)
        XCTAssertTrue(undo.canUndo)

        undo.undo()
        let restored = try! XCTUnwrap(store.workspaces.first { $0.id == workspaceB.id })
        XCTAssertEqual(restored.layout, .accordion)
        XCTAssertEqual(restored.layoutConfiguration?.orientation, .vertical)
        XCTAssertEqual(restored.layoutConfiguration?.accordionPadding, 175)
    }

    func testReleaseSearchNeverExposesDebugOnlyControls() {
        XCTAssertTrue(SettingsCatalog.search("logs", includeDebug: false).isEmpty)
        XCTAssertFalse(SettingsCatalog.search("logs", includeDebug: true).isEmpty)
        XCTAssertTrue(SettingsCatalog.search("rejected windows", includeDebug: false).isEmpty)
        XCTAssertEqual(
            SettingsCatalog.search("rejected windows", includeDebug: true).first?.id,
            "diagnostics-admission"
        )
    }

    func testSettingsSearchFindsFreeformByCurrentAndLegacyTerms() {
        for query in ["Freeform", "none", "manual frames", "no automatic layout"] {
            XCTAssertEqual(
                SettingsCatalog.search(query, includeDebug: false).first?.id,
                "workspace-layout",
                "Expected workspace layout result for \(query)"
            )
        }
    }

    func testGenericLayoutCycleIsAvailableThroughSharedCommandLayer() {
        var received: WindowManagerCommand?
        let dispatcher = WindowManagerCommandDispatcher { command, _ in received = command }

        XCTAssertEqual(dispatcher.dispatch(.cycleLayout(1), source: .radialMenu), .dispatched)
        XCTAssertEqual(received, .cycleLayout(1))
    }

    func testPrimaryMenuBarTargetCanOnlyOpenMenu() {
        XCTAssertEqual(MenuBarInteractionRouter.action(for: .primary), .openMenu)
        XCTAssertEqual(MenuBarInteractionRouter.action(for: .displayIndicator("external")), .openMenu)
        XCTAssertEqual(
            MenuBarInteractionRouter.action(for: .workspace(
                workspaceID: workspaceB.id,
                displayIdentifier: "external"
            )),
            .switchWorkspace(workspaceID: workspaceB.id, displayIdentifier: "external")
        )
    }

    func testMenuBarPresentationModesKeepPrimaryMenuSeparateFromWorkspaceButtons() {
        XCTAssertEqual(
            MenuBarPresentationMode.compact.primaryLabelDescriptor,
            MenuBarPrimaryLabelDescriptor(
                showsIcon: true,
                indicatorStyle: .compact,
                showsWorkspaceStrip: false
            )
        )
        XCTAssertEqual(
            MenuBarPresentationMode.medium.primaryLabelDescriptor,
            MenuBarPrimaryLabelDescriptor(
                showsIcon: true,
                indicatorStyle: .medium,
                showsWorkspaceStrip: false
            )
        )
        XCTAssertTrue(MenuBarPresentationMode.full.primaryLabelDescriptor.showsWorkspaceStrip)
        XCTAssertTrue(MenuBarPresentationMode.full.primaryLabelDescriptor.showsIcon)
        XCTAssertEqual(
            MenuBarPresentationMode.full.primaryLabelDescriptor,
            MenuBarPrimaryLabelDescriptor(
                showsIcon: true,
                indicatorStyle: .none,
                showsWorkspaceStrip: true
            )
        )
    }

    @MainActor
    func testPrimaryMenuBarStateUsesInteractionWorkspaceWithMultipleActiveDisplays() {
        let model = MenuBarStateModel(workspaces: [workspaceA, workspaceB, workspaceC])
        model.update(
            state: WorkspaceEngineState(
                currentWorkspaceID: workspaceB.id,
                activeWorkspaceIDs: [workspaceA.id, workspaceB.id],
                previousWorkspaceID: workspaceC.id,
                managedWindowCount: 3,
                accessibilityGranted: true
            ),
            workspaces: [workspaceA, workspaceB, workspaceC]
        )

        XCTAssertEqual(model.currentWorkspaceName, workspaceB.name)
        XCTAssertEqual(model.activeWorkspaceNames, [workspaceA.name, workspaceB.name])
        XCTAssertTrue(model.accessibilityLabel.contains("Interaction workspace \(workspaceB.name)"))
        XCTAssertEqual(
            model.workspaceItems.filter(\.isActive).map(\.id),
            [workspaceA.id, workspaceB.id]
        )
        XCTAssertEqual(
            model.workspaceItems.first(where: \.isInteractionWorkspace)?.id,
            workspaceB.id
        )
    }

    @MainActor
    func testMenuBarPresentationDefaultsToCompactAndPersistsLocally() {
        let defaults = isolatedDefaults()
        defaults.set(false, forKey: "iCloudSyncEnabled")

        do {
            let writer = SettingsStore(
                defaults: defaults,
                ubiquitousStore: nil,
                connectedDisplaysProvider: { [] }
            )
            XCTAssertEqual(writer.menuBarPresentationMode, .compact)
            writer.menuBarPresentationMode = .full
        }

        let reader = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] }
        )
        XCTAssertEqual(reader.menuBarPresentationMode, .full)
    }

    @MainActor
    func testUnknownMenuBarPresentationMigratesSafelyToCompact() {
        let defaults = isolatedDefaults()
        defaults.set(false, forKey: "iCloudSyncEnabled")
        defaults.set("future-mode", forKey: "menuBarPresentationMode.v1")

        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] }
        )

        XCTAssertEqual(store.menuBarPresentationMode, .compact)
    }

    func testSettingsSearchFindsMenuBarPresentationAndSynonyms() {
        for query in ["Menu bar presentation", "status item", "notch", "workspace indicator"] {
            XCTAssertEqual(
                SettingsCatalog.search(query, includeDebug: false).first?.id,
                "menu-bar-presentation",
                "Expected menu-bar presentation result for \(query)"
            )
        }
        XCTAssertEqual(
            SettingsCatalog.search("highlight colour", includeDebug: false).first?.id,
            "menu-bar-highlight"
        )
        XCTAssertEqual(
            SettingsCatalog.search("workspace key label", includeDebug: false).first?.id,
            "menu-bar-workspace-labels"
        )
    }

    func testSettingsSearchFindsApplicationRulePause() {
        XCTAssertEqual(
            SettingsCatalog.search("pause rule", includeDebug: false).first?.id,
            "app-rule-pause"
        )
        XCTAssertEqual(
            SettingsCatalog.search("resume", includeDebug: false).first?.id,
            "app-rule-pause"
        )
    }

    func testSettingsSearchFindsApplicationRuleUndo() {
        XCTAssertEqual(
            SettingsCatalog.search("undo rule", includeDebug: false).first?.id,
            "app-rule-undo"
        )
    }

    func testConfigurableShortcutDefaultsPreserveExistingBindings() {
        let configuration = HotKeyConfiguration()

        XCTAssertEqual(
            configuration.chord(for: .selectAccordion),
            HotKeyChord(keyCode: HotKeyManager.accordionKeyCode, modifiers: UInt32(optionKey))
        )
        XCTAssertEqual(
            configuration.chord(for: .selectTiled),
            HotKeyChord(keyCode: HotKeyManager.tiledKeyCode, modifiers: UInt32(optionKey))
        )
        XCTAssertEqual(
            configuration.chord(for: .toggleFloating),
            HotKeyChord(
                keyCode: HotKeyManager.toggleFloatingKeyCode,
                modifiers: HotKeyManager.toggleFloatingModifiers
            )
        )
        XCTAssertEqual(
            configuration.chord(for: .moveWorkspaceToNextDisplay),
            HotKeyManager.moveWorkspaceDisplayChord
        )
        XCTAssertEqual(
            configuration.chord(for: .commandWheel),
            HotKeyChord(keyCode: 49, modifiers: UInt32(controlKey | optionKey))
        )
    }

    func testConfigurableShortcutOverrideRoundTripsAndResets() throws {
        var configuration = HotKeyConfiguration()
        let replacement = HotKeyChord(keyCode: 6, modifiers: UInt32(controlKey | cmdKey))
        configuration.setChord(replacement, for: .previousWindow)

        let restored = try JSONDecoder().decode(
            HotKeyConfiguration.self,
            from: JSONEncoder().encode(configuration)
        )
        XCTAssertEqual(restored.chord(for: .previousWindow), replacement)
        XCTAssertFalse(restored.isUsingDefault(for: .previousWindow))

        var reset = restored
        reset.reset(.previousWindow)
        XCTAssertEqual(reset.chord(for: .previousWindow), ConfigurableHotKeyAction.previousWindow.defaultChord)
        XCTAssertTrue(reset.isUsingDefault(for: .previousWindow))
    }

    func testShortcutConflictChecksCommandsWorkspacesAndCommandWheel() {
        let configuration = HotKeyConfiguration()
        XCTAssertNotNil(HotKeyManager.configurableShortcutConflict(
            action: .previousWindow,
            chord: configuration.chord(for: .nextWindow),
            configuration: configuration,
            workspaces: [workspaceA]
        ))
        XCTAssertNotNil(HotKeyManager.configurableShortcutConflict(
            action: .previousWindow,
            chord: HotKeyChord(keyCode: 8, modifiers: UInt32(controlKey | optionKey)),
            configuration: configuration,
            workspaces: [workspaceA]
        ))
        XCTAssertNotNil(HotKeyManager.configurableShortcutConflict(
            action: .previousWindow,
            chord: configuration.chord(for: .commandWheel),
            configuration: configuration,
            workspaces: [workspaceA]
        ))
        XCTAssertNotNil(HotKeyManager.shortcutValidationMessage(
            HotKeyChord(keyCode: 8, modifiers: UInt32(shiftKey))
        ))
    }

    func testAuthoritativeShortcutModelNamesEveryCollidingOwnerAndSkipsBoth() {
        var configuration = HotKeyConfiguration()
        configuration.setChord(
            configuration.chord(for: .nextWindow),
            for: .previousWindow
        )
        let bracketWorkspace = WorkspaceDefinition(name: "Bracket", key: "[", layout: .none)
        let report = ShortcutConflictModel.evaluate(
            configuration: configuration,
            workspaces: [bracketWorkspace]
        )

        let globalIssue = try! XCTUnwrap(report.issues(for: .previousWindow).first)
        XCTAssertEqual(globalIssue.kind, .duplicate)
        XCTAssertTrue(globalIssue.message.contains("Previous window"))
        XCTAssertTrue(globalIssue.message.contains("Next window"))
        XCTAssertFalse(report.eligibleBindings.contains {
            $0.owner.configurableAction == .previousWindow ||
                $0.owner.configurableAction == .nextWindow
        })

        let workspaceIssues = report.issues(forWorkspace: bracketWorkspace.id)
        XCTAssertTrue(workspaceIssues.contains {
            $0.message.contains("Switch to workspace Bracket") &&
                $0.message.contains("Previous workspace")
        })
        XCTAssertFalse(report.eligibleBindings.contains {
            $0.owner.workspaceID == bracketWorkspace.id && $0.owner.kind == .workspaceSwitch
        })
        XCTAssertTrue(report.eligibleBindings.contains {
            $0.owner.workspaceID == bracketWorkspace.id && $0.owner.kind == .workspaceMove
        })
    }

    func testShortcutModelRejectsUnsupportedSavedKeysAndModifierCombinations() {
        var configuration = HotKeyConfiguration()
        configuration.setChord(
            HotKeyChord(keyCode: 999, modifiers: UInt32(controlKey)),
            for: .previousWindow
        )
        configuration.setChord(
            HotKeyChord(keyCode: 8, modifiers: UInt32(shiftKey)),
            for: .nextWindow
        )
        let report = ShortcutConflictModel.evaluate(
            configuration: configuration,
            workspaces: [WorkspaceDefinition(name: "Unsupported", key: "", layout: .none)]
        )

        XCTAssertEqual(report.issues(for: .previousWindow).first?.kind, .invalid)
        XCTAssertTrue(report.issues(for: .previousWindow).first?.message.contains("not supported") == true)
        XCTAssertEqual(report.issues(for: .nextWindow).first?.kind, .invalid)
        XCTAssertEqual(report.issues.filter { $0.chord == nil }.count, 2)
    }

    func testInjectedRegistrationFailureIsIsolatedAndReplacementUnregistersEveryOldToken() {
        let service = TestGlobalHotKeyRegistrationService()
        let failingChord = ConfigurableHotKeyAction.nextWindow.defaultChord
        service.failures[failingChord] = -9_878
        let manager = HotKeyManager(
            dispatcher: WindowManagerCommandDispatcher { _, _ in },
            registrationService: service,
            installsEventHandler: false
        )

        let first = manager.register(
            workspaces: [],
            hotKeyConfiguration: HotKeyConfiguration(),
            radialMenuEnabled: true
        )
        XCTAssertEqual(first.runtimeIssues.map(\.owner.configurableAction), [.nextWindow])
        XCTAssertFalse(first.registeredOwners.contains { $0.configurableAction == .nextWindow })
        XCTAssertTrue(first.registeredOwners.contains { $0.configurableAction == .previousWindow })
        let firstTokens = Set(service.registrations.map(\.token))
        XCTAssertEqual(firstTokens.count, ConfigurableHotKeyAction.allCases.count - 1)

        service.failures.removeAll()
        let second = manager.register(
            workspaces: [],
            hotKeyConfiguration: HotKeyConfiguration(),
            radialMenuEnabled: true
        )
        XCTAssertEqual(Set(service.unregistrations), firstTokens)
        XCTAssertTrue(second.runtimeIssues.isEmpty)
        XCTAssertEqual(second.registeredOwners.count, ConfigurableHotKeyAction.allCases.count)

        let replacementTokens = Set(service.registrations.suffix(second.registeredOwners.count).map(\.token))
        manager.suspendRegistration()
        XCTAssertTrue(replacementTokens.isSubset(of: Set(service.unregistrations)))
        let countAfterFirstSuspend = service.unregistrations.count
        manager.suspendRegistration()
        XCTAssertEqual(service.unregistrations.count, countAfterFirstSuspend)
    }

    func testFullscreenGameRegistrationScopeKeepsOnlyWorkspaceNavigation() {
        let service = TestGlobalHotKeyRegistrationService()
        let manager = HotKeyManager(
            dispatcher: WindowManagerCommandDispatcher { _, _ in },
            registrationService: service,
            installsEventHandler: false
        )
        let workspace = WorkspaceDefinition(name: "Game", key: "1", layout: .none)

        let report = manager.register(
            workspaces: [workspace],
            hotKeyConfiguration: HotKeyConfiguration(),
            radialMenuEnabled: true,
            scope: .workspaceNavigationOnly
        )

        XCTAssertTrue(report.registeredOwners.contains {
            $0.kind == .workspaceSwitch && $0.workspaceID == workspace.id
        })
        XCTAssertFalse(report.registeredOwners.contains { $0.kind == .workspaceMove })
        XCTAssertEqual(
            Set(report.registeredOwners.compactMap(\.configurableAction)),
            Set([.previousWorkspace, .nextWorkspace, .backAndForthWorkspace])
        )
        XCTAssertFalse(report.registeredOwners.contains { $0.kind == .commandWheel })
    }

    func testFullscreenGameRegistrationScopeReservesCommandEscapeForGameOverlay() {
        let service = TestGlobalHotKeyRegistrationService()
        let manager = HotKeyManager(
            dispatcher: WindowManagerCommandDispatcher { _, _ in },
            registrationService: service,
            installsEventHandler: false
        )
        var configuration = HotKeyConfiguration()
        configuration.setChord(
            HotKeyChord(keyCode: 53, modifiers: UInt32(cmdKey)),
            for: .previousWorkspace
        )

        let report = manager.register(
            workspaces: [],
            hotKeyConfiguration: configuration,
            scope: .workspaceNavigationOnly
        )

        XCTAssertFalse(report.registeredOwners.contains {
            $0.configurableAction == .previousWorkspace
        })
        XCTAssertFalse(service.registrations.contains {
            $0.chord == HotKeyChord(keyCode: 53, modifiers: UInt32(cmdKey))
        })
    }

    func testFailedUnregistrationIsRetriedWithoutReusingItsEventIdentifier() {
        let service = TestGlobalHotKeyRegistrationService()
        let manager = HotKeyManager(
            dispatcher: WindowManagerCommandDispatcher { _, _ in },
            registrationService: service,
            installsEventHandler: false
        )
        let first = manager.register(
            workspaces: [],
            hotKeyConfiguration: HotKeyConfiguration(),
            radialMenuEnabled: false
        )
        XCTAssertFalse(first.registeredOwners.isEmpty)
        let firstRegistrations = service.registrations
        let retained = firstRegistrations[0]
        service.unregistrationFailures[retained.token] = -9_877

        _ = manager.register(
            workspaces: [],
            hotKeyConfiguration: HotKeyConfiguration(),
            radialMenuEnabled: false
        )

        let replacementIdentifiers = Set(
            service.registrations.dropFirst(firstRegistrations.count).map(\.identifier)
        )
        XCTAssertFalse(replacementIdentifiers.contains(retained.identifier))
        XCTAssertEqual(service.unregistrations.filter { $0 == retained.token }.count, 1)

        service.unregistrationFailures.removeValue(forKey: retained.token)
        manager.suspendRegistration()
        XCTAssertEqual(service.unregistrations.filter { $0 == retained.token }.count, 2)
    }

    func testEventHandlerInstallationFailureRegistersNoSystemHotKeys() {
        let sink = MemoryDiagnosticSink()
        let logger = DiagnosticLogger(buildMode: .debug, sink: sink)
        let service = TestGlobalHotKeyRegistrationService()
        let manager = HotKeyManager(
            dispatcher: WindowManagerCommandDispatcher { _, _ in },
            diagnostics: logger,
            registrationService: service,
            eventHandlerInstaller: { _, _ in -9_876 }
        )

        let report = manager.register(
            workspaces: [],
            hotKeyConfiguration: HotKeyConfiguration(),
            radialMenuEnabled: false
        )

        XCTAssertTrue(service.registrations.isEmpty)
        XCTAssertTrue(report.registeredOwners.isEmpty)
        XCTAssertEqual(report.runtimeIssues.count, ConfigurableHotKeyAction.allCases.count - 1)
        XCTAssertTrue(report.runtimeIssues.allSatisfy { $0.status == -9_876 })
        XCTAssertTrue(sink.text.contains("event-handler-installation-failed"))
    }

    func testRegistrationNeverLetsFirstDuplicateSilentlyOwnTheChord() {
        var configuration = HotKeyConfiguration()
        configuration.setChord(
            configuration.chord(for: .nextWindow),
            for: .previousWindow
        )
        let service = TestGlobalHotKeyRegistrationService()
        let manager = HotKeyManager(
            dispatcher: WindowManagerCommandDispatcher { _, _ in },
            registrationService: service,
            installsEventHandler: false
        )

        let report = manager.register(
            workspaces: [],
            hotKeyConfiguration: configuration,
            radialMenuEnabled: false
        )

        XCTAssertFalse(report.registeredOwners.contains { $0.configurableAction == .previousWindow })
        XCTAssertFalse(report.registeredOwners.contains { $0.configurableAction == .nextWindow })
        XCTAssertFalse(service.registrations.contains { $0.chord == ConfigurableHotKeyAction.nextWindow.defaultChord })
    }

    func testShortcutRegistrationDiagnosticsUseSafeOwnerIDsAndStatus() {
        let sink = MemoryDiagnosticSink()
        let logger = DiagnosticLogger(buildMode: .debug, sink: sink)
        let service = TestGlobalHotKeyRegistrationService()
        service.failures[ConfigurableHotKeyAction.nextWindow.defaultChord] = -9_878
        let manager = HotKeyManager(
            dispatcher: WindowManagerCommandDispatcher { _, _ in },
            diagnostics: logger,
            registrationService: service,
            installsEventHandler: false
        )

        _ = manager.register(workspaces: [], radialMenuEnabled: false)

        XCTAssertTrue(sink.text.contains("registration-failed"))
        XCTAssertTrue(sink.text.contains("global:nextWindow"))
        XCTAssertTrue(sink.text.contains("-9878"))
        XCTAssertFalse(sink.text.contains("window-title"))
    }

    @MainActor
    func testRuntimeShortcutFailuresRemainLocalAndAreNotPersisted() {
        let defaults = isolatedDefaults()
        defaults.set(false, forKey: "iCloudSyncEnabled")
        let first = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] }
        )
        first.setHotKeyRuntimeIssues([HotKeyRuntimeIssue(
            owner: .global(.nextWindow),
            chord: .init(keyCode: 30, modifiers: UInt32(optionKey)),
            status: -9_878
        )])
        first.setDirectionalMoveGestureRuntimeIssue("gesture monitor unavailable")
        XCTAssertEqual(first.hotKeyRuntimeIssues.count, 1)
        XCTAssertEqual(first.directionalMoveGestureRuntimeIssue, "gesture monitor unavailable")

        let restored = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] }
        )
        XCTAssertTrue(restored.hotKeyRuntimeIssues.isEmpty)
        XCTAssertNil(restored.directionalMoveGestureRuntimeIssue)
        XCTAssertNil(defaults.object(forKey: "hotKeyRuntimeIssues"))
        XCTAssertNil(defaults.object(forKey: "directionalMoveGestureRuntimeIssue"))
    }

    func testShortcutRecorderConvertsNativeEventToCarbonChord() {
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.control, .option, .shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "c",
            charactersIgnoringModifiers: "c",
            isARepeat: false,
            keyCode: 8
        )

        XCTAssertEqual(
            event.flatMap(HotKeyManager.recordedChord),
            HotKeyChord(keyCode: 8, modifiers: UInt32(controlKey | optionKey | shiftKey))
        )
    }

    func testShortcutRecorderRejectsModifierOnlyTriggerWithoutInstallingEventTap() {
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.control],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 59
        )
        XCTAssertNil(event.flatMap(HotKeyManager.recordedChord))
    }

    @MainActor
    func testShortcutConfigurationPersistsWithoutChangingDefaults() {
        let defaults = isolatedDefaults()
        defaults.set(false, forKey: "iCloudSyncEnabled")
        let replacement = HotKeyChord(keyCode: 6, modifiers: UInt32(controlKey | cmdKey))
        do {
            let writer = SettingsStore(
                defaults: defaults,
                ubiquitousStore: nil,
                connectedDisplaysProvider: { [] }
            )
            writer.setShortcut(replacement, for: .previousWindow)
        }
        let reader = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] }
        )
        XCTAssertEqual(reader.hotKeyConfiguration.chord(for: .previousWindow), replacement)
        XCTAssertEqual(
            reader.hotKeyConfiguration.chord(for: .selectAccordion),
            ConfigurableHotKeyAction.selectAccordion.defaultChord
        )
    }

    func testSettingsSearchFindsShortcutRecorder() {
        XCTAssertEqual(
            SettingsCatalog.search("customize hotkeys", includeDebug: false).first?.id,
            "shortcut-recorder"
        )
    }

    func testWorkspaceResetUsesWindowManagerTerminologyEverywhere() {
        XCTAssertEqual(
            SettingsCopy.restoreWindowManagerDefaultsTitle,
            "Restore WindowRanger Defaults"
        )
        XCTAssertEqual(
            SettingsCatalog.search("Restore WindowRanger defaults", includeDebug: false).first?.id,
            "workspace-defaults"
        )
        XCTAssertTrue(
            SettingsCatalog.entries
                .filter { !$0.debugOnly }
                .allSatisfy { entry in
                    !([entry.title, entry.description] + entry.synonyms)
                        .joined(separator: " ")
                        .localizedCaseInsensitiveContains("AeroSpace defaults")
                }
        )
    }

    func testSettingsSearchRoutesHoldAndTwoRingEditorToCommandWheel() {
        XCTAssertEqual(
            SettingsCatalog.search("hold trigger timeout", includeDebug: false).first?.id,
            "radial-activation"
        )
        XCTAssertEqual(
            SettingsCatalog.search("outer ring customize", includeDebug: false).first?.id,
            "radial-editor"
        )
    }

    func testSettingsSearchIndexesEveryBuiltInWheelItem() {
        for metadata in RadialCommandCatalogue.allMetadata {
            let matches = SettingsCatalog.search(metadata.title, includeDebug: false)
            XCTAssertTrue(
                matches.contains { $0.category == .radialMenu },
                "Expected Settings search to route \(metadata.title) to Command Wheel"
            )
        }
    }

    @MainActor
    func testRadialSettingsPersistWithoutICloudOrSystemSideEffects() {
        let defaults = isolatedDefaults()
        defaults.set(false, forKey: "iCloudSyncEnabled")
        do {
            let writer = SettingsStore(
                defaults: defaults,
                ubiquitousStore: nil,
                connectedDisplaysProvider: { [] }
            )
            writer.radialMenuEnabled = false
            writer.radialMenuActivationStyle = .holdToShow
            writer.radialMenuHoldDelay = 0.35
            writer.radialMenuGlobeFnHoldEnabled = true
            writer.setShortcut(
                LegacyRadialMenuShortcut.controlOptionBackslash.chord,
                for: .commandWheel
            )
            writer.radialWheelDefinition = .minimalFallback
        }
        let reader = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] }
        )
        XCTAssertFalse(reader.radialMenuEnabled)
        XCTAssertEqual(reader.radialMenuActivationStyle, .holdToShow)
        XCTAssertEqual(reader.radialMenuHoldDelay, 0.35, accuracy: 0.001)
        XCTAssertTrue(reader.radialMenuGlobeFnHoldEnabled)
        XCTAssertEqual(
            reader.hotKeyConfiguration.chord(for: .commandWheel),
            LegacyRadialMenuShortcut.controlOptionBackslash.chord
        )
        XCTAssertEqual(reader.radialWheelDefinition, .minimalFallback)
    }

    @MainActor
    func testGlobeFnHoldDefaultsOffStaysDeviceLocalAndIsSearchable() {
        let defaults = isolatedDefaults()
        let cloud = RecordingUbiquitousStore()
        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: cloud,
            connectedDisplaysProvider: { [] }
        )
        XCTAssertFalse(store.radialMenuGlobeFnHoldEnabled)

        store.radialMenuGlobeFnHoldEnabled = true
        XCTAssertEqual(
            defaults.bool(forKey: "radialMenuGlobeFnHoldEnabled.v1"),
            true
        )
        XCTAssertFalse(cloud.keys.contains("radialMenuGlobeFnHoldEnabled.v1"))
        XCTAssertTrue(
            SettingsCatalog.search("Globe Fn emoji", includeDebug: false)
                .contains { $0.id == "radial-globe-fn" && $0.category == .radialMenu }
        )

        let profileData = try! JSONEncoder().encode(store.profiles)
        let profileJSON = String(decoding: profileData, as: UTF8.self)
        XCTAssertFalse(profileJSON.contains("GlobeFn"))
        XCTAssertFalse(profileJSON.contains("radialMenuGlobeFnHoldEnabled"))
    }

    @MainActor
    func testWheelEditorMutationParticipatesInNativeUndoAndRedo() {
        let defaults = isolatedDefaults()
        defaults.set(false, forKey: "iCloudSyncEnabled")
        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] }
        )
        store.radialWheelDefinition = RadialWheelDefinition(items: [.layoutType])
        let original = store.radialWheelDefinition
        let undo = UndoManager()

        store.updateRadialWheelDefinition(actionName: "Add Wheel Item", undoManager: undo) {
            $0.add(.goToSpace)
        }
        XCTAssertTrue(store.radialWheelDefinition.items.contains(.goToSpace))
        XCTAssertTrue(undo.canUndo)

        undo.undo()
        XCTAssertEqual(store.radialWheelDefinition, original)
        XCTAssertTrue(undo.canRedo)
        undo.redo()
        XCTAssertTrue(store.radialWheelDefinition.items.contains(.goToSpace))
    }

    @MainActor
    func testLegacyWheelShortcutMigratesIntoSharedRecorderOnce() {
        let defaults = isolatedDefaults()
        defaults.set(false, forKey: "iCloudSyncEnabled")
        defaults.set(LegacyRadialMenuShortcut.controlOptionReturn.rawValue, forKey: "radialMenuShortcut.v1")

        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] }
        )

        XCTAssertEqual(
            store.hotKeyConfiguration.chord(for: .commandWheel),
            LegacyRadialMenuShortcut.controlOptionReturn.chord
        )
        XCTAssertNil(defaults.string(forKey: "radialMenuShortcut.v1"))
    }

    func testWheelSettingsAreGlobalAndNotEncodedInProfileDefinitions() throws {
        let role = ProfileDisplayRole(name: "Main")
        let profileData = try JSONEncoder().encode(WindowManagerProfile(
            name: "Test",
            workspaces: [workspaceA],
            displayMode: .unified,
            displayRoles: [role],
            workspaceRoleAssignments: [workspaceA.id: role.id],
            appRules: []
        ))
        let json = try XCTUnwrap(String(data: profileData, encoding: .utf8))
        XCTAssertFalse(json.contains("radialWheelDefinition"))
        XCTAssertFalse(json.contains("radialMenuActivationStyle"))
        XCTAssertFalse(json.contains("commandWheel"))
    }

    private func context(
        layout: WorkspaceLayout = .tiled,
        mode: MultiDisplayMode = .unified,
        window: RadialFocusedWindowContext?,
        focusSource: RadialFocusSource = .focusedManagedWindow,
        focusFollowsMovedWindow: Bool = false,
        availableFocusDirections: Set<WindowDirection> = [],
        availableMoveDirections: Set<WindowDirection> = [],
        canSmartResize: Bool = false
    ) -> RadialCommandContext {
        let options = [
            RadialWorkspaceOption(id: workspaceA.id, name: workspaceA.name, layout: layout, homeDisplayIdentifier: "external"),
            RadialWorkspaceOption(id: workspaceB.id, name: workspaceB.name, layout: workspaceB.layout, homeDisplayIdentifier: "main"),
            RadialWorkspaceOption(id: workspaceC.id, name: workspaceC.name, layout: workspaceC.layout, homeDisplayIdentifier: "external"),
        ]
        var value = RadialCommandContext(
            focusedWindow: window,
            focusSource: window == nil ? .none : focusSource,
            workspaceID: workspaceA.id,
            workspaceName: workspaceA.name,
            layout: layout,
            displayIdentifier: "external",
            displayName: "External Display",
            displayBounds: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
            displayMode: mode,
            focusFollowsMovedWindow: focusFollowsMovedWindow,
            connectedDisplayIdentifiers: ["main", "external"],
            connectedDisplays: [
                RadialDisplayOption(id: "main", name: "Main Display", isMain: true),
                RadialDisplayOption(id: "external", name: "External Display", isMain: false),
            ],
            availableFocusDirections: availableFocusDirections,
            availableMoveDirections: availableMoveDirections,
            canSmartResize: canSmartResize,
            workspaces: options,
            supportedCommands: RadialCommandCapability.current,
            validationToken: "token"
        )
        if layout == .tiled,
           let window,
           window.layoutState == .managed || window.layoutState == .explicitlyManaged {
            let focused = WindowKey(
                processIdentifier: window.processIdentifier,
                windowIdentifier: window.windowIdentifier
            )
            let sibling = WindowKey(processIdentifier: 43, windowIdentifier: 100)
            let bounds = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
            if let tree = TiledLayoutEngine.flatTree(
                windowKeys: [focused, sibling],
                orientation: .horizontal
            ) {
                value.tiledPlacementPreviews = VisualPlacement.compassOrder.compactMap {
                    try? TiledLayoutEngine.placing(
                        focused,
                        at: $0,
                        in: tree,
                        bounds: bounds,
                        configuration: .aeroSpaceUserDefaults
                    )
                }
            }
        }
        return value
    }

    private func settingsDisplays() -> [SettingsDisplayDescriptor] {
        [
            SettingsDisplayDescriptor(
                identifier: "main",
                visibleFrame: CGRect(x: 0, y: 0, width: 1728, height: 1080),
                isMain: true
            ),
            SettingsDisplayDescriptor(
                identifier: "external",
                visibleFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
                isMain: false
            ),
        ]
    }

    private func window(
        _ state: RadialFocusedWindowLayoutState,
        automaticDialog: Bool = false,
        appRuleExcluded: Bool = false,
        keepsOnAll: Bool = false
    ) -> RadialFocusedWindowContext {
        RadialFocusedWindowContext(
            processIdentifier: 42,
            windowIdentifier: 99,
            workspaceID: workspaceA.id,
            frame: WindowFrame(position: CGPoint(x: -1500, y: 100), size: CGSize(width: 900, height: 700)),
            layoutState: state,
            isAutomaticallyFloatingDialog: automaticDialog,
            isAppRuleExcluded: appRuleExcluded,
            keepsOnAllWorkspaces: keepsOnAll
        )
    }

    private func flatten(_ items: [RadialMenuItem]) -> [RadialMenuItem] {
        items + items.flatMap { flatten($0.children) }
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "WindowRangerTests.Radial.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

@MainActor
private final class TestSettingsWindowSurface: SettingsWindowSurface {
    var frame: CGRect
    private(set) var isVisible = false
    private(set) var constraintCount = 0
    private(set) var prepareCount = 0
    private(set) var surfacedFrames: [CGRect] = []
    private(set) var nonactivatingSurfaceFrames: [CGRect] = []
    private(set) var repositionedFrames: [CGRect] = []
    private(set) var hideCount = 0
    private(set) var restoreCount = 0

    init(frame: CGRect) {
        self.frame = frame
    }

    func applyWindowConstraints() { constraintCount += 1 }

    func prepareAsFloatingUtility() { prepareCount += 1 }

    func surface(at frame: CGRect) {
        self.frame = frame
        isVisible = true
        surfacedFrames.append(frame)
    }

    func surfaceWithoutActivation(at frame: CGRect) {
        self.frame = frame
        isVisible = true
        nonactivatingSurfaceFrames.append(frame)
    }

    func repositionWithoutActivation(to frame: CGRect) {
        self.frame = frame
        repositionedFrames.append(frame)
    }

    func hideForWorkspace() {
        isVisible = false
        hideCount += 1
    }

    func restoreOrdinaryLifecycle() { restoreCount += 1 }
}

private final class TestGlobalHotKeyRegistrationService: GlobalHotKeyRegistrationService {
    struct Registration {
        let chord: HotKeyChord
        let identifier: UInt32
        let token: HotKeyRegistrationToken
    }

    var failures: [HotKeyChord: OSStatus] = [:]
    var unregistrationFailures: [HotKeyRegistrationToken: OSStatus] = [:]
    private(set) var registrations: [Registration] = []
    private(set) var unregistrations: [HotKeyRegistrationToken] = []

    func register(
        chord: HotKeyChord,
        identifier: UInt32
    ) -> Result<HotKeyRegistrationToken, HotKeyRegistrationFailure> {
        if let status = failures[chord] {
            return .failure(HotKeyRegistrationFailure(status: status))
        }
        let token = HotKeyRegistrationToken()
        registrations.append(Registration(chord: chord, identifier: identifier, token: token))
        return .success(token)
    }

    func unregister(_ token: HotKeyRegistrationToken) -> OSStatus {
        unregistrations.append(token)
        return unregistrationFailures[token] ?? noErr
    }
}

private final class RecordingUbiquitousStore: UbiquitousKeyValueStoring {
    private var values: [String: Any] = [:]
    var notificationObject: AnyObject { self }
    var keys: Set<String> { Set(values.keys) }

    func object(forKey aKey: String) -> Any? { values[aKey] }
    func string(forKey aKey: String) -> String? { values[aKey] as? String }
    func data(forKey aKey: String) -> Data? { values[aKey] as? Data }
    func set(_ anObject: Any?, forKey aKey: String) { values[aKey] = anObject }
    func removeObject(forKey aKey: String) { values.removeValue(forKey: aKey) }
    func synchronize() -> Bool { true }
}

@MainActor
private final class TestGlobeFnRadialTrigger: GlobeFnRadialTriggerHandling {
    private(set) var beginRecognizedHoldCount = 0
    private(set) var events: [RadialMenuTriggerInputEvent] = []
    private(set) var cancelReasons: [String] = []

    func beginRecognizedHold() {
        beginRecognizedHoldCount += 1
    }

    func handle(
        _ event: RadialMenuTriggerInputEvent,
        style _: RadialMenuActivationStyle,
        holdDelay _: TimeInterval
    ) {
        events.append(event)
    }

    func cancel(reason: String) {
        cancelReasons.append(reason)
    }
}

@MainActor
private final class TestGlobeFnScheduledTask: GlobeFnScheduledTask {
    private(set) var isCancelled = false
    let delay: TimeInterval
    let action: @MainActor () -> Void

    init(delay: TimeInterval, action: @escaping @MainActor () -> Void) {
        self.delay = delay
        self.action = action
    }

    func cancel() {
        isCancelled = true
    }

    func run() {
        guard !isCancelled else { return }
        action()
    }
}

@MainActor
private final class TestGlobeFnScheduler: GlobeFnScheduling {
    private var tasks: [TestGlobeFnScheduledTask] = []

    var pendingCount: Int { tasks.filter { !$0.isCancelled }.count }
    var pendingDelays: [TimeInterval] {
        tasks.filter { !$0.isCancelled }.map(\.delay)
    }

    func schedule(
        after delay: TimeInterval,
        _ action: @escaping @MainActor () -> Void
    ) -> GlobeFnScheduledTask {
        let task = TestGlobeFnScheduledTask(delay: delay, action: action)
        tasks.append(task)
        return task
    }

    func runNext() {
        while !tasks.isEmpty {
            let task = tasks.removeFirst()
            if !task.isCancelled {
                task.run()
                return
            }
        }
    }

    func runAll() {
        while !tasks.isEmpty { runNext() }
    }
}

@MainActor
private final class TestGlobeFnEventMonitor: GlobeFnEventMonitoring {
    var eventHandler: CGGlobeFnEventMonitor.EventHandler?
    var interruptionHandler: CGGlobeFnEventMonitor.InterruptionHandler?
    var reenableResult = true
    private var startResults: [Bool]
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var reenableCount = 0

    init(startResults: [Bool] = [true]) {
        self.startResults = startResults
    }

    func start() -> Bool {
        startCount += 1
        return startResults.isEmpty ? true : startResults.removeFirst()
    }

    func stop() {
        stopCount += 1
    }

    func reenable() -> Bool {
        reenableCount += 1
        return reenableResult
    }

    func send(_ event: GlobeFnObservedEvent) -> Bool {
        eventHandler?(event) ?? false
    }

    func interrupt(_ interruption: GlobeFnEventMonitorInterruption) {
        interruptionHandler?(interruption)
    }
}

@MainActor
private final class TestSettingsMenuCommandTarget: NSObject {
    private(set) var invocationCount = 0

    @objc func openSettings(_ sender: NSMenuItem) {
        invocationCount += 1
    }
}

private extension CGRect {
    var midpoint: CGPoint { CGPoint(x: midX, y: midY) }
}
