import AppKit
import XCTest

final class TiledResizePreviewTests: XCTestCase {
    func testPanelPolicyCannotActivateCaptureMouseOrEnterWindowCycle() {
        let policy = TiledResizePreviewPanelPolicy.nonActivating

        XCTAssertFalse(policy.canBecomeKey)
        XCTAssertFalse(policy.canBecomeMain)
        XCTAssertTrue(policy.ignoresMouseEvents)
        XCTAssertFalse(policy.participatesInWindowCycle)
    }

    func testMoveTransitionAnimatesOnlyAnExistingPreview() {
        XCTAssertFalse(TiledResizePreviewTransition.immediate.shouldAnimate(isContinuation: true))
        XCTAssertFalse(TiledResizePreviewTransition.animated.shouldAnimate(isContinuation: false))
        XCTAssertTrue(TiledResizePreviewTransition.animated.shouldAnimate(isContinuation: true))
        XCTAssertGreaterThan(TiledResizePreviewPolicy.moveAnimationDuration, 0)
    }

    func testAccessibilityFrameConversionUsesMainDisplayTopAcrossGlobalDesktop() {
        let frame = WindowFrame(
            position: CGPoint(x: -800, y: -300),
            size: CGSize(width: 640, height: 480)
        )

        XCTAssertEqual(
            TiledResizePreviewPolicy.appKitFrame(for: frame, mainScreenTop: 1_000),
            CGRect(x: -800, y: 820, width: 640, height: 480)
        )
    }

    func testTileFrameIsRelativeToCurtainAndReservesVisibleSeparation() {
        let frame = WindowFrame(
            position: CGPoint(x: 110, y: 120),
            size: CGSize(width: 300, height: 240)
        )
        let panelFrame = CGRect(x: 100, y: 640, width: 800, height: 500)

        XCTAssertEqual(
            TiledResizePreviewPolicy.localTileFrame(
                frame,
                panelFrame: panelFrame,
                mainScreenTop: 1_000
            ),
            CGRect(x: 12, y: 2, width: 296, height: 236)
        )
    }

    func testDraggedEdgesInferInternalLeadingAndTrailingChanges() {
        let expected = WindowFrame(
            position: CGPoint(x: 100, y: 200),
            size: CGSize(width: 500, height: 400)
        )

        XCTAssertEqual(
            TiledResizeDraggedEdges.inferred(
                expectedFrame: expected,
                observedFrame: WindowFrame(
                    position: CGPoint(x: 160, y: 200),
                    size: CGSize(width: 440, height: 470)
                )
            ),
            [.left, .bottom]
        )
        XCTAssertEqual(
            TiledResizeDraggedEdges.inferred(
                expectedFrame: expected,
                observedFrame: WindowFrame(
                    position: CGPoint(x: 100, y: 150),
                    size: CGSize(width: 560, height: 450)
                )
            ),
            [.right, .top]
        )
    }

    func testDraggedEdgesProjectFrameFromPointerAfterRealWindowIsParked() throws {
        let edges: TiledResizeDraggedEdges = [.left, .bottom]
        let projected = try XCTUnwrap(
            edges.projectedFrame(
                from: WindowFrame(
                    position: CGPoint(x: 300, y: 100),
                    size: CGSize(width: 500, height: 400)
                ),
                anchorPointer: CGPoint(x: 300, y: 500),
                pointer: CGPoint(x: 250, y: 560)
            )
        )

        XCTAssertEqual(projected.position, CGPoint(x: 250, y: 100))
        XCTAssertEqual(projected.size, CGSize(width: 550, height: 460))
    }

