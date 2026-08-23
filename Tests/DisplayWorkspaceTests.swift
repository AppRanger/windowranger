import Carbon
import XCTest

final class DisplayWorkspaceTests: XCTestCase {
    func testDisplayPinPrefersExactRuntimeIdentifier() {
        let pin = WorkspaceDisplayPin(
            lastKnownIdentifier: "external-old",
            fingerprint: fingerprint(uuid: "stable-uuid", serial: "42")
        )
        let displays = [display(
            "external-old",
            fingerprint: fingerprint(uuid: "different-uuid", serial: "99")
        )]

        XCTAssertEqual(
            DisplayIdentityResolver.resolve(pin, among: displays),
            .exactIdentifier("external-old")
        )
    }

    func testDisplayPinUsesExactUUIDBeforeHardwareFallback() {
        let pin = WorkspaceDisplayPin(
            lastKnownIdentifier: "gone",
            fingerprint: fingerprint(uuid: "stable-uuid", serial: "42")
        )
        let displays = [display(
            "runtime-new",
            fingerprint: fingerprint(uuid: "STABLE-UUID", serial: "different")
        )]

        XCTAssertEqual(
            DisplayIdentityResolver.resolve(pin, among: displays),
            .exactUUID("runtime-new")
        )
    }

    func testDisplayPinUsesPortableHardwareIdentityWhenRuntimeUUIDChanges() {
        let pin = WorkspaceDisplayPin(
            lastKnownIdentifier: "gone",
            fingerprint: fingerprint(uuid: "old-uuid", serial: "42")
        )
        let displays = [display(
            "runtime-new",
            fingerprint: fingerprint(uuid: "new-uuid", serial: "42", name: "Renamed by macOS")
        )]

        XCTAssertEqual(
            DisplayIdentityResolver.resolve(pin, among: displays),
            .portableFingerprint("runtime-new")
        )
    }

    func testIdenticalHardwareMatchesAreAmbiguousRatherThanGuessed() {
        let pin = WorkspaceDisplayPin(
            lastKnownIdentifier: "gone",
            fingerprint: fingerprint(uuid: "old", serial: nil)
        )
        let displays = [
            display("left", fingerprint: fingerprint(uuid: "left", serial: nil)),
            display("right", fingerprint: fingerprint(uuid: "right", serial: nil)),
        ]

        XCTAssertEqual(DisplayIdentityResolver.resolve(pin, among: displays), .ambiguous)
    }

    func testNameAndSizeWithoutHardwareIdentityNeverGuess() {
        let fingerprint = DisplayFingerprint(
            displayUUID: "old",
            displayName: "DisplayLink Display",
            widthPoints: 1920,
            heightPoints: 1080
        )
        let pin = WorkspaceDisplayPin(lastKnownIdentifier: "gone", fingerprint: fingerprint)
        let candidate = DisplaySnapshot(
            identifier: "new",
            bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            isMain: false,
            name: "DisplayLink Display",
            fingerprint: DisplayFingerprint(
                displayUUID: "new",
                displayName: "DisplayLink Display",
                widthPoints: 1920,
                heightPoints: 1080
            )
        )

        XCTAssertEqual(DisplayIdentityResolver.resolve(pin, among: [candidate]), .disconnected)
    }

    @MainActor
    func testLegacyUUIDAssignmentMigratesFallsBackAndReturnsOnReconnect() throws {
        let suite = "WindowRangerTests.DisplayMigration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "iCloudSyncEnabled")
        let workspaceID = WorkspaceDefinition.defaults[0].id
        defaults.set(
            try JSONEncoder().encode([workspaceID.uuidString: "external-old"]),
            forKey: "workspaceDisplayAssignments.v1"
        )
        var displays = [
            display("main", isMain: true, fingerprint: fingerprint(uuid: "main", serial: "1")),
            display("external-old", fingerprint: fingerprint(uuid: "old", serial: "42")),
        ]
        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { displays }
        )

        XCTAssertEqual(store.workspaceDisplayAssignments[workspaceID], "external-old")
        XCTAssertNotNil(store.workspaceDisplayPins[workspaceID]?.fingerprint)
        XCTAssertNotNil(defaults.data(forKey: "profileLibrary.v1"))
        XCTAssertNotNil(defaults.data(forKey: "profileLocalState.v1"))
        XCTAssertNil(defaults.data(forKey: "workspaceDisplayPins.v2"))

        displays = [display(
            "main",
            isMain: true,
            fingerprint: fingerprint(uuid: "main", serial: "1")
        )]
        store.refreshConnectedDisplays()
        XCTAssertNil(store.workspaceDisplayAssignments[workspaceID])
        XCTAssertEqual(store.workspaceDisplayHomesForEngine[workspaceID], "external-old")
        XCTAssertEqual(store.effectiveDisplayIdentifier(for: workspaceID), "main")
        XCTAssertEqual(store.displayIdentifier(for: workspaceID), "external-old")

