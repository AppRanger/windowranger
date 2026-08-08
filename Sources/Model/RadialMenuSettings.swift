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
        case .commandWheel: "Contextual command wheel"
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
