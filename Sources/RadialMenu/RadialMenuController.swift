import AppKit
import ApplicationServices
import SwiftUI

struct RadialMenuSessionState: Equatable, Sendable {
    private(set) var isPresented = true
    private(set) var hasCommitted = false

    mutating func commit() -> Bool {
        guard isPresented, !hasCommitted else { return false }
        hasCommitted = true
        isPresented = false
        return true
    }

    mutating func dismiss() {
        isPresented = false
    }
}

@MainActor
final class RadialMenuTriggerController {
    private let menuController: RadialMenuController
    private let diagnostics: DiagnosticLogger
    private var state = RadialMenuTriggerStateMachine()
    private var thresholdWorkItem: DispatchWorkItem?
    private var capturedContexts: [UInt64: RadialCommandContext] = [:]
    private var correlations: [UInt64: String] = [:]

    init(menuController: RadialMenuController, diagnostics: DiagnosticLogger = .disabled) {
        self.menuController = menuController
        self.diagnostics = diagnostics
        menuController.onDismissed = { [weak self] reason in
            self?.menuDidDismiss(reason: reason)
        }
    }

    func handle(
        _ event: RadialMenuTriggerInputEvent,
        style: RadialMenuActivationStyle,
        holdDelay: TimeInterval
    ) {
        diagnostics.log(
            category: "radial-trigger",
            event: event.diagnosticName,
            fields: [
                "activation-style": style.rawValue,
                "hold-delay-ms": String(Int(RadialMenuHoldDelay.clamped(holdDelay) * 1_000)),
            ]
        )
        apply(state.handle(event, style: style, holdDelay: holdDelay))
    }

    func cancel(reason: String) {
        let effects = state.cancel(reason: reason)
        apply(effects)
        // Press-to-toggle intentionally keeps no held-key phase in the trigger state machine.
        // Explicit lifecycle/profile/shortcut cancellations must nevertheless dismiss it.
        if effects.isEmpty, menuController.isPresented {
            menuController.dismiss(reason: reason)
        }
    }

    /// Starts the normal captured-context hold pipeline after a separate hardware gesture has
    /// already crossed its own threshold. This avoids a second radial implementation and avoids
    /// applying the configurable delay twice.
    func beginRecognizedHold() {
        cancel(reason: "recognized-hold-superseded-existing-trigger")
        let effects = state.handle(
            .pressed,
            style: .holdToShow,
            holdDelay: RadialMenuHoldDelay.permittedRange.lowerBound
        )
        let generation = state.latestGeneration
        apply(effects.filter { effect in
            if case .scheduleThreshold = effect { return false }
            return true
        })
        apply(state.thresholdElapsed(generation: generation))
    }

    private func apply(_ effects: [RadialMenuTriggerEffect]) {
        for effect in effects {
            switch effect {
            case .toggle:
                menuController.toggle()
            case let .captureContext(generation):
                let correlation = diagnostics.makeCorrelationID()
                correlations[generation] = correlation
                menuController.captureContext { [weak self] context in
                    guard let self else { return }
                    let hasActions = self.menuController.hasRelevantActions(in: context)
                    let effects = self.state.contextCaptured(
                        generation: generation,
                        hasRelevantActions: hasActions
                    )
                    if hasActions, !self.state.isIdle {
                        self.capturedContexts[generation] = context
                    }
                    self.apply(effects)
                    self.removeInactiveCaptures()
                }
            case let .scheduleThreshold(generation, delay):
                thresholdWorkItem?.cancel()
                let item = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.diagnostics.log(
                        category: "radial-trigger",
                        event: "hold-threshold-reached",
                        correlation: self.correlations[generation],
                        fields: ["generation": String(generation)]
                    )
                    self.apply(self.state.thresholdElapsed(generation: generation))
                }
                thresholdWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
            case let .cancelThreshold(reason):
                thresholdWorkItem?.cancel()
                thresholdWorkItem = nil
                diagnostics.log(
                    category: "radial-trigger",
                    event: "cancelled",
                    fields: ["reason": reason]
                )
                removeInactiveCaptures()
            case let .presentCaptured(generation):
                thresholdWorkItem?.cancel()
                thresholdWorkItem = nil
                guard let context = capturedContexts[generation] else {
                    diagnostics.log(
                        category: "radial-trigger",
                        event: "presentation-rejected",
                        correlation: correlations[generation],
                        fields: ["reason": "captured-context-unavailable"]
                    )
                    apply(state.presentationRejected(
                        generation: generation,
                        reason: "captured-context-unavailable"
                    ))
                    continue
                }
                let correlation = correlations[generation]
                menuController.presentCaptured(
                    context,
                    triggerGeneration: generation,
                    correlationID: correlation,
                    isStillCurrent: { [weak self] in
                        self?.state.isPresented(generation: generation) == true
                    }
                ) { [weak self] presented in
                    guard let self, !presented,
                          self.state.isPresented(generation: generation)
                    else { return }
                    self.diagnostics.log(
                        category: "radial-trigger",
                        event: "presentation-rejected",
                        correlation: self.correlations[generation],
                        fields: ["reason": "captured-context-stale"]
                    )
                    self.apply(self.state.presentationRejected(
                        generation: generation,
                        reason: "captured-context-stale"
                    ))
                }
            case let .commitHighlightedOrDismiss(generation):
                diagnostics.log(
                    category: "radial-trigger",
                    event: "released-after-presentation",
                    correlation: correlations[generation],
                    fields: ["generation": String(generation)]
                )
                menuController.commitHighlightedOrDismiss()
                capturedContexts.removeValue(forKey: generation)
                correlations.removeValue(forKey: generation)
            case let .dismiss(reason):
                menuController.dismiss(reason: reason)
                removeInactiveCaptures()
            }
        }
    }

    private func menuDidDismiss(reason: String) {
        let effects = state.cancel(reason: "menu-\(reason)")
        if !effects.isEmpty { apply(effects) }
        removeInactiveCaptures()
    }

    private func removeInactiveCaptures() {
        guard state.isIdle else { return }
        capturedContexts.removeAll()
        correlations.removeAll()
    }
}

@MainActor
protocol GlobeFnRadialTriggerHandling: AnyObject {
    func beginRecognizedHold()
    func handle(
        _ event: RadialMenuTriggerInputEvent,
        style: RadialMenuActivationStyle,
        holdDelay: TimeInterval
    )
    func cancel(reason: String)
}

extension RadialMenuTriggerController: GlobeFnRadialTriggerHandling {}

@MainActor
protocol GlobeFnScheduledTask: AnyObject {
    func cancel()
}

@MainActor
protocol GlobeFnScheduling: AnyObject {
    func schedule(
        after delay: TimeInterval,
        _ action: @escaping @MainActor () -> Void
    ) -> GlobeFnScheduledTask
}

