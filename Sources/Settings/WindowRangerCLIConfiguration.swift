import Foundation

/// Top-level configuration seen by the CLI. `settings` contains WindowRanger's synced and
/// machine-local window-management preferences; the remaining values are durable app settings
/// owned by macOS or other controllers rather than SettingsStore.
struct WindowRangerCLIApplicationConfiguration: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    var settings: WindowRangerCLIConfiguration
    var launchAtLoginEnabled: Bool
    var updates: WindowRangerCLIUpdateConfiguration
    var onboarding: WindowRangerCLIOnboardingConfiguration

    init(
        version: Int = Self.currentVersion,
        settings: WindowRangerCLIConfiguration,
        launchAtLoginEnabled: Bool,
        updates: WindowRangerCLIUpdateConfiguration,
        onboarding: WindowRangerCLIOnboardingConfiguration
    ) {
        self.version = version
        self.settings = settings
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.updates = updates
        self.onboarding = onboarding
    }

    func validated() -> Result<Self, WindowRangerCLIConfigurationError> {
        guard version == Self.currentVersion else { return .failure(.unsupportedVersion(version)) }
        guard OnboardingStep(rawValue: onboarding.currentStep) != nil else {
            return .failure(.invalidOnboardingStep(onboarding.currentStep))
        }
        switch settings.validated() {
        case let .failure(error): return .failure(error)
        case let .success(settings):
            var normalized = self
            normalized.settings = settings
            return .success(normalized)
        }
    }

    func applicationPreflightError(
        currentlyICloudSyncEnabled: Bool
    ) -> WindowRangerCLIErrorCode? {
        guard currentlyICloudSyncEnabled || !settings.iCloudSyncEnabled else {
            return .confirmationRequired
        }
        return nil
    }

    static func decodeStrict(
        from document: WindowRangerCLIJSONValue
    ) throws -> WindowRangerCLIApplicationConfiguration {
        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(Self.self, from: data)
        let canonicalData = try JSONEncoder().encode(decoded)
        let canonical = try JSONDecoder().decode(
            WindowRangerCLIJSONValue.self,
            from: canonicalData
        )
        guard document.containsNoUnknownFields(comparedTo: canonical) else {
            throw WindowRangerCLIConfigurationError.unknownField
        }
        return decoded
    }
}

struct WindowRangerCLIUpdateConfiguration: Codable, Equatable, Sendable {
    var betaUpdatesEnabled: Bool
    var automaticChecksEnabled: Bool
    var automaticDownloadsEnabled: Bool
}

struct WindowRangerCLIOnboardingConfiguration: Codable, Equatable, Sendable {
    var requiresOnboarding: Bool
    var currentStep: Int
}

