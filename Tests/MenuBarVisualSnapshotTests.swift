import AppKit
import SwiftUI
import XCTest

/// An opt-in, non-hosted visual fixture. Normal tests only verify that the production views can be
/// composed; setting WINDOWMANAGER_MENU_SNAPSHOT_DIR writes Retina PNGs without starting the app,
/// AppDelegate, Accessibility, hotkeys, iCloud, or any live window-management path.
final class MenuBarVisualSnapshotTests: XCTestCase {
    @MainActor
    func testOffscreenProductionMenuBarComponents() throws {
        let snapshots = representativeSnapshots()
        XCTAssertEqual(Set(snapshots.map(\.mode)), Set(MenuBarPresentationMode.allCases))

        guard let outputPath = ProcessInfo.processInfo.environment[
            "WINDOWMANAGER_MENU_SNAPSHOT_DIR"
        ], !outputPath.isEmpty else {
            return
        }

        let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        for snapshot in snapshots {
            let view = MenuBarSnapshotCanvas(snapshot: snapshot)
            let data = try renderRetinaPNG(view)
            let url = outputDirectory.appendingPathComponent(
                "window-manager-menu-bar-\(snapshot.mode.rawValue).png"
            )
            try data.write(to: url, options: .atomic)
            XCTAssertGreaterThan(data.count, 1_000)
        }
    }

    @MainActor
    private func representativeSnapshots() -> [MenuBarPresentationSnapshot] {
        let workspaces = [
            workspace("30000000-0000-0000-0000-000000000001", "1"),
            workspace("30000000-0000-0000-0000-000000000002", "2"),
            workspace("30000000-0000-0000-0000-000000000003", "3"),
            workspace("30000000-0000-0000-0000-000000000007", "7"),
            workspace("30000000-0000-0000-0000-000000000008", "8"),
            workspace("30000000-0000-0000-0000-000000000009", "9"),
        ]
        let builtIn = DisplaySnapshot(
            identifier: "fixture-built-in",
            bounds: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            isMain: true,
            isBuiltIn: true,
            name: "Built-in Display"
        )
        let external = DisplaySnapshot(
            identifier: "fixture-external",
            bounds: CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080),
            isMain: false,
            name: "Studio Display"
        )
        let assignments = Dictionary(uniqueKeysWithValues: workspaces.enumerated().map {
            ($0.element.id, $0.offset < 3 ? builtIn.identifier : external.identifier)
        })
        return MenuBarPresentationMode.allCases.map { mode in
            let builtInActive = mode == .full ? workspaces[1].id : workspaces[0].id
            let interaction = mode == .compact ? builtInActive : workspaces[5].id
            let state = WorkspaceEngineState(
                currentWorkspaceID: interaction,
                activeWorkspaceIDs: [builtInActive, workspaces[5].id],
                previousWorkspaceID: nil,
                managedWindowCount: 6,
                accessibilityGranted: true,
                activeWorkspaceIDByDisplay: [
                    builtIn.identifier: builtInActive,
                    external.identifier: workspaces[5].id,
                ]
            )
            return MenuBarPresentationResolver.resolve(
                mode: mode,
                displayMode: .independent,
                state: state,
                workspaces: workspaces,
                connectedDisplays: [external, builtIn],
                workspaceDisplayAssignments: assignments
            )
        }
    }

    private func workspace(_ id: String, _ name: String) -> WorkspaceDefinition {
        WorkspaceDefinition(id: UUID(uuidString: id)!, name: name, key: name)
    }

    @MainActor
    private func renderRetinaPNG<V: View>(_ view: V) throws -> Data {
        let hosting = NSHostingView(rootView: view)
        hosting.layoutSubtreeIfNeeded()
        let fitting = hosting.fittingSize
        XCTAssertGreaterThan(fitting.width, 1)
        XCTAssertGreaterThan(fitting.height, 1)
        hosting.frame = CGRect(origin: .zero, size: fitting)
        hosting.layoutSubtreeIfNeeded()

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(ceil(fitting.width * 2)),
            pixelsHigh: Int(ceil(fitting.height * 2)),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw SnapshotError.couldNotAllocateBitmap
        }
        bitmap.size = fitting
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError.couldNotEncodePNG
        }
        return png
    }
}

