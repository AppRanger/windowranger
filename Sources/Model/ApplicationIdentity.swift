import Foundation

enum ApplicationIdentity {
    static let bundleIdentifier = "dev.appranger.WindowRanger"
    static let testBundleIdentifier = "dev.appranger.WindowRangerTests"
    static let legacyBundleIdentifier = "com.windowranger.WindowRanger"
    static let legacyICloudKeyValueStoreIdentifier =
        "$(TeamIdentifierPrefix)com.windowranger.WindowRanger"

    static let preferenceMigrationMarker = "appRangerBundleIdentityMigration.v1"

    static var cacheDirectoryURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            .map { $0.appendingPathComponent(bundleIdentifier, isDirectory: true) }
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent(bundleIdentifier, isDirectory: true)
    }

    static var legacyCacheDirectoryURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            .map { $0.appendingPathComponent(legacyBundleIdentifier, isDirectory: true) }
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent(legacyBundleIdentifier, isDirectory: true)
    }

    static var diagnosticDirectoryURL: URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        return library
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
    }
}

enum ApplicationIdentityMigration {
    @discardableResult
    static func migratePreferencesIfNeeded(
        defaults: UserDefaults = .standard,
        currentDomainName: String = ApplicationIdentity.bundleIdentifier,
        legacyDomainName: String = ApplicationIdentity.legacyBundleIdentifier,
        markerKey: String = ApplicationIdentity.preferenceMigrationMarker
    ) -> Bool {
        let currentDomain = defaults.persistentDomain(forName: currentDomainName) ?? [:]
        guard currentDomain[markerKey] as? Bool != true else { return false }

        var copiedValue = false
        if let legacyDomain = defaults.persistentDomain(forName: legacyDomainName) {
            for (key, value) in legacyDomain where currentDomain[key] == nil {
                defaults.set(value, forKey: key)
                copiedValue = true
            }
        }
        defaults.set(true, forKey: markerKey)
        return copiedValue
    }

    @discardableResult
    static func copyFileIfNeeded(
        from legacyURL: URL,
        to currentURL: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        guard !fileManager.fileExists(atPath: currentURL.path),
              fileManager.fileExists(atPath: legacyURL.path)
        else { return false }

        do {
            try fileManager.createDirectory(
                at: currentURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: legacyURL, to: currentURL)
            return true
        } catch {
            return false
        }
    }

    static func perform() {
        migratePreferencesIfNeeded()
        copyFileIfNeeded(
            from: ApplicationIdentity.legacyCacheDirectoryURL
                .appendingPathComponent("workspace-state.json", isDirectory: false),
            to: ApplicationIdentity.cacheDirectoryURL
                .appendingPathComponent("workspace-state.json", isDirectory: false)
        )
    }
}
