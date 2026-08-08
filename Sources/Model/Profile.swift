import Foundation
import Darwin

struct ProfileDisplayRole: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

struct WindowManagerProfile: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var workspaces: [WorkspaceDefinition]
    var displayMode: MultiDisplayMode
    var displayRoles: [ProfileDisplayRole]
    var workspaceRoleAssignments: [UUID: UUID]
    var appRules: [AppRule]

    init(
        id: UUID = UUID(),
        name: String,
        workspaces: [WorkspaceDefinition],
        displayMode: MultiDisplayMode,
        displayRoles: [ProfileDisplayRole],
        workspaceRoleAssignments: [UUID: UUID],
        appRules: [AppRule]
    ) {
        self.id = id
        self.name = name
        self.workspaces = workspaces
        self.displayMode = displayMode
        self.displayRoles = displayRoles
        self.workspaceRoleAssignments = workspaceRoleAssignments
        self.appRules = appRules
    }

    func cloned(
        id newProfileID: UUID = UUID(),
        name newName: String,
        makeUUID: () -> UUID = UUID.init
    ) -> WindowManagerProfile {
        let workspaceIDMap = Dictionary(uniqueKeysWithValues: workspaces.map { ($0.id, makeUUID()) })
        let roleIDMap = Dictionary(uniqueKeysWithValues: displayRoles.map { ($0.id, makeUUID()) })
        let clonedWorkspaces = workspaces.compactMap { workspace -> WorkspaceDefinition? in
            guard let id = workspaceIDMap[workspace.id] else { return nil }
            return WorkspaceDefinition(
                id: id,
                name: workspace.name,
                key: workspace.key,
                layout: workspace.layout,
                layoutConfiguration: workspace.layoutConfiguration
            )
        }
        let clonedRoles = displayRoles.compactMap { role -> ProfileDisplayRole? in
            roleIDMap[role.id].map { ProfileDisplayRole(id: $0, name: role.name) }
        }
        let clonedAssignments: [UUID: UUID] = Dictionary(
            uniqueKeysWithValues: workspaceRoleAssignments.compactMap {
            workspaceID, roleID in
            guard let clonedWorkspaceID = workspaceIDMap[workspaceID],
                  let clonedRoleID = roleIDMap[roleID]
            else { return nil }
            return (clonedWorkspaceID, clonedRoleID)
            }
        )
        let clonedRules = appRules.map { rule -> AppRule in
            var clone = rule
            clone.assignedWorkspaceID = rule.assignedWorkspaceID.flatMap { workspaceIDMap[$0] }
            return clone
        }
        return WindowManagerProfile(
            id: newProfileID,
            name: newName,
            workspaces: clonedWorkspaces,
            displayMode: displayMode,
            displayRoles: clonedRoles,
            workspaceRoleAssignments: clonedAssignments,
            appRules: clonedRules
        )
    }

    func normalized() -> WindowManagerProfile? {
        guard !workspaces.isEmpty else { return nil }
        let workspaceIDs = Set(workspaces.map(\.id))
        let roles = Self.uniqueByID(displayRoles)
        guard !roles.isEmpty else { return nil }
        let roleIDs = Set(roles.map(\.id))
        let assignments = workspaceRoleAssignments.filter {
            workspaceIDs.contains($0.key) && roleIDs.contains($0.value)
        }
        let rules = Self.uniqueAppRules(appRules).map { rule -> AppRule in
            var normalized = rule
            if let workspaceID = normalized.assignedWorkspaceID,
               !workspaceIDs.contains(workspaceID) {
                normalized.assignedWorkspaceID = nil
            }
            return normalized
        }
        var seenWorkspaceIDs = Set<UUID>()
        let uniqueWorkspaces = workspaces.filter { seenWorkspaceIDs.insert($0.id).inserted }
        guard !uniqueWorkspaces.isEmpty else { return nil }
        return WindowManagerProfile(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Profile" : name,
            workspaces: uniqueWorkspaces,
            displayMode: displayMode,
            displayRoles: roles,
            workspaceRoleAssignments: assignments,
            appRules: rules
        )
    }

    private static func uniqueByID(_ values: [ProfileDisplayRole]) -> [ProfileDisplayRole] {
        var seen = Set<UUID>()
        return values.filter { seen.insert($0.id).inserted }
    }

    private static func uniqueAppRules(_ values: [AppRule]) -> [AppRule] {
        var seen = Set<String>()
        return values.filter { rule in
            !rule.bundleIdentifier.isEmpty && seen.insert(rule.bundleIdentifier.lowercased()).inserted
        }
    }
}

