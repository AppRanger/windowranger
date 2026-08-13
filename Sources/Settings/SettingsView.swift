import AppKit
import ApplicationServices
import SwiftUI

enum SettingsWindowMetrics {
    static let minimumSize = CGSize(width: 760, height: 560)
    static let defaultSize = CGSize(width: 1280, height: 780)
    static let sidebarWidth: CGFloat = 240
    static let masterListWidth: CGFloat = 300
    static let masterRowMinimumHeight: CGFloat = 44
    static let masterActionRowVerticalPadding: CGFloat = 9
    static let masterActionIconSize: CGFloat = 16
    static let appRuleTrailingControlWidth: CGFloat = 220

    static func constrainedFrameSize(
        currentSize: CGSize,
        availableSize: CGSize
    ) -> CGSize {
        CGSize(
            width: min(max(currentSize.width, minimumSize.width), availableSize.width),
            height: min(max(currentSize.height, minimumSize.height), availableSize.height)
        )
    }
}

enum SettingsDetailLayout: Equatable, Sendable {
    case compact
    case wide

    static let wideBreakpoint: CGFloat = 900

    static func resolve(availableWidth: CGFloat) -> SettingsDetailLayout {
        availableWidth >= wideBreakpoint ? .wide : .compact
    }
}

struct SettingsBuildIdentity: Equatable, Sendable {
    let version: String
    let build: String
    let commit: String
    let isDebugBuild: Bool

    static var current: SettingsBuildIdentity {
        let info = Bundle.main.infoDictionary ?? [:]
        return SettingsBuildIdentity(
            version: info["CFBundleShortVersionString"] as? String ?? "Unknown",
            build: info["CFBundleVersion"] as? String ?? "Unknown",
            commit: normalizedCommit(info["WindowRangerGitCommit"] as? String),
            isDebugBuild: _isDebugAssertConfiguration()
        )
    }

    var versionText: String {
        "Version \(version) (\(build))"
    }

    var sourceText: String {
        [isDebugBuild ? "Dev" : nil, commit].compactMap { $0 }.joined(separator: " · ")
    }

    var accessibilityText: String {
        "\(versionText), \(sourceText.replacingOccurrences(of: " · ", with: ", "))"
    }

    private static func normalizedCommit(_ value: String?) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              !value.contains("$(")
        else { return "unknown commit" }
        return value
    }
}

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    let engine: WorkspaceEngine
    @ObservedObject var navigation: SettingsNavigationModel
    let windowCoordinator: SettingsWindowCoordinator
    let diagnostics: DiagnosticLogger
    let shortcutRecordingStateChanged: (Bool) -> Void

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                settingsSidebar
                    .frame(width: SettingsWindowMetrics.sidebarWidth)
                Divider()
                GeometryReader { geometry in
                    detail
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height,
                            alignment: .topLeading
                        )
                }
                .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(
            minWidth: SettingsWindowMetrics.minimumSize.width,
            idealWidth: SettingsWindowMetrics.defaultSize.width,
            maxWidth: .infinity,
            minHeight: SettingsWindowMetrics.minimumSize.height,
            idealHeight: SettingsWindowMetrics.defaultSize.height,
            maxHeight: .infinity
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
        VStack(spacing: 0) {
            SettingsSearchField(text: $navigation.searchText)
                .frame(height: 28)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Group {
                if navigation.searchText.isEmpty {
                    List(selection: Binding(
                        get: { Optional(navigation.selectedCategory) },
                        set: {
                            if let category = $0, category != navigation.selectedCategory {
                                DispatchQueue.main.async {
                                    navigation.select(category)
                                }
                            }
                        }
                    )) {
                        Section("WindowRanger") {
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
                    .scrollContentBackground(.hidden)
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
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxHeight: .infinity)

            Divider()
            VStack(alignment: .leading, spacing: 2) {
                Text(SettingsBuildIdentity.current.versionText)
                Text(SettingsBuildIdentity.current.sourceText)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(SettingsBuildIdentity.current.accessibilityText)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
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
                    AppRulesSettingsView(store: store, engine: engine)
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

private struct SettingsSearchField: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.placeholderString = "Search"
        searchField.setAccessibilityLabel("Search Settings")
        searchField.sendsSearchStringImmediately = true
        searchField.delegate = context.coordinator
        return searchField
    }

    func updateNSView(_ searchField: NSSearchField, context: Context) {
        if searchField.stringValue != text {
            searchField.stringValue = text
        }
        context.coordinator.text = $text
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let searchField = notification.object as? NSSearchField else { return }
            text.wrappedValue = searchField.stringValue
        }
    }
}

private struct SettingsDetailContainer<Content: View>: View {
    let category: SettingsCategory
    let highlightedEntry: SettingsSearchEntry?
    @ViewBuilder let content: () -> Content

    var body: some View {
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
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .accessibilityLabel("Search result: \(highlightedEntry.title). \(highlightedEntry.description)")
            }
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle(category.title)
    }
}

private struct SettingsActionRow<Action: View>: View {
    let title: String
    let description: String
    @ViewBuilder let action: () -> Action

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                action()
            }
        }
    }
}

private struct SettingsMasterActionButton: View {
    let systemImage: String
    let role: ButtonRole?
    let action: () -> Void

    init(
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .frame(
                    width: SettingsWindowMetrics.masterActionIconSize,
                    height: SettingsWindowMetrics.masterActionIconSize
                )
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }
}

