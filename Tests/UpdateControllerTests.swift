import Foundation
import XCTest

@MainActor
final class UpdateControllerTests: XCTestCase {
    func testDevelopmentBuildNeverUsesAnInjectedUpdater() {
        let service = UpdateServiceSpy()
        let controller = UpdateController(
            configuration: UpdateRuntimeConfiguration(
                buildChannel: .development,
                feedURL: URL(string: "https://updates.windowranger.app/appcast.xml"),
                publicKey: "public-key"
            ),
            updater: service
        )

        XCTAssertEqual(controller.availability, .developmentBuild)
        XCTAssertFalse(controller.canCheckForUpdates)
        controller.checkForUpdates()
        XCTAssertEqual(service.checkCount, 0)
    }

    func testStableAndBetaChannelSelectionUsesOnlyBetaAsAnAdditionalAllowedChannel() {
        let stable = UpdateRuntimeConfiguration(
            buildChannel: .stable,
            feedURL: URL(string: "https://updates.windowranger.app/appcast.xml"),
            publicKey: "public-key"
        )
        let beta = UpdateRuntimeConfiguration(
            buildChannel: .beta,
            feedURL: URL(string: "https://updates.windowranger.app/appcast.xml"),
            publicKey: "public-key"
        )

        XCTAssertEqual(stable.selectedFeedChannel(betaOptIn: false), .stable)
        XCTAssertEqual(stable.allowedChannels(betaOptIn: false), [])
        XCTAssertEqual(stable.selectedFeedChannel(betaOptIn: true), .beta)
        XCTAssertEqual(stable.allowedChannels(betaOptIn: true), ["beta"])
        XCTAssertEqual(beta.selectedFeedChannel(betaOptIn: false), .stable)
        XCTAssertEqual(beta.allowedChannels(betaOptIn: false), [])
    }

    func testConfigurationRefusesPlaceholderAndIncompletePublicBuildValues() {
        let placeholder = UpdateRuntimeConfiguration(infoDictionary: [
            UpdateRuntimeConfiguration.buildChannelKey: "stable",
            UpdateRuntimeConfiguration.feedURLKey: "$(WINDOWRANGER_UPDATE_FEED_URL)",
            UpdateRuntimeConfiguration.publicKeyKey: "$(WINDOWRANGER_UPDATE_PUBLIC_KEY)",
        ])
        let invalidURL = UpdateRuntimeConfiguration(
            buildChannel: .stable,
            feedURL: URL(string: "http://updates.windowranger.app/appcast.xml"),
            publicKey: "public-key"
        )

        XCTAssertEqual(placeholder.availability, .missingFeedURL)
        XCTAssertEqual(invalidURL.availability, .invalidFeedURL)
    }

    func testPreferencesAreLocalAndControllerSynchronizesThemWithUpdater() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = UpdatePreferences(defaults: defaults)
        preferences.betaOptIn = true
        preferences.automaticChecks = true
        preferences.automaticDownloads = true
        let service = UpdateServiceSpy()
        let controller = UpdateController(
            configuration: availableConfiguration,
            preferences: preferences,
            updater: service
        )

        XCTAssertTrue(controller.canCheckForUpdates)
        XCTAssertEqual(controller.selectedFeedChannel, .beta)
        XCTAssertTrue(service.automaticallyChecksForUpdates)
        XCTAssertTrue(service.automaticallyDownloadsUpdates)

        controller.automaticChecksEnabled = false
        controller.automaticDownloadsEnabled = false
        controller.betaUpdatesEnabled = false
        controller.checkForUpdates()

        XCTAssertFalse(defaults.bool(forKey: "windowranger.updates.automaticChecks"))
        XCTAssertFalse(defaults.bool(forKey: "windowranger.updates.automaticDownloads"))
        XCTAssertFalse(defaults.bool(forKey: "windowranger.updates.betaOptIn"))
        XCTAssertFalse(service.automaticallyChecksForUpdates)
        XCTAssertFalse(service.automaticallyDownloadsUpdates)
        XCTAssertEqual(service.checkCount, 1)
    }

    func testBetaBuildDefaultsToBetaButHonorsAPersistedOptOut() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = UpdatePreferences(defaults: defaults)
        let betaConfiguration = UpdateRuntimeConfiguration(
            buildChannel: .beta,
            feedURL: URL(string: "https://updates.windowranger.app/appcast.xml"),
            publicKey: "public-key"
        )

        let firstRun = UpdateController(
            configuration: betaConfiguration,
            preferences: preferences,
            updater: UpdateServiceSpy()
        )
        XCTAssertTrue(firstRun.betaUpdatesEnabled)
        XCTAssertEqual(firstRun.selectedFeedChannel, .beta)
        XCTAssertFalse(preferences.hasBetaOptInPreference())

        preferences.betaOptIn = false
        let optedOut = UpdateController(
            configuration: betaConfiguration,
            preferences: preferences,
            updater: UpdateServiceSpy()
        )
        XCTAssertFalse(optedOut.betaUpdatesEnabled)
        XCTAssertEqual(optedOut.selectedFeedChannel, .stable)
    }

    private var availableConfiguration: UpdateRuntimeConfiguration {
        UpdateRuntimeConfiguration(
            buildChannel: .stable,
            feedURL: URL(string: "https://updates.windowranger.app/appcast.xml"),
            publicKey: "public-key"
        )
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "UpdateControllerTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }
}

@MainActor
private final class UpdateServiceSpy: UpdateServicing {
    var automaticallyChecksForUpdates = false
    var automaticallyDownloadsUpdates = false
    private(set) var checkCount = 0

    func checkForUpdates() {
        checkCount += 1
    }
}
