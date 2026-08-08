import XCTest

final class MenuBarPresentationTests: XCTestCase {
    private let workspace1 = WorkspaceDefinition(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
        name: "1",
        key: "1"
    )
    private let workspace2 = WorkspaceDefinition(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
        name: "Writing",
        key: "w"
    )
    private let workspace3 = WorkspaceDefinition(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
        name: "9",
        key: "9"
    )

    func testLegacyPresentationValuesMigrateToThreeModes() {
        XCTAssertEqual(MenuBarPresentationMode.migrated(from: "compact"), .compact)
        XCTAssertEqual(MenuBarPresentationMode.migrated(from: "icon-only"), .compact)
        XCTAssertEqual(MenuBarPresentationMode.migrated(from: "workspace-label"), .medium)
        XCTAssertEqual(MenuBarPresentationMode.migrated(from: "full-workspace-strip"), .full)
        XCTAssertEqual(MenuBarPresentationMode.migrated(from: "future-value"), .compact)
        XCTAssertEqual(MenuBarPresentationMode.migrated(from: nil), .compact)
    }

    @MainActor
    func testSettingsMigrationRewritesLegacyValueToCanonicalRawValue() {
        let cases: [(String, MenuBarPresentationMode)] = [
            ("compact", .compact),
            ("icon-only", .compact),
            ("workspace-label", .medium),
            ("full-workspace-strip", .full),
        ]
        for (legacy, expected) in cases {
            let suite = "MenuBarPresentationTests.\(legacy).\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(false, forKey: "iCloudSyncEnabled")
            defaults.set(legacy, forKey: "menuBarPresentationMode.v1")
            let store = SettingsStore(
                defaults: defaults,
                ubiquitousStore: nil,
                connectedDisplaysProvider: { [] }
            )
            XCTAssertEqual(store.menuBarPresentationMode, expected)
            XCTAssertEqual(defaults.string(forKey: "menuBarPresentationMode.v1"), expected.rawValue)
        }
    }

    @MainActor
    func testMenuBarModeMigratesAndPersistsThroughInjectedICloudStore() {
        let suite = "MenuBarPresentationTests.iCloud.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "iCloudSyncEnabled")
        let cloud = FakeUbiquitousKeyValueStore()
        cloud.set("workspace-label", forKey: "menuBarPresentationMode.v1")

        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: cloud,
            connectedDisplaysProvider: { [] }
        )

