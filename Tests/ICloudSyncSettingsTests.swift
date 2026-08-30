import XCTest

final class ICloudSyncSettingsTests: XCTestCase {
    @MainActor
    func testNewInstallationDefaultsToLocalOnlyWithoutCloudContact() {
        let (defaults, suite) = isolatedDefaults("FirstRun")
        defer { defaults.removePersistentDomain(forName: suite) }
        let cloud = InspectableUbiquitousStore()
        cloud.seed("workspace-label", forKey: "menuBarPresentationMode.v1")

        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: cloud,
            connectedDisplaysProvider: { [] }
        )

        XCTAssertFalse(store.iCloudSyncEnabled)
        XCTAssertEqual(store.menuBarPresentationMode, .compact)
        XCTAssertEqual(cloud.readCount, 0)
        XCTAssertEqual(cloud.writeCount, 0)
        XCTAssertEqual(cloud.synchronizeCount, 0)
    }

    @MainActor
    func testSavedEnabledAndDisabledChoicesSurviveRestart() {
        for enabled in [false, true] {
            let (defaults, suite) = isolatedDefaults("SavedChoice-\(enabled)")
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(enabled, forKey: "iCloudSyncEnabled")
            let cloud = InspectableUbiquitousStore()

            let store = SettingsStore(
                defaults: defaults,
                ubiquitousStore: cloud,
                connectedDisplaysProvider: { [] }
            )

            XCTAssertEqual(store.iCloudSyncEnabled, enabled)
            XCTAssertEqual(defaults.bool(forKey: "iCloudSyncEnabled"), enabled)
            XCTAssertEqual(cloud.synchronizeCount > 0, enabled)
            XCTAssertEqual(store.iCloudSyncState, enabled ? .waitingForCloud : .disabled)
            XCTAssertEqual(cloud.writeCount, 0)
        }
    }

    @MainActor
    func testRemoteWorkspaceSuffixWinsOverConflictingGlobalActionDefault() throws {
        let (defaults, suite) = isolatedDefaults("RemoteShortcutReservation")
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "iCloudSyncEnabled")

        let workspace = WorkspaceDefinition(name: "Floating Work", key: "f")
        let role = ProfileDisplayRole(name: "Main")
        let remoteProfile = WindowManagerProfile(
            name: "Remote",
            workspaces: [workspace],
            displayMode: .unified,
            displayRoles: [role],
            workspaceRoleAssignments: [workspace.id: role.id],
            appRules: []
        )
        let cloud = InspectableUbiquitousStore()
        cloud.seed(
            try JSONEncoder().encode(ProfileLibrary(profiles: [remoteProfile])),
            forKey: "profileLibrary.v1"
        )
        cloud.seed(
            try JSONEncoder().encode(HotKeyConfiguration()),
            forKey: "hotKeyConfiguration.v1"
        )

        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: cloud,
            connectedDisplaysProvider: { [] }
        )

        XCTAssertEqual(store.profiles.first?.workspaces.first?.key, "f")
        XCTAssertNil(store.hotKeyConfiguration.optionalChord(for: .toggleFloating))
        let normalizedCloudData = try XCTUnwrap(cloud.peekData(forKey: "hotKeyConfiguration.v1"))
        let normalizedCloud = try JSONDecoder().decode(
            HotKeyConfiguration.self,
            from: normalizedCloudData
        )
        XCTAssertNotNil(normalizedCloud.optionalChord(for: .toggleFloating))
    }

    @MainActor
    func testDisablingSyncImmediatelyIsolatesCloudAndKeepsLocalPersistence() {
        let (defaults, suite) = isolatedDefaults("Disable")
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "iCloudSyncEnabled")
        let cloud = InspectableUbiquitousStore()
        cloud.seed("keep-me", forKey: "previously.synced.value")
        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: cloud,
            connectedDisplaysProvider: { [] }
        )
        cloud.resetCounters()

        store.iCloudSyncEnabled = false
        store.menuBarPresentationMode = .full
        store.menuBarWorkspaceLabelMode = .key

        XCTAssertFalse(defaults.bool(forKey: "iCloudSyncEnabled"))
        XCTAssertEqual(defaults.string(forKey: "menuBarPresentationMode.v1"), "full")
        XCTAssertEqual(defaults.string(forKey: "menuBarWorkspaceLabelMode.v1"), "key")
        XCTAssertEqual(cloud.peekString(forKey: "previously.synced.value"), "keep-me")
        XCTAssertEqual(cloud.readCount, 0)
        XCTAssertEqual(cloud.writeCount, 0)
        XCTAssertEqual(cloud.synchronizeCount, 0)
    }

    @MainActor
    func testEnablingUsesExistingCloudSettingsWithoutWritingLocalDefaults() throws {
        let (defaults, suite) = isolatedDefaults("Reenable")
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "iCloudSyncEnabled")
        let remote = ProfileLibrary(profiles: [profile(name: "Existing Cloud")])
        let cloud = InspectableUbiquitousStore()
        cloud.seed("keep-me", forKey: "unrelated.remote.value")
        cloud.seed(try JSONEncoder().encode(remote), forKey: "profileLibrary.v1")
        cloud.seed("medium", forKey: "menuBarPresentationMode.v1")
        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: cloud,
            connectedDisplaysProvider: { [] }
        )
        store.menuBarPresentationMode = .full
        cloud.resetCounters()

        store.iCloudSyncEnabled = true

        XCTAssertTrue(defaults.bool(forKey: "iCloudSyncEnabled"))
        XCTAssertEqual(store.iCloudSyncState, .active)
        XCTAssertEqual(store.profiles.map(\.name), ["Existing Cloud"])
        XCTAssertEqual(store.menuBarPresentationMode, .medium)
        XCTAssertEqual(cloud.peekString(forKey: "menuBarPresentationMode.v1"), "medium")
        XCTAssertEqual(cloud.peekString(forKey: "unrelated.remote.value"), "keep-me")
        XCTAssertGreaterThan(cloud.readCount, 0)
        XCTAssertEqual(cloud.writeCount, 0)
        XCTAssertGreaterThan(cloud.synchronizeCount, 0)
    }

    @MainActor
    func testEmptyCloudWaitsWithoutWritingUntilUserExplicitlyUsesThisMac() throws {
        let (defaults, suite) = isolatedDefaults("ExplicitInitialization")
        defer { defaults.removePersistentDomain(forName: suite) }
        let local = ProfileLibrary(profiles: [profile(name: "Local Source")])
        defaults.set(try JSONEncoder().encode(local), forKey: "profileLibrary.v1")
        let cloud = InspectableUbiquitousStore()
        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: cloud,
            connectedDisplaysProvider: { [] }
        )

        store.iCloudSyncEnabled = true

        XCTAssertEqual(store.iCloudSyncState, .waitingForCloud)
        XCTAssertEqual(cloud.writeCount, 0)
        cloud.resetCounters()

        XCTAssertTrue(store.replaceICloudSettingsWithLocalCopy())
        XCTAssertEqual(store.iCloudSyncState, .active)
        XCTAssertGreaterThan(cloud.writeCount, 0)
        let cloudData = try XCTUnwrap(cloud.peekData(forKey: "profileLibrary.v1"))
        XCTAssertEqual(SettingsStore.decodedRemoteProfileLibrary(cloudData)?.profiles.map(\.name), ["Local Source"])
    }

    @MainActor
    func testExplicitReplacementCanPublishLocalSettingsBeforeEnablingPull() throws {
        let (defaults, suite) = isolatedDefaults("ReplaceWhileOff")
        defer { defaults.removePersistentDomain(forName: suite) }
        let local = ProfileLibrary(profiles: [profile(name: "Recovered Local")])
        defaults.set(try JSONEncoder().encode(local), forKey: "profileLibrary.v1")
        let cloud = InspectableUbiquitousStore()
        cloud.seed(
            try JSONEncoder().encode(ProfileLibrary(profiles: [profile(name: "Damaged Cloud")])),
            forKey: "profileLibrary.v1"
        )
        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: cloud,
            connectedDisplaysProvider: { [] }
        )
        cloud.resetCounters()

        XCTAssertTrue(store.replaceICloudSettingsWithLocalCopy())

        XCTAssertTrue(store.iCloudSyncEnabled)
        XCTAssertTrue(defaults.bool(forKey: "iCloudSyncEnabled"))
        XCTAssertEqual(store.iCloudSyncState, .active)
        XCTAssertEqual(cloud.readCount, 0)
        let cloudData = try XCTUnwrap(cloud.peekData(forKey: "profileLibrary.v1"))
        XCTAssertEqual(SettingsStore.decodedRemoteProfileLibrary(cloudData)?.profiles.map(\.name), ["Recovered Local"])
    }

    @MainActor
    func testDelayedCloudLibraryWinsWhileLocalWritesRemainBlocked() async throws {
        let (defaults, suite) = isolatedDefaults("DelayedArrival")
        defer { defaults.removePersistentDomain(forName: suite) }
        let cloud = InspectableUbiquitousStore()
        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: cloud,
            connectedDisplaysProvider: { [] }
        )

        store.iCloudSyncEnabled = true
        store.renameProfile(store.activeProfileID, to: "Edited While Waiting")
        store.menuBarPresentationMode = .full

        XCTAssertEqual(store.iCloudSyncState, .waitingForCloud)
        XCTAssertEqual(cloud.writeCount, 0)

        cloud.seed(
            try JSONEncoder().encode(ProfileLibrary(profiles: [profile(name: "Arrived Later")])),
            forKey: "profileLibrary.v1"
        )
        cloud.notifyExternalChange()
        for _ in 0..<4 { await Task.yield() }

        XCTAssertEqual(store.iCloudSyncState, .active)
        XCTAssertEqual(store.profiles.map(\.name), ["Arrived Later"])
        XCTAssertEqual(cloud.writeCount, 0)
    }

    @MainActor
    func testLocalOnlyModeWorksWithoutAnAvailableCloudStore() {
        let (defaults, suite) = isolatedDefaults("NoStore")
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] }
        )
        store.menuBarPresentationMode = .medium

        XCTAssertFalse(store.iCloudSyncEnabled)
        XCTAssertEqual(defaults.string(forKey: "menuBarPresentationMode.v1"), "medium")
    }

    func testSyncedLibraryAcceptsDocumentAtCountAndNameBoundaries() throws {
        let name = String(repeating: "n", count: SyncedProfileLibraryPolicy.maximumNameCharacters)
        let profiles = (0..<SyncedProfileLibraryPolicy.maximumProfiles).map {
            profile(name: "\(name.dropLast(String($0).count))\($0)")
        }
        let data = try JSONEncoder().encode(ProfileLibrary(profiles: profiles))

        guard case let .accepted(library) = SyncedProfileLibraryPolicy.validate(data) else {
            return XCTFail("Expected the documented boundary to be accepted")
        }
        XCTAssertEqual(library.profiles.count, SyncedProfileLibraryPolicy.maximumProfiles)
    }

    func testSyncedLibraryRejectsOversizedDocumentBeforeDecoding() {
        let data = Data(repeating: 0x20, count: SyncedProfileLibraryPolicy.maximumDocumentBytes + 1)

        XCTAssertEqual(SyncedProfileLibraryPolicy.validate(data), .rejected(.documentTooLarge(
            actualBytes: data.count,
            maximumBytes: SyncedProfileLibraryPolicy.maximumDocumentBytes
        )))
    }

    func testSyncedLibraryRejectsExcessCountsAndNamesWithoutTruncating() throws {
        let tooMany = (0...SyncedProfileLibraryPolicy.maximumProfiles).map {
            profile(name: "Profile \($0)")
        }
        XCTAssertEqual(
            SyncedProfileLibraryPolicy.validate(try JSONEncoder().encode(ProfileLibrary(profiles: tooMany))),
            .rejected(.profileCount(
                actual: tooMany.count,
                maximum: SyncedProfileLibraryPolicy.maximumProfiles
            ))
        )

        let longName = String(repeating: "x", count: SyncedProfileLibraryPolicy.maximumNameCharacters + 1)
        XCTAssertEqual(
            SyncedProfileLibraryPolicy.validate(try JSONEncoder().encode(ProfileLibrary(
                profiles: [profile(name: longName)]
            ))),
            .rejected(.nameTooLong(
                kind: "profile",
                maximumCharacters: SyncedProfileLibraryPolicy.maximumNameCharacters
            ))
        )
    }

    func testSyncedLibraryRejectsEveryNestedCollectionLimit() throws {
        var workspaceHeavy = profile(name: "Workspaces")
        workspaceHeavy.workspaces = (0...SyncedProfileLibraryPolicy.maximumWorkspacesPerProfile).map {
            WorkspaceDefinition(name: "Workspace \($0)", key: "1")
        }
        XCTAssertEqual(
            SyncedProfileLibraryPolicy.validate(try JSONEncoder().encode(ProfileLibrary(
                profiles: [workspaceHeavy]
            ))),
            .rejected(.workspaceCount(
                profileIndex: 0,
                actual: workspaceHeavy.workspaces.count,
                maximum: SyncedProfileLibraryPolicy.maximumWorkspacesPerProfile
            ))
        )

        var roleHeavy = profile(name: "Roles")
        roleHeavy.displayRoles = (0...SyncedProfileLibraryPolicy.maximumDisplayRolesPerProfile).map {
            ProfileDisplayRole(name: "Role \($0)")
        }
        XCTAssertEqual(
            SyncedProfileLibraryPolicy.validate(try JSONEncoder().encode(ProfileLibrary(
                profiles: [roleHeavy]
            ))),
            .rejected(.displayRoleCount(
                profileIndex: 0,
                actual: roleHeavy.displayRoles.count,
                maximum: SyncedProfileLibraryPolicy.maximumDisplayRolesPerProfile
            ))
        )

        var ruleHeavy = profile(name: "Rules")
        ruleHeavy.appRules = (0...SyncedProfileLibraryPolicy.maximumAppRulesPerProfile).map {
            AppRule(bundleIdentifier: "com.example.app\($0)", displayName: "App \($0)")
        }
        XCTAssertEqual(
            SyncedProfileLibraryPolicy.validate(try JSONEncoder().encode(ProfileLibrary(
                profiles: [ruleHeavy]
            ))),
            .rejected(.appRuleCount(
                profileIndex: 0,
                actual: ruleHeavy.appRules.count,
                maximum: SyncedProfileLibraryPolicy.maximumAppRulesPerProfile
            ))
        )

        var quickAppHeavy = profile(name: "Quick Apps")
        quickAppHeavy.quickApps = (0...QuickAppShelfPolicy.maximumCount).map {
            DropDownAppConfiguration(
                bundleIdentifier: "com.example.quick\($0)",
                displayName: "Quick \($0)"
            )
        }
        quickAppHeavy.dropDownApp = quickAppHeavy.quickApps.first
        XCTAssertEqual(
            SyncedProfileLibraryPolicy.validate(try JSONEncoder().encode(ProfileLibrary(
                profiles: [quickAppHeavy]
            ))),
            .rejected(.invalidLibrary)
        )
    }

    func testSyncedLibraryRejectsInvalidSharedShelfPresentation() throws {
        var invalid = profile(name: "Invalid Shelf")
        invalid.quickApps = [DropDownAppConfiguration(
            bundleIdentifier: "com.example.quick",
            displayName: "Quick"
        )]
        invalid.dropDownApp = invalid.quickApps.first
        invalid.quickAppShelfPresentation.heightFraction = 1.5

        XCTAssertEqual(
            SyncedProfileLibraryPolicy.validate(try JSONEncoder().encode(ProfileLibrary(
                profiles: [invalid]
            ))),
            .rejected(.invalidLibrary)
        )

        invalid.quickAppShelfPresentation.heightFraction = 0.8
        invalid.quickAppShelfPresentation.visibleCount = QuickAppShelfPolicy.maximumCount + 1
        XCTAssertEqual(
            SyncedProfileLibraryPolicy.validate(try JSONEncoder().encode(ProfileLibrary(
                profiles: [invalid]
            ))),
            .rejected(.invalidLibrary)
        )
    }

    @MainActor
    func testRejectedRemoteLibraryKeepsLocalProfilesAndOffersRecovery() throws {
        let (defaults, suite) = isolatedDefaults("RejectedRemote")
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "iCloudSyncEnabled")
        let local = ProfileLibrary(profiles: [profile(name: "Local")])
        defaults.set(try JSONEncoder().encode(local), forKey: "profileLibrary.v1")
        let cloud = InspectableUbiquitousStore()
        let rejectedRemote = Data(repeating: 0x20, count: SyncedProfileLibraryPolicy.maximumDocumentBytes + 1)
        cloud.seed(rejectedRemote, forKey: "profileLibrary.v1")

        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: cloud,
            connectedDisplaysProvider: { [] }
        )

        XCTAssertEqual(store.profiles.map(\.name), ["Local"])
        XCTAssertEqual(store.iCloudProfileLibraryIssue?.source, .remote)
        XCTAssertTrue(store.iCloudProfileLibraryIssue?.canReplaceCloudCopy == true)
        XCTAssertEqual(cloud.peekData(forKey: "profileLibrary.v1"), rejectedRemote)
    }

    @MainActor
    func testRecoveryExplicitlyReplacesRejectedRemoteWithValidLocalCopy() throws {
        let (defaults, suite) = isolatedDefaults("RecoverRemote")
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "iCloudSyncEnabled")
        let local = ProfileLibrary(profiles: [profile(name: "Kept Local")])
        defaults.set(try JSONEncoder().encode(local), forKey: "profileLibrary.v1")
        let cloud = InspectableUbiquitousStore()
        cloud.seed(Data("not-json".utf8), forKey: "profileLibrary.v1")
        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: cloud,
            connectedDisplaysProvider: { [] }
        )

        XCTAssertTrue(store.replaceICloudSettingsWithLocalCopy())
        let cloudData = try XCTUnwrap(cloud.peekData(forKey: "profileLibrary.v1"))
        XCTAssertEqual(SettingsStore.decodedRemoteProfileLibrary(cloudData)?.profiles.map(\.name), ["Kept Local"])
        XCTAssertNil(store.iCloudProfileLibraryIssue)
    }

    @MainActor
    func testLocalEditsCannotImplicitlyReplaceARejectedRemoteLibrary() throws {
        let (defaults, suite) = isolatedDefaults("RejectedRemoteEdit")
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "iCloudSyncEnabled")
        let local = ProfileLibrary(profiles: [profile(name: "Local")])
        defaults.set(try JSONEncoder().encode(local), forKey: "profileLibrary.v1")
        let cloud = InspectableUbiquitousStore()
        let rejectedRemote = Data("not-json".utf8)
        cloud.seed(rejectedRemote, forKey: "profileLibrary.v1")
        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: cloud,
            connectedDisplaysProvider: { [] }
        )

        store.renameProfile(store.activeProfileID, to: "Edited Local")

        XCTAssertEqual(store.profiles.map(\.name), ["Edited Local"])
        XCTAssertEqual(cloud.peekData(forKey: "profileLibrary.v1"), rejectedRemote)
        XCTAssertEqual(store.iCloudProfileLibraryIssue?.source, .remote)
    }

    @MainActor
    func testExistingOversizedLocalPrivateLibraryRemainsAvailableWhenSyncIsOff() throws {
        let (defaults, suite) = isolatedDefaults("ExistingLocal")
        defer { defaults.removePersistentDomain(forName: suite) }
        let profiles = (0...SyncedProfileLibraryPolicy.maximumProfiles).map {
            profile(name: "Private \($0)")
        }
        defaults.set(
            try JSONEncoder().encode(ProfileLibrary(profiles: profiles)),
            forKey: "profileLibrary.v1"
        )

        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] }
        )

        XCTAssertFalse(store.iCloudSyncEnabled)
        XCTAssertEqual(store.profiles.count, profiles.count)
        XCTAssertNil(store.iCloudProfileLibraryIssue)
    }

    @MainActor
    func testExplicitReplacementRejectsOversizedLocalLibraryWithoutEnablingOrWriting() throws {
        let (defaults, suite) = isolatedDefaults("OversizedLocalReplacement")
        defer { defaults.removePersistentDomain(forName: suite) }
        let profiles = (0...SyncedProfileLibraryPolicy.maximumProfiles).map {
            profile(name: "Private \($0)")
        }
        defaults.set(
            try JSONEncoder().encode(ProfileLibrary(profiles: profiles)),
            forKey: "profileLibrary.v1"
        )
        let cloud = InspectableUbiquitousStore()
        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: cloud,
            connectedDisplaysProvider: { [] }
        )
        cloud.resetCounters()

        XCTAssertFalse(store.replaceICloudSettingsWithLocalCopy())

        XCTAssertFalse(store.iCloudSyncEnabled)
        XCTAssertFalse(defaults.bool(forKey: "iCloudSyncEnabled"))
        XCTAssertEqual(store.iCloudSyncState, .disabled)
        XCTAssertEqual(store.iCloudProfileLibraryIssue?.source, .local)
        XCTAssertEqual(store.iCloudProfileLibraryIssue?.canReplaceCloudCopy, false)
        XCTAssertEqual(cloud.readCount, 0)
        XCTAssertEqual(cloud.writeCount, 0)
        XCTAssertEqual(cloud.synchronizeCount, 0)
    }

    @MainActor
    func testEnablingSyncWithOversizedLocalLibraryStillAcceptsValidCloudProfiles() throws {
        let (defaults, suite) = isolatedDefaults("OversizedLocalEnable")
        defer { defaults.removePersistentDomain(forName: suite) }
        let oversized = (0...SyncedProfileLibraryPolicy.maximumProfiles).map {
            profile(name: "Private \($0)")
        }
        defaults.set(
            try JSONEncoder().encode(ProfileLibrary(profiles: oversized)),
            forKey: "profileLibrary.v1"
        )
        let cloud = InspectableUbiquitousStore()
        let existingCloud = try JSONEncoder().encode(ProfileLibrary(
            profiles: [profile(name: "Existing Cloud")]
        ))
        cloud.seed(existingCloud, forKey: "profileLibrary.v1")
        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: cloud,
            connectedDisplaysProvider: { [] }
        )

        store.iCloudSyncEnabled = true

        XCTAssertEqual(store.profiles.map(\.name), ["Existing Cloud"])
        XCTAssertNil(store.iCloudProfileLibraryIssue)
        XCTAssertEqual(store.iCloudSyncState, .active)
        XCTAssertEqual(cloud.peekData(forKey: "profileLibrary.v1"), existingCloud)
    }

    func testMalformedAndFutureSyncedDocumentsHaveDistinctRecoveryReasons() throws {
        XCTAssertEqual(
            SyncedProfileLibraryPolicy.validate(Data("not-json".utf8)),
            .rejected(.malformedDocument)
        )
        let future = ProfileLibrary(version: 999, profiles: [profile(name: "Future")])
        XCTAssertEqual(
            SyncedProfileLibraryPolicy.validate(try JSONEncoder().encode(future)),
            .rejected(.unsupportedVersion(999))
        )
    }

    private func isolatedDefaults(_ suffix: String) -> (UserDefaults, String) {
        let suite = "ICloudSyncSettingsTests.\(suffix).\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    private func profile(name: String) -> WindowManagerProfile {
        WindowManagerProfile(
            name: name,
            workspaces: [WorkspaceDefinition(name: "Workspace", key: "1")],
            displayMode: .unified,
            displayRoles: [ProfileDisplayRole(name: "Main")],
            workspaceRoleAssignments: [:],
            appRules: []
        )
    }
}