/// Opt-in native Settings fixture. It renders the production Settings hierarchy in an offscreen
/// AppKit host without constructing AppDelegate, starting WorkspaceEngine, contacting iCloud,
/// requesting Accessibility, registering hotkeys, or ordering a window onto the user's desktop.
final class WorkspaceSettingsVisualSnapshotTests: XCTestCase {
    private static let snapshotSize = CGSize(width: 1_440, height: 1_024)

    @MainActor
    func testOffscreenProductionWorkspaceSettings() throws {
        let defaultsSuite = "WindowManagerTests.SettingsSnapshot.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        defaults.removePersistentDomain(forName: defaultsSuite)
        defaults.set(false, forKey: "iCloudSyncEnabled")

        let displays = [
            DisplaySnapshot(
                identifier: "fixture-built-in",
                bounds: CGRect(x: 0, y: 0, width: 1_512, height: 982),
                isMain: true,
                isBuiltIn: true,
                name: "Built-in Display"
            ),
            DisplaySnapshot(
                identifier: "fixture-studio",
                bounds: CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080),
                isMain: false,
                name: "Studio Display"
            ),
        ]
        let focus = workspace("60000000-0000-0000-0000-000000000001", "Focus", "f", .tiled)
        var writing = workspace("60000000-0000-0000-0000-000000000002", "Writing", "w", .accordion)
        writing.layoutConfiguration = WorkspaceLayoutConfiguration(
            orientation: .automatic,
            accordionPadding: 16,
            gaps: .aeroSpaceUserDefaults
        )
        let chat = workspace("60000000-0000-0000-0000-000000000003", "Chat", "c", .tiled)
        let review = workspace("60000000-0000-0000-0000-000000000004", "Review", "r", .none)
        let workspaces = [focus, writing, chat, review]

        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { displays },
            isPortableMacProvider: { true },
            diagnostics: .disabled
        )
        store.workspaces = workspaces
        store.multiDisplayMode = .independent
        let roleID = store.activeProfile.displayRoles[0].id
        store.renameDisplayRole(roleID, to: "Studio Display")
        workspaces.forEach { store.assignWorkspace($0.id, toRole: roleID) }

        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "WindowManager-SettingsSnapshot-\(UUID().uuidString).json"
        )
        defer { try? FileManager.default.removeItem(at: stateURL) }
        let engine = WorkspaceEngine(
            workspaces: workspaces,
            profileID: store.activeProfileID,
            displayMode: .independent,
            stateStore: WorkspaceStateStore(fileURL: stateURL, sessionProvider: { "fixture" }),
            diagnostics: .disabled
        )
        let navigation = SettingsNavigationModel(defaults: defaults, includeDebug: false)
        navigation.selectWorkspace(writing.id)
        let coordinator = SettingsWindowCoordinator(
            diagnostics: .disabled,
            displayProvider: { [] },
            applicationActivator: {}
        )
        let view = SettingsView(
            store: store,
            engine: engine,
            navigation: navigation,
            windowCoordinator: coordinator,
            diagnostics: .disabled,
            shortcutRecordingStateChanged: { _ in }
        )
        .frame(width: Self.snapshotSize.width, height: Self.snapshotSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .light)
        .environment(\.controlActiveState, .key)

        XCTAssertEqual(store.multiDisplayMode, .independent)
        XCTAssertEqual(navigation.requestedWorkspaceID, writing.id)
        XCTAssertEqual(store.workspaces.first { $0.id == writing.id }?.layout, .accordion)

        guard let outputPath = ProcessInfo.processInfo.environment[
            "WINDOWMANAGER_SETTINGS_SNAPSHOT_DIR"
        ], !outputPath.isEmpty else { return }

        let data = try renderRetinaPNG(
            view,
            size: Self.snapshotSize
        )
        XCTAssertGreaterThan(data.count, 25_000)
        let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        try data.write(
            to: outputDirectory.appendingPathComponent("window-manager-settings-workspaces.png"),
            options: .atomic
        )

        let darkView = SettingsView(
            store: store,
            engine: engine,
            navigation: navigation,
            windowCoordinator: coordinator,
            diagnostics: .disabled,
            shortcutRecordingStateChanged: { _ in }
        )
        .frame(width: Self.snapshotSize.width, height: Self.snapshotSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .dark)
        .environment(\.controlActiveState, .key)
        let darkData = try renderRetinaPNG(
            darkView,
            size: Self.snapshotSize,
            appearance: .darkAqua
        )
        XCTAssertGreaterThan(darkData.count, 25_000)
        try darkData.write(
            to: outputDirectory.appendingPathComponent("window-manager-settings-workspaces-dark.png"),
            options: .atomic
        )

        let currentProfileID = store.activeProfileID
        store.renameProfile(currentProfileID, to: "Current Setup")
        _ = store.createProfile(named: "Travel", source: .scratch)
        store.selectProfile(currentProfileID)
        navigation.select(.profiles)
        let profilesData = try renderRetinaPNG(view, size: Self.snapshotSize)
        XCTAssertGreaterThan(profilesData.count, 25_000)
        try profilesData.write(
            to: outputDirectory.appendingPathComponent("window-manager-settings-profiles.png"),
            options: .atomic
        )

        let largeTextSize = CGSize(width: 1_180, height: 900)
        let largeTextData = try renderRetinaPNG(
            WorkspaceSettingsView(
                store: store,
                engine: engine,
                initiallySelectedWorkspaceID: writing.id
            )
            .frame(width: largeTextSize.width, height: largeTextSize.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .light)
            .environment(\.controlActiveState, .key)
            .environment(\.dynamicTypeSize, .accessibility2),
            size: largeTextSize
        )
        try largeTextData.write(
            to: outputDirectory.appendingPathComponent(
                "window-manager-settings-workspaces-accessibility-text.png"
            ),
            options: .atomic
        )
        XCTAssertGreaterThan(largeTextData.count, 25_000)
    }

    private func workspace(
        _ id: String,
        _ name: String,
        _ key: String,
        _ layout: WorkspaceLayout
    ) -> WorkspaceDefinition {
        WorkspaceDefinition(id: UUID(uuidString: id)!, name: name, key: key, layout: layout)
    }

    @MainActor
    private func renderRetinaPNG<V: View>(
        _ view: V,
        size: CGSize,
        appearance: NSAppearance.Name = .aqua
    ) throws -> Data {
        let renderedView = NSHostingView(rootView: view)
        renderedView.appearance = NSAppearance(named: appearance)
        renderedView.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: renderedView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.contentView = renderedView
        renderedView.layoutSubtreeIfNeeded()
        // SwiftUI Lists and NavigationSplitView virtualize their AppKit descendants. A bounded
        // genuine update cycle realizes those descendants without ever ordering this window.
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        renderedView.layoutSubtreeIfNeeded()
        emphasizeSelectedControls(in: renderedView)
        renderedView.displayIfNeeded()
        XCTAssertEqual(renderedView.bounds.size.width, size.width, accuracy: 1)
        XCTAssertEqual(renderedView.bounds.size.height, size.height, accuracy: 1)

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2),
            pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw SnapshotError.couldNotAllocateBitmap
        }
        bitmap.size = size
        renderedView.cacheDisplay(in: renderedView.bounds, to: bitmap)
        window.close()
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError.couldNotEncodePNG
        }
        return png
    }

    private func emphasizeSelectedControls(in view: NSView) {
        if let row = view as? NSTableRowView, row.isSelected {
            row.isEmphasized = true
        }
        if let segmented = view as? NSSegmentedControl {
            segmented.selectedSegmentBezelColor = .controlAccentColor
        }
        view.subviews.forEach(emphasizeSelectedControls)
    }
}

private enum SnapshotError: Error {
    case couldNotAllocateBitmap
    case couldNotEncodePNG
}

private struct MenuBarSnapshotCanvas: View {
    let snapshot: MenuBarPresentationSnapshot

    var body: some View {
        MenuBarStatusContentRepresentable(snapshot: snapshot, availableWidth: 620)
            .fixedSize()
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color(red: 0.075, green: 0.075, blue: 0.085))
        .environment(\.colorScheme, .dark)
        .fixedSize()
    }
}
