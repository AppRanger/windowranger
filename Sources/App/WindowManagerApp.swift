import AppKit
import SwiftUI

@main
struct WindowManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(
                store: appDelegate.settingsStore,
                engine: appDelegate.engine,
                navigation: appDelegate.settingsNavigation,
                windowCoordinator: appDelegate.settingsWindowCoordinator,
                diagnostics: appDelegate.diagnostics,
                shortcutRecordingStateChanged: appDelegate.shortcutRecordingStateDidChange
            )
        }
        .defaultSize(
            width: SettingsWindowMetrics.defaultSize.width,
            height: SettingsWindowMetrics.defaultSize.height
        )
        .windowResizability(.contentMinSize)
        .commands {
            WindowManagerSettingsCommands(
                navigation: appDelegate.settingsNavigation,
                engine: appDelegate.engine,
                coordinator: appDelegate.settingsWindowCoordinator,
                requestRouter: appDelegate.settingsCommandRequestRouter
            )
        }
    }
}

private struct WindowManagerSettingsCommands: Commands {
    @ObservedObject var navigation: SettingsNavigationModel
    let engine: WorkspaceEngine
    let coordinator: SettingsWindowCoordinator
    let requestRouter: SettingsCommandRequestRouter
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
    }
}
