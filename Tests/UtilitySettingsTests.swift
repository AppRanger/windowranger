import XCTest

@MainActor
final class UtilitySettingsTests: XCTestCase {
    private final class FakeLaunchAtLoginService: LaunchAtLoginServicing {
        var isEnabled: Bool
        var requestedValues: [Bool] = []
        var error: Error?

        init(isEnabled: Bool) {
            self.isEnabled = isEnabled
        }

        func setEnabled(_ enabled: Bool) throws {
            requestedValues.append(enabled)
            if let error { throw error }
            isEnabled = enabled
        }
    }

    private struct TestError: LocalizedError {
        var errorDescription: String? { "Could not update login item" }
    }

    func testLaunchAtLoginControllerOnlyMutatesServiceAfterExplicitToggle() {
        let service = FakeLaunchAtLoginService(isEnabled: false)
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
        let service = FakeLaunchAtLoginService(isEnabled: false)
        service.error = TestError()
        let controller = LaunchAtLoginController(service: service)

        controller.setEnabled(true)

        XCTAssertFalse(controller.isEnabled)
        XCTAssertEqual(service.requestedValues, [true])
        XCTAssertEqual(controller.errorMessage, "Could not update login item")
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
