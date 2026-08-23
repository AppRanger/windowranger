import Foundation

/// The distribution channel baked into an application build. Development builds deliberately never
/// create an updater, even when a developer happens to have update preferences on this Mac.
enum UpdateBuildChannel: String, CaseIterable, Equatable {
    case development
    case stable
    case beta

    init(rawValue: String?) {
        switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "stable":
            self = .stable
        case "beta":
            self = .beta
        default:
            self = .development
        }
    }

    var supportsUpdates: Bool {
        self != .development
    }
}

/// A user-facing choice, independent from the distribution channel of the installed build.
enum UpdateFeedChannel: String, Equatable {
    case stable
    case beta
}

enum UpdateAvailability: Equatable {
    case available
    case developmentBuild
    case missingFeedURL
    case invalidFeedURL
    case missingPublicKey
    case frameworkUnavailable

    var message: String {
        switch self {
        case .available:
            return "Updates are ready."
        case .developmentBuild:
            return "Updates are unavailable in development builds."
        case .missingFeedURL:
            return "Updates are unavailable because this build has no update feed."
        case .invalidFeedURL:
            return "Updates are unavailable because this build has an invalid update feed URL."
        case .missingPublicKey:
            return "Updates are unavailable because this build has no update signing key."
        case .frameworkUnavailable:
            return "Updates are unavailable because the updater framework is not included in this build."
        }
    }
}

/// The small, testable boundary between build-time Info.plist values and the update runtime.
///
/// These values are intentionally not profile settings and are never read from iCloud.
struct UpdateRuntimeConfiguration: Equatable {
    static let buildChannelKey = "WindowRangerUpdateChannel"
    static let feedURLKey = "SUFeedURL"
    static let publicKeyKey = "SUPublicEDKey"

    let buildChannel: UpdateBuildChannel
    let feedURL: URL?
    let publicKey: String?

    init(
        buildChannel: UpdateBuildChannel,
        feedURL: URL?,
        publicKey: String?
    ) {
        self.buildChannel = buildChannel
        self.feedURL = feedURL
        self.publicKey = Self.normalized(publicKey)
    }

    init(infoDictionary: [String: Any]) {
        let rawFeedURL = Self.normalized(infoDictionary[Self.feedURLKey] as? String)
        self.init(
            buildChannel: UpdateBuildChannel(rawValue: infoDictionary[Self.buildChannelKey] as? String),
            feedURL: rawFeedURL.flatMap(URL.init(string:)),
            publicKey: infoDictionary[Self.publicKeyKey] as? String
        )
    }

    static var mainBundle: UpdateRuntimeConfiguration {
        UpdateRuntimeConfiguration(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }

    var availability: UpdateAvailability {
        guard buildChannel.supportsUpdates else { return .developmentBuild }
        guard let feedURL else { return .missingFeedURL }
        guard feedURL.scheme?.lowercased() == "https", feedURL.host != nil else {
            return .invalidFeedURL
        }
        guard publicKey != nil else { return .missingPublicKey }
        return .available
    }

    func selectedFeedChannel(betaOptIn: Bool) -> UpdateFeedChannel {
        betaOptIn ? .beta : .stable
    }

    func allowedChannels(betaOptIn: Bool) -> Set<String> {
        selectedFeedChannel(betaOptIn: betaOptIn) == .beta ? [UpdateFeedChannel.beta.rawValue] : []
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              !normalized.hasPrefix("$(")
        else { return nil }
        return normalized
    }
}

/// Local update preferences. They are deliberately separate from SettingsStore so profiles and
/// iCloud sync cannot make one Mac join a beta channel or change another Mac's update behaviour.
struct UpdatePreferences {
    private enum Keys {
        static let betaOptIn = "windowranger.updates.betaOptIn"
        static let automaticChecks = "windowranger.updates.automaticChecks"
        static let automaticDownloads = "windowranger.updates.automaticDownloads"
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var betaOptIn: Bool {
        get { defaults.bool(forKey: Keys.betaOptIn) }
        nonmutating set { defaults.set(newValue, forKey: Keys.betaOptIn) }
    }

    func hasBetaOptInPreference() -> Bool {
        defaults.object(forKey: Keys.betaOptIn) != nil
    }

    var automaticChecks: Bool {
        get { defaults.bool(forKey: Keys.automaticChecks) }
        nonmutating set { defaults.set(newValue, forKey: Keys.automaticChecks) }
    }

    var automaticDownloads: Bool {
        get { defaults.bool(forKey: Keys.automaticDownloads) }
        nonmutating set { defaults.set(newValue, forKey: Keys.automaticDownloads) }
    }

    func hasAutomaticChecksPreference() -> Bool {
        defaults.object(forKey: Keys.automaticChecks) != nil
    }

    func hasAutomaticDownloadsPreference() -> Bool {
        defaults.object(forKey: Keys.automaticDownloads) != nil
    }
}
