import ApplicationServices
import XCTest

final class WindowAdmissionFixtureTests: XCTestCase {
    func testPrivacySafeAdmissionFixtureCorpus() {
        for fixture in fixtures {
            XCTAssertEqual(
                AccessibilityWindow.admissionDecision(for: fixture.metadata),
                fixture.expected,
                fixture.name
            )
        }
    }

    func testFixedSizeCapabilityEvidenceDoesNotOverrideDocumentControls() {
        let metadata = fixtureMetadata(
            subrole: kAXStandardWindowSubrole as String,
            modalObservation: .trueValue,
            focusedObservation: .trueValue,
            mainObservation: .trueValue,
            fullscreenButton: .present,
            minimizeButton: .present,
            closeButton: .present,
            zoomButton: .present,
            positionSettable: .falseValue,
            sizeSettable: .falseValue
        )

        XCTAssertEqual(
            AccessibilityWindow.admissionDecision(for: metadata),
            decision(.managedNormal, .normalWindow)
        )
    }

    func testCompanionIdentifierReadIsRestrictedToExactKnownBundles() {
        XCTAssertTrue(AccessibilityWindow.shouldReadAccessibilityIdentifierForCompatibility(
            "DEV.APPRANGER.DESKTOPRANGER.SURFACELAB"
        ))
        XCTAssertFalse(AccessibilityWindow.shouldReadAccessibilityIdentifierForCompatibility(
            "dev.appranger.DesktopRanger"
        ))
        XCTAssertFalse(AccessibilityWindow.shouldReadAccessibilityIdentifierForCompatibility(
            "dev.appranger.DesktopRanger.Helper"
        ))
        XCTAssertFalse(AccessibilityWindow.shouldReadAccessibilityIdentifierForCompatibility(
            "com.example.Editor"
        ))
        XCTAssertFalse(AccessibilityWindow.shouldReadAccessibilityIdentifierForCompatibility(nil))
    }

    func testTaggedCompanionSurfaceRemainsIgnoredAcrossTransientIdentifierFailure() {
        let previous = fixtureMetadata(
            bundleIdentifier: "dev.appranger.DesktopRanger.SurfaceLab",
            accessibilityIdentifier: AccessibilityWindow.desktopRangerSurfaceAccessibilityIdentifier,
            subrole: kAXFloatingWindowSubrole as String,
            windowLayer: 3
        )
        let transientRefresh = WindowAdmissionMetadata(
            bundleIdentifier: "dev.appranger.DesktopRanger.SurfaceLab",
            accessibilityIdentifierObservation: .unavailable,
            role: kAXWindowRole as String,
            subrole: kAXFloatingWindowSubrole as String,
            windowLayer: 3,
            isMinimized: false
        )

        let merged = transientRefresh.retainingSupportEvidence(from: previous)
        let decision = AccessibilityWindow.admissionDecision(for: merged)

        XCTAssertEqual(
            merged.accessibilityIdentifier,
            AccessibilityWindow.desktopRangerSurfaceAccessibilityIdentifier
        )
        XCTAssertEqual(decision, WindowAdmissionDecision(
            disposition: .ignoredCompanionSurface,
            reason: .rangerCompanionSurface,
            compatibilityProfileIdentifier: "desktopranger-owned-surface-v1"
        ))
    }

    func testFirstCompanionIdentifierFailureIsTemporarilyIneligible() {
        let metadata = WindowAdmissionMetadata(
            bundleIdentifier: "dev.appranger.DesktopRanger.SurfaceLab",
            accessibilityIdentifierObservation: .unavailable,
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            windowLayer: 0,
            isMinimized: false
        )

        let decision = AccessibilityWindow.admissionDecision(for: metadata)

        XCTAssertEqual(decision, WindowAdmissionDecision(
            disposition: .temporarilyIneligible,
            reason: .rangerCompanionSurfaceIdentifierUnavailable
        ))
        XCTAssertFalse(decision.disposition.admitsNewWindow)
        XCTAssertFalse(decision.disposition.evictsTrackedWindow)
    }

