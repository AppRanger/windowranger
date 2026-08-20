import XCTest

final class CommandPaletteTests: XCTestCase {
    private let focusID = UUID(uuidString: "81000000-0000-0000-0000-000000000001")!
    private let writingID = UUID(uuidString: "81000000-0000-0000-0000-000000000002")!

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

        XCTAssertEqual(
            entries.first { $0.destination == .command(.cycleWindow(1)) }?.shortcut,
            HotKeyConfiguration().chord(for: .nextWindow).title
        )
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

    private func context(
        layout: WorkspaceLayout = .accordion,
        canSmartResize: Bool = true
    ) -> RadialCommandContext {
        RadialCommandContext(
            focusedWindow: RadialFocusedWindowContext(
                processIdentifier: 410,
                windowIdentifier: 510,
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
            validationToken: "palette-test"
        )
    }

    private func freeformPlacementContext() -> RadialCommandContext {
        var value = context(layout: .none, canSmartResize: false)
        let key = WindowKey(processIdentifier: 410, windowIdentifier: 510)
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
