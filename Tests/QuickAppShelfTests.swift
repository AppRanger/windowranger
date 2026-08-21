import XCTest

final class QuickAppShelfTests: XCTestCase {
    private func app(_ bundle: String, _ name: String = "App") -> DropDownAppConfiguration {
        DropDownAppConfiguration(bundleIdentifier: bundle, displayName: name)
    }

    func testNormalizesDuplicatesAndCapsAtFourInOrder() {
        let values = [app("A"), app("b"), app("a"), app("C"), app("D"), app("E")]
        XCTAssertEqual(
            QuickAppShelfPolicy.normalized(values).map(\.bundleIdentifier),
            ["A", "b", "C", "D"]
        )
    }

    func testReplacingAppendsOnlyWhenCapacityAllows() {
        let values = [app("A"), app("B")]
        XCTAssertEqual(QuickAppShelfPolicy.replacing(values, with: app("C")).map(\.bundleIdentifier), ["A", "B", "C"])
        XCTAssertEqual(QuickAppShelfPolicy.replacing(values, with: app("a")).map(\.bundleIdentifier), ["A", "B"])
    }

    func testDirectSelectionAndNextPreviousSwitchingStayOnTheShelf() {
        let values = [app("A"), app("B"), app("C")]
        XCTAssertEqual(
            QuickAppShelfSelectionPolicy.selectedIndex(bundleIdentifier: "b", in: values),
            1
        )
        XCTAssertEqual(
            QuickAppShelfSelectionPolicy.index(currentBundleIdentifier: "B", offset: 1, in: values),
            2
        )
        XCTAssertEqual(
            QuickAppShelfSelectionPolicy.index(currentBundleIdentifier: "B", offset: -1, in: values),
            0
        )
        XCTAssertEqual(
            QuickAppShelfSelectionPolicy.index(currentBundleIdentifier: "C", offset: 1, in: values),
            0
        )

        var current = "A"
        var visited: [String] = []
        for _ in values.indices {
            let index = QuickAppShelfSelectionPolicy.index(
                currentBundleIdentifier: current,
                offset: 1,
                in: values
            )!
            current = values[index].bundleIdentifier
            visited.append(current)
        }
        XCTAssertEqual(visited, ["B", "C", "A"])
        XCTAssertEqual(values.map(\.bundleIdentifier), ["A", "B", "C"])
    }

    func testFourEntryCycleKeepsConfiguredOrderStable() {
        let values = [app("A"), app("B"), app("C"), app("D")]
        XCTAssertEqual(
            QuickAppShelfSelectionPolicy.index(
                currentBundleIdentifier: "C",
                offset: 1,
                in: values
            ),
            3
        )
        XCTAssertEqual(
            QuickAppShelfSelectionPolicy.index(
                currentBundleIdentifier: "D",
                offset: 1,
                in: values
            ),
            0
        )
        XCTAssertEqual(
            QuickAppShelfSelectionPolicy.index(
                currentBundleIdentifier: "A",
                offset: -1,
                in: values
            ),
            3
        )
        XCTAssertEqual(values.map(\.bundleIdentifier), ["A", "B", "C", "D"])
    }

    func testVisibleGroupUsesOnlyAvailableAppsAndCentersSelectedWhenPossible() {
        let values = [app("A"), app("B"), app("C"), app("D")]
        XCTAssertEqual(
            QuickAppShelfGroupPolicy.visibleConfigurations(
                selectedBundleIdentifier: "C",
                configurations: values,
                availableBundleIdentifiers: ["A", "c", "D"],
                maximumCount: 3
            ).map(\.bundleIdentifier),
            ["A", "C", "D"]
        )
        XCTAssertEqual(
            QuickAppShelfGroupPolicy.visibleConfigurations(
                selectedBundleIdentifier: "C",
                configurations: values,
                availableBundleIdentifiers: ["c"],
                maximumCount: 4
            ).map(\.bundleIdentifier),
            ["C"]
        )
    }

