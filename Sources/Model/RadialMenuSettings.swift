import Carbon
import Foundation

struct HotKeyChord: Hashable, Codable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32

    var keyCaps: [String] {
        var values: [String] = []
        if modifiers & UInt32(controlKey) != 0 { values.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { values.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { values.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { values.append("⌘") }
        values.append(Self.keyLabel(for: keyCode))
        return values
    }

    var title: String { keyCaps.joined(separator: " ") }

    static func keyLabel(for keyCode: UInt32) -> String {
        switch keyCode {
        case 0: "A"; case 1: "S"; case 2: "D"; case 3: "F"; case 4: "H"
        case 5: "G"; case 6: "Z"; case 7: "X"; case 8: "C"; case 9: "V"
        case 11: "B"; case 12: "Q"; case 13: "W"; case 14: "E"; case 15: "R"
        case 16: "Y"; case 17: "T"; case 18: "1"; case 19: "2"; case 20: "3"
        case 21: "4"; case 22: "6"; case 23: "5"; case 24: "="; case 25: "9"
        case 26: "7"; case 27: "−"; case 28: "8"; case 29: "0"; case 30: "]"
        case 31: "O"; case 32: "U"; case 33: "["; case 34: "I"; case 35: "P"
        case 36: "↩"; case 37: "L"; case 38: "J"; case 40: "K"; case 41: ";"
        case 42: "\\"; case 43: ","; case 44: "/"; case 45: "N"; case 46: "M"
        case 47: "."; case 48: "⇥"; case 49: "Space"; case 50: "`"
        case 51: "⌫"; case 53: "Esc"; case 76: "⌤"
        case 115: "Home"; case 116: "Page Up"; case 117: "⌦"; case 119: "End"
        case 121: "Page Down"; case 123: "←"; case 124: "→"; case 125: "↓"; case 126: "↑"
        default: "Key \(keyCode)"
        }
    }
}

enum ConfigurableHotKeyAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case previousWorkspace
    case nextWorkspace
    case backAndForthWorkspace
    case previousWindow
    case nextWindow
    case selectAccordion
    case selectTiled
    case toggleFloating
    case toggleDropDownApp
    case focusLeft
    case focusDown
    case focusUp
    case focusRight
    case moveLeft
    case moveDown
    case moveUp
    case moveRight
    case resizeSmaller
    case resizeLarger
    case moveWorkspaceToNextDisplay
    case commandWheel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .previousWorkspace: "Previous workspace"
        case .nextWorkspace: "Next workspace"
        case .backAndForthWorkspace: "Back and forth workspace"
        case .previousWindow: "Previous window"
        case .nextWindow: "Next window"
        case .selectAccordion: "Select Accordion"
        case .selectTiled: "Select Tiled"
        case .toggleFloating: "Toggle focused window Floating"
        case .toggleDropDownApp: "Toggle Quick App"
        case .focusLeft: "Focus left"
        case .focusDown: "Focus down"
        case .focusUp: "Focus up"
        case .focusRight: "Focus right"
        case .moveLeft: "Reorder left"
        case .moveDown: "Reorder down"
        case .moveUp: "Reorder up"
        case .moveRight: "Reorder right"
        case .resizeSmaller: "Smart resize smaller"
        case .resizeLarger: "Smart resize larger"
        case .moveWorkspaceToNextDisplay: "Move workspace to next display"
        case .commandWheel: "Command palette"
        }
    }

    var command: WindowManagerCommand? {
        switch self {
        case .previousWorkspace: .cycleWorkspace(-1)
        case .nextWorkspace: .cycleWorkspace(1)
        case .backAndForthWorkspace: .previousWorkspace
        case .previousWindow: .cycleWindow(-1)
        case .nextWindow: .cycleWindow(1)
        case .selectAccordion: .selectLayoutFromShortcut(.accordion)
        case .selectTiled: .selectLayoutFromShortcut(.tiled)
        case .toggleFloating: .toggleFloating
        case .toggleDropDownApp: .toggleDropDownApp
        case .focusLeft: .focusDirection(.left)
        case .focusDown: .focusDirection(.down)
        case .focusUp: .focusDirection(.up)
        case .focusRight: .focusDirection(.right)
        case .moveLeft: .moveWindowDirection(.left)
        case .moveDown: .moveWindowDirection(.down)
        case .moveUp: .moveWindowDirection(.up)
        case .moveRight: .moveWindowDirection(.right)
        case .resizeSmaller: .smartResize(-50)
        case .resizeLarger: .smartResize(50)
        case .moveWorkspaceToNextDisplay: .moveCurrentWorkspaceToNextDisplay
        case .commandWheel: nil
        }
    }

    var defaultChord: HotKeyChord {
        switch self {
        case .previousWorkspace: .init(keyCode: 33, modifiers: UInt32(controlKey | optionKey))
        case .nextWorkspace: .init(keyCode: 30, modifiers: UInt32(controlKey | optionKey))
        case .backAndForthWorkspace: .init(keyCode: 48, modifiers: UInt32(controlKey | optionKey))
        case .previousWindow: .init(keyCode: 33, modifiers: UInt32(optionKey))
        case .nextWindow: .init(keyCode: 30, modifiers: UInt32(optionKey))
        case .selectAccordion: .init(keyCode: 43, modifiers: UInt32(optionKey))
        case .selectTiled: .init(keyCode: 47, modifiers: UInt32(optionKey))
        case .toggleFloating: .init(keyCode: 3, modifiers: UInt32(controlKey | optionKey))
        case .toggleDropDownApp: .init(keyCode: 50, modifiers: UInt32(controlKey | optionKey))
        case .focusLeft: .init(keyCode: 4, modifiers: UInt32(optionKey))
        case .focusDown: .init(keyCode: 38, modifiers: UInt32(optionKey))
        case .focusUp: .init(keyCode: 40, modifiers: UInt32(optionKey))
        case .focusRight: .init(keyCode: 37, modifiers: UInt32(optionKey))
        case .moveLeft: .init(keyCode: 123, modifiers: UInt32(controlKey | optionKey))
        case .moveDown: .init(keyCode: 125, modifiers: UInt32(controlKey | optionKey))
        case .moveUp: .init(keyCode: 126, modifiers: UInt32(controlKey | optionKey))
        case .moveRight: .init(keyCode: 124, modifiers: UInt32(controlKey | optionKey))
        case .resizeSmaller: .init(keyCode: 27, modifiers: UInt32(controlKey | optionKey))
        case .resizeLarger: .init(keyCode: 24, modifiers: UInt32(controlKey | optionKey))
        case .moveWorkspaceToNextDisplay: .init(keyCode: 48, modifiers: UInt32(optionKey | shiftKey))
        case .commandWheel: .init(keyCode: 49, modifiers: UInt32(controlKey | optionKey))
        }
    }
}

