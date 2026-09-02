import AppKit
import CoreGraphics
import ImageIO
import Observation
import ScreenCaptureKit
import SwiftUI

/// A stable, capture-independent description of one workspace. Frames use the same global
/// Quartz coordinate space as WindowRanger's tracked window frames.
struct WorkspacePreviewDescriptor: Identifiable, Sendable, Equatable {
    let workspaceID: UUID
    let name: String
    let canvasFrame: CGRect
    let displayIdentifier: String?
    let items: [WorkspacePreviewItemDescriptor]

    var id: UUID { workspaceID }

    init(
        workspaceID: UUID,
        name: String,
        canvasFrame: CGRect,
        displayIdentifier: String? = nil,
        items: [WorkspacePreviewItemDescriptor]
    ) {
        self.workspaceID = workspaceID
        self.name = name
        self.canvasFrame = canvasFrame
        self.displayIdentifier = displayIdentifier
        self.items = items
    }
}

struct WorkspacePreviewItemDescriptor: Identifiable, Sendable, Equatable {
    let key: WindowKey
    let applicationTarget: WorkspaceApplicationTarget
    let name: String
    let applicationURL: URL?
    let frame: CGRect

    var id: WindowKey { key }

    init(
        key: WindowKey,
        applicationTarget: WorkspaceApplicationTarget,
        name: String,
        applicationURL: URL?,
        frame: CGRect
    ) {
        self.key = key
        self.applicationTarget = applicationTarget
        self.name = name
        self.applicationURL = applicationURL
        self.frame = frame
    }
}

enum WorkspacePreviewInteractionMode: Sendable, Equatable {
    case workspaceOnly
    case itemsOnly
    case workspaceAndItems

    var acceptsWorkspace: Bool { self != .itemsOnly }
    var acceptsItems: Bool { self != .workspaceOnly }
}

enum WorkspacePreviewGeometry {
    static func canvasDisplay(
        homeDisplayIdentifier: String?,
        displays: [DisplaySnapshot]
    ) -> DisplaySnapshot? {
        if let homeDisplayIdentifier,
           let homeDisplay = displays.first(where: { $0.identifier == homeDisplayIdentifier }),
           homeDisplay.bounds.width > 0,
           homeDisplay.bounds.height > 0 {
            return homeDisplay
        }
        return (displays.first(where: \.isMain) ?? displays.first).flatMap { display in
            display.bounds.width > 0 && display.bounds.height > 0 ? display : nil
        }
    }

    static func thumbnailSize(for sourceSize: CGSize, fitting maximumSize: CGSize) -> CGSize {
        guard sourceSize.width.isFinite,
              sourceSize.height.isFinite,
              maximumSize.width.isFinite,
              maximumSize.height.isFinite,
              sourceSize.width > 0,
              sourceSize.height > 0,
              maximumSize.width > 0,
              maximumSize.height > 0
        else { return CGSize(width: 1, height: 1) }

        let scale = min(
            maximumSize.width / sourceSize.width,
            maximumSize.height / sourceSize.height
        )
        return CGSize(
            width: max(1, (sourceSize.width * scale).rounded(.down)),
            height: max(1, (sourceSize.height * scale).rounded(.down))
        )
    }