struct ProfileLibrary: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    var profiles: [WindowManagerProfile]

    init(version: Int = currentVersion, profiles: [WindowManagerProfile]) {
        self.version = version
        self.profiles = profiles
    }

    func normalized() -> ProfileLibrary? {
        guard version == Self.currentVersion else { return nil }
        var seen = Set<UUID>()
        let normalizedProfiles = profiles.compactMap { $0.normalized() }.filter {
            seen.insert($0.id).inserted
        }
        guard !normalizedProfiles.isEmpty else { return nil }
        return ProfileLibrary(profiles: normalizedProfiles)
    }
}

struct ProfileRuntimeWorkspaceState: Codable, Equatable, Sendable {
    var currentWorkspaceID: UUID
    var activeWorkspaceIDByRole: [UUID: UUID]
}

struct ExactProfileTrigger: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var profileID: UUID
    var displayPins: [WorkspaceDisplayPin]

    init(
        id: UUID = UUID(),
        name: String,
        profileID: UUID,
        displayPins: [WorkspaceDisplayPin]
    ) {
        self.id = id
        self.name = name
        self.profileID = profileID
        self.displayPins = displayPins
    }
}

struct ProfileLocalState: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    var activeProfileID: UUID
    var manualPinnedProfileID: UUID?
    var defaultProfileID: UUID
    var dockedProfileID: UUID?
    var undockedProfileID: UUID?
    var exactTriggers: [ExactProfileTrigger]
    var roleBindings: [UUID: WorkspaceDisplayPin]
    var runtimeWorkspaceStates: [UUID: ProfileRuntimeWorkspaceState]

    init(
        version: Int = currentVersion,
        activeProfileID: UUID,
        manualPinnedProfileID: UUID? = nil,
        defaultProfileID: UUID,
        dockedProfileID: UUID? = nil,
        undockedProfileID: UUID? = nil,
        exactTriggers: [ExactProfileTrigger] = [],
        roleBindings: [UUID: WorkspaceDisplayPin] = [:],
        runtimeWorkspaceStates: [UUID: ProfileRuntimeWorkspaceState] = [:]
    ) {
        self.version = version
        self.activeProfileID = activeProfileID
        self.manualPinnedProfileID = manualPinnedProfileID
        self.defaultProfileID = defaultProfileID
        self.dockedProfileID = dockedProfileID
        self.undockedProfileID = undockedProfileID
        self.exactTriggers = exactTriggers
        self.roleBindings = roleBindings
        self.runtimeWorkspaceStates = runtimeWorkspaceStates
    }

    mutating func removeReferences(to profileID: UUID, validProfileIDs: Set<UUID>) {
        exactTriggers.removeAll { $0.profileID == profileID || !validProfileIDs.contains($0.profileID) }
        runtimeWorkspaceStates.removeValue(forKey: profileID)
        if manualPinnedProfileID == profileID { manualPinnedProfileID = nil }
        if dockedProfileID == profileID { dockedProfileID = nil }
        if undockedProfileID == profileID { undockedProfileID = nil }
    }

    mutating func normalize(validProfiles: [WindowManagerProfile]) {
        let validIDs = Set(validProfiles.map(\.id))
        let fallback = validProfiles.first!.id
        if !validIDs.contains(defaultProfileID) { defaultProfileID = fallback }
        if !validIDs.contains(activeProfileID) { activeProfileID = defaultProfileID }
        if let manualPinnedProfileID, !validIDs.contains(manualPinnedProfileID) {
            self.manualPinnedProfileID = nil
        }
        if let dockedProfileID, !validIDs.contains(dockedProfileID) { self.dockedProfileID = nil }
        if let undockedProfileID, !validIDs.contains(undockedProfileID) { self.undockedProfileID = nil }
        exactTriggers.removeAll { !validIDs.contains($0.profileID) || $0.displayPins.isEmpty }
        runtimeWorkspaceStates = Dictionary(uniqueKeysWithValues: runtimeWorkspaceStates.compactMap {
            profileID, runtime in
            guard let profile = validProfiles.first(where: { $0.id == profileID }) else { return nil }
            let validWorkspaceIDs = Set(profile.workspaces.map(\.id))
            let validRoleIDs = Set(profile.displayRoles.map(\.id))
            let currentWorkspaceID = validWorkspaceIDs.contains(runtime.currentWorkspaceID)
                ? runtime.currentWorkspaceID : profile.workspaces[0].id
            let activeByRole = runtime.activeWorkspaceIDByRole.filter {
                validRoleIDs.contains($0.key) && validWorkspaceIDs.contains($0.value)
            }
            return (
                profileID,
                ProfileRuntimeWorkspaceState(
                    currentWorkspaceID: currentWorkspaceID,
                    activeWorkspaceIDByRole: activeByRole
                )
            )
        })
        let validRoleIDs = Set(validProfiles.flatMap { $0.displayRoles.map(\.id) })
        roleBindings = roleBindings.filter { validRoleIDs.contains($0.key) }
    }
}

