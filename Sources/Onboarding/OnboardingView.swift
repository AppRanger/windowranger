import AppKit
import Carbon
import SwiftUI

struct OnboardingWizardView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @ObservedObject private var store: SettingsStore
    @StateObject private var accessibilityPermission = AccessibilityPermissionMonitor()
    @State private var showsApplicationPicker = false
    @State private var showsICloudReplacementConfirmation = false

    init(coordinator: OnboardingCoordinator) {
        self.coordinator = coordinator
        store = coordinator.settingsStore
    }

    var body: some View {
        ZStack {
            Color(nsColor: NSColor(srgbRed: 0.075, green: 0.085, blue: 0.11, alpha: 1))
            LinearGradient(
                colors: [Color.blue.opacity(0.12), .clear, Color.orange.opacity(0.035)],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )

            VStack(spacing: 0) {
                header
                Divider().overlay(.white.opacity(0.08))
                HStack(spacing: 0) {
                    ScrollView {
                        stepContent
                            .padding(.horizontal, 34)
                            .padding(.vertical, 28)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(width: 480)

                    Divider().overlay(.white.opacity(0.08))

                    artworkColumn
                }
                Divider().overlay(.white.opacity(0.08))
                footer
            }
        }
        .frame(width: OnboardingWindowConfiguration.contentSize.width,
               height: OnboardingWindowConfiguration.contentSize.height)
        .preferredColorScheme(.dark)
        .tint(.blue)
        .sheet(isPresented: $showsApplicationPicker) {
            OnboardingApplicationPicker(
                excludedBundleIdentifiers: Set(store.settingsQuickApps.map {
                    $0.bundleIdentifier.lowercased()
                })
            ) { application in
                coordinator.addQuickApp(application)
            }
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
        .onAppear {
            accessibilityPermission.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            accessibilityPermission.refresh()
        }
        .task(id: accessibilityPermission.isGranted) {
            await accessibilityPermission.refreshUntilGranted()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.blue.opacity(0.18))
                Image(systemName: coordinator.step.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.blue)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(coordinator.step.title)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("Step \(coordinator.stepNumber) of \(OnboardingStep.allCases.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("WindowRanger Setup")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 26)
        .frame(height: 72)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch coordinator.step {
        case .welcome: welcomeStep
        case .iCloud: iCloudStep
        case .shortcuts: shortcutsStep
        case .focusBorder: focusBorderStep
        case .menuBar: menuBarStep
        case .quickAppShelf: quickAppShelfStep
        case .workspaces: workspacesStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepHeading(
                "Welcome to WindowRanger",
                detail: "A faster, calmer way to move through windows and workspaces. Let's set up the parts you'll use every day."
            )

            onboardingBand(accent: .blue) {
                HStack(spacing: 12) {
                    Image(systemName: accessibilityPermission.isGranted
                          ? "checkmark.shield.fill" : "hand.raised.fill")
                        .font(.title2)
                        .foregroundStyle(accessibilityPermission.isGranted ? .green : .orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Accessibility Access").font(.headline)
                        Text(accessibilityPermission.isGranted
                             ? "Ready to discover, focus, move and resize windows."
                             : "Required so WindowRanger can manage your windows.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if !accessibilityPermission.isGranted {
                    Button("Grant Access") {
                        _ = AccessibilityWindow.requestPermission()
                        accessibilityPermission.refresh()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Label("Seven short steps; every choice can be changed later in Settings.",
                  systemImage: "clock")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var iCloudStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepHeading(
                "Keep your setup in sync",
                detail: "iCloud can carry reusable profiles and global preferences to your other Macs. Machine-specific permissions and input monitors stay local."
            )

            onboardingBand(accent: .blue) {
                Toggle(isOn: Binding(
                    get: { store.iCloudSyncEnabled },
                    set: coordinator.setICloudSyncEnabled
                )) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Sync settings with iCloud").font(.headline)
                            Text("Off by default. Your local setup is kept either way.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                    }
                }
                .toggleStyle(.switch)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }

            if store.iCloudSyncState == .disabled,
               store.iCloudProfileLibraryIssue?.source != .local {
                Button("Replace iCloud with This Mac’s Settings…") {
                    showsICloudReplacementConfirmation = true
                }
            } else if store.iCloudSyncState == .waitingForCloud {
                Label(
                    "Waiting for existing iCloud settings. Nothing from this Mac will be uploaded while WindowRanger waits.",
                    systemImage: "icloud.and.arrow.down"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                Button("Use This Mac’s Settings in iCloud…") {
                    showsICloudReplacementConfirmation = true
                }
            } else if let issue = store.iCloudProfileLibraryIssue {
                Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                if issue.canReplaceCloudCopy {
                    Button("Use This Mac’s Settings in iCloud…") {
                        showsICloudReplacementConfirmation = true
                    }
                }
            } else {
                Label(store.iCloudSyncEnabled ? "iCloud sync is on" : "This Mac will stay local-only",
                      systemImage: store.iCloudSyncEnabled ? "checkmark.icloud.fill" : "macbook")
                    .foregroundStyle(store.iCloudSyncEnabled ? .green : .secondary)
            }
        }
    }

    private var shortcutsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeading(
                "Set up your shortcuts",
                detail: "Two modifier families are the foundation of WindowRanger. Workspace numbers and command keys are added after them."
            )

            shortcutFamilyBand(
                family: .navigate,
                color: .blue,
                detail: "Move between workspaces and focused windows."
            )
            shortcutFamilyBand(
                family: .arrange,
                color: .orange,
                detail: "Send and arrange the focused window."
            )

            HStack(spacing: 10) {
                shortcutExample(family: .navigate, key: "2", label: "Go to workspace 2", color: .blue)
                Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                shortcutExample(family: .arrange, key: "2", label: "Send window to 2", color: .orange)
            }

            if let message = coordinator.shortcutConflictMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var focusBorderStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepHeading(
                "Never lose the focused window",
                detail: "Focus Border draws a subtle outline around the window that will receive your next command. The preview updates as you choose."
            )

            onboardingBand(accent: store.focusedWindowHighlightColor.color) {
                Toggle(isOn: Binding(
                    get: { store.focusedWindowHighlightEnabled },
                    set: coordinator.setFocusBorderEnabled
                )) {
                    HStack {
                        Text("Show Focus Border").font(.headline)
                        Spacer(minLength: 12)
                    }
                }
                .toggleStyle(.switch)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())

                HStack {
                    Text("Border colour")
                    Spacer()
                    ColorPicker("Border colour", selection: Binding(
                        get: { store.focusedWindowHighlightColor.color },
                        set: { color in
                            let resolved = MenuBarHighlightColor(nsColor: NSColor(color))
                                ?? .focusBorderDefault
                            coordinator.setFocusBorderColor(resolved)
                        }
                    ), supportsOpacity: false)
                    .labelsHidden()
                }
                .disabled(!store.focusedWindowHighlightEnabled)
            }

            FocusBorderMiniPreview(
                enabled: store.focusedWindowHighlightEnabled,
                color: store.focusedWindowHighlightColor.color
            )
        }
    }

    private var menuBarStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeading(
                "Choose your menu-bar view",
                detail: "Use a tiny signal, a readable current-workspace chip, or the complete workspace strip."
            )

            ForEach(MenuBarPresentationMode.allCases) { mode in
                Button {
                    coordinator.setMenuBarPresentation(mode)
                } label: {
                    HStack(spacing: 14) {
                        MenuBarModePreview(mode: mode)
                            .frame(width: 150, height: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.title).font(.headline)
                            Text(menuBarShortExplanation(mode))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: store.menuBarPresentationMode == mode
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(store.menuBarPresentationMode == mode ? .blue : .secondary)
                    }
                    .padding(12)
                    .contentShape(Rectangle())
                    .background(.white.opacity(store.menuBarPresentationMode == mode ? 0.08 : 0.035),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(store.menuBarPresentationMode == mode
                                    ? Color.blue.opacity(0.7) : Color.white.opacity(0.08))
                            .allowsHitTesting(false)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var quickAppShelfStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeading(
                "Put important apps on the Shelf",
                detail: "Access the apps you need faster from any workspace—like your terminal, notes, or calendar. Choose up to four in the order you want them to appear."
            )

            if store.settingsQuickApps.isEmpty {
                onboardingBand(accent: .blue) {
                    Label("No apps selected yet", systemImage: "square.stack.3d.up.slash")
                        .font(.headline)
                    Text("The Shelf stays out of your way until you add an app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(store.settingsQuickApps.enumerated()), id: \.element.bundleIdentifier) { index, app in
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.monospacedDigit().bold())
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            applicationIcon(bundleIdentifier: app.bundleIdentifier)
                            Text(app.displayName).lineLimit(1)
                            Spacer()
                            Button {
                                coordinator.moveQuickApps(
                                    from: IndexSet(integer: index),
                                    to: index - 1
                                )
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .disabled(index == 0)
                            .help("Move \(app.displayName) up")

                            Button {
                                coordinator.moveQuickApps(
                                    from: IndexSet(integer: index),
                                    to: index + 2
                                )
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .disabled(index == store.settingsQuickApps.count - 1)
                            .help("Move \(app.displayName) down")

                            Button {
                                coordinator.removeQuickApp(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Remove \(app.displayName)")
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 42)
                        .background(.white.opacity(0.045),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }

            HStack(spacing: 10) {
                Button("Add Applications…", systemImage: "plus") {
                    showsApplicationPicker = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.settingsQuickApps.count >= QuickAppShelfPolicy.maximumCount)
                Spacer()
                Text("\(store.settingsQuickApps.count) of \(QuickAppShelfPolicy.maximumCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Label("You can add, remove, or reorder Shelf apps later in Settings.",
                  systemImage: "gearshape")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var workspacesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeading(
                "Move through workspaces naturally",
                detail: "Most setups use numbered workspaces. The same number works with both shortcut families."
            )

            shortcutExample(family: .navigate, key: "2", label: "Switch to workspace 2", color: .blue)
            shortcutExample(family: .arrange, key: "2", label: "Send this window to 2", color: .orange)

            onboardingBand(accent: .blue) {
                Toggle(isOn: Binding(
                    get: { store.workspaceSwipeEnabled },
                    set: coordinator.setWorkspaceSwipeEnabled
                )) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Trackpad workspace swipes").font(.headline)
                            Text("Swipe horizontally to move to the previous or next workspace.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                    }
                }
                .toggleStyle(.switch)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())

                if store.workspaceSwipeEnabled {
                    Picker("Gesture", selection: Binding(
                        get: { store.workspaceSwipeFingerCount },
                        set: coordinator.setWorkspaceSwipeFingerCount
                    )) {
                        ForEach(WorkspaceSwipeFingerCount.allCases) { count in
                            Text(count.title).tag(count)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Label("You're ready. WindowRanger will keep teaching through the passive shortcut guide and Command Palette.",
                  systemImage: "checkmark.seal.fill")
                .font(.subheadline)
                .foregroundStyle(.green)
        }
    }

    private var artworkPanel: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.black.opacity(0.34))
            LinearGradient(
                colors: [.blue.opacity(0.20), .clear, .orange.opacity(0.07)],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            GeometryReader { proxy in
                Image(
                    coordinator.step.assetName,
                    bundle: Bundle(for: OnboardingAssetBundle.self)
                )
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .id(coordinator.step)
                    .transition(.opacity)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(artworkTitle)
                    .font(.headline)
                Text(artworkDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.10))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Illustration: \(artworkTitle). \(artworkDetail)")
    }

    private var artworkColumn: some View {
        GeometryReader { proxy in
            artworkPanel
                .frame(
                    width: max(0, proxy.size.width - 48),
                    height: max(0, proxy.size.height - 48)
                )
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .allowsHitTesting(false)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button("Back") { coordinator.goBack() }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!coordinator.canGoBack)

            Spacer()
            HStack(spacing: 9) {
                ForEach(OnboardingStep.allCases) { step in
                    Button {
                        guard step.rawValue <= coordinator.step.rawValue else { return }
                        coordinator.move(to: step)
                    } label: {
                        Image(systemName: step.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 30, height: 30)
                            .background(step == coordinator.step ? Color.blue.opacity(0.28) : .clear,
                                        in: Circle())
                            .foregroundStyle(step == coordinator.step ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(step.rawValue > coordinator.step.rawValue)
                    .help(step.title)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.035), in: Capsule())
            Spacer()

            Button(coordinator.isFinalStep ? "Finish" : "Continue") {
                coordinator.goForward()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 26)
        .frame(height: 70)
    }

    private func stepHeading(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
            Text(detail)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func onboardingBand<Content: View>(
        accent: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.045))
                    .overlay {
                        LinearGradient(
                            colors: [accent.opacity(0.10), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(accent.opacity(0.18))
                    .allowsHitTesting(false)
            }
    }

    private func shortcutFamilyBand(
        family: ShortcutFamily,
        color: Color,
        detail: String
    ) -> some View {
        onboardingBand(accent: color) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(family.title).font(.headline).foregroundStyle(color)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                modifierKeyCaps(store.hotKeyConfiguration.modifierMask(for: family), color: color)
                Menu {
                    ForEach(coordinator.availableShortcutFamilyModifierChoices(for: family), id: \.self) { modifiers in
                        Button(modifierTitle(modifiers)) {
                            coordinator.setShortcutFamilyModifiers(modifiers, for: family)
                        }
                    }
                } label: {
                    Text("Change…")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(color)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Change \(family.title) shortcut modifiers")
            }
        }
    }

    private func shortcutExample(
        family: ShortcutFamily,
        key: String,
        label: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(color)
            HStack(spacing: 5) {
                ForEach(modifierSymbols(store.hotKeyConfiguration.modifierMask(for: family)), id: \.self) {
                    keyCap($0, color: color)
                }
                Text("+").foregroundStyle(.tertiary)
                keyCap(key, color: color)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func modifierKeyCaps(_ modifiers: UInt32, color: Color) -> some View {
        HStack(spacing: 5) {
            ForEach(modifierSymbols(modifiers), id: \.self) { keyCap($0, color: color) }
        }
    }

    private func keyCap(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .padding(.horizontal, 9)
            .frame(minWidth: 34, minHeight: 28)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(color.opacity(0.38))
                    .allowsHitTesting(false)
            }
    }

    private func modifierSymbols(_ modifiers: UInt32) -> [String] {
        Array(HotKeyChord(keyCode: 0, modifiers: modifiers).keyCaps.dropLast())
    }

    private func modifierTitle(_ modifiers: UInt32) -> String {
        modifierSymbols(modifiers).joined(separator: " ")
    }

    private func menuBarShortExplanation(_ mode: MenuBarPresentationMode) -> String {
        switch mode {
        case .compact: "Tiny active-workspace signal"
        case .medium: "One readable workspace chip"
        case .full: "Every workspace visible and clickable"
        }
    }

    private func applicationIcon(bundleIdentifier: String) -> some View {
        let image = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier).map {
            NSWorkspace.shared.icon(forFile: $0.path)
        } ?? NSImage()
        return Image(nsImage: image).resizable().frame(width: 26, height: 26)
    }

    private var artworkTitle: String {
        switch coordinator.step {
        case .welcome: "Your windows, under control"
        case .iCloud: "One setup across your Macs"
        case .shortcuts: "Navigate or arrange"
        case .focusBorder: "See what is focused"
        case .menuBar: "A signal at a glance"
        case .quickAppShelf: "Important apps, close by"
        case .workspaces: "Move between contexts"
        }
    }

    private var artworkDetail: String {
        switch coordinator.step {
        case .welcome: "The Ranger will guide you through the core setup."
        case .iCloud: "Sync is optional and can be changed at any time."
        case .shortcuts: "Blue changes focus; amber moves the window."
        case .focusBorder: "A quiet outline marks the command target."
        case .menuBar: "Choose how much workspace context stays visible."
        case .quickAppShelf: "Your chosen order becomes the Shelf order."
        case .workspaces: "Use numbers, arrows, or a horizontal trackpad swipe."
        }
    }
}

private final class OnboardingAssetBundle: NSObject {}

private struct FocusBorderMiniPreview: View {
    let enabled: Bool
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.black.opacity(0.22))
            HStack(spacing: 16) {
                sampleWindow(opacity: 0.40)
                sampleWindow(opacity: 0.82)
                    .overlay {
                        if enabled {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(color, lineWidth: 3)
                                .shadow(color: color.opacity(0.65), radius: 5)
                        }
                    }
            }
            .padding(18)
        }
        .frame(height: 126)
        .overlay(alignment: .bottomTrailing) {
            Text(enabled ? "Focused" : "Border off")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(8)
        }
    }

    private func sampleWindow(opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(.white.opacity(0.10 * opacity))
            .overlay(alignment: .topLeading) {
                HStack(spacing: 4) {
                    Circle().fill(.white.opacity(0.35)).frame(width: 5, height: 5)
                    Circle().fill(.white.opacity(0.22)).frame(width: 5, height: 5)
                }
                .padding(8)
            }
            .frame(maxWidth: .infinity)
    }
}

private struct MenuBarModePreview: View {
    let mode: MenuBarPresentationMode

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "viewfinder")
            switch mode {
            case .compact:
                Circle().fill(.blue).frame(width: 7, height: 7)
            case .medium:
                workspaceChip("2", selected: true)
            case .full:
                ForEach(["1", "2", "3"], id: \.self) { workspaceChip($0, selected: $0 == "2") }
            }
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.40), in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.12))
                .allowsHitTesting(false)
        }
    }

    private func workspaceChip(_ label: String, selected: Bool) -> some View {
        Text(label)
            .frame(minWidth: 18, minHeight: 18)
            .background(selected ? Color.blue : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
    }
}

private struct OnboardingApplicationPicker: View {
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
            } else if groups.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                List {
                    if !groups.openApplications.isEmpty {
                        Section("Open Applications") {
                            ForEach(groups.openApplications) { applicationRow($0) }
                        }
                    }
                    if !groups.otherApplications.isEmpty {
                        Section("Other Applications") {
                            ForEach(groups.otherApplications) { applicationRow($0) }
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

    private var groups: InstalledApplicationGroups {
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
