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
        if effects.isEmpty, menuController.hasActivePresentationRequest {
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
    func setNativeGlobeFilteringEnabled(_ enabled: Bool)
}

/// Thread-safe state read by the dedicated active-filter callback. Ordinary keys fast-path without
/// taking this lock; only the synthetic native Globe key consults it.
private final class GlobeFnNativeFilterState: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = false

    func setEnabled(_ enabled: Bool) {
        lock.lock()
        self.enabled = enabled
        lock.unlock()
    }

    func shouldSuppress(keyCode: UInt16) -> Bool {
        guard keyCode == GlobeFnEventNormalizer.nativeGlobeActionKeyCode else { return false }
        lock.lock()
        let enabled = self.enabled
        lock.unlock()
        return GlobeFnNativeEventFilterPolicy.shouldSuppress(
            keyCode: keyCode,
            nativeGlobeFilteringEnabled: enabled
        )
    }
}

/// Owns one event-tap source on a dedicated user-interactive run loop. Keeping the active filter
/// independent of AppKit's main loop means UI, Accessibility, layout, and diagnostic work cannot
/// hold ordinary input delivery behind the filter.
private final class GlobeFnActiveTapRunLoopHost: @unchecked Sendable {
    private let eventTap: CFMachPort
    private let retainedContext: AnyObject
    private let lock = NSLock()
    private var runLoop: CFRunLoop?
    private var runLoopSource: CFRunLoopSource?
    private var thread: Thread?
    private var started = false

    init(eventTap: CFMachPort, retainedContext: AnyObject) {
        self.eventTap = eventTap
        self.retainedContext = retainedContext
    }

    func start() -> Bool {
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            let currentRunLoop = CFRunLoopGetCurrent()
            guard let source = CFMachPortCreateRunLoopSource(
                kCFAllocatorDefault,
                eventTap,
                0
            ) else {
                ready.signal()
                return
            }

            lock.lock()
            runLoop = currentRunLoop
            runLoopSource = source
            lock.unlock()

            CFRunLoopAddSource(currentRunLoop, source, .defaultMode)
            CGEvent.tapEnable(tap: eventTap, enable: true)

            lock.lock()
            started = CGEvent.tapIsEnabled(tap: eventTap)
            let shouldRun = started
            lock.unlock()
            ready.signal()

            if shouldRun { CFRunLoopRun() }

            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFRunLoopRemoveSource(currentRunLoop, source, .defaultMode)
            CFMachPortInvalidate(eventTap)
            lock.lock()
            runLoopSource = nil
            runLoop = nil
            self.thread = nil
            started = false
            lock.unlock()
        }
        thread.name = "WindowRanger Globe/Fn Filter"
        thread.qualityOfService = .userInteractive
        lock.lock()
        self.thread = thread
        lock.unlock()
        thread.start()

        guard ready.wait(timeout: .now() + 1) == .success else {
            stop()
            return false
        }
        lock.lock()
        let result = started
        lock.unlock()
        return result
    }

    func stop() {
        lock.lock()
        let runLoop = self.runLoop
        let source = runLoopSource
        lock.unlock()
        guard let runLoop else {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            return
        }

        let eventTap = self.eventTap
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            if let source {
                CFRunLoopRemoveSource(runLoop, source, .defaultMode)
            }
            CFMachPortInvalidate(eventTap)
            CFRunLoopStop(runLoop)
        }
        CFRunLoopWakeUp(runLoop)
    }
}

private final class GlobeFnActiveFilterContext: @unchecked Sendable {
    let filterState: GlobeFnNativeFilterState
    let interruptionHandler: @Sendable (GlobeFnEventMonitorInterruption) -> Void

    init(
        filterState: GlobeFnNativeFilterState,
        interruptionHandler: @escaping @Sendable (GlobeFnEventMonitorInterruption) -> Void
    ) {
        self.filterState = filterState
        self.interruptionHandler = interruptionHandler
    }
}