struct HotKeyConfiguration: Codable, Equatable, Sendable {
    private var overrides: [String: HotKeyChord] = [:]

    func chord(for action: ConfigurableHotKeyAction) -> HotKeyChord {
        overrides[action.rawValue] ?? action.defaultChord
    }

    func isUsingDefault(for action: ConfigurableHotKeyAction) -> Bool {
        chord(for: action) == action.defaultChord
    }

    func hasExplicitChord(for action: ConfigurableHotKeyAction) -> Bool {
        overrides[action.rawValue] != nil
    }

    mutating func setChord(_ chord: HotKeyChord, for action: ConfigurableHotKeyAction) {
        if chord == action.defaultChord {
            overrides.removeValue(forKey: action.rawValue)
        } else {
            overrides[action.rawValue] = chord
        }
    }

    mutating func reset(_ action: ConfigurableHotKeyAction) {
        overrides.removeValue(forKey: action.rawValue)
    }

    mutating func resetAll() {
        overrides.removeAll()
    }
}

/// Read-only compatibility for the three choices stored by builds before the command wheel joined
/// the shared shortcut recorder. SettingsStore consumes and removes this value after conversion.
enum LegacyRadialMenuShortcut: String, Codable, Sendable {
    case controlOptionSpace
    case controlOptionReturn
    case controlOptionBackslash

