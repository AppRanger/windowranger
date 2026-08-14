import Carbon
import CoreGraphics
import XCTest

final class DropDownAppTests: XCTestCase {
    func testConfigurationDefaultsToEightyPercentAnimatedFromTopAndClampsUnsafeValues() {
        let defaults = DropDownAppConfiguration(
            bundleIdentifier: "com.example.Terminal",
            displayName: "Terminal"
        )
        XCTAssertEqual(defaults.heightFraction, 0.8)
        XCTAssertTrue(defaults.isAnimationEnabled)
        XCTAssertEqual(defaults.direction, .top)
        XCTAssertEqual(
            DropDownAppConfiguration(
                bundleIdentifier: "com.example.Terminal",
                displayName: "Terminal",
                heightFraction: 0.1
            ).heightFraction,
            0.25
        )
        XCTAssertEqual(
            DropDownAppConfiguration(
                bundleIdentifier: "com.example.Terminal",
                displayName: "Terminal",
                heightFraction: 2
            ).heightFraction,
            1
        )
    }

    func testPresentedAndRetractedFramesRespectEveryScreenEdge() {
        let bounds = CGRect(x: 100, y: 24, width: 1_400, height: 900)
        let top = DropDownAppGeometry.presentedFrame(
            in: bounds,
            sizeFraction: 0.8,
            direction: .top
        )

        XCTAssertEqual(top.position, CGPoint(x: 100, y: 24))
        XCTAssertEqual(top.size, CGSize(width: 1_400, height: 720))
        let collapsedTop = DropDownAppGeometry.retractedFrame(
            for: top,
            in: bounds,
            direction: .top
        )
        XCTAssertEqual(collapsedTop.position, CGPoint(x: 100, y: 24))
        XCTAssertEqual(collapsedTop.size, CGSize(width: 1_400, height: 1))

        let bottom = DropDownAppGeometry.presentedFrame(
            in: bounds,
            sizeFraction: 0.8,
            direction: .bottom
        )
        XCTAssertEqual(bottom.position, CGPoint(x: 100, y: 204))
        XCTAssertEqual(bottom.size, CGSize(width: 1_400, height: 720))
        XCTAssertEqual(
            DropDownAppGeometry.retractedFrame(for: bottom, in: bounds, direction: .bottom).position,
            CGPoint(x: 100, y: 924)
        )

        let left = DropDownAppGeometry.presentedFrame(
            in: bounds,
            sizeFraction: 0.8,
            direction: .left
        )
        XCTAssertEqual(left.position, CGPoint(x: 100, y: 24))
        XCTAssertEqual(left.size, CGSize(width: 1_120, height: 900))
        XCTAssertEqual(
            DropDownAppGeometry.retractedFrame(for: left, in: bounds, direction: .left).position,
            CGPoint(x: -1_020, y: 24)
        )

        let right = DropDownAppGeometry.presentedFrame(
            in: bounds,
            sizeFraction: 0.8,
            direction: .right
        )
        XCTAssertEqual(right.position, CGPoint(x: 380, y: 24))
        XCTAssertEqual(right.size, CGSize(width: 1_120, height: 900))
        XCTAssertEqual(
            DropDownAppGeometry.retractedFrame(for: right, in: bounds, direction: .right).position,
            CGPoint(x: 1_500, y: 24)
        )
    }

    func testAnimationFinishesExactlyAtDestination() {
        let start = WindowFrame(
            position: CGPoint(x: 0, y: -800),
            size: CGSize(width: 1_200, height: 800)
        )
        let end = WindowFrame(
            position: CGPoint(x: 0, y: 24),
            size: CGSize(width: 1_200, height: 800)
        )

        let frames = DropDownAppGeometry.animationFrames(from: start, to: end)

        XCTAssertEqual(frames.count, DropDownAppGeometry.animationStepCount)
        XCTAssertEqual(frames.last, end)
        XCTAssertTrue(zip(frames, frames.dropFirst()).allSatisfy { $0.position.y <= $1.position.y })
    }

    func testLegacyProfileWithoutDropDownConfigurationStillDecodes() throws {
        let profile = WindowManagerProfile(
            name: "Default",
            workspaces: WorkspaceDefinition.freshDefaults(),
            displayMode: .unified,
            displayRoles: [ProfileDisplayRole(name: "Primary")],
            workspaceRoleAssignments: [:],
            appRules: []
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any]
        )
        object.removeValue(forKey: "dropDownApp")

        let decoded = try JSONDecoder().decode(
            WindowManagerProfile.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertNil(decoded.dropDownApp)
    }

    func testLegacyDropDownConfigurationDefaultsToAnimatedFromTop() throws {
        let configuration = DropDownAppConfiguration(
            bundleIdentifier: "com.example.Terminal",
            displayName: "Terminal",
            heightFraction: 0.7,
            isAnimationEnabled: false,
            direction: .right
        )
        let profile = WindowManagerProfile(
            name: "Default",
            workspaces: WorkspaceDefinition.freshDefaults(),
            displayMode: .unified,
            displayRoles: [ProfileDisplayRole(name: "Primary")],
            workspaceRoleAssignments: [:],
            appRules: [],
            dropDownApp: configuration
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any]
        )
        var oldConfiguration = try XCTUnwrap(object["dropDownApp"] as? [String: Any])
        oldConfiguration.removeValue(forKey: "isAnimationEnabled")
        oldConfiguration.removeValue(forKey: "direction")
        object["dropDownApp"] = oldConfiguration

