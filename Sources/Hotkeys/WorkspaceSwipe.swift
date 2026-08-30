import AppKit
import ApplicationServices
import CoreGraphics

enum WorkspaceSwipeFingerCount: Int, CaseIterable, Identifiable, Sendable {
    case three = 3
    case four = 4

    var id: Int { rawValue }
    var title: String { "\(rawValue) Fingers" }
}

enum WorkspaceSwipeDirection: String, Equatable, Sendable {
    case previous
    case next

    var workspaceOffset: Int {
        switch self {
        case .previous: -1
        case .next: 1
        }
    }
}

struct WorkspaceSwipeTouch: Equatable, Sendable {
    let identity: String
    let normalizedPosition: CGPoint
}

enum WorkspaceSwipeInput: Equatable, Sendable {
    case touches([WorkspaceSwipeTouch])
    case ended
    case cancel
}

enum WorkspaceSwipeEffect: Equatable, Sendable {
    case switchWorkspace(WorkspaceSwipeDirection)
}

/// Pure gesture admission. The runtime adapter supplies only non-resting, active touches, while
/// this state machine owns finger-count continuity, horizontal intent, the movement threshold, and
/// the one-command-per-complete-gesture invariant.
struct WorkspaceSwipeStateMachine: Sendable {
    private enum Phase: Sendable {
        case idle
        case tracking
        case latched
    }

    static let movementThreshold: CGFloat = 0.05
    private static let axisDominance: CGFloat = 1.2

    private(set) var fingerCount: WorkspaceSwipeFingerCount
    private var phase: Phase = .idle
    private var previousPositions: [String: CGPoint] = [:]
    private var accumulatedX: CGFloat = 0
    private var accumulatedY: CGFloat = 0

    init(fingerCount: WorkspaceSwipeFingerCount = .three) {
        self.fingerCount = fingerCount
    }

    mutating func updateFingerCount(_ fingerCount: WorkspaceSwipeFingerCount) {
        guard self.fingerCount != fingerCount else { return }
        self.fingerCount = fingerCount
        reset()
    }

    mutating func handle(_ input: WorkspaceSwipeInput) -> [WorkspaceSwipeEffect] {
        switch input {
        case .cancel, .ended:
            reset()
            return []
        case let .touches(touches):
            return handleTouches(touches)
        }
    }

    private mutating func handleTouches(
        _ touches: [WorkspaceSwipeTouch]
    ) -> [WorkspaceSwipeEffect] {
        guard !touches.isEmpty else {
            reset()
            return []
        }
        guard phase != .latched else { return [] }

        let positions = Dictionary(uniqueKeysWithValues: touches.map {
            ($0.identity, $0.normalizedPosition)
        })
        guard positions.count == fingerCount.rawValue else {
            if phase == .tracking { latch() }
            return []
        }

        if phase == .idle {
            phase = .tracking
            previousPositions = positions
            return []
        }

        guard Set(positions.keys) == Set(previousPositions.keys) else {
            latch()
            return []
        }

        let deltas = positions.compactMap { identity, position -> CGPoint? in
            previousPositions[identity].map {
                CGPoint(x: position.x - $0.x, y: position.y - $0.y)
            }
        }
        previousPositions = positions
        guard deltas.count == fingerCount.rawValue else {
            latch()
            return []
        }

        accumulatedX += coherentAverage(deltas.map(\.x))
        accumulatedY += coherentAverage(deltas.map(\.y))

        let absoluteX = abs(accumulatedX)
        let absoluteY = abs(accumulatedY)
        if absoluteY >= Self.movementThreshold,
           absoluteY > absoluteX * Self.axisDominance {
            latch()
            return []
        }
        guard absoluteX >= Self.movementThreshold,
              absoluteX > absoluteY * Self.axisDominance
        else { return [] }

        let direction: WorkspaceSwipeDirection = accumulatedX < 0 ? .next : .previous
        latch()
        return [.switchWorkspace(direction)]
    }

    private func coherentAverage(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let allNonnegative = values.allSatisfy { $0 >= 0 }
        let allNonpositive = values.allSatisfy { $0 <= 0 }
        guard allNonnegative || allNonpositive else { return 0 }
        return values.reduce(0, +) / CGFloat(values.count)
    }

    private mutating func latch() {
        phase = .latched
        previousPositions.removeAll(keepingCapacity: true)
    }

    private mutating func reset() {
        phase = .idle
        previousPositions.removeAll(keepingCapacity: true)
        accumulatedX = 0
        accumulatedY = 0
    }
}

@MainActor
protocol WorkspaceSwipeEventMonitoring: AnyObject {
    typealias InputHandler = @MainActor (WorkspaceSwipeInput) -> Void
    typealias RuntimeIssueHandler = @MainActor (String?) -> Void

    func start(
        inputHandler: @escaping InputHandler,
        runtimeIssueHandler: @escaping RuntimeIssueHandler
    ) -> Bool
    func stop()
}

/// WindowServer currently exposes generic trackpad contacts to a HID event tap using the raw event
/// value shared with AppKit's public `.gesture` type. Core Graphics does not publish a named
/// `CGEventType` for that value, so this adapter is deliberately optional, isolated, and fail-closed.
/// It never suppresses or modifies an event and never logs touch identities or positions.
@MainActor
final class CGWorkspaceSwipeEventMonitor: WorkspaceSwipeEventMonitoring {
    private static let gestureEventType = CGEventType(
        rawValue: UInt32(NSEvent.EventType.gesture.rawValue)
    )!

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var inputHandler: InputHandler?
    private var runtimeIssueHandler: RuntimeIssueHandler?

    deinit {
        MainActor.assumeIsolated { stop() }
    }