    static func canvasFrame(
        homeDisplayIdentifier: String?,
        displays: [DisplaySnapshot],
        fallbackItemFrames: [CGRect]
    ) -> CGRect {
        if let display = canvasDisplay(
            homeDisplayIdentifier: homeDisplayIdentifier,
            displays: displays
        ) {
            return display.bounds
        }
        let itemUnion = fallbackItemFrames.reduce(CGRect.null) { $0.union($1) }
        if !itemUnion.isNull, itemUnion.width > 0, itemUnion.height > 0 {
            return itemUnion
        }
        return CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    static func intersectsCanvas(_ itemFrame: CGRect, canvasFrame: CGRect) -> Bool {
        let intersection = itemFrame.intersection(canvasFrame)
        return !intersection.isNull && intersection.width > 0 && intersection.height > 0
    }

    static func rect(_ itemFrame: CGRect, in canvas: CGRect, renderedSize: CGSize) -> CGRect {
        guard canvas.width > 0, canvas.height > 0,
              renderedSize.width > 0, renderedSize.height > 0
        else { return .zero }
        return CGRect(
            x: (itemFrame.minX - canvas.minX) / canvas.width * renderedSize.width,
            y: (itemFrame.minY - canvas.minY) / canvas.height * renderedSize.height,
            width: itemFrame.width / canvas.width * renderedSize.width,
            height: itemFrame.height / canvas.height * renderedSize.height
        ).integral
    }
}

/// `CGImage` is only read and displayed on the main actor. This wrapper makes that ownership
/// explicit at asynchronous capture boundaries without making image data part of the descriptor.
struct WorkspacePreviewThumbnail: @unchecked Sendable {
    let image: CGImage

    var approximateByteCount: Int { image.bytesPerRow * image.height }
}

enum WorkspacePreviewWallpaperContentMode: Int, Sendable, Equatable {
    case fill
    case fit
    case stretch
}

struct WorkspacePreviewWallpaperRenderRequest: Sendable {
    let url: URL
    let width: Int
    let height: Int
    let contentMode: WorkspacePreviewWallpaperContentMode
    let fillRed: Double
    let fillGreen: Double
    let fillBlue: Double
    let fillAlpha: Double
}

enum WorkspacePreviewWallpaperRenderer {
    static func render(_ request: WorkspacePreviewWallpaperRenderRequest) -> WorkspacePreviewThumbnail? {
        guard request.width > 0,
              request.height > 0,
              let source = CGImageSourceCreateWithURL(request.url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let sourceWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let sourceHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              sourceWidth > 0,
              sourceHeight > 0
        else { return nil }

        let horizontalScale = Double(request.width) / sourceWidth
        let verticalScale = Double(request.height) / sourceHeight
        let renderScale: Double
        switch request.contentMode {
        case .fill:
            renderScale = max(horizontalScale, verticalScale)
        case .fit:
            renderScale = min(horizontalScale, verticalScale)
        case .stretch:
            renderScale = max(horizontalScale, verticalScale)
        }
        let requiredPixelSize = min(
            2_048,
            max(
                request.width,
                request.height,
                Int(ceil(max(sourceWidth * renderScale, sourceHeight * renderScale)))
            )
        )
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceThumbnailMaxPixelSize: requiredPixelSize,
        ]
        guard let sourceImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions as CFDictionary
        ), let image = render(
            sourceImage,
            width: request.width,
            height: request.height,
            contentMode: request.contentMode,
            fillRed: request.fillRed,
            fillGreen: request.fillGreen,
            fillBlue: request.fillBlue,
            fillAlpha: request.fillAlpha
        ) else { return nil }
        return WorkspacePreviewThumbnail(image: image)
    }

    static func render(
        _ sourceImage: CGImage,
        width: Int,
        height: Int,
        contentMode: WorkspacePreviewWallpaperContentMode,
        fillRed: Double = 0,
        fillGreen: Double = 0,
        fillBlue: Double = 0,
        fillAlpha: Double = 1
    ) -> CGImage? {
        guard width > 0,
              height > 0,
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        context.setFillColor(
            red: CGFloat(fillRed),
            green: CGFloat(fillGreen),
            blue: CGFloat(fillBlue),
            alpha: CGFloat(fillAlpha)
        )
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high

        let outputSize = CGSize(width: width, height: height)
        let sourceSize = CGSize(width: sourceImage.width, height: sourceImage.height)
        let destination: CGRect
        switch contentMode {
        case .stretch:
            destination = CGRect(origin: .zero, size: outputSize)
        case .fill, .fit:
            let horizontalScale = outputSize.width / sourceSize.width
            let verticalScale = outputSize.height / sourceSize.height
            let scale = contentMode == .fill
                ? max(horizontalScale, verticalScale)
                : min(horizontalScale, verticalScale)
            let size = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
            destination = CGRect(
                x: (outputSize.width - size.width) / 2,
                y: (outputSize.height - size.height) / 2,
                width: size.width,
                height: size.height
            )
        }
        context.draw(sourceImage, in: destination)
        return context.makeImage()
    }
}