/// A passive tap observes Fn state and competing input without participating in delivery. A second
/// active tap sees key events on its own run loop and fast-passes every key except the synthetic
/// native Globe action while an accepted hold has explicitly armed suppression.
@MainActor
final class CGGlobeFnEventMonitor: GlobeFnEventMonitoring {
    typealias EventHandler = @MainActor (GlobeFnObservedEvent) -> Bool
    typealias InterruptionHandler = @MainActor (GlobeFnEventMonitorInterruption) -> Void

    private let eventHandler: EventHandler
    private let interruptionHandler: InterruptionHandler
    private let nativeFilterState = GlobeFnNativeFilterState()
    private var observationTap: CFMachPort?
    private var observationRunLoopSource: CFRunLoopSource?
    private var activeTapHost: GlobeFnActiveTapRunLoopHost?
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
        stop()
        guard AXIsProcessTrusted() else { return false }

        let passivelyObservedTypes: [CGEventType] = [
            .flagsChanged,
            .keyDown,
            .keyUp,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            Self.systemDefinedEventType,
        ]
        let observationMask = passivelyObservedTypes.reduce(CGEventMask(0)) {
            $0 | (CGEventMask(1) << $1.rawValue)
        }
        let observationCallback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<CGGlobeFnEventMonitor>
                .fromOpaque(userInfo)
                .takeUnretainedValue()
            MainActor.assumeIsolated {
                monitor.observe(type: type, event: event)
            }
            return Unmanaged.passUnretained(event)
        }
        guard let observationTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: observationMask,
            callback: observationCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let observationSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            observationTap,
            0
        )
        else { return false }

        let filterContext = GlobeFnActiveFilterContext(
            filterState: nativeFilterState,
            interruptionHandler: { [weak self] interruption in
                Task { @MainActor [weak self] in
                    self?.interruptionHandler(interruption)
                }
            }
        )
        let activeCallback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let context = Unmanaged<GlobeFnActiveFilterContext>
                .fromOpaque(userInfo)
                .takeUnretainedValue()
            switch type {
            case .tapDisabledByTimeout:
                context.interruptionHandler(.timedOut)
                return Unmanaged.passUnretained(event)
            case .tapDisabledByUserInput:
                context.interruptionHandler(.disabledByUserInput)
                return Unmanaged.passUnretained(event)
            case .keyDown, .keyUp:
                let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                return context.filterState.shouldSuppress(keyCode: keyCode)
                    ? nil
                    : Unmanaged.passUnretained(event)
            default:
                return Unmanaged.passUnretained(event)
            }
        }
        let keyMask = [CGEventType.keyDown, .keyUp].reduce(CGEventMask(0)) {
            $0 | (CGEventMask(1) << $1.rawValue)
        }
        guard let activeTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: keyMask,
            callback: activeCallback,
            userInfo: Unmanaged.passUnretained(filterContext).toOpaque()
        ) else {
            CFMachPortInvalidate(observationTap)
            return false
        }
        let activeHost = GlobeFnActiveTapRunLoopHost(
            eventTap: activeTap,
            retainedContext: filterContext
        )
        guard activeHost.start() else {
            activeHost.stop()
            CFMachPortInvalidate(observationTap)
            return false
        }

        self.observationTap = observationTap
        observationRunLoopSource = observationSource
        self.activeTapHost = activeHost
        CFRunLoopAddSource(CFRunLoopGetMain(), observationSource, .commonModes)
        CGEvent.tapEnable(tap: observationTap, enable: true)
        let observationEnabled = CGEvent.tapIsEnabled(tap: observationTap)
        if !observationEnabled { stop() }
        return observationEnabled
    }

    func stop() {
        nativeFilterState.setEnabled(false)
        if let source = observationRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let observationTap {
            CGEvent.tapEnable(tap: observationTap, enable: false)
            CFMachPortInvalidate(observationTap)
        }
        activeTapHost?.stop()
        observationRunLoopSource = nil
        observationTap = nil
        activeTapHost = nil
    }

    func setNativeGlobeFilteringEnabled(_ enabled: Bool) {
        nativeFilterState.setEnabled(enabled)
    }

    private func observe(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout:
            Task { @MainActor [weak self] in self?.interruptionHandler(.timedOut) }
        case .tapDisabledByUserInput:
            Task { @MainActor [weak self] in self?.interruptionHandler(.disabledByUserInput) }
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
            _ = eventHandler(.flagsChanged(
                functionDown: flags.contains(.maskSecondaryFn),
                otherModifiersDown: !flags.intersection(otherModifiers).isEmpty
            ))
        case .keyDown, .keyUp:
            _ = eventHandler(.keyChanged(
                isDown: type == .keyDown,
                keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            ))
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            _ = eventHandler(.mouseButtonDown)
        case let eventType where eventType == Self.systemDefinedEventType:
            _ = eventHandler(.systemDefined)
        default:
            break
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
        guard monitor != nil else { return }
        cancel(reason: interruption.rawValue)
        monitor?.stop()
        monitor = nil
        lastObservedFunctionState = nil
        runtimeIssueChanged?(
            "Globe/Fn monitoring stopped after macOS reported an unresponsive input filter. Toggle the option off and on to retry."
        )
        diagnostics.log(
            category: "globe-fn-trigger",
            event: "monitor-stopped-fail-open",
            fields: ["reason": interruption.rawValue]
        )
    }

    @discardableResult
    private func apply(_ effects: [GlobeFnGestureEffect]) -> Bool {
        if effects.contains(where: {
            if case .activateHold = $0 { return true }
            return false
        }) {
            monitor?.setNativeGlobeFilteringEnabled(true)
        }
        defer {
            let explicitlyCancelled = effects.contains(where: {
                switch $0 {
                case .cancelHold, .cancelSuppressionExpiry:
                    return true
                default:
                    return false
                }
            })
            if explicitlyCancelled || state.phaseName == "idle" {
                monitor?.setNativeGlobeFilteringEnabled(false)
            }
        }
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
            case let .cancelThreshold(reason):
                thresholdTask?.cancel()
                thresholdTask = nil
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
                radialTrigger.handle(
                    .released,
                    style: .holdToShow,
                    holdDelay: holdDelay
                )
            case let .cancelHold(reason):
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
    private(set) var pendingInnerIndex: Int?

    mutating func selectPointer(
        _ selection: RadialMenuGeometry.Selection?,
        childCounts: [Int]
    ) -> [RadialMenuInteractionEffect] {
        switch selection?.ring {
        case .inner:
            guard let index = selection?.index, childCounts.indices.contains(index) else { return [] }
            if let activeGroupIndex, index != activeGroupIndex {
                pendingInnerIndex = index
                selectedInnerIndex = activeGroupIndex
                selectedOuterIndex = nil
                return [.scheduleGroupDwell(index)]
            }
            pendingInnerIndex = nil
            selectedInnerIndex = index
            selectedOuterIndex = nil
            if childCounts[index] > 0 {
                guard activeGroupIndex != index else { return [.cancelGroupDwell] }
                pendingInnerIndex = index
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
            pendingInnerIndex = nil
            selectedInnerIndex = group
            selectedOuterIndex = index
            return [.cancelGroupDwell]
        case nil:
            pendingInnerIndex = nil
            selectedInnerIndex = nil
            selectedOuterIndex = nil
            return [.cancelGroupDwell]
        }
    }

    mutating func discloseSelectedGroupImmediately(childCounts: [Int]) -> [RadialMenuInteractionEffect] {
        guard let index = selectedInnerIndex,
              childCounts.indices.contains(index),
              childCounts[index] > 0
        else { return [] }
        pendingInnerIndex = nil
        activeGroupIndex = index
        selectedOuterIndex = nil
        return [.cancelGroupDwell]
    }

    mutating func dwellElapsed(for index: Int, childCounts: [Int]) -> [RadialMenuInteractionEffect] {
        guard pendingInnerIndex == index,
              childCounts.indices.contains(index)
        else { return [] }
        pendingInnerIndex = nil
        selectedInnerIndex = index
        activeGroupIndex = childCounts[index] > 0 ? index : nil
        selectedOuterIndex = nil
        return [.cancelGroupDwell]
    }

    mutating func moveSelection(_ offset: Int, childCounts: [Int]) -> [RadialMenuInteractionEffect] {
        pendingInnerIndex = nil
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
        pendingInnerIndex = nil
        activeGroupIndex = index
        selectedOuterIndex = 0
        return [.cancelGroupDwell]
    }

    mutating func returnInward() -> [RadialMenuInteractionEffect] {
        guard let activeGroupIndex else { return [] }
        pendingInnerIndex = nil
        selectedInnerIndex = activeGroupIndex
        selectedOuterIndex = nil
        self.activeGroupIndex = nil
        return [.cancelGroupDwell]
    }

    mutating func clear() -> [RadialMenuInteractionEffect] {
        pendingInnerIndex = nil
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
    private static let initialGroupDisclosureDelay = 110
    private static let openGroupSwitchDelay = 350
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
        guard interaction.pendingInnerIndex == nil else { return nil }
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

    var selectedItemDetail: String? {
        guard let selectedItem else { return nil }
        if requiresExplicitActivation(selectedItem) {
            return "Click or press Return to confirm"
        }
        return selectedItem.detail
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
           activeGroupIndex == nil,
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
        guard let item = highlightedCommandItemBeforeReleaseProtection(),
              !requiresExplicitActivation(item)
        else { return nil }
        return item
    }

    var highlightedItemRequiresExplicitActivation: Bool {
        highlightedCommandItemBeforeReleaseProtection().map(requiresExplicitActivation) == true
    }

    func accessibilityHint(for item: RadialMenuItem) -> String {
        if requiresExplicitActivation(item) {
            return "Click or press Return to confirm. Releasing Globe or Fn will not run this command."
        }
        if item.isGroup {
            return item.command == nil
                ? "Opens generated commands on the outer ring"
                : "Click performs the primary command; moving outward opens generated commands"
        }
        return "Performs this command"
    }

    private func highlightedCommandItemBeforeReleaseProtection() -> RadialMenuItem? {
        // A group remains latched while the pointer crosses another inner wedge so users can
        // travel naturally to any outer child. Releasing on a direct command is unambiguous,
        // though, and should commit that wedge rather than dismiss as if nothing were selected.
        if let pendingInnerIndex = interaction.pendingInnerIndex,
           items.indices.contains(pendingInnerIndex) {
            let pending = items[pendingInnerIndex]
            if pending.children.isEmpty, pending.command != nil {
                return pending
            }
        }
        guard let selectedItem, selectedItem.command != nil else { return nil }
        return selectedItem
    }

    private func requiresExplicitActivation(_ item: RadialMenuItem) -> Bool {
        activationStyle == .holdToShow && item.command == .resetAllWindows
    }

    func openGroupAfterDwell(_ index: Int) {
        mutateInteraction(disclosureReason: "dwell") {
            $0.dwellElapsed(for: index, childCounts: childCounts)
        }
    }

    private func scheduleGroupDwell(_ index: Int, delayMilliseconds: Int) {
        dwellWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.openGroupAfterDwell(index) }
        dwellWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delayMilliseconds), execute: work)
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
                scheduleGroupDwell(
                    index,
                    delayMilliseconds: priorGroupIndex == nil
                        ? Self.initialGroupDisclosureDelay
                        : Self.openGroupSwitchDelay
                )
            case .cancelGroupDwell:
                dwellWorkItem?.cancel()
                dwellWorkItem = nil
            }
        }
    }
}