@MainActor
private final class DispatchGlobeFnScheduledTask: GlobeFnScheduledTask {
    private var item: DispatchWorkItem?

    init(item: DispatchWorkItem) {
        self.item = item
    }

    func cancel() {
        item?.cancel()
        item = nil
    }
}

@MainActor
final class MainQueueGlobeFnScheduler: GlobeFnScheduling {
    func schedule(
        after delay: TimeInterval,
        _ action: @escaping @MainActor () -> Void
    ) -> GlobeFnScheduledTask {
        let item = DispatchWorkItem { action() }
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: item)
        return DispatchGlobeFnScheduledTask(item: item)
    }
}

enum GlobeFnEventMonitorInterruption: String, Equatable, Sendable {
    case timedOut = "tap-timeout"
    case disabledByUserInput = "tap-disabled-by-user-input"
}

@MainActor
protocol GlobeFnEventMonitoring: AnyObject {
    func start() -> Bool
    func stop()
    func reenable() -> Bool
}

/// One centrally owned public Quartz event tap. It forwards every event except a synthetic native
/// Globe action that the pure state machine explicitly associates with an accepted hold. It never
/// requests permission; failure is reported to Settings and can be retried safely.
@MainActor
final class CGGlobeFnEventMonitor: GlobeFnEventMonitoring {
    typealias EventHandler = @MainActor (GlobeFnObservedEvent) -> Bool
    typealias InterruptionHandler = @MainActor (GlobeFnEventMonitorInterruption) -> Void

    private let eventHandler: EventHandler
    private let interruptionHandler: InterruptionHandler
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private static let systemDefinedEventType = CGEventType(rawValue: 14)!

    init(
        eventHandler: @escaping EventHandler,
        interruptionHandler: @escaping InterruptionHandler
    ) {
        self.eventHandler = eventHandler
        self.interruptionHandler = interruptionHandler
    }

    deinit {
        MainActor.assumeIsolated { stop() }
    }

    func start() -> Bool {
        if let eventTap, CFMachPortIsValid(eventTap) {
            CGEvent.tapEnable(tap: eventTap, enable: true)
            return CGEvent.tapIsEnabled(tap: eventTap)
        }

        guard AXIsProcessTrusted() else { return false }

        let observedTypes: [CGEventType] = [
            .flagsChanged,
            .keyDown,
            .keyUp,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            Self.systemDefinedEventType,
        ]
        let mask = observedTypes.reduce(CGEventMask(0)) {
            $0 | (CGEventMask(1) << $1.rawValue)
        }
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<CGGlobeFnEventMonitor>
                .fromOpaque(userInfo)
                .takeUnretainedValue()
            return MainActor.assumeIsolated {
                if monitor.process(type: type, event: event) {
                    return nil
                }
                return Unmanaged.passUnretained(event)
            }
        }
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        else { return false }

        self.eventTap = eventTap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return CGEvent.tapIsEnabled(tap: eventTap)
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
    }

    func reenable() -> Bool {
        guard let eventTap, CFMachPortIsValid(eventTap) else { return false }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return CGEvent.tapIsEnabled(tap: eventTap)
    }

    private func process(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout:
            interruptionHandler(.timedOut)
            return false
        case .tapDisabledByUserInput:
            interruptionHandler(.disabledByUserInput)
            return false
        case .flagsChanged:
            let flags = event.flags
            let otherModifiers: CGEventFlags = [
                .maskAlphaShift,
                .maskShift,
                .maskControl,
                .maskAlternate,
                .maskCommand,
                .maskHelp,
                .maskNumericPad,
            ]
            return eventHandler(.flagsChanged(
                functionDown: flags.contains(.maskSecondaryFn),
                otherModifiersDown: !flags.intersection(otherModifiers).isEmpty
            ))
        case .keyDown, .keyUp:
            return eventHandler(.keyChanged(
                isDown: type == .keyDown,
                keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            ))
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return eventHandler(.mouseButtonDown)
        case let eventType where eventType == Self.systemDefinedEventType:
            return eventHandler(.systemDefined)
        default:
            return false
        }
    }
}

/// Runtime adapter for the pure gesture state. The normal Carbon shortcut and Fn trigger both feed
/// the same `RadialMenuTriggerController`; only admission, timing and native-event passthrough live
/// here.
@MainActor
final class GlobeFnHoldActivationController {
    typealias MonitorFactory = @MainActor (
        @escaping CGGlobeFnEventMonitor.EventHandler,
        @escaping CGGlobeFnEventMonitor.InterruptionHandler
    ) -> GlobeFnEventMonitoring

    private let radialTrigger: GlobeFnRadialTriggerHandling
    private let scheduler: GlobeFnScheduling
    private let diagnostics: DiagnosticLogger
    private let monitorFactory: MonitorFactory
    private var state = GlobeFnGestureStateMachine()
    private var normalizer = GlobeFnEventNormalizer()
    private var thresholdTask: GlobeFnScheduledTask?
    private var safetyTask: GlobeFnScheduledTask?
    private var suppressionTask: GlobeFnScheduledTask?
    private var monitor: GlobeFnEventMonitoring?
    private var desiredEnabled = false
    private var holdDelay = RadialMenuHoldDelay.defaultValue
    private var lastObservedFunctionState: Bool?
    private var lastLoggedConfiguration: String?

    var runtimeIssueChanged: ((String?) -> Void)?

    init(
        radialTrigger: GlobeFnRadialTriggerHandling,
        scheduler: GlobeFnScheduling? = nil,
        diagnostics: DiagnosticLogger = .disabled,
        monitorFactory: @escaping MonitorFactory = { eventHandler, interruptionHandler in
            CGGlobeFnEventMonitor(
                eventHandler: eventHandler,
                interruptionHandler: interruptionHandler
            )
        }
    ) {
        self.radialTrigger = radialTrigger
        self.scheduler = scheduler ?? MainQueueGlobeFnScheduler()
        self.diagnostics = diagnostics
        self.monitorFactory = monitorFactory
    }

    func update(enabled: Bool, holdDelay: TimeInterval) {
        let clampedDelay = RadialMenuHoldDelay.clamped(holdDelay)
        let configuration = "enabled=\(enabled)|delay=\(Int(clampedDelay * 1_000))"
        if configuration != lastLoggedConfiguration {
            lastLoggedConfiguration = configuration
            diagnostics.log(
                category: "globe-fn-trigger",
                event: "configuration-updated",
                fields: [
                    "enabled": String(enabled),
                    "hold-delay-ms": String(Int(clampedDelay * 1_000)),
                ]
            )
        }
        if self.holdDelay != clampedDelay {
            cancel(reason: "hold-delay-changed")
            self.holdDelay = clampedDelay
        }
        desiredEnabled = enabled
        if enabled {
            installMonitorIfNeeded(reason: "setting-enabled")
        } else {
            cancel(reason: "setting-disabled")
            monitor?.stop()
            monitor = nil
            lastObservedFunctionState = nil
            runtimeIssueChanged?(nil)
        }
    }