private struct SettingsCompactDetailHeader: View {
    let backTitle: String
    let title: String
    let goBack: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: goBack) {
                Label(backTitle, systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            .help("Back to \(backTitle)")

            Spacer()

            Text(title)
                .font(.headline)
                .lineLimit(1)

            Spacer()

            Color.clear
                .frame(width: 72, height: 1)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
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
                if let statusMessage = launchAtLogin.statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(launchAtLogin.status == .notFound ? .red : .secondary)
                }
                if launchAtLogin.status == .requiresApproval {
                    Button("Open Login Items Settings", systemImage: "gear") {
                        launchAtLogin.openSystemSettings()
                    }
                }
                Toggle("Sync settings with iCloud", isOn: $store.iCloudSyncEnabled)
                Text("Off by default. When enabled, named profile definitions and supported global preferences sync through your private iCloud key-value store. The active profile, automatic trigger mappings, live window state, and physical monitor bindings always remain local to each Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if store.iCloudSyncEnabled, let issue = store.iCloudProfileLibraryIssue {
                    Label(issue.message, systemImage: "exclamationmark.icloud")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    if issue.canReplaceCloudCopy {
                        Button("Replace iCloud Profile Library with This Mac") {
                            store.replaceICloudProfileLibraryWithLocalCopy()
                        }
                    }
                }
                if let errorMessage = launchAtLogin.errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Menu Bar") {
                LabeledContent("Presentation") {
                    HStack {
                        Spacer()
                        Picker("Presentation", selection: $store.menuBarPresentationMode) {
                            ForEach(MenuBarPresentationMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    .frame(width: 280)
                }
                LabeledContent("Workspace Labels") {
                    HStack {
                        Spacer()
                        Picker("Workspace Labels", selection: $store.menuBarWorkspaceLabelMode) {
                            ForEach(MenuBarWorkspaceLabelMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    .frame(width: 280)
                }
                Text("Show each workspace's full name or its single shortcut key. Full names may still compact when menu-bar space is limited.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Highlight Colour") {
                    HStack {
                        Spacer()
                        ColorPicker(
                            "Highlight Colour",
                            selection: Binding(
                                get: { store.menuBarHighlightColor.color },
                                set: { color in
                                    if let resolved = MenuBarHighlightColor(nsColor: NSColor(color)) {
                                        store.menuBarHighlightColor = resolved
                                    }
                                }
                            ),
                            supportsOpacity: false
                        )
                        .labelsHidden()
                    }
                    .frame(width: 280)
                }
                Text("Choose one highlight colour. WindowRanger automatically derives readable labels, borders, and secondary active states. White keeps the menu bar monochrome.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                MenuBarSettingsPreview(snapshot: MenuBarPresentationResolver.preview(
                    mode: store.menuBarPresentationMode,
                    workspaceLabelMode: store.menuBarWorkspaceLabelMode,
                    displayMode: store.multiDisplayMode,
                    workspaces: store.workspaces,
                    connectedDisplays: store.connectedDisplays,
                    workspaceDisplayAssignments: store.workspaceDisplayAssignments
                ),
                highlightColor: store.menuBarHighlightColor,
                displayIconConfiguration: store.menuBarDisplayIconConfiguration)
                Text(store.menuBarPresentationMode.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if store.menuBarPresentationMode == .full {
                    Text("Only explicit workspace buttons switch. Display areas and group backgrounds remain menu targets; labels compact and overflow is disclosed when menu-bar space is tight.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("In Independent Displays mode, every connected display shows its own active workspace and the interaction display receives the stronger accent. In Unified mode, one combined-displays indicator is shown. Indicators are informational and the whole item opens the app menu.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Recovery") {
                SettingsActionRow(
                    title: "All managed windows",
                    description: "Use this if the app or a display change leaves a managed window parked at the edge of the desktop."
                ) {
                    Button("Bring Back On Screen") {
                        engine.restoreAllWindows()
                    }
                }
            }

            Section("Moving windows") {
                Toggle("Focus follows moved window", isOn: $store.focusFollowsMovedWindow)
                Text(store.focusFollowsMovedWindow
                    ? "Moving a window also opens its destination workspace and focuses it there. The command wheel still shows the effective move action."
                    : "Moving a window keeps you on the source workspace and focuses the next visible local window. The command wheel offers Move & Follow when you want it once.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Trackpad") {
                Toggle("Swipe between workspaces", isOn: $store.workspaceSwipeEnabled)
                LabeledContent("Swipe with") {
                    Picker("Swipe with", selection: $store.workspaceSwipeFingerCount) {
                        ForEach(WorkspaceSwipeFingerCount.allCases) { fingerCount in
                            Text(fingerCount.title).tag(fingerCount)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                .disabled(!store.workspaceSwipeEnabled)
                if let issue = store.workspaceSwipeRuntimeIssue {
                    Label(issue, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("Off by default and local to this Mac. One horizontal swipe moves to the previous or next workspace and wraps at either end. In Independent Displays mode it follows the display you are interacting with. macOS system gestures may take precedence.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Window focus") {
                Toggle(
                    "Highlight the focused window",
                    isOn: $store.focusedWindowHighlightEnabled
                )
                LabeledContent("Border Colour") {
                    ColorPicker(
                        "Border Colour",
                        selection: Binding(
                            get: { store.focusedWindowHighlightColor.color },
                            set: { color in
                                if let resolved = MenuBarHighlightColor(nsColor: NSColor(color)) {
                                    store.focusedWindowHighlightColor = resolved
                                }
                            }
                        ),
                        supportsOpacity: false
                    )
                    .labelsHidden()
                }
                .disabled(!store.focusedWindowHighlightEnabled)
                Toggle(
                    "Only in Tiled workspaces",
                    isOn: $store.focusedWindowHighlightTiledOnly
                )
                .disabled(!store.focusedWindowHighlightEnabled)
                Toggle(
                    "Only when the workspace has multiple windows",
                    isOn: $store.focusedWindowHighlightMultipleWindowsOnly
                )
                .disabled(!store.focusedWindowHighlightEnabled)
                Text("Off by default and local to this Mac. Workspace filters hide the border when their condition is not met. Tiled and Accordion layouts still reserve four points at screen edges while highlighting is enabled. The click-through border never takes focus or intercepts input.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Compatibility") {
                Toggle(
                    "Automatically unhide applications when focusing their windows",
                    isOn: $store.automaticallyUnhideApplications
                )
                Text("Off by default. When enabled, WindowRanger only unhides an app while carrying out an explicit focus command, with duplicate attempts throttled to avoid loops.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin.refresh()
        }
    }

}

private struct ProfilesSettingsView: View {
    @ObservedObject var store: SettingsStore
    @Environment(\.undoManager) private var undoManager
    @StateObject private var transferCoordinator: ProfileTransferCoordinator
    @State private var pendingProfileDeletion: UUID?
    @State private var pendingProfileImport: ProfileImportPlan?
    @State private var transferNotice: ProfileTransferNotice?
    @State private var isCreatingProfile = false
    @State private var profileBeingRenamed: ProfileRenameRequest?
    @State private var showsCompactDetails = false

    init(store: SettingsStore) {
        self.store = store
        _transferCoordinator = StateObject(wrappedValue: ProfileTransferCoordinator(
            diagnostics: store.profileTransferDiagnosticLogger
        ))
    }

    var body: some View {
        GeometryReader { geometry in
            responsiveContent(for: SettingsDetailLayout.resolve(availableWidth: geometry.size.width))
        }
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
        .sheet(isPresented: $isCreatingProfile) {
            NewProfileView(
                currentProfileName: store.activeProfile.name,
                cancel: { isCreatingProfile = false },
                create: { name, source in
                    _ = store.createProfile(named: name, source: source)
                    isCreatingProfile = false
                }
            )
        }
        .sheet(item: $profileBeingRenamed) { request in
            RenameProfileView(
                currentName: request.currentName,
                cancel: { profileBeingRenamed = nil },
                rename: { name in
                    store.renameProfile(request.id, to: name)
                    profileBeingRenamed = nil
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
    private func responsiveContent(for layout: SettingsDetailLayout) -> some View {
        switch layout {
        case .wide:
            HStack(spacing: 0) {
                profileListColumn()
                    .frame(width: SettingsWindowMetrics.masterListWidth)
                    .frame(maxHeight: .infinity)
                Divider()
                automaticSelectionForm(includesProfileManagement: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .compact:
            VStack(spacing: 0) {
                if showsCompactDetails {
                    SettingsCompactDetailHeader(
                        backTitle: "Profiles",
                        title: store.activeProfile.name,
                        goBack: { showsCompactDetails = false }
                    )
                    Divider()
                    automaticSelectionForm(includesProfileManagement: true)
                } else {
                    profileListColumn(showsDisclosure: true)
                }
            }
        }
    }

    private func profileListColumn(showsDisclosure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Profiles")
                    .font(.headline)
                Text("Choose the reusable configuration active on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            List(selection: Binding(
                get: { Optional(store.activeProfileID) },
                set: { profileID in
                    if let profileID {
                        if profileID != store.activeProfileID {
                            store.selectProfile(profileID)
                        }
                        if showsDisclosure { showsCompactDetails = true }
                    }
                }
            )) {
                ForEach(store.profiles) { profile in
                    profileListRow(profile, showsDisclosure: showsDisclosure)
                        .tag(profile.id)
                        .onTapGesture {
                            if profile.id != store.activeProfileID {
                                store.selectProfile(profile.id)
                            }
                            if showsDisclosure { showsCompactDetails = true }
                        }
                        .contextMenu {
                            Button("Use Profile") { store.selectProfile(profile.id) }
                                .disabled(profile.id == store.activeProfileID)
                            Button("Rename…") {
                                profileBeingRenamed = ProfileRenameRequest(profile: profile)
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                pendingProfileDeletion = profile.id
                            }
                            .disabled(store.profiles.count == 1)
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(
                \.defaultMinListRowHeight,
                SettingsWindowMetrics.masterRowMinimumHeight
            )

            Divider()

            HStack(spacing: 8) {
                SettingsMasterActionButton(systemImage: "plus") { isCreatingProfile = true }
                .help("New profile")
                .accessibilityLabel("New profile")

                SettingsMasterActionButton(systemImage: "pencil") {
                    profileBeingRenamed = ProfileRenameRequest(profile: store.activeProfile)
                }
                .help("Rename selected profile")
                .accessibilityLabel("Rename selected profile")

                SettingsMasterActionButton(systemImage: "trash", role: .destructive) {
                    pendingProfileDeletion = store.activeProfileID
                }
                .disabled(store.profiles.count == 1)
                .help("Delete selected profile")
                .accessibilityLabel("Delete selected profile")

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, SettingsWindowMetrics.masterActionRowVerticalPadding)

            Divider()

            SettingsActionRow(
                title: "Profile library",
                description: "Import adds reusable profiles without changing the active profile or this Mac's local bindings. Export includes every profile."
            ) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        Button("Import…", systemImage: "square.and.arrow.down") {
                            prepareProfileImport()
                        }
                        Button("Export All…", systemImage: "square.and.arrow.up") {
                            exportProfiles()
                        }
                    }
                    VStack(alignment: .trailing, spacing: 8) {
                        Button("Import…", systemImage: "square.and.arrow.down") {
                            prepareProfileImport()
                        }
                        Button("Export All…", systemImage: "square.and.arrow.up") {
                            exportProfiles()
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func automaticSelectionForm(includesProfileManagement: Bool) -> some View {
        Form {
            if includesProfileManagement {
                Section("Selection") {
                    LabeledContent("Active profile", value: store.activeProfile.name)
                    LabeledContent("Selection mode", value: store.activeProfileSelectionReason.title)
                    if store.manualPinnedProfileID != nil {
                        Button("Resume Automatic", systemImage: "arrow.triangle.2.circlepath") {
                            store.resumeAutomaticProfileSelection()
                        }
                        Text("This profile remains pinned on this Mac until automatic selection resumes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Automatic selection uses exact display mappings, dock state, then this Mac's default profile.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Automatic Selection") {
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
                Text("Dock rules apply to portable Macs. Desktop Macs fall through to an exact display mapping or the local default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()
                HStack {
                    Text("Exact display setups").font(.headline)
                    Spacer()
                    Button("Map Current Displays", systemImage: "display.2") {
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
                                ForEach(store.profiles) { profile in Text(profile.name).tag(profile.id) }
                            }
                            .labelsHidden()
                            .frame(width: 170)
                            Button(role: .destructive) {
                                store.removeExactTrigger(trigger.id)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                Text("Automatic selection rules and the active profile are local to this Mac and never cause another Mac to switch profiles.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Display Roles") {
                ForEach(store.activeProfile.displayRoles) { role in
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Role name") {
                            HStack(spacing: 8) {
                                Spacer()
                                TextField("Role name", text: Binding(
                                    get: {
                                        store.activeProfile.displayRoles.first(where: { $0.id == role.id })?.name
                                            ?? role.name
                                    },
                                    set: { store.renameDisplayRole(role.id, to: $0) }
                                ))
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 220)

                                Button(role: .destructive) {
                                    _ = store.deleteDisplayRole(role.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .frame(width: 20)
                                .disabled(store.activeProfile.displayRoles.count == 1)
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }

                        LabeledContent("This Mac's display") {
                            HStack(spacing: 8) {
                                Spacer()
                                Picker("This Mac's display", selection: Binding<String?>(
                                    get: { store.roleBindings[role.id]?.lastKnownIdentifier },
                                    set: { store.bindDisplayRole(role.id, to: $0) }
                                )) {
                                    Text("Unbound — safe main-display fallback").tag(nil as String?)
                                    ForEach(roleDisplayOptions(role.id)) { display in
                                        Text(display.name).tag(Optional(display.identifier))
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 220, alignment: .trailing)
                                Color.clear.frame(width: 20, height: 1)
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }

                        LabeledContent("Menu bar icon") {
                            HStack(spacing: 8) {
                                Spacer()
                                Picker(
                                    "Menu bar icon",
                                    selection: Binding(
                                        get: {
                                            store.menuBarDisplayIconStyle(forRole: role.id)
                                        },
                                        set: {
                                            store.setMenuBarDisplayIconStyle($0, forRole: role.id)
                                        }
                                    )
                                ) {
                                    ForEach(MenuBarDisplayIconStyle.allCases) { style in
                                        Label(
                                            style.title,
                                            systemImage: style.pickerSystemImage
                                        ).tag(style)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 220, alignment: .trailing)
                                Color.clear.frame(width: 20, height: 1)
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        if let note = roleBindingNote(role.id) {
                            Text(note).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button("Add Display Role", systemImage: "plus") {
                        _ = store.addDisplayRole()
                    }
                }
                Text("Role names, workspace assignments, and menu-bar icons sync with the profile. Physical monitor bindings stay on this Mac. Automatic derives the icon from the display bound here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func profileListRow(
        _ profile: WindowManagerProfile,
        showsDisclosure: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: profile.id == store.activeProfileID
                ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(profile.id == store.activeProfileID ? Color.accentColor : .secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(profileSummary(profile))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 3)
        .frame(minHeight: SettingsWindowMetrics.masterRowMinimumHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(profile.name), \(profileSummary(profile))")
        .accessibilityHint(showsDisclosure
            ? "Opens profile details"
            : profile.id == store.activeProfileID ? "Active profile" : "Selects this profile")
    }

    private func prepareProfileImport() {
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

    private func exportProfiles() {
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

    private func profileSummary(_ profile: WindowManagerProfile) -> String {
        let workspaceLabel = profile.workspaces.count == 1 ? "workspace" : "workspaces"
        let roleLabel = profile.displayRoles.count == 1 ? "display role" : "display roles"
        let ruleLabel = profile.appRules.count == 1 ? "app rule" : "app rules"
        return "\(profile.workspaces.count) \(workspaceLabel) · "
            + "\(profile.displayRoles.count) \(roleLabel) · "
            + "\(profile.appRules.count) \(ruleLabel)"
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
            "Two identical monitors match. WindowRanger will not guess; this role uses the safe main-display fallback."
        case .disconnected:
            "The bound monitor is disconnected. Its role is preserved and will return on reconnect."
        case .exactIdentifier, .exactUUID, .portableFingerprint:
            "Bound using a stable runtime identity with a conservative monitor-fingerprint fallback."
        case nil:
            "Unbound on this Mac; workspaces using this role fall back safely without changing the synced profile."
        }
    }
}

private struct ProfileRenameRequest: Identifiable {
    let id: UUID
    let currentName: String

    init(profile: WindowManagerProfile) {
        id = profile.id
        currentName = profile.name
    }
}

private struct RenameProfileView: View {
    let currentName: String
    let cancel: () -> Void
    let rename: (String) -> Void
    @State private var name: String
    @FocusState private var isNameFocused: Bool

    init(currentName: String, cancel: @escaping () -> Void, rename: @escaping (String) -> Void) {
        self.currentName = currentName
        self.cancel = cancel
        self.rename = rename
        _name = State(initialValue: currentName)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Rename Profile")
                    .font(.title2.weight(.semibold))
                Text("Choose a new name for “\(currentName)”.")
                    .foregroundStyle(.secondary)
            }

            TextField("Profile name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)

            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Rename") {
                    rename(trimmedName)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty || trimmedName == currentName)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear { isNameFocused = true }
    }
}

private struct NewProfileView: View {
    let currentProfileName: String
    let cancel: () -> Void
    let create: (String, ProfileCreationSource) -> Void
    @State private var name = ""
    @State private var source: ProfileCreationSource = .currentProfile
    @FocusState private var isNameFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("New Profile")
                    .font(.title2.weight(.semibold))
                Text("Name the profile and choose its starting point.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Profile name")
                    .font(.headline)
                TextField("For example, Work or Travel", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFocused)
            }

            Picker("Starting point", selection: $source) {
                Text("Copy Current Profile").tag(ProfileCreationSource.currentProfile)
                Text("Start from Scratch").tag(ProfileCreationSource.scratch)
            }
            .pickerStyle(.radioGroup)

            Group {
                switch source {
                case .currentProfile:
                    Text("Copies “\(currentProfileName)” including its workspaces, display mode and roles, workspace assignments, and app rules.")
                case .scratch:
                    Text("Creates a clean profile with four workspaces—1, 2, 3, and 4—assigned to their matching keys.")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Create Profile") {
                    create(trimmedName, source)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear { isNameFocused = true }
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

@MainActor
enum WorkspaceSettingsFieldBindings {
    static func name(store: SettingsStore, workspaceID: UUID) -> Binding<String> {
        Binding(
            get: {
                store.workspaces.first(where: { $0.id == workspaceID })?.name ?? ""
            },
            set: { store.setWorkspaceName($0, for: workspaceID) }
        )
    }

    static func key(store: SettingsStore, workspaceID: UUID) -> Binding<String> {
        Binding(
            get: {
                store.workspaces.first(where: { $0.id == workspaceID })?.key.uppercased() ?? ""
            },
            set: { store.setWorkspaceKey($0, for: workspaceID) }
        )
    }

    static func layout(store: SettingsStore, workspaceID: UUID) -> Binding<WorkspaceLayout> {
        Binding(
            get: {
                store.workspaces.first(where: { $0.id == workspaceID })?.layout ?? .none
            },
            set: { store.setLayout($0, for: workspaceID) }
        )
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
    @State private var showsCompactInspector: Bool

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
        let initialWorkspaceID = requestedWorkspaceID ?? highlightedEntry?.workspaceID
            ?? initiallySelectedWorkspaceID
        _selectedWorkspaceID = State(
            initialValue: initialWorkspaceID
        )
        _showsCompactInspector = State(initialValue: initialWorkspaceID != nil)
    }

    var body: some View {
        GeometryReader { geometry in
            responsiveContent(for: SettingsDetailLayout.resolve(availableWidth: geometry.size.width))
        }
        .onAppear {
            reconcileSelection(preferred: requestedWorkspaceID ?? highlightedEntry?.workspaceID)
        }
        .onChange(of: store.workspaces.map(\.id)) { _, _ in reconcileSelection() }
        .onChange(of: store.activeProfileID) { _, _ in reconcileSelection() }
        .onChange(of: highlightedEntry?.workspaceID) { _, workspaceID in
            reconcileSelection(preferred: workspaceID)
            if workspaceID != nil { showsCompactInspector = true }
        }
        .onChange(of: requestedWorkspaceID) { _, workspaceID in
            reconcileSelection(preferred: workspaceID)
            if workspaceID != nil { showsCompactInspector = true }
        }
    }

    @ViewBuilder
    private func responsiveContent(for layout: SettingsDetailLayout) -> some View {
        switch layout {
        case .wide:
            HStack(spacing: 0) {
                masterColumn()
                    .frame(width: SettingsWindowMetrics.masterListWidth)
                    .frame(maxHeight: .infinity)
                Divider()
                inspectorColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .compact:
            VStack(spacing: 0) {
                if showsCompactInspector {
                    SettingsCompactDetailHeader(
                        backTitle: "Workspaces",
                        title: selectedWorkspace?.name ?? "Workspace",
                        goBack: { showsCompactInspector = false }
                    )
                    Divider()
                    inspectorColumn
                } else {
                    masterColumn(showsDisclosure: true)
                }
            }
        }
    }

    private func masterColumn(showsDisclosure: Bool = false) -> some View {
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

            List(selection: Binding(
                get: { selectedWorkspaceID },
                set: { workspaceID in
                    selectedWorkspaceID = workspaceID
                    if showsDisclosure, workspaceID != nil {
                        showsCompactInspector = true
                    }
                }
            )) {
                ForEach(store.workspaces) { workspace in
                    workspaceRow(workspace, showsDisclosure: showsDisclosure)
                        .tag(workspace.id)
                        .onTapGesture {
                            selectedWorkspaceID = workspace.id
                            if showsDisclosure { showsCompactInspector = true }
                        }
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
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(
                \.defaultMinListRowHeight,
                SettingsWindowMetrics.masterRowMinimumHeight
            )

            Divider()

            HStack(spacing: 8) {
                SettingsMasterActionButton(systemImage: "plus") {
                    selectedWorkspaceID = store.addWorkspace()
                    if showsDisclosure { showsCompactInspector = true }
                }
                .help("Add workspace")
                .accessibilityLabel("Add workspace")

                SettingsMasterActionButton(systemImage: "square.on.square") {
                    duplicateSelectedWorkspace()
                }
                .disabled(selectedWorkspace == nil)
                .help("Duplicate selected workspace")
                .accessibilityLabel("Duplicate selected workspace")

                SettingsMasterActionButton(systemImage: "trash", role: .destructive) {
                    deleteSelectedWorkspace()
                }
                .disabled(store.workspaces.count <= 1 || selectedWorkspace == nil)
                .help("Delete selected workspace")
                .accessibilityLabel("Delete selected workspace")

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, SettingsWindowMetrics.masterActionRowVerticalPadding)

            Divider()

            VStack(spacing: 12) {
                SettingsActionRow(
                    title: "Active workspace",
                    description: "Recover the interaction display's active workspace, clear transient positioning, and reapply its current layout."
                ) {
                    Button("Bring Windows Back On Screen") {
                        engine.resetCurrentWorkspace()
                    }
                }

                Divider()

                SettingsActionRow(
                    title: "Workspace collection",
                    description: "Restore WindowRanger's built-in workspace names, order, keys, and layout choices."
                ) {
                    Button("Restore Defaults") {
                        store.resetToWindowManagerDefaults()
                        reconcileSelection()
                    }
                    .help(SettingsCopy.restoreWindowManagerDefaultsTitle)
                    .accessibilityLabel(SettingsCopy.restoreWindowManagerDefaultsTitle)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .background(Color(nsColor: .controlBackgroundColor))
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
            .id(workspace.id)
        } else {
            ContentUnavailableView(
                "No Workspace Selected",
                systemImage: "square.grid.3x3",
                description: Text("Add or select a workspace to configure it.")
            )
        }
    }

    private func inspectorHeader(_ workspace: WorkspaceDefinition) -> some View {
        HStack(spacing: 10) {
            Image(systemName: workspace.layout.systemImage)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                TextField(
                    "Workspace name",
                    text: WorkspaceSettingsFieldBindings.name(
                        store: store,
                        workspaceID: workspace.id
                    )
                )
                .textFieldStyle(.roundedBorder)
                .font(.headline)
                .accessibilityLabel("Workspace name")

                Text("\(displayRoleName(for: workspace.id)) · \(workspace.layout.title)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
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
                    TextField(
                        "Key",
                        text: WorkspaceSettingsFieldBindings.key(
                            store: store,
                            workspaceID: workspace.id
                        )
                    )
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
                Picker(
                    "Layout Style",
                    selection: WorkspaceSettingsFieldBindings.layout(
                        store: store,
                        workspaceID: workspace.id
                    )
                ) {
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
                    Text("Freeform leaves window frames under manual control. WindowRanger still manages workspace visibility, focus, persistence, display assignment, and quit/wake recovery.")
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
                SettingsActionRow(
                    title: "Selected workspace",
                    description: "Restore Freeform and WindowRanger's built-in geometry while keeping its name, key, Home Display, app rules, and live window membership. This settings change can be undone."
                ) {
                    Button("Reset Workspace", systemImage: "arrow.counterclockwise") {
                        store.resetWorkspaceSettings(workspace.id, undoManager: undoManager)
                    }
                }
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
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) {
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
                VStack(alignment: .leading, spacing: 8) {
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
            ViewThatFits(in: .horizontal) {
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
                VStack(alignment: .leading, spacing: 8) {
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

    private func workspaceRow(
        _ workspace: WorkspaceDefinition,
        showsDisclosure: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: workspace.layout.systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
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
            Text("⌃⌥\(workspace.key.uppercased())")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 3)
        .frame(minHeight: SettingsWindowMetrics.masterRowMinimumHeight)
        .contentShape(Rectangle())
        .help("\(workspace.name) — \(displayRoleName(for: workspace.id)), \(workspace.layout.title), key \(workspace.key.uppercased())")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WorkspaceSettingsAccessibility.rowLabel(
            workspace: workspace,
            displayRoleName: displayRoleName(for: workspace.id)
        ))
        .accessibilityHint(showsDisclosure ? "Opens workspace details" : "Selects this workspace")
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
        else { return "No display role is assigned; WindowRanger uses the safe main-display fallback." }
        switch store.roleBindingResolution(roleID) {
        case .ambiguous:
            return "\(role.name) matches multiple identical monitors, so WindowRanger will not guess and uses the safe main-display fallback."
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
    let engine: WorkspaceEngine
    @Environment(\.undoManager) private var undoManager
    @State private var showsAppPicker = false
    @State private var selectedRuleID: AppRule.ID?
    @State private var showsCompactEditor = false

    var body: some View {
        GeometryReader { geometry in
            responsiveContent(for: SettingsDetailLayout.resolve(availableWidth: geometry.size.width))
        }
        .onAppear { reconcileSelection() }
        .onChange(of: store.appRules.map(\.id)) { _, _ in reconcileSelection() }
        .sheet(isPresented: $showsAppPicker) {
            InstalledApplicationPicker(
                excludedBundleIdentifiers: Set(store.appRules.map { $0.bundleIdentifier.lowercased() })
            ) { application in
                addRule(for: application)
            }
        }
    }

    @ViewBuilder
    private func responsiveContent(for layout: SettingsDetailLayout) -> some View {
        switch layout {
        case .wide:
            HStack(spacing: 0) {
                ruleListColumn()
                    .frame(width: SettingsWindowMetrics.masterListWidth)
                    .frame(maxHeight: .infinity)
                Divider()
                ruleInspectorColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .compact:
            VStack(spacing: 0) {
                if showsCompactEditor {
                    SettingsCompactDetailHeader(
                        backTitle: "Applications",
                        title: selectedRule?.displayName ?? "Application Rule",
                        goBack: { showsCompactEditor = false }
                    )
                    Divider()
                    ruleInspectorColumn
                } else {
                    ruleListColumn(showsDisclosure: true)
                }
            }
        }
    }

    private func ruleListColumn(showsDisclosure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Application Rules")
                    .font(.headline)
                Text("Choose an application to edit its workspace and window behavior.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if store.appRules.isEmpty {
                ContentUnavailableView(
                    "No Application Rules",
                    systemImage: "app.badge",
                    description: Text("Add an installed or currently running app to create a rule.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: Binding(
                    get: { selectedRuleID },
                    set: { selection in
                        selectedRuleID = selection
                        if showsDisclosure, selection != nil { showsCompactEditor = true }
                    }
                )) {
                    ForEach(store.appRules) { rule in
                        ruleListRow(rule, showsDisclosure: showsDisclosure)
                            .tag(rule.id)
                            .onTapGesture {
                                selectedRuleID = rule.id
                                if showsDisclosure { showsCompactEditor = true }
                            }
                            .contextMenu {
                                Button("Remove Rule", role: .destructive) {
                                    selectedRuleID = rule.id
                                    removeSelectedRule()
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(
                    \.defaultMinListRowHeight,
                    SettingsWindowMetrics.masterRowMinimumHeight
                )
            }

            Divider()

            HStack(spacing: 8) {
                SettingsMasterActionButton(systemImage: "plus") { showsAppPicker = true }
                .help("Add application rule")
                .accessibilityLabel("Add application rule")

                SettingsMasterActionButton(systemImage: "trash", role: .destructive) {
                    removeSelectedRule()
                }
                .disabled(selectedRule == nil)
                .help("Remove selected rule")
                .accessibilityLabel("Remove selected rule")

                SettingsMasterActionButton(systemImage: "arrow.uturn.backward") {
                    undoManager?.undo()
                }
                .disabled(!(undoManager?.canUndo ?? false))
                .help("Undo last rule change")
                .accessibilityLabel("Undo last rule change")

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, SettingsWindowMetrics.masterActionRowVerticalPadding)

            Text("Behavior changes apply immediately, support Command-Z, and sync through iCloud when enabled. This-Mac appearance overrides stay local.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var ruleInspectorColumn: some View {
        if let rule = selectedRule {
            AppRuleEditor(
                store: store,
                rule: Binding(
                    get: { store.appRules.first(where: { $0.id == rule.id }) ?? rule },
                    set: { store.updateAppRule($0, undoManager: undoManager) }
                ),
                workspaces: store.workspaces
            )
            .id(rule.id)
        } else {
            ContentUnavailableView(
                "No Rule Selected",
                systemImage: "app.badge",
                description: Text("Add or select an application rule to configure it.")
            )
        }
    }

    private func ruleListRow(_ rule: AppRule, showsDisclosure: Bool) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: appIcon(bundleIdentifier: rule.bundleIdentifier))
                .resizable()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(rule.displayName)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if !rule.isEnabled {
                        Text("Paused")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(ruleSummary(rule))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 3)
        .frame(minHeight: SettingsWindowMetrics.masterRowMinimumHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(showsDisclosure ? "Opens application rule details" : "")
    }

    private var selectedRule: AppRule? {
        selectedRuleID.flatMap { id in store.appRules.first { $0.id == id } }
    }

    private func reconcileSelection() {
        if let selectedRuleID, store.appRules.contains(where: { $0.id == selectedRuleID }) {
            return
        }
        selectedRuleID = store.appRules.first?.id
    }

    private func removeSelectedRule() {
        guard let selectedRule else { return }
        let ids = store.appRules.map(\.id)
        let index = ids.firstIndex(of: selectedRule.id) ?? 0
        let nextID: AppRule.ID? = if ids.count <= 1 {
            nil
        } else if index < ids.count - 1 {
            ids[index + 1]
        } else {
            ids[index - 1]
        }
        store.removeAppRule(bundleIdentifier: selectedRule.bundleIdentifier)
        selectedRuleID = nextID
        if nextID == nil { showsCompactEditor = false }
    }

    private func addRule(for application: InstalledApplication) {
        guard application.isRunning else {
            finishAddingRule(for: application, defaultWorkspaceID: nil)
            return
        }
        engine.appRuleDefaultWorkspaceID(forBundleIdentifier: application.bundleIdentifier) {
            workspaceID in
            finishAddingRule(for: application, defaultWorkspaceID: workspaceID)
        }
    }

    private func finishAddingRule(
        for application: InstalledApplication,
        defaultWorkspaceID: UUID?
    ) {
        store.addAppRule(for: application, defaultWorkspaceID: defaultWorkspaceID)
        selectedRuleID = application.bundleIdentifier.lowercased()
        showsCompactEditor = true
        showsAppPicker = false
    }

    private func ruleSummary(_ rule: AppRule) -> String {
        if !rule.isEnabled { return "Rule paused" }
        if rule.keepsOnAllWorkspaces { return "All workspaces" }
        if let id = rule.assignedWorkspaceID,
           let workspace = store.workspaces.first(where: { $0.id == id }) {
            return workspace.name
        }
        return "Current workspace"
    }

    private func appIcon(bundleIdentifier: String) -> NSImage {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)
            ?? NSImage()
    }
}

private struct AppRuleEditor: View {
    @ObservedObject var store: SettingsStore
    @Binding var rule: AppRule
    let workspaces: [WorkspaceDefinition]
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.displayName)
                            .font(.headline)
                        Text(rule.bundleIdentifier)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    HStack(spacing: 10) {
                        Text("Enabled")
                        Toggle("Enabled", isOn: $rule.isEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .accessibilityLabel("Enabled")
                    }
                    .fixedSize()
                    .help(rule.isEnabled ? "Pause this rule" : "Resume this rule")
                }
            }

            Section("Behavior") {
                LabeledContent("Workspace") { workspacePicker }
                Toggle("Keep on all workspaces", isOn: keepEverywhereBinding)
                Toggle("Do not include in Tiled or Accordion", isOn: layoutExclusionBinding)
                Toggle("Float detected dialogs and secondary windows", isOn: floatDialogsBinding)
                    .disabled(rule.excludesFromLayout)
            }
            .disabled(!rule.isEnabled)
            .opacity(rule.isEnabled ? 1 : 0.62)

            Section("Focused Window Border") {
                Toggle("Use a custom corner radius", isOn: customCornerRadiusBinding)
                if let radius = cornerRadiusOverride {
                    LabeledContent("Corner radius") {
                        HStack(spacing: 8) {
                            Text("\(radius, specifier: "%.0f") pt")
                                .monospacedDigit()
                                .frame(minWidth: 42, alignment: .trailing)
                            Stepper(
                                "Corner radius",
                                value: cornerRadiusBinding,
                                in: FocusedWindowHighlightPolicy.cornerRadiusRange,
                                step: 1
                            )
                            .labelsHidden()
                        }
                    }
                }
                Text("Automatic uses \(automaticCornerRadius, specifier: "%.0f") pt on macOS \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion). A custom value applies only to this app on this Mac and does not sync with the profile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !rule.isEnabled || rule.keepsOnAllWorkspaces || rule.floatsSecondaryWindows {
                Section("Status") {
                    if !rule.isEnabled {
                        Label(
                            "This rule is paused. Its saved actions will apply again when resumed.",
                            systemImage: "pause.circle"
                        )
                    }
                    if rule.keepsOnAllWorkspaces, rule.assignedWorkspaceID != nil {
                        Label(
                            "Workspace assignment is paused while Keep on all workspaces is enabled.",
                            systemImage: "info.circle"
                        )
                    }
                    if rule.floatsSecondaryWindows {
                        Text(rule.excludesFromLayout
                            ? "The full-app layout exclusion takes precedence while it is enabled."
                            : "Explicit per-window layout choices take precedence. Verified dialogs already float automatically; this rule also covers conservative dialog-like metadata.")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var workspacePicker: some View {
        Picker("Workspace", selection: Binding(
            get: { rule.assignedWorkspaceID },
            set: { rule.assignedWorkspaceID = $0 }
        )) {
            Text("Use current workspace").tag(nil as UUID?)
            ForEach(workspaces) { Text($0.name).tag(Optional($0.id)) }
        }
        .labelsHidden()
        .frame(
            width: SettingsWindowMetrics.appRuleTrailingControlWidth,
            alignment: .trailing
        )
        .disabled(rule.keepsOnAllWorkspaces)
    }

    private var keepEverywhereBinding: Binding<Bool> {
        Binding(
            get: { rule.keepsOnAllWorkspaces },
            set: { rule.keepsOnAllWorkspaces = $0 }
        )
    }

    private var layoutExclusionBinding: Binding<Bool> {
        Binding(
            get: { rule.excludesFromLayout },
            set: { rule.excludesFromLayout = $0 }
        )
    }

    private var floatDialogsBinding: Binding<Bool> {
        Binding(
            get: { rule.floatsSecondaryWindows },
            set: { rule.floatsSecondaryWindows = $0 }
        )
    }

    private var automaticCornerRadius: Double {
        Double(FocusedWindowHighlightPolicy.automaticCornerRadius())
    }

    private var cornerRadiusOverride: Double? {
        store.focusedWindowHighlightCornerRadiusOverride(for: rule.bundleIdentifier)
    }

    private var customCornerRadiusBinding: Binding<Bool> {
        Binding(
            get: { cornerRadiusOverride != nil },
            set: { enabled in
                store.setFocusedWindowHighlightCornerRadiusOverride(
                    enabled ? automaticCornerRadius : nil,
                    for: rule.bundleIdentifier,
                    undoManager: undoManager
                )
            }
        )
    }

    private var cornerRadiusBinding: Binding<Double> {
        Binding(
            get: { cornerRadiusOverride ?? automaticCornerRadius },
            set: { radius in
                store.setFocusedWindowHighlightCornerRadiusOverride(
                    radius,
                    for: rule.bundleIdentifier,
                    undoManager: undoManager
                )
            }
        )
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
            } else if applicationGroups.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                List {
                    if !applicationGroups.openApplications.isEmpty {
                        Section("Open Applications") {
                            ForEach(applicationGroups.openApplications) { application in
                                applicationRow(application)
                            }
                        }
                    }
                    if !applicationGroups.otherApplications.isEmpty {
                        Section("Other Applications") {
                            ForEach(applicationGroups.otherApplications) { application in
                                applicationRow(application)
                            }
                        }
                    }
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

    private var applicationGroups: InstalledApplicationGroups {
        InstalledApplicationPickerPolicy.groups(applications: applications, search: search)
    }

    private func applicationRow(_ application: InstalledApplication) -> some View {
        Button { select(application) } label: {
            HStack(spacing: 10) {
                Image(nsImage: application.bundleURL.map {
                    NSWorkspace.shared.icon(forFile: $0.path)
                } ?? NSImage())
                .resizable()
                .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(application.displayName)
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

    private var directionalMoveCornerStatus: (available: Bool, message: String) {
        if let issue = store.directionalMoveGestureRuntimeIssue {
            return (false, issue)
        }
        switch DirectionalMoveChordFamily.resolve(
            configuration: store.hotKeyConfiguration,
            report: configurationReport
        ) {
        case let .failure(issue):
            return (false, issue.message)
        case .success:
            let directionalActions = Set(DirectionalMoveChordFamily.actionDirections.map(\.0))
            if store.hotKeyRuntimeIssues.contains(where: {
                $0.owner.configurableAction.map(directionalActions.contains) == true
            }) {
                return (
                    false,
                    "macOS must successfully register all four Reorder shortcuts before two-arrow corner placement is available."
                )
            }
            return (
                true,
                "In Tiled workspaces, press two perpendicular Reorder directions within 200 ms to place the focused window in that corner. A single direction keeps its normal reorder behavior."
            )
        }
    }

    private let workspaceActions: [ConfigurableHotKeyAction] = [
        .previousWorkspace, .nextWorkspace, .backAndForthWorkspace, .moveWorkspaceToNextDisplay,
    ]
    private let focusActions: [ConfigurableHotKeyAction] = [
        .previousWindow, .nextWindow, .focusLeft, .focusDown, .focusUp, .focusRight,
    ]
    private let layoutActions: [ConfigurableHotKeyAction] = [
        .selectAccordion, .selectTiled, .toggleFloating,
        .moveLeft, .moveDown, .moveUp, .moveRight, .resizeSmaller, .resizeLarger,
    ]

    var body: some View {
        Form {
            Section {
                Text("Select a global command shortcut to record a replacement. Workspace keys and their derived switch/move shortcuts are configured in Workspaces.")
                    .foregroundStyle(.secondary)
            }

            if !configurationReport.issues.isEmpty || !store.hotKeyRuntimeIssues.isEmpty {
                Section("Needs Attention") {
                    Label(
                        "Some shortcuts are unavailable",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                    Text("Conflicting shortcuts are not registered for either command. A macOS registration failure affects only that command.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Reset Conflicting Custom Shortcuts") {
                        finishRecording()
                        store.resetShortcuts(conflictingCustomActions)
                    }
                    .disabled(conflictingCustomActions.isEmpty)
                    Text("If both commands use built-in defaults, record a different shortcut here or change the affected workspace key in Workspaces.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Workspace Navigation") {
                ForEach(workspaceActions) { action in shortcutRow(action) }
            }

            Section("Window Focus") {
                ForEach(focusActions) { action in shortcutRow(action) }
            }

            Section("Layout and Placement") {
                ForEach(layoutActions) { action in shortcutRow(action) }
                LabeledContent("Select Freeform", value: "Command wheel or Settings")
                    .foregroundStyle(.secondary)

                Label(
                    "Tiled corner placement: \(directionalMoveCornerStatus.message)",
                    systemImage: directionalMoveCornerStatus.available
                        ? "arrow.up.left.and.arrow.down.right"
                        : "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(
                    directionalMoveCornerStatus.available ? Color.secondary : Color.orange
                )
                .accessibilityLabel(
                    directionalMoveCornerStatus.available
                        ? "Two-arrow corner placement available. \(directionalMoveCornerStatus.message)"
                        : "Two-arrow corner placement unavailable. \(directionalMoveCornerStatus.message)"
                )
            }

            if let conflictMessage {
                Section("Recording") {
                    Label(conflictMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Shortcut conflict. \(conflictMessage)")
                }
            }

            Section {
                Button("Reset All Shortcuts") {
                    finishRecording()
                    conflictMessage = nil
                    store.resetAllShortcuts()
                }
                Text("Escape cancels recording. A global shortcut must include Control, Option, or Command.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("App-level layout exclusions remain authoritative. Workspace-specific shortcuts stay with each workspace in Workspaces.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onDisappear { finishRecording() }
    }

    private func shortcutRow(_ action: ConfigurableHotKeyAction) -> some View {
        let chord = store.hotKeyConfiguration.chord(for: action)
        return LabeledContent {
            HStack(spacing: 8) {
                Button {
                    beginRecording(action)
                } label: {
                    if recordingAction == action {
                        Text("Press shortcut…")
                            .frame(minWidth: 110)
                    } else {
                        ShortcutCaps(keys: chord.keyCaps)
                            .frame(minWidth: 110)
                    }
                }
                .buttonStyle(.bordered)
                .help("Record a new global shortcut for \(action.title)")

                Button {
                    if recordingAction == action { finishRecording() }
                    conflictMessage = nil
                    store.resetShortcut(action)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .disabled(store.hotKeyConfiguration.isUsingDefault(for: action))
                .help("Reset \(action.title)")
                .accessibilityLabel("Reset \(action.title)")
            }
        } label: {
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
                LabeledContent("Global shortcut") {
                    HStack(spacing: 8) {
                        Button {
                            beginShortcutRecording()
                        } label: {
                            if isRecordingShortcut {
                                Text("Press shortcut…").frame(minWidth: 120)
                            } else {
                                ShortcutCaps(keys: wheelChord.keyCaps)
                                    .frame(minWidth: 120)
                            }
                        }
                        .buttonStyle(.bordered)
                        Button {
                            finishShortcutRecording()
                            conflictMessage = nil
                            store.resetShortcut(.commandWheel)
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .disabled(store.hotKeyConfiguration.isUsingDefault(for: .commandWheel))
                        .help("Reset command wheel shortcut")
                        .accessibilityLabel("Reset command wheel shortcut")
                    }
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
                LabeledContent("Activation style") {
                    Picker("Activation style", selection: $store.radialMenuActivationStyle) {
                        ForEach(RadialMenuActivationStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)
                }
                Toggle(
                    "Hold Globe/Fn to show Command Wheel",
                    isOn: $store.radialMenuGlobeFnHoldEnabled
                )
                .disabled(!store.radialMenuEnabled)
                .help("A quick Globe/Fn tap remains assigned to macOS. Only a deliberate hold opens WindowRanger's command wheel.")
                Text("Optional and local to this Mac. A quick tap is passed through unchanged to macOS. Fn combined with another key or modifier is never treated as a wheel gesture.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let issue = store.globeFnRuntimeIssue {
                    Label(issue, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Globe or Function key monitoring unavailable. \(issue)")
                }
                if store.radialMenuActivationStyle == .holdToShow
                    || store.radialMenuGlobeFnHoldEnabled {
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
                    Text(store.radialMenuGlobeFnHoldEnabled
                        ? "The same delay applies to Globe/Fn. Hold past it, point to an action, then release to run it; releasing with no action selected cancels."
                        : "A shorter shortcut tap does nothing. Hold past the delay, point to an action, then release to run it; releasing with no action selected cancels.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Press once to show the wheel; click or use the keyboard to choose an action. Press the shortcut again or Escape to cancel.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("The normal shortcut recorder accepts a modifier plus a non-modifier key. Globe/Fn hold is a separate optional hardware gesture, so it does not replace or conflict with that shortcut.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Appearance and interaction") {
                CommandWheelPreview(definition: store.radialWheelDefinition)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                Text("The wheel opens at the pointer and first focuses the eligible window directly beneath it. Its inner ring mixes direct actions and groups; a group reveals its valid actions on the outer ring. Desktop, transient UI, and unavailable actions fall back safely.")
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
                                CommandWheelMetadataLabel(metadata: metadata)
                            }
                        }
                    }
                    .disabled(availableItems.isEmpty)
                    .help(availableItems.isEmpty
                        ? "Every available command family is already in the wheel"
                        : "Add a command family to the wheel")
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
        RadialCommandCatalogue.availableMetadata(excluding: store.radialWheelDefinition.items)
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
            Group {
                if let metadata {
                    CommandWheelMetadataLabel(metadata: metadata)
                } else {
                    Label("Unavailable item", systemImage: "questionmark.diamond")
                }
            }
            .fontWeight(.medium)
            Text("Contextual").font(.caption).foregroundStyle(.secondary)
            Spacer()
            editorControls
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
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

private struct CommandWheelMetadataLabel: View {
    let metadata: RadialCommandMetadata

    var body: some View {
        HStack(spacing: 6) {
            RadialMenuSymbol(systemImage: metadata.systemImage, size: 14, weight: .semibold)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            Text(metadata.title)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(metadata.title)
    }
}

struct CommandWheelPreview: View {
    let definition: RadialWheelDefinition

    var body: some View {
        RadialMenuView(model: CommandWheelPreviewFixture.presentation(definition: definition))
            .scaleEffect(0.72)
            .frame(width: 324, height: 324)
            .allowsHitTesting(false)
            .id(definition.items.map(\.rawValue).joined(separator: "|"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Production command wheel preview with \(definition.items.count) saved command families"
        )
    }
}

@MainActor
private enum CommandWheelPreviewFixture {
    static func presentation(definition: RadialWheelDefinition) -> RadialMenuPresentationModel {
        let menu = RadialCommandContextBuilder.build(from: context, definition: definition)
        let presentation = RadialMenuPresentationModel(menu: menu)
        if let groupIndex = menu.items.firstIndex(where: \.isGroup) {
            for _ in 0...groupIndex { presentation.moveSelection(1) }
            presentation.enterSelectedGroup()
        }
        return presentation
    }

    private static let context: RadialCommandContext = {
        let activeWorkspaceID = UUID(uuidString: "71000000-0000-0000-0000-000000000001")!
        let workspaces = [
            RadialWorkspaceOption(
                id: activeWorkspaceID,
                name: "Focus",
                key: "f",
                layout: .accordion,
                homeDisplayIdentifier: "preview-display"
            ),
            RadialWorkspaceOption(
                id: UUID(uuidString: "71000000-0000-0000-0000-000000000002")!,
                name: "Writing",
                key: "w",
                layout: .none,
                homeDisplayIdentifier: "preview-display"
            ),
            RadialWorkspaceOption(
                id: UUID(uuidString: "71000000-0000-0000-0000-000000000003")!,
                name: "Review",
                key: "r",
                layout: .tiled,
                homeDisplayIdentifier: "preview-display"
            ),
        ]
        let activeProfileID = UUID(uuidString: "72000000-0000-0000-0000-000000000001")!
        return RadialCommandContext(
            focusedWindow: RadialFocusedWindowContext(
                processIdentifier: 42,
                windowIdentifier: 900,
                workspaceID: activeWorkspaceID,
                frame: WindowFrame(
                    position: CGPoint(x: 160, y: 120),
                    size: CGSize(width: 960, height: 720)
                ),
                layoutState: .managed,
                isAutomaticallyFloatingDialog: false,
                isAppRuleExcluded: false,
                keepsOnAllWorkspaces: false
            ),
            focusSource: .focusedManagedWindow,
            workspaceID: activeWorkspaceID,
            workspaceName: "Focus",
            layout: .accordion,
            displayIdentifier: "preview-display",
            displayName: "Studio Display",
            displayBounds: CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
            displayMode: .independent,
            focusFollowsMovedWindow: false,
            connectedDisplayIdentifiers: ["preview-display"],
            connectedDisplays: [
                RadialDisplayOption(id: "preview-display", name: "Studio Display", isMain: true),
            ],
            availableFocusDirections: Set(WindowDirection.allCases),
            availableMoveDirections: Set(WindowDirection.allCases),
            canSmartResize: true,
            workspaces: workspaces,
            supportedCommands: RadialCommandCapability.current,
            validationToken: "settings-preview",
            profiles: [
                RadialProfileOption(id: activeProfileID, name: "Laptop"),
                RadialProfileOption(
                    id: UUID(uuidString: "72000000-0000-0000-0000-000000000002")!,
                    name: "Studio"
                ),
            ],
            activeProfileID: activeProfileID,
            isProfileManuallyPinned: true
        )
    }()
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
                LabeledContent("Recent logs") {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            copyDiagnosticsButton
                            revealDiagnosticsButton
                        }
                        VStack(alignment: .trailing, spacing: 8) {
                            copyDiagnosticsButton
                            revealDiagnosticsButton
                        }
                    }
                }
            }
            Section("Window admission") {
                HStack {
                    Text("Privacy-safe current classifications")
                    Spacer()
                    Button("Copy Snapshot") { copyAdmissionSnapshot() }
                        .disabled(admissionRecords.isEmpty)
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
                            if let profile = record.compatibilityProfileIdentifier {
                                Text("Built-in compatibility: \(profile)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Text("Modal \(record.modalObservation) · focused \(record.focusedObservation) · main \(record.mainObservation) · controls F/M/C/Z \(record.fullscreenButton)/\(record.minimizeButton)/\(record.closeButton)/\(record.zoomButton) · move \(record.positionSettable) · resize \(record.sizeSettable)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                    .frame(minHeight: 180)
                }
                Text("This view never includes window titles, document names, URLs, typed content, file paths, or window contents. Refresh performs read-only capability queries for already tracked windows; it does not re-enumerate, move, resize, or refocus them.")
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

    private var copyDiagnosticsButton: some View {
        Button("Copy Recent Diagnostics") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(diagnostics.recentDiagnosticsText(), forType: .string)
        }
    }

    private var revealDiagnosticsButton: some View {
        Button("Reveal Diagnostics File") {
            guard let fileURL = diagnostics.fileURL else { return }
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        }
        .disabled(diagnostics.fileURL == nil)
    }

    private func refreshAdmissionRecords() {
        engine.admissionSupportSnapshot { records in
            admissionRecords = records
            hasLoadedAdmissionRecords = true
        }
    }

    private func copyAdmissionSnapshot() {
        guard let snapshot = WindowAdmissionSupportSnapshot(records: admissionRecords).encodedString() else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snapshot, forType: .string)
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
