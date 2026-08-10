import XCTest

@MainActor
final class UtilitySettingsTests: XCTestCase {
    private final class RecordingCloudStore: UbiquitousKeyValueStoring {
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

    private final class FakeLaunchAtLoginService: LaunchAtLoginServicing {
        var status: LaunchAtLoginStatus
        var enabledResultStatus: LaunchAtLoginStatus = .enabled
        var requestedValues: [Bool] = []
        var openSystemSettingsCount = 0
        var error: Error?

        init(status: LaunchAtLoginStatus) {
            self.status = status
        }

        func setEnabled(_ enabled: Bool) throws {
            requestedValues.append(enabled)
            if let error { throw error }
            status = enabled ? enabledResultStatus : .notRegistered
        }

        func openSystemSettings() {
            openSystemSettingsCount += 1
        }
    }

    private struct TestError: LocalizedError {
        var errorDescription: String? { "Could not update login item" }
    }

    func testApplicationPickerGroupsOpenAppsFirstAndFiltersBothGroups() {
        let applications = [
            InstalledApplication(
                bundleIdentifier: "com.example.Zebra",
                displayName: "Zebra",
                bundleURL: nil,
                isRunning: false
            ),
            InstalledApplication(
                bundleIdentifier: "com.example.Mail",
                displayName: "Mail",
                bundleURL: nil,
                isRunning: true
            ),
            InstalledApplication(
                bundleIdentifier: "com.example.Editor",
                displayName: "Editor",
                bundleURL: nil,
                isRunning: true
            ),
            InstalledApplication(
                bundleIdentifier: "com.example.Archive",
                displayName: "Archive",
                bundleURL: nil,
                isRunning: false
            ),
        ]

        let groups = InstalledApplicationPickerPolicy.groups(
            applications: applications,
            search: ""
        )
        XCTAssertEqual(groups.openApplications.map(\.displayName), ["Editor", "Mail"])
        XCTAssertEqual(groups.otherApplications.map(\.displayName), ["Archive", "Zebra"])

        let filtered = InstalledApplicationPickerPolicy.groups(
            applications: applications,
            search: "example.mail"
        )
        XCTAssertEqual(filtered.openApplications.map(\.displayName), ["Mail"])
        XCTAssertTrue(filtered.otherApplications.isEmpty)
    }

    func testAppRuleWorkspaceDefaultRequiresOneUnambiguousRunningAssignment() {
        let workspaceA = UUID()
        let workspaceB = UUID()

        XCTAssertEqual(
            AppRuleDefaultWorkspacePolicy.resolve(
                applicationIsRunning: true,
                liveWorkspaceIDs: [workspaceA, workspaceA]
            ),
            workspaceA
        )
        XCTAssertNil(AppRuleDefaultWorkspacePolicy.resolve(
            applicationIsRunning: true,
            liveWorkspaceIDs: []
        ))
        XCTAssertNil(AppRuleDefaultWorkspacePolicy.resolve(
            applicationIsRunning: true,
            liveWorkspaceIDs: [workspaceA, workspaceB]
        ))
        XCTAssertNil(AppRuleDefaultWorkspacePolicy.resolve(
            applicationIsRunning: false,
            liveWorkspaceIDs: [workspaceA]
        ))
    }

    func testAddingRunningAppRuleUsesOnlyAValidSuggestedWorkspace() {
        let suite = "UtilitySettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] }
        )
        let workspaceID = store.workspaces[0].id
        let running = InstalledApplication(
            bundleIdentifier: "com.example.Running",
            displayName: "Running",
            bundleURL: nil,
            isRunning: true
        )
        let closed = InstalledApplication(
            bundleIdentifier: "com.example.Closed",
            displayName: "Closed",
            bundleURL: nil,
            isRunning: false
        )
        let invalid = InstalledApplication(
            bundleIdentifier: "com.example.Invalid",
            displayName: "Invalid",
            bundleURL: nil,
            isRunning: true
        )

        store.addAppRule(for: running, defaultWorkspaceID: workspaceID)
        store.addAppRule(for: closed, defaultWorkspaceID: workspaceID)
        store.addAppRule(for: invalid, defaultWorkspaceID: UUID())

