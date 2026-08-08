import AppKit
import SwiftUI

@main
struct WindowManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            WindowManagerAppMenu(
                navigation: appDelegate.settingsNavigation,
                settingsStore: appDelegate.settingsStore,
                engine: appDelegate.engine,
                settingsWindowCoordinator: appDelegate.settingsWindowCoordinator,
                menuBarState: appDelegate.menuBarState,
                diagnostics: appDelegate.diagnostics
            )
        } label: {
            WindowManagerPrimaryMenuLabel(
                state: appDelegate.menuBarState,
                settingsStore: appDelegate.settingsStore
            )
        }
        .menuBarExtraStyle(.menu)

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
        .defaultSize(width: 920, height: 650)
        .windowResizability(.contentMinSize)
        .commands {
            WindowManagerSettingsCommands(
                navigation: appDelegate.settingsNavigation,
                engine: appDelegate.engine,
                coordinator: appDelegate.settingsWindowCoordinator
            )
        }
    }
}

struct WindowManagerPrimaryMenuLabel: View {
    @ObservedObject var state: MenuBarStateModel
    @ObservedObject var settingsStore: SettingsStore

    var body: some View {
        let mode = settingsStore.menuBarPresentationMode
        MenuBarPrimaryStatusView(snapshot: state.presentation(for: mode))
    }
}

private struct WindowManagerAppMenu: View {
    @ObservedObject var navigation: SettingsNavigationModel
    @ObservedObject var settingsStore: SettingsStore
    let engine: WorkspaceEngine
    let settingsWindowCoordinator: SettingsWindowCoordinator
    @ObservedObject var menuBarState: MenuBarStateModel
    let diagnostics: DiagnosticLogger
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text("Profile: \(settingsStore.activeProfile.name)")
        Text(settingsStore.activeProfileSelectionReason.title)

        Menu("Switch Profile") {
            ForEach(settingsStore.profiles) { profile in
                Button {
                    settingsStore.selectProfile(profile.id)
                } label: {
                    if profile.id == settingsStore.activeProfileID {
                        Label(profile.name, systemImage: "checkmark")
                    } else {
                        Text(profile.name)
                    }
                }
            }
        }

        if settingsStore.manualPinnedProfileID != nil {
            Button("Resume Automatic", systemImage: "arrow.triangle.2.circlepath") {
                settingsStore.resumeAutomaticProfileSelection()
            }
        }

        if settingsStore.menuBarPresentationMode == .full {
            let snapshot = menuBarState.presentation(for: .full)
            let layout = MenuBarPressurePolicy.layout(
                displays: snapshot.displays,
                availableWidth: MenuBarPressurePolicy.defaultAvailableWidth
            )
            if let overflowSummary = layout.overflowSummary {
                Text("Menu bar overflow: \(overflowSummary)")
            }
        }

        Button {
            openSettingsPane(.profiles)
        } label: {
            Label("Profile Settings…", systemImage: "person.crop.rectangle.stack")
        }

        Divider()

        Button {
            openSettingsPane(nil)
        } label: {
            Label("Settings…", systemImage: "gearshape")
        }
        .keyboardShortcut(",", modifiers: .command)

        Button {
            openSettingsPane(.radialMenu)
        } label: {
            Label("Command Wheel Settings…", systemImage: "circle.hexagongrid")
        }

        #if DEBUG
        Divider()
        Text("WindowManager Debug")
        Button("Copy Recent Diagnostics") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(diagnostics.recentDiagnosticsText(), forType: .string)
        }
        Button("Reveal Diagnostics File") {
            guard let fileURL = diagnostics.fileURL else { return }
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        }
        .disabled(diagnostics.fileURL == nil)
        #endif

        Divider()
        Button("Quit WindowManager") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func openSettingsPane(_ category: SettingsCategory?) {
        SettingsWindowOpener.open(
            category: category,
            preferPointerDisplay: true,
            navigation: navigation,
            engine: engine,
            coordinator: settingsWindowCoordinator,
            openSettings: { openSettings() }
        )
    }
}

private struct WindowManagerSettingsCommands: Commands {
    @ObservedObject var navigation: SettingsNavigationModel
    let engine: WorkspaceEngine
    let coordinator: SettingsWindowCoordinator
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                SettingsWindowOpener.open(
                    category: nil,
                    preferPointerDisplay: false,
                    navigation: navigation,
                    engine: engine,
                    coordinator: coordinator,
                    openSettings: { openSettings() }
                )
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}

@MainActor
private enum SettingsWindowOpener {
    static func open(
        category: SettingsCategory?,
        preferPointerDisplay: Bool,
        navigation: SettingsNavigationModel,
        engine: WorkspaceEngine,
        coordinator: SettingsWindowCoordinator,
        openSettings: @escaping @MainActor () -> Void
    ) {
        if let category { navigation.select(category) }
        let preferredDisplayIdentifier = preferPointerDisplay
            ? SettingsWindowCoordinator.pointerDisplayIdentifierForCurrentMouseEvent()
            : nil
        engine.settingsSurfaceContext(
            preferredDisplayIdentifier: preferredDisplayIdentifier
        ) { context in
            coordinator.requestOpen(context: context, openSettings: openSettings)
        }
    }
}
