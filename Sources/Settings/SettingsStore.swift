import AppKit
import Combine
import Foundation

protocol UbiquitousKeyValueStoring: AnyObject {
    var notificationObject: AnyObject { get }
    func object(forKey aKey: String) -> Any?
    func string(forKey aKey: String) -> String?
    func data(forKey aKey: String) -> Data?
    func set(_ anObject: Any?, forKey aKey: String)
    func removeObject(forKey aKey: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: UbiquitousKeyValueStoring {
    var notificationObject: AnyObject { self }
}

@MainActor
final class SettingsStore: ObservableObject {
    private enum Keys {
        // Profile-backed storage is authoritative. The five legacy keys below are read only by the
        // one-off private-install conversion and are removed after the new library is verified.
        static let legacyWorkspaces = "workspaceDefinitions.v1"
        static let legacyMultiDisplayMode = "multiDisplayMode.v1"
        static let legacyWorkspaceDisplayAssignments = "workspaceDisplayAssignments.v1"
        static let legacyWorkspaceDisplayPins = "workspaceDisplayPins.v2"
        static let legacyAppRules = "appRules.v1"
        static let profileLibrary = "profileLibrary.v1"
        static let profileLocalState = "profileLocalState.v1"
        static let profileConversionBackup = "profileConversionBackup.v1"
        static let profileConversionCompleted = "profileConversionCompleted.v1"

        static let iCloudSync = "iCloudSyncEnabled"
        static let radialMenuEnabled = "radialMenuEnabled.v1"
        // Read once to preserve the pre-recorder three-choice command-wheel shortcut.
        static let radialMenuShortcut = "radialMenuShortcut.v1"
        static let radialMenuActivationStyle = "radialMenuActivationStyle.v1"
        static let radialMenuHoldDelay = "radialMenuHoldDelay.v1"
        static let radialWheelDefinition = "radialWheelDefinition.v1"
        static let hotKeyConfiguration = "hotKeyConfiguration.v1"
        static let menuBarPresentationMode = "menuBarPresentationMode.v1"
        static let focusFollowsMovedWindow = "focusFollowsMovedWindow.v1"
        static let automaticallyUnhideApplications = "automaticallyUnhideApplications.v1"
    }

    @Published private(set) var profiles: [WindowManagerProfile]
    @Published private(set) var localProfileState: ProfileLocalState
    @Published private(set) var activeProfileID: UUID
    @Published private(set) var activeProfileSelectionReason: ProfileSelectionReason
    @Published private(set) var profileActivationRequest: ProfileActivationRequest?

    @Published var workspaces: [WorkspaceDefinition] {
        didSet { activeProfileContentDidChange() }
    }

    @Published var multiDisplayMode: MultiDisplayMode {
        didSet { activeProfileContentDidChange() }
    }

    @Published var appRules: [AppRule] {
        didSet { activeProfileContentDidChange() }
    }

    @Published var iCloudSyncEnabled: Bool {
        didSet {
            guard !isApplyingRemoteChange else { return }
            defaults.set(iCloudSyncEnabled, forKey: Keys.iCloudSync)
            if iCloudSyncEnabled {
                pushToICloud()
                ubiquitousStore?.synchronize()
            }
        }
    }

    @Published var radialMenuEnabled: Bool {
        didSet { persistRadialMenuSettings() }
    }

    @Published var radialMenuActivationStyle: RadialMenuActivationStyle {
        didSet { persistRadialMenuSettings() }
    }

    @Published var radialMenuHoldDelay: TimeInterval {
        didSet {
            let clamped = RadialMenuHoldDelay.clamped(radialMenuHoldDelay)
            if radialMenuHoldDelay != clamped {
                radialMenuHoldDelay = clamped
            } else {
                persistRadialMenuSettings()
            }
        }
    }

    @Published var radialWheelDefinition: RadialWheelDefinition {
        didSet { persistRadialMenuSettings() }
    }

    @Published var hotKeyConfiguration: HotKeyConfiguration {
        didSet { persistHotKeyConfiguration() }
    }

    @Published var menuBarPresentationMode: MenuBarPresentationMode {
        didSet { persistMenuBarPresentationMode() }
    }

    @Published var focusFollowsMovedWindow: Bool {
        didSet { persistFocusFollowsMovedWindow() }
    }

    @Published var automaticallyUnhideApplications: Bool {
        didSet { persistAutomaticallyUnhideApplications() }
    }

    @Published private(set) var workspaceDisplayAssignments: [UUID: String]
    @Published private(set) var workspaceDisplayHomesForEngine: [UUID: String]
    @Published private(set) var connectedDisplays: [DisplaySnapshot]

    private let defaults: UserDefaults
    private let ubiquitousStore: UbiquitousKeyValueStoring?
    private let connectedDisplaysProvider: () -> [DisplaySnapshot]
    private let isPortableMacProvider: () -> Bool
    private let diagnostics: DiagnosticLogger
    private var isApplyingRemoteChange = false
    private(set) var isApplyingProfileActivation = false
    private var profileActivationGeneration: UInt64 = 0
    private var iCloudObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?

    private struct BootstrapResult {
        let library: ProfileLibrary
        let localState: ProfileLocalState
        let convertedLegacyConfiguration: Bool
    }

    init(
        defaults: UserDefaults = .standard,
        ubiquitousStore: UbiquitousKeyValueStoring? = NSUbiquitousKeyValueStore.default,
        connectedDisplaysProvider: @escaping () -> [DisplaySnapshot] = WorkspaceEngine.activeDisplays,
        isPortableMacProvider: @escaping () -> Bool = MachineKind.isPortableMac,
        diagnostics: DiagnosticLogger = .disabled
    ) {
        self.defaults = defaults
        self.ubiquitousStore = ubiquitousStore
        self.connectedDisplaysProvider = connectedDisplaysProvider
        self.isPortableMacProvider = isPortableMacProvider
        self.diagnostics = diagnostics

        let initialDisplays = connectedDisplaysProvider()
        let bootstrap = Self.bootstrapProfiles(defaults: defaults, displays: initialDisplays)
        let initialProfiles = bootstrap.library.profiles
        profiles = initialProfiles
        var initialLocalState = bootstrap.localState
        initialLocalState.normalize(validProfiles: initialProfiles)
        let selection = ProfileTriggerResolver.resolve(
            profiles: initialProfiles,
            localState: initialLocalState,
            displays: initialDisplays,
            isPortableMac: isPortableMacProvider()
        )
        initialLocalState.activeProfileID = selection.profileID
        localProfileState = initialLocalState
        activeProfileID = selection.profileID
        activeProfileSelectionReason = selection.reason
        profileActivationRequest = nil
        let active = initialProfiles.first(where: { $0.id == selection.profileID }) ?? initialProfiles[0]
        workspaces = active.workspaces
        multiDisplayMode = active.displayMode
        appRules = active.appRules
        connectedDisplays = initialDisplays
        workspaceDisplayHomesForEngine = ProfileRoleBindingResolver.resolve(
            profile: active,
            roleBindings: initialLocalState.roleBindings,
            displays: initialDisplays
        ).workspaceDisplayHomes
        workspaceDisplayAssignments = Self.resolvedConnectedWorkspaceAssignments(
            profile: active,
            roleBindings: initialLocalState.roleBindings,
            displays: initialDisplays
        )

        iCloudSyncEnabled = defaults.object(forKey: Keys.iCloudSync) as? Bool ?? true
        radialMenuEnabled = defaults.object(forKey: Keys.radialMenuEnabled) as? Bool ?? true
        radialMenuActivationStyle = defaults.string(forKey: Keys.radialMenuActivationStyle)
            .flatMap(RadialMenuActivationStyle.init(rawValue:)) ?? .pressToToggle
        radialMenuHoldDelay = RadialMenuHoldDelay.clamped(
            defaults.object(forKey: Keys.radialMenuHoldDelay) as? TimeInterval
                ?? RadialMenuHoldDelay.defaultValue
        )
        radialWheelDefinition = defaults.data(forKey: Keys.radialWheelDefinition)
            .flatMap { try? JSONDecoder().decode(RadialWheelDefinition.self, from: $0) }
            ?? .builtInDefault
        var initialHotKeyConfiguration = defaults.data(forKey: Keys.hotKeyConfiguration)
            .flatMap { try? JSONDecoder().decode(HotKeyConfiguration.self, from: $0) }
            ?? HotKeyConfiguration()
        if !initialHotKeyConfiguration.hasExplicitChord(for: .commandWheel),
           let legacy = defaults.string(forKey: Keys.radialMenuShortcut)
            .flatMap(LegacyRadialMenuShortcut.init(rawValue:)) {
            initialHotKeyConfiguration.setChord(legacy.chord, for: .commandWheel)
        }
        hotKeyConfiguration = initialHotKeyConfiguration
        if let data = try? JSONEncoder().encode(initialHotKeyConfiguration) {
            defaults.set(data, forKey: Keys.hotKeyConfiguration)
        }
        defaults.removeObject(forKey: Keys.radialMenuShortcut)
        let initialMenuBarPresentationMode = MenuBarPresentationMode.migrated(
            from: defaults.string(forKey: Keys.menuBarPresentationMode)
        )
        menuBarPresentationMode = initialMenuBarPresentationMode
        defaults.set(initialMenuBarPresentationMode.rawValue, forKey: Keys.menuBarPresentationMode)
        focusFollowsMovedWindow = defaults.object(forKey: Keys.focusFollowsMovedWindow) as? Bool ?? false
        automaticallyUnhideApplications = defaults.object(
            forKey: Keys.automaticallyUnhideApplications
        ) as? Bool ?? false

        // A decoded v1 wheel is already normalized by RadialWheelDefinition. Persist that v2 value
        // immediately so the private-install conversion is truly one-off, even if the user never
        // opens the wheel editor.
        if let normalizedWheelData = try? JSONEncoder().encode(radialWheelDefinition) {
            defaults.set(normalizedWheelData, forKey: Keys.radialWheelDefinition)
        }
        persistProfileLibrary(syncToCloud: false)
        persistLocalProfileState()
        if bootstrap.convertedLegacyConfiguration {
            diagnostics.log(
                category: "profile",
                event: "initial-conversion-completed",
                fields: [
                    "profile": Self.shortIdentifier(activeProfileID),
                    "workspace-count": String(workspaces.count),
                    "role-count": String(active.displayRoles.count),
                    "rule-count": String(appRules.count),
                ]
            )
        }
        logProfileSelection(selection, source: "startup")
        logRoleResolutions(for: active, source: "startup")

        if let ubiquitousStore {
            iCloudObserver = NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: ubiquitousStore.notificationObject,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.pullFromICloud() }
            }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshConnectedDisplays() }
        }

