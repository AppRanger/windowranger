import AppKit
import Carbon
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
        let suite = "WindowManagerTests.SettingsNavigation.\(UUID().uuidString)"
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
            frame: CGRect(x: 100, y: 100, width: 900, height: 640)
        )
        let context = SettingsSurfaceContext(
            workspaceID: workspaceB.id,
            displayIdentifier: "external",
            displayMode: .independent,
            resolutionReason: "test"
        )

        coordinator.requestOpen(context: context) { openCount += 1 }
        XCTAssertEqual(openCount, 1)
        XCTAssertTrue(surface.surfacedFrames.isEmpty)

        coordinator.attach(surface: surface)

        XCTAssertEqual(activationCount, 1)
        XCTAssertEqual(surface.prepareCount, 1)
        XCTAssertEqual(surface.surfacedFrames.count, 1)
        XCTAssertEqual(coordinator.assignedContext, context)
        XCTAssertTrue(displays[1].visibleFrame.contains(surface.surfacedFrames[0].midpoint))
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
        coordinator.requestOpen(
            context: SettingsSurfaceContext(
                workspaceID: workspaceA.id,
                displayIdentifier: "main",
                displayMode: .independent,
                resolutionReason: "first"
            ),
            openSettings: {}
        )
        surface.frame = surface.surfacedFrames.last!

        let reopened = SettingsSurfaceContext(
            workspaceID: workspaceB.id,
            displayIdentifier: "external",
            displayMode: .independent,
            resolutionReason: "reopen"
        )
        coordinator.requestOpen(context: reopened, openSettings: {})

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
            openSettings: {}
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

    func testSettingsPlacementCentersAcrossDisplaysAndClampsOnSameDisplay() {
        let displays = settingsDisplays()
        let crossing = SettingsWindowGeometry.placement(
            currentFrame: CGRect(x: 120, y: 120, width: 900, height: 640),
            requestedDisplayIdentifier: "external",
            displays: displays
        )
        XCTAssertEqual(crossing?.displayIdentifier, "external")
        XCTAssertEqual(crossing?.resolutionReason, "requested-display-centered")
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
            "Restore WindowManager Defaults"
        )
        XCTAssertEqual(
            SettingsCatalog.search("Restore WindowManager defaults", includeDebug: false).first?.id,
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
        XCTAssertEqual(
            reader.hotKeyConfiguration.chord(for: .commandWheel),
            LegacyRadialMenuShortcut.controlOptionBackslash.chord
        )
        XCTAssertEqual(reader.radialWheelDefinition, .minimalFallback)
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
        let suite = "WindowManagerTests.Radial.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

@MainActor
private final class TestSettingsWindowSurface: SettingsWindowSurface {
    var frame: CGRect
    private(set) var isVisible = false
    private(set) var prepareCount = 0
    private(set) var surfacedFrames: [CGRect] = []
    private(set) var nonactivatingSurfaceFrames: [CGRect] = []
    private(set) var repositionedFrames: [CGRect] = []
    private(set) var hideCount = 0
    private(set) var restoreCount = 0

    init(frame: CGRect) {
        self.frame = frame
    }

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

private extension CGRect {
    var midpoint: CGPoint { CGPoint(x: midX, y: midY) }
}
