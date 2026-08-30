import AppKit
import XCTest

@MainActor
final class WorkspacePreviewTests: XCTestCase {
    func testInteractionPolicySeparatesWorkspaceAndItemActivation() {
        XCTAssertTrue(WorkspacePreviewInteractionMode.workspaceOnly.acceptsWorkspace)
        XCTAssertFalse(WorkspacePreviewInteractionMode.workspaceOnly.acceptsItems)
        XCTAssertFalse(WorkspacePreviewInteractionMode.itemsOnly.acceptsWorkspace)
        XCTAssertTrue(WorkspacePreviewInteractionMode.itemsOnly.acceptsItems)
        XCTAssertTrue(WorkspacePreviewInteractionMode.workspaceAndItems.acceptsWorkspace)
        XCTAssertTrue(WorkspacePreviewInteractionMode.workspaceAndItems.acceptsItems)
    }

    func testClickedWindowIsPrioritizedWithoutDiscardingSameAppFallbacks() {
        let first = WindowKey(processIdentifier: 10, windowIdentifier: 100)
        let clicked = WindowKey(processIdentifier: 10, windowIdentifier: 200)
        let third = WindowKey(processIdentifier: 10, windowIdentifier: 300)

        XCTAssertEqual(
            WorkspacePreviewFocusCandidatePolicy.prioritizing(
                clicked,
                in: [first, clicked, third]
            ),
            [clicked, first, third]
        )
        XCTAssertEqual(
            WorkspacePreviewFocusCandidatePolicy.prioritizing(
                WindowKey(processIdentifier: 99, windowIdentifier: 999),
                in: [first, third]
            ),
            [first, third]
        )
    }

    func testGeometryScalesQuartzFramesIntoPreviewCoordinates() {
        let result = WorkspacePreviewGeometry.rect(
            CGRect(x: 100, y: 50, width: 400, height: 200),
            in: CGRect(x: 0, y: 0, width: 1_000, height: 500),
            renderedSize: CGSize(width: 300, height: 150)
        )
        XCTAssertEqual(result, CGRect(x: 30, y: 15, width: 120, height: 60))
    }

    func testInactiveTiledPreviewReconstructsFirstVisitFramesFromSavedTree() throws {
        let first = WindowKey(processIdentifier: 10, windowIdentifier: 100)
        let second = WindowKey(processIdentifier: 11, windowIdentifier: 200)
        let third = WindowKey(processIdentifier: 12, windowIdentifier: 300)
        let tree = TiledNode.split(
            axis: .horizontal,
            ratio: 0.64,
            first: .window(first),
            second: .split(
                axis: .vertical,
                ratio: 0.42,
                first: .window(second),
                second: .window(third)
            )
        )
        let configuration = WorkspaceLayoutConfiguration(
            orientation: .automatic,
            accordionPadding: 250,
            gaps: WorkspaceLayoutGaps(
                innerHorizontal: 12,
                innerVertical: 18,
                outerTop: 24,
                outerRight: 30,
                outerBottom: 36,
                outerLeft: 42
            )
        )
        let bounds = CGRect(x: -1_920, y: 25, width: 1_920, height: 1_055)
        let expected = try TiledLayoutEngine.frames(
            for: tree,
            in: bounds,
            configuration: configuration
        )

        XCTAssertEqual(
            WorkspaceEngine.inactiveWorkspaceLayoutFrames(
                layout: .tiled,
                orderedWindowKeys: [first, second, third],
                weights: [1, 1, 1],
                layoutBounds: bounds,
                layoutConfiguration: configuration,
                existingTiledTree: tree,
                accordionFocusedIndex: nil
            ),
            expected
        )
    }

