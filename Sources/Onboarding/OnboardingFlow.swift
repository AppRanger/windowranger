import AppKit
import Carbon
import Combine
import Foundation

enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable {
    case welcome
    case iCloud
    case shortcuts
    case focusBorder
    case menuBar
    case quickAppShelf
    case workspaces

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .iCloud: "iCloud"
        case .shortcuts: "Shortcuts"
        case .focusBorder: "Focus Border"
        case .menuBar: "Menu Bar"
        case .quickAppShelf: "Quick App Shelf"
        case .workspaces: "Workspaces"
        }
    }

    var systemImage: String {
        switch self {
        case .welcome: "sparkles"
        case .iCloud: "icloud"
        case .shortcuts: "keyboard"
        case .focusBorder: "viewfinder"
        case .menuBar: "menubar.rectangle"
        case .quickAppShelf: "square.stack.3d.up"
        case .workspaces: "rectangle.3.group"
        }
    }

    var assetName: String {
        switch self {
        case .welcome: "OnboardingWelcome"
        case .iCloud: "OnboardingICloud"
        case .shortcuts: "OnboardingShortcuts"
        case .focusBorder: "OnboardingFocusBorder"
        case .menuBar: "OnboardingMenuBar"
        case .quickAppShelf: "OnboardingQuickAppShelf"
        case .workspaces: "OnboardingWorkspaces"
        }
    }
}

struct OnboardingWindowConfiguration: Equatable, Sendable {
    static let contentSize = CGSize(width: 980, height: 660)
    static let isResizable = false
    static let isReleasedWhenClosed = false
    static let level: NSWindow.Level = .floating
    static let collectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
    ]
}

@MainActor
enum OnboardingRestartHandoff {
    static func perform(
        dismissSettings: () -> Void,
        schedulePresentation: (@escaping () -> Void) -> Void,
        presentOnboarding: @escaping () -> Void
    ) {
        dismissSettings()
        schedulePresentation(presentOnboarding)
    }
}

/// Onboarding is local application progress, not reusable profile content or a synced preference.
final class OnboardingProgressStore {
    static let currentVersion = 1

    private enum Keys {
        static let completedVersion = "windowranger.onboarding.completedVersion"

        static func currentStep(version: Int) -> String {
            "windowranger.onboarding.currentStep.v\(version)"
        }
    }

    private let defaults: UserDefaults
    private let version: Int

    init(defaults: UserDefaults = .standard, version: Int = currentVersion) {
        self.defaults = defaults
        self.version = version
    }

    var requiresOnboarding: Bool {
        defaults.integer(forKey: Keys.completedVersion) < version
    }

    var currentStep: OnboardingStep {
        let key = Keys.currentStep(version: version)
        guard requiresOnboarding,
              defaults.object(forKey: key) != nil,
              let step = OnboardingStep(rawValue: defaults.integer(forKey: key))
        else { return .welcome }
        return step
    }

    var configurationSnapshot: WindowRangerCLIOnboardingConfiguration {
        WindowRangerCLIOnboardingConfiguration(
            requiresOnboarding: requiresOnboarding,
            currentStep: currentStep.rawValue
        )
    }

    func apply(configuration: WindowRangerCLIOnboardingConfiguration) -> Bool {
        guard let step = OnboardingStep(rawValue: configuration.currentStep) else { return false }
        if configuration.requiresOnboarding {
            defaults.removeObject(forKey: Keys.completedVersion)
            defaults.set(step.rawValue, forKey: Keys.currentStep(version: version))
        } else {
            defaults.set(version, forKey: Keys.completedVersion)
            defaults.removeObject(forKey: Keys.currentStep(version: version))
        }
        return true
    }

    func save(step: OnboardingStep) {
        guard requiresOnboarding else { return }
        defaults.set(step.rawValue, forKey: Keys.currentStep(version: version))
    }

    func complete() {
        defaults.set(version, forKey: Keys.completedVersion)
        defaults.removeObject(forKey: Keys.currentStep(version: version))
    }

    func restartFromBeginning() {
        defaults.removeObject(forKey: Keys.completedVersion)
        defaults.set(
            OnboardingStep.welcome.rawValue,
            forKey: Keys.currentStep(version: version)
        )
    }
}