    func testFixedSizeEvidenceCollectionRequiresTheNarrowStandardWindowShape() {
        let updaterCore = fixtureMetadata(
            bundleIdentifier: "com.openai.codex",
            subrole: kAXStandardWindowSubrole as String,
            fullscreenButton: .absent,
            minimizeButton: .unavailable,
            zoomButton: .unavailable,
            positionSettable: .unsupported,
            sizeSettable: .unsupported
        )

        XCTAssertTrue(AccessibilityWindow.shouldCollectFixedSizeStandardWindowEvidence(updaterCore))
        XCTAssertFalse(AccessibilityWindow.hasAuthoritativeMoveResizeEvidence(updaterCore))
        XCTAssertFalse(AccessibilityWindow.shouldCollectFixedSizeStandardWindowEvidence(
            fixtureMetadata(subrole: kAXStandardWindowSubrole as String, fullscreenButton: .present)
        ))
        XCTAssertFalse(AccessibilityWindow.shouldCollectFixedSizeStandardWindowEvidence(
            fixtureMetadata(
                subrole: kAXDialogSubrole as String,
                fullscreenButton: .absent
            )
        ))
    }

    func testBroadRefreshUpdatesClassifierInputsButRetainsSupportOnlyEvidence() {
        let previous = fixtureMetadata(
            subrole: kAXStandardWindowSubrole as String,
            modalObservation: .trueValue,
            focusedObservation: .trueValue,
            mainObservation: .trueValue,
            fullscreenButton: .present,
            minimizeButton: .absent,
            closeButton: .present,
            zoomButton: .absent,
            positionSettable: .trueValue,
            sizeSettable: .falseValue
        )
        let refreshedCore = WindowAdmissionMetadata(
            bundleIdentifier: "com.example.Editor",
            accessibilityIdentifier: AccessibilityWindow.desktopRangerSurfaceAccessibilityIdentifier,
            role: kAXWindowRole as String,
            subrole: kAXDialogSubrole as String,
            windowLayer: 0,
            isMinimized: false,
            fullscreenButton: .absent,
            closeButton: .present
        )

        let merged = refreshedCore.retainingSupportEvidence(from: previous)

        XCTAssertEqual(merged.subrole, kAXDialogSubrole as String)
        XCTAssertEqual(
            merged.accessibilityIdentifier,
            AccessibilityWindow.desktopRangerSurfaceAccessibilityIdentifier
        )
        XCTAssertEqual(merged.fullscreenButton, .absent)
        XCTAssertEqual(merged.modalObservation, .trueValue)
        XCTAssertEqual(merged.minimizeButton, .absent)
        XCTAssertEqual(merged.positionSettable, .trueValue)
        XCTAssertEqual(merged.sizeSettable, .falseValue)
    }
}

private struct WindowAdmissionFixture {
    let name: String
    let metadata: WindowAdmissionMetadata
    let expected: WindowAdmissionDecision
}