@MainActor
protocol WorkspacePreviewWallpaperProviding {
    func wallpaper(
        for displayIdentifier: String,
        canvasSize: CGSize,
        maximumSize: CGSize
    ) async -> WorkspacePreviewThumbnail?

    func purge()
}

@MainActor
final class DesktopWorkspacePreviewWallpaperProvider: WorkspacePreviewWallpaperProviding {
    private struct CacheKey: Equatable {
        let url: URL
        let width: Int
        let height: Int
        let contentMode: WorkspacePreviewWallpaperContentMode
        let fillRed: Double
        let fillGreen: Double
        let fillBlue: Double
        let fillAlpha: Double
    }

    private var cache: [String: (key: CacheKey, thumbnail: WorkspacePreviewThumbnail)] = [:]

    func wallpaper(
        for displayIdentifier: String,
        canvasSize: CGSize,
        maximumSize: CGSize
    ) async -> WorkspacePreviewThumbnail? {
        guard let screen = Self.screen(for: displayIdentifier),
              let url = NSWorkspace.shared.desktopImageURL(for: screen)
        else {
            cache.removeValue(forKey: displayIdentifier)
            return nil
        }

        let outputSize = WorkspacePreviewGeometry.thumbnailSize(
            for: canvasSize,
            fitting: maximumSize
        )
        let options = NSWorkspace.shared.desktopImageOptions(for: screen)
        let allowsClipping = (options?[.allowClipping] as? NSNumber)?.boolValue ?? true
        let scalingRawValue = (options?[.imageScaling] as? NSNumber)?.uintValue
        let contentMode: WorkspacePreviewWallpaperContentMode
        if scalingRawValue == NSImageScaling.scaleAxesIndependently.rawValue {
            contentMode = .stretch
        } else {
            contentMode = allowsClipping ? .fill : .fit
        }
        let color = ((options?[.fillColor] as? NSColor) ?? .black)
            .usingColorSpace(.deviceRGB) ?? .black
        let key = CacheKey(
            url: url,
            width: Int(outputSize.width),
            height: Int(outputSize.height),
            contentMode: contentMode,
            fillRed: Double(color.redComponent),
            fillGreen: Double(color.greenComponent),
            fillBlue: Double(color.blueComponent),
            fillAlpha: Double(color.alphaComponent)
        )
        if let cached = cache[displayIdentifier], cached.key == key {
            return cached.thumbnail
        }

        let request = WorkspacePreviewWallpaperRenderRequest(
            url: key.url,
            width: key.width,
            height: key.height,
            contentMode: key.contentMode,
            fillRed: key.fillRed,
            fillGreen: key.fillGreen,
            fillBlue: key.fillBlue,
            fillAlpha: key.fillAlpha
        )
        let thumbnail = await Task.detached(priority: .utility) {
            WorkspacePreviewWallpaperRenderer.render(request)
        }.value
        if let thumbnail {
            cache[displayIdentifier] = (key, thumbnail)
        } else {
            cache.removeValue(forKey: displayIdentifier)
        }
        return thumbnail
    }

    func purge() {
        cache.removeAll()
    }

    private static func screen(for identifier: String) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else { return false }
            let displayID = CGDirectDisplayID(number.uint32Value)
            if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
                return (CFUUIDCreateString(nil, uuid) as String) == identifier
            }
            return "session-display-\(displayID)" == identifier
        }
    }
}

@MainActor
protocol WorkspacePreviewCapturing {
    /// One batch means shareable-content enumeration happens at most once per workspace update.
    func capture(
        items: [WorkspacePreviewItemDescriptor],
        maximumSize: CGSize,
        maximumItemCount: Int,
        maximumByteCount: Int
    ) async -> [WindowKey: WorkspacePreviewThumbnail]
}

