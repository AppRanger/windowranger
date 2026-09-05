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

    func testAuthoritativeFixedSizeCapabilityFloatsDespiteDocumentControls() {
        let metadata = fixtureMetadata(
            subrole: kAXStandardWindowSubrole as String,
            modalObservation: .trueValue,
            focusedObservation: .trueValue,
            mainObservation: .trueValue,
            fullscreenButton: .present,
            minimizeButton: .present,
            closeButton: .present,
            zoomButton: .present,
            positionSettable: .trueValue,
            sizeSettable: .falseValue
        )

        XCTAssertEqual(
            AccessibilityWindow.admissionDecision(for: metadata),
            decision(.managedDialog, .fixedSizeStandardWindow)
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
        XCTAssertTrue(AccessibilityWindow.shouldCollectFixedSizeStandardWindowEvidence(
            fixtureMetadata(subrole: kAXStandardWindowSubrole as String, fullscreenButton: .present)
        ))
        XCTAssertFalse(AccessibilityWindow.shouldCollectFixedSizeStandardWindowEvidence(
            fixtureMetadata(
                subrole: kAXDialogSubrole as String,
                fullscreenButton: .absent
            )
        ))

        let attemptedUnsupportedEvidence = WindowAdmissionMetadata(
            bundleIdentifier: "com.example.Editor",
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            windowLayer: 0,
            isMinimized: false,
            fullscreenButton: .present,
            closeButton: .present,
            supportMetadataWasCollected: true
        )
        XCTAssertFalse(AccessibilityWindow.shouldCollectFixedSizeSupportMetadata(
            coreMetadata: fixtureMetadata(
                subrole: kAXStandardWindowSubrole as String,
                fullscreenButton: .present
            ),
            retainedMetadata: attemptedUnsupportedEvidence
        ))
        XCTAssertEqual(
            AccessibilityWindow.fixedSizeDecisionAfterIneffectiveResize(attemptedUnsupportedEvidence),
            decision(.managedDialog, .fixedSizeStandardWindow)
        )
        XCTAssertNil(AccessibilityWindow.fixedSizeDecisionAfterIneffectiveResize(
            fixtureMetadata(subrole: kAXDialogSubrole as String)
        ))
    }

    func testOperationalNoOpResizeCanRecoverMisleadingSettableSupport() {
        let finderCopyStyleEvidence = fixtureMetadata(
            bundleIdentifier: "com.apple.finder",
            subrole: kAXStandardWindowSubrole as String,
            windowLayer: 0,
            modalObservation: .falseValue,
            fullscreenButton: .absent,
            minimizeButton: .present,
            closeButton: .present,
            zoomButton: .present,
            positionSettable: .trueValue,
            sizeSettable: .trueValue
        )

        XCTAssertEqual(
            AccessibilityWindow.admissionDecision(for: finderCopyStyleEvidence),
            decision(.managedNormal, .normalWindow)
        )
        XCTAssertEqual(
            AccessibilityWindow.fixedSizeDecisionAfterIneffectiveResize(finderCopyStyleEvidence),
            decision(.managedDialog, .fixedSizeStandardWindow)
        )
    }

    func testFixedSizeRecoveryRequiresAChangedObservedSizeAfterCooldown() {
        let start = Date(timeIntervalSinceReferenceDate: 100)
        let state = FixedSizeRecoveryState.seeded(
            observedSize: CGSize(width: 400, height: 300),
            now: start
        )
        let core = fixtureMetadata(subrole: kAXStandardWindowSubrole as String)

        XCTAssertFalse(state.shouldRecheck(
            coreMetadata: core,
            observedSize: CGSize(width: 400, height: 300),
            isVisibleActive: true,
            isPaused: false,
            now: start.addingTimeInterval(6)
        ))
        XCTAssertTrue(state.shouldRecheck(
            coreMetadata: core,
            observedSize: CGSize(width: 640, height: 480),
            isVisibleActive: true,
            isPaused: false,
            now: start.addingTimeInterval(6)
        ))
    }

    func testFixedSizeRecoveryKeepsBaselineAfterFailedProbeCooldown() {
        let start = Date(timeIntervalSinceReferenceDate: 100)
        let baseline = CGSize(width: 400, height: 300)
        let core = fixtureMetadata(subrole: kAXStandardWindowSubrole as String)
        let failedObservations: [(AXBooleanAttributeObservation, AXBooleanAttributeObservation)] = [
            (.trueValue, .falseValue),
            (.falseValue, .trueValue),
            (.unsupported, .trueValue),
            (.trueValue, .unavailable),
        ]

        for (positionSettable, sizeSettable) in failedObservations {
            var state = FixedSizeRecoveryState.seeded(observedSize: baseline, now: start)
            XCTAssertTrue(state.shouldRecheck(
                coreMetadata: core,
                observedSize: CGSize(width: 640, height: 480),
                isVisibleActive: true,
                isPaused: false,
                now: start.addingTimeInterval(6)
            ))
            XCTAssertFalse(state.recordCapabilityProbe(
                positionSettable: positionSettable,
                sizeSettable: sizeSettable,
                now: start.addingTimeInterval(6)
            ))
            XCTAssertEqual(state.baselineSize, baseline)
            XCTAssertFalse(state.shouldRecheck(
                coreMetadata: core,
                observedSize: CGSize(width: 640, height: 480),
                isVisibleActive: true,
                isPaused: false,
                now: start.addingTimeInterval(10)
            ))
            XCTAssertTrue(state.shouldRecheck(
                coreMetadata: core,
                observedSize: CGSize(width: 640, height: 480),
                isVisibleActive: true,
                isPaused: false,
                now: start.addingTimeInterval(11)
            ))
        }
    }

    func testFixedSizeRecoveryPositiveProbeReadmitsAfterChangedSize() {
        let start = Date(timeIntervalSinceReferenceDate: 100)
        var state = FixedSizeRecoveryState.seeded(
            observedSize: CGSize(width: 400, height: 300),
            now: start
        )
        let core = fixtureMetadata(subrole: kAXStandardWindowSubrole as String)

        XCTAssertTrue(state.shouldRecheck(
            coreMetadata: core,
            observedSize: CGSize(width: 640, height: 480),
            isVisibleActive: true,
            isPaused: false,
            now: start.addingTimeInterval(6)
        ))
        XCTAssertTrue(state.recordCapabilityProbe(
            positionSettable: .trueValue,
            sizeSettable: .trueValue,
            now: start.addingTimeInterval(6)
        ))
    }

    func testFixedSizeRecoveryLearnsFirstReadableSizeAfterUnavailableFailure() {
        let start = Date(timeIntervalSinceReferenceDate: 100)
        var state = FixedSizeRecoveryState.seeded(observedSize: nil, now: start)
        let core = fixtureMetadata(subrole: kAXStandardWindowSubrole as String)
        let actualSize = CGSize(width: 400, height: 300)

        XCTAssertFalse(state.shouldRecheck(
            coreMetadata: core,
            observedSize: actualSize,
            isVisibleActive: true,
            isPaused: false,
            now: start.addingTimeInterval(6)
        ))
        state.recordObservedSizeIfNeeded(actualSize)
        XCTAssertEqual(state.baselineSize, actualSize)
        XCTAssertFalse(state.shouldRecheck(
            coreMetadata: core,
            observedSize: actualSize,
            isVisibleActive: true,
            isPaused: false,
            now: start.addingTimeInterval(6)
        ))
        XCTAssertTrue(state.shouldRecheck(
            coreMetadata: core,
            observedSize: CGSize(width: 640, height: 480),
            isVisibleActive: true,
            isPaused: false,
            now: start.addingTimeInterval(6)
        ))
    }

    func testFixedSizeRecoveryExcludesPausedAndIneligibleShapes() {
        let start = Date(timeIntervalSinceReferenceDate: 100)
        let state = FixedSizeRecoveryState.seeded(
            observedSize: CGSize(width: 400, height: 300),
            now: start
        )
        let changedSize = CGSize(width: 640, height: 480)

        XCTAssertFalse(state.shouldRecheck(
            coreMetadata: fixtureMetadata(subrole: kAXStandardWindowSubrole as String),
            observedSize: changedSize,
            isVisibleActive: false,
            isPaused: false,
            now: start.addingTimeInterval(6)
        ))
        XCTAssertFalse(state.shouldRecheck(
            coreMetadata: fixtureMetadata(subrole: kAXStandardWindowSubrole as String),
            observedSize: changedSize,
            isVisibleActive: true,
            isPaused: true,
            now: start.addingTimeInterval(6)
        ))
        XCTAssertFalse(state.shouldRecheck(
            coreMetadata: fixtureMetadata(subrole: kAXStandardWindowSubrole as String),
            observedSize: nil,
            isVisibleActive: true,
            isPaused: false,
            now: start.addingTimeInterval(6)
        ))
        XCTAssertFalse(state.shouldRecheck(
            coreMetadata: fixtureMetadata(subrole: kAXStandardWindowSubrole as String),
            observedSize: .zero,
            isVisibleActive: true,
            isPaused: false,
            now: start.addingTimeInterval(6)
        ))
        XCTAssertFalse(state.shouldRecheck(
            coreMetadata: fixtureMetadata(
                subrole: kAXStandardWindowSubrole as String,
                isMinimized: true
            ),
            observedSize: changedSize,
            isVisibleActive: true,
            isPaused: false,
            now: start.addingTimeInterval(6)
        ))
        XCTAssertFalse(state.shouldRecheck(
            coreMetadata: fixtureMetadata(
                subrole: kAXStandardWindowSubrole as String,
                isFullscreen: true
            ),
            observedSize: changedSize,
            isVisibleActive: true,
            isPaused: false,
            now: start.addingTimeInterval(6)
        ))
        XCTAssertFalse(state.shouldRecheck(
            coreMetadata: fixtureMetadata(
                subrole: kAXStandardWindowSubrole as String,
                windowLayer: 3
            ),
            observedSize: changedSize,
            isVisibleActive: true,
            isPaused: false,
            now: start.addingTimeInterval(6)
        ))
    }

    func testFreshWritableCapabilityEvidenceReadmitsFixedSizeWindowToLayout() {
        let retained = fixtureMetadata(
            subrole: kAXStandardWindowSubrole as String,
            positionSettable: .trueValue,
            sizeSettable: .falseValue
        )
        let refreshed = AccessibilityWindow.refreshingMoveResizeCapabilities(
            coreMetadata: retained,
            retaining: retained,
            positionSettable: .trueValue,
            sizeSettable: .trueValue
        )

        XCTAssertEqual(AccessibilityWindow.admissionDecision(for: refreshed),
                       decision(.managedNormal, .normalWindow))
        XCTAssertTrue(WorkspaceEngine.layoutDecision(
            layoutOverride: .automatic,
            admissionDecision: AccessibilityWindow.admissionDecision(for: refreshed),
            rule: .none
        ).includesInLayout)
    }

    func testFixedSizeRecoveryPreservesCurrentTemporaryAndIgnoredAdmission() {
        let ordinary = fixtureMetadata(subrole: kAXStandardWindowSubrole as String)
        let temporary = WindowAdmissionMetadata(
            bundleIdentifier: "dev.appranger.DesktopRanger.SurfaceLab",
            accessibilityIdentifierObservation: .unavailable,
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            windowLayer: 0,
            isMinimized: false,
            closeButton: .present
        )
        let ignored = fixtureMetadata(
            bundleIdentifier: "dev.appranger.DesktopRanger.SurfaceLab",
            accessibilityIdentifier: AccessibilityWindow.desktopRangerSurfaceAccessibilityIdentifier,
            subrole: kAXStandardWindowSubrole as String,
            windowLayer: 0
        )
        let capabilityProvenFixed = fixtureMetadata(
            subrole: kAXStandardWindowSubrole as String,
            positionSettable: .trueValue,
            sizeSettable: .falseValue
        )

        XCTAssertEqual(
            AccessibilityWindow.effectiveAdmissionDecision(
                genericDecision: AccessibilityWindow.admissionDecision(for: temporary),
                metadata: temporary,
                hasFixedSizeRecoveryState: true
            ),
            AccessibilityWindow.admissionDecision(for: temporary)
        )
        XCTAssertEqual(
            AccessibilityWindow.effectiveAdmissionDecision(
                genericDecision: AccessibilityWindow.admissionDecision(for: ignored),
                metadata: ignored,
                hasFixedSizeRecoveryState: true
            ),
            AccessibilityWindow.admissionDecision(for: ignored)
        )
        XCTAssertEqual(
            AccessibilityWindow.effectiveAdmissionDecision(
                genericDecision: AccessibilityWindow.admissionDecision(for: ordinary),
                metadata: ordinary,
                hasFixedSizeRecoveryState: true
            ),
            decision(.managedDialog, .fixedSizeStandardWindow)
        )
        XCTAssertTrue(AccessibilityWindow.shouldRecheckFixedSizeCapabilities(
            for: AccessibilityWindow.admissionDecision(for: ordinary)
        ))
        XCTAssertTrue(AccessibilityWindow.shouldRecheckFixedSizeCapabilities(
            for: AccessibilityWindow.admissionDecision(for: capabilityProvenFixed)
        ))
        XCTAssertFalse(AccessibilityWindow.shouldRecheckFixedSizeCapabilities(
            for: AccessibilityWindow.admissionDecision(for: temporary)
        ))
        XCTAssertFalse(AccessibilityWindow.shouldRecheckFixedSizeCapabilities(
            for: AccessibilityWindow.admissionDecision(for: ignored)
        ))
    }

    func testStandardWindowDialogControlProbeRequiresTheNarrowCloselessShapeAndRunsOnce() {
        let candidate = WindowAdmissionMetadata(
            bundleIdentifier: "com.example.Editor",
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            windowLayer: nil,
            isMinimized: false,
            fullscreenButton: .absent,
            closeButton: .absent
        )
        XCTAssertTrue(AccessibilityWindow.shouldCollectStandardWindowDialogControlEvidence(candidate))
        XCTAssertTrue(AccessibilityWindow.shouldCollectStandardWindowDialogSupportMetadata(
            coreMetadata: candidate,
            retainedMetadata: candidate
        ))

        let attempted = WindowAdmissionMetadata(
            bundleIdentifier: "com.example.Editor",
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            windowLayer: nil,
            isMinimized: false,
            fullscreenButton: .absent,
            closeButton: .absent,
            supportMetadataWasCollected: true
        )
        XCTAssertFalse(AccessibilityWindow.shouldCollectStandardWindowDialogSupportMetadata(
            coreMetadata: candidate,
            retainedMetadata: attempted
        ))
        XCTAssertFalse(AccessibilityWindow.shouldCollectStandardWindowDialogControlEvidence(
            fixtureMetadata(
                subrole: kAXStandardWindowSubrole as String,
                fullscreenButton: .present,
                closeButton: .present
            )
        ))
        XCTAssertFalse(AccessibilityWindow.shouldCollectStandardWindowDialogControlEvidence(
            fixtureMetadata(
                subrole: kAXDialogSubrole as String,
                fullscreenButton: .absent,
                closeButton: .absent
            )
        ))
        XCTAssertFalse(AccessibilityWindow.shouldCollectStandardWindowDialogControlEvidence(
            fixtureMetadata(
                subrole: kAXStandardWindowSubrole as String,
                windowLayer: 8,
                fullscreenButton: .absent,
                closeButton: .absent
            )
        ))
    }

    func testNativeFilePanelIdentifierObservationReducesRawIdentifiersImmediately() {
        XCTAssertEqual(
            AccessibilityWindow.nativeFilePanelIdentifierObservation(
                accessibilityIdentifier: "open-panel"
            ),
            .trueValue
        )
        XCTAssertEqual(
            AccessibilityWindow.nativeFilePanelIdentifierObservation(
                accessibilityIdentifier: "SAVE-PANEL"
            ),
            .trueValue
        )
        XCTAssertEqual(
            AccessibilityWindow.nativeFilePanelIdentifierObservation(
                accessibilityIdentifier: "document-window"
            ),
            .falseValue
        )
        XCTAssertEqual(
            AccessibilityWindow.nativeFilePanelIdentifierObservation(
                accessibilityIdentifier: nil
            ),
            .unsupported
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
            defaultButton: .present,
            cancelButton: .present,
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
        XCTAssertEqual(merged.defaultButton, .present)
        XCTAssertEqual(merged.cancelButton, .present)
        XCTAssertEqual(merged.positionSettable, .trueValue)
        XCTAssertEqual(merged.sizeSettable, .falseValue)
        XCTAssertTrue(merged.supportMetadataWasCollected)
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
        name: "captured fixed-size Simulator device window floats through generic capability evidence",
        metadata: fixtureMetadata(
            bundleIdentifier: "com.apple.iphonesimulator",
            subrole: kAXStandardWindowSubrole as String,
            windowLayer: 0,
            fullscreenButton: .present,
            minimizeButton: .present,
            closeButton: .present,
            zoomButton: .present,
            positionSettable: .trueValue,
            sizeSettable: .falseValue
        ),
        expected: decision(
            .managedDialog,
            .fixedSizeStandardWindow
        )
    ),
    WindowAdmissionFixture(
        name: "live TextEdit Open panel floats through its native panel identifier",
        metadata: fixtureMetadata(
            bundleIdentifier: "com.apple.TextEdit",
            subrole: kAXStandardWindowSubrole as String,
            windowLayer: nil,
            modalObservation: .unsupported,
            focusedObservation: .unsupported,
            mainObservation: .unsupported,
            fullscreenButton: .absent,
            minimizeButton: .unavailable,
            closeButton: .absent,
            zoomButton: .unavailable,
            defaultButton: .absent,
            cancelButton: .absent,
            nativeFilePanelIdentifierObservation: .trueValue,
            positionSettable: .trueValue,
            sizeSettable: .trueValue
        ),
        expected: decision(.managedDialog, .nativeFilePanelIdentifier)
    ),
    WindowAdmissionFixture(
        name: "movable resizable Save panel still floats through structural dialog controls",
        metadata: fixtureMetadata(
            subrole: kAXStandardWindowSubrole as String,
            fullscreenButton: .absent,
            closeButton: .absent,
            defaultButton: .present,
            cancelButton: .present,
            positionSettable: .trueValue,
            sizeSettable: .trueValue
        ),
        expected: decision(.managedDialog, .standardWindowWithDialogControls)
    ),
    WindowAdmissionFixture(
        name: "closeless standard window with failed dialog-control reads stays managed",
        metadata: fixtureMetadata(
            subrole: kAXStandardWindowSubrole as String,
            fullscreenButton: .absent,
            closeButton: .absent,
            defaultButton: .unavailable,
            cancelButton: .unavailable
        ),
        expected: decision(.managedNormal, .normalWindow)
    ),
    WindowAdmissionFixture(
        name: "unrelated closeless identifier does not float a standard window",
        metadata: fixtureMetadata(
            subrole: kAXStandardWindowSubrole as String,
            fullscreenButton: .absent,
            closeButton: .absent,
            defaultButton: .absent,
            cancelButton: .absent,
            nativeFilePanelIdentifierObservation: .falseValue
        ),
        expected: decision(.managedNormal, .normalWindow)
    ),
    WindowAdmissionFixture(
        name: "native panel identifier cannot override ordinary document controls",
        metadata: fixtureMetadata(
            subrole: kAXStandardWindowSubrole as String,
            fullscreenButton: .present,
            closeButton: .present,
            nativeFilePanelIdentifierObservation: .trueValue
        ),
        expected: decision(.managedNormal, .normalWindow)
    ),
    WindowAdmissionFixture(
        name: "closeless standard window with only a default button stays managed",
        metadata: fixtureMetadata(
            subrole: kAXStandardWindowSubrole as String,
            fullscreenButton: .absent,
            closeButton: .absent,
            defaultButton: .present,
            cancelButton: .absent
        ),
        expected: decision(.managedNormal, .normalWindow)
    ),
    WindowAdmissionFixture(
        name: "closeless standard window with only a cancel button stays managed",
        metadata: fixtureMetadata(
            subrole: kAXStandardWindowSubrole as String,
            fullscreenButton: .absent,
            closeButton: .absent,
            defaultButton: .absent,
            cancelButton: .present
        ),
        expected: decision(.managedNormal, .normalWindow)
    ),
    WindowAdmissionFixture(
        name: "ordinary document controls win over embedded default and cancel relationships",
        metadata: fixtureMetadata(
            subrole: kAXStandardWindowSubrole as String,
            fullscreenButton: .present,
            closeButton: .present,
            defaultButton: .present,
            cancelButton: .present
        ),
        expected: decision(.managedNormal, .normalWindow)
    ),
    WindowAdmissionFixture(
        name: "known non-normal standard layer does not use the dialog-control rule",
        metadata: fixtureMetadata(
            subrole: kAXStandardWindowSubrole as String,
            windowLayer: 3,
            fullscreenButton: .absent,
            closeButton: .absent,
            defaultButton: .present,
            cancelButton: .present
        ),
        expected: decision(.managedNormal, .normalWindow)
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
        name: "captured Codex update precursor is ignored",
        metadata: fixtureMetadata(
            bundleIdentifier: "com.openai.codex",
            subrole: kAXStandardWindowSubrole as String,
            windowLayer: 0,
            modalObservation: .falseValue,
            mainObservation: .trueValue,
            fullscreenButton: .absent,
            minimizeButton: .absent,
            closeButton: .absent,
            zoomButton: .absent,
            defaultButton: .absent,
            cancelButton: .absent,
            positionSettable: .trueValue,
            sizeSettable: .falseValue
        ),
        expected: decision(
            .ignoredTransientPopup,
            .verifiedBundleTransientStandardWindow,
            compatibilityProfileIdentifier: "codex-update-precursor-v1"
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
    defaultButton: AXAttributePresence = .absent,
    cancelButton: AXAttributePresence = .absent,
    nativeFilePanelIdentifierObservation: AXBooleanAttributeObservation = .unsupported,
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
        defaultButton: defaultButton,
        cancelButton: cancelButton,
        nativeFilePanelIdentifierObservation: nativeFilePanelIdentifierObservation,
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
