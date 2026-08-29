import Darwin
import Foundation
import XCTest

final class CLIPathManagerTests: XCTestCase {
    private var root: URL!
    private var fileSystem: FixtureCLIPathFileSystem!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CLIPathManagerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        fileSystem = FixtureCLIPathFileSystem(fileManager: .default)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        root = nil
        fileSystem = nil
    }

    func testInstallAndRemovePreserveExistingStartupFileBytes() throws {
        let paths = try makePaths()
        let startupFile = try XCTUnwrap(paths.startupFileURL)
        let original = Data("export FOO=bar".utf8)
        try original.write(to: startupFile)
        let manager = CLIPathManager(fileSystem: fileSystem, paths: paths)

        XCTAssertEqual(manager.state(), .notInstalled)
        XCTAssertEqual(manager.install(), .installed)
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: paths.commandURL.path),
            paths.bundledExecutableURL.path
        )
        let installedProfile = try Data(contentsOf: startupFile)
        XCTAssertTrue(String(decoding: installedProfile, as: UTF8.self).contains("# >>> WindowRanger CLI"))

        XCTAssertEqual(manager.remove(), .notInstalled)
        XCTAssertEqual(try Data(contentsOf: startupFile), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.commandURL.path))
    }

    func testInstallDoesNotAddManagedBlockWhenUserAlreadyAddsLocalBinToPath() throws {
        let paths = try makePaths()
        let startupFile = try XCTUnwrap(paths.startupFileURL)
        try Data("export PATH=\"$HOME/.local/bin:$PATH\"\n".utf8).write(to: startupFile)
        let manager = CLIPathManager(fileSystem: fileSystem, paths: paths)

        XCTAssertEqual(manager.install(), .installed)
        let profile = String(decoding: try Data(contentsOf: startupFile), as: UTF8.self)
        XCTAssertFalse(profile.contains("WindowRanger CLI"))
        XCTAssertEqual(manager.remove(), .notInstalled)
        XCTAssertEqual(profile, String(decoding: try Data(contentsOf: startupFile), as: UTF8.self))
    }

    func testSimilarPathComponentDoesNotSuppressManagedBlock() throws {
        let paths = try makePaths(suffix: "similar-path")
        let startupFile = try XCTUnwrap(paths.startupFileURL)
        try Data("export PATH=\"$HOME/.local/bin-tools:$PATH\"\n".utf8).write(to: startupFile)
        let manager = CLIPathManager(fileSystem: fileSystem, paths: paths)

        XCTAssertEqual(manager.install(), .installed)
        let profile = String(decoding: try Data(contentsOf: startupFile), as: UTF8.self)
        XCTAssertTrue(profile.contains("# >>> WindowRanger CLI"))
    }

    func testInstallAndRemovePreserveRestrictiveStartupFileMode() throws {
        let paths = try makePaths(suffix: "metadata")
        let startupFile = try XCTUnwrap(paths.startupFileURL)
        try Data("export SECRET=value\n".utf8).write(to: startupFile)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: startupFile.path
        )
        try setExtendedAttribute("private-profile", at: startupFile)
        let manager = CLIPathManager(paths: paths)

        XCTAssertEqual(manager.install(), .installed)
        XCTAssertEqual(try posixMode(at: startupFile), 0o600)
        XCTAssertEqual(try extendedAttribute(at: startupFile), "private-profile")
        XCTAssertEqual(manager.remove(), .notInstalled)
        XCTAssertEqual(try posixMode(at: startupFile), 0o600)
        XCTAssertEqual(try extendedAttribute(at: startupFile), "private-profile")
    }

    func testInstallRejectsExistingRegularFileOrForeignSymlink() throws {
        let regularPaths = try makePaths(suffix: "regular")
        try FileManager.default.createDirectory(at: regularPaths.commandDirectory, withIntermediateDirectories: true)
        try Data("user-owned".utf8).write(to: regularPaths.commandURL)
        let regularManager = CLIPathManager(fileSystem: fileSystem, paths: regularPaths)

        XCTAssertEqual(regularManager.state(), .conflict)
        XCTAssertEqual(regularManager.install(), .conflict)
        XCTAssertEqual(try Data(contentsOf: regularPaths.commandURL), Data("user-owned".utf8))

        let foreignPaths = try makePaths(suffix: "foreign")
        try FileManager.default.createDirectory(at: foreignPaths.commandDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: foreignPaths.commandURL.path,
            withDestinationPath: "/usr/local/bin/someone-else"
        )
        let foreignManager = CLIPathManager(fileSystem: fileSystem, paths: foreignPaths)

        XCTAssertEqual(foreignManager.state(), .conflict)
        XCTAssertEqual(foreignManager.install(), .conflict)
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: foreignPaths.commandURL.path),
            "/usr/local/bin/someone-else"
        )
    }

    func testStateIsStaleForASeparatedManagedBlockAndInstallRepairsIt() throws {
        let paths = try makePaths()
        let manager = CLIPathManager(fileSystem: fileSystem, paths: paths)

        XCTAssertEqual(manager.install(), .installed)
        try FileManager.default.removeItem(at: paths.commandURL)
        XCTAssertEqual(manager.state(), .stale)
        XCTAssertEqual(manager.install(), .installed)
    }

    func testStartupConflictLeavesTheCommandLinkUntouched() throws {
        let paths = try makePaths()
        let startupFile = try XCTUnwrap(paths.startupFileURL)
        try Data("# >>> WindowRanger CLI >>>\nuser edited this block\n".utf8).write(to: startupFile)
        let manager = CLIPathManager(fileSystem: fileSystem, paths: paths)

        XCTAssertEqual(manager.install(), .conflict)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.commandURL.path))

        try FileManager.default.createDirectory(at: paths.commandDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: paths.commandURL.path,
            withDestinationPath: paths.bundledExecutableURL.path
        )
        XCTAssertEqual(manager.remove(), .conflict)
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: paths.commandURL.path),
            paths.bundledExecutableURL.path
        )
    }

    func testUnsupportedShellDoesNotWriteFiles() throws {
        let paths = try makePaths(loginShell: "/bin/fish")
        let manager = CLIPathManager(fileSystem: fileSystem, paths: paths)

        XCTAssertEqual(manager.state(), .unsupported)
        XCTAssertEqual(manager.install(), .unsupported)
        XCTAssertEqual(manager.remove(), .unsupported)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.commandDirectory.path))
    }

    private func makePaths(suffix: String = "default", loginShell: String = "/bin/zsh") throws -> CLIPathManager.Paths {
        let fixtureRoot = root.appendingPathComponent(suffix, isDirectory: true)
        let home = fixtureRoot.appendingPathComponent("home", isDirectory: true)
        let bundle = fixtureRoot.appendingPathComponent("WindowRanger.app", isDirectory: true)
        let helper = bundle
            .appendingPathComponent("Contents/Helpers", isDirectory: true)
            .appendingPathComponent("windowranger", isDirectory: false)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("helper".utf8).write(to: helper)
        return CLIPathManager.Paths(homeDirectory: home, loginShell: loginShell, bundleURL: bundle)
    }

    private func posixMode(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    private func setExtendedAttribute(_ value: String, at url: URL) throws {
        let bytes = Array(value.utf8)
        let result = bytes.withUnsafeBytes {
            setxattr(url.path, "dev.appranger.WindowRanger.test", $0.baseAddress, $0.count, 0, 0)
        }
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    private func extendedAttribute(at url: URL) throws -> String {
        let name = "dev.appranger.WindowRanger.test"
        let count = getxattr(url.path, name, nil, 0, 0, 0)
        guard count >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var bytes = [UInt8](repeating: 0, count: count)
        let read = bytes.withUnsafeMutableBytes {
            getxattr(url.path, name, $0.baseAddress, $0.count, 0, 0)
        }
        guard read == count else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return String(decoding: bytes, as: UTF8.self)
    }
}

private struct FixtureCLIPathFileSystem: CLIPathFileSystem {
    private let fileManager: FileManager

    init(fileManager: FileManager) {
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
        try data.write(to: url, options: .atomic)
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
