import AppKit
import ApplicationServices

enum FocusedWindowHighlightObservationSource: String, Equatable, Sendable {
    case accessibilityFocusedWindow = "accessibility-focused-window"
    case verifiedFocusTransaction = "verified-focus-transaction"
}

struct FocusedWindowHighlightTarget: Equatable, Sendable {
    let key: WindowKey
    let frame: WindowFrame
    let fullscreenObservation: AXBooleanAttributeObservation
    let bundleIdentifier: String?
    let observationSource: FocusedWindowHighlightObservationSource

    init(
        key: WindowKey,
        frame: WindowFrame,
        fullscreenObservation: AXBooleanAttributeObservation,
        bundleIdentifier: String? = nil,
        observationSource: FocusedWindowHighlightObservationSource = .accessibilityFocusedWindow
    ) {
        self.key = key
        self.frame = frame
        self.fullscreenObservation = fullscreenObservation
        self.bundleIdentifier = bundleIdentifier
        self.observationSource = observationSource
    }
}

struct FocusedWindowHighlightWorkspaceContext: Equatable, Sendable {
    let layout: WorkspaceLayout
    let windowCount: Int
}

struct FocusedWindowHighlightFilters: Equatable, Sendable {
    let tiledWorkspacesOnly: Bool
    let multipleWindowsOnly: Bool

    static let unrestricted = FocusedWindowHighlightFilters(
        tiledWorkspacesOnly: false,
        multipleWindowsOnly: false
    )
}

struct FocusedWindowHighlightPanelPolicy: Equatable, Sendable {
    let canBecomeKey: Bool
    let canBecomeMain: Bool
    let ignoresMouseEvents: Bool
    let participatesInWindowCycle: Bool

    static let nonActivating = FocusedWindowHighlightPanelPolicy(
        canBecomeKey: false,
        canBecomeMain: false,
        ignoresMouseEvents: true,
        participatesInWindowCycle: false
    )
}

enum FocusedWindowHighlightPolicy {
    static let refreshInterval: TimeInterval = 0.1
    static let borderWidth: CGFloat = 3
    static let borderOutset: CGFloat = 2
    static let fallbackCornerRadius: CGFloat = 10
    static let cornerRadiusRange: ClosedRange<Double> = 0...40
    static let managedLayoutScreenEdgeClearance: CGFloat = 4

    /// Other apps' rendered radii are not available through public window metadata. Keep this
    /// generation policy explicit so verified defaults can change without rewriting app overrides.
    static func automaticCornerRadius(
        for operatingSystemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) -> CGFloat {
        switch operatingSystemVersion.majorVersion {
        case 14, 15:
            10
        case 26:
            10
        case 27...:
            16
        default:
            fallbackCornerRadius
        }
    }

    static func normalizedCornerRadius(_ radius: Double) -> Double {
        let finiteRadius = radius.isFinite ? radius : Double(fallbackCornerRadius)
        return min(max(finiteRadius, cornerRadiusRange.lowerBound), cornerRadiusRange.upperBound)
    }

    static func resolvedCornerRadius(
        bundleIdentifier: String?,
        overrides: [String: Double],
        operatingSystemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) -> CGFloat {
        let key = bundleIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let key, let override = overrides[key] {
            return CGFloat(normalizedCornerRadius(override))
        }
        return automaticCornerRadius(for: operatingSystemVersion)
    }

    static func reservingScreenEdgeClearance(in bounds: CGRect, enabled: Bool) -> CGRect {
        guard enabled else { return bounds }
        let inset = managedLayoutScreenEdgeClearance
        let candidate = bounds.insetBy(dx: inset, dy: inset)
        return candidate.width > 0 && candidate.height > 0 ? candidate : bounds
    }

    static func preferredTarget(
        accessibilityTarget: FocusedWindowHighlightTarget?,
        verifiedTarget: FocusedWindowHighlightTarget?,
        verifiedApplicationIsActive: Bool,
        verifiedWindowServerMatches: Bool
    ) -> FocusedWindowHighlightTarget? {
        guard let verifiedTarget,
              verifiedApplicationIsActive,
              verifiedWindowServerMatches
        else { return accessibilityTarget }
        if accessibilityTarget?.key == verifiedTarget.key {
            return accessibilityTarget
        }
        return verifiedTarget
    }

