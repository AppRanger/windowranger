import Combine
import Foundation

#if canImport(Sparkle)
import Sparkle
#endif

@MainActor
protocol UpdateServicing: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }
    func checkForUpdates()
}

/// Observable boundary for Settings and the menu bar. It intentionally owns only local update
/// preferences; release channel, feed URL, and signing key come from the signed application build.
@MainActor
final class UpdateController: NSObject, ObservableObject {
    @Published private(set) var availability: UpdateAvailability
    @Published private(set) var statusMessage: String?
    @Published var betaUpdatesEnabled: Bool {
        didSet {
            guard betaUpdatesEnabled != oldValue else { return }
            preferences.betaOptIn = betaUpdatesEnabled
        }
    }
    @Published var automaticChecksEnabled: Bool {
        didSet {
            guard automaticChecksEnabled != oldValue else { return }
            preferences.automaticChecks = automaticChecksEnabled
            updater?.automaticallyChecksForUpdates = automaticChecksEnabled
        }
    }
    @Published var automaticDownloadsEnabled: Bool {
        didSet {
            guard automaticDownloadsEnabled != oldValue else { return }
            preferences.automaticDownloads = automaticDownloadsEnabled
            updater?.automaticallyDownloadsUpdates = automaticDownloadsEnabled
        }
    }

    let configuration: UpdateRuntimeConfiguration

    private let preferences: UpdatePreferences
    private var updater: UpdateServicing?

    #if canImport(Sparkle)
    private var standardUpdaterController: SPUStandardUpdaterController?
    #endif

    var canCheckForUpdates: Bool {
        availability == .available && updater != nil
    }

    var selectedFeedChannel: UpdateFeedChannel {
        configuration.selectedFeedChannel(betaOptIn: betaUpdatesEnabled)
    }

    override convenience init() {
        self.init(configuration: .mainBundle)
    }

    init(
        configuration: UpdateRuntimeConfiguration,
        preferences: UpdatePreferences = UpdatePreferences(),
        updater: UpdateServicing? = nil
    ) {
        self.configuration = configuration
        self.preferences = preferences
        availability = configuration.availability
        statusMessage = configuration.availability == .available ? nil : configuration.availability.message
        // A Beta artifact starts in the Beta channel so it can discover the next Beta build. Once
        // the user has made a choice, that local choice wins—even on a Beta artifact—so opting out
        // naturally returns them to the default Stable channel without attempting a downgrade.
        betaUpdatesEnabled = preferences.hasBetaOptInPreference()
            ? preferences.betaOptIn
            : configuration.buildChannel == .beta
        automaticChecksEnabled = preferences.automaticChecks
        automaticDownloadsEnabled = preferences.automaticDownloads
        self.updater = updater
        super.init()

        guard availability == .available else {
            // A caller cannot accidentally make a development or malformed build contact an updater.
            self.updater = nil
            return
        }

        if self.updater == nil {
            installStandardUpdaterIfAvailable()
        }

        guard let updater = self.updater else { return }
        if !preferences.hasAutomaticChecksPreference() {
            automaticChecksEnabled = updater.automaticallyChecksForUpdates
        } else {
            updater.automaticallyChecksForUpdates = automaticChecksEnabled
        }
        if !preferences.hasAutomaticDownloadsPreference() {
            automaticDownloadsEnabled = updater.automaticallyDownloadsUpdates
        } else {
            updater.automaticallyDownloadsUpdates = automaticDownloadsEnabled
        }
    }

    func checkForUpdates() {
        guard let updater, canCheckForUpdates else {
            statusMessage = availability.message
            return
        }
        statusMessage = nil
        updater.checkForUpdates()
    }

    private func installStandardUpdaterIfAvailable() {
        #if canImport(Sparkle)
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        standardUpdaterController = controller
        updater = SparkleUpdateService(updater: controller.updater)
        #else
        availability = .frameworkUnavailable
        statusMessage = availability.message
        #endif
    }
}

#if canImport(Sparkle)
@MainActor
extension UpdateController: SPUUpdaterDelegate {
    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        // Sparkle always includes the default channel. Supplying beta merely opts the user into the
        // additional beta channel, so a beta user still receives a newer stable release.
        MainActor.assumeIsolated {
            configuration.allowedChannels(betaOptIn: betaUpdatesEnabled)
        }
    }
}

@MainActor
private final class SparkleUpdateService: UpdateServicing {
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
    }

    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { updater.automaticallyDownloadsUpdates }
        set { updater.automaticallyDownloadsUpdates = newValue }
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}
#endif
