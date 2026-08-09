import XCTest

@MainActor
final class UtilitySettingsTests: XCTestCase {
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
    }
}