@MainActor
final class RadialMenuController: NSObject, NSWindowDelegate {
    static let panelSize = CGSize(width: 450, height: 450)

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
    private var toggleRequestGeneration: UInt64 = 0
    private var pendingToggleRequest: UInt64?
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
    var hasActivePresentationRequest: Bool { isPresented || pendingToggleRequest != nil }

    func toggle() {
        if hasActivePresentationRequest {
            dismiss(reason: "trigger-toggled")
            return
        }
        toggleRequestGeneration &+= 1
        let request = toggleRequestGeneration
        pendingToggleRequest = request
        engine.radialCommandContext(
            focusingWindowAt: CGEvent(source: nil)?.location
        ) { [weak self] context in
            guard let self else { return }
            defer { self.engine.radialPointerFocusPresentationFinished() }
            guard self.pendingToggleRequest == request else { return }
            self.pendingToggleRequest = nil
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
            let pointerLocation = CGEvent(source: nil)?.location
            self.engine.radialCommandContext(
                focusingWindowAt: pointerLocation
            ) { [weak self] targeted in
                guard let self else {
                    completion(false)
                    return
                }
                defer { self.engine.radialPointerFocusPresentationFinished() }
                guard isStillCurrent() else {
                    completion(false)
                    return
                }
                let targeted = self.contextEnricher(targeted)
                guard self.hasRelevantActions(in: targeted) else {
                    completion(false)
                    return
                }
                self.present(
                    targeted,
                    activationStyle: .holdToShow,
                    correlationID: correlationID,
                    triggerGeneration: triggerGeneration
                )
                completion(self.isPresented)
            }
        }
    }

