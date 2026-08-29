import AppKit
import SwiftUI
import XCTest

/// An opt-in, non-hosted visual fixture. Normal tests only verify that the production views can be
/// composed; setting WINDOWRANGER_MENU_SNAPSHOT_DIR writes Retina PNGs without starting the app,
/// AppDelegate, Accessibility, hotkeys, iCloud, or any live window-management path.
final class MenuBarVisualSnapshotTests: XCTestCase {
    @MainActor
    func testOffscreenProductionMenuBarComponents() throws {
        let snapshots = representativeSnapshots()
        XCTAssertEqual(Set(snapshots.map(\.mode)), Set(MenuBarPresentationMode.allCases))

        guard let outputPath = ProcessInfo.processInfo.environment[
            "WINDOWRANGER_MENU_SNAPSHOT_DIR"
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
            let labelModeSuffix = snapshot.mode == .compact
                ? "-\(snapshot.workspaceLabelMode.rawValue)"
                : ""
            let url = outputDirectory.appendingPathComponent(
                "windowranger-menu-bar-\(snapshot.mode.rawValue)\(labelModeSuffix).png"
            )
            try data.write(to: url, options: .atomic)
            XCTAssertGreaterThan(data.count, 1_000)
        }
        let keyIconReview = try XCTUnwrap(compactKeyIconReviewSnapshot(from: snapshots))
        let keyIconReviewData = try renderRetinaPNG(
            CompactKeyIconReviewCanvas(snapshot: keyIconReview)
        )
        try keyIconReviewData.write(
            to: outputDirectory.appendingPathComponent(
                "windowranger-menu-bar-compact-key-icon-review.png"
            ),
            options: .atomic
        )
        XCTAssertGreaterThan(keyIconReviewData.count, 1_000)
    }

    @MainActor
    func testOffscreenReusableWorkspacePreviewFallback() throws {
        let workspaceID = UUID(uuidString: "30000000-0000-0000-0000-000000000010")!
        let descriptor = WorkspacePreviewDescriptor(
            workspaceID: workspaceID,
            name: "Writing",
            canvasFrame: CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
            items: [
                previewItem(workspaceID: workspaceID, pid: 10, windowID: 100, name: "Notes", frame: CGRect(x: 40, y: 50, width: 1_150, height: 720)),
                previewItem(workspaceID: workspaceID, pid: 20, windowID: 200, name: "Reference", frame: CGRect(x: 1_220, y: 50, width: 660, height: 480)),
                previewItem(workspaceID: workspaceID, pid: 30, windowID: 300, name: "Messages", frame: CGRect(x: 1_220, y: 560, width: 660, height: 470)),
            ]
        )
        let view = WorkspacePreviewView(
            descriptor: descriptor,
            interactionMode: .workspaceAndItems,
            onWorkspaceSelected: {},
            onItemSelected: { _ in }
        )
        .frame(width: 360, height: 190)
        .padding(10)
        .background(Color(nsColor: .windowBackgroundColor))
        let data = try renderRetinaPNG(view)
        XCTAssertGreaterThan(data.count, 1_000)

        let portraitWorkspaceID = UUID(uuidString: "30000000-0000-0000-0000-000000000011")!
        let portraitDescriptor = WorkspacePreviewDescriptor(
            workspaceID: portraitWorkspaceID,
            name: "Portrait",
            canvasFrame: CGRect(x: -1_080, y: 0, width: 1_080, height: 1_920),
            items: [
                previewItem(workspaceID: portraitWorkspaceID, pid: 40, windowID: 400, name: "Top", frame: CGRect(x: -1_040, y: 80, width: 1_000, height: 760)),
                previewItem(workspaceID: portraitWorkspaceID, pid: 50, windowID: 500, name: "Bottom", frame: CGRect(x: -900, y: 920, width: 820, height: 900)),
            ]
        )
        let portraitView = WorkspacePreviewView(
            descriptor: portraitDescriptor,
            interactionMode: .workspaceAndItems,
            onWorkspaceSelected: {},
            onItemSelected: { _ in }
        )
        .frame(width: 360, height: 190)
        .padding(10)
        .background(Color(nsColor: .windowBackgroundColor))
        let portraitData = try renderRetinaPNG(portraitView)
        XCTAssertGreaterThan(portraitData.count, 1_000)

        if let outputPath = ProcessInfo.processInfo.environment["WINDOWRANGER_MENU_SNAPSHOT_DIR"],
           !outputPath.isEmpty {
            let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            try data.write(
                to: outputDirectory.appendingPathComponent("windowranger-workspace-preview-fallback.png"),
                options: .atomic
            )
            try portraitData.write(
                to: outputDirectory.appendingPathComponent("windowranger-workspace-preview-portrait-fallback.png"),
                options: .atomic
            )
        }
    }

