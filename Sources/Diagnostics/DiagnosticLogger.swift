import Foundation

enum DiagnosticBuildMode: String, Sendable {
    case debug = "Debug"
    case release = "Release"
    case test = "Test"
}

protocol DiagnosticSink: AnyObject {
    var fileURL: URL? { get }
    func append(_ data: Data)
    func recent(maxBytes: Int) -> Data
}

final class NoOpDiagnosticSink: DiagnosticSink {
    var fileURL: URL? { nil }
    func append(_ data: Data) {}
    func recent(maxBytes: Int) -> Data { Data() }
}

final class MemoryDiagnosticSink: DiagnosticSink {
    private let lock = NSLock()
    private var data = Data()
    var fileURL: URL? { nil }

    func append(_ newData: Data) {
        lock.lock()
        data.append(newData)
        lock.unlock()
    }

    func recent(maxBytes: Int) -> Data {
        lock.lock()
        defer { lock.unlock() }
        return Data(data.suffix(max(0, maxBytes)))
    }

    var text: String { String(decoding: recent(maxBytes: .max), as: UTF8.self) }
}

final class RotatingFileDiagnosticSink: DiagnosticSink {
    let fileURL: URL?
    let maxBytes: Int
    let backupCount: Int

    private let fileManager: FileManager
    private let lock = NSLock()

    init(
        fileURL: URL,
        maxBytes: Int = 1_000_000,
        backupCount: Int = 2,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.maxBytes = max(1_024, maxBytes)
        self.backupCount = max(0, backupCount)
        self.fileManager = fileManager
    }

    func append(_ data: Data) {
        guard let fileURL, !data.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let currentSize = ((try? fileManager.attributesOfItem(atPath: fileURL.path)[.size]) as? NSNumber)?.intValue ?? 0
            if currentSize + data.count > maxBytes {
                try rotate(fileURL)
            }
            if !fileManager.fileExists(atPath: fileURL.path) {
                _ = fileManager.createFile(atPath: fileURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            // Diagnostics must never interfere with window management.
        }
    }

    func recent(maxBytes: Int) -> Data {
        guard let fileURL else { return Data() }
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL) else { return Data() }
        return Data(data.suffix(max(0, maxBytes)))
    }

    private func rotate(_ fileURL: URL) throws {
        guard backupCount > 0 else {
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
            return
        }
        for index in stride(from: backupCount, through: 1, by: -1) {
            let destination = backupURL(for: fileURL, index: index)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            let source = index == 1 ? fileURL : backupURL(for: fileURL, index: index - 1)
            if fileManager.fileExists(atPath: source.path) {
                try fileManager.moveItem(at: source, to: destination)
            }
        }
    }

    private func backupURL(for fileURL: URL, index: Int) -> URL {
        fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(fileURL.lastPathComponent).\(index)")
    }
}

private struct DiagnosticRecord: Codable {
    let timestamp: String
    let sequence: UInt64
    let session: String
    let category: String
    let event: String
    let correlation: String?
    let fields: [String: String]
}

final class DiagnosticLogger {
    static let privacySummary = "No window titles, document names, URLs, typed content, full paths, or window contents are collected."

    let buildMode: DiagnosticBuildMode
    let sessionIdentifier: String
    let isVerbose: Bool

    private let sink: DiagnosticSink
    private let lock = NSLock()
    private var sequence: UInt64 = 0
    private var correlatedRecords: [String: [Data]] = [:]
    private var correlationOrder: [String] = []
    private var correlatedRecordBytes = 0
    private let timestampFormatter = ISO8601DateFormatter()

    init(
        buildMode: DiagnosticBuildMode,
        sink: DiagnosticSink,
        sessionIdentifier: String = UUID().uuidString,
        isVerbose: Bool = true
    ) {
        self.buildMode = buildMode
        self.sink = sink
        self.sessionIdentifier = sessionIdentifier
        self.isVerbose = isVerbose
        timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    static let disabled = DiagnosticLogger(
        buildMode: .release,
        sink: NoOpDiagnosticSink(),
        sessionIdentifier: "disabled",
        isVerbose: false
    )

    static func make(
        buildMode: DiagnosticBuildMode,
        fileURL: URL? = nil,
        maxBytes: Int = 1_000_000,
        backupCount: Int = 2
    ) -> DiagnosticLogger {
        guard buildMode == .debug, let fileURL else { return .disabled }
        return DiagnosticLogger(
            buildMode: buildMode,
            sink: RotatingFileDiagnosticSink(
                fileURL: fileURL,
                maxBytes: maxBytes,
                backupCount: backupCount
            )
        )
    }

    static func makeAppLogger() -> DiagnosticLogger {
        #if DEBUG
        return make(buildMode: .debug, fileURL: defaultFileURL)
        #else
        return .disabled
        #endif
    }

    static var defaultFileURL: URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        return library
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("com.chris.WindowManager", isDirectory: true)
            .appendingPathComponent("diagnostics.jsonl")
    }

    var fileURL: URL? { sink.fileURL }

    func makeCorrelationID() -> String {
        "action-\(UUID().uuidString.prefix(8).lowercased())"
    }

    func log(
        category: String,
        event: String,
        correlation: String? = nil,
        fields: [String: String] = [:]
    ) {
        guard isVerbose else { return }
        lock.lock()
        sequence += 1
        let record = DiagnosticRecord(
            timestamp: timestampFormatter.string(from: Date()),
            sequence: sequence,
            session: sessionIdentifier,
            category: sanitizedToken(category),
            event: sanitizedToken(event),
            correlation: correlation.map(sanitizedToken),
            fields: sanitizedFields(fields)
        )
        guard var data = try? JSONEncoder().encode(record) else {
            lock.unlock()
            return
        }
        data.append(0x0A)
        if let correlation = record.correlation {
            if correlatedRecords[correlation] == nil {
                correlationOrder.append(correlation)
                correlatedRecords[correlation] = []
            }
            correlatedRecords[correlation, default: []].append(data)
            correlatedRecordBytes += data.count
            trimCorrelatedRecordsIfNeeded()
        }
        sink.append(data)
        lock.unlock()
    }

