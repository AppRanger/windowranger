import XCTest

@MainActor
final class CLIConfigurationTests: XCTestCase {
    func testConfigurationApplyNormalizesAndPersistsTheCompleteDocument() {
        let suite = "CLIConfigurationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] }
        )
        var configuration = store.cliConfigurationSnapshot()
        configuration.workspaceSwipeEnabled = true
        configuration.workspaceSwipeFingerCount = 4
        configuration.commandPalettePosition = CommandPalettePosition.bottom.rawValue
        configuration.menuBarHighlightColor = "#abcdef"
        configuration.focusedWindowHighlightColor = "#123456"
        configuration.focusedWindowHighlightCornerRadiusOverrides = [
            " com.example.Window ": 12,
        ]
        configuration.automaticallyUnhideApplications = true

        let result = store.applyCLIConfiguration(configuration)
        guard case .success = result else {
            return XCTFail("Expected complete CLI configuration to apply: \(result)")
        }
        let applied = store.cliConfigurationSnapshot()
        XCTAssertTrue(applied.workspaceSwipeEnabled)
        XCTAssertEqual(applied.workspaceSwipeFingerCount, 4)
        XCTAssertEqual(applied.commandPalettePosition, CommandPalettePosition.bottom.rawValue)
        XCTAssertEqual(applied.menuBarHighlightColor, "#ABCDEF")
        XCTAssertEqual(applied.focusedWindowHighlightColor, "#123456")
        XCTAssertEqual(applied.focusedWindowHighlightCornerRadiusOverrides, ["com.example.window": 12])
        XCTAssertTrue(applied.automaticallyUnhideApplications)

        let restored = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] }
        )
        XCTAssertEqual(restored.cliConfigurationSnapshot(), applied)
    }

    func testConfigurationApplyRejectsInvalidInputWithoutMutatingStore() {
        let suite = "CLIConfigurationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] }
        )
        let before = store.cliConfigurationSnapshot()
        var invalid = before
        invalid.workspaceSwipeFingerCount = 2

        let result = store.applyCLIConfiguration(invalid)
        XCTAssertEqual(result, .failure(.invalidWorkspaceSwipeFingerCount(2)))
        XCTAssertEqual(store.cliConfigurationSnapshot(), before)
    }

    func testStrictConfigurationDecodeRejectsUnknownRootAndNestedFields() throws {
        let suite = "CLIConfigurationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] }
        )
        let configuration = WindowRangerCLIApplicationConfiguration(
            settings: store.cliConfigurationSnapshot(),
            launchAtLoginEnabled: false,
            updates: .init(
                betaUpdatesEnabled: false,
                automaticChecksEnabled: false,
                automaticDownloadsEnabled: false
            ),
            onboarding: .init(requiresOnboarding: false, currentStep: 0)
        )
        let data = try JSONEncoder().encode(configuration)
        let document = try JSONDecoder().decode(WindowRangerCLIJSONValue.self, from: data)
        XCTAssertEqual(
            try WindowRangerCLIApplicationConfiguration.decodeStrict(from: document),
            configuration
        )

        guard case var .object(root) = document,
              case var .object(settings) = root["settings"] else {
            return XCTFail("Expected object-shaped configuration")
        }
        root["misspelledRoot"] = .bool(true)
        XCTAssertThrowsError(try WindowRangerCLIApplicationConfiguration.decodeStrict(
            from: .object(root)
        )) { error in
            XCTAssertEqual(error as? WindowRangerCLIConfigurationError, .unknownField)
        }

        guard case var .object(cleanRoot) = document else { return }
        settings["misspelledNested"] = .bool(true)
        cleanRoot["settings"] = .object(settings)
        XCTAssertThrowsError(try WindowRangerCLIApplicationConfiguration.decodeStrict(
            from: .object(cleanRoot)
        )) { error in
            XCTAssertEqual(error as? WindowRangerCLIConfigurationError, .unknownField)
        }
    }

    func testApplicationPreflightRejectsEnablingICloudWithoutMutatingSettings() {
        let suite = "CLIConfigurationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] }
        )
        let before = store.cliConfigurationSnapshot()
        var settings = before
        settings.iCloudSyncEnabled = true
        let configuration = WindowRangerCLIApplicationConfiguration(
            settings: settings,
            launchAtLoginEnabled: false,
            updates: .init(
                betaUpdatesEnabled: false,
                automaticChecksEnabled: false,
                automaticDownloadsEnabled: false
            ),
            onboarding: .init(requiresOnboarding: false, currentStep: 0)
        )

        XCTAssertEqual(
            configuration.applicationPreflightError(currentlyICloudSyncEnabled: false),
            .confirmationRequired
        )
        XCTAssertNil(configuration.applicationPreflightError(currentlyICloudSyncEnabled: true))
        XCTAssertEqual(store.cliConfigurationSnapshot(), before)
    }
}