    func testStartupInactiveWorkspaceSizingRequiresAParkedResizableLayoutParticipant() {
        func shouldResize(
            isEnabled: Bool = true,
            isWorkspaceActive: Bool = false,
            layout: WorkspaceLayout = .tiled,
            includesInLayout: Bool = true,
            writeMode: WindowGeometryWriteMode = .frame,
            isWriteDeferred: Bool = false,
            hasFullscreenSession: Bool = false,
            isMeaningfullyVisible: Bool = false,
            currentSize: CGSize = CGSize(width: 1_200, height: 800),
            targetSize: CGSize = CGSize(width: 1_913, height: 1_582)
        ) -> Bool {
            StartupInactiveWorkspaceSizingPolicy.shouldResize(
                isEnabled: isEnabled,
                isWorkspaceActive: isWorkspaceActive,
                layout: layout,
                includesInLayout: includesInLayout,
                writeMode: writeMode,
                isWriteDeferred: isWriteDeferred,
                hasFullscreenSession: hasFullscreenSession,
                isMeaningfullyVisible: isMeaningfullyVisible,
                currentSize: currentSize,
                targetSize: targetSize
            )
        }

        XCTAssertTrue(shouldResize())
        XCTAssertTrue(shouldResize(layout: .accordion))
        XCTAssertFalse(shouldResize(isEnabled: false))
        XCTAssertFalse(shouldResize(isWorkspaceActive: true))
        XCTAssertFalse(shouldResize(layout: .none))
        XCTAssertFalse(shouldResize(includesInLayout: false))
        XCTAssertFalse(shouldResize(writeMode: .positionOnly))
        XCTAssertFalse(shouldResize(isWriteDeferred: true))
        XCTAssertFalse(shouldResize(hasFullscreenSession: true))
        XCTAssertFalse(shouldResize(isMeaningfullyVisible: true))
        XCTAssertFalse(shouldResize(targetSize: CGSize(width: 1_200, height: 800)))
    }

    func testStartupInactiveWorkspaceSizingMessagesRotateDeterministically() {
        let messages = StartupInactiveWorkspaceSizingPolicy.messages
        XCTAssertGreaterThan(messages.count, 1)
        XCTAssertTrue(messages.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(
            Set((0..<messages.count).map(StartupInactiveWorkspaceSizingPolicy.message(seed:))),
            Set(messages)
        )
        XCTAssertEqual(
            StartupInactiveWorkspaceSizingPolicy.message(seed: messages.count),
            messages[0]
        )
    }

    func testThumbnailCaptureSizePreservesEachWindowAspectRatioWithinBudget() {
        XCTAssertEqual(
            WorkspacePreviewGeometry.thumbnailSize(
                for: CGSize(width: 3_840, height: 3_240),
                fitting: CGSize(width: 320, height: 200)
            ),
            CGSize(width: 237, height: 200)
        )
        XCTAssertEqual(
            WorkspacePreviewGeometry.thumbnailSize(
                for: CGSize(width: 3_840, height: 1_620),
                fitting: CGSize(width: 320, height: 200)
            ),
            CGSize(width: 320, height: 135)
        )
        XCTAssertEqual(
            WorkspacePreviewGeometry.thumbnailSize(
                for: CGSize(width: 0, height: 1_620),
                fitting: CGSize(width: 320, height: 200)
            ),
            CGSize(width: 1, height: 1)
        )
    }

    func testCanvasUsesWorkspaceHomeDisplayInsteadOfDisplayUnion() {
        let main = DisplaySnapshot(
            identifier: "main",
            bounds: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            isMain: true,
            name: "Built-in Display"
        )
        let external = DisplaySnapshot(
            identifier: "external",
            bounds: CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080),
            isMain: false,
            name: "External Display"
        )

        XCTAssertEqual(
            WorkspacePreviewGeometry.canvasFrame(
                homeDisplayIdentifier: external.identifier,
                displays: [main, external],
                fallbackItemFrames: []
            ),
            external.bounds
        )
        XCTAssertEqual(
            WorkspacePreviewGeometry.canvasFrame(
                homeDisplayIdentifier: "disconnected",
                displays: [main, external],
                fallbackItemFrames: []
            ),
            main.bounds
        )
        XCTAssertEqual(
            WorkspacePreviewGeometry.canvasDisplay(
                homeDisplayIdentifier: external.identifier,
                displays: [main, external]
            )?.identifier,
            external.identifier
        )
    }

