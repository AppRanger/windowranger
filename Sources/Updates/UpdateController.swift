import Combine
import Foundation

#if canImport(Sparkle)
import Sparkle
#endif

@MainActor
protocol UpdateServicing: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }
    var canCheckForUpdates: Bool { get }
    func checkForUpdates()
}

/// Observable boundary for Settings and the menu bar. It intentionally owns only local update
/// preferences; release channel, feed URL, and signing key come from the signed application build.
@MainActor
final class UpdateController: NSObject, ObservableObject {
    @Published private(set) var availability: UpdateAvailability
    @Published private(set) var statusMessage: String?
    @Published private(set) var isCheckingForUpdates = false
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
    private let diagnostics: DiagnosticLogger
    private var updater: UpdateServicing?
    private var manualCheckRequestedAt: Date?
    private var pendingReadinessRetry: DispatchWorkItem?
    private var manualCheckDispatched = false
    private static let sparkleNoUpdateErrorCode = 1001

    #if canImport(Sparkle)
    private var standardUpdaterController: SPUStandardUpdaterController?
    #endif

    var canCheckForUpdates: Bool {
        availability == .available && updater != nil && !isCheckingForUpdates
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
        updater: UpdateServicing? = nil,
        diagnostics: DiagnosticLogger = .disabled
    ) {
        self.configuration = configuration
        self.preferences = preferences
        self.diagnostics = diagnostics
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
        guard availability == .available, updater != nil else {
            statusMessage = availability.message
            return
        }
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        statusMessage = "Checking for updates…"
        manualCheckRequestedAt = Date()
        diagnostics.log(category: "updates", event: "manual-check-requested")
        performManualCheckWhenReady()
    }

    private func performManualCheckWhenReady() {
        guard isCheckingForUpdates, let updater, let requestedAt = manualCheckRequestedAt else {
            return
        }
        guard updater.canCheckForUpdates else {
            if Date().timeIntervalSince(requestedAt) >= 30 {
                diagnostics.log(category: "updates", event: "updater-readiness-timeout")
                finishUpdateCheck(.failed)
                return
            }
            if pendingReadinessRetry == nil {
                diagnostics.log(category: "updates", event: "waiting-for-updater-readiness")
            }
            let retry = DispatchWorkItem { [weak self] in
                self?.performManualCheckWhenReady()
            }
            pendingReadinessRetry?.cancel()
            pendingReadinessRetry = retry
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: retry)
            return
        }

        pendingReadinessRetry?.cancel()
        pendingReadinessRetry = nil
        manualCheckDispatched = true
        let startedAt = Date()
        diagnostics.log(category: "updates", event: "manual-check-started")
        updater.checkForUpdates()
        diagnostics.log(
            category: "updates",
            event: "manual-check-call-returned",
            fields: [
                "duration-ms": String(Int(Date().timeIntervalSince(startedAt) * 1_000)),
            ]
        )
    }

    func finishUpdateCheck(_ result: UpdateCheckResult) {
        guard isCheckingForUpdates else { return }
        pendingReadinessRetry?.cancel()
        pendingReadinessRetry = nil
        manualCheckDispatched = false
        isCheckingForUpdates = false
        switch result {
        case .updateAvailable:
            statusMessage = "An update is available."
        case .upToDate:
            statusMessage = "WindowRanger is up to date."
        case .failed:
            statusMessage = "Couldn’t check for updates. Please try again."
        }
        var fields = ["result": result.diagnosticValue]
        if let manualCheckRequestedAt {
            fields["total-duration-ms"] = String(
                Int(Date().timeIntervalSince(manualCheckRequestedAt) * 1_000)
            )
        }
        self.manualCheckRequestedAt = nil
        diagnostics.log(category: "updates", event: "manual-check-finished", fields: fields)
    }

    #if canImport(Sparkle)
    static func completedCycleResult(error: NSError?) -> UpdateCheckResult {
        guard let error else { return .upToDate }
        if error.domain == SUSparkleErrorDomain && error.code == sparkleNoUpdateErrorCode {
            return .upToDate
        }
        return .failed
    }
    #endif

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

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor [weak self] in
            guard let self, self.manualCheckDispatched else { return }
            self.finishUpdateCheck(.updateAvailable)
        }
    }

    // Sparkle calls this compatibility hook after its installer-status probe. The newer NSError
    // bridge is not dynamically exposed by Swift 6.2 when supplied from an actor-isolated class.
    nonisolated func updaterMayCheck(forUpdates updater: SPUUpdater) -> Bool {
        Task { @MainActor [weak self] in
            self?.logManualCheckMilestone("installer-probe-finished")
        }
        return true
    }

    nonisolated func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        Task { @MainActor [weak self] in
            self?.logManualCheckMilestone("appcast-loaded")
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        Task { @MainActor [weak self] in
            self?.logManualCheckMilestone("update-cycle-aborted")
        }
    }

    nonisolated func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.manualCheckDispatched, updateCheck == .updates else { return }
            let error = error as NSError?
            self.finishUpdateCheck(Self.completedCycleResult(error: error))
        }
    }

    private func logManualCheckMilestone(_ milestone: String) {
        guard manualCheckDispatched, let manualCheckRequestedAt else { return }
        diagnostics.log(category: "updates", event: milestone, fields: [
            "elapsed-ms": String(Int(Date().timeIntervalSince(manualCheckRequestedAt) * 1_000)),
        ])
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

    var canCheckForUpdates: Bool {
        updater.canCheckForUpdates
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}
#endif

enum UpdateCheckResult: Equatable, Sendable {
    case updateAvailable
    case upToDate
    case failed

    var diagnosticValue: String {
        switch self {
        case .updateAvailable: "update-available"
        case .upToDate: "up-to-date"
        case .failed: "failed"
        }
    }
}