    static func shouldPresent(
        target: FocusedWindowHighlightTarget?,
        enabled: Bool,
        suppressed: Bool,
        ownProcessIdentifier: pid_t,
        isDeclaredGame: Bool = false,
        filters: FocusedWindowHighlightFilters = .unrestricted,
        workspaceContext: FocusedWindowHighlightWorkspaceContext? = nil
    ) -> Bool {
        guard enabled, !suppressed, !isDeclaredGame, let target,
              target.key.processIdentifier != ownProcessIdentifier,
              target.fullscreenObservation == .falseValue,
              target.frame.position.x.isFinite,
              target.frame.position.y.isFinite,
              target.frame.size.width.isFinite,
              target.frame.size.height.isFinite,
              target.frame.size.width > borderWidth * 2,
              target.frame.size.height > borderWidth * 2
        else { return false }
        if filters.tiledWorkspacesOnly || filters.multipleWindowsOnly {
            guard let workspaceContext else { return false }
            if filters.tiledWorkspacesOnly, workspaceContext.layout != .tiled {
                return false
            }
            if filters.multipleWindowsOnly, workspaceContext.windowCount <= 1 {
                return false
            }
        }
        return true
    }

    /// Accessibility frames use a top-left global origin. AppKit shares global X but mirrors Y
    /// around the main display's top edge, including for displays positioned above or below it.
    static func appKitFrame(for frame: WindowFrame, mainScreenTop: CGFloat) -> CGRect {
        CGRect(
            x: frame.position.x,
            y: mainScreenTop - frame.position.y - frame.size.height,
            width: frame.size.width,
            height: frame.size.height
        ).insetBy(dx: -borderOutset, dy: -borderOutset)
    }
}

@MainActor
protocol FocusedWindowHighlightPresenting: AnyObject {
    func update(enabled: Bool, color: NSColor, filters: FocusedWindowHighlightFilters)
    func updateVerifiedFocusTarget(_ target: FocusedWindowHighlightTarget)
    func updateCornerRadiusOverrides(_ overrides: [String: Double])
    func updateWorkspaceContexts(_ contexts: [WindowKey: FocusedWindowHighlightWorkspaceContext])
    func setSuppressed(_ suppressed: Bool, reason: String)
    func screenParametersDidChange()
    func shutdown()
}

@MainActor
final class FocusedWindowHighlightController: FocusedWindowHighlightPresenting {
    typealias ObservationProvider = @MainActor () -> FocusedWindowHighlightTarget?
    typealias MainScreenTopProvider = @MainActor () -> CGFloat?

    private let diagnostics: DiagnosticLogger
    private let ownProcessIdentifier: pid_t
    private let observationProvider: ObservationProvider
    private let mainScreenTopProvider: MainScreenTopProvider
    private var enabled = false
    private var suppressed = false
    private var color = NSColor.controlAccentColor
    private var filters = FocusedWindowHighlightFilters.unrestricted
    private var cornerRadiusOverrides: [String: Double] = [:]
    private var workspaceContexts: [WindowKey: FocusedWindowHighlightWorkspaceContext] = [:]
    private var declaredGameByApplicationIdentity: [String: Bool] = [:]
    private var timer: Timer?
    private var panel: FocusedWindowHighlightPanel?
    private var borderView: FocusedWindowHighlightView?
    private var presentedTarget: WindowKey?
    private var verifiedFocusTarget: FocusedWindowHighlightTarget?

    init(
        diagnostics: DiagnosticLogger = .disabled,
        ownProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        observationProvider: @escaping ObservationProvider = FocusedWindowHighlightController.focusedTarget,
        mainScreenTopProvider: @escaping MainScreenTopProvider = FocusedWindowHighlightController.mainScreenTop
    ) {
        self.diagnostics = diagnostics
        self.ownProcessIdentifier = ownProcessIdentifier
        self.observationProvider = observationProvider
        self.mainScreenTopProvider = mainScreenTopProvider
    }

    func update(enabled: Bool, color: NSColor, filters: FocusedWindowHighlightFilters) {
        let enabledChanged = self.enabled != enabled
        let filtersChanged = self.filters != filters
        self.enabled = enabled
        self.color = color
        self.filters = filters
        if !enabled {
            verifiedFocusTarget = nil
        }
        borderView?.strokeColor = color
        let reason = enabledChanged
            ? "setting-changed"
            : filtersChanged ? "filters-changed" : "colour-changed"
        reconcileMonitoring(reason: reason)
    }

