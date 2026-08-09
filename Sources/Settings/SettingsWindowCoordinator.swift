import AppKit
import CoreGraphics
import Foundation
import SwiftUI

@MainActor
enum SettingsWindowOpener {
    static func open(
        category: SettingsCategory?,
        preferPointerDisplay: Bool,
        navigation: SettingsNavigationModel,
        engine: WorkspaceEngine,
        coordinator: SettingsWindowCoordinator,
        openSettings: @escaping @MainActor () -> Bool
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

struct SettingsCommandRequest: Equatable, Sendable {
    let category: SettingsCategory?
    let preferPointerDisplay: Bool

    static let applicationMenuDefault = SettingsCommandRequest(
        category: nil,
        preferPointerDisplay: false
    )
}

/// Carries status-menu routing context into the SwiftUI-owned Command-comma action. The pending
/// request is consumed exactly once, so a normal application-menu or keyboard invocation always
/// falls back to the canonical default behavior.
@MainActor
final class SettingsCommandRequestRouter {
    private var pendingRequest: SettingsCommandRequest?

    func prepare(_ request: SettingsCommandRequest) {
        pendingRequest = request
    }

    func consume() -> SettingsCommandRequest {
        defer { pendingRequest = nil }
        return pendingRequest ?? .applicationMenuDefault
    }

    func cancelPendingRequest() {
        pendingRequest = nil
    }
}

/// Finds and performs the SwiftUI Settings command installed in the app's main menu. Matching the
/// standard Command-comma equivalent avoids depending on removed private AppKit selectors or on a
/// localized menu title.
@MainActor
enum SettingsMenuCommandDispatcher {
    static func performSettingsCommand(in rootMenu: NSMenu?) -> Bool {
        guard let item = settingsCommandItem(in: rootMenu),
              let action = item.action
        else { return false }
        return NSApplication.shared.sendAction(action, to: item.target, from: item)
    }

    private static func settingsCommandItem(in menu: NSMenu?) -> NSMenuItem? {
        guard let menu else { return nil }
        for item in menu.items {
            if item.isEnabled,
               item.keyEquivalent == ",",
               item.keyEquivalentModifierMask.contains(.command) {
                return item
            }
            if let nested = settingsCommandItem(in: item.submenu) {
                return nested
            }
        }
        return nil
    }
}

/// The virtual-workspace/display destination captured at the moment the user asks for Settings.
/// This is deliberately independent from tracked third-party windows: Settings is an app-owned
/// utility with a small, explicit lifecycle rather than a participant in discovery or persistence.
struct SettingsSurfaceContext: Equatable, Sendable {
    let workspaceID: UUID
    let displayIdentifier: String
    let displayMode: MultiDisplayMode
    let resolutionReason: String
}

struct SettingsDisplayDescriptor: Equatable, Sendable {
    let identifier: String
    let visibleFrame: CGRect
    let isMain: Bool
}

struct SettingsWindowPlacement: Equatable, Sendable {
    let displayIdentifier: String
    let frame: CGRect
    let resolutionReason: String
}

enum SettingsSceneOpenResult: Equatable, Sendable {
    /// Context is ready; a `SettingsLink` owns the actual scene-opening action.
    case preparedForSettingsLink
    /// The supported SwiftUI `openSettings` action was invoked for a first open.
    case sceneRequested
    /// A rapid request updated the pending destination without requesting a duplicate scene.
    case coalescedPendingScene
    /// The existing Settings utility was repositioned and raised directly.
    case resurfacedExistingWindow
    /// The injected scene-opening action was unavailable and no pending request remains.
    case sceneActionUnavailable
}

enum SettingsWindowGeometry {
    /// Keeps a user-positioned Settings window when it already belongs to the requested display,
    /// but centers it when crossing displays. In both cases the result is clamped to the display's
    /// visible frame so a disconnected monitor cannot strand the utility window off screen.
    static func placement(
        currentFrame: CGRect,
        requestedDisplayIdentifier: String,
        displays: [SettingsDisplayDescriptor],
        edgeInset: CGFloat = 18
    ) -> SettingsWindowPlacement? {
        guard !displays.isEmpty else { return nil }
        let requested = displays.first { $0.identifier == requestedDisplayIdentifier }
        let display = requested ?? displays.first(where: \SettingsDisplayDescriptor.isMain) ?? displays[0]
        let safeFrame = display.visibleFrame.insetBy(dx: edgeInset, dy: edgeInset)
        let bounds = safeFrame.width > 0 && safeFrame.height > 0 ? safeFrame : display.visibleFrame
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let width = min(max(1, currentFrame.width), bounds.width)
        let height = min(max(1, currentFrame.height), bounds.height)
        let size = CGSize(width: width, height: height)
        let intersection = currentFrame.intersection(display.visibleFrame)
        let alreadyOnDisplay = !intersection.isNull &&
            intersection.width * intersection.height >= min(4_096, currentFrame.width * currentFrame.height * 0.1)
        let proposedOrigin = alreadyOnDisplay
            ? currentFrame.origin
            : CGPoint(x: display.visibleFrame.midX - width / 2, y: display.visibleFrame.midY - height / 2)
        let maximumX = max(bounds.minX, bounds.maxX - size.width)
        let maximumY = max(bounds.minY, bounds.maxY - size.height)
        let origin = CGPoint(
            x: min(max(proposedOrigin.x, bounds.minX), maximumX),
            y: min(max(proposedOrigin.y, bounds.minY), maximumY)
        )
        let reason: String
        if requested != nil {
            reason = alreadyOnDisplay ? "requested-display-preserved-and-clamped" : "requested-display-centered"
        } else if display.isMain {
            reason = "requested-display-disconnected-main-fallback"
        } else {
            reason = "requested-display-disconnected-first-fallback"
        }
        return SettingsWindowPlacement(
            displayIdentifier: display.identifier,
            frame: CGRect(origin: origin, size: size),
            resolutionReason: reason
        )
    }
}

/// Test seam for Settings presentation. Unit tests use an in-memory surface, so they never create
/// an NSWindow, activate the app, query Accessibility, or disturb the desktop.
@MainActor
protocol SettingsWindowSurface: AnyObject {
    var frame: CGRect { get }
    var isVisible: Bool { get }
    func prepareAsFloatingUtility()
    func surface(at frame: CGRect)
    func surfaceWithoutActivation(at frame: CGRect)
    func repositionWithoutActivation(to frame: CGRect)
    func hideForWorkspace()
    func restoreOrdinaryLifecycle()
}

@MainActor
final class SettingsWindowCoordinator {
    typealias DisplayProvider = @MainActor () -> [SettingsDisplayDescriptor]
    typealias ApplicationActivator = @MainActor () -> Void

    private let diagnostics: DiagnosticLogger
    private let displayProvider: DisplayProvider
    private let applicationActivator: ApplicationActivator
    private var surface: SettingsWindowSurface?
    private weak var attachedWindow: NSWindow?
    private var closeObserver: NSObjectProtocol?
    private var pendingContext: SettingsSurfaceContext?
    private(set) var assignedContext: SettingsSurfaceContext?
    private(set) var requestGeneration: UInt64 = 0
    private(set) var isHiddenForWorkspace = false

    init(
        diagnostics: DiagnosticLogger = .disabled,
        displayProvider: @escaping DisplayProvider = SettingsWindowCoordinator.activeDisplays,
        applicationActivator: @escaping ApplicationActivator = {
            NSApp.activate(ignoringOtherApps: true)
        }
    ) {
        self.diagnostics = diagnostics
        self.displayProvider = displayProvider
        self.applicationActivator = applicationActivator
    }

    /// Uses an injected SwiftUI `openSettings` action for first-scene creation. Existing windows are
    /// surfaced directly, and rapid pre-attachment requests are coalesced so they cannot create
    /// duplicate Settings scenes.
    @discardableResult
    func requestOpen(
        context: SettingsSurfaceContext,
        openSettings: () -> Bool
    ) -> SettingsSceneOpenResult {
        let preparation = prepareOpen(context: context)
        switch preparation {
        case .resurfacedExistingWindow, .coalescedPendingScene:
            return preparation
        case .preparedForSettingsLink:
            let generation = requestGeneration
            guard openSettings() else {
                if requestGeneration == generation { pendingContext = nil }
                diagnostics.log(
                    category: "settings-window",
                    event: "scene-action-unavailable",
                    fields: ["generation": String(generation)]
                )
                return .sceneActionUnavailable
            }
            diagnostics.log(
                category: "settings-window",
                event: "scene-open-requested",
                fields: ["generation": String(generation), "route": "open-settings-action"]
            )
            return .sceneRequested
        case .sceneRequested, .sceneActionUnavailable:
            assertionFailure("Unexpected Settings preparation result")
            return preparation
        }
    }

    /// Prepares the shared placement/resurface pipeline for a SwiftUI `SettingsLink`. The link
    /// remains the sole owner of scene creation; this method is deliberately UI-independent so the
    /// AppKit status menu can bridge to the supported SwiftUI control without a private selector.
    @discardableResult
    func prepareOpen(context: SettingsSurfaceContext) -> SettingsSceneOpenResult {
        let wasWaitingForScene = pendingContext != nil && surface == nil
        requestGeneration &+= 1
        pendingContext = context
        diagnostics.log(
            category: "settings-window",
            event: "open-requested",
            fields: [
                "generation": String(requestGeneration),
                "workspace": Self.short(context.workspaceID.uuidString),
                "display": Self.short(context.displayIdentifier),
                "display-mode": context.displayMode.rawValue,
                "context-resolution": context.resolutionReason,
            ]
        )
        surfacePendingRequestIfPossible()
        if surface != nil {
            return .resurfacedExistingWindow
        }
        if wasWaitingForScene {
            diagnostics.log(
                category: "settings-window",
                event: "scene-open-coalesced",
                fields: ["generation": String(requestGeneration)]
            )
            return .coalescedPendingScene
        }
        return .preparedForSettingsLink
    }

    func attach(window: NSWindow) {
        if attachedWindow === window, surface != nil {
            surfacePendingRequestIfPossible()
            return
        }
        detach(restoreLifecycle: true)
        let adapter = AppKitSettingsWindowSurface(window: window)
        attachedWindow = window
        surface = adapter
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            Task { @MainActor in
                guard let self, self.attachedWindow === window else { return }
                self.windowWillClose()
            }
        }
        surfacePendingRequestIfPossible()
    }

    /// Internal injection point used by non-hosted tests.
    func attach(surface: SettingsWindowSurface) {
        detach(restoreLifecycle: true)
        self.surface = surface
        surfacePendingRequestIfPossible()
    }

    func workspaceStateDidChange(_ state: WorkspaceEngineState) {
        guard let assignedContext, let surface else { return }
        let remainsActive = state.activeWorkspaceIDs.contains(assignedContext.workspaceID)
        if !remainsActive, surface.isVisible {
            surface.hideForWorkspace()
            isHiddenForWorkspace = true
            diagnostics.log(
                category: "settings-window",
                event: "workspace-hidden",
                fields: [
                    "workspace": Self.short(assignedContext.workspaceID.uuidString),
                    "display": Self.short(assignedContext.displayIdentifier),
                ]
            )
        } else if remainsActive, isHiddenForWorkspace {
            // Returning to the utility's assigned virtual workspace should restore it without
            // activating WindowRanger or stealing focus from the workspace switch target.
            guard let placement = SettingsWindowGeometry.placement(
                currentFrame: surface.frame,
                requestedDisplayIdentifier: assignedContext.displayIdentifier,
                displays: displayProvider()
            ) else { return }
            surface.prepareAsFloatingUtility()
            surface.surfaceWithoutActivation(at: placement.frame)
            isHiddenForWorkspace = false
            diagnostics.log(
                category: "settings-window",
                event: "workspace-restored",
                fields: [
                    "workspace": Self.short(assignedContext.workspaceID.uuidString),
                    "display": Self.short(placement.displayIdentifier),
                ]
            )
        }
    }

    func screenParametersDidChange() {
        guard let assignedContext, let surface, surface.isVisible,
              let placement = SettingsWindowGeometry.placement(
                  currentFrame: surface.frame,
                  requestedDisplayIdentifier: assignedContext.displayIdentifier,
                  displays: displayProvider()
              )
        else { return }
        surface.prepareAsFloatingUtility()
        surface.repositionWithoutActivation(to: placement.frame)
        diagnostics.log(
            category: "settings-window",
            event: "display-reconciled",
            fields: [
                "requested-display": Self.short(assignedContext.displayIdentifier),
                "resolved-display": Self.short(placement.displayIdentifier),
                "display-resolution": placement.resolutionReason,
            ]
        )
    }

    func shutdown() {
        detach(restoreLifecycle: true)
        pendingContext = nil
        assignedContext = nil
        isHiddenForWorkspace = false
    }

    static func activeDisplays() -> [SettingsDisplayDescriptor] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else { return nil }
            let displayID = CGDirectDisplayID(number.uint32Value)
            let identifier: String
            if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
                identifier = CFUUIDCreateString(nil, uuid) as String
            } else {
                identifier = "session-display-\(displayID)"
            }
            return SettingsDisplayDescriptor(
                identifier: identifier,
                visibleFrame: screen.visibleFrame,
                isMain: displayID == CGMainDisplayID()
            )
        }
    }

    /// Menu-bar actions are pointer-local; command-key invocations deliberately retain the AX/
    /// recent interaction display instead of following an unrelated idle pointer.
    static func pointerDisplayIdentifierForCurrentMouseEvent() -> String? {
        guard let type = NSApp.currentEvent?.type,
              [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
               .otherMouseDown, .otherMouseUp].contains(type)
        else { return nil }
        let location = NSEvent.mouseLocation
        return activeDisplays().first { $0.visibleFrame.contains(location) }?.identifier
    }

    private func surfacePendingRequestIfPossible() {
        guard let context = pendingContext, let surface,
              let placement = SettingsWindowGeometry.placement(
                  currentFrame: surface.frame,
                  requestedDisplayIdentifier: context.displayIdentifier,
                  displays: displayProvider()
              )
        else { return }
        pendingContext = nil
        assignedContext = context
        isHiddenForWorkspace = false
        surface.prepareAsFloatingUtility()
        applicationActivator()
        surface.surface(at: placement.frame)
        diagnostics.log(
            category: "settings-window",
            event: "surfaced",
            fields: [
                "generation": String(requestGeneration),
                "workspace": Self.short(context.workspaceID.uuidString),
                "requested-display": Self.short(context.displayIdentifier),
                "resolved-display": Self.short(placement.displayIdentifier),
                "display-resolution": placement.resolutionReason,
                "window-level": "floating",
            ]
        )
    }

    private func windowWillClose() {
        diagnostics.log(
            category: "settings-window",
            event: "closed",
            fields: ["workspace": assignedContext.map { Self.short($0.workspaceID.uuidString) } ?? "none"]
        )
        detach(restoreLifecycle: true)
        assignedContext = nil
        isHiddenForWorkspace = false
    }

    private func detach(restoreLifecycle: Bool) {
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
            self.closeObserver = nil
        }
        if restoreLifecycle { surface?.restoreOrdinaryLifecycle() }
        surface = nil
        attachedWindow = nil
    }

    private static func short(_ value: String) -> String {
        value.count > 16 ? "\(value.prefix(6))-\(value.suffix(6))" : value
    }
}

