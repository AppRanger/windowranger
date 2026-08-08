import AppKit
import Carbon
import Foundation

struct ShortcutBindingOwner: Hashable, Sendable, Identifiable {
    enum Kind: String, Hashable, Sendable {
        case globalCommand
        case commandWheel
        case workspaceSwitch
        case workspaceMove
    }

    let id: String
    let title: String
    let kind: Kind
    let configurableAction: ConfigurableHotKeyAction?
    let workspaceID: UUID?

    static func global(_ action: ConfigurableHotKeyAction) -> ShortcutBindingOwner {
        ShortcutBindingOwner(
            id: "global:\(action.rawValue)",
            title: action.title,
            kind: action == .commandWheel ? .commandWheel : .globalCommand,
            configurableAction: action,
            workspaceID: nil
        )
    }

    static func workspaceSwitch(_ workspace: WorkspaceDefinition) -> ShortcutBindingOwner {
        ShortcutBindingOwner(
            id: "workspace:\(workspace.id.uuidString):switch",
            title: "Switch to workspace \(workspace.name)",
            kind: .workspaceSwitch,
            configurableAction: nil,
            workspaceID: workspace.id
        )
    }

    static func workspaceMove(_ workspace: WorkspaceDefinition) -> ShortcutBindingOwner {
        ShortcutBindingOwner(
            id: "workspace:\(workspace.id.uuidString):move",
            title: "Move window to workspace \(workspace.name)",
            kind: .workspaceMove,
            configurableAction: nil,
            workspaceID: workspace.id
        )
    }
}

struct ShortcutBindingDefinition: Equatable, Sendable {
    let owner: ShortcutBindingOwner
    let chord: HotKeyChord
}

struct ShortcutConfigurationIssue: Equatable, Sendable, Identifiable {
    enum Kind: String, Equatable, Sendable {
        case invalid
        case duplicate
    }

    let kind: Kind
    let chord: HotKeyChord?
    let owners: [ShortcutBindingOwner]
    let reason: String

    var id: String {
        let ownerIDs = owners.map(\.id).sorted().joined(separator: ",")
        let chordID = chord.map { "\($0.keyCode):\($0.modifiers)" } ?? "none"
        return "\(kind.rawValue):\(chordID):\(ownerIDs)"
    }

    var message: String {
        let names = Self.joinedTitles(owners.map(\.title))
        switch kind {
        case .invalid:
            return "\(names) cannot use \(chord?.title ?? "that workspace key"): \(reason)"
        case .duplicate:
            return "\(names) all use \(chord?.title ?? "the same shortcut"). No command owns this shortcut until it is repaired."
        }
    }

    private static func joinedTitles(_ titles: [String]) -> String {
        switch titles.count {
        case 0: return "This command"
        case 1: return titles[0]
        case 2: return "\(titles[0]) and \(titles[1])"
        default: return titles.dropLast().joined(separator: ", ") + ", and " + titles.last!
        }
    }
}

struct ShortcutConfigurationReport: Equatable, Sendable {
    let eligibleBindings: [ShortcutBindingDefinition]
    let issues: [ShortcutConfigurationIssue]

    func issues(for owner: ShortcutBindingOwner) -> [ShortcutConfigurationIssue] {
        issues.filter { $0.owners.contains(owner) }
    }

    func issues(for action: ConfigurableHotKeyAction) -> [ShortcutConfigurationIssue] {
        issues(for: .global(action))
    }

    func issues(forWorkspace workspaceID: UUID) -> [ShortcutConfigurationIssue] {
        issues.filter { issue in issue.owners.contains { $0.workspaceID == workspaceID } }
    }
}

enum ShortcutConflictModel {
    static let modifierOnlyKeyCodes: Set<UInt32> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
    static let supportedModifierMask = UInt32(controlKey | optionKey | shiftKey | cmdKey)
    static let requiredModifierMask = UInt32(controlKey | optionKey | cmdKey)