    func ordinaryShortcutWillBegin() {
        cancel(reason: "ordinary-shortcut-superseded")
    }

    func cancel(reason: String) {
        let before = state.phaseName
        let effects = state.handle(.cancel(reason: reason), holdDelay: holdDelay)
        apply(effects)
        normalizer.reset()
        if before != state.phaseName || !effects.isEmpty {
            diagnostics.log(
                category: "globe-fn-trigger",
                event: "cancelled",
                fields: ["reason": reason]
            )
        }
    }

    func retryMonitor(reason: String) {
        guard desiredEnabled else { return }
        monitor?.stop()
        monitor = nil
        installMonitorIfNeeded(reason: reason)
    }

    func resumeAfterLifecycle(reason: String) {
        guard desiredEnabled else { return }
        cancel(reason: reason)
        installMonitorIfNeeded(reason: reason)
    }

    func shutdown() {
        desiredEnabled = false
        cancel(reason: "shutdown")
        monitor?.stop()
        monitor = nil
        lastObservedFunctionState = nil
    }

    @discardableResult
    func receive(_ observedEvent: GlobeFnObservedEvent) -> Bool {
        guard desiredEnabled else { return false }
        if case let .flagsChanged(functionDown, otherModifiersDown) = observedEvent,
           lastObservedFunctionState != functionDown {
            lastObservedFunctionState = functionDown
            diagnostics.log(
                category: "globe-fn-trigger",
                event: "fn-transition-observed",
                fields: [
                    "state": functionDown ? "down" : "up",
                    "other-modifiers": String(otherModifiersDown),
                ]
            )
        }
        guard let input = normalizer.normalize(observedEvent) else { return false }
        let before = state.phaseName
        let effects = state.handle(input, holdDelay: holdDelay)
        let shouldSuppress = apply(effects)
        let after = state.phaseName
        if before == "candidate",
           effects.contains(where: { effect in
               if case .cancelThreshold = effect { return true }
               return false
           }) {
            diagnostics.log(
                category: "globe-fn-trigger",
                event: "hold-not-accepted",
                fields: ["reason": input.diagnosticName]
            )
        }
        if before != after || shouldSuppress {
            diagnostics.log(
                category: "globe-fn-trigger",
                event: "state-transition",
                fields: [
                    "from": before,
                    "to": after,
                    "input": input.diagnosticName,
                    "suppressed-native-event": String(shouldSuppress),
                ]
            )
        }
        return shouldSuppress
    }

    private func installMonitorIfNeeded(reason: String) {
        guard monitor == nil else { return }
        let monitor = monitorFactory(
            { [weak self] event in self?.receive(event) ?? false },
            { [weak self] interruption in self?.monitorInterrupted(interruption) }
        )
        guard monitor.start() else {
            monitor.stop()
            runtimeIssueChanged?(
                "Globe/Fn monitoring is unavailable. WindowRanger did not request another permission; turn the option off and on after Accessibility access is available."
            )
            diagnostics.log(
                category: "globe-fn-trigger",
                event: "monitor-install-failed",
                fields: ["reason": reason]
            )
            return
        }
        self.monitor = monitor
        lastObservedFunctionState = nil
        runtimeIssueChanged?(nil)
        diagnostics.log(
            category: "globe-fn-trigger",
            event: "monitor-installed",
            fields: ["reason": reason]
        )
        diagnostics.log(
            category: "globe-fn-trigger",
            event: "monitor-awaiting-fn-transition",
            fields: [:]
        )
    }

    private func monitorInterrupted(_ interruption: GlobeFnEventMonitorInterruption) {
        cancel(reason: interruption.rawValue)
        let restored = monitor?.reenable() == true
        if !restored {
            monitor?.stop()
            monitor = nil
            lastObservedFunctionState = nil
        }
        runtimeIssueChanged?(restored ? nil : "Globe/Fn monitoring stopped and could not be restored. Toggle the option to retry.")
        diagnostics.log(
            category: "globe-fn-trigger",
            event: restored ? "monitor-reenabled" : "monitor-reenable-failed",
            fields: ["reason": interruption.rawValue]
        )
    }

    @discardableResult
    private func apply(_ effects: [GlobeFnGestureEffect]) -> Bool {
        var shouldSuppress = false
        for effect in effects {
            switch effect {
            case let .scheduleThreshold(generation, delay):
                thresholdTask?.cancel()
                thresholdTask = scheduler.schedule(after: delay) { [weak self] in
                    guard let self else { return }
                    self.thresholdTask = nil
                    _ = self.apply(self.state.handle(
                        .thresholdElapsed(generation: generation),
                        holdDelay: self.holdDelay
                    ))
                }
                safetyTask?.cancel()
                safetyTask = scheduler.schedule(
                    after: GlobeFnGestureStateMachine.maximumGestureDuration
                ) { [weak self] in
                    guard let self else { return }
                    self.safetyTask = nil
                    _ = self.apply(self.state.handle(
                        .cancel(reason: "gesture-safety-timeout"),
                        holdDelay: self.holdDelay
                    ))
                    self.normalizer.reset()
                    self.diagnostics.log(
                        category: "globe-fn-trigger",
                        event: "gesture-safety-timeout",
                        fields: [:]
                    )
                }
            case let .cancelThreshold(reason):
                thresholdTask?.cancel()
                thresholdTask = nil
                safetyTask?.cancel()
                safetyTask = nil
                diagnostics.log(
                    category: "globe-fn-trigger",
                    event: "threshold-cancelled",
                    fields: ["reason": reason]
                )
            case .activateHold:
                diagnostics.log(
                    category: "globe-fn-trigger",
                    event: "hold-accepted",
                    fields: [:]
                )
                radialTrigger.beginRecognizedHold()
            case .releaseHold:
                safetyTask?.cancel()
                safetyTask = nil
                radialTrigger.handle(
                    .released,
                    style: .holdToShow,
                    holdDelay: holdDelay
                )
            case let .cancelHold(reason):
                safetyTask?.cancel()
                safetyTask = nil
                radialTrigger.cancel(reason: "globe-fn-\(reason)")
            case let .scheduleSuppressionExpiry(generation, delay):
                suppressionTask?.cancel()
                suppressionTask = scheduler.schedule(after: delay) { [weak self] in
                    guard let self else { return }
                    self.suppressionTask = nil
                    _ = self.apply(self.state.handle(
                        .suppressionExpired(generation: generation),
                        holdDelay: self.holdDelay
                    ))
                }
            case .cancelSuppressionExpiry:
                suppressionTask?.cancel()
                suppressionTask = nil
            case .suppressCurrentEvent:
                shouldSuppress = true
            }
        }
        return shouldSuppress
    }
}