        displays.append(display(
            "external-new",
            fingerprint: fingerprint(uuid: "new", serial: "42", name: "Docked Display")
        ))
        store.refreshConnectedDisplays()
        XCTAssertEqual(store.workspaceDisplayAssignments[workspaceID], "external-new")
        XCTAssertEqual(store.workspaceDisplayHomesForEngine[workspaceID], "external-new")
        XCTAssertEqual(store.workspaceDisplayPins[workspaceID]?.lastKnownIdentifier, "external-new")
    }

    func testWorkspaceDisplayMoveSwapsDestinationWorkspaceAndPreservesOtherDisplays() throws {
        let moving = UUID()
        let displaced = UUID()
        let untouched = UUID()
        let plan = try XCTUnwrap(WorkspaceEngine.workspaceDisplayMovePlan(
            workspaceIDs: [moving, displaced, untouched],
            homeByWorkspace: [moving: "external", displaced: "main", untouched: "portrait"],
            activeWorkspaceIDByDisplay: [
                "external": moving,
                "main": displaced,
                "portrait": untouched,
            ],
            movingWorkspaceID: moving,
            sourceDisplayIdentifier: "external",
            destinationDisplayIdentifier: "main"
        ))

        XCTAssertEqual(plan.replacementWorkspaceID, displaced)
        XCTAssertEqual(plan.changedAssignments, [moving: "main", displaced: "external"])
        XCTAssertEqual(plan.activeWorkspaceIDByDisplay, [
            "external": displaced,
            "main": moving,
            "portrait": untouched,
        ])
        XCTAssertEqual(Set(plan.activeWorkspaceIDByDisplay.values).count, 3)
    }

    func testWorkspaceDisplayMoveUsesInactiveSourceWorkspaceWhenDestinationIsEmpty() throws {
        let moving = UUID()
        let replacement = UUID()
        let plan = try XCTUnwrap(WorkspaceEngine.workspaceDisplayMovePlan(
            workspaceIDs: [moving, replacement],
            homeByWorkspace: [moving: "main", replacement: "main"],
            activeWorkspaceIDByDisplay: ["main": moving],
            movingWorkspaceID: moving,
            sourceDisplayIdentifier: "main",
            destinationDisplayIdentifier: "external"
        ))

        XCTAssertEqual(plan.replacementWorkspaceID, replacement)
        XCTAssertEqual(plan.activeWorkspaceIDByDisplay, [
            "main": replacement,
            "external": moving,
        ])
    }

    func testWorkspaceDisplayMoveRefusesToLeaveSourceWithoutWorkspace() {
        let moving = UUID()
        XCTAssertNil(WorkspaceEngine.workspaceDisplayMovePlan(
            workspaceIDs: [moving],
            homeByWorkspace: [moving: "main"],
            activeWorkspaceIDByDisplay: ["main": moving],
            movingWorkspaceID: moving,
            sourceDisplayIdentifier: "main",
            destinationDisplayIdentifier: "external"
        ))
    }

    func testMoveWorkspaceDisplayShortcutUsesApprovedArrangeDDefault() {
        XCTAssertEqual(
            HotKeyConfiguration().chord(for: .moveWorkspaceToNextDisplay),
            HotKeyChord(keyCode: 2, modifiers: UInt32(optionKey | cmdKey))
        )
    }

    private func fingerprint(
        uuid: String,
        serial: String?,
        name: String = "Studio Display"
    ) -> DisplayFingerprint {
        DisplayFingerprint(
            displayUUID: uuid,
            vendorID: 0x610,
            modelID: 0xA0,
            serialNumber: serial,
            displayName: name,
            widthPoints: 1920,
            heightPoints: 1080
        )
    }

    private func display(
        _ identifier: String,
        isMain: Bool = false,
        fingerprint: DisplayFingerprint
    ) -> DisplaySnapshot {
        DisplaySnapshot(
            identifier: identifier,
            bounds: CGRect(x: isMain ? 0 : -1920, y: 0, width: 1920, height: 1080),
            isMain: isMain,
            name: fingerprint.displayName ?? "Display",
            fingerprint: fingerprint
        )
    }
}

@MainActor
final class ProfileTests: XCTestCase {
    func testProfileCloneCopiesReusableConfigurationWithFreshIdentities() throws {
        let first = WorkspaceDefinition(
            name: "Code",
            key: "c",
            layout: .accordion,
            layoutConfiguration: WorkspaceLayoutConfiguration(
                orientation: .vertical,
                accordionPadding: 175,
                gaps: WorkspaceLayoutGaps(
                    innerHorizontal: 7,
                    innerVertical: 9,
                    outerTop: 11,
                    outerRight: 13,
                    outerBottom: 15,
                    outerLeft: 17
                )
            )
        )
        let second = WorkspaceDefinition(name: "Mail", key: "m", layout: .tiled)
        let primary = ProfileDisplayRole(name: "Desk", menuBarIconStyle: .horizontalMonitor)
        let portrait = ProfileDisplayRole(name: "Portrait", menuBarIconStyle: .verticalMonitor)
        let pausedRule = AppRule(
            bundleIdentifier: "com.example.Mail",
            displayName: "Mail",
            actions: [.assignWorkspace(second.id), .floatSecondaryWindows],
            isEnabled: false
        )
        let source = WindowManagerProfile(
            name: "Work",
            workspaces: [first, second],
            displayMode: .independent,
            displayRoles: [primary, portrait],
            workspaceRoleAssignments: [first.id: primary.id, second.id: portrait.id],
            appRules: [pausedRule]
        )

        let clone = source.cloned(name: "Work Copy")

        XCTAssertNotEqual(clone.id, source.id)
        XCTAssertTrue(Set(clone.workspaces.map(\.id)).isDisjoint(with: source.workspaces.map(\.id)))
        XCTAssertTrue(Set(clone.displayRoles.map(\.id)).isDisjoint(with: source.displayRoles.map(\.id)))
        XCTAssertEqual(clone.displayMode, .independent)
        XCTAssertEqual(
            clone.displayRoles.map(\.menuBarIconStyle),
            [.horizontalMonitor, .verticalMonitor]
        )
        XCTAssertEqual(clone.workspaces.map(\.layout), [.accordion, .tiled])
        XCTAssertEqual(clone.workspaces[0].layoutConfiguration, first.layoutConfiguration)
        XCTAssertEqual(clone.appRules[0].assignedWorkspaceID, clone.workspaces[1].id)
        XCTAssertFalse(clone.appRules[0].isEnabled)
        XCTAssertEqual(clone.workspaceRoleAssignments[clone.workspaces[0].id], clone.displayRoles[0].id)
        XCTAssertEqual(clone.workspaceRoleAssignments[clone.workspaces[1].id], clone.displayRoles[1].id)

        let encoded = try JSONEncoder().encode(ProfileLibrary(profiles: [clone]))
        let text = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(text.contains("manualPinnedProfileID"))
        XCTAssertFalse(text.contains("activeWorkspaceID"))
        XCTAssertFalse(text.contains("windowIdentifier"))
        XCTAssertFalse(text.contains("restoreFrame"))
    }

    func testInitialConversionPreservesConfigurationButSeparatesPhysicalBindings() throws {
        let code = WorkspaceDefinition(
            name: "Code",
            key: "c",
            layout: .accordion,
            layoutConfiguration: .aeroSpaceUserDefaults
        )
        let chat = WorkspaceDefinition(name: "Chat", key: "h", layout: .none)
        let externalPin = WorkspaceDisplayPin(
            lastKnownIdentifier: "external-runtime-id",
            fingerprint: profileFingerprint(uuid: "external-stable", serial: "42")
        )
        let pausedRule = AppRule(
            bundleIdentifier: "com.example.Chat",
            displayName: "Chat",
            actions: [.assignWorkspace(chat.id), .excludeFromLayout],
            isEnabled: false
        )
        let conversion = InitialProfileConverter.convert(
            legacy: LegacyProfileConfiguration(
                workspaces: [code, chat],
                displayMode: .independent,
                workspaceDisplayPins: [chat.id: externalPin],
                appRules: [pausedRule]
            ),
            connectedDisplays: [
                profileDisplay("built-in", isMain: true, isBuiltIn: true, serial: "1"),
                profileDisplay("external-runtime-id", serial: "42"),
            ]
        )

        let profile = try XCTUnwrap(conversion.library.profiles.first)
        XCTAssertEqual(profile.name, "Current Setup")
        XCTAssertEqual(profile.workspaces, [code, chat])
        XCTAssertEqual(profile.displayMode, .independent)
        XCTAssertEqual(profile.appRules, [pausedRule])
        let externalRoleID = try XCTUnwrap(profile.workspaceRoleAssignments[chat.id])
        XCTAssertEqual(
            conversion.localState.roleBindings[externalRoleID]?.lastKnownIdentifier,
            "external-runtime-id"
        )

        let syncedText = String(decoding: try JSONEncoder().encode(conversion.library), as: UTF8.self)
        let localText = String(decoding: try JSONEncoder().encode(conversion.localState), as: UTF8.self)
        XCTAssertFalse(syncedText.contains("external-runtime-id"))
        XCTAssertTrue(localText.contains("external-runtime-id"))
        XCTAssertFalse(syncedText.contains("manualPinnedProfileID"))
    }

