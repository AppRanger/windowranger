import XCTest

final class ProfileTransferTests: XCTestCase {
    func testRoundTripPreservesReusableDefinitionAndExcludesMachineState() throws {
        let source = profile(name: "Writing")
        let data = try ProfileTransferCodec.encode(profiles: [source])
        let text = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(text.contains("window-manager-profile-export"))
        XCTAssertFalse(text.contains("activeProfileID"))
        XCTAssertFalse(text.contains("manualPinnedProfileID"))
        XCTAssertFalse(text.contains("runtimeWorkspaceStates"))
        XCTAssertFalse(text.contains("lastKnownIdentifier"))
        XCTAssertFalse(text.contains("displayUUID"))

        let plan = try ProfileTransferCodec.decodeAndPlan(data, existingProfiles: [])
        let imported = try XCTUnwrap(plan.importedProfiles.first)
        XCTAssertNotEqual(imported.id, source.id)
        XCTAssertEqual(imported.name, source.name)
        XCTAssertEqual(imported.iconStyle, source.iconStyle)
        XCTAssertEqual(imported.displayMode, source.displayMode)
        XCTAssertEqual(imported.workspaces.map(\.name), source.workspaces.map(\.name))
        XCTAssertEqual(imported.workspaces.map(\.key), source.workspaces.map(\.key))
        XCTAssertEqual(imported.workspaces.map(\.layout), source.workspaces.map(\.layout))
        XCTAssertEqual(
            imported.workspaces.map(\.layoutConfiguration),
            source.workspaces.map(\.layoutConfiguration)
        )
        XCTAssertEqual(imported.displayRoles.map(\.name), source.displayRoles.map(\.name))
        XCTAssertEqual(
            imported.displayRoles.map(\.menuBarIconStyle),
            source.displayRoles.map(\.menuBarIconStyle)
        )
        XCTAssertEqual(imported.appRules.first?.bundleIdentifier, "com.example.Editor")
        XCTAssertEqual(
            imported.appRules.first?.assignedWorkspaceID,
            imported.workspaces.last?.id
        )
        XCTAssertEqual(
            imported.workspaceRoleAssignments[imported.workspaces[0].id],
            imported.displayRoles[0].id
        )
        XCTAssertEqual(
            imported.workspaceRoleAssignments[imported.workspaces[1].id],
            imported.displayRoles[1].id
        )
    }

    func testLegacyArchiveWithoutProfileIconUsesDefault() throws {
        let source = profile(name: "Legacy")
        let encoded = try ProfileTransferCodec.encode(profiles: [source])
        var archive = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        var profiles = try XCTUnwrap(archive["profiles"] as? [[String: Any]])
        profiles[0].removeValue(forKey: "iconStyle")
        archive["profiles"] = profiles

        let legacyData = try JSONSerialization.data(withJSONObject: archive)
        let plan = try ProfileTransferCodec.decodeAndPlan(
            legacyData,
            existingProfiles: []
        )

        XCTAssertEqual(plan.importedProfiles.first?.iconStyle, .profile)
    }

    func testLegacyFutureMalformedAndOversizeDocumentsAreRejected() throws {
        XCTAssertThrowsError(try ProfileTransferCodec.decodeAndPlan(
            Data("not json".utf8), existingProfiles: []
        )) { XCTAssertEqual($0 as? ProfileTransferError, .malformedDocument) }

        let legacyLibrary = try JSONEncoder().encode(ProfileLibrary(profiles: [profile(name: "Old")]))
        XCTAssertThrowsError(try ProfileTransferCodec.decodeAndPlan(
            legacyLibrary, existingProfiles: []
        )) { XCTAssertEqual($0 as? ProfileTransferError, .invalidFormat) }

        for version in [0, PortableProfileArchive.currentVersion + 1] {
            let archive = PortableProfileArchive(version: version, profiles: [])
            let data = try JSONEncoder().encode(archive)
            XCTAssertThrowsError(try ProfileTransferCodec.decodeAndPlan(
                data, existingProfiles: []
            )) { XCTAssertEqual($0 as? ProfileTransferError, .unsupportedVersion(version)) }
        }

        let oversized = Data(repeating: 0x20, count: ProfileTransferCodec.maximumDocumentBytes + 1)
        XCTAssertThrowsError(try ProfileTransferCodec.decodeAndPlan(
            oversized, existingProfiles: []
        )) {
            XCTAssertEqual(
                $0 as? ProfileTransferError,
                .documentTooLarge(maximumBytes: ProfileTransferCodec.maximumDocumentBytes)
            )
        }
    }

