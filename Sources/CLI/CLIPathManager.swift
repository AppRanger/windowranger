import Darwin
import Foundation

/// Installs the WindowRanger command-line helper for the current user without invoking a shell.
///
/// The manager deliberately owns only its named startup-file block and a symlink at
/// `~/.local/bin/windowranger`. It never replaces a user file or another tool's symlink.
struct CLIPathManager {
    enum State: Equatable {
        case installed
        case notInstalled
        case stale
        case conflict
        case unsupported
        case error(String)
    }

    struct Paths {
        let homeDirectory: URL
        let loginShell: String
        let bundleURL: URL

        init(
            homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
            loginShell: String = Self.currentLoginShell(),
            bundleURL: URL = Bundle.main.bundleURL
        ) {
            self.homeDirectory = homeDirectory.standardizedFileURL
            self.loginShell = loginShell
            self.bundleURL = bundleURL.standardizedFileURL
        }

        static func currentLoginShell() -> String {
            if let account = getpwuid(getuid()) {
                let shell = String(cString: account.pointee.pw_shell)
                if !shell.isEmpty { return shell }
            }
            return ProcessInfo.processInfo.environment["SHELL"] ?? ""
        }

        var commandDirectory: URL {
            homeDirectory.appendingPathComponent(".local/bin", isDirectory: true)
        }

        var commandURL: URL {
            commandDirectory.appendingPathComponent("windowranger", isDirectory: false)
        }

        var bundledExecutableURL: URL {
            bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Helpers", isDirectory: true)
                .appendingPathComponent("windowranger", isDirectory: false)
        }

        var startupFileURL: URL? {
            switch URL(fileURLWithPath: loginShell).lastPathComponent {
            case "zsh":
                return homeDirectory.appendingPathComponent(".zprofile", isDirectory: false)
            case "bash":
                return homeDirectory.appendingPathComponent(".bash_profile", isDirectory: false)
            default:
                return nil
            }
        }
    }

    enum ItemKind {
        case missing
        case directory
        case regularFile
        case symbolicLink(destination: String)
        case other
    }

    private let fileSystem: CLIPathFileSystem
    let paths: Paths

    init(
        fileSystem: CLIPathFileSystem = LocalCLIPathFileSystem(),
        paths: Paths = Paths()
    ) {
        self.fileSystem = fileSystem
        self.paths = paths
    }

    func state() -> State {
        guard let startupFileURL = paths.startupFileURL else {
            return .unsupported
        }

        switch commandLinkState() {
        case .conflict:
            return .conflict
        case .error(let message):
            return .error(message)
        case .missing:
            switch startupBlockState(at: startupFileURL) {
            case .missing:
                return .notInstalled
            case .installed:
                return .stale
            case .conflict:
                return .conflict
            case .error(let message):
                return .error(message)
            }
        case .installed:
            guard bundledExecutableIsAvailable else {
                return .stale
            }
            switch startupBlockState(at: startupFileURL) {
            case .conflict:
                return .conflict
            case .error(let message):
                return .error(message)
            case .installed:
                return .installed
            case .missing:
                return isCommandDirectoryAlreadyOnPath(in: startupFileURL) ? .installed : .stale
            }
        }
    }

    @discardableResult
    func install() -> State {
        guard let startupFileURL = paths.startupFileURL else {
            return .unsupported
        }
        guard bundledExecutableIsAvailable else {
            return .error("The bundled WindowRanger command-line helper is unavailable.")
        }

        let startupState = startupBlockState(at: startupFileURL)
        switch startupState {
        case .conflict:
            return .conflict
        case .error(let message):
            return .error(message)
        case .installed, .missing:
            break
        }

        if let message = ensureCommandDirectory() {
            return .error(message)
        }

        switch commandLinkState() {
        case .installed:
            break
        case .missing:
            do {
                try fileSystem.createSymbolicLink(at: paths.commandURL, withDestinationPath: paths.bundledExecutableURL.path)
            } catch {
                return .error("Could not create the WindowRanger command link: \(error.localizedDescription)")
            }
        case .conflict:
            return .conflict
        case .error(let message):
            return .error(message)
        }

        switch startupState {
        case .installed:
            return state()
        case .conflict:
            return .conflict
        case .error(let message):
            return .error(message)
        case .missing:
            guard !isCommandDirectoryAlreadyOnPath(in: startupFileURL) else {
                return state()
            }
            do {
                let existingData = try startupFileData(at: startupFileURL)
                try fileSystem.writeDataPreservingMetadata(addingManagedBlock(to: existingData), to: startupFileURL)
            } catch {
                return .error("Could not update the login shell startup file: \(error.localizedDescription)")
            }
            return state()
        }
    }