/// The complete durable configuration controlled by WindowRanger's CLI.
///
/// This deliberately contains both the reusable, iCloud-synchronised profile library and the
/// local choices which describe one Mac. Runtime diagnostics, granted permissions, connected
/// displays, and the current Game Mode observation are intentionally absent: they are observed
/// state, not configuration an agent can safely restore.
struct WindowRangerCLIConfiguration: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    var profileLibrary: ProfileLibrary
    var localProfileState: ProfileLocalState
    var settingsProfileID: UUID

    var iCloudSyncEnabled: Bool
    var radialMenuEnabled: Bool
    var radialWheelDefinition: RadialWheelDefinition
    var hotKeyConfiguration: HotKeyConfiguration

    var commandPalettePosition: String
    var workspaceSwipeEnabled: Bool
    /// Kept as an integer in the CLI document so it remains a stable wire value rather than an
    /// implementation enum. Only the supported physical gesture counts are accepted on apply.
    var workspaceSwipeFingerCount: Int
    var shortcutGuideEnabled: Bool
    var shortcutGuideSize: String
    var shortcutGuidePosition: String

    var menuBarPresentationMode: String
    var menuBarWorkspaceLabelMode: String
    /// Six-digit sRGB values are portable across AppKit generations.
    var menuBarHighlightColor: String
    var workspacePreviewThumbnailsEnabled: Bool

    var focusedWindowHighlightEnabled: Bool
    var focusedWindowHighlightColor: String
    var focusedWindowHighlightTiledOnly: Bool
    var focusedWindowHighlightMultipleWindowsOnly: Bool
    var focusedWindowHighlightCornerRadiusOverrides: [String: Double]

    var focusFollowsMovedWindow: Bool
    var automaticallyUnhideApplications: Bool

    init(
        version: Int = Self.currentVersion,
        profileLibrary: ProfileLibrary,
        localProfileState: ProfileLocalState,
        settingsProfileID: UUID,
        iCloudSyncEnabled: Bool,
        radialMenuEnabled: Bool,
        radialWheelDefinition: RadialWheelDefinition,
        hotKeyConfiguration: HotKeyConfiguration,
        commandPalettePosition: String,
        workspaceSwipeEnabled: Bool,
        workspaceSwipeFingerCount: Int,
        shortcutGuideEnabled: Bool,
        shortcutGuideSize: String,
        shortcutGuidePosition: String,
        menuBarPresentationMode: String,
        menuBarWorkspaceLabelMode: String,
        menuBarHighlightColor: String,
        workspacePreviewThumbnailsEnabled: Bool,
        focusedWindowHighlightEnabled: Bool,
        focusedWindowHighlightColor: String,
        focusedWindowHighlightTiledOnly: Bool,
        focusedWindowHighlightMultipleWindowsOnly: Bool,
        focusedWindowHighlightCornerRadiusOverrides: [String: Double],
        focusFollowsMovedWindow: Bool,
        automaticallyUnhideApplications: Bool
    ) {
        self.version = version
        self.profileLibrary = profileLibrary
        self.localProfileState = localProfileState
        self.settingsProfileID = settingsProfileID
        self.iCloudSyncEnabled = iCloudSyncEnabled
        self.radialMenuEnabled = radialMenuEnabled
        self.radialWheelDefinition = radialWheelDefinition
        self.hotKeyConfiguration = hotKeyConfiguration
        self.commandPalettePosition = commandPalettePosition
        self.workspaceSwipeEnabled = workspaceSwipeEnabled
        self.workspaceSwipeFingerCount = workspaceSwipeFingerCount
        self.shortcutGuideEnabled = shortcutGuideEnabled
        self.shortcutGuideSize = shortcutGuideSize
        self.shortcutGuidePosition = shortcutGuidePosition
        self.menuBarPresentationMode = menuBarPresentationMode
        self.menuBarWorkspaceLabelMode = menuBarWorkspaceLabelMode
        self.menuBarHighlightColor = menuBarHighlightColor
        self.workspacePreviewThumbnailsEnabled = workspacePreviewThumbnailsEnabled
        self.focusedWindowHighlightEnabled = focusedWindowHighlightEnabled
        self.focusedWindowHighlightColor = focusedWindowHighlightColor
        self.focusedWindowHighlightTiledOnly = focusedWindowHighlightTiledOnly
        self.focusedWindowHighlightMultipleWindowsOnly = focusedWindowHighlightMultipleWindowsOnly
        self.focusedWindowHighlightCornerRadiusOverrides = focusedWindowHighlightCornerRadiusOverrides
        self.focusFollowsMovedWindow = focusFollowsMovedWindow
        self.automaticallyUnhideApplications = automaticallyUnhideApplications
    }
}