    func testInvalidReferencesDuplicateIdentitiesAndUnsafeCountsAreRejected() throws {
        let source = profile(name: "Source")
        var portable = PortableProfileDefinition(profile: source)
        portable.workspaceRoleAssignments[UUID()] = portable.displayRoles[0].id
        XCTAssertThrowsError(try decode(PortableProfileArchive(profiles: [portable]))) {
            XCTAssertEqual(
                $0 as? ProfileTransferError,
                .invalidReference("display assignment workspace")
            )
        }

        portable = PortableProfileDefinition(profile: source)
        portable.workspaces.append(portable.workspaces[0])
        XCTAssertThrowsError(try decode(PortableProfileArchive(profiles: [portable]))) {
            XCTAssertEqual($0 as? ProfileTransferError, .duplicateIdentity("workspace"))
        }

        portable = PortableProfileDefinition(profile: source)
        portable.appRules[0].assignedWorkspaceID = UUID()
        XCTAssertThrowsError(try decode(PortableProfileArchive(profiles: [portable]))) {
            XCTAssertEqual(
                $0 as? ProfileTransferError,
                .invalidReference("application rule workspace")
            )
        }

        let duplicateProfiles = PortableProfileArchive(profiles: [
            PortableProfileDefinition(profile: source),
            PortableProfileDefinition(profile: source),
        ])
        XCTAssertThrowsError(try decode(duplicateProfiles)) {
            XCTAssertEqual($0 as? ProfileTransferError, .duplicateIdentity("profile"))
        }

        let excessive = Array(
            repeating: PortableProfileDefinition(profile: source),
            count: ProfileTransferCodec.maximumProfiles + 1
        )
        XCTAssertThrowsError(try decode(PortableProfileArchive(profiles: excessive))) {
            XCTAssertEqual(
                $0 as? ProfileTransferError,
                .limitExceeded("more than \(ProfileTransferCodec.maximumProfiles) profiles")
            )
        }

        portable = PortableProfileDefinition(profile: source)
        portable.quickApps = (0...QuickAppShelfPolicy.maximumCount).map {
            DropDownAppConfiguration(
                bundleIdentifier: "com.example.quick\($0)",
                displayName: "Quick \($0)"
            )
        }
        XCTAssertThrowsError(try decode(PortableProfileArchive(profiles: [portable]))) {
            XCTAssertEqual(
                $0 as? ProfileTransferError,
                .limitExceeded(
                    "more than \(QuickAppShelfPolicy.maximumCount) Quick Apps in one profile"
                )
            )
        }

        portable = PortableProfileDefinition(profile: source)
        portable.quickApps = [
            DropDownAppConfiguration(bundleIdentifier: "com.example.quick", displayName: "One"),
            DropDownAppConfiguration(bundleIdentifier: "COM.EXAMPLE.QUICK", displayName: "Two"),
        ]
        XCTAssertThrowsError(try decode(PortableProfileArchive(profiles: [portable]))) {
            XCTAssertEqual(
                $0 as? ProfileTransferError,
                .invalidValue("Quick Apps must be distinct normalized configurations")
            )
        }

        portable = PortableProfileDefinition(profile: source)
        portable.quickAppShelfPresentation.visibleCount = QuickAppShelfPolicy.maximumCount + 1
        XCTAssertThrowsError(try decode(PortableProfileArchive(profiles: [portable]))) {
            XCTAssertEqual(
                $0 as? ProfileTransferError,
                .invalidValue("Quick App Shelf visible count")
            )
        }
    }

    func testEveryIdentityAndRelationshipIsRemappedWithDeterministicUniqueNames() throws {
        let existing = profile(name: "Work")
        let first = profile(name: "Work")
        let second = profile(name: "Work")
        let data = try ProfileTransferCodec.encode(profiles: [first, second])
        let plan = try ProfileTransferCodec.decodeAndPlan(data, existingProfiles: [existing])

        XCTAssertEqual(plan.importedProfiles.map(\.name), ["Work 2", "Work 3"])
        let oldIDs = Set(([existing, first, second]).flatMap { profile in
            [profile.id] + profile.workspaces.map(\.id) + profile.displayRoles.map(\.id)
        })
        let newIDs = plan.importedProfiles.flatMap { profile in
            [profile.id] + profile.workspaces.map(\.id) + profile.displayRoles.map(\.id)
        }
        XCTAssertEqual(Set(newIDs).count, newIDs.count)
        XCTAssertTrue(Set(newIDs).isDisjoint(with: oldIDs))
        for imported in plan.importedProfiles {
            XCTAssertEqual(imported.appRules[0].assignedWorkspaceID, imported.workspaces[1].id)
            XCTAssertEqual(
                imported.workspaceRoleAssignments[imported.workspaces[1].id],
                imported.displayRoles[1].id
            )
        }
    }