    func updateVerifiedFocusTarget(_ target: FocusedWindowHighlightTarget) {
        verifiedFocusTarget = target
        guard enabled, !suppressed else { return }
        refresh()
    }

    func updateWorkspaceContexts(
        _ contexts: [WindowKey: FocusedWindowHighlightWorkspaceContext]
    ) {
        guard workspaceContexts != contexts else { return }
        workspaceContexts = contexts
        guard enabled, !suppressed else { return }
        refresh()
    }

    func updateCornerRadiusOverrides(_ overrides: [String: Double]) {
        guard cornerRadiusOverrides != overrides else { return }
        cornerRadiusOverrides = overrides
        guard enabled, !suppressed else { return }
        refresh()
    }

    func setSuppressed(_ suppressed: Bool, reason: String) {
        guard self.suppressed != suppressed else { return }
        self.suppressed = suppressed
        if suppressed {
            verifiedFocusTarget = nil
        }
        reconcileMonitoring(reason: reason)
    }

    func screenParametersDidChange() {
        guard enabled, !suppressed else { return }
        refresh()
    }

    func shutdown() {
        enabled = false
        verifiedFocusTarget = nil
        stopMonitoring()
        dismiss(reason: "shutdown")
        panel?.close()
        panel = nil
        borderView = nil
    }

    private func reconcileMonitoring(reason: String) {
        guard enabled, !suppressed else {
            stopMonitoring()
            dismiss(reason: reason)
            return
        }
        startMonitoringIfNeeded()
        refresh()
    }

