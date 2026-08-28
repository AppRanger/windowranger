import XCTest
import Carbon

final class CommandPaletteTests: XCTestCase {
    private let focusID = UUID(uuidString: "81000000-0000-0000-0000-000000000001")!
    private let writingID = UUID(uuidString: "81000000-0000-0000-0000-000000000002")!
    private let profileID = UUID(uuidString: "81000000-0000-0000-0000-000000000003")!

    func testPalettePositionDefaultsToTopAndUsesBritishDisplayTitle() {
        XCTAssertEqual(CommandPalettePosition.defaultValue, .top)
        XCTAssertEqual(CommandPalettePosition.allCases, [.top, .center, .bottom])
        XCTAssertEqual(CommandPalettePosition.center.title, "Centre")
    }

    @MainActor
    func testPaletteGeometryKeepsHistoricalTopPlacementAndFitsNegativeCoordinateDisplay() {
        let visibleFrame = CGRect(x: -1_920, y: 24, width: 1_920, height: 1_056)
        let frame = CommandPaletteGeometry.frame(
            visibleFrame: visibleFrame,
            preferredSize: CommandPaletteController.panelSize,
            basePaletteSize: CommandPaletteController.panelSize,
            position: .top
        )

        XCTAssertEqual(frame.origin.x, -1_270, accuracy: 0.001)
        XCTAssertEqual(frame.origin.y, 470, accuracy: 0.001)
        XCTAssertEqual(frame.size, CommandPaletteController.panelSize)
        XCTAssertTrue(visibleFrame.contains(frame))
    }

    @MainActor
    func testPaletteGeometryPositionsAndHaloFramesStayWithinUsableAreaWithoutDrift() {
        let visibleFrame = CGRect(x: 2_560, y: -900, width: 1_440, height: 900)
        for position in CommandPalettePosition.allCases {
            let base = CommandPaletteGeometry.frame(
                visibleFrame: visibleFrame,
                preferredSize: CommandPaletteController.panelSize,
                basePaletteSize: CommandPaletteController.panelSize,
                position: position
            )
            let expanded = CommandPaletteGeometry.frame(
                visibleFrame: visibleFrame,
                preferredSize: CommandPaletteController.expandedPanelSize,
                basePaletteSize: CommandPaletteController.panelSize,
                position: position
            )
            let collapsed = CommandPaletteGeometry.frame(
                visibleFrame: visibleFrame,
                preferredSize: CommandPaletteController.panelSize,
                basePaletteSize: CommandPaletteController.panelSize,
                position: position
            )

            XCTAssertTrue(visibleFrame.contains(base), "\(position)")
            XCTAssertTrue(visibleFrame.contains(expanded), "\(position)")
            XCTAssertEqual(collapsed, base, "\(position)")
        }
    }

    @MainActor
    func testPaletteGeometryClampsUndersizedUsableArea() {
        let visibleFrame = CGRect(x: -300, y: 40, width: 500, height: 320)
        let frame = CommandPaletteGeometry.frame(
            visibleFrame: visibleFrame,
            preferredSize: CommandPaletteController.expandedPanelSize,
            basePaletteSize: CommandPaletteController.panelSize,
            position: .bottom
        )

        XCTAssertEqual(frame, visibleFrame)
        XCTAssertTrue(visibleFrame.contains(frame))
    }

    @MainActor
    func testPaletteHaloKeepsBasePaletteStationaryWhenTheDisplayHasRoom() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        let base = CommandPaletteGeometry.frame(
            visibleFrame: visibleFrame,
            preferredSize: CommandPaletteController.panelSize,
            basePaletteSize: CommandPaletteController.panelSize,
            position: .center
        )
        let expanded = CommandPaletteGeometry.frame(
            visibleFrame: visibleFrame,
            preferredSize: CommandPaletteController.expandedPanelSize,
            basePaletteSize: CommandPaletteController.panelSize,
            position: .center
        )