private let fixtures: [WindowAdmissionFixture] = [
    WindowAdmissionFixture(
        name: "SurfaceLab standard host surface is ignored",
        metadata: fixtureMetadata(
            bundleIdentifier: "dev.appranger.DesktopRanger.SurfaceLab",
            accessibilityIdentifier: AccessibilityWindow.desktopRangerSurfaceAccessibilityIdentifier,
            subrole: kAXStandardWindowSubrole as String
        ),
        expected: decision(
            .ignoredCompanionSurface,
            .rangerCompanionSurface,
            compatibilityProfileIdentifier: "desktopranger-owned-surface-v1"
        )
    ),
    WindowAdmissionFixture(
        name: "SurfaceLab non-normal dialog host surface is ignored",
        metadata: fixtureMetadata(
            bundleIdentifier: "dev.appranger.DesktopRanger.SurfaceLab",
            accessibilityIdentifier: AccessibilityWindow.desktopRangerSurfaceAccessibilityIdentifier,
            subrole: kAXDialogSubrole as String,
            windowLayer: 8,
            fullscreenButton: .absent
        ),
        expected: decision(
            .ignoredCompanionSurface,
            .rangerCompanionSurface,
            compatibilityProfileIdentifier: "desktopranger-owned-surface-v1"
        )
    ),
    WindowAdmissionFixture(
        name: "SurfaceLab floating host surface is ignored",
        metadata: fixtureMetadata(
            bundleIdentifier: "dev.appranger.DesktopRanger.SurfaceLab",
            accessibilityIdentifier: AccessibilityWindow.desktopRangerSurfaceAccessibilityIdentifier,
            subrole: kAXFloatingWindowSubrole as String,
            windowLayer: 3
        ),
        expected: decision(
            .ignoredCompanionSurface,
            .rangerCompanionSurface,
            compatibilityProfileIdentifier: "desktopranger-owned-surface-v1"
        )
    ),
    WindowAdmissionFixture(
        name: "untagged SurfaceLab standard window remains managed",
        metadata: fixtureMetadata(
            bundleIdentifier: "dev.appranger.DesktopRanger.SurfaceLab",
            subrole: kAXStandardWindowSubrole as String
        ),
        expected: decision(.managedNormal, .normalWindow)
    ),
    WindowAdmissionFixture(
        name: "SurfaceLab window with a nearby marker remains managed",
        metadata: fixtureMetadata(
            bundleIdentifier: "dev.appranger.DesktopRanger.SurfaceLab",
            accessibilityIdentifier: "dev.appranger.desktopranger.surface.v2",
            subrole: kAXStandardWindowSubrole as String
        ),
        expected: decision(.managedNormal, .normalWindow)
    ),
    WindowAdmissionFixture(
        name: "nearby SurfaceLab bundle suffix with the marker remains managed",
        metadata: fixtureMetadata(
            bundleIdentifier: "dev.appranger.DesktopRanger.SurfaceLab.Helper",
            accessibilityIdentifier: AccessibilityWindow.desktopRangerSurfaceAccessibilityIdentifier,
            subrole: kAXStandardWindowSubrole as String
        ),
        expected: decision(.managedNormal, .normalWindow)
    ),
    WindowAdmissionFixture(
        name: "nearby SurfaceLab bundle prefix with the marker remains managed",
        metadata: fixtureMetadata(
            bundleIdentifier: "dev.appranger.PreDesktopRanger.SurfaceLab",
            accessibilityIdentifier: AccessibilityWindow.desktopRangerSurfaceAccessibilityIdentifier,
            subrole: kAXStandardWindowSubrole as String
        ),
        expected: decision(.managedNormal, .normalWindow)
    ),
    WindowAdmissionFixture(
        name: "SurfaceLab window with a marker suffix remains managed",
        metadata: fixtureMetadata(
            bundleIdentifier: "dev.appranger.DesktopRanger.SurfaceLab",
            accessibilityIdentifier: AccessibilityWindow.desktopRangerSurfaceAccessibilityIdentifier + ".helper",
            subrole: kAXStandardWindowSubrole as String
        ),
        expected: decision(.managedNormal, .normalWindow)
    ),
    WindowAdmissionFixture(
        name: "SurfaceLab window with a marker prefix remains managed",
        metadata: fixtureMetadata(
            bundleIdentifier: "dev.appranger.DesktopRanger.SurfaceLab",
            accessibilityIdentifier: "prefix." + AccessibilityWindow.desktopRangerSurfaceAccessibilityIdentifier,
            subrole: kAXStandardWindowSubrole as String
        ),
        expected: decision(.managedNormal, .normalWindow)
    ),
    WindowAdmissionFixture(
        name: "unrelated bundle with the marker remains managed",
        metadata: fixtureMetadata(
            bundleIdentifier: "com.example.Editor",
            accessibilityIdentifier: AccessibilityWindow.desktopRangerSurfaceAccessibilityIdentifier,
            subrole: kAXStandardWindowSubrole as String
        ),
        expected: decision(.managedNormal, .normalWindow)
    ),
    WindowAdmissionFixture(
        name: "standard document window",
        metadata: fixtureMetadata(subrole: kAXStandardWindowSubrole as String),
        expected: decision(.managedNormal, .normalWindow)
    ),
    WindowAdmissionFixture(
        name: "captured ChatGPT document window remains managed",
        metadata: fixtureMetadata(
            bundleIdentifier: "com.openai.codex",
            subrole: kAXStandardWindowSubrole as String,
            fullscreenButton: .present,
            closeButton: .present,
            positionSettable: .trueValue,
            sizeSettable: .trueValue
        ),
        expected: decision(.managedNormal, .normalWindow)
    ),
    WindowAdmissionFixture(
        name: "captured fixed-size ChatGPT Sparkle updater floats",
        metadata: fixtureMetadata(
            bundleIdentifier: "com.openai.codex",
            subrole: kAXStandardWindowSubrole as String,
            fullscreenButton: .absent,
            minimizeButton: .absent,
            closeButton: .present,
            zoomButton: .absent,
            positionSettable: .trueValue,
            sizeSettable: .falseValue
        ),
        expected: decision(.managedDialog, .fixedSizeStandardWindow)
    ),
    WindowAdmissionFixture(
        name: "fixed-size standard candidate with failed capability reads stays managed",
        metadata: fixtureMetadata(
            subrole: kAXStandardWindowSubrole as String,
            fullscreenButton: .absent,
            closeButton: .present,
            positionSettable: .unavailable,
            sizeSettable: .unavailable
        ),
        expected: decision(.managedNormal, .normalWindow)
    ),
    WindowAdmissionFixture(
        name: "immovable fixed-size standard candidate stays managed conservatively",
        metadata: fixtureMetadata(
            subrole: kAXStandardWindowSubrole as String,
            fullscreenButton: .absent,
            closeButton: .present,
            positionSettable: .falseValue,
            sizeSettable: .falseValue
        ),
        expected: decision(.managedNormal, .normalWindow)
    ),
    WindowAdmissionFixture(
        name: "missing subrole remains conservatively managed",
        metadata: fixtureMetadata(subrole: nil),
        expected: decision(.managedNormal, .normalWindow)
    ),
    WindowAdmissionFixture(
        name: "sheet floats",
        metadata: fixtureMetadata(role: kAXSheetRole as String, subrole: nil),
        expected: decision(.managedDialog, .sheetRole)
    ),
    WindowAdmissionFixture(
        name: "system dialog floats",
        metadata: fixtureMetadata(subrole: kAXSystemDialogSubrole as String),
        expected: decision(.managedDialog, .systemDialogSubrole)
    ),
    WindowAdmissionFixture(
        name: "corroborated dialog floats",
        metadata: fixtureMetadata(
            subrole: kAXDialogSubrole as String,
            fullscreenButton: .absent
        ),
        expected: decision(.managedDialog, .dialogSubroleWithoutFullscreenButton)
    ),
    WindowAdmissionFixture(
        name: "corroborated floating secondary window floats",
        metadata: fixtureMetadata(
            subrole: kAXFloatingWindowSubrole as String,
            fullscreenButton: .absent,
            closeButton: .present
        ),
        expected: decision(.managedDialog, .floatingWindowWithoutFullscreenButton)
    ),
    WindowAdmissionFixture(
        name: "verified Codex non-normal layer is ignored",
        metadata: fixtureMetadata(
            bundleIdentifier: "com.openai.codex",
            subrole: kAXStandardWindowSubrole as String,
            windowLayer: 3
        ),
        expected: decision(
            .ignoredTransientPopup,
            .verifiedBundleNonNormalLayer,
            compatibilityProfileIdentifier: "codex-transient-non-normal-layer-v1"
        )
    ),
    WindowAdmissionFixture(
        name: "captured Ghostty non-normal dialog is deferred until its layer settles",
        metadata: fixtureMetadata(
            bundleIdentifier: "com.mitchellh.ghostty",
            subrole: kAXDialogSubrole as String,
            windowLayer: 8,
            fullscreenButton: .absent,
            minimizeButton: .unavailable,
            closeButton: .absent,
            zoomButton: .unavailable,
            positionSettable: .unsupported,
            sizeSettable: .unsupported
        ),
        expected: decision(.temporarilyIneligible, .transientDialogNonNormalLayer)
    ),
    WindowAdmissionFixture(
        name: "dialog with fullscreen control remains in layout",
        metadata: fixtureMetadata(
            subrole: kAXDialogSubrole as String,
            fullscreenButton: .present
        ),
        expected: decision(.managedNormal, .ambiguousDialogMetadata)
    ),
    WindowAdmissionFixture(
        name: "floating metadata without reliable controls remains in layout",
        metadata: fixtureMetadata(
            subrole: kAXFloatingWindowSubrole as String,
            fullscreenButton: .unavailable,
            closeButton: .unavailable
        ),
        expected: decision(.managedNormal, .ambiguousDialogMetadata)
    ),
    WindowAdmissionFixture(
        name: "minimized window is deferred",
        metadata: fixtureMetadata(
            subrole: kAXStandardWindowSubrole as String,
            isMinimized: true
        ),
        expected: decision(.temporarilyIneligible, .minimized)
    ),
    WindowAdmissionFixture(
        name: "fullscreen window is deferred",
        metadata: fixtureMetadata(
            subrole: kAXStandardWindowSubrole as String,
            isFullscreen: true
        ),
        expected: decision(.temporarilyIneligible, .fullscreen)
    ),
    WindowAdmissionFixture(
        name: "toolbar child role is not admitted as a window",
        metadata: fixtureMetadata(role: kAXToolbarRole as String, subrole: nil),
        expected: decision(.temporarilyIneligible, .unsupportedRole)
    ),
    WindowAdmissionFixture(
        name: "unknown window subrole is deferred",
        metadata: fixtureMetadata(subrole: kAXUnknownSubrole as String),
        expected: decision(.temporarilyIneligible, .unsupportedSubrole)
    ),
]

