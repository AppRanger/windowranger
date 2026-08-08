import ApplicationServices
import XCTest

final class DiagnosticLoggerTests: XCTestCase {
    func testReleaseLoggerDoesNotCreateVerboseFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("diagnostics.jsonl")
        let logger = DiagnosticLogger.make(buildMode: .release, fileURL: fileURL)

        logger.log(category: "test", event: "must-not-write")

        XCTAssertFalse(logger.isVerbose)
        XCTAssertNil(logger.fileURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testDebugLoggerWritesStructuredCorrelatedSequence() throws {
        let sink = MemoryDiagnosticSink()
        let logger = DiagnosticLogger(
            buildMode: .debug,
            sink: sink,
            sessionIdentifier: "session-test"
        )
        let correlation = "action-test"

        logger.log(category: "hotkey", event: "received", correlation: correlation)
        logger.log(category: "focus-cycle", event: "target-chosen", correlation: correlation)

        let records = try decodedRecords(sink.text)
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.map { $0["sequence"] as? Int }, [1, 2])
        XCTAssertEqual(records.map { $0["session"] as? String }, ["session-test", "session-test"])
        XCTAssertEqual(records.map { $0["correlation"] as? String }, [correlation, correlation])
        XCTAssertEqual(records.map { $0["event"] as? String }, ["received", "target-chosen"])
    }

    func testCopiedDiagnosticsRetainsLatestActionAfterNoisyBackgroundAndUsesCompleteLines() throws {
        let sink = MemoryDiagnosticSink()
        let logger = DiagnosticLogger(
            buildMode: .debug,
            sink: sink,
            sessionIdentifier: "copy-session"
        )
        logger.log(
            category: "hotkey",
            event: "received",
            correlation: "action-important",
            fields: ["action": "cycle-window"]
        )
        logger.log(
            category: "focus-cycle",
            event: "target-chosen",
            correlation: "action-important",
            fields: ["window": "100:200"]
        )
        for index in 0..<500 {
            logger.log(
                category: "background",
                event: "noise",
                fields: ["index": String(index), "payload": String(repeating: "x", count: 80)]
            )
        }

        let copied = logger.recentDiagnosticsText(maxBytes: 4_096)

        XCTAssertTrue(copied.contains("action-important"))
        XCTAssertTrue(copied.contains("cycle-window"))
        for line in copied.split(separator: "\n") where line.first == "{" {
            XCTAssertNoThrow(
                try JSONSerialization.jsonObject(with: Data(line.utf8)),
                "Invalid copied diagnostics line: \(line)"
            )
        }
    }

    func testCompleteJSONLineSuffixDropsPartialFirstRecord() throws {
        let data = Data("partial-field\n{\"sequence\":2}\n{\"sequence\":3}\n".utf8)

        let suffix = DiagnosticLogger.completeJSONLinesSuffix(from: data, maxBytes: data.count)
        let text = String(decoding: suffix, as: UTF8.self)

        XCTAssertEqual(text, "{\"sequence\":2}\n{\"sequence\":3}\n")
        _ = try decodedRecords(text)
    }

    func testCompleteJSONLineSuffixDropsPartialLastRecord() throws {
        let data = Data("{\"sequence\":1}\n{\"sequence\":2}\n{\"sequence\":".utf8)

        let suffix = DiagnosticLogger.completeJSONLinesSuffix(from: data, maxBytes: data.count)
        let text = String(decoding: suffix, as: UTF8.self)

        XCTAssertEqual(text, "{\"sequence\":1}\n{\"sequence\":2}\n")
        _ = try decodedRecords(text)
    }