    @MainActor
    func testStoreApplyIsAtomicPersistedAndDoesNotActivateOrChangeLocalState() throws {
        let (store, defaults, suite) = makeStore("Apply")
        defer { defaults.removePersistentDomain(forName: suite) }
        let originalProfiles = store.profiles
        let activeID = store.activeProfileID
        let localState = store.localProfileState
        let activationRequest = store.profileActivationRequest
        let data = try ProfileTransferCodec.encode(profiles: [originalProfiles[0]])
        let plan = try ProfileTransferCodec.decodeAndPlan(data, existingProfiles: originalProfiles)

        XCTAssertEqual(store.applyProfileImport(plan), .applied(profileCount: 1))
        XCTAssertEqual(store.profiles.count, originalProfiles.count + 1)
        XCTAssertEqual(store.activeProfileID, activeID)
        XCTAssertEqual(store.localProfileState, localState)
        XCTAssertEqual(store.profileActivationRequest, activationRequest)

        let saved = try XCTUnwrap(defaults.data(forKey: "profileLibrary.v1"))
        let library = try JSONDecoder().decode(ProfileLibrary.self, from: saved)
        XCTAssertEqual(library.profiles, store.profiles)
        XCTAssertNil(store.roleBindings[plan.importedProfiles[0].displayRoles[0].id])
    }

    @MainActor
    func testStalePreviewAndCancelCauseNoMutation() async throws {
        let (store, defaults, suite) = makeStore("Stale")
        defer { defaults.removePersistentDomain(forName: suite) }
        let data = try ProfileTransferCodec.encode(profiles: [store.profiles[0]])
        let plan = try ProfileTransferCodec.decodeAndPlan(data, existingProfiles: store.profiles)
        store.renameProfile(store.activeProfileID, to: "Changed after preview")
        let changedProfiles = store.profiles

        XCTAssertEqual(store.applyProfileImport(plan), .stalePreview)
        XCTAssertEqual(store.profiles, changedProfiles)

        let panels = FakeProfileTransferPanels(importURL: nil, exportURL: nil)
        let files = MemoryProfileTransferFiles()
        let coordinator = ProfileTransferCoordinator(fileAccess: files, panels: panels)
        let prepared = try await coordinator.prepareImport(existingProfiles: store.profiles)
        let exported = try await coordinator.exportProfiles(store.profiles)
        XCTAssertNil(prepared)
        XCTAssertFalse(exported)
        XCTAssertEqual(files.readCount, 0)
        XCTAssertEqual(files.writeCount, 0)
        XCTAssertEqual(store.profiles, changedProfiles)
    }

    @MainActor
    func testUndoRemovesOnlyUnchangedUnusedImportedProfiles() throws {
        let (store, defaults, suite) = makeStore("Undo")
        defer { defaults.removePersistentDomain(forName: suite) }
        let originalCount = store.profiles.count
        let data = try ProfileTransferCodec.encode(profiles: [store.profiles[0]])
        let undo = UndoManager()
        let plan = try ProfileTransferCodec.decodeAndPlan(data, existingProfiles: store.profiles)
        XCTAssertEqual(store.applyProfileImport(plan, undoManager: undo), .applied(profileCount: 1))
        XCTAssertTrue(undo.canUndo)
        undo.undo()
        XCTAssertEqual(store.profiles.count, originalCount)

        let secondUndo = UndoManager()
        let secondPlan = try ProfileTransferCodec.decodeAndPlan(data, existingProfiles: store.profiles)
        XCTAssertEqual(
            store.applyProfileImport(secondPlan, undoManager: secondUndo),
            .applied(profileCount: 1)
        )
        let importedID = secondPlan.importedProfiles[0].id
        store.selectProfile(importedID)
        secondUndo.undo()
        XCTAssertTrue(store.profiles.contains(where: { $0.id == importedID }))
        XCTAssertEqual(store.activeProfileID, importedID)
    }