    @MainActor
    func testGlassTileUsesNativeGlassWhenAvailableAndHUDMaterialOtherwise() throws {
        let surface = TiledResizeGlassSurfaceFactory.make(
            frame: CGRect(x: 0, y: 0, width: 300, height: 240)
        )

        if #available(macOS 26.0, *) {
            let glass = try XCTUnwrap(surface as? NSGlassEffectView)
            XCTAssertEqual(glass.style, .clear)
            XCTAssertEqual(glass.cornerRadius, TiledResizePreviewPolicy.tileCornerRadius)
            XCTAssertNil(glass.tintColor)
            XCTAssertNil(glass.contentView)
        } else {
            let material = try XCTUnwrap(surface as? NSVisualEffectView)
            XCTAssertEqual(material.material, .hudWindow)
            XCTAssertEqual(material.blendingMode, .withinWindow)
            XCTAssertEqual(
                material.layer?.cornerRadius,
                TiledResizePreviewPolicy.tileCornerRadius
            )
        }
        XCTAssertFalse(surface.isAccessibilityElement())
    }

    @MainActor
    func testNativeCanvasLeavesDesktopTransparentAndBatchesGlassTiles() throws {
        let canvas = TiledResizePreviewCanvas(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )

        if #available(macOS 26.0, *) {
            XCTAssertTrue(canvas.usesNativeGlassContainer)
            let container = try XCTUnwrap(canvas.subviews.first as? NSGlassEffectContainerView)
            XCTAssertEqual(container.spacing, 0)
            XCTAssertNil(canvas.layer?.backgroundColor)
            XCTAssertTrue(canvas.layer?.sublayers?.isEmpty ?? true)
        } else {
            XCTAssertFalse(canvas.usesNativeGlassContainer)
            XCTAssertNil(canvas.layer?.backgroundColor)
        }
    }

    @MainActor
    func testNativeTileUsesClearGlassAndPlacesBorderInsideGlass() throws {
        let tile = TiledResizePreviewTileView(
            frame: CGRect(x: 0, y: 0, width: 400, height: 300)
        )

        if #available(macOS 26.0, *) {
            let glass = try XCTUnwrap(tile.surface as? NSGlassEffectView)
            XCTAssertEqual(glass.style, .clear)
            XCTAssertTrue(tile.subviews.first === glass)
            let border = try XCTUnwrap(glass.contentView)
            XCTAssertEqual(
                border.layer?.borderWidth,
                TiledResizePreviewPolicy.nativeBorderWidth
            )
            XCTAssertEqual(border.layer?.cornerRadius, TiledResizePreviewPolicy.tileCornerRadius)
        } else {
            XCTAssertTrue(tile.surface is NSVisualEffectView)
        }
    }

    @MainActor
    func testStaleDismissCannotRemoveNewerPreview() {
        let firstToken = UUID()
        let secondToken = UUID()
        let key = WindowKey(processIdentifier: 42, windowIdentifier: 7)
        let controller = TiledResizePreviewController(mainScreenTopProvider: { 1_000 })

        func presentation(_ token: UUID) -> TiledResizePreviewPresentation {
            TiledResizePreviewPresentation(
                token: token,
                displayIdentifier: "display",
                layoutBounds: WindowFrame(
                    position: CGPoint(x: 0, y: 0),
                    size: CGSize(width: 800, height: 600)
                ),
                frames: [
                    key: WindowFrame(
                        position: CGPoint(x: 0, y: 0),
                        size: CGSize(width: 800, height: 600)
                    ),
                ],
                transition: .immediate
            )
        }

        controller.present(presentation(firstToken))
        controller.present(presentation(secondToken))
        XCTAssertFalse(controller.dismiss(token: firstToken, reason: "stale"))
        XCTAssertEqual(controller.presentedToken, secondToken)

        XCTAssertTrue(controller.dismiss(token: secondToken, reason: "current"))
        XCTAssertNil(controller.presentedToken)
        controller.shutdown()
    }

    @MainActor
    func testDisplayChangeReportsWhetherItDismissedAnActivePreview() {
        let token = UUID()
        let key = WindowKey(processIdentifier: 42, windowIdentifier: 7)
        let controller = TiledResizePreviewController(mainScreenTopProvider: { 1_000 })
        controller.present(TiledResizePreviewPresentation(
            token: token,
            displayIdentifier: "display",
            layoutBounds: WindowFrame(
                position: CGPoint(x: 0, y: 0),
                size: CGSize(width: 800, height: 600)
            ),
            frames: [
                key: WindowFrame(
                    position: CGPoint(x: 0, y: 0),
                    size: CGSize(width: 800, height: 600)
                ),
            ],
            transition: .immediate
        ))

        XCTAssertTrue(controller.screenParametersDidChange())
        XCTAssertNil(controller.presentedToken)
        XCTAssertFalse(controller.screenParametersDidChange())
        controller.shutdown()
    }

    @MainActor
    func testOffscreenProductionPreviewRender() throws {
        guard let outputPath = ProcessInfo.processInfo.environment[
            "WINDOWRANGER_TILED_RESIZE_PREVIEW_PATH"
        ], !outputPath.isEmpty else { return }

        let size = CGSize(width: 1_200, height: 800)
        let canvas = TiledResizePreviewCanvas(frame: CGRect(origin: .zero, size: size))
        let keys = (1...3).map {
            WindowKey(processIdentifier: 42, windowIdentifier: CGWindowID($0))
        }
        canvas.update(
            frames: [
                keys[0]: WindowFrame(
                    position: CGPoint(x: 0, y: 0),
                    size: CGSize(width: 720, height: 800)
                ),
                keys[1]: WindowFrame(
                    position: CGPoint(x: 720, y: 0),
                    size: CGSize(width: 480, height: 460)
                ),
                keys[2]: WindowFrame(
                    position: CGPoint(x: 720, y: 460),
                    size: CGSize(width: 480, height: 340)
                ),
            ],
            panelFrame: CGRect(origin: .zero, size: size),
            mainScreenTop: size.height
        )
        canvas.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
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
        ))
        bitmap.size = size
        canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        XCTAssertGreaterThan(data.count, 1_000)
    }
}