    func testCarouselAndAccordionFramesStayInsideTheShelfContainer() {
        let container = WindowFrame(
            position: CGPoint(x: 20, y: 40),
            size: CGSize(width: 900, height: 600)
        )
        let carousel = DropDownAppGeometry.groupFrames(
            in: container,
            count: 3,
            style: .carousel,
            direction: .top
        )
        XCTAssertEqual(carousel.count, 3)
        XCTAssertLessThanOrEqual(
            carousel[0].position.x + carousel[0].size.width,
            carousel[1].position.x
        )
        XCTAssertLessThanOrEqual(
            carousel[1].position.x + carousel[1].size.width,
            carousel[2].position.x
        )
        XCTAssertEqual(carousel[0].position.x, container.position.x, accuracy: 0.001)
        XCTAssertEqual(
            carousel[2].position.x + carousel[2].size.width,
            container.position.x + container.size.width,
            accuracy: 0.001
        )

        let accordion = DropDownAppGeometry.groupFrames(
            in: container,
            count: 3,
            style: .accordion,
            direction: .left
        )
        XCTAssertEqual(accordion.count, 3)
        XCTAssertLessThan(
            accordion[1].position.y,
            accordion[0].position.y + accordion[0].size.height
        )
        XCTAssertLessThan(
            accordion[2].position.y,
            accordion[1].position.y + accordion[1].size.height
        )
        XCTAssertEqual(
            accordion[1].position.y - accordion[0].position.y,
            DropDownAppGeometry.accordionVisibleEdge,
            accuracy: 0.001
        )
        XCTAssertEqual(
            accordion[2].position.y + accordion[2].size.height,
            container.position.y + container.size.height,
            accuracy: 0.001
        )
    }

    func testTransitionPolicySerializesRapidSwitchingAndKeepsDirectShowIdempotent() {
        XCTAssertEqual(
            QuickAppTransitionPolicy.switchDisposition(
                phase: .hiding("a"),
                targetBundleKey: "b"
            ),
            .queueLatest
        )
        XCTAssertEqual(
            QuickAppTransitionPolicy.switchDisposition(
                phase: .showing("a"),
                targetBundleKey: "c"
            ),
            .queueLatest
        )
        XCTAssertEqual(
            QuickAppTransitionPolicy.switchDisposition(
                phase: .launching("b"),
                targetBundleKey: "c"
            ),
            .cancelLaunchAndBegin
        )
        XCTAssertEqual(
            QuickAppTransitionPolicy.directShowDisposition(
                phase: .idle,
                isPresented: true
            ),
            .ignore
        )
        XCTAssertEqual(
            QuickAppTransitionPolicy.directShowDisposition(
                phase: .hiding("b"),
                isPresented: false
            ),
            .queueLatest
        )
    }

    func testRepeatedCycleAdvancesFromLatestPendingSelection() {
        let values = [app("A"), app("B"), app("C")]
        let firstOrigin = QuickAppTransitionPolicy.cycleOriginBundleIdentifier(
            selectedBundleIdentifier: "A",
            pendingBundleIdentifier: nil
        )
        let firstIndex = QuickAppShelfSelectionPolicy.index(
            currentBundleIdentifier: firstOrigin,
            offset: 1,
            in: values
        )
        XCTAssertEqual(firstIndex, 1)

        let secondOrigin = QuickAppTransitionPolicy.cycleOriginBundleIdentifier(
            selectedBundleIdentifier: "A",
            pendingBundleIdentifier: values[firstIndex!].bundleIdentifier
        )
        XCTAssertEqual(
            QuickAppShelfSelectionPolicy.index(
                currentBundleIdentifier: secondOrigin,
                offset: 1,
                in: values
            ),
            2
        )
    }

