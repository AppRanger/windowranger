import AppKit
import Carbon
import SwiftUI
import XCTest

@MainActor
final class OnboardingFlowTests: XCTestCase {
    func testProgressDefaultsToWelcomeAndPersistsResumeStep() {
        withDefaults { defaults in
            let progress = OnboardingProgressStore(defaults: defaults)

            XCTAssertTrue(progress.requiresOnboarding)
            XCTAssertEqual(progress.currentStep, .welcome)

            progress.save(step: .menuBar)
            XCTAssertEqual(OnboardingProgressStore(defaults: defaults).currentStep, .menuBar)
        }
    }

    func testCompletionIsVersionedAndClearsResumeStep() {
        withDefaults { defaults in
            let firstVersion = OnboardingProgressStore(defaults: defaults, version: 1)
            firstVersion.save(step: .quickAppShelf)
            firstVersion.complete()

            XCTAssertFalse(OnboardingProgressStore(defaults: defaults, version: 1).requiresOnboarding)
            XCTAssertEqual(OnboardingProgressStore(defaults: defaults, version: 1).currentStep, .welcome)
            XCTAssertTrue(OnboardingProgressStore(defaults: defaults, version: 2).requiresOnboarding)
        }
    }

    func testRestartAfterCompletionReturnsToWelcomeWithoutChangingSettings() throws {
        try withDefaults { defaults in
            let settings = makeSettingsStore(defaults: defaults)
            settings.focusedWindowHighlightEnabled = true
            settings.menuBarPresentationMode = .full
            let activeProfileID = settings.activeProfileID
            let editedProfileID = try XCTUnwrap(settings.duplicateProfile(activeProfileID))
            let workspaceID = try XCTUnwrap(settings.settingsWorkspaces.first?.id)
            settings.setSettingsWorkspaceName("Rerun preserved", for: workspaceID)
            settings.setSettingsQuickApp(InstalledApplication(
                bundleIdentifier: "example.onboarding.preserved",
                displayName: "Preserved",
                bundleURL: nil,
                isRunning: false
            ))
            let profilesBeforeRestart = settings.profiles
            let settingsWorkspacesBeforeRestart = settings.settingsWorkspaces
            let settingsQuickAppsBeforeRestart = settings.settingsQuickApps
            let progress = OnboardingProgressStore(defaults: defaults)
            progress.save(step: .quickAppShelf)
            progress.complete()

            progress.restartFromBeginning()

            XCTAssertTrue(progress.requiresOnboarding)
            XCTAssertEqual(progress.currentStep, .welcome)
            XCTAssertTrue(settings.focusedWindowHighlightEnabled)
            XCTAssertEqual(settings.menuBarPresentationMode, .full)
            XCTAssertEqual(settings.activeProfileID, activeProfileID)
            XCTAssertEqual(settings.settingsProfileID, editedProfileID)
            XCTAssertEqual(settings.profiles, profilesBeforeRestart)
            XCTAssertEqual(settings.settingsWorkspaces, settingsWorkspacesBeforeRestart)
            XCTAssertEqual(settings.settingsQuickApps, settingsQuickAppsBeforeRestart)

            progress.save(step: .menuBar)
            XCTAssertEqual(
                OnboardingProgressStore(defaults: defaults).currentStep,
                .menuBar
            )
        }
    }

    func testRestartHandoffClosesSettingsBeforeSchedulingOnboarding() {
        var events: [String] = []
        var pendingPresentation: (() -> Void)?

        OnboardingRestartHandoff.perform(
            dismissSettings: {
                events.append("settings-closed")
            },
            schedulePresentation: { action in
                pendingPresentation = action
            },
            presentOnboarding: {
                events.append("onboarding-presented")
            }
        )

        XCTAssertEqual(events, ["settings-closed"])
        XCTAssertNotNil(pendingPresentation)

        pendingPresentation?()
        XCTAssertEqual(events, ["settings-closed", "onboarding-presented"])
    }