    func testOneOffSettingsConversionIsVerifiedThenLegacyStorageIsRemoved() throws {
        let (defaults, suite) = isolatedDefaults("ProfileConversion")
        defer { defaults.removePersistentDomain(forName: suite) }
        let workspaces = [
            WorkspaceDefinition(name: "One", key: "1", layout: .tiled),
            WorkspaceDefinition(name: "Two", key: "2", layout: .accordion),
        ]
        let rule = AppRule(
            bundleIdentifier: "com.example.Editor",
            displayName: "Editor",
            actions: [.assignWorkspace(workspaces[1].id), .floatSecondaryWindows],
            isEnabled: false
        )
        let pin = WorkspaceDisplayPin(
            lastKnownIdentifier: "external",
            fingerprint: profileFingerprint(uuid: "external", serial: "22")
        )
        defaults.set(false, forKey: "iCloudSyncEnabled")
        defaults.set(try JSONEncoder().encode(workspaces), forKey: "workspaceDefinitions.v1")
        defaults.set(MultiDisplayMode.independent.rawValue, forKey: "multiDisplayMode.v1")
        defaults.set(
            try JSONEncoder().encode([workspaces[1].id.uuidString: pin]),
            forKey: "workspaceDisplayPins.v2"
        )
        defaults.set(try JSONEncoder().encode([rule]), forKey: "appRules.v1")

        var store: SettingsStore? = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: {
                [self.profileDisplay("main", isMain: true, isBuiltIn: true, serial: "1")]
            },
            isPortableMacProvider: { true }
        )
        let convertedID = try XCTUnwrap(store?.activeProfileID)
        XCTAssertEqual(store?.workspaces, workspaces)
        XCTAssertEqual(store?.multiDisplayMode, .independent)
        XCTAssertEqual(store?.appRules, [rule])
        XCTAssertNotNil(defaults.data(forKey: "profileLibrary.v1"))
        XCTAssertNotNil(defaults.data(forKey: "profileLocalState.v1"))
        XCTAssertTrue(defaults.bool(forKey: "profileConversionCompleted.v1"))
        XCTAssertNil(defaults.data(forKey: "profileConversionBackup.v1"))
        XCTAssertNil(defaults.data(forKey: "workspaceDefinitions.v1"))
        XCTAssertNil(defaults.object(forKey: "multiDisplayMode.v1"))
        XCTAssertNil(defaults.data(forKey: "workspaceDisplayPins.v2"))
        XCTAssertNil(defaults.data(forKey: "appRules.v1"))
        store = nil

