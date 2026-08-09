import Foundation

enum DiagnosticReportValue: Equatable, Sendable {
    case value(String)
    case unavailable(String)
    case failed(String)

    var rendered: String {
        switch self {
        case let .value(value): value
        case let .unavailable(reason): "unavailable (\(reason))"
        case let .failed(reason): "failed (\(reason))"
        }
    }
}

struct FocusedWindowDiagnosticSnapshot: Equatable, Sendable {
    static let schemaVersion = 1
    static let maximumReportBytes = 64_000

    let timestamp: Date
    let appVersion: String
    let appBuild: String
    let buildMode: String
    let macOSVersion: String
    let windowServerSession: String
    let targetStatus: String
    let targetBundleIdentifier: DiagnosticReportValue
    let targetWindowIdentifier: DiagnosticReportValue
    let accessibility: [(String, DiagnosticReportValue)]
    let management: [(String, DiagnosticReportValue)]
    let relatedHistory: String

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.timestamp == rhs.timestamp &&
            lhs.appVersion == rhs.appVersion &&
            lhs.appBuild == rhs.appBuild &&
            lhs.buildMode == rhs.buildMode &&
            lhs.macOSVersion == rhs.macOSVersion &&
            lhs.windowServerSession == rhs.windowServerSession &&
            lhs.targetStatus == rhs.targetStatus &&
            lhs.targetBundleIdentifier == rhs.targetBundleIdentifier &&
            lhs.targetWindowIdentifier == rhs.targetWindowIdentifier &&
            lhs.accessibility.elementsEqual(rhs.accessibility, by: { $0 == $1 }) &&
            lhs.management.elementsEqual(rhs.management, by: { $0 == $1 }) &&
            lhs.relatedHistory == rhs.relatedHistory
    }
}

enum FocusedWindowDiagnosticReport {
    static let privacyNotice = "Review before sharing. " + DiagnosticLogger.privacySummary

    static func render(_ snapshot: FocusedWindowDiagnosticSnapshot) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var lines = [
            "WindowRanger focused-window diagnostic report",
            "schema-version: \(FocusedWindowDiagnosticSnapshot.schemaVersion)",
            "privacy: \(privacyNotice)",
            "timestamp: \(formatter.string(from: snapshot.timestamp))",
            "windowranger-version: \(snapshot.appVersion)",
            "windowranger-build: \(snapshot.appBuild)",
            "build-mode: \(snapshot.buildMode)",
            "macos-version: \(snapshot.macOSVersion)",
            "windowserver-session: \(snapshot.windowServerSession)",
            "target-status: \(snapshot.targetStatus)",
            "target-bundle-identifier: \(snapshot.targetBundleIdentifier.rendered)",
            "target-window-identifier: \(snapshot.targetWindowIdentifier.rendered)",
            "",
            "[accessibility]",
        ]
        lines.append(contentsOf: snapshot.accessibility.map { "\($0.0): \($0.1.rendered)" })
        lines.append("")
        lines.append("[management]")
        lines.append(contentsOf: snapshot.management.map { "\($0.0): \($0.1.rendered)" })
        lines.append("")
        lines.append("[related-history]")
        lines.append(snapshot.relatedHistory.isEmpty ? "unavailable (no related in-memory events)" : snapshot.relatedHistory)

        let scrubbed = DiagnosticLogger.sanitizedReport(lines.joined(separator: "\n") + "\n")
        return boundedUTF8Prefix(scrubbed, maxBytes: FocusedWindowDiagnosticSnapshot.maximumReportBytes)
    }

    private static func boundedUTF8Prefix(_ text: String, maxBytes: Int) -> String {
        let data = Data(text.utf8)
        guard data.count > maxBytes else { return text }
        let marker = "\n[report-truncated-at-\(maxBytes)-bytes]\n"
        let budget = max(0, maxBytes - marker.utf8.count)
        var prefix = Data(data.prefix(budget))
        while !prefix.isEmpty, String(data: prefix, encoding: .utf8) == nil {
            prefix.removeLast()
        }
        var result = String(decoding: prefix, as: UTF8.self)
        if let lastNewline = result.lastIndex(of: "\n") {
            result = String(result[...lastNewline])
        }
        return result + marker
    }
}
