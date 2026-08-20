import AppKit
import SwiftUI
import XCTest

/// Opt-in production-view snapshots. Normal tests only build the fixture; an explicit output
/// directory writes Retina PNGs without AppDelegate, Accessibility, global hotkeys, iCloud, or a
/// WindowRanger.app process.
final class RadialMenuVisualSnapshotTests: XCTestCase {
    private static let snapshotSize = CGSize(width: 620, height: 620)

    @MainActor
    func testOffscreenProductionRadialMenuStates() throws {
        let contexts = representativeContexts()
        let snapshots: [(String, RadialMenuPresentationModel)] = [
            ("base", RadialMenuPresentationModel(menu: RadialCommandContextBuilder.build(from: contexts.tiled))),
            ("place", presentation(context: contexts.tiled, selected: .resize, outerIndex: 7)),
            ("freeform-place", presentation(context: contexts.freeform, selected: .resize, outerIndex: 7)),
            ("move-to-space", presentation(context: contexts.tiled, selected: .moveToSpace, outerIndex: 2)),
            ("go-to-space", presentation(context: contexts.tiled, selected: .goToSpace, outerIndex: 2)),
            ("layout", presentation(context: contexts.tiled, selected: .layoutType, outerIndex: 1)),
            ("accordion-layout", presentation(context: contexts.accordion, selected: .layoutType, outerIndex: 2)),
            ("profiles", presentation(context: contexts.profiles, selected: .profiles, outerIndex: 1)),
            ("long-labels", presentation(context: contexts.longLabels, selected: .profiles, outerIndex: 1)),
        ]
        XCTAssertNil(snapshots[0].1.activeGroupIndex)
        XCTAssertTrue(snapshots.dropFirst().allSatisfy { $0.1.activeGroupIndex != nil })
        XCTAssertTrue(snapshots.dropFirst().allSatisfy { !$0.1.activeChildren.isEmpty })

        guard let outputPath = ProcessInfo.processInfo.environment[
            "WINDOWRANGER_RADIAL_SNAPSHOT_DIR"
        ], !outputPath.isEmpty else {
            return
        }
        let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        for (name, model) in snapshots {
            let view = RadialMenuSnapshotCanvas(model: model)
            let data = try renderRetinaPNG(view)
            try data.write(
                to: outputDirectory.appendingPathComponent("windowranger-radial-\(name).png"),
                options: .atomic
            )
            XCTAssertGreaterThan(data.count, 10_000)
        }
    }