@MainActor
final class ScreenCaptureKitWorkspacePreviewCapturer: WorkspacePreviewCapturing {
    func capture(
        items: [WorkspacePreviewItemDescriptor],
        maximumSize: CGSize,
        maximumItemCount: Int,
        maximumByteCount: Int
    ) async -> [WindowKey: WorkspacePreviewThumbnail] {
        guard maximumSize.width > 0,
              maximumSize.height > 0,
              maximumItemCount > 0,
              maximumByteCount > 0
        else { return [:] }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                true,
                onScreenWindowsOnly: false
            )
            let windows: [WindowKey: SCWindow] = Dictionary(uniqueKeysWithValues: content.windows.compactMap { window in
                guard let processIdentifier = window.owningApplication?.processID else { return nil }
                return (WindowKey(processIdentifier: processIdentifier, windowIdentifier: window.windowID), window)
            })
            var results: [WindowKey: WorkspacePreviewThumbnail] = [:]
            var capturedByteCount = 0
            for item in items.prefix(maximumItemCount) {
                guard !Task.isCancelled else { break }
                guard let window = windows[item.key] else { continue }
                do {
                    // Match the pixel buffer to the frame rendered by the preview. Asking
                    // ScreenCaptureKit for one fixed aspect ratio causes it to letterbox windows
                    // whose shape differs, leaving visible empty bars in the composed desktop.
                    let captureSize = WorkspacePreviewGeometry.thumbnailSize(
                        for: item.frame.size,
                        fitting: maximumSize
                    )
                    let configuration = SCStreamConfiguration()
                    configuration.width = Int(captureSize.width)
                    configuration.height = Int(captureSize.height)
                    configuration.scalesToFit = true
                    configuration.preservesAspectRatio = true
                    configuration.showsCursor = false
                    configuration.capturesAudio = false
                    configuration.ignoreShadowsSingleWindow = true
                    configuration.ignoreGlobalClipSingleWindow = true
                    let image = try await SCScreenshotManager.captureImage(
                        contentFilter: SCContentFilter(desktopIndependentWindow: window),
                        configuration: configuration
                    )
                    let thumbnail = WorkspacePreviewThumbnail(image: image)
                    guard capturedByteCount + thumbnail.approximateByteCount <= maximumByteCount else {
                        break
                    }
                    results[item.key] = thumbnail
                    capturedByteCount += thumbnail.approximateByteCount
                } catch {
                    // A single protected or stale window is just a placeholder; continue the batch.
                }
            }
            return results
        } catch {
            // Capture failure is intentionally a privacy-safe placeholder, never a user-visible error.
            return [:]
        }
    }
}

enum WorkspacePreviewScreenRecordingAuthorization: Sendable, Equatable {
    case authorized
    case denied
    case unknown
}

/// Permission policy is deliberately injectable so preview rendering never causes TCC work.
struct WorkspacePreviewPermissionProvider {
    let preflight: @Sendable () -> Bool
    let request: @Sendable () -> Bool
    let openSettings: @Sendable () -> Void

    init(
        preflight: @escaping @Sendable () -> Bool = { CGPreflightScreenCaptureAccess() },
        request: @escaping @Sendable () -> Bool = { CGRequestScreenCaptureAccess() },
        openSettings: @escaping @Sendable () -> Void = {
            guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
            NSWorkspace.shared.open(url)
        }
    ) {
        self.preflight = preflight
        self.request = request
        self.openSettings = openSettings
    }

    func currentAuthorization() -> WorkspacePreviewScreenRecordingAuthorization {
        preflight() ? .authorized : .denied
    }

    /// The only API that is permitted to prompt. Call it exclusively from an explicit user action.
    func requestAuthorizationFromUser() -> WorkspacePreviewScreenRecordingAuthorization {
        request() ? .authorized : currentAuthorization()
    }
}

@MainActor
@Observable
final class WorkspacePreviewPermissionMonitor {
    private let provider: WorkspacePreviewPermissionProvider
    private(set) var authorization: WorkspacePreviewScreenRecordingAuthorization