    func testHomeDisplayCoordinatesPreserveWindowPositionAndExcludeOtherScreens() {
        let canvas = CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080)
        let result = WorkspacePreviewGeometry.rect(
            CGRect(x: -1_824, y: 108, width: 960, height: 540),
            in: canvas,
            renderedSize: CGSize(width: 320, height: 180)
        )

        XCTAssertEqual(result, CGRect(x: 16, y: 18, width: 160, height: 90))
        XCTAssertTrue(WorkspacePreviewGeometry.intersectsCanvas(
            CGRect(x: -1_824, y: 108, width: 960, height: 540),
            canvasFrame: canvas
        ))
        XCTAssertFalse(WorkspacePreviewGeometry.intersectsCanvas(
            CGRect(x: 100, y: 100, width: 800, height: 600),
            canvasFrame: canvas
        ))
    }

    func testInitializationPreflightsButNeverRequestsPermission() {
        let counter = PreviewPermissionCallCounter()
        let provider = WorkspacePreviewPermissionProvider(
            preflight: { counter.recordPreflight(); return false },
            request: { counter.recordRequest(); return true },
            openSettings: {}
        )
        _ = WorkspacePreviewRepository(capturer: FakeCapturer(), permissionProvider: provider)
        XCTAssertEqual(counter.preflightCalls, 1)
        XCTAssertEqual(counter.requestCalls, 0)
    }

    func testDisabledAndDeniedRepositoriesPublishMetadataFallbackOnly() async {
        let capturer = FakeCapturer()
        let disabled = WorkspacePreviewRepository(isEnabled: false, capturer: capturer, permissionProvider: deniedProvider())
        disabled.update(descriptor: descriptor())
        let denied = WorkspacePreviewRepository(isEnabled: true, capturer: capturer, permissionProvider: deniedProvider())
        denied.update(descriptor: descriptor(workspaceID: UUID()))
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(capturer.calls, 0)
        XCTAssertNotNil(disabled.entry(for: descriptor().workspaceID))
        XCTAssertTrue(disabled.entry(for: descriptor().workspaceID)?.images.isEmpty == true)
    }

    func testAuthorizedEmptyWorkspaceDoesNotEnumerateCaptureSources() async {
        let capturer = FakeCapturer()
        let repository = WorkspacePreviewRepository(
            isEnabled: true,
            capturer: capturer,
            permissionProvider: WorkspacePreviewPermissionProvider(
                preflight: { true },
                request: { true },
                openSettings: {}
            )
        )
        let empty = WorkspacePreviewDescriptor(
            workspaceID: UUID(),
            name: "Empty",
            canvasFrame: CGRect(x: 0, y: 0, width: 1_000, height: 500),
            items: []
        )

        repository.update(descriptor: empty)
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(capturer.calls, 0)
        XCTAssertEqual(repository.entry(for: empty.workspaceID)?.descriptor, empty)
    }

    func testAuthorizedEmptyWorkspaceLoadsBoundedWallpaperWithoutEnumeratingWindows() async {
        let capturer = FakeCapturer()
        let wallpaperProvider = FakeWallpaperProvider()
        let repository = WorkspacePreviewRepository(
            isEnabled: true,
            capturer: capturer,
            wallpaperProvider: wallpaperProvider,
            permissionProvider: WorkspacePreviewPermissionProvider(
                preflight: { true },
                request: { true },
                openSettings: {}
            ),
            maximumByteCount: 16
        )
        let empty = WorkspacePreviewDescriptor(
            workspaceID: UUID(),
            name: "Empty",
            canvasFrame: CGRect(x: 0, y: 0, width: 1_000, height: 500),
            displayIdentifier: "display",
            items: []
        )

        repository.update(descriptor: empty)
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(capturer.calls, 0)
        XCTAssertEqual(wallpaperProvider.calls, 1)
        XCTAssertNotNil(repository.entry(for: empty.workspaceID)?.background)
        XCTAssertEqual(repository.entry(for: empty.workspaceID)?.approximateByteCount, 16)
    }

    func testWallpaperRendererProducesOnlyFinalPreviewSizedPixels() throws {
        let source = try XCTUnwrap(testPreviewImage())
        let rendered = try XCTUnwrap(WorkspacePreviewWallpaperRenderer.render(
            source,
            width: 8,
            height: 4,
            contentMode: .fill
        ))

        XCTAssertEqual(rendered.width, 8)
        XCTAssertEqual(rendered.height, 4)
        XCTAssertEqual(rendered.bytesPerRow * rendered.height, 128)
    }

    func testCacheEvictsLeastRecentlyUsedMetadataEntriesAtHardCountBound() {
        let repository = WorkspacePreviewRepository(
            capturer: FakeCapturer(),
            permissionProvider: deniedProvider(),
            maximumEntryCount: 2
        )
        let first = descriptor(workspaceID: UUID())
        let second = descriptor(workspaceID: UUID())
        let third = descriptor(workspaceID: UUID())
        repository.update(descriptor: first)
        repository.update(descriptor: second)
        _ = repository.entry(for: first.workspaceID)
        repository.update(descriptor: third)
        XCTAssertNotNil(repository.entry(for: first.workspaceID))
        XCTAssertNil(repository.entry(for: second.workspaceID))
        XCTAssertNotNil(repository.entry(for: third.workspaceID))
    }

    func testCapturedPixelsCannotExceedHardByteBound() async {
        let repository = WorkspacePreviewRepository(
            isEnabled: true,
            capturer: ImageCapturer(),
            permissionProvider: WorkspacePreviewPermissionProvider(
                preflight: { true },
                request: { true },
                openSettings: {}
            ),
            maximumByteCount: 0
        )
        let descriptor = descriptor()

        repository.update(descriptor: descriptor)
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertNotNil(repository.entry(for: descriptor.workspaceID))
        XCTAssertTrue(repository.entry(for: descriptor.workspaceID)?.images.isEmpty == true)
    }

    func testRepositoryPassesPerWorkspaceCaptureBudgets() async {
        let capturer = BudgetRecordingCapturer()
        let repository = WorkspacePreviewRepository(
            isEnabled: true,
            capturer: capturer,
            permissionProvider: WorkspacePreviewPermissionProvider(
                preflight: { true },
                request: { true },
                openSettings: {}
            ),
            maximumByteCount: 1_234,
            maximumCapturedItemCountPerWorkspace: 2
        )

        repository.update(descriptor: descriptor())
        await capturer.waitUntilCalled()

        XCTAssertEqual(capturer.maximumItemCount, 2)
        XCTAssertEqual(capturer.maximumByteCount, 1_234)
    }

    func testOverlappingWorkspaceRequestsSerializeAndReserveBytesAtStart() async {
        let capturer = BlockingImageCapturer()
        let repository = WorkspacePreviewRepository(
            isEnabled: true,
            capturer: capturer,
            permissionProvider: WorkspacePreviewPermissionProvider(
                preflight: { true },
                request: { true },
                openSettings: {}
            ),
            maximumByteCount: 16
        )
        let first = descriptor(workspaceID: UUID())
        let second = descriptor(workspaceID: UUID())

        repository.update(descriptor: first)
        await capturer.waitUntilFirstCaptureStarts()
        repository.update(descriptor: second)
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(capturer.calls, 1)

        capturer.releaseFirstCapture()
        try? await Task.sleep(for: .milliseconds(40))

        XCTAssertEqual(capturer.calls, 1)
        XCTAssertEqual(repository.entry(for: first.workspaceID)?.images.count, 1)
        XCTAssertTrue(repository.entry(for: second.workspaceID)?.images.isEmpty == true)
    }

    func testPurgeDefersReplacementWithoutOverlappingNonCooperativeCapture() async {
        let capturer = BlockingImageCapturer()
        let repository = WorkspacePreviewRepository(
            isEnabled: true,
            capturer: capturer,
            permissionProvider: WorkspacePreviewPermissionProvider(
                preflight: { true },
                request: { true },
                openSettings: {}
            ),
            maximumByteCount: 16
        )
        let stale = descriptor(workspaceID: UUID())
        let replacement = descriptor(workspaceID: UUID())

        repository.update(descriptor: stale)
        await capturer.waitUntilFirstCaptureStarts()
        repository.purge()
        repository.update(descriptor: replacement)
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(capturer.calls, 1)
        XCTAssertNotNil(repository.entry(for: replacement.workspaceID))
        XCTAssertTrue(repository.entry(for: replacement.workspaceID)?.images.isEmpty == true)

        capturer.releaseFirstCapture()
        try? await Task.sleep(for: .milliseconds(40))
        XCTAssertNil(repository.entry(for: stale.workspaceID))
        XCTAssertEqual(capturer.calls, 2)
        XCTAssertEqual(repository.entry(for: replacement.workspaceID)?.images.count, 1)
    }

    func testSemanticInvalidationRemovesOnlyChangedWorkspaces() {
        let repository = WorkspacePreviewRepository(
            capturer: FakeCapturer(),
            permissionProvider: deniedProvider()
        )
        let changed = descriptor(workspaceID: UUID())
        let untouched = descriptor(workspaceID: UUID())
        repository.update(descriptor: changed)
        repository.update(descriptor: untouched)

        repository.invalidate(workspaceIDs: [changed.workspaceID])

        XCTAssertEqual(repository.invalidationGeneration, 1)
        XCTAssertNil(repository.entry(for: changed.workspaceID))
        XCTAssertNotNil(repository.entry(for: untouched.workspaceID))
    }

    func testExplicitPermissionRequestAndLaterRevocationPurgeCapturedPixels() async {
        let permission = MutablePreviewPermission(isGranted: false)
        let repository = WorkspacePreviewRepository(
            isEnabled: true,
            capturer: ImageCapturer(),
            permissionProvider: WorkspacePreviewPermissionProvider(
                preflight: { permission.isGranted },
                request: { permission.grant(); return true },
                openSettings: {}
            )
        )
        XCTAssertEqual(permission.requestCalls, 0)
        repository.requestAuthorizationFromUser()
        XCTAssertEqual(permission.requestCalls, 1)
        XCTAssertEqual(repository.authorization, .authorized)

        let descriptor = descriptor()
        repository.update(descriptor: descriptor)
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(repository.entry(for: descriptor.workspaceID)?.images.count, 1)

        permission.revoke()
        repository.refreshAuthorization()
        XCTAssertEqual(repository.authorization, .denied)
        XCTAssertTrue(repository.entry(for: descriptor.workspaceID)?.images.isEmpty == true)
    }

    func testPermissionRevocationPurgesWallpaperPixels() async {
        let permission = MutablePreviewPermission(isGranted: true)
        let wallpaperProvider = FakeWallpaperProvider()
        let repository = WorkspacePreviewRepository(
            isEnabled: true,
            capturer: FakeCapturer(),
            wallpaperProvider: wallpaperProvider,
            permissionProvider: WorkspacePreviewPermissionProvider(
                preflight: { permission.isGranted },
                request: { permission.isGranted },
                openSettings: {}
            )
        )
        let descriptor = WorkspacePreviewDescriptor(
            workspaceID: UUID(),
            name: "Wallpaper",
            canvasFrame: CGRect(x: 0, y: 0, width: 1_000, height: 500),
            displayIdentifier: "display",
            items: []
        )

        repository.update(descriptor: descriptor)
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertNotNil(repository.entry(for: descriptor.workspaceID)?.background)

        permission.revoke()
        repository.refreshAuthorization()
        XCTAssertNil(repository.entry(for: descriptor.workspaceID)?.background)
        XCTAssertEqual(wallpaperProvider.purgeCalls, 1)
    }

    func testLateCancelledCaptureCannotOverwriteNewerDescriptor() async {
        let capturer = DelayedFirstCapturer()
        let repository = WorkspacePreviewRepository(
            isEnabled: true,
            capturer: capturer,
            permissionProvider: WorkspacePreviewPermissionProvider(
                preflight: { true },
                request: { true },
                openSettings: {}
            )
        )
        let original = descriptor()
        let changed = WorkspacePreviewDescriptor(
            workspaceID: original.workspaceID,
            name: original.name,
            canvasFrame: original.canvasFrame,
            items: original.items.map {
                WorkspacePreviewItemDescriptor(
                    key: $0.key,
                    applicationTarget: $0.applicationTarget,
                    name: $0.name,
                    applicationURL: $0.applicationURL,
                    frame: $0.frame.offsetBy(dx: 25, dy: 0)
                )
            }
        )
        repository.update(descriptor: original)
        await capturer.waitUntilFirstCaptureStarts()
        repository.update(descriptor: changed)
        try? await Task.sleep(for: .milliseconds(90))

        XCTAssertEqual(repository.entry(for: original.workspaceID)?.descriptor, changed)
        XCTAssertTrue(repository.entry(for: original.workspaceID)?.images.isEmpty == true)
    }

    private func deniedProvider() -> WorkspacePreviewPermissionProvider {
        WorkspacePreviewPermissionProvider(preflight: { false }, request: { false }, openSettings: {})
    }

    private func descriptor(workspaceID: UUID = UUID(uuidString: "10000000-0000-0000-0000-000000000100")!) -> WorkspacePreviewDescriptor {
        let key = WindowKey(processIdentifier: 10, windowIdentifier: 20)
        return WorkspacePreviewDescriptor(
            workspaceID: workspaceID,
            name: "Writing",
            canvasFrame: CGRect(x: 0, y: 0, width: 1_000, height: 500),
            items: [WorkspacePreviewItemDescriptor(
                key: key,
                applicationTarget: WorkspaceApplicationTarget(workspaceID: workspaceID, bundleIdentifier: "com.example.app", processIdentifier: 10),
                name: "Example",
                applicationURL: nil,
                frame: CGRect(x: 50, y: 50, width: 300, height: 200)
            )]
        )
    }
}

