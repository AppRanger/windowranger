import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
private func AXUIElementGetWindowID(
    _ element: AXUIElement,
    _ identifier: UnsafeMutablePointer<CGWindowID>
) -> AXError

struct WindowKey: Codable, Hashable, Sendable {
    let processIdentifier: pid_t
    let windowIdentifier: CGWindowID
}

struct WindowFrame: Codable, Equatable, Sendable {
    var position: CGPoint
    var size: CGSize
}

struct WindowFocusCapabilities: Equatable, Sendable {
    let role: String?
    let subrole: String?
    let windowLayer: Int?
    let isMinimized: Bool
    let isFocused: Bool?
    let isMain: Bool?
    let focusedAttributeSettable: Bool
    let mainAttributeSettable: Bool
    let applicationFocusedWindowAttributeSettable: Bool
    let raiseActionSupported: Bool
}

struct WindowServerWindowOrderEntry: Equatable, Sendable {
    let processIdentifier: pid_t
    let windowIdentifier: CGWindowID
    let layer: Int
}

struct WindowServerPointerEntry: Equatable, Sendable {
    let key: WindowKey
    let layer: Int
    let bounds: CGRect
}

enum WindowAdmissionDisposition: String, Equatable, Sendable {
    case managedNormal = "managed-normal"
    case managedDialog = "managed-dialog"
    case ignoredTransientPopup = "ignored-transient-popup"
    case temporarilyIneligible = "temporarily-ineligible"

    var admitsNewWindow: Bool {
        self == .managedNormal || self == .managedDialog
    }

    var evictsTrackedWindow: Bool {
        self == .ignoredTransientPopup
    }
}

enum WindowAdmissionReason: String, Equatable, Sendable {
    case normalWindow = "normal-window"
    case sheetRole = "sheet-role"
    case systemDialogSubrole = "system-dialog-subrole"
    case dialogSubroleWithoutFullscreenButton = "dialog-subrole-without-fullscreen-button"
    case floatingWindowWithoutFullscreenButton = "floating-window-without-fullscreen-button"
    case ambiguousDialogMetadata = "ambiguous-dialog-metadata"
    case verifiedBundleNonNormalLayer = "verified-bundle-non-normal-layer"
    case unsupportedRole = "unsupported-role"
    case minimized = "minimized"
    case fullscreen = "fullscreen"
    case unsupportedSubrole = "unsupported-subrole"
}

enum AXAttributePresence: String, Equatable, Sendable {
    case present
    case absent
    case unavailable
}

enum AXBooleanAttributeObservation: String, Equatable, Sendable {
    case trueValue = "true"
    case falseValue = "false"
    case unsupported
    case unavailable

    var value: Bool? {
        switch self {
        case .trueValue: true
        case .falseValue: false
        case .unsupported, .unavailable: nil
        }
    }
}

struct WindowAdmissionMetadata: Equatable, Sendable {
    let bundleIdentifier: String?
    let role: String?
    let subrole: String?
    let windowLayer: Int?
    let isMinimized: Bool
    let isFullscreen: Bool
    let fullscreenObservation: AXBooleanAttributeObservation
    let fullscreenButton: AXAttributePresence
    let closeButton: AXAttributePresence

    init(
        bundleIdentifier: String?,
        role: String?,
        subrole: String?,
        windowLayer: Int?,
        isMinimized: Bool,
        isFullscreen: Bool = false,
        fullscreenObservation: AXBooleanAttributeObservation? = nil,
        fullscreenButton: AXAttributePresence = .unavailable,
        closeButton: AXAttributePresence = .unavailable
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.role = role
        self.subrole = subrole
        self.windowLayer = windowLayer
        self.isMinimized = isMinimized
        self.isFullscreen = isFullscreen
        self.fullscreenObservation = fullscreenObservation
            ?? (isFullscreen ? .trueValue : .falseValue)
        self.fullscreenButton = fullscreenButton
        self.closeButton = closeButton
    }
}

struct WindowAdmissionDecision: Equatable, Sendable {
    let disposition: WindowAdmissionDisposition
    let reason: WindowAdmissionReason

    var automaticallyFloats: Bool { disposition == .managedDialog }

    /// A deliberately conservative app-rule hook. High-confidence dialogs already float without
    /// a rule; ambiguous AXDialog/AXFloating metadata may opt in per app. Standard document
    /// windows are never inferred to be secondary from size, resizability, or window level alone.
    var isSecondaryWindowCandidate: Bool {
        automaticallyFloats || reason == .ambiguousDialogMetadata
    }
}