enum ProfileDockState: String, Equatable, Sendable {
    case docked
    case undocked
    case notApplicable

    static func resolve(isPortableMac: Bool, displays: [DisplaySnapshot]) -> ProfileDockState {
        guard isPortableMac, !displays.isEmpty else { return .notApplicable }
        if displays.contains(where: { !$0.isBuiltIn }) { return .docked }
        if displays.count == 1, displays[0].isBuiltIn { return .undocked }
        return .notApplicable
    }
}

enum ProfileSelectionReason: Equatable, Sendable {
    case manualPin
    case exactTopology(UUID)
    case docked
    case undocked
    case localDefault
    case safeFallback

    var diagnosticValue: String {
        switch self {
        case .manualPin: "manual-pin"
        case .exactTopology: "exact-topology"
        case .docked: "generic-docked"
        case .undocked: "generic-undocked"
        case .localDefault: "local-default"
        case .safeFallback: "safe-fallback"
        }
    }

    var title: String {
        switch self {
        case .manualPin: "Manually selected"
        case .exactTopology: "Automatic · exact display setup"
        case .docked: "Automatic · docked"
        case .undocked: "Automatic · undocked"
        case .localDefault: "Automatic · this Mac's default"
        case .safeFallback: "Automatic · safe fallback"
        }
    }
}

struct ProfileSelection: Equatable, Sendable {
    let profileID: UUID
    let reason: ProfileSelectionReason
}

enum ProfileTriggerResolver {
    static func resolve(
        profiles: [WindowManagerProfile],
        localState: ProfileLocalState,
        displays: [DisplaySnapshot],
        isPortableMac: Bool
    ) -> ProfileSelection {
        let validIDs = Set(profiles.map(\.id))
        if let manual = localState.manualPinnedProfileID, validIDs.contains(manual) {
            return ProfileSelection(profileID: manual, reason: .manualPin)
        }
        for trigger in localState.exactTriggers where validIDs.contains(trigger.profileID) {
            if exactTopologyMatches(trigger.displayPins, displays: displays) {
                return ProfileSelection(
                    profileID: trigger.profileID,
                    reason: .exactTopology(trigger.id)
                )
            }
        }
        switch ProfileDockState.resolve(isPortableMac: isPortableMac, displays: displays) {
        case .docked:
            if let id = localState.dockedProfileID, validIDs.contains(id) {
                return ProfileSelection(profileID: id, reason: .docked)
            }
        case .undocked:
            if let id = localState.undockedProfileID, validIDs.contains(id) {
                return ProfileSelection(profileID: id, reason: .undocked)
            }
        case .notApplicable:
            break
        }
        if validIDs.contains(localState.defaultProfileID) {
            return ProfileSelection(profileID: localState.defaultProfileID, reason: .localDefault)
        }
        return ProfileSelection(profileID: profiles[0].id, reason: .safeFallback)
    }

    static func exactTopologyMatches(
        _ pins: [WorkspaceDisplayPin],
        displays: [DisplaySnapshot]
    ) -> Bool {
        guard !pins.isEmpty, pins.count == displays.count else { return false }
        var usedDisplays = Set<String>()
        for pin in pins {
            guard let identifier = DisplayIdentityResolver.resolve(pin, among: displays).displayIdentifier,
                  usedDisplays.insert(identifier).inserted
            else { return false }
        }
        return usedDisplays.count == displays.count
    }
}

struct ProfileRoleResolution: Equatable, Sendable {
    let workspaceDisplayHomes: [UUID: String]
    let resolutionByRole: [UUID: DisplayPinResolution?]
}

enum ProfileRoleBindingResolver {
    static func resolve(
        profile: WindowManagerProfile,
        roleBindings: [UUID: WorkspaceDisplayPin],
        displays: [DisplaySnapshot]
    ) -> ProfileRoleResolution {
        var homes: [UUID: String] = [:]
        var resolutions: [UUID: DisplayPinResolution?] = [:]
        for role in profile.displayRoles {
            guard let pin = roleBindings[role.id] else {
                resolutions[role.id] = .none
                continue
            }
            let resolution = DisplayIdentityResolver.resolve(pin, among: displays)
            resolutions[role.id] = resolution
            let logicalHome = resolution.displayIdentifier ?? pin.lastKnownIdentifier
            for (workspaceID, roleID) in profile.workspaceRoleAssignments where roleID == role.id {
                homes[workspaceID] = logicalHome
            }
        }
        return ProfileRoleResolution(
            workspaceDisplayHomes: homes,
            resolutionByRole: resolutions
        )
    }
}

