import AppKit

struct TiledResizePreviewPresentation: Equatable, Sendable {
    let token: UUID
    let displayIdentifier: String
    let layoutBounds: WindowFrame
    let frames: [WindowKey: WindowFrame]
    let transition: TiledResizePreviewTransition
    let role: TiledResizePreviewRole
}

enum TiledResizePreviewRole: Equatable, Sendable {
    case layout
    case landing
}

enum TiledResizePreviewTransition: Equatable, Sendable {
    case immediate
    case animated

    func shouldAnimate(isContinuation: Bool) -> Bool {
        self == .animated && isContinuation
    }
}

enum TiledResizePreviewEvent: Equatable, Sendable {
    case present(TiledResizePreviewPresentation)
    case dismiss(token: UUID, reason: String)
}

struct TiledResizePreviewPanelPolicy: Equatable, Sendable {
    let canBecomeKey: Bool
    let canBecomeMain: Bool
    let ignoresMouseEvents: Bool
    let participatesInWindowCycle: Bool

    static let nonActivating = TiledResizePreviewPanelPolicy(
        canBecomeKey: false,
        canBecomeMain: false,
        ignoresMouseEvents: true,
        participatesInWindowCycle: false
    )
}

enum TiledResizePreviewPolicy {
    static let updateInterval: TimeInterval = 1.0 / 30.0
    static let moveAnimationDuration: TimeInterval = 0.16
    static let tileCornerRadius: CGFloat = 18
    static let tileInset: CGFloat = 2
    static let nativeBorderWidth: CGFloat = 0.75

    /// Accessibility and Core Graphics frames use a top-left global origin. AppKit mirrors Y
    /// around the main display's top edge, including for displays above or below the main display.
    static func appKitFrame(for frame: WindowFrame, mainScreenTop: CGFloat) -> CGRect {
        CGRect(
            x: frame.position.x,
            y: mainScreenTop - frame.position.y - frame.size.height,
            width: frame.size.width,
            height: frame.size.height
        )
    }

    static func localTileFrame(
        _ frame: WindowFrame,
        panelFrame: CGRect,
        mainScreenTop: CGFloat
    ) -> CGRect {
        let global = appKitFrame(for: frame, mainScreenTop: mainScreenTop)
        return global.offsetBy(dx: -panelFrame.minX, dy: -panelFrame.minY)
            .insetBy(dx: tileInset, dy: tileInset)
    }
}

struct TiledResizeDraggedEdges: OptionSet, Equatable, Sendable {
    let rawValue: UInt8

    static let left = TiledResizeDraggedEdges(rawValue: 1 << 0)
    static let right = TiledResizeDraggedEdges(rawValue: 1 << 1)
    static let top = TiledResizeDraggedEdges(rawValue: 1 << 2)
    static let bottom = TiledResizeDraggedEdges(rawValue: 1 << 3)

    static func inferred(
        expectedFrame: WindowFrame,
        observedFrame: WindowFrame,
        tolerance: CGFloat = 2
    ) -> TiledResizeDraggedEdges {
        let expected = CGRect(origin: expectedFrame.position, size: expectedFrame.size)
        let observed = CGRect(origin: observedFrame.position, size: observedFrame.size)
        var result: TiledResizeDraggedEdges = []

        if abs(observed.width - expected.width) > tolerance {
            let leadingDelta = abs(observed.minX - expected.minX)
            let trailingDelta = abs(observed.maxX - expected.maxX)
            result.insert(leadingDelta > trailingDelta ? .left : .right)
        }
        if abs(observed.height - expected.height) > tolerance {
            let leadingDelta = abs(observed.minY - expected.minY)
            let trailingDelta = abs(observed.maxY - expected.maxY)
            result.insert(leadingDelta > trailingDelta ? .top : .bottom)
        }
        return result
    }

    func containsPointer(
        _ pointer: CGPoint,
        on frame: WindowFrame,
        tolerance: CGFloat
    ) -> Bool {
        guard !isEmpty, tolerance.isFinite, tolerance >= 0 else { return false }
        let rect = CGRect(origin: frame.position, size: frame.size)
        if contains(.left) || contains(.right),
           pointer.y < rect.minY - tolerance || pointer.y > rect.maxY + tolerance {
            return false
        }
        if contains(.top) || contains(.bottom),
           pointer.x < rect.minX - tolerance || pointer.x > rect.maxX + tolerance {
            return false
        }
        if contains(.left), abs(pointer.x - rect.minX) > tolerance { return false }
        if contains(.right), abs(pointer.x - rect.maxX) > tolerance { return false }
        if contains(.top), abs(pointer.y - rect.minY) > tolerance { return false }
        if contains(.bottom), abs(pointer.y - rect.maxY) > tolerance { return false }
        return true
    }