@MainActor
private final class FakeCapturer: WorkspacePreviewCapturing {
    private(set) var calls = 0

    func capture(
        items: [WorkspacePreviewItemDescriptor],
        maximumSize: CGSize,
        maximumItemCount: Int,
        maximumByteCount: Int
    ) async -> [WindowKey: WorkspacePreviewThumbnail] {
        calls += 1
        return [:]
    }
}

@MainActor
private final class FakeWallpaperProvider: WorkspacePreviewWallpaperProviding {
    private(set) var calls = 0
    private(set) var purgeCalls = 0

    func wallpaper(
        for displayIdentifier: String,
        canvasSize: CGSize,
        maximumSize: CGSize
    ) async -> WorkspacePreviewThumbnail? {
        calls += 1
        return testPreviewImage().map(WorkspacePreviewThumbnail.init(image:))
    }

    func purge() {
        purgeCalls += 1
    }
}

private final class PreviewPermissionCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var preflights = 0
    private var requests = 0

    var preflightCalls: Int { lock.withLock { preflights } }
    var requestCalls: Int { lock.withLock { requests } }

    func recordPreflight() { lock.withLock { preflights += 1 } }
    func recordRequest() { lock.withLock { requests += 1 } }
}

private final class MutablePreviewPermission: @unchecked Sendable {
    private let lock = NSLock()
    private var granted: Bool
    private var requests = 0

