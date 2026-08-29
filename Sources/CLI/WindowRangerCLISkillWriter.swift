import Darwin
import Foundation

enum WindowRangerCLISkillWriterError: Error, Equatable, LocalizedError {
    case destinationExists
    case destinationIsSymbolicLink
    case destinationIsNotARegularFile

    var errorDescription: String? {
        switch self {
        case .destinationExists:
            "The agent skill already exists. Pass --force to replace that regular file."
        case .destinationIsSymbolicLink:
            "Refusing to write the agent skill through a symbolic link."
        case .destinationIsNotARegularFile:
            "The agent skill destination exists but is not a regular file."
        }
    }
}

enum WindowRangerCLISkillWriter {
    static func destination(for rawPath: String) -> URL {
        let expanded = requestedURL(for: rawPath)
        if expanded.lastPathComponent == WindowRangerCLIAgentSkill.fileName {
            return expanded
        }
        return expanded
            .appendingPathComponent("windowranger-cli", isDirectory: true)
            .appendingPathComponent(WindowRangerCLIAgentSkill.fileName, isDirectory: false)
            .standardizedFileURL
    }

    private static func requestedURL(for rawPath: String) -> URL {
        (rawPath.hasPrefix("~/")
            ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(String(rawPath.dropFirst(2)))
            : URL(fileURLWithPath: rawPath))
            .standardizedFileURL
    }

    static func write(
        content: String,
        to rawPath: String,
        force: Bool,
        fileManager: FileManager = .default
    ) throws -> URL {
        let requested = requestedURL(for: rawPath)
        if requested.lastPathComponent != WindowRangerCLIAgentSkill.fileName,
           try itemType(at: requested) == S_IFLNK {
            throw WindowRangerCLISkillWriterError.destinationIsSymbolicLink
        }
        let destination = destination(for: rawPath)
        if try containsUserSymbolicLinkComponent(in: destination.deletingLastPathComponent()) {
            throw WindowRangerCLISkillWriterError.destinationIsSymbolicLink
        }
        if let type = try itemType(at: destination) {
            switch type {
            case S_IFLNK:
                throw WindowRangerCLISkillWriterError.destinationIsSymbolicLink
            case S_IFREG:
                guard force else { throw WindowRangerCLISkillWriterError.destinationExists }
            default:
                throw WindowRangerCLISkillWriterError.destinationIsNotARegularFile
            }
        }

        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let options: Data.WritingOptions = force ? .atomic : .withoutOverwriting
        try Data(content.utf8).write(to: destination, options: options)
        return destination
    }

    private static func itemType(at url: URL) throws -> mode_t? {
        var status = stat()
        if lstat(url.path, &status) == 0 {
            return status.st_mode & S_IFMT
        }
        if errno == ENOENT { return nil }
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    private static func containsUserSymbolicLinkComponent(in directory: URL) throws -> Bool {
        let components = directory.standardizedFileURL.pathComponents
        guard components.first == "/" else { return true }
        var current = URL(fileURLWithPath: "/", isDirectory: true)
        for component in components.dropFirst() {
            current.appendPathComponent(component, isDirectory: true)
            guard let type = try itemType(at: current) else {
                // Once an ancestor does not exist, no deeper component can currently redirect the
                // write. createDirectory will construct the remaining path without following one.
                return false
            }
            if type == S_IFLNK {
                // macOS exposes these root aliases as system-owned links. Canonical user paths and
                // temporary test paths commonly pass through them; links below them remain refused.
                let allowedSystemAlias = current.path == "/tmp" ||
                    current.path == "/var" ||
                    current.path == "/etc"
                if !allowedSystemAlias { return true }
            }
        }
        return false
    }
}