private extension GlobeFnGestureInputEvent {
    var diagnosticName: String {
        switch self {
        case let .functionChanged(isDown, otherModifiersDown):
            if otherModifiersDown { return isDown ? "fn-down-with-modifier" : "fn-up-with-modifier" }
            return isDown ? "fn-down" : "fn-up"
        case let .competingInput(input): return "competing-\(input.rawValue)"
        case let .nativeGlobeKey(isDown): return isDown ? "native-globe-down" : "native-globe-up"
        case .thresholdElapsed: return "threshold-elapsed"
        case .suppressionExpired: return "suppression-expired"
        case let .cancel(reason): return "cancel-\(reason)"
        }
    }
}

private extension RadialMenuTriggerInputEvent {
    var diagnosticName: String {
        switch self {
        case .pressed: "pressed"
        case .released: "released"
        case .escape: "escape"
        }
    }
}

enum RadialMenuInteractionEffect: Equatable, Sendable {
    case scheduleGroupDwell(Int)
    case cancelGroupDwell
}

/// Pure two-ring interaction state. Timing and AppKit event delivery stay in the presentation
/// adapter; selection, group disclosure, inward return, and keyboard ordering are deterministic
/// and testable without creating a window or installing an event monitor.
struct RadialMenuInteractionState: Equatable, Sendable {
    private(set) var selectedInnerIndex: Int?
    private(set) var activeGroupIndex: Int?
    private(set) var selectedOuterIndex: Int?

    mutating func selectPointer(
        _ selection: RadialMenuGeometry.Selection?,
        childCounts: [Int]
    ) -> [RadialMenuInteractionEffect] {
        switch selection?.ring {
        case .inner:
            guard let index = selection?.index, childCounts.indices.contains(index) else { return [] }
            selectedInnerIndex = index
            selectedOuterIndex = nil
            if childCounts[index] > 0 {
                guard activeGroupIndex != index else { return [] }
                activeGroupIndex = nil
                return [.scheduleGroupDwell(index)]
            }
            activeGroupIndex = nil
            return [.cancelGroupDwell]
        case .outer:
            guard let group = activeGroupIndex,
                  childCounts.indices.contains(group),
                  let index = selection?.index,
                  (0..<childCounts[group]).contains(index)
            else { return [] }
            selectedOuterIndex = index
            return []
        case nil:
            selectedInnerIndex = nil
            selectedOuterIndex = nil
            return []
        }
    }

    mutating func discloseSelectedGroupImmediately(childCounts: [Int]) -> [RadialMenuInteractionEffect] {
        guard let index = selectedInnerIndex,
              childCounts.indices.contains(index),
              childCounts[index] > 0
        else { return [] }
        activeGroupIndex = index
        selectedOuterIndex = nil
        return [.cancelGroupDwell]
    }

    mutating func dwellElapsed(for index: Int, childCounts: [Int]) -> [RadialMenuInteractionEffect] {
        guard selectedInnerIndex == index,
              childCounts.indices.contains(index),
              childCounts[index] > 0
        else { return [] }
        activeGroupIndex = index
        selectedOuterIndex = nil
        return [.cancelGroupDwell]
    }

    mutating func moveSelection(_ offset: Int, childCounts: [Int]) -> [RadialMenuInteractionEffect] {
        if let group = activeGroupIndex,
           childCounts.indices.contains(group),
           selectedOuterIndex != nil,
           childCounts[group] > 0 {
            selectedOuterIndex = Self.wrapped(
                (selectedOuterIndex ?? (offset > 0 ? -1 : 0)) + offset,
                count: childCounts[group]
            )
            return []
        }
        guard !childCounts.isEmpty else { return [] }
        selectedInnerIndex = Self.wrapped(
            (selectedInnerIndex ?? (offset > 0 ? -1 : 0)) + offset,
            count: childCounts.count
        )
        activeGroupIndex = nil
        selectedOuterIndex = nil
        return [.cancelGroupDwell]
    }

    mutating func enterSelectedGroup(childCounts: [Int]) -> [RadialMenuInteractionEffect] {
        guard let index = selectedInnerIndex,
              childCounts.indices.contains(index),
              childCounts[index] > 0
        else { return [] }
        activeGroupIndex = index
        selectedOuterIndex = 0
        return [.cancelGroupDwell]
    }

    mutating func returnInward() -> [RadialMenuInteractionEffect] {
        guard let activeGroupIndex else { return [] }
        selectedInnerIndex = activeGroupIndex
        selectedOuterIndex = nil
        self.activeGroupIndex = nil
        return [.cancelGroupDwell]
    }

    mutating func clear() -> [RadialMenuInteractionEffect] {
        selectedInnerIndex = nil
        activeGroupIndex = nil
        selectedOuterIndex = nil
        return [.cancelGroupDwell]
    }

    private static func wrapped(_ value: Int, count: Int) -> Int {
        (value % count + count) % count
    }
}

@MainActor
final class RadialMenuPresentationModel: ObservableObject {
    let menu: RadialMenuModel
    let activationStyle: RadialMenuActivationStyle
    @Published private var interaction = RadialMenuInteractionState()
    private var pointerState = RadialMenuGeometry.PointerState()
    private var dwellWorkItem: DispatchWorkItem?
    var commitItem: ((RadialMenuItem, Bool) -> Void)?
    var cancel: (() -> Void)?
    var groupDisclosed: ((RadialMenuItem, String) -> Void)?

    init(menu: RadialMenuModel, activationStyle: RadialMenuActivationStyle = .pressToToggle) {
        self.menu = menu
        self.activationStyle = activationStyle
    }

    var items: [RadialMenuItem] { menu.items }
    var selectedInnerIndex: Int? { interaction.selectedInnerIndex }
    var activeGroupIndex: Int? { interaction.activeGroupIndex }
    var selectedOuterIndex: Int? { interaction.selectedOuterIndex }

    private var childCounts: [Int] { items.map(\.children.count) }

    var activeChildren: [RadialMenuItem] {
        guard let activeGroupIndex, items.indices.contains(activeGroupIndex) else { return [] }
        return items[activeGroupIndex].children
    }

    var selectedItem: RadialMenuItem? {
        if let selectedOuterIndex, activeChildren.indices.contains(selectedOuterIndex) {
            return activeChildren[selectedOuterIndex]
        }
        guard let selectedInnerIndex, items.indices.contains(selectedInnerIndex) else { return nil }
        return items[selectedInnerIndex]
    }

    var selectedRing: RadialMenuGeometry.Ring? {
        if selectedOuterIndex != nil { return .outer }
        if selectedInnerIndex != nil { return .inner }
        return nil
    }