    func testPaletteOwnsFocusWithoutClosingPresentedShelf() {
        XCTAssertTrue(QuickAppInteractionPolicy.preservesPresentedShelfForActivation(
            activatedProcessIdentifier: 100,
            ownProcessIdentifier: 100,
            commandPalettePresented: true
        ))
        XCTAssertFalse(QuickAppInteractionPolicy.preservesPresentedShelfForActivation(
            activatedProcessIdentifier: 200,
            ownProcessIdentifier: 100,
            commandPalettePresented: true
        ))
        XCTAssertFalse(QuickAppInteractionPolicy.preservesPresentedShelfForActivation(
            activatedProcessIdentifier: 100,
            ownProcessIdentifier: 100,
            commandPalettePresented: false
        ))
        XCTAssertFalse(QuickAppInteractionPolicy.activatesApplicationForLaunch(
            commandPalettePresented: true
        ))
        XCTAssertFalse(QuickAppInteractionPolicy.focusesQuickAppAfterShow(
            commandPalettePresented: true
        ))
        XCTAssertTrue(QuickAppInteractionPolicy.activatesApplicationForLaunch(
            commandPalettePresented: false
        ))
        XCTAssertTrue(QuickAppInteractionPolicy.focusesQuickAppAfterShow(
            commandPalettePresented: false
        ))
        XCTAssertTrue(QuickAppInteractionPolicy.restoresPresentedShelfFocus(
            shelfProcessIdentifier: 200,
            precedingProcessIdentifier: 200
        ))
        XCTAssertFalse(QuickAppInteractionPolicy.restoresPresentedShelfFocus(
            shelfProcessIdentifier: 200,
            precedingProcessIdentifier: 300
        ))
        XCTAssertFalse(QuickAppInteractionPolicy.restoresPresentedShelfFocus(
            shelfProcessIdentifier: 200,
            precedingProcessIdentifier: nil
        ))
    }

    func testWindowCycleRoutesThroughPresentedShelf() {
        XCTAssertTrue(QuickAppInteractionPolicy.routesWindowCycleToShelf(
            shelfIsPresented: true,
            configuredAppCount: 3
        ))
        XCTAssertTrue(QuickAppInteractionPolicy.routesWindowCycleToShelf(
            shelfIsPresented: true,
            configuredAppCount: 1
        ))
        XCTAssertFalse(QuickAppInteractionPolicy.routesWindowCycleToShelf(
            shelfIsPresented: false,
            configuredAppCount: 3
        ))
        XCTAssertFalse(QuickAppInteractionPolicy.routesWindowCycleToShelf(
            shelfIsPresented: true,
            configuredAppCount: 0
        ))
    }

    func testInactiveSessionRebindDoesNotInvalidateAnotherAppsTransition() {
        XCTAssertFalse(QuickAppTransitionPolicy.shouldInvalidateAnimationForRebind(
            reboundBundleKey: "b",
            phase: .showing("a"),
            sessionIsPresented: false
        ))
        XCTAssertFalse(QuickAppTransitionPolicy.shouldInvalidateAnimationForRebind(
            reboundBundleKey: "b",
            phase: .hiding("a"),
            sessionIsPresented: false
        ))
        XCTAssertTrue(QuickAppTransitionPolicy.shouldInvalidateAnimationForRebind(
            reboundBundleKey: "a",
            phase: .showing("a"),
            sessionIsPresented: false
        ))
        XCTAssertTrue(QuickAppTransitionPolicy.shouldInvalidateAnimationForRebind(
            reboundBundleKey: "b",
            phase: .idle,
            sessionIsPresented: true
        ))
    }

    func testUnchangedShelfEchoDoesNotCancelClosedSecondaryLaunch() {
        let previous = [app("A"), app("B")]
        XCTAssertFalse(QuickAppTransitionPolicy.shouldCancelPendingLaunch(
            bundleIdentifier: "B",
            previousConfigurations: previous,
            nextConfigurations: previous
        ))
        XCTAssertTrue(QuickAppTransitionPolicy.shouldCancelPendingLaunch(
            bundleIdentifier: "B",
            previousConfigurations: previous,
            nextConfigurations: [app("A")]
        ))
        XCTAssertTrue(QuickAppTransitionPolicy.shouldCancelPendingLaunch(
            bundleIdentifier: "B",
            previousConfigurations: previous,
            nextConfigurations: [
                app("A"),
                DropDownAppConfiguration(
                    bundleIdentifier: "B",
                    displayName: "App",
                    heightFraction: 0.5
                ),
            ]
        ))
    }

    func testSelectedEntryRetainsExactLaunchAndAmbiguityBoundary() {
        let candidates = [
            DropDownAppStartupCandidate(
                key: WindowKey(processIdentifier: 1, windowIdentifier: 1),
                bundleIdentifier: "com.example.one",
                isMeaningfullyVisible: false,
                displayIdentifier: nil,
                wasHiddenByWindowRanger: false
            ),
            DropDownAppStartupCandidate(
                key: WindowKey(processIdentifier: 2, windowIdentifier: 2),
                bundleIdentifier: "com.example.two",
                isMeaningfullyVisible: true,
                displayIdentifier: "main",
                wasHiddenByWindowRanger: false
            ),
        ]
        XCTAssertEqual(
            DropDownAppStartupPolicy.selection(bundleIdentifier: "com.example.two", candidates: candidates)?.windowKey,
            WindowKey(processIdentifier: 2, windowIdentifier: 2)
        )
        XCTAssertNil(DropDownAppStartupPolicy.selection(
            bundleIdentifier: "com.example.two",
            candidates: candidates + [candidates[1]]
        ))
    }