private func fixtureMetadata(
    bundleIdentifier: String = "com.example.Editor",
    accessibilityIdentifier: String? = nil,
    role: String = kAXWindowRole as String,
    subrole: String?,
    windowLayer: Int? = 0,
    isMinimized: Bool = false,
    isFullscreen: Bool = false,
    modalObservation: AXBooleanAttributeObservation = .falseValue,
    focusedObservation: AXBooleanAttributeObservation = .falseValue,
    mainObservation: AXBooleanAttributeObservation = .falseValue,
    fullscreenButton: AXAttributePresence = .present,
    minimizeButton: AXAttributePresence = .present,
    closeButton: AXAttributePresence = .present,
    zoomButton: AXAttributePresence = .present,
    positionSettable: AXBooleanAttributeObservation = .trueValue,
    sizeSettable: AXBooleanAttributeObservation = .trueValue
) -> WindowAdmissionMetadata {
    WindowAdmissionMetadata(
        bundleIdentifier: bundleIdentifier,
        accessibilityIdentifier: accessibilityIdentifier,
        role: role,
        subrole: subrole,
        windowLayer: windowLayer,
        isMinimized: isMinimized,
        isFullscreen: isFullscreen,
        modalObservation: modalObservation,
        focusedObservation: focusedObservation,
        mainObservation: mainObservation,
        fullscreenButton: fullscreenButton,
        minimizeButton: minimizeButton,
        closeButton: closeButton,
        zoomButton: zoomButton,
        positionSettable: positionSettable,
        sizeSettable: sizeSettable
    )
}

private func decision(
    _ disposition: WindowAdmissionDisposition,
    _ reason: WindowAdmissionReason,
    compatibilityProfileIdentifier: String? = nil
) -> WindowAdmissionDecision {
    WindowAdmissionDecision(
        disposition: disposition,
        reason: reason,
        compatibilityProfileIdentifier: compatibilityProfileIdentifier
    )
}