    var chord: HotKeyChord {
        let keyCode: UInt32 = switch self {
        case .controlOptionSpace: 49
        case .controlOptionReturn: 36
        case .controlOptionBackslash: 42
        }
        return HotKeyChord(keyCode: keyCode, modifiers: UInt32(controlKey | optionKey))
    }
}

enum RadialMenuActivationStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case pressToToggle
    case holdToShow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pressToToggle: "Press to toggle"
        case .holdToShow: "Hold to show"
        }
    }
}

enum RadialMenuHoldDelay {
    static let defaultValue: TimeInterval = 0.2
    static let permittedRange: ClosedRange<TimeInterval> = 0.15...1.0

    static func clamped(_ value: TimeInterval) -> TimeInterval {
        min(max(value, permittedRange.lowerBound), permittedRange.upperBound)
    }
}

/// Immutable runtime inputs for the optional device-local Globe/Fn trigger. Callers that receive
/// an `@Published` value must pass that emitted value here instead of synchronously rereading its
/// source object, because Combine publishes from `willSet`.
struct GlobeFnRuntimeSettings: Equatable, Sendable {
    let isEnabled: Bool
    let holdDelay: TimeInterval

    init(
        radialMenuEnabled: Bool,
        globeFnEnabled: Bool,
        isShortcutRecording: Bool,
        holdDelay: TimeInterval
    ) {
        isEnabled = radialMenuEnabled && globeFnEnabled && !isShortcutRecording
        self.holdDelay = RadialMenuHoldDelay.clamped(holdDelay)
    }
}

enum RadialMenuTriggerInputEvent: Equatable, Sendable {
    case pressed
    case released
    case escape
}

enum RadialMenuTriggerEffect: Equatable, Sendable {
    case toggle
    case captureContext(generation: UInt64)
    case scheduleThreshold(generation: UInt64, delay: TimeInterval)
    case cancelThreshold(reason: String)
    case presentCaptured(generation: UInt64)
    case commitHighlightedOrDismiss(generation: UInt64)
    case dismiss(reason: String)
}

/// Pure state machine shared by runtime and deterministic tests. It has no event tap, timer, AX,
/// window, or application side effects; runtime adapts Carbon hot-key press/release events to it.
struct RadialMenuTriggerStateMachine: Equatable, Sendable {
    private enum Phase: Equatable, Sendable {
        case idle
        case waiting(generation: UInt64, thresholdReached: Bool, contextReady: Bool)
        case presented(generation: UInt64)
    }

    private var phase: Phase = .idle
    private(set) var latestGeneration: UInt64 = 0

    var isIdle: Bool { phase == .idle }

    func isPresented(generation: UInt64) -> Bool {
        phase == .presented(generation: generation)
    }

    mutating func handle(
        _ event: RadialMenuTriggerInputEvent,
        style: RadialMenuActivationStyle,
        holdDelay: TimeInterval
    ) -> [RadialMenuTriggerEffect] {
        switch (style, event) {
        case (.pressToToggle, .pressed):
            return [.toggle]
        case (.pressToToggle, .released):
            return []
        case (.pressToToggle, .escape):
            return [.dismiss(reason: "escape")]
        case (.holdToShow, .pressed):
            guard case .idle = phase else { return [] }
            latestGeneration &+= 1
            let generation = latestGeneration
            phase = .waiting(generation: generation, thresholdReached: false, contextReady: false)
            return [
                .captureContext(generation: generation),
                .scheduleThreshold(
                    generation: generation,
                    delay: RadialMenuHoldDelay.clamped(holdDelay)
                ),
            ]
        case (.holdToShow, .released):
            switch phase {
            case .idle:
                return []
            case .waiting:
                phase = .idle
                return [.cancelThreshold(reason: "released-before-presentation")]
            case let .presented(generation):
                phase = .idle
                return [.commitHighlightedOrDismiss(generation: generation)]
            }
        case (.holdToShow, .escape):
            guard phase != .idle else { return [] }
            phase = .idle
            return [
                .cancelThreshold(reason: "escape"),
                .dismiss(reason: "escape"),
            ]
        }
    }