        XCTAssertEqual(expanded.origin.x, base.origin.x, accuracy: 0.001)
        XCTAssertTrue(visibleFrame.contains(expanded))
    }

    @MainActor
    func testPaletteHaloShiftsOnlyEnoughToContainRightOverflow() {
        let visibleFrame = CGRect(x: -1_200, y: 0, width: 900, height: 900)
        let base = CommandPaletteGeometry.frame(
            visibleFrame: visibleFrame,
            preferredSize: CommandPaletteController.panelSize,
            basePaletteSize: CommandPaletteController.panelSize,
            position: .bottom
        )
        let expanded = CommandPaletteGeometry.frame(
            visibleFrame: visibleFrame,
            preferredSize: CommandPaletteController.expandedPanelSize,
            basePaletteSize: CommandPaletteController.panelSize,
            position: .bottom
        )

        XCTAssertEqual(expanded.maxX, visibleFrame.maxX, accuracy: 0.001)
        XCTAssertEqual(expanded.origin.x, base.origin.x - 60, accuracy: 0.001)
        XCTAssertTrue(visibleFrame.contains(expanded))
    }

    func testPaletteCombinesContextualCommandsAndRegisteredShortcuts() {
        let entries = CommandPaletteIndex.entries(
            context: context(),
            query: "",
            hotKeyConfiguration: HotKeyConfiguration()
        )
        let destinations = Set(entries.map(\.destination))

        XCTAssertTrue(destinations.contains(.settings))
        XCTAssertTrue(destinations.contains(.command(.switchWorkspace(writingID))))
        XCTAssertTrue(destinations.contains(.command(.moveFocusedWindow(writingID))))
        XCTAssertTrue(destinations.contains(.command(.moveFocusedWindowAndFollow(writingID))))
        XCTAssertTrue(destinations.contains(.command(.focusDirection(.left))))
        XCTAssertFalse(destinations.contains(.command(.focusDirection(.right))))
        XCTAssertTrue(destinations.contains(.command(.moveWindowDirection(.right))))
        XCTAssertFalse(destinations.contains(.command(.moveWindowDirection(.left))))
        XCTAssertTrue(destinations.contains(.command(.smartResize(-50))))
        XCTAssertTrue(destinations.contains(.command(.smartResize(50))))
        XCTAssertTrue(destinations.contains(.command(.setPauseMode(true))))

        XCTAssertEqual(
            entries.first { $0.destination == .command(.cycleWindow(1)) }?.shortcut,
            HotKeyConfiguration().chord(for: .nextWindow).title
        )
    }

    func testPausedPaletteOffersOnlyResumeAndRejectsStalePauseEntry() {
        let value = context()
        let configuration = HotKeyConfiguration()
        let entries = CommandPaletteIndex.entries(
            context: value,
            query: "",
            hotKeyConfiguration: configuration,
            isPauseModeEnabled: true
        )

        XCTAssertEqual(entries.map(\.destination), [.command(.setPauseMode(false))])
        XCTAssertEqual(entries.first?.title, "Resume WindowRanger")
        XCTAssertNil(entries.first?.shortcut)
        XCTAssertTrue(CommandPaletteIndex.entries(
            context: value,
            query: "continue",
            hotKeyConfiguration: configuration,
            isPauseModeEnabled: true
        ).contains { $0.destination == .command(.setPauseMode(false)) })
        XCTAssertFalse(CommandPaletteIndex.contains(
            .command(.setPauseMode(true)),
            context: value,
            hotKeyConfiguration: configuration,
            isPauseModeEnabled: true
        ))
    }

    func testDispatcherRoutesPauseModeWithoutTouchingEngineCommands() {
        var requested: (Bool, String)?
        let dispatcher = WindowManagerCommandDispatcher(
            engine: WorkspaceEngine(workspaces: WorkspaceDefinition.defaults),
            setPauseMode: { requested = ($0, $1) }
        )

        XCTAssertEqual(
            dispatcher.dispatch(
                .setPauseMode(true),
                source: .commandPalette,
                correlationID: "pause-test"
            ),
            .dispatched
        )
        XCTAssertEqual(requested?.0, true)
        XCTAssertEqual(requested?.1, "pause-test")
    }

    func testDispatcherPreservesCommandSourceForQuickAppRecoveryBoundary() {
        var received: [(WindowManagerCommand, WindowManagerCommandSource)] = []
        let dispatcher = WindowManagerCommandDispatcher(
            sourceAwareExecutor: { command, _, source in
                received.append((command, source))
            }
        )

        dispatcher.dispatch(
            .toggleDropDownApp,
            source: .commandPalette,
            correlationID: "palette-quick-app"
        )
        dispatcher.dispatch(
            .toggleDropDownApp,
            source: .hotkey,
            correlationID: "hotkey-quick-app"
        )

        XCTAssertEqual(received.map(\.0), [.toggleDropDownApp, .toggleDropDownApp])
        XCTAssertEqual(received.map(\.1), [.commandPalette, .hotkey])
    }

    func testPaletteDoesNotInventAChordForAnUnassignedCommand() {
        var configuration = HotKeyConfiguration()
        configuration.setKeyCode(nil, for: .nextWindow)

        let entry = CommandPaletteIndex.entries(
            context: context(),
            query: "",
            hotKeyConfiguration: configuration
        ).first { $0.destination == .command(.cycleWindow(1)) }

        XCTAssertNotNil(entry)
        XCTAssertNil(entry?.shortcut)
    }

    func testSearchMatchesMultipleTermsAndRanksTheTitleMatchFirst() {
        let entries = CommandPaletteIndex.entries(
            context: context(),
            query: "move writing",
            hotKeyConfiguration: HotKeyConfiguration()
        )

        XCTAssertEqual(entries.first?.title, "Move to Writing")
        XCTAssertEqual(
            Set(entries.map(\.destination)),
            [
                .command(.moveFocusedWindow(writingID)),
                .command(.moveFocusedWindowAndFollow(writingID)),
            ]
        )
    }

    func testWindowCommandsDisappearAndPlacementHaloIsUnavailableWithoutAValidTarget() {
        var value = context()
        value = RadialCommandContext(
            focusedWindow: nil,
            focusSource: .none,
            workspaceID: value.workspaceID,
            workspaceName: value.workspaceName,
            layout: value.layout,
            displayIdentifier: value.displayIdentifier,
            displayName: value.displayName,
            displayBounds: value.displayBounds,
            displayMode: value.displayMode,
            focusFollowsMovedWindow: value.focusFollowsMovedWindow,
            connectedDisplayIdentifiers: value.connectedDisplayIdentifiers,
            connectedDisplays: value.connectedDisplays,
            availableFocusDirections: [],
            availableMoveDirections: [],
            canSmartResize: false,
            workspaces: value.workspaces,
            supportedCommands: value.supportedCommands,
            validationToken: value.validationToken
        )

        let destinations = Set(CommandPaletteIndex.entries(
            context: value,
            query: "",
            hotKeyConfiguration: HotKeyConfiguration()
        ).map(\.destination))

        XCTAssertFalse(CommandPaletteIndex.hasSpatialPlacementActions(in: value))
        XCTAssertTrue(CommandPaletteIndex.spatialPlacementActions(in: value).isEmpty)
        XCTAssertFalse(destinations.contains(.command(.moveFocusedWindow(writingID))))
        XCTAssertFalse(destinations.contains(.command(.toggleFloating)))
        XCTAssertTrue(destinations.contains(.command(.switchWorkspace(writingID))))
        XCTAssertTrue(destinations.contains(.settings))
    }

    func testPlacementHaloContainsOnlyStableCompassPlacementActions() {
        let value = freeformPlacementContext()

        let actions = CommandPaletteIndex.spatialPlacementActions(in: value)

        XCTAssertEqual(
            actions.compactMap { $0.freeformPlacementPreview?.placement },
            VisualPlacement.compassOrder
        )
        XCTAssertTrue(CommandPaletteIndex.hasSpatialPlacementActions(in: value))
        XCTAssertTrue(actions.allSatisfy { item in
            guard case .placeFreeformWindow = item.command else { return false }
            return true
        })
        let spatialMenu = RadialCommandContextBuilder.build(from: value, definition: .spatial)
        XCTAssertEqual(spatialMenu.items.map(\.id), actions.map(\.id))
        XCTAssertTrue(spatialMenu.items.allSatisfy { !$0.isGroup })
    }

    func testPlacementHaloKeyboardNavigationStartsRightAndWrapsCompassOrder() {
        let actions = CommandPaletteIndex.spatialPlacementActions(in: freeformPlacementContext())
        let initial = CommandPalettePlacementNavigation.initialPlacement(in: actions)

        XCTAssertEqual(initial, .right)
        XCTAssertEqual(
            CommandPalettePlacementNavigation.moved(from: initial, offset: 1, in: actions),
            .bottomRight
        )
        XCTAssertEqual(
            CommandPalettePlacementNavigation.moved(from: initial, offset: -1, in: actions),
            .topRight
        )
        XCTAssertEqual(
            CommandPalettePlacementNavigation.moved(from: .topLeft, offset: 1, in: actions),
            .top
        )
        XCTAssertEqual(
            CommandPalettePlacementNavigation.moved(from: .top, offset: -1, in: actions),
            .topLeft
        )
        XCTAssertEqual(
            CommandPalettePlacementNavigation.item(for: .right, in: actions)?.freeformPlacementPreview?.placement,
            .right
        )
    }

    func testQuickActionsStackLayoutAboveAvailablePlacement() {
        XCTAssertEqual(
            CommandPaletteQuickActionNavigation.availableActions(
                supportsLayoutSelection: true,
                supportsPlacement: true
            ),
            [.workspaceLayout, .placement]
        )
        XCTAssertEqual(
            CommandPaletteQuickActionNavigation.availableActions(
                supportsLayoutSelection: true,
                supportsPlacement: false
            ),
            [.workspaceLayout]
        )
        XCTAssertEqual(
            CommandPaletteQuickActionNavigation.availableActions(
                supportsLayoutSelection: false,
                supportsPlacement: true
            ),
            [.placement]
        )
        XCTAssertTrue(CommandPaletteQuickActionNavigation.availableActions(
            supportsLayoutSelection: false,
            supportsPlacement: false
        ).isEmpty)
        XCTAssertTrue(CommandPaletteQuickActionNavigation.availableActions(
            supportsLayoutSelection: true,
            supportsPlacement: true,
            isSearchEmpty: false
        ).isEmpty)
    }

    func testUpFromTopResultEntersTheNearestVisibleQuickAction() {
        let actions: [CommandPaletteQuickAction] = [.workspaceLayout, .placement]

        XCTAssertEqual(
            CommandPaletteQuickActionNavigation.actionEnteringFromTopResult(
                selectedIndex: 0,
                resultCount: 4,
                actions: actions
            ),
            .placement
        )
        XCTAssertEqual(
            CommandPaletteQuickActionNavigation.actionEnteringFromTopResult(
                selectedIndex: 0,
                resultCount: 4,
                actions: [.workspaceLayout]
            ),
            .workspaceLayout
        )
        XCTAssertNil(CommandPaletteQuickActionNavigation.actionEnteringFromTopResult(
            selectedIndex: 1,
            resultCount: 4,
            actions: actions
        ))
        XCTAssertNil(CommandPaletteQuickActionNavigation.actionEnteringFromTopResult(
            selectedIndex: 0,
            resultCount: 4,
            actions: []
        ))
    }

    func testQuickActionVerticalNavigationDoesNotCrossLayoutSegments() {
        let actions: [CommandPaletteQuickAction] = [.workspaceLayout, .placement]

        XCTAssertEqual(
            CommandPaletteQuickActionNavigation.moved(
                from: .workspaceLayout,
                offset: 1,
                in: actions
            ),
            .placement
        )
        XCTAssertEqual(
            CommandPaletteQuickActionNavigation.moved(
                from: .placement,
                offset: -1,
                in: actions
            ),
            .workspaceLayout
        )
        XCTAssertNil(CommandPaletteQuickActionNavigation.moved(
            from: .workspaceLayout,
            offset: -1,
            in: actions
        ))
        XCTAssertNil(CommandPaletteQuickActionNavigation.moved(
            from: .placement,
            offset: 1,
            in: actions
        ))
    }

    func testLayoutQuickActionWrapsOnlyItsOwnSegmentOrder() {
        XCTAssertEqual(
            CommandPaletteLayoutNavigation.moved(from: .none, offset: 1),
            .tiled
        )
        XCTAssertEqual(
            CommandPaletteLayoutNavigation.moved(from: .accordion, offset: 1),
            .none
        )
        XCTAssertEqual(
            CommandPaletteLayoutNavigation.moved(from: .none, offset: -1),
            .accordion
        )
    }

    func testInlineLayoutRefreshRebindsPlacementToSettledValidationToken() {
        let original = freeformPlacementContext(validationToken: "before-layout-settled")
        let current = freeformPlacementContext(validationToken: "after-layout-settled")

        XCTAssertEqual(
            CommandPaletteSelectionRevalidation.destination(
                .command(.placeFreeformWindow(.left, validationToken: original.validationToken)),
                original: original,
                current: current,
                hotKeyConfiguration: HotKeyConfiguration(),
                allowsInlineLayoutRefresh: true
            ),
            .command(.placeFreeformWindow(.left, validationToken: current.validationToken))
        )
    }

    func testInlineLayoutRefreshRebindsAnOlderPlacementWithinSettledContext() {
        let settled = freeformPlacementContext(validationToken: "settled-token")

        XCTAssertEqual(
            CommandPaletteSelectionRevalidation.destination(
                .command(.placeFreeformWindow(.right, validationToken: "older-preview-token")),
                original: settled,
                current: settled,
                hotKeyConfiguration: HotKeyConfiguration(),
                allowsInlineLayoutRefresh: true
            ),
            .command(.placeFreeformWindow(.right, validationToken: settled.validationToken))
        )
    }

    func testCommandsValidateBeforeDismissalAndOnlyPlacementDefersFocusRestoration() {
        XCTAssertTrue(CommandPaletteSelectionRevalidation.validatesBeforeDismissal(
            .command(.setLayout(.none))
        ))
        XCTAssertTrue(CommandPaletteSelectionRevalidation.validatesBeforeDismissal(
            .command(.placeFreeformWindow(.left, validationToken: "token"))
        ))
        XCTAssertFalse(CommandPaletteSelectionRevalidation.validatesBeforeDismissal(.settings))
        XCTAssertTrue(CommandPaletteSelectionRevalidation.defersFocusRestoration(
            for: .command(.placeFreeformWindow(.left, validationToken: "token"))
        ))
        XCTAssertTrue(CommandPaletteSelectionRevalidation.defersFocusRestoration(
            for: .command(.placeTiledWindow(.topLeft, validationToken: "token"))
        ))
        XCTAssertFalse(CommandPaletteSelectionRevalidation.defersFocusRestoration(
            for: .command(.setLayout(.none))
        ))
        XCTAssertFalse(CommandPaletteSelectionRevalidation.defersFocusRestoration(for: .settings))
    }

    func testAsyncValidationCannotCompleteAgainstAReplacementPalette() {
        XCTAssertTrue(CommandPaletteSelectionRevalidation.isValidationRequestCurrent(
            presentationGeneration: 7,
            requestGeneration: 7,
            isPresented: true
        ))
        XCTAssertFalse(CommandPaletteSelectionRevalidation.isValidationRequestCurrent(
            presentationGeneration: 7,
            requestGeneration: 8,
            isPresented: true
        ))
        XCTAssertFalse(CommandPaletteSelectionRevalidation.isValidationRequestCurrent(
            presentationGeneration: 7,
            requestGeneration: 7,
            isPresented: false
        ))
    }

    func testOrdinaryCommandRevalidationAcceptsOnlyTheCapturedContext() {
        let original = context(validationToken: "captured")
        let requested = CommandPaletteDestination.command(.switchWorkspace(writingID))

        XCTAssertEqual(
            CommandPaletteSelectionRevalidation.destination(
                requested,
                original: original,
                current: original,
                hotKeyConfiguration: HotKeyConfiguration(),
                allowsInlineLayoutRefresh: false
            ),
            requested
        )
        XCTAssertNil(CommandPaletteSelectionRevalidation.destination(
            requested,
            original: original,
            current: context(validationToken: "changed", windowIdentifier: 999),
            hotKeyConfiguration: HotKeyConfiguration(),
            allowsInlineLayoutRefresh: false
        ))
    }

    func testInlineLayoutRefreshRejectsAChangedWindowOrLayout() {
        let original = freeformPlacementContext(validationToken: "before-layout-settled")
        let changedWindow = freeformPlacementContext(
            validationToken: "after-layout-settled",
            windowIdentifier: 999
        )
        let changedLayout = context(layout: .tiled, validationToken: "after-layout-settled")
        let requested = CommandPaletteDestination.command(
            .placeFreeformWindow(.left, validationToken: original.validationToken)
        )

        XCTAssertNil(CommandPaletteSelectionRevalidation.destination(
            requested,
            original: original,
            current: changedWindow,
            hotKeyConfiguration: HotKeyConfiguration(),
            allowsInlineLayoutRefresh: true
        ))
        XCTAssertNil(CommandPaletteSelectionRevalidation.destination(
            requested,
            original: original,
            current: changedLayout,
            hotKeyConfiguration: HotKeyConfiguration(),
            allowsInlineLayoutRefresh: true
        ))
        XCTAssertNil(CommandPaletteSelectionRevalidation.destination(
            requested,
            original: original,
            current: freeformPlacementContext(validationToken: "after-layout-settled"),
            hotKeyConfiguration: HotKeyConfiguration(),
            allowsInlineLayoutRefresh: false
        ))
    }

    func testProfileAndLayoutChildrenUseTheSharedContextCatalogue() {
        let laptop = UUID(uuidString: "82000000-0000-0000-0000-000000000001")!
        let studio = UUID(uuidString: "82000000-0000-0000-0000-000000000002")!
        var value = context()
        value.profiles = [
            .init(id: laptop, name: "Laptop"),
            .init(id: studio, name: "Studio"),
        ]
        value.activeProfileID = laptop
        value.isProfileManuallyPinned = true

        let destinations = Set(CommandPaletteIndex.entries(
            context: value,
            query: "",
            hotKeyConfiguration: HotKeyConfiguration()
        ).map(\.destination))

        XCTAssertTrue(destinations.contains(.command(.selectProfile(studio))))
        XCTAssertTrue(destinations.contains(.command(.resumeAutomaticProfileSelection)))
        XCTAssertTrue(destinations.contains(.command(.setLayout(.tiled))))
        XCTAssertTrue(destinations.contains(.command(.setLayout(.none))))
    }

    func testQuickAppShelfAddsDirectSelectionAndCycleActionsOnlyWhenConfigured() {
        var value = context()
        value.quickApps = [
            DropDownAppConfiguration(bundleIdentifier: "com.example.one", displayName: "One"),
            DropDownAppConfiguration(bundleIdentifier: "com.example.two", displayName: "Two"),
        ]
        let defaults = CommandPaletteIndex.entries(
            context: value,
            query: "",
            hotKeyConfiguration: HotKeyConfiguration()
        )
        XCTAssertTrue(defaults.contains { $0.destination == .command(.selectQuickApp("com.example.one")) })
        XCTAssertEqual(
            defaults.first { $0.destination == .command(.selectQuickApp("com.example.one")) }?.detail,
            "Quick App · \(value.workspaceName)"
        )
        XCTAssertTrue(defaults.contains { $0.destination == .command(.cycleQuickApp(-1)) })
        XCTAssertTrue(defaults.contains { $0.destination == .command(.cycleQuickApp(1)) })
        XCTAssertEqual(
            defaults.first { $0.destination == .command(.cycleQuickApp(-1)) }?.title,
            "Previous Quick App"
        )
        XCTAssertEqual(
            defaults.first { $0.destination == .command(.cycleQuickApp(1)) }?.title,
            "Next Quick App"
        )
        XCTAssertFalse(defaults.contains { $0.destination == .command(.cycleQuickApp(1)) && $0.shortcut != nil })
    }

    func testCurrentApplicationOffersSearchableApplicationAndShelfActions() {
        var value = context()
        value.activeProfileID = profileID
        value.currentApplication = RadialApplicationOption(
            bundleIdentifier: "com.example.Editor", displayName: "Editor"
        )
        let applicationCommand = WindowManagerCommand.addCurrentApplication(
            "com.example.Editor", displayName: "Editor", workspaceID: focusID, profileID: profileID,
            expectedMembership: .none
        )
        let shelfCommand = WindowManagerCommand.addCurrentApplicationToQuickAppShelf(
            "com.example.Editor", displayName: "Editor", profileID: profileID, expectedMembership: .none
        )

        let defaults = CommandPaletteIndex.entries(
            context: value, query: "", hotKeyConfiguration: HotKeyConfiguration()
        )
        XCTAssertEqual(defaults.first { $0.destination == .command(applicationCommand) }?.title,
                       "Add Editor to Applications")
        XCTAssertEqual(defaults.first { $0.destination == .command(shelfCommand) }?.title,
                       "Add Editor to App Shelf")
        XCTAssertTrue(CommandPaletteIndex.entries(
            context: value, query: "current application", hotKeyConfiguration: HotKeyConfiguration()
        ).contains { $0.destination == .command(applicationCommand) })
        XCTAssertTrue(CommandPaletteIndex.entries(
            context: value, query: "quick access", hotKeyConfiguration: HotKeyConfiguration()
        ).contains { $0.destination == .command(shelfCommand) })
    }

    func testCurrentApplicationActionsReflectExclusiveMembershipShelfCapacityAndCompanionRestriction() {
        var value = context()
        value.activeProfileID = profileID
        value.currentApplication = RadialApplicationOption(
            bundleIdentifier: "com.example.Editor", displayName: "Editor"
        )
        let applicationCommand = WindowManagerCommand.addCurrentApplication(
            "com.example.Editor", displayName: "Editor", workspaceID: focusID, profileID: profileID,
            expectedMembership: .none
        )
        let shelfCommand = WindowManagerCommand.addCurrentApplicationToQuickAppShelf(
            "com.example.Editor", displayName: "Editor", profileID: profileID, expectedMembership: .none
        )

        value.applicationRuleBundleIdentifiers = ["com.example.editor"]
        var entries = CommandPaletteIndex.entries(context: value, query: "", hotKeyConfiguration: .init())
        XCTAssertFalse(entries.contains { $0.destination == .command(applicationCommand) })
        let removalCommand = WindowManagerCommand.removeCurrentApplication(
            "com.example.Editor", profileID: profileID, expectedMembership: .appRule
        )
        XCTAssertEqual(entries.first { $0.destination == .command(removalCommand) }?.title,
                       "Remove Editor from Applications")
        XCTAssertEqual(entries.first { $0.destination == .command(removalCommand) }?.detail,
                       "Already in Applications · Remove application rule")
        XCTAssertTrue(CommandPaletteIndex.entries(
            context: value, query: "remove current application", hotKeyConfiguration: .init()
        ).contains { $0.destination == .command(removalCommand) })
        XCTAssertTrue(CommandPaletteIndex.entries(
            context: value, query: "add editor", hotKeyConfiguration: .init()
        ).contains { $0.destination == .command(removalCommand) })
        XCTAssertTrue(CommandPaletteIndex.entries(
            context: value, query: "add", hotKeyConfiguration: .init()
        ).contains { $0.destination == .command(removalCommand) })
        let ruleToShelfCommand = WindowManagerCommand.addCurrentApplicationToQuickAppShelf(
            "com.example.Editor", displayName: "Editor", profileID: profileID,
            expectedMembership: .appRule
        )
        XCTAssertEqual(entries.first { $0.destination == .command(ruleToShelfCommand) }?.title,
                       "Move Editor to App Shelf")

        value.applicationRuleBundleIdentifiers = []
        value.quickApps = [DropDownAppConfiguration(bundleIdentifier: "com.example.Editor", displayName: "Editor")]
        entries = CommandPaletteIndex.entries(context: value, query: "", hotKeyConfiguration: .init())
        let shelfToRuleCommand = WindowManagerCommand.addCurrentApplication(
            "com.example.Editor", displayName: "Editor", workspaceID: focusID, profileID: profileID,
            expectedMembership: .quickAppShelf
        )
        XCTAssertEqual(entries.first { $0.destination == .command(shelfToRuleCommand) }?.title,
                       "Move Editor to Applications")
        XCTAssertFalse(entries.contains { $0.destination == .command(removalCommand) })
        XCTAssertFalse(entries.contains { $0.destination == .command(shelfCommand) })

        value.quickApps = (1...QuickAppShelfPolicy.maximumCount).map {
            DropDownAppConfiguration(bundleIdentifier: "com.example.\($0)", displayName: "App \($0)")
        }
        entries = CommandPaletteIndex.entries(context: value, query: "", hotKeyConfiguration: .init())
        XCTAssertFalse(entries.contains { $0.destination == .command(shelfCommand) })

        value.quickApps = []
        value.currentApplication = RadialApplicationOption(
            bundleIdentifier: "dev.appranger.DesktopRanger.SurfaceLab", displayName: "SurfaceLab"
        )
        entries = CommandPaletteIndex.entries(context: value, query: "", hotKeyConfiguration: .init())
        XCTAssertTrue(entries.contains { entry in
            if case .command(.addCurrentApplication) = entry.destination { return true }
            return false
        })
        XCTAssertFalse(entries.contains { entry in
            if case .command(.addCurrentApplicationToQuickAppShelf) = entry.destination { return true }
            return false
        })
    }

    func testDispatcherRoutesCurrentApplicationConfigurationCommands() {
        var applicationRequest: (String, String, UUID, UUID, String)?
        var removalRequest: (String, UUID, CurrentApplicationConfigurationMembership, String)?
        var shelfRequest: (String, String, UUID, String)?
        let dispatcher = WindowManagerCommandDispatcher(
            engine: WorkspaceEngine(workspaces: WorkspaceDefinition.defaults),
            addCurrentApplication: { applicationRequest = ($0, $1, $2, $3, $5) },
            removeCurrentApplication: { removalRequest = ($0, $1, $2, $3) },
            addCurrentApplicationToQuickAppShelf: { shelfRequest = ($0, $1, $2, $4) }
        )
        dispatcher.dispatch(.addCurrentApplication(
            "com.example.Editor", displayName: "Editor", workspaceID: focusID, profileID: profileID,
            expectedMembership: .none
        ), source: .commandPalette, correlationID: "application-test")
        dispatcher.dispatch(.addCurrentApplicationToQuickAppShelf(
            "com.example.Editor", displayName: "Editor", profileID: profileID, expectedMembership: .none
        ), source: .commandPalette, correlationID: "shelf-test")
        dispatcher.dispatch(.removeCurrentApplication(
            "com.example.Editor", profileID: profileID, expectedMembership: .appRule
        ), source: .commandPalette, correlationID: "removal-test")
        XCTAssertEqual(applicationRequest?.0, "com.example.Editor")
        XCTAssertEqual(applicationRequest?.2, focusID)
        XCTAssertEqual(applicationRequest?.3, profileID)
        XCTAssertEqual(applicationRequest?.4, "application-test")
        XCTAssertEqual(shelfRequest?.0, "com.example.Editor")
        XCTAssertEqual(shelfRequest?.2, profileID)
        XCTAssertEqual(shelfRequest?.3, "shelf-test")
        XCTAssertEqual(removalRequest?.0, "com.example.Editor")
        XCTAssertEqual(removalRequest?.1, profileID)
        XCTAssertEqual(removalRequest?.2, .appRule)
        XCTAssertEqual(removalRequest?.3, "removal-test")
    }

    private func context(
        layout: WorkspaceLayout = .accordion,
        canSmartResize: Bool = true,
        validationToken: String = "palette-test",
        windowIdentifier: CGWindowID = 510
    ) -> RadialCommandContext {
        RadialCommandContext(
            focusedWindow: RadialFocusedWindowContext(
                processIdentifier: 410,
                windowIdentifier: windowIdentifier,
                workspaceID: focusID,
                frame: WindowFrame(
                    position: CGPoint(x: 100, y: 100),
                    size: CGSize(width: 900, height: 700)
                ),
                layoutState: .managed,
                isAutomaticallyFloatingDialog: false,
                isAppRuleExcluded: false,
                keepsOnAllWorkspaces: false
            ),
            focusSource: .focusedManagedWindow,
            workspaceID: focusID,
            workspaceName: "Focus",
            layout: layout,
            displayIdentifier: "display-1",
            displayName: "Studio Display",
            displayBounds: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            displayMode: .unified,
            focusFollowsMovedWindow: false,
            connectedDisplayIdentifiers: ["display-1"],
            connectedDisplays: [
                RadialDisplayOption(id: "display-1", name: "Studio Display", isMain: true),
            ],
            availableFocusDirections: [.left],
            availableMoveDirections: [.right],
            canSmartResize: canSmartResize,
            workspaces: [
                RadialWorkspaceOption(
                    id: focusID,
                    name: "Focus",
                    key: "f",
                    layout: .accordion,
                    homeDisplayIdentifier: "display-1"
                ),
                RadialWorkspaceOption(
                    id: writingID,
                    name: "Writing",
                    key: "w",
                    layout: .none,
                    homeDisplayIdentifier: "display-1"
                ),
            ],
            supportedCommands: RadialCommandCapability.current,
            validationToken: validationToken
        )
    }

    private func freeformPlacementContext(
        validationToken: String = "palette-test",
        windowIdentifier: CGWindowID = 510
    ) -> RadialCommandContext {
        var value = context(
            layout: .none,
            canSmartResize: false,
            validationToken: validationToken,
            windowIdentifier: windowIdentifier
        )
        let key = WindowKey(processIdentifier: 410, windowIdentifier: windowIdentifier)
        let originalFrame = WindowFrame(
            position: CGPoint(x: 100, y: 100),
            size: CGSize(width: 900, height: 700)
        )
        value.freeformPlacementPreviews = VisualPlacement.compassOrder.compactMap { placement in
            FreeformPlacementEngine.preview(
                focusedWindow: key,
                displayIdentifier: value.displayIdentifier,
                originalFrame: originalFrame,
                placement: placement,
                displayBounds: value.displayBounds
            )
        }
        return value
    }
}