    @MainActor
    func testInjectedFilesPanelsAndDiagnosticsRemainPrivate() async throws {
        let source = profile(name: "Private Planning Profile")
        let importURL = URL(fileURLWithPath: "/private/tmp/secret-profile-source.json")
        let exportURL = URL(fileURLWithPath: "/private/tmp/secret-profile-destination.json")
        let files = MemoryProfileTransferFiles()
        files.storage[importURL] = try ProfileTransferCodec.encode(profiles: [source])
        let panels = FakeProfileTransferPanels(importURL: importURL, exportURL: exportURL)
        let sink = MemoryDiagnosticSink()
        let logger = DiagnosticLogger(
            buildMode: .test,
            sink: sink,
            sessionIdentifier: "profile-transfer-test"
        )
        let coordinator = ProfileTransferCoordinator(
            fileAccess: files,
            panels: panels,
            diagnostics: logger
        )

        let plan = try await coordinator.prepareImport(existingProfiles: [])
        let exported = try await coordinator.exportProfiles([source])
        XCTAssertEqual(plan?.importedProfiles.count, 1)
        XCTAssertTrue(exported)
        XCTAssertNotNil(files.storage[exportURL])
        XCTAssertEqual(files.readCount, 1)
        XCTAssertEqual(files.writeCount, 1)
        XCTAssertFalse(sink.text.contains("Private Planning Profile"))
        XCTAssertFalse(sink.text.contains("com.example.Editor"))
        XCTAssertFalse(sink.text.contains("secret-profile"))
    }

    @MainActor
    func testProfileTransferIsSearchable() {
        XCTAssertEqual(
            SettingsCatalog.search("export profiles", includeDebug: false).first?.id,
            "profiles-transfer"
        )
        XCTAssertEqual(
            SettingsCatalog.search("portable JSON", includeDebug: false).first?.category,
            .profiles
        )
    }

    private func decode(_ archive: PortableProfileArchive) throws -> ProfileImportPlan {
        try ProfileTransferCodec.decodeAndPlan(
            JSONEncoder().encode(archive),
            existingProfiles: []
        )
    }

    private func profile(name: String) -> WindowManagerProfile {
        let writing = WorkspaceDefinition(
            name: "Writing",
            key: "w",
            layout: .accordion,
            layoutConfiguration: WorkspaceLayoutConfiguration(
                orientation: .horizontal,
                accordionPadding: 220,
                gaps: WorkspaceLayoutGaps(
                    innerHorizontal: 8,
                    innerVertical: 9,
                    outerTop: 10,
                    outerRight: 11,
                    outerBottom: 12,
                    outerLeft: 13
                )
            )
        )
        let review = WorkspaceDefinition(
            name: "Review",
            key: "r",
            layout: .tiled,
            layoutConfiguration: .aeroSpaceUserDefaults
        )
        let primary = ProfileDisplayRole(name: "Built-in", menuBarIconStyle: .laptop)
        let studio = ProfileDisplayRole(
            name: "Studio Display",
            menuBarIconStyle: .horizontalMonitor
        )
        return WindowManagerProfile(
            name: name,
            iconStyle: .work,
            workspaces: [writing, review],
            displayMode: .independent,
            displayRoles: [primary, studio],
            workspaceRoleAssignments: [writing.id: primary.id, review.id: studio.id],
            appRules: [AppRule(
                bundleIdentifier: "com.example.Editor",
                displayName: "Editor",
                actions: [
                    .assignWorkspace(review.id),
                    .excludeFromLayout,
                    .floatSecondaryWindows,
                ],
                isEnabled: false
            )]
        )
    }

    @MainActor
    private func makeStore(_ suffix: String) -> (SettingsStore, UserDefaults, String) {
        let suite = "WindowRangerTests.ProfileTransfer.\(suffix).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: "iCloudSyncEnabled")
        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [DisplaySnapshot(
                identifier: "main",
                bounds: CGRect(x: 0, y: 0, width: 1440, height: 900),
                isMain: true,
                isBuiltIn: true,
                name: "Built-in"
            )] },
            isPortableMacProvider: { true }
        )
        return (store, defaults, suite)
    }
}

private final class MemoryProfileTransferFiles: ProfileTransferFileAccess {
    var storage: [URL: Data] = [:]
    private(set) var readCount = 0
    private(set) var writeCount = 0

    func read(from url: URL) throws -> Data {
        readCount += 1
        guard let data = storage[url] else { throw CocoaError(.fileNoSuchFile) }
        return data
    }

    func write(_ data: Data, to url: URL) throws {
        writeCount += 1
        storage[url] = data
    }
}

@MainActor
private final class FakeProfileTransferPanels: ProfileTransferPanelPresenting {
    let importURL: URL?
    let exportURL: URL?

    init(importURL: URL?, exportURL: URL?) {
        self.importURL = importURL
        self.exportURL = exportURL
    }

    func chooseImportURL() async -> URL? { importURL }
    func chooseExportURL(suggestedFileName: String) async -> URL? { exportURL }
}
