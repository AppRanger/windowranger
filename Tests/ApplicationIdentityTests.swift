import XCTest

final class ApplicationIdentityTests: XCTestCase {
    func testBundleIdentifiersUseAppRangerDomain() {
        XCTAssertEqual(ApplicationIdentity.bundleIdentifier, "dev.appranger.WindowRanger")
        XCTAssertEqual(ApplicationIdentity.publicBundleIdentifier, "dev.appranger.WindowRanger")
        XCTAssertEqual(ApplicationIdentity.developmentBundleIdentifier, "dev.appranger.WindowRanger.Debug")
        XCTAssertFalse(ApplicationIdentity.isDevelopment)
        XCTAssertEqual(ApplicationIdentity.testBundleIdentifier, "dev.appranger.WindowRangerTests")
        XCTAssertEqual(ApplicationIdentity.legacyBundleIdentifier, "com.windowranger.WindowRanger")
    }

    func testLegacyMigrationRunsOnlyForThePublicIdentity() {
        XCTAssertTrue(ApplicationIdentityMigration.shouldPerform(isDevelopment: false))
        XCTAssertFalse(ApplicationIdentityMigration.shouldPerform(isDevelopment: true))
    }

    func testInstancePolicyAllowsOnlyTheCurrentManagedApplication() {
        XCTAssertTrue(ApplicationInstancePolicy.shouldStart(
            currentProcessIdentifier: 10,
            runningApplications: [
                RunningApplicationIdentity(
                    processIdentifier: 10,
                    bundleIdentifier: ApplicationIdentity.publicBundleIdentifier
                ),
                RunningApplicationIdentity(processIdentifier: 20, bundleIdentifier: "com.apple.Safari"),
            ]
        ))
    }

    func testInstancePolicyRejectsAReleaseAndDevelopmentSibling() {
        for siblingBundleIdentifier in [
            ApplicationIdentity.publicBundleIdentifier,
            ApplicationIdentity.developmentBundleIdentifier,
        ] {
            XCTAssertFalse(ApplicationInstancePolicy.shouldStart(
                currentProcessIdentifier: 10,
                runningApplications: [
                    RunningApplicationIdentity(processIdentifier: 10, bundleIdentifier: nil),
                    RunningApplicationIdentity(
                        processIdentifier: 20,
                        bundleIdentifier: siblingBundleIdentifier
                    ),
                ]
            ))
        }
    }

    func testPreferenceMigrationCopiesOnlyMissingValuesOnce() throws {
        let token = UUID().uuidString
        let currentDomain = "ApplicationIdentityTests.current.\(token)"
        let legacyDomain = "ApplicationIdentityTests.legacy.\(token)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: currentDomain))
        defer {
            defaults.removePersistentDomain(forName: currentDomain)
            defaults.removePersistentDomain(forName: legacyDomain)
        }

        defaults.setPersistentDomain(
            ["legacy-only": "copied", "shared": "legacy"],
            forName: legacyDomain
        )
        defaults.set("current", forKey: "shared")

        XCTAssertTrue(
            ApplicationIdentityMigration.migratePreferencesIfNeeded(
                defaults: defaults,
                currentDomainName: currentDomain,
                legacyDomainName: legacyDomain
            )
        )
        XCTAssertEqual(defaults.string(forKey: "legacy-only"), "copied")
        XCTAssertEqual(defaults.string(forKey: "shared"), "current")
        XCTAssertEqual(
            defaults.bool(forKey: ApplicationIdentity.preferenceMigrationMarker),
            true
        )

        defaults.setPersistentDomain(["late": "ignored"], forName: legacyDomain)
        XCTAssertFalse(
            ApplicationIdentityMigration.migratePreferencesIfNeeded(
                defaults: defaults,
                currentDomainName: currentDomain,
                legacyDomainName: legacyDomain
            )
        )
        XCTAssertNil(defaults.object(forKey: "late"))
    }

    func testFileMigrationDoesNotOverwriteOrDeleteLegacyFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ApplicationIdentityTests-\(UUID().uuidString)", isDirectory: true)
        let legacyURL = root.appendingPathComponent("legacy/state.json")
        let currentURL = root.appendingPathComponent("current/state.json")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: legacyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("legacy".utf8).write(to: legacyURL)

        XCTAssertTrue(ApplicationIdentityMigration.copyFileIfNeeded(from: legacyURL, to: currentURL))
        XCTAssertEqual(try Data(contentsOf: currentURL), Data("legacy".utf8))
        XCTAssertEqual(try Data(contentsOf: legacyURL), Data("legacy".utf8))

        try Data("current".utf8).write(to: currentURL)
        XCTAssertFalse(ApplicationIdentityMigration.copyFileIfNeeded(from: legacyURL, to: currentURL))
        XCTAssertEqual(try Data(contentsOf: currentURL), Data("current".utf8))
    }
}
