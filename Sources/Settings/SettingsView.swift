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
    let shortcutRecordingStateChanged: (Bool) -> Void
    let onboardingRestartRequested: () -> Void

    init(
        store: SettingsStore,
        engine: WorkspaceEngine,
        navigation: SettingsNavigationModel,
        windowCoordinator: SettingsWindowCoordinator,
        diagnostics: DiagnosticLogger,
        updateController: UpdateController,
        shortcutRecordingStateChanged: @escaping (Bool) -> Void,
        onboardingRestartRequested: @escaping () -> Void = {}
    ) {
        self.store = store
        self.engine = engine
        self.navigation = navigation
        self.windowCoordinator = windowCoordinator
        self.diagnostics = diagnostics
        self.updateController = updateController
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
                            sidebarRow(.profileSwitching)
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
                        category: navigation.selectedCategory,
                        onboardingRestartRequested: onboardingRestartRequested
                    )
                case .updates:
                    UpdateSettingsView(updateController: updateController)
                case .profiles:
                    ProfilesSettingsView(store: store)
                case .profileSwitching:
                    ProfileSwitchingSettingsView(store: store)
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
}

private struct GeneralSettingsView: View {
    @ObservedObject var store: SettingsStore
    let engine: WorkspaceEngine
    let category: SettingsCategory
    let onboardingRestartRequested: () -> Void
    @Environment(\.undoManager) private var undoManager
    @StateObject private var accessibilityPermission = AccessibilityPermissionMonitor()
    @StateObject private var launchAtLogin = LaunchAtLoginController()
    @State private var showsFocusBorderAppPicker = false

    private var iCloudSyncStatusTitle: String {
        guard store.iCloudSyncEnabled else { return "Off" }
        return store.iCloudProfileLibraryIssue == nil ? "On" : "Needs Attention"
    }