        XCTAssertEqual(
            store.appRules.first(where: { $0.id == running.id })?.assignedWorkspaceID,
            workspaceID
        )
        XCTAssertNil(store.appRules.first(where: { $0.id == closed.id })?.assignedWorkspaceID)
        XCTAssertNil(store.appRules.first(where: { $0.id == invalid.id })?.assignedWorkspaceID)
        defaults.removePersistentDomain(forName: suite)
    }

    func testLaunchAtLoginControllerOnlyMutatesServiceAfterExplicitToggle() {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        let controller = LaunchAtLoginController(service: service)

        XCTAssertFalse(controller.isEnabled)
        XCTAssertTrue(service.requestedValues.isEmpty)

        controller.setEnabled(true)
        XCTAssertTrue(controller.isEnabled)
        XCTAssertEqual(service.requestedValues, [true])

        controller.setEnabled(true)
        XCTAssertEqual(service.requestedValues, [true])
    }

    func testLaunchAtLoginFailureRestoresObservedServiceState() {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        service.error = TestError()
        let controller = LaunchAtLoginController(service: service)

        controller.setEnabled(true)

        XCTAssertFalse(controller.isEnabled)
        XCTAssertEqual(service.requestedValues, [true])
        XCTAssertEqual(controller.errorMessage, "Could not update login item")
    }

    func testLaunchAtLoginApprovalStateRemainsVisuallyEnabled() {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        service.enabledResultStatus = .requiresApproval
        let controller = LaunchAtLoginController(service: service)

        controller.setEnabled(true)

        XCTAssertTrue(controller.isEnabled)
        XCTAssertEqual(controller.status, .requiresApproval)
        XCTAssertEqual(service.requestedValues, [true])

        controller.setEnabled(true)
        XCTAssertEqual(service.requestedValues, [true])
    }

    func testLaunchAtLoginRefreshObservesApprovalAndOpeningSystemSettings() {
        let service = FakeLaunchAtLoginService(status: .requiresApproval)
        let controller = LaunchAtLoginController(service: service)

        XCTAssertTrue(controller.isEnabled)
        XCTAssertNotNil(controller.statusMessage)

        controller.openSystemSettings()
        XCTAssertEqual(service.openSystemSettingsCount, 1)

        service.status = .enabled
        controller.refresh()
        XCTAssertEqual(controller.status, .enabled)
        XCTAssertTrue(controller.isEnabled)
    }