@MainActor
final class OnboardingCoordinator: ObservableObject {
    static let shortcutFamilyModifierChoices: [UInt32] = [
        UInt32(controlKey | optionKey), UInt32(controlKey | cmdKey), UInt32(optionKey | cmdKey),
        UInt32(controlKey | shiftKey), UInt32(optionKey | shiftKey), UInt32(cmdKey | shiftKey),
        UInt32(controlKey | optionKey | shiftKey), UInt32(controlKey | optionKey | cmdKey),
        UInt32(controlKey | cmdKey | shiftKey), UInt32(optionKey | cmdKey | shiftKey),
        UInt32(controlKey | optionKey | cmdKey | shiftKey),
    ]

    @Published private(set) var step: OnboardingStep
    @Published private(set) var shortcutConflictMessage: String?

    let settingsStore: SettingsStore
    var supportsICloudSync: Bool { settingsStore.supportsICloudSync }
    private let progressStore: OnboardingProgressStore
    private let finishAction: () -> Void

    init(
        settingsStore: SettingsStore,
        progressStore: OnboardingProgressStore = OnboardingProgressStore(),
        finishAction: @escaping () -> Void
    ) {
        self.settingsStore = settingsStore
        self.progressStore = progressStore
        self.finishAction = finishAction
        step = progressStore.currentStep
    }

    var stepNumber: Int { step.rawValue + 1 }
    var canGoBack: Bool { step != .welcome }
    var isFinalStep: Bool { step == .workspaces }

    func goBack() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        move(to: previous)
    }

    func goForward() {
        if isFinalStep {
            progressStore.complete()
            finishAction()
            return
        }
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        move(to: next)
    }

    func move(to step: OnboardingStep) {
        self.step = step
        shortcutConflictMessage = nil
        progressStore.save(step: step)
    }

    func setICloudSyncEnabled(_ enabled: Bool) {
        guard supportsICloudSync else { return }
        settingsStore.iCloudSyncEnabled = enabled
    }

    func replaceICloudSettingsWithLocalCopy() {
        guard supportsICloudSync else { return }
        settingsStore.replaceICloudSettingsWithLocalCopy()
    }

    func setShortcutFamilyModifiers(_ modifiers: UInt32, for family: ShortcutFamily) {
        shortcutConflictMessage = settingsStore.setShortcutFamilyModifiers(modifiers, for: family)
        if shortcutConflictMessage != nil { NSSound.beep() }
    }

    func availableShortcutFamilyModifierChoices(for family: ShortcutFamily) -> [UInt32] {
        let configuration = settingsStore.hotKeyConfiguration
        return Self.shortcutFamilyModifierChoices.filter { candidate in
            let navigate = family == .navigate
                ? candidate
                : configuration.modifierMask(for: .navigate)
            let arrange = family == .arrange
                ? candidate
                : configuration.modifierMask(for: .arrange)
            return HotKeyConfiguration.familyValidationMessage(
                navigate: navigate,
                arrange: arrange
            ) == nil
        }
    }

    func setFocusBorderEnabled(_ enabled: Bool) {
        settingsStore.focusedWindowHighlightEnabled = enabled
    }

    func setFocusBorderColor(_ color: MenuBarHighlightColor) {
        settingsStore.focusedWindowHighlightColor = color
    }

    func setMenuBarPresentation(_ mode: MenuBarPresentationMode) {
        settingsStore.menuBarPresentationMode = mode
    }

    func addQuickApp(_ application: InstalledApplication) {
        settingsStore.setSettingsQuickApp(application)
    }

    func removeQuickApp(at index: Int) {
        settingsStore.removeSettingsQuickApp(at: index)
    }

    func moveQuickApps(from source: IndexSet, to destination: Int) {
        settingsStore.moveSettingsQuickApps(from: source, to: destination)
    }

    func setWorkspaceSwipeEnabled(_ enabled: Bool) {
        settingsStore.workspaceSwipeEnabled = enabled
    }

    func setWorkspaceSwipeFingerCount(_ count: WorkspaceSwipeFingerCount) {
        settingsStore.workspaceSwipeFingerCount = count
    }
}