    func commitHighlightedOrDismiss() {
        if presentation?.highlightedItemRequiresExplicitActivation == true {
            dismiss(reason: "trigger-released-requires-explicit-activation")
            return
        }
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
        pendingToggleRequest = nil
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
                    let itemAngle = RadialMenuGeometry.itemAngle(index: index, count: model.items.count)
                    ZStack {
                        RadialMenuSymbol(systemImage: item.systemImage, size: 20, weight: .semibold)
                            .frame(width: 30, height: 30)
                        if item.isGroup {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(model.selectedInnerIndex == index ? Color.white.opacity(0.9) : Color.secondary)
                                .rotationEffect(.radians(Double(itemAngle)))
                                .offset(
                                    x: cos(itemAngle) * 22,
                                    y: sin(itemAngle) * 22
                                )
                        }
                    }
                    .foregroundStyle(model.selectedInnerIndex == index ? Color.white : Color.primary)
                    .frame(width: 60, height: 60)
                    .allowsHitTesting(false)
                    .accessibilityLabel(item.label)
                    .accessibilityHint(model.accessibilityHint(for: item))
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
                        ZStack(alignment: .topTrailing) {
                            RadialMenuSymbol(systemImage: child.systemImage, size: 23, weight: .semibold)
                                .frame(width: 34, height: 34)
                            if child.isCurrent {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .offset(x: 6, y: -4)
                            }
                        }
                        .foregroundStyle(model.selectedOuterIndex == childIndex ? Color.white : Color.primary)
                        .frame(width: 44, height: 44)
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
                        width: RadialMenuGeometry.centerDeadZone * 1.9,
                        height: RadialMenuGeometry.centerDeadZone * 1.9
                    )