    static func evaluate(
        configuration: HotKeyConfiguration,
        workspaces: [WorkspaceDefinition],
        includeCommandWheel: Bool = true
    ) -> ShortcutConfigurationReport {
        var validBindings: [ShortcutBindingDefinition] = []
        var issues: [ShortcutConfigurationIssue] = []

        for workspace in workspaces {
            let owners = [
                ShortcutBindingOwner.workspaceSwitch(workspace),
                ShortcutBindingOwner.workspaceMove(workspace),
            ]
            guard let keyCode = HotKeyManager.keyCodes[workspace.key.lowercased()] else {
                issues.append(contentsOf: owners.map { owner in
                    ShortcutConfigurationIssue(
                        kind: .invalid,
                        chord: nil,
                        owners: [owner],
                        reason: "choose one supported workspace key in Workspaces settings."
                    )
                })
                continue
            }
            validBindings.append(ShortcutBindingDefinition(
                owner: owners[0],
                chord: HotKeyChord(
                    keyCode: keyCode,
                    modifiers: UInt32(controlKey | optionKey)
                )
            ))
            validBindings.append(ShortcutBindingDefinition(
                owner: owners[1],
                chord: HotKeyChord(
                    keyCode: keyCode,
                    modifiers: UInt32(optionKey | cmdKey)
                )
            ))
        }

        for action in ConfigurableHotKeyAction.allCases where includeCommandWheel || action != .commandWheel {
            let binding = ShortcutBindingDefinition(
                owner: .global(action),
                chord: configuration.chord(for: action)
            )
            if let reason = validationMessage(binding.chord) {
                issues.append(ShortcutConfigurationIssue(
                    kind: .invalid,
                    chord: binding.chord,
                    owners: [binding.owner],
                    reason: reason
                ))
            } else {
                validBindings.append(binding)
            }
        }

        let grouped = Dictionary(grouping: validBindings, by: \.chord)
        let duplicateChords = Set(grouped.compactMap { chord, bindings in
            bindings.count > 1 ? chord : nil
        })
        for chord in duplicateChords.sorted(by: chordSort) {
            let owners = grouped[chord, default: []].map(\.owner).sorted { $0.id < $1.id }
            issues.append(ShortcutConfigurationIssue(
                kind: .duplicate,
                chord: chord,
                owners: owners,
                reason: "choose a unique shortcut for each command."
            ))
        }

        return ShortcutConfigurationReport(
            eligibleBindings: validBindings.filter { !duplicateChords.contains($0.chord) },
            issues: issues.sorted { $0.id < $1.id }
        )
    }

    static func validationMessage(_ chord: HotKeyChord) -> String? {
        guard chord.keyCode <= 127, !modifierOnlyKeyCodes.contains(chord.keyCode) else {
            return "the saved key is not supported by WindowManager's global shortcut recorder."
        }
        guard chord.modifiers & ~supportedModifierMask == 0 else {
            return "the saved modifier combination is not supported."
        }
        guard chord.modifiers & requiredModifierMask != 0 else {
            return "use Control, Option, or Command so normal typing is never captured globally."
        }
        return nil
    }

    private static func chordSort(_ lhs: HotKeyChord, _ rhs: HotKeyChord) -> Bool {
        lhs.modifiers == rhs.modifiers ? lhs.keyCode < rhs.keyCode : lhs.modifiers < rhs.modifiers
    }
}

struct HotKeyRegistrationToken: Hashable, Sendable {
    let id: UUID

    init(id: UUID = UUID()) { self.id = id }
}

struct HotKeyRegistrationFailure: Error, Equatable, Sendable {
    let status: OSStatus
}

protocol GlobalHotKeyRegistrationService: AnyObject {
    func register(
        chord: HotKeyChord,
        identifier: UInt32
    ) -> Result<HotKeyRegistrationToken, HotKeyRegistrationFailure>
    func unregister(_ token: HotKeyRegistrationToken) -> OSStatus
}

final class CarbonGlobalHotKeyRegistrationService: GlobalHotKeyRegistrationService {
    private var references: [HotKeyRegistrationToken: EventHotKeyRef] = [:]

    func register(
        chord: HotKeyChord,
        identifier: UInt32
    ) -> Result<HotKeyRegistrationToken, HotKeyRegistrationFailure> {
        let hotKeyID = EventHotKeyID(signature: OSType(0x574D4752), id: identifier) // WMGR
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            chord.keyCode,
            chord.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else {
            return .failure(HotKeyRegistrationFailure(status: status))
        }
        let token = HotKeyRegistrationToken()
        references[token] = reference
        return .success(token)
    }

