import AppKit
import SwiftUI

@main
struct WindowRangerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(
                store: appDelegate.settingsStore,
                engine: appDelegate.engine,
                navigation: appDelegate.settingsNavigation,
                windowCoordinator: appDelegate.settingsWindowCoordinator,
                diagnostics: appDelegate.diagnostics,
                updateController: appDelegate.updateController,
                shortcutRecordingStateChanged: appDelegate.shortcutRecordingStateDidChange,
                onboardingRestartRequested: appDelegate.restartOnboardingFromSettings
            )
        }
        .defaultSize(
            width: SettingsWindowMetrics.defaultSize.width,
            height: SettingsWindowMetrics.defaultSize.height
        )
        .windowResizability(.contentMinSize)
        .commands {
            WindowRangerSettingsCommands(
                navigation: appDelegate.settingsNavigation,
                engine: appDelegate.engine,
                coordinator: appDelegate.settingsWindowCoordinator,
                requestRouter: appDelegate.settingsCommandRequestRouter,
                updateController: appDelegate.updateController
            )
        }
    }
}

private struct WindowRangerSettingsCommands: Commands {
    @ObservedObject var navigation: SettingsNavigationModel
    let engine: WorkspaceEngine
    let coordinator: SettingsWindowCoordinator
    let requestRouter: SettingsCommandRequestRouter
    @ObservedObject var updateController: UpdateController
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                let request = requestRouter.consume()
                SettingsWindowOpener.open(
                    category: request.category,
                    preferPointerDisplay: request.preferPointerDisplay,
                    navigation: navigation,
                    engine: engine,
                    coordinator: coordinator,
                    openSettings: {
                        openSettings()
                        return true
                    }
                )
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                updateController.checkForUpdates()
            }
            .disabled(!updateController.canCheckForUpdates)
        }
    }
}
