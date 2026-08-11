import AppKit
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

    func testHighlightColourNormalizesHexAndDerivesReadableForeground() {
        XCTAssertEqual(MenuBarHighlightColor(hex: "ffffff"), .default)
        XCTAssertEqual(MenuBarHighlightColor(hex: "#0A80FF")?.hex, "#0A80FF")
        XCTAssertNil(MenuBarHighlightColor(hex: "not-a-colour"))
        XCTAssertTrue(MenuBarHighlightColor.default.usesDarkForeground)
        XCTAssertFalse(MenuBarHighlightColor(red: 0, green: 0, blue: 0).usesDarkForeground)
    }

    func testDisplayIconStylesResolveWithoutChangingHardwareIdentity() {
        XCTAssertEqual(
            MenuBarDisplayIconStyle.automatic.systemImage(for: .builtIn),
            "laptopcomputer"
        )
        XCTAssertEqual(
            MenuBarDisplayIconStyle.automatic.systemImage(for: .combined),
            "display.2"
        )
        XCTAssertEqual(
            MenuBarDisplayIconStyle.automatic.systemImage(
                for: .builtIn,
                automaticSystemImage: "display"
            ),
            "display"
        )
        XCTAssertEqual(
            MenuBarDisplayIconStyle.horizontalMonitor.systemImage(for: .builtIn),
            "display"
        )
        XCTAssertEqual(
            MenuBarDisplayIconStyle.verticalMonitor.systemImage(for: .external),
            "rectangle.portrait"
        )
        XCTAssertEqual(
            MenuBarDisplayIconStyle.laptop.systemImage(for: .combined),
            "laptopcomputer"
        )
        XCTAssertNil(MenuBarDisplayIconStyle.none.systemImage(for: .external))
    }

    func testProfileDisplayIconFollowsConservativePhysicalDisplayIdentity() {
        let fingerprint = DisplayFingerprint(
            displayUUID: "stable-panel-uuid",
            vendorID: 10,
            modelID: 20,
            serialNumber: "panel-123",
            displayName: "Portrait Display",
            widthPoints: 1_080,
            heightPoints: 1_920
        )
        let reconnected = DisplaySnapshot(
            identifier: "new-runtime-identifier",
            bounds: CGRect(x: 1_512, y: 0, width: 1_080, height: 1_920),
            isMain: false,
            name: "Portrait Display",
            fingerprint: fingerprint
        )
        let role = ProfileDisplayRole(
            name: "Portrait",
            menuBarIconStyle: .verticalMonitor
        )
        let profile = WindowManagerProfile(
            name: "Desk",
            workspaces: [workspace1],
            displayMode: .independent,
            displayRoles: [role],
            workspaceRoleAssignments: [workspace1.id: role.id],
            appRules: []
        )
        let configuration = MenuBarProfileDisplayIconResolver.configuration(
            profile: profile,
            roleBindings: [
                role.id: WorkspaceDisplayPin(
                    lastKnownIdentifier: "old-runtime-identifier",
                    fingerprint: fingerprint
                ),
            ],
            displays: [reconnected]
        )

        XCTAssertEqual(
            configuration.stylesByDisplayIdentifier[reconnected.identifier],
            .verticalMonitor
        )
    }

    func testDisplayIconConfigurationResolvesEachDisplayIndependently() {
        let snapshot = independentSnapshot(displays: [externalDisplay, mainDisplay])
        let configuration = MenuBarDisplayIconConfiguration(
            stylesByDisplayIdentifier: [
                mainDisplay.identifier: .laptop,
                externalDisplay.identifier: .verticalMonitor,
            ]
        )

        XCTAssertEqual(configuration.systemImage(for: snapshot.displays[0]), "laptopcomputer")
        XCTAssertEqual(configuration.systemImage(for: snapshot.displays[1]), "rectangle.portrait")
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
        cloud.set("key", forKey: "menuBarWorkspaceLabelMode.v1")
        cloud.set("#FF7A00", forKey: "menuBarHighlightColor.v1")

        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: cloud,
            connectedDisplaysProvider: { [] }
        )

        XCTAssertEqual(store.menuBarPresentationMode, .medium)
        XCTAssertEqual(store.menuBarWorkspaceLabelMode, .key)
        XCTAssertEqual(store.menuBarHighlightColor.hex, "#FF7A00")
        XCTAssertEqual(cloud.string(forKey: "menuBarPresentationMode.v1"), "medium")
        XCTAssertEqual(cloud.string(forKey: "menuBarWorkspaceLabelMode.v1"), "key")
        XCTAssertEqual(cloud.string(forKey: "menuBarHighlightColor.v1"), "#FF7A00")
        store.menuBarPresentationMode = .full
        store.menuBarWorkspaceLabelMode = .name
        store.menuBarHighlightColor = MenuBarHighlightColor(red: 0, green: 0.5, blue: 1)
        XCTAssertEqual(defaults.string(forKey: "menuBarPresentationMode.v1"), "full")
        XCTAssertEqual(cloud.string(forKey: "menuBarPresentationMode.v1"), "full")
        XCTAssertEqual(defaults.string(forKey: "menuBarWorkspaceLabelMode.v1"), "name")
        XCTAssertEqual(cloud.string(forKey: "menuBarWorkspaceLabelMode.v1"), "name")
        XCTAssertEqual(defaults.string(forKey: "menuBarHighlightColor.v1"), "#0080FF")
        XCTAssertEqual(cloud.string(forKey: "menuBarHighlightColor.v1"), "#0080FF")
        XCTAssertGreaterThan(cloud.synchronizeCount, 0)
    }

    @MainActor
    func testMenuBarHighlightDefaultsToWhiteAndPersistsLocally() {
        let suite = "MenuBarHighlightTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "iCloudSyncEnabled")

        let writer = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] }
        )
        XCTAssertEqual(writer.menuBarHighlightColor, .default)
        XCTAssertEqual(defaults.string(forKey: "menuBarHighlightColor.v1"), "#FFFFFF")
        writer.menuBarHighlightColor = MenuBarHighlightColor(red: 0.2, green: 0.4, blue: 0.6)

        let reader = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] }
        )
        XCTAssertEqual(reader.menuBarHighlightColor.hex, "#336699")
    }

    @MainActor
    func testMenuBarWorkspaceLabelsDefaultToNamesAndPersistLocally() {
        let suite = "MenuBarWorkspaceLabelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "iCloudSyncEnabled")

        let writer = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] }
        )
        XCTAssertEqual(writer.menuBarWorkspaceLabelMode, .name)
        XCTAssertEqual(defaults.string(forKey: "menuBarWorkspaceLabelMode.v1"), "name")
        writer.menuBarWorkspaceLabelMode = .key

        let reader = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] }
        )
        XCTAssertEqual(reader.menuBarWorkspaceLabelMode, .key)
    }

    @MainActor
    func testMenuBarDisplayIconsBelongToProfilesAndPersistThroughICloud() throws {
        let suite = "MenuBarDisplayIconTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "iCloudSyncEnabled")

        let cloud = FakeUbiquitousKeyValueStore()
        let writer = SettingsStore(
            defaults: defaults,
            ubiquitousStore: cloud,
            connectedDisplaysProvider: { [self.mainDisplay, self.externalDisplay] }
        )
        let mainRoleID = try XCTUnwrap(writer.roleBindings.first(where: {
            $0.value.lastKnownIdentifier == self.mainDisplay.identifier
        })?.key)
        let externalRoleID = try XCTUnwrap(writer.roleBindings.first(where: {
            $0.value.lastKnownIdentifier == self.externalDisplay.identifier
        })?.key)
        XCTAssertEqual(writer.menuBarDisplayIconStyle(forRole: mainRoleID), .automatic)
        XCTAssertEqual(writer.menuBarDisplayIconStyle(forRole: externalRoleID), .automatic)
        writer.setMenuBarDisplayIconStyle(.laptop, forRole: mainRoleID)
        writer.setMenuBarDisplayIconStyle(.verticalMonitor, forRole: externalRoleID)

        let sourceProfileID = writer.activeProfileID
        let travelProfileID = try XCTUnwrap(
            writer.createProfile(named: "Travel", source: .scratch)
        )
        let travelRoleID = try XCTUnwrap(writer.activeProfile.displayRoles.first?.id)
        XCTAssertEqual(writer.menuBarDisplayIconStyle(forRole: travelRoleID), .automatic)
        writer.setMenuBarDisplayIconStyle(.none, forRole: travelRoleID)
        XCTAssertEqual(
            writer.menuBarDisplayIconConfiguration
                .stylesByDisplayIdentifier[mainDisplay.identifier],
            MenuBarDisplayIconStyle.none
        )
        writer.selectProfile(sourceProfileID)
        XCTAssertEqual(writer.menuBarDisplayIconStyle(forRole: mainRoleID), .laptop)
        XCTAssertEqual(writer.menuBarDisplayIconStyle(forRole: externalRoleID), .verticalMonitor)
        XCTAssertEqual(
            writer.menuBarDisplayIconConfiguration.stylesByDisplayIdentifier,
            [
                mainDisplay.identifier: .laptop,
                externalDisplay.identifier: .verticalMonitor,
            ]
        )

        let cloudData = try XCTUnwrap(cloud.data(forKey: "profileLibrary.v1"))
        let cloudLibrary = try JSONDecoder().decode(ProfileLibrary.self, from: cloudData)
        XCTAssertEqual(
            cloudLibrary.profiles.first(where: { $0.id == sourceProfileID })?
                .displayRoles.first(where: { $0.id == mainRoleID })?.menuBarIconStyle,
            .laptop
        )
        XCTAssertEqual(
            cloudLibrary.profiles.first(where: { $0.id == travelProfileID })?
                .displayRoles.first?.menuBarIconStyle,
            MenuBarDisplayIconStyle.none
        )
        let reader = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [self.mainDisplay, self.externalDisplay] }
        )
        XCTAssertEqual(reader.menuBarDisplayIconStyle(forRole: mainRoleID), .laptop)
        XCTAssertEqual(reader.menuBarDisplayIconStyle(forRole: externalRoleID), .verticalMonitor)
        XCTAssertEqual(
            reader.profiles.first(where: { $0.id == travelProfileID })?
                .displayRoles.first?.menuBarIconStyle,
            MenuBarDisplayIconStyle.none
        )
    }

    func testDuplicateProfileDisplayRoleIconsFallBackToAutomatic() {
        let firstRole = ProfileDisplayRole(name: "First", menuBarIconStyle: .laptop)
        let secondRole = ProfileDisplayRole(name: "Second", menuBarIconStyle: .none)
        let profile = WindowManagerProfile(
            name: "Ambiguous",
            workspaces: [workspace1],
            displayMode: .independent,
            displayRoles: [firstRole, secondRole],
            workspaceRoleAssignments: [workspace1.id: firstRole.id],
            appRules: []
        )
        let pin = WorkspaceDisplayPin(
            lastKnownIdentifier: mainDisplay.identifier,
            fingerprint: mainDisplay.fingerprint
        )

        let configuration = MenuBarProfileDisplayIconResolver.configuration(
            profile: profile,
            roleBindings: [firstRole.id: pin, secondRole.id: pin],
            displays: [mainDisplay]
        )

        XCTAssertEqual(configuration.stylesByDisplayIdentifier, [:])
    }

    func testLegacyDisplayRoleDecodesWithAutomaticIconStyle() throws {
        let id = UUID()
        let data = Data("{\"id\":\"\(id.uuidString)\",\"name\":\"Desk\"}".utf8)

        let role = try JSONDecoder().decode(ProfileDisplayRole.self, from: data)

        XCTAssertEqual(role, ProfileDisplayRole(id: id, name: "Desk"))
        XCTAssertEqual(role.menuBarIconStyle, .automatic)
    }

    @MainActor
    func testWorkspaceKeyLabelsRenderWithoutReplacingFullAccessibilityNames() {
        let snapshot = MenuBarPresentationResolver.resolve(
            mode: .full,
            workspaceLabelMode: .key,
            displayMode: .unified,
            state: engineState(current: workspace2.id, active: [workspace2.id]),
            workspaces: [workspace1, workspace2, workspace3],
            connectedDisplays: [mainDisplay],
            workspaceDisplayAssignments: [:]
        )
        let content = MenuBarStatusContentView(
            snapshot: snapshot,
            availableWidth: 620,
            workspaceAction: nil
        )

        layout(content)
        XCTAssertEqual(Set(workspaceButtons(in: content).map(\.title)), Set(["1", "W", "9"]))
        XCTAssertEqual(
            snapshot.displays[0].activeWorkspaceLabel(mode: .key),
            "W"
        )
        XCTAssertTrue(snapshot.primaryTooltip.contains(workspace2.name))
        XCTAssertTrue(snapshot.primaryAccessibilityLabel.contains(workspace2.name))
        XCTAssertEqual(MenuBarWorkspaceLabelFormatter.key(""), "—")
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
        var displays: [DisplaySnapshot] = []
        for index in 0..<4 {
            displays.append(DisplaySnapshot(
                identifier: "display-\(index)",
                bounds: CGRect(x: CGFloat(index * 1_200), y: 0, width: 1_200, height: 800),
                isMain: index == 0,
                isBuiltIn: index == 0,
                name: "Display \(index + 1)"
            ))
        }
        var workspaces: [WorkspaceDefinition] = []
        for index in 0..<20 {
            workspaces.append(WorkspaceDefinition(
                id: UUID(uuidString: String(format: "20000000-0000-0000-0000-%012d", index + 1))!,
                name: "Workspace \(index + 1)",
                key: "w\(index + 1)"
            ))
        }
        var assignments: [UUID: String] = [:]
        for (index, workspace) in workspaces.enumerated() {
            assignments[workspace.id] = displays[index % displays.count].identifier
        }
        var activeByDisplay: [String: UUID] = [:]
        for (index, display) in displays.enumerated() {
            activeByDisplay[display.identifier] = workspaces[index].id
        }
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
            XCTAssertTrue(group.visibleWorkspaces.contains { workspace in workspace.isActive })
        }
        XCTAssertNotNil(layout.overflowSummary)
    }

    func testDisplayGroupStatusItemsAreLimitedToFullModeOnMacOS27AndLater() {
        let macOS26 = OperatingSystemVersion(majorVersion: 26, minorVersion: 6, patchVersion: 0)
        let macOS27 = OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)
        let macOS28 = OperatingSystemVersion(majorVersion: 28, minorVersion: 0, patchVersion: 0)

        XCTAssertFalse(MenuBarStatusItemCompositionPolicy.usesDisplayGroups(
            for: .full,
            operatingSystemVersion: macOS26
        ))
        XCTAssertFalse(MenuBarStatusItemCompositionPolicy.usesDisplayGroups(
            for: .compact,
            operatingSystemVersion: macOS27
        ))
        XCTAssertFalse(MenuBarStatusItemCompositionPolicy.usesDisplayGroups(
            for: .medium,
            operatingSystemVersion: macOS27
        ))
        XCTAssertTrue(MenuBarStatusItemCompositionPolicy.usesDisplayGroups(
            for: .full,
            operatingSystemVersion: macOS27
        ))
        XCTAssertTrue(MenuBarStatusItemCompositionPolicy.usesDisplayGroups(
            for: .full,
            operatingSystemVersion: macOS28
        ))
    }

    func testDisplayGroupStatusItemActivationSeparatesPointerAndMenuActions() {
        XCTAssertFalse(MenuBarStatusItemActivationPolicy.opensMenu(
            eventType: .leftMouseUp,
            modifierFlags: []
        ))
        XCTAssertTrue(MenuBarStatusItemActivationPolicy.opensMenu(
            eventType: .rightMouseDown,
            modifierFlags: []
        ))
        XCTAssertTrue(MenuBarStatusItemActivationPolicy.opensMenu(
            eventType: .rightMouseUp,
            modifierFlags: []
        ))
        XCTAssertTrue(MenuBarStatusItemActivationPolicy.opensMenu(
            eventType: .leftMouseUp,
            modifierFlags: .control
        ))
        XCTAssertTrue(MenuBarStatusItemActivationPolicy.opensMenu(
            eventType: nil,
            modifierFlags: []
        ))
    }

    func testDisplayGroupStatusItemPlanKeepsOneMovableItemPerDisplay() {
        let snapshot = independentSnapshot(displays: [mainDisplay, externalDisplay])
            .replacingMode(.full)
        let groups = MenuBarDisplayGroupStatusItemPlanner.groups(
            for: snapshot,
            availableWidth: 620
        )

        XCTAssertEqual(groups.map(\.group.display.id), [
            mainDisplay.identifier,
            externalDisplay.identifier,
        ])
        XCTAssertEqual(groups[0].group.visibleWorkspaces.map(\.id), [workspace1.id, workspace2.id])
        XCTAssertEqual(groups[1].group.visibleWorkspaces.map(\.id), [workspace3.id])
        XCTAssertTrue(groups.allSatisfy { $0.overflowCount == 0 })
        XCTAssertEqual(
            MenuBarDisplayGroupStatusItemPlanner.configurationOrder(for: groups)
                .map(\.group.display.id),
            groups.reversed().map(\.group.display.id)
        )
    }

    func testDisplayGroupStatusItemPlanCarriesPressureOverflowInLastGroup() {
        let workspaces = (0..<20).map { index in
            WorkspaceDefinition(
                id: UUID(uuidString: String(format: "30000000-0000-0000-0000-%012d", index + 1))!,
                name: "Workspace \(index + 1)",
                key: "w\(index + 1)"
            )
        }
        let snapshot = MenuBarPresentationResolver.resolve(
            mode: .full,
            displayMode: .unified,
            state: engineState(current: workspaces[0].id, active: [workspaces[0].id]),
            workspaces: workspaces,
            connectedDisplays: [mainDisplay],
            workspaceDisplayAssignments: [:]
        )
        let groups = MenuBarDisplayGroupStatusItemPlanner.groups(for: snapshot, availableWidth: 220)
        let overflowGroup = groups.last

        XCTAssertGreaterThan(overflowGroup?.overflowCount ?? 0, 0)
        XCTAssertTrue(overflowGroup?.overflowSummary?.contains("more workspace") == true)
    }

    func testScreenSpaceTargetResolverUsesGlobalSegmentFramesWithoutGuessingGaps() {
        let targets = [
            MenuBarScreenSpaceTarget(
                frame: CGRect(x: 100, y: 900, width: 30, height: 22),
                hitTarget: .workspace(
                    workspaceID: workspace1.id,
                    displayIdentifier: mainDisplay.identifier
                )
            ),
            MenuBarScreenSpaceTarget(
                frame: CGRect(x: 132, y: 900, width: 30, height: 22),
                hitTarget: .workspace(
                    workspaceID: workspace2.id,
                    displayIdentifier: mainDisplay.identifier
                )
            ),
        ]

        XCTAssertEqual(
            MenuBarScreenSpaceTargetResolver.target(
                at: CGPoint(x: 145, y: -500),
                among: targets
            ),
            .workspace(workspaceID: workspace2.id, displayIdentifier: mainDisplay.identifier)
        )
        XCTAssertNil(MenuBarScreenSpaceTargetResolver.target(
            at: CGPoint(x: 131, y: 910),
            among: targets
        ))
    }

    func testWorkspaceHoverStateTracksOnlyWorkspaceSegmentsAndClearsAtGapsAndExit() {
        let firstTarget = MenuBarHitTarget.workspace(
            workspaceID: workspace1.id,
            displayIdentifier: mainDisplay.identifier
        )
        let secondTarget = MenuBarHitTarget.workspace(
            workspaceID: workspace2.id,
            displayIdentifier: mainDisplay.identifier
        )
        let targets = [
            MenuBarScreenSpaceTarget(
                frame: CGRect(x: 100, y: 900, width: 30, height: 22),
                hitTarget: firstTarget
            ),
            MenuBarScreenSpaceTarget(
                frame: CGRect(x: 132, y: 900, width: 30, height: 22),
                hitTarget: secondTarget
            ),
        ]
        var state = MenuBarWorkspaceHoverState()

        XCTAssertTrue(state.update(pointer: CGPoint(x: 115, y: -500), among: targets))
        XCTAssertEqual(state.target, firstTarget)
        XCTAssertFalse(state.update(pointer: CGPoint(x: 115, y: 1_500), among: targets))
        XCTAssertTrue(state.update(pointer: CGPoint(x: 145, y: -500), among: targets))
        XCTAssertEqual(state.target, secondTarget)
        XCTAssertTrue(state.update(pointer: CGPoint(x: 131, y: 910), among: targets))
        XCTAssertNil(state.target)
        XCTAssertFalse(state.update(pointer: nil, among: targets))

        XCTAssertFalse(state.update(
            pointer: CGPoint(x: 5, y: 5),
            among: [MenuBarScreenSpaceTarget(
                frame: CGRect(x: 0, y: 0, width: 10, height: 10),
                hitTarget: .displayIndicator(mainDisplay.identifier)
            )]
        ))
        XCTAssertNil(state.target)
    }

    func testApplicationShelfGeometryAnchorsBelowWorkspaceAndClampsToVisibleScreen() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_000, height: 700)
        let centered = MenuBarApplicationShelfGeometry.frame(
            anchor: CGRect(x: 480, y: 700, width: 30, height: 22),
            contentSize: CGSize(width: 240, height: 180),
            visibleFrame: visibleFrame
        )
        XCTAssertEqual(centered.midX, 495, accuracy: 0.001)
        XCTAssertEqual(centered.maxY, 692, accuracy: 0.001)

        let rightEdge = MenuBarApplicationShelfGeometry.frame(
            anchor: CGRect(x: 990, y: 700, width: 20, height: 22),
            contentSize: CGSize(width: 240, height: 180),
            visibleFrame: visibleFrame
        )
        XCTAssertEqual(rightEdge.maxX, visibleFrame.maxX - 8, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(rightEdge.minY, visibleFrame.minY + 8)
    }

    func testApplicationShelfRestoresHoverBeforeItsDismissalGraceExpires() {
        XCTAssertGreaterThan(MenuBarApplicationShelfTiming.dwell, 0)
        XCTAssertGreaterThan(MenuBarApplicationShelfTiming.hoverRestorationDelay, 0)
        XCTAssertLessThan(
            MenuBarApplicationShelfTiming.hoverRestorationDelay,
            MenuBarApplicationShelfTiming.dismissalGrace
        )
    }

    @MainActor
    func testApplicationShelfUsesNativeGlassAndInstallsContent() throws {
        let frame = CGRect(x: 0, y: 0, width: 240, height: 100)
        let surface = MenuBarApplicationShelfSurfaceFactory.make(frame: frame)
        let content = NSView(frame: frame)
        MenuBarApplicationShelfSurfaceFactory.installContent(content, in: surface)

        if #available(macOS 26.0, *) {
            let glass = try XCTUnwrap(surface as? NSGlassEffectView)
            XCTAssertEqual(glass.style, .regular)
            XCTAssertEqual(glass.cornerRadius, MenuBarApplicationShelfSurfaceFactory.cornerRadius)
            XCTAssertTrue(glass.contentView === content)
        } else {
            let material = try XCTUnwrap(surface as? NSVisualEffectView)
            XCTAssertEqual(material.material, .menu)
            XCTAssertTrue(content.superview === material)
        }
    }

    @MainActor
    func testApplicationShelfConfiguresEmptyAndPopulatedStatesAfterJoiningViewHierarchy() {
        let content = MenuBarApplicationShelfContentView(frame: .zero)
        content.configure(
            workspaceName: "Empty",
            applications: [],
            imageProvider: { _ in nil },
            onSelect: { _ in }
        )
        layout(content)
        XCTAssertFalse(content.usesVerticalScroller)
        XCTAssertTrue(textFields(in: content).contains {
            $0.stringValue == "No apps in this workspace"
        })

        let application = WorkspaceApplicationSummary(
            id: "chrome",
            target: WorkspaceApplicationTarget(
                workspaceID: workspace1.id,
                bundleIdentifier: "com.google.Chrome",
                processIdentifier: 123
            ),
            name: "Chrome",
            windowCount: 2,
            applicationURL: nil
        )
        content.configure(
            workspaceName: "Writing",
            applications: [application],
            imageProvider: { _ in nil },
            onSelect: { _ in }
        )
        layout(content)
        XCTAssertFalse(content.usesVerticalScroller)
        XCTAssertTrue(workspaceButtons(in: content).contains {
            $0.title.contains("Chrome") && $0.title.contains("2")
        })

        content.configure(
            workspaceName: "Empty again",
            applications: [],
            imageProvider: { _ in nil },
            onSelect: { _ in }
        )
        layout(content)
        XCTAssertFalse(content.usesVerticalScroller)
        XCTAssertTrue(textFields(in: content).contains {
            $0.stringValue == "No apps in this workspace"
        })

        let overflow = (0..<9).map { index in
            WorkspaceApplicationSummary(
                id: "app-\(index)",
                target: WorkspaceApplicationTarget(
                    workspaceID: workspace1.id,
                    bundleIdentifier: "com.example.app\(index)",
                    processIdentifier: pid_t(200 + index)
                ),
                name: "App \(index)",
                windowCount: 1,
                applicationURL: nil
            )
        }
        content.configure(
            workspaceName: "Overflow",
            applications: overflow,
            imageProvider: { _ in nil },
            onSelect: { _ in }
        )
        layout(content)
        XCTAssertTrue(content.usesVerticalScroller)
    }

    @MainActor
    func testDisplayGroupContentNeverClaimsTheParentStatusButtonsPointerHit() throws {
        let snapshot = independentSnapshot(displays: [mainDisplay]).replacingMode(.full)
        let plan = try XCTUnwrap(MenuBarDisplayGroupStatusItemPlanner.groups(
            for: snapshot,
            availableWidth: 620
        ).first)
        let content = MenuBarDisplayGroupContentView(
            plan: plan,
            workspaceLabelMode: snapshot.workspaceLabelMode,
            highlightColor: .default
        )
        layout(content)

        XCTAssertGreaterThan(content.intrinsicContentSize.width, 24)
        let trackingRegions = content.workspaceTrackingRegions(in: content)
        XCTAssertEqual(trackingRegions.count, plan.group.visibleWorkspaces.count)
        XCTAssertEqual(
            trackingRegions.map(\.hitTarget),
            plan.group.visibleWorkspaces.map {
                .workspace(workspaceID: $0.id, displayIdentifier: plan.group.display.id)
            }
        )
        XCTAssertTrue(trackingRegions.allSatisfy { !$0.frame.isEmpty })
        XCTAssertNil(content.hitTest(NSPoint(
            x: content.bounds.midX,
            y: content.bounds.midY
        )))
    }

    @MainActor
    func testHiddenDisplayIconRemovesImageAndReclaimsGroupWidth() throws {
        let snapshot = independentSnapshot(displays: [mainDisplay]).replacingMode(.full)
        let hiddenConfiguration = MenuBarDisplayIconConfiguration(
            stylesByDisplayIdentifier: [mainDisplay.identifier: .none]
        )
        let automaticPlan = try XCTUnwrap(MenuBarDisplayGroupStatusItemPlanner.groups(
            for: snapshot,
            availableWidth: 620,
            displayIconConfiguration: .automatic
        ).first)
        let hiddenPlan = try XCTUnwrap(MenuBarDisplayGroupStatusItemPlanner.groups(
            for: snapshot,
            availableWidth: 620,
            displayIconConfiguration: hiddenConfiguration
        ).first)
        let automatic = MenuBarDisplayGroupContentView(
            plan: automaticPlan,
            workspaceLabelMode: snapshot.workspaceLabelMode,
            highlightColor: .default,
            displayIconConfiguration: .automatic
        )
        let hidden = MenuBarDisplayGroupContentView(
            plan: hiddenPlan,
            workspaceLabelMode: snapshot.workspaceLabelMode,
            highlightColor: .default,
            displayIconConfiguration: hiddenConfiguration
        )
        layout(automatic)
        layout(hidden)

        XCTAssertEqual(imageViews(in: automatic).count, 1)
        XCTAssertTrue(imageViews(in: hidden).isEmpty)
        XCTAssertEqual(
            automatic.intrinsicContentSize.width - hidden.intrinsicContentSize.width,
            MenuBarVisualTokens.displayIconWidth + MenuBarVisualTokens.displayWorkspaceGap,
            accuracy: 1
        )
        XCTAssertEqual(
            hidden.workspaceTrackingRegions(in: hidden).map(\.hitTarget),
            automatic.workspaceTrackingRegions(in: automatic).map(\.hitTarget)
        )
    }

    @MainActor
    func testHiddenDisplayIconReclaimsCompactMediumAndFullStripWidth() {
        let hiddenConfiguration = MenuBarDisplayIconConfiguration(
            stylesByDisplayIdentifier: [mainDisplay.identifier: .none]
        )
        for mode in [MenuBarPresentationMode.compact, .medium] {
            let snapshot = independentSnapshot(displays: [mainDisplay]).replacingMode(mode)
            let automatic = MenuBarStatusContentView(
                snapshot: snapshot,
                availableWidth: 620,
                displayIconConfiguration: .automatic,
                workspaceAction: nil
            )
            let hidden = MenuBarStatusContentView(
                snapshot: snapshot,
                availableWidth: 620,
                displayIconConfiguration: hiddenConfiguration,
                workspaceAction: nil
            )
            layout(automatic)
            layout(hidden)

            XCTAssertLessThan(
                hidden.intrinsicContentSize.width,
                automatic.intrinsicContentSize.width,
                "\(mode.title) should reclaim the hidden icon width"
            )
        }

        let snapshot = independentSnapshot(displays: [mainDisplay]).replacingMode(.full)
        let automatic = MenuBarFullStripView(
            snapshot: snapshot,
            availableWidth: 620,
            displayIconConfiguration: .automatic,
            workspaceAction: nil
        )
        let hidden = MenuBarFullStripView(
            snapshot: snapshot,
            availableWidth: 620,
            displayIconConfiguration: hiddenConfiguration,
            workspaceAction: nil
        )
        layout(automatic)
        layout(hidden)

        XCTAssertLessThan(hidden.intrinsicContentSize.width, automatic.intrinsicContentSize.width)
        XCTAssertEqual(
            workspaceButtons(in: hidden).map(\.title),
            workspaceButtons(in: automatic).map(\.title)
        )
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
    func testStableStatusContentTransitionsRemoveAndRestoreOnlyExplicitWorkspaceButtons() {
        let medium = independentSnapshot(displays: [mainDisplay, externalDisplay])
        let full = medium.replacingMode(.full)
        let compact = medium.replacingMode(.compact)
        var actions: [MenuBarHitTarget] = []
        let content = MenuBarStatusContentView(
            snapshot: full,
            availableWidth: 620,
            workspaceAction: { actions.append($0) }
        )
        let originalIdentity = ObjectIdentifier(content)

        layout(content)
        let fullButtons = workspaceButtons(in: content)
        XCTAssertEqual(Set(fullButtons.map(\.title)), Set(["1", "Writing", "9"]))
        XCTAssertNil(content.hitTest(NSPoint(x: 2, y: content.bounds.midY)))
        for button in fullButtons {
            let point = content.convert(
                NSPoint(x: button.bounds.midX, y: button.bounds.midY),
                from: button
            )
            XCTAssertTrue(content.hitTest(point) === button)
        }

        content.configure(snapshot: medium, availableWidth: 620, workspaceAction: { actions.append($0) })
        layout(content)
        XCTAssertEqual(ObjectIdentifier(content), originalIdentity)
        XCTAssertTrue(workspaceButtons(in: content).isEmpty)
        XCTAssertNil(content.hitTest(NSPoint(x: content.bounds.midX, y: content.bounds.midY)))

        content.configure(snapshot: full, availableWidth: 620, workspaceAction: { actions.append($0) })
        layout(content)
        let restoredButtons = workspaceButtons(in: content)
        XCTAssertEqual(restoredButtons.count, 3)
        restoredButtons.first(where: { $0.title == "Writing" })?.performClick(nil)
        XCTAssertEqual(actions, [
            .workspace(workspaceID: workspace2.id, displayIdentifier: mainDisplay.identifier),
        ])

        content.configure(snapshot: compact, availableWidth: 620, workspaceAction: { actions.append($0) })
        layout(content)
        XCTAssertEqual(ObjectIdentifier(content), originalIdentity)
        XCTAssertTrue(workspaceButtons(in: content).isEmpty)
        XCTAssertNil(content.hitTest(NSPoint(x: content.bounds.midX, y: content.bounds.midY)))
    }

    @MainActor
    func testCustomStatusHostSeparatesWorkspacePrimaryClicksFromMenuClicks() throws {
        let snapshot = independentSnapshot(displays: [mainDisplay, externalDisplay]).replacingMode(.full)
        var workspaceActions: [MenuBarHitTarget] = []
        var menuRequestCount = 0
        let requestMenu = { menuRequestCount += 1 }
        let content = MenuBarStatusContentView(
            snapshot: snapshot,
            availableWidth: 620,
            workspaceAction: { workspaceActions.append($0) },
            menuAction: requestMenu
        )
        let host = MenuBarStatusHostView(contentView: content, menuAction: requestMenu)
        host.configure(
            menuAction: requestMenu,
            accessibilityLabel: snapshot.primaryAccessibilityLabel,
            accessibilityHelp: "Opens the WindowRanger menu."
        )
        layout(host)

        let primaryPoint = NSPoint(x: 2, y: host.bounds.midY)
        XCTAssertTrue(host.hitTest(primaryPoint) === host)
        host.mouseDown(with: mouseEvent(type: .leftMouseDown))
        host.rightMouseDown(with: mouseEvent(type: .rightMouseDown))
        XCTAssertEqual(menuRequestCount, 2)

        let writingButton = try XCTUnwrap(
            workspaceButtons(in: content).first(where: { $0.title == "Writing" })
        )
        let workspacePoint = host.convert(
            NSPoint(x: writingButton.bounds.midX, y: writingButton.bounds.midY),
            from: writingButton
        )
        XCTAssertTrue(host.hitTest(workspacePoint) === writingButton)

        writingButton.performClick(nil)
        XCTAssertEqual(workspaceActions, [
            .workspace(workspaceID: workspace2.id, displayIdentifier: mainDisplay.identifier),
        ])
        XCTAssertEqual(menuRequestCount, 2)

        writingButton.rightMouseDown(with: mouseEvent(type: .rightMouseDown))
        writingButton.mouseDown(with: mouseEvent(type: .leftMouseDown, modifierFlags: .control))
        XCTAssertEqual(menuRequestCount, 4)
        XCTAssertEqual(workspaceActions.count, 1)
    }

    @MainActor
    func testCustomStatusHostPreservesMenuAccessibilityAndTrackingHighlight() {
        let snapshot = independentSnapshot(displays: [mainDisplay]).replacingMode(.compact)
        var menuRequestCount = 0
        let content = MenuBarStatusContentView(
            snapshot: snapshot,
            availableWidth: 620,
            workspaceAction: nil
        )
        let host = MenuBarStatusHostView(
            contentView: content,
            menuAction: { menuRequestCount += 1 }
        )
        host.configure(
            menuAction: { menuRequestCount += 1 },
            accessibilityLabel: "WindowRanger, workspace Writing",
            accessibilityHelp: "Opens the WindowRanger menu."
        )

        XCTAssertEqual(host.accessibilityRole(), .button)
        XCTAssertEqual(host.accessibilityLabel(), "WindowRanger, workspace Writing")
        XCTAssertEqual(host.accessibilityHelp(), "Opens the WindowRanger menu.")
        XCTAssertTrue(host.accessibilityPerformPress())
        XCTAssertEqual(menuRequestCount, 1)

        XCTAssertFalse(host.isMenuPresented)
        host.setMenuPresented(true)
        XCTAssertTrue(host.isMenuPresented)
        host.setMenuPresented(false)
        XCTAssertFalse(host.isMenuPresented)
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

    @MainActor
    private func layout(_ view: NSView) {
        view.frame = CGRect(origin: .zero, size: view.intrinsicContentSize)
        view.layoutSubtreeIfNeeded()
    }

    @MainActor
    private func workspaceButtons(in view: NSView) -> [NSButton] {
        view.subviews.flatMap { child -> [NSButton] in
            let nested = workspaceButtons(in: child)
            if let button = child as? NSButton { return [button] + nested }
            return nested
        }
    }

    @MainActor
    private func textFields(in view: NSView) -> [NSTextField] {
        view.subviews.flatMap { child -> [NSTextField] in
            let nested = textFields(in: child)
            if let textField = child as? NSTextField { return [textField] + nested }
            return nested
        }
    }

    @MainActor
    private func imageViews(in view: NSView) -> [NSImageView] {
        view.subviews.flatMap { child -> [NSImageView] in
            let nested = imageViews(in: child)
            if let imageView = child as? NSImageView { return [imageView] + nested }
            return nested
        }
    }

    private func mouseEvent(
        type: NSEvent.EventType,
        location: NSPoint = .zero,
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )!
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