    func recentDiagnosticsText(maxBytes: Int = 64_000) -> String {
        let actionBudget = max(1_024, maxBytes * 3 / 4)
        lock.lock()
        let actionData = recentCorrelatedActionsLocked(maxBytes: actionBudget)
        lock.unlock()

        let backgroundBudget = max(1_024, maxBytes - actionData.count)
        let rawBackground = sink.recent(maxBytes: backgroundBudget + 4_096)
        let backgroundData = Self.completeJSONLinesSuffix(
            from: rawBackground,
            maxBytes: backgroundBudget
        )
        let actionExcerpt = Self.newlineTerminatedText(actionData)
        let backgroundExcerpt = Self.newlineTerminatedText(backgroundData)
        return "WindowManager \(buildMode.rawValue) diagnostics\n" +
            "Session: \(sessionIdentifier)\n" +
            "Privacy: \(Self.privacySummary)\n\n" +
            "Recent correlated actions (trigger and results):\n" +
            actionExcerpt +
            "Recent background/file tail (complete lines):\n" +
            backgroundExcerpt
    }

    static func completeJSONLinesSuffix(from data: Data, maxBytes: Int) -> Data {
        guard maxBytes > 0, !data.isEmpty else { return Data() }
        var suffix = Data(data.suffix(maxBytes))
        if suffix.first != 0x7B, let firstNewline = suffix.firstIndex(of: 0x0A) {
            suffix.removeSubrange(suffix.startIndex...firstNewline)
        } else if suffix.first != 0x7B {
            return Data()
        }
        // A concurrent writer or a byte cap can leave a trailing partial record. JSON Lines is
        // useful only when both boundaries are complete, so retain through the final newline.
        if suffix.last != 0x0A {
            guard let lastNewline = suffix.lastIndex(of: 0x0A) else { return Data() }
            suffix.removeSubrange(suffix.index(after: lastNewline)..<suffix.endIndex)
        }
        return suffix
    }

    private static func newlineTerminatedText(_ data: Data) -> String {
        guard !data.isEmpty else { return "" }
        let text = String(decoding: data, as: UTF8.self)
        return text.hasSuffix("\n") ? text : text + "\n"
    }

    private func trimCorrelatedRecordsIfNeeded(maxBytes: Int = 512_000, maxActions: Int = 12) {
        while correlationOrder.count > maxActions || correlatedRecordBytes > maxBytes {
            guard correlationOrder.count > 1 else {
                guard let only = correlationOrder.first,
                      var records = correlatedRecords[only],
                      records.count > 3
                else { break }
                let removed = records.remove(at: 2)
                correlatedRecords[only] = records
                correlatedRecordBytes -= removed.count
                continue
            }
            let oldest = correlationOrder.removeFirst()
            let removed = correlatedRecords.removeValue(forKey: oldest) ?? []
            correlatedRecordBytes -= removed.reduce(0) { $0 + $1.count }
        }
    }

    private func recentCorrelatedActionsLocked(maxBytes: Int) -> Data {
        guard maxBytes > 0 else { return Data() }
        var selectedGroups: [Data] = []
        var remaining = maxBytes
        for correlation in correlationOrder.reversed() {
            guard let records = correlatedRecords[correlation], !records.isEmpty else { continue }
            let group = boundedActionGroup(records, maxBytes: remaining)
            guard !group.isEmpty else { continue }
            selectedGroups.append(group)
            remaining -= group.count
            if remaining < 1_024 { break }
        }
        return selectedGroups.reversed().reduce(into: Data()) { $0.append($1) }
    }

    private func boundedActionGroup(_ records: [Data], maxBytes: Int) -> Data {
        guard maxBytes > 0 else { return Data() }
        let total = records.reduce(0) { $0 + $1.count }
        if total <= maxBytes {
            return records.reduce(into: Data()) { $0.append($1) }
        }

        var result = Data()
        var included = Set<Int>()
        let headBudget = min(maxBytes / 3, 12_000)
        for (index, record) in records.enumerated() {
            guard result.count + record.count <= headBudget else { break }
            result.append(record)
            included.insert(index)
        }
        var tail: [Data] = []
        var tailBytes = 0
        for (index, record) in records.enumerated().reversed() where !included.contains(index) {
            guard result.count + tailBytes + record.count <= maxBytes else { continue }
            tail.append(record)
            tailBytes += record.count
        }
        for record in tail.reversed() { result.append(record) }
        return result
    }

    private func sanitizedFields(_ fields: [String: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: fields.map { key, value in
            let safeKey = sanitizedToken(key)
            if Self.isForbiddenField(safeKey) || Self.looksSensitive(value) {
                return (safeKey, "[redacted]")
            }
            return (safeKey, String(value.prefix(512)))
        })
    }

    private func sanitizedToken(_ value: String) -> String {
        let allowed = value.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0)
        }
        return String(String.UnicodeScalarView(allowed)).prefix(80).description
    }

    private static func isForbiddenField(_ key: String) -> Bool {
        let lower = key.lowercased()
        return ["title", "document", "url", "path", "content", "typed", "text"].contains {
            lower.contains($0)
        }
    }

    private static func looksSensitive(_ value: String) -> Bool {
        value.hasPrefix("/") || value.contains("://") || value.contains("/Users/") || value.contains("\\Users\\")
    }
}