    func testNewOnboardingVersionDoesNotReuseEarlierResumeStep() {
        withDefaults { defaults in
            let firstVersion = OnboardingProgressStore(defaults: defaults, version: 1)
            firstVersion.save(step: .quickAppShelf)

            XCTAssertEqual(firstVersion.currentStep, .quickAppShelf)
            XCTAssertEqual(
                OnboardingProgressStore(defaults: defaults, version: 2).currentStep,
                .welcome
            )
        }
    }

    func testCoordinatorResumesNavigatesAndCompletes() {
        withDefaults { defaults in
            let progress = OnboardingProgressStore(defaults: defaults)
            progress.save(step: .focusBorder)
            let settings = makeSettingsStore(defaults: defaults)
            var didFinish = false
            let coordinator = OnboardingCoordinator(
                settingsStore: settings,
                progressStore: progress
            ) {
                didFinish = true
            }

            XCTAssertEqual(coordinator.step, .focusBorder)
            coordinator.goBack()
            XCTAssertEqual(coordinator.step, .shortcuts)
            XCTAssertEqual(progress.currentStep, .shortcuts)

            coordinator.move(to: .workspaces)
            coordinator.goForward()
            XCTAssertTrue(didFinish)
            XCTAssertFalse(progress.requiresOnboarding)
        }
    }

    func testCoordinatorMutatesTheRealSettingsOwners() {
        withDefaults { defaults in
            let settings = makeSettingsStore(defaults: defaults)
            let coordinator = OnboardingCoordinator(
                settingsStore: settings,
                progressStore: OnboardingProgressStore(defaults: defaults),
                finishAction: {}
            )

            coordinator.setICloudSyncEnabled(true)
            XCTAssertTrue(settings.iCloudSyncEnabled)

            let navigateModifiers = UInt32(controlKey | cmdKey)
            coordinator.setShortcutFamilyModifiers(navigateModifiers, for: .navigate)
            XCTAssertNil(coordinator.shortcutConflictMessage)
            XCTAssertEqual(settings.hotKeyConfiguration.modifierMask(for: .navigate), navigateModifiers)

            coordinator.setFocusBorderEnabled(true)
            coordinator.setFocusBorderColor(MenuBarHighlightColor(red: 0.2, green: 0.6, blue: 1))
            XCTAssertTrue(settings.focusedWindowHighlightEnabled)
            XCTAssertEqual(settings.focusedWindowHighlightColor.hex, "#3399FF")

            coordinator.setMenuBarPresentation(.full)
            XCTAssertEqual(settings.menuBarPresentationMode, .full)

            let application = InstalledApplication(
                bundleIdentifier: "example.onboarding.app",
                displayName: "Example",
                bundleURL: nil,
                isRunning: false
            )
            coordinator.addQuickApp(application)
            XCTAssertEqual(settings.settingsQuickApps.map(\.bundleIdentifier), [application.bundleIdentifier])
            let secondApplication = InstalledApplication(
                bundleIdentifier: "example.onboarding.second",
                displayName: "Second",
                bundleURL: nil,
                isRunning: false
            )
            coordinator.addQuickApp(secondApplication)
            coordinator.moveQuickApps(from: IndexSet(integer: 1), to: 0)
            XCTAssertEqual(
                settings.settingsQuickApps.map(\.bundleIdentifier),
                [secondApplication.bundleIdentifier, application.bundleIdentifier]
            )
            coordinator.removeQuickApp(at: 0)
            coordinator.removeQuickApp(at: 0)
            XCTAssertTrue(settings.settingsQuickApps.isEmpty)

            coordinator.setWorkspaceSwipeEnabled(true)
            coordinator.setWorkspaceSwipeFingerCount(.four)
            XCTAssertTrue(settings.workspaceSwipeEnabled)
            XCTAssertEqual(settings.workspaceSwipeFingerCount, .four)
        }
    }