@MainActor
private final class AppKitSettingsWindowSurface: SettingsWindowSurface {
    private weak var window: NSWindow?
    private let originalLevel: NSWindow.Level
    private let originalCollectionBehavior: NSWindow.CollectionBehavior

    init(window: NSWindow) {
        self.window = window
        originalLevel = window.level
        originalCollectionBehavior = window.collectionBehavior
    }

    var frame: CGRect { window?.frame ?? .zero }
    var isVisible: Bool { window?.isVisible == true }

    func prepareAsFloatingUtility() {
        guard let window else { return }
        window.identifier = NSUserInterfaceItemIdentifier("com.windowranger.WindowRanger.settings")
        window.level = .floating
        window.collectionBehavior.insert(.moveToActiveSpace)
    }

    func surface(at frame: CGRect) {
        guard let window else { return }
        window.setFrame(frame, display: false)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func surfaceWithoutActivation(at frame: CGRect) {
        guard let window else { return }
        window.setFrame(frame, display: false)
        window.orderFront(nil)
    }

    func repositionWithoutActivation(to frame: CGRect) {
        window?.setFrame(frame, display: true)
    }

    func hideForWorkspace() {
        window?.orderOut(nil)
    }

    func restoreOrdinaryLifecycle() {
        guard let window else { return }
        window.level = originalLevel
        window.collectionBehavior = originalCollectionBehavior
    }
}

extension SettingsWindowSurface {
    func surfaceWithoutActivation(at frame: CGRect) {
        surface(at: frame)
    }

    func repositionWithoutActivation(to frame: CGRect) {
        surface(at: frame)
    }
}

/// Captures the NSWindow created and owned by SwiftUI's Settings scene without searching by title
/// or accidentally adopting the command-feedback/radial panels.
struct SettingsWindowReader: NSViewRepresentable {
    let didResolveWindow: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> SettingsWindowReaderView {
        let view = SettingsWindowReaderView()
        view.didResolveWindow = didResolveWindow
        return view
    }

    func updateNSView(_ nsView: SettingsWindowReaderView, context: Context) {
        nsView.didResolveWindow = didResolveWindow
        nsView.resolveWindowIfAvailable()
    }
}

final class SettingsWindowReaderView: NSView {
    var didResolveWindow: (@MainActor (NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        resolveWindowIfAvailable()
    }

    func resolveWindowIfAvailable() {
        guard let window else { return }
        Task { @MainActor [weak self, weak window] in
            guard let self, let window else { return }
            self.didResolveWindow?(window)
        }
    }
}