    func testLegacyProfileDecodingMigratesSingleQuickAppToFirstEntry() throws {
        let configuration = DropDownAppConfiguration(
            bundleIdentifier: "com.example.quick",
            displayName: "Quick",
            heightFraction: 0.55,
            isAnimationEnabled: false,
            direction: .left
        )
        let profile = WindowManagerProfile(
            name: "Legacy",
            workspaces: WorkspaceDefinition.defaults,
            displayMode: .unified,
            displayRoles: [ProfileDisplayRole(name: "Primary")],
            workspaceRoleAssignments: [:],
            appRules: [],
            dropDownApp: configuration
        )
        let encoded = try JSONEncoder().encode(profile)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "quickApps")
        object.removeValue(forKey: "quickAppShelfPresentation")
        let decoded = try JSONDecoder().decode(
            WindowManagerProfile.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertEqual(decoded.quickApps, [configuration])
        XCTAssertEqual(decoded.dropDownApp, configuration)
        XCTAssertEqual(decoded.quickAppShelfPresentation, QuickAppShelfPresentation(configuration))
    }

    func testLegacySharedPresentationDefaultsToOneWindowCarousel() throws {
        let presentation = QuickAppShelfPresentation(
            heightFraction: 0.65,
            isAnimationEnabled: false,
            direction: .bottom
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(presentation))
                as? [String: Any]
        )
        object.removeValue(forKey: "layoutStyle")
        object.removeValue(forKey: "visibleCount")
        let decoded = try JSONDecoder().decode(
            QuickAppShelfPresentation.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertEqual(decoded.layoutStyle, .carousel)
        XCTAssertEqual(decoded.visibleCount, 1)
        XCTAssertEqual(decoded.heightFraction, 0.65, accuracy: 0.001)
        XCTAssertFalse(decoded.isAnimationEnabled)
        XCTAssertEqual(decoded.direction, .bottom)
    }

    func testPersistedShelfSessionsKeepExactOwnersAndDecodeLegacySingleSession() throws {
        let workspaceID = WorkspaceDefinition.defaults[0].id
        let sessionA = PersistedDropDownAppSession(
            windowKey: WindowKey(processIdentifier: 10, windowIdentifier: 20),
            bundleIdentifier: "com.example.A",
            displayIdentifier: "main",
            isApplicationHiddenByWindowRanger: true
        )
        let sessionB = PersistedDropDownAppSession(
            windowKey: WindowKey(processIdentifier: 11, windowIdentifier: 21),
            bundleIdentifier: "com.example.B",
            displayIdentifier: "external",
            isApplicationHiddenByWindowRanger: true
        )
        let legacy = PersistedWorkspaceState(
            version: PersistedWorkspaceState.currentVersion,
            windowServerSession: "session",
            activeWorkspaceID: workspaceID,
            windows: [:],
            dropDownAppSession: sessionA
        )
        let decodedLegacy = try JSONDecoder().decode(
            PersistedWorkspaceState.self,
            from: JSONEncoder().encode(legacy)
        )
        XCTAssertEqual(decodedLegacy.dropDownAppSession, sessionA)
        XCTAssertNil(decodedLegacy.dropDownAppSessions)

        let shelf = PersistedWorkspaceState(
            version: PersistedWorkspaceState.currentVersion,
            windowServerSession: "session",
            activeWorkspaceID: workspaceID,
            windows: [:],
            dropDownAppSession: sessionA,
            dropDownAppSessions: ["com.example.a": sessionA, "com.example.b": sessionB]
        )
        let decodedShelf = try JSONDecoder().decode(
            PersistedWorkspaceState.self,
            from: JSONEncoder().encode(shelf)
        )
        XCTAssertEqual(decodedShelf.dropDownAppSessions?["com.example.a"], sessionA)
        XCTAssertEqual(decodedShelf.dropDownAppSessions?["com.example.b"], sessionB)
    }