    @discardableResult
    func remove() -> State {
        guard let startupFileURL = paths.startupFileURL else {
            return .unsupported
        }

        let startupState = startupBlockState(at: startupFileURL)
        switch startupState {
        case .conflict:
            return .conflict
        case .error(let message):
            return .error(message)
        case .installed, .missing:
            break
        }

        let linkState = commandLinkState()
        switch linkState {
        case .conflict:
            return .conflict
        case .error(let message):
            return .error(message)
        case .installed, .missing:
            break
        }

        switch linkState {
        case .installed:
            do {
                try fileSystem.removeItem(at: paths.commandURL)
            } catch {
                return .error("Could not remove the WindowRanger command link: \(error.localizedDescription)")
            }
        case .missing:
            break
        case .conflict:
            return .conflict
        case .error(let message):
            return .error(message)
        }

        switch startupState {
        case .missing:
            return state()
        case .installed:
            do {
                let existingData = try startupFileData(at: startupFileURL)
                guard let updatedData = removingManagedBlock(from: existingData) else {
                    return .conflict
                }
                try fileSystem.writeDataPreservingMetadata(updatedData, to: startupFileURL)
            } catch {
                return .error("Could not update the login shell startup file: \(error.localizedDescription)")
            }
            return state()
        case .conflict:
            return .conflict
        case .error(let message):
            return .error(message)
        }
    }

    private var bundledExecutableIsAvailable: Bool {
        switch fileSystem.itemKind(at: paths.bundledExecutableURL) {
        case .regularFile, .symbolicLink:
            return true
        case .missing, .directory, .other:
            return false
        }
    }

    private func ensureCommandDirectory() -> String? {
        switch fileSystem.itemKind(at: paths.commandDirectory) {
        case .directory:
            return nil
        case .missing:
            do {
                try fileSystem.createDirectory(at: paths.commandDirectory)
                return nil
            } catch {
                return "Could not create ~/.local/bin: \(error.localizedDescription)"
            }
        case .regularFile, .symbolicLink, .other:
            return "~/.local/bin exists but is not a directory."
        }
    }

    private enum CommandLinkState {
        case installed
        case missing
        case conflict
        case error(String)
    }

    private func commandLinkState() -> CommandLinkState {
        switch fileSystem.itemKind(at: paths.commandURL) {
        case .missing:
            return .missing
        case .symbolicLink(let destination):
            return destination == paths.bundledExecutableURL.path ? .installed : .conflict
        case .regularFile, .directory, .other:
            return .conflict
        }
    }

    private enum StartupBlockState {
        case installed
        case missing
        case conflict
        case error(String)
    }

    private func startupBlockState(at startupFileURL: URL) -> StartupBlockState {
        switch fileSystem.itemKind(at: startupFileURL) {
        case .missing, .regularFile:
            break
        case .directory, .symbolicLink, .other:
            return .conflict
        }
        do {
            let data = try startupFileData(at: startupFileURL)
            return managedBlockState(in: data)
        } catch {
            return .error("Could not read the login shell startup file: \(error.localizedDescription)")
        }
    }

    private func startupFileData(at startupFileURL: URL) throws -> Data {
        switch fileSystem.itemKind(at: startupFileURL) {
        case .missing:
            return Data()
        case .regularFile:
            return try fileSystem.readData(at: startupFileURL)
        case .directory, .symbolicLink, .other:
            throw CLIPathManagerError.unsupportedStartupFile
        }
    }

    private func managedBlockState(in data: Data) -> StartupBlockState {
        guard let text = String(data: data, encoding: .utf8) else {
            return .conflict
        }

        let standardStarts = text.ranges(of: Self.standardBlockStart).count
        let separatorStarts = text.ranges(of: Self.separatorBlockStart).count
        let ends = text.ranges(of: Self.blockEnd).count
        let startCount = standardStarts + separatorStarts
        guard startCount == 0, ends == 0 else {
            guard startCount == 1, ends == 1,
                  let blockRange = managedBlockRange(in: text),
                  text[blockRange] == expectedManagedBlock(startingWith: text[blockRange].hasPrefix(Self.separatorBlockStart) ? Self.separatorBlockStart : Self.standardBlockStart) else {
                return .conflict
            }
            return .installed
        }
        return .missing
    }

    private func isCommandDirectoryAlreadyOnPath(in startupFileURL: URL) -> Bool {
        guard let data = try? startupFileData(at: startupFileURL),
              let text = String(data: data, encoding: .utf8) else {
            return false
        }

        let candidates: Set<String> = [
            paths.commandDirectory.path,
            "$HOME/.local/bin",
            "${HOME}/.local/bin",
            "~/.local/bin",
        ]
        return text.split(whereSeparator: \.isNewline).contains { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let pathAssignment = line.range(
                of: #"(^|[;[:space:]])(export[[:space:]]+)?PATH[[:space:]]*(\+?=)"#,
                options: .regularExpression
            ) != nil || line.range(
                of: #"(^|[;[:space:]])path[[:space:]]*="#,
                options: .regularExpression
            ) != nil
            guard !line.hasPrefix("#"), pathAssignment else { return false }
            guard let equals = line.firstIndex(of: "=") else { return false }
            let value = line[line.index(after: equals)...]
            let separators = CharacterSet(charactersIn: ": \t\"'();")
            let components = value.components(separatedBy: separators).filter { !$0.isEmpty }
            return components.contains { candidates.contains($0) }
        }
    }