    private var iCloudSyncStatusColor: Color {
        guard store.iCloudSyncEnabled else { return .secondary }
        return store.iCloudProfileLibraryIssue == nil ? .green : .orange
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
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard category == .general else { return }
            accessibilityPermission.refresh()
            launchAtLogin.refresh()
        }
        .task(id: accessibilityPermission.isGranted) {
            guard category == .general else { return }
            guard !accessibilityPermission.isGranted else { return }
            while !Task.isCancelled, !accessibilityPermission.isGranted {
                do {
                    try await Task.sleep(
                        nanoseconds: AccessibilityPermissionMonitor
                            .missingPermissionRefreshIntervalNanoseconds
                    )
                } catch {
                    return
                }
                accessibilityPermission.refresh()
            }
        }
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

private struct ProfilesSettingsView: View {
    @ObservedObject var store: SettingsStore
    @Environment(\.undoManager) private var undoManager
    @StateObject private var transferCoordinator: ProfileTransferCoordinator
    @State private var pendingProfileDeletion: UUID?
    @State private var pendingProfileImport: ProfileImportPlan?
    @State private var transferNotice: ProfileTransferNotice?
    @State private var isCreatingProfile = false
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
    private func responsiveContent(for layout: SettingsDetailLayout) -> some View {
        switch layout {
        case .wide:
            HStack(spacing: 0) {
                profileListColumn()
                    .frame(width: SettingsWindowMetrics.masterListWidth)
                    .frame(maxHeight: .infinity)
                Divider()
                profileStatusForm
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .compact:
            VStack(spacing: 0) {
                if showsCompactDetails {
                    SettingsCompactDetailHeader(
                        backTitle: "Profiles",
                        title: store.settingsProfile.name,
                        goBack: { showsCompactDetails = false }
                    )
                    Divider()
                    profileStatusForm
                } else {
                    profileListColumn(showsDisclosure: true)
                }
            }
        }
    }

    private func profileListColumn(showsDisclosure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Profile Library")
                    .font(.headline)
                Text("Reusable configurations that can sync or be exported.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            List(selection: Binding(
                get: { Optional(store.settingsProfileID) },
                set: { profileID in
                    if let profileID {
                        if profileID != store.settingsProfileID {
                            store.selectProfileForEditing(profileID)
                        }
                        if showsDisclosure { showsCompactDetails = true }
                    }
                }
            )) {
                ForEach(store.profiles) { profile in
                    profileListRow(profile, showsDisclosure: showsDisclosure)
                        .tag(profile.id)
                        .onTapGesture {
                            if profile.id != store.settingsProfileID {
                                store.selectProfileForEditing(profile.id)
                            }
                            if showsDisclosure { showsCompactDetails = true }
                        }
                        .contextMenu {
                            Button("Use Profile") {
                                store.selectProfileForEditing(profile.id)
                                store.activateSettingsProfile()
                            }
                                .disabled(profile.id == store.activeProfileID)
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

                SettingsMasterActionButton(systemImage: "trash", role: .destructive) {
                    pendingProfileDeletion = store.settingsProfileID
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
                title: "Import or export library",
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

    private var profileStatusForm: some View {
        Form {
            Section("Profile Status") {
                ProfileIdentityEditor(store: store)
                LabeledContent("Active on this Mac", value: store.activeProfile.name)
                LabeledContent("Selection mode", value: store.activeProfileSelectionReason.title)
                if !store.isEditingActiveProfile {
                    Button("Use \(store.settingsProfile.name)", systemImage: "checkmark.circle") {
                        store.activateSettingsProfile()
                    }
                    Text("Selecting a profile in the library only chooses what to edit. Use Profile changes the desktop to that profile and pins it on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Set local automatic selection rules in Profile Switching. Configure this profile's displays, workspaces, applications, and shelf in their own sections.")
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
            Image(systemName: profile.iconStyle.systemImage)
                .frame(width: 18)
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
            if profile.id == store.activeProfileID {
                Text("Active")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                    .accessibilityHidden(true)
            }
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
            : profile.id == store.activeProfileID ? "Active profile; selects it for editing" : "Selects this profile for editing")
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
        let quickAppCount = profile.quickApps.count
        let quickAppLabel: String = if quickAppCount == 0 {
            ""
        } else {
            " · \(quickAppCount) Quick App\(quickAppCount == 1 ? "" : "s")"
        }
        return "\(profile.workspaces.count) \(workspaceLabel) · "
            + "\(profile.displayRoles.count) \(roleLabel) · "
            + "\(profile.appRules.count) \(ruleLabel)"
            + quickAppLabel
    }

}

private struct ProfileSwitchingSettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section("Active on This Mac") {
                LabeledContent("Active profile", value: store.activeProfile.name)
                LabeledContent("Selection mode", value: store.activeProfileSelectionReason.title)
                if store.manualPinnedProfileID != nil {
                    Button("Resume Automatic", systemImage: "arrow.triangle.2.circlepath") {
                        store.resumeAutomaticProfileSelection()
                    }
                    Text("The active profile remains pinned on this Mac until automatic selection resumes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Automatic selection uses exact display setups, dock state, then this Mac's default profile.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Automatic Selection on This Mac") {
                profilePicker("Default profile", selection: Binding(
                    get: { Optional(store.defaultProfileID) },
                    set: { if let id = $0 { store.setDefaultProfile(id) } }
                ), permitsNone: false)
                profilePicker("During Game Mode", selection: Binding(
                    get: { store.gameModeProfileID },
                    set: { store.setGameModeProfile($0) }
                ))
                Text("Uses this profile while a foreground full-screen game that explicitly supports macOS Game Mode is active. Game Mode takes priority over display rules, but not a manually selected profile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                profilePicker("When docked", selection: Binding(
                    get: { store.dockedProfileID },
                    set: { store.setDockedProfile($0) }
                ))
                profilePicker("When undocked", selection: Binding(
                    get: { store.undockedProfileID },
                    set: { store.setUndockedProfile($0) }
                ))
                Text("Dock rules apply to portable Macs. Desktop Macs fall through to an exact display setup or the local default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()
                HStack {
                    Text("Exact display setups").font(.headline)
                    Spacer()
                    Button("Map to Active Profile", systemImage: "display.2") {
                        _ = store.addExactTriggerForCurrentDisplays(profileID: store.activeProfileID)
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
                            Button(role: .destructive) { store.removeExactTrigger(trigger.id) } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                Text("Automatic selection rules and the active profile are local to this Mac. Viewing this section never changes the profile being edited elsewhere in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func profilePicker(
        _ title: String,
        selection: Binding<UUID?>,
        permitsNone: Bool = true
    ) -> some View {
        Picker(title, selection: selection) {
            if permitsNone { Text("Not assigned").tag(nil as UUID?) }
            ForEach(store.profiles) { profile in Text(profile.name).tag(Optional(profile.id)) }
        }
    }
}

private struct DisplaysSettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
                Section("Workspace Behavior") {
                    Picker("Display workspace behavior", selection: Binding(
                        get: { store.settingsMultiDisplayMode },
                        set: { store.setSettingsMultiDisplayMode($0) }
                    )) {
                        ForEach(MultiDisplayMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Display workspace behavior")
                    Text(displayModeExplanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Display Roles in \(store.settingsProfile.name)") {
                    ForEach(store.settingsProfile.displayRoles) { role in
                        profileDisplayRoleDefinition(role)
                    }
                    HStack {
                        Spacer()
                        Button("Add Display Role", systemImage: "plus") {
                            _ = store.addSettingsDisplayRole()
                        }
                    }
                    Text("Role names belong to this reusable profile and sync when iCloud is enabled. Choose each role's menu-bar icon in Menu Bar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Display Bindings on This Mac") {
                    ForEach(store.settingsProfile.displayRoles) { role in
                        localDisplayBinding(role)
                    }
                    Text("Physical monitor identities stay on this Mac. A missing or ambiguous display falls back safely without changing the selected profile's synced role.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
        }
        .formStyle(.grouped)
    }

    private var displayModeExplanation: String {
        store.settingsMultiDisplayMode == .unified
            ? "One active workspace is shared by every display; windows keep their display affinity."
            : "Each display has its own active workspace and each workspace has a Home Display."
    }

    private func profileDisplayRoleDefinition(_ role: ProfileDisplayRole) -> some View {
        LabeledContent("Role name") {
            HStack(spacing: 8) {
                Spacer()
                TextField("Role name", text: Binding(
                    get: { store.settingsProfile.displayRoles.first(where: { $0.id == role.id })?.name ?? role.name },
                    set: { store.renameSettingsDisplayRole(role.id, to: $0) }
                ))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 220)
                .accessibilityLabel("Role name for \(role.name)")
                Button(role: .destructive) { _ = store.deleteSettingsDisplayRole(role.id) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .frame(width: 20)
                .disabled(store.settingsProfile.displayRoles.count == 1)
                .accessibilityLabel("Delete \(role.name) role")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func localDisplayBinding(_ role: ProfileDisplayRole) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent(role.name) {
                Picker("This Mac's display", selection: Binding<String?>(
                    get: { store.roleBindings[role.id]?.lastKnownIdentifier },
                    set: { store.bindSettingsDisplayRole(role.id, to: $0) }
                )) {
                    Text("Unbound — safe main-display fallback").tag(nil as String?)
                    ForEach(roleDisplayOptions(role.id)) { display in
                        Text(display.name).tag(Optional(display.identifier))
                    }
                }
                .labelsHidden()
                .frame(width: 240, alignment: .trailing)
            }
            if let note = roleBindingNote(role.id) {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
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

private struct ProfileIdentityEditor: View {
    @ObservedObject var store: SettingsStore
    @State private var draftName: String
    @State private var draftProfileID: UUID
    @FocusState private var isNameFocused: Bool

    init(store: SettingsStore) {
        self.store = store
        _draftName = State(initialValue: store.settingsProfile.name)
        _draftProfileID = State(initialValue: store.settingsProfileID)
    }

    var body: some View {
        Group {
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

            TextField("Name", text: $draftName)
                .focused($isNameFocused)
                .onSubmit { commitDraftName() }
                .help("Rename the profile being edited.")
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
        .onChange(of: store.settingsWorkspaces.map(\.id)) { _, _ in reconcileSelection() }
        .onChange(of: store.settingsProfileID) { _, _ in reconcileSelection() }
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
                ForEach(store.settingsWorkspaces) { workspace in
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
                            store.moveSettingsWorkspace(id: source, before: workspace.id)
                            return true
                        }
                        .contextMenu { workspaceContextMenu(workspace) }
                        .accessibilityAction(named: "Move up") {
                            store.moveSettingsWorkspace(id: workspace.id, offset: -1)
                        }
                        .accessibilityAction(named: "Move down") {
                            store.moveSettingsWorkspace(id: workspace.id, offset: 1)
                        }
                }
                .onMove(perform: store.moveSettingsWorkspaces)
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
                    selectedWorkspaceID = store.addSettingsWorkspace()
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
                .disabled(store.settingsWorkspaces.count <= 1 || selectedWorkspace == nil)
                .help("Delete selected workspace")
                .accessibilityLabel("Delete selected workspace")

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, SettingsWindowMetrics.masterActionRowVerticalPadding)

            Divider()

            VStack(spacing: 12) {
                if store.isEditingActiveProfile {
                    SettingsActionRow(
                        title: "Active workspace",
                        description: "Recover the interaction display's active workspace, clear transient positioning, and reapply its current layout."
                    ) {
                        Button("Bring Windows Back On Screen") {
                            engine.resetCurrentWorkspace()
                        }
                    }

                    Divider()
                }

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
                    ForEach(store.settingsProfile.displayRoles) { role in
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
                    if let keyCode = HotKeyManager.keyCodes[workspace.key.lowercased()] {
                        WorkspaceShortcutCaps(keys: store.hotKeyConfiguration
                            .chord(forWorkspaceKeyCode: keyCode, family: .navigate)
                            .keyCaps)
                    } else {
                        Text("Not set").foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Move Window to \(workspace.name)") {
                    if let keyCode = HotKeyManager.keyCodes[workspace.key.lowercased()] {
                        WorkspaceShortcutCaps(keys: store.hotKeyConfiguration
                            .chord(forWorkspaceKeyCode: keyCode, family: .arrange)
                            .keyCaps)
                    } else {
                        Text("Not set").foregroundStyle(.secondary)
                    }
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

                LabeledContent("Copy Layout") {
                    Menu("Choose Workspace…") {
                        ForEach(store.settingsWorkspaces.filter { $0.id != workspace.id }) { source in
                            Button {
                                store.copySettingsLayout(
                                    from: source.id,
                                    to: workspace.id,
                                    undoManager: undoManager
                                )
                            } label: {
                                Label(
                                    "\(source.name) — \(source.layout.title)",
                                    systemImage: source.layout.systemImage
                                )
                            }
                        }
                    }
                    .disabled(store.settingsWorkspaces.count <= 1)
                    .help("Copy another workspace's layout style and geometry")
                }
                Text(
                    "Copies the layout style, orientation, gaps and padding from another workspace. "
                        + "Its name, key, Home Display, app rules and window membership stay unchanged."
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if store.settingsUsesLegacyLayoutGeometry(for: workspace.id), workspace.layout != .none {
                    Label(
                        "This workspace is preserving its pre-upgrade geometry.",
                        systemImage: "clock.arrow.circlepath"
                    )
                    .foregroundStyle(.secondary)
                    Button("Use Current Layout Defaults") {
                        store.setSettingsLayoutConfiguration(
                            .aeroSpaceUserDefaults,
                            for: workspace.id
                        )
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
                        store.resetSettingsWorkspace(workspace.id, undoManager: undoManager)
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
            if let keyCode = HotKeyManager.keyCodes[workspace.key.lowercased()] {
                Text(store.hotKeyConfiguration
                    .chord(forWorkspaceKeyCode: keyCode, family: .navigate)
                    .title)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
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
        Button("Move Up") { store.moveSettingsWorkspace(id: workspace.id, offset: -1) }
            .disabled(store.settingsWorkspaces.first?.id == workspace.id)
        Button("Move Down") { store.moveSettingsWorkspace(id: workspace.id, offset: 1) }
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

    private func gapBinding(
        _ keyPath: WritableKeyPath<WorkspaceLayoutGaps, Double>,
        workspaceID: UUID
    ) -> Binding<Double> {
        Binding(
            get: { configuration(for: workspaceID).gaps[keyPath: keyPath] },
            set: { newValue in
                var updated = configuration(for: workspaceID)
                updated.gaps[keyPath: keyPath] = newValue
                store.setSettingsLayoutConfiguration(updated, for: workspaceID)
            }
        )
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
