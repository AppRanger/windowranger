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

    func testTitleBarMoveWithTransientSizeNoiseIsNotClaimedAsResize() {
        let expected = WindowFrame(
            position: CGPoint(x: 100, y: 200),
            size: CGSize(width: 500, height: 400)
        )
        let observed = WindowFrame(
            position: CGPoint(x: 180, y: 250),
            size: CGSize(width: 506, height: 404)
        )

        XCTAssertEqual(
            TiledManualDragClassifier.classify(
                expectedFrame: expected,
                observedFrame: observed,
                pointer: CGPoint(x: 430, y: 278)
            ),
            .move
        )
    }

    func testPointerOnChangedEdgeClassifiesRightAndLeftResize() {
        let expected = WindowFrame(
            position: CGPoint(x: 100, y: 200),
            size: CGSize(width: 500, height: 400)
        )

        XCTAssertEqual(
            TiledManualDragClassifier.classify(
                expectedFrame: expected,
                observedFrame: WindowFrame(
                    position: expected.position,
                    size: CGSize(width: 560, height: 400)
                ),
                pointer: CGPoint(x: 660, y: 400)
            ),
            .resize(.right)
        )
        XCTAssertEqual(
            TiledManualDragClassifier.classify(
                expectedFrame: expected,
                observedFrame: WindowFrame(
                    position: CGPoint(x: 160, y: 200),
                    size: CGSize(width: 440, height: 400)
                ),
                pointer: CGPoint(x: 160, y: 400)
            ),
            .resize(.left)
        )
    }

    func testCornerResizeRequiresPointerOnBothChangedEdges() {
        let expected = WindowFrame(
            position: CGPoint(x: 100, y: 200),
            size: CGSize(width: 500, height: 400)
        )
        let observed = WindowFrame(
            position: expected.position,
            size: CGSize(width: 560, height: 460)
        )

        XCTAssertEqual(
            TiledManualDragClassifier.classify(
                expectedFrame: expected,
                observedFrame: observed,
                pointer: CGPoint(x: 660, y: 660)
            ),
            .resize([.right, .bottom])
        )
        XCTAssertNil(TiledManualDragClassifier.classify(
            expectedFrame: expected,
            observedFrame: observed,
            pointer: CGPoint(x: 660, y: 400)
        ))
    }

    func testChangedEdgeDoesNotMatchPointerBeyondItsSpan() {
        let expected = WindowFrame(
            position: CGPoint(x: 100, y: 200),
            size: CGSize(width: 500, height: 400)
        )
        let observed = WindowFrame(
            position: expected.position,
            size: CGSize(width: 560, height: 400)
        )

        XCTAssertNil(TiledManualDragClassifier.classify(
            expectedFrame: expected,
            observedFrame: observed,
            pointer: CGPoint(x: 660, y: 1_600)
        ))
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
    func testLandingTileUsesAccentTintAndStrongerBorder() throws {
        let tile = TiledResizePreviewTileView(
            frame: CGRect(x: 0, y: 0, width: 400, height: 300),
            role: .landing
        )

        if #available(macOS 26.0, *) {
            let glass = try XCTUnwrap(tile.surface as? NSGlassEffectView)
            XCTAssertNotNil(glass.tintColor)
            let border = try XCTUnwrap(glass.contentView)
            XCTAssertGreaterThan(
                border.layer?.borderWidth ?? 0,
                TiledResizePreviewPolicy.nativeBorderWidth
            )
        } else {
            XCTAssertGreaterThan(tile.surface.layer?.borderWidth ?? 0, 1)
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
                transition: .immediate,
                role: .layout
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
            transition: .immediate,
            role: .layout
        ))

        XCTAssertTrue(controller.screenParametersDidChange())
        XCTAssertNil(controller.presentedToken)
        XCTAssertFalse(controller.screenParametersDidChange())
        controller.shutdown()
    }

    @MainActor
    func testOffscreenProductionPreviewRender() throws {
        let environment = ProcessInfo.processInfo.environment
        let resizePath = environment["WINDOWRANGER_TILED_RESIZE_PREVIEW_PATH"]
        let landingPath = environment["WINDOWRANGER_TILED_LANDING_PREVIEW_PATH"]
        guard let outputPath = [landingPath, resizePath].compactMap({ $0 }).first,
              !outputPath.isEmpty
        else { return }

        let size = CGSize(width: 1_200, height: 800)
        let canvas = TiledResizePreviewCanvas(frame: CGRect(origin: .zero, size: size))
        let keys = (1...3).map {
            WindowKey(processIdentifier: 42, windowIdentifier: CGWindowID($0))
        }
        let layoutFrames: [WindowKey: WindowFrame] = [
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
            ]
        let landingFrames = [
            keys[0]: WindowFrame(
                position: CGPoint(x: 720, y: 0),
                size: CGSize(width: 240, height: 460)
            ),
        ]
        canvas.update(
            frames: landingPath == nil ? layoutFrames : landingFrames,
            panelFrame: CGRect(origin: .zero, size: size),
            mainScreenTop: size.height,
            role: landingPath == nil ? .layout : .landing
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