    func testShortcutMenusOnlyOfferChoicesValidAgainstTheOtherFamily() {
        withDefaults { defaults in
            let settings = makeSettingsStore(defaults: defaults)
            let coordinator = OnboardingCoordinator(
                settingsStore: settings,
                progressStore: OnboardingProgressStore(defaults: defaults),
                finishAction: {}
            )

            for family in ShortcutFamily.allCases {
                let choices = coordinator.availableShortcutFamilyModifierChoices(for: family)
                XCTAssertFalse(choices.isEmpty)
                XCTAssertTrue(choices.contains(settings.hotKeyConfiguration.modifierMask(for: family)))

                for candidate in choices {
                    let navigate = family == .navigate
                        ? candidate
                        : settings.hotKeyConfiguration.modifierMask(for: .navigate)
                    let arrange = family == .arrange
                        ? candidate
                        : settings.hotKeyConfiguration.modifierMask(for: .arrange)
                    XCTAssertNil(HotKeyConfiguration.familyValidationMessage(
                        navigate: navigate,
                        arrange: arrange
                    ))
                }
            }

            XCTAssertFalse(coordinator.availableShortcutFamilyModifierChoices(for: .navigate).contains(
                settings.hotKeyConfiguration.modifierMask(for: .arrange)
            ))
        }
    }

    func testWindowConfigurationIsFixedAndLargeEnoughForSevenStages() {
        XCTAssertEqual(OnboardingWindowConfiguration.contentSize.width, 980)
        XCTAssertEqual(OnboardingWindowConfiguration.contentSize.height, 660)
        XCTAssertFalse(OnboardingWindowConfiguration.isResizable)
        XCTAssertFalse(OnboardingWindowConfiguration.isReleasedWhenClosed)
        XCTAssertEqual(OnboardingWindowConfiguration.level, .floating)
        XCTAssertTrue(OnboardingWindowConfiguration.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(OnboardingWindowConfiguration.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(OnboardingWindowConfiguration.collectionBehavior.contains(.moveToActiveSpace))
    }

    /// Opt-in production-view fixture. This exercises every real onboarding stage without
    /// starting AppDelegate, registering hotkeys, or ordering a window onto the desktop.
    func testOffscreenProductionOnboardingStages() throws {
        guard let outputPath = ProcessInfo.processInfo.environment[
            "WINDOWRANGER_ONBOARDING_SNAPSHOT_DIR"
        ], !outputPath.isEmpty else {
            return
        }

        let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        try withDefaults { defaults in
            let store = makeSettingsStore(defaults: defaults)
            let applications = [
                InstalledApplication(
                    bundleIdentifier: "com.apple.Safari",
                    displayName: "Safari",
                    bundleURL: nil,
                    isRunning: false
                ),
                InstalledApplication(
                    bundleIdentifier: "com.apple.Notes",
                    displayName: "Notes",
                    bundleURL: nil,
                    isRunning: false
                ),
            ]
            let coordinator = OnboardingCoordinator(
                settingsStore: store,
                progressStore: OnboardingProgressStore(defaults: defaults),
                finishAction: {}
            )
            applications.forEach(coordinator.addQuickApp)

            for step in OnboardingStep.allCases {
                coordinator.move(to: step)
                let view = OnboardingWizardView(coordinator: coordinator)
                let data = try renderRetinaPNG(view)
                XCTAssertGreaterThan(data.count, 50_000)
                try data.write(
                    to: outputDirectory.appendingPathComponent(
                        "windowranger-onboarding-\(step.rawValue + 1)-\(step.title.lowercased().replacingOccurrences(of: " ", with: "-"))-dark.png"
                    ),
                    options: .atomic
                )
            }
        }
    }

    private func makeSettingsStore(defaults: UserDefaults) -> SettingsStore {
        SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] },
            isPortableMacProvider: { false },
            diagnostics: .disabled
        )
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suiteName = "OnboardingFlowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }

    private func renderRetinaPNG<V: View>(_ view: V) throws -> Data {
        let size = OnboardingWindowConfiguration.contentSize
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .darkAqua)
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2),
            pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw NSError(domain: "OnboardingFlowTests", code: 1)
        }
        bitmap.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "OnboardingFlowTests", code: 2)
        }
        return png
    }

}