enum WindowRangerCLIConfigurationError: Error, Equatable, Sendable, LocalizedError {
    case unsupportedVersion(Int)
    case invalidProfileLibrary(String)
    case unsupportedLocalStateVersion(Int)
    case unknownSettingsProfile(UUID)
    case invalidCommandPalettePosition(String)
    case invalidWorkspaceSwipeFingerCount(Int)
    case invalidShortcutGuideSize(String)
    case invalidShortcutGuidePosition(String)
    case invalidMenuBarPresentationMode(String)
    case invalidMenuBarWorkspaceLabelMode(String)
    case invalidColor(field: String, value: String)
    case invalidCornerRadiusOverride(bundleIdentifier: String, value: Double)
    case invalidRadialWheel
    case invalidOnboardingStep(Int)
    case unknownField

    var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version):
            "Unsupported WindowRanger CLI configuration version \(version)."
        case let .invalidProfileLibrary(message):
            "Invalid profile library: \(message)"
        case let .unsupportedLocalStateVersion(version):
            "Unsupported local profile state version \(version)."
        case let .unknownSettingsProfile(id):
            "The selected Settings profile \(id.uuidString) is not in the profile library."
        case let .invalidCommandPalettePosition(value):
            "Unsupported command palette position '\(value)'."
        case let .invalidWorkspaceSwipeFingerCount(value):
            "Workspace swipe finger count must be 3 or 4, not \(value)."
        case let .invalidShortcutGuideSize(value):
            "Unsupported shortcut guide size '\(value)'."
        case let .invalidShortcutGuidePosition(value):
            "Unsupported shortcut guide position '\(value)'."
        case let .invalidMenuBarPresentationMode(value):
            "Unsupported menu bar presentation mode '\(value)'."
        case let .invalidMenuBarWorkspaceLabelMode(value):
            "Unsupported menu bar workspace label mode '\(value)'."
        case let .invalidColor(field, value):
            "\(field) must be a six-digit sRGB hex colour, not '\(value)'."
        case let .invalidCornerRadiusOverride(bundleIdentifier, value):
            "Corner radius override for '\(bundleIdentifier)' must be finite and between 0 and 40, not \(value)."
        case .invalidRadialWheel:
            "The radial wheel must use the current format with known, non-duplicated items."
        case let .invalidOnboardingStep(step):
            "Unsupported onboarding step \(step)."
        case .unknownField:
            "The configuration contains an unknown or misspelled field."
        }
    }
}

struct WindowRangerCLIConfigurationApplyResult: Equatable, Sendable {
    let profileCount: Int
    let activeProfileID: UUID
    let settingsProfileID: UUID
}