    init(
        provider: WorkspacePreviewPermissionProvider = WorkspacePreviewPermissionProvider(),
        initialAuthorization: WorkspacePreviewScreenRecordingAuthorization? = nil
    ) {
        self.provider = provider
        // This is a preflight only; construction must not cause a permission prompt.
        authorization = initialAuthorization ?? provider.currentAuthorization()
    }

    func refresh() {
        authorization = provider.currentAuthorization()
    }

    func requestAuthorizationFromUser() {
        authorization = provider.requestAuthorizationFromUser()
    }

    func openSettings() {
        provider.openSettings()
    }
}

@MainActor
@Observable
final class WorkspacePreviewRepository {
    struct Entry {
        let descriptor: WorkspacePreviewDescriptor
        var background: WorkspacePreviewThumbnail?
        var images: [WindowKey: WorkspacePreviewThumbnail]
        var lastAccess: UInt64

        var approximateByteCount: Int {
            (background?.approximateByteCount ?? 0)
                + images.values.reduce(0) { $0 + $1.approximateByteCount }
        }
    }

    private(set) var entries: [UUID: Entry] = [:]
    private(set) var authorization: WorkspacePreviewScreenRecordingAuthorization
    private(set) var invalidationGeneration: UInt64 = 0
    var isEnabled: Bool

    private let capturer: any WorkspacePreviewCapturing
    private let wallpaperProvider: any WorkspacePreviewWallpaperProviding
    let permissionMonitor: WorkspacePreviewPermissionMonitor
    private let maximumEntryCount: Int
    private let maximumByteCount: Int
    private let maximumCapturedItemCountPerWorkspace: Int
    private let thumbnailMaximumSize: CGSize
    private var accessCounter: UInt64 = 0
    private var generations: [UUID: UInt64] = [:]
    private var captureTasks: [UUID: Task<Void, Never>] = [:]
    private var captureTail: Task<Void, Never>?
    private var captureLaneGeneration: UInt64 = 0
    private var activeCaptureLaneGeneration: UInt64?
    private var deferredCaptureDescriptors: [UUID: WorkspacePreviewDescriptor] = [:]

    init(
        isEnabled: Bool = false,
        capturer: (any WorkspacePreviewCapturing)? = nil,
        wallpaperProvider: (any WorkspacePreviewWallpaperProviding)? = nil,
        permissionProvider: WorkspacePreviewPermissionProvider = WorkspacePreviewPermissionProvider(),
        maximumEntryCount: Int = 16,
        maximumByteCount: Int = 24 * 1024 * 1024,
        maximumCapturedItemCountPerWorkspace: Int = 32,
        thumbnailMaximumSize: CGSize = CGSize(width: 320, height: 200)
    ) {
        self.isEnabled = isEnabled
        self.capturer = capturer ?? ScreenCaptureKitWorkspacePreviewCapturer()
        self.wallpaperProvider = wallpaperProvider ?? DesktopWorkspacePreviewWallpaperProvider()
        // Do not read an @Observable getter while constructing another @Observable object. Under
        // Release optimization that can enter the nested object's registrar before it is valid.
        let initialAuthorization = permissionProvider.currentAuthorization()
        let permissionMonitor = WorkspacePreviewPermissionMonitor(
            provider: permissionProvider,
            initialAuthorization: initialAuthorization
        )
        self.permissionMonitor = permissionMonitor
        self.maximumEntryCount = max(1, maximumEntryCount)
        self.maximumByteCount = max(0, maximumByteCount)
        self.maximumCapturedItemCountPerWorkspace = max(0, maximumCapturedItemCountPerWorkspace)
        self.thumbnailMaximumSize = thumbnailMaximumSize
        // Preflight is non-prompting. Initialization must never call `request`.
        authorization = initialAuthorization
    }

    func refreshAuthorization() {
        permissionMonitor.refresh()
        authorization = permissionMonitor.authorization
        if authorization != .authorized { purgeImages() }
    }

