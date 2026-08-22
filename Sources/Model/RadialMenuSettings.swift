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

enum ShortcutFamily: String, Codable, CaseIterable, Identifiable, Sendable {
    case navigate
    case arrange

    var id: String { rawValue }

    var title: String {
        switch self {
        case .navigate: "Navigate"
        case .arrange: "Arrange"
        }
    }

    var defaultModifiers: UInt32 {
        switch self {
        case .navigate: UInt32(controlKey | optionKey)
        case .arrange: UInt32(optionKey | cmdKey)
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

    /// The modifier family is deliberately owned by the action definition, rather than by an
    /// independently-recorded complete chord. This keeps the two shortcut families learnable.
    var family: ShortcutFamily {
        switch self {
        case .previousWorkspace, .nextWorkspace, .backAndForthWorkspace,
             .previousWindow, .nextWindow, .toggleDropDownApp,
             .focusLeft, .focusDown, .focusUp, .focusRight, .commandWheel:
            .navigate
        case .selectAccordion, .selectTiled, .toggleFloating,
             .moveLeft, .moveDown, .moveUp, .moveRight,
             .resizeSmaller, .resizeLarger, .moveWorkspaceToNextDisplay:
            .arrange
        }
    }

    /// `nil` is an intentionally unassigned command. It is still available through the palette.
    var defaultKeyCode: UInt32? {
        switch self {
        case .previousWorkspace: 33 // [
        case .nextWorkspace: 30 // ]
        case .backAndForthWorkspace: 48 // Tab
        case .previousWindow: 43 // ,
        case .nextWindow: 47 // .
        case .selectAccordion: 43 // ,
        case .selectTiled: 47 // .
        case .toggleFloating: 3 // F
        case .toggleDropDownApp: 50 // `
        case .focusLeft: 123
        case .focusDown: 125
        case .focusUp: 126
        case .focusRight: 124
        case .moveLeft: 123
        case .moveDown: 125
        case .moveUp: 126
        case .moveRight: 124
        case .resizeSmaller: 27 // -
        case .resizeLarger: 24 // =
        case .moveWorkspaceToNextDisplay: 2 // D
        case .commandWheel: 49 // Space
        }
    }

}

struct HotKeyConfiguration: Codable, Equatable, Sendable {
    private var familyModifiers: [String: UInt32]
    private var keyOverrides: [String: UInt32]
    private var disabledActions: Set<String>

    init() {
        familyModifiers = Dictionary(uniqueKeysWithValues: ShortcutFamily.allCases.map {
            ($0.rawValue, $0.defaultModifiers)
        })
        keyOverrides = [:]
        disabledActions = []
    }

    private enum CodingKeys: String, CodingKey {
        case familyModifiers
        case keyOverrides
        case disabledActions
        // Private pre-release format: complete chords. Decode it safely, but deliberately adopt
        // the approved family map instead of preserving a now-incoherent set of individual chords.
        case overrides
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedFamilies = try container.decodeIfPresent([String: UInt32].self, forKey: .familyModifiers)
        let decodedKeys = try container.decodeIfPresent([String: UInt32].self, forKey: .keyOverrides)
        let decodedDisabled = try container.decodeIfPresent(Set<String>.self, forKey: .disabledActions)

        // Absence of the new keys identifies both an empty private-install `{ "overrides": {} }`
        // and older full-chord data. Both deterministically migrate to the approved defaults.
        guard decodedFamilies != nil || decodedKeys != nil || decodedDisabled != nil else {
            self.init()
            return
        }

        self.init()
        if let decodedFamilies,
           Self.familyValidationMessage(navigate: decodedFamilies[ShortcutFamily.navigate.rawValue] ?? ShortcutFamily.navigate.defaultModifiers,
                                        arrange: decodedFamilies[ShortcutFamily.arrange.rawValue] ?? ShortcutFamily.arrange.defaultModifiers) == nil {
            familyModifiers[ShortcutFamily.navigate.rawValue] = decodedFamilies[ShortcutFamily.navigate.rawValue] ?? ShortcutFamily.navigate.defaultModifiers
            familyModifiers[ShortcutFamily.arrange.rawValue] = decodedFamilies[ShortcutFamily.arrange.rawValue] ?? ShortcutFamily.arrange.defaultModifiers
        }
        let supportedActionNames = Set(ConfigurableHotKeyAction.allCases.map(\.rawValue))
        keyOverrides = (decodedKeys ?? [:]).filter { supportedActionNames.contains($0.key) }
        disabledActions = (decodedDisabled ?? []).intersection(supportedActionNames)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(familyModifiers, forKey: .familyModifiers)
        try container.encode(keyOverrides, forKey: .keyOverrides)
        try container.encode(disabledActions, forKey: .disabledActions)
    }

    func modifierMask(for family: ShortcutFamily) -> UInt32 {
        familyModifiers[family.rawValue] ?? family.defaultModifiers
    }

    func keyCode(for action: ConfigurableHotKeyAction) -> UInt32? {
        guard !disabledActions.contains(action.rawValue) else { return nil }
        return keyOverrides[action.rawValue] ?? action.defaultKeyCode
    }

    func chord(for action: ConfigurableHotKeyAction) -> HotKeyChord {
        guard let chord = optionalChord(for: action) else {
            preconditionFailure("Use optionalChord(for:) for an unassigned shortcut action.")
        }
        return chord
    }

    func optionalChord(for action: ConfigurableHotKeyAction) -> HotKeyChord? {
        guard let keyCode = keyCode(for: action) else { return nil }
        return HotKeyChord(keyCode: keyCode, modifiers: modifierMask(for: action.family))
    }

    func chord(forWorkspaceKeyCode keyCode: UInt32, family: ShortcutFamily) -> HotKeyChord {
        HotKeyChord(keyCode: keyCode, modifiers: modifierMask(for: family))
    }

    func isEnabled(_ action: ConfigurableHotKeyAction) -> Bool {
        optionalChord(for: action) != nil
    }

    func isUsingDefault(for action: ConfigurableHotKeyAction) -> Bool {
        keyCode(for: action) == action.defaultKeyCode &&
            modifierMask(for: action.family) == action.family.defaultModifiers
    }

    func hasExplicitKeyAssignment(for action: ConfigurableHotKeyAction) -> Bool {
        keyOverrides[action.rawValue] != nil || disabledActions.contains(action.rawValue)
    }

    mutating func setKeyCode(_ keyCode: UInt32?, for action: ConfigurableHotKeyAction) {
        if keyCode == action.defaultKeyCode {
            keyOverrides.removeValue(forKey: action.rawValue)
            disabledActions.remove(action.rawValue)
        } else if let keyCode {
            keyOverrides[action.rawValue] = keyCode
            disabledActions.remove(action.rawValue)
        } else {
            keyOverrides.removeValue(forKey: action.rawValue)
            disabledActions.insert(action.rawValue)
        }
    }

    @discardableResult
    mutating func setModifierMask(_ modifiers: UInt32, for family: ShortcutFamily) -> String? {
        let navigate = family == .navigate ? modifiers : modifierMask(for: .navigate)
        let arrange = family == .arrange ? modifiers : modifierMask(for: .arrange)
        guard let message = Self.familyValidationMessage(navigate: navigate, arrange: arrange) else {
            familyModifiers[family.rawValue] = modifiers
            return nil
        }
        return message
    }

    @discardableResult
    mutating func resetModifierMask(for family: ShortcutFamily) -> String? {
        setModifierMask(family.defaultModifiers, for: family)
    }

    static func familyValidationMessage(navigate: UInt32, arrange: UInt32) -> String? {
        let supported = UInt32(controlKey | optionKey | shiftKey | cmdKey)
        let required = UInt32(controlKey | optionKey | cmdKey)
        func valid(_ modifiers: UInt32) -> Bool {
            modifiers & ~supported == 0 &&
                modifiers.nonzeroBitCount >= 2 &&
                modifiers & required != 0
        }
        guard valid(navigate), valid(arrange) else {
            return "Use at least two of Control, Option, Shift, and Command, including Control, Option, or Command."
        }
        guard navigate != arrange else {
            return "Navigate and Arrange must use different modifier combinations."
        }
        let intersection = navigate & arrange
        guard intersection != navigate, intersection != arrange else {
            return "Navigate and Arrange cannot be subsets of one another."
        }
        return nil
    }

    mutating func reset(_ action: ConfigurableHotKeyAction) {
        keyOverrides.removeValue(forKey: action.rawValue)
        disabledActions.remove(action.rawValue)
    }

    mutating func resetAll() {
        self = Self()
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
