import Foundation
import XCTest

#if canImport(Sparkle)
import Sparkle
#endif

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

    func testPreferencesAreLocalAndControllerSynchronizesThemWithUpdater() async {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = UpdatePreferences(defaults: defaults)
        preferences.betaOptIn = true
        preferences.automaticChecks = true
        preferences.automaticDownloads = true
        let service = UpdateServiceSpy()
        let checkCalled = expectation(description: "Updater check dispatched")
        service.onCheck = { checkCalled.fulfill() }
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

        await fulfillment(of: [checkCalled], timeout: 1)

        XCTAssertFalse(defaults.bool(forKey: "windowranger.updates.automaticChecks"))
        XCTAssertFalse(defaults.bool(forKey: "windowranger.updates.automaticDownloads"))
        XCTAssertFalse(defaults.bool(forKey: "windowranger.updates.betaOptIn"))
        XCTAssertFalse(service.automaticallyChecksForUpdates)
        XCTAssertFalse(service.automaticallyDownloadsUpdates)
        XCTAssertEqual(service.checkCount, 1)
    }

    func testManualCheckPublishesProgressAndRejectsDuplicateRequests() async {
        let service = UpdateServiceSpy()
        let checkCalled = expectation(description: "Updater check dispatched")
        service.onCheck = { checkCalled.fulfill() }
        let controller = UpdateController(
            configuration: availableConfiguration,
            updater: service
        )
        controller.checkForUpdates()
        controller.checkForUpdates()

        XCTAssertTrue(controller.isCheckingForUpdates)
        XCTAssertFalse(controller.canCheckForUpdates)
        XCTAssertEqual(controller.statusMessage, "Checking for updates…")
        XCTAssertEqual(service.checkCount, 1)
        await fulfillment(of: [checkCalled], timeout: 1)
        XCTAssertEqual(service.checkCount, 1)
    }

    func testManualCheckPublishesTerminalResults() {
        let service = UpdateServiceSpy()
        let controller = UpdateController(
            configuration: availableConfiguration,
            updater: service
        )

        controller.checkForUpdates()
        controller.finishUpdateCheck(.upToDate)
        XCTAssertFalse(controller.isCheckingForUpdates)
        XCTAssertTrue(controller.canCheckForUpdates)
        XCTAssertEqual(controller.statusMessage, "WindowRanger is up to date.")

        controller.checkForUpdates()
        controller.finishUpdateCheck(.updateAvailable)
        XCTAssertEqual(controller.statusMessage, "An update is available.")

        controller.checkForUpdates()
        controller.finishUpdateCheck(.failed)
        XCTAssertEqual(
            controller.statusMessage,
            "Couldn’t check for updates. Please try again."
        )
    }

    func testControllerExposesSparkleManualCheckDelegateCallbacks() {
        let controller = UpdateController(
            configuration: availableConfiguration,
            updater: UpdateServiceSpy()
        )

        XCTAssertTrue(controller.responds(to: NSSelectorFromString("updater:didFindValidUpdate:")))
        XCTAssertTrue(controller.responds(to: NSSelectorFromString("updaterMayCheckForUpdates:")))
        XCTAssertTrue(controller.responds(to: NSSelectorFromString("updater:didFinishLoadingAppcast:")))
        XCTAssertTrue(controller.responds(to: NSSelectorFromString("updater:didAbortWithError:")))
        XCTAssertTrue(controller.responds(to: NSSelectorFromString(
            "updater:didFinishUpdateCycleForUpdateCheck:error:"
        )))
    }

    func testManualCheckWaitsForSparkleStartupBeforeDispatching() async {
        let service = UpdateServiceSpy()
        service.canCheckForUpdates = false
        let controller = UpdateController(
            configuration: availableConfiguration,
            updater: service
        )

        controller.checkForUpdates()
        XCTAssertTrue(controller.isCheckingForUpdates)
        XCTAssertEqual(service.checkCount, 0)

        service.canCheckForUpdates = true
        try? await Task.sleep(for: .milliseconds(250))

        XCTAssertEqual(service.checkCount, 1)
    }

    func testSparkleCycleCompletionDistinguishesNoUpdateFromFailure() {
        XCTAssertEqual(UpdateController.completedCycleResult(error: nil), .upToDate)
        XCTAssertEqual(UpdateController.completedCycleResult(error: NSError(
            domain: SUSparkleErrorDomain,
            code: 1001
        )), .upToDate)
        XCTAssertEqual(UpdateController.completedCycleResult(error: NSError(
            domain: SUSparkleErrorDomain,
            code: 1002
        )), .failed)
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
    var canCheckForUpdates = true
    private(set) var checkCount = 0
    var onCheck: (() -> Void)?

    func checkForUpdates() {
        checkCount += 1
        onCheck?()
    }
}
