import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let settingsStore: SettingsStore
    private let progressStore: OnboardingProgressStore
    private let diagnostics: DiagnosticLogger
    private var coordinator: OnboardingCoordinator?
    private var restoredAccessoryPolicy = false

    init(
        settingsStore: SettingsStore,
        progressStore: OnboardingProgressStore = OnboardingProgressStore(),
        diagnostics: DiagnosticLogger = .disabled
    ) {
        self.settingsStore = settingsStore
        self.progressStore = progressStore
        self.diagnostics = diagnostics
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @discardableResult
    func presentIfNeeded() -> Bool {
        guard progressStore.requiresOnboarding else { return false }
        present()
        return true
    }

    func present() {
        if window == nil { createWindow() }
        restoredAccessoryPolicy = false
        NSApp.setActivationPolicy(.regular)
        guard let window else { return }
        moveToActiveScreen(window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
        diagnostics.log(
            category: "onboarding",
            event: "presented",
            fields: [
                "step": coordinator?.step.title ?? "unknown",
                "application-active": NSApp.isActive.description,
                "window-key": window.isKeyWindow.description,
                "window-main": window.isMainWindow.description,
            ]
        )
    }

    func presentFromBeginning() {
        progressStore.restartFromBeginning()
        window?.orderOut(nil)
        coordinator = nil
        window = nil
        diagnostics.log(category: "onboarding", event: "restart-requested")
        present()
    }

    func shutdown() {
        window?.orderOut(nil)
        coordinator = nil
        window = nil
        restoreAccessoryPolicyIfNeeded()
    }

    func windowWillClose(_ notification: Notification) {
        diagnostics.log(
            category: "onboarding",
            event: "dismissed-incomplete",
            fields: ["step": coordinator?.step.title ?? "unknown"]
        )
        restoreAccessoryPolicyIfNeeded()
    }

    private func createWindow() {
        let coordinator = OnboardingCoordinator(
            settingsStore: settingsStore,
            progressStore: progressStore
        ) { [weak self] in
            self?.finish()
        }
        self.coordinator = coordinator
        let hostingController = NSHostingController(rootView: OnboardingWizardView(coordinator: coordinator))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: OnboardingWindowConfiguration.contentSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to WindowRanger"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = OnboardingWindowConfiguration.isReleasedWhenClosed
        window.delegate = self
        window.contentViewController = hostingController
        window.setContentSize(OnboardingWindowConfiguration.contentSize)
        window.contentMinSize = OnboardingWindowConfiguration.contentSize
        window.contentMaxSize = OnboardingWindowConfiguration.contentSize
        window.level = OnboardingWindowConfiguration.level
        window.collectionBehavior = OnboardingWindowConfiguration.collectionBehavior
        window.animationBehavior = .documentWindow
        self.window = window
    }

    private func finish() {
        diagnostics.log(category: "onboarding", event: "completed")
        window?.orderOut(nil)
        restoreAccessoryPolicyIfNeeded()
    }

    private func restoreAccessoryPolicyIfNeeded() {
        guard !restoredAccessoryPolicy else { return }
        restoredAccessoryPolicy = true
        NSApp.setActivationPolicy(.accessory)
    }

    private func moveToActiveScreen(_ window: NSWindow) {
        let screen = NSApp.keyWindow?.screen ?? NSScreen.screens.first(where: {
            NSPointInRect(NSEvent.mouseLocation, $0.frame)
        }) ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            window.center()
            return
        }
        let size = window.frame.size
        let origin = CGPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2
        )
        window.setFrame(NSRect(origin: origin, size: size), display: false)
    }
}
