import AppKit
import ApplicationServices
import Carbon
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
    @ObservedObject var updateController: UpdateController
    let workspacePreviewRepository: WorkspacePreviewRepository?
    let shortcutRecordingStateChanged: (Bool) -> Void
    let onboardingRestartRequested: () -> Void

    init(
        store: SettingsStore,
        engine: WorkspaceEngine,
        navigation: SettingsNavigationModel,
        windowCoordinator: SettingsWindowCoordinator,
        diagnostics: DiagnosticLogger,
        updateController: UpdateController,
        workspacePreviewRepository: WorkspacePreviewRepository? = nil,
        shortcutRecordingStateChanged: @escaping (Bool) -> Void,
        onboardingRestartRequested: @escaping () -> Void = {}
    ) {
        self.store = store
        self.engine = engine
        self.navigation = navigation
        self.windowCoordinator = windowCoordinator
        self.diagnostics = diagnostics
        self.updateController = updateController
        self.workspacePreviewRepository = workspacePreviewRepository
        self.shortcutRecordingStateChanged = shortcutRecordingStateChanged
        self.onboardingRestartRequested = onboardingRestartRequested
    }

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
                            sidebarRow(.updates)
                            sidebarRow(.sync)
                            sidebarRow(.behavior)
                            sidebarRow(.profiles)
                        }
                        Section("Appearance") {
                            sidebarRow(.menuBar)
                            sidebarRow(.focusBorder)
                        }
                        Section {
                            ProfileSidebarContext(store: store)
                                .listRowInsets(EdgeInsets(
                                    top: 0,
                                    leading: 10,
                                    bottom: 0,
                                    trailing: 10
                                ))
                            sidebarRow(.displays)
                            sidebarRow(.workspaces)
                            sidebarRow(.appRules)
                            sidebarRow(.quickAppShelf)
                        } header: {
                            Text("Editing Profile")
                        }
                        Section("Controls") {
                            sidebarRow(.shortcuts)
                            sidebarRow(.shortcutGuide)
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
                previewRepository: workspacePreviewRepository,
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
                case .general, .sync, .appearance, .menuBar, .focusBorder, .behavior:
                    GeneralSettingsView(
                        store: store,
                        engine: engine,
                        previewRepository: workspacePreviewRepository,
                        category: navigation.selectedCategory,
                        onboardingRestartRequested: onboardingRestartRequested
                    )
                case .updates:
                    UpdateSettingsView(updateController: updateController)
                case .profiles, .profileSwitching:
                    ProfilesSettingsView(store: store)
                case .displays:
                    DisplaysSettingsView(store: store)
                case .workspaces, .layouts:
                    EmptyView()
                case .appRules:
                    AppRulesSettingsView(store: store, engine: engine)
                case .quickAppShelf:
                    QuickAppShelfSettingsView(store: store)
                case .shortcuts:
                    ShortcutSettingsView(
                        store: store,
                        recordingStateChanged: shortcutRecordingStateChanged
                    )
                case .shortcutGuide:
                    ShortcutGuideSettingsView(store: store)
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
            workspaces: store.settingsWorkspaces
        )
    }

    private var highlightedEntry: SettingsSearchEntry? {
        SettingsCatalog.search(
            "",
            includeDebug: navigation.includeDebug,
            workspaces: store.settingsWorkspaces
        ).first { entry in
            entry.id == navigation.highlightedSettingID &&
                entry.category.canonicalDestination == navigation.selectedCategory.canonicalDestination
        }
    }
}

private struct UpdateSettingsView: View {
    @ObservedObject var updateController: UpdateController

    private var buildChannelTitle: String {
        switch updateController.configuration.buildChannel {
        case .development: "Development"
        case .stable: "Stable"
        case .beta: "Beta"
        }
    }