        let decoded = try JSONDecoder().decode(
            WindowManagerProfile.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertTrue(try XCTUnwrap(decoded.dropDownApp).isAnimationEnabled)
        XCTAssertEqual(decoded.dropDownApp?.direction, .top)
        XCTAssertEqual(decoded.dropDownApp?.heightFraction, 0.7)
    }

    func testProfileRoundTripAndPortableTransferKeepDropDownConfiguration() throws {
        let configuration = DropDownAppConfiguration(
            bundleIdentifier: "com.example.Terminal",
            displayName: "Terminal",
            heightFraction: 0.7,
            isAnimationEnabled: false,
            direction: .left
        )
        let profile = WindowManagerProfile(
            name: "Default",
            workspaces: WorkspaceDefinition.freshDefaults(),
            displayMode: .unified,
            displayRoles: [ProfileDisplayRole(name: "Primary")],
            workspaceRoleAssignments: [:],
            appRules: [],
            dropDownApp: configuration
        )

        let decodedProfile = try JSONDecoder().decode(
            WindowManagerProfile.self,
            from: JSONEncoder().encode(profile)
        )
        XCTAssertEqual(decodedProfile.dropDownApp, configuration)

        let imported = try ProfileTransferCodec.decodeAndPlan(
            ProfileTransferCodec.encode(profiles: [profile]),
            existingProfiles: []
        ).importedProfiles
        XCTAssertEqual(imported.first?.dropDownApp, configuration)
    }

    func testProfileCloneAndEngineConfigurationPreserveDropDownApp() {
        let configuration = DropDownAppConfiguration(
            bundleIdentifier: "com.example.Terminal",
            displayName: "Terminal",
            heightFraction: 0.65,
            direction: .bottom
        )
        let profile = WindowManagerProfile(
            name: "Default",
            workspaces: WorkspaceDefinition.freshDefaults(),
            displayMode: .unified,
            displayRoles: [ProfileDisplayRole(name: "Primary")],
            workspaceRoleAssignments: [:],
            appRules: [],
            dropDownApp: configuration
        )

        XCTAssertEqual(profile.cloned(name: "Clone").dropDownApp, configuration)
        XCTAssertEqual(profile.normalized()?.dropDownApp, configuration)
    }

    func testProfileNormalizationMakesQuickAppWinOverConflictingRule() throws {
        let quickApp = DropDownAppConfiguration(
            bundleIdentifier: "com.example.Terminal",
            displayName: "Terminal"
        )
        let profile = WindowManagerProfile(
            name: "Default",
            workspaces: WorkspaceDefinition.freshDefaults(),
            displayMode: .unified,
            displayRoles: [ProfileDisplayRole(name: "Primary")],
            workspaceRoleAssignments: [:],
            appRules: [
                AppRule(bundleIdentifier: "com.example.Terminal", displayName: "Terminal"),
                AppRule(bundleIdentifier: "com.example.Browser", displayName: "Browser")
            ],
            dropDownApp: quickApp
        )

        let normalized = try XCTUnwrap(profile.normalized())

        XCTAssertEqual(normalized.dropDownApp, quickApp)
        XCTAssertEqual(normalized.appRules.map(\.bundleIdentifier), ["com.example.Browser"])
    }

    @MainActor
    func testSettingsStoreConvertsBetweenQuickAppAndNormalRulesExclusively() throws {
        let suite = "DropDownAppTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults, ubiquitousStore: nil)
        let application = InstalledApplication(
            bundleIdentifier: "com.example.Terminal",
            displayName: "Terminal",
            bundleURL: nil,
            isRunning: false
        )

        store.addAppRule(for: application)
        store.convertAppRuleToQuickApp(bundleIdentifier: application.bundleIdentifier)
        XCTAssertTrue(store.appRules.isEmpty)
        XCTAssertEqual(store.dropDownApp?.bundleIdentifier, application.bundleIdentifier)

        store.convertQuickAppToAppRule()
        XCTAssertNil(store.dropDownApp)
        XCTAssertEqual(store.appRules.map(\.bundleIdentifier), [application.bundleIdentifier])

        store.setDropDownApp(application)
        store.addAppRule(for: application)
        XCTAssertNil(store.dropDownApp)
        XCTAssertEqual(store.appRules.map(\.bundleIdentifier), [application.bundleIdentifier])
    }

    func testPortableImportMigratesConflictingQuickAppRule() throws {
        let quickApp = DropDownAppConfiguration(
            bundleIdentifier: "com.example.Terminal",
            displayName: "Terminal"
        )
        let profile = WindowManagerProfile(
            name: "Default",
            workspaces: WorkspaceDefinition.freshDefaults(),
            displayMode: .unified,
            displayRoles: [ProfileDisplayRole(name: "Primary")],
            workspaceRoleAssignments: [:],
            appRules: [AppRule(
                bundleIdentifier: quickApp.bundleIdentifier,
                displayName: quickApp.displayName
            )],
            dropDownApp: quickApp
        )

        let imported = try XCTUnwrap(ProfileTransferCodec.decodeAndPlan(
            ProfileTransferCodec.encode(profiles: [profile]),
            existingProfiles: []
        ).importedProfiles.first)

        XCTAssertEqual(imported.dropDownApp, quickApp)
        XCTAssertTrue(imported.appRules.isEmpty)
    }

    func testDropDownShortcutDefaultIsControlOptionBacktick() {
        XCTAssertEqual(
            ConfigurableHotKeyAction.toggleDropDownApp.defaultChord,
            HotKeyChord(keyCode: 50, modifiers: UInt32(controlKey | optionKey))
        )
        XCTAssertEqual(
            ConfigurableHotKeyAction.toggleDropDownApp.command,
            .toggleDropDownApp
        )
    }
}