    func projectedFrame(
        from anchorFrame: WindowFrame,
        anchorPointer: CGPoint,
        pointer: CGPoint
    ) -> WindowFrame? {
        guard !isEmpty else { return nil }
        var projected = CGRect(origin: anchorFrame.position, size: anchorFrame.size)
        let delta = CGPoint(x: pointer.x - anchorPointer.x, y: pointer.y - anchorPointer.y)

        if contains(.left) {
            let fixed = projected.maxX
            projected.origin.x += delta.x
            projected.size.width = fixed - projected.minX
        } else if contains(.right) {
            projected.size.width += delta.x
        }
        if contains(.top) {
            let fixed = projected.maxY
            projected.origin.y += delta.y
            projected.size.height = fixed - projected.minY
        } else if contains(.bottom) {
            projected.size.height += delta.y
        }

        guard projected.minX.isFinite, projected.minY.isFinite,
              projected.width.isFinite, projected.height.isFinite,
              projected.width > 1, projected.height > 1
        else { return nil }
        return WindowFrame(position: projected.origin, size: projected.size)
    }
}

enum TiledManualDragIntent: Equatable, Sendable {
    case move
    case resize(TiledResizeDraggedEdges)
}

enum TiledManualDragClassifier {
    /// AX can briefly report small size changes during an ordinary title-bar move. A resize is
    /// therefore credible only when the pointer is still on every edge whose geometry changed.
    /// Left/top resizes remain distinguishable from moves even though both position and size move.
    static func classify(
        expectedFrame: WindowFrame,
        observedFrame: WindowFrame,
        pointer: CGPoint,
        positionTolerance: CGFloat = 8,
        sizeTolerance: CGFloat = 2,
        edgeTolerance: CGFloat = 8
    ) -> TiledManualDragIntent? {
        guard positionTolerance.isFinite, positionTolerance >= 0,
              sizeTolerance.isFinite, sizeTolerance >= 0,
              edgeTolerance.isFinite, edgeTolerance >= 0
        else { return nil }

        let draggedEdges = TiledResizeDraggedEdges.inferred(
            expectedFrame: expectedFrame,
            observedFrame: observedFrame,
            tolerance: sizeTolerance
        )
        if draggedEdges.containsPointer(pointer, on: observedFrame, tolerance: edgeTolerance) {
            return .resize(draggedEdges)
        }

        let moved = abs(observedFrame.position.x - expectedFrame.position.x) > positionTolerance ||
            abs(observedFrame.position.y - expectedFrame.position.y) > positionTolerance
        return moved ? .move : nil
    }
}

@MainActor
protocol TiledResizePreviewPresenting: AnyObject {
    func present(_ presentation: TiledResizePreviewPresentation)
    @discardableResult func dismiss(token: UUID?, reason: String) -> Bool
    @discardableResult func screenParametersDidChange() -> Bool
    func shutdown()
}

@MainActor
final class TiledResizePreviewController: TiledResizePreviewPresenting {
    typealias MainScreenTopProvider = @MainActor () -> CGFloat?

    private let diagnostics: DiagnosticLogger
    private let mainScreenTopProvider: MainScreenTopProvider
    private var panel: TiledResizePreviewPanel?
    private var canvas: TiledResizePreviewCanvas?
    private var presentation: TiledResizePreviewPresentation?

    var presentedToken: UUID? { presentation?.token }

    init(
        diagnostics: DiagnosticLogger = .disabled,
        mainScreenTopProvider: @escaping MainScreenTopProvider = TiledResizePreviewController.mainScreenTop
    ) {
        self.diagnostics = diagnostics
        self.mainScreenTopProvider = mainScreenTopProvider
    }

