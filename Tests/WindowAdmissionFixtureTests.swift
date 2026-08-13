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

    func testNewCapabilityEvidenceDoesNotChangeAdmissionBeforeLiveValidation() {
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
            role: kAXWindowRole as String,
            subrole: kAXDialogSubrole as String,
            windowLayer: 0,
            isMinimized: false,
            fullscreenButton: .absent,
            closeButton: .present
        )

        let merged = refreshedCore.retainingSupportEvidence(from: previous)

        XCTAssertEqual(merged.subrole, kAXDialogSubrole as String)
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
        name: "standard document window",
        metadata: fixtureMetadata(subrole: kAXStandardWindowSubrole as String),
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
        name: "unverified non-normal dialog remains managed",
        metadata: fixtureMetadata(
            bundleIdentifier: "com.example.UnusualWindowLevels",
            subrole: kAXDialogSubrole as String,
            windowLayer: 3,
            fullscreenButton: .absent
        ),
        expected: decision(.managedNormal, .ambiguousDialogMetadata)
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