    mutating func contextCaptured(generation: UInt64, hasRelevantActions: Bool) -> [RadialMenuTriggerEffect] {
        guard case let .waiting(current, thresholdReached, _) = phase,
              current == generation
        else { return [] }
        guard hasRelevantActions else {
            phase = .idle
            return [.cancelThreshold(reason: "no-relevant-actions")]
        }
        if thresholdReached {
            phase = .presented(generation: generation)
            return [.presentCaptured(generation: generation)]
        }
        phase = .waiting(generation: generation, thresholdReached: false, contextReady: true)
        return []
    }

    mutating func thresholdElapsed(generation: UInt64) -> [RadialMenuTriggerEffect] {
        guard case let .waiting(current, _, contextReady) = phase,
              current == generation
        else { return [] }
        if contextReady {
            phase = .presented(generation: generation)
            return [.presentCaptured(generation: generation)]
        }
        phase = .waiting(generation: generation, thresholdReached: true, contextReady: false)
        return []
    }

    mutating func presentationRejected(generation: UInt64, reason: String) -> [RadialMenuTriggerEffect] {
        guard case let .presented(current) = phase, current == generation else { return [] }
        phase = .idle
        return [.dismiss(reason: reason)]
    }

    mutating func cancel(reason: String) -> [RadialMenuTriggerEffect] {
        guard phase != .idle else { return [] }
        phase = .idle
        return [
            .cancelThreshold(reason: reason),
            .dismiss(reason: reason),
        ]
    }
}

enum GlobeFnCompetingInput: String, Equatable, Sendable {
    case modifier
    case key
    case escape
    case mouseButton
    case systemDefined
}

/// Public-event facts emitted by the runtime monitor. Keeping these facts free of `CGEvent`
/// makes Fn/Globe gesture admission deterministic and prevents unit tests from installing a tap.
enum GlobeFnObservedEvent: Equatable, Sendable {
    case flagsChanged(functionDown: Bool, otherModifiersDown: Bool)
    case keyChanged(isDown: Bool, keyCode: UInt16, isRepeat: Bool)
    case mouseButtonDown
    case systemDefined
}

/// The active Quartz filter exists only to discard the synthetic native Globe key after an
/// accepted hold. Every ordinary key and mouse event must pass without consulting app state.
enum GlobeFnNativeEventFilterPolicy {
    static func shouldSuppress(
        keyCode: UInt16,
        nativeGlobeFilteringEnabled: Bool
    ) -> Bool {
        nativeGlobeFilteringEnabled &&
            keyCode == GlobeFnEventNormalizer.nativeGlobeActionKeyCode
    }
}

/// Input-monitor suspension is intentionally broader than native-fullscreen geometry protection.
/// A borderless declared game still needs an unobstructed keyboard and mouse path even though its
/// window remains an ordinary non-fullscreen Accessibility object.
enum ForegroundGameInputProtectionPolicy {
    static func shouldSuppressOptionalInputMonitors(
        isDeclaredGameApplicationActive: Bool,
        hasNativeFullscreenGameSession: Bool
    ) -> Bool {
        isDeclaredGameApplicationActive || hasNativeFullscreenGameSession
    }
}

enum GlobeFnGestureInputEvent: Equatable, Sendable {
    case functionChanged(isDown: Bool, otherModifiersDown: Bool)
    case competingInput(GlobeFnCompetingInput)
    case nativeGlobeKey(isDown: Bool)
    case thresholdElapsed(generation: UInt64)
    case suppressionExpired(generation: UInt64)
    case cancel(reason: String)
}

/// Converts event-tap facts into gesture facts without exposing key content or device identity.
/// Public Quartz events do not reliably distinguish the built-in Fn key from an external Globe
/// key, so both intentionally share the same conservative state machine.
struct GlobeFnEventNormalizer: Equatable, Sendable {
    /// The public key code emitted for the native Globe/Emoji action after a Globe tap.
    static let nativeGlobeActionKeyCode: UInt16 = 0xB3

    private(set) var functionDown = false