private final class InspectableUbiquitousStore: UbiquitousKeyValueStoring {
    private var values: [String: Any] = [:]
    private(set) var readCount = 0
    private(set) var writeCount = 0
    private(set) var synchronizeCount = 0
    var notificationObject: AnyObject { self }

    func object(forKey aKey: String) -> Any? {
        readCount += 1
        return values[aKey]
    }

    func string(forKey aKey: String) -> String? {
        readCount += 1
        return values[aKey] as? String
    }

    func data(forKey aKey: String) -> Data? {
        readCount += 1
        return values[aKey] as? Data
    }

    func set(_ anObject: Any?, forKey aKey: String) {
        writeCount += 1
        values[aKey] = anObject
    }

    func removeObject(forKey aKey: String) {
        writeCount += 1
        values.removeValue(forKey: aKey)
    }

    func synchronize() -> Bool {
        synchronizeCount += 1
        return true
    }

    func seed(_ value: Any, forKey key: String) {
        values[key] = value
    }

    func peekString(forKey key: String) -> String? {
        values[key] as? String
    }

    func peekData(forKey key: String) -> Data? {
        values[key] as? Data
    }

    func resetCounters() {
        readCount = 0
        writeCount = 0
        synchronizeCount = 0
    }

    func notifyExternalChange() {
        NotificationCenter.default.post(
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: self
        )
    }
}
