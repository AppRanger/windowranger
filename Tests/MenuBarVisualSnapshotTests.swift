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
        let state = WorkspaceEngineState(
            currentWorkspaceID: workspaces[5].id,
            activeWorkspaceIDs: [workspaces[1].id, workspaces[5].id],
            previousWorkspaceID: nil,
            managedWindowCount: 6,
            accessibilityGranted: true,
            activeWorkspaceIDByDisplay: [
                builtIn.identifier: workspaces[1].id,
                external.identifier: workspaces[5].id,
            ]
        )
        return MenuBarPresentationMode.allCases.map { mode in
            MenuBarPresentationResolver.resolve(
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

private enum SnapshotError: Error {
    case couldNotAllocateBitmap
    case couldNotEncodePNG
}

private struct MenuBarSnapshotCanvas: View {
    let snapshot: MenuBarPresentationSnapshot

    var body: some View {
        HStack(spacing: 5) {
            MenuBarPrimaryStatusView(snapshot: snapshot)
            if snapshot.mode == .full {
                Rectangle()
                    .fill(.white.opacity(0.20))
                    .frame(width: 0.5, height: MenuBarVisualTokens.separatorHeight)
                MenuBarFullStripRepresentable(snapshot: snapshot, availableWidth: 620)
                    .fixedSize()
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color(red: 0.075, green: 0.075, blue: 0.085))
        .environment(\.colorScheme, .dark)
        .fixedSize()
    }
}