        if iCloudSyncEnabled {
            ubiquitousStore?.synchronize()
            pullFromICloud()
        }
    }

    deinit {
        if let iCloudObserver { NotificationCenter.default.removeObserver(iCloudObserver) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    var activeProfile: WindowManagerProfile {
        profiles.first(where: { $0.id == activeProfileID }) ?? profiles[0]
    }

    var manualPinnedProfileID: UUID? { localProfileState.manualPinnedProfileID }
    var defaultProfileID: UUID { localProfileState.defaultProfileID }
    var dockedProfileID: UUID? { localProfileState.dockedProfileID }
    var undockedProfileID: UUID? { localProfileState.undockedProfileID }
    var exactProfileTriggers: [ExactProfileTrigger] { localProfileState.exactTriggers }
    var roleBindings: [UUID: WorkspaceDisplayPin] { localProfileState.roleBindings }

    var workspaceDisplayPins: [UUID: WorkspaceDisplayPin] {
        Dictionary(uniqueKeysWithValues: activeProfile.workspaceRoleAssignments.compactMap {
            workspaceID, roleID in
            localProfileState.roleBindings[roleID].map { (workspaceID, $0) }
        })
    }

    func activeProfileEngineConfiguration() -> ProfileEngineConfiguration {
        engineConfiguration(for: activeProfile, selectionReason: activeProfileSelectionReason)
    }

    // MARK: - Profile selection and management

    func selectProfile(_ profileID: UUID) {
        guard profiles.contains(where: { $0.id == profileID }) else { return }
        var local = localProfileState
        local.manualPinnedProfileID = profileID
        local.activeProfileID = profileID
        localProfileState = local
        persistLocalProfileState()
        activateProfile(profileID, reason: .manualPin, source: "manual-selection")
    }

    func resumeAutomaticProfileSelection() {
        guard localProfileState.manualPinnedProfileID != nil else { return }
        var local = localProfileState
        local.manualPinnedProfileID = nil
        localProfileState = local
        persistLocalProfileState()
        evaluateAutomaticProfileSelection(source: "resume-automatic")
    }

    @discardableResult
    func createProfileFromCurrentConfiguration(name: String = "New Profile") -> UUID {
        cloneProfile(activeProfile, proposedName: name)
    }

    @discardableResult
    func duplicateProfile(_ profileID: UUID) -> UUID? {
        guard let source = profiles.first(where: { $0.id == profileID }) else { return nil }
        return cloneProfile(source, proposedName: "\(source.name) Copy")
    }

    func renameProfile(_ profileID: UUID, to proposedName: String) {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = profiles
        updated[index].name = uniqueProfileName(trimmed, excluding: profileID)
        profiles = updated
        persistProfileLibrary()
    }

    @discardableResult
    func deleteProfile(_ profileID: UUID) -> Bool {
        guard profiles.count > 1,
              profiles.contains(where: { $0.id == profileID })
        else { return false }
        let deletedRoleIDs = Set(
            profiles.first(where: { $0.id == profileID })?.displayRoles.map(\.id) ?? []
        )
        profiles.removeAll { $0.id == profileID }
        let validIDs = Set(profiles.map(\.id))
        var local = localProfileState
        local.removeReferences(to: profileID, validProfileIDs: validIDs)
        for roleID in deletedRoleIDs { local.roleBindings.removeValue(forKey: roleID) }
        local.normalize(validProfiles: profiles)
        localProfileState = local
        persistProfileLibrary()
        persistLocalProfileState()
        if activeProfileID == profileID {
            evaluateAutomaticProfileSelection(source: "profile-deleted")
        }
        return true
    }

    func setDefaultProfile(_ profileID: UUID) {
        guard profiles.contains(where: { $0.id == profileID }) else { return }
        var local = localProfileState
        local.defaultProfileID = profileID
        localProfileState = local
        persistLocalProfileState()
        if manualPinnedProfileID == nil { evaluateAutomaticProfileSelection(source: "default-changed") }
    }

    func setDockedProfile(_ profileID: UUID?) {
        setGenericProfile(profileID, docked: true)
    }

    func setUndockedProfile(_ profileID: UUID?) {
        setGenericProfile(profileID, docked: false)
    }

    @discardableResult
    func addExactTriggerForCurrentDisplays(profileID: UUID? = nil) -> UUID? {
        let targetID = profileID ?? activeProfileID
        guard profiles.contains(where: { $0.id == targetID }), !connectedDisplays.isEmpty else { return nil }
        let pins = connectedDisplays.map {
            WorkspaceDisplayPin(lastKnownIdentifier: $0.identifier, fingerprint: $0.fingerprint)
        }
        guard !localProfileState.exactTriggers.contains(where: {
            ProfileTriggerResolver.exactTopologyMatches($0.displayPins, displays: connectedDisplays)
        }) else { return nil }
        let trigger = ExactProfileTrigger(
            name: connectedDisplays.count == 1 ? "1 display" : "\(connectedDisplays.count) displays",
            profileID: targetID,
            displayPins: pins
        )
        var local = localProfileState
        local.exactTriggers.append(trigger)
        localProfileState = local
        persistLocalProfileState()
        if manualPinnedProfileID == nil { evaluateAutomaticProfileSelection(source: "exact-trigger-added") }
        return trigger.id
    }

    func setExactTrigger(_ triggerID: UUID, profileID: UUID) {
        guard profiles.contains(where: { $0.id == profileID }),
              let index = localProfileState.exactTriggers.firstIndex(where: { $0.id == triggerID })
        else { return }
        var local = localProfileState
        local.exactTriggers[index].profileID = profileID
        localProfileState = local
        persistLocalProfileState()
        if manualPinnedProfileID == nil { evaluateAutomaticProfileSelection(source: "exact-trigger-edited") }
    }

    func removeExactTrigger(_ triggerID: UUID) {
        var local = localProfileState
        let previousCount = local.exactTriggers.count
        local.exactTriggers.removeAll { $0.id == triggerID }
        guard local.exactTriggers.count != previousCount else { return }
        localProfileState = local
        persistLocalProfileState()
        if manualPinnedProfileID == nil { evaluateAutomaticProfileSelection(source: "exact-trigger-removed") }
    }

    // MARK: - Abstract display roles and local bindings

    @discardableResult
    func addDisplayRole(name: String = "Display Role") -> UUID {
        let role = ProfileDisplayRole(name: uniqueRoleName(name))
        mutateActiveProfile { $0.displayRoles.append(role) }
        return role.id
    }

    func renameDisplayRole(_ roleID: UUID, to proposedName: String) {
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutateActiveProfile { profile in
            guard let index = profile.displayRoles.firstIndex(where: { $0.id == roleID }) else { return }
            profile.displayRoles[index].name = trimmed
        }
    }

    @discardableResult
    func deleteDisplayRole(_ roleID: UUID) -> Bool {
        let profile = activeProfile
        guard profile.displayRoles.count > 1,
              profile.displayRoles.contains(where: { $0.id == roleID }),
              let fallbackRoleID = profile.displayRoles.first(where: { $0.id != roleID })?.id
        else { return false }
        mutateActiveProfile { profile in
            profile.displayRoles.removeAll { $0.id == roleID }
            for (workspaceID, assignedRoleID) in profile.workspaceRoleAssignments
            where assignedRoleID == roleID {
                profile.workspaceRoleAssignments[workspaceID] = fallbackRoleID
            }
        }
        var local = localProfileState
        local.roleBindings.removeValue(forKey: roleID)
        if var runtime = local.runtimeWorkspaceStates[activeProfileID] {
            runtime.activeWorkspaceIDByRole.removeValue(forKey: roleID)
            local.runtimeWorkspaceStates[activeProfileID] = runtime
        }
        localProfileState = local
        persistLocalProfileState()
        refreshResolvedWorkspaceDisplayAssignments()
        return true
    }

    func assignWorkspace(_ workspaceID: UUID, toRole roleID: UUID) {
        guard activeProfile.workspaces.contains(where: { $0.id == workspaceID }),
              activeProfile.displayRoles.contains(where: { $0.id == roleID })
        else { return }
        mutateActiveProfile { $0.workspaceRoleAssignments[workspaceID] = roleID }
        refreshResolvedWorkspaceDisplayAssignments()
    }

    func bindDisplayRole(_ roleID: UUID, to displayIdentifier: String?) {
        guard activeProfile.displayRoles.contains(where: { $0.id == roleID }) else { return }
        var local = localProfileState
        if let displayIdentifier,
           let display = connectedDisplays.first(where: { $0.identifier == displayIdentifier }) {
            local.roleBindings[roleID] = WorkspaceDisplayPin(
                lastKnownIdentifier: displayIdentifier,
                fingerprint: display.fingerprint
            )
        } else {
            local.roleBindings.removeValue(forKey: roleID)
        }
        localProfileState = local
        persistLocalProfileState()
        refreshResolvedWorkspaceDisplayAssignments()
        logRoleResolutions(for: activeProfile, source: "role-binding-changed")
    }

    func roleID(for workspaceID: UUID) -> UUID? {
        activeProfile.workspaceRoleAssignments[workspaceID]
    }

    func roleBindingResolution(_ roleID: UUID) -> DisplayPinResolution? {
        localProfileState.roleBindings[roleID].map {
            DisplayIdentityResolver.resolve($0, among: connectedDisplays)
        }
    }

    func displayIdentifier(for workspaceID: UUID) -> String {
        workspaceDisplayPins[workspaceID]?.lastKnownIdentifier
            ?? connectedDisplays.first(where: \.isMain)?.identifier
            ?? connectedDisplays.first?.identifier
            ?? "main-display"
    }

    func effectiveDisplayIdentifier(for workspaceID: UUID) -> String {
        workspaceDisplayAssignments[workspaceID]
            ?? connectedDisplays.first(where: \.isMain)?.identifier
            ?? connectedDisplays.first?.identifier
            ?? "main-display"
    }

    func displayPinResolution(for workspaceID: UUID) -> DisplayPinResolution? {
        workspaceDisplayPins[workspaceID].map {
            DisplayIdentityResolver.resolve($0, among: connectedDisplays)
        }
    }

    /// Converts physical assignments emitted by the engine back into the active profile's abstract
    /// role assignments. An unseen display creates one reusable role instead of syncing its UUID.
    func assignWorkspaces(_ assignments: [UUID: String]) {
        guard !assignments.isEmpty else { return }
        var profile = activeProfile
        var local = localProfileState
        for (workspaceID, displayIdentifier) in assignments
        where profile.workspaces.contains(where: { $0.id == workspaceID }) {
            let roleID = profile.displayRoles.first { role in
                guard let pin = local.roleBindings[role.id] else { return false }
                return DisplayIdentityResolver.resolve(pin, among: connectedDisplays).displayIdentifier
                    == displayIdentifier
            }?.id ?? {
                let display = connectedDisplays.first(where: { $0.identifier == displayIdentifier })
                let role = ProfileDisplayRole(name: uniqueRoleName(display?.name ?? "Display"))
                profile.displayRoles.append(role)
                local.roleBindings[role.id] = WorkspaceDisplayPin(
                    lastKnownIdentifier: displayIdentifier,
                    fingerprint: display?.fingerprint
                )
                return role.id
            }()
            profile.workspaceRoleAssignments[workspaceID] = roleID
        }
        replaceActiveProfile(profile)
        localProfileState = local
        persistProfileLibrary()
        persistLocalProfileState()
        refreshResolvedWorkspaceDisplayAssignments()
    }

    func assignWorkspace(_ workspaceID: UUID, to displayIdentifier: String) {
        assignWorkspaces([workspaceID: displayIdentifier])
    }

    func refreshConnectedDisplays() {
        connectedDisplays = connectedDisplaysProvider()
        var local = localProfileState
        var changed = false
        for (roleID, pin) in local.roleBindings {
            guard let identifier = DisplayIdentityResolver.resolve(
                pin,
                among: connectedDisplays
            ).displayIdentifier,
                  let display = connectedDisplays.first(where: { $0.identifier == identifier })
            else { continue }
            let rebound = WorkspaceDisplayPin(
                lastKnownIdentifier: identifier,
                fingerprint: display.fingerprint ?? pin.fingerprint
            )
            if rebound != pin {
                local.roleBindings[roleID] = rebound
                changed = true
            }
        }
        if changed {
            localProfileState = local
            persistLocalProfileState()
        }
        refreshResolvedWorkspaceDisplayAssignments()
        logRoleResolutions(for: activeProfile, source: "display-topology")
        evaluateAutomaticProfileSelection(source: "display-topology")
    }

    // MARK: - Existing profile-owned setting operations

    func addWorkspace() {
        let existing = Set(workspaces.map { $0.name })
        let name = (1...99).map(String.init).first { !existing.contains($0) } ?? "New"
        let workspace = WorkspaceDefinition(name: name, key: name.lowercased())
        workspaces.append(workspace)
        if let roleID = activeProfile.displayRoles.first?.id {
            assignWorkspace(workspace.id, toRole: roleID)
        }
    }

    func removeWorkspace(id: UUID) {
        guard workspaces.count > 1 else { return }
        workspaces.removeAll { $0.id == id }
        for index in appRules.indices where appRules[index].assignedWorkspaceID == id {
            appRules[index].assignedWorkspaceID = nil
        }
        var local = localProfileState
        if var runtime = local.runtimeWorkspaceStates[activeProfileID] {
            if runtime.currentWorkspaceID == id {
                runtime.currentWorkspaceID = workspaces[0].id
            }
            runtime.activeWorkspaceIDByRole = runtime.activeWorkspaceIDByRole.filter {
                $0.value != id
            }
            local.runtimeWorkspaceStates[activeProfileID] = runtime
            localProfileState = local
            persistLocalProfileState()
        }
    }

    func moveWorkspace(id: UUID, offset: Int) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + offset
        guard workspaces.indices.contains(destination) else { return }
        workspaces.swapAt(index, destination)
    }

    func resetToWindowManagerDefaults() {
        let replacements = WorkspaceDefinition.defaults.map {
            WorkspaceDefinition(name: $0.name, key: $0.key, layout: $0.layout)
        }
        workspaces = replacements
        if let roleID = activeProfile.displayRoles.first?.id {
            mutateActiveProfile { profile in
                profile.workspaceRoleAssignments = Dictionary(
                    uniqueKeysWithValues: replacements.map { ($0.id, roleID) }
                )
            }
            refreshResolvedWorkspaceDisplayAssignments()
        }
    }

    func setLayout(_ layout: WorkspaceLayout, for workspaceID: UUID) {
        guard let index = workspaces.firstIndex(where: { $0.id == workspaceID }),
              workspaces[index].layout != layout
        else { return }
        if workspaces[index].layoutConfiguration == nil {
            workspaces[index].layoutConfiguration = .aeroSpaceUserDefaults
        }
        workspaces[index].layout = layout
    }

    func layoutConfiguration(for workspaceID: UUID) -> WorkspaceLayoutConfiguration {
        workspaces.first(where: { $0.id == workspaceID })?.layoutConfiguration
            ?? .aeroSpaceUserDefaults
    }

    func isUsingLegacyLayoutGeometry(for workspaceID: UUID) -> Bool {
        workspaces.first(where: { $0.id == workspaceID })?.layoutConfiguration == nil
    }

    func setLayoutConfiguration(
        _ configuration: WorkspaceLayoutConfiguration,
        for workspaceID: UUID
    ) {
        guard let index = workspaces.firstIndex(where: { $0.id == workspaceID }) else { return }
        let clamped = configuration.clamped()
        guard workspaces[index].layoutConfiguration != clamped else { return }
        workspaces[index].layoutConfiguration = clamped
    }

    func useCurrentLayoutDefaults(for workspaceID: UUID) {
        setLayoutConfiguration(.aeroSpaceUserDefaults, for: workspaceID)
    }

    func addAppRule(for application: InstalledApplication) {
        guard !appRules.contains(where: { $0.id == application.id }) else { return }
        appRules.append(AppRule(
            bundleIdentifier: application.bundleIdentifier,
            displayName: application.displayName
        ))
    }

    func removeAppRule(bundleIdentifier: String) {
        appRules.removeAll { $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame }
    }

    func updateAppRule(_ updatedRule: AppRule, undoManager: UndoManager?) {
        guard let index = appRules.firstIndex(where: { $0.id == updatedRule.id }) else { return }
        let previousRule = appRules[index]
        guard previousRule != updatedRule else { return }
        if let undoManager {
            undoManager.registerUndo(withTarget: self) { [weak undoManager] target in
                target.updateAppRule(previousRule, undoManager: undoManager)
            }
            undoManager.setActionName("Change Application Rule")
        }
        appRules[index] = updatedRule
    }

    func setShortcut(_ chord: HotKeyChord, for action: ConfigurableHotKeyAction) {
        var updated = hotKeyConfiguration
        updated.setChord(chord, for: action)
        hotKeyConfiguration = updated
    }

    func resetShortcut(_ action: ConfigurableHotKeyAction) {
        var updated = hotKeyConfiguration
        updated.reset(action)
        hotKeyConfiguration = updated
    }

    func updateRadialWheelDefinition(
        actionName: String = "Edit Command Wheel",
        undoManager: UndoManager? = nil,
        _ mutation: (inout RadialWheelDefinition) -> Bool
    ) {
        var updated = radialWheelDefinition
        guard mutation(&updated), updated != radialWheelDefinition else { return }
        setRadialWheelDefinition(updated, actionName: actionName, undoManager: undoManager)
    }

    func setRadialWheelDefinition(
        _ definition: RadialWheelDefinition,
        actionName: String = "Edit Command Wheel",
        undoManager: UndoManager? = nil
    ) {
        guard definition != radialWheelDefinition else { return }
        let previous = radialWheelDefinition
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] store in
            store.setRadialWheelDefinition(
                previous,
                actionName: actionName,
                undoManager: undoManager
            )
        }
        undoManager?.setActionName(actionName)
        radialWheelDefinition = definition
    }

    func resetRadialWheelDefinition(undoManager: UndoManager? = nil) {
        setRadialWheelDefinition(
            .builtInDefault,
            actionName: "Reset Command Wheel",
            undoManager: undoManager
        )
    }

    func repairRadialWheelDefinition(undoManager: UndoManager? = nil) {
        setRadialWheelDefinition(
            radialWheelDefinition.repaired(),
            actionName: "Repair Command Wheel",
            undoManager: undoManager
        )
    }

    func resetAllShortcuts() {
        var updated = hotKeyConfiguration
        updated.resetAll()
        hotKeyConfiguration = updated
    }

    func recordActiveWorkspaceState(_ state: WorkspaceEngineState) {
        guard state.profileID == activeProfileID else { return }
        let validWorkspaceIDs = Set(workspaces.map(\.id))
        guard validWorkspaceIDs.contains(state.currentWorkspaceID) else { return }
        var activeByRole = localProfileState.runtimeWorkspaceStates[activeProfileID]?
            .activeWorkspaceIDByRole ?? [:]
        for (displayIdentifier, workspaceID) in state.activeWorkspaceIDByDisplay
        where validWorkspaceIDs.contains(workspaceID) {
            guard let roleID = roleID(boundTo: displayIdentifier, profile: activeProfile) else { continue }
            activeByRole[roleID] = workspaceID
        }
        let runtime = ProfileRuntimeWorkspaceState(
            currentWorkspaceID: state.currentWorkspaceID,
            activeWorkspaceIDByRole: activeByRole
        )
        guard localProfileState.runtimeWorkspaceStates[activeProfileID] != runtime else { return }
        var local = localProfileState
        local.runtimeWorkspaceStates[activeProfileID] = runtime
        localProfileState = local
        persistLocalProfileState()
    }

    // MARK: - Persistence and activation internals

    private func activeProfileContentDidChange() {
        guard !isApplyingProfileActivation, !workspaces.isEmpty,
              let index = profiles.firstIndex(where: { $0.id == activeProfileID })
        else { return }
        var updated = profiles
        updated[index].workspaces = workspaces
        updated[index].displayMode = multiDisplayMode
        updated[index].appRules = Self.normalizedAppRules(appRules)
        guard let normalized = updated[index].normalized() else { return }
        updated[index] = normalized
        profiles = updated
        persistProfileLibrary()
        refreshResolvedWorkspaceDisplayAssignments()
    }

    private func cloneProfile(_ source: WindowManagerProfile, proposedName: String) -> UUID {
        let clone = source.cloned(name: uniqueProfileName(proposedName))
        var updated = profiles
        updated.append(clone)
        profiles = updated
        var local = localProfileState
        for (sourceRole, clonedRole) in zip(source.displayRoles, clone.displayRoles) {
            if let binding = local.roleBindings[sourceRole.id] {
                local.roleBindings[clonedRole.id] = binding
            }
        }
        local.manualPinnedProfileID = clone.id
        local.activeProfileID = clone.id
        localProfileState = local
        persistProfileLibrary()
        persistLocalProfileState()
        activateProfile(clone.id, reason: .manualPin, source: "profile-created")
        return clone.id
    }

    private func setGenericProfile(_ profileID: UUID?, docked: Bool) {
        guard profileID == nil || profiles.contains(where: { $0.id == profileID }) else { return }
        var local = localProfileState
        if docked { local.dockedProfileID = profileID } else { local.undockedProfileID = profileID }
        localProfileState = local
        persistLocalProfileState()
        if manualPinnedProfileID == nil {
            evaluateAutomaticProfileSelection(source: docked ? "docked-rule-changed" : "undocked-rule-changed")
        }
    }

    private func evaluateAutomaticProfileSelection(source: String) {
        let selection = ProfileTriggerResolver.resolve(
            profiles: profiles,
            localState: localProfileState,
            displays: connectedDisplays,
            isPortableMac: isPortableMacProvider()
        )
        if selection.profileID == activeProfileID {
            let reasonChanged = selection.reason != activeProfileSelectionReason
            activeProfileSelectionReason = selection.reason
            var local = localProfileState
            local.activeProfileID = selection.profileID
            localProfileState = local
            persistLocalProfileState()
            if reasonChanged { logProfileSelection(selection, source: source) }
            return
        }
        activateProfile(selection.profileID, reason: selection.reason, source: source)
    }

    private func activateProfile(
        _ profileID: UUID,
        reason: ProfileSelectionReason,
        source: String
    ) {
        guard let profile = profiles.first(where: { $0.id == profileID }) else { return }
        isApplyingProfileActivation = true
        activeProfileID = profileID
        activeProfileSelectionReason = reason
        var local = localProfileState
        local.activeProfileID = profileID
        localProfileState = local
        workspaces = profile.workspaces
        multiDisplayMode = profile.displayMode
        appRules = profile.appRules
        refreshResolvedWorkspaceDisplayAssignments()
        isApplyingProfileActivation = false
        persistLocalProfileState()
        profileActivationGeneration &+= 1
        profileActivationRequest = ProfileActivationRequest(
            generation: profileActivationGeneration,
            configuration: engineConfiguration(for: profile, selectionReason: reason)
        )
        logProfileSelection(ProfileSelection(profileID: profileID, reason: reason), source: source)
        logRoleResolutions(for: profile, source: source)
    }

    private func engineConfiguration(
        for profile: WindowManagerProfile,
        selectionReason: ProfileSelectionReason
    ) -> ProfileEngineConfiguration {
        let runtime = localProfileState.runtimeWorkspaceStates[profile.id]
        let validWorkspaceIDs = Set(profile.workspaces.map(\.id))
        var activeByDisplay: [String: UUID] = [:]
        if let runtime {
            for (roleID, workspaceID) in runtime.activeWorkspaceIDByRole
            where validWorkspaceIDs.contains(workspaceID) {
                guard let pin = localProfileState.roleBindings[roleID] else { continue }
                let identifier = DisplayIdentityResolver.resolve(pin, among: connectedDisplays)
                    .displayIdentifier ?? pin.lastKnownIdentifier
                activeByDisplay[identifier] = workspaceID
            }
        }
        return ProfileEngineConfiguration(
            profileID: profile.id,
            profileName: profile.name,
            workspaces: profile.workspaces,
            displayMode: profile.displayMode,
            workspaceDisplayAssignments: ProfileRoleBindingResolver.resolve(
                profile: profile,
                roleBindings: localProfileState.roleBindings,
                displays: connectedDisplays
            ).workspaceDisplayHomes,
            appRules: profile.appRules,
            preferredCurrentWorkspaceID: runtime?.currentWorkspaceID,
            preferredActiveWorkspaceIDByDisplay: activeByDisplay,
            selectionReason: selectionReason
        )
    }

    private func mutateActiveProfile(_ mutation: (inout WindowManagerProfile) -> Void) {
        guard let index = profiles.firstIndex(where: { $0.id == activeProfileID }) else { return }
        var profile = profiles[index]
        mutation(&profile)
        guard let normalized = profile.normalized() else { return }
        var updated = profiles
        updated[index] = normalized
        profiles = updated
        persistProfileLibrary()
    }

    private func replaceActiveProfile(_ profile: WindowManagerProfile) {
        guard profile.id == activeProfileID,
              let index = profiles.firstIndex(where: { $0.id == activeProfileID }),
              let normalized = profile.normalized()
        else { return }
        var updated = profiles
        updated[index] = normalized
        profiles = updated
    }

    private func refreshResolvedWorkspaceDisplayAssignments() {
        workspaceDisplayHomesForEngine = ProfileRoleBindingResolver.resolve(
            profile: activeProfile,
            roleBindings: localProfileState.roleBindings,
            displays: connectedDisplays
        ).workspaceDisplayHomes
        workspaceDisplayAssignments = Self.resolvedConnectedWorkspaceAssignments(
            profile: activeProfile,
            roleBindings: localProfileState.roleBindings,
            displays: connectedDisplays
        )
    }

    private static func resolvedConnectedWorkspaceAssignments(
        profile: WindowManagerProfile,
        roleBindings: [UUID: WorkspaceDisplayPin],
        displays: [DisplaySnapshot]
    ) -> [UUID: String] {
        Dictionary(uniqueKeysWithValues: profile.workspaceRoleAssignments.compactMap {
            workspaceID, roleID in
            guard let pin = roleBindings[roleID],
                  let identifier = DisplayIdentityResolver.resolve(pin, among: displays).displayIdentifier
            else { return nil }
            return (workspaceID, identifier)
        })
    }

    static func resolvedWorkspaceDisplayAssignments(
        _ pins: [UUID: WorkspaceDisplayPin],
        displays: [DisplaySnapshot]
    ) -> [UUID: String] {
        Dictionary(uniqueKeysWithValues: pins.compactMap { workspaceID, pin in
            DisplayIdentityResolver.resolve(pin, among: displays).displayIdentifier.map {
                (workspaceID, $0)
            }
        })
    }

    private func roleID(boundTo displayIdentifier: String, profile: WindowManagerProfile) -> UUID? {
        profile.displayRoles.first { role in
            guard let pin = localProfileState.roleBindings[role.id] else { return false }
            return DisplayIdentityResolver.resolve(pin, among: connectedDisplays).displayIdentifier
                == displayIdentifier || pin.lastKnownIdentifier == displayIdentifier
        }?.id
    }

    private func uniqueProfileName(_ proposed: String, excluding excludedID: UUID? = nil) -> String {
        let trimmed = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Profile" : trimmed
        let existing = Set(profiles.filter { $0.id != excludedID }.map { $0.name.lowercased() })
        guard existing.contains(base.lowercased()) else { return base }
        var suffix = 2
        while existing.contains("\(base) \(suffix)".lowercased()) { suffix += 1 }
        return "\(base) \(suffix)"
    }

    private func uniqueRoleName(_ proposed: String) -> String {
        let trimmed = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Display Role" : trimmed
        let existing = Set(activeProfile.displayRoles.map { $0.name.lowercased() })
        guard existing.contains(base.lowercased()) else { return base }
        var suffix = 2
        while existing.contains("\(base) \(suffix)".lowercased()) { suffix += 1 }
        return "\(base) \(suffix)"
    }

    private func persistProfileLibrary(syncToCloud: Bool = true) {
        let library = ProfileLibrary(profiles: profiles)
        guard let data = try? JSONEncoder().encode(library) else { return }
        defaults.set(data, forKey: Keys.profileLibrary)
        guard syncToCloud, !isApplyingRemoteChange, iCloudSyncEnabled, let ubiquitousStore else { return }
        ubiquitousStore.set(data, forKey: Keys.profileLibrary)
        ubiquitousStore.synchronize()
    }

    private func persistLocalProfileState() {
        guard let data = try? JSONEncoder().encode(localProfileState) else { return }
        defaults.set(data, forKey: Keys.profileLocalState)
    }

    private func pushToICloud() {
        guard let ubiquitousStore else { return }
        if let data = try? JSONEncoder().encode(ProfileLibrary(profiles: profiles)) {
            ubiquitousStore.set(data, forKey: Keys.profileLibrary)
        }
        ubiquitousStore.set(radialMenuEnabled, forKey: Keys.radialMenuEnabled)
        ubiquitousStore.set(radialMenuActivationStyle.rawValue, forKey: Keys.radialMenuActivationStyle)
        ubiquitousStore.set(radialMenuHoldDelay, forKey: Keys.radialMenuHoldDelay)
        if let wheelData = try? JSONEncoder().encode(radialWheelDefinition) {
            ubiquitousStore.set(wheelData, forKey: Keys.radialWheelDefinition)
        }
        if let hotKeyData = try? JSONEncoder().encode(hotKeyConfiguration) {
            ubiquitousStore.set(hotKeyData, forKey: Keys.hotKeyConfiguration)
        }
        ubiquitousStore.set(menuBarPresentationMode.rawValue, forKey: Keys.menuBarPresentationMode)
        ubiquitousStore.set(focusFollowsMovedWindow, forKey: Keys.focusFollowsMovedWindow)
        ubiquitousStore.set(
            automaticallyUnhideApplications,
            forKey: Keys.automaticallyUnhideApplications
        )
        removeLegacyProfileKeys(from: ubiquitousStore)
    }

    private func pullFromICloud() {
        guard iCloudSyncEnabled, let ubiquitousStore else { return }
        let remoteLibraryData = ubiquitousStore.data(forKey: Keys.profileLibrary)
        let remoteLibrary = Self.decodedRemoteProfileLibrary(remoteLibraryData)
        let remoteRadialEnabled = ubiquitousStore.object(forKey: Keys.radialMenuEnabled) as? Bool
        let remoteRadialActivationStyle = ubiquitousStore.string(forKey: Keys.radialMenuActivationStyle)
            .flatMap(RadialMenuActivationStyle.init(rawValue:))
        let remoteRadialHoldDelay = ubiquitousStore.object(forKey: Keys.radialMenuHoldDelay) as? TimeInterval
        let remoteWheelData = ubiquitousStore.data(forKey: Keys.radialWheelDefinition)
        let remoteWheelDefinition = remoteWheelData.flatMap {
            try? JSONDecoder().decode(RadialWheelDefinition.self, from: $0)
        }
        let remoteLegacyRadialShortcut = ubiquitousStore.string(forKey: Keys.radialMenuShortcut)
            .flatMap(LegacyRadialMenuShortcut.init(rawValue:))
        let remoteHotKeyData = ubiquitousStore.data(forKey: Keys.hotKeyConfiguration)
        let remoteHotKeyConfiguration = remoteHotKeyData.flatMap {
            try? JSONDecoder().decode(HotKeyConfiguration.self, from: $0)
        }
        let remoteMenuBarPresentationRawValue = ubiquitousStore.string(
            forKey: Keys.menuBarPresentationMode
        )
        let remoteMenuBarPresentationMode = remoteMenuBarPresentationRawValue.map {
            MenuBarPresentationMode.migrated(from: $0)
        }
        let remoteFocusFollowsMovedWindow = ubiquitousStore.object(
            forKey: Keys.focusFollowsMovedWindow
        ) as? Bool
        let remoteAutomaticallyUnhideApplications = ubiquitousStore.object(
            forKey: Keys.automaticallyUnhideApplications
        ) as? Bool

        if remoteLibraryData == nil { pushToICloud() }
        if ubiquitousStore.object(forKey: Keys.radialMenuEnabled) == nil {
            ubiquitousStore.set(radialMenuEnabled, forKey: Keys.radialMenuEnabled)
        }
        if ubiquitousStore.string(forKey: Keys.radialMenuActivationStyle) == nil {
            ubiquitousStore.set(radialMenuActivationStyle.rawValue, forKey: Keys.radialMenuActivationStyle)
        }
        if ubiquitousStore.object(forKey: Keys.radialMenuHoldDelay) == nil {
            ubiquitousStore.set(radialMenuHoldDelay, forKey: Keys.radialMenuHoldDelay)
        }
        if remoteWheelData == nil,
           let data = try? JSONEncoder().encode(radialWheelDefinition) {
            ubiquitousStore.set(data, forKey: Keys.radialWheelDefinition)
        }
        if remoteHotKeyData == nil,
           let data = try? JSONEncoder().encode(hotKeyConfiguration) {
            ubiquitousStore.set(data, forKey: Keys.hotKeyConfiguration)
        }
        if ubiquitousStore.string(forKey: Keys.menuBarPresentationMode) == nil {
            ubiquitousStore.set(menuBarPresentationMode.rawValue, forKey: Keys.menuBarPresentationMode)
        }
        if ubiquitousStore.object(forKey: Keys.focusFollowsMovedWindow) == nil {
            ubiquitousStore.set(focusFollowsMovedWindow, forKey: Keys.focusFollowsMovedWindow)
        }
        if ubiquitousStore.object(forKey: Keys.automaticallyUnhideApplications) == nil {
            ubiquitousStore.set(
                automaticallyUnhideApplications,
                forKey: Keys.automaticallyUnhideApplications
            )
        }

        isApplyingRemoteChange = true
        if let remoteLibrary, remoteLibrary.profiles != profiles {
            profiles = remoteLibrary.profiles
            var local = localProfileState
            local.normalize(validProfiles: profiles)
            localProfileState = local
            let selection = ProfileTriggerResolver.resolve(
                profiles: profiles,
                localState: local,
                displays: connectedDisplays,
                isPortableMac: isPortableMacProvider()
            )
            persistProfileLibrary(syncToCloud: false)
            persistLocalProfileState()
            activateProfile(selection.profileID, reason: selection.reason, source: "icloud-library-update")
            diagnostics.log(
                category: "profile",
                event: "icloud-library-applied",
                fields: [
                    "profile-count": String(profiles.count),
                    "active-profile": Self.shortIdentifier(selection.profileID),
                ]
            )
        }
        if let remoteRadialEnabled, remoteRadialEnabled != radialMenuEnabled {
            radialMenuEnabled = remoteRadialEnabled
            defaults.set(remoteRadialEnabled, forKey: Keys.radialMenuEnabled)
        }
        if let remoteRadialActivationStyle,
           remoteRadialActivationStyle != radialMenuActivationStyle {
            radialMenuActivationStyle = remoteRadialActivationStyle
            defaults.set(remoteRadialActivationStyle.rawValue, forKey: Keys.radialMenuActivationStyle)
        }
        if let remoteRadialHoldDelay {
            let clamped = RadialMenuHoldDelay.clamped(remoteRadialHoldDelay)
            if clamped != radialMenuHoldDelay {
                radialMenuHoldDelay = clamped
                defaults.set(clamped, forKey: Keys.radialMenuHoldDelay)
            }
        }
        if let remoteWheelDefinition {
            let normalizedData = try? JSONEncoder().encode(remoteWheelDefinition)
            if remoteWheelDefinition != radialWheelDefinition {
                radialWheelDefinition = remoteWheelDefinition
            }
            if let normalizedData {
                defaults.set(normalizedData, forKey: Keys.radialWheelDefinition)
                if normalizedData != remoteWheelData {
                    ubiquitousStore.set(normalizedData, forKey: Keys.radialWheelDefinition)
                }
            }
        }
        if let remoteHotKeyData, let remoteHotKeyConfiguration,
           remoteHotKeyConfiguration != hotKeyConfiguration {
            hotKeyConfiguration = remoteHotKeyConfiguration
            defaults.set(remoteHotKeyData, forKey: Keys.hotKeyConfiguration)
        } else if remoteHotKeyData == nil, let remoteLegacyRadialShortcut,
                  !hotKeyConfiguration.hasExplicitChord(for: .commandWheel) {
            var migrated = hotKeyConfiguration
            migrated.setChord(remoteLegacyRadialShortcut.chord, for: .commandWheel)
            hotKeyConfiguration = migrated
            if let migratedData = try? JSONEncoder().encode(migrated) {
                defaults.set(migratedData, forKey: Keys.hotKeyConfiguration)
                ubiquitousStore.set(migratedData, forKey: Keys.hotKeyConfiguration)
            }
            ubiquitousStore.removeObject(forKey: Keys.radialMenuShortcut)
        }
        if let remoteMenuBarPresentationMode,
           remoteMenuBarPresentationMode != menuBarPresentationMode {
            menuBarPresentationMode = remoteMenuBarPresentationMode
            defaults.set(remoteMenuBarPresentationMode.rawValue, forKey: Keys.menuBarPresentationMode)
        }
        if remoteMenuBarPresentationRawValue != nil,
           remoteMenuBarPresentationRawValue != remoteMenuBarPresentationMode?.rawValue {
            ubiquitousStore.set(
                (remoteMenuBarPresentationMode ?? .compact).rawValue,
                forKey: Keys.menuBarPresentationMode
            )
        }
        if let remoteFocusFollowsMovedWindow,
           remoteFocusFollowsMovedWindow != focusFollowsMovedWindow {
            focusFollowsMovedWindow = remoteFocusFollowsMovedWindow
            defaults.set(remoteFocusFollowsMovedWindow, forKey: Keys.focusFollowsMovedWindow)
        }
        if let remoteAutomaticallyUnhideApplications,
           remoteAutomaticallyUnhideApplications != automaticallyUnhideApplications {
            automaticallyUnhideApplications = remoteAutomaticallyUnhideApplications
            defaults.set(
                remoteAutomaticallyUnhideApplications,
                forKey: Keys.automaticallyUnhideApplications
            )
        }
        isApplyingRemoteChange = false
    }

    /// Profile definitions form one versioned, atomic iCloud value. A valid remote value replaces
    /// the local definition library as a whole; an absent, corrupt, or future-version value is
    /// ignored. Machine-local activation, triggers, runtime state, and role bindings are never part
    /// of this decision.
    static func decodedRemoteProfileLibrary(_ data: Data?) -> ProfileLibrary? {
        guard let data,
              let decoded = try? JSONDecoder().decode(ProfileLibrary.self, from: data)
        else { return nil }
        return decoded.normalized()
    }

    private func persistRadialMenuSettings() {
        guard !isApplyingRemoteChange else { return }
        defaults.set(radialMenuEnabled, forKey: Keys.radialMenuEnabled)
        defaults.set(radialMenuActivationStyle.rawValue, forKey: Keys.radialMenuActivationStyle)
        defaults.set(radialMenuHoldDelay, forKey: Keys.radialMenuHoldDelay)
        let wheelData = try? JSONEncoder().encode(radialWheelDefinition)
        if let wheelData { defaults.set(wheelData, forKey: Keys.radialWheelDefinition) }
        if iCloudSyncEnabled, let ubiquitousStore {
            ubiquitousStore.set(radialMenuEnabled, forKey: Keys.radialMenuEnabled)
            ubiquitousStore.set(radialMenuActivationStyle.rawValue, forKey: Keys.radialMenuActivationStyle)
            ubiquitousStore.set(radialMenuHoldDelay, forKey: Keys.radialMenuHoldDelay)
            if let wheelData { ubiquitousStore.set(wheelData, forKey: Keys.radialWheelDefinition) }
            ubiquitousStore.synchronize()
        }
    }

    private func persistMenuBarPresentationMode() {
        guard !isApplyingRemoteChange else { return }
        defaults.set(menuBarPresentationMode.rawValue, forKey: Keys.menuBarPresentationMode)
        if iCloudSyncEnabled, let ubiquitousStore {
            ubiquitousStore.set(menuBarPresentationMode.rawValue, forKey: Keys.menuBarPresentationMode)
            ubiquitousStore.synchronize()
        }
    }

    private func persistHotKeyConfiguration() {
        guard !isApplyingRemoteChange,
              let data = try? JSONEncoder().encode(hotKeyConfiguration)
        else { return }
        defaults.set(data, forKey: Keys.hotKeyConfiguration)
        if iCloudSyncEnabled, let ubiquitousStore {
            ubiquitousStore.set(data, forKey: Keys.hotKeyConfiguration)
            ubiquitousStore.synchronize()
        }
    }

    private func persistFocusFollowsMovedWindow() {
        guard !isApplyingRemoteChange else { return }
        defaults.set(focusFollowsMovedWindow, forKey: Keys.focusFollowsMovedWindow)
        if iCloudSyncEnabled, let ubiquitousStore {
            ubiquitousStore.set(focusFollowsMovedWindow, forKey: Keys.focusFollowsMovedWindow)
            ubiquitousStore.synchronize()
        }
    }

    private func persistAutomaticallyUnhideApplications() {
        guard !isApplyingRemoteChange else { return }
        defaults.set(automaticallyUnhideApplications, forKey: Keys.automaticallyUnhideApplications)
        if iCloudSyncEnabled, let ubiquitousStore {
            ubiquitousStore.set(
                automaticallyUnhideApplications,
                forKey: Keys.automaticallyUnhideApplications
            )
            ubiquitousStore.synchronize()
        }
    }

    private func logProfileSelection(_ selection: ProfileSelection, source: String) {
        diagnostics.log(
            category: "profile",
            event: "selection-resolved",
            fields: [
                "profile": Self.shortIdentifier(selection.profileID),
                "reason": selection.reason.diagnosticValue,
                "source": source,
                "manual-pin": String(localProfileState.manualPinnedProfileID != nil),
                "display-count": String(connectedDisplays.count),
            ]
        )
    }

    private func logRoleResolutions(for profile: WindowManagerProfile, source: String) {
        let resolution = ProfileRoleBindingResolver.resolve(
            profile: profile,
            roleBindings: localProfileState.roleBindings,
            displays: connectedDisplays
        )
        for role in profile.displayRoles {
            let value: String
            switch resolution.resolutionByRole[role.id] ?? nil {
            case let .exactIdentifier(identifier): value = "exact-identifier:\(Self.shortIdentifier(identifier))"
            case let .exactUUID(identifier): value = "exact-uuid:\(Self.shortIdentifier(identifier))"
            case let .portableFingerprint(identifier): value = "portable:\(Self.shortIdentifier(identifier))"
            case .ambiguous: value = "ambiguous-main-fallback"
            case .disconnected: value = "disconnected-main-fallback"
            case nil: value = "unbound-main-fallback"
            }
            diagnostics.log(
                category: "profile",
                event: "role-resolution",
                fields: [
                    "profile": Self.shortIdentifier(profile.id),
                    "role": Self.shortIdentifier(role.id),
                    "resolution": value,
                    "source": source,
                ]
            )
        }
    }

    static func normalizedAppRules(_ rules: [AppRule]) -> [AppRule] {
        var seen = Set<String>()
        return rules.filter { rule in
            !rule.bundleIdentifier.isEmpty && seen.insert(rule.bundleIdentifier.lowercased()).inserted
        }
    }

    private static func bootstrapProfiles(
        defaults: UserDefaults,
        displays: [DisplaySnapshot]
    ) -> BootstrapResult {
        if let data = defaults.data(forKey: Keys.profileLibrary),
           let library = try? JSONDecoder().decode(ProfileLibrary.self, from: data).normalized() {
            let local = decodedLocalState(defaults: defaults, profiles: library.profiles)
            confirmProfileConversion(defaults: defaults)
            return BootstrapResult(
                library: library,
                localState: local,
                convertedLegacyConfiguration: false
            )
        }

        let legacy: LegacyProfileConfiguration
        if let backupData = defaults.data(forKey: Keys.profileConversionBackup),
           let backup = try? JSONDecoder().decode(LegacyProfileConfiguration.self, from: backupData) {
            legacy = backup
        } else {
            legacy = readLegacyConfiguration(defaults: defaults)
            if let backup = try? JSONEncoder().encode(legacy) {
                defaults.set(backup, forKey: Keys.profileConversionBackup)
            }
        }
        let conversion = InitialProfileConverter.convert(legacy: legacy, connectedDisplays: displays)
        guard let libraryData = try? JSONEncoder().encode(conversion.library),
              let localData = try? JSONEncoder().encode(conversion.localState)
        else {
            return conversionResult(conversion, converted: false)
        }
        defaults.set(libraryData, forKey: Keys.profileLibrary)
        defaults.set(localData, forKey: Keys.profileLocalState)
        let confirmedLibrary = defaults.data(forKey: Keys.profileLibrary).flatMap {
            try? JSONDecoder().decode(ProfileLibrary.self, from: $0)
        }
        let confirmedLocal = defaults.data(forKey: Keys.profileLocalState).flatMap {
            try? JSONDecoder().decode(ProfileLocalState.self, from: $0)
        }
        let confirmed = confirmedLibrary == conversion.library && confirmedLocal == conversion.localState
        if confirmed { confirmProfileConversion(defaults: defaults) }
        return conversionResult(conversion, converted: confirmed)
    }

    private static func conversionResult(
        _ conversion: InitialProfileConversion,
        converted: Bool
    ) -> BootstrapResult {
        BootstrapResult(
            library: conversion.library,
            localState: conversion.localState,
            convertedLegacyConfiguration: converted
        )
    }

    private static func decodedLocalState(
        defaults: UserDefaults,
        profiles: [WindowManagerProfile]
    ) -> ProfileLocalState {
        if let data = defaults.data(forKey: Keys.profileLocalState),
           var local = try? JSONDecoder().decode(ProfileLocalState.self, from: data),
           local.version == ProfileLocalState.currentVersion {
            local.normalize(validProfiles: profiles)
            return local
        }
        return ProfileLocalState(
            activeProfileID: profiles[0].id,
            defaultProfileID: profiles[0].id
        )
    }

    private static func readLegacyConfiguration(defaults: UserDefaults) -> LegacyProfileConfiguration {
        let workspaces = defaults.data(forKey: Keys.legacyWorkspaces).flatMap {
            try? JSONDecoder().decode([WorkspaceDefinition].self, from: $0)
        }.flatMap { $0.isEmpty ? nil : $0 } ?? WorkspaceDefinition.defaults
        let mode = defaults.string(forKey: Keys.legacyMultiDisplayMode)
            .flatMap(MultiDisplayMode.init(rawValue:)) ?? .unified
        let pins: [UUID: WorkspaceDisplayPin]
        if let data = defaults.data(forKey: Keys.legacyWorkspaceDisplayPins),
           let decoded = try? JSONDecoder().decode([String: WorkspaceDisplayPin].self, from: data) {
            pins = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
                UUID(uuidString: key).map { ($0, value) }
            })
        } else if let data = defaults.data(forKey: Keys.legacyWorkspaceDisplayAssignments),
                  let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            pins = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
                UUID(uuidString: key).map {
                    ($0, WorkspaceDisplayPin(lastKnownIdentifier: value, fingerprint: nil))
                }
            })
        } else {
            pins = [:]
        }
        let rules = defaults.data(forKey: Keys.legacyAppRules).flatMap {
            try? JSONDecoder().decode([AppRule].self, from: $0)
        } ?? []
        return LegacyProfileConfiguration(
            workspaces: workspaces,
            displayMode: mode,
            workspaceDisplayPins: pins,
            appRules: normalizedAppRules(rules)
        )
    }

    private static func confirmProfileConversion(defaults: UserDefaults) {
        defaults.set(true, forKey: Keys.profileConversionCompleted)
        defaults.removeObject(forKey: Keys.profileConversionBackup)
        defaults.removeObject(forKey: Keys.legacyWorkspaces)
        defaults.removeObject(forKey: Keys.legacyMultiDisplayMode)
        defaults.removeObject(forKey: Keys.legacyWorkspaceDisplayAssignments)
        defaults.removeObject(forKey: Keys.legacyWorkspaceDisplayPins)
        defaults.removeObject(forKey: Keys.legacyAppRules)
    }

    private func removeLegacyProfileKeys(from store: UbiquitousKeyValueStoring) {
        store.removeObject(forKey: Keys.legacyWorkspaces)
        store.removeObject(forKey: Keys.legacyMultiDisplayMode)
        store.removeObject(forKey: Keys.legacyWorkspaceDisplayAssignments)
        store.removeObject(forKey: Keys.legacyWorkspaceDisplayPins)
        store.removeObject(forKey: Keys.legacyAppRules)
    }

    private static func shortIdentifier(_ value: UUID) -> String {
        String(value.uuidString.prefix(12))
    }

    private static func shortIdentifier(_ value: String) -> String {
        String(value.prefix(12))
    }
}