    func activate(_ item: RadialMenuItem, useAlternate: Bool = false) {
        if let command = useAlternate ? (item.alternateCommand ?? item.command) : item.command,
           command == item.command || command == item.alternateCommand {
            commitItem?(item, useAlternate && item.alternateCommand != nil)
        } else if item.isGroup, let index = items.firstIndex(where: { $0.id == item.id }) {
            mutateInteraction(disclosureReason: "click") { state in
                var effects = state.selectPointer(
                    .init(ring: .inner, index: index),
                    childCounts: childCounts
                )
                effects.append(contentsOf: state.enterSelectedGroup(childCounts: childCounts))
                return effects
            }
        }
    }

    func activateSelection() {
        guard let selectedItem else { return }
        activate(selectedItem, useAlternate: NSEvent.modifierFlags.contains(.option))
    }

    func moveSelection(_ offset: Int) {
        mutateInteraction { $0.moveSelection(offset, childCounts: childCounts) }
    }

    func enterSelectedGroup() {
        mutateInteraction(disclosureReason: "keyboard") {
            $0.enterSelectedGroup(childCounts: childCounts)
        }
    }

    func returnInward() {
        pointerState.reset()
        mutateInteraction { $0.returnInward() }
    }

    func pointerMoved(to point: CGPoint, center: CGPoint) {
        if activationStyle == .holdToShow,
           let selectedInnerIndex,
           items.indices.contains(selectedInnerIndex),
           items[selectedInnerIndex].isGroup,
           hypot(point.x - center.x, point.y - center.y) >= RadialMenuGeometry.outerInnerRadius,
           activeGroupIndex != selectedInnerIndex {
            mutateInteraction(disclosureReason: "hold-outward") {
                $0.discloseSelectedGroupImmediately(childCounts: childCounts)
            }
        }
        let selection = pointerState.update(
            point: point,
            center: center,
            innerItemCount: items.count,
            outerItemCount: activeChildren.count,
            activeGroupIndex: activeGroupIndex,
            outerGeometry: activeGroupIndex.flatMap { items.indices.contains($0) ? items[$0].childGeometry : nil }
                ?? .equalCircle
        )
        mutateInteraction { $0.selectPointer(selection, childCounts: childCounts) }
    }

    func pointerEnded() {
        pointerState.reset()
        mutateInteraction { $0.clear() }
    }

    func highlightedCommandItem() -> RadialMenuItem? {
        guard let selectedItem, selectedItem.command != nil else { return nil }
        return selectedItem
    }

    func openGroupAfterDwell(_ index: Int) {
        mutateInteraction(disclosureReason: "dwell") {
            $0.dwellElapsed(for: index, childCounts: childCounts)
        }
    }

    private func scheduleGroupDwell(_ index: Int) {
        dwellWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.openGroupAfterDwell(index) }
        dwellWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(110), execute: work)
    }

    private func mutateInteraction(
        disclosureReason: String? = nil,
        _ mutation: (inout RadialMenuInteractionState) -> [RadialMenuInteractionEffect]
    ) {
        let priorGroupIndex = interaction.activeGroupIndex
        var updated = interaction
        let effects = mutation(&updated)
        interaction = updated
        if priorGroupIndex != updated.activeGroupIndex,
           let index = updated.activeGroupIndex,
           items.indices.contains(index) {
            groupDisclosed?(items[index], disclosureReason ?? "selection")
        }
        for effect in effects {
            switch effect {
            case let .scheduleGroupDwell(index):
                scheduleGroupDwell(index)
            case .cancelGroupDwell:
                dwellWorkItem?.cancel()
                dwellWorkItem = nil
            }
        }
    }
}

@MainActor
final class RadialMenuController: NSObject, NSWindowDelegate {
    static let panelSize = CGSize(width: 360, height: 360)

    private let engine: WorkspaceEngine
    private let dispatcher: WindowManagerCommandDispatcher
    private let diagnostics: DiagnosticLogger
    private let definitionProvider: () -> RadialWheelDefinition
    private let contextEnricher: @MainActor (RadialCommandContext) -> RadialCommandContext
    private var panel: RadialMenuPanel?
    private var presentation: RadialMenuPresentationModel?
    private var context: RadialCommandContext?
    private var session = RadialMenuSessionState()
    private var correlationID: String?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalKeyboardMonitor: Any?
    private var localKeyboardMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var isValidating = false
    var onDismissed: ((String) -> Void)?

    init(
        engine: WorkspaceEngine,
        dispatcher: WindowManagerCommandDispatcher,
        diagnostics: DiagnosticLogger = .disabled,
        definitionProvider: @escaping () -> RadialWheelDefinition = { .builtInDefault },
        contextEnricher: @escaping @MainActor (RadialCommandContext) -> RadialCommandContext = { $0 }
    ) {
        self.engine = engine
        self.dispatcher = dispatcher
        self.diagnostics = diagnostics
        self.definitionProvider = definitionProvider
        self.contextEnricher = contextEnricher
        super.init()
    }

    var isPresented: Bool { panel?.isVisible == true }

    func toggle() {
        if isPresented {
            dismiss(reason: "trigger-toggled")
            return
        }
        engine.radialCommandContext { [weak self] context in
            guard let self else { return }
            self.present(self.contextEnricher(context), activationStyle: .pressToToggle)
        }
    }

    func captureContext(completion: @escaping (RadialCommandContext) -> Void) {
        engine.radialCommandContext { [weak self] context in
            guard let self else { return }
            completion(self.contextEnricher(context))
        }
    }

    func hasRelevantActions(in context: RadialCommandContext) -> Bool {
        !resolvedMenu(for: context).items.isEmpty
    }

    func presentCaptured(
        _ captured: RadialCommandContext,
        triggerGeneration: UInt64,
        correlationID: String?,
        isStillCurrent: @escaping @MainActor () -> Bool,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        engine.radialCommandContext { [weak self] current in
            guard let self, isStillCurrent() else {
                completion(false)
                return
            }
            let current = self.contextEnricher(current)
            guard current.sessionValidationToken == captured.sessionValidationToken
            else {
                completion(false)
                return
            }
            self.present(
                captured,
                activationStyle: .holdToShow,
                correlationID: correlationID,
                triggerGeneration: triggerGeneration
            )
            completion(self.isPresented)
        }
    }

    func commitHighlightedOrDismiss() {
        guard let item = presentation?.highlightedCommandItem() else {
            dismiss(reason: "trigger-released-without-action")
            return
        }
        commit(item, useAlternate: NSEvent.modifierFlags.contains(.option))
    }

    func contextDidPossiblyChange() {
        guard isPresented, !isValidating else { return }
        isValidating = true
        engine.radialCommandContext { [weak self] current in
            guard let self else { return }
            self.isValidating = false
            guard let original = self.context else { return }
            let current = self.contextEnricher(current)
            if current.sessionValidationToken != original.sessionValidationToken {
                self.dismiss(reason: "context-changed")
            }
        }
    }