    func present(_ presentation: TiledResizePreviewPresentation) {
        guard let mainScreenTop = mainScreenTopProvider(), !presentation.frames.isEmpty else {
            dismiss(token: presentation.token, reason: "invalid-presentation")
            return
        }
        if let current = self.presentation, current.token != presentation.token {
            dismiss(token: current.token, reason: "superseded")
        }

        let panelFrame = TiledResizePreviewPolicy.appKitFrame(
            for: presentation.layoutBounds,
            mainScreenTop: mainScreenTop
        )
        let panel = ensurePanel()
        panel.setFrame(panelFrame, display: true)
        let isContinuation = self.presentation?.token == presentation.token && panel.isVisible
        canvas?.update(
            frames: presentation.frames,
            panelFrame: panelFrame,
            mainScreenTop: mainScreenTop,
            animated: presentation.transition.shouldAnimate(isContinuation: isContinuation),
            role: presentation.role
        )
        let isNewPresentation = !isContinuation
        self.presentation = presentation
        if isNewPresentation {
            panel.orderFrontRegardless()
            diagnostics.log(
                category: "manual-resize-preview",
                event: "overlay-presented",
                fields: [
                    "display": presentation.displayIdentifier,
                    "window-count": String(presentation.frames.count),
                    "non-activating": "true",
                ]
            )
        }
    }

    @discardableResult
    func dismiss(token: UUID?, reason: String) -> Bool {
        guard let presentation else { return false }
        guard token == nil || token == presentation.token else { return false }
        panel?.orderOut(nil)
        canvas?.removeTiles()
        self.presentation = nil
        diagnostics.log(
            category: "manual-resize-preview",
            event: "overlay-dismissed",
            fields: ["reason": reason]
        )
        return true
    }

    @discardableResult
    func screenParametersDidChange() -> Bool {
        dismiss(token: nil, reason: "display-configuration-changed")
    }

    func shutdown() {
        dismiss(token: nil, reason: "shutdown")
        panel?.close()
        panel = nil
        canvas = nil
    }

    private func ensurePanel() -> TiledResizePreviewPanel {
        if let panel { return panel }
        let panel = TiledResizePreviewPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = TiledResizePreviewPanelPolicy.nonActivating.ignoresMouseEvents
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false

        let canvas = TiledResizePreviewCanvas(frame: .zero)
        canvas.autoresizingMask = [.width, .height]
        panel.contentView = canvas
        self.panel = panel
        self.canvas = canvas
        return panel
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

@MainActor
final class TiledResizePointerMonitor {
    private let onDragged: () -> Void
    private let onReleased: () -> Void
    private var monitor: Any?
    private var lastUpdate = Date.distantPast

    init(onDragged: @escaping () -> Void, onReleased: @escaping () -> Void) {
        self.onDragged = onDragged
        self.onReleased = onReleased
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            Task { @MainActor [weak self] in self?.handle(event) }
        }
    }

    func shutdown() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        lastUpdate = .distantPast
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDragged:
            let now = Date()
            guard now.timeIntervalSince(lastUpdate) >= TiledResizePreviewPolicy.updateInterval else {
                return
            }
            lastUpdate = now
            onDragged()
        case .leftMouseUp:
            lastUpdate = .distantPast
            onReleased()
        default:
            break
        }
    }
}

@MainActor
enum TiledResizeGlassSurfaceFactory {
    static func make(frame: CGRect) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: frame)
            glass.style = .clear
            glass.cornerRadius = TiledResizePreviewPolicy.tileCornerRadius
            glass.setAccessibilityElement(false)
            return glass
        }

        let material = NSVisualEffectView(frame: frame)
        material.material = .hudWindow
        material.blendingMode = .withinWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = TiledResizePreviewPolicy.tileCornerRadius
        material.layer?.masksToBounds = true
        material.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        material.addSubview(tileWash(frame: material.bounds))
        material.setAccessibilityElement(false)
        return material
    }

    private static func tileWash(frame: CGRect) -> NSView {
        let wash = NSView(frame: frame)
        wash.autoresizingMask = [.width, .height]
        wash.wantsLayer = true
        wash.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        wash.setAccessibilityElement(false)
        return wash
    }
}

@MainActor
final class TiledResizePreviewTileView: NSView {
    private(set) var surface: NSView!
    private let role: TiledResizePreviewRole

    override init(frame frameRect: NSRect) {
        role = .layout
        super.init(frame: frameRect)
        configureSurface()
        setAccessibilityElement(false)
    }