    init(isGranted: Bool) { granted = isGranted }
    var isGranted: Bool { lock.withLock { granted } }
    var requestCalls: Int { lock.withLock { requests } }
    func grant() { lock.withLock { requests += 1; granted = true } }
    func revoke() { lock.withLock { granted = false } }
}

@MainActor
private final class ImageCapturer: WorkspacePreviewCapturing {
    func capture(
        items: [WorkspacePreviewItemDescriptor],
        maximumSize: CGSize,
        maximumItemCount: Int,
        maximumByteCount: Int
    ) async -> [WindowKey: WorkspacePreviewThumbnail] {
        guard let item = items.first, let image = testPreviewImage() else { return [:] }
        return [item.key: WorkspacePreviewThumbnail(image: image)]
    }
}

@MainActor
private final class DelayedFirstCapturer: WorkspacePreviewCapturing {
    private var callCount = 0
    private var firstCaptureStarted = false
    private var firstCaptureContinuation: CheckedContinuation<Void, Never>?

    func waitUntilFirstCaptureStarts() async {
        guard !firstCaptureStarted else { return }
        await withCheckedContinuation { continuation in
            firstCaptureContinuation = continuation
        }
    }

    func capture(
        items: [WorkspacePreviewItemDescriptor],
        maximumSize: CGSize,
        maximumItemCount: Int,
        maximumByteCount: Int
    ) async -> [WindowKey: WorkspacePreviewThumbnail] {
        callCount += 1
        guard callCount == 1 else { return [:] }
        firstCaptureStarted = true
        firstCaptureContinuation?.resume()
        firstCaptureContinuation = nil
        try? await Task.sleep(for: .milliseconds(60))
        guard let item = items.first, let image = testPreviewImage() else { return [:] }
        return [item.key: WorkspacePreviewThumbnail(image: image)]
    }
}