    func dismiss(reason: String) {
        guard let panel else { return }
        session.dismiss()
        diagnostics.log(
            category: "radial-menu",
            event: "dismissed",
            correlation: correlationID,
            fields: ["reason": reason]
        )
        removeEventMonitors()
        removeObservers()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.orderOut(nil)
        } else {
            NSAnimationContext.runAnimationGroup { animation in
                animation.duration = 0.08
                panel.animator().alphaValue = 0
            } completionHandler: {
                panel.orderOut(nil)
                panel.alphaValue = 1
            }
        }
        self.panel = nil
        presentation = nil
        context = nil
        correlationID = nil
        onDismissed?(reason)
    }

    private func present(
        _ context: RadialCommandContext,
        activationStyle: RadialMenuActivationStyle,
        correlationID suppliedCorrelationID: String? = nil,
        triggerGeneration: UInt64? = nil
    ) {
        let menu = resolvedMenu(for: context)
        guard !menu.items.isEmpty else {
            diagnostics.log(
                category: "radial-menu",
                event: "open-cancelled",
                fields: ["reason": "no-relevant-actions"]
            )
            onDismissed?("no-relevant-actions")
            return
        }

        let correlationID = suppliedCorrelationID ?? diagnostics.makeCorrelationID()
        let presentation = RadialMenuPresentationModel(menu: menu, activationStyle: activationStyle)
        presentation.commitItem = { [weak self] item, useAlternate in
            self?.commit(item, useAlternate: useAlternate)
        }
        presentation.cancel = { [weak self] in self?.dismiss(reason: "center-cancel") }
        presentation.groupDisclosed = { [weak self] item, reason in
            guard let self else { return }
            self.diagnostics.log(
                category: "radial-menu",
                event: "group-disclosed",
                correlation: correlationID,
                fields: [
                    "definition-item": item.definitionID,
                    "item": item.id,
                    "ring": "outer",
                    "child-count": String(item.children.count),
                    "reason": reason,
                ]
            )
        }
        let panel = RadialMenuPanel(
            contentRect: CGRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: RadialMenuView(model: presentation))

        let targetScreen = screen(for: context.displayIdentifier)
            ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
        guard let targetScreen else { return }
        let preferred = preferredCenter(for: context, screen: targetScreen)
        let center = RadialMenuGeometry.clampedCenter(
            preferred: preferred,
            panelSize: Self.panelSize,
            within: targetScreen.visibleFrame
        )
        panel.setFrameOrigin(CGPoint(
            x: center.x - Self.panelSize.width / 2,
            y: center.y - Self.panelSize.height / 2
        ))

        self.context = context
        self.presentation = presentation
        self.panel = panel
        self.session = RadialMenuSessionState()
        self.correlationID = correlationID
        diagnostics.log(
            category: "radial-menu",
            event: "opened",
            correlation: correlationID,
            fields: [
                "workspace": short(context.workspaceID.uuidString),
                "display": short(context.displayIdentifier),
                "display-mode": context.displayMode.rawValue,
                "layout": context.layout.rawValue,
                "focus-source": context.focusSource.rawValue,
                "window-state": context.focusedWindow?.layoutState.rawValue ?? "none",
                "action-count": String(menu.items.count),
                "definition-version": String(menu.definitionVersion),
                "definition-fallback": String(menu.usedFallbackDefinition),
                "omitted-definition-items": menu.omittedDefinitionItemIDs.joined(separator: ","),
                "activation-style": activationStyle.rawValue,
                "trigger-generation": triggerGeneration.map(String.init) ?? "none",
            ]
        )
        installEventMonitors()
        installObservers()
        panel.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0
        panel.orderFrontRegardless()
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { animation in
                animation.duration = 0.1
                panel.animator().alphaValue = 1
            }
        }
    }

    private func commit(_ item: RadialMenuItem, useAlternate: Bool = false) {
        let requestedCommand = useAlternate ? (item.alternateCommand ?? item.command) : item.command
        guard let requestedCommand, session.isPresented, !session.hasCommitted else { return }
        engine.radialCommandContext { [weak self] current in
            guard let self,
                  let original = self.context
            else {
                self?.dismiss(reason: "stale-target")
                return
            }
            let current = self.contextEnricher(current)
            guard current.sessionValidationToken == original.sessionValidationToken,
                  Self.contains(command: requestedCommand, in: self.resolvedMenu(for: current).items),
                  self.session.commit()
            else {
                self.dismiss(reason: "stale-target")
                return
            }
            let correlationID = self.correlationID ?? self.diagnostics.makeCorrelationID()
            self.diagnostics.log(
                category: "radial-menu",
                event: "action-committed",
                correlation: correlationID,
                fields: requestedCommand.diagnosticFields.merging([
                    "item": item.id,
                    "definition-item": item.definitionID,
                    "ring": self.presentation?.selectedRing?.rawValue ?? "unknown",
                    "alternate": String(useAlternate && item.alternateCommand != nil),
                    "workspace": self.short(current.workspaceID.uuidString),
                    "display": self.short(current.displayIdentifier),
                ]) { _, new in new }
            )
            self.removeEventMonitors()
            self.removeObservers()
            self.panel?.orderOut(nil)
            self.panel = nil
            self.presentation = nil
            self.context = nil
            self.correlationID = nil
            self.onDismissed?("action-committed")
            self.dispatcher.dispatch(requestedCommand, source: .radialMenu, correlationID: correlationID)
        }
    }

    private static func contains(command: WindowManagerCommand, in items: [RadialMenuItem]) -> Bool {
        items.contains {
            $0.command == command || $0.alternateCommand == command || contains(command: command, in: $0.children)
        }
    }

    private func handleKey(_ event: NSEvent) {
        guard let presentation else { return }
        switch event.keyCode {
        case 53: // Escape
            dismiss(reason: "escape")
        case 36, 49: // Return or Space
            presentation.activateSelection()
        case 48: // Tab enters a group; Shift-Tab returns to the inner ring.
            if event.modifierFlags.contains(.shift) {
                presentation.returnInward()
            } else {
                presentation.enterSelectedGroup()
            }
        case 51, 117: // Delete returns to the inner ring.
            presentation.returnInward()
        case 123, 125: // Left or Down cycles the current ring.
            presentation.moveSelection(-1)
        case 124, 126: // Right or Up
            presentation.moveSelection(1)
        default:
            break
        }
    }

    private func installEventMonitors() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            guard let self, let panel = self.panel else { return }
            if !panel.frame.contains(NSEvent.mouseLocation) {
                self.dismiss(reason: "outside-click")
            }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if !panel.frame.contains(NSEvent.mouseLocation) {
                self.dismiss(reason: "outside-click")
            }
            return event
        }
        globalKeyboardMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in self?.handleKey(event) }
        }
        localKeyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event)
            return event
        }
    }

    private func removeEventMonitors() {
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalKeyboardMonitor { NSEvent.removeMonitor(globalKeyboardMonitor) }
        if let localKeyboardMonitor { NSEvent.removeMonitor(localKeyboardMonitor) }
        globalMouseMonitor = nil
        localMouseMonitor = nil
        globalKeyboardMonitor = nil
        localKeyboardMonitor = nil
    }

    private func installObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.dismiss(reason: "display-topology-changed") }
        })
        observers.append(center.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.dismiss(reason: "app-deactivated") }
        })
    }

    private func removeObservers() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
    }

    private func preferredCenter(for context: RadialCommandContext, screen: NSScreen) -> CGPoint {
        let pointer = NSEvent.mouseLocation
        if screen.frame.contains(pointer) { return pointer }
        if let frame = context.focusedWindow?.frame, let mainScreen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
                == CGMainDisplayID()
        }) ?? NSScreen.main {
            return RadialMenuGeometry.appKitCenter(for: frame, mainScreenTop: mainScreen.frame.maxY)
        }
        return CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY)
    }

    private func screen(for displayIdentifier: String) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
            else { return false }
            return (CFUUIDCreateString(nil, uuid) as String) == displayIdentifier
        }
    }

    private func short(_ value: String) -> String {
        String(value.prefix(12))
    }

    private func resolvedMenu(for context: RadialCommandContext) -> RadialMenuModel {
        RadialCommandContextBuilder.build(from: context, definition: definitionProvider())
    }
}

