import AppKit
import XCTest

final class FocusedWindowDiagnosticReportTests: XCTestCase {
    private let timestamp = Date(timeIntervalSince1970: 1_754_694_400.125)

    func testSchemaAndOutputAreStable() {
        let first = FocusedWindowDiagnosticReport.render(snapshot())
        let second = FocusedWindowDiagnosticReport.render(snapshot())

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.hasPrefix("WindowRanger focused-window diagnostic report\nschema-version: 1\n"))
        XCTAssertTrue(first.contains("target-status: managed"))
        XCTAssertTrue(first.contains("ax-focused: true"))
    }

    func testAllRequiredManagementStatesRemainExplicit() {
        let cases: [(String, String)] = [
            ("managed", "layout-decision: managed-normal"),
            ("ignored", "admission-disposition: ignored-transient-popup"),
            ("deferred", "temporarily-deferred: true"),
            ("floating", "layout-decision: explicitly-floating"),
            ("excluded", "layout-decision: app-rule-excluded"),
            ("minimized", "ax-minimized: true"),
            ("full-screen", "ax-fullscreen: true"),
            ("parked", "parking-state: expected-parked"),
            ("stale", "expected-frame-matches-observed: unavailable (stale observation)"),
        ]

        for (status, evidence) in cases {
            let report = FocusedWindowDiagnosticReport.render(snapshot(
                targetStatus: status,
                accessibility: evidence.hasPrefix("ax-") ? [(String(evidence.split(separator: ":")[0]), .value("true"))] : nil,
                management: evidence.hasPrefix("ax-") ? nil : [reportPair(evidence)]
            ))
            XCTAssertTrue(report.contains("target-status: \(status)"), status)
            XCTAssertTrue(report.contains(evidence), status)
        }
    }

    func testUnavailableAndFailedReadsAreNotRenderedAsFalse() {
        let report = FocusedWindowDiagnosticReport.render(snapshot(accessibility: [
            ("ax-focused", .failed("AXError -25204")),
            ("ax-main", .unavailable("unsupported")),
        ]))

        XCTAssertTrue(report.contains("ax-focused: failed (AXError -25204)"))
        XCTAssertTrue(report.contains("ax-main: unavailable (unsupported)"))
        XCTAssertFalse(report.contains("ax-focused: false"))
        XCTAssertFalse(report.contains("ax-main: false"))
    }

    func testNoTargetAndAccessibilityUnavailableAreClearOutcomes() {
        for status in ["no-target", "accessibility-unavailable"] {
            let report = FocusedWindowDiagnosticReport.render(snapshot(
                targetStatus: status,
                bundle: .unavailable(status),
                window: .unavailable(status),
                accessibility: [],
                management: []
            ))
            XCTAssertTrue(report.contains("target-status: \(status)"))
            XCTAssertTrue(report.contains("target-window-identifier: unavailable (\(status))"))
        }
    }

    func testRenderingIsPureAndDoesNotMutateSnapshot() {
        let value = snapshot()
        let original = value

        _ = FocusedWindowDiagnosticReport.render(value)

        XCTAssertEqual(value, original)
    }

    func testFinalPrivacyPassRedactsForbiddenValuesFromEverySource() {
        let secretURL = "https://example.test/private"
        let secretPath = "/Users/alice/Documents/secret.txt"
        let report = FocusedWindowDiagnosticReport.render(snapshot(
            appVersion: secretPath,
            appBuild: secretURL,
            macOS: secretPath,
            session: secretURL,
            targetStatus: secretPath,
            bundle: .value(secretURL),
            window: .value(secretPath),
            accessibility: [("ax-role", .value(secretPath))],
            management: [("layout", .value(secretURL))],
            history: "{\"event\":\"\(secretPath)\"}\n"
        ))

        XCTAssertFalse(report.contains(secretURL))
        XCTAssertFalse(report.contains(secretPath))
        XCTAssertTrue(report.contains("[redacted]"))
        XCTAssertTrue(report.contains(DiagnosticLogger.privacySummary))
    }

    func testReportIsBoundedAndEndsWithTruncationMarker() {
        let report = FocusedWindowDiagnosticReport.render(snapshot(
            history: String(repeating: "{\"event\":\"safe\"}\n", count: 10_000)
        ))

        XCTAssertLessThanOrEqual(report.utf8.count, FocusedWindowDiagnosticSnapshot.maximumReportBytes)
        XCTAssertTrue(report.contains("[report-truncated-at-64000-bytes]"))
    }

    func testReleaseBuildCanRevealFocusedReportWithoutVerboseLog() {
        XCTAssertTrue(FocusedWindowSupportMenuPolicy.isVisible(modifierFlags: [.option]))
        XCTAssertFalse(FocusedWindowSupportMenuPolicy.isVisible(modifierFlags: []))
        XCTAssertEqual(VerboseDiagnosticsMenuPolicy.entries(
            buildSupportsVerboseDiagnostics: false,
            modifierFlags: [.option],
            diagnosticFileAvailable: false
        ), [])
    }

    func testRelatedHistoryIsBoundedAndFiltersUnrelatedActions() {
        let logger = DiagnosticLogger(
            buildMode: .release,
            sink: NoOpDiagnosticSink(),
            sessionIdentifier: "support-test",
            isVerbose: false,
            capturesSupportHistory: true
        )
        logger.log(category: "command", event: "begin", correlation: "action-a", fields: ["window": "1:2"])
        logger.log(category: "command", event: "result", correlation: "action-a", fields: ["result": "success"])
        logger.log(category: "command", event: "begin", correlation: "action-b", fields: ["window": "9:9"])

        let history = logger.relatedDiagnosticsText(windowToken: "1:2", maxBytes: 4_096)

        XCTAssertTrue(history.contains("action-a"))
        XCTAssertTrue(history.contains("success"))
        XCTAssertFalse(history.contains("action-b"))
        XCTAssertLessThanOrEqual(history.utf8.count, 4_096)
        XCTAssertNil(logger.fileURL)
        XCTAssertFalse(logger.isVerbose)
    }

    func testRelatedHistoryMatchesOnlyStructuredWindowFieldTokens() {
        let metadataOnlyLogger = DiagnosticLogger(
            buildMode: .release,
            sink: NoOpDiagnosticSink(),
            sessionIdentifier: "1:2",
            isVerbose: false,
            capturesSupportHistory: true
        )
        metadataOnlyLogger.log(
            category: "1:2",
            event: "1:2",
            correlation: "1:2",
            fields: ["window": "9:9"]
        )

        XCTAssertEqual(metadataOnlyLogger.relatedDiagnosticsText(windowToken: "1:2"), "")
        XCTAssertTrue(DiagnosticLogger.fieldValue("1:2", referencesWindowToken: "1:2"))
        XCTAssertTrue(DiagnosticLogger.fieldValue("1:2,9:9", referencesWindowToken: "1:2"))
        XCTAssertTrue(DiagnosticLogger.fieldValue("window=1:2", referencesWindowToken: "1:2"))
        XCTAssertFalse(DiagnosticLogger.fieldValue("11:2", referencesWindowToken: "1:2"))
        XCTAssertFalse(DiagnosticLogger.fieldValue("1:20", referencesWindowToken: "1:2"))
        XCTAssertFalse(DiagnosticLogger.fieldValue(
            "2026-08-11T19:01:25.000Z",
            referencesWindowToken: "1:2"
        ))
    }

    private func snapshot(
        appVersion: String = "0.1.0",
        appBuild: String = "42",
        macOS: String = "Version 15.6",
        session: String = "ws:123:456",
        targetStatus: String = "managed",
        bundle: DiagnosticReportValue = .value("com.example.Editor"),
        window: DiagnosticReportValue = .value("123:456"),
        accessibility: [(String, DiagnosticReportValue)]? = nil,
        management: [(String, DiagnosticReportValue)]? = nil,
        history: String = ""
    ) -> FocusedWindowDiagnosticSnapshot {
        FocusedWindowDiagnosticSnapshot(
            timestamp: timestamp,
            appVersion: appVersion,
            appBuild: appBuild,
            buildMode: "Release",
            macOSVersion: macOS,
            windowServerSession: session,
            targetStatus: targetStatus,
            targetBundleIdentifier: bundle,
            targetWindowIdentifier: window,
            accessibility: accessibility ?? [
                ("ax-role", .value("AXWindow")),
                ("ax-focused", .value("true")),
                ("ax-minimized", .value("false")),
                ("ax-fullscreen", .value("false")),
            ],
            management: management ?? [
                ("admission-disposition", .value("managed-normal")),
                ("layout-decision", .value("managed-normal")),
                ("parking-state", .value("not-expected-parked")),
            ],
            relatedHistory: history
        )
    }

    private func reportPair(_ line: String) -> (String, DiagnosticReportValue) {
        let pieces = line.split(separator: ":", maxSplits: 1).map(String.init)
        let value = pieces[1].trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("unavailable (") {
            return (pieces[0], .unavailable(String(value.dropFirst(13).dropLast())))
        }
        return (pieces[0], .value(value))
    }
}