    func testPrivacyFilterRemovesForbiddenFieldsAndSensitiveValues() {
        let sink = MemoryDiagnosticSink()
        let logger = DiagnosticLogger(buildMode: .test, sink: sink)

        logger.log(
            category: "privacy",
            event: "sample",
            fields: [
                "window-title": "Private quarterly plan",
                "document-name": "Secret.docx",
                "source-url": "https://private.example/path",
                "typed-content": "password-like text",
                "safe-path-shaped-value": "/Users/chris/private/file",
                "bundle": "com.example.SafeApp",
            ]
        )

        XCTAssertFalse(sink.text.contains("Private quarterly plan"))
        XCTAssertFalse(sink.text.contains("Secret.docx"))
        XCTAssertFalse(sink.text.contains("private.example"))
        XCTAssertFalse(sink.text.contains("password-like"))
        XCTAssertFalse(sink.text.contains("/Users/chris"))
        XCTAssertTrue(sink.text.contains("com.example.SafeApp"))
        XCTAssertTrue(sink.text.contains("[redacted]"))
    }

    func testRotatingSinkCapsStorageAndKeepsBoundedBackups() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("diagnostics.jsonl")
        let logger = DiagnosticLogger(
            buildMode: .debug,
            sink: RotatingFileDiagnosticSink(fileURL: fileURL, maxBytes: 1_024, backupCount: 2)
        )

        for index in 0..<40 {
            logger.log(
                category: "rotation",
                event: "record",
                fields: ["index": String(index), "safe-payload": String(repeating: "x", count: 300)]
            )
        }