    func testUnsetCycleShortcutDoesNotEnableRegistration() {
        let configuration = HotKeyConfiguration()
        XCTAssertFalse(configuration.isEnabled(.cycleQuickApp))
        var configured = configuration
        configured.setChord(HotKeyChord(keyCode: 18, modifiers: 256), for: .cycleQuickApp)
        XCTAssertTrue(configured.isEnabled(.cycleQuickApp))
    }

    @MainActor
    func testStableOrderAndSelectedQuickAppArePersistedPerProfile() {
        let suite = "QuickAppShelfTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] }
        )
        let firstProfileID = store.activeProfileID
        store.quickApps = [app("com.example.one", "One"), app("com.example.two", "Two")]
        store.recordSelectedQuickApp(bundleIdentifier: "com.example.two")
        XCTAssertEqual(store.quickApps.map(\.bundleIdentifier), ["com.example.one", "com.example.two"])
        XCTAssertEqual(store.selectedQuickAppBundleIdentifier, "com.example.two")

        let secondProfileID = store.createProfileFromCurrentConfiguration(name: "Second")
        store.selectProfile(secondProfileID)
        store.quickApps = [app("com.example.three", "Three")]
        store.recordSelectedQuickApp(bundleIdentifier: "com.example.three")
        store.selectProfile(firstProfileID)

        XCTAssertEqual(store.quickApps.map(\.bundleIdentifier), ["com.example.one", "com.example.two"])
        XCTAssertEqual(store.selectedQuickAppBundleIdentifier, "com.example.two")
        XCTAssertEqual(
            store.profiles.first(where: { $0.id == secondProfileID })?.quickApps.map(\.bundleIdentifier),
            ["com.example.three"]
        )
        XCTAssertEqual(
            store.localProfileState.runtimeWorkspaceStates[secondProfileID]?
                .selectedQuickAppBundleIdentifier,
            "com.example.three"
        )
    }

    @MainActor
    func testShelfPresentationAppliesToEveryEntryAndPersistsWithProfile() {
        let suite = "QuickAppShelfTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] }
        )
        store.quickApps = [app("com.example.one", "One"), app("com.example.two", "Two")]
        store.setDropDownAppDirection(.right)
        store.setDropDownAppHeightFraction(0.6)
        store.setDropDownAppAnimationEnabled(false)
        store.setQuickAppShelfLayoutStyle(.accordion)
        store.setQuickAppShelfVisibleCount(3)

        let expected = QuickAppShelfPresentation(
            heightFraction: 0.6,
            isAnimationEnabled: false,
            direction: .right,
            layoutStyle: .accordion,
            visibleCount: 3
        )
        XCTAssertEqual(store.quickAppShelfPresentation, expected)
        XCTAssertTrue(store.quickApps.allSatisfy { expected.applying(to: $0) == $0 })
        XCTAssertEqual(store.activeProfile.quickAppShelfPresentation, expected)
        XCTAssertTrue(store.activeProfile.quickApps.allSatisfy { expected.applying(to: $0) == $0 })
    }

    func testShelfPresentationRoundTripsThroughProfileExport() throws {
        let presentation = QuickAppShelfPresentation(
            heightFraction: 0.45,
            isAnimationEnabled: false,
            direction: .bottom,
            layoutStyle: .accordion,
            visibleCount: 4
        )
        let profile = WindowManagerProfile(
            name: "Shelf",
            workspaces: WorkspaceDefinition.defaults,
            displayMode: .unified,
            displayRoles: [ProfileDisplayRole(name: "Primary")],
            workspaceRoleAssignments: [:],
            appRules: [],
            quickApps: [app("com.example.one", "One"), app("com.example.two", "Two")],
            quickAppShelfPresentation: presentation
        )

        let archive = try JSONDecoder().decode(
            PortableProfileArchive.self,
            from: ProfileTransferCodec.encode(profiles: [profile])
        )
        let exported = try XCTUnwrap(archive.profiles.first)
        XCTAssertEqual(exported.quickAppShelfPresentation, presentation)
        XCTAssertTrue(exported.quickApps.allSatisfy { presentation.applying(to: $0) == $0 })
    }
}
