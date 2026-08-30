import Foundation
import XCTest

final class WindowRangerCLISkillWriterTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WindowRangerCLISkillWriterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    func testRefusesExistingFileUnlessForceIsExplicit() throws {
        let destination = root.appendingPathComponent("SKILL.md")
        try Data("user-owned".utf8).write(to: destination)

        XCTAssertThrowsError(
            try WindowRangerCLISkillWriter.write(content: "generated", to: destination.path, force: false)
        ) { error in
            XCTAssertEqual(error as? WindowRangerCLISkillWriterError, .destinationExists)
        }
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "user-owned")

        XCTAssertEqual(
            try WindowRangerCLISkillWriter.write(content: "generated", to: destination.path, force: true),
            destination
        )
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "generated")
    }

    func testRefusesExistingSymbolicLinkEvenWithForce() throws {
        let target = root.appendingPathComponent("target.md")
        let destination = root.appendingPathComponent("SKILL.md")
        try Data("user-owned".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: target)

        XCTAssertThrowsError(
            try WindowRangerCLISkillWriter.write(content: "generated", to: destination.path, force: true)
        ) { error in
            XCTAssertEqual(error as? WindowRangerCLISkillWriterError, .destinationIsSymbolicLink)
        }
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "user-owned")
    }

    func testRefusesSymbolicLinkOutputDirectory() throws {
        let targetDirectory = root.appendingPathComponent("target", isDirectory: true)
        let linkedDirectory = root.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linkedDirectory, withDestinationURL: targetDirectory)

        XCTAssertThrowsError(
            try WindowRangerCLISkillWriter.write(content: "generated", to: linkedDirectory.path, force: false)
        ) { error in
            XCTAssertEqual(error as? WindowRangerCLISkillWriterError, .destinationIsSymbolicLink)
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: targetDirectory.appendingPathComponent("windowranger-cli/SKILL.md").path
            )
        )
    }

    func testRefusesDirectSkillFileUnderSymbolicLinkParent() throws {
        let targetDirectory = root.appendingPathComponent("direct-target", isDirectory: true)
        let linkedDirectory = root.appendingPathComponent("direct-linked", isDirectory: true)
        let targetSkill = targetDirectory.appendingPathComponent("SKILL.md")
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        try Data("user-owned".utf8).write(to: targetSkill)
        try FileManager.default.createSymbolicLink(at: linkedDirectory, withDestinationURL: targetDirectory)
        let linkedSkill = linkedDirectory.appendingPathComponent("SKILL.md")

        XCTAssertThrowsError(
            try WindowRangerCLISkillWriter.write(content: "generated", to: linkedSkill.path, force: true)
        ) { error in
            XCTAssertEqual(error as? WindowRangerCLISkillWriterError, .destinationIsSymbolicLink)
        }
        XCTAssertEqual(try String(contentsOf: targetSkill, encoding: .utf8), "user-owned")
    }
}
