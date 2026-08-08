import AppKit
import Carbon
import Foundation

final class HotKeyManager {
    private enum Action {
        case command(WindowManagerCommand)
        case radialMenu

        var diagnosticFields: [String: String] {
            switch self {
            case let .command(command): command.diagnosticFields
            case .radialMenu: ["action": "open-radial-menu"]
            }
        }
    }

    private let dispatcher: WindowManagerCommandDispatcher
    private let diagnostics: DiagnosticLogger
    private let radialMenuTrigger: (RadialMenuTriggerInputEvent) -> Void
    private var eventHandler: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef] = []
    private var actions: [UInt32: Action] = [:]
    private var registeredChords = Set<HotKeyChord>()

    init(
        dispatcher: WindowManagerCommandDispatcher,
        diagnostics: DiagnosticLogger = .disabled,
        radialMenuTrigger: @escaping (RadialMenuTriggerInputEvent) -> Void = { _ in }
    ) {
        self.dispatcher = dispatcher
        self.diagnostics = diagnostics
        self.radialMenuTrigger = radialMenuTrigger
        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            ),
        ]
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                return manager.handle(event: event)
            },
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    deinit {
        unregisterAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    func suspendRegistration() {
        unregisterAll()
    }

    func register(
        workspaces: [WorkspaceDefinition],
        hotKeyConfiguration: HotKeyConfiguration = HotKeyConfiguration(),
        radialMenuEnabled: Bool = false
    ) {
        unregisterAll()
        var identifier: UInt32 = 1

        for workspace in workspaces {
            guard let keyCode = Self.keyCodes[workspace.key.lowercased()] else { continue }
            add(
                id: &identifier,
                chord: HotKeyChord(keyCode: keyCode, modifiers: UInt32(controlKey | optionKey)),
                action: .command(.switchWorkspace(workspace.id))
            )
            add(
                id: &identifier,
                chord: HotKeyChord(keyCode: keyCode, modifiers: UInt32(optionKey | cmdKey)),
                action: .command(.moveFocusedWindow(workspace.id))
            )
        }

        for action in ConfigurableHotKeyAction.allCases {
            if action == .commandWheel {
                if radialMenuEnabled {
                    add(
                        id: &identifier,
                        chord: hotKeyConfiguration.chord(for: action),
                        action: .radialMenu
                    )
                }
            } else if let command = action.command {
                add(
                    id: &identifier,
                    chord: hotKeyConfiguration.chord(for: action),
                    action: .command(command)
                )
            }
        }
    }

    static func configurableShortcutConflict(
        action: ConfigurableHotKeyAction,
        chord: HotKeyChord,
        configuration: HotKeyConfiguration,
        workspaces: [WorkspaceDefinition]
    ) -> String? {
        if let validation = shortcutValidationMessage(chord) { return validation }
        if let other = ConfigurableHotKeyAction.allCases.first(where: {
            $0 != action && configuration.chord(for: $0) == chord
        }) {
            return "That shortcut is already used by \(other.title)."
        }
        return workspaceShortcutConflict(chord, workspaces: workspaces)
    }

    static func shortcutValidationMessage(_ chord: HotKeyChord) -> String? {
        let required = UInt32(controlKey | optionKey | cmdKey)
        guard chord.modifiers & required != 0 else {
            return "Use Control, Option, or Command so normal typing is never captured globally."
        }
        return nil
    }

    static func recordedChord(from event: NSEvent) -> HotKeyChord? {
        let modifierOnlyKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        guard !modifierOnlyKeyCodes.contains(event.keyCode) else { return nil }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        return HotKeyChord(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }

    private static func workspaceShortcutConflict(
        _ chord: HotKeyChord,
        workspaces: [WorkspaceDefinition]
    ) -> String? {
        for workspace in workspaces {
            guard let keyCode = keyCodes[workspace.key.lowercased()] else { continue }
            if chord == HotKeyChord(keyCode: keyCode, modifiers: UInt32(controlKey | optionKey)) {
                return "That shortcut switches to workspace \(workspace.name)."
            }
            if chord == HotKeyChord(keyCode: keyCode, modifiers: UInt32(optionKey | cmdKey)) {
                return "That shortcut moves a window to workspace \(workspace.name)."
            }
        }
        return nil
    }

    private func add(id: inout UInt32, chord: HotKeyChord, action: Action) {
        guard registeredChords.insert(chord).inserted else {
            diagnostics.log(
                category: "hotkey",
                event: "registration-skipped",
                fields: action.diagnosticFields.merging(["reason": "internal-conflict"]) { _, new in new }
            )
            id += 1
            return
        }
        let hotKeyID = EventHotKeyID(signature: OSType(0x574D4752), id: id) // WMGR
        var reference: EventHotKeyRef?
        let result = RegisterEventHotKey(
            chord.keyCode,
            chord.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if result == noErr, let reference {
            hotKeys.append(reference)
            actions[id] = action
        } else {
            diagnostics.log(
                category: "hotkey",
                event: "registration-failed",
                fields: action.diagnosticFields.merging(["status": String(result)]) { _, new in new }
            )
        }
        id += 1
    }

    private func unregisterAll() {
        for hotKey in hotKeys { UnregisterEventHotKey(hotKey) }
        hotKeys.removeAll()
        actions.removeAll()
        registeredChords.removeAll()
    }

    private func handle(event: EventRef) -> OSStatus {
        var identifier = EventHotKeyID()
        let result = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &identifier
        )
        guard result == noErr, let action = actions[identifier.id] else { return result }
        let eventKind = GetEventKind(event)
        if case .command = action, !Self.shouldDispatchCommand(forEventKind: eventKind) {
            return noErr
        }
        let correlation = diagnostics.makeCorrelationID()
        diagnostics.log(
            category: "hotkey",
            event: "received",
            correlation: correlation,
            fields: action.diagnosticFields
        )
        switch action {
        case let .command(command):
            dispatcher.dispatch(command, source: .hotkey, correlationID: correlation)
        case .radialMenu:
            if let input = Self.radialTriggerInput(forEventKind: eventKind) {
                radialMenuTrigger(input)
            }
        }
        return noErr
    }

    static func shouldDispatchCommand(forEventKind eventKind: UInt32) -> Bool {
        eventKind == UInt32(kEventHotKeyPressed)
    }

    static func radialTriggerInput(forEventKind eventKind: UInt32) -> RadialMenuTriggerInputEvent? {
        switch eventKind {
        case UInt32(kEventHotKeyPressed): .pressed
        case UInt32(kEventHotKeyReleased): .released
        default: nil
        }
    }

    static let toggleFloatingKeyCode: UInt32 = 3
    static let toggleFloatingModifiers = UInt32(controlKey | optionKey)
    static let accordionKeyCode: UInt32 = 43
    static let tiledKeyCode: UInt32 = 47

    static let directionalFocusKeyCodes: [(WindowDirection, UInt32)] = [
        (.left, 4), (.down, 38), (.up, 40), (.right, 37),
    ]
    static let directionalMoveKeyCodes: [(WindowDirection, UInt32)] = [
        (.left, 123), (.down, 125), (.up, 126), (.right, 124),
    ]
    static let moveWorkspaceDisplayChord = HotKeyChord(
        keyCode: 48,
        modifiers: UInt32(optionKey | shiftKey)
    )

    static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
        "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37,
        "j": 38, "k": 40, "\\": 42, "n": 45, "m": 46, "space": 49,
    ]
}
