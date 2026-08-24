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
            DropDownAppGeometry.retractedFrame(for: bottom, in: bounds, direction: .bottom),
            WindowFrame(position: CGPoint(x: 100, y: 923), size: CGSize(width: 1_400, height: 1))
        )

        let left = DropDownAppGeometry.presentedFrame(
            in: bounds,
            sizeFraction: 0.8,
            direction: .left
        )
        XCTAssertEqual(left.position, CGPoint(x: 100, y: 24))
        XCTAssertEqual(left.size, CGSize(width: 1_120, height: 900))
        XCTAssertEqual(
            DropDownAppGeometry.retractedFrame(for: left, in: bounds, direction: .left),
            WindowFrame(position: CGPoint(x: 100, y: 24), size: CGSize(width: 1, height: 900))
        )

        let right = DropDownAppGeometry.presentedFrame(
            in: bounds,
            sizeFraction: 0.8,
            direction: .right
        )
        XCTAssertEqual(right.position, CGPoint(x: 380, y: 24))
        XCTAssertEqual(right.size, CGSize(width: 1_120, height: 900))
        XCTAssertEqual(
            DropDownAppGeometry.retractedFrame(for: right, in: bounds, direction: .right),
            WindowFrame(position: CGPoint(x: 1_499, y: 24), size: CGSize(width: 1, height: 900))
        )
    }

    func testPresentationBoundsReserveFocusBorderClearanceOnlyWhenEnabled() {
        let usableBounds = CGRect(x: -1_200, y: 30, width: 1_200, height: 1_920)

        XCTAssertEqual(
            DropDownAppGeometry.presentationBounds(
                in: usableBounds,
                focusedWindowHighlightEnabled: false
            ),
            usableBounds
        )
        XCTAssertEqual(
            DropDownAppGeometry.presentationBounds(
                in: usableBounds,
                focusedWindowHighlightEnabled: true
            ),
            CGRect(x: -1_196, y: 34, width: 1_192, height: 1_912)
        )

        let right = DropDownAppGeometry.presentedFrame(
            in: DropDownAppGeometry.presentationBounds(
                in: usableBounds,
                focusedWindowHighlightEnabled: true
            ),
            sizeFraction: 0.8,
            direction: .right
        )
        XCTAssertEqual(right.position, CGPoint(x: -957.6, y: 34))
        XCTAssertEqual(right.size, CGSize(width: 953.6, height: 1_912))
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
        object.removeValue(forKey: "quickApps")
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
            HotKeyConfiguration().chord(for: .toggleDropDownApp),
            HotKeyChord(keyCode: 50, modifiers: UInt32(controlKey | optionKey))
        )
        XCTAssertEqual(
            ConfigurableHotKeyAction.toggleDropDownApp.command,
            .toggleDropDownApp
        )
    }

    func testQuickAppFollowsOneNewSameProcessNativeTabWindow() throws {
        let previous = WindowKey(processIdentifier: 42, windowIdentifier: 100)
        let replacement = WindowKey(processIdentifier: 42, windowIdentifier: 101)

        let result = DropDownAppWindowHandoffPolicy.replacementWindowKey(
            sessionWindowKey: previous,
            sessionBundleIdentifier: "com.mitchellh.ghostty",
            removedWindowKeys: [previous],
            newlyTrackedWindowKeys: [replacement],
            availableWindows: [DropDownAppWindowHandoffCandidate(
                key: replacement,
                bundleIdentifier: "com.mitchellh.ghostty"
            )]
        )

        XCTAssertEqual(result, replacement)
    }

    func testQuickAppDoesNotFollowAmbiguousOrUnrelatedReplacementWindows() {
        let previous = WindowKey(processIdentifier: 42, windowIdentifier: 100)
        let replacement = WindowKey(processIdentifier: 42, windowIdentifier: 101)
        let other = WindowKey(processIdentifier: 42, windowIdentifier: 102)
        let otherProcess = WindowKey(processIdentifier: 73, windowIdentifier: 200)

        XCTAssertNil(DropDownAppWindowHandoffPolicy.replacementWindowKey(
            sessionWindowKey: previous,
            sessionBundleIdentifier: "com.mitchellh.ghostty",
            removedWindowKeys: [previous],
            newlyTrackedWindowKeys: [replacement, other],
            availableWindows: [
                DropDownAppWindowHandoffCandidate(
                    key: replacement,
                    bundleIdentifier: "com.mitchellh.ghostty"
                ),
                DropDownAppWindowHandoffCandidate(
                    key: other,
                    bundleIdentifier: "com.mitchellh.ghostty"
                ),
            ]
        ))
        XCTAssertNil(DropDownAppWindowHandoffPolicy.replacementWindowKey(
            sessionWindowKey: previous,
            sessionBundleIdentifier: "com.mitchellh.ghostty",
            removedWindowKeys: [previous],
            newlyTrackedWindowKeys: [otherProcess],
            availableWindows: [DropDownAppWindowHandoffCandidate(
                key: otherProcess,
                bundleIdentifier: "com.mitchellh.ghostty"
            )]
        ))
        XCTAssertNil(DropDownAppWindowHandoffPolicy.replacementWindowKey(
            sessionWindowKey: previous,
            sessionBundleIdentifier: "com.mitchellh.ghostty",
            removedWindowKeys: [previous],
            newlyTrackedWindowKeys: [replacement],
            availableWindows: [DropDownAppWindowHandoffCandidate(
                key: replacement,
                bundleIdentifier: "com.example.Other"
            )]
        ))
    }

    func testQuickAppDoesNotFollowPreexistingWindowOrWithoutAuthoritativeRemoval() {
        let previous = WindowKey(processIdentifier: 42, windowIdentifier: 100)
        let candidate = WindowKey(processIdentifier: 42, windowIdentifier: 101)
        let available = [DropDownAppWindowHandoffCandidate(
            key: candidate,
            bundleIdentifier: "com.mitchellh.ghostty"
        )]

        XCTAssertNil(DropDownAppWindowHandoffPolicy.replacementWindowKey(
            sessionWindowKey: previous,
            sessionBundleIdentifier: "com.mitchellh.ghostty",
            removedWindowKeys: [previous],
            newlyTrackedWindowKeys: [],
            availableWindows: available
        ))
        XCTAssertNil(DropDownAppWindowHandoffPolicy.replacementWindowKey(
            sessionWindowKey: previous,
            sessionBundleIdentifier: "com.mitchellh.ghostty",
            removedWindowKeys: [],
            newlyTrackedWindowKeys: [candidate],
            availableWindows: available
        ))
    }

    func testSameBundlePresentationEditsPreserveTheQuickAppSession() {
        let ghostty = DropDownAppConfiguration(
            bundleIdentifier: "com.mitchellh.ghostty",
            displayName: "Ghostty",
            heightFraction: 0.8,
            direction: .bottom
        )
        let resized = DropDownAppConfiguration(
            bundleIdentifier: "com.mitchellh.ghostty",
            displayName: "Ghostty",
            heightFraction: 0.5,
            isAnimationEnabled: false,
            direction: .top
        )
        XCTAssertTrue(DropDownAppConfigurationUpdatePolicy.shouldPreserveSession(
            previous: ghostty,
            next: resized
        ))
        XCTAssertFalse(DropDownAppConfigurationUpdatePolicy.shouldPreserveSession(
            previous: ghostty,
            next: DropDownAppConfiguration(
                bundleIdentifier: "com.apple.Terminal",
                displayName: "Terminal"
            )
        ))
        XCTAssertFalse(DropDownAppConfigurationUpdatePolicy.shouldPreserveSession(
            previous: ghostty,
            next: nil
        ))
    }

    func testQuickAppSessionSurvivesDisplaySleepAndCoordinatedWakeTopologyChanges() {
        XCTAssertFalse(DropDownAppLifecyclePolicy.shouldClearSessionForTopologyChange(
            topologyChanged: true,
            isLifecycleTransitionActive: false,
            deferredGlobalEmptySnapshot: true
        ))
        XCTAssertFalse(DropDownAppLifecyclePolicy.shouldClearSessionForTopologyChange(
            topologyChanged: true,
            isLifecycleTransitionActive: true,
            deferredGlobalEmptySnapshot: false
        ))
    }

    func testQuickAppSessionStillClearsForAnUncoordinatedActiveTopologyChange() {
        XCTAssertTrue(DropDownAppLifecyclePolicy.shouldClearSessionForTopologyChange(
            topologyChanged: true,
            isLifecycleTransitionActive: false,
            deferredGlobalEmptySnapshot: false
        ))
        XCTAssertFalse(DropDownAppLifecyclePolicy.shouldClearSessionForTopologyChange(
            topologyChanged: false,
            isLifecycleTransitionActive: false,
            deferredGlobalEmptySnapshot: false
        ))
    }

    func testStartupClaimsOneVisibleQuickAppWindowAsHidden() {
        let key = WindowKey(processIdentifier: 42, windowIdentifier: 100)

        let selection = DropDownAppStartupPolicy.selection(
            bundleIdentifier: "com.mitchellh.ghostty",
            candidates: [DropDownAppStartupCandidate(
                key: key,
                bundleIdentifier: "com.mitchellh.ghostty",
                isMeaningfullyVisible: true,
                wasHiddenByWindowRanger: false
            )]
        )

        XCTAssertEqual(
            selection,
            DropDownAppStartupSelection(
                windowKey: key,
                wasMeaningfullyVisible: true,
                wasHiddenByWindowRanger: false
            )
        )
    }

    func testStartupClaimsOneParkedQuickAppWindowAsHidden() {
        let key = WindowKey(processIdentifier: 42, windowIdentifier: 100)

        let selection = DropDownAppStartupPolicy.selection(
            bundleIdentifier: "com.mitchellh.ghostty",
            candidates: [DropDownAppStartupCandidate(
                key: key,
                bundleIdentifier: "com.mitchellh.ghostty",
                isMeaningfullyVisible: false,
                wasHiddenByWindowRanger: false
            )]
        )

        XCTAssertEqual(
            selection,
            DropDownAppStartupSelection(
                windowKey: key,
                wasMeaningfullyVisible: false,
                wasHiddenByWindowRanger: false
            )
        )
    }

    func testStartupDoesNotClaimAmbiguousOrUnrelatedQuickAppWindows() {
        let first = WindowKey(processIdentifier: 42, windowIdentifier: 100)
        let second = WindowKey(processIdentifier: 42, windowIdentifier: 101)

        XCTAssertNil(DropDownAppStartupPolicy.selection(
            bundleIdentifier: "com.mitchellh.ghostty",
            candidates: [
                DropDownAppStartupCandidate(
                    key: first,
                    bundleIdentifier: "com.mitchellh.ghostty",
                    isMeaningfullyVisible: true,
                    wasHiddenByWindowRanger: false
                ),
                DropDownAppStartupCandidate(
                    key: second,
                    bundleIdentifier: "com.mitchellh.ghostty",
                    isMeaningfullyVisible: true,
                    wasHiddenByWindowRanger: false
                ),
            ]
        ))
        XCTAssertNil(DropDownAppStartupPolicy.selection(
            bundleIdentifier: "com.mitchellh.ghostty",
            candidates: [DropDownAppStartupCandidate(
                key: first,
                bundleIdentifier: "com.example.Other",
                isMeaningfullyVisible: true,
                wasHiddenByWindowRanger: false
            )]
        ))
    }

    func testStartupRecoversOnlyTheExactWindowRangerHiddenQuickAppAsHidden() {
        let key = WindowKey(processIdentifier: 42, windowIdentifier: 100)

        let selection = DropDownAppStartupPolicy.selection(
            bundleIdentifier: "com.mitchellh.ghostty",
            candidates: [DropDownAppStartupCandidate(
                key: key,
                bundleIdentifier: "com.mitchellh.ghostty",
                isMeaningfullyVisible: false,
                wasHiddenByWindowRanger: true
            )]
        )

        XCTAssertEqual(selection, DropDownAppStartupSelection(
            windowKey: key,
            wasMeaningfullyVisible: false,
            wasHiddenByWindowRanger: true
        ))
    }

    func testHiddenSessionRecoveryRequiresTheExactWindowBundleAndStartupBoundary() {
        let key = WindowKey(processIdentifier: 42, windowIdentifier: 100)
        let persisted = PersistedDropDownAppSession(
            windowKey: key,
            bundleIdentifier: "com.mitchellh.ghostty",
            displayIdentifier: "external",
            isApplicationHiddenByWindowRanger: true
        )

        XCTAssertTrue(DropDownAppHiddenSessionRecoveryPolicy.matches(
            persisted,
            windowKey: key,
            bundleIdentifier: "com.mitchellh.ghostty",
            isStartup: true,
            isApplicationHidden: true
        ))
        XCTAssertFalse(DropDownAppHiddenSessionRecoveryPolicy.matches(
            persisted,
            windowKey: WindowKey(processIdentifier: 42, windowIdentifier: 101),
            bundleIdentifier: "com.mitchellh.ghostty",
            isStartup: true,
            isApplicationHidden: true
        ))
        XCTAssertFalse(DropDownAppHiddenSessionRecoveryPolicy.matches(
            persisted,
            windowKey: key,
            bundleIdentifier: "com.apple.Terminal",
            isStartup: true,
            isApplicationHidden: true
        ))
        XCTAssertFalse(DropDownAppHiddenSessionRecoveryPolicy.matches(
            persisted,
            windowKey: key,
            bundleIdentifier: "com.mitchellh.ghostty",
            isStartup: false,
            isApplicationHidden: true
        ))
        XCTAssertFalse(DropDownAppHiddenSessionRecoveryPolicy.matches(
            persisted,
            windowKey: key,
            bundleIdentifier: "com.mitchellh.ghostty",
            isStartup: true,
            isApplicationHidden: false
        ))
    }

    func testApplicationVisibilityConfirmationWaitsForDelayedStateWithoutWaitingForever() {
        XCTAssertEqual(
            DropDownAppVisibilityConfirmationPolicy.disposition(
                expectedHidden: false,
                observedHidden: true,
                attempt: 0
            ),
            .retry
        )
        XCTAssertEqual(
            DropDownAppVisibilityConfirmationPolicy.disposition(
                expectedHidden: false,
                observedHidden: nil,
                attempt: 9
            ),
            .retry
        )
        XCTAssertEqual(
            DropDownAppVisibilityConfirmationPolicy.disposition(
                expectedHidden: false,
                observedHidden: false,
                attempt: 10
            ),
            .confirmed
        )
        XCTAssertEqual(
            DropDownAppVisibilityConfirmationPolicy.disposition(
                expectedHidden: false,
                observedHidden: true,
                attempt: 10
            ),
            .timedOut
        )
        XCTAssertEqual(
            DropDownAppVisibilityConfirmationPolicy.disposition(
                expectedHidden: true,
                observedHidden: true,
                attempt: 1
            ),
            .confirmed
        )
        XCTAssertEqual(
            DropDownAppVisibilityConfirmationPolicy.disposition(
                expectedHidden: true,
                observedHidden: false,
                attempt: 10
            ),
            .timedOut
        )
    }

    func testApplicationVisibilityRequestUsesObservedStateInsteadOfAppKitReturnValue() {
        XCTAssertTrue(DropDownAppVisibilityRequestPolicy.wasDispatched(
            applicationMatched: true,
            appKitReturnValue: false
        ))
        XCTAssertTrue(DropDownAppVisibilityRequestPolicy.wasDispatched(
            applicationMatched: true,
            appKitReturnValue: true
        ))
        XCTAssertFalse(DropDownAppVisibilityRequestPolicy.wasDispatched(
            applicationMatched: false,
            appKitReturnValue: true
        ))
    }

    func testLaunchWindowWatchdogResolvesRetriesAndStopsAtItsBound() {
        XCTAssertTrue(
            DropDownAppLaunchWatchdogPolicy.activatesApplication,
            "A normal activation is required to make windowless apps handle reopen and create a window."
        )
        XCTAssertEqual(
            DropDownAppLaunchWatchdogPolicy.disposition(
                availableWindowCount: 1,
                remainingAttempts: 8
            ),
            .resolveToggle
        )
        XCTAssertEqual(
            DropDownAppLaunchWatchdogPolicy.disposition(
                availableWindowCount: 2,
                remainingAttempts: 8
            ),
            .resolveToggle,
            "The ordinary toggle path must report ambiguity rather than letting the watchdog guess."
        )
        XCTAssertEqual(
            DropDownAppLaunchWatchdogPolicy.disposition(
                availableWindowCount: 0,
                remainingAttempts: 8
            ),
            .retry(remainingAttempts: 7)
        )
        XCTAssertEqual(
            DropDownAppLaunchWatchdogPolicy.disposition(
                availableWindowCount: 0,
                remainingAttempts: 1
            ),
            .exhausted
        )
        XCTAssertEqual(DropDownAppLaunchWatchdogPolicy.maximumAttempts, 8)
        XCTAssertEqual(DropDownAppLaunchWatchdogPolicy.initialDelay, 0.2)
        XCTAssertEqual(DropDownAppLaunchWatchdogPolicy.retryDelay, 0.15)
    }

    func testWorkspaceStateRoundTripsTheWindowServerBoundHiddenQuickAppOwnership() throws {
        let workspaceID = UUID()
        let persisted = PersistedWorkspaceState(
            version: PersistedWorkspaceState.currentVersion,
            windowServerSession: "same-session",
            activeWorkspaceID: workspaceID,
            windows: [:],
            dropDownAppSession: PersistedDropDownAppSession(
                windowKey: WindowKey(processIdentifier: 42, windowIdentifier: 100),
                bundleIdentifier: "com.mitchellh.ghostty",
                displayIdentifier: "external",
                isApplicationHiddenByWindowRanger: true
            )
        )

        let roundTripped = try JSONDecoder().decode(
            PersistedWorkspaceState.self,
            from: JSONEncoder().encode(persisted)
        )
        XCTAssertEqual(roundTripped, persisted)

        var legacyMinimized = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(persisted)) as? [String: Any]
        )
        var legacySession = try XCTUnwrap(legacyMinimized["dropDownAppSession"] as? [String: Any])
        legacySession.removeValue(forKey: "isApplicationHiddenByWindowRanger")
        legacySession["isMinimizedByWindowRanger"] = true
        legacyMinimized["dropDownAppSession"] = legacySession
        let legacyMinimizedDecoded = try JSONDecoder().decode(
            PersistedWorkspaceState.self,
            from: JSONSerialization.data(withJSONObject: legacyMinimized)
        )
        XCTAssertEqual(
            legacyMinimizedDecoded.dropDownAppSession?.isApplicationHiddenByWindowRanger,
            false
        )

        var legacy = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(persisted)) as? [String: Any]
        )
        legacy.removeValue(forKey: "dropDownAppSession")
        let legacyDecoded = try JSONDecoder().decode(
            PersistedWorkspaceState.self,
            from: JSONSerialization.data(withJSONObject: legacy)
        )
        XCTAssertNil(legacyDecoded.dropDownAppSession)
    }
}