private final class RadialMenuPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// One deliberately small visual vocabulary for the first native wheel style. Keeping these
/// values together lets the presentation evolve without coupling appearance choices to command,
/// geometry, or input behavior.
private enum RadialWheelAppearanceTokens {
    static let outerDiscDarkOpacity = 0.28
    static let outerDiscLightOpacity = 0.20
    static let outerBorderStandardOpacity = 0.13
    static let outerBorderIncreasedOpacity = 0.42
    static let innerBorderStandardOpacity = 0.20
    static let innerBorderIncreasedOpacity = 0.72
    static let innerWedgeOpacity = 0.045
    static let innerSelectionOpacity = 0.66
    static let wedgeBorderStandardOpacity = 0.10
    static let wedgeBorderIncreasedOpacity = 0.45
    static let outerPillOpacity = 0.09
    static let outerSelectionOpacity = 0.64
    static let outerPillBorderStandardOpacity = 0.13
    static let outerPillBorderIncreasedOpacity = 0.48
    static let darkShadowOpacity = 0.48
    static let lightShadowOpacity = 0.25
    static let transitionDuration = 0.12
}

struct RadialMenuView: View {
    @ObservedObject var model: RadialMenuPresentationModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            ZStack {
                if model.activeGroupIndex != nil {
                    Circle()
                        .fill(.black.opacity(
                            colorScheme == .dark
                                ? RadialWheelAppearanceTokens.outerDiscDarkOpacity
                                : RadialWheelAppearanceTokens.outerDiscLightOpacity
                        ))
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(
                            .white.opacity(
                                contrast == .increased
                                    ? RadialWheelAppearanceTokens.outerBorderIncreasedOpacity
                                    : RadialWheelAppearanceTokens.outerBorderStandardOpacity
                            ),
                            lineWidth: contrast == .increased ? 2 : 1
                        ))
                        .frame(
                            width: RadialMenuGeometry.outerRadius * 2,
                            height: RadialMenuGeometry.outerRadius * 2
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }

                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().stroke(
                        .white.opacity(
                            contrast == .increased
                                ? RadialWheelAppearanceTokens.innerBorderIncreasedOpacity
                                : RadialWheelAppearanceTokens.innerBorderStandardOpacity
                        ),
                        lineWidth: contrast == .increased ? 2 : 1
                    ))
                    .shadow(
                        color: .black.opacity(
                            colorScheme == .dark
                                ? RadialWheelAppearanceTokens.darkShadowOpacity
                                : RadialWheelAppearanceTokens.lightShadowOpacity
                        ),
                        radius: 24,
                        y: 10
                    )
                    .frame(
                        width: RadialMenuGeometry.innerOuterRadius * 2,
                        height: RadialMenuGeometry.innerOuterRadius * 2
                    )

                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                    RadialWedgeShape(
                        index: index,
                        count: model.items.count,
                        innerRadius: RadialMenuGeometry.centerDeadZone,
                        outerRadius: RadialMenuGeometry.innerOuterRadius - 5,
                        gapRadians: 0.012
                    )
                    .fill(
                        model.selectedInnerIndex == index
                            ? Color.accentColor.opacity(RadialWheelAppearanceTokens.innerSelectionOpacity)
                            : Color.primary.opacity(RadialWheelAppearanceTokens.innerWedgeOpacity)
                    )
                    .overlay {
                        RadialWedgeShape(
                            index: index,
                            count: model.items.count,
                            innerRadius: RadialMenuGeometry.centerDeadZone,
                            outerRadius: RadialMenuGeometry.innerOuterRadius - 5,
                            gapRadians: 0.012
                        )
                        .stroke(
                            Color.primary.opacity(
                                contrast == .increased
                                    ? RadialWheelAppearanceTokens.wedgeBorderIncreasedOpacity
                                    : RadialWheelAppearanceTokens.wedgeBorderStandardOpacity
                            ),
                            lineWidth: 1
                        )
                    }
                    .contentShape(RadialWedgeShape(
                        index: index,
                        count: model.items.count,
                        innerRadius: RadialMenuGeometry.centerDeadZone,
                        outerRadius: RadialMenuGeometry.innerOuterRadius - 5,
                        gapRadians: 0.01
                    ))
                    .onTapGesture {
                        model.activate(item, useAlternate: NSEvent.modifierFlags.contains(.option))
                    }