    mutating func normalize(_ event: GlobeFnObservedEvent) -> GlobeFnGestureInputEvent? {
        switch event {
        case let .flagsChanged(isFunctionDown, otherModifiersDown):
            if isFunctionDown != functionDown {
                functionDown = isFunctionDown
                return .functionChanged(
                    isDown: isFunctionDown,
                    otherModifiersDown: otherModifiersDown
                )
            }
            if functionDown, otherModifiersDown {
                return .competingInput(.modifier)
            }
            return nil

        case let .keyChanged(isDown, keyCode, _):
            if keyCode == Self.nativeGlobeActionKeyCode {
                return .nativeGlobeKey(isDown: isDown)
            }
            guard functionDown, isDown else { return nil }
            return .competingInput(keyCode == 53 ? .escape : .key)

        case .mouseButtonDown:
            return functionDown ? .competingInput(.mouseButton) : nil

        case .systemDefined:
            return functionDown ? .competingInput(.systemDefined) : nil
        }
    }

    mutating func reset() {
        functionDown = false
    }
}

enum GlobeFnGestureEffect: Equatable, Sendable {
    case scheduleThreshold(generation: UInt64, delay: TimeInterval)
    case cancelThreshold(reason: String)
    case activateHold(generation: UInt64)
    case releaseHold(generation: UInt64)
    case cancelHold(reason: String)
    case scheduleSuppressionExpiry(generation: UInt64, delay: TimeInterval)
    case cancelSuppressionExpiry
    case suppressCurrentEvent
}

/// Pure admission state for the optional Globe/Fn gesture. It never installs a tap, opens a menu,
/// or synthesizes an event. A quick tap and every chorded sequence therefore remain untouched;
/// only the native Globe action following an accepted hold can be filtered by the runtime adapter.
struct GlobeFnGestureStateMachine: Equatable, Sendable {
    private enum NativeEventProgress: Equatable, Sendable {
        case none
        case downSuppressed
        case completed
    }

    private enum Phase: Equatable, Sendable {
        case idle
        case candidate(generation: UInt64)
        case held(generation: UInt64, nativeEvent: NativeEventProgress)
        case blockedAwaitingFunctionRelease
        case awaitingNativeGlobe(generation: UInt64)
        case suppressingNativeGlobeKeyUp(generation: UInt64)
    }

    static let nativeSuppressionWindow: TimeInterval = 0.5

    private var phase: Phase = .idle
    private(set) var latestGeneration: UInt64 = 0

    var phaseName: String {
        switch phase {
        case .idle: "idle"
        case .candidate: "candidate"
        case .held: "held"
        case .blockedAwaitingFunctionRelease: "blocked"
        case .awaitingNativeGlobe: "awaiting-native-globe"
        case .suppressingNativeGlobeKeyUp: "suppressing-native-globe-key-up"
        }
    }

    mutating func handle(
        _ event: GlobeFnGestureInputEvent,
        holdDelay: TimeInterval
    ) -> [GlobeFnGestureEffect] {
        switch event {
        case let .functionChanged(isDown, otherModifiersDown):
            return functionChanged(
                isDown: isDown,
                otherModifiersDown: otherModifiersDown,
                holdDelay: holdDelay
            )

        case let .competingInput(input):
            return competingInput(input)

        case let .nativeGlobeKey(isDown):
            return nativeGlobeKey(isDown: isDown)

        case let .thresholdElapsed(generation):
            guard case let .candidate(current) = phase, current == generation else { return [] }
            phase = .held(generation: generation, nativeEvent: .none)
            return [.activateHold(generation: generation)]

        case let .suppressionExpired(generation):
            switch phase {
            case .awaitingNativeGlobe(generation), .suppressingNativeGlobeKeyUp(generation):
                phase = .idle
                return []
            default:
                return []
            }

        case let .cancel(reason):
            return cancel(reason: reason)
        }
    }