    @MainActor
    func testOffscreenSettingsCommandWheelPreview() throws {
        guard let outputPath = ProcessInfo.processInfo.environment[
            "WINDOWRANGER_RADIAL_SNAPSHOT_DIR"
        ], !outputPath.isEmpty else {
            return
        }
        let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let view = ZStack {
            Color(nsColor: .windowBackgroundColor)
            CommandWheelPreview(definition: .builtInDefault)
        }
        .frame(width: 420, height: 380)
        .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(CGSize(width: 420, height: 380))
        renderer.scale = 2
        guard let image = renderer.cgImage else { throw SnapshotError.couldNotAllocateBitmap }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError.couldNotEncodePNG
        }
        try data.write(
            to: outputDirectory.appendingPathComponent("windowranger-settings-command-wheel-preview.png"),
            options: .atomic
        )
        XCTAssertGreaterThan(data.count, 10_000)
    }

    @MainActor
    func testOffscreenCommandPalettePlacementHalo() throws {
        let context = representativeContexts().freeform
        XCTAssertEqual(CommandPaletteIndex.spatialPlacementActions(in: context).count, 8)
        guard let outputPath = ProcessInfo.processInfo.environment[
            "WINDOWRANGER_RADIAL_SNAPSHOT_DIR"
        ], !outputPath.isEmpty else {
            return
        }
        let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let size = CommandPaletteController.expandedPanelSize
        let view = ZStack {
            Color(nsColor: .windowBackgroundColor)
            CommandPaletteView(
                context: context,
                hotKeyConfiguration: HotKeyConfiguration(),
                initiallyShowsPlacementHalo: true,
                initialPlacementHaloSelection: .right,
                initiallyKeyboardFocusesPlacementHalo: true,
                focusesSearchOnAppear: false,
                choose: { _ in },
                placementHaloPresentationChanged: { _ in },
                dismiss: {}
            )
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, .light)
        let data = try renderHostedRetinaPNG(view, size: size)
        try data.write(
            to: outputDirectory.appendingPathComponent("windowranger-command-palette-placement-halo.png"),
            options: .atomic
        )
        XCTAssertGreaterThan(data.count, 10_000)
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

    private func representativeContexts() -> (
        tiled: RadialCommandContext,
        freeform: RadialCommandContext,
        accordion: RadialCommandContext,
        profiles: RadialCommandContext,
        longLabels: RadialCommandContext
    ) {
        let focused = WindowKey(processIdentifier: 42, windowIdentifier: 900)
        let siblingA = WindowKey(processIdentifier: 43, windowIdentifier: 901)
        let siblingB = WindowKey(processIdentifier: 44, windowIdentifier: 902)
        let bounds = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        let workspaceIndexes = Array(1...6)
        let workspaces: [RadialWorkspaceOption] = workspaceIndexes.map { index in
            let identifier = String(format: "40000000-0000-0000-0000-%012d", index)
            let workspaceID = UUID(uuidString: identifier)!
            let name = index == 4 ? "Writing" : String(index)
            let layout: WorkspaceLayout = index == 1 ? .tiled : .none
            return RadialWorkspaceOption(
                id: workspaceID,
                name: name,
                key: index == 4 ? "w" : String(index),
                layout: layout,
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
        var freeformContext = RadialCommandContext(
            focusedWindow: context.focusedWindow,
            focusSource: context.focusSource,
            workspaceID: context.workspaceID,
            workspaceName: context.workspaceName,
            layout: .none,
            displayIdentifier: context.displayIdentifier,
            displayName: context.displayName,
            displayBounds: context.displayBounds,
            displayMode: context.displayMode,
            focusFollowsMovedWindow: context.focusFollowsMovedWindow,
            connectedDisplayIdentifiers: context.connectedDisplayIdentifiers,
            connectedDisplays: context.connectedDisplays,
            availableFocusDirections: context.availableFocusDirections,
            availableMoveDirections: context.availableMoveDirections,
            canSmartResize: false,
            workspaces: context.workspaces,
            supportedCommands: context.supportedCommands,
            validationToken: "freeform-visual-fixture"
        )
        let originalFrame = WindowFrame(
            position: CGPoint(x: 120, y: 90),
            size: CGSize(width: 980, height: 760)
        )
        freeformContext.freeformPlacementPreviews = VisualPlacement.compassOrder.compactMap {
            FreeformPlacementEngine.preview(
                focusedWindow: focused,
                displayIdentifier: "external",
                originalFrame: originalFrame,
                placement: $0,
                displayBounds: bounds
            )
        }
        let accordionContext = RadialCommandContext(
            focusedWindow: context.focusedWindow,
            focusSource: context.focusSource,
            workspaceID: context.workspaceID,
            workspaceName: context.workspaceName,
            layout: .accordion,
            displayIdentifier: context.displayIdentifier,
            displayName: context.displayName,
            displayBounds: context.displayBounds,
            displayMode: context.displayMode,
            focusFollowsMovedWindow: context.focusFollowsMovedWindow,
            connectedDisplayIdentifiers: context.connectedDisplayIdentifiers,
            connectedDisplays: context.connectedDisplays,
            availableFocusDirections: context.availableFocusDirections,
            availableMoveDirections: context.availableMoveDirections,
            canSmartResize: context.canSmartResize,
            workspaces: context.workspaces,
            supportedCommands: context.supportedCommands,
            validationToken: "accordion-visual-fixture"
        )
        var profileContext = context
        profileContext.profiles = [
            RadialProfileOption(id: UUID(uuidString: "50000000-0000-0000-0000-000000000001")!, name: "Laptop"),
            RadialProfileOption(id: UUID(uuidString: "50000000-0000-0000-0000-000000000002")!, name: "Studio"),
            RadialProfileOption(id: UUID(uuidString: "50000000-0000-0000-0000-000000000003")!, name: "Travel"),
            RadialProfileOption(id: UUID(uuidString: "50000000-0000-0000-0000-000000000004")!, name: "Presentation"),
        ]
        profileContext.activeProfileID = profileContext.profiles[1].id
        profileContext.isProfileManuallyPinned = true
        var longLabelContext = profileContext
        longLabelContext.profiles = [
            RadialProfileOption(id: UUID(uuidString: "60000000-0000-0000-0000-000000000001")!, name: "Laptop"),
            RadialProfileOption(id: UUID(uuidString: "60000000-0000-0000-0000-000000000002")!, name: "Extremely Long Client Presentation Profile"),
            RadialProfileOption(id: UUID(uuidString: "60000000-0000-0000-0000-000000000003")!, name: "Travel Configuration With Extra Words"),
            RadialProfileOption(id: UUID(uuidString: "60000000-0000-0000-0000-000000000004")!, name: "Studio"),
        ]
        longLabelContext.activeProfileID = longLabelContext.profiles[1].id
        return (context, freeformContext, accordionContext, profileContext, longLabelContext)
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

    @MainActor
    private func renderHostedRetinaPNG<V: View>(_ view: V, size: CGSize) throws -> Data {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()
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
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
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