    private func addingManagedBlock(to data: Data) -> Data {
        guard !data.isEmpty else {
            return Data(expectedManagedBlock(startingWith: Self.standardBlockStart).utf8)
        }

        let hasTrailingLineBreak = data.last == 10
        let start = hasTrailingLineBreak ? Self.standardBlockStart : Self.separatorBlockStart
        var result = data
        if !hasTrailingLineBreak {
            result.append(10)
        }
        result.append(contentsOf: expectedManagedBlock(startingWith: start).utf8)
        return result
    }

    private func removingManagedBlock(from data: Data) -> Data? {
        guard let text = String(data: data, encoding: .utf8),
              let range = managedBlockRange(in: text) else {
            return nil
        }

        let startMarker = text[range].hasPrefix(Self.separatorBlockStart) ? Self.separatorBlockStart : Self.standardBlockStart
        let block = expectedManagedBlock(startingWith: startMarker)
        guard text[range] == block,
              let dataRange = data.range(of: Data(block.utf8)) else {
            return nil
        }

        var removalRange = dataRange
        if startMarker == Self.separatorBlockStart,
           removalRange.lowerBound > data.startIndex,
           data[data.index(before: removalRange.lowerBound)] == 10 {
            removalRange = data.index(before: removalRange.lowerBound)..<removalRange.upperBound
        }
        var result = data
        result.removeSubrange(removalRange)
        return result
    }

    private func managedBlockRange(in text: String) -> Range<String.Index>? {
        let starts = [Self.standardBlockStart, Self.separatorBlockStart]
            .compactMap { marker in text.range(of: marker).map { (marker, $0) } }
        guard starts.count == 1,
              let (marker, startRange) = starts.first,
              let endRange = text.range(of: Self.blockEnd),
              startRange.lowerBound < endRange.lowerBound else {
            return nil
        }

        let lineEnd = text[endRange.upperBound...].firstIndex(of: "\n")
            .map { text.index(after: $0) } ?? endRange.upperBound
        guard text[startRange.lowerBound...].hasPrefix(marker) else { return nil }
        return startRange.lowerBound..<lineEnd
    }

    private func expectedManagedBlock(startingWith startMarker: String) -> String {
        """
        \(startMarker)
        export PATH="$HOME/.local/bin:$PATH"
        \(Self.blockEnd)

        """
    }

    private static let standardBlockStart = "# >>> WindowRanger CLI >>>"
    private static let separatorBlockStart = "# >>> WindowRanger CLI (managed separator) >>>"
    private static let blockEnd = "# <<< WindowRanger CLI <<<"
}

protocol CLIPathFileSystem {
    func itemKind(at url: URL) -> CLIPathManager.ItemKind
    func readData(at url: URL) throws -> Data
    func writeDataPreservingMetadata(_ data: Data, to url: URL) throws
    func createDirectory(at url: URL) throws
    func createSymbolicLink(at url: URL, withDestinationPath path: String) throws
    func removeItem(at url: URL) throws
}

private enum CLIPathManagerError: LocalizedError {
    case unsupportedStartupFile

    var errorDescription: String? {
        "The login shell startup path is not a regular file."
    }
}

private struct LocalCLIPathFileSystem: CLIPathFileSystem {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func itemKind(at url: URL) -> CLIPathManager.ItemKind {
        if let destination = try? fileManager.destinationOfSymbolicLink(atPath: url.path) {
            return .symbolicLink(destination: destination)
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .missing
        }
        return isDirectory.boolValue ? .directory : .regularFile
    }

    func readData(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func writeDataPreservingMetadata(_ data: Data, to url: URL) throws {
        let parent = url.deletingLastPathComponent()
        let temporary = parent.appendingPathComponent(".windowranger-cli-\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporary) }
        try data.write(to: temporary, options: [.withoutOverwriting])

        if fileManager.fileExists(atPath: url.path) {
            // FileManager's replacement operation retains the original item's metadata unless
            // `.usingNewMetadataOnly` is requested. That preserves the user's mode, ACLs, flags,
            // and extended attributes while the content update remains atomic.
            _ = try fileManager.replaceItemAt(url, withItemAt: temporary, backupItemName: nil, options: [])
        } else {
            try fileManager.moveItem(at: temporary, to: url)
        }
    }

    func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func createSymbolicLink(at url: URL, withDestinationPath path: String) throws {
        try fileManager.createSymbolicLink(atPath: url.path, withDestinationPath: path)
    }

    func removeItem(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }
}