                Group {
                    if let preview = model.selectedItem?.freeformPlacementPreview {
                        FreeformPlacementMiniPreview(preview: preview)
                    } else if let preview = model.selectedItem?.placementPreview {
                        TiledPlacementMiniPreview(preview: preview)
                    } else if let selectedItem = model.selectedItem {
                        VStack(spacing: 4) {
                            RadialMenuSymbol(systemImage: selectedItem.systemImage, size: 16, weight: .semibold)
                                .foregroundStyle(.secondary)
                            Text(selectedItem.label)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(3)
                                .minimumScaleFactor(0.72)
                                .multilineTextAlignment(.center)
                            if let detail = model.selectedItemDetail {
                                Text(detail)
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.75)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    } else {
                        VStack(spacing: 4) {
                            Text(model.menu.title)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(2)
                                .minimumScaleFactor(0.72)
                                .multilineTextAlignment(.center)
                            Text(model.menu.subtitle)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.7)
                                .multilineTextAlignment(.center)
                            if let note = model.menu.stateNote {
                                Text(note)
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.7)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    }
                }
                .frame(
                    width: RadialMenuGeometry.centerDeadZone * 1.68,
                    height: RadialMenuGeometry.centerDeadZone * 1.68
                )
                .contentShape(Circle())
                .onTapGesture { model.cancel?() }
                .accessibilityLabel("Cancel command wheel")
                .accessibilityAddTraits(.isButton)
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

/// Keeps the wheel on one monochrome SF Symbols vocabulary. The selected action-first command
/// glyphs are small compositions of system symbols so their distinct meaning survives at wheel,
/// centre, and Settings sizes without shipping a second icon asset set.
struct RadialMenuSymbol: View {
    let systemImage: String
    let size: CGFloat
    let weight: Font.Weight

    @ViewBuilder
    var body: some View {
        switch systemImage {
        case RadialCommandCatalogue.SymbolName.moveToSpace:
            RadialMoveToSpaceSymbol(size: size, weight: weight)
        case RadialCommandCatalogue.SymbolName.placeWindow:
            RadialPlaceWindowSymbol(size: size, weight: weight)
        case RadialCommandCatalogue.SymbolName.goToSpace:
            RadialGoToSpaceSymbol(size: size, weight: weight)
        case RadialCommandCatalogue.SymbolName.resetWindowsInSpace:
            RadialResetWindowsInSpaceSymbol(size: size, weight: weight)
        case "arrow.right", "arrow.left":
            Image(systemName: systemImage)
                .font(.system(size: size * 1.28, weight: .regular))
        case WorkspaceLayout.accordion.systemImage:
            AccordionLayoutSymbol(size: size, weight: weight)
        default:
            Image(systemName: systemImage)
                .font(.system(size: size, weight: weight))
        }
    }
}

/// A framed window plus an outward transfer arrow distinguishes moving the focused window from
/// navigating the current workspace. Every layer is an SF Symbol and shares the inherited colour.
private struct RadialMoveToSpaceSymbol: View {
    let size: CGFloat
    let weight: Font.Weight

    var body: some View {
        ZStack {
            Image(systemName: "viewfinder")
                .font(.system(size: size * 1.28, weight: weight))
                .mask(alignment: .top) {
                    Rectangle()
                        .frame(height: size * 0.4)
                }
                .offset(y: -size * 0.14)
            Image(systemName: "minus")
                .font(.system(size: size * 0.48, weight: .bold))
                .offset(y: -size * 0.43)
            RadialWindowGlyph(size: size, weight: weight)
                .offset(x: -size * 0.08, y: size * 0.12)
            Image(systemName: "arrow.up.right")
                .font(.system(size: size * 0.52, weight: .semibold))
                .offset(x: size * 0.4, y: -size * 0.25)
        }
        .frame(width: size * 1.28, height: size * 1.18)
    }
}

/// The same focused-window frame without a transfer arrow reads as placing or resizing the
/// current window, rather than moving between workspaces.
private struct RadialPlaceWindowSymbol: View {
    let size: CGFloat
    let weight: Font.Weight

    var body: some View {
        ZStack {
            Image(systemName: "viewfinder")
                .font(.system(size: size * 1.22, weight: weight))
            Image(systemName: "rectangle")
                .font(.system(size: size * 0.58, weight: weight))
        }
        .frame(width: size * 1.18, height: size * 1.18)
    }
}

/// Workspace tiles plus a small navigation target separate Go to Space from Place Window's
/// single framed window and Move to Space's transfer arrow.
private struct RadialGoToSpaceSymbol: View {
    let size: CGFloat
    let weight: Font.Weight

    var body: some View {
        ZStack {
            Image(systemName: "square")
                .font(.system(size: size * 0.43, weight: .bold))
                .offset(x: -size * 0.25, y: -size * 0.25)
            Image(systemName: "square")
                .font(.system(size: size * 0.43, weight: .bold))
                .offset(x: size * 0.25, y: -size * 0.25)
            Image(systemName: "square")
                .font(.system(size: size * 0.43, weight: .bold))
                .offset(x: -size * 0.25, y: size * 0.25)
            Image(systemName: "scope")
                .font(.system(size: size * 0.68, weight: .bold))
                .offset(x: size * 0.29, y: size * 0.29)
        }
        .frame(width: size * 1.22, height: size * 1.18)
    }
}

/// The current-space reset combines a single window with the selected clockwise restore loop;
/// Reset All retains the separate two-arrow circular symbol from the surrounding catalogue.
private struct RadialResetWindowsInSpaceSymbol: View {
    let size: CGFloat
    let weight: Font.Weight

    var body: some View {
        ZStack {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: size * 1.48, weight: .regular))
            RadialWindowGlyph(size: size * 0.7, weight: weight)
                .offset(x: -size * 0.06, y: size * 0.08)
        }
        .frame(width: size * 1.12, height: size * 1.12)
    }
}