    private mutating func functionChanged(
        isDown: Bool,
        otherModifiersDown: Bool,
        holdDelay: TimeInterval
    ) -> [GlobeFnGestureEffect] {
        if isDown {
            switch phase {
            case .candidate, .held, .blockedAwaitingFunctionRelease:
                return []
            case .awaitingNativeGlobe, .suppressingNativeGlobeKeyUp:
                phase = .idle
                return [.cancelSuppressionExpiry] + startCandidate(
                    otherModifiersDown: otherModifiersDown,
                    holdDelay: holdDelay
                )
            case .idle:
                return startCandidate(
                    otherModifiersDown: otherModifiersDown,
                    holdDelay: holdDelay
                )
            }
        }

        switch phase {
        case .idle, .awaitingNativeGlobe, .suppressingNativeGlobeKeyUp:
            return []
        case .candidate:
            phase = .idle
            return [.cancelThreshold(reason: "quick-tap")]
        case let .held(generation, nativeEvent):
            let effects: [GlobeFnGestureEffect] = [.releaseHold(generation: generation)]
            switch nativeEvent {
            case .completed:
                phase = .idle
                return effects
            case .none:
                phase = .awaitingNativeGlobe(generation: generation)
            case .downSuppressed:
                phase = .suppressingNativeGlobeKeyUp(generation: generation)
            }
            return effects + [
                .scheduleSuppressionExpiry(
                    generation: generation,
                    delay: Self.nativeSuppressionWindow
                ),
            ]
        case .blockedAwaitingFunctionRelease:
            phase = .idle
            return []
        }
    }

    private mutating func startCandidate(
        otherModifiersDown: Bool,
        holdDelay: TimeInterval
    ) -> [GlobeFnGestureEffect] {
        guard !otherModifiersDown else {
            phase = .blockedAwaitingFunctionRelease
            return []
        }
        latestGeneration &+= 1
        let generation = latestGeneration
        phase = .candidate(generation: generation)
        return [
            .scheduleThreshold(
                generation: generation,
                delay: RadialMenuHoldDelay.clamped(holdDelay)
            ),
        ]
    }

    private mutating func competingInput(
        _ input: GlobeFnCompetingInput
    ) -> [GlobeFnGestureEffect] {
        switch phase {
        case .idle, .blockedAwaitingFunctionRelease:
            return []
        case .candidate:
            phase = .blockedAwaitingFunctionRelease
            return [.cancelThreshold(reason: "competing-\(input.rawValue)")]
        case .held where input == .mouseButton || input == .systemDefined:
            // Once the deliberate hold has opened the wheel, pointer input belongs to the wheel.
            // Some keyboards also emit a system-defined event beside a click while Fn remains
            // down, so treating either event as a competing chord makes clickable wedges dismiss
            // before SwiftUI receives the completed click. They remain disqualifying during the
            // pre-threshold candidate phase, preserving quick Fn-click and native Globe behavior.
            return []
        case .held:
            phase = .blockedAwaitingFunctionRelease
            return [
                .cancelThreshold(reason: "competing-\(input.rawValue)"),
                .cancelHold(reason: "competing-\(input.rawValue)"),
            ]
        case .awaitingNativeGlobe, .suppressingNativeGlobeKeyUp:
            phase = .idle
            return [.cancelSuppressionExpiry]
        }
    }

    private mutating func nativeGlobeKey(isDown: Bool) -> [GlobeFnGestureEffect] {
        switch phase {
        case let .held(generation, _):
            let next: NativeEventProgress
            if isDown {
                next = .downSuppressed
            } else {
                next = .completed
            }
            phase = .held(generation: generation, nativeEvent: next)
            return [.suppressCurrentEvent]

        case let .awaitingNativeGlobe(generation):
            if isDown {
                phase = .suppressingNativeGlobeKeyUp(generation: generation)
            } else {
                phase = .idle
            }
            return [.suppressCurrentEvent]

        case .suppressingNativeGlobeKeyUp:
            if !isDown { phase = .idle }
            return [.suppressCurrentEvent]

        case .idle, .candidate, .blockedAwaitingFunctionRelease:
            return []
        }
    }

    private mutating func cancel(reason: String) -> [GlobeFnGestureEffect] {
        switch phase {
        case .idle:
            return []
        case .candidate:
            phase = .idle
            return [.cancelThreshold(reason: reason)]
        case .held:
            phase = .idle
            return [
                .cancelThreshold(reason: reason),
                .cancelHold(reason: reason),
            ]
        case .blockedAwaitingFunctionRelease:
            phase = .idle
            return []
        case .awaitingNativeGlobe, .suppressingNativeGlobeKeyUp:
            phase = .idle
            return [.cancelSuppressionExpiry]
        }
    }
}