        XCTAssertEqual(store.menuBarPresentationMode, .medium)
        XCTAssertEqual(cloud.string(forKey: "menuBarPresentationMode.v1"), "medium")
        store.menuBarPresentationMode = .full
        XCTAssertEqual(defaults.string(forKey: "menuBarPresentationMode.v1"), "full")
        XCTAssertEqual(cloud.string(forKey: "menuBarPresentationMode.v1"), "full")
        XCTAssertGreaterThan(cloud.synchronizeCount, 0)
    }

    func testUnifiedModeUsesOneCombinedDisplaySignal() {
        let snapshot = MenuBarPresentationResolver.resolve(
            mode: .medium,
            displayMode: .unified,
            state: engineState(current: workspace2.id, active: [workspace2.id]),
            workspaces: [workspace1, workspace2, workspace3],
            connectedDisplays: [externalDisplay, mainDisplay],
            workspaceDisplayAssignments: [
                workspace1.id: mainDisplay.identifier,
                workspace2.id: externalDisplay.identifier,
            ]
        )

        XCTAssertEqual(snapshot.displays.count, 1)
        XCTAssertEqual(snapshot.displays[0].iconKind, .combined)
        XCTAssertEqual(snapshot.displays[0].name, "All Displays")
        XCTAssertEqual(snapshot.displays[0].activeWorkspaceID, workspace2.id)
        XCTAssertEqual(snapshot.displays[0].workspaces.map(\.id), [workspace1.id, workspace2.id, workspace3.id])
    }

    func testIndependentModeOrdersDisplaysAndShowsEachActiveWorkspace() {
        let snapshot = independentSnapshot(displays: [externalDisplay, mainDisplay])

        XCTAssertEqual(snapshot.displays.map(\.id), [mainDisplay.identifier, externalDisplay.identifier])
        XCTAssertEqual(snapshot.displays.map(\.activeWorkspaceID), [workspace1.id, workspace3.id])
        XCTAssertFalse(snapshot.displays[0].isInteractionDisplay)
        XCTAssertTrue(snapshot.displays[1].isInteractionDisplay)
        XCTAssertEqual(snapshot.displays[0].iconKind, .builtIn)
        XCTAssertEqual(snapshot.displays[1].iconKind, .external)
        XCTAssertEqual(snapshot.displays[0].workspaces.map(\.id), [workspace1.id, workspace2.id])
        XCTAssertEqual(snapshot.displays[1].workspaces.map(\.id), [workspace3.id])
    }

    func testThreeDisplaysRemainDeterministicAcrossInputReordering() {
        let third = DisplaySnapshot(
            identifier: "third-display",
            bounds: CGRect(x: 1_512, y: 0, width: 1_600, height: 900),
            isMain: false,
            name: "Projector"
        )
        let workspaces = [workspace1, workspace2, workspace3]
        let assignments = [
            workspace1.id: mainDisplay.identifier,
            workspace2.id: third.identifier,
            workspace3.id: externalDisplay.identifier,
        ]
        let state = WorkspaceEngineState(
            currentWorkspaceID: workspace2.id,
            activeWorkspaceIDs: [workspace1.id, workspace2.id, workspace3.id],
            previousWorkspaceID: nil,
            managedWindowCount: 0,
            accessibilityGranted: true,
            activeWorkspaceIDByDisplay: [
                mainDisplay.identifier: workspace1.id,
                externalDisplay.identifier: workspace3.id,
                third.identifier: workspace2.id,
            ]
        )
        let first = MenuBarPresentationResolver.resolve(
            mode: .compact,
            displayMode: .independent,
            state: state,
            workspaces: workspaces,
            connectedDisplays: [third, externalDisplay, mainDisplay],
            workspaceDisplayAssignments: assignments
        )
        let second = MenuBarPresentationResolver.resolve(
            mode: .compact,
            displayMode: .independent,
            state: state,
            workspaces: workspaces,
            connectedDisplays: [mainDisplay, third, externalDisplay],
            workspaceDisplayAssignments: assignments
        )

        XCTAssertEqual(first.displays.map(\.id), second.displays.map(\.id))
        XCTAssertEqual(first.displays.map(\.id), [mainDisplay.identifier, externalDisplay.identifier, third.identifier])
        XCTAssertEqual(first.displays.filter(\.isInteractionDisplay).map(\.id), [third.identifier])
    }

    func testDisconnectedHomeFallsBackVisiblyWithoutMutatingAssignmentAndReturnsOnReconnect() {
        let assignments = [workspace3.id: externalDisplay.identifier]
        let disconnected = MenuBarPresentationResolver.resolve(
            mode: .full,
            displayMode: .independent,
            state: engineState(
                current: workspace3.id,
                active: [workspace3.id],
                activeByDisplay: [mainDisplay.identifier: workspace3.id]
            ),
            workspaces: [workspace1, workspace3],
            connectedDisplays: [mainDisplay],
            workspaceDisplayAssignments: assignments
        )
        XCTAssertTrue(disconnected.displays[0].workspaces.contains(where: { $0.id == workspace3.id }))
        XCTAssertEqual(assignments[workspace3.id], externalDisplay.identifier)

        let reconnected = MenuBarPresentationResolver.resolve(
            mode: .full,
            displayMode: .independent,
            state: engineState(
                current: workspace3.id,
                active: [workspace1.id, workspace3.id],
                activeByDisplay: [
                    mainDisplay.identifier: workspace1.id,
                    externalDisplay.identifier: workspace3.id,
                ]
            ),
            workspaces: [workspace1, workspace3],
            connectedDisplays: [mainDisplay, externalDisplay],
            workspaceDisplayAssignments: assignments
        )
        XCTAssertEqual(
            reconnected.displays.first(where: { $0.id == externalDisplay.identifier })?.activeWorkspaceID,
            workspace3.id
        )
    }

    func testLongWorkspaceNamesAreVisuallyBoundedButAccessibleInFull() {
        let long = WorkspaceDefinition(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000099")!,
            name: "Very Long Research Workspace",
            key: "v"
        )
        let snapshot = MenuBarPresentationResolver.resolve(
            mode: .compact,
            displayMode: .unified,
            state: engineState(current: long.id, active: [long.id]),
            workspaces: [long],
            connectedDisplays: [mainDisplay],
            workspaceDisplayAssignments: [:]
        )

        XCTAssertEqual(snapshot.displays[0].activeWorkspaceCompactName, "Ve…")
        XCTAssertTrue(snapshot.primaryTooltip.contains(long.name))
        XCTAssertTrue(snapshot.primaryAccessibilityLabel.contains(long.name))
        XCTAssertFalse(snapshot.primaryAccessibilityLabel.contains(mainDisplay.identifier))
    }

    func testExtremePressureKeepsEveryDisplayActiveWorkspaceAndHidesInactiveItems() {
        let displays = (0..<4).map { index in
            DisplaySnapshot(
                identifier: "display-\(index)",
                bounds: CGRect(x: index * 1_200, y: 0, width: 1_200, height: 800),
                isMain: index == 0,
                isBuiltIn: index == 0,
                name: "Display \(index + 1)"
            )
        }
        let workspaces = (0..<20).map { index in
            WorkspaceDefinition(
                id: UUID(uuidString: String(format: "20000000-0000-0000-0000-%012d", index + 1))!,
                name: "Workspace \(index + 1)",
                key: "w\(index + 1)"
            )
        }
        let assignments = Dictionary(uniqueKeysWithValues: workspaces.enumerated().map {
            ($0.element.id, displays[$0.offset % displays.count].identifier)
        })
        let activeByDisplay = Dictionary(uniqueKeysWithValues: displays.enumerated().map {
            ($0.element.identifier, workspaces[$0.offset].id)
        })
        let snapshot = MenuBarPresentationResolver.resolve(
            mode: .full,
            displayMode: .independent,
            state: engineState(
                current: workspaces[3].id,
                active: Set(activeByDisplay.values),
                activeByDisplay: activeByDisplay
            ),
            workspaces: workspaces,
            connectedDisplays: displays,
            workspaceDisplayAssignments: assignments
        )
        let layout = MenuBarPressurePolicy.layout(displays: snapshot.displays, availableWidth: 220)

        XCTAssertEqual(layout.groups.count, displays.count)
        XCTAssertGreaterThan(layout.hiddenWorkspaceCount, 0)
        XCTAssertEqual(layout.labelStyle, .compact)
        for group in layout.groups {
            XCTAssertTrue(group.visibleWorkspaces.contains(where: \.isActive))
        }
        XCTAssertNotNil(layout.overflowSummary)
    }

    func testInformationalTargetsNeverRouteToWorkspaceSwitch() {
        XCTAssertEqual(MenuBarInteractionRouter.action(for: .primary), .openMenu)
        XCTAssertEqual(
            MenuBarInteractionRouter.action(for: .displayIndicator(externalDisplay.identifier)),
            .openMenu
        )
        XCTAssertEqual(
            MenuBarInteractionRouter.action(for: .workspace(
                workspaceID: workspace3.id,
                displayIdentifier: externalDisplay.identifier
            )),
            .switchWorkspace(
                workspaceID: workspace3.id,
                displayIdentifier: externalDisplay.identifier
            )
        )
    }

    @MainActor
    func testRapidModelUpdatesReplaceStateWithoutRetainingStaleDisplayOrder() {
        let model = MenuBarStateModel(
            workspaces: [workspace1, workspace2, workspace3],
            displayMode: .independent,
            connectedDisplays: [mainDisplay, externalDisplay],
            workspaceDisplayAssignments: [
                workspace1.id: mainDisplay.identifier,
                workspace2.id: mainDisplay.identifier,
                workspace3.id: externalDisplay.identifier,
            ]
        )
        model.update(
            state: engineState(
                current: workspace3.id,
                active: [workspace1.id, workspace3.id],
                activeByDisplay: [
                    mainDisplay.identifier: workspace1.id,
                    externalDisplay.identifier: workspace3.id,
                ]
            ),
            workspaces: [workspace1, workspace2, workspace3]
        )
        model.update(
            state: engineState(
                current: workspace2.id,
                active: [workspace2.id, workspace3.id],
                activeByDisplay: [
                    mainDisplay.identifier: workspace2.id,
                    externalDisplay.identifier: workspace3.id,
                ]
            ),
            workspaces: [workspace1, workspace2, workspace3]
        )

        let snapshot = model.presentation(for: .medium)
        XCTAssertEqual(snapshot.displays.map(\.id), [mainDisplay.identifier, externalDisplay.identifier])
        XCTAssertEqual(snapshot.displays.first?.activeWorkspaceID, workspace2.id)
        XCTAssertTrue(snapshot.displays.first?.isInteractionDisplay == true)
    }

    private var mainDisplay: DisplaySnapshot {
        DisplaySnapshot(
            identifier: "main-display",
            bounds: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            isMain: true,
            isBuiltIn: true,
            name: "Built-in Display"
        )
    }

    private var externalDisplay: DisplaySnapshot {
        DisplaySnapshot(
            identifier: "external-display",
            bounds: CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080),
            isMain: false,
            name: "Studio Display"
        )
    }

    private func engineState(
        current: UUID,
        active: Set<UUID>,
        activeByDisplay: [String: UUID] = [:]
    ) -> WorkspaceEngineState {
        WorkspaceEngineState(
            currentWorkspaceID: current,
            activeWorkspaceIDs: active,
            previousWorkspaceID: nil,
            managedWindowCount: 0,
            accessibilityGranted: true,
            activeWorkspaceIDByDisplay: activeByDisplay
        )
    }

    private func independentSnapshot(displays: [DisplaySnapshot]) -> MenuBarPresentationSnapshot {
        MenuBarPresentationResolver.resolve(
            mode: .medium,
            displayMode: .independent,
            state: engineState(
                current: workspace3.id,
                active: [workspace1.id, workspace3.id],
                activeByDisplay: [
                    mainDisplay.identifier: workspace1.id,
                    externalDisplay.identifier: workspace3.id,
                ]
            ),
            workspaces: [workspace1, workspace2, workspace3],
            connectedDisplays: displays,
            workspaceDisplayAssignments: [
                workspace1.id: mainDisplay.identifier,
                workspace2.id: mainDisplay.identifier,
                workspace3.id: externalDisplay.identifier,
            ]
        )
    }
}

private final class FakeUbiquitousKeyValueStore: UbiquitousKeyValueStoring {
    private var values: [String: Any] = [:]
    private(set) var synchronizeCount = 0
    var notificationObject: AnyObject { self }

    func object(forKey aKey: String) -> Any? { values[aKey] }
    func string(forKey aKey: String) -> String? { values[aKey] as? String }
    func data(forKey aKey: String) -> Data? { values[aKey] as? Data }

    func set(_ anObject: Any?, forKey aKey: String) {
        values[aKey] = anObject
    }

    func removeObject(forKey aKey: String) { values.removeValue(forKey: aKey) }

    func synchronize() -> Bool {
        synchronizeCount += 1
        return true
    }
}