    func start(
        inputHandler: @escaping InputHandler,
        runtimeIssueHandler: @escaping RuntimeIssueHandler
    ) -> Bool {
        stop()
        guard AXIsProcessTrusted() else { return false }

        self.inputHandler = inputHandler
        self.runtimeIssueHandler = runtimeIssueHandler
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<CGWorkspaceSwipeEventMonitor>
                .fromOpaque(userInfo)
                .takeUnretainedValue()
            MainActor.assumeIsolated {
                monitor.process(type: type, event: event)
            }
            return Unmanaged.passUnretained(event)
        }
        guard let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: NSEvent.EventTypeMask.gesture.rawValue,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        else {
            self.inputHandler = nil
            self.runtimeIssueHandler = nil
            return false
        }

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
        inputHandler = nil
        runtimeIssueHandler = nil
    }

    private func process(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            guard let eventTap else {
                runtimeIssueHandler?(Self.unavailableMessage)
                return
            }
            CGEvent.tapEnable(tap: eventTap, enable: true)
            runtimeIssueHandler?(
                CGEvent.tapIsEnabled(tap: eventTap) ? nil : Self.unavailableMessage
            )
            return
        }
        guard type == Self.gestureEventType,
              let nsEvent = NSEvent(cgEvent: event)
        else { return }

        let allTouches = nsEvent.allTouches()
        // Some macOS releases emit empty generic-gesture packets mid-sequence. They carry no
        // reliable lifecycle information, so ignore them rather than ending a valid gesture.
        guard !allTouches.isEmpty else { return }
        let nonResting = allTouches.filter { !$0.isResting }
        let active = nonResting.filter {
            $0.phase != .ended && $0.phase != .cancelled
        }
        guard !active.isEmpty else {
            inputHandler?(.ended)
            return
        }
        inputHandler?(.touches(active.map {
            WorkspaceSwipeTouch(
                identity: String(describing: $0.identity),
                normalizedPosition: $0.normalizedPosition
            )
        }))
    }

    private static let unavailableMessage =
        "macOS could not observe global trackpad gestures. Workspace swiping is inactive."
}

@MainActor
final class WorkspaceSwipeController {
    typealias RuntimeIssueHandler = @MainActor (String?) -> Void

    private let monitor: WorkspaceSwipeEventMonitoring
    private let dispatcher: WindowManagerCommandDispatcher
    private let diagnostics: DiagnosticLogger
    private var stateMachine = WorkspaceSwipeStateMachine()
    private var enabled = false
    private var fingerCount: WorkspaceSwipeFingerCount = .three
    private var suppressionReasons = Set<String>()
    private var isMonitoring = false

    var runtimeIssueChanged: RuntimeIssueHandler?

    init(
        monitor: WorkspaceSwipeEventMonitoring? = nil,
        dispatcher: WindowManagerCommandDispatcher,
        diagnostics: DiagnosticLogger = .disabled
    ) {
        self.monitor = monitor ?? CGWorkspaceSwipeEventMonitor()
        self.dispatcher = dispatcher
        self.diagnostics = diagnostics
    }

    func update(enabled: Bool, fingerCount: WorkspaceSwipeFingerCount) {
        let configurationChanged = self.fingerCount != fingerCount
        self.enabled = enabled
        self.fingerCount = fingerCount
        if configurationChanged {
            stateMachine.updateFingerCount(fingerCount)
        }
        reconcileMonitoring()
    }

    func setSuppressed(_ suppressed: Bool, reason: String) {
        let changed: Bool
        if suppressed {
            changed = suppressionReasons.insert(reason).inserted
        } else {
            changed = suppressionReasons.remove(reason) != nil
        }
        guard changed else { return }
        cancel(reason: reason)
        reconcileMonitoring()
    }

    func cancel(reason: String) {
        _ = stateMachine.handle(.cancel)
        guard enabled || isMonitoring else { return }
        diagnostics.log(
            category: "workspace-swipe",
            event: "gesture-cancelled",
            fields: ["reason": reason]
        )
    }

    func shutdown() {
        enabled = false
        suppressionReasons.insert("shutdown")
        _ = stateMachine.handle(.cancel)
        monitor.stop()
        isMonitoring = false
        runtimeIssueChanged?(nil)
    }

    private func reconcileMonitoring() {
        guard enabled, suppressionReasons.isEmpty else {
            if isMonitoring { monitor.stop() }
            isMonitoring = false
            _ = stateMachine.handle(.cancel)
            runtimeIssueChanged?(nil)
            return
        }
        guard !isMonitoring else { return }

        let started = monitor.start(
            inputHandler: { [weak self] input in self?.handle(input) },
            runtimeIssueHandler: { [weak self] issue in
                self?.runtimeIssueChanged?(issue)
            }
        )
        isMonitoring = started
        let issue = started ? nil :
            "macOS could not observe global trackpad gestures. Workspace swiping is inactive."
        runtimeIssueChanged?(issue)
        diagnostics.log(
            category: "workspace-swipe",
            event: started ? "monitor-started" : "monitor-unavailable",
            fields: ["fingers": String(fingerCount.rawValue)]
        )
    }

    private func handle(_ input: WorkspaceSwipeInput) {
        for effect in stateMachine.handle(input) {
            guard case let .switchWorkspace(direction) = effect else { continue }
            diagnostics.log(
                category: "workspace-swipe",
                event: "gesture-accepted",
                fields: [
                    "direction": direction.rawValue,
                    "fingers": String(fingerCount.rawValue),
                ]
            )
            dispatcher.dispatch(
                .cycleWorkspace(direction.workspaceOffset),
                source: .workspaceSwipe
            )
        }
    }
}