    func requestAuthorizationFromUser() {
        permissionMonitor.requestAuthorizationFromUser()
        authorization = permissionMonitor.authorization
        if authorization != .authorized { purgeImages() }
    }

    func openScreenRecordingSettings() {
        permissionMonitor.openSettings()
    }

    func entry(for workspaceID: UUID) -> Entry? {
        touch(workspaceID)
        return entries[workspaceID]
    }

    /// Publishes metadata immediately. Image enrichment is opt-in, authorization-gated, and
    /// does not retain any failed capture result.
    func update(descriptor: WorkspacePreviewDescriptor, captureEnabled: Bool = true) {
        let generation = nextGeneration(for: descriptor.workspaceID)
        captureTasks.removeValue(forKey: descriptor.workspaceID)?.cancel()
        accessCounter &+= 1
        let retainedImages = entries[descriptor.workspaceID]?.descriptor == descriptor
            ? entries[descriptor.workspaceID]?.images ?? [:]
            : [:]
        let retainedBackground = entries[descriptor.workspaceID]?.descriptor == descriptor
            ? entries[descriptor.workspaceID]?.background
            : nil
        entries[descriptor.workspaceID] = Entry(
            descriptor: descriptor,
            background: retainedBackground,
            // Keep a still-valid cache for a repeated render, but never place an old thumbnail
            // against changed window ownership or geometry.
            images: retainedImages,
            lastAccess: accessCounter
        )
        enforceBounds()
        let shouldCaptureWindows = retainedImages.isEmpty
            && !descriptor.items.isEmpty
            && maximumCapturedItemCountPerWorkspace > 0
        let shouldResolveWallpaper = descriptor.displayIdentifier != nil
        guard captureEnabled,
              isEnabled,
              authorization == .authorized,
              maximumByteCount > 0,
              shouldCaptureWindows || shouldResolveWallpaper
        else {
            deferredCaptureDescriptors.removeValue(forKey: descriptor.workspaceID)
            return
        }
        // A purged ScreenCaptureKit request may ignore Swift cancellation until the system call
        // returns. Keep publishing metadata, but do not overlap it with a new pixel reservation.
        guard activeCaptureLaneGeneration == nil
                || activeCaptureLaneGeneration == captureLaneGeneration
        else {
            deferredCaptureDescriptors[descriptor.workspaceID] = descriptor
            return
        }
        deferredCaptureDescriptors.removeValue(forKey: descriptor.workspaceID)
        let previousCapture = captureTail
        let laneGeneration = captureLaneGeneration
        let task = Task {
            [weak self, capturer, wallpaperProvider, thumbnailMaximumSize, maximumCapturedItemCountPerWorkspace] in
            await previousCapture?.value
            guard let self,
                  !Task.isCancelled,
                  self.captureLaneGeneration == laneGeneration,
                  self.generations[descriptor.workspaceID] == generation
            else { return }
            self.refreshAuthorization()
            guard self.authorization == .authorized else {
                self.completeRequest(for: descriptor.workspaceID, generation: generation)
                return
            }
            let retainedByteCount = self.entries
                .filter { $0.key != descriptor.workspaceID }
                .values
                .reduce(0) { $0 + $1.approximateByteCount }
            var availableByteCount = max(0, self.maximumByteCount - retainedByteCount)
            let retainedImageByteCount = retainedImages.values.reduce(0) {
                $0 + $1.approximateByteCount
            }
            guard retainedImageByteCount <= availableByteCount else {
                self.completeRequest(for: descriptor.workspaceID, generation: generation)
                return
            }
            availableByteCount -= retainedImageByteCount
            self.activeCaptureLaneGeneration = laneGeneration
            var background: WorkspacePreviewThumbnail?
            if let displayIdentifier = descriptor.displayIdentifier {
                let candidate = await wallpaperProvider.wallpaper(
                    for: displayIdentifier,
                    canvasSize: descriptor.canvasFrame.size,
                    maximumSize: thumbnailMaximumSize
                )
                if let candidate, candidate.approximateByteCount <= availableByteCount {
                    background = candidate
                    availableByteCount -= candidate.approximateByteCount
                }
            }
            let images: [WindowKey: WorkspacePreviewThumbnail]
            if shouldCaptureWindows, availableByteCount > 0 {
                images = await capturer.capture(
                    items: descriptor.items,
                    maximumSize: thumbnailMaximumSize,
                    maximumItemCount: maximumCapturedItemCountPerWorkspace,
                    maximumByteCount: availableByteCount
                )
            } else {
                images = retainedImages
            }
            self.finishCaptureLane(generation: laneGeneration)
            guard !Task.isCancelled,
                  self.captureLaneGeneration == laneGeneration,
                  self.generations[descriptor.workspaceID] == generation
            else { return }
            self.refreshAuthorization()
            guard self.authorization == .authorized else {
                self.completeRequest(for: descriptor.workspaceID, generation: generation)
                return
            }
            self.publish(
                background: background,
                images: images,
                for: descriptor,
                generation: generation
            )
            self.completeRequest(for: descriptor.workspaceID, generation: generation)
        }
        captureTasks[descriptor.workspaceID] = task
        captureTail = task
    }