    var body: some View {
        Form {
            Section("Software Updates") {
                LabeledContent("Current build", value: buildChannelTitle)
                if updateController.availability == .available {
                    Picker(
                        "Update channel",
                        selection: Binding(
                            get: { updateController.betaUpdatesEnabled },
                            set: { updateController.betaUpdatesEnabled = $0 }
                        )
                    ) {
                        Text("Stable").tag(false)
                        Text("Beta").tag(true)
                    }
                    .pickerStyle(.segmented)

                    Button("Check for Updates…", systemImage: "arrow.triangle.2.circlepath") {
                        updateController.checkForUpdates()
                    }
                    .disabled(!updateController.canCheckForUpdates)
                } else {
                    Label(
                        updateController.statusMessage ?? updateController.availability.message,
                        systemImage: "hammer"
                    )
                    .foregroundStyle(.secondary)
                    Text("Development builds continue to use WindowRanger's local development install flow and never contact the public update feed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if updateController.availability == .available {
                Section("Automatic Updates") {
                    Toggle(
                        "Automatically check for updates",
                        isOn: Binding(
                            get: { updateController.automaticChecksEnabled },
                            set: { updateController.automaticChecksEnabled = $0 }
                        )
                    )
                    Toggle(
                        "Download updates automatically",
                        isOn: Binding(
                            get: { updateController.automaticDownloadsEnabled },
                            set: { updateController.automaticDownloadsEnabled = $0 }
                        )
                    )
                    .disabled(!updateController.automaticChecksEnabled)
                    Text("Updates are verified with WindowRanger's embedded public signing key before installation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Release Channel") {
                    if updateController.betaUpdatesEnabled {
                        Text("Beta includes prerelease builds as well as newer Stable releases.")
                    } else {
                        Text("Stable excludes prerelease builds.")
                    }
                    Text("Returning to Stable does not downgrade an installed Beta. WindowRanger waits until a newer Stable release is available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
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

private struct ProfileSidebarContext: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Menu {
            Picker("Editing Profile", selection: Binding(
                get: { store.settingsProfileID },
                set: { profileID in
                    if profileID != store.settingsProfileID {
                        store.selectProfileForEditing(profileID)
                    }
                }
            )) {
                ForEach(store.profiles) { profile in
                    Label(profile.name, systemImage: profile.iconStyle.systemImage)
                        .tag(profile.id)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: store.settingsProfile.iconStyle.systemImage)
                    .frame(width: 18)
                Text(store.settingsProfile.name)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .frame(width: SettingsWindowMetrics.sidebarWidth - 20, alignment: .leading)
            .frame(minHeight: 30, alignment: .leading)
            .background(
                Color.primary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .frame(width: SettingsWindowMetrics.sidebarWidth - 20)
        // Sidebar sections add 16 points before custom row content. Destination selection
        // backgrounds start at the list's outer margin, so compensate to share their bounds.
        .offset(x: -16)
        .help("Chooses which reusable profile Settings edits without changing the live desktop.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Editing Profile, \(store.settingsProfile.name)")
        .accessibilityHint("Changes what Settings edits without activating the desktop.")
    }
}

@MainActor
final class AccessibilityPermissionMonitor: ObservableObject {
    typealias TrustProvider = () -> Bool
    typealias Sleep = (UInt64) async throws -> Void

    static let missingPermissionRefreshIntervalNanoseconds: UInt64 = 750_000_000

    @Published private(set) var isGranted: Bool
    private let trustProvider: TrustProvider

    init(trustProvider: @escaping TrustProvider = { AXIsProcessTrusted() }) {
        self.trustProvider = trustProvider
        isGranted = trustProvider()
    }

    @discardableResult
    func refresh() -> Bool {
        let latest = trustProvider()
        if latest != isGranted { isGranted = latest }
        return latest
    }

    func refreshUntilGranted(
        sleep: @escaping Sleep = { try await Task.sleep(nanoseconds: $0) }
    ) async {
        refresh()
        while !Task.isCancelled, !isGranted {
            do {
                try await sleep(Self.missingPermissionRefreshIntervalNanoseconds)
            } catch {
                return
            }
            refresh()
        }
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var store: SettingsStore
    let engine: WorkspaceEngine
    let previewRepository: WorkspacePreviewRepository?
    let category: SettingsCategory
    let onboardingRestartRequested: () -> Void
    @Environment(\.undoManager) private var undoManager
    @StateObject private var accessibilityPermission = AccessibilityPermissionMonitor()
    @StateObject private var launchAtLogin = LaunchAtLoginController()
    @State private var showsFocusBorderAppPicker = false
    @State private var showsICloudReplacementConfirmation = false

    private var iCloudSyncStatusTitle: String {
        switch store.iCloudSyncState {
        case .disabled: "Off"
        case .waitingForCloud: "Waiting for iCloud"
        case .active: "On"
        case .needsAttention: "Needs Attention"
        }
    }

    private var iCloudSyncStatusColor: Color {
        switch store.iCloudSyncState {
        case .disabled: .secondary
        case .waitingForCloud, .needsAttention: .orange
        case .active: .green
        }
    }

    var body: some View {
        Form {
            if category == .general {
                Section("Permissions") {
                    LabeledContent("Accessibility") {
                        HStack {
                            Text(accessibilityPermission.isGranted ? "Granted" : "Required")
                                .foregroundStyle(accessibilityPermission.isGranted ? .green : .orange)
                            if !accessibilityPermission.isGranted {
                                Button("Grant Access") {
                                    _ = AccessibilityWindow.requestPermission()
                                    accessibilityPermission.refresh()
                                }
                            }
                        }
                    }
                    Text("Accessibility access lets the app discover, move, resize, and focus windows.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()

                    Toggle("Show window previews", isOn: Binding(
                        get: { store.workspacePreviewThumbnailsEnabled },
                        set: { enabled in
                            store.workspacePreviewThumbnailsEnabled = enabled
                            previewRepository?.isEnabled = enabled
                            if enabled {
                                previewRepository?.requestAuthorizationFromUser()
                            } else {
                                previewRepository?.purgeImages()
                            }
                        }
                    ))
                    LabeledContent("Screen Recording") {
                        HStack {
                            Text(screenRecordingStatusTitle)
                                .foregroundStyle(screenRecordingStatusColor)
                            if store.workspacePreviewThumbnailsEnabled,
                               previewRepository?.authorization != .authorized {
                                Button("Open Screen Recording Settings") {
                                    previewRepository?.openScreenRecordingSettings()
                                }
                            }
                        }
                    }
                    Text("Off by default and stored only on this Mac. When enabled, WindowRanger adds the current desktop wallpaper and small window thumbnails to workspace previews. At launch, inactive Tiled and Accordion windows may be resized while parked so their previews are accurate. Preview pixels stay in memory and are never synced, saved, exported, or included in diagnostics; unavailable images fall back safely.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Startup") {
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
                    if let errorMessage = launchAtLogin.errorMessage {
                        Text(errorMessage).font(.caption).foregroundStyle(.red)
                    }
                }

                Section("Setup") {
                    Button("Run Setup Again…", systemImage: "sparkles") {
                        onboardingRestartRequested()
                    }
                    Text("Revisit the guided setup without resetting your existing profiles or choices.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if category == .sync {
                Section("iCloud") {
                    Toggle("Sync settings with iCloud", isOn: $store.iCloudSyncEnabled)
                    LabeledContent("Status") {
                        Text(iCloudSyncStatusTitle)
                            .foregroundStyle(iCloudSyncStatusColor)
                    }
                    Text("Off by default. When enabled, named profile definitions and supported global preferences sync through your private iCloud key-value store. The active profile, automatic trigger mappings, live window state, and physical monitor bindings always remain local to each Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("iCloud does not provide WindowRanger with a reliable list of the Macs participating in this sync.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if store.iCloudSyncState == .disabled,
                       store.iCloudProfileLibraryIssue?.source != .local {
                        Button("Replace iCloud with This Mac’s Settings…") {
                            showsICloudReplacementConfirmation = true
                        }
                    }
                    if store.iCloudSyncState == .waitingForCloud {
                        Label(
                            "WindowRanger is waiting for an existing profile library. Nothing from this Mac will be uploaded while it waits.",
                            systemImage: "icloud.and.arrow.down"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                        Button("Use This Mac’s Settings in iCloud…") {
                            showsICloudReplacementConfirmation = true
                        }
                    }
                    if let issue = store.iCloudProfileLibraryIssue {
                        Label(issue.message, systemImage: "exclamationmark.icloud")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        if issue.canReplaceCloudCopy {
                            Button("Use This Mac’s Settings in iCloud…") {
                                showsICloudReplacementConfirmation = true
                            }
                        }
                    }
                }

                Section("Syncs when Enabled") {
                    Label("Profile library — workspaces, layouts, display roles, Application Rules, and Quick App Shelves", systemImage: "person.crop.rectangle.stack")
                    Label("Menu Bar presentation, workspace labels, and highlight colour", systemImage: "menubar.rectangle")
                    Label("Global shortcuts and Command Palette activation", systemImage: "keyboard")
                    Label("Focus-follows-move and automatic application-unhide behavior", systemImage: "arrow.triangle.turn.up.right.diamond")
                }

                Section("Always Stays on This Mac") {
                    Label("Active profile, automatic selection rules, and display bindings", systemImage: "display.2")
                    Label("Trackpad gestures, Shortcut Guide, and Focus Border settings", systemImage: "hand.draw")
                    Label("Permissions, Open at Login, live windows, and diagnostics", systemImage: "lock.macwindow")
                }
            }

            if category == .menuBar || category == .appearance {
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
                Text("Presentation, workspace labels, and highlight colour are global preferences and sync when iCloud is enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

                Section("Display Icons in \(store.settingsProfile.name)") {
                    ForEach(store.settingsProfile.displayRoles) { role in
                        Picker(
                            role.name,
                            selection: Binding(
                                get: { store.settingsMenuBarDisplayIconStyle(forRole: role.id) },
                                set: { store.setSettingsMenuBarDisplayIconStyle($0, forRole: role.id) }
                            )
                        ) {
                            ForEach(MenuBarDisplayIconStyle.allCases) { style in
                                Label(style.title, systemImage: style.pickerSystemImage).tag(style)
                            }
                        }
                    }
                    Text("These icon choices sync with this profile; physical monitor bindings remain local to this Mac in Displays.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if category == .behavior {
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
                    ? "Moving a window also opens its destination workspace and focuses it there. The Command Palette still shows the effective move action."
                    : "Moving a window keeps you on the source workspace and focuses the next visible local window. The Command Palette offers Move & Follow when you want it once.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Global preference · syncs when iCloud is enabled.")
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

            }

            if category == .focusBorder {
                Section("Focused Window Border") {
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

                Section("Application Corner Radius Overrides") {
                    if focusBorderOverrideBundleIdentifiers.isEmpty {
                        Text("No application overrides. Automatic corner matching is used everywhere.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(focusBorderOverrideBundleIdentifiers, id: \.self) { bundleIdentifier in
                            LabeledContent(applicationDisplayName(bundleIdentifier)) {
                                HStack(spacing: 10) {
                                    Text("\(focusBorderCornerRadius(bundleIdentifier), specifier: "%.0f") pt")
                                        .monospacedDigit()
                                        .frame(minWidth: 42, alignment: .trailing)
                                    Stepper(
                                        "Corner radius for \(applicationDisplayName(bundleIdentifier))",
                                        value: focusBorderCornerRadiusBinding(bundleIdentifier),
                                        in: FocusedWindowHighlightPolicy.cornerRadiusRange,
                                        step: 1
                                    )
                                    .labelsHidden()
                                    Button(role: .destructive) {
                                        store.setFocusedWindowHighlightCornerRadiusOverride(
                                            nil,
                                            for: bundleIdentifier,
                                            undoManager: undoManager
                                        )
                                    } label: {
                                        Image(systemName: "minus.circle")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Remove corner radius override")
                                }
                            }
                        }
                    }

                    Button("Add Application Override", systemImage: "plus") {
                        showsFocusBorderAppPicker = true
                    }
                    Text("Overrides are local to this Mac and apply by application, independently of profiles, Application Rules, and Quick Apps.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if category == .behavior {
                Section("Compatibility") {
                Toggle(
                    "Automatically unhide applications when focusing their windows",
                    isOn: $store.automaticallyUnhideApplications
                )
                Text("Off by default. When enabled, WindowRanger only unhides an app while carrying out an explicit focus command, with duplicate attempts throttled to avoid loops. This global preference syncs when iCloud is enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

        }
        .formStyle(.grouped)
        .sheet(isPresented: $showsFocusBorderAppPicker) {
            InstalledApplicationPicker(
                excludedBundleIdentifiers: Set(focusBorderOverrideBundleIdentifiers)
            ) { application in
                store.setFocusedWindowHighlightCornerRadiusOverride(
                    automaticFocusBorderCornerRadius,
                    for: application.bundleIdentifier,
                    undoManager: undoManager
                )
                showsFocusBorderAppPicker = false
            }
        }
        .onAppear {
            guard category == .general else { return }
            accessibilityPermission.refresh()
            launchAtLogin.refresh()
            previewRepository?.isEnabled = store.workspacePreviewThumbnailsEnabled
            previewRepository?.refreshAuthorization()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard category == .general else { return }
            accessibilityPermission.refresh()
            launchAtLogin.refresh()
            previewRepository?.refreshAuthorization()
        }
        .task(id: accessibilityPermission.isGranted) {
            guard category == .general else { return }
            await accessibilityPermission.refreshUntilGranted()
        }
        .confirmationDialog(
            "Use this Mac’s settings in iCloud?",
            isPresented: $showsICloudReplacementConfirmation,
            titleVisibility: .visible
        ) {
            Button("Replace iCloud Settings", role: .destructive) {
                store.replaceICloudSettingsWithLocalCopy()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This uploads this Mac’s profiles and supported global settings. Any existing WindowRanger settings in iCloud that have not arrived yet will be replaced. If Sync is off, it will be turned on and remain enabled.")
        }
    }

    private var screenRecordingStatusTitle: String {
        guard store.workspacePreviewThumbnailsEnabled else { return "Off" }
        return previewRepository?.authorization == .authorized ? "Granted" : "Required"
    }

    private var screenRecordingStatusColor: Color {
        guard store.workspacePreviewThumbnailsEnabled else { return .secondary }
        return previewRepository?.authorization == .authorized ? .green : .orange
    }

    private var automaticFocusBorderCornerRadius: Double {
        Double(FocusedWindowHighlightPolicy.automaticCornerRadius())
    }

    private var focusBorderOverrideBundleIdentifiers: [String] {
        store.focusedWindowHighlightCornerRadiusOverrides.keys.sorted {
            applicationDisplayName($0).localizedStandardCompare(applicationDisplayName($1))
                == .orderedAscending
        }
    }

    private func focusBorderCornerRadius(_ bundleIdentifier: String) -> Double {
        store.focusedWindowHighlightCornerRadiusOverride(for: bundleIdentifier)
            ?? automaticFocusBorderCornerRadius
    }

    private func focusBorderCornerRadiusBinding(_ bundleIdentifier: String) -> Binding<Double> {
        Binding(
            get: { focusBorderCornerRadius(bundleIdentifier) },
            set: { radius in
                store.setFocusedWindowHighlightCornerRadiusOverride(
                    radius,
                    for: bundleIdentifier,
                    undoManager: undoManager
                )
            }
        )
    }

    private func applicationDisplayName(_ bundleIdentifier: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else { return bundleIdentifier }
        return Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
    }

}

enum ProfileAutomaticContext: CaseIterable, Identifiable, Sendable {
    case localDefault
    case gameMode
    case docked
    case undocked

    var id: Self { self }

    var title: String {
        switch self {
        case .localDefault: "Make default"
        case .gameMode: "Use during Game Mode"
        case .docked: "Use when docked"
        case .undocked: "Use when undocked"
        }
    }

    var explanation: String {
        switch self {
        case .localDefault: "Used when no higher-priority automatic rule matches."
        case .gameMode: "Used for a foreground full-screen game that declares macOS Game Mode support."
        case .docked: "Used on a portable Mac while an external display is connected."
        case .undocked: "Used on a portable Mac with only its built-in display."
        }
    }

    var permitsNoOwner: Bool { self != .localDefault }
}

enum ProfileAutomaticAssignmentPolicy {
    static func replacementOwner(
        currentOwner: UUID?,
        selectedProfileID: UUID,
        context: ProfileAutomaticContext
    ) -> UUID? {
        if currentOwner == selectedProfileID {
            return context.permitsNoOwner ? nil : selectedProfileID
        }
        return selectedProfileID
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

    init(store: SettingsStore) {
        self.store = store
        _transferCoordinator = StateObject(wrappedValue: ProfileTransferCoordinator(
            diagnostics: store.profileTransferDiagnosticLogger
        ))
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    profileTabStrip
                    profileInspector(
                        layout: SettingsDetailLayout.resolve(availableWidth: geometry.size.width)
                    )
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
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
                currentProfileName: store.settingsProfile.name,
                cancel: { isCreatingProfile = false },
                create: { name, source in
                    _ = store.createProfile(named: name, source: source)
                    isCreatingProfile = false
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
    private func profileInspector(layout: SettingsDetailLayout) -> some View {
        switch layout {
        case .wide:
            HStack(alignment: .top, spacing: 16) {
                profileIdentityPanel
                    .frame(width: 280)
                automaticUsePanel
                    .frame(maxWidth: .infinity)
            }
        case .compact:
            VStack(alignment: .leading, spacing: 16) {
                profileIdentityPanel
                automaticUsePanel
            }
        }
    }

    private var profileTabStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(store.profiles) { profile in
                    profileTab(profile)
                }
                Button {
                    isCreatingProfile = true
                } label: {
                    VStack(spacing: 7) {
                        Image(systemName: "plus")
                            .font(.system(size: 25, weight: .medium))
                        Text("Add Profile")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .frame(width: 96, height: 82)
                    .contentShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add profile")
            }
            .padding(8)
        }
        .scrollIndicators(.hidden)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Profiles")
    }

    private func profileTab(_ profile: WindowManagerProfile) -> some View {
        let isSelected = profile.id == store.settingsProfileID
        let context = profileContextLabel(profile.id)
        return Button {
            store.selectProfileForEditing(profile.id)
        } label: {
            VStack(spacing: 5) {
                Image(systemName: profile.iconStyle.systemImage)
                    .font(.system(size: 28, weight: .medium))
                    .frame(height: 32)
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
                Text(profile.name)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let context {
                    Text(context)
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                        .foregroundStyle(profile.id == store.activeProfileID ? Color.accentColor : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                } else {
                    Text(" ")
                        .font(.caption2)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 132, height: 82)
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .background(
                isSelected ? Color.accentColor.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 9)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Use Profile") {
                store.selectProfileForEditing(profile.id)
                store.activateSettingsProfile()
            }
            .disabled(profile.id == store.activeProfileID)
            Button("Duplicate") { _ = store.duplicateProfile(profile.id) }
            Divider()
            Button("Delete", role: .destructive) {
                pendingProfileDeletion = profile.id
            }
            .disabled(store.profiles.count == 1)
        }
        .accessibilityLabel(profileTabAccessibilityLabel(profile))
        .accessibilityHint("Selects this profile for editing without activating it")
    }

    private var profileIdentityPanel: some View {
        profileSettingsPanel("Profile identity") {
            ProfileIdentityEditor(store: store, presentation: .prominent)

            Divider()

            LabeledContent("Active on this Mac", value: store.activeProfile.name)
            LabeledContent("Selection mode", value: store.activeProfileSelectionReason.title)

            if store.isEditingActiveProfile {
                Label("This profile is active", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                if store.manualPinnedProfileID != nil {
                    Button("Resume Automatic", systemImage: "arrow.triangle.2.circlepath") {
                        store.resumeAutomaticProfileSelection()
                    }
                }
            } else {
                Button("Use \(store.settingsProfile.name)", systemImage: "checkmark.circle") {
                    store.activateSettingsProfile()
                }
                .buttonStyle(.borderedProminent)
            }

            Text("Selecting a tab chooses what to edit. Use Profile activates it and pins it on this Mac until automatic selection resumes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Button("Duplicate Profile", systemImage: "plus.square.on.square") {
                    _ = store.duplicateProfile(store.settingsProfileID)
                }
                Button("Import Profiles…", systemImage: "square.and.arrow.down") {
                    prepareProfileImport()
                }
                Button("Export All Profiles…", systemImage: "square.and.arrow.up") {
                    exportProfiles()
                }
                Button("Delete Profile", systemImage: "trash", role: .destructive) {
                    pendingProfileDeletion = store.settingsProfileID
                }
                .disabled(store.profiles.count == 1)
            }
            .buttonStyle(.borderless)
        }
    }

    private var automaticUsePanel: some View {
        profileSettingsPanel("Automatic use on this Mac") {
            Text("Choose when \(store.settingsProfile.name) owns each exclusive local context.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(ProfileAutomaticContext.allCases) { context in
                automaticAssignmentRow(context)
                if context != .undocked { Divider() }
            }

            Divider()

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Exact display setups")
                        .font(.headline)
                    Text("Use a profile for a specific conservative monitor arrangement.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Assign Connected Displays", systemImage: "display.2") {
                    _ = store.assignCurrentDisplaySetup(to: store.settingsProfileID)
                }
                .disabled(store.connectedDisplays.isEmpty)
                .help("Use \(store.settingsProfile.name) for the currently connected display arrangement")
            }

            if store.exactProfileTriggers.isEmpty {
                Text("No exact display setup mappings on this Mac.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.exactProfileTriggers) { trigger in
                    exactDisplayTriggerRow(trigger)
                }
            }

            Divider()

            Text("Reusable profile settings may sync or be exported. The active profile and every automatic assignment shown here stay local to this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func automaticAssignmentRow(_ context: ProfileAutomaticContext) -> some View {
        let ownerID = automaticOwnerID(for: context)
        let isSelected = ownerID == store.settingsProfileID
        let ownerName = ownerID.flatMap(profileName) ?? "Not assigned"
        return Button {
            let replacement = ProfileAutomaticAssignmentPolicy.replacementOwner(
                currentOwner: ownerID,
                selectedProfileID: store.settingsProfileID,
                context: context
            )
            setAutomaticOwner(replacement, for: context)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.title)
                        .foregroundStyle(.primary)
                    Text(context.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Text(ownerName)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(context.title), \(ownerName)")
        .accessibilityHint(isSelected && context.permitsNoOwner
            ? "Removes this automatic assignment"
            : isSelected ? "Already assigned to this profile" : "Assigns this context to \(store.settingsProfile.name)")
    }

    private func exactDisplayTriggerRow(_ trigger: ExactProfileTrigger) -> some View {
        let isSelected = trigger.profileID == store.settingsProfileID
        let ownerName = profileName(trigger.profileID) ?? "Unknown profile"
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "display.2")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(trigger.name)
                    Text("\(trigger.displayPins.count) conservative monitor identities")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(ownerName)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .lineLimit(1)
                if !isSelected {
                    Button("Use Here") {
                        store.setExactTrigger(trigger.id, profileID: store.settingsProfileID)
                    }
                }
                Button(role: .destructive) {
                    store.removeExactTrigger(trigger.id)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove this display setup mapping")
                .accessibilityLabel("Remove \(trigger.name)")
            }
        }
        .padding(.vertical, 4)
    }

    private func profileSettingsPanel<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            Divider()
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
    }

    private func automaticOwnerID(for context: ProfileAutomaticContext) -> UUID? {
        switch context {
        case .localDefault: store.defaultProfileID
        case .gameMode: store.gameModeProfileID
        case .docked: store.dockedProfileID
        case .undocked: store.undockedProfileID
        }
    }

    private func setAutomaticOwner(_ profileID: UUID?, for context: ProfileAutomaticContext) {
        switch context {
        case .localDefault:
            if let profileID { store.setDefaultProfile(profileID) }
        case .gameMode:
            store.setGameModeProfile(profileID)
        case .docked:
            store.setDockedProfile(profileID)
        case .undocked:
            store.setUndockedProfile(profileID)
        }
    }

    private func profileName(_ profileID: UUID) -> String? {
        store.profiles.first(where: { $0.id == profileID })?.name
    }

    private func profileContextLabel(_ profileID: UUID) -> String? {
        var labels: [String] = []
        if profileID == store.activeProfileID { labels.append("Active") }
        if profileID == store.defaultProfileID { labels.append("Default") }
        if profileID == store.gameModeProfileID { labels.append("Game Mode") }
        if profileID == store.dockedProfileID { labels.append("Docked") }
        if profileID == store.undockedProfileID { labels.append("Undocked") }
        if labels.isEmpty,
           store.exactProfileTriggers.contains(where: { $0.profileID == profileID }) {
            labels.append("Display setup")
        }
        guard !labels.isEmpty else { return nil }
        let visible = labels.prefix(2).joined(separator: " · ")
        return labels.count > 2 ? "\(visible) +\(labels.count - 2)" : visible
    }

    private func profileTabAccessibilityLabel(_ profile: WindowManagerProfile) -> String {
        let context = profileContextLabel(profile.id).map { ", \($0)" } ?? ""
        let selected = profile.id == store.settingsProfileID ? ", selected for editing" : ""
        return "\(profile.name)\(context)\(selected)"
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

}

struct DisplayWorkspaceModePresentation: Equatable, Sendable {
    let title: String
    let supportingText: String
    let technicalTerm: String
    let explanation: String
    let accessibilityHint: String

    static func value(for mode: MultiDisplayMode) -> DisplayWorkspaceModePresentation {
        switch mode {
        case .unified:
            DisplayWorkspaceModePresentation(
                title: "Switch together",
                supportingText: "All displays change workspace together",
                technicalTerm: "Unified",
                explanation: "Switching changes every display at once. Windows remain on their current display.",
                accessibilityHint: "All displays share one active workspace and switch together."
            )
        case .independent:
            DisplayWorkspaceModePresentation(
                title: "Switch separately",
                supportingText: "Each display keeps its own workspace",
                technicalTerm: "Independent",
                explanation: "Switching changes only the display you are using. Each workspace has a Home Display.",
                accessibilityHint: "Each display has its own active workspace and switches independently."
            )
        }
    }
}

enum DisplayRoleBindingTone: Equatable, Sendable {
    case connected
    case attention
    case inactive
}

struct DisplayRoleBindingPresentation: Equatable, Sendable {
    let title: String
    let systemImage: String
    let detail: String?
    let tone: DisplayRoleBindingTone

    static func value(for resolution: DisplayPinResolution?) -> DisplayRoleBindingPresentation {
        switch resolution {
        case .exactIdentifier, .exactUUID, .portableFingerprint:
            DisplayRoleBindingPresentation(
                title: "Connected",
                systemImage: "checkmark.circle.fill",
                detail: nil,
                tone: .connected
            )
        case .ambiguous:
            DisplayRoleBindingPresentation(
                title: "Needs attention",
                systemImage: "exclamationmark.triangle.fill",
                detail: "Two matching displays were found. Choose the intended display.",
                tone: .attention
            )
        case .disconnected:
            DisplayRoleBindingPresentation(
                title: "Disconnected",
                systemImage: "exclamationmark.triangle.fill",
                detail: "Will reconnect automatically when the display is available.",
                tone: .attention
            )
        case nil:
            DisplayRoleBindingPresentation(
                title: "Not assigned on this Mac",
                systemImage: "circle.dashed",
                detail: "Workspaces use the safe main-display fallback.",
                tone: .inactive
            )
        }
    }
}

private struct DisplaysSettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
                Section("Workspace switching") {
                    displayModeChoices
                    Text(DisplayWorkspaceModePresentation.value(
                        for: store.settingsMultiDisplayMode
                    ).explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    ForEach(store.settingsProfile.displayRoles) { role in
                        displayRoleMapping(role)
                    }
                    HStack {
                        Spacer()
                        Button("Add Display Role", systemImage: "plus") {
                            _ = store.addSettingsDisplayRole()
                        }
                    }
                } header: {
                    Text("Display setup for \(store.settingsProfile.name)")
                } footer: {
                    Text("Names sync with this profile. Monitor choices stay on this Mac.")
                        .font(.caption)
                }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var displayModeChoices: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                ForEach(MultiDisplayMode.allCases) { mode in
                    displayModeChoice(mode)
                }
            }
            VStack(spacing: 10) {
                ForEach(MultiDisplayMode.allCases) { mode in
                    displayModeChoice(mode)
                }
            }
        }
    }

    private func displayModeChoice(_ mode: MultiDisplayMode) -> some View {
        let presentation = DisplayWorkspaceModePresentation.value(for: mode)
        return DisplayWorkspaceModeChoiceCard(
            mode: mode,
            presentation: presentation,
            isSelected: store.settingsMultiDisplayMode == mode
        ) {
            store.setSettingsMultiDisplayMode(mode)
        }
    }

    private func displayRoleMapping(_ role: ProfileDisplayRole) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(role.name)
                        .font(.subheadline.weight(.semibold))
                    Label("Profile & iCloud", systemImage: "icloud")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) {
                    _ = store.deleteSettingsDisplayRole(role.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .frame(width: 28, height: 28)
                .disabled(store.settingsProfile.displayRoles.count == 1)
                .accessibilityLabel("Delete \(role.name) role")
                .help("Delete \(role.name) from this profile")
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 24) {
                    roleNameEditor(role)
                        .frame(minWidth: 180, maxWidth: .infinity)
                    localDisplayPicker(role)
                        .frame(minWidth: 220, maxWidth: .infinity)
                    roleBindingStatus(role.id)
                        .frame(width: 180, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 10) {
                    roleNameEditor(role)
                    localDisplayPicker(role)
                    roleBindingStatus(role.id)
                }
            }
        }
        .padding(.vertical, 16)
    }

    private func roleNameEditor(_ role: ProfileDisplayRole) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Name in profile")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Name in profile", text: Binding(
                get: {
                    store.settingsProfile.displayRoles.first(where: { $0.id == role.id })?.name
                        ?? role.name
                },
                set: { store.renameSettingsDisplayRole(role.id, to: $0) }
            ))
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Name in profile for \(role.name)")
            .accessibilityHint("This reusable name syncs when iCloud is enabled.")
        }
    }

    private func localDisplayPicker(_ role: ProfileDisplayRole) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("On this Mac")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("On this Mac", selection: Binding<String?>(
                get: { store.roleBindings[role.id]?.lastKnownIdentifier },
                set: { store.bindSettingsDisplayRole(role.id, to: $0) }
            )) {
                Text("Not assigned — use main display").tag(nil as String?)
                ForEach(roleDisplayOptions(role.id)) { display in
                    Text(display.name).tag(Optional(display.identifier))
                }
            }
            .labelsHidden()
            .accessibilityLabel("Display on this Mac for \(role.name)")
        }
    }

    private func roleBindingStatus(_ roleID: UUID) -> some View {
        let presentation = DisplayRoleBindingPresentation.value(
            for: store.roleBindingResolution(roleID)
        )
        return VStack(alignment: .leading, spacing: 3) {
            Label(presentation.title, systemImage: presentation.systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(roleBindingStatusColor(presentation.tone))
            if let detail = presentation.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func roleBindingStatusColor(_ tone: DisplayRoleBindingTone) -> Color {
        switch tone {
        case .connected: .green
        case .attention: .orange
        case .inactive: .secondary
        }
    }

    private func roleDisplayOptions(_ roleID: UUID) -> [DisplaySnapshot] {
        guard let selected = store.roleBindings[roleID]?.lastKnownIdentifier,
              !store.connectedDisplays.contains(where: { $0.identifier == selected })
        else { return store.connectedDisplays }
        return store.connectedDisplays + [DisplaySnapshot(
            identifier: selected, bounds: .zero, isMain: false, name: "Disconnected Display"
        )]
    }

}

private struct DisplayWorkspaceModeChoiceCard: View {
    let mode: MultiDisplayMode
    let presentation: DisplayWorkspaceModePresentation
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Text(presentation.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                Text(presentation.supportingText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                DisplayWorkspaceModeDiagram(mode: mode)
                    .frame(height: 76)
                Text(presentation.technicalTerm)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 190)
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .background(
                isSelected ? Color.accentColor.opacity(0.11) : Color.primary.opacity(0.025),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(Color.accentColor)
                        .padding(8)
                }
            }
        }
        .buttonStyle(.plain)
        .help(presentation.accessibilityHint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(presentation.title). \(presentation.supportingText)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(presentation.accessibilityHint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct DisplayWorkspaceModeDiagram: View {
    let mode: MultiDisplayMode

    var body: some View {
        HStack(spacing: 8) {
            monitor("1")
            Group {
                if mode == .unified {
                    Image(systemName: "link")
                } else {
                    Color.clear
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 14)
            monitor(mode == .unified ? "1" : "W")
        }
        .accessibilityHidden(true)
    }

    private func monitor(_ workspace: String) -> some View {
        ZStack {
            Image(systemName: "display")
                .font(.system(size: 58, weight: .regular))
                .foregroundStyle(.secondary)
            Text(workspace)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.primary)
                .offset(y: -3)
        }
        .frame(width: 86, height: 68)
    }
}

private struct ProfileIdentityEditor: View {
    enum Presentation {
        case formRows
        case prominent
    }

    @ObservedObject var store: SettingsStore
    let presentation: Presentation
    @State private var draftName: String
    @State private var draftProfileID: UUID
    @FocusState private var isNameFocused: Bool

    init(store: SettingsStore, presentation: Presentation = .formRows) {
        self.store = store
        self.presentation = presentation
        _draftName = State(initialValue: store.settingsProfile.name)
        _draftProfileID = State(initialValue: store.settingsProfileID)
    }

    var body: some View {
        Group {
            switch presentation {
            case .formRows:
                Picker("Icon", selection: Binding(
                    get: { store.settingsProfile.iconStyle },
                    set: { store.setSettingsProfileIconStyle($0) }
                )) {
                    ForEach(ProfileIconStyle.allCases) { iconStyle in
                        Label(iconStyle.title, systemImage: iconStyle.systemImage)
                            .tag(iconStyle)
                    }
                }
                .pickerStyle(.menu)
                .help("Choose the icon shown for this profile in Settings.")

                nameField
            case .prominent:
                VStack(spacing: 12) {
                    Menu {
                        ForEach(ProfileIconStyle.allCases) { iconStyle in
                            Button {
                                store.setSettingsProfileIconStyle(iconStyle)
                            } label: {
                                Label {
                                    Text(iconStyle.title)
                                } icon: {
                                    Image(systemName: iconStyle == store.settingsProfile.iconStyle
                                        ? "checkmark"
                                        : iconStyle.systemImage)
                                }
                            }
                        }
                    } label: {
                        VStack(spacing: 7) {
                            ZStack(alignment: .bottomTrailing) {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                                Image(systemName: store.settingsProfile.iconStyle.systemImage)
                                    .font(.system(size: 48, weight: .medium))
                                Image(systemName: "chevron.down.circle.fill")
                                    .font(.title3)
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.secondary)
                                    .padding(7)
                            }
                            .frame(width: 104, height: 104)
                            Text("Change Icon")
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .help("Choose the icon shown for this profile in Settings.")
                    .accessibilityLabel("Profile icon, \(store.settingsProfile.iconStyle.title)")

                    nameField
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .font(.title3.weight(.semibold))
                        .accessibilityLabel("Profile name")
                }
            }
        }
        .onChange(of: isNameFocused) { wasFocused, isFocused in
            if wasFocused && !isFocused { commitDraftName() }
        }
        .onChange(of: store.settingsProfileID) { _, profileID in
            commitDraftName()
            draftProfileID = profileID
            draftName = store.settingsProfile.name
        }
        .onChange(of: store.settingsProfile.name) { _, name in
            if !isNameFocused {
                draftProfileID = store.settingsProfileID
                draftName = name
            }
        }
    }

    private var nameField: some View {
        TextField("Name", text: $draftName)
            .focused($isNameFocused)
            .onSubmit { commitDraftName() }
            .help("Rename the profile being edited.")
    }

    private func commitDraftName() {
        store.renameProfile(draftProfileID, to: draftName)
        if draftProfileID == store.settingsProfileID {
            draftName = store.settingsProfile.name
        }
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
                Text("Copy Editing Profile").tag(ProfileCreationSource.currentProfile)
                Text("Start from Scratch").tag(ProfileCreationSource.scratch)
            }
            .pickerStyle(.radioGroup)

            Group {
                switch source {
                case .currentProfile:
                    Text("Copies “\(currentProfileName)” including its workspaces, display mode and roles, workspace assignments, and application settings.")
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

enum WorkspaceSettingsPreviewRefreshPolicy {
    static func captureOrder(workspaceIDs: [UUID], selectedWorkspaceID: UUID?) -> [UUID] {
        guard let selectedWorkspaceID,
              workspaceIDs.contains(selectedWorkspaceID)
        else { return workspaceIDs }
        return [selectedWorkspaceID] + workspaceIDs.filter { $0 != selectedWorkspaceID }
    }
}

@MainActor
enum WorkspaceSettingsFieldBindings {
    static func name(store: SettingsStore, workspaceID: UUID) -> Binding<String> {
        Binding(
            get: {
                store.settingsWorkspaces.first(where: { $0.id == workspaceID })?.name ?? ""
            },
            set: { store.setSettingsWorkspaceName($0, for: workspaceID) }
        )
    }

    static func key(store: SettingsStore, workspaceID: UUID) -> Binding<String> {
        Binding(
            get: {
                store.settingsWorkspaces.first(where: { $0.id == workspaceID })?.key.uppercased() ?? ""
            },
            set: { store.setSettingsWorkspaceKey($0, for: workspaceID) }
        )
    }

    static func layout(store: SettingsStore, workspaceID: UUID) -> Binding<WorkspaceLayout> {
        Binding(
            get: {
                store.settingsWorkspaces.first(where: { $0.id == workspaceID })?.layout ?? .none
            },
            set: { store.setSettingsLayout($0, for: workspaceID) }
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

/// Local editing policy for the Tiled geometry inspector. Link choices deliberately belong to the
/// transient Settings view rather than the workspace configuration, profile, or synced state.
enum TiledGeometryEditPolicy {
    enum LinkGroup {
        case inner
        case outer
    }

    enum Gap: CaseIterable {
        case innerHorizontal
        case innerVertical
        case outerTop
        case outerRight
        case outerBottom
        case outerLeft

        var keyPath: WritableKeyPath<WorkspaceLayoutGaps, Double> {
            switch self {
            case .innerHorizontal: \WorkspaceLayoutGaps.innerHorizontal
            case .innerVertical: \WorkspaceLayoutGaps.innerVertical
            case .outerTop: \WorkspaceLayoutGaps.outerTop
            case .outerRight: \WorkspaceLayoutGaps.outerRight
            case .outerBottom: \WorkspaceLayoutGaps.outerBottom
            case .outerLeft: \WorkspaceLayoutGaps.outerLeft
            }
        }

        var isInner: Bool {
            switch self {
            case .innerHorizontal, .innerVertical: true
            case .outerTop, .outerRight, .outerBottom, .outerLeft: false
            }
        }
    }

    static func normalizedForInnerLink(_ gaps: WorkspaceLayoutGaps) -> WorkspaceLayoutGaps {
        var result = gaps
        result.innerVertical = result.innerHorizontal
        return result
    }

    static func normalizedForOuterLink(_ gaps: WorkspaceLayoutGaps) -> WorkspaceLayoutGaps {
        var result = gaps
        result.outerRight = result.outerTop
        result.outerBottom = result.outerTop
        result.outerLeft = result.outerTop
        return result
    }

    static func normalizationForLinkActivation(
        _ group: LinkGroup,
        gaps: WorkspaceLayoutGaps,
        preservesLegacyGeometry: Bool
    ) -> WorkspaceLayoutGaps? {
        guard !preservesLegacyGeometry else { return nil }
        return switch group {
        case .inner: normalizedForInnerLink(gaps)
        case .outer: normalizedForOuterLink(gaps)
        }
    }

    static func pointValueText(_ value: Double) -> String {
        let representation = String(value)
        return representation.hasSuffix(".0")
            ? String(representation.dropLast(2))
            : representation
    }

    /// The compact diagram is explanatory rather than a scale drawing. A square-root scale keeps
    /// small non-zero values visible while preserving zero, monotonic growth, and the exact maximum.
    static func previewExtent(
        value: Double,
        maximumValue: Double,
        maximumExtent: CGFloat
    ) -> CGFloat {
        guard maximumValue > 0, maximumExtent > 0 else { return 0 }
        let normalized = min(max(value / maximumValue, 0), 1)
        return CGFloat(normalized.squareRoot()) * maximumExtent
    }

    static func applying(
        _ value: Double,
        to gap: Gap,
        gaps: WorkspaceLayoutGaps,
        isInnerLinked: Bool,
        isOuterLinked: Bool
    ) -> WorkspaceLayoutGaps {
        var result = gaps
        result[keyPath: gap.keyPath] = value
        if gap.isInner, isInnerLinked {
            result.innerHorizontal = value
            result.innerVertical = value
        } else if !gap.isInner, isOuterLinked {
            result.outerTop = value
            result.outerRight = value
            result.outerBottom = value
            result.outerLeft = value
        }
        return result
    }
}

struct TiledGeometryEditingLinks: Equatable {
    var inner = false
    var outer = false

    mutating func reset() {
        inner = false
        outer = false
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

enum WorkspaceLayoutMiniatureKind: Equatable, Sendable {
    case freeform
    case tiled
    case accordion

    init(layout: WorkspaceLayout) {
        self = switch layout {
        case .none: .freeform
        case .tiled: .tiled
        case .accordion: .accordion
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .freeform: "Freeform layout preview"
        case .tiled: "Tiled layout preview"
        case .accordion: "Accordion layout preview"
        }
    }
}

enum WorkspaceLayoutChoiceDescription {
    static func layout(_ layout: WorkspaceLayout) -> String {
        switch layout {
        case .none:
            "Overlapping windows stay where you place them."
        case .tiled:
            "Windows fill the screen without overlapping."
        case .accordion:
            "Windows overlap while neighbouring edges remain visible."
        }
    }

    static func orientation(
        _ orientation: WorkspaceLayoutOrientation,
        layout: WorkspaceLayout
    ) -> String {
        switch orientation {
        case .automatic:
            "Flows left to right on a wide display and top to bottom on a portrait display."
        case .horizontal:
            layout == .accordion
                ? "Accordion windows overlap from left to right."
                : "Windows tile from left to right."
        case .vertical:
            layout == .accordion
                ? "Accordion windows overlap from top to bottom."
                : "Windows tile from top to bottom."
        }
    }
}

struct WorkspaceSettingsView: View {
    @ObservedObject var store: SettingsStore
    let engine: WorkspaceEngine
    let previewRepository: WorkspacePreviewRepository?
    let highlightedEntry: SettingsSearchEntry?
    let requestedWorkspaceID: UUID?
    @Environment(\.undoManager) private var undoManager
    @State private var selectedWorkspaceID: UUID?
    @State private var tiledGeometryEditingLinks = TiledGeometryEditingLinks()

    init(
        store: SettingsStore,
        engine: WorkspaceEngine,
        previewRepository: WorkspacePreviewRepository? = nil,
        highlightedEntry: SettingsSearchEntry? = nil,
        requestedWorkspaceID: UUID? = nil,
        initiallySelectedWorkspaceID: UUID? = nil
    ) {
        self.store = store
        self.engine = engine
        self.previewRepository = previewRepository
        self.highlightedEntry = highlightedEntry
        self.requestedWorkspaceID = requestedWorkspaceID
        let initialWorkspaceID = requestedWorkspaceID ?? highlightedEntry?.workspaceID
            ?? initiallySelectedWorkspaceID
        _selectedWorkspaceID = State(
            initialValue: initialWorkspaceID
        )
    }

    var body: some View {
        GeometryReader { geometry in
            responsiveContent(for: SettingsDetailLayout.resolve(availableWidth: geometry.size.width))
        }
        .onAppear {
            engine.setWorkspacePreviewObservationEnabled(store.isEditingActiveProfile)
            reconcileSelection(preferred: requestedWorkspaceID ?? highlightedEntry?.workspaceID)
            refreshWorkspacePreviews()
        }
        .onDisappear {
            engine.setWorkspacePreviewObservationEnabled(false)
        }
        .onChange(of: store.settingsWorkspaces.map(\.id)) { _, _ in
            reconcileSelection()
            refreshWorkspacePreviews()
        }
        .onChange(of: store.settingsProfileID) { _, _ in
            engine.setWorkspacePreviewObservationEnabled(store.isEditingActiveProfile)
            resetTiledGeometryEditingLinks()
            reconcileSelection()
            refreshWorkspacePreviews()
        }
        .onChange(of: store.activeProfileID) { _, _ in
            engine.setWorkspacePreviewObservationEnabled(store.isEditingActiveProfile)
            refreshWorkspacePreviews()
        }
        .onChange(of: store.settingsWorkspaces.map { "\($0.id.uuidString):\($0.layout.rawValue)" }) { _, _ in
            resetTiledGeometryEditingLinks()
            refreshWorkspacePreviews()
        }
        .onChange(of: selectedWorkspaceID) { _, _ in
            resetTiledGeometryEditingLinks()
            refreshSelectedWorkspacePreview()
        }
        .onChange(of: store.workspacePreviewThumbnailsEnabled) { _, _ in
            refreshSelectedWorkspacePreview()
        }
        .onChange(of: previewRepository?.invalidationGeneration) { _, _ in
            refreshWorkspacePreviews()
        }
        .onChange(of: highlightedEntry?.workspaceID) { _, workspaceID in
            reconcileSelection(preferred: workspaceID)
        }
        .onChange(of: requestedWorkspaceID) { _, workspaceID in
            reconcileSelection(preferred: workspaceID)
        }
    }

    @ViewBuilder
    private func responsiveContent(for layout: SettingsDetailLayout) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                workspaceTabStrip
                if hasIdentityConflict {
                    Label(
                        "Resolve duplicate or empty names and keys before relying on shortcuts.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
                if let highlightedEntry {
                    searchHighlight(highlightedEntry)
                }
                if let workspace = selectedWorkspace {
                    workspaceInspector(workspace, layout: layout)
                        .id(workspace.id)
                } else {
                    ContentUnavailableView(
                        "No Workspace Selected",
                        systemImage: "square.grid.3x3",
                        description: Text("Add or select a workspace to configure it.")
                    )
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var workspaceTabStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(store.settingsWorkspaces) { workspace in
                        workspaceTab(workspace)
                            .id(workspace.id)
                    }
                    Button {
                        selectedWorkspaceID = store.addSettingsWorkspace()
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 26, weight: .medium))
                            Text("Add Workspace")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        .frame(width: 168, height: 126)
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    Color(nsColor: .separatorColor),
                                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add workspace")
                    .dropDestination(for: String.self) { values, _ in
                        guard let source = values.first.flatMap(UUID.init(uuidString:)),
                              let sourceIndex = store.settingsWorkspaces.firstIndex(where: { $0.id == source })
                        else { return false }
                        store.moveSettingsWorkspaces(
                            fromOffsets: IndexSet(integer: sourceIndex),
                            toOffset: store.settingsWorkspaces.count
                        )
                        return true
                    }
                }
                .padding(8)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                if let selectedWorkspaceID {
                    proxy.scrollTo(selectedWorkspaceID, anchor: .center)
                }
            }
            .onChange(of: selectedWorkspaceID) { _, workspaceID in
                guard let workspaceID else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    proxy.scrollTo(workspaceID, anchor: .center)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspaces")
    }

    private func workspaceTab(_ workspace: WorkspaceDefinition) -> some View {
        let isSelected = selectedWorkspaceID == workspace.id
        return Button {
            selectedWorkspaceID = workspace.id
        } label: {
            VStack(spacing: 7) {
                workspaceTabPreview(workspace)
                    .frame(height: 82)
                HStack(spacing: 8) {
                    Text(workspace.name)
                        .font(.subheadline.weight(isSelected ? .semibold : .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 2)
                    Text(workspace.key.uppercased().isEmpty ? "—" : workspace.key.uppercased())
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(isSelected ? Color.white : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                }
            }
            .padding(8)
            .frame(width: 168, height: 126)
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .background(
                isSelected ? Color.accentColor.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .draggable(workspace.id.uuidString)
        .dropDestination(for: String.self) { values, _ in
            guard let source = values.first.flatMap(UUID.init(uuidString:)) else { return false }
            store.moveSettingsWorkspace(id: source, before: workspace.id)
            return true
        }
        .contextMenu { workspaceContextMenu(workspace) }
        .help("\(workspace.name) — \(displayRoleName(for: workspace.id)), \(workspace.layout.title), key \(workspace.key.uppercased())")
        .accessibilityLabel(WorkspaceSettingsAccessibility.rowLabel(
            workspace: workspace,
            displayRoleName: displayRoleName(for: workspace.id)
        ))
        .accessibilityHint("Selects this workspace for editing")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "Move earlier") {
            store.moveSettingsWorkspace(id: workspace.id, offset: -1)
        }
        .accessibilityAction(named: "Move later") {
            store.moveSettingsWorkspace(id: workspace.id, offset: 1)
        }
    }

    @ViewBuilder
    private func workspaceTabPreview(_ workspace: WorkspaceDefinition) -> some View {
        if store.isEditingActiveProfile,
           let entry = previewRepository?.entries[workspace.id] {
            WorkspacePreviewView(
                descriptor: entry.descriptor,
                background: entry.background,
                images: entry.images,
                interactionMode: .workspaceOnly
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        } else {
            WorkspaceLayoutMiniature(kind: WorkspaceLayoutMiniatureKind(layout: workspace.layout))
        }
    }

    private func searchHighlight(_ entry: SettingsSearchEntry) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title).font(.subheadline.weight(.semibold))
                Text(entry.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "magnifyingglass")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityLabel("Search result: \(entry.title). \(entry.description)")
    }

    @ViewBuilder
    private func workspaceInspector(_ workspace: WorkspaceDefinition, layout: SettingsDetailLayout) -> some View {
        switch layout {
        case .wide:
            HStack(alignment: .top, spacing: 16) {
                workspaceDetailsPanel(workspace)
                    .frame(width: 320)
                VStack(alignment: .leading, spacing: 16) {
                    workspaceLayoutPanel(workspace)
                    workspaceRepairPanel(workspace)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        case .compact:
            VStack(alignment: .leading, spacing: 16) {
                workspaceDetailsPanel(workspace)
                workspaceLayoutPanel(workspace)
                workspaceRepairPanel(workspace)
            }
        }
    }

    private func workspaceDetailsPanel(_ workspace: WorkspaceDefinition) -> some View {
        workspaceSettingsPanel("Workspace details") {
            Text("Name")
                .font(.subheadline.weight(.medium))
            TextField(
                "Workspace name",
                text: WorkspaceSettingsFieldBindings.name(store: store, workspaceID: workspace.id)
            )
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Workspace name")

            Divider()

            Picker("Home Display", selection: roleBinding(for: workspace.id)) {
                ForEach(store.settingsProfile.displayRoles) { role in
                    Text(role.name).tag(role.id)
                }
            }
            Text(roleNote(for: workspace.id))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            LabeledContent("Workspace Key") {
                TextField(
                    "Key",
                    text: WorkspaceSettingsFieldBindings.key(store: store, workspaceID: workspace.id)
                )
                .labelsHidden()
                .multilineTextAlignment(.center)
                .frame(width: 68)
                .accessibilityLabel("Workspace key")
            }

            workspaceIdentityWarnings(workspace)

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                Text("Generated shortcuts")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                workspaceShortcutSummaryRow("Switch workspace", workspace: workspace, family: .navigate)
                workspaceShortcutSummaryRow("Move window", workspace: workspace, family: .arrange)
                Text("Change the workspace key above to update both. Modifier keys are set globally in Shortcuts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack(spacing: 8) {
                Button {
                    duplicateSelectedWorkspace()
                } label: {
                    Label("Duplicate", systemImage: "square.on.square")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel("Duplicate selected workspace")
                Button(role: .destructive) {
                    deleteSelectedWorkspace()
                } label: {
                    Label("Delete", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .disabled(store.settingsWorkspaces.count <= 1)
                .accessibilityLabel("Delete selected workspace")
            }
            .buttonStyle(.bordered)

            Divider()

            SettingsActionRow(
                title: "Workspace collection",
                description: "Restore WindowRanger's built-in workspace names, order, keys, and layout choices."
            ) {
                Button("Restore Defaults") {
                    store.resetSettingsWorkspacesToDefaults()
                    reconcileSelection()
                }
                .help(SettingsCopy.restoreWindowManagerDefaultsTitle)
                .accessibilityLabel(SettingsCopy.restoreWindowManagerDefaultsTitle)
            }
        }
    }

    @ViewBuilder
    private func workspaceIdentityWarnings(_ workspace: WorkspaceDefinition) -> some View {
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
    }

    private func workspaceShortcutSummaryRow(
        _ title: String,
        workspace: WorkspaceDefinition,
        family: ShortcutFamily
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 8)
            if let keyCode = HotKeyManager.keyCodes[workspace.key.lowercased()] {
                let keys = store.hotKeyConfiguration
                    .chord(forWorkspaceKeyCode: keyCode, family: family)
                    .keyCaps
                Text(keys.joined())
                    .font(.system(.callout, design: .monospaced).weight(.medium))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(keys.joined(separator: " "))
            } else {
                Text("Not set").foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func workspaceLayoutPanel(_ workspace: WorkspaceDefinition) -> some View {
        workspaceSettingsPanel("Layout") {
            layoutStyleSelector(workspace)

            Divider()

            LabeledContent("Copy Layout") {
                Menu("Choose Workspace…") {
                    ForEach(store.settingsWorkspaces.filter { $0.id != workspace.id }) { source in
                        Button {
                            store.copySettingsLayout(from: source.id, to: workspace.id, undoManager: undoManager)
                        } label: {
                            Label("\(source.name) — \(source.layout.title)", systemImage: source.layout.systemImage)
                        }
                    }
                }
                .disabled(store.settingsWorkspaces.count <= 1)
                .help("Copy another workspace's layout style and geometry")
                .frame(minWidth: 220, alignment: .trailing)
            }
            Text(
                "Copies the layout style, orientation, gaps and padding from another workspace. "
                    + "Its name, key, Home Display, app rules and window membership stay unchanged."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if store.settingsUsesLegacyLayoutGeometry(for: workspace.id), workspace.layout != .none {
                Divider()
                Label(
                    "This workspace is preserving its pre-upgrade geometry.",
                    systemImage: "clock.arrow.circlepath"
                )
                .foregroundStyle(.secondary)
                Button("Use Current Layout Defaults") {
                    store.setSettingsLayoutConfiguration(.aeroSpaceUserDefaults, for: workspace.id)
                }
            }

            let controls = WorkspaceInspectorControlVisibility(layout: workspace.layout)
            if controls.showsFreeformExplanation {
                Divider()
                Text("Freeform leaves window frames under manual control. WindowRanger still manages workspace visibility, focus, persistence, display assignment, and quit/wake recovery.")
                    .foregroundStyle(.secondary)
            }
            if controls.showsOrientation {
                Divider()
                orientationPicker(workspace)
            }
            if controls.showsTiledGeometry {
                tiledGeometryControls(workspace.id)
            }
            if controls.showsAccordionPadding {
                Divider()
                LabeledContent("Visible edge padding") {
                    HStack(spacing: 8) {
                        Text("\(Int(configuration(for: workspace.id).accordionPadding)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Stepper(
                            "Visible edge padding",
                            value: configurationBinding(\.accordionPadding, workspaceID: workspace.id),
                            in: 0...800,
                            step: 5
                        )
                        .labelsHidden()
                    }
                }
                Text("Padding controls how much of neighbouring Accordion windows remains visible.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
            Text("Floating windows, automatically detected dialogs, and apps excluded by a rule keep their own frames and never affect layout geometry.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func workspaceRepairPanel(_ workspace: WorkspaceDefinition) -> some View {
        workspaceSettingsPanel("Repair") {
            SettingsActionRow(
                title: "Selected workspace",
                description: "Restore Freeform and WindowRanger's built-in geometry while keeping its name, key, Home Display, app rules, and live window membership. This settings change can be undone."
            ) {
                Button("Reset Workspace", systemImage: "arrow.counterclockwise") {
                    store.resetSettingsWorkspace(workspace.id, undoManager: undoManager)
                }
            }

            if store.isEditingActiveProfile {
                Divider()
                SettingsActionRow(
                    title: "Active workspace",
                    description: "Recover the interaction display's active workspace, clear transient positioning, and reapply its current layout."
                ) {
                    Button("Bring Windows Back On Screen") {
                        engine.resetCurrentWorkspace()
                    }
                }
            }
        }
    }

    private func workspaceSettingsPanel<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            Divider()
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
    }

    private func layoutStyleSelector(_ workspace: WorkspaceDefinition) -> some View {
        let selection = WorkspaceSettingsFieldBindings.layout(store: store, workspaceID: workspace.id)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Layout Style")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                ForEach(WorkspaceLayout.allCases) { layout in
                    WorkspaceVisualChoiceCard(
                        title: layout.title,
                        isSelected: selection.wrappedValue == layout,
                        accessibilityHint: WorkspaceLayoutChoiceDescription.layout(layout)
                    ) {
                        selection.wrappedValue = layout
                    } preview: {
                        WorkspaceLayoutChoiceDiagram(
                            layout: layout,
                            orientation: .horizontal
                        )
                    }
                }
            }
        }
    }

    private func orientationPicker(_ workspace: WorkspaceDefinition) -> some View {
        let selection = configurationBinding(\.orientation, workspaceID: workspace.id)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Orientation")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                ForEach(WorkspaceLayoutOrientation.allCases) { orientation in
                    WorkspaceVisualChoiceCard(
                        title: orientation.title,
                        isSelected: selection.wrappedValue == orientation,
                        accessibilityHint: WorkspaceLayoutChoiceDescription.orientation(
                            orientation,
                            layout: workspace.layout
                        )
                    ) {
                        selection.wrappedValue = orientation
                    } preview: {
                        WorkspaceLayoutChoiceDiagram(
                            layout: workspace.layout,
                            orientation: orientation
                        )
                    }
                }
            }
            Text("Automatic uses horizontal windows on a wide display and vertical windows on a portrait display.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func tiledGeometryControls(_ workspaceID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Inner gaps").font(.subheadline.weight(.semibold))
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    innerGapPreview(configuration(for: workspaceID).gaps)
                    innerGapValueControls(workspaceID)
                        .frame(width: 276, alignment: .leading)
                    innerGapLinkToggle(workspaceID)
                }
                VStack(alignment: .leading, spacing: 8) {
                    innerGapPreview(configuration(for: workspaceID).gaps)
                    innerGapValueControls(workspaceID)
                    innerGapLinkToggle(workspaceID)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            Text("Outer screen padding").font(.subheadline.weight(.semibold))
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    outerPaddingPreview(configuration(for: workspaceID).gaps)
                    outerPaddingValueControls(workspaceID, usesGrid: true)
                        .frame(width: 276, alignment: .leading)
                    outerPaddingLinkToggle(workspaceID)
                }
                VStack(alignment: .leading, spacing: 8) {
                    outerPaddingPreview(configuration(for: workspaceID).gaps)
                    outerPaddingValueControls(workspaceID, usesGrid: false)
                    outerPaddingLinkToggle(workspaceID)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    private func innerGapValueControls(_ workspaceID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            gapStepper("Horizontal", .innerHorizontal, workspaceID: workspaceID, range: 0...200)
            gapStepper("Vertical", .innerVertical, workspaceID: workspaceID, range: 0...200)
        }
    }

    private func innerGapLinkToggle(_ workspaceID: UUID) -> some View {
        geometryLinkToggle("Keep equal", isOn: innerLinkBinding(workspaceID))
    }

    private func outerPaddingLinkToggle(_ workspaceID: UUID) -> some View {
        geometryLinkToggle("Keep all sides equal", isOn: outerLinkBinding(workspaceID))
    }

    private func geometryLinkToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Label(title, systemImage: "link")
                .lineLimit(1)
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .accessibilityLabel(title)
        }
    }

    @ViewBuilder
    private func outerPaddingValueControls(_ workspaceID: UUID, usesGrid: Bool) -> some View {
        if usesGrid {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    outerPaddingStepper(.outerTop, workspaceID: workspaceID)
                        .frame(width: 132)
                    outerPaddingStepper(.outerRight, workspaceID: workspaceID)
                        .frame(width: 132)
                }
                GridRow {
                    outerPaddingStepper(.outerBottom, workspaceID: workspaceID)
                        .frame(width: 132)
                    outerPaddingStepper(.outerLeft, workspaceID: workspaceID)
                        .frame(width: 132)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                outerPaddingStepper(.outerTop, workspaceID: workspaceID)
                outerPaddingStepper(.outerRight, workspaceID: workspaceID)
                outerPaddingStepper(.outerBottom, workspaceID: workspaceID)
                outerPaddingStepper(.outerLeft, workspaceID: workspaceID)
            }
        }
    }

    private func outerPaddingStepper(
        _ gap: TiledGeometryEditPolicy.Gap,
        workspaceID: UUID
    ) -> some View {
        let title: String = switch gap {
        case .outerTop: "Top"
        case .outerRight: "Right"
        case .outerBottom: "Bottom"
        case .outerLeft: "Left"
        case .innerHorizontal, .innerVertical: preconditionFailure("Outer padding only")
        }
        return gapStepper(title, gap, workspaceID: workspaceID, range: 0...400)
    }

    private func gapStepper(
        _ title: String,
        _ gap: TiledGeometryEditPolicy.Gap,
        workspaceID: UUID,
        range: ClosedRange<Double>
    ) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .lineLimit(1)
                .accessibilityHidden(true)
            Spacer(minLength: 2)
            Text(
                "\(TiledGeometryEditPolicy.pointValueText(configuration(for: workspaceID).gaps[keyPath: gap.keyPath])) pt"
            )
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 42, alignment: .trailing)
                .accessibilityHidden(true)
            Stepper(
                title,
                value: gapBinding(gap, workspaceID: workspaceID),
                in: range
            )
            .labelsHidden()
            .accessibilityLabel(title)
            .accessibilityValue(
                "\(TiledGeometryEditPolicy.pointValueText(configuration(for: workspaceID).gaps[keyPath: gap.keyPath])) points"
            )
        }
    }

    private func innerGapPreview(_ gaps: WorkspaceLayoutGaps) -> some View {
        GeometryReader { geometry in
            let horizontalGap = TiledGeometryEditPolicy.previewExtent(
                value: gaps.innerHorizontal,
                maximumValue: 200,
                maximumExtent: geometry.size.width * 0.22
            )
            let verticalGap = TiledGeometryEditPolicy.previewExtent(
                value: gaps.innerVertical,
                maximumValue: 200,
                maximumExtent: geometry.size.height * 0.28
            )
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(nsColor: .controlBackgroundColor))
                Rectangle()
                    .fill(horizontalGap > 0
                        ? Color.accentColor.opacity(0.55)
                        : Color(nsColor: .separatorColor))
                    .frame(width: max(horizontalGap, 0.5))
                Rectangle()
                    .fill(verticalGap > 0
                        ? Color.accentColor.opacity(0.55)
                        : Color(nsColor: .separatorColor))
                    .frame(height: max(verticalGap, 0.5))
                RoundedRectangle(cornerRadius: 5)
                    .stroke(.separator, lineWidth: 0.5)
            }
        }
        .frame(width: 92, height: 58)
        .accessibilityHidden(true)
    }

    private func outerPaddingPreview(_ gaps: WorkspaceLayoutGaps) -> some View {
        GeometryReader { geometry in
            let maximumHorizontalInset = geometry.size.width * 0.28
            let maximumVerticalInset = geometry.size.height * 0.28
            let top = TiledGeometryEditPolicy.previewExtent(
                value: gaps.outerTop,
                maximumValue: 400,
                maximumExtent: maximumVerticalInset
            )
            let right = TiledGeometryEditPolicy.previewExtent(
                value: gaps.outerRight,
                maximumValue: 400,
                maximumExtent: maximumHorizontalInset
            )
            let bottom = TiledGeometryEditPolicy.previewExtent(
                value: gaps.outerBottom,
                maximumValue: 400,
                maximumExtent: maximumVerticalInset
            )
            let left = TiledGeometryEditPolicy.previewExtent(
                value: gaps.outerLeft,
                maximumValue: 400,
                maximumExtent: maximumHorizontalInset
            )
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.accentColor.opacity(0.55))
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(.separator, lineWidth: 0.5)
                    }
                    .frame(
                        width: max(8, geometry.size.width - left - right),
                        height: max(8, geometry.size.height - top - bottom)
                    )
                    .offset(x: left, y: top)
            }
        }
        .frame(width: 92, height: 58)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func workspaceContextMenu(_ workspace: WorkspaceDefinition) -> some View {
        Button("Move Left") { store.moveSettingsWorkspace(id: workspace.id, offset: -1) }
            .disabled(store.settingsWorkspaces.first?.id == workspace.id)
        Button("Move Right") { store.moveSettingsWorkspace(id: workspace.id, offset: 1) }
            .disabled(store.settingsWorkspaces.last?.id == workspace.id)
        Divider()
        Button("Duplicate") {
            selectedWorkspaceID = store.duplicateSettingsWorkspace(id: workspace.id)
        }
        Button("Delete", role: .destructive) {
            selectedWorkspaceID = WorkspaceSettingsSelectionPolicy.selectionAfterDeleting(
                workspace.id,
                from: store.settingsWorkspaces.map(\.id)
            )
            store.removeSettingsWorkspace(id: workspace.id)
        }
        .disabled(store.settingsWorkspaces.count <= 1)
    }

    private var selectedWorkspace: WorkspaceDefinition? {
        selectedWorkspaceID.flatMap { id in store.settingsWorkspaces.first { $0.id == id } }
    }

    private var hasIdentityConflict: Bool {
        store.settingsWorkspaces.contains { workspace in
            workspace.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                workspace.key.isEmpty || isDuplicateName(workspace) || isDuplicateKey(workspace) ||
                !shortcutConfigurationReport.issues(forWorkspace: workspace.id).isEmpty
        }
    }

    private var shortcutConfigurationReport: ShortcutConfigurationReport {
        ShortcutConflictModel.evaluate(
            configuration: store.hotKeyConfiguration,
            workspaces: store.settingsWorkspaces
        )
    }

    private func isDuplicateName(_ workspace: WorkspaceDefinition) -> Bool {
        let name = workspace.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !name.isEmpty && store.settingsWorkspaces.filter {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == name
        }.count > 1
    }

    private func isDuplicateKey(_ workspace: WorkspaceDefinition) -> Bool {
        !workspace.key.isEmpty && store.settingsWorkspaces.filter {
            $0.key.lowercased() == workspace.key.lowercased()
        }.count > 1
    }

    private func displayRoleName(for workspaceID: UUID) -> String {
        guard let roleID = store.settingsRoleID(for: workspaceID),
              let role = store.settingsProfile.displayRoles.first(where: { $0.id == roleID })
        else { return "Unassigned" }
        return role.name
    }

    private func roleBinding(for workspaceID: UUID) -> Binding<UUID> {
        Binding(
            get: {
                store.settingsRoleID(for: workspaceID)
                    ?? store.settingsProfile.displayRoles.first!.id
            },
            set: { store.assignSettingsWorkspace(workspaceID, toRole: $0) }
        )
    }

    private func roleNote(for workspaceID: UUID) -> String {
        guard let roleID = store.settingsRoleID(for: workspaceID),
              let role = store.settingsProfile.displayRoles.first(where: { $0.id == roleID })
        else { return "No display role is assigned; WindowRanger uses the safe main-display fallback." }
        switch store.roleBindingResolution(roleID) {
        case .ambiguous:
            return "\(role.name) matches multiple identical monitors, so WindowRanger will not guess and uses the safe main-display fallback."
        case .disconnected:
            return "\(role.name)'s monitor is disconnected; this home is preserved and returns when the binding reconnects."
        case .exactIdentifier, .exactUUID, .portableFingerprint:
            return "The synced \(role.name) role is bound on this Mac using a conservative monitor identity."
        case nil:
            return "The synced \(role.name) role is unbound on this Mac and currently uses the safe main-display fallback. Bind it in Displays."
        }
    }

    private func configuration(for workspaceID: UUID) -> WorkspaceLayoutConfiguration {
        store.settingsLayoutConfiguration(for: workspaceID)
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
                store.setSettingsLayoutConfiguration(updated, for: workspaceID)
            }
        )
    }

    private func innerLinkBinding(_ workspaceID: UUID) -> Binding<Bool> {
        Binding(
            get: { tiledGeometryEditingLinks.inner },
            set: { isLinked in
                tiledGeometryEditingLinks.inner = isLinked
                guard isLinked else { return }
                guard let normalized = TiledGeometryEditPolicy.normalizationForLinkActivation(
                    .inner,
                    gaps: configuration(for: workspaceID).gaps,
                    preservesLegacyGeometry: store.settingsUsesLegacyLayoutGeometry(
                        for: workspaceID
                    )
                ) else { return }
                updateGaps(
                    normalized,
                    workspaceID: workspaceID,
                    undoManager: undoManager
                )
            }
        )
    }

    private func outerLinkBinding(_ workspaceID: UUID) -> Binding<Bool> {
        Binding(
            get: { tiledGeometryEditingLinks.outer },
            set: { isLinked in
                tiledGeometryEditingLinks.outer = isLinked
                guard isLinked else { return }
                guard let normalized = TiledGeometryEditPolicy.normalizationForLinkActivation(
                    .outer,
                    gaps: configuration(for: workspaceID).gaps,
                    preservesLegacyGeometry: store.settingsUsesLegacyLayoutGeometry(
                        for: workspaceID
                    )
                ) else { return }
                updateGaps(
                    normalized,
                    workspaceID: workspaceID,
                    undoManager: undoManager
                )
            }
        )
    }

    private func gapBinding(
        _ gap: TiledGeometryEditPolicy.Gap,
        workspaceID: UUID
    ) -> Binding<Double> {
        Binding(
            get: { configuration(for: workspaceID).gaps[keyPath: gap.keyPath] },
            set: { newValue in
                let linkedEdit = gap.isInner
                    ? tiledGeometryEditingLinks.inner
                    : tiledGeometryEditingLinks.outer
                updateGaps(
                    TiledGeometryEditPolicy.applying(
                        newValue,
                        to: gap,
                        gaps: configuration(for: workspaceID).gaps,
                        isInnerLinked: tiledGeometryEditingLinks.inner,
                        isOuterLinked: tiledGeometryEditingLinks.outer
                    ),
                    workspaceID: workspaceID,
                    undoManager: linkedEdit ? undoManager : nil
                )
            }
        )
    }

    private func updateGaps(
        _ gaps: WorkspaceLayoutGaps,
        workspaceID: UUID,
        undoManager: UndoManager? = nil
    ) {
        var updated = configuration(for: workspaceID)
        updated.gaps = gaps
        store.setSettingsLayoutConfiguration(
            updated,
            for: workspaceID,
            undoManager: undoManager,
            actionName: "Change Linked Layout Geometry"
        )
    }

    private func resetTiledGeometryEditingLinks() {
        tiledGeometryEditingLinks.reset()
    }

    private func duplicateSelectedWorkspace() {
        guard let workspaceID = selectedWorkspace?.id else { return }
        selectedWorkspaceID = store.duplicateSettingsWorkspace(id: workspaceID)
    }

    private func deleteSelectedWorkspace() {
        guard let workspaceID = selectedWorkspace?.id, store.settingsWorkspaces.count > 1 else { return }
        selectedWorkspaceID = WorkspaceSettingsSelectionPolicy.selectionAfterDeleting(
            workspaceID,
            from: store.settingsWorkspaces.map(\.id)
        )
        store.removeSettingsWorkspace(id: workspaceID)
    }

    private func reconcileSelection(preferred: UUID? = nil) {
        selectedWorkspaceID = WorkspaceSettingsSelectionPolicy.reconciled(
            current: selectedWorkspaceID,
            preferred: preferred,
            workspaceIDs: store.settingsWorkspaces.map(\.id)
        )
    }

    private func refreshSelectedWorkspacePreview() {
        guard store.isEditingActiveProfile,
              let workspace = selectedWorkspace,
              let previewRepository
        else { return }
        let expectedProfileID = store.settingsProfileID
        previewRepository.isEnabled = store.workspacePreviewThumbnailsEnabled
        engine.workspacePreviewDescriptor(
            for: workspace.id,
            workspaceName: workspace.name
        ) { [weak store, weak previewRepository] descriptor in
            guard let store,
                  let previewRepository,
                  store.settingsProfileID == expectedProfileID,
                  store.isEditingActiveProfile,
                  store.settingsWorkspaces.contains(where: { $0.id == descriptor.workspaceID })
            else { return }
            previewRepository.update(
                descriptor: descriptor,
                captureEnabled: store.workspacePreviewThumbnailsEnabled
            )
        }
    }

    /// Populate every active-profile tab when Settings opens. Capture batches remain serialized and
    /// bounded by the shared repository; asking for the selected workspace first makes the current
    /// editor fill promptly while the remaining tab previews arrive progressively.
    private func refreshWorkspacePreviews() {
        guard store.isEditingActiveProfile,
              let previewRepository
        else { return }
        let expectedProfileID = store.settingsProfileID
        let selectedWorkspaceID = selectedWorkspaceID
        previewRepository.isEnabled = store.workspacePreviewThumbnailsEnabled
        let workspacesByID = Dictionary(uniqueKeysWithValues: store.settingsWorkspaces.map { ($0.id, $0) })
        let captureOrder = WorkspaceSettingsPreviewRefreshPolicy.captureOrder(
            workspaceIDs: store.settingsWorkspaces.map(\.id),
            selectedWorkspaceID: selectedWorkspaceID
        )
        for workspaceID in captureOrder {
            guard let workspace = workspacesByID[workspaceID] else { continue }
            engine.workspacePreviewDescriptor(
                for: workspace.id,
                workspaceName: workspace.name
            ) { [weak store, weak previewRepository] descriptor in
                guard let store,
                      let previewRepository,
                      store.settingsProfileID == expectedProfileID,
                      store.isEditingActiveProfile,
                      store.settingsWorkspaces.contains(where: { $0.id == descriptor.workspaceID })
                else { return }
                previewRepository.update(
                    descriptor: descriptor,
                    captureEnabled: store.workspacePreviewThumbnailsEnabled
                )
            }
        }
    }
}

private struct WorkspaceVisualChoiceCard<Preview: View>: View {
    let title: String
    let isSelected: Bool
    let accessibilityHint: String
    let action: () -> Void
    let preview: Preview

    init(
        title: String,
        isSelected: Bool,
        accessibilityHint: String,
        action: @escaping () -> Void,
        @ViewBuilder preview: () -> Preview
    ) {
        self.title = title
        self.isSelected = isSelected
        self.accessibilityHint = accessibilityHint
        self.action = action
        self.preview = preview()
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                preview
                    .frame(height: 48)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 78)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .background(
                isSelected ? Color.accentColor.opacity(0.11) : Color.primary.opacity(0.025),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
        .help(accessibilityHint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct WorkspaceLayoutChoiceDiagram: View {
    let layout: WorkspaceLayout
    let orientation: WorkspaceLayoutOrientation

    var body: some View {
        GeometryReader { geometry in
            if orientation == .automatic, layout != .none {
                HStack(alignment: .center, spacing: 7) {
                    WorkspaceLayoutDiagramCanvas(layout: layout, orientation: .horizontal)
                        .frame(
                            width: geometry.size.width * 0.54,
                            height: geometry.size.height * 0.72
                        )
                    WorkspaceLayoutDiagramCanvas(layout: layout, orientation: .vertical)
                        .frame(
                            width: geometry.size.width * 0.24,
                            height: geometry.size.height * 0.92
                        )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                WorkspaceLayoutDiagramCanvas(
                    layout: layout,
                    orientation: orientation == .vertical ? .vertical : .horizontal
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct WorkspaceLayoutDiagramCanvas: View {
    let layout: WorkspaceLayout
    let orientation: WorkspaceLayoutOrientation

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(0.035))
                ForEach(Array(paneFrames(in: geometry.size).enumerated()), id: \.offset) { index, frame in
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.primary.opacity(index == 2 ? 0.14 : 0.09))
                        .overlay {
                            RoundedRectangle(cornerRadius: 2.5)
                                .stroke(Color.primary.opacity(0.34), lineWidth: 0.7)
                        }
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                }
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.primary.opacity(0.25), lineWidth: 0.7)
            }
        }
    }

    private func paneFrames(in size: CGSize) -> [CGRect] {
        let inset: CGFloat = 4
        let bounds = CGRect(
            x: inset,
            y: inset,
            width: max(1, size.width - inset * 2),
            height: max(1, size.height - inset * 2)
        )
        let gap: CGFloat = 3

        switch layout {
        case .none:
            return [
                CGRect(
                    x: bounds.minX,
                    y: bounds.minY + bounds.height * 0.06,
                    width: bounds.width * 0.58,
                    height: bounds.height * 0.62
                ),
                CGRect(
                    x: bounds.minX + bounds.width * 0.34,
                    y: bounds.minY + bounds.height * 0.34,
                    width: bounds.width * 0.62,
                    height: bounds.height * 0.62
                ),
                CGRect(
                    x: bounds.minX + bounds.width * 0.51,
                    y: bounds.minY,
                    width: bounds.width * 0.45,
                    height: bounds.height * 0.48
                ),
            ]
        case .tiled:
            if orientation == .vertical {
                let paneHeight = max(1, (bounds.height - gap * 2) / 3)
                return (0..<3).map { index in
                    CGRect(
                        x: bounds.minX,
                        y: bounds.minY + CGFloat(index) * (paneHeight + gap),
                        width: bounds.width,
                        height: paneHeight
                    )
                }
            }
            let paneWidth = max(1, (bounds.width - gap * 2) / 3)
            return (0..<3).map { index in
                CGRect(
                    x: bounds.minX + CGFloat(index) * (paneWidth + gap),
                    y: bounds.minY,
                    width: paneWidth,
                    height: bounds.height
                )
            }
        case .accordion:
            if orientation == .vertical {
                let paneHeight = bounds.height * 0.72
                let offset = (bounds.height - paneHeight) / 2
                return (0..<3).map { index in
                    CGRect(
                        x: bounds.minX,
                        y: bounds.minY + CGFloat(index) * offset,
                        width: bounds.width,
                        height: paneHeight
                    )
                }
            }
            let paneWidth = bounds.width * 0.72
            let offset = (bounds.width - paneWidth) / 2
            return (0..<3).map { index in
                CGRect(
                    x: bounds.minX + CGFloat(index) * offset,
                    y: bounds.minY,
                    width: paneWidth,
                    height: bounds.height
                )
            }
        }
    }
}

private struct WorkspaceLayoutMiniature: View {
    let kind: WorkspaceLayoutMiniatureKind

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.primary.opacity(0.035))
                miniature(in: geometry.size)
                    .padding(8)
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func miniature(in size: CGSize) -> some View {
        switch kind {
        case .freeform:
            ZStack {
                miniaturePane
                    .frame(width: size.width * 0.48, height: size.height * 0.48)
                    .offset(x: -size.width * 0.14, y: -size.height * 0.11)
                miniaturePane
                    .frame(width: size.width * 0.52, height: size.height * 0.45)
                    .offset(x: size.width * 0.13, y: size.height * 0.12)
                miniaturePane
                    .frame(width: size.width * 0.36, height: size.height * 0.34)
                    .offset(x: size.width * 0.18, y: -size.height * 0.17)
            }
        case .tiled:
            HStack(spacing: 3) {
                miniaturePane
                VStack(spacing: 3) {
                    miniaturePane
                    miniaturePane
                }
            }
        case .accordion:
            VStack(spacing: 3) {
                miniaturePane
                miniaturePane
                miniaturePane
            }
        }
    }

    private var miniaturePane: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.primary.opacity(0.1))
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.primary.opacity(0.24), lineWidth: 0.7)
            }
    }
}

private struct QuickAppShelfSettingsView: View {
    @ObservedObject var store: SettingsStore
    @State private var showsAppPicker = false

    var body: some View {
        Form {
            Section {
                Picker(
                    "Style",
                    selection: Binding(
                        get: { store.settingsQuickAppShelfPresentation.layoutStyle },
                        set: { style in
                            var presentation = store.settingsQuickAppShelfPresentation
                            presentation.layoutStyle = style
                            store.setSettingsQuickAppShelfPresentation(presentation)
                        }
                    )
                ) {
                    ForEach(QuickAppShelfPresentation.LayoutStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                Stepper(
                    value: Binding(
                        get: { store.settingsQuickAppShelfPresentation.visibleCount },
                        set: { count in
                            var presentation = store.settingsQuickAppShelfPresentation
                            presentation.visibleCount = count
                            store.setSettingsQuickAppShelfPresentation(presentation)
                        }
                    ),
                    in: 1...QuickAppShelfPolicy.maximumCount
                ) {
                    LabeledContent("Show at once") {
                        Text("\(store.settingsQuickAppShelfPresentation.visibleCount)")
                            .monospacedDigit()
                    }
                }

                Picker(
                    "Open from",
                    selection: Binding(
                        get: { store.settingsQuickAppShelfPresentation.direction },
                        set: { direction in
                            var presentation = store.settingsQuickAppShelfPresentation
                            presentation.direction = direction
                            store.setSettingsQuickAppShelfPresentation(presentation)
                        }
                    )
                ) {
                    ForEach(DropDownAppDirection.allCases) { direction in
                        Text(direction.title).tag(direction)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent(store.settingsQuickAppShelfPresentation.direction.sizeLabel) {
                    HStack(spacing: 10) {
                        Slider(
                            value: Binding(
                                get: { store.settingsQuickAppShelfPresentation.heightFraction },
                                set: { fraction in
                                    var presentation = store.settingsQuickAppShelfPresentation
                                    presentation.heightFraction = fraction
                                    store.setSettingsQuickAppShelfPresentation(presentation)
                                }
                            ),
                            in: DropDownAppConfiguration.minimumHeightFraction
                                ... DropDownAppConfiguration.maximumHeightFraction,
                            step: 0.05
                        )
                        .frame(minWidth: 180)
                        Text("\(Int((store.settingsQuickAppShelfPresentation.heightFraction * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                    }
                }

                Toggle(
                    "Animate opening and closing",
                    isOn: Binding(
                        get: { store.settingsQuickAppShelfPresentation.isAnimationEnabled },
                        set: { enabled in
                            var presentation = store.settingsQuickAppShelfPresentation
                            presentation.isAnimationEnabled = enabled
                            store.setSettingsQuickAppShelfPresentation(presentation)
                        }
                    )
                )

                if store.settingsQuickAppShelfPresentation.direction == .top {
                    Label(
                        "Top opens by resizing the window. Choose another edge if an app does not resize smoothly.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } header: {
                Text("Presentation")
            } footer: {
                Text("These settings apply to every app in the shelf for the \(store.settingsProfile.name) profile. The visible count is a maximum; WindowRanger does not launch other apps just to fill it.")
            }

            Section {
                if store.settingsQuickApps.isEmpty {
                    ContentUnavailableView(
                        "No Quick Apps",
                        systemImage: "rectangle.stack.badge.play",
                        description: Text("Add up to four apps, then arrange the order used when cycling the shelf.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else {
                    ForEach(Array(store.settingsQuickApps.enumerated()), id: \.element.bundleIdentifier) { index, app in
                        HStack(spacing: 12) {
                            Image(nsImage: appIcon(bundleIdentifier: app.bundleIdentifier))
                                .resizable()
                                .frame(width: 30, height: 30)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.displayName).fontWeight(.medium)
                                Text("Shelf position \(index + 1)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                store.moveSettingsQuickApps(from: IndexSet(integer: index), to: index - 1)
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .buttonStyle(.borderless)
                            .disabled(index == 0)
                            .help("Move \(app.displayName) up")

                            Button {
                                store.moveSettingsQuickApps(from: IndexSet(integer: index), to: index + 2)
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .buttonStyle(.borderless)
                            .disabled(index == store.settingsQuickApps.count - 1)
                            .help("Move \(app.displayName) down")

                            Button(role: .destructive) {
                                store.removeSettingsQuickApp(at: index)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove \(app.displayName) from the shelf")
                        }
                    }
                }

                Button {
                    showsAppPicker = true
                } label: {
                    Label("Add Quick App", systemImage: "plus")
                }
                .disabled(store.settingsQuickApps.count >= QuickAppShelfPolicy.maximumCount)
            } header: {
                HStack {
                    Text("Apps")
                    Spacer()
                    Text("\(store.settingsQuickApps.count) of \(QuickAppShelfPolicy.maximumCount)")
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            } footer: {
                Text("The regular shortcut toggles the most recently used app. Previous and Next Window follow this order while the shelf is open.")
            }

                Section("Global Shortcut") {
                    LabeledContent("Show or hide shelf") {
                        if let chord = store.hotKeyConfiguration.optionalChord(for: .toggleDropDownApp) {
                            ShortcutCaps(keys: chord.keyCaps)
                        } else {
                            Text("Not set").foregroundStyle(.secondary)
                        }
                    }
                    Text("This shortcut is shared by every profile. Change it in Shortcuts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showsAppPicker) {
            InstalledApplicationPicker(
                excludedBundleIdentifiers: Set(
                    store.settingsAppRules.map { $0.bundleIdentifier.lowercased() }
                        + store.settingsQuickApps.map { $0.bundleIdentifier.lowercased() }
                ).union(
                    RangerCompanionApplicationPolicy
                        .wholeApplicationVisibilityRestrictedBundleIdentifiers
                )
            ) { application in
                store.setSettingsQuickApp(application)
                showsAppPicker = false
            }
        }
    }

    private func appIcon(bundleIdentifier: String) -> NSImage {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)
            ?? NSImage()
    }
}

private enum ApplicationConfigurationMode: String, CaseIterable, Identifiable {
    case appRules
    case quickApp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appRules: "App Rules"
        case .quickApp: "Quick App"
        }
    }
}

private struct AppRulesSettingsView: View {
    @ObservedObject var store: SettingsStore
    let engine: WorkspaceEngine
    @Environment(\.undoManager) private var undoManager
    @State private var showsAppPicker = false
    @State private var selectedRuleID: AppRule.ID?
    @State private var showsCompactEditor = false
    @State private var pendingQuickAppRule: AppRule?

    var body: some View {
        GeometryReader { geometry in
            responsiveContent(for: SettingsDetailLayout.resolve(availableWidth: geometry.size.width))
        }
        .onAppear { reconcileSelection() }
        .onChange(of: store.settingsAppRules.map(\.id)) { _, _ in reconcileSelection() }
        .onChange(of: store.settingsProfileID) { _, _ in reconcileSelection() }
        .confirmationDialog(
            pendingQuickAppRule.map { "Add \($0.displayName) to Quick Apps?" }
                ?? "Add this application to Quick Apps?",
            isPresented: Binding(
                get: { pendingQuickAppRule != nil },
                set: { if !$0 { pendingQuickAppRule = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Add to Quick Apps", role: .destructive) {
                if let rule = pendingQuickAppRule {
                    store.convertSettingsAppRuleToQuickApp(bundleIdentifier: rule.bundleIdentifier)
                    selectedRuleID = rule.id
                }
                pendingQuickAppRule = nil
            }
            Button("Cancel", role: .cancel) { pendingQuickAppRule = nil }
        } message: {
            Text("Its saved workspace and window rules will be removed. Existing Quick Apps will stay in the shelf.")
        }
        .sheet(isPresented: $showsAppPicker) {
            InstalledApplicationPicker(
                excludedBundleIdentifiers: Set(
                    store.settingsAppRules.map { $0.bundleIdentifier.lowercased() }
                        + store.settingsQuickApps.map { $0.bundleIdentifier.lowercased() }
                )
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
                        title: selectedDisplayName ?? "Application",
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
                Text("Applications")
                    .font(.headline)
                Text("Choose workspace and layout rules for apps in \(store.settingsProfile.name).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if store.settingsAppRules.isEmpty {
                ContentUnavailableView {
                    Label("No Applications Yet", systemImage: "app.badge")
                } description: {
                    Text("Add an app to route its windows or change how it participates in layouts.")
                } actions: {
                    Button("Add Application") {
                        showsAppPicker = true
                    }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: Binding(
                    get: { selectedRuleID },
                    set: { selection in
                        selectedRuleID = selection
                        if showsDisclosure, selection != nil { showsCompactEditor = true }
                    }
                )) {
                    ForEach(store.settingsAppRules) { rule in
                        ruleListRow(rule, showsDisclosure: showsDisclosure)
                            .tag(rule.id)
                            .onTapGesture {
                                selectedRuleID = rule.id
                                if showsDisclosure { showsCompactEditor = true }
                            }
                            .contextMenu {
                                Button("Add to Quick Apps…") {
                                    pendingQuickAppRule = rule
                                }
                                Divider()
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
                Button {
                    showsAppPicker = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Add an application rule")
                .accessibilityLabel("Add application rule")

                SettingsMasterActionButton(systemImage: "trash", role: .destructive) {
                    removeSelectedRule()
                }
                .disabled(selectedRuleID == nil)
                .help("Remove selected application configuration")
                .accessibilityLabel("Remove selected application configuration")

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

            Label(
                store.iCloudSyncEnabled
                    ? "\(store.settingsProfile.name) profile · iCloud sync"
                    : "\(store.settingsProfile.name) profile",
                systemImage: "person.crop.circle"
            )
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
                rule: Binding(
                    get: { store.settingsAppRules.first(where: { $0.id == rule.id }) ?? rule },
                    set: { store.updateSettingsAppRule($0, undoManager: undoManager) }
                ),
                workspaces: store.settingsWorkspaces,
                makeQuickApp: { pendingQuickAppRule = rule }
            )
            .id(rule.id)
        } else {
            ContentUnavailableView(
                "No Application Selected",
                systemImage: "app.badge",
                description: Text("Add or select an application to configure it.")
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
                Text("App Rules · \(ruleSummary(rule))")
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
        selectedRuleID.flatMap { id in store.settingsAppRules.first { $0.id == id } }
    }

    private var selectedDisplayName: String? {
        selectedRule?.displayName
    }

    private func reconcileSelection() {
        if let selectedRuleID,
           store.settingsAppRules.contains(where: { $0.id == selectedRuleID }) {
            return
        }
        selectedRuleID = store.settingsAppRules.first?.id
    }

    private func removeSelectedRule() {
        guard let selectedRule else { return }
        let ids = store.settingsAppRules.map(\.id)
        let index = ids.firstIndex(of: selectedRule.id) ?? 0
        let nextID: AppRule.ID? = if ids.count <= 1 {
            nil
        } else if index < ids.count - 1 {
            ids[index + 1]
        } else {
            ids[index - 1]
        }
        store.removeSettingsAppRule(bundleIdentifier: selectedRule.bundleIdentifier)
        selectedRuleID = nextID
        if selectedRuleID == nil { showsCompactEditor = false }
    }

    private func addRule(for application: InstalledApplication) {
        guard store.isEditingActiveProfile, application.isRunning else {
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
        store.addSettingsAppRule(for: application, defaultWorkspaceID: defaultWorkspaceID)
        selectedRuleID = application.bundleIdentifier.lowercased()
        showsCompactEditor = true
        showsAppPicker = false
    }

    private func ruleSummary(_ rule: AppRule) -> String {
        if !rule.isEnabled { return "Rule paused" }
        if rule.keepsOnAllWorkspaces { return "All workspaces" }
        if let id = rule.assignedWorkspaceID,
           let workspace = store.settingsWorkspaces.first(where: { $0.id == id }) {
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
    @Binding var rule: AppRule
    let workspaces: [WorkspaceDefinition]
    let makeQuickApp: () -> Void

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
                LabeledContent("Mode") {
                    Picker(
                        "Mode",
                        selection: Binding(
                            get: { ApplicationConfigurationMode.appRules },
                            set: { mode in
                                if mode == .quickApp { makeQuickApp() }
                            }
                        )
                    ) {
                        ForEach(ApplicationConfigurationMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)
                }
                Text("App Rules automatically control this application's workspace and window behavior.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        Button {
            select(application)
            dismiss()
        } label: {
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

private struct ShortcutGuideSettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section("Shortcut Guide") {
                Toggle("Show while shortcut modifiers are held", isOn: $store.shortcutGuideEnabled)
                Text("Hold either configured Navigate or Arrange modifier family to see the matching actions. Releasing a modifier hides the guide without changing focus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let issue = store.shortcutGuideRuntimeIssue {
                    Label(issue, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Appearance") {
                LabeledContent("Size") {
                    Picker("Size", selection: $store.shortcutGuideSize) {
                        ForEach(ShortcutGuideSize.allCases) { size in
                            Text(size.title).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                LabeledContent("Position") {
                    Picker("Position", selection: $store.shortcutGuidePosition) {
                        ForEach(ShortcutGuidePosition.allCases) { position in
                            Text(position.title).tag(position)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Text("The guide follows the interaction display used by the focused window and stays within that screen's usable area. These preferences stay on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("What Appears") {
                Label("Workspace keys and names from the active profile", systemImage: "square.grid.3x3")
                Label("Only conflict-free shortcuts using the held modifier family", systemImage: "checkmark.circle")
                Text("Numbered workspaces use the same key-map layout as lettered workspaces. Unavailable or conflicting actions are left out rather than shown disabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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

    private var navigateActions: [ConfigurableHotKeyAction] {
        ConfigurableHotKeyAction.allCases.filter { $0.family == .navigate }
    }

    private var arrangeActions: [ConfigurableHotKeyAction] {
        ConfigurableHotKeyAction.allCases.filter { $0.family == .arrange }
    }

    private let shortcutFamilyModifierChoices: [UInt32] = [
        UInt32(controlKey | optionKey), UInt32(controlKey | cmdKey), UInt32(optionKey | cmdKey),
        UInt32(controlKey | shiftKey), UInt32(optionKey | shiftKey), UInt32(cmdKey | shiftKey),
        UInt32(controlKey | optionKey | shiftKey), UInt32(controlKey | optionKey | cmdKey),
        UInt32(controlKey | cmdKey | shiftKey), UInt32(optionKey | cmdKey | shiftKey),
        UInt32(controlKey | optionKey | cmdKey | shiftKey),
    ]

    var body: some View {
        Form {
            Section("Shortcut Families") {
                Text("Choose the two prefixes once. Each command and workspace then owns only its key suffix.")
                    .foregroundStyle(.secondary)
                ForEach(ShortcutFamily.allCases) { family in
                    LabeledContent(family.title) {
                        HStack(spacing: 8) {
                            Menu(HotKeyChord(keyCode: 0, modifiers: store.hotKeyConfiguration.modifierMask(for: family)).keyCaps.dropLast().joined(separator: " ")) {
                                ForEach(shortcutFamilyModifierChoices, id: \.self) { modifiers in
                                    Button(HotKeyChord(keyCode: 0, modifiers: modifiers).keyCaps.dropLast().joined(separator: " ")) {
                                        if let message = store.setShortcutFamilyModifiers(modifiers, for: family) {
                                            conflictMessage = message
                                            NSSound.beep()
                                        } else {
                                            conflictMessage = nil
                                        }
                                    }
                                }
                            }
                            Button { conflictMessage = store.resetShortcutFamilyModifiers(family) } label: {
                                Image(systemName: "arrow.counterclockwise")
                            }
                            .disabled(store.hotKeyConfiguration.modifierMask(for: family) == family.defaultModifiers)
                        }
                    }
                }
                Text("Families must be distinct and neither can be a subset of the other.")
                    .font(.caption)
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

            Section("Navigate") {
                ForEach(navigateActions) { action in shortcutRow(action) }
            }

            Section("Arrange") {
                ForEach(arrangeActions) { action in shortcutRow(action) }
                LabeledContent("Select Freeform", value: "Command Palette or Layout selector")
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
                    conflictMessage = store.resetAllShortcuts()
                }
                Text("Escape cancels recording. Press a key to assign its suffix, or use Unassign for palette-only access.")
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
        let chord = store.hotKeyConfiguration.optionalChord(for: action)
        return LabeledContent {
            HStack(spacing: 8) {
                Button {
                    beginRecording(action)
                } label: {
                    if recordingAction == action {
                        Text("Press shortcut…")
                            .frame(minWidth: 110)
                    } else if let chord {
                        ShortcutCaps(keys: chord.keyCaps)
                            .frame(minWidth: 110)
                    } else {
                        Text("Not set")
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 110)
                    }
                }
                .buttonStyle(.bordered)
                .help("Record a new global shortcut for \(action.title)")

                Button {
                    if recordingAction == action { finishRecording() }
                    conflictMessage = store.resetShortcut(action)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .disabled(!store.hotKeyConfiguration.hasExplicitKeyAssignment(for: action))
                .help("Reset \(action.title)")
                .accessibilityLabel("Reset \(action.title)")

                Button("Unassign") {
                    if recordingAction == action { finishRecording() }
                    conflictMessage = store.setShortcutKey(nil, for: action)
                }
                .disabled(chord == nil)
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
            guard !ShortcutConflictModel.modifierOnlyKeyCodes.contains(UInt32(event.keyCode)) else {
                conflictMessage = "Press a supported non-modifier key."
                NSSound.beep()
                return nil
            }
            guard let recordingAction else { return event }
            if let conflict = store.setShortcutKey(UInt32(event.keyCode), for: recordingAction) {
                conflictMessage = conflict
                NSSound.beep()
                return nil
            }
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

    private var paletteChord: HotKeyChord? {
        store.hotKeyConfiguration.optionalChord(for: .commandWheel)
    }

    private var runtimeIssue: HotKeyRuntimeIssue? {
        store.hotKeyRuntimeIssues.first { $0.owner.configurableAction == .commandWheel }
    }

    var body: some View {
        Form {
            Section("Activation") {
                Toggle("Enable Command Palette", isOn: $store.radialMenuEnabled)
                LabeledContent("Global shortcut") {
                    if let paletteChord {
                        ShortcutCaps(keys: paletteChord.keyCaps)
                            .frame(minWidth: 120)
                    } else {
                        Text("Not set")
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 120)
                    }
                }
                .disabled(!store.radialMenuEnabled)
                if let runtimeIssue {
                    Label(runtimeIssue.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Shortcut registration failed. \(runtimeIssue.message)")
                }
                Text("Change the Navigate family or Command Palette suffix in Shortcuts. Press it to open the searchable palette; type to filter, use arrows to select, Return to run, and Escape to close.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Position") {
                Picker("Position", selection: $store.commandPalettePosition) {
                    ForEach(CommandPalettePosition.allCases) { position in
                        Text(position.title).tag(position)
                    }
                }
                Text("Choose where the palette opens on the interaction display. This setting stays on this Mac and does not change profiles or iCloud content.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
        .accessibilityLabel("Radial menu preview")
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
                            Text("Modal \(record.modalObservation) · focused \(record.focusedObservation) · main \(record.mainObservation) · controls F/M/C/Z/D/Ca \(record.fullscreenButton)/\(record.minimizeButton)/\(record.closeButton)/\(record.zoomButton)/\(record.defaultButton)/\(record.cancelButton) · native file panel \(record.nativeFilePanelIdentifierObservation) · move \(record.positionSettable) · resize \(record.sizeSettable)")
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