    func unregister(_ token: HotKeyRegistrationToken) -> OSStatus {
        guard let reference = references[token] else { return noErr }
        let status = UnregisterEventHotKey(reference)
        if status == noErr { references.removeValue(forKey: token) }
        return status
    }
}

struct HotKeyRuntimeIssue: Equatable, Sendable, Identifiable {
    let owner: ShortcutBindingOwner
    let chord: HotKeyChord
    let status: OSStatus

    var id: String { owner.id }
    var message: String {
        "macOS could not register \(chord.title) for \(owner.title) (status \(status)). Another app may own it; choose a different shortcut or reset this command."
    }
}

struct HotKeyRegistrationReport: Equatable, Sendable {
    let configurationIssues: [ShortcutConfigurationIssue]
    let runtimeIssues: [HotKeyRuntimeIssue]
    let registeredOwners: [ShortcutBindingOwner]

    static let empty = HotKeyRegistrationReport(
        configurationIssues: [],
        runtimeIssues: [],
        registeredOwners: []
    )
}

final class HotKeyManager {
    typealias EventHandlerInstaller = (
        _ userData: UnsafeMutableRawPointer,
        _ eventHandler: UnsafeMutablePointer<EventHandlerRef?>
    ) -> OSStatus

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
    private let registrationService: GlobalHotKeyRegistrationService
    private var eventHandler: EventHandlerRef?
    private var eventHandlerInstallationFailure: OSStatus?
    private var hotKeys: [(
        token: HotKeyRegistrationToken,
        identifier: UInt32,
        binding: ShortcutBindingDefinition
    )] = []
    private var actions: [UInt32: Action] = [:]
    private var nextRegistrationIdentifier: UInt32 = 1

