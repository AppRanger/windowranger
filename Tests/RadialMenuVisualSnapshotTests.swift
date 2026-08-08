import AppKit
import SwiftUI
import XCTest

/// Opt-in production-view snapshots. Normal tests only build the fixture; an explicit output
/// directory writes Retina PNGs without AppDelegate, Accessibility, global hotkeys, iCloud, or a
/// WindowManager.app process.
final class RadialMenuVisualSnapshotTests: XCTestCase {
    private static let snapshotSize = CGSize(width: 620, height: 620)

    @MainActor
    func testOffscreenProductionRadialMenuStates() throws {
        let contexts = representativeContexts()
        let snapshots: [(String, RadialMenuPresentationModel)] = [
            ("place", presentation(context: contexts.tiled, selected: .resize, outerIndex: 7)),
            ("move-to-space", presentation(context: contexts.tiled, selected: .moveToSpace, outerIndex: 2)),
            ("profiles", presentation(context: contexts.profiles, selected: .profiles, outerIndex: 1)),
        ]
        XCTAssertTrue(snapshots.allSatisfy { $0.1.activeGroupIndex != nil })
        XCTAssertTrue(snapshots.allSatisfy { !$0.1.activeChildren.isEmpty })

        guard let outputPath = ProcessInfo.processInfo.environment[
            "WINDOWMANAGER_RADIAL_SNAPSHOT_DIR"
        ], !outputPath.isEmpty else {
            return
        }
        let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        for (name, model) in snapshots {
            let view = RadialMenuSnapshotCanvas(model: model)
            let data = try renderRetinaPNG(view)
            try data.write(
                to: outputDirectory.appendingPathComponent("window-manager-radial-\(name).png"),
                options: .atomic
            )
            XCTAssertGreaterThan(data.count, 10_000)
        }
    }

    @MainActor
    private func presentation(
        context: RadialCommandContext,
        selected itemID: RadialTopLevelItemID,
        outerIndex: Int
    ) -> RadialMenuPresentationModel {
        let menu = RadialCommandContextBuilder.build(from: context)
        let model = RadialMenuPresentationModel(menu: menu)
        let index = menu.items.firstIndex { $0.definitionID == itemID.rawValue }!
        for _ in 0...index { model.moveSelection(1) }
        model.enterSelectedGroup()
        for _ in 0..<outerIndex { model.moveSelection(1) }
        return model
    }

    private func representativeContexts() -> (tiled: RadialCommandContext, profiles: RadialCommandContext) {
        let focused = WindowKey(processIdentifier: 42, windowIdentifier: 900)
        let siblingA = WindowKey(processIdentifier: 43, windowIdentifier: 901)
        let siblingB = WindowKey(processIdentifier: 44, windowIdentifier: 902)
        let bounds = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        let workspaces = (1...6).map { index in
            RadialWorkspaceOption(
                id: UUID(uuidString: String(format: "40000000-0000-0000-0000-%012d", index))!,
                name: index == 4 ? "Writing" : String(index),
                layout: index == 1 ? .tiled : .none,
                homeDisplayIdentifier: "external"
            )
        }
        var context = RadialCommandContext(
            focusedWindow: RadialFocusedWindowContext(
                processIdentifier: focused.processIdentifier,
                windowIdentifier: focused.windowIdentifier,
                workspaceID: workspaces[0].id,
                frame: WindowFrame(position: CGPoint(x: 120, y: 90), size: CGSize(width: 980, height: 760)),
                layoutState: .managed,
                isAutomaticallyFloatingDialog: false,
                isAppRuleExcluded: false,
                keepsOnAllWorkspaces: false
            ),
            focusSource: .focusedManagedWindow,
            workspaceID: workspaces[0].id,
            workspaceName: workspaces[0].name,
            layout: .tiled,
            displayIdentifier: "external",
            displayName: "Studio Display",
            displayBounds: bounds,
            displayMode: .independent,
            focusFollowsMovedWindow: false,
            connectedDisplayIdentifiers: ["built-in", "external"],
            connectedDisplays: [
                RadialDisplayOption(id: "built-in", name: "Built-in Display", isMain: true),
                RadialDisplayOption(id: "external", name: "Studio Display", isMain: false),
            ],
            availableFocusDirections: Set(WindowDirection.allCases),
            availableMoveDirections: Set(WindowDirection.allCases),
            canSmartResize: true,
            workspaces: workspaces,
            supportedCommands: RadialCommandCapability.current,
            validationToken: "visual-fixture"
        )
        if let tree = TiledLayoutEngine.flatTree(
            windowKeys: [focused, siblingA, siblingB],
            weights: [1, 1, 1],
            orientation: .horizontal
        ) {
            context.tiledPlacementPreviews = VisualPlacement.compassOrder.compactMap {
                try? TiledLayoutEngine.placing(
                    focused,
                    at: $0,
                    in: tree,
                    bounds: bounds,
                    configuration: .aeroSpaceUserDefaults
                )
            }
        }
        var profileContext = context
        profileContext.profiles = [
            RadialProfileOption(id: UUID(uuidString: "50000000-0000-0000-0000-000000000001")!, name: "Laptop"),
            RadialProfileOption(id: UUID(uuidString: "50000000-0000-0000-0000-000000000002")!, name: "Studio"),
            RadialProfileOption(id: UUID(uuidString: "50000000-0000-0000-0000-000000000003")!, name: "Travel"),
            RadialProfileOption(id: UUID(uuidString: "50000000-0000-0000-0000-000000000004")!, name: "Presentation"),
        ]
        profileContext.activeProfileID = profileContext.profiles[1].id
        profileContext.isProfileManuallyPinned = true
        return (context, profileContext)
    }

    @MainActor
    private func renderRetinaPNG<V: View>(_ view: V) throws -> Data {
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(Self.snapshotSize)
        renderer.scale = 2
        guard let image = renderer.cgImage else { throw SnapshotError.couldNotAllocateBitmap }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError.couldNotEncodePNG
        }
        return data
    }
}

private enum SnapshotError: Error {
    case couldNotAllocateBitmap
    case couldNotEncodePNG
}

private struct RadialMenuSnapshotCanvas: View {
    @ObservedObject var model: RadialMenuPresentationModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(red: 0.07, green: 0.16, blue: 0.30)
            RadialMenuView(model: model)
                .frame(
                    width: RadialMenuController.panelSize.width,
                    height: RadialMenuController.panelSize.height
                )
                .position(x: 310, y: 310)
        }
        .frame(width: 620, height: 620)
        .clipped()
        .environment(\.colorScheme, .dark)
    }
}