                    let itemCenter = RadialMenuGeometry.itemCenter(
                        index: index,
                        count: model.items.count,
                        center: center,
                        radius: RadialMenuGeometry.innerItemRadius
                    )
                    VStack(spacing: 3) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 17, weight: .semibold))
                        if item.isGroup {
                            Image(systemName: "arrowtriangle.right.fill")
                                .font(.system(size: 5, weight: .bold))
                                .foregroundStyle(model.selectedInnerIndex == index ? Color.white.opacity(0.9) : Color.secondary)
                        }
                    }
                    .foregroundStyle(model.selectedInnerIndex == index ? Color.white : Color.primary)
                    .frame(width: 54, height: 54)
                    .allowsHitTesting(false)
                    .accessibilityLabel(item.label)
                    .accessibilityHint(
                        item.isGroup
                            ? (item.command == nil
                                ? "Opens generated commands on the outer ring"
                                : "Click performs the primary command; moving outward opens generated commands")
                            : "Performs this command"
                    )
                    .position(itemCenter)
                }

                if let groupIndex = model.activeGroupIndex,
                   model.items.indices.contains(groupIndex) {
                    ForEach(Array(model.activeChildren.enumerated()), id: \.element.id) { childIndex, child in
                        RadialWedgeShape(
                            index: childIndex,
                            count: model.activeChildren.count,
                            innerRadius: RadialMenuGeometry.outerInnerRadius,
                            outerRadius: RadialMenuGeometry.outerRadius - 5,
                            gapRadians: 0.007
                        )
                        .fill(
                            model.selectedOuterIndex == childIndex
                                ? Color.accentColor.opacity(RadialWheelAppearanceTokens.outerSelectionOpacity)
                                : Color.primary.opacity(child.isCurrent ? 0.13 : 0.035)
                        )
                        .overlay {
                            RadialWedgeShape(
                                index: childIndex,
                                count: model.activeChildren.count,
                                innerRadius: RadialMenuGeometry.outerInnerRadius,
                                outerRadius: RadialMenuGeometry.outerRadius - 5,
                                gapRadians: 0.007
                            )
                            .stroke(
                                Color.primary.opacity(
                                    contrast == .increased
                                        ? RadialWheelAppearanceTokens.outerPillBorderIncreasedOpacity
                                        : RadialWheelAppearanceTokens.outerPillBorderStandardOpacity
                                ),
                                lineWidth: contrast == .increased ? 2 : 1
                            )
                        }
                        .contentShape(RadialWedgeShape(
                            index: childIndex,
                            count: model.activeChildren.count,
                            innerRadius: RadialMenuGeometry.outerInnerRadius,
                            outerRadius: RadialMenuGeometry.outerRadius - 5,
                            gapRadians: 0
                        ))
                        .onTapGesture {
                            model.activate(child, useAlternate: NSEvent.modifierFlags.contains(.option))
                        }

                        let childCenter = RadialMenuGeometry.outerItemCenter(
                            index: childIndex,
                            parentIndex: groupIndex,
                            parentCount: model.items.count,
                            childCount: model.activeChildren.count,
                            center: center,
                            geometry: model.items[groupIndex].childGeometry
                        )
                        VStack(spacing: 3) {
                            Image(systemName: child.systemImage)
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .foregroundStyle(model.selectedOuterIndex == childIndex ? Color.white : Color.primary)
                        .frame(width: 82, height: 54)
                        .allowsHitTesting(false)
                        .accessibilityLabel(child.label)
                        .accessibilityHint(child.alternateCommand == nil
                            ? "Performs this outer-ring command"
                            : "Performs this command; hold Option for Move and Follow")
                        .position(childCenter)
                    }
                }

                Circle()
                    .fill(.black.opacity(colorScheme == .dark ? 0.34 : 0.24))
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(
                        .white.opacity(contrast == .increased ? 0.72 : 0.18),
                        lineWidth: contrast == .increased ? 2 : 1
                    ))
                    .frame(
                        width: RadialMenuGeometry.centerDeadZone * 1.88,
                        height: RadialMenuGeometry.centerDeadZone * 1.88
                    )

                Button {
                    model.cancel?()
                } label: {
                    Group {
                        if let preview = model.selectedItem?.placementPreview {
                            TiledPlacementMiniPreview(preview: preview)
                        } else {
                            VStack(spacing: 3) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Text(model.selectedItem?.label ?? model.menu.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                Text(model.selectedItem == nil ? model.menu.subtitle : "")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                if model.selectedItem == nil, let note = model.menu.stateNote {
                                    Text(note)
                                        .font(.system(size: 8, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                }
                            }
                        }
                    }
                    .frame(
                        width: RadialMenuGeometry.centerDeadZone * 1.75,
                        height: RadialMenuGeometry.centerDeadZone * 1.75
                    )
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel command wheel")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case let .active(location):
                    model.pointerMoved(to: location, center: center)
                case .ended:
                    model.pointerEnded()
                }
            }
            .animation(
                reduceMotion ? nil : .easeOut(duration: RadialWheelAppearanceTokens.transitionDuration),
                value: model.activeGroupIndex
            )
        }
        .frame(width: RadialMenuController.panelSize.width, height: RadialMenuController.panelSize.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Contextual command wheel")
    }
}

private struct TiledPlacementMiniPreview: View {
    let preview: TiledPlacementPreview

    private var orderedFrames: [(WindowKey, WindowFrame)] {
        preview.frames.sorted {
            if $0.key.processIdentifier != $1.key.processIdentifier {
                return $0.key.processIdentifier < $1.key.processIdentifier
            }
            return $0.key.windowIdentifier < $1.key.windowIdentifier
        }
    }

    private var bounds: CGRect {
        orderedFrames.reduce(CGRect.null) { partial, entry in
            partial.union(CGRect(origin: entry.1.position, size: entry.1.size))
        }
    }

    var body: some View {
        VStack(spacing: 3) {
            GeometryReader { proxy in
                let source = bounds.isNull ? CGRect(x: 0, y: 0, width: 1, height: 1) : bounds
                ForEach(Array(orderedFrames.enumerated()), id: \.offset) { _, entry in
                    let rect = CGRect(origin: entry.1.position, size: entry.1.size)
                    let x = (rect.minX - source.minX) / max(1, source.width) * proxy.size.width
                    let y = (rect.minY - source.minY) / max(1, source.height) * proxy.size.height
                    let width = rect.width / max(1, source.width) * proxy.size.width
                    let height = rect.height / max(1, source.height) * proxy.size.height
                    RoundedRectangle(cornerRadius: 2)
                        .fill(entry.0 == preview.focusedWindow ? Color.accentColor : Color.primary.opacity(0.18))
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(.white.opacity(0.45), lineWidth: 0.7))
                        .frame(width: max(3, width - 2), height: max(3, height - 2))
                        .position(x: x + width / 2, y: y + height / 2)
                }
            }
            .frame(width: 54, height: 38)
            Text(preview.placement.title)
                .font(.system(size: 8, weight: .semibold))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview \(preview.placement.title) tiled placement")
    }
}

private struct RadialWedgeShape: Shape {
    let index: Int
    let count: Int
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let gapRadians: CGFloat

    func path(in rect: CGRect) -> Path {
        guard count > 0 else { return Path() }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let span = CGFloat.pi * 2 / CGFloat(count)
        let middle = CGFloat(index) * span - .pi / 2
        let start = middle - span / 2 + gapRadians
        let end = middle + span / 2 - gapRadians
        var path = Path()
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: .radians(start),
            endAngle: .radians(end),
            clockwise: false
        )
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: .radians(end),
            endAngle: .radians(start),
            clockwise: true
        )
        path.closeSubpath()
        return path
    }
}