/// A compact title-bar window assembled from native SF Symbols. Keeping the title bar explicit
/// avoids the three-dot browser treatment of `macwindow` and matches the selected icon grammar.
private struct RadialWindowGlyph: View {
    let size: CGFloat
    let weight: Font.Weight

    var body: some View {
        ZStack {
            Image(systemName: "rectangle")
                .font(.system(size: size, weight: weight))
            Image(systemName: "minus")
                .font(.system(size: size * 0.62, weight: .bold))
                .offset(y: -size * 0.16)
        }
    }
}

/// Uses the real rounded-window SF Symbol with two square-ended native strokes. The dividers are
/// positioned independently so the central Accordion pane is genuinely wider, and their butt caps
/// meet the inside edges cleanly rather than appearing short at wheel size.
private struct AccordionLayoutSymbol: View {
    let size: CGFloat
    let weight: Font.Weight

    var body: some View {
        ZStack {
            Image(systemName: "rectangle")
                .font(.system(size: size, weight: weight))
            AccordionDivider()
                .stroke(
                    style: StrokeStyle(
                        lineWidth: size * 0.095,
                        lineCap: .butt
                    )
                )
                .frame(width: size * 0.095, height: size * 0.69)
                .offset(x: -size * 0.23)
            AccordionDivider()
                .stroke(
                    style: StrokeStyle(
                        lineWidth: size * 0.095,
                        lineCap: .butt
                    )
                )
                .frame(width: size * 0.095, height: size * 0.69)
                .offset(x: size * 0.23)
        }
        .frame(width: size * 1.22, height: size)
    }
}

private struct AccordionDivider: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let x = rect.midX
        path.move(to: CGPoint(x: x, y: rect.minY))
        path.addLine(to: CGPoint(x: x, y: rect.maxY))
        return path
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

private struct FreeformPlacementMiniPreview: View {
    let preview: FreeformPlacementPreview

    var body: some View {
        VStack(spacing: 3) {
            GeometryReader { proxy in
                let source = preview.displayBounds
                let target = CGRect(origin: preview.targetFrame.position, size: preview.targetFrame.size)
                let x = (target.minX - source.minX) / max(1, source.width) * proxy.size.width
                let y = (target.minY - source.minY) / max(1, source.height) * proxy.size.height
                let width = target.width / max(1, source.width) * proxy.size.width
                let height = target.height / max(1, source.height) * proxy.size.height
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.primary.opacity(0.35), lineWidth: 1)
                    .overlay(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor)
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(.white.opacity(0.55), lineWidth: 0.7))
                            .frame(width: max(3, width - 2), height: max(3, height - 2))
                            .offset(x: x + 1, y: y + 1)
                    }
            }
            .frame(width: 54, height: 38)
            Text(preview.placement.title)
                .font(.system(size: 8, weight: .semibold))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview \(preview.placement.title) Freeform placement")
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