extension WindowRangerCLIConfiguration {
    /// Performs all decoding, policy validation, and normalisation before SettingsStore changes a
    /// single published value. The returned document is canonical and can be persisted as-is.
    func validated() -> Result<WindowRangerCLIConfiguration, WindowRangerCLIConfigurationError> {
        guard version == Self.currentVersion else { return .failure(.unsupportedVersion(version)) }
        guard localProfileState.version == ProfileLocalState.currentVersion else {
            return .failure(.unsupportedLocalStateVersion(localProfileState.version))
        }
        guard let libraryData = try? JSONEncoder().encode(profileLibrary) else {
            return .failure(.invalidProfileLibrary("could not encode the document"))
        }
        let library: ProfileLibrary
        switch SyncedProfileLibraryPolicy.validate(libraryData) {
        case let .accepted(valid):
            library = valid
        case let .rejected(rejection):
            return .failure(.invalidProfileLibrary(rejection.userMessage))
        case .absent:
            return .failure(.invalidProfileLibrary("the document is empty"))
        }
        guard library.profiles.contains(where: { $0.id == settingsProfileID }) else {
            return .failure(.unknownSettingsProfile(settingsProfileID))
        }
        guard let palettePosition = CommandPalettePosition(rawValue: commandPalettePosition) else {
            return .failure(.invalidCommandPalettePosition(commandPalettePosition))
        }
        guard let fingerCount = WorkspaceSwipeFingerCount(rawValue: workspaceSwipeFingerCount) else {
            return .failure(.invalidWorkspaceSwipeFingerCount(workspaceSwipeFingerCount))
        }
        guard let guideSize = ShortcutGuideSize(rawValue: shortcutGuideSize) else {
            return .failure(.invalidShortcutGuideSize(shortcutGuideSize))
        }
        guard let guidePosition = ShortcutGuidePosition(rawValue: shortcutGuidePosition) else {
            return .failure(.invalidShortcutGuidePosition(shortcutGuidePosition))
        }
        guard let menuPresentation = MenuBarPresentationMode(rawValue: menuBarPresentationMode) else {
            return .failure(.invalidMenuBarPresentationMode(menuBarPresentationMode))
        }
        guard let labelMode = MenuBarWorkspaceLabelMode(rawValue: menuBarWorkspaceLabelMode) else {
            return .failure(.invalidMenuBarWorkspaceLabelMode(menuBarWorkspaceLabelMode))
        }
        guard let menuColor = MenuBarHighlightColor(hex: menuBarHighlightColor) else {
            return .failure(.invalidColor(field: "menuBarHighlightColor", value: menuBarHighlightColor))
        }
        guard let focusColor = MenuBarHighlightColor(hex: focusedWindowHighlightColor) else {
            return .failure(.invalidColor(field: "focusedWindowHighlightColor", value: focusedWindowHighlightColor))
        }
        guard radialWheelDefinition.version == RadialWheelDefinition.currentVersion,
              !radialWheelDefinition.hasUnresolvedReferences,
              radialWheelDefinition.repaired() == radialWheelDefinition
        else {
            return .failure(.invalidRadialWheel)
        }
        for (bundleIdentifier, radius) in focusedWindowHighlightCornerRadiusOverrides {
            let normalizedIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedIdentifier.isEmpty,
                  radius.isFinite,
                  FocusedWindowHighlightPolicy.cornerRadiusRange.contains(radius)
            else {
                return .failure(.invalidCornerRadiusOverride(
                    bundleIdentifier: bundleIdentifier,
                    value: radius
                ))
            }
        }

        var local = localProfileState
        local.normalize(validProfiles: library.profiles)
        let canonicalOverrides = Dictionary(
            focusedWindowHighlightCornerRadiusOverrides.map { key, value in
                (key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), value)
            },
            uniquingKeysWith: { _, latest in latest }
        )
        return .success(WindowRangerCLIConfiguration(
            profileLibrary: library,
            localProfileState: local,
            settingsProfileID: settingsProfileID,
            iCloudSyncEnabled: iCloudSyncEnabled,
            radialMenuEnabled: radialMenuEnabled,
            radialWheelDefinition: radialWheelDefinition,
            hotKeyConfiguration: hotKeyConfiguration,
            commandPalettePosition: palettePosition.rawValue,
            workspaceSwipeEnabled: workspaceSwipeEnabled,
            workspaceSwipeFingerCount: fingerCount.rawValue,
            shortcutGuideEnabled: shortcutGuideEnabled,
            shortcutGuideSize: guideSize.rawValue,
            shortcutGuidePosition: guidePosition.rawValue,
            menuBarPresentationMode: menuPresentation.rawValue,
            menuBarWorkspaceLabelMode: labelMode.rawValue,
            menuBarHighlightColor: menuColor.hex,
            workspacePreviewThumbnailsEnabled: workspacePreviewThumbnailsEnabled,
            focusedWindowHighlightEnabled: focusedWindowHighlightEnabled,
            focusedWindowHighlightColor: focusColor.hex,
            focusedWindowHighlightTiledOnly: focusedWindowHighlightTiledOnly,
            focusedWindowHighlightMultipleWindowsOnly: focusedWindowHighlightMultipleWindowsOnly,
            focusedWindowHighlightCornerRadiusOverrides: canonicalOverrides,
            focusFollowsMovedWindow: focusFollowsMovedWindow,
            automaticallyUnhideApplications: automaticallyUnhideApplications
        ))
    }
}