    private func startMonitoringIfNeeded() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: FocusedWindowHighlightPolicy.refreshInterval, repeats: true) {
            [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        diagnostics.log(
            category: "focused-window-highlight",
            event: "monitoring-started",
            fields: ["non-activating": "true"]
        )
    }

    private func stopMonitoring() {
        guard timer != nil else { return }
        timer?.invalidate()
        timer = nil
        diagnostics.log(
            category: "focused-window-highlight",
            event: "monitoring-stopped"
        )
    }

    private func refresh() {
        let accessibilityTarget = observationProvider()
        let verifiedApplicationIsActive = verifiedFocusTarget.flatMap {
            NSRunningApplication(processIdentifier: $0.key.processIdentifier)
        }?.isActive == true
        let verifiedWindowServerMatches = verifiedFocusTarget.map {
            AccessibilityWindow.frontmostOnScreenNormalWindowIdentifier(
                for: $0.key.processIdentifier
            ) == $0.key.windowIdentifier
        } ?? false
        let target = FocusedWindowHighlightPolicy.preferredTarget(
            accessibilityTarget: accessibilityTarget,
            verifiedTarget: verifiedFocusTarget,
            verifiedApplicationIsActive: verifiedApplicationIsActive,
            verifiedWindowServerMatches: verifiedWindowServerMatches
        )
        if let verifiedFocusTarget {
            if accessibilityTarget?.key == verifiedFocusTarget.key ||
                !verifiedApplicationIsActive || !verifiedWindowServerMatches {
                self.verifiedFocusTarget = nil
            }
        }
        guard FocusedWindowHighlightPolicy.shouldPresent(
            target: target,
            enabled: enabled,
            suppressed: suppressed,
            ownProcessIdentifier: ownProcessIdentifier,
            isDeclaredGame: target.map(isDeclaredGame) ?? false,
            filters: filters,
            workspaceContext: target.flatMap { workspaceContexts[$0.key] }
        ), let target, let mainScreenTop = mainScreenTopProvider()
        else {
            dismiss(reason: "no-eligible-focused-window")
            return
        }

        let frame = FocusedWindowHighlightPolicy.appKitFrame(
            for: target.frame,
            mainScreenTop: mainScreenTop
        )
        let panel = ensurePanel()
        borderView?.cornerRadius = FocusedWindowHighlightPolicy.resolvedCornerRadius(
            bundleIdentifier: target.bundleIdentifier,
            overrides: cornerRadiusOverrides
        )
        panel.setFrame(frame, display: true)
        if presentedTarget != target.key || !panel.isVisible {
            panel.orderFrontRegardless()
            diagnostics.log(
                category: "focused-window-highlight",
                event: "presented",
                fields: [
                    "non-activating": "true",
                    "observation-source": target.observationSource.rawValue,
                ]
            )
        }
        presentedTarget = target.key
    }

    private func isDeclaredGame(_ target: FocusedWindowHighlightTarget) -> Bool {
        let application = NSRunningApplication(
            processIdentifier: target.key.processIdentifier
        )
        let identity = target.bundleIdentifier?.lowercased()
            ?? application?.bundleURL?.standardizedFileURL.path.lowercased()
            ?? "pid:\(target.key.processIdentifier)"
        if let cached = declaredGameByApplicationIdentity[identity] { return cached }
        guard let bundle = application?.bundleURL.flatMap({ Bundle(url: $0) }) else {
            // A launch transition can expose the AX window before Launch Services resolves its
            // bundle. Do not cache that temporary absence; the next highlight poll will retry.
            return false
        }
        let declared = FullscreenGameMetadataPolicy.isDeclaredGame(bundle: bundle)
        declaredGameByApplicationIdentity[identity] = declared
        return declared
    }

    private func dismiss(reason: String) {
        guard presentedTarget != nil || panel?.isVisible == true else { return }
        panel?.orderOut(nil)
        presentedTarget = nil
        diagnostics.log(
            category: "focused-window-highlight",
            event: "dismissed",
            fields: ["reason": reason]
        )
    }

    private func ensurePanel() -> FocusedWindowHighlightPanel {
        if let panel { return panel }
        let panel = FocusedWindowHighlightPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = FocusedWindowHighlightPanelPolicy.nonActivating.ignoresMouseEvents
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false

        let borderView = FocusedWindowHighlightView(
            strokeColor: color,
            lineWidth: FocusedWindowHighlightPolicy.borderWidth,
            cornerRadius: FocusedWindowHighlightPolicy.automaticCornerRadius()
        )
        borderView.autoresizingMask = [.width, .height]
        panel.contentView = borderView
        self.panel = panel
        self.borderView = borderView
        return panel
    }

    private static func focusedTarget() -> FocusedWindowHighlightTarget? {
        let system = AXUIElementCreateSystemWide()
        guard let focusedApplication = AccessibilityWindow.copyAttribute(
            system,
            kAXFocusedApplicationAttribute as CFString,
            as: AXUIElement.self
        ) else { return nil }

        var processIdentifier: pid_t = 0
        AXUIElementGetPid(focusedApplication, &processIdentifier)
        let application = NSRunningApplication(processIdentifier: processIdentifier)
        let bundleIdentifier = application?.bundleIdentifier
        guard let focusedWindow = AccessibilityWindow.copyAttribute(
            focusedApplication,
            kAXFocusedWindowAttribute as CFString,
            as: AXUIElement.self
        ) else { return nil }

        return target(
            for: focusedWindow,
            processIdentifier: processIdentifier,
            bundleIdentifier: bundleIdentifier,
            observationSource: .accessibilityFocusedWindow
        )
    }

    private static func target(
        for window: AXUIElement,
        processIdentifier: pid_t,
        bundleIdentifier: String?,
        observationSource: FocusedWindowHighlightObservationSource
    ) -> FocusedWindowHighlightTarget? {
        guard let key = AccessibilityWindow.identifier(
            for: window,
            processIdentifier: processIdentifier
        ), let frame = AccessibilityWindow.frame(of: window)
        else { return nil }
        return FocusedWindowHighlightTarget(
            key: key,
            frame: frame,
            fullscreenObservation: AccessibilityWindow.fullscreenObservation(of: window),
            bundleIdentifier: bundleIdentifier,
            observationSource: observationSource
        )
    }

    private static func mainScreenTop() -> CGFloat? {
        let mainDisplayID = CGMainDisplayID()
        return NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else { return false }
            return number.uint32Value == mainDisplayID
        }?.frame.maxY
    }
}

private final class FocusedWindowHighlightPanel: NSPanel {
    override var canBecomeKey: Bool {
        FocusedWindowHighlightPanelPolicy.nonActivating.canBecomeKey
    }

    override var canBecomeMain: Bool {
        FocusedWindowHighlightPanelPolicy.nonActivating.canBecomeMain
    }
}

private final class FocusedWindowHighlightView: NSView {
    var strokeColor: NSColor {
        didSet { needsDisplay = true }
    }
    private let lineWidth: CGFloat
    var cornerRadius: CGFloat {
        didSet { needsDisplay = true }
    }

    init(strokeColor: NSColor, lineWidth: CGFloat, cornerRadius: CGFloat) {
        self.strokeColor = strokeColor
        self.lineWidth = lineWidth
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        strokeColor.setStroke()
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2),
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )
        path.lineWidth = lineWidth
        path.stroke()
    }
}