enum AccessibilityWindow {
    private static let enhancedUserInterfaceAttribute = "AXEnhancedUserInterface" as CFString
    private static let fullScreenAttribute = "AXFullScreen" as CFString

    /// Window levels are not globally reliable enough to reject for every application. This
    /// cautious allowlist grows only when an application's AX/WindowServer behaviour is verified.
    static let bundleIdentifiersWithVerifiedTransientNonNormalLayers: Set<String> = [
        "com.openai.codex",
    ]

    static func hasVerifiedTransientNonNormalLayers(_ bundleIdentifier: String?) -> Bool {
        bundleIdentifier.map { bundleIdentifiersWithVerifiedTransientNonNormalLayers.contains($0.lowercased()) }
            ?? false
    }

    static func requestPermission(
        isTrusted: () -> Bool = { AXIsProcessTrusted() },
        showSystemPrompt: () -> Bool = {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
    ) -> Bool {
        // Passing the prompt option on every launch needlessly asks TCC to present UI again.
        // Only use that path when the exact currently running code identity is not yet trusted.
        isTrusted() ? true : showSystemPrompt()
    }

    static func identifier(for element: AXUIElement, processIdentifier: pid_t) -> WindowKey? {
        var identifier: CGWindowID = 0
        guard AXUIElementGetWindowID(element, &identifier) == .success, identifier != 0 else { return nil }
        return WindowKey(processIdentifier: processIdentifier, windowIdentifier: identifier)
    }

    static func copyAttribute<T>(_ element: AXUIElement, _ attribute: CFString, as type: T.Type) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? T
    }

    /// Distinguishes a reliably absent window control from an AX read that timed out or failed.
    /// Dialog heuristics must not treat missing metadata as evidence: false positives are more
    /// disruptive than leaving an unusual dialog in the layout.
    static func attributePresence(_ attribute: CFString, of element: AXUIElement) -> AXAttributePresence {
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(element, attribute, &value) {
        case .success:
            return value == nil ? .absent : .present
        case .noValue, .attributeUnsupported:
            return .absent
        default:
            return .unavailable
        }
    }

    /// Unlike a plain optional read, this preserves the difference between an authoritative false
    /// value, a window that does not expose the attribute, and a temporarily failed AX request.
    /// Full-screen sessions use that distinction to avoid becoming frame-write eligible merely
    /// because a busy game stopped answering Accessibility for one discovery pass.
    static func booleanAttributeObservation(
        _ attribute: CFString,
        of element: AXUIElement
    ) -> AXBooleanAttributeObservation {
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(element, attribute, &value) {
        case .success:
            guard let boolean = value as? Bool else { return .unavailable }
            return boolean ? .trueValue : .falseValue
        case .noValue, .attributeUnsupported:
            return .unsupported
        default:
            return .unavailable
        }
    }

    static func fullscreenObservation(of element: AXUIElement) -> AXBooleanAttributeObservation {
        booleanAttributeObservation(fullScreenAttribute, of: element)
    }

