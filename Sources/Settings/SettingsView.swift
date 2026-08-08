import AppKit
import ApplicationServices
import SwiftUI

enum SettingsWindowMetrics {
    static let minimumSize = CGSize(width: 1120, height: 680)
    static let defaultSize = CGSize(width: 1280, height: 780)
}

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    let engine: WorkspaceEngine
    @ObservedObject var navigation: SettingsNavigationModel
    let windowCoordinator: SettingsWindowCoordinator
    let diagnostics: DiagnosticLogger
    let shortcutRecordingStateChanged: (Bool) -> Void
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            settingsSidebar
                .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 300)
        } detail: {
            detail
                .frame(minWidth: 860, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(
            minWidth: SettingsWindowMetrics.minimumSize.width,
            idealWidth: SettingsWindowMetrics.defaultSize.width,
            minHeight: SettingsWindowMetrics.minimumSize.height,
            idealHeight: SettingsWindowMetrics.defaultSize.height
        )
        .background {
            SettingsWindowReader { window in
                windowCoordinator.attach(window: window)
            }
            .frame(width: 0, height: 0)
        }
        .onAppear { navigation.validateSelection() }
    }

    private var settingsSidebar: some View {
        Group {
            if navigation.searchText.isEmpty {
                List(selection: Binding(
                    get: { Optional(navigation.selectedCategory) },
                    set: { if let category = $0 { navigation.select(category) } }
                )) {
                    Section("WindowManager") {
                        sidebarRow(.general)
                        sidebarRow(.profiles)
                        sidebarRow(.workspaces)
                    }
                    Section("Behavior") {
                        sidebarRow(.appRules)
                        sidebarRow(.shortcuts)
                        sidebarRow(.radialMenu)
                    }
                    #if DEBUG
                    Section("Development") { sidebarRow(.diagnostics) }
                    #endif
                }
                .listStyle(.sidebar)
            } else if searchResults.isEmpty {
                ContentUnavailableView.search(text: navigation.searchText)
            } else {
                List(searchResults) { result in
                    Button {
                        navigation.select(result)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Label(result.title, systemImage: result.category.systemImage)
                                .font(.body.weight(.medium))
                            Text(result.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens \(result.category.title) settings")
                }
                .listStyle(.sidebar)
            }
        }
        .searchable(
            text: $navigation.searchText,
            placement: .sidebar,
            prompt: "Search Settings"
        )
        .navigationTitle("Settings")
    }

    private func sidebarRow(_ category: SettingsCategory) -> some View {
        Label(category.title, systemImage: category.systemImage)
            .tag(category)
            .accessibilityLabel(category.title)
    }

    @ViewBuilder
    private var detail: some View {
        if navigation.selectedCategory.canonicalDestination == .workspaces {
            WorkspaceSettingsView(
                store: store,
                engine: engine,
                highlightedEntry: highlightedEntry,
                requestedWorkspaceID: navigation.requestedWorkspaceID
            )
            .navigationTitle(SettingsCategory.workspaces.title)
        } else {
            SettingsDetailContainer(
                category: navigation.selectedCategory,
                highlightedEntry: highlightedEntry
            ) {
                switch navigation.selectedCategory {
                case .general:
                    GeneralSettingsView(store: store, engine: engine)
                case .profiles:
                    ProfilesSettingsView(store: store)
                case .workspaces, .displays, .layouts:
                    EmptyView()
                case .appRules:
                    AppRulesSettingsView(store: store)
                case .shortcuts:
                    ShortcutSettingsView(
                        store: store,
                        recordingStateChanged: shortcutRecordingStateChanged
                    )
                case .radialMenu:
                    RadialMenuSettingsView(
                        store: store,
                        recordingStateChanged: shortcutRecordingStateChanged
                    )
                case .diagnostics:
                    #if DEBUG
                    DiagnosticsSettingsView(diagnostics: diagnostics, engine: engine)
                    #else
                    ContentUnavailableView("Unavailable", systemImage: "nosign")
                    #endif
                }
            }
        }
    }

    private var searchResults: [SettingsSearchEntry] {
        SettingsCatalog.search(
            navigation.searchText,
            includeDebug: navigation.includeDebug,
            workspaces: store.workspaces
        )
    }

    private var highlightedEntry: SettingsSearchEntry? {
        SettingsCatalog.search(
            "",
            includeDebug: navigation.includeDebug,
            workspaces: store.workspaces
        ).first { entry in
            entry.id == navigation.highlightedSettingID &&
                entry.category.canonicalDestination == navigation.selectedCategory.canonicalDestination
        }
    }
}

private struct SettingsDetailContainer<Content: View>: View {
    let category: SettingsCategory
    let highlightedEntry: SettingsSearchEntry?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Label(category.title, systemImage: category.systemImage)
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                if let highlightedEntry {
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(highlightedEntry.title).font(.subheadline.weight(.semibold))
                            Text(highlightedEntry.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "magnifyingglass")
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityLabel("Search result: \(highlightedEntry.title). \(highlightedEntry.description)")
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle(category.title)
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var store: SettingsStore
    let engine: WorkspaceEngine
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @StateObject private var launchAtLogin = LaunchAtLoginController()

    var body: some View {
        Form {
            Section("Permissions") {
                LabeledContent("Accessibility") {
                    HStack {
                        Text(accessibilityGranted ? "Granted" : "Required")
                            .foregroundStyle(accessibilityGranted ? .green : .orange)
                        if !accessibilityGranted {
                            Button("Grant Access") {
                                _ = AccessibilityWindow.requestPermission()
                                accessibilityGranted = AXIsProcessTrusted()
                            }
                        }
                    }
                }
                Text("Accessibility access lets the app discover, move, resize, and focus windows.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Startup and sync") {
                Toggle("Open at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                Toggle("Sync settings with iCloud", isOn: $store.iCloudSyncEnabled)
                Text("Named profile definitions and global preferences sync through your private iCloud key-value store. The active profile, automatic trigger mappings, live window state, and physical monitor bindings remain local to each Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let errorMessage = launchAtLogin.errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Menu Bar") {
                Picker("Presentation", selection: $store.menuBarPresentationMode) {
                    ForEach(MenuBarPresentationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                MenuBarSettingsPreview(snapshot: MenuBarPresentationResolver.preview(
                    mode: store.menuBarPresentationMode,
                    displayMode: store.multiDisplayMode,
                    workspaces: store.workspaces,
                    connectedDisplays: store.connectedDisplays,
                    workspaceDisplayAssignments: store.workspaceDisplayAssignments
                ))
                Text(store.menuBarPresentationMode.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if store.menuBarPresentationMode == .full {
                    Text("The app icon remains a distinct menu target inside one stable status component. Only explicit workspace buttons switch; display symbols and group backgrounds open the menu. Labels compact and overflow is disclosed when menu-bar space is tight.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("In Independent Displays mode, every connected display shows its own active workspace and the interaction display receives the stronger accent. In Unified mode, one combined-displays indicator is shown. Indicators are informational and the whole item opens the app menu.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Recovery") {
                Button("Bring All Managed Windows Back On Screen") {
                    engine.restoreAllWindows()
                }
                Text("Use this if the app or a display change leaves a managed window parked at the edge of the desktop.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Moving windows") {
                Toggle("Focus follows moved window", isOn: $store.focusFollowsMovedWindow)
                Text(store.focusFollowsMovedWindow
                    ? "Moving a window also opens its destination workspace and focuses it there. The command wheel still shows the effective move action."
                    : "Moving a window keeps you on the source workspace and focuses the next visible local window. The command wheel offers Move & Follow when you want it once.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Compatibility") {
                Toggle(
                    "Automatically unhide applications when focusing their windows",
                    isOn: $store.automaticallyUnhideApplications
                )
                Text("Off by default. When enabled, WindowManager only unhides an app while carrying out an explicit focus command, with duplicate attempts throttled to avoid loops.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Quit WindowManager") { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
    }

}

private struct ProfilesSettingsView: View {
    @ObservedObject var store: SettingsStore
    @Environment(\.undoManager) private var undoManager
    @StateObject private var transferCoordinator: ProfileTransferCoordinator
    @State private var pendingProfileDeletion: UUID?
    @State private var pendingProfileImport: ProfileImportPlan?
    @State private var transferNotice: ProfileTransferNotice?

    init(store: SettingsStore) {
        self.store = store
        _transferCoordinator = StateObject(wrappedValue: ProfileTransferCoordinator(
            diagnostics: store.profileTransferDiagnosticLogger
        ))
    }

    var body: some View {
        Form {
            Section("Current profile") {
                Picker("Active configuration", selection: Binding(
                    get: { store.activeProfileID },
                    set: { store.selectProfile($0) }
                )) {
                    ForEach(store.profiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                LabeledContent("Selection", value: store.activeProfileSelectionReason.title)
                if store.manualPinnedProfileID != nil {
                    Button("Resume Automatic", systemImage: "arrow.triangle.2.circlepath") {
                        store.resumeAutomaticProfileSelection()
                    }
                    Text("This profile is pinned on this Mac. Wake, docking, timers, and display changes cannot clear the pin; only Resume Automatic can.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Automatic selection uses the first matching rule in this order: exact display setup, docked or undocked, then this Mac's default profile.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Synced profile definitions") {
                ForEach(store.profiles) { profile in
                    HStack(spacing: 10) {
                        Image(systemName: profile.id == store.activeProfileID
                            ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(profile.id == store.activeProfileID ? Color.accentColor : .secondary)
                        TextField("Profile name", text: Binding(
                            get: {
                                store.profiles.first(where: { $0.id == profile.id })?.name
                                    ?? profile.name
                            },
                            set: { store.renameProfile(profile.id, to: $0) }
                        ))
                        Button {
                            _ = store.duplicateProfile(profile.id)
                        } label: {
                            Image(systemName: "plus.square.on.square")
                        }
                        .buttonStyle(.borderless)
                        .help("Duplicate profile")
                        Button(role: .destructive) {
                            pendingProfileDeletion = profile.id
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .disabled(store.profiles.count == 1)
                        .help("Delete profile")
                    }
                }
                Button("Create Profile from Current Configuration", systemImage: "plus") {
                    _ = store.createProfileFromCurrentConfiguration()
                }
                Text("Profiles sync workspace definitions and order, workspace keys and layouts, display mode and abstract roles, workspace-to-role assignments, and the complete app-rule collection. They never contain open-window identities, membership, frames, or focus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Transfer reusable profiles") {
                HStack {
                    Button("Export All Profiles…", systemImage: "square.and.arrow.up") {
                        Task {
                            do {
                                if try await transferCoordinator.exportProfiles(store.profiles) {
                                    transferNotice = ProfileTransferNotice(
                                        title: "Profiles Exported",
                                        message: "The portable file contains reusable profile definitions only."
                                    )
                                }
                            } catch {
                                transferNotice = ProfileTransferNotice(
                                    title: "Could Not Export Profiles",
                                    message: error.localizedDescription
                                )
                            }
                        }
                    }
                    Button("Import Profiles…", systemImage: "square.and.arrow.down") {
                        Task {
                            do {
                                pendingProfileImport = try await transferCoordinator.prepareImport(
                                    existingProfiles: store.profiles
                                )
                            } catch {
                                transferNotice = ProfileTransferNotice(
                                    title: "Could Not Import Profiles",
                                    message: error.localizedDescription
                                )
                            }
                        }
                    }
                }
                Text("Export includes synced reusable definitions. Import previews and adds fresh copies; it never activates them or transfers this Mac's triggers, current selection, physical monitor bindings, runtime workspaces, or open windows.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Automatic selection on this Mac") {
                profilePicker("Default profile", selection: Binding(
                    get: { Optional(store.defaultProfileID) },
                    set: { if let id = $0 { store.setDefaultProfile(id) } }
                ), permitsNone: false)
                profilePicker("When docked", selection: Binding(
                    get: { store.dockedProfileID },
                    set: { store.setDockedProfile($0) }
                ))
                profilePicker("When undocked", selection: Binding(
                    get: { store.undockedProfileID },
                    set: { store.setUndockedProfile($0) }
                ))
                Text("Docked/undocked applies only when this Mac is a portable: built-in display only is undocked; any active external display is docked. Desktop Macs fall through to an exact mapping or the local default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()
                HStack {
                    Text("Exact display setups").font(.headline)
                    Spacer()
                    Button("Map Current Displays", systemImage: "display.badge.plus") {
                        _ = store.addExactTriggerForCurrentDisplays()
                    }
                    .disabled(store.connectedDisplays.isEmpty)
                }
                if store.exactProfileTriggers.isEmpty {
                    Text("No exact display setup mappings on this Mac.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.exactProfileTriggers) { trigger in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(trigger.name)
                                Text("\(trigger.displayPins.count) conservative monitor identities")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Picker("Profile", selection: Binding(
                                get: { trigger.profileID },
                                set: { store.setExactTrigger(trigger.id, profileID: $0) }
                            )) {
                                ForEach(store.profiles) { profile in
                                    Text(profile.name).tag(profile.id)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 190)
                            Button(role: .destructive) {
                                store.removeExactTrigger(trigger.id)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                Text("The default, exact mappings, dock rules, active selection, and manual pin are local. They never sync or cause another Mac to switch profiles.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Display roles") {
                ForEach(store.activeProfile.displayRoles) { role in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField("Role name", text: Binding(
                                get: {
                                    store.activeProfile.displayRoles.first(where: { $0.id == role.id })?.name
                                        ?? role.name
                                },
                                set: { store.renameDisplayRole(role.id, to: $0) }
                            ))
                            Button(role: .destructive) {
                                _ = store.deleteDisplayRole(role.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .disabled(store.activeProfile.displayRoles.count == 1)
                        }
                        Picker("This Mac", selection: Binding<String?>(
                            get: { store.roleBindings[role.id]?.lastKnownIdentifier },
                            set: { store.bindDisplayRole(role.id, to: $0) }
                        )) {
                            Text("Unbound — safe main-display fallback").tag(nil as String?)
                            ForEach(roleDisplayOptions(role.id)) { display in
                                Text(display.name).tag(Optional(display.identifier))
                            }
                        }
                        if let note = roleBindingNote(role.id) {
                            Text(note).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Add Display Role", systemImage: "plus") {
                    _ = store.addDisplayRole()
                }
                Text("Role names and workspace assignments sync as part of this profile. The fingerprint binding above is local to this Mac. Missing, disconnected, or ambiguous roles fall back safely without rewriting the synced assignment.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Delete this profile?",
            isPresented: Binding(
                get: { pendingProfileDeletion != nil },
                set: { if !$0 { pendingProfileDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Profile", role: .destructive) {
                if let id = pendingProfileDeletion { _ = store.deleteProfile(id) }
                pendingProfileDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingProfileDeletion = nil }
        } message: {
            Text("The synced definition will be removed. Local default, trigger, runtime, and display-role references are cleaned up safely.")
        }
        .sheet(item: $pendingProfileImport) { plan in
            ProfileImportPreviewView(
                plan: plan,
                cancel: { pendingProfileImport = nil },
                confirm: {
                    switch store.applyProfileImport(plan, undoManager: undoManager) {
                    case let .applied(profileCount):
                        pendingProfileImport = nil
                        transferNotice = ProfileTransferNotice(
                            title: profileCount == 1 ? "Profile Imported" : "Profiles Imported",
                            message: "Added \(profileCount) reusable \(profileCount == 1 ? "profile" : "profiles") without changing the active profile or this Mac's bindings."
                        )
                    case .stalePreview:
                        pendingProfileImport = nil
                        transferNotice = ProfileTransferNotice(
                            title: "Profiles Changed",
                            message: "The profile library changed after this preview. Choose the file again to create a fresh preview."
                        )
                    case .invalidPlan:
                        pendingProfileImport = nil
                        transferNotice = ProfileTransferNotice(
                            title: "Import Was Not Applied",
                            message: "The preview is no longer safe to apply. No profiles were changed."
                        )
                    }
                }
            )
        }
        .alert(item: $transferNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private func profilePicker(
        _ title: String,
        selection: Binding<UUID?>,
        permitsNone: Bool = true
    ) -> some View {
        Picker(title, selection: selection) {
            if permitsNone { Text("Not assigned").tag(nil as UUID?) }
            ForEach(store.profiles) { profile in
                Text(profile.name).tag(Optional(profile.id))
            }
        }
    }

    private func roleDisplayOptions(_ roleID: UUID) -> [DisplaySnapshot] {
        guard let selected = store.roleBindings[roleID]?.lastKnownIdentifier,
              !store.connectedDisplays.contains(where: { $0.identifier == selected })
        else { return store.connectedDisplays }
        return store.connectedDisplays + [DisplaySnapshot(
            identifier: selected,
            bounds: .zero,
            isMain: false,
            name: "Disconnected Display"
        )]
    }

    private func roleBindingNote(_ roleID: UUID) -> String? {
        switch store.roleBindingResolution(roleID) {
        case .ambiguous:
            "Two identical monitors match. WindowManager will not guess; this role uses the safe main-display fallback."
        case .disconnected:
            "The bound monitor is disconnected. Its role is preserved and will return on reconnect."
        case .exactIdentifier, .exactUUID, .portableFingerprint:
            "Bound using a stable runtime identity with a conservative monitor-fingerprint fallback."
        case nil:
            "Unbound on this Mac; workspaces using this role fall back safely without changing the synced profile."
        }
    }
}

private struct ProfileTransferNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct ProfileImportPreviewView: View {
    let plan: ProfileImportPlan
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import Profiles")
                    .font(.title2.weight(.semibold))
                Text("Review the reusable definitions before adding them.")
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(plan.summaries) { summary in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "person.crop.rectangle.stack")
                                .foregroundStyle(.tint)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(summary.resultingName).fontWeight(.medium)
                                if summary.sourceName != summary.resultingName {
                                    Text("Imported from “\(summary.sourceName)”")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text("\(summary.workspaceCount) workspaces · \(summary.displayRoleCount) display roles · \(summary.appRuleCount) app rules")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .frame(minHeight: 160, maxHeight: 360)

            Label(
                "Imported profiles are added with fresh identities. They are not activated, assigned to triggers, or bound to this Mac's monitors.",
                systemImage: "checkmark.shield"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(plan.summaries.count == 1 ? "Add Profile" : "Add Profiles", action: confirm)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 520, idealWidth: 600)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Profile import preview")
    }
}

enum WorkspaceSettingsSelectionPolicy {
    static func reconciled(
        current: UUID?,
        preferred: UUID?,
        workspaceIDs: [UUID]
    ) -> UUID? {
        if let preferred, workspaceIDs.contains(preferred) { return preferred }
        if let current, workspaceIDs.contains(current) { return current }
        return workspaceIDs.first
    }

    static func selectionAfterDeleting(_ id: UUID, from workspaceIDs: [UUID]) -> UUID? {
        guard let index = workspaceIDs.firstIndex(of: id) else { return workspaceIDs.first }
        let remaining = workspaceIDs.filter { $0 != id }
        guard !remaining.isEmpty else { return nil }
        return remaining[min(index, remaining.count - 1)]
    }
}

struct WorkspaceInspectorControlVisibility: Equatable {
    let showsFreeformExplanation: Bool
    let showsOrientation: Bool
    let showsTiledGeometry: Bool
    let showsAccordionPadding: Bool

    init(
        showsFreeformExplanation: Bool,
        showsOrientation: Bool,
        showsTiledGeometry: Bool,
        showsAccordionPadding: Bool
    ) {
        self.showsFreeformExplanation = showsFreeformExplanation
        self.showsOrientation = showsOrientation
        self.showsTiledGeometry = showsTiledGeometry
        self.showsAccordionPadding = showsAccordionPadding
    }

    init(layout: WorkspaceLayout) {
        showsFreeformExplanation = layout == .none
        showsOrientation = layout != .none
        showsTiledGeometry = layout == .tiled
        showsAccordionPadding = layout == .accordion
    }
}

enum WorkspaceSettingsAccessibility {
    static func rowLabel(
        workspace: WorkspaceDefinition,
        displayRoleName: String
    ) -> String {
        "\(workspace.name), Home Display \(displayRoleName), \(workspace.layout.title) layout, workspace key \(workspace.key.uppercased())"
    }
}

struct WorkspaceSettingsView: View {
    @ObservedObject var store: SettingsStore
    let engine: WorkspaceEngine
    let highlightedEntry: SettingsSearchEntry?
    let requestedWorkspaceID: UUID?
    @Environment(\.undoManager) private var undoManager
    @State private var selectedWorkspaceID: UUID?

    init(
        store: SettingsStore,
        engine: WorkspaceEngine,
        highlightedEntry: SettingsSearchEntry? = nil,
        requestedWorkspaceID: UUID? = nil,
        initiallySelectedWorkspaceID: UUID? = nil
    ) {
        self.store = store
        self.engine = engine
        self.highlightedEntry = highlightedEntry
        self.requestedWorkspaceID = requestedWorkspaceID
        _selectedWorkspaceID = State(
            initialValue: requestedWorkspaceID ?? highlightedEntry?.workspaceID
                ?? initiallySelectedWorkspaceID
        )
    }

    var body: some View {
        HSplitView {
            masterColumn
                .frame(minWidth: 330, idealWidth: 385, maxWidth: 420)
            inspectorColumn
                .frame(minWidth: 530, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            reconcileSelection(preferred: requestedWorkspaceID ?? highlightedEntry?.workspaceID)
        }
        .onChange(of: store.workspaces.map(\.id)) { _, _ in reconcileSelection() }
        .onChange(of: store.activeProfileID) { _, _ in reconcileSelection() }
        .onChange(of: highlightedEntry?.workspaceID) { _, workspaceID in
            reconcileSelection(preferred: workspaceID)
        }
        .onChange(of: requestedWorkspaceID) { _, workspaceID in
            reconcileSelection(preferred: workspaceID)
        }
    }

    private var masterColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                Picker("Display workspace behavior", selection: $store.multiDisplayMode) {
                    ForEach(MultiDisplayMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Display workspace behavior")
                Text(displayModeExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            Text("Workspaces")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 6)

            if hasIdentityConflict {
                Label(
                    "Resolve duplicate or empty names and keys before relying on shortcuts.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
            }

            List(selection: $selectedWorkspaceID) {
                ForEach(store.workspaces) { workspace in
                    workspaceRow(workspace)
                        .tag(workspace.id)
                        .draggable(workspace.id.uuidString)
                        .dropDestination(for: String.self) { values, _ in
                            guard let source = values.first.flatMap(UUID.init(uuidString:)) else {
                                return false
                            }
                            store.moveWorkspace(id: source, before: workspace.id)
                            return true
                        }
                        .contextMenu { workspaceContextMenu(workspace) }
                        .accessibilityAction(named: "Move up") {
                            store.moveWorkspace(id: workspace.id, offset: -1)
                        }
                        .accessibilityAction(named: "Move down") {
                            store.moveWorkspace(id: workspace.id, offset: 1)
                        }
                }
                .onMove(perform: store.moveWorkspaces)
            }
            .listStyle(.sidebar)

            Divider()

            HStack(spacing: 8) {
                Button { selectedWorkspaceID = store.addWorkspace() } label: {
                    Image(systemName: "plus")
                }
                .help("Add workspace")
                .accessibilityLabel("Add workspace")

                Button { duplicateSelectedWorkspace() } label: {
                    Image(systemName: "square.on.square")
                }
                .disabled(selectedWorkspace == nil)
                .help("Duplicate selected workspace")
                .accessibilityLabel("Duplicate selected workspace")

                Button(role: .destructive) { deleteSelectedWorkspace() } label: {
                    Image(systemName: "trash")
                }
                .disabled(store.workspaces.count <= 1 || selectedWorkspace == nil)
                .help("Delete selected workspace")
                .accessibilityLabel("Delete selected workspace")

                Spacer()
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Divider()

            Button(SettingsCopy.restoreWindowManagerDefaultsTitle) {
                store.resetToWindowManagerDefaults()
                reconcileSelection()
            }
            .help("Restore WindowManager's built-in workspace configuration")
            .accessibilityLabel(SettingsCopy.restoreWindowManagerDefaultsTitle)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .background(.background)
    }

    @ViewBuilder
    private var inspectorColumn: some View {
        if let workspace = selectedWorkspace {
            VStack(alignment: .leading, spacing: 0) {
                if let highlightedEntry {
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(highlightedEntry.title).font(.subheadline.weight(.semibold))
                            Text(highlightedEntry.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "magnifyingglass")
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
                    .padding(.horizontal, 22)
                    .padding(.top, 14)
                    .accessibilityLabel(
                        "Search result: \(highlightedEntry.title). \(highlightedEntry.description)"
                    )
                }

                inspectorHeader(workspace)
                Divider()
                inspectorForm(workspace)
            }
        } else {
            ContentUnavailableView(
                "No Workspace Selected",
                systemImage: "square.grid.3x3",
                description: Text("Add or select a workspace to configure it.")
            )
        }
    }

    private func inspectorHeader(_ workspace: WorkspaceDefinition) -> some View {
        HStack(spacing: 14) {
            Image(systemName: workspace.layout.systemImage)
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 52, height: 52)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 11))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                TextField("Workspace name", text: Binding(
                    get: { selectedWorkspace?.name ?? "" },
                    set: { store.setWorkspaceName($0, for: workspace.id) }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.title2.weight(.semibold))
                .accessibilityLabel("Workspace name")

                Text("\(displayRoleName(for: workspace.id)) · \(workspace.layout.title)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private func inspectorForm(_ workspace: WorkspaceDefinition) -> some View {
        Form {
            Section("General") {
                Picker("Home Display", selection: roleBinding(for: workspace.id)) {
                    ForEach(store.activeProfile.displayRoles) { role in
                        Text(role.name).tag(role.id)
                    }
                }
                Text(roleNote(for: workspace.id))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Workspace Key") {
                    TextField("Key", text: Binding(
                        get: { selectedWorkspace?.key.uppercased() ?? "" },
                        set: { store.setWorkspaceKey($0, for: workspace.id) }
                    ))
                    .labelsHidden()
                    .multilineTextAlignment(.center)
                    .frame(width: 68)
                    .accessibilityLabel("Workspace key")
                }

                if workspace.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    isDuplicateName(workspace) {
                    Label("Workspace names must be non-empty and unique.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if workspace.key.isEmpty || isDuplicateKey(workspace) {
                    Label("Choose a unique supported workspace key.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                ForEach(shortcutConfigurationReport.issues(forWorkspace: workspace.id)) { issue in
                    Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Shortcut conflict. \(issue.message)")
                }
                ForEach(store.hotKeyRuntimeIssues.filter { $0.owner.workspaceID == workspace.id }) { issue in
                    Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Shortcut registration failed. \(issue.message)")
                }

                LabeledContent("Switch to \(workspace.name)") {
                    WorkspaceShortcutCaps(keys: ["⌃", "⌥", workspace.key.uppercased()])
                }
                LabeledContent("Move Window to \(workspace.name)") {
                    WorkspaceShortcutCaps(keys: ["⌥", "⌘", workspace.key.uppercased()])
                }
                Text("Workspace keys are synced with this profile. These two shortcuts are derived from the key; global command shortcuts remain in Shortcuts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Layout") {
                Picker("Layout Style", selection: Binding(
                    get: { selectedWorkspace?.layout ?? .none },
                    set: { store.setLayout($0, for: workspace.id) }
                )) {
                    ForEach(WorkspaceLayout.allCases) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
                .pickerStyle(.segmented)

                if store.isUsingLegacyLayoutGeometry(for: workspace.id), workspace.layout != .none {
                    Label(
                        "This workspace is preserving its pre-upgrade geometry.",
                        systemImage: "clock.arrow.circlepath"
                    )
                    .foregroundStyle(.secondary)
                    Button("Use Current Layout Defaults") {
                        store.useCurrentLayoutDefaults(for: workspace.id)
                    }
                }

                let controls = WorkspaceInspectorControlVisibility(layout: workspace.layout)
                if controls.showsFreeformExplanation {
                    Text("Freeform leaves window frames under manual control. WindowManager still manages workspace visibility, focus, persistence, display assignment, and quit/wake recovery.")
                        .foregroundStyle(.secondary)
                }
                if controls.showsOrientation {
                    orientationPicker(workspace.id)
                }
                if controls.showsTiledGeometry {
                    tiledGeometryControls(workspace.id)
                }
                if controls.showsAccordionPadding {
                    Stepper(
                        "Visible edge padding: \(Int(configuration(for: workspace.id).accordionPadding)) pt",
                        value: configurationBinding(\.accordionPadding, workspaceID: workspace.id),
                        in: 0...800,
                        step: 5
                    )
                    Text("Padding controls how much of neighbouring Accordion windows remains visible.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Floating windows, automatically detected dialogs, and apps excluded by a rule keep their own frames and never affect layout geometry.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Repair") {
                Button("Reset This Workspace", systemImage: "arrow.counterclockwise") {
                    store.resetWorkspaceSettings(workspace.id, undoManager: undoManager)
                }
                Text("Restores Freeform and WindowManager's built-in geometry. It keeps the workspace name, key, Home Display, app rules, and live window membership. The settings change can be undone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Button("Bring Active Workspace Windows Back On Screen", systemImage: "rectangle.inset.filled.and.person.filled") {
                    engine.resetCurrentWorkspace()
                }
                Text("Recovers managed windows in the interaction display's active workspace, clears transient positioning state, and reapplies that workspace's current layout. Accessibility frame changes cannot be undone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func orientationPicker(_ workspaceID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Picker(
                "Orientation",
                selection: configurationBinding(\.orientation, workspaceID: workspaceID)
            ) {
                ForEach(WorkspaceLayoutOrientation.allCases) { orientation in
                    Text(orientation.title).tag(orientation)
                }
            }
            .pickerStyle(.segmented)
            Text("Automatic uses horizontal windows on a wide display and vertical windows on a portrait display.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func tiledGeometryControls(_ workspaceID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Inner gaps").font(.subheadline.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                GridRow {
                    Stepper(
                        "Horizontal: \(Int(configuration(for: workspaceID).gaps.innerHorizontal)) pt",
                        value: gapBinding(\.innerHorizontal, workspaceID: workspaceID),
                        in: 0...200
                    )
                    Stepper(
                        "Vertical: \(Int(configuration(for: workspaceID).gaps.innerVertical)) pt",
                        value: gapBinding(\.innerVertical, workspaceID: workspaceID),
                        in: 0...200
                    )
                }
            }

            Text("Outer screen padding").font(.subheadline.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                GridRow {
                    Stepper(
                        "Top: \(Int(configuration(for: workspaceID).gaps.outerTop)) pt",
                        value: gapBinding(\.outerTop, workspaceID: workspaceID),
                        in: 0...400
                    )
                    Stepper(
                        "Right: \(Int(configuration(for: workspaceID).gaps.outerRight)) pt",
                        value: gapBinding(\.outerRight, workspaceID: workspaceID),
                        in: 0...400
                    )
                }
                GridRow {
                    Stepper(
                        "Bottom: \(Int(configuration(for: workspaceID).gaps.outerBottom)) pt",
                        value: gapBinding(\.outerBottom, workspaceID: workspaceID),
                        in: 0...400
                    )
                    Stepper(
                        "Left: \(Int(configuration(for: workspaceID).gaps.outerLeft)) pt",
                        value: gapBinding(\.outerLeft, workspaceID: workspaceID),
                        in: 0...400
                    )
                }
            }
        }
    }

    private func workspaceRow(_ workspace: WorkspaceDefinition) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Image(systemName: workspace.layout.systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text("\(displayRoleName(for: workspace.id)) · \(workspace.layout.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            WorkspaceShortcutCaps(keys: ["⌃", "⌥", workspace.key.uppercased()], compact: true)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .help("\(workspace.name) — \(displayRoleName(for: workspace.id)), \(workspace.layout.title), key \(workspace.key.uppercased())")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WorkspaceSettingsAccessibility.rowLabel(
            workspace: workspace,
            displayRoleName: displayRoleName(for: workspace.id)
        ))
    }

    @ViewBuilder
    private func workspaceContextMenu(_ workspace: WorkspaceDefinition) -> some View {
        Button("Move Up") { store.moveWorkspace(id: workspace.id, offset: -1) }
            .disabled(store.workspaces.first?.id == workspace.id)
        Button("Move Down") { store.moveWorkspace(id: workspace.id, offset: 1) }
            .disabled(store.workspaces.last?.id == workspace.id)
        Divider()
        Button("Duplicate") {
            selectedWorkspaceID = store.duplicateWorkspace(id: workspace.id)
        }
        Button("Delete", role: .destructive) {
            selectedWorkspaceID = WorkspaceSettingsSelectionPolicy.selectionAfterDeleting(
                workspace.id,
                from: store.workspaces.map(\.id)
            )
            store.removeWorkspace(id: workspace.id)
        }
        .disabled(store.workspaces.count <= 1)
    }

    private var selectedWorkspace: WorkspaceDefinition? {
        selectedWorkspaceID.flatMap { id in store.workspaces.first { $0.id == id } }
    }

    private var displayModeExplanation: String {
        store.multiDisplayMode == .unified
            ? "One active workspace is shared by every display; windows keep their display affinity."
            : "Each display has its own active workspace and each workspace has a Home Display."
    }

    private var hasIdentityConflict: Bool {
        store.workspaces.contains { workspace in
            workspace.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                workspace.key.isEmpty || isDuplicateName(workspace) || isDuplicateKey(workspace) ||
                !shortcutConfigurationReport.issues(forWorkspace: workspace.id).isEmpty
        }
    }

    private var shortcutConfigurationReport: ShortcutConfigurationReport {
        ShortcutConflictModel.evaluate(
            configuration: store.hotKeyConfiguration,
            workspaces: store.workspaces
        )
    }

    private func isDuplicateName(_ workspace: WorkspaceDefinition) -> Bool {
        let name = workspace.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !name.isEmpty && store.workspaces.filter {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == name
        }.count > 1
    }

    private func isDuplicateKey(_ workspace: WorkspaceDefinition) -> Bool {
        !workspace.key.isEmpty && store.workspaces.filter {
            $0.key.lowercased() == workspace.key.lowercased()
        }.count > 1
    }

    private func displayRoleName(for workspaceID: UUID) -> String {
        guard let roleID = store.roleID(for: workspaceID),
              let role = store.activeProfile.displayRoles.first(where: { $0.id == roleID })
        else { return "Unassigned" }
        return role.name
    }

    private func roleBinding(for workspaceID: UUID) -> Binding<UUID> {
        Binding(
            get: {
                store.roleID(for: workspaceID)
                    ?? store.activeProfile.displayRoles.first!.id
            },
            set: { store.assignWorkspace(workspaceID, toRole: $0) }
        )
    }

    private func roleNote(for workspaceID: UUID) -> String {
        guard let roleID = store.roleID(for: workspaceID),
              let role = store.activeProfile.displayRoles.first(where: { $0.id == roleID })
        else { return "No display role is assigned; WindowManager uses the safe main-display fallback." }
        switch store.roleBindingResolution(roleID) {
        case .ambiguous:
            return "\(role.name) matches multiple identical monitors, so WindowManager will not guess and uses the safe main-display fallback."
        case .disconnected:
            return "\(role.name)'s monitor is disconnected; this home is preserved and returns when the binding reconnects."
        case .exactIdentifier, .exactUUID, .portableFingerprint:
            return "The synced \(role.name) role is bound on this Mac using a conservative monitor identity."
        case nil:
            return "The synced \(role.name) role is unbound on this Mac and currently uses the safe main-display fallback. Bind it in Profiles."
        }
    }

    private func configuration(for workspaceID: UUID) -> WorkspaceLayoutConfiguration {
        store.layoutConfiguration(for: workspaceID)
    }

    private func configurationBinding<Value>(
        _ keyPath: WritableKeyPath<WorkspaceLayoutConfiguration, Value>,
        workspaceID: UUID
    ) -> Binding<Value> {
        Binding(
            get: { configuration(for: workspaceID)[keyPath: keyPath] },
            set: { newValue in
                var updated = configuration(for: workspaceID)
                updated[keyPath: keyPath] = newValue
                store.setLayoutConfiguration(updated, for: workspaceID)
            }
        )
    }

    private func gapBinding(
        _ keyPath: WritableKeyPath<WorkspaceLayoutGaps, Double>,
        workspaceID: UUID
    ) -> Binding<Double> {
        Binding(
            get: { configuration(for: workspaceID).gaps[keyPath: keyPath] },
            set: { newValue in
                var updated = configuration(for: workspaceID)
                updated.gaps[keyPath: keyPath] = newValue
                store.setLayoutConfiguration(updated, for: workspaceID)
            }
        )
    }

    private func duplicateSelectedWorkspace() {
        guard let workspaceID = selectedWorkspace?.id else { return }
        selectedWorkspaceID = store.duplicateWorkspace(id: workspaceID)
    }

    private func deleteSelectedWorkspace() {
        guard let workspaceID = selectedWorkspace?.id, store.workspaces.count > 1 else { return }
        selectedWorkspaceID = WorkspaceSettingsSelectionPolicy.selectionAfterDeleting(
            workspaceID,
            from: store.workspaces.map(\.id)
        )
        store.removeWorkspace(id: workspaceID)
    }

    private func reconcileSelection(preferred: UUID? = nil) {
        selectedWorkspaceID = WorkspaceSettingsSelectionPolicy.reconciled(
            current: selectedWorkspaceID,
            preferred: preferred,
            workspaceIDs: store.workspaces.map(\.id)
        )
    }
}

private struct WorkspaceShortcutCaps: View {
    let keys: [String]
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 1 : 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key.isEmpty ? "—" : key)
                    .font(.system(size: compact ? 10 : 12, weight: .medium, design: .rounded))
            }
        }
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 3 : 4)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .combine)
    }
}

private struct AppRulesSettingsView: View {
    @ObservedObject var store: SettingsStore
    @Environment(\.undoManager) private var undoManager
    @State private var showsAppPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rules use bundle identifiers, so they remain stable if an app is renamed or moved.")
                .foregroundStyle(.secondary)
            if store.appRules.isEmpty {
                ContentUnavailableView(
                    "No Application Rules",
                    systemImage: "app.badge",
                    description: Text("Add an installed or currently running app, then choose one or more behaviors.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.appRules) { rule in
                        AppRuleEditor(rule: Binding(
                            get: { store.appRules.first(where: { $0.id == rule.id }) ?? rule },
                            set: { store.updateAppRule($0, undoManager: undoManager) }
                        ), workspaces: store.workspaces) {
                            store.removeAppRule(bundleIdentifier: rule.bundleIdentifier)
                        }
                        .padding(.vertical, 6)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
            HStack {
                Button("Add Application…", systemImage: "plus") { showsAppPicker = true }
                Button("Undo Last Rule Change", systemImage: "arrow.uturn.backward") {
                    undoManager?.undo()
                }
                .disabled(!(undoManager?.canUndo ?? false))
                Spacer()
                Text("Changes apply immediately to managed windows and can be undone with Command-Z. Rules sync through iCloud when enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .sheet(isPresented: $showsAppPicker) {
            InstalledApplicationPicker(
                excludedBundleIdentifiers: Set(store.appRules.map { $0.bundleIdentifier.lowercased() })
            ) { application in
                store.addAppRule(for: application)
                showsAppPicker = false
            }
        }
    }
}

private struct AppRuleEditor: View {
    @Binding var rule: AppRule
    let workspaces: [WorkspaceDefinition]
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(nsImage: icon).resizable().frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(rule.displayName).font(.headline)
                    Text(rule.bundleIdentifier)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Toggle("Enabled", isOn: $rule.isEnabled)
                    .toggleStyle(.switch)
                    .help(rule.isEnabled ? "Pause this rule without deleting it" : "Resume this rule")
                Button(role: .destructive, action: remove) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("Remove rule")
            }
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow {
                    Text("Workspace")
                    Picker("Workspace", selection: Binding(
                        get: { rule.assignedWorkspaceID },
                        set: { rule.assignedWorkspaceID = $0 }
                    )) {
                        Text("Use current workspace").tag(nil as UUID?)
                        ForEach(workspaces) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)
                    .disabled(rule.keepsOnAllWorkspaces)
                }
                GridRow {
                    Text("Visibility")
                    Toggle("Keep on all workspaces", isOn: Binding(
                        get: { rule.keepsOnAllWorkspaces },
                        set: { rule.keepsOnAllWorkspaces = $0 }
                    ))
                }
                GridRow {
                    Text("Layouts")
                    Toggle("Do not include in Tiled or Accordion", isOn: Binding(
                        get: { rule.excludesFromLayout },
                        set: { rule.excludesFromLayout = $0 }
                    ))
                }
                GridRow {
                    Text("Secondary windows")
                    Toggle("Float detected dialogs and secondary windows", isOn: Binding(
                        get: { rule.floatsSecondaryWindows },
                        set: { rule.floatsSecondaryWindows = $0 }
                    ))
                    .disabled(rule.excludesFromLayout)
                }
            }
            .disabled(!rule.isEnabled)
            .opacity(rule.isEnabled ? 1 : 0.62)
            if !rule.isEnabled {
                Label(
                    "This rule is paused. Its actions are preserved and will apply again when resumed.",
                    systemImage: "pause.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if rule.keepsOnAllWorkspaces, rule.assignedWorkspaceID != nil {
                Label("Workspace assignment is paused while Keep on all workspaces is enabled.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if rule.floatsSecondaryWindows {
                Text(rule.excludesFromLayout
                    ? "The full app layout exclusion takes precedence while it is enabled."
                    : "Explicit per-window layout choices take precedence. Verified dialogs already float automatically; this rule also covers conservative dialog-like metadata without using window titles.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var icon: NSImage {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.bundleIdentifier)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)
            ?? NSImage()
    }
}

private struct InstalledApplicationPicker: View {
    @Environment(\.dismiss) private var dismiss
    let excludedBundleIdentifiers: Set<String>
    let select: (InstalledApplication) -> Void
    @State private var applications: [InstalledApplication] = []
    @State private var search = ""
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Choose an Application").font(.title2.bold())
                Spacer()
                Button("Cancel") { dismiss() }
            }
            TextField("Search apps or bundle identifiers", text: $search)
                .textFieldStyle(.roundedBorder)
            if isLoading {
                ProgressView("Finding installed applications…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredApplications.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                List(filteredApplications) { application in
                    Button { select(application) } label: {
                        HStack(spacing: 10) {
                            Image(nsImage: application.bundleURL.map {
                                NSWorkspace.shared.icon(forFile: $0.path)
                            } ?? NSImage())
                            .resizable()
                            .frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack {
                                    Text(application.displayName)
                                    if application.isRunning {
                                        Text("Running")
                                            .font(.caption2)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(.quaternary, in: Capsule())
                                    }
                                }
                                Text(application.bundleIdentifier)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .padding(20)
        .frame(width: 560, height: 520)
        .task {
            let discovered = await Task.detached(priority: .userInitiated) {
                InstalledApplicationCatalog.discover()
            }.value
            applications = discovered.filter {
                !excludedBundleIdentifiers.contains($0.bundleIdentifier.lowercased())
            }
            isLoading = false
        }
    }

    private var filteredApplications: [InstalledApplication] {
        guard !search.isEmpty else { return applications }
        return applications.filter {
            $0.displayName.localizedCaseInsensitiveContains(search) ||
                $0.bundleIdentifier.localizedCaseInsensitiveContains(search)
        }
    }
}

private struct ShortcutSettingsView: View {
    @ObservedObject var store: SettingsStore
    let recordingStateChanged: (Bool) -> Void
    @State private var recordingAction: ConfigurableHotKeyAction?
    @State private var eventMonitor: Any?
    @State private var conflictMessage: String?

    private var configurationReport: ShortcutConfigurationReport {
        ShortcutConflictModel.evaluate(
            configuration: store.hotKeyConfiguration,
            workspaces: store.workspaces
        )
    }

    private var conflictingCustomActions: Set<ConfigurableHotKeyAction> {
        Set(configurationReport.issues.flatMap(\.owners).compactMap(\.configurableAction).filter {
            !store.hotKeyConfiguration.isUsingDefault(for: $0)
        })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Select a global command shortcut to record a replacement. Workspace keys and their derived switch/move shortcuts are configured in Workspaces.")
                    .foregroundStyle(.secondary)
                if !configurationReport.issues.isEmpty || !store.hotKeyRuntimeIssues.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Label(
                            "Some shortcuts need attention",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.headline)
                        .foregroundStyle(.orange)
                        Text("Conflicting shortcuts are not registered for either command. A macOS registration failure affects only that command; other valid shortcuts remain available.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Reset Conflicting Custom Shortcuts") {
                            finishRecording()
                            store.resetShortcuts(conflictingCustomActions)
                        }
                        .disabled(conflictingCustomActions.isEmpty)
                        Text("If both commands use built-in defaults, record a different global shortcut here or change the affected workspace key in Workspaces.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 12) {
                    GridRow {
                        Text("Action").bold()
                        Text("Shortcut").bold()
                        Text("Reset").bold()
                    }
                    Divider()
                    ForEach(ConfigurableHotKeyAction.allCases) { action in
                        shortcutRow(action)
                    }
                    GridRow {
                        Text("Select Freeform")
                        Text("Command wheel or Settings").foregroundStyle(.secondary)
                        Color.clear.frame(width: 1, height: 1)
                    }
                }
                if let conflictMessage {
                    Label(conflictMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Shortcut conflict. \(conflictMessage)")
                }
                HStack {
                    Button("Reset All Shortcuts") {
                        finishRecording()
                        conflictMessage = nil
                        store.resetAllShortcuts()
                    }
                    Spacer()
                    Text("Escape cancels recording. A global shortcut must include Control, Option, or Command.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()
                Text("An app-level layout exclusion remains authoritative; window-level floating controls cannot override it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Workspace-specific shortcuts are intentionally kept with each workspace's name, display home, and layout in Workspaces.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onDisappear { finishRecording() }
    }

    private func shortcutRow(_ action: ConfigurableHotKeyAction) -> some View {
        let chord = store.hotKeyConfiguration.chord(for: action)
        return GridRow {
            VStack(alignment: .leading, spacing: 3) {
                Text(action.title)
                ForEach(configurationReport.issues(for: action)) { issue in
                    Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Shortcut conflict. \(issue.message)")
                }
                ForEach(store.hotKeyRuntimeIssues.filter {
                    $0.owner.configurableAction == action
                }) { issue in
                    Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Shortcut registration failed. \(issue.message)")
                }
            }
            Button {
                beginRecording(action)
            } label: {
                if recordingAction == action {
                    Text("Press shortcut…")
                        .frame(minWidth: 110)
                } else {
                    ShortcutCaps(keys: chord.keyCaps)
                }
            }
            .buttonStyle(.bordered)
            .help("Record a new global shortcut for \(action.title)")
            Button("Reset") {
                if recordingAction == action { finishRecording() }
                conflictMessage = nil
                store.resetShortcut(action)
            }
            .disabled(store.hotKeyConfiguration.isUsingDefault(for: action))
        }
    }

    private func beginRecording(_ action: ConfigurableHotKeyAction) {
        removeEventMonitor()
        recordingAction = action
        conflictMessage = nil
        recordingStateChanged(true)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                finishRecording()
                return nil
            }
            guard let chord = HotKeyManager.recordedChord(from: event) else {
                conflictMessage = "Press a non-modifier key together with Control, Option, or Command."
                NSSound.beep()
                return nil
            }
            guard let recordingAction else { return event }
            if let conflict = HotKeyManager.configurableShortcutConflict(
                action: recordingAction,
                chord: chord,
                configuration: store.hotKeyConfiguration,
                workspaces: store.workspaces
            ) {
                conflictMessage = conflict
                NSSound.beep()
                return nil
            }
            store.setShortcut(chord, for: recordingAction)
            finishRecording()
            return nil
        }
    }

    private func finishRecording() {
        let wasRecording = recordingAction != nil || eventMonitor != nil
        removeEventMonitor()
        recordingAction = nil
        if wasRecording { recordingStateChanged(false) }
    }

    private func removeEventMonitor() {
        guard let eventMonitor else { return }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }
}

private struct RadialMenuSettingsView: View {
    @ObservedObject var store: SettingsStore
    let recordingStateChanged: (Bool) -> Void
    @Environment(\.undoManager) private var undoManager
    @State private var isRecordingShortcut = false
    @State private var shortcutEventMonitor: Any?
    @State private var conflictMessage: String?

    private var wheelChord: HotKeyChord {
        store.hotKeyConfiguration.chord(for: .commandWheel)
    }

    private var storedConflict: String? {
        HotKeyManager.configurableShortcutConflict(
            action: .commandWheel,
            chord: wheelChord,
            configuration: store.hotKeyConfiguration,
            workspaces: store.workspaces
        )
    }

    private var runtimeIssue: HotKeyRuntimeIssue? {
        store.hotKeyRuntimeIssues.first { $0.owner.configurableAction == .commandWheel }
    }

    var body: some View {
        Form {
            Section("Activation") {
                Toggle("Enable command wheel", isOn: $store.radialMenuEnabled)
                HStack {
                    Text("Global shortcut")
                    Spacer()
                    Button {
                        beginShortcutRecording()
                    } label: {
                        if isRecordingShortcut {
                            Text("Press shortcut…").frame(minWidth: 120)
                        } else {
                            ShortcutCaps(keys: wheelChord.keyCaps)
                        }
                    }
                    .buttonStyle(.bordered)
                    Button("Reset") {
                        finishShortcutRecording()
                        conflictMessage = nil
                        store.resetShortcut(.commandWheel)
                    }
                    .disabled(store.hotKeyConfiguration.isUsingDefault(for: .commandWheel))
                }
                .disabled(!store.radialMenuEnabled)
                if let conflict = conflictMessage ?? storedConflict {
                    Label(conflict, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                if let runtimeIssue {
                    Label(runtimeIssue.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Shortcut registration failed. \(runtimeIssue.message)")
                }
                Picker("Activation style", selection: $store.radialMenuActivationStyle) {
                    ForEach(RadialMenuActivationStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                if store.radialMenuActivationStyle == .holdToShow {
                    LabeledContent("Hold delay") {
                        HStack {
                            Slider(
                                value: $store.radialMenuHoldDelay,
                                in: RadialMenuHoldDelay.permittedRange,
                                step: 0.05
                            )
                            .frame(width: 210)
                            Text("\(store.radialMenuHoldDelay, specifier: "%.2f") s")
                                .monospacedDigit()
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                    Text("A shorter tap does nothing. Hold past the delay, point to an action, then release to run it; releasing with no action selected cancels.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Press once to show the wheel; click or use the keyboard to choose an action. Press the shortcut again or Escape to cancel.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("This first version records a modifier plus a non-modifier key. Modifier-only, Fn-only, and left-versus-right modifier triggers are intentionally not captured by the Carbon shortcut path.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Appearance and interaction") {
                CommandWheelPreview(definition: store.radialWheelDefinition)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                Text("The wheel opens at the pointer on the interaction display. Its inner ring mixes direct actions and groups; a group reveals its valid actions on the outer ring. Empty groups and unavailable actions close up automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Move across a ring to select. Return or Space activates, Tab enters a group, Shift-Tab or Delete returns inward, and Escape always cancels. The centre is a generous cancel zone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Top-level catalogue") {
                if store.radialWheelDefinition.hasUnresolvedReferences {
                    Label("This definition contains duplicate or unavailable entries. They are omitted safely when the wheel opens.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Button("Repair Definition") {
                        store.repairRadialWheelDefinition(undoManager: undoManager)
                    }
                }
                if store.radialWheelDefinition.items.isEmpty {
                    ContentUnavailableView(
                        "No Saved Wheel Items",
                        systemImage: "circle.dashed",
                        description: Text("The wheel uses a minimal safe fallback until you add an item or reset it.")
                    )
                }
                ForEach(Array(store.radialWheelDefinition.items.enumerated()), id: \.element.id) { index, item in
                    CommandWheelEditorRow(
                        store: store,
                        item: item,
                        index: index,
                        total: store.radialWheelDefinition.items.count,
                        undoManager: undoManager
                    )
                }
                HStack {
                    Menu("Add Item", systemImage: "plus") {
                        ForEach(availableItems) { metadata in
                            Button {
                                store.updateRadialWheelDefinition(
                                    actionName: "Add Wheel Item",
                                    undoManager: undoManager
                                ) { definition in
                                    definition.add(metadata.reference)
                                }
                            } label: {
                                Label(metadata.title, systemImage: metadata.systemImage)
                            }
                        }
                    }
                    Spacer()
                    Button("Reset to Built-In Default") {
                        store.resetRadialWheelDefinition(undoManager: undoManager)
                    }
                    .disabled(store.radialWheelDefinition == .builtInDefault)
                }
                Text("Choose and order the command families on the inner ring. Each family generates its current workspace, profile, layout, or window actions automatically. This synced preference is global and is not part of a Profile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onDisappear { finishShortcutRecording() }
    }

    private var availableItems: [RadialCommandMetadata] {
        let existing = Set(store.radialWheelDefinition.items)
        return RadialCommandCatalogue.allMetadata.filter { !existing.contains($0.reference) }
    }

    private func beginShortcutRecording() {
        finishShortcutRecording()
        isRecordingShortcut = true
        conflictMessage = nil
        recordingStateChanged(true)
        shortcutEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                finishShortcutRecording()
                return nil
            }
            guard let chord = HotKeyManager.recordedChord(from: event) else {
                conflictMessage = "Press a non-modifier key together with Control, Option, or Command."
                NSSound.beep()
                return nil
            }
            if let conflict = HotKeyManager.configurableShortcutConflict(
                action: .commandWheel,
                chord: chord,
                configuration: store.hotKeyConfiguration,
                workspaces: store.workspaces
            ) {
                conflictMessage = conflict
                NSSound.beep()
                return nil
            }
            store.setShortcut(chord, for: .commandWheel)
            finishShortcutRecording()
            return nil
        }
    }

    private func finishShortcutRecording() {
        let wasRecording = isRecordingShortcut || shortcutEventMonitor != nil
        if let shortcutEventMonitor { NSEvent.removeMonitor(shortcutEventMonitor) }
        shortcutEventMonitor = nil
        isRecordingShortcut = false
        if wasRecording { recordingStateChanged(false) }
    }
}

private struct CommandWheelEditorRow: View {
    @ObservedObject var store: SettingsStore
    let item: RadialTopLevelItemID
    let index: Int
    let total: Int
    let undoManager: UndoManager?

    var body: some View {
        HStack {
            let metadata = RadialCommandCatalogue.metadata(for: item)
            Label(metadata?.title ?? "Unavailable item", systemImage: metadata?.systemImage ?? "questionmark.diamond")
                .fontWeight(.medium)
            Text("Contextual").font(.caption).foregroundStyle(.secondary)
            Spacer()
            editorControls
        }
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
        .draggable(item.rawValue)
        .dropDestination(for: String.self) { values, _ in
            guard let raw = values.first else { return false }
            let moving = RadialTopLevelItemID(rawValue: raw)
            guard let from = store.radialWheelDefinition.items.firstIndex(of: moving),
                  let to = store.radialWheelDefinition.items.firstIndex(of: item), from != to
            else { return false }
            var didMove = false
            store.updateRadialWheelDefinition(
                actionName: "Reorder Wheel Items",
                undoManager: undoManager
            ) { definition in
                didMove = definition.moveItem(id: moving, offset: to - from)
                return didMove
            }
            return didMove
        }
    }

    private var editorControls: some View {
        HStack(spacing: 6) {
            Button {
                moveItem(-1)
            } label: { Image(systemName: "arrow.up") }
                .disabled(index == 0)
                .help("Move earlier")
            Button {
                moveItem(1)
            } label: { Image(systemName: "arrow.down") }
                .disabled(index >= total - 1)
                .help("Move later")
            Button(role: .destructive) {
                store.updateRadialWheelDefinition(
                    actionName: "Remove Wheel Item",
                    undoManager: undoManager
                ) { $0.removeItem(id: item) }
            } label: { Image(systemName: "trash") }
                .help("Remove")
        }
        .buttonStyle(.borderless)
    }

    private func moveItem(_ offset: Int) {
        store.updateRadialWheelDefinition(
            actionName: "Reorder Wheel Items",
            undoManager: undoManager
        ) { $0.moveItem(id: item, offset: offset) }
    }
}

private struct CommandWheelPreview: View {
    let definition: RadialWheelDefinition

    private var previewItems: [RadialTopLevelItemID] {
        Array(definition.items.prefix(10))
    }

    private var previewGroup: RadialTopLevelItemID? {
        previewItems.first { !RadialCommandCatalogue.previewChildSystemImages(for: $0).isEmpty }
    }

    private var previewChildren: [String] {
        previewGroup.map(RadialCommandCatalogue.previewChildSystemImages) ?? []
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.20))
                .background(.ultraThinMaterial, in: Circle())
                .frame(width: 214, height: 214)
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().stroke(Color.primary.opacity(0.14), lineWidth: 1))
                .frame(width: 128, height: 128)
            ForEach(Array(previewItems.enumerated()), id: \.element.id) { index, item in
                let center = RadialMenuGeometry.itemCenter(
                    index: index,
                    count: previewItems.count,
                    center: CGPoint(x: 120, y: 120),
                    radius: 45
                )
                Image(systemName: previewImage(for: item))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(item == previewGroup ? Color.accentColor : Color.primary)
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(item == previewGroup ? 0.14 : 0.06), in: Circle())
                    .position(center)
            }

            ForEach(Array(previewChildren.enumerated()), id: \.offset) { index, image in
                let center = RadialMenuGeometry.itemCenter(
                    index: index,
                    count: previewChildren.count,
                    center: CGPoint(x: 120, y: 120),
                    radius: 91
                )
                Image(systemName: image)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 22)
                    .background(Color.primary.opacity(0.07), in: Capsule())
                    .position(center)
            }

            VStack(spacing: 2) {
                Text("Contextual")
                    .font(.caption2.weight(.semibold))
                Text("Generated actions")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 240, height: 240)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Command wheel preview with \(previewItems.count) saved inner items and \(previewChildren.count) generated outer actions"
        )
    }

    private func previewImage(for item: RadialTopLevelItemID) -> String {
        RadialCommandCatalogue.metadata(for: item)?.systemImage ?? "questionmark"
    }
}

#if DEBUG
private struct DiagnosticsSettingsView: View {
    let diagnostics: DiagnosticLogger
    let engine: WorkspaceEngine
    @State private var admissionRecords: [WindowAdmissionSupportRecord] = []
    @State private var hasLoadedAdmissionRecords = false

    var body: some View {
        Form {
            Section("Debug diagnostics") {
                Button("Copy Recent Diagnostics") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(diagnostics.recentDiagnosticsText(), forType: .string)
                }
                Button("Reveal Diagnostics File") {
                    guard let fileURL = diagnostics.fileURL else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                }
                .disabled(diagnostics.fileURL == nil)
            }
            Section("Window admission") {
                HStack {
                    Text("Privacy-safe current classifications")
                    Spacer()
                    Button("Refresh") { refreshAdmissionRecords() }
                }
                if !hasLoadedAdmissionRecords {
                    Text("Choose Refresh to inspect the app and Accessibility metadata used to manage, float, defer, or ignore current windows.")
                        .foregroundStyle(.secondary)
                } else if admissionRecords.isEmpty {
                    ContentUnavailableView(
                        "No Window Classifications",
                        systemImage: "rectangle.dashed",
                        description: Text("No current admission records are available.")
                    )
                } else {
                    List(admissionRecords) { record in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(record.bundleIdentifier)
                                    .font(.body.monospaced())
                                Spacer()
                                Text(record.disposition)
                                    .font(.caption.weight(.semibold))
                            }
                            Text("Reason: \(record.reason) · AX: \(record.role) / \(record.subrole) · layer \(record.windowLayer) · window \(record.id)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                    .frame(minHeight: 180)
                }
                Text("This view never includes window titles, document names, URLs, typed content, file paths, or window contents. Refresh reads the engine's existing classification snapshot and does not move or refocus windows.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Privacy and retention") {
                Text("Debug logs rotate at 1 MB with two backups. They include safe internal IDs, workspace/display decisions, frames, command correlations, and success/failure results.")
                Text("They do not include window titles, document names, URLs, typed content, full user paths, or window contents.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private func refreshAdmissionRecords() {
        engine.admissionSupportSnapshot { records in
            admissionRecords = records
            hasLoadedAdmissionRecords = true
        }
    }
}
#endif

struct ShortcutCaps: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height),
            subviews: subviews
        )
        for (index, point) in result.points.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let width = proposal.width ?? .infinity
        var points: [CGPoint] = []
        var cursor = CGPoint.zero
        var lineHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursor.x > 0, cursor.x + size.width > width {
                cursor.x = 0
                cursor.y += lineHeight + spacing
                lineHeight = 0
            }
            points.append(cursor)
            cursor.x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            usedWidth = max(usedWidth, cursor.x - spacing)
        }
        return (CGSize(width: min(usedWidth, width), height: cursor.y + lineHeight), points)
    }
}