        let restored = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] },
            isPortableMacProvider: { true }
        )
        XCTAssertEqual(restored.activeProfileID, convertedID)
        XCTAssertEqual(restored.workspaces, workspaces)
        XCTAssertEqual(restored.appRules, [rule])
    }

    func testSelectionPrecedenceAndPortableDockRulesAreConservative() {
        let first = profile(name: "First")
        let exact = profile(name: "Exact")
        let docked = profile(name: "Docked")
        let displays = [
            profileDisplay("built-in", isMain: true, isBuiltIn: true, serial: "1"),
            profileDisplay("external", serial: "2"),
        ]
        let exactTrigger = ExactProfileTrigger(
            name: "Desk",
            profileID: exact.id,
            displayPins: displays.map {
                WorkspaceDisplayPin(lastKnownIdentifier: $0.identifier, fingerprint: $0.fingerprint)
            }
        )
        var local = ProfileLocalState(
            activeProfileID: first.id,
            manualPinnedProfileID: first.id,
            defaultProfileID: first.id,
            dockedProfileID: docked.id,
            undockedProfileID: exact.id,
            exactTriggers: [exactTrigger]
        )

        XCTAssertEqual(
            ProfileTriggerResolver.resolve(
                profiles: [first, exact, docked],
                localState: local,
                displays: displays,
                isPortableMac: true
            ),
            ProfileSelection(profileID: first.id, reason: .manualPin)
        )
        local.manualPinnedProfileID = nil
        XCTAssertEqual(
            ProfileTriggerResolver.resolve(
                profiles: [first, exact, docked],
                localState: local,
                displays: displays,
                isPortableMac: true
            ),
            ProfileSelection(profileID: exact.id, reason: .exactTopology(exactTrigger.id))
        )
        local.exactTriggers = []
        XCTAssertEqual(
            ProfileTriggerResolver.resolve(
                profiles: [first, exact, docked],
                localState: local,
                displays: displays,
                isPortableMac: true
            ),
            ProfileSelection(profileID: docked.id, reason: .docked)
        )
        XCTAssertEqual(
            ProfileTriggerResolver.resolve(
                profiles: [first, exact, docked],
                localState: local,
                displays: displays,
                isPortableMac: false
            ),
            ProfileSelection(profileID: first.id, reason: .localDefault)
        )
        XCTAssertEqual(
            ProfileDockState.resolve(
                isPortableMac: true,
                displays: [profileDisplay("built-in", isMain: true, isBuiltIn: true, serial: "1")]
            ),
            .undocked
        )
        XCTAssertEqual(ProfileDockState.resolve(isPortableMac: false, displays: displays), .notApplicable)
    }

    func testGameModeProfileTakesPriorityOverDisplayRulesButNotManualPin() {
        let first = profile(name: "First")
        let game = profile(name: "Game")
        let exact = profile(name: "Exact")
        let displays = [profileDisplay("main", isMain: true, serial: "1")]
        let exactTrigger = ExactProfileTrigger(
            name: "Desk",
            profileID: exact.id,
            displayPins: [WorkspaceDisplayPin(
                lastKnownIdentifier: displays[0].identifier,
                fingerprint: displays[0].fingerprint
            )]
        )
        var local = ProfileLocalState(
            activeProfileID: first.id,
            manualPinnedProfileID: first.id,
            defaultProfileID: first.id,
            gameModeProfileID: game.id,
            exactTriggers: [exactTrigger]
        )

        XCTAssertEqual(
            ProfileTriggerResolver.resolve(
                profiles: [first, game, exact],
                localState: local,
                displays: displays,
                isPortableMac: false,
                isGameModeActive: true
            ),
            ProfileSelection(profileID: first.id, reason: .manualPin)
        )

        local.manualPinnedProfileID = nil
        XCTAssertEqual(
            ProfileTriggerResolver.resolve(
                profiles: [first, game, exact],
                localState: local,
                displays: displays,
                isPortableMac: false,
                isGameModeActive: true
            ),
            ProfileSelection(profileID: game.id, reason: .gameMode)
        )
        XCTAssertEqual(
            ProfileTriggerResolver.resolve(
                profiles: [first, game, exact],
                localState: local,
                displays: displays,
                isPortableMac: false,
                isGameModeActive: false
            ),
            ProfileSelection(profileID: exact.id, reason: .exactTopology(exactTrigger.id))
        )

        local.gameModeProfileID = UUID()
        XCTAssertEqual(
            ProfileTriggerResolver.resolve(
                profiles: [first, game, exact],
                localState: local,
                displays: displays,
                isPortableMac: false,
                isGameModeActive: true
            ),
            ProfileSelection(profileID: exact.id, reason: .exactTopology(exactTrigger.id))
        )
    }

    func testExactTopologyAndRoleBindingsNeverGuessAmbiguousIdenticalMonitors() {
        let workspace = WorkspaceDefinition(name: "Work", key: "w")
        let role = ProfileDisplayRole(name: "Desk")
        let configured = WindowManagerProfile(
            name: "Work",
            workspaces: [workspace],
            displayMode: .independent,
            displayRoles: [role],
            workspaceRoleAssignments: [workspace.id: role.id],
            appRules: []
        )
        let ambiguousFingerprint = DisplayFingerprint(
            displayUUID: "old",
            vendorID: 10,
            modelID: 20,
            serialNumber: nil,
            displayName: "Identical",
            widthPoints: 1920,
            heightPoints: 1080
        )
        let pin = WorkspaceDisplayPin(lastKnownIdentifier: "gone", fingerprint: ambiguousFingerprint)
        let displays = [
            profileDisplay("left", serial: nil),
            profileDisplay("right", serial: nil),
        ]

        XCTAssertFalse(ProfileTriggerResolver.exactTopologyMatches([pin], displays: displays))
        let resolution = ProfileRoleBindingResolver.resolve(
            profile: configured,
            roleBindings: [role.id: pin],
            displays: displays
        )
        XCTAssertEqual(resolution.workspaceDisplayHomes[workspace.id], "gone")
        XCTAssertEqual(configured.workspaceRoleAssignments[workspace.id], role.id)

        let unbound = ProfileRoleBindingResolver.resolve(
            profile: configured,
            roleBindings: [:],
            displays: displays
        )
        XCTAssertNil(unbound.workspaceDisplayHomes[workspace.id])
        XCTAssertEqual(configured.workspaceRoleAssignments[workspace.id], role.id)
    }

    func testUnbindingDisconnectedRoleImmediatelyClearsEngineHomeAndCannotResurrect() {
        let (defaults, suite) = isolatedDefaults("DisconnectedRoleUnbind")
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "iCloudSyncEnabled")
        var displays = [
            profileDisplay("main", isMain: true, isBuiltIn: true, serial: "1"),
            profileDisplay("external", serial: "2"),
        ]
        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { displays },
            isPortableMacProvider: { true }
        )
        let workspaceID = store.workspaces[0].id
        let externalRoleID = store.addDisplayRole(name: "External")
        store.bindDisplayRole(externalRoleID, to: "external")
        store.assignWorkspace(workspaceID, toRole: externalRoleID)
        XCTAssertEqual(store.workspaceDisplayHomesForEngine[workspaceID], "external")
        XCTAssertEqual(store.workspaceDisplayAssignments[workspaceID], "external")

        displays = [profileDisplay("main", isMain: true, isBuiltIn: true, serial: "1")]
        store.refreshConnectedDisplays()
        XCTAssertEqual(store.workspaceDisplayHomesForEngine[workspaceID], "external")
        XCTAssertNil(store.workspaceDisplayAssignments[workspaceID])

        store.bindDisplayRole(externalRoleID, to: nil)
        XCTAssertNil(store.workspaceDisplayHomesForEngine[workspaceID])
        displays.append(profileDisplay("external", serial: "2"))
        store.refreshConnectedDisplays()
        XCTAssertNil(store.workspaceDisplayHomesForEngine[workspaceID])
        XCTAssertNil(store.workspaceDisplayAssignments[workspaceID])
    }

    func testManualSelectionStaysPinnedAcrossDisplayRefreshUntilResumeAutomatic() throws {
        let (defaults, suite) = isolatedDefaults("ManualPin")
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "iCloudSyncEnabled")
        var displays = [
            profileDisplay("built-in", isMain: true, isBuiltIn: true, serial: "1"),
            profileDisplay("external", serial: "2"),
        ]
        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { displays },
            isPortableMacProvider: { true }
        )
        let automaticID = store.activeProfileID
        let manualID = try XCTUnwrap(store.duplicateProfile(automaticID))
        XCTAssertEqual(store.activeProfileID, automaticID)
        XCTAssertEqual(store.settingsProfileID, manualID)
        store.activateSettingsProfile()
        store.setDockedProfile(automaticID)

        displays = [profileDisplay("external-new", isMain: true, serial: "2")]
        store.refreshConnectedDisplays()
        store.refreshConnectedDisplays()
        XCTAssertEqual(store.activeProfileID, manualID)
        XCTAssertEqual(store.manualPinnedProfileID, manualID)
        XCTAssertEqual(store.activeProfileSelectionReason, .manualPin)

        store.resumeAutomaticProfileSelection()
        XCTAssertNil(store.manualPinnedProfileID)
        XCTAssertEqual(store.activeProfileID, automaticID)
        XCTAssertEqual(store.activeProfileSelectionReason, .docked)
    }

    func testProfileSwitchingRulesCanActivateWithoutChangingSettingsEditTarget() throws {
        let (defaults, suite) = isolatedDefaults("ProfileSwitchingPreservesEditTarget")
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "iCloudSyncEnabled")
        var displays = [
            profileDisplay("built-in", isMain: true, isBuiltIn: true, serial: "1"),
        ]
        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { displays },
            isPortableMacProvider: { true }
        )
        let editingProfileID = store.activeProfileID
        let automaticProfileID = try XCTUnwrap(
            store.createProfile(named: "Automatic", source: .scratch)
        )
        store.selectProfileForEditing(editingProfileID)

        store.setDefaultProfile(automaticProfileID)

        XCTAssertEqual(store.activeProfileID, automaticProfileID)
        XCTAssertEqual(store.settingsProfileID, editingProfileID)
        XCTAssertEqual(store.activeProfileSelectionReason, .localDefault)

        store.setUndockedProfile(editingProfileID)
        XCTAssertEqual(store.activeProfileID, editingProfileID)
        XCTAssertEqual(store.settingsProfileID, editingProfileID)
        XCTAssertEqual(store.activeProfileSelectionReason, .undocked)

        store.setDockedProfile(automaticProfileID)
        XCTAssertEqual(store.settingsProfileID, editingProfileID)
        displays.append(profileDisplay("external", serial: "2"))
        store.refreshConnectedDisplays()
        store.selectProfileForEditing(editingProfileID)
        store.setDockedProfile(editingProfileID)
        XCTAssertEqual(store.activeProfileID, editingProfileID)
        XCTAssertEqual(store.settingsProfileID, editingProfileID)
        XCTAssertEqual(store.activeProfileSelectionReason, .docked)

        let exactTriggerID = try XCTUnwrap(
            store.addExactTriggerForCurrentDisplays(profileID: automaticProfileID)
        )
        XCTAssertEqual(store.activeProfileID, automaticProfileID)
        XCTAssertEqual(store.settingsProfileID, editingProfileID)
        XCTAssertEqual(store.activeProfileSelectionReason, .exactTopology(exactTriggerID))

        store.activateSettingsProfile()
        XCTAssertEqual(store.activeProfileID, editingProfileID)
        XCTAssertEqual(store.settingsProfileID, editingProfileID)
        store.resumeAutomaticProfileSelection()
        XCTAssertEqual(store.activeProfileID, automaticProfileID)
        XCTAssertEqual(store.settingsProfileID, editingProfileID)
        XCTAssertEqual(store.activeProfileSelectionReason, .exactTopology(exactTriggerID))
    }

    func testGameModeActivationRestoresAutomaticProfileAndPreservesSettingsTarget() throws {
        let (defaults, suite) = isolatedDefaults("GameModeProfileSelection")
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "iCloudSyncEnabled")
        let displays = [profileDisplay("main", isMain: true, serial: "1")]
        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { displays },
            isPortableMacProvider: { false }
        )
        let editingProfileID = store.activeProfileID
        let gameProfileID = try XCTUnwrap(
            store.createProfile(named: "Game", source: .scratch)
        )
        store.selectProfileForEditing(editingProfileID)
        store.setGameModeProfile(gameProfileID)

        store.setGameModeActive(true)
        XCTAssertTrue(store.isGameModeActive)
        XCTAssertEqual(store.activeProfileID, gameProfileID)
        XCTAssertEqual(store.activeProfileSelectionReason, .gameMode)
        XCTAssertEqual(store.settingsProfileID, editingProfileID)

        store.setGameModeActive(false)
        XCTAssertFalse(store.isGameModeActive)
        XCTAssertEqual(store.activeProfileID, editingProfileID)
        XCTAssertEqual(store.activeProfileSelectionReason, .localDefault)
        XCTAssertEqual(store.settingsProfileID, editingProfileID)

        store.setGameModeActive(true)
        XCTAssertTrue(store.deleteProfile(gameProfileID))
        XCTAssertNil(store.gameModeProfileID)
        XCTAssertEqual(store.activeProfileID, editingProfileID)
        XCTAssertEqual(store.activeProfileSelectionReason, .localDefault)
    }

    func testFreshInstallStartsWithDefaultProfileAndFourNumberedWorkspaces() {
        let (defaults, suite) = isolatedDefaults("FreshProfileDefaults")
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "iCloudSyncEnabled")

        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: {
                [self.profileDisplay("main", isMain: true, serial: "1")]
            }
        )

        XCTAssertEqual(store.activeProfile.name, "Default")
        XCTAssertEqual(store.workspaces.map(\.name), ["1", "2", "3", "4"])
        XCTAssertEqual(store.workspaces.map(\.key), ["1", "2", "3", "4"])
    }

    func testNewScratchProfileUsesCleanDefaultsInsteadOfCurrentConfiguration() throws {
        let (defaults, suite) = isolatedDefaults("ScratchProfile")
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "iCloudSyncEnabled")
        let displays = [profileDisplay("main", isMain: true, serial: "1")]
        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { displays }
        )
        let activeProfileID = store.activeProfileID
        store.multiDisplayMode = .independent
        _ = store.addWorkspace()

        let profileID = try XCTUnwrap(store.createProfile(named: "Travel", source: .scratch))
        let profile = try XCTUnwrap(store.profiles.first(where: { $0.id == profileID }))

        XCTAssertEqual(profile.name, "Travel")
        XCTAssertEqual(profile.workspaces.map(\.name), ["1", "2", "3", "4"])
        XCTAssertEqual(profile.workspaces.map(\.key), ["1", "2", "3", "4"])
        XCTAssertEqual(profile.displayMode, .unified)
        XCTAssertEqual(profile.displayRoles.map(\.name), ["Primary Display"])
        XCTAssertTrue(profile.appRules.isEmpty)
        XCTAssertEqual(Set(profile.workspaceRoleAssignments.keys), Set(profile.workspaces.map(\.id)))
        XCTAssertEqual(store.roleBindings[profile.displayRoles[0].id]?.lastKnownIdentifier, "main")
        XCTAssertEqual(store.settingsProfileID, profileID)
        XCTAssertEqual(store.activeProfileID, activeProfileID)
        XCTAssertNil(store.manualPinnedProfileID)
    }

    func testNewCopiedProfileUsesChosenNameAndCopiesCurrentConfiguration() throws {
        let (defaults, suite) = isolatedDefaults("CopiedProfile")
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "iCloudSyncEnabled")
        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: {
                [self.profileDisplay("main", isMain: true, serial: "1")]
            }
        )
        _ = store.addWorkspace()
        let sourceRoleID = try XCTUnwrap(store.activeProfile.displayRoles.first?.id)
        store.setMenuBarDisplayIconStyle(.laptop, forRole: sourceRoleID)
        store.setSettingsProfileIconStyle(.desktop)
        let source = store.activeProfile

        let copiedID = try XCTUnwrap(
            store.createProfile(named: "  Desk  ", source: .currentProfile)
        )
        let copied = try XCTUnwrap(store.profiles.first(where: { $0.id == copiedID }))

        XCTAssertEqual(copied.name, "Desk")
        XCTAssertEqual(copied.workspaces.map(\.name), source.workspaces.map(\.name))
        XCTAssertEqual(copied.workspaces.map(\.key), source.workspaces.map(\.key))
        XCTAssertTrue(Set(copied.workspaces.map(\.id)).isDisjoint(with: source.workspaces.map(\.id)))
        XCTAssertEqual(copied.displayMode, source.displayMode)
        XCTAssertEqual(copied.displayRoles.map(\.menuBarIconStyle), [.laptop])
        XCTAssertEqual(copied.iconStyle, .desktop)
    }

    func testNewProfileRejectsBlankNameWithoutChangingLibrary() {
        let (defaults, suite) = isolatedDefaults("BlankProfileName")
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "iCloudSyncEnabled")
        let store = SettingsStore(defaults: defaults, ubiquitousStore: nil)
        let profiles = store.profiles

        XCTAssertNil(store.createProfile(named: "  \n ", source: .scratch))
        XCTAssertEqual(store.profiles, profiles)
    }

    func testRenameProfileTrimsUniquifiesAndRejectsBlankNames() throws {
        let (defaults, suite) = isolatedDefaults("RenameProfile")
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "iCloudSyncEnabled")
        let store = SettingsStore(defaults: defaults, ubiquitousStore: nil)
        let originalID = store.activeProfileID
        let secondID = try XCTUnwrap(
            store.createProfile(named: "Second", source: .currentProfile)
        )

        store.renameProfile(originalID, to: "  Home  ")
        store.renameProfile(secondID, to: "Home")
        XCTAssertEqual(store.profiles.first(where: { $0.id == originalID })?.name, "Home")
        XCTAssertEqual(store.profiles.first(where: { $0.id == secondID })?.name, "Home 2")

        store.renameProfile(secondID, to: "  \n ")
        XCTAssertEqual(store.profiles.first(where: { $0.id == secondID })?.name, "Home 2")
    }

    func testLegacyStoredProfileWithoutIconUsesDefault() throws {
        let source = profile(name: "Legacy")
        let encoded = try JSONEncoder().encode(source)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "iconStyle")

        let decoded = try JSONDecoder().decode(
            WindowManagerProfile.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded.iconStyle, .profile)
    }

    func testLegacyLocalProfileStateWithoutGameModeTargetDecodes() throws {
        let configured = profile(name: "Legacy")
        let local = ProfileLocalState(
            activeProfileID: configured.id,
            defaultProfileID: configured.id
        )
        let encoded = try JSONEncoder().encode(local)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "gameModeProfileID")

        let decoded = try JSONDecoder().decode(
            ProfileLocalState.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertNil(decoded.gameModeProfileID)
        XCTAssertEqual(decoded.version, ProfileLocalState.currentVersion)
    }

    func testProfileCrudCleansLocalReferencesAndProtectsOnlyRemainingProfile() throws {
        let (defaults, suite) = isolatedDefaults("ProfileCrud")
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "iCloudSyncEnabled")
        let displays = [profileDisplay("main", isMain: true, isBuiltIn: true, serial: "1")]
        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { displays },
            isPortableMacProvider: { true }
        )
        let originalID = store.activeProfileID
        let duplicateID = try XCTUnwrap(store.duplicateProfile(originalID))
        store.renameProfile(duplicateID, to: "Travel")
        store.setDefaultProfile(duplicateID)
        store.setGameModeProfile(duplicateID)
        store.setDockedProfile(duplicateID)
        _ = store.addExactTriggerForCurrentDisplays(profileID: duplicateID)

        XCTAssertTrue(store.deleteProfile(duplicateID))
        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(store.activeProfileID, originalID)
        XCTAssertEqual(store.defaultProfileID, originalID)
        XCTAssertNil(store.gameModeProfileID)
        XCTAssertNil(store.dockedProfileID)
        XCTAssertTrue(store.exactProfileTriggers.isEmpty)
        XCTAssertFalse(store.deleteProfile(originalID))
    }

    func testRuntimeWorkspaceStateUsesRolesAndGeneralPreferencesRemainGlobal() throws {
        let (defaults, suite) = isolatedDefaults("ProfileRuntime")
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "iCloudSyncEnabled")
        let displays = [profileDisplay("main", isMain: true, isBuiltIn: true, serial: "1")]
        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { displays },
            isPortableMacProvider: { true }
        )
        let firstProfileID = store.activeProfileID
        let workspaceID = store.workspaces[1].id
        store.menuBarPresentationMode = .medium
        store.focusFollowsMovedWindow = true
        XCTAssertNil(store.setShortcutFamilyModifiers(UInt32(controlKey | shiftKey), for: .navigate))
        XCTAssertNil(store.setShortcutKey(6, for: .nextWindow))
        store.recordActiveWorkspaceState(WorkspaceEngineState(
            currentWorkspaceID: workspaceID,
            activeWorkspaceIDs: [workspaceID],
            previousWorkspaceID: nil,
            managedWindowCount: 3,
            accessibilityGranted: true,
            profileID: firstProfileID,
            activeWorkspaceIDByDisplay: ["main": workspaceID]
        ))
        let configuration = store.activeProfileEngineConfiguration()
        XCTAssertEqual(configuration.preferredCurrentWorkspaceID, workspaceID)
        XCTAssertEqual(configuration.preferredActiveWorkspaceIDByDisplay["main"], workspaceID)

        let secondProfileID = try XCTUnwrap(store.duplicateProfile(firstProfileID))
        XCTAssertEqual(store.activeProfileID, firstProfileID)
        store.activateSettingsProfile()
        XCTAssertEqual(store.activeProfileID, secondProfileID)
        XCTAssertEqual(store.menuBarPresentationMode, .medium)
        XCTAssertTrue(store.focusFollowsMovedWindow)
        XCTAssertEqual(
            store.hotKeyConfiguration.chord(for: .nextWindow),
            HotKeyChord(keyCode: 6, modifiers: UInt32(controlKey | shiftKey))
        )

        let localData = try XCTUnwrap(defaults.data(forKey: "profileLocalState.v1"))
        let localText = String(decoding: localData, as: UTF8.self)
        let libraryData = try XCTUnwrap(defaults.data(forKey: "profileLibrary.v1"))
        let libraryText = String(decoding: libraryData, as: UTF8.self)
        XCTAssertTrue(localText.contains("runtimeWorkspaceStates"))
        XCTAssertFalse(libraryText.contains("runtimeWorkspaceStates"))
        XCTAssertFalse(libraryText.contains("manualPinnedProfileID"))
    }

    @MainActor
    func testInactiveProfileCanBeEditedWithoutChangingTheLiveDesktop() throws {
        let (defaults, suite) = isolatedDefaults("InactiveProfileEditing")
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "iCloudSyncEnabled")
        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: {
                [self.profileDisplay("main", isMain: true, isBuiltIn: true, serial: "1")]
            }
        )
        let activeProfileID = store.activeProfileID
        let activeWorkspaces = store.workspaces
        let activeDisplayMode = store.multiDisplayMode
        let activeRules = store.appRules
        let activeQuickApps = store.quickApps
        let activeProfileIconStyle = store.activeProfile.iconStyle
        let activationRequest = store.profileActivationRequest

        let editedProfileID = try XCTUnwrap(store.duplicateProfile(activeProfileID))
        XCTAssertEqual(store.settingsProfileID, editedProfileID)
        XCTAssertEqual(store.activeProfileID, activeProfileID)
        XCTAssertNil(store.manualPinnedProfileID)

        let workspaceID = try XCTUnwrap(store.settingsWorkspaces.first?.id)
        store.setSettingsWorkspaceName("Edited while inactive", for: workspaceID)
        store.setSettingsMultiDisplayMode(
            activeDisplayMode == .unified ? .independent : .unified
        )
        store.addSettingsAppRule(for: InstalledApplication(
            bundleIdentifier: "dev.appranger.inactive-rule",
            displayName: "Inactive Rule",
            bundleURL: nil,
            isRunning: false
        ))
        store.setSettingsQuickApp(InstalledApplication(
            bundleIdentifier: "dev.appranger.inactive-shelf",
            displayName: "Inactive Shelf",
            bundleURL: nil,
            isRunning: false
        ))
        let roleID = store.addSettingsDisplayRole(name: "Inactive Display")
        store.setSettingsMenuBarDisplayIconStyle(.laptop, forRole: roleID)
        store.setSettingsProfileIconStyle(.travel)

        XCTAssertEqual(store.activeProfileID, activeProfileID)
        XCTAssertNil(store.manualPinnedProfileID)
        XCTAssertEqual(store.profileActivationRequest, activationRequest)
        XCTAssertEqual(store.workspaces, activeWorkspaces)
        XCTAssertEqual(store.multiDisplayMode, activeDisplayMode)
        XCTAssertEqual(store.appRules, activeRules)
        XCTAssertEqual(store.quickApps, activeQuickApps)
        XCTAssertEqual(store.activeProfile.iconStyle, activeProfileIconStyle)
        XCTAssertEqual(store.settingsProfile.iconStyle, .travel)
        XCTAssertEqual(store.settingsWorkspaces.first?.name, "Edited while inactive")
        XCTAssertTrue(store.settingsAppRules.contains {
            $0.bundleIdentifier == "dev.appranger.inactive-rule"
        })
        XCTAssertTrue(store.settingsQuickApps.contains {
            $0.bundleIdentifier == "dev.appranger.inactive-shelf"
        })
        XCTAssertEqual(store.settingsMenuBarDisplayIconStyle(forRole: roleID), .laptop)

        store.activateSettingsProfile()

        XCTAssertEqual(store.activeProfileID, editedProfileID)
        XCTAssertEqual(store.manualPinnedProfileID, editedProfileID)
        XCTAssertEqual(store.workspaces, store.settingsWorkspaces)
        XCTAssertEqual(store.appRules, store.settingsAppRules)
        XCTAssertEqual(store.quickApps, store.settingsQuickApps)
        XCTAssertEqual(store.activeProfile.iconStyle, .travel)

        store.setSettingsWorkspaceName("Edited while active", for: workspaceID)
        XCTAssertEqual(store.workspaces.first(where: { $0.id == workspaceID })?.name, "Edited while active")
        XCTAssertEqual(store.activeProfile.workspaces.first(where: { $0.id == workspaceID })?.name, "Edited while active")
    }

    func testRemoteProfileLibraryReplacementIsAtomicAndRejectsInvalidVersions() throws {
        let local = ProfileLibrary(profiles: [profile(name: "Local")])
        let remote = ProfileLibrary(profiles: [profile(name: "Remote")])
        let decoded = SettingsStore.decodedRemoteProfileLibrary(try JSONEncoder().encode(remote))
        XCTAssertEqual(decoded, remote)

        let future = ProfileLibrary(version: 999, profiles: remote.profiles)
        XCTAssertNil(SettingsStore.decodedRemoteProfileLibrary(try JSONEncoder().encode(future)))
        XCTAssertNil(SettingsStore.decodedRemoteProfileLibrary(Data("not-json".utf8)))
        XCTAssertEqual(local.profiles[0].name, "Local")
    }

    func testLocalRuntimeNormalizationRemovesDeletedWorkspaceAndRoleReferences() {
        let configured = profile(name: "Work")
        let invalidWorkspaceID = UUID()
        let invalidRoleID = UUID()
        var local = ProfileLocalState(
            activeProfileID: configured.id,
            defaultProfileID: configured.id,
            roleBindings: [
                invalidRoleID: WorkspaceDisplayPin(lastKnownIdentifier: "gone", fingerprint: nil),
            ],
            runtimeWorkspaceStates: [
                configured.id: ProfileRuntimeWorkspaceState(
                    currentWorkspaceID: invalidWorkspaceID,
                    activeWorkspaceIDByRole: [invalidRoleID: invalidWorkspaceID]
                ),
            ]
        )

        local.normalize(validProfiles: [configured])

        XCTAssertEqual(
            local.runtimeWorkspaceStates[configured.id]?.currentWorkspaceID,
            configured.workspaces[0].id
        )
        XCTAssertTrue(local.runtimeWorkspaceStates[configured.id]?.activeWorkspaceIDByRole.isEmpty == true)
        XCTAssertTrue(local.roleBindings.isEmpty)
    }

    func testTransitionPolicyRejectsIgnoredAndDeferredWindowsAndDoesNotReuseOtherProfileState() {
        XCTAssertTrue(WorkspaceEngine.profileTransitionShouldRecoverWindow(
            disposition: .managedNormal,
            isTemporarilyDeferred: false,
            isMinimized: false,
            isFullscreen: false
        ))
        XCTAssertTrue(WorkspaceEngine.profileTransitionShouldRecoverWindow(
            disposition: .managedDialog,
            isTemporarilyDeferred: false,
            isMinimized: false,
            isFullscreen: false
        ))
        XCTAssertFalse(WorkspaceEngine.profileTransitionShouldRecoverWindow(
            disposition: .ignoredTransientPopup,
            isTemporarilyDeferred: false,
            isMinimized: false,
            isFullscreen: false
        ))
        XCTAssertFalse(WorkspaceEngine.profileTransitionShouldRecoverWindow(
            disposition: .managedNormal,
            isTemporarilyDeferred: true,
            isMinimized: false,
            isFullscreen: false
        ))
        XCTAssertFalse(WorkspaceEngine.profileTransitionShouldRecoverWindow(
            disposition: .managedNormal,
            isTemporarilyDeferred: false,
            isMinimized: true,
            isFullscreen: false
        ))
        XCTAssertFalse(WorkspaceEngine.profileTransitionShouldRecoverWindow(
            disposition: .managedNormal,
            isTemporarilyDeferred: false,
            isMinimized: false,
            isFullscreen: true
        ))

        let oldProfile = UUID()
        let newProfile = UUID()
        XCTAssertTrue(WorkspaceEngine.persistedStateProfileMatches(
            persistedProfileID: oldProfile,
            currentProfileID: oldProfile
        ))
        XCTAssertFalse(WorkspaceEngine.persistedStateProfileMatches(
            persistedProfileID: oldProfile,
            currentProfileID: newProfile
        ))
        XCTAssertTrue(WorkspaceEngine.persistedStateProfileMatches(
            persistedProfileID: nil,
            currentProfileID: newProfile
        ))
    }

    func testTransitionRoutingPrioritizesRulesThenLocalActiveWorkspace() {
        let old = UUID()
        let localActive = UUID()
        let ruleTarget = UUID()
        let fallback = UUID()
        let valid: Set<UUID> = [localActive, ruleTarget, fallback]

        XCTAssertEqual(WorkspaceEngine.profileTransitionWorkspaceID(
            existingWorkspaceID: old,
            preserveExistingMembership: false,
            validWorkspaceIDs: valid,
            assignedWorkspaceID: ruleTarget,
            activeDisplayWorkspaceID: localActive,
            defaultWorkspaceID: fallback
        ), ruleTarget)
        XCTAssertEqual(WorkspaceEngine.profileTransitionWorkspaceID(
            existingWorkspaceID: old,
            preserveExistingMembership: false,
            validWorkspaceIDs: valid,
            assignedWorkspaceID: nil,
            activeDisplayWorkspaceID: localActive,
            defaultWorkspaceID: fallback
        ), localActive)
        XCTAssertEqual(WorkspaceEngine.profileTransitionWorkspaceID(
            existingWorkspaceID: old,
            preserveExistingMembership: false,
            validWorkspaceIDs: valid,
            assignedWorkspaceID: nil,
            activeDisplayWorkspaceID: nil,
            defaultWorkspaceID: fallback
        ), fallback)
    }

    func testTransitionRecoveryUsesVisibleFramesAndClampsParkedWindows() throws {
        let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let external = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let visibleCurrent = WindowFrame(
            position: CGPoint(x: -1500, y: 100),
            size: CGSize(width: 800, height: 700)
        )
        let visibleSaved = WindowFrame(
            position: CGPoint(x: 200, y: 120),
            size: CGSize(width: 900, height: 650)
        )
        let parked = WindowFrame(
            position: CGPoint(x: 50_000, y: 100),
            size: CGSize(width: 900, height: 650)
        )

        XCTAssertEqual(WorkspaceEngine.profileTransitionVisibleFrame(
            currentFrame: visibleCurrent,
            savedFrame: visibleSaved,
            displayBounds: [main, external]
        ), visibleCurrent)
        XCTAssertEqual(WorkspaceEngine.profileTransitionVisibleFrame(
            currentFrame: parked,
            savedFrame: visibleSaved,
            displayBounds: [main, external]
        ), visibleSaved)
        let recovered = try XCTUnwrap(WorkspaceEngine.profileTransitionVisibleFrame(
            currentFrame: parked,
            savedFrame: parked,
            displayBounds: [main, external]
        ))
        XCTAssertTrue(WorkspaceEngine.isMeaningfullyVisible(recovered, displays: [
            DisplaySnapshot(identifier: "main", bounds: main, isMain: true, name: "Main"),
            DisplaySnapshot(identifier: "external", bounds: external, isMain: false, name: "External"),
        ]))
    }

    func testLatestProfileTransitionGenerationSupersedesRapidEarlierRequests() {
        let gate = ProfileTransitionGenerationGate()
        gate.register(1)
        XCTAssertTrue(gate.isCurrent(1))
        gate.register(3)
        XCTAssertFalse(gate.isCurrent(1))
        XCTAssertTrue(gate.isCurrent(3))
        gate.register(2)
        XCTAssertFalse(gate.isCurrent(2))
        XCTAssertTrue(gate.isCurrent(3))
    }

    func testProfileSettingsAreSearchableByTheirSeparateOwners() {
        XCTAssertEqual(
            SettingsCatalog.search("create manage profiles", includeDebug: false).first?.category,
            .profiles
        )
        XCTAssertEqual(
            SettingsCatalog.search("docked topology", includeDebug: false).first?.category,
            .profileSwitching
        )
        XCTAssertEqual(
            SettingsCatalog.search("monitor fingerprint role", includeDebug: false).first?.category,
            .displays
        )
    }

    func testProfileDiagnosticsArePrivacySafeIdentifiersAndReasons() {
        let (defaults, suite) = isolatedDefaults("ProfileDiagnostics")
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "iCloudSyncEnabled")
        let sink = MemoryDiagnosticSink()
        let diagnostics = DiagnosticLogger(
            buildMode: .test,
            sink: sink,
            sessionIdentifier: "profiles-test"
        )
        _ = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: {
                [self.profileDisplay("private-runtime-identifier", isMain: true, serial: "99")]
            },
            diagnostics: diagnostics
        )

        XCTAssertTrue(sink.text.contains("selection-resolved"))
        XCTAssertTrue(sink.text.contains("role-resolution"))
        XCTAssertTrue(sink.text.contains("local-default"))
        XCTAssertFalse(sink.text.contains("private-runtime-identifier"))
        XCTAssertFalse(sink.text.contains("window-title"))
    }

    private func profile(name: String) -> WindowManagerProfile {
        let workspace = WorkspaceDefinition(name: "1", key: "1")
        let role = ProfileDisplayRole(name: "Primary")
        return WindowManagerProfile(
            name: name,
            workspaces: [workspace],
            displayMode: .unified,
            displayRoles: [role],
            workspaceRoleAssignments: [workspace.id: role.id],
            appRules: []
        )
    }

    private func isolatedDefaults(_ label: String) -> (UserDefaults, String) {
        let suite = "WindowRangerTests.\(label).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    private func profileFingerprint(uuid: String, serial: String?) -> DisplayFingerprint {
        DisplayFingerprint(
            displayUUID: uuid,
            vendorID: 10,
            modelID: 20,
            serialNumber: serial,
            displayName: "Profile Test Display",
            widthPoints: 1920,
            heightPoints: 1080
        )
    }

    private func profileDisplay(
        _ identifier: String,
        isMain: Bool = false,
        isBuiltIn: Bool = false,
        serial: String?
    ) -> DisplaySnapshot {
        DisplaySnapshot(
            identifier: identifier,
            bounds: CGRect(x: isMain ? 0 : -1920, y: 0, width: 1920, height: 1080),
            isMain: isMain,
            isBuiltIn: isBuiltIn,
            name: "Profile Test Display",
            fingerprint: profileFingerprint(uuid: identifier, serial: serial)
        )
    }
}