    func invalidate(_ workspaceID: UUID) {
        captureTasks.removeValue(forKey: workspaceID)?.cancel()
        deferredCaptureDescriptors.removeValue(forKey: workspaceID)
        _ = nextGeneration(for: workspaceID)
        entries[workspaceID]?.background = nil
        entries[workspaceID]?.images = [:]
    }

    func invalidate(workspaceIDs: Set<UUID>) {
        guard !workspaceIDs.isEmpty else { return }
        for workspaceID in workspaceIDs {
            captureTasks.removeValue(forKey: workspaceID)?.cancel()
            deferredCaptureDescriptors.removeValue(forKey: workspaceID)
            _ = nextGeneration(for: workspaceID)
            entries.removeValue(forKey: workspaceID)
        }
        invalidationGeneration &+= 1
    }

    func purgeImages() {
        deferredCaptureDescriptors.removeAll()
        for key in entries.keys {
            captureTasks.removeValue(forKey: key)?.cancel()
            _ = nextGeneration(for: key)
            entries[key]?.background = nil
            entries[key]?.images = [:]
        }
        wallpaperProvider.purge()
        resetCaptureLane()
    }

    func purge() {
        deferredCaptureDescriptors.removeAll()
        captureTasks.values.forEach { $0.cancel() }
        captureTasks.removeAll()
        wallpaperProvider.purge()
        resetCaptureLane()
        entries.removeAll()
        generations.removeAll()
    }

    private func publish(
        background: WorkspacePreviewThumbnail?,
        images: [WindowKey: WorkspacePreviewThumbnail],
        for descriptor: WorkspacePreviewDescriptor,
        generation: UInt64
    ) {
        guard generations[descriptor.workspaceID] == generation,
              var entry = entries[descriptor.workspaceID]
        else { return }
        entry.background = background
        entry.images = images
        entries[descriptor.workspaceID] = entry
        enforceBounds()
    }

    private func nextGeneration(for workspaceID: UUID) -> UInt64 {
        let next = (generations[workspaceID] ?? 0) &+ 1
        generations[workspaceID] = next
        return next
    }

    private func resetCaptureLane() {
        captureLaneGeneration &+= 1
        captureTail?.cancel()
        captureTail = nil
    }

    private func finishCaptureLane(generation: UInt64) {
        guard activeCaptureLaneGeneration == generation else { return }
        activeCaptureLaneGeneration = nil
        // Resume on the next MainActor turn so the completed capture's local image buffers can be
        // released before a replacement capture receives the global byte reservation.
        Task { @MainActor [weak self] in
            self?.resumeDeferredCaptures()
        }
    }