struct ProfileEngineConfiguration: Equatable, Sendable {
    let profileID: UUID
    let profileName: String
    let workspaces: [WorkspaceDefinition]
    let displayMode: MultiDisplayMode
    let workspaceDisplayAssignments: [UUID: String]
    let appRules: [AppRule]
    let preferredCurrentWorkspaceID: UUID?
    let preferredActiveWorkspaceIDByDisplay: [String: UUID]
    let selectionReason: ProfileSelectionReason
}

struct ProfileActivationRequest: Equatable, Sendable {
    let generation: UInt64
    let configuration: ProfileEngineConfiguration
}

final class ProfileTransitionGenerationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var latestGeneration: UInt64 = 0

    func register(_ generation: UInt64) {
        lock.lock()
        latestGeneration = max(latestGeneration, generation)
        lock.unlock()
    }

    func isCurrent(_ generation: UInt64) -> Bool {
        lock.lock()
        let result = latestGeneration == generation
        lock.unlock()
        return result
    }
}

struct LegacyProfileConfiguration: Codable, Equatable, Sendable {
    let workspaces: [WorkspaceDefinition]
    let displayMode: MultiDisplayMode
    let workspaceDisplayPins: [UUID: WorkspaceDisplayPin]
    let appRules: [AppRule]
}

struct InitialProfileConversion: Equatable, Sendable {
    let library: ProfileLibrary
    let localState: ProfileLocalState
}

enum InitialProfileConverter {
    static func convert(
        legacy: LegacyProfileConfiguration,
        connectedDisplays: [DisplaySnapshot],
        profileID: UUID = UUID(),
        makeUUID: () -> UUID = UUID.init
    ) -> InitialProfileConversion {
        var roles: [ProfileDisplayRole] = []
        var bindings: [UUID: WorkspaceDisplayPin] = [:]
        var roleIDByDisplayIdentifier: [String: UUID] = [:]
        var usedNames = Set<String>()

        func uniqueRoleName(_ proposed: String) -> String {
            let base = proposed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Display" : proposed
            var candidate = base
            var suffix = 2
            while !usedNames.insert(candidate.lowercased()).inserted {
                candidate = "\(base) \(suffix)"
                suffix += 1
            }
            return candidate
        }

        func addRole(identifier: String, fingerprint: DisplayFingerprint?, name: String) -> UUID {
            if let existing = roleIDByDisplayIdentifier[identifier] { return existing }
            let roleID = makeUUID()
            roles.append(ProfileDisplayRole(id: roleID, name: uniqueRoleName(name)))
            bindings[roleID] = WorkspaceDisplayPin(
                lastKnownIdentifier: identifier,
                fingerprint: fingerprint
            )
            roleIDByDisplayIdentifier[identifier] = roleID
            return roleID
        }

        for display in connectedDisplays.sorted(by: {
            if $0.isMain != $1.isMain { return $0.isMain }
            return $0.identifier < $1.identifier
        }) {
            _ = addRole(
                identifier: display.identifier,
                fingerprint: display.fingerprint,
                name: display.isMain ? "Primary Display" : display.name
            )
        }
        for pin in legacy.workspaceDisplayPins.values.sorted(by: {
            $0.lastKnownIdentifier < $1.lastKnownIdentifier
        }) where roleIDByDisplayIdentifier[pin.lastKnownIdentifier] == nil {
            _ = addRole(
                identifier: pin.lastKnownIdentifier,
                fingerprint: pin.fingerprint,
                name: pin.fingerprint?.displayName ?? "Disconnected Display"
            )
        }
        if roles.isEmpty {
            roles = [ProfileDisplayRole(id: makeUUID(), name: "Primary Display")]
        }
        let mainRoleID = connectedDisplays.first(where: \.isMain)
            .flatMap { roleIDByDisplayIdentifier[$0.identifier] }
            ?? roles[0].id
        let assignments = Dictionary(uniqueKeysWithValues: legacy.workspaces.map { workspace in
            let roleID = legacy.workspaceDisplayPins[workspace.id]
                .flatMap { roleIDByDisplayIdentifier[$0.lastKnownIdentifier] }
                ?? mainRoleID
            return (workspace.id, roleID)
        })
        let profile = WindowManagerProfile(
            id: profileID,
            name: "Current Setup",
            workspaces: legacy.workspaces.isEmpty ? WorkspaceDefinition.defaults : legacy.workspaces,
            displayMode: legacy.displayMode,
            displayRoles: roles,
            workspaceRoleAssignments: assignments,
            appRules: legacy.appRules
        ).normalized()!
        let localState = ProfileLocalState(
            activeProfileID: profileID,
            defaultProfileID: profileID,
            roleBindings: bindings
        )
        return InitialProfileConversion(
            library: ProfileLibrary(profiles: [profile]),
            localState: localState
        )
    }
}

enum MachineKind {
    static func isPortableMac() -> Bool {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 1 else { return false }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return false }
        return String(cString: buffer).hasPrefix("MacBook")
    }
}