    init(frame frameRect: NSRect, role: TiledResizePreviewRole) {
        self.role = role
        super.init(frame: frameRect)
        configureSurface()
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureSurface() {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: bounds)
            glass.autoresizingMask = [.width, .height]
            glass.style = .clear
            glass.cornerRadius = TiledResizePreviewPolicy.tileCornerRadius
            if role == .landing {
                glass.tintColor = NSColor.controlAccentColor.withAlphaComponent(0.22)
            }
            glass.setAccessibilityElement(false)

            let border = NSView(frame: glass.bounds)
            border.autoresizingMask = [.width, .height]
            border.wantsLayer = true
            border.layer?.cornerRadius = TiledResizePreviewPolicy.tileCornerRadius
            border.layer?.masksToBounds = true
            border.layer?.borderWidth = role == .landing
                ? 1.5
                : TiledResizePreviewPolicy.nativeBorderWidth
            border.layer?.borderColor = (role == .landing
                ? NSColor.controlAccentColor.withAlphaComponent(0.90)
                : NSColor.white.withAlphaComponent(0.30)).cgColor
            border.setAccessibilityElement(false)
            glass.contentView = border

            addSubview(glass)
            surface = glass
            return
        }

        let material = TiledResizeGlassSurfaceFactory.make(frame: bounds)
        material.autoresizingMask = [.width, .height]
        material.wantsLayer = true
        material.layer?.cornerRadius = TiledResizePreviewPolicy.tileCornerRadius
        material.layer?.masksToBounds = true
        if role == .landing {
            material.layer?.backgroundColor = NSColor.controlAccentColor
                .withAlphaComponent(0.20).cgColor
            material.layer?.borderWidth = 1.5
            material.layer?.borderColor = NSColor.controlAccentColor
                .withAlphaComponent(0.90).cgColor
        } else {
            material.layer?.borderWidth = 1
            material.layer?.borderColor = NSColor.white.withAlphaComponent(0.34).cgColor
        }
        addSubview(material)
        surface = material
    }
}

@MainActor
final class TiledResizePreviewCanvas: NSView {
    private var tileViews: [WindowKey: NSView] = [:]
    private var tileHost: NSView!
    private(set) var usesNativeGlassContainer = false
    private var previewRole: TiledResizePreviewRole?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        configureTileHost()
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        frames: [WindowKey: WindowFrame],
        panelFrame: CGRect,
        mainScreenTop: CGFloat,
        animated: Bool = false,
        role: TiledResizePreviewRole = .layout
    ) {
        if let previewRole, previewRole != role {
            removeTiles()
        }
        previewRole = role
        for key in tileViews.keys where frames[key] == nil {
            tileViews.removeValue(forKey: key)?.removeFromSuperview()
        }
        var animatedChanges: [(NSView, CGRect)] = []
        for (key, frame) in frames {
            let existed = tileViews[key] != nil
            let tile = tileViews[key] ?? makeTile(for: key, role: role)
            let targetFrame = TiledResizePreviewPolicy.localTileFrame(
                frame,
                panelFrame: panelFrame,
                mainScreenTop: mainScreenTop
            )
            if animated, existed, tile.frame != targetFrame {
                animatedChanges.append((tile, targetFrame))
            } else {
                tile.frame = targetFrame
            }
        }
        guard !animatedChanges.isEmpty else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = TiledResizePreviewPolicy.moveAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            for (tile, targetFrame) in animatedChanges {
                tile.animator().frame = targetFrame
            }
        }
    }

    func removeTiles() {
        tileViews.values.forEach { $0.removeFromSuperview() }
        tileViews.removeAll()
        previewRole = nil
    }

    private func makeTile(for key: WindowKey, role: TiledResizePreviewRole) -> NSView {
        let tile = TiledResizePreviewTileView(frame: .zero, role: role)
        tile.autoresizingMask = []
        tileHost.addSubview(tile)
        tileViews[key] = tile
        return tile
    }

    private func configureTileHost() {
        if #available(macOS 26.0, *) {
            let container = NSGlassEffectContainerView(frame: bounds)
            container.autoresizingMask = [.width, .height]
            container.spacing = 0

            let content = NSView(frame: container.bounds)
            content.autoresizingMask = [.width, .height]
            container.contentView = content
            addSubview(container)

            tileHost = content
            usesNativeGlassContainer = true
            return
        }

        tileHost = self
    }
}

private final class TiledResizePreviewPanel: NSPanel {
    override var canBecomeKey: Bool {
        TiledResizePreviewPanelPolicy.nonActivating.canBecomeKey
    }

    override var canBecomeMain: Bool {
        TiledResizePreviewPanelPolicy.nonActivating.canBecomeMain
    }
}