        let currentSize = ((try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size]) as? NSNumber)?.intValue
        XCTAssertNotNil(currentSize)
        XCTAssertLessThanOrEqual(currentSize ?? .max, 1_024)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path + ".1"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path + ".2"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path + ".3"))
    }

    func testInteractionDisplayUsesActualFocusedFrameOnSecondDisplay() {
        let displays = [
            DisplaySnapshot(
                identifier: "main-display-long-id",
                bounds: CGRect(x: 0, y: 0, width: 1_440, height: 900),
                isMain: true,
                name: "Main"
            ),
            DisplaySnapshot(
                identifier: "second-display-long-id",
                bounds: CGRect(x: 1_440, y: 0, width: 1_920, height: 1_080),
                isMain: false,
                name: "Second"
            ),
        ]
        let focusedFrame = WindowFrame(
            position: CGPoint(x: 1_700, y: 100),
            size: CGSize(width: 800, height: 700)
        )

        let result = WorkspaceEngine.interactionDisplaySelection(
            focusedFrame: focusedFrame,
            mode: .unified,
            managedWorkspaceHomeDisplayIdentifier: "main-display-long-id",
            displays: displays
        )

        XCTAssertEqual(result.identifier, "second-display-long-id")
        XCTAssertEqual(result.reason, "focused-window-frame")
    }

    func testTemporaryNilFocusKeepsNextHotkeyOnRecentExternalDisplay() {
        let displays = [
            DisplaySnapshot(
                identifier: "main",
                bounds: CGRect(x: 0, y: 0, width: 1_440, height: 900),
                isMain: true,
                name: "Main"
            ),
            DisplaySnapshot(
                identifier: "external",
                bounds: CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080),
                isMain: false,
                name: "External"
            ),
        ]

        let result = WorkspaceEngine.interactionDisplaySelection(
            focusedFrame: nil,
            mode: .independent,
            managedWorkspaceHomeDisplayIdentifier: nil,
            recentInteractionDisplayIdentifier: "external",
            displays: displays
        )

        XCTAssertEqual(result.identifier, "external")
        XCTAssertEqual(result.reason, "recent-action-display-no-focused-frame")
    }

    func testActiveSameAppCrossDisplayFocusDoesNotReactivateApplication() {
        XCTAssertEqual(
            WorkspaceEngine.exactWindowFocusPlan(applicationIsActive: true),
            [.markWindowMain, .focusWindowElement, .focusApplicationWindow, .raiseWindow]
        )
        XCTAssertEqual(
            WorkspaceEngine.exactWindowFocusPlan(applicationIsActive: false),
            [
                .markWindowMain,
                .raiseWindow,
                .activateApplication,
                .markWindowMain,
                .focusWindowElement,
                .focusApplicationWindow,
                .raiseWindow,
            ]
        )
        XCTAssertTrue(WorkspaceEngine.shouldReassertAfterActivation(
            activatedProcessIdentifier: 100,
            focusedProcessIdentifier: 100
        ))
        XCTAssertFalse(WorkspaceEngine.shouldReassertAfterActivation(
            activatedProcessIdentifier: 100,
            focusedProcessIdentifier: 200
        ))
    }

    func testFocusCycleEligibilityRejectsUtilityLayerAndKeepsCapableNormalWindow() {
        let normal = WindowFocusCapabilities(
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            windowLayer: 0,
            isMinimized: false,
            isFocused: false,
            isMain: false,
            focusedAttributeSettable: true,
            mainAttributeSettable: true,
            applicationFocusedWindowAttributeSettable: true,
            raiseActionSupported: true
        )
        XCTAssertTrue(AccessibilityWindow.isEligibleFocusCycleCandidate(normal))

        let utilityPanel = WindowFocusCapabilities(
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            windowLayer: 3,
            isMinimized: false,
            isFocused: false,
            isMain: false,
            focusedAttributeSettable: true,
            mainAttributeSettable: true,
            applicationFocusedWindowAttributeSettable: true,
            raiseActionSupported: true
        )
        XCTAssertFalse(AccessibilityWindow.isEligibleFocusCycleCandidate(utilityPanel))

        let nonFocusable = WindowFocusCapabilities(
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            windowLayer: 0,
            isMinimized: false,
            isFocused: false,
            isMain: false,
            focusedAttributeSettable: false,
            mainAttributeSettable: false,
            applicationFocusedWindowAttributeSettable: false,
            raiseActionSupported: true
        )
        XCTAssertFalse(AccessibilityWindow.isEligibleFocusCycleCandidate(nonFocusable))
    }

    func testSameAppWrongWindowRetriesThenAdvancesDespiteSuccessfulAXWrites() {
        let expected = WindowKey(processIdentifier: 42394, windowIdentifier: 15153)
        let wrongSameApp = WindowKey(processIdentifier: 42394, windowIdentifier: 14533)

        XCTAssertEqual(
            WorkspaceEngine.focusCycleVerificationDecision(
                expected: expected,
                actual: wrongSameApp,
                applicationIsActive: true,
                exactAttempt: 0,
                maximumExactAttempts: 1
            ),
            .retryExactTarget
        )
        XCTAssertEqual(
            WorkspaceEngine.focusCycleVerificationDecision(
                expected: expected,
                actual: wrongSameApp,
                applicationIsActive: true,
                exactAttempt: 1,
                maximumExactAttempts: 1
            ),
            .advanceToNextCandidate
        )
    }

    func testFocusCycleVerificationDoesNotOverrideGenuineCompetingAppFocus() {
        let expected = WindowKey(processIdentifier: 42394, windowIdentifier: 15153)
        let competing = WindowKey(processIdentifier: 13768, windowIdentifier: 16704)

        XCTAssertEqual(
            WorkspaceEngine.focusCycleVerificationDecision(
                expected: expected,
                actual: competing,
                applicationIsActive: false,
                exactAttempt: 0
            ),
            .abortForCompetingFocus
        )
        XCTAssertEqual(
            WorkspaceEngine.focusCycleVerificationDecision(
                expected: expected,
                actual: expected,
                applicationIsActive: true,
                exactAttempt: 0
            ),
            .succeeded
        )
    }

    func testCycleAttemptOrderStaysInUserOrderAndSkipsCurrentWindow() {
        let ordered = ["slack", "codex-panel", "codex-a", "codex-b"]
        XCTAssertEqual(
            WorkspaceEngine.focusCycleAttemptOrder(
                current: "slack",
                orderedCandidates: ordered,
                offset: 1
            ),
            ["codex-panel", "codex-a", "codex-b"]
        )
        XCTAssertEqual(
            WorkspaceEngine.focusCycleAttemptOrder(
                current: "codex-a",
                orderedCandidates: ordered,
                offset: -1
            ),
            ["codex-panel", "slack", "codex-b"]
        )
    }

    func testRapidActionsSupersedeOlderFocusVerification() {
        let older = FocusVerificationToken(generation: 4, correlationID: "action-old")
        let newer = FocusVerificationToken(generation: 5, correlationID: "action-new")

        XCTAssertFalse(WorkspaceEngine.verificationIsCurrent(older, generation: 5))
        XCTAssertTrue(WorkspaceEngine.verificationIsCurrent(newer, generation: 5))
    }

    func testRapidCycleUsesRecentExternalTargetWhenAXFocusIsTemporarilyNil() {
        let candidates = ["external-a", "external-b", "external-c"]
        let context = WorkspaceEngine.interactionFocusContext(
            focused: nil as String?,
            recent: "external-b",
            recentIsValid: true
        )

        XCTAssertEqual(context, "external-b")
        XCTAssertEqual(
            WorkspaceEngine.focusCycleTarget(
                current: context,
                orderedCandidates: candidates,
                offset: 1
            ),
            "external-c"
        )
    }

    func testNilFocusRecoveryRequiresCurrentActionAndActiveExpectedApp() {
        XCTAssertTrue(WorkspaceEngine.shouldRecoverNilFocus(
            hasExpectedWindow: true,
            hasActualWindow: false,
            applicationIsActive: true,
            verificationIsCurrent: true
        ))
        XCTAssertFalse(WorkspaceEngine.shouldRecoverNilFocus(
            hasExpectedWindow: true,
            hasActualWindow: true,
            applicationIsActive: true,
            verificationIsCurrent: true
        ))
        XCTAssertFalse(WorkspaceEngine.shouldRecoverNilFocus(
            hasExpectedWindow: true,
            hasActualWindow: false,
            applicationIsActive: false,
            verificationIsCurrent: true
        ))
    }

    func testUnchangedBackgroundLayoutDoesNotRetryRejectedTargetUntilInputChanges() {
        let rejectedObservedState = "window=1|actual=unchanged|target=rejected"
        XCTAssertTrue(WorkspaceEngine.shouldApplyBackgroundLayout(
            previousSignature: nil,
            currentSignature: rejectedObservedState,
            isStartup: false
        ))
        XCTAssertFalse(WorkspaceEngine.shouldApplyBackgroundLayout(
            previousSignature: rejectedObservedState,
            currentSignature: rejectedObservedState,
            isStartup: false
        ))
        XCTAssertTrue(WorkspaceEngine.shouldApplyBackgroundLayout(
            previousSignature: rejectedObservedState,
            currentSignature: rejectedObservedState + "|membership-changed",
            isStartup: false
        ))
    }

    func testFocusCycleScopeNeverCrossesKnownInteractionDisplay() {
        XCTAssertTrue(WorkspaceEngine.focusCycleCandidateIsInScope(
            candidateDisplayIdentifier: "second",
            interactionDisplayIdentifier: "second"
        ))
        XCTAssertFalse(WorkspaceEngine.focusCycleCandidateIsInScope(
            candidateDisplayIdentifier: "main",
            interactionDisplayIdentifier: "second"
        ))
        XCTAssertFalse(WorkspaceEngine.focusCycleCandidateIsInScope(
            candidateDisplayIdentifier: nil,
            interactionDisplayIdentifier: "second"
        ))
    }

    func testDisconnectedIndependentHomeLogsAndUsesMainFallback() {
        let displays = [
            DisplaySnapshot(
                identifier: "main",
                bounds: CGRect(x: 0, y: 0, width: 1_440, height: 900),
                isMain: true,
                name: "Main"
            ),
        ]

        let result = WorkspaceEngine.interactionDisplaySelection(
            focusedFrame: nil,
            mode: .independent,
            managedWorkspaceHomeDisplayIdentifier: "disconnected-second",
            displays: displays
        )

        XCTAssertEqual(result.identifier, "main")
        XCTAssertEqual(result.reason, "independent-home-disconnected-main-fallback")
    }

    func testCommandFeedbackCoalescesUpdatesAndRejectsStaleDismissal() {
        var state = CommandFeedbackPresentationState()

        XCTAssertEqual(state.present(), .show)
        let firstGeneration = state.generation
        XCTAssertEqual(state.present(), .update)
        let latestGeneration = state.generation

        XCTAssertFalse(state.dismiss(ifCurrent: firstGeneration))
        XCTAssertTrue(state.isPresented)
        XCTAssertTrue(state.dismiss(ifCurrent: latestGeneration))
        XCTAssertFalse(state.isPresented)
    }

    func testCommandFeedbackCentersOnPreferredExternalDisplay() throws {
        let displays = [
            CommandFeedbackDisplayDescriptor(
                identifier: "main",
                visibleFrame: CGRect(x: 0, y: 24, width: 1_440, height: 876),
                isMain: true
            ),
            CommandFeedbackDisplayDescriptor(
                identifier: "external",
                visibleFrame: CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080),
                isMain: false
            ),
        ]

        let placement = try XCTUnwrap(CommandFeedbackGeometry.placement(
            preferredDisplayIdentifier: "external",
            panelSize: CGSize(width: 360, height: 72),
            displays: displays
        ))

        XCTAssertEqual(placement.displayIdentifier, "external")
        XCTAssertEqual(placement.resolutionReason, "preferred-connected-display")
        XCTAssertEqual(placement.panelFrame.midX, -960, accuracy: 0.001)
        XCTAssertEqual(placement.panelFrame.midY, 540, accuracy: 0.001)
    }

    func testCommandFeedbackUsesMainFallbackWhenPreferredDisplayDisconnects() throws {
        let main = CommandFeedbackDisplayDescriptor(
            identifier: "main",
            visibleFrame: CGRect(x: 0, y: 24, width: 1_440, height: 876),
            isMain: true
        )

        let placement = try XCTUnwrap(CommandFeedbackGeometry.placement(
            preferredDisplayIdentifier: "disconnected",
            panelSize: CGSize(width: 360, height: 72),
            displays: [main]
        ))

        XCTAssertEqual(placement.displayIdentifier, "main")
        XCTAssertEqual(placement.resolutionReason, "preferred-disconnected-main-fallback")
    }

    func testCommandFeedbackGeometryClampsToSmallVisibleFrame() throws {
        let display = CommandFeedbackDisplayDescriptor(
            identifier: "small",
            visibleFrame: CGRect(x: 100, y: 200, width: 220, height: 60),
            isMain: true
        )

        let placement = try XCTUnwrap(CommandFeedbackGeometry.placement(
            preferredDisplayIdentifier: "small",
            panelSize: CGSize(width: 360, height: 72),
            displays: [display]
        ))

        XCTAssertTrue(display.visibleFrame.contains(placement.panelFrame))
        XCTAssertLessThanOrEqual(placement.panelFrame.width, display.visibleFrame.width)
        XCTAssertLessThanOrEqual(placement.panelFrame.height, display.visibleFrame.height)
    }

    func testCommandFeedbackPanelPolicyCannotActivateOrEnterWindowCycle() {
        let policy = CommandFeedbackPanelPolicy.nonActivating

        XCTAssertFalse(policy.canBecomeKey)
        XCTAssertFalse(policy.canBecomeMain)
        XCTAssertTrue(policy.ignoresMouseEvents)
        XCTAssertFalse(policy.participatesInWindowCycle)
    }

    func testFloatingToggleFeedbackUsesSharedCommandFeedbackMessage() {
        XCTAssertEqual(FloatingToggleResult.enabled.commandFeedbackMessage, "Window is floating")
        XCTAssertEqual(
            FloatingToggleResult.disabled.commandFeedbackMessage,
            "Window returned to the workspace layout"
        )
        XCTAssertEqual(
            FloatingToggleResult.blockedByAppRule("Mail").commandFeedbackMessage,
            "Mail is excluded by an App Rule. That rule remains in control."
        )
    }

    @MainActor
    func testDebugConfigurationExposesDiagnosticMenuControls() {
        let enabled = WorkspaceStatusBarController.verboseDiagnosticsMenuEnabled
        #if DEBUG
        XCTAssertTrue(enabled)
        #else
        XCTAssertFalse(enabled)
        #endif
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WindowManagerDiagnosticTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func decodedRecords(_ text: String) throws -> [[String: Any]] {
        try text.split(separator: "\n").map { line in
            let object = try JSONSerialization.jsonObject(with: Data(line.utf8))
            return try XCTUnwrap(object as? [String: Any])
        }
    }
}