@MainActor
private final class BudgetRecordingCapturer: WorkspacePreviewCapturing {
    private(set) var maximumItemCount: Int?
    private(set) var maximumByteCount: Int?
    private var continuation: CheckedContinuation<Void, Never>?

    func waitUntilCalled() async {
        guard maximumItemCount == nil else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func capture(
        items: [WorkspacePreviewItemDescriptor],
        maximumSize: CGSize,
        maximumItemCount: Int,
        maximumByteCount: Int
    ) async -> [WindowKey: WorkspacePreviewThumbnail] {
        self.maximumItemCount = maximumItemCount
        self.maximumByteCount = maximumByteCount
        continuation?.resume()
        continuation = nil
        return [:]
    }
}

@MainActor
private final class BlockingImageCapturer: WorkspacePreviewCapturing {
    private(set) var calls = 0
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var firstCaptureStarted = false

    func waitUntilFirstCaptureStarts() async {
        guard !firstCaptureStarted else { return }
        await withCheckedContinuation { startedContinuation = $0 }
    }

    func releaseFirstCapture() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func capture(
        items: [WorkspacePreviewItemDescriptor],
        maximumSize: CGSize,
        maximumItemCount: Int,
        maximumByteCount: Int
    ) async -> [WindowKey: WorkspacePreviewThumbnail] {
        calls += 1
        if calls == 1 {
            firstCaptureStarted = true
            startedContinuation?.resume()
            startedContinuation = nil
            await withCheckedContinuation { releaseContinuation = $0 }
        }
        guard let item = items.first, let image = testPreviewImage() else { return [:] }
        return [item.key: WorkspacePreviewThumbnail(image: image)]
    }
}

private func testPreviewImage() -> CGImage? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: 2,
        height: 2,
        bitsPerComponent: 8,
        bytesPerRow: 8,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.setFillColor(NSColor.systemBlue.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
    return context.makeImage()
}