    @MainActor
    private func representativeSnapshots() -> [MenuBarPresentationSnapshot] {
        let workspaces = [
            workspace("30000000-0000-0000-0000-000000000001", "Focus", "M"),
            workspace("30000000-0000-0000-0000-000000000002", "Writing", "2"),
            workspace("30000000-0000-0000-0000-000000000003", "Chat", "3"),
            workspace("30000000-0000-0000-0000-000000000007", "Review", "7"),
            workspace("30000000-0000-0000-0000-000000000008", "Utilities", "8"),
            workspace("30000000-0000-0000-0000-000000000009", "Meetings", "2"),
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
        let nameSnapshots = MenuBarPresentationMode.allCases.map { mode in
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
        guard let compactName = nameSnapshots.first(where: { $0.mode == .compact }) else {
            return nameSnapshots
        }
        let compactKey = MenuBarPresentationSnapshot(
            mode: .compact,
            workspaceLabelMode: .key,
            displayMode: compactName.displayMode,
            interactionWorkspaceID: compactName.interactionWorkspaceID,
            displays: compactName.displays
        )
        return nameSnapshots + [compactKey]
    }

    private func workspace(_ id: String, _ name: String, _ key: String) -> WorkspaceDefinition {
        WorkspaceDefinition(id: UUID(uuidString: id)!, name: name, key: key)
    }

    private func previewItem(
        workspaceID: UUID,
        pid: pid_t,
        windowID: CGWindowID,
        name: String,
        frame: CGRect
    ) -> WorkspacePreviewItemDescriptor {
        WorkspacePreviewItemDescriptor(
            key: WindowKey(processIdentifier: pid, windowIdentifier: windowID),
            applicationTarget: WorkspaceApplicationTarget(
                workspaceID: workspaceID,
                bundleIdentifier: "dev.appranger.fixture.\(pid)",
                processIdentifier: pid
            ),
            name: name,
            applicationURL: nil,
            frame: frame
        )
    }

    private func compactKeyIconReviewSnapshot(
        from snapshots: [MenuBarPresentationSnapshot]
    ) -> MenuBarPresentationSnapshot? {
        guard let source = snapshots.first(where: { $0.mode == .compact })?.displays.first else {
            return nil
        }
        let variants: [(String, MenuBarDisplayIconKind)] = [
            ("review-horizontal", .external),
            ("review-vertical", .external),
            ("review-laptop", .builtIn),
            ("review-combined", .combined),
        ]
        let displays = variants.map { identifier, iconKind in
            MenuBarDisplayItem(
                id: identifier,
                name: identifier,
                iconKind: iconKind,
                isInteractionDisplay: identifier == "review-horizontal",
                activeWorkspaceID: source.activeWorkspaceID,
                activeWorkspaceName: source.activeWorkspaceName,
                activeWorkspaceCompactName: source.activeWorkspaceCompactName,
                activeWorkspaceKey: "M",
                workspaces: source.workspaces
            )
        }
        return MenuBarPresentationSnapshot(
            mode: .compact,
            workspaceLabelMode: .key,
            displayMode: .independent,
            interactionWorkspaceID: source.activeWorkspaceID,
            displays: displays
        )
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
        let snapshotScope = ProcessInfo.processInfo.environment[
            "WINDOWRANGER_SETTINGS_SNAPSHOT_SCOPE"
        ]
        let defaultsSuite = "WindowRangerTests.SettingsSnapshot.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        defaults.removePersistentDomain(forName: defaultsSuite)
        defaults.set(false, forKey: "iCloudSyncEnabled")

        let displays = [
            DisplaySnapshot(
                identifier: "fixture-built-in",
                bounds: CGRect(x: 0, y: 0, width: 1_512, height: 982),
                isMain: true,
                isBuiltIn: true,
                name: snapshotScope == "displays" ? "TYPE-C" : "Built-in Display"
            ),
            DisplaySnapshot(
                identifier: "fixture-studio",
                bounds: CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080),
                isMain: false,
                name: snapshotScope == "displays" ? "DELL U4021QW" : "Studio Display"
            ),
        ]
        var focus = workspace("60000000-0000-0000-0000-000000000001", "Focus", "f", .tiled)
        focus.layoutConfiguration = WorkspaceLayoutConfiguration(
            orientation: .automatic,
            accordionPadding: 250,
            gaps: WorkspaceLayoutGaps(
                innerHorizontal: 140,
                innerVertical: 55,
                outerTop: 70,
                outerRight: 280,
                outerBottom: 220,
                outerLeft: 110
            )
        )
        var writing = workspace("60000000-0000-0000-0000-000000000002", "Writing", "w", .accordion)
        writing.layoutConfiguration = WorkspaceLayoutConfiguration(
            orientation: .automatic,
            accordionPadding: 16,
            gaps: .aeroSpaceUserDefaults
        )
        var chat = workspace("60000000-0000-0000-0000-000000000003", "Chat", "c", .tiled)
        chat.layoutConfiguration = WorkspaceLayoutConfiguration(
            orientation: .automatic,
            accordionPadding: 250,
            gaps: WorkspaceLayoutGaps(
                innerHorizontal: 0,
                innerVertical: 0,
                outerTop: 0,
                outerRight: 0,
                outerBottom: 0,
                outerLeft: 0
            )
        )
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
        store.appRules = [AppRule(
            bundleIdentifier: "com.example.Writer",
            displayName: "Writer",
            actions: [.assignWorkspace(writing.id), .floatSecondaryWindows]
        )]
        store.multiDisplayMode = .independent
        let roleID = store.activeProfile.displayRoles[0].id
        store.renameDisplayRole(roleID, to: "Studio Display")
        workspaces.forEach { store.assignWorkspace($0.id, toRole: roleID) }
        if snapshotScope == "displays" {
            store.renameProfile(store.activeProfileID, to: "Desktop 2 screens")
            store.renameDisplayRole(roleID, to: "Primary Display")
            let sideRoleID: UUID
            if let existingSideRoleID = store.activeProfile.displayRoles.dropFirst().first?.id {
                sideRoleID = existingSideRoleID
                store.renameDisplayRole(sideRoleID, to: "Side bar")
            } else {
                sideRoleID = store.addDisplayRole(name: "Side bar")
            }
            store.bindDisplayRole(roleID, to: "fixture-studio")
            store.bindDisplayRole(sideRoleID, to: "fixture-built-in")
        }

        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "WindowRanger-SettingsSnapshot-\(UUID().uuidString).json"
        )
        defer { try? FileManager.default.removeItem(at: stateURL) }
        let engine = WorkspaceEngine(
            workspaces: workspaces,
            profileID: store.activeProfileID,
            displayMode: .independent,
            stateStore: WorkspaceStateStore(fileURL: stateURL, sessionProvider: { "fixture" }),
            diagnostics: .disabled
        )
        let navigation = SettingsNavigationModel(defaults: defaults, includeDebug: true)
        if snapshotScope == "displays" {
            navigation.select(.displays)
        } else {
            navigation.selectWorkspace(writing.id)
        }
        let coordinator = SettingsWindowCoordinator(
            diagnostics: .disabled,
            displayProvider: { [] },
            applicationActivator: {}
        )
        let updateController = UpdateController(
            configuration: UpdateRuntimeConfiguration(
                buildChannel: .development,
                feedURL: nil,
                publicKey: nil
            )
        )
        let view = SettingsView(
            store: store,
            engine: engine,
            navigation: navigation,
            windowCoordinator: coordinator,
            diagnostics: .disabled,
            updateController: updateController,
            shortcutRecordingStateChanged: { _ in }
        )
        .frame(width: Self.snapshotSize.width, height: Self.snapshotSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .light)
        .environment(\.controlActiveState, .key)

        XCTAssertEqual(store.multiDisplayMode, .independent)
        if snapshotScope == "displays" {
            XCTAssertEqual(navigation.selectedCategory, .displays)
            XCTAssertNil(navigation.requestedWorkspaceID)
        } else {
            XCTAssertEqual(navigation.requestedWorkspaceID, writing.id)
        }
        XCTAssertEqual(store.workspaces.first { $0.id == writing.id }?.layout, .accordion)

        guard let outputPath = ProcessInfo.processInfo.environment[
            "WINDOWRANGER_SETTINGS_SNAPSHOT_DIR"
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
        if snapshotScope == "displays" {
            let displayWideSize = CGSize(width: 1_536, height: 1_024)
            let lightDisplaysView = SettingsView(
                store: store,
                engine: engine,
                navigation: navigation,
                windowCoordinator: coordinator,
                diagnostics: .disabled,
                updateController: updateController,
                shortcutRecordingStateChanged: { _ in }
            )
            .frame(width: displayWideSize.width, height: displayWideSize.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .light)
            .environment(\.controlActiveState, .key)
            let lightDisplaysData = try renderRetinaPNG(
                lightDisplaysView,
                size: displayWideSize
            )
            XCTAssertGreaterThan(lightDisplaysData.count, 25_000)
            try lightDisplaysData.write(
                to: outputDirectory.appendingPathComponent(
                    "windowranger-settings-displays.png"
                ),
                options: .atomic
            )
            let darkDisplaysView = SettingsView(
                store: store,
                engine: engine,
                navigation: navigation,
                windowCoordinator: coordinator,
                diagnostics: .disabled,
                updateController: updateController,
                shortcutRecordingStateChanged: { _ in }
            )
            .frame(width: displayWideSize.width, height: displayWideSize.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .dark)
            .environment(\.controlActiveState, .key)
            let darkDisplaysData = try renderRetinaPNG(
                darkDisplaysView,
                size: displayWideSize,
                appearance: .darkAqua
            )
            XCTAssertGreaterThan(darkDisplaysData.count, 25_000)
            try darkDisplaysData.write(
                to: outputDirectory.appendingPathComponent(
                    "windowranger-settings-displays-dark.png"
                ),
                options: .atomic
            )

            let compactSize = SettingsWindowMetrics.minimumSize
            let compactDisplaysView = SettingsView(
                store: store,
                engine: engine,
                navigation: navigation,
                windowCoordinator: coordinator,
                diagnostics: .disabled,
                updateController: updateController,
                shortcutRecordingStateChanged: { _ in }
            )
            .frame(width: compactSize.width, height: compactSize.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .dark)
            .environment(\.controlActiveState, .key)
            let compactDisplaysData = try renderRetinaPNG(
                compactDisplaysView,
                size: compactSize,
                appearance: .darkAqua
            )
            XCTAssertGreaterThan(compactDisplaysData.count, 15_000)
            try compactDisplaysData.write(
                to: outputDirectory.appendingPathComponent(
                    "windowranger-settings-displays-compact-dark.png"
                ),
                options: .atomic
            )
            return
        }
        try data.write(
            to: outputDirectory.appendingPathComponent("windowranger-settings-workspaces.png"),
            options: .atomic
        )

        let darkView = SettingsView(
            store: store,
            engine: engine,
            navigation: navigation,
            windowCoordinator: coordinator,
            diagnostics: .disabled,
            updateController: updateController,
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
            to: outputDirectory.appendingPathComponent("windowranger-settings-workspaces-dark.png"),
            options: .atomic
        )

        navigation.selectWorkspace(focus.id)
        let tiledDarkView = SettingsView(
            store: store,
            engine: engine,
            navigation: navigation,
            windowCoordinator: coordinator,
            diagnostics: .disabled,
            updateController: updateController,
            shortcutRecordingStateChanged: { _ in }
        )
        .frame(width: Self.snapshotSize.width, height: Self.snapshotSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .dark)
        .environment(\.controlActiveState, .key)
        let tiledDarkData = try renderRetinaPNG(
            tiledDarkView,
            size: Self.snapshotSize,
            appearance: .darkAqua
        )
        XCTAssertGreaterThan(tiledDarkData.count, 25_000)
        try tiledDarkData.write(
            to: outputDirectory.appendingPathComponent(
                "windowranger-settings-workspaces-tiled-dark.png"
            ),
            options: .atomic
        )
        navigation.selectWorkspace(writing.id)

        if snapshotScope == "workspaces" {
            let compactSize = SettingsWindowMetrics.minimumSize
            let compactView = SettingsView(
                store: store,
                engine: engine,
                navigation: navigation,
                windowCoordinator: coordinator,
                diagnostics: .disabled,
                updateController: updateController,
                shortcutRecordingStateChanged: { _ in }
            )
            .frame(width: compactSize.width, height: compactSize.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .light)
            .environment(\.controlActiveState, .key)
            let compactData = try renderRetinaPNG(compactView, size: compactSize)
            XCTAssertGreaterThan(compactData.count, 15_000)
            try compactData.write(
                to: outputDirectory.appendingPathComponent(
                    "windowranger-settings-workspaces-compact.png"
                ),
                options: .atomic
            )

            let compactDarkView = SettingsView(
                store: store,
                engine: engine,
                navigation: navigation,
                windowCoordinator: coordinator,
                diagnostics: .disabled,
                updateController: updateController,
                shortcutRecordingStateChanged: { _ in }
            )
            .frame(width: compactSize.width, height: compactSize.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .dark)
            .environment(\.controlActiveState, .key)
            let compactDarkData = try renderRetinaPNG(
                compactDarkView,
                size: compactSize,
                appearance: .darkAqua
            )
            XCTAssertGreaterThan(compactDarkData.count, 15_000)
            try compactDarkData.write(
                to: outputDirectory.appendingPathComponent(
                    "windowranger-settings-workspaces-compact-dark.png"
                ),
                options: .atomic
            )

            let longWorkspace = workspace(
                "60000000-0000-0000-0000-000000000009",
                "Long-form Research and Reference",
                "l",
                .none
            )
            let additionalWorkspaces = [
                workspace("60000000-0000-0000-0000-000000000005", "Planning", "p", .tiled),
                workspace("60000000-0000-0000-0000-000000000006", "Meetings", "m", .accordion),
                workspace("60000000-0000-0000-0000-000000000007", "Build", "b", .tiled),
                workspace("60000000-0000-0000-0000-000000000008", "Archive", "a", .none),
                longWorkspace,
            ]
            store.workspaces = workspaces + additionalWorkspaces
            additionalWorkspaces.forEach { store.assignWorkspace($0.id, toRole: roleID) }
            navigation.selectWorkspace(longWorkspace.id)

            let manyWorkspacesView = SettingsView(
                store: store,
                engine: engine,
                navigation: navigation,
                windowCoordinator: coordinator,
                diagnostics: .disabled,
                updateController: updateController,
                shortcutRecordingStateChanged: { _ in }
            )
            .frame(width: Self.snapshotSize.width, height: Self.snapshotSize.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .dark)
            .environment(\.controlActiveState, .key)
            let manyWorkspacesData = try renderRetinaPNG(
                manyWorkspacesView,
                size: Self.snapshotSize,
                appearance: .darkAqua
            )
            XCTAssertGreaterThan(manyWorkspacesData.count, 25_000)
            try manyWorkspacesData.write(
                to: outputDirectory.appendingPathComponent(
                    "windowranger-settings-workspaces-many-dark.png"
                ),
                options: .atomic
            )

            let compactManyWorkspacesView = SettingsView(
                store: store,
                engine: engine,
                navigation: navigation,
                windowCoordinator: coordinator,
                diagnostics: .disabled,
                updateController: updateController,
                shortcutRecordingStateChanged: { _ in }
            )
            .frame(width: compactSize.width, height: compactSize.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .dark)
            .environment(\.controlActiveState, .key)
            let compactManyWorkspacesData = try renderRetinaPNG(
                compactManyWorkspacesView,
                size: compactSize,
                appearance: .darkAqua
            )
            XCTAssertGreaterThan(compactManyWorkspacesData.count, 15_000)
            try compactManyWorkspacesData.write(
                to: outputDirectory.appendingPathComponent(
                    "windowranger-settings-workspaces-many-compact-dark.png"
                ),
                options: .atomic
            )
            return
        }

        navigation.selectWorkspace(focus.id)

        let tiledGeometryWideSize = CGSize(width: 2_200, height: Self.snapshotSize.height)
        let tiledGeometryWideView = SettingsView(
            store: store,
            engine: engine,
            navigation: navigation,
            windowCoordinator: coordinator,
            diagnostics: .disabled,
            updateController: updateController,
            shortcutRecordingStateChanged: { _ in }
        )
        .frame(width: tiledGeometryWideSize.width, height: tiledGeometryWideSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .light)
        .environment(\.controlActiveState, .key)
        let tiledGeometryWideData = try renderRetinaPNG(
            tiledGeometryWideView,
            size: tiledGeometryWideSize
        )
        XCTAssertGreaterThan(tiledGeometryWideData.count, 25_000)
        try tiledGeometryWideData.write(
            to: outputDirectory.appendingPathComponent(
                "windowranger-settings-tiled-geometry-wide.png"
            ),
            options: .atomic
        )

        let tiledGeometryData = try renderRetinaPNG(view, size: Self.snapshotSize)
        XCTAssertGreaterThan(tiledGeometryData.count, 25_000)
        try tiledGeometryData.write(
            to: outputDirectory.appendingPathComponent(
                "windowranger-settings-tiled-geometry.png"
            ),
            options: .atomic
        )
        let tiledGeometryDarkData = try renderRetinaPNG(
            darkView,
            size: Self.snapshotSize,
            appearance: .darkAqua
        )
        XCTAssertGreaterThan(tiledGeometryDarkData.count, 25_000)
        try tiledGeometryDarkData.write(
            to: outputDirectory.appendingPathComponent(
                "windowranger-settings-tiled-geometry-dark.png"
            ),
            options: .atomic
        )

        let tiledGeometryCompactSize = CGSize(
            width: SettingsWindowMetrics.minimumSize.width,
            height: Self.snapshotSize.height
        )
        let tiledGeometryCompactView = SettingsView(
            store: store,
            engine: engine,
            navigation: navigation,
            windowCoordinator: coordinator,
            diagnostics: .disabled,
            updateController: updateController,
            shortcutRecordingStateChanged: { _ in }
        )
        .frame(
            width: tiledGeometryCompactSize.width,
            height: tiledGeometryCompactSize.height
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .light)
        .environment(\.controlActiveState, .key)
        let tiledGeometryCompactData = try renderRetinaPNG(
            tiledGeometryCompactView,
            size: tiledGeometryCompactSize
        )
        XCTAssertGreaterThan(tiledGeometryCompactData.count, 15_000)
        try tiledGeometryCompactData.write(
            to: outputDirectory.appendingPathComponent(
                "windowranger-settings-tiled-geometry-compact.png"
            ),
            options: .atomic
        )

        navigation.selectWorkspace(chat.id)
        let tiledGeometryZeroData = try renderRetinaPNG(view, size: Self.snapshotSize)
        XCTAssertGreaterThan(tiledGeometryZeroData.count, 25_000)
        try tiledGeometryZeroData.write(
            to: outputDirectory.appendingPathComponent(
                "windowranger-settings-tiled-geometry-zero.png"
            ),
            options: .atomic
        )

        store.setSettingsLayoutConfiguration(
            WorkspaceLayoutConfiguration(
                orientation: .automatic,
                accordionPadding: 250,
                gaps: WorkspaceLayoutGaps(
                    innerHorizontal: 5,
                    innerVertical: 5,
                    outerTop: 5,
                    outerRight: 5,
                    outerBottom: 5,
                    outerLeft: 5
                )
            ),
            for: chat.id
        )
        let tiledGeometryFivePointData = try renderRetinaPNG(view, size: Self.snapshotSize)
        XCTAssertGreaterThan(tiledGeometryFivePointData.count, 25_000)
        try tiledGeometryFivePointData.write(
            to: outputDirectory.appendingPathComponent(
                "windowranger-settings-tiled-geometry-five-point.png"
            ),
            options: .atomic
        )
        let tiledGeometryFivePointDarkData = try renderRetinaPNG(
            darkView,
            size: Self.snapshotSize,
            appearance: .darkAqua
        )
        XCTAssertGreaterThan(tiledGeometryFivePointDarkData.count, 25_000)
        try tiledGeometryFivePointDarkData.write(
            to: outputDirectory.appendingPathComponent(
                "windowranger-settings-tiled-geometry-five-point-dark.png"
            ),
            options: .atomic
        )

        navigation.selectWorkspace(writing.id)

        let currentProfileID = store.activeProfileID
        store.renameProfile(currentProfileID, to: "Current Setup")
        store.setSettingsProfileIconStyle(.desktop)
        let travelProfileID = try XCTUnwrap(
            store.createProfile(named: "Travel", source: .scratch)
        )
        store.setSettingsProfileIconStyle(.travel)
        let gameProfileID = try XCTUnwrap(
            store.createProfile(named: "Game Room", source: .scratch)
        )
        store.setSettingsProfileIconStyle(.home)
        let studioProfileID = try XCTUnwrap(
            store.createProfile(named: "Studio With External Displays", source: .scratch)
        )
        store.setSettingsProfileIconStyle(.work)
        store.selectProfile(currentProfileID)
        store.setDefaultProfile(currentProfileID)
        store.setGameModeProfile(gameProfileID)
        store.setDockedProfile(studioProfileID)
        store.setUndockedProfile(travelProfileID)
        _ = store.assignCurrentDisplaySetup(to: studioProfileID)
        store.selectProfileForEditing(travelProfileID)
        store.setFocusedWindowHighlightCornerRadiusOverride(
            14,
            for: "com.apple.Terminal",
            undoManager: nil
        )
        navigation.select(.profiles)
        let profilesData = try renderRetinaPNG(view, size: Self.snapshotSize)
        XCTAssertGreaterThan(profilesData.count, 25_000)
        try profilesData.write(
            to: outputDirectory.appendingPathComponent("windowranger-settings-profiles.png"),
            options: .atomic
        )
        let darkProfilesData = try renderRetinaPNG(
            darkView,
            size: Self.snapshotSize,
            appearance: .darkAqua
        )
        XCTAssertGreaterThan(darkProfilesData.count, 25_000)
        try darkProfilesData.write(
            to: outputDirectory.appendingPathComponent(
                "windowranger-settings-profiles-dark.png"
            ),
            options: .atomic
        )

        for category in [
            SettingsCategory.general,
            .updates,
            .sync,
            .behavior,
            .menuBar,
            .focusBorder,
            .displays,
            .appRules,
            .quickAppShelf,
            .shortcuts,
            .shortcutGuide,
            .radialMenu,
            .diagnostics,
        ] {
            navigation.select(category)
            let wideCategoryData = try renderRetinaPNG(view, size: Self.snapshotSize)
            XCTAssertGreaterThan(wideCategoryData.count, 25_000)
            try wideCategoryData.write(
                to: outputDirectory.appendingPathComponent(
                    "windowranger-settings-\(category.rawValue).png"
                ),
                options: .atomic
            )
            let darkCategoryData = try renderRetinaPNG(
                darkView,
                size: Self.snapshotSize,
                appearance: .darkAqua
            )
            XCTAssertGreaterThan(darkCategoryData.count, 25_000)
            try darkCategoryData.write(
                to: outputDirectory.appendingPathComponent(
                    "windowranger-settings-\(category.rawValue)-dark.png"
                ),
                options: .atomic
            )
        }

        store.appRules = []
        store.dropDownApp = DropDownAppConfiguration(
            bundleIdentifier: "com.example.Terminal",
            displayName: "Terminal",
            heightFraction: 0.8,
            isAnimationEnabled: true,
            direction: .top
        )
        navigation.select(.appRules)
        let quickAppData = try renderRetinaPNG(view, size: Self.snapshotSize)
        XCTAssertGreaterThan(quickAppData.count, 25_000)
        try quickAppData.write(
            to: outputDirectory.appendingPathComponent(
                "windowranger-settings-quick-app.png"
            ),
            options: .atomic
        )
        let darkQuickAppData = try renderRetinaPNG(
            darkView,
            size: Self.snapshotSize,
            appearance: .darkAqua
        )
        XCTAssertGreaterThan(darkQuickAppData.count, 25_000)
        try darkQuickAppData.write(
            to: outputDirectory.appendingPathComponent(
                "windowranger-settings-quick-app-dark.png"
            ),
            options: .atomic
        )

        let compactSize = SettingsWindowMetrics.minimumSize
        navigation.select(.profiles)
        let compactProfilesView = SettingsView(
            store: store,
            engine: engine,
            navigation: navigation,
            windowCoordinator: coordinator,
            diagnostics: .disabled,
            updateController: updateController,
            shortcutRecordingStateChanged: { _ in }
        )
        .frame(width: compactSize.width, height: compactSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .light)
        .environment(\.controlActiveState, .key)
        let compactProfilesData = try renderRetinaPNG(
            compactProfilesView,
            size: compactSize
        )
        XCTAssertGreaterThan(compactProfilesData.count, 15_000)
        try compactProfilesData.write(
            to: outputDirectory.appendingPathComponent(
                "windowranger-settings-profiles-compact.png"
            ),
            options: .atomic
        )

        navigation.selectWorkspace(writing.id)
        let compactWorkspacesView = SettingsView(
            store: store,
            engine: engine,
            navigation: navigation,
            windowCoordinator: coordinator,
            diagnostics: .disabled,
            updateController: updateController,
            shortcutRecordingStateChanged: { _ in }
        )
        .frame(width: compactSize.width, height: compactSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .light)
        .environment(\.controlActiveState, .key)
        let compactWorkspacesData = try renderRetinaPNG(
            compactWorkspacesView,
            size: compactSize
        )
        XCTAssertGreaterThan(compactWorkspacesData.count, 15_000)
        try compactWorkspacesData.write(
            to: outputDirectory.appendingPathComponent(
                "windowranger-settings-workspaces-compact.png"
            ),
            options: .atomic
        )

        for category in [
            SettingsCategory.general,
            .sync,
            .behavior,
            .menuBar,
            .focusBorder,
            .displays,
            .appRules,
            .quickAppShelf,
            .shortcuts,
            .shortcutGuide,
            .radialMenu,
            .diagnostics,
        ] {
            navigation.select(category)
            let compactCategoryView = SettingsView(
                store: store,
                engine: engine,
                navigation: navigation,
                windowCoordinator: coordinator,
                diagnostics: .disabled,
                updateController: updateController,
                shortcutRecordingStateChanged: { _ in }
            )
            .frame(width: compactSize.width, height: compactSize.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .light)
            .environment(\.controlActiveState, .key)
            let compactCategoryData = try renderRetinaPNG(
                compactCategoryView,
                size: compactSize
            )
            XCTAssertGreaterThan(compactCategoryData.count, 15_000)
            try compactCategoryData.write(
                to: outputDirectory.appendingPathComponent(
                    "windowranger-settings-\(category.rawValue)-compact.png"
                ),
                options: .atomic
            )
        }

        navigation.select(.appRules)
        let compactQuickAppView = SettingsView(
            store: store,
            engine: engine,
            navigation: navigation,
            windowCoordinator: coordinator,
            diagnostics: .disabled,
            updateController: updateController,
            shortcutRecordingStateChanged: { _ in }
        )
        .frame(width: compactSize.width, height: compactSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .light)
        .environment(\.controlActiveState, .key)
        let compactQuickAppData = try renderRetinaPNG(
            compactQuickAppView,
            size: compactSize
        )
        XCTAssertGreaterThan(compactQuickAppData.count, 15_000)
        try compactQuickAppData.write(
            to: outputDirectory.appendingPathComponent(
                "windowranger-settings-quick-app-compact.png"
            ),
            options: .atomic
        )

        let quickAppAccessibilitySize = CGSize(width: 1_180, height: 900)
        let quickAppAccessibilityView = SettingsView(
            store: store,
            engine: engine,
            navigation: navigation,
            windowCoordinator: coordinator,
            diagnostics: .disabled,
            updateController: updateController,
            shortcutRecordingStateChanged: { _ in }
        )
        .frame(
            width: quickAppAccessibilitySize.width,
            height: quickAppAccessibilitySize.height
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .light)
        .environment(\.controlActiveState, .key)
        .environment(\.dynamicTypeSize, .accessibility2)
        let quickAppAccessibilityData = try renderRetinaPNG(
            quickAppAccessibilityView,
            size: quickAppAccessibilitySize
        )
        XCTAssertGreaterThan(quickAppAccessibilityData.count, 25_000)
        try quickAppAccessibilityData.write(
            to: outputDirectory.appendingPathComponent(
                "windowranger-settings-quick-app-accessibility-text.png"
            ),
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
                "windowranger-settings-workspaces-accessibility-text.png"
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
        MenuBarSettingsPreview(
            snapshot: snapshot,
            displayIconConfiguration: MenuBarDisplayIconConfiguration(
                stylesByDisplayIdentifier: [
                    "fixture-built-in": .laptop,
                    "fixture-external": .horizontalMonitor,
                ]
            )
        )
        .background(Color(red: 0.075, green: 0.075, blue: 0.085))
        .environment(\.colorScheme, .dark)
        .fixedSize()
    }
}

private struct CompactKeyIconReviewCanvas: View {
    let snapshot: MenuBarPresentationSnapshot

    var body: some View {
        MenuBarSettingsPreview(
            snapshot: snapshot,
            displayIconConfiguration: MenuBarDisplayIconConfiguration(
                stylesByDisplayIdentifier: [
                    "review-horizontal": .horizontalMonitor,
                    "review-vertical": .verticalMonitor,
                    "review-laptop": .laptop,
                    "review-combined": .automatic,
                ]
            )
        )
        .background(Color(red: 0.075, green: 0.075, blue: 0.085))
        .environment(\.colorScheme, .dark)
        .fixedSize()
    }
}