    static func isAttributeSettable(_ attribute: CFString, of element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute, &settable) == .success && settable.boolValue
    }

    static func supportsAction(_ action: CFString, on element: AXUIElement) -> Bool {
        var values: CFArray?
        guard AXUIElementCopyActionNames(element, &values) == .success,
              let actions = values as? [String]
        else { return false }
        return actions.contains(action as String)
    }

    /// Returns the WindowServer layer for an on-screen window. Layer zero is a normal app window;
    /// nonzero layers are commonly panels, popovers, inspectors, and other transient UI that can
    /// appear in AXWindows but cannot reliably become an application's main keyboard window.
    static func windowLayer(for windowIdentifier: CGWindowID) -> Int? {
        guard let records = CGWindowListCopyWindowInfo(
            [.optionIncludingWindow, .excludeDesktopElements],
            windowIdentifier
        ) as? [[CFString: Any]],
            let record = records.first,
            let layer = record[kCGWindowLayer] as? NSNumber
        else { return nil }
        return layer.intValue
    }

    /// Fetch all visible WindowServer levels once for a discovery pass. Callers retain a last-known
    /// value for already observed windows, because parked or temporarily hidden windows can be
    /// absent from this snapshot.
    static func visibleWindowLayers() -> [CGWindowID: Int]? {
        guard let records = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else { return nil }

        var result: [CGWindowID: Int] = [:]
        result.reserveCapacity(records.count)
        for record in records {
            guard let identifier = (record[kCGWindowNumber] as? NSNumber)?.uint32Value,
                  let layer = record[kCGWindowLayer] as? NSNumber
            else { continue }
            result[CGWindowID(identifier)] = layer.intValue
        }
        return result
    }

    /// WindowServer supplies on-screen windows in front-to-back order and in the same global,
    /// top-left coordinate space used by AX window frames and CGEvent pointer locations.
    static func onScreenPointerOrder() -> [WindowServerPointerEntry]? {
        guard let records = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else { return nil }

        return records.compactMap { record in
            guard let owner = (record[kCGWindowOwnerPID] as? NSNumber)?.int32Value,
                  let identifier = (record[kCGWindowNumber] as? NSNumber)?.uint32Value,
                  let layer = (record[kCGWindowLayer] as? NSNumber)?.intValue,
                  let boundsDictionary = record[kCGWindowBounds] as? NSDictionary
            else { return nil }
            var bounds = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDictionary as CFDictionary, &bounds) else {
                return nil
            }
            return WindowServerPointerEntry(
                key: WindowKey(
                    processIdentifier: pid_t(owner),
                    windowIdentifier: CGWindowID(identifier)
                ),
                layer: layer,
                bounds: bounds
            )
        }
    }

    /// Resolve only the actual frontmost WindowServer surface at the pointer. If that surface is
    /// not an eligible normal window, fail closed rather than clicking through it to another app.
    static func pointerTargetWindow(
        at pointer: CGPoint,
        in orderedWindows: [WindowServerPointerEntry],
        eligibleWindowKeys: Set<WindowKey>
    ) -> WindowKey? {
        guard let frontmostHit = orderedWindows.first(where: { $0.bounds.contains(pointer) }),
              frontmostHit.layer == 0,
              eligibleWindowKeys.contains(frontmostHit.key)
        else { return nil }
        return frontmostHit.key
    }

    /// WindowServer returns on-screen windows from front to back. This observation is deliberately
    /// separate from Accessibility focus: some applications can be visibly frontmost while their
    /// application-level AXFocusedWindow value is temporarily unavailable.
    static func frontmostNormalWindowIdentifier(
        for processIdentifier: pid_t,
        in orderedWindows: [WindowServerWindowOrderEntry]
    ) -> CGWindowID? {
        guard let frontmostApplicationWindow = orderedWindows.first(where: {
            $0.processIdentifier == processIdentifier
        }), frontmostApplicationWindow.layer == 0
        else { return nil }
        return frontmostApplicationWindow.windowIdentifier
    }

    static func frontmostOnScreenNormalWindowIdentifier(
        for processIdentifier: pid_t
    ) -> CGWindowID? {
        guard let records = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else { return nil }

        let orderedWindows = records.compactMap { record -> WindowServerWindowOrderEntry? in
            guard let owner = (record[kCGWindowOwnerPID] as? NSNumber)?.int32Value,
                  let identifier = (record[kCGWindowNumber] as? NSNumber)?.uint32Value,
                  let layer = (record[kCGWindowLayer] as? NSNumber)?.intValue
            else { return nil }
            return WindowServerWindowOrderEntry(
                processIdentifier: pid_t(owner),
                windowIdentifier: CGWindowID(identifier),
                layer: layer
            )
        }
        return frontmostNormalWindowIdentifier(
            for: processIdentifier,
            in: orderedWindows
        )
    }

    static func admissionMetadata(
        of element: AXUIElement,
        bundleIdentifier: String?,
        windowLayer: Int?,
        fullscreenObservation suppliedFullscreenObservation: AXBooleanAttributeObservation? = nil,
        effectiveFullscreen: Bool? = nil
    ) -> WindowAdmissionMetadata {
        let fullscreenObservation = suppliedFullscreenObservation ?? self.fullscreenObservation(of: element)
        return WindowAdmissionMetadata(
            bundleIdentifier: bundleIdentifier,
            role: copyAttribute(element, kAXRoleAttribute as CFString, as: String.self),
            subrole: copyAttribute(element, kAXSubroleAttribute as CFString, as: String.self),
            windowLayer: windowLayer,
            isMinimized: copyAttribute(element, kAXMinimizedAttribute as CFString, as: Bool.self) ?? false,
            isFullscreen: effectiveFullscreen ?? fullscreenObservation.value ?? false,
            fullscreenObservation: fullscreenObservation,
            fullscreenButton: attributePresence(kAXFullScreenButtonAttribute as CFString, of: element),
            closeButton: attributePresence(kAXCloseButtonAttribute as CFString, of: element)
        )
    }

    static func admissionDecision(for metadata: WindowAdmissionMetadata) -> WindowAdmissionDecision {
        if let layer = metadata.windowLayer,
           layer != 0,
           hasVerifiedTransientNonNormalLayers(metadata.bundleIdentifier) {
            return WindowAdmissionDecision(
                disposition: .ignoredTransientPopup,
                reason: .verifiedBundleNonNormalLayer
            )
        }

        guard metadata.role == kAXWindowRole as String || metadata.role == kAXSheetRole as String else {
            return WindowAdmissionDecision(disposition: .temporarilyIneligible, reason: .unsupportedRole)
        }
        guard !metadata.isMinimized else {
            return WindowAdmissionDecision(disposition: .temporarilyIneligible, reason: .minimized)
        }
        guard !metadata.isFullscreen else {
            return WindowAdmissionDecision(disposition: .temporarilyIneligible, reason: .fullscreen)
        }

        if metadata.role == kAXSheetRole as String {
            return WindowAdmissionDecision(disposition: .managedDialog, reason: .sheetRole)
        }

        if metadata.subrole == nil || metadata.subrole == kAXStandardWindowSubrole as String {
            return WindowAdmissionDecision(disposition: .managedNormal, reason: .normalWindow)
        }
        if metadata.subrole == kAXSystemDialogSubrole as String {
            return WindowAdmissionDecision(disposition: .managedDialog, reason: .systemDialogSubrole)
        }
        if metadata.subrole == kAXDialogSubrole as String {
            guard metadata.windowLayer == 0,
                  metadata.fullscreenButton == .absent
            else {
                return WindowAdmissionDecision(
                    disposition: .managedNormal,
                    reason: .ambiguousDialogMetadata
                )
            }
            return WindowAdmissionDecision(
                disposition: .managedDialog,
                reason: .dialogSubroleWithoutFullscreenButton
            )
        }
        if metadata.subrole == kAXFloatingWindowSubrole as String {
            guard metadata.windowLayer == 0,
                  metadata.fullscreenButton == .absent,
                  metadata.closeButton == .present
            else {
                return WindowAdmissionDecision(
                    disposition: .managedNormal,
                    reason: .ambiguousDialogMetadata
                )
            }
            return WindowAdmissionDecision(
                disposition: .managedDialog,
                reason: .floatingWindowWithoutFullscreenButton
            )
        }
        return WindowAdmissionDecision(disposition: .temporarilyIneligible, reason: .unsupportedSubrole)
    }

    static func focusCapabilities(
        of element: AXUIElement,
        processIdentifier: pid_t,
        windowIdentifier: CGWindowID
    ) -> WindowFocusCapabilities {
        let application = AXUIElementCreateApplication(processIdentifier)
        return WindowFocusCapabilities(
            role: copyAttribute(element, kAXRoleAttribute as CFString, as: String.self),
            subrole: copyAttribute(element, kAXSubroleAttribute as CFString, as: String.self),
            windowLayer: windowLayer(for: windowIdentifier),
            isMinimized: copyAttribute(element, kAXMinimizedAttribute as CFString, as: Bool.self) ?? false,
            isFocused: copyAttribute(element, kAXFocusedAttribute as CFString, as: Bool.self),
            isMain: copyAttribute(element, kAXMainAttribute as CFString, as: Bool.self),
            focusedAttributeSettable: isAttributeSettable(kAXFocusedAttribute as CFString, of: element),
            mainAttributeSettable: isAttributeSettable(kAXMainAttribute as CFString, of: element),
            applicationFocusedWindowAttributeSettable: isAttributeSettable(
                kAXFocusedWindowAttribute as CFString,
                of: application
            ),
            raiseActionSupported: supportsAction(kAXRaiseAction as CFString, on: element)
        )
    }

    static func isEligibleFocusCycleCandidate(_ capabilities: WindowFocusCapabilities) -> Bool {
        guard capabilities.role == kAXWindowRole as String || capabilities.role == kAXSheetRole as String,
              !capabilities.isMinimized,
              capabilities.windowLayer == nil || capabilities.windowLayer == 0,
              capabilities.subrole == nil ||
                capabilities.subrole == kAXStandardWindowSubrole as String ||
                capabilities.subrole == kAXDialogSubrole as String ||
                capabilities.subrole == kAXSystemDialogSubrole as String ||
                capabilities.subrole == kAXFloatingWindowSubrole as String,
              capabilities.raiseActionSupported
        else { return false }

        return capabilities.focusedAttributeSettable ||
            capabilities.mainAttributeSettable ||
            capabilities.applicationFocusedWindowAttributeSettable
    }

    /// Best-effort neutral focus for the uncommon case where the last visible window is sent away.
    /// WindowRanger never activates itself just to manufacture a replacement focus target.
    static func clearFocus(
        of element: AXUIElement
    ) -> (focused: AXError?, main: AXError?) {
        let focusedResult = isAttributeSettable(kAXFocusedAttribute as CFString, of: element)
            ? AXUIElementSetAttributeValue(
                element,
                kAXFocusedAttribute as CFString,
                false as CFTypeRef
            )
            : nil
        let mainResult = isAttributeSettable(kAXMainAttribute as CFString, of: element)
            ? AXUIElementSetAttributeValue(
                element,
                kAXMainAttribute as CFString,
                false as CFTypeRef
            )
            : nil
        return (focusedResult, mainResult)
    }

    static func frame(of element: AXUIElement) -> WindowFrame? {
        guard let positionValue = copyAttribute(element, kAXPositionAttribute as CFString, as: AXValue.self),
              let sizeValue = copyAttribute(element, kAXSizeAttribute as CFString, as: AXValue.self)
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size)
        else { return nil }
        return WindowFrame(position: position, size: size)
    }

    static func position(of element: AXUIElement) -> CGPoint? {
        guard let positionValue = copyAttribute(element, kAXPositionAttribute as CFString, as: AXValue.self) else {
            return nil
        }
        var position = CGPoint.zero
        return AXValueGetValue(positionValue, .cgPoint, &position) ? position : nil
    }

    static func positionsMatch(_ current: CGPoint, _ target: CGPoint, tolerance: CGFloat = 1) -> Bool {
        abs(current.x - target.x) < tolerance && abs(current.y - target.y) < tolerance
    }

    static func framesMatch(_ current: WindowFrame, _ target: WindowFrame, tolerance: CGFloat = 1) -> Bool {
        positionsMatch(current.position, target.position, tolerance: tolerance) &&
            abs(current.size.width - target.size.width) < tolerance &&
            abs(current.size.height - target.size.height) < tolerance
    }

    /// Workspace visibility never changes a window's size. A position-only write avoids the
    /// resize/move/resize sequence needed by layout engines and, unlike a size write, does not
    /// force an otherwise unchanged window to repaint over DisplayLink or USB displays.
    @discardableResult
    static func setPositionIfNeeded(_ target: CGPoint, of element: AXUIElement) -> Bool {
        if let current = position(of: element), positionsMatch(current, target) {
            return true
        }
        var target = target
        guard let value = AXValueCreate(.cgPoint, &target) else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success
    }

    /// Suppresses the receiving application's own Accessibility transition animation for a batch
    /// of position writes, then restores its exact prior value. This is app-scoped and does not
    /// change global macOS animation or Accessibility preferences.
    static func withoutPositionAnimations(for processIdentifier: pid_t, _ body: () -> Void) {
        let app = AXUIElementCreateApplication(processIdentifier)
        let wasEnhanced = copyAttribute(
            app,
            enhancedUserInterfaceAttribute,
            as: Bool.self
        ) == true
        if wasEnhanced {
            AXUIElementSetAttributeValue(app, enhancedUserInterfaceAttribute, false as CFTypeRef)
        }
        defer {
            if wasEnhanced {
                AXUIElementSetAttributeValue(app, enhancedUserInterfaceAttribute, true as CFTypeRef)
            }
        }
        body()
    }

    @discardableResult
    static func setFrame(_ frame: WindowFrame, of element: AXUIElement) -> Bool {
        if let current = self.frame(of: element), framesMatch(current, frame) {
            return true
        }

        var position = frame.position
        var size = frame.size
        guard let positionValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size)
        else { return false }

        // Size-position-size is the most reliable sequence for apps that clamp one dimension after
        // the other changes. Normal workspace switches remain position-only; this is used only when
        // quit recovery or a smaller replacement display requires a safe resize.
        let firstSizeResult = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        let positionResult = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
        let finalSizeResult = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        return firstSizeResult == .success && positionResult == .success && finalSizeResult == .success
    }

}
