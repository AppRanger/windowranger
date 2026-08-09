import XCTest

final class ICloudSyncSettingsTests: XCTestCase {
    @MainActor
    func testNewInstallationDefaultsToLocalOnlyWithoutCloudContact() {
        let (defaults, suite) = isolatedDefaults("FirstRun")
        defer { defaults.removePersistentDomain(forName: suite) }
        let cloud = InspectableUbiquitousStore()
        cloud.seed("workspace-label", forKey: "menuBarPresentationMode.v1")

        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: cloud,
            connectedDisplaysProvider: { [] }
        )

        XCTAssertFalse(store.iCloudSyncEnabled)
        XCTAssertEqual(store.menuBarPresentationMode, .compact)
        XCTAssertEqual(cloud.readCount, 0)
        XCTAssertEqual(cloud.writeCount, 0)
        XCTAssertEqual(cloud.synchronizeCount, 0)
    }

    @MainActor
    func testSavedEnabledAndDisabledChoicesSurviveRestart() {
        for enabled in [false, true] {
            let (defaults, suite) = isolatedDefaults("SavedChoice-\(enabled)")
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(enabled, forKey: "iCloudSyncEnabled")
            let cloud = InspectableUbiquitousStore()

            let store = SettingsStore(
                defaults: defaults,
                ubiquitousStore: cloud,
                connectedDisplaysProvider: { [] }
            )

            XCTAssertEqual(store.iCloudSyncEnabled, enabled)
            XCTAssertEqual(defaults.bool(forKey: "iCloudSyncEnabled"), enabled)
            XCTAssertEqual(cloud.synchronizeCount > 0, enabled)
        }
    }

    @MainActor
    func testDisablingSyncImmediatelyIsolatesCloudAndKeepsLocalPersistence() {
        let (defaults, suite) = isolatedDefaults("Disable")
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "iCloudSyncEnabled")
        let cloud = InspectableUbiquitousStore()
        cloud.seed("keep-me", forKey: "previously.synced.value")
        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: cloud,
            connectedDisplaysProvider: { [] }
        )
        cloud.resetCounters()

        store.iCloudSyncEnabled = false
        store.menuBarPresentationMode = .full
        store.menuBarWorkspaceLabelMode = .key

        XCTAssertFalse(defaults.bool(forKey: "iCloudSyncEnabled"))
        XCTAssertEqual(defaults.string(forKey: "menuBarPresentationMode.v1"), "full")
        XCTAssertEqual(defaults.string(forKey: "menuBarWorkspaceLabelMode.v1"), "key")
        XCTAssertEqual(cloud.peekString(forKey: "previously.synced.value"), "keep-me")
        XCTAssertEqual(cloud.readCount, 0)
        XCTAssertEqual(cloud.writeCount, 0)
        XCTAssertEqual(cloud.synchronizeCount, 0)
    }

    @MainActor
    func testReenablingPushesLocalSettingsWithoutDeletingExistingCloudData() {
        let (defaults, suite) = isolatedDefaults("Reenable")
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "iCloudSyncEnabled")
        let cloud = InspectableUbiquitousStore()
        cloud.seed("keep-me", forKey: "unrelated.remote.value")
        cloud.seed("workspace-label", forKey: "menuBarPresentationMode.v1")
        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: cloud,
            connectedDisplaysProvider: { [] }
        )
        store.menuBarPresentationMode = .full
        cloud.resetCounters()

        store.iCloudSyncEnabled = true

        XCTAssertTrue(defaults.bool(forKey: "iCloudSyncEnabled"))
        XCTAssertEqual(cloud.peekString(forKey: "menuBarPresentationMode.v1"), "full")
        XCTAssertEqual(cloud.peekString(forKey: "unrelated.remote.value"), "keep-me")
        XCTAssertEqual(cloud.readCount, 0)
        XCTAssertGreaterThan(cloud.writeCount, 0)
        XCTAssertGreaterThan(cloud.synchronizeCount, 0)
    }

    @MainActor
    func testLocalOnlyModeWorksWithoutAnAvailableCloudStore() {
        let (defaults, suite) = isolatedDefaults("NoStore")
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] }
        )
        store.menuBarPresentationMode = .medium

        XCTAssertFalse(store.iCloudSyncEnabled)
        XCTAssertEqual(defaults.string(forKey: "menuBarPresentationMode.v1"), "medium")
    }

    private func isolatedDefaults(_ suffix: String) -> (UserDefaults, String) {
        let suite = "ICloudSyncSettingsTests.\(suffix).\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }
}

private final class InspectableUbiquitousStore: UbiquitousKeyValueStoring {
    private var values: [String: Any] = [:]
    private(set) var readCount = 0
    private(set) var writeCount = 0
    private(set) var synchronizeCount = 0
    var notificationObject: AnyObject { self }

    func object(forKey aKey: String) -> Any? {
        readCount += 1
        return values[aKey]
    }

    func string(forKey aKey: String) -> String? {
        readCount += 1
        return values[aKey] as? String
    }

    func data(forKey aKey: String) -> Data? {
        readCount += 1
        return values[aKey] as? Data
    }

    func set(_ anObject: Any?, forKey aKey: String) {
        writeCount += 1
        values[aKey] = anObject
    }

    func removeObject(forKey aKey: String) {
        writeCount += 1
        values.removeValue(forKey: aKey)
    }

    func synchronize() -> Bool {
        synchronizeCount += 1
        return true
    }

    func seed(_ value: Any, forKey key: String) {
        values[key] = value
    }

    func peekString(forKey key: String) -> String? {
        values[key] as? String
    }

    func resetCounters() {
        readCount = 0
        writeCount = 0
        synchronizeCount = 0
    }
}