    func testAutomaticallyUnhideApplicationsIsMigrationSafeAndPersistsLocally() {
        let suite = "UtilitySettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(false, forKey: "iCloudSyncEnabled")

        var store: SettingsStore? = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] }
        )
        XCTAssertFalse(store!.automaticallyUnhideApplications)
        store!.automaticallyUnhideApplications = true
        store = nil

        let restored = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] }
        )
        XCTAssertTrue(restored.automaticallyUnhideApplications)
        defaults.removePersistentDomain(forName: suite)
    }

    func testFocusedWindowHighlightIsOffByDefaultAndPersistsLocally() {
        let suite = "UtilitySettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: "iCloudSyncEnabled")
        let cloud = RecordingCloudStore()

        var store: SettingsStore? = SettingsStore(
            defaults: defaults,
            ubiquitousStore: cloud,
            connectedDisplaysProvider: { [] }
        )
        XCTAssertFalse(store!.focusedWindowHighlightEnabled)
        XCTAssertEqual(store!.focusedWindowHighlightColor, .default)
        XCTAssertFalse(store!.focusedWindowHighlightTiledOnly)
        XCTAssertFalse(store!.focusedWindowHighlightMultipleWindowsOnly)
        XCTAssertTrue(store!.focusedWindowHighlightCornerRadiusOverrides.isEmpty)
        store!.focusedWindowHighlightEnabled = true
        let customColor = try! XCTUnwrap(MenuBarHighlightColor(hex: "#4080BF"))
        store!.focusedWindowHighlightColor = customColor
        store!.focusedWindowHighlightTiledOnly = true
        store!.focusedWindowHighlightMultipleWindowsOnly = true
        store!.setFocusedWindowHighlightCornerRadiusOverride(
            18,
            for: "com.example.Editor",
            undoManager: nil
        )
        XCTAssertFalse(cloud.keys.contains("focusedWindowHighlightEnabled.v1"))
        XCTAssertFalse(cloud.keys.contains("focusedWindowHighlightColor.v1"))
        XCTAssertFalse(cloud.keys.contains("focusedWindowHighlightTiledOnly.v1"))
        XCTAssertFalse(cloud.keys.contains("focusedWindowHighlightMultipleWindowsOnly.v1"))
        XCTAssertFalse(cloud.keys.contains("focusedWindowHighlightCornerRadiusOverrides.v1"))
        store = nil

        let restored = SettingsStore(
            defaults: defaults,
            ubiquitousStore: cloud,
            connectedDisplaysProvider: { [] }
        )
        XCTAssertTrue(restored.focusedWindowHighlightEnabled)
        XCTAssertEqual(restored.focusedWindowHighlightColor, customColor)
        XCTAssertTrue(restored.focusedWindowHighlightTiledOnly)
        XCTAssertTrue(restored.focusedWindowHighlightMultipleWindowsOnly)
        XCTAssertEqual(
            restored.focusedWindowHighlightCornerRadiusOverride(for: "COM.EXAMPLE.EDITOR"),
            18
        )
        restored.addAppRule(for: InstalledApplication(
            bundleIdentifier: "com.example.Editor",
            displayName: "Editor",
            bundleURL: nil,
            isRunning: false
        ))
        restored.removeAppRule(bundleIdentifier: "com.example.Editor")
        XCTAssertNil(
            restored.focusedWindowHighlightCornerRadiusOverride(for: "com.example.Editor")
        )
        defaults.removePersistentDomain(forName: suite)
    }

    func testFocusedWindowHighlightResolvesOSDefaultAndPerAppCornerRadius() {
        let version14 = OperatingSystemVersion(majorVersion: 14, minorVersion: 7, patchVersion: 0)
        let version15 = OperatingSystemVersion(majorVersion: 15, minorVersion: 6, patchVersion: 0)
        let version26 = OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
        let version27 = OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)
        let futureVersion = OperatingSystemVersion(
            majorVersion: 99,
            minorVersion: 0,
            patchVersion: 0
        )

        for version in [version14, version15, version26] {
            XCTAssertEqual(
                FocusedWindowHighlightPolicy.automaticCornerRadius(for: version),
                10
            )
        }
        XCTAssertEqual(
            FocusedWindowHighlightPolicy.automaticCornerRadius(for: version27),
            16
        )
        XCTAssertEqual(
            FocusedWindowHighlightPolicy.automaticCornerRadius(for: futureVersion),
            16
        )
        XCTAssertEqual(
            FocusedWindowHighlightPolicy.resolvedCornerRadius(
                bundleIdentifier: "COM.EXAMPLE.EDITOR",
                overrides: ["com.example.editor": 18],
                operatingSystemVersion: version14
            ),
            18
        )
        XCTAssertEqual(FocusedWindowHighlightPolicy.normalizedCornerRadius(-5), 0)
        XCTAssertEqual(FocusedWindowHighlightPolicy.normalizedCornerRadius(50), 40)
        XCTAssertEqual(
            FocusedWindowHighlightPolicy.normalizedCornerRadius(.infinity),
            10
        )
    }

    func testFocusedWindowHighlightReservesFourPointsForManagedLayouts() {
        let bounds = CGRect(x: -1_920, y: 24, width: 1_920, height: 1_056)

        XCTAssertEqual(
            FocusedWindowHighlightPolicy.reservingScreenEdgeClearance(
                in: bounds,
                enabled: false
            ),
            bounds
        )
        XCTAssertEqual(
            FocusedWindowHighlightPolicy.reservingScreenEdgeClearance(
                in: bounds,
                enabled: true
            ),
            CGRect(x: -1_916, y: 28, width: 1_912, height: 1_048)
        )
        XCTAssertEqual(
            FocusedWindowHighlightPolicy.reservingScreenEdgeClearance(
                in: CGRect(x: 0, y: 0, width: 6, height: 6),
                enabled: true
            ),
            CGRect(x: 0, y: 0, width: 6, height: 6)
        )
    }

    func testFocusedWindowHighlightPolicyRejectsIneligibleTargets() {
        let eligible = FocusedWindowHighlightTarget(
            key: WindowKey(processIdentifier: 123, windowIdentifier: 456),
            frame: WindowFrame(
                position: CGPoint(x: 100, y: 200),
                size: CGSize(width: 800, height: 600)
            ),
            fullscreenObservation: .falseValue
        )

        XCTAssertTrue(FocusedWindowHighlightPolicy.shouldPresent(
            target: eligible,
            enabled: true,
            suppressed: false,
            ownProcessIdentifier: 999
        ))
        XCTAssertFalse(FocusedWindowHighlightPolicy.shouldPresent(
            target: eligible,
            enabled: false,
            suppressed: false,
            ownProcessIdentifier: 999
        ))
        XCTAssertFalse(FocusedWindowHighlightPolicy.shouldPresent(
            target: eligible,
            enabled: true,
            suppressed: true,
            ownProcessIdentifier: 999
        ))
        XCTAssertFalse(FocusedWindowHighlightPolicy.shouldPresent(
            target: eligible,
            enabled: true,
            suppressed: false,
            ownProcessIdentifier: 123
        ))
        XCTAssertFalse(FocusedWindowHighlightPolicy.shouldPresent(
            target: eligible,
            enabled: true,
            suppressed: false,
            ownProcessIdentifier: 999,
            isDeclaredGame: true
        ))

        let fullscreen = FocusedWindowHighlightTarget(
            key: eligible.key,
            frame: eligible.frame,
            fullscreenObservation: .trueValue
        )
        XCTAssertFalse(FocusedWindowHighlightPolicy.shouldPresent(
            target: fullscreen,
            enabled: true,
            suppressed: false,
            ownProcessIdentifier: 999
        ))

        let unknownFullscreenState = FocusedWindowHighlightTarget(
            key: eligible.key,
            frame: eligible.frame,
            fullscreenObservation: .unavailable
        )
        XCTAssertFalse(FocusedWindowHighlightPolicy.shouldPresent(
            target: unknownFullscreenState,
            enabled: true,
            suppressed: false,
            ownProcessIdentifier: 999
        ))
    }

    func testFocusedWindowHighlightPolicyAppliesWorkspaceFiltersIndependently() {
        let target = FocusedWindowHighlightTarget(
            key: WindowKey(processIdentifier: 123, windowIdentifier: 456),
            frame: WindowFrame(
                position: CGPoint(x: 100, y: 200),
                size: CGSize(width: 800, height: 600)
            ),
            fullscreenObservation: .falseValue
        )
        let tiledSingle = FocusedWindowHighlightWorkspaceContext(
            layout: .tiled,
            windowCount: 1
        )
        let freeformMultiple = FocusedWindowHighlightWorkspaceContext(
            layout: .none,
            windowCount: 2
        )
        let tiledMultiple = FocusedWindowHighlightWorkspaceContext(
            layout: .tiled,
            windowCount: 2
        )

        XCTAssertTrue(FocusedWindowHighlightPolicy.shouldPresent(
            target: target,
            enabled: true,
            suppressed: false,
            ownProcessIdentifier: 999,
            filters: FocusedWindowHighlightFilters(
                tiledWorkspacesOnly: true,
                multipleWindowsOnly: false
            ),
            workspaceContext: tiledSingle
        ))
        XCTAssertFalse(FocusedWindowHighlightPolicy.shouldPresent(
            target: target,
            enabled: true,
            suppressed: false,
            ownProcessIdentifier: 999,
            filters: FocusedWindowHighlightFilters(
                tiledWorkspacesOnly: false,
                multipleWindowsOnly: true
            ),
            workspaceContext: tiledSingle
        ))
        XCTAssertTrue(FocusedWindowHighlightPolicy.shouldPresent(
            target: target,
            enabled: true,
            suppressed: false,
            ownProcessIdentifier: 999,
            filters: FocusedWindowHighlightFilters(
                tiledWorkspacesOnly: false,
                multipleWindowsOnly: true
            ),
            workspaceContext: freeformMultiple
        ))
        XCTAssertFalse(FocusedWindowHighlightPolicy.shouldPresent(
            target: target,
            enabled: true,
            suppressed: false,
            ownProcessIdentifier: 999,
            filters: FocusedWindowHighlightFilters(
                tiledWorkspacesOnly: true,
                multipleWindowsOnly: true
            ),
            workspaceContext: freeformMultiple
        ))
        XCTAssertTrue(FocusedWindowHighlightPolicy.shouldPresent(
            target: target,
            enabled: true,
            suppressed: false,
            ownProcessIdentifier: 999,
            filters: FocusedWindowHighlightFilters(
                tiledWorkspacesOnly: true,
                multipleWindowsOnly: true
            ),
            workspaceContext: tiledMultiple
        ))
        XCTAssertFalse(FocusedWindowHighlightPolicy.shouldPresent(
            target: target,
            enabled: true,
            suppressed: false,
            ownProcessIdentifier: 999,
            filters: FocusedWindowHighlightFilters(
                tiledWorkspacesOnly: true,
                multipleWindowsOnly: false
            ),
            workspaceContext: nil
        ))
    }

    func testFocusedWindowHighlightConvertsAccessibilityFrameAndOutsetsBorder() {
        let frame = FocusedWindowHighlightPolicy.appKitFrame(
            for: WindowFrame(
                position: CGPoint(x: 100, y: 200),
                size: CGSize(width: 800, height: 600)
            ),
            mainScreenTop: 1_080
        )

        XCTAssertEqual(frame, CGRect(x: 98, y: 278, width: 804, height: 604))
    }

    func testFocusedWindowHighlightPanelCannotActivateOrInterceptInput() {
        XCTAssertEqual(
            FocusedWindowHighlightPanelPolicy.nonActivating,
            FocusedWindowHighlightPanelPolicy(
                canBecomeKey: false,
                canBecomeMain: false,
                ignoresMouseEvents: true,
                participatesInWindowCycle: false
            )
        )
    }

    func testAutomaticUnhidePolicyIsOptInAndThrottlesRepeatedAttempts() {
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(ApplicationUnhidePolicy.decision(
            enabled: false,
            isHidden: true,
            lastAttempt: nil,
            now: now
        ), .disabled)
        XCTAssertEqual(ApplicationUnhidePolicy.decision(
            enabled: true,
            isHidden: false,
            lastAttempt: nil,
            now: now
        ), .alreadyVisible)
        XCTAssertEqual(ApplicationUnhidePolicy.decision(
            enabled: true,
            isHidden: true,
            lastAttempt: nil,
            now: now
        ), .attempt)
        XCTAssertEqual(ApplicationUnhidePolicy.decision(
            enabled: true,
            isHidden: true,
            lastAttempt: now.addingTimeInterval(-1),
            now: now
        ), .throttled)
        XCTAssertEqual(ApplicationUnhidePolicy.decision(
            enabled: true,
            isHidden: true,
            lastAttempt: now.addingTimeInterval(-2),
            now: now
        ), .attempt)
    }

    func testUtilityAndSecondaryWindowSettingsAreSearchable() {
        XCTAssertEqual(
            SettingsCatalog.search("login item", includeDebug: false).first?.id,
            "launch-at-login"
        )
        XCTAssertEqual(
            SettingsCatalog.search("hidden compatibility", includeDebug: false).first?.id,
            "auto-unhide-apps"
        )
        XCTAssertEqual(
            SettingsCatalog.search("secondary dialog", includeDebug: false).first?.id,
            "app-float-secondary"
        )
        XCTAssertEqual(
            SettingsCatalog.search("focus ring border", includeDebug: false).first?.id,
            "focused-window-highlight"
        )
        XCTAssertEqual(
            SettingsCatalog.search("corner radius", includeDebug: false).first?.id,
            "focused-window-highlight"
        )
    }
}