    private func resumeDeferredCaptures() {
        guard activeCaptureLaneGeneration == nil, !deferredCaptureDescriptors.isEmpty else { return }
        let descriptors = deferredCaptureDescriptors.values.sorted {
            $0.workspaceID.uuidString < $1.workspaceID.uuidString
        }
        deferredCaptureDescriptors.removeAll()
        for descriptor in descriptors {
            update(descriptor: descriptor)
        }
    }

    private func completeRequest(for workspaceID: UUID, generation: UInt64) {
        guard generations[workspaceID] == generation else { return }
        captureTasks.removeValue(forKey: workspaceID)
    }

    private func touch(_ workspaceID: UUID) {
        guard var entry = entries[workspaceID] else { return }
        accessCounter &+= 1
        entry.lastAccess = accessCounter
        entries[workspaceID] = entry
    }

    private func enforceBounds() {
        while entries.count > maximumEntryCount || entries.values.reduce(0, { $0 + $1.approximateByteCount }) > maximumByteCount {
            guard let oldest = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key else { return }
            captureTasks.removeValue(forKey: oldest)?.cancel()
            deferredCaptureDescriptors.removeValue(forKey: oldest)
            entries.removeValue(forKey: oldest)
            generations.removeValue(forKey: oldest)
        }
    }
}

struct WorkspacePreviewView: View {
    let descriptor: WorkspacePreviewDescriptor
    let background: WorkspacePreviewThumbnail?
    let images: [WindowKey: WorkspacePreviewThumbnail]
    let interactionMode: WorkspacePreviewInteractionMode
    let onWorkspaceSelected: (() -> Void)?
    let onItemSelected: ((WorkspacePreviewItemDescriptor) -> Void)?

    init(
        descriptor: WorkspacePreviewDescriptor,
        background: WorkspacePreviewThumbnail? = nil,
        images: [WindowKey: WorkspacePreviewThumbnail] = [:],
        interactionMode: WorkspacePreviewInteractionMode = .workspaceOnly,
        onWorkspaceSelected: (() -> Void)? = nil,
        onItemSelected: ((WorkspacePreviewItemDescriptor) -> Void)? = nil
    ) {
        self.descriptor = descriptor
        self.background = background
        self.images = images
        self.interactionMode = interactionMode
        self.onWorkspaceSelected = onWorkspaceSelected
        self.onItemSelected = onItemSelected
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard interactionMode.acceptsWorkspace else { return }
                        onWorkspaceSelected?()
                    }
                    .accessibilityLabel("Workspace \(descriptor.name)")
                    .accessibilityHint(interactionMode.acceptsWorkspace ? "Select workspace" : "Workspace preview")

                if let background {
                    Image(decorative: background.image, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .allowsHitTesting(false)
                }

                ForEach(descriptor.items) { item in
                    let frame = WorkspacePreviewGeometry.rect(item.frame, in: descriptor.canvasFrame, renderedSize: proxy.size)
                    WorkspacePreviewItemView(item: item, thumbnail: images[item.key])
                        .frame(width: max(1, frame.width), height: max(1, frame.height))
                        .position(x: frame.midX, y: frame.midY)
                        .contentShape(Rectangle())
                        .allowsHitTesting(interactionMode.acceptsItems)
                        .onTapGesture {
                            guard interactionMode.acceptsItems else { return }
                            onItemSelected?(item)
                        }
                        .accessibilityLabel(item.name)
                        .accessibilityHint(interactionMode.acceptsItems ? "Select this item" : "Workspace item preview")
                }

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.secondary.opacity(0.25))
                    .allowsHitTesting(false)
            }
        }
        .aspectRatio(max(descriptor.canvasFrame.width, 1) / max(descriptor.canvasFrame.height, 1), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct WorkspacePreviewItemView: View {
    let item: WorkspacePreviewItemDescriptor
    let thumbnail: WorkspacePreviewThumbnail?

    var body: some View {
        ZStack {
            if let thumbnail {
                Image(decorative: thumbnail.image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(nsColor: .controlBackgroundColor)
                if let applicationURL = item.applicationURL {
                    let icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                } else {
                    Image(systemName: "app.dashed")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(.primary.opacity(0.18)) }
    }
}