    init(
        dispatcher: WindowManagerCommandDispatcher,
        diagnostics: DiagnosticLogger = .disabled,
        radialMenuTrigger: @escaping (RadialMenuTriggerInputEvent) -> Void = { _ in },
        registrationService: GlobalHotKeyRegistrationService = CarbonGlobalHotKeyRegistrationService(),
        installsEventHandler: Bool = true,
        eventHandlerInstaller: EventHandlerInstaller? = nil
    ) {
        self.dispatcher = dispatcher
        self.diagnostics = diagnostics
        self.radialMenuTrigger = radialMenuTrigger
        self.registrationService = registrationService
        guard installsEventHandler else { return }
        let installer = eventHandlerInstaller ?? Self.installCarbonEventHandler
        let status = installer(Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        if status != noErr || eventHandler == nil {
            let failureStatus: OSStatus = status == noErr ? OSStatus(paramErr) : status
            eventHandlerInstallationFailure = failureStatus
            diagnostics.log(
                category: "hotkey",
                event: "event-handler-installation-failed",
                fields: ["status": String(failureStatus)]
            )
        }
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
    ) -> HotKeyRegistrationReport {
        unregisterAll()
        let configuration = ShortcutConflictModel.evaluate(
            configuration: hotKeyConfiguration,
            workspaces: workspaces,
            includeCommandWheel: radialMenuEnabled
        )
        for issue in configuration.issues {
            diagnostics.log(
                category: "hotkey",
                event: "registration-skipped",
                fields: [
                    "reason": issue.kind.rawValue,
                    "owners": issue.owners.map(\.id).joined(separator: ","),
                    "chord": issue.chord?.title ?? "none",
                ]
            )
        }

        if let status = eventHandlerInstallationFailure {
            let runtimeIssues = configuration.eligibleBindings.map {
                HotKeyRuntimeIssue(owner: $0.owner, chord: $0.chord, status: status)
            }
            return HotKeyRegistrationReport(
                configurationIssues: configuration.issues,
                runtimeIssues: runtimeIssues,
                registeredOwners: []
            )
        }

        var runtimeIssues: [HotKeyRuntimeIssue] = []
        var registeredOwners: [ShortcutBindingOwner] = []
        for binding in configuration.eligibleBindings {
            guard let action = action(for: binding.owner) else { continue }
            let identifier = allocateRegistrationIdentifier()
            if let issue = add(id: identifier, binding: binding, action: action) {
                runtimeIssues.append(issue)
            } else {
                registeredOwners.append(binding.owner)
            }
        }
        return HotKeyRegistrationReport(
            configurationIssues: configuration.issues,
            runtimeIssues: runtimeIssues,
            registeredOwners: registeredOwners
        )
    }

    static func configurableShortcutConflict(
        action: ConfigurableHotKeyAction,
        chord: HotKeyChord,
        configuration: HotKeyConfiguration,
        workspaces: [WorkspaceDefinition]
    ) -> String? {
        var proposed = configuration
        proposed.setChord(chord, for: action)
        return ShortcutConflictModel.evaluate(
            configuration: proposed,
            workspaces: workspaces
        ).issues(for: action).first?.message
    }

    static func shortcutValidationMessage(_ chord: HotKeyChord) -> String? {
        ShortcutConflictModel.validationMessage(chord)
    }

    static func recordedChord(from event: NSEvent) -> HotKeyChord? {
        guard !ShortcutConflictModel.modifierOnlyKeyCodes.contains(UInt32(event.keyCode)) else {
            return nil
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        return HotKeyChord(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }

    private func action(for owner: ShortcutBindingOwner) -> Action? {
        switch owner.kind {
        case .commandWheel:
            return .radialMenu
        case .globalCommand:
            return owner.configurableAction?.command.map(Action.command)
        case .workspaceSwitch:
            return owner.workspaceID.map { .command(.switchWorkspace($0)) }
        case .workspaceMove:
            return owner.workspaceID.map { .command(.moveFocusedWindow($0)) }
        }
    }

    private func add(
        id: UInt32,
        binding: ShortcutBindingDefinition,
        action: Action
    ) -> HotKeyRuntimeIssue? {
        switch registrationService.register(chord: binding.chord, identifier: id) {
        case let .success(token):
            hotKeys.append((token, id, binding))
            actions[id] = action
            return nil
        case let .failure(failure):
            diagnostics.log(
                category: "hotkey",
                event: "registration-failed",
                fields: action.diagnosticFields.merging([
                    "owner": binding.owner.id,
                    "chord": binding.chord.title,
                    "status": String(failure.status),
                ]) { _, new in new }
            )
            return HotKeyRuntimeIssue(
                owner: binding.owner,
                chord: binding.chord,
                status: failure.status
            )
        }
    }

    private func unregisterAll() {
        var failedUnregistrations: [(
            token: HotKeyRegistrationToken,
            identifier: UInt32,
            binding: ShortcutBindingDefinition
        )] = []
        for hotKey in hotKeys {
            let status = registrationService.unregister(hotKey.token)
            if status != noErr {
                failedUnregistrations.append(hotKey)
                diagnostics.log(
                    category: "hotkey",
                    event: "unregistration-failed",
                    fields: [
                        "owner": hotKey.binding.owner.id,
                        "chord": hotKey.binding.chord.title,
                        "status": String(status),
                    ]
                )
            }
        }
        // A failed Carbon unregistration may still own its system chord. Keep its token so a
        // later suspend/reconfigure can retry, but remove its action immediately so a stale event
        // can never execute the old command. Registration identifiers are monotonic, preventing a
        // retained stale event from being mistaken for a newly registered command.
        hotKeys = failedUnregistrations
        actions.removeAll()
    }

    private func allocateRegistrationIdentifier() -> UInt32 {
        let identifier = nextRegistrationIdentifier
        nextRegistrationIdentifier &+= 1
        if nextRegistrationIdentifier == 0 { nextRegistrationIdentifier = 1 }
        return identifier
    }

    private static func installCarbonEventHandler(
        userData: UnsafeMutableRawPointer,
        eventHandler: UnsafeMutablePointer<EventHandlerRef?>
    ) -> OSStatus {
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
        return InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, callbackData in
                guard let event, let callbackData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(callbackData)
                    .takeUnretainedValue()
                return manager.handle(event: event)
            },
            eventTypes.count,
            &eventTypes,
            userData,
            eventHandler
        )
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
