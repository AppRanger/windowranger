import Carbon
import XCTest

final class WorkspaceDefinitionTests: XCTestCase {
    func testDefaultsContainFourNumberedWorkspaces() {
        XCTAssertEqual(WorkspaceDefinition.defaults.map(\.name), ["1", "2", "3", "4"])
        XCTAssertEqual(WorkspaceDefinition.defaults.map(\.key), ["1", "2", "3", "4"])
    }

    func testDefaultWorkspaceKeysAreUnique() {
        let keys = WorkspaceDefinition.defaults.map(\.key)
        XCTAssertEqual(Set(keys).count, keys.count)
    }

    func testFreshDefaultsUseFreshIdentities() {
        let first = WorkspaceDefinition.freshDefaults()
        let second = WorkspaceDefinition.freshDefaults()

        XCTAssertEqual(first.map(\.name), WorkspaceDefinition.defaults.map(\.name))
        XCTAssertTrue(Set(first.map(\.id)).isDisjoint(with: second.map(\.id)))
    }

    func testWorkspaceDefinitionsRoundTripThroughJSON() throws {
        let data = try JSONEncoder().encode(WorkspaceDefinition.defaults)
        let decoded = try JSONDecoder().decode([WorkspaceDefinition].self, from: data)
        XCTAssertEqual(decoded, WorkspaceDefinition.defaults)
    }

    func testLegacyWorkspaceDefinitionMigratesToNoneLayout() throws {
        let id = WorkspaceDefinition.defaults[0].id
        let json = """
        {"id":"\(id.uuidString)","name":"Legacy","key":"L"}
        """

        let decoded = try JSONDecoder().decode(WorkspaceDefinition.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.layout, .none)
        XCTAssertEqual(decoded.key, "l")
        XCTAssertNil(decoded.layoutConfiguration)
    }

    func testNewWorkspaceUsesConfirmedAeroSpaceLayoutDefaults() {
        let workspace = WorkspaceDefinition(name: "New", key: "n")

        XCTAssertEqual(workspace.layoutConfiguration, .aeroSpaceUserDefaults)
        XCTAssertEqual(workspace.layoutConfiguration?.orientation, .automatic)
        XCTAssertEqual(workspace.layoutConfiguration?.accordionPadding, 250)
        XCTAssertEqual(workspace.layoutConfiguration?.gaps.innerHorizontal, 5)
        XCTAssertEqual(workspace.layoutConfiguration?.gaps.innerVertical, 5)
        XCTAssertEqual(workspace.layoutConfiguration?.gaps.outerTop, 0)
    }

    func testWorkspaceLayoutSelectionPersistsAcrossJSONRestart() throws {
        let workspace = WorkspaceDefinition(name: "Code", key: "c", layout: .accordion)

        let restored = try JSONDecoder().decode(
            WorkspaceDefinition.self,
            from: JSONEncoder().encode(workspace)
        )

        XCTAssertEqual(restored, workspace)
        XCTAssertEqual(restored.layout, .accordion)
    }

    func testWorkspaceLayoutCycleWrapsInBothDirections() {
        XCTAssertEqual(WorkspaceLayout.none.cycled(by: 1), .tiled)
        XCTAssertEqual(WorkspaceLayout.tiled.cycled(by: 1), .accordion)
        XCTAssertEqual(WorkspaceLayout.accordion.cycled(by: 1), .none)
        XCTAssertEqual(WorkspaceLayout.none.cycled(by: -1), .accordion)
    }

    func testSuccessfulEnumerationEvictsClosedNativeTabFromEveryPureManagedIndex() throws {
        let workspaceID = UUID()
        let partition = TiledLayoutPartitionKey(workspaceID: workspaceID, displayIdentifier: "main")
        let first = WindowKey(processIdentifier: 42, windowIdentifier: 100)
        let closedTab = WindowKey(processIdentifier: 42, windowIdentifier: 101)
        let third = WindowKey(processIdentifier: 73, windowIdentifier: 200)
        let tree = TiledNode.split(
            axis: .horizontal,
            ratio: 0.4,
            first: .window(first),
            second: .split(
                axis: .vertical,
                ratio: 0.65,
                first: .window(closedTab),
                second: .window(third)
            )
        )

        let removed = WindowEnumerationLifecycle.removedTrackedWindowKeys(
            trackedWindowKeys: [first, closedTab, third],
            runningProcessIdentifiers: [42, 73],
            successfullyEnumeratedProcessIdentifiers: [42, 73],
            enumeratedWindowKeys: [first, third]
        )
        let trees = WindowEnumerationLifecycle.pruning(
            [partition: tree],
            removedWindowKeys: removed
        )
        let history = WindowEnumerationLifecycle.pruning(
            [workspaceID: closedTab],
            removedWindowKeys: removed
        )

        XCTAssertEqual(removed, [closedTab])
        XCTAssertEqual(try XCTUnwrap(trees[partition]).windowKeys, [first, third])
        guard case let .split(axis, ratio, _, _) = try XCTUnwrap(trees[partition]) else {
            return XCTFail("The surviving topology should collapse only the closed tab's parent")
        }
        XCTAssertEqual(axis, .horizontal)
        XCTAssertEqual(ratio, 0.4)
        XCTAssertTrue(history.isEmpty)
    }

    func testFailedWindowEnumerationRetainsNativeTabsForRecovery() {
        let first = WindowKey(processIdentifier: 42, windowIdentifier: 100)
        let inactiveTab = WindowKey(processIdentifier: 42, windowIdentifier: 101)

        XCTAssertTrue(WindowEnumerationLifecycle.removedTrackedWindowKeys(
            trackedWindowKeys: [first, inactiveTab],
            runningProcessIdentifiers: [42],
            successfullyEnumeratedProcessIdentifiers: [],
            enumeratedWindowKeys: []
        ).isEmpty)
    }

    func testFreeformDisplayNamePreservesMigrationSafeRawValue() {
        XCTAssertEqual(WorkspaceLayout.none.title, "Freeform")
        XCTAssertEqual(WorkspaceLayout.none.rawValue, "none")
        XCTAssertEqual(WorkspaceLayout(rawValue: "none"), Optional(WorkspaceLayout.none))
    }

    func testLayoutSelectionShortcutsKeepEstablishedDirectMappings() {
        XCTAssertEqual(ConfigurableHotKeyAction.selectAccordion.defaultKeyCode, 43)
        XCTAssertEqual(ConfigurableHotKeyAction.selectTiled.defaultKeyCode, 47)
        XCTAssertEqual(
            ConfigurableHotKeyAction.selectAccordion.command,
            .selectLayoutFromShortcut(.accordion)
        )
        XCTAssertEqual(
            ConfigurableHotKeyAction.selectTiled.command,
            .selectLayoutFromShortcut(.tiled)
        )
    }

    func testRepeatedTiledShortcutSelectionAlternatesConcreteOrientationAndPreservesGeometrySettings() throws {
        let tiled = WorkspaceDefinition(
            name: "Code",
            key: "c",
            layout: .tiled,
            layoutConfiguration: WorkspaceLayoutConfiguration(
                orientation: .automatic,
                accordionPadding: 173,
                gaps: WorkspaceLayoutGaps(
                    innerHorizontal: 7,
                    innerVertical: 9,
                    outerTop: 11,
                    outerRight: 13,
                    outerBottom: 15,
                    outerLeft: 17
                )
            )
        )
        let first = WorkspaceEngine.layoutDefinitionAfterSelection(
            tiled,
            targetLayout: .tiled,
            cycleOrientationWhenAlreadySelected: true,
            automaticOrientation: .horizontal
        )
        let second = WorkspaceEngine.layoutDefinitionAfterSelection(
            first,
            targetLayout: .tiled,
            cycleOrientationWhenAlreadySelected: true,
            automaticOrientation: .horizontal
        )

        XCTAssertEqual(first.layoutConfiguration?.orientation, .vertical)
        XCTAssertEqual(second.layoutConfiguration?.orientation, .horizontal)
        XCTAssertEqual(first.layoutConfiguration?.accordionPadding, 173)
        XCTAssertEqual(first.layoutConfiguration?.gaps, tiled.layoutConfiguration?.gaps)

        let restarted = try JSONDecoder().decode(
            WorkspaceDefinition.self,
            from: JSONEncoder().encode(second)
        )
        XCTAssertEqual(restarted, second)
        XCTAssertEqual(restarted.layoutConfiguration?.orientation, .horizontal)
    }

    func testRepeatedAccordionShortcutSelectionAlternatesOrientationAndPreservesConfiguration() throws {
        let accordion = WorkspaceDefinition(
            name: "Writing",
            key: "w",
            layout: .accordion,
            layoutConfiguration: WorkspaceLayoutConfiguration(
                orientation: .horizontal,
                accordionPadding: 321,
                gaps: WorkspaceLayoutGaps(
                    innerHorizontal: 0,
                    innerVertical: 0,
                    outerTop: 0,
                    outerRight: 0,
                    outerBottom: 0,
                    outerLeft: 0
                )
            )
        )

        let first = WorkspaceEngine.layoutDefinitionAfterSelection(
            accordion,
            targetLayout: .accordion,
            cycleOrientationWhenAlreadySelected: true,
            automaticOrientation: .horizontal
        )
        let second = WorkspaceEngine.layoutDefinitionAfterSelection(
            first,
            targetLayout: .accordion,
            cycleOrientationWhenAlreadySelected: true,
            automaticOrientation: .horizontal
        )

        XCTAssertEqual(first.layoutConfiguration?.orientation, .vertical)
        XCTAssertEqual(second.layoutConfiguration?.orientation, .horizontal)
        XCTAssertEqual(first.layoutConfiguration?.accordionPadding, 321)
        XCTAssertEqual(first.layoutConfiguration?.gaps, accordion.layoutConfiguration?.gaps)

        let restarted = try JSONDecoder().decode(
            WorkspaceDefinition.self,
            from: JSONEncoder().encode(second)
        )
        XCTAssertEqual(restarted, second)
        XCTAssertEqual(restarted.layoutConfiguration?.orientation, .horizontal)
    }

    func testAutomaticOrientationCyclesToTheOppositeVisiblePortraitDirection() {
        let tiled = WorkspaceDefinition(
            name: "Portrait",
            key: "p",
            layout: .tiled,
            layoutConfiguration: .aeroSpaceUserDefaults
        )

        let cycled = WorkspaceEngine.layoutDefinitionAfterSelection(
            tiled,
            targetLayout: .tiled,
            cycleOrientationWhenAlreadySelected: true,
            automaticOrientation: .vertical
        )

        XCTAssertEqual(cycled.layoutConfiguration?.orientation, .horizontal)
    }

    func testSelectingDifferentLayoutActivatesModernDefaultsWithoutChangingOrientation() {
        let legacy = WorkspaceDefinition(
            name: "Legacy",
            key: "l",
            layout: .none,
            layoutConfiguration: nil
        )
        let tiled = WorkspaceEngine.layoutDefinitionAfterSelection(
            legacy,
            targetLayout: .tiled,
            cycleOrientationWhenAlreadySelected: true,
            automaticOrientation: .horizontal
        )

        XCTAssertEqual(tiled.layout, .tiled)
        XCTAssertEqual(tiled.layoutConfiguration, .aeroSpaceUserDefaults)

        var configured = legacy
        configured.layoutConfiguration = WorkspaceLayoutConfiguration(
            orientation: .vertical,
            accordionPadding: 175,
            gaps: .aeroSpaceUserDefaults
        )
        let configuredTiled = WorkspaceEngine.layoutDefinitionAfterSelection(
            configured,
            targetLayout: .tiled,
            cycleOrientationWhenAlreadySelected: true,
            automaticOrientation: .horizontal
        )
        XCTAssertEqual(configuredTiled.layout, .tiled)
        XCTAssertEqual(configuredTiled.layoutConfiguration, configured.layoutConfiguration)
    }

    func testNonShortcutLayoutSelectionDoesNotCycleAnAlreadySelectedLayout() {
        let tiled = WorkspaceDefinition(
            name: "Code",
            key: "c",
            layout: .tiled,
            layoutConfiguration: WorkspaceLayoutConfiguration(
                orientation: .vertical,
                accordionPadding: 250,
                gaps: .aeroSpaceUserDefaults
            )
        )

        XCTAssertEqual(
            WorkspaceEngine.layoutDefinitionAfterSelection(
                tiled,
                targetLayout: .tiled,
                cycleOrientationWhenAlreadySelected: false,
                automaticOrientation: .horizontal
            ),
            tiled
        )
    }

    func testFloatingShortcutUsesApprovedArrangeFDefault() {
        XCTAssertEqual(ConfigurableHotKeyAction.toggleFloating.defaultKeyCode, 3)
        XCTAssertEqual(
            ConfigurableHotKeyAction.toggleFloating.family.defaultModifiers,
            UInt32(optionKey | cmdKey)
        )
    }

    func testFloatingToggleSwitchesInBothDirections() {
        let normal = WindowAdmissionDecision(disposition: .managedNormal, reason: .normalWindow)
        XCTAssertEqual(
            WorkspaceEngine.floatingToggleDecision(
                currentOverride: .automatic,
                admissionDecision: normal,
                rule: .none
            ),
            .setLayoutOverride(.floating)
        )
        XCTAssertEqual(
            WorkspaceEngine.floatingToggleDecision(
                currentOverride: .floating,
                admissionDecision: normal,
                rule: .none
            ),
            .setLayoutOverride(.managed)
        )
    }

    func testAppLayoutExclusionBlocksPerWindowFloatingToggle() {
        let rule = ResolvedAppRule(
            assignedWorkspaceID: nil,
            keepsOnAllWorkspaces: false,
            excludesFromLayout: true
        )

        XCTAssertEqual(
            WorkspaceEngine.floatingToggleDecision(
                currentOverride: .automatic,
                admissionDecision: WindowAdmissionDecision(
                    disposition: .managedNormal,
                    reason: .normalWindow
                ),
                rule: rule
            ),
            .blockedByAppRule
        )
        XCTAssertEqual(WorkspaceEngine.restoredLayoutOverride(.floating), .floating)
    }

    func testFloatingWindowIsExcludedWhileManagedWindowRemainsInLayout() {
        XCTAssertFalse(WorkspaceEngine.shouldIncludeInLayout(
            isFloating: true,
            rule: .none
        ))
        XCTAssertTrue(WorkspaceEngine.shouldIncludeInLayout(
            isFloating: false,
            rule: .none
        ))
        XCTAssertEqual(
            WorkspaceEngine.layoutFrames(
                .tiled,
                count: [false, true, false].filter {
                    WorkspaceEngine.shouldIncludeInLayout(isFloating: $0, rule: .none)
                }.count,
                in: CGRect(x: 0, y: 0, width: 1920, height: 1080)
            ).count,
            2
        )
    }

    func testFloatingDisplayResolutionPreservesUnifiedAffinityAndIndependentHome() {
        let displays = testDisplays()
        let frame = WindowFrame(
            position: CGPoint(x: 2200, y: 100),
            size: CGSize(width: 800, height: 600)
        )

        XCTAssertEqual(WorkspaceEngine.layoutDisplayIdentifier(
            preferredDisplayIdentifier: "external",
            savedFrame: frame,
            mode: .unified,
            workspaceHomeDisplayIdentifier: nil,
            displays: displays
        ), "external")
        XCTAssertEqual(WorkspaceEngine.layoutDisplayIdentifier(
            preferredDisplayIdentifier: "main",
            savedFrame: frame,
            mode: .independent,
            workspaceHomeDisplayIdentifier: "external",
            displays: displays
        ), "external")
        XCTAssertEqual(WorkspaceEngine.displayModeForWindowPlacement(
            configuredMode: .independent,
            rule: ResolvedAppRule(
                assignedWorkspaceID: nil,
                keepsOnAllWorkspaces: true,
                excludesFromLayout: false
            )
        ), .unified)
    }

    func testAppRuleActionsCanBeCreatedAndEditedIndependently() {
        let workspaceID = WorkspaceDefinition.defaults[1].id
        var rule = AppRule(bundleIdentifier: "com.example.Editor", displayName: "Editor")

        rule.assignedWorkspaceID = workspaceID
        rule.keepsOnAllWorkspaces = true
        rule.excludesFromLayout = true

        XCTAssertEqual(rule.assignedWorkspaceID, workspaceID)
        XCTAssertTrue(rule.keepsOnAllWorkspaces)
        XCTAssertTrue(rule.excludesFromLayout)

        rule.keepsOnAllWorkspaces = false
        XCTAssertFalse(rule.keepsOnAllWorkspaces)
        XCTAssertEqual(rule.assignedWorkspaceID, workspaceID)
        XCTAssertTrue(rule.excludesFromLayout)
    }

    func testPausedAppRulePreservesActionsButResolvesToNoPolicy() {
        let workspaceID = WorkspaceDefinition.defaults[1].id
        var rule = AppRule(
            bundleIdentifier: "com.example.Editor",
            displayName: "Editor",
            actions: [
                .assignWorkspace(workspaceID),
                .keepOnAllWorkspaces,
                .excludeFromLayout,
                .floatSecondaryWindows,
            ],
            isEnabled: false
        )

        XCTAssertEqual(rule.resolved(validWorkspaceIDs: [workspaceID]), .none)
        XCTAssertEqual(rule.assignedWorkspaceID, workspaceID)
        XCTAssertTrue(rule.keepsOnAllWorkspaces)
        XCTAssertTrue(rule.excludesFromLayout)
        XCTAssertTrue(rule.floatsSecondaryWindows)

        rule.isEnabled = true
        let resumed = rule.resolved(validWorkspaceIDs: [workspaceID])
        XCTAssertTrue(resumed.keepsOnAllWorkspaces)
        XCTAssertNil(resumed.assignedWorkspaceID)
        XCTAssertTrue(resumed.excludesFromLayout)
        XCTAssertTrue(resumed.floatsSecondaryWindows)
    }

    func testLegacyAppRuleWithoutEnabledFieldMigratesEnabled() throws {
        let json = """
        {
          "bundleIdentifier": "com.example.Legacy",
          "displayName": "Legacy",
          "actions": []
        }
        """

        let rule = try JSONDecoder().decode(AppRule.self, from: Data(json.utf8))

        XCTAssertTrue(rule.isEnabled)
        XCTAssertEqual(rule.resolved(validWorkspaceIDs: []), .none)
    }

    func testAppRulesPersistAcrossJSONRestart() throws {
        let workspaceID = WorkspaceDefinition.defaults[2].id
        let rules = [AppRule(
            bundleIdentifier: "com.example.Editor",
            displayName: "Example Editor",
            actions: [.assignWorkspace(workspaceID), .excludeFromLayout]
        )]

        let restored = try JSONDecoder().decode(
            [AppRule].self,
            from: JSONEncoder().encode(rules)
        )

        XCTAssertEqual(restored, rules)
        XCTAssertEqual(restored[0].id, "com.example.editor")
        XCTAssertTrue(restored[0].isEnabled)
    }

    @MainActor
    func testSettingsStoreRestoresAppRulesFromLocalPreferences() {
        let suiteName = "WindowRangerTests.AppRules.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated preferences")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: "iCloudSyncEnabled")
        let workspaceID = WorkspaceDefinition.defaults[3].id
        let expected = [AppRule(
            bundleIdentifier: "com.example.Terminal",
            displayName: "Terminal",
            actions: [.assignWorkspace(workspaceID), .excludeFromLayout]
        )]

        do {
            let writer = SettingsStore(
                defaults: defaults,
                ubiquitousStore: nil,
                connectedDisplaysProvider: { [] }
            )
            writer.appRules = expected
        }

        let reader = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] }
        )
        XCTAssertEqual(reader.appRules, expected)
    }

    @MainActor
    func testApplicationRuleChangeAppliesImmediatelyAndCanBeUndone() {
        let suiteName = "WindowRangerTests.AppRuleUndo.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated preferences")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: "iCloudSyncEnabled")
        let store = SettingsStore(
            defaults: defaults,
            ubiquitousStore: nil,
            connectedDisplaysProvider: { [] }
        )
        let original = AppRule(
            bundleIdentifier: "com.example.Editor",
            displayName: "Editor"
        )
        store.appRules = [original]
        let undoManager = UndoManager()
        var changed = original
        changed.excludesFromLayout = true

        store.updateAppRule(changed, undoManager: undoManager)
        XCTAssertTrue(store.appRules[0].excludesFromLayout)
        XCTAssertTrue(undoManager.canUndo)

        undoManager.undo()
        XCTAssertEqual(store.appRules, [original])
        XCTAssertTrue(undoManager.canRedo)
    }

    func testKeepOnAllWorkspacesTakesPrecedenceOverAssignment() {
        let workspaceID = WorkspaceDefinition.defaults[3].id
        let rule = AppRule(
            bundleIdentifier: "com.example.Chat",
            displayName: "Chat",
            actions: [.assignWorkspace(workspaceID), .keepOnAllWorkspaces]
        )

        let resolved = rule.resolved(validWorkspaceIDs: [workspaceID])

        XCTAssertTrue(resolved.keepsOnAllWorkspaces)
        XCTAssertNil(resolved.assignedWorkspaceID)
    }

    func testUnknownWorkspaceAssignmentIsIgnoredSafely() {
        let rule = AppRule(
            bundleIdentifier: "com.example.Editor",
            displayName: "Editor",
            actions: [.assignWorkspace(UUID())]
        )

        XCTAssertNil(rule.resolved(validWorkspaceIDs: Set(WorkspaceDefinition.defaults.map(\.id))).assignedWorkspaceID)
    }

    func testAssignedWorkspaceOverridesRememberedWorkspaceDuringRestartRecovery() {
        let rememberedWorkspaceID = WorkspaceDefinition.defaults[0].id
        let assignedWorkspaceID = WorkspaceDefinition.defaults[1].id
        let rule = AppRule(
            bundleIdentifier: "com.example.Editor",
            displayName: "Editor",
            actions: [.assignWorkspace(assignedWorkspaceID)]
        ).resolved(validWorkspaceIDs: [rememberedWorkspaceID, assignedWorkspaceID])

        XCTAssertEqual(
            WorkspaceEngine.routedWorkspaceID(
                fallbackWorkspaceID: rememberedWorkspaceID,
                rule: rule
            ),
            assignedWorkspaceID
        )
    }

    func testKeepOnAllWindowIsVisibleWhenItsStoredWorkspaceIsInactive() {
        let storedWorkspaceID = WorkspaceDefinition.defaults[0].id
        let activeWorkspaceID = WorkspaceDefinition.defaults[1].id
        let rule = ResolvedAppRule(
            assignedWorkspaceID: nil,
            keepsOnAllWorkspaces: true,
            excludesFromLayout: false
        )

        XCTAssertTrue(WorkspaceEngine.shouldWindowBeVisible(
            workspaceID: storedWorkspaceID,
            activeWorkspaceIDs: [activeWorkspaceID],
            rule: rule
        ))
        XCTAssertFalse(WorkspaceEngine.shouldWindowBeVisible(
            workspaceID: storedWorkspaceID,
            activeWorkspaceIDs: [activeWorkspaceID],
            rule: .none
        ))
    }

    func testLayoutExclusionIsIndependentFromVisibilityRule() {
        let rule = ResolvedAppRule(
            assignedWorkspaceID: nil,
            keepsOnAllWorkspaces: true,
            excludesFromLayout: true
        )

        XCTAssertFalse(WorkspaceEngine.shouldIncludeInLayout(rule: rule))
        XCTAssertTrue(WorkspaceEngine.shouldIncludeInLayout(rule: .none))
    }

    func testCodexLayerThreeDialogIsIgnoredAtCentralAdmissionBoundary() {
        let decision = AccessibilityWindow.admissionDecision(for: WindowAdmissionMetadata(
            bundleIdentifier: "com.openai.codex",
            role: kAXWindowRole as String,
            subrole: kAXDialogSubrole as String,
            windowLayer: 3,
            isMinimized: false
        ))

        XCTAssertEqual(decision, WindowAdmissionDecision(
            disposition: .ignoredTransientPopup,
            reason: .verifiedBundleNonNormalLayer,
            compatibilityProfileIdentifier: "codex-transient-non-normal-layer-v1"
        ))
        XCTAssertFalse(decision.disposition.admitsNewWindow)
        XCTAssertTrue(decision.disposition.evictsTrackedWindow)
    }

    func testTaggedDesktopRangerSurfaceIsIgnoredAtCentralAdmissionBoundary() {
        let decision = AccessibilityWindow.admissionDecision(for: WindowAdmissionMetadata(
            bundleIdentifier: "dev.appranger.DesktopRanger.SurfaceLab",
            accessibilityIdentifier: AccessibilityWindow.desktopRangerSurfaceAccessibilityIdentifier,
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            windowLayer: 0,
            isMinimized: false
        ))

        XCTAssertEqual(decision, WindowAdmissionDecision(
            disposition: .ignoredCompanionSurface,
            reason: .rangerCompanionSurface,
            compatibilityProfileIdentifier: "desktopranger-owned-surface-v1"
        ))
        XCTAssertFalse(decision.disposition.admitsNewWindow)
        XCTAssertTrue(decision.disposition.evictsTrackedWindow)
    }

    func testCodexNormalAndUnknownLayersRemainManagedConservatively() {
        let normal = AccessibilityWindow.admissionDecision(for: WindowAdmissionMetadata(
            bundleIdentifier: "com.openai.codex",
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            windowLayer: 0,
            isMinimized: false
        ))
        let unknownDialog = AccessibilityWindow.admissionDecision(for: WindowAdmissionMetadata(
            bundleIdentifier: "com.openai.codex",
            role: kAXWindowRole as String,
            subrole: kAXDialogSubrole as String,
            windowLayer: nil,
            isMinimized: false
        ))

        XCTAssertEqual(normal.disposition, .managedNormal)
        XCTAssertEqual(unknownDialog.disposition, .managedNormal)
        XCTAssertEqual(unknownDialog.reason, .ambiguousDialogMetadata)
        XCTAssertTrue(normal.disposition.admitsNewWindow)
        XCTAssertTrue(unknownDialog.disposition.admitsNewWindow)
    }

    func testFixedSizeSimulatorDeviceWindowFloatsByCapabilityWithoutWholeAppPolicy() {
        let coreMetadata = WindowAdmissionMetadata(
            bundleIdentifier: "com.apple.iphonesimulator",
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            windowLayer: 0,
            isMinimized: false,
            fullscreenButton: .present,
            closeButton: .present
        )
        XCTAssertTrue(AccessibilityWindow.shouldCollectFixedSizeStandardWindowEvidence(coreMetadata))
        XCTAssertFalse(AccessibilityWindow.shouldCollectSupportMetadataForCompatibility(coreMetadata))
        XCTAssertFalse(AccessibilityWindow.mayNeedDirectLayerResolutionForCompatibility(
            "com.apple.iphonesimulator"
        ))

        let fixedSizeDevice = WindowAdmissionMetadata(
            bundleIdentifier: "com.apple.iphonesimulator",
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            windowLayer: 0,
            isMinimized: false,
            fullscreenButton: .present,
            minimizeButton: .present,
            closeButton: .present,
            zoomButton: .present,
            positionSettable: .trueValue,
            sizeSettable: .falseValue
        )
        let decision = AccessibilityWindow.admissionDecision(for: fixedSizeDevice)

        XCTAssertEqual(decision, WindowAdmissionDecision(
            disposition: .managedDialog,
            reason: .fixedSizeStandardWindow
        ))
        XCTAssertFalse(WorkspaceEngine.shouldIncludeInLayout(
            layoutOverride: .automatic,
            admissionDecision: decision,
            rule: .none
        ))
        XCTAssertEqual(
            WorkspaceEngine.layoutDecision(
                layoutOverride: .managed,
                admissionDecision: decision,
                rule: .none
            ),
            .automaticallyFloatingDialog
        )
        XCTAssertEqual(
            WorkspaceEngine.floatingToggleDecision(
                currentOverride: .automatic,
                admissionDecision: decision,
                rule: .none
            ),
            .blockedByFixedSizeWindow
        )
        XCTAssertEqual(WorkspaceEngine.geometryWriteMode(for: decision), .positionOnly)

        let resolvedOnSmallerDisplay = WorkspaceEngine.resolveDisplayFrame(
            savedFrame: WindowFrame(
                position: CGPoint(x: 3_839, y: 1_568),
                size: CGSize(width: 1_400, height: 1_200)
            ),
            placement: PersistedDisplayPlacement(
                displayIdentifier: "removed-display",
                normalizedOrigin: CGPoint(x: 0.5, y: 0.5)
            ),
            displays: [DisplaySnapshot(
                identifier: "main",
                bounds: CGRect(x: 0, y: 0, width: 1_000, height: 800),
                isMain: true,
                name: "Main"
            )]
        )
        XCTAssertEqual(resolvedOnSmallerDisplay.frame.size, CGSize(width: 1_000, height: 800))
        XCTAssertEqual(resolvedOnSmallerDisplay.frame.position, .zero)
        XCTAssertEqual(WorkspaceEngine.geometryWriteMode(for: decision), .positionOnly)

        let resizableDevice = WindowAdmissionMetadata(
            bundleIdentifier: "com.apple.iphonesimulator",
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            windowLayer: 0,
            isMinimized: false,
            fullscreenButton: .present,
            minimizeButton: .present,
            closeButton: .present,
            zoomButton: .present,
            positionSettable: .trueValue,
            sizeSettable: .trueValue
        )
        XCTAssertEqual(
            AccessibilityWindow.admissionDecision(for: resizableDevice),
            WindowAdmissionDecision(disposition: .managedNormal, reason: .normalWindow)
        )
        XCTAssertEqual(
            WorkspaceEngine.geometryWriteMode(
                for: AccessibilityWindow.admissionDecision(for: resizableDevice)
            ),
            .frame
        )

        let unrelatedFixedSizeWindow = WindowAdmissionMetadata(
            bundleIdentifier: "com.example.FixedSizeUtility",
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            windowLayer: 0,
            isMinimized: false,
            fullscreenButton: .present,
            closeButton: .present,
            positionSettable: .trueValue,
            sizeSettable: .falseValue
        )
        XCTAssertEqual(
            AccessibilityWindow.admissionDecision(for: unrelatedFixedSizeWindow),
            WindowAdmissionDecision(disposition: .managedDialog, reason: .fixedSizeStandardWindow)
        )

        let normalDecision = WindowAdmissionDecision(
            disposition: .managedNormal,
            reason: .normalWindow
        )
        let participantCount = [normalDecision, normalDecision, decision, decision].filter {
            WorkspaceEngine.shouldIncludeInLayout(
                layoutOverride: .automatic,
                admissionDecision: $0,
                rule: .none
            )
        }.count
        XCTAssertEqual(participantCount, 2)
    }

    func testNonNormalLayerStandardWindowIsNotRejectedGloballyForUnverifiedApplications() {
        let decision = AccessibilityWindow.admissionDecision(for: WindowAdmissionMetadata(
            bundleIdentifier: "com.example.UnusualWindowLevels",
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            windowLayer: 3,
            isMinimized: false
        ))

        XCTAssertEqual(decision.disposition, .managedNormal)
        XCTAssertEqual(decision.reason, .normalWindow)
        XCTAssertTrue(AccessibilityWindow.mayNeedDirectLayerResolutionForCompatibility("COM.OPENAI.CODEX"))
        XCTAssertFalse(AccessibilityWindow.mayNeedDirectLayerResolutionForCompatibility("com.example.UnusualWindowLevels"))
        XCTAssertNil(decision.compatibilityProfileIdentifier)
    }

    func testCompatibilityProfilesRequireBundleAndEveryDeclaredSurfaceSignal() {
        let profile = WindowCompatibilityProfile(
            identifier: "example-picker-v1",
            bundleIdentifiers: ["com.example.Editor"],
            accessibilityIdentifier: "com.example.editor.picker.v1",
            role: kAXWindowRole as String,
            subrole: kAXDialogSubrole as String,
            layer: .exact(3),
            modalObservation: .trueValue,
            closeButton: .present,
            positionSettable: .falseValue,
            disposition: .ignoredCompanionSurface,
            reason: .verifiedBundleNonNormalLayer
        )
        let matching = WindowAdmissionMetadata(
            bundleIdentifier: "COM.EXAMPLE.EDITOR",
            accessibilityIdentifier: "com.example.editor.picker.v1",
            role: kAXWindowRole as String,
            subrole: kAXDialogSubrole as String,
            windowLayer: 3,
            isMinimized: false,
            modalObservation: .trueValue,
            closeButton: .present,
            positionSettable: .falseValue
        )

        XCTAssertTrue(profile.matches(matching))
        XCTAssertEqual(profile.decision().compatibilityProfileIdentifier, "example-picker-v1")
        XCTAssertFalse(profile.matches(WindowAdmissionMetadata(
            bundleIdentifier: "com.example.Editor",
            accessibilityIdentifier: "com.example.editor.picker.v1",
            role: kAXWindowRole as String,
            subrole: kAXDialogSubrole as String,
            windowLayer: 3,
            isMinimized: false,
            modalObservation: .falseValue,
            closeButton: .present,
            positionSettable: .falseValue
        )))
        XCTAssertFalse(profile.matches(WindowAdmissionMetadata(
            bundleIdentifier: "com.example.Other",
            accessibilityIdentifier: "com.example.editor.picker.v1",
            role: kAXWindowRole as String,
            subrole: kAXDialogSubrole as String,
            windowLayer: 3,
            isMinimized: false,
            modalObservation: .trueValue,
            closeButton: .present,
            positionSettable: .falseValue
        )))
        XCTAssertFalse(profile.matches(WindowAdmissionMetadata(
            bundleIdentifier: "com.example.Editor",
            accessibilityIdentifier: "com.example.editor.other.v1",
            role: kAXWindowRole as String,
            subrole: kAXDialogSubrole as String,
            windowLayer: 3,
            isMinimized: false,
            modalObservation: .trueValue,
            closeButton: .present,
            positionSettable: .falseValue
        )))

        let coreCandidate = WindowAdmissionMetadata(
            bundleIdentifier: "com.example.Editor",
            accessibilityIdentifier: "com.example.editor.picker.v1",
            role: kAXWindowRole as String,
            subrole: kAXDialogSubrole as String,
            windowLayer: 3,
            isMinimized: false,
            closeButton: .present
        )
        XCTAssertTrue(AccessibilityWindow.shouldCollectSupportMetadataForCompatibility(
            coreCandidate,
            profiles: [profile]
        ))
        XCTAssertFalse(AccessibilityWindow.shouldCollectSupportMetadataForCompatibility(
            WindowAdmissionMetadata(
                bundleIdentifier: "com.example.Editor",
                accessibilityIdentifier: "com.example.editor.picker.v1",
                role: kAXWindowRole as String,
                subrole: kAXStandardWindowSubrole as String,
                windowLayer: 3,
                isMinimized: false,
                closeButton: .present
            ),
            profiles: [profile]
        ))
    }

    func testBuiltInCompatibilityRegistryCannotContainWholeAppPolicy() {
        let profiles = AccessibilityWindow.builtInCompatibilityProfiles

        XCTAssertEqual(Set(profiles.map(\.identifier)).count, profiles.count)
        for profile in profiles {
            XCTAssertFalse(profile.identifier.isEmpty)
            XCTAssertFalse(profile.bundleIdentifiers.isEmpty)
            XCTAssertTrue(profile.bundleIdentifiers.allSatisfy { $0 == $0.lowercased() })
            XCTAssertTrue(
                profile.accessibilityIdentifier != nil ||
                    profile.role != nil ||
                    profile.subrole != nil ||
                    profile.layer != nil ||
                    profile.modalObservation != nil ||
                    profile.focusedObservation != nil ||
                    profile.mainObservation != nil ||
                    profile.fullscreenButton != nil ||
                    profile.minimizeButton != nil ||
                    profile.closeButton != nil ||
                    profile.zoomButton != nil ||
                    profile.positionSettable != nil ||
                    profile.sizeSettable != nil,
                "A compatibility profile must identify a surface, not apply policy to a whole app"
            )
        }
    }

    func testOverlappingCompatibilityProfilesDoNotSelectBySourceOrder() throws {
        let profile = try XCTUnwrap(AccessibilityWindow.builtInCompatibilityProfiles.first {
            $0.identifier == "codex-transient-non-normal-layer-v1"
        })
        let metadata = WindowAdmissionMetadata(
            bundleIdentifier: "com.openai.codex",
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            windowLayer: 3,
            isMinimized: false
        )

        XCTAssertNil(AccessibilityWindow.uniqueMatchingCompatibilityProfile(
            for: metadata,
            in: [profile, profile]
        ))
    }

    func testHighConfidenceSheetAndSystemDialogMetadataFloatAutomatically() {
        let sheet = AccessibilityWindow.admissionDecision(for: WindowAdmissionMetadata(
            bundleIdentifier: "com.example.Editor",
            role: kAXSheetRole as String,
            subrole: nil,
            windowLayer: 0,
            isMinimized: false
        ))
        let systemDialog = AccessibilityWindow.admissionDecision(for: WindowAdmissionMetadata(
            bundleIdentifier: "com.example.Editor",
            role: kAXWindowRole as String,
            subrole: kAXSystemDialogSubrole as String,
            windowLayer: nil,
            isMinimized: false
        ))

        XCTAssertEqual(sheet, WindowAdmissionDecision(disposition: .managedDialog, reason: .sheetRole))
        XCTAssertEqual(systemDialog, WindowAdmissionDecision(
            disposition: .managedDialog,
            reason: .systemDialogSubrole
        ))
        XCTAssertTrue(sheet.automaticallyFloats)
        XCTAssertTrue(systemDialog.automaticallyFloats)
    }

    func testDialogHeuristicsRequireCorroboratedLayerAndWindowControls() {
        let dialog = AccessibilityWindow.admissionDecision(for: WindowAdmissionMetadata(
            bundleIdentifier: "com.example.Editor",
            role: kAXWindowRole as String,
            subrole: kAXDialogSubrole as String,
            windowLayer: 0,
            isMinimized: false,
            fullscreenButton: .absent
        ))
        let floatingSecondary = AccessibilityWindow.admissionDecision(for: WindowAdmissionMetadata(
            bundleIdentifier: "com.example.Editor",
            role: kAXWindowRole as String,
            subrole: kAXFloatingWindowSubrole as String,
            windowLayer: 0,
            isMinimized: false,
            fullscreenButton: .absent,
            closeButton: .present
        ))

        XCTAssertEqual(dialog, WindowAdmissionDecision(
            disposition: .managedDialog,
            reason: .dialogSubroleWithoutFullscreenButton
        ))
        XCTAssertEqual(floatingSecondary, WindowAdmissionDecision(
            disposition: .managedDialog,
            reason: .floatingWindowWithoutFullscreenButton
        ))
    }

    func testNonNormalLayerDialogDefersUntilItsLayerSettles() {
        let transient = AccessibilityWindow.admissionDecision(for: WindowAdmissionMetadata(
            bundleIdentifier: "com.mitchellh.ghostty",
            role: kAXWindowRole as String,
            subrole: kAXDialogSubrole as String,
            windowLayer: 8,
            isMinimized: false,
            fullscreenButton: .absent
        ))
        let settled = AccessibilityWindow.admissionDecision(for: WindowAdmissionMetadata(
            bundleIdentifier: "com.mitchellh.ghostty",
            role: kAXWindowRole as String,
            subrole: kAXDialogSubrole as String,
            windowLayer: 0,
            isMinimized: false,
            fullscreenButton: .absent
        ))

        XCTAssertEqual(transient, WindowAdmissionDecision(
            disposition: .temporarilyIneligible,
            reason: .transientDialogNonNormalLayer
        ))
        XCTAssertEqual(settled, WindowAdmissionDecision(
            disposition: .managedDialog,
            reason: .dialogSubroleWithoutFullscreenButton
        ))
    }

    func testNormalAndAmbiguousDialogLikeWindowsStayLayoutManaged() {
        let normalWithoutFullscreen = AccessibilityWindow.admissionDecision(for: WindowAdmissionMetadata(
            bundleIdentifier: "com.example.Editor",
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            windowLayer: 0,
            isMinimized: false,
            fullscreenButton: .absent,
            closeButton: .present,
            positionSettable: .unsupported,
            sizeSettable: .unsupported
        ))
        let dialogWithFullscreen = AccessibilityWindow.admissionDecision(for: WindowAdmissionMetadata(
            bundleIdentifier: "com.example.Editor",
            role: kAXWindowRole as String,
            subrole: kAXDialogSubrole as String,
            windowLayer: 0,
            isMinimized: false,
            fullscreenButton: .present
        ))
        let dialogWithUnknownLayer = AccessibilityWindow.admissionDecision(for: WindowAdmissionMetadata(
            bundleIdentifier: "com.openai.codex",
            role: kAXWindowRole as String,
            subrole: kAXDialogSubrole as String,
            windowLayer: nil,
            isMinimized: false,
            fullscreenButton: .absent
        ))
        let floatingWithoutReliableControls = AccessibilityWindow.admissionDecision(for: WindowAdmissionMetadata(
            bundleIdentifier: "com.example.Editor",
            role: kAXWindowRole as String,
            subrole: kAXFloatingWindowSubrole as String,
            windowLayer: 0,
            isMinimized: false,
            fullscreenButton: .unavailable,
            closeButton: .unavailable
        ))

        XCTAssertEqual(normalWithoutFullscreen.disposition, .managedNormal)
        XCTAssertEqual(normalWithoutFullscreen.reason, .normalWindow)
        for decision in [dialogWithFullscreen, dialogWithUnknownLayer, floatingWithoutReliableControls] {
            XCTAssertEqual(decision.disposition, .managedNormal)
            XCTAssertEqual(decision.reason, .ambiguousDialogMetadata)
            XCTAssertFalse(decision.automaticallyFloats)
        }
    }

    func testExplicitLayoutChoicesTakePrecedenceOverAutomaticDialogFloating() {
        let dialog = WindowAdmissionDecision(
            disposition: .managedDialog,
            reason: .dialogSubroleWithoutFullscreenButton
        )
        let excludedRule = ResolvedAppRule(
            assignedWorkspaceID: nil,
            keepsOnAllWorkspaces: false,
            excludesFromLayout: true
        )

        XCTAssertEqual(WorkspaceEngine.layoutDecision(
            layoutOverride: .managed,
            admissionDecision: dialog,
            rule: .none
        ), .explicitlyManaged)
        XCTAssertEqual(WorkspaceEngine.layoutDecision(
            layoutOverride: .floating,
            admissionDecision: WindowAdmissionDecision(disposition: .managedNormal, reason: .normalWindow),
            rule: .none
        ), .explicitlyFloating)
        XCTAssertEqual(WorkspaceEngine.layoutDecision(
            layoutOverride: .automatic,
            admissionDecision: dialog,
            rule: .none
        ), .automaticallyFloatingDialog)
        XCTAssertEqual(WorkspaceEngine.layoutDecision(
            layoutOverride: .managed,
            admissionDecision: dialog,
            rule: excludedRule
        ), .appRuleExcluded)
        XCTAssertEqual(WorkspaceEngine.floatingToggleDecision(
            currentOverride: .automatic,
            admissionDecision: dialog,
            rule: .none
        ), .setLayoutOverride(.managed))
        XCTAssertEqual(WorkspaceEngine.floatingToggleDecision(
            currentOverride: .managed,
            admissionDecision: dialog,
            rule: .none
        ), .setLayoutOverride(.floating))
    }

    func testFloatSecondaryWindowsRuleIsConservativeAndExplicitChoicesWin() {
        let ambiguousSecondary = WindowAdmissionDecision(
            disposition: .managedNormal,
            reason: .ambiguousDialogMetadata
        )
        let document = WindowAdmissionDecision(
            disposition: .managedNormal,
            reason: .normalWindow
        )
        let secondaryRule = ResolvedAppRule(
            assignedWorkspaceID: nil,
            keepsOnAllWorkspaces: false,
            excludesFromLayout: false,
            floatsSecondaryWindows: true
        )
        let excludedRule = ResolvedAppRule(
            assignedWorkspaceID: nil,
            keepsOnAllWorkspaces: false,
            excludesFromLayout: true,
            floatsSecondaryWindows: true
        )

        XCTAssertTrue(ambiguousSecondary.isSecondaryWindowCandidate)
        XCTAssertFalse(document.isSecondaryWindowCandidate)
        XCTAssertEqual(WorkspaceEngine.layoutDecision(
            layoutOverride: .automatic,
            admissionDecision: ambiguousSecondary,
            rule: secondaryRule
        ), .automaticallyFloatingSecondary)
        XCTAssertEqual(WorkspaceEngine.layoutDecision(
            layoutOverride: .automatic,
            admissionDecision: document,
            rule: secondaryRule
        ), .managedNormal)
        XCTAssertEqual(WorkspaceEngine.layoutDecision(
            layoutOverride: .managed,
            admissionDecision: ambiguousSecondary,
            rule: secondaryRule
        ), .explicitlyManaged)
        XCTAssertEqual(WorkspaceEngine.layoutDecision(
            layoutOverride: .floating,
            admissionDecision: document,
            rule: secondaryRule
        ), .explicitlyFloating)
        XCTAssertEqual(WorkspaceEngine.layoutDecision(
            layoutOverride: .managed,
            admissionDecision: ambiguousSecondary,
            rule: excludedRule
        ), .appRuleExcluded)
    }

    func testFloatSecondaryWindowsRulePersistsAndDoesNotInflateLayoutCount() throws {
        var rule = AppRule(
            bundleIdentifier: "com.example.Editor",
            displayName: "Editor"
        )
        rule.floatsSecondaryWindows = true
        let restored = try JSONDecoder().decode(
            AppRule.self,
            from: JSONEncoder().encode(rule)
        )
        let resolved = restored.resolved(validWorkspaceIDs: Set(WorkspaceDefinition.defaults.map(\.id)))
        let document = WindowAdmissionDecision(disposition: .managedNormal, reason: .normalWindow)
        let secondary = WindowAdmissionDecision(disposition: .managedNormal, reason: .ambiguousDialogMetadata)
        let participants = [document, secondary, document].filter {
            WorkspaceEngine.shouldIncludeInLayout(
                layoutOverride: .automatic,
                admissionDecision: $0,
                rule: resolved
            )
        }

        XCTAssertTrue(restored.floatsSecondaryWindows)
        XCTAssertTrue(resolved.floatsSecondaryWindows)
        XCTAssertEqual(participants.count, 2)
    }

    func testAutomaticDialogsStayManagedButDoNotInflateLayoutGeometry() {
        let normal = WindowAdmissionDecision(disposition: .managedNormal, reason: .normalWindow)
        let dialog = WindowAdmissionDecision(disposition: .managedDialog, reason: .sheetRole)
        let decisions = [normal, dialog, normal]
        let participants = decisions.filter {
            WorkspaceEngine.shouldIncludeInLayout(
                layoutOverride: .automatic,
                admissionDecision: $0,
                rule: .none
            )
        }

        XCTAssertTrue(decisions.allSatisfy(\.disposition.admitsNewWindow))
        XCTAssertEqual(participants.count, 2)
        XCTAssertEqual(WorkspaceEngine.layoutFrames(
            .tiled,
            count: participants.count,
            in: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        ).count, 2)
        XCTAssertEqual(WorkspaceEngine.layoutFrames(
            .accordion,
            count: participants.count,
            in: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        ).count, 2)
    }

    func testAutomaticDialogRetainsWorkspaceVisibilityFocusAndDisplaySemantics() {
        let workspace = WorkspaceDefinition.defaults[1].id
        let dialog = WindowAdmissionDecision(disposition: .managedDialog, reason: .sheetRole)
        XCTAssertTrue(dialog.disposition.admitsNewWindow)
        XCTAssertTrue(WorkspaceEngine.shouldWindowBeVisible(
            workspaceID: workspace,
            activeWorkspaceIDs: [workspace],
            rule: .none
        ))
        XCTAssertFalse(WorkspaceEngine.shouldWindowBeVisible(
            workspaceID: workspace,
            activeWorkspaceIDs: [],
            rule: .none
        ))
        XCTAssertEqual(WorkspaceEngine.focusFollowPlan(
            focusedWorkspaceID: workspace,
            mode: .independent,
            currentWorkspaceID: WorkspaceDefinition.defaults[0].id,
            activeWorkspaceIDByDisplay: ["external": WorkspaceDefinition.defaults[2].id],
            homeDisplayIdentifier: "external"
        )?.targetWorkspaceID, workspace)
        XCTAssertTrue(AccessibilityWindow.isEligibleFocusCycleCandidate(WindowFocusCapabilities(
            role: kAXSheetRole as String,
            subrole: nil,
            windowLayer: 0,
            isMinimized: false,
            isFocused: false,
            isMain: false,
            focusedAttributeSettable: true,
            mainAttributeSettable: true,
            applicationFocusedWindowAttributeSettable: true,
            raiseActionSupported: true
        )))

        let displays = testDisplays()
        let externalFrame = WindowFrame(
            position: CGPoint(x: 2200, y: 100),
            size: CGSize(width: 500, height: 400)
        )
        XCTAssertEqual(WorkspaceEngine.layoutDisplayIdentifier(
            preferredDisplayIdentifier: "external",
            savedFrame: externalFrame,
            mode: .unified,
            workspaceHomeDisplayIdentifier: nil,
            displays: displays
        ), "external")
        XCTAssertEqual(WorkspaceEngine.layoutDisplayIdentifier(
            preferredDisplayIdentifier: "main",
            savedFrame: externalFrame,
            mode: .independent,
            workspaceHomeDisplayIdentifier: "external",
            displays: displays
        ), "external")
    }

    func testReliableMetadataChangesReevaluateAutomaticLayoutParticipation() {
        let dialog = AccessibilityWindow.admissionDecision(for: WindowAdmissionMetadata(
            bundleIdentifier: "com.example.Editor",
            role: kAXWindowRole as String,
            subrole: kAXDialogSubrole as String,
            windowLayer: 0,
            isMinimized: false,
            fullscreenButton: .absent
        ))
        let normal = AccessibilityWindow.admissionDecision(for: WindowAdmissionMetadata(
            bundleIdentifier: "com.example.Editor",
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            windowLayer: 0,
            isMinimized: false,
            fullscreenButton: .present
        ))

        XCTAssertFalse(WorkspaceEngine.shouldIncludeInLayout(
            layoutOverride: .automatic,
            admissionDecision: dialog,
            rule: .none
        ))
        XCTAssertTrue(WorkspaceEngine.shouldIncludeInLayout(
            layoutOverride: .automatic,
            admissionDecision: normal,
            rule: .none
        ))
        XCTAssertTrue(WorkspaceEngine.shouldLogAdmissionDecisionChange(previous: dialog, current: normal))
        XCTAssertFalse(WorkspaceEngine.shouldLogAdmissionDecisionChange(previous: normal, current: normal))
    }

    func testAutomaticClassificationIsNotPersistedOrGuessedOntoNewWindowIDs() throws {
        let workspace = WorkspaceDefinition.defaults[0]
        let assignment = PersistedWindowAssignment(
            bundleIdentifier: "com.example.Editor",
            workspaceID: workspace.id,
            restoreFrame: WindowFrame(position: .zero, size: CGSize(width: 600, height: 400)),
            layoutOverride: .managed
        )
        let data = try JSONEncoder().encode(assignment)
        let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))
        let restored = try JSONDecoder().decode(PersistedWindowAssignment.self, from: data)
        let newlyDiscovered = PersistedWindowAssignment(
            bundleIdentifier: "com.example.Editor",
            workspaceID: workspace.id,
            restoreFrame: WindowFrame(position: .zero, size: CGSize(width: 600, height: 400))
        )

        XCTAssertEqual(restored.layoutOverride, .managed)
        XCTAssertEqual(newlyDiscovered.layoutOverride, .automatic)
        XCTAssertFalse(encoded.contains("automaticallyFloatingDialog"))
        XCTAssertFalse(encoded.contains("managedDialog"))
    }

    func testAdmissionDiagnosticsAreDeduplicatedAndPrivacySafe() {
        let metadata = WindowAdmissionMetadata(
            bundleIdentifier: "com.example.Editor",
            role: kAXWindowRole as String,
            subrole: kAXDialogSubrole as String,
            windowLayer: 0,
            isMinimized: false,
            modalObservation: .trueValue,
            focusedObservation: .falseValue,
            mainObservation: .trueValue,
            fullscreenButton: .absent,
            minimizeButton: .absent,
            closeButton: .present,
            zoomButton: .absent,
            positionSettable: .trueValue,
            sizeSettable: .falseValue
        )
        let decision = AccessibilityWindow.admissionDecision(for: metadata)
        let fields = WorkspaceEngine.admissionDiagnosticFields(
            decision: decision,
            metadata: metadata,
            key: WindowKey(processIdentifier: 101, windowIdentifier: 202),
            layerSource: "test"
        )

        XCTAssertTrue(WorkspaceEngine.shouldLogAdmissionDecisionChange(previous: nil, current: decision))
        XCTAssertFalse(WorkspaceEngine.shouldLogAdmissionDecisionChange(previous: decision, current: decision))
        XCTAssertEqual(fields["automatic-floating"], "true")
        XCTAssertEqual(fields["ax-modal"], "true")
        XCTAssertEqual(fields["ax-focused"], "false")
        XCTAssertEqual(fields["ax-main"], "true")
        XCTAssertEqual(fields["fullscreen-button"], "absent")
        XCTAssertEqual(fields["minimize-button"], "absent")
        XCTAssertEqual(fields["zoom-button"], "absent")
        XCTAssertEqual(fields["position-settable"], "true")
        XCTAssertEqual(fields["size-settable"], "false")
        XCTAssertEqual(fields["compatibility-profile"], "none")
        XCTAssertNil(fields["title"])
        XCTAssertNil(fields["document"])
        XCTAssertNil(fields["url"])
        XCTAssertNil(fields["path"])
        XCTAssertFalse(fields.values.contains { $0.contains("/Users/") })
    }

    func testCompanionSurfaceDiagnosticsReportContractWithoutRawMarker() {
        let marker = AccessibilityWindow.desktopRangerSurfaceAccessibilityIdentifier
        let metadata = WindowAdmissionMetadata(
            bundleIdentifier: "dev.appranger.DesktopRanger.SurfaceLab",
            accessibilityIdentifier: marker,
            role: kAXWindowRole as String,
            subrole: kAXFloatingWindowSubrole as String,
            windowLayer: 3,
            isMinimized: false
        )
        let decision = AccessibilityWindow.admissionDecision(for: metadata)
        let fields = WorkspaceEngine.admissionDiagnosticFields(
            decision: decision,
            metadata: metadata,
            key: WindowKey(processIdentifier: 303, windowIdentifier: 404),
            layerSource: "test"
        )

        XCTAssertEqual(fields["reason"], WindowAdmissionReason.rangerCompanionSurface.rawValue)
        XCTAssertEqual(fields["compatibility-profile"], "desktopranger-owned-surface-v1")
        XCTAssertFalse(fields.values.contains(marker))
        XCTAssertNil(fields["ax-identifier"])
        XCTAssertNil(fields["accessibility-identifier"])
    }

    func testLateCompanionIdentifierEvictsTrackedWindowWithoutARecoveryOrFrameOperation() {
        let workspace = WorkspaceDefinition(name: "Mail", key: "m")
        let ignored = WindowKey(processIdentifier: 42_394, windowIdentifier: 17_298)
        let legitimate = WindowKey(processIdentifier: 1_697, windowIdentifier: 115)
        let initiallyManagedDecision = AccessibilityWindow.admissionDecision(for: WindowAdmissionMetadata(
            bundleIdentifier: "dev.appranger.DesktopRanger.SurfaceLab",
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            windowLayer: 0,
            isMinimized: false
        ))
        let companionDecision = AccessibilityWindow.admissionDecision(for: WindowAdmissionMetadata(
            bundleIdentifier: "dev.appranger.DesktopRanger.SurfaceLab",
            accessibilityIdentifier: AccessibilityWindow.desktopRangerSurfaceAccessibilityIdentifier,
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            windowLayer: 0,
            isMinimized: false
        ))
        XCTAssertEqual(initiallyManagedDecision.disposition, .managedNormal)
        XCTAssertEqual(companionDecision, WindowAdmissionDecision(
            disposition: .ignoredCompanionSurface,
            reason: .rangerCompanionSurface,
            compatibilityProfileIdentifier: "desktopranger-owned-surface-v1"
        ))
        var tracked = [ignored: "DesktopRanger surface", legitimate: "Mail"]
        var pending = [
            "17298": PersistedWindowAssignment(
                bundleIdentifier: "dev.appranger.DesktopRanger.SurfaceLab",
                workspaceID: workspace.id,
                restoreFrame: WindowFrame(
                    position: CGPoint(x: -3_094, y: 0),
                    size: CGSize(width: 384, height: 131)
                ),
                isFloating: true
            ),
        ]
        var lastFocused = [workspace.id: ignored]
        let partition = TiledLayoutPartitionKey(
            workspaceID: workspace.id,
            displayIdentifier: "main"
        )
        var tiledTrees = [
            partition: TiledNode.split(
                axis: .horizontal,
                ratio: 0.5,
                first: .window(ignored),
                second: .window(legitimate)
            ),
        ]
        var fullscreenSessions = [ignored: "DesktopRanger fullscreen", legitimate: "Mail fullscreen"]
        var fullscreenFalseCounts = [ignored: 1, legitimate: 2]

        let result = WorkspaceEngine.removeIgnoredWindowState(
            ignored,
            bundleIdentifier: "dev.appranger.DesktopRanger.SurfaceLab",
            trackedWindows: &tracked,
            pendingRestoredWindows: &pending,
            lastFocusedWindow: &lastFocused,
            tiledTrees: &tiledTrees,
            fullscreenSessions: &fullscreenSessions,
            fullscreenAuthoritativeFalseCounts: &fullscreenFalseCounts
        )

        XCTAssertEqual(result, IgnoredWindowRemovalResult(
            removedTrackedWindow: true,
            removedPendingAssignment: true,
            clearedLastFocusedWorkspaceIDs: [workspace.id],
            removedTiledLayoutState: true,
            removedFullscreenState: true
        ))
        XCTAssertEqual(tracked, [legitimate: "Mail"])
        XCTAssertTrue(pending.isEmpty)
        XCTAssertTrue(lastFocused.isEmpty)
        XCTAssertEqual(tiledTrees[partition]?.windowKeys, [legitimate])
        XCTAssertEqual(fullscreenSessions, [legitimate: "Mail fullscreen"])
        XCTAssertEqual(fullscreenFalseCounts, [legitimate: 2])
        XCTAssertFalse(companionDecision.disposition.admitsNewWindow)
        XCTAssertTrue(companionDecision.disposition.evictsTrackedWindow)
        // The cleanup API deliberately has no AX element or frame writer: ignored windows can
        // only be removed from state, never restored, parked, resized, or moved.
        XCTAssertEqual(WorkspaceEngine.layoutFrames(
            .accordion,
            count: tracked.count,
            in: CGRect(x: -3360, y: 0, width: 3360, height: 1418)
        ).count, 1)
    }

    func testSixCodexPanelsDoNotInflateAccordionOrTiledParticipantCounts() {
        let normal = WindowAdmissionDecision(disposition: .managedNormal, reason: .normalWindow)
        let ignored = WindowAdmissionDecision(
            disposition: .ignoredTransientPopup,
            reason: .verifiedBundleNonNormalLayer
        )
        let traceDecisions = Array(repeating: normal, count: 3) + Array(repeating: ignored, count: 6)
        let managedCount = traceDecisions.filter { $0.disposition.admitsNewWindow }.count

        XCTAssertEqual(managedCount, 3)
        XCTAssertEqual(WorkspaceEngine.layoutFrames(
            .accordion,
            count: managedCount,
            in: CGRect(x: -3360, y: 0, width: 3360, height: 1418)
        ).count, 3)
        XCTAssertEqual(WorkspaceEngine.layoutFrames(
            .tiled,
            count: managedCount,
            in: CGRect(x: -3360, y: 0, width: 3360, height: 1418)
        ).count, 3)
    }

    func testIgnoredFocusIsConsumedBeforeWorkspaceFollowOrDisplayInteraction() {
        let pet = WindowKey(processIdentifier: 42_394, windowIdentifier: 17_298)

        XCTAssertTrue(WorkspaceEngine.shouldIgnoreFocusObservation(
            focusedWindow: pet,
            ignoredWindowKeys: [pet]
        ))
        XCTAssertFalse(WorkspaceEngine.shouldIgnoreFocusObservation(
            focusedWindow: WindowKey(processIdentifier: 1_697, windowIdentifier: 115),
            ignoredWindowKeys: [pet]
        ))
    }

    func testAppOwnedAndIgnoredWindowsPreserveExternalInteractionFocusAnchor() {
        let ownWindow = WindowKey(processIdentifier: 69767, windowIdentifier: 20689)
        let ignoredPopup = WindowKey(processIdentifier: 42_394, windowIdentifier: 17_298)
        let externalWindow = WindowKey(processIdentifier: 1_697, windowIdentifier: 115)

        XCTAssertTrue(WorkspaceEngine.shouldPreserveInteractionFocusAnchor(
            focusedWindow: ownWindow,
            ownProcessIdentifier: ownWindow.processIdentifier,
            ignoredWindowKeys: [ignoredPopup]
        ))
        XCTAssertTrue(WorkspaceEngine.shouldPreserveInteractionFocusAnchor(
            focusedWindow: ignoredPopup,
            ownProcessIdentifier: ownWindow.processIdentifier,
            ignoredWindowKeys: [ignoredPopup]
        ))
        XCTAssertFalse(WorkspaceEngine.shouldPreserveInteractionFocusAnchor(
            focusedWindow: externalWindow,
            ownProcessIdentifier: ownWindow.processIdentifier,
            ignoredWindowKeys: [ignoredPopup]
        ))
        XCTAssertFalse(WorkspaceEngine.shouldPreserveInteractionFocusAnchor(
            focusedWindow: nil,
            ownProcessIdentifier: ownWindow.processIdentifier,
            ignoredWindowKeys: [ignoredPopup]
        ))
        XCTAssertTrue(WorkspaceEngine.shouldPreserveInteractionFocusAnchor(
            focusedWindow: nil,
            ownProcessIdentifier: ownWindow.processIdentifier,
            ignoredWindowKeys: [ignoredPopup],
            commandPalettePresented: true
        ))
    }

    func testUnchangedAdmissionDecisionDoesNotRepeatDiagnosticsOrReadmitPopup() {
        let ignored = WindowAdmissionDecision(
            disposition: .ignoredTransientPopup,
            reason: .verifiedBundleNonNormalLayer
        )

        XCTAssertTrue(WorkspaceEngine.shouldLogAdmissionDecisionChange(previous: nil, current: ignored))
        XCTAssertFalse(WorkspaceEngine.shouldLogAdmissionDecisionChange(previous: ignored, current: ignored))
        XCTAssertFalse(ignored.disposition.admitsNewWindow)
    }

    func testAdmissionSupportSnapshotIsPrivacySafeAndIncludesDispositionReasons() {
        let managedKey = WindowKey(processIdentifier: 12, windowIdentifier: 34)
        let ignoredKey = WindowKey(processIdentifier: 56, windowIdentifier: 78)
        let records = WorkspaceEngine.admissionSupportRecords(
            decisions: [
                managedKey: WindowAdmissionDecision(
                    disposition: .managedDialog,
                    reason: .systemDialogSubrole
                ),
                ignoredKey: WindowAdmissionDecision(
                    disposition: .ignoredTransientPopup,
                    reason: .verifiedBundleNonNormalLayer,
                    compatibilityProfileIdentifier: "codex-transient-non-normal-layer-v1"
                ),
            ],
            metadata: [
                managedKey: WindowAdmissionMetadata(
                    bundleIdentifier: "com.example.Editor",
                    role: "AXWindow",
                    subrole: "AXSystemDialog",
                    windowLayer: 0,
                    isMinimized: false,
                    modalObservation: .trueValue,
                    focusedObservation: .trueValue,
                    mainObservation: .trueValue,
                    fullscreenButton: .absent,
                    minimizeButton: .absent,
                    closeButton: .present,
                    zoomButton: .absent,
                    positionSettable: .trueValue,
                    sizeSettable: .falseValue
                ),
                ignoredKey: WindowAdmissionMetadata(
                    bundleIdentifier: "com.openai.codex",
                    role: "AXWindow",
                    subrole: "AXDialog",
                    windowLayer: 3,
                    isMinimized: false
                ),
            ]
        )

        XCTAssertEqual(records.map(\.bundleIdentifier), ["com.example.Editor", "com.openai.codex"])
        XCTAssertEqual(records[0].disposition, "managed-dialog")
        XCTAssertEqual(records[1].reason, "verified-bundle-non-normal-layer")
        XCTAssertEqual(records[1].windowLayer, "3")
        XCTAssertEqual(
            records[1].compatibilityProfileIdentifier,
            "codex-transient-non-normal-layer-v1"
        )
        XCTAssertEqual(records[0].modalObservation, "true")
        XCTAssertEqual(records[0].positionSettable, "true")
        XCTAssertEqual(records[0].sizeSettable, "false")
        XCTAssertFalse(String(describing: records).lowercased().contains("title"))

        let snapshot = try? XCTUnwrap(
            WindowAdmissionSupportSnapshot(records: records).encodedString()
        )
        XCTAssertTrue(snapshot?.contains("\"schemaVersion\" : 2") == true)
        XCTAssertTrue(snapshot?.contains("\"modalObservation\" : \"true\"") == true)
        XCTAssertTrue(snapshot?.contains("codex-transient-non-normal-layer-v1") == true)
        XCTAssertFalse(snapshot?.lowercased().contains("title") == true)
        XCTAssertFalse(snapshot?.contains("/Users/") == true)
    }

    func testAssignedWorkspaceUsesItsIndependentDisplayHome() {
        let assignedWorkspaceID = WorkspaceDefinition.defaults[1].id
        let rule = AppRule(
            bundleIdentifier: "com.example.Editor",
            displayName: "Editor",
            actions: [.assignWorkspace(assignedWorkspaceID)]
        ).resolved(validWorkspaceIDs: [assignedWorkspaceID])
        let routed = WorkspaceEngine.routedWorkspaceID(
            fallbackWorkspaceID: WorkspaceDefinition.defaults[0].id,
            rule: rule
        )

        XCTAssertEqual(routed, assignedWorkspaceID)
        XCTAssertEqual(WorkspaceEngine.layoutDisplayIdentifier(
            preferredDisplayIdentifier: "main",
            savedFrame: WindowFrame(position: .zero, size: CGSize(width: 800, height: 600)),
            mode: .independent,
            workspaceHomeDisplayIdentifier: "external",
            displays: testDisplays()
        ), "external")
    }

    func testNoneLayoutProducesNoManagedFrames() {
        XCTAssertTrue(WorkspaceEngine.layoutFrames(
            .none,
            count: 3,
            in: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        ).isEmpty)
    }

    func testSingleTiledWindowUsesInsetDisplayBounds() {
        let frames = WorkspaceEngine.layoutFrames(
            .tiled,
            count: 1,
            in: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        )

        XCTAssertEqual(frames, [WindowFrame(
            position: CGPoint(x: 8, y: 8),
            size: CGSize(width: 1904, height: 1064)
        )])
    }

    func testSingleAccordionWindowUsesFullPrimaryBounds() {
        let display = CGRect(x: 0, y: 0, width: 1440, height: 900)

        XCTAssertEqual(
            WorkspaceEngine.layoutFrames(.accordion, count: 1, in: display),
            [WindowFrame(
                position: .zero,
                size: CGSize(width: 1440, height: 900)
            )]
        )
    }

    func testTiledWindowsAreNonOverlappingAndInsideDisplay() {
        let display = CGRect(x: -2560, y: 0, width: 2560, height: 1440)
        let frames = WorkspaceEngine.layoutFrames(.tiled, count: 7, in: display)

        XCTAssertEqual(frames.count, 7)
        for frame in frames {
            XCTAssertTrue(display.contains(CGRect(origin: frame.position, size: frame.size)))
        }
        for leftIndex in frames.indices {
            for rightIndex in frames.indices where rightIndex > leftIndex {
                let intersection = CGRect(
                    origin: frames[leftIndex].position,
                    size: frames[leftIndex].size
                ).intersection(CGRect(
                    origin: frames[rightIndex].position,
                    size: frames[rightIndex].size
                ))
                XCTAssertTrue(intersection.isNull || intersection.width == 0 || intersection.height == 0)
            }
        }
    }

    func testRefinedTiledUsesFlatAutomaticHorizontalGeometryOnWideDisplay() {
        let bounds = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let frames = WorkspaceEngine.layoutFrames(
            .tiled,
            count: 3,
            in: bounds,
            layoutConfiguration: .aeroSpaceUserDefaults
        )

        XCTAssertEqual(frames, [
            WindowFrame(position: CGPoint(x: 0, y: 0), size: CGSize(width: 397, height: 800)),
            WindowFrame(position: CGPoint(x: 402, y: 0), size: CGSize(width: 396, height: 800)),
            WindowFrame(position: CGPoint(x: 803, y: 0), size: CGSize(width: 397, height: 800)),
        ])
    }

    func testRefinedTiledUsesFlatAutomaticVerticalGeometryOnPortraitDisplay() {
        let bounds = CGRect(x: -900, y: -200, width: 900, height: 1400)
        let frames = WorkspaceEngine.layoutFrames(
            .tiled,
            count: 2,
            in: bounds,
            layoutConfiguration: .aeroSpaceUserDefaults
        )

        XCTAssertEqual(frames, [
            WindowFrame(position: CGPoint(x: -900, y: -200), size: CGSize(width: 900, height: 698)),
            WindowFrame(position: CGPoint(x: -900, y: 503), size: CGSize(width: 900, height: 697)),
        ])
    }

    func testExplicitOrientationAndOuterGapsApplyPerWorkspace() {
        let configuration = WorkspaceLayoutConfiguration(
            orientation: .vertical,
            accordionPadding: 80,
            gaps: WorkspaceLayoutGaps(
                innerHorizontal: 9,
                innerVertical: 10,
                outerTop: 20,
                outerRight: 30,
                outerBottom: 40,
                outerLeft: 50
            )
        )
        let bounds = CGRect(x: 100, y: 200, width: 1000, height: 800)
        let frames = WorkspaceEngine.layoutFrames(
            .tiled,
            count: 2,
            in: bounds,
            layoutConfiguration: configuration
        )

        XCTAssertEqual(frames, [
            WindowFrame(position: CGPoint(x: 150, y: 220), size: CGSize(width: 920, height: 365)),
            WindowFrame(position: CGPoint(x: 150, y: 595), size: CGSize(width: 920, height: 365)),
        ])
    }

    func testAccordionUsesPerWorkspacePaddingOrientationAndOuterGaps() {
        let configuration = WorkspaceLayoutConfiguration(
            orientation: .vertical,
            accordionPadding: 100,
            gaps: WorkspaceLayoutGaps(
                innerHorizontal: 99,
                innerVertical: 99,
                outerTop: 20,
                outerRight: 30,
                outerBottom: 40,
                outerLeft: 50
            )
        )
        let frames = WorkspaceEngine.layoutFrames(
            .accordion,
            count: 2,
            in: CGRect(x: 100, y: 200, width: 1000, height: 800),
            accordionFocusedIndex: 0,
            layoutConfiguration: configuration
        )

        XCTAssertEqual(frames, [
            WindowFrame(position: CGPoint(x: 150, y: 220), size: CGSize(width: 920, height: 640)),
            WindowFrame(position: CGPoint(x: 150, y: 320), size: CGSize(width: 920, height: 640)),
        ])
    }

    func testResetWorkspaceTargetsInteractionDisplayOnlyInIndependentMode() {
        let displays = testDisplays()
        let frame = WindowFrame(position: CGPoint(x: 100, y: 100), size: CGSize(width: 800, height: 600))

        XCTAssertEqual(WorkspaceEngine.resetTargetDisplayIdentifier(
            mode: .independent,
            interactionDisplayIdentifier: "external",
            preferredDisplayIdentifier: "main",
            savedFrame: frame,
            displays: displays
        ), "external")
        XCTAssertEqual(WorkspaceEngine.resetTargetDisplayIdentifier(
            mode: .unified,
            interactionDisplayIdentifier: "external",
            preferredDisplayIdentifier: "main",
            savedFrame: frame,
            displays: displays
        ), "main")
    }

    func testHorizontalAccordionMatchesAeroSpaceOverlappingPaddingGeometry() {
        let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let frames = WorkspaceEngine.layoutFrames(
            .accordion,
            count: 5,
            in: display,
            accordionFocusedIndex: 2
        )

        XCTAssertEqual(frames, [
            WindowFrame(position: CGPoint(x: 0, y: 0), size: CGSize(width: 1670, height: 1080)),
            WindowFrame(position: CGPoint(x: 0, y: 0), size: CGSize(width: 1420, height: 1080)),
            WindowFrame(position: CGPoint(x: 250, y: 0), size: CGSize(width: 1420, height: 1080)),
            WindowFrame(position: CGPoint(x: 500, y: 0), size: CGSize(width: 1420, height: 1080)),
            WindowFrame(position: CGPoint(x: 250, y: 0), size: CGSize(width: 1670, height: 1080)),
        ])
        for frame in frames {
            XCTAssertTrue(display.contains(CGRect(origin: frame.position, size: frame.size)))
        }
        XCTAssertGreaterThan(
            CGRect(origin: frames[1].position, size: frames[1].size)
                .intersection(CGRect(origin: frames[2].position, size: frames[2].size)).width,
            0
        )
    }

    func testTwoWindowAccordionLeavesOneVisibleEdgeForEachWindow() {
        let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let focusedFirst = WorkspaceEngine.layoutFrames(
            .accordion,
            count: 2,
            in: display,
            accordionFocusedIndex: 0
        )
        let focusedSecond = WorkspaceEngine.layoutFrames(
            .accordion,
            count: 2,
            in: display,
            accordionFocusedIndex: 1
        )

        XCTAssertEqual(focusedFirst, [
            WindowFrame(position: .zero, size: CGSize(width: 1670, height: 1080)),
            WindowFrame(position: CGPoint(x: 250, y: 0), size: CGSize(width: 1670, height: 1080)),
        ])
        XCTAssertEqual(focusedSecond, focusedFirst)
    }

    func testPortraitAccordionAutomaticallyUsesVerticalPadding() {
        let frames = WorkspaceEngine.layoutFrames(
            .accordion,
            count: 5,
            in: CGRect(x: 0, y: 0, width: 900, height: 1440),
            accordionFocusedIndex: 2
        )

        XCTAssertEqual(frames, [
            WindowFrame(position: .zero, size: CGSize(width: 900, height: 1190)),
            WindowFrame(position: .zero, size: CGSize(width: 900, height: 940)),
            WindowFrame(position: CGPoint(x: 0, y: 250), size: CGSize(width: 900, height: 940)),
            WindowFrame(position: CGPoint(x: 0, y: 500), size: CGSize(width: 900, height: 940)),
            WindowFrame(position: CGPoint(x: 0, y: 250), size: CGSize(width: 900, height: 1190)),
        ])
    }

    func testAccordionFocusChangesNeighbourIndicatorsWithoutPromotingWindowOrder() {
        let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let focusSecond = WorkspaceEngine.layoutFrames(
            .accordion,
            count: 5,
            in: display,
            accordionFocusedIndex: 1
        )
        let focusFourth = WorkspaceEngine.layoutFrames(
            .accordion,
            count: 5,
            in: display,
            accordionFocusedIndex: 3
        )

        XCTAssertEqual(focusSecond[2].position.x, 500)
        XCTAssertEqual(focusFourth[2].position.x, 0)
        XCTAssertEqual(focusSecond[0], focusFourth[0])
        XCTAssertEqual(focusSecond[4], focusFourth[4])
    }

    func testAccordionUsesConfiguredPaddingAndIgnoresTiledGap() {
        let frames = WorkspaceEngine.layoutFrames(
            .accordion,
            count: 3,
            in: CGRect(x: 0, y: 0, width: 1200, height: 800),
            gap: 99,
            accordionFocusedIndex: 1,
            accordionPadding: 250
        )

        XCTAssertEqual(frames[0], WindowFrame(
            position: .zero,
            size: CGSize(width: 950, height: 800)
        ))
        XCTAssertEqual(frames[1], WindowFrame(
            position: CGPoint(x: 250, y: 0),
            size: CGSize(width: 700, height: 800)
        ))
        XCTAssertEqual(frames[2], WindowFrame(
            position: CGPoint(x: 250, y: 0),
            size: CGSize(width: 950, height: 800)
        ))
    }

    func testAccordionUsableBoundsConvertFromCocoaToAccessibilityCoordinates() {
        XCTAssertEqual(
            WorkspaceEngine.accessibilityBounds(
                forCocoaBounds: CGRect(x: -900, y: 25, width: 900, height: 1375),
                mainScreenTop: 1080
            ),
            CGRect(x: -900, y: -320, width: 900, height: 1375)
        )
    }

    func testAutoHiddenBottomDockRestoresOnlyBottomDisplayEdge() {
        let screen = CGRect(x: 0, y: 0, width: 3360, height: 1418)
        let visible = CGRect(x: 0, y: 59, width: 3360, height: 1329)

        XCTAssertEqual(
            WorkspaceEngine.usableCocoaBounds(
                screenFrame: screen,
                visibleFrame: visible,
                dockPreferences: DockLayoutPreferences(automaticallyHides: true, edge: .bottom)
            ),
            CGRect(x: 0, y: 0, width: 3360, height: 1388)
        )
    }

    func testVisibleBottomDockKeepsAppKitSafeBounds() {
        let visible = CGRect(x: 0, y: 59, width: 3360, height: 1329)

        XCTAssertEqual(
            WorkspaceEngine.usableCocoaBounds(
                screenFrame: CGRect(x: 0, y: 0, width: 3360, height: 1418),
                visibleFrame: visible,
                dockPreferences: DockLayoutPreferences(automaticallyHides: false, edge: .bottom)
            ),
            visible
        )
    }

    func testAutoHiddenSideDockRestoresOnlyConfiguredEdge() {
        let screen = CGRect(x: -1200, y: 0, width: 1200, height: 900)
        let leftVisible = CGRect(x: -1140, y: 0, width: 1140, height: 875)
        let rightVisible = CGRect(x: -1200, y: 0, width: 1140, height: 875)

        XCTAssertEqual(
            WorkspaceEngine.usableCocoaBounds(
                screenFrame: screen,
                visibleFrame: leftVisible,
                dockPreferences: DockLayoutPreferences(automaticallyHides: true, edge: .left)
            ),
            CGRect(x: -1200, y: 0, width: 1200, height: 875)
        )
        XCTAssertEqual(
            WorkspaceEngine.usableCocoaBounds(
                screenFrame: screen,
                visibleFrame: rightVisible,
                dockPreferences: DockLayoutPreferences(automaticallyHides: true, edge: .right)
            ),
            CGRect(x: -1200, y: 0, width: 1200, height: 875)
        )
    }

    func testUnknownAutoHiddenDockEdgeKeepsAppKitSafeBounds() {
        let visible = CGRect(x: 0, y: 59, width: 3360, height: 1329)

        XCTAssertEqual(
            WorkspaceEngine.usableCocoaBounds(
                screenFrame: CGRect(x: 0, y: 0, width: 3360, height: 1418),
                visibleFrame: visible,
                dockPreferences: DockLayoutPreferences(automaticallyHides: true, edge: nil)
            ),
            visible
        )
    }

    func testAccordionExcludesFloatingAndAppExcludedWindowsFromItsCount() {
        let excludedRule = ResolvedAppRule(
            assignedWorkspaceID: nil,
            keepsOnAllWorkspaces: false,
            excludesFromLayout: true
        )
        let participants = [
            WorkspaceEngine.shouldIncludeInLayout(isFloating: false, rule: .none),
            WorkspaceEngine.shouldIncludeInLayout(isFloating: true, rule: .none),
            WorkspaceEngine.shouldIncludeInLayout(isFloating: false, rule: excludedRule),
            WorkspaceEngine.shouldIncludeInLayout(isFloating: false, rule: .none),
        ].filter { $0 }

        let frames = WorkspaceEngine.layoutFrames(
            .accordion,
            count: participants.count,
            in: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        )

        XCTAssertEqual(participants.count, 2)
        XCTAssertEqual(frames.count, 2)
        XCTAssertGreaterThan(
            CGRect(origin: frames[0].position, size: frames[0].size)
                .intersection(CGRect(origin: frames[1].position, size: frames[1].size)).width,
            0
        )
    }

    func testUnifiedLayoutKeepsEachWindowOnPreferredDisplay() {
        let displays = testDisplays()
        let mainFrame = WindowFrame(position: CGPoint(x: 100, y: 100), size: CGSize(width: 800, height: 600))
        let externalFrame = WindowFrame(position: CGPoint(x: 2200, y: 100), size: CGSize(width: 800, height: 600))

        XCTAssertEqual(WorkspaceEngine.layoutDisplayIdentifier(
            preferredDisplayIdentifier: "main",
            savedFrame: mainFrame,
            mode: .unified,
            workspaceHomeDisplayIdentifier: nil,
            displays: displays
        ), "main")
        XCTAssertEqual(WorkspaceEngine.layoutDisplayIdentifier(
            preferredDisplayIdentifier: "external",
            savedFrame: externalFrame,
            mode: .unified,
            workspaceHomeDisplayIdentifier: nil,
            displays: displays
        ), "external")
    }

    func testAccordionUsesUnifiedAffinityAndIndependentWorkspaceHomeBounds() {
        let displays = testDisplays()
        let savedFrame = WindowFrame(
            position: CGPoint(x: 2200, y: 100),
            size: CGSize(width: 800, height: 600)
        )
        let unifiedDisplayID = WorkspaceEngine.layoutDisplayIdentifier(
            preferredDisplayIdentifier: "external",
            savedFrame: savedFrame,
            mode: .unified,
            workspaceHomeDisplayIdentifier: nil,
            displays: displays
        )
        let independentDisplayID = WorkspaceEngine.layoutDisplayIdentifier(
            preferredDisplayIdentifier: "main",
            savedFrame: savedFrame,
            mode: .independent,
            workspaceHomeDisplayIdentifier: "external",
            displays: displays
        )

        XCTAssertEqual(unifiedDisplayID, "external")
        XCTAssertEqual(independentDisplayID, "external")
        let externalBounds = try! XCTUnwrap(displays.first { $0.identifier == "external" }?.bounds)
        for frame in WorkspaceEngine.layoutFrames(
            .accordion,
            count: 3,
            in: externalBounds,
            accordionFocusedIndex: 1
        ) {
            XCTAssertTrue(externalBounds.contains(CGRect(origin: frame.position, size: frame.size)))
        }
    }

    func testIndependentLayoutUsesWorkspaceHomeAndFallsBackWhenDisconnected() {
        let displays = testDisplays()
        let frame = WindowFrame(position: CGPoint(x: 100, y: 100), size: CGSize(width: 800, height: 600))

        XCTAssertEqual(WorkspaceEngine.layoutDisplayIdentifier(
            preferredDisplayIdentifier: "main",
            savedFrame: frame,
            mode: .independent,
            workspaceHomeDisplayIdentifier: "external",
            displays: displays
        ), "external")
        XCTAssertEqual(WorkspaceEngine.layoutDisplayIdentifier(
            preferredDisplayIdentifier: "external",
            savedFrame: frame,
            mode: .independent,
            workspaceHomeDisplayIdentifier: "missing-display",
            displays: displays
        ), "main")
    }

    func testPositionComparisonSkipsSubpixelDifferences() {
        XCTAssertTrue(AccessibilityWindow.positionsMatch(
            CGPoint(x: 100.25, y: 200.75),
            CGPoint(x: 100, y: 200)
        ))
    }

    func testPositionComparisonKeepsRealMoves() {
        XCTAssertFalse(AccessibilityWindow.positionsMatch(
            CGPoint(x: 100, y: 200),
            CGPoint(x: 101, y: 200)
        ))
    }

    func testFrameWriteStopsBeforePositionWhenInitialSizeIsRejected() {
        var operations: [String] = []

        let succeeded = AccessibilityWindow.applyFrameWriteSequence(
            writeSize: {
                operations.append("size")
                return false
            },
            writePosition: {
                operations.append("position")
                return true
            }
        )

        XCTAssertFalse(succeeded)
        XCTAssertEqual(operations, ["size"])
    }

    func testFrameWriteRetainsSizePositionSizeSequenceWhenSupported() {
        var operations: [String] = []

        let succeeded = AccessibilityWindow.applyFrameWriteSequence(
            writeSize: {
                operations.append("size")
                return true
            },
            writePosition: {
                operations.append("position")
                return true
            }
        )

        XCTAssertTrue(succeeded)
        XCTAssertEqual(operations, ["size", "position", "size"])
    }

    func testFrameWriteResultPromotesOnlyAnInitialSizeRejection() {
        XCTAssertEqual(
            AccessibilityWindow.applyFrameWriteSequenceResult(
                writeSize: { false },
                writePosition: { true }
            ),
            .initialSizeRejected
        )

        var positionFailureSizeWrites = 0
        XCTAssertEqual(
            AccessibilityWindow.applyFrameWriteSequenceResult(
                writeSize: {
                    positionFailureSizeWrites += 1
                    return true
                },
                writePosition: { false }
            ),
            .positionRejected
        )
        XCTAssertEqual(positionFailureSizeWrites, 1)

        var finalSizeWrites = 0
        XCTAssertEqual(
            AccessibilityWindow.applyFrameWriteSequenceResult(
                writeSize: {
                    finalSizeWrites += 1
                    return finalSizeWrites == 1
                },
                writePosition: { true }
            ),
            .finalSizeRejected
        )
        XCTAssertEqual(finalSizeWrites, 2)
    }

    func testTrustedInteractiveLaunchChecksTrustOnceWithoutPrompting() {
        var trustCheckCount = 0
        var promptCount = 0
        XCTAssertTrue(AccessibilityWindow.requestPermission(
            isTrusted: {
                trustCheckCount += 1
                return true
            },
            showSystemPrompt: {
                promptCount += 1
                return false
            }
        ))
        XCTAssertEqual(trustCheckCount, 1)
        XCTAssertEqual(promptCount, 0)
    }

    func testUntrustedInteractiveLaunchChecksTrustAndPromptsExactlyOnce() {
        var trustCheckCount = 0
        var promptCount = 0
        XCTAssertFalse(AccessibilityWindow.requestPermission(
            isTrusted: {
                trustCheckCount += 1
                return false
            },
            showSystemPrompt: {
                promptCount += 1
                return false
            }
        ))
        XCTAssertEqual(trustCheckCount, 1)
        XCTAssertEqual(promptCount, 1)
    }

    func testRecoveryKeepsMeaningfullyVisiblePosition() {
        let frame = WindowFrame(position: CGPoint(x: -100, y: 100), size: CGSize(width: 800, height: 600))
        XCTAssertEqual(
            WorkspaceEngine.recoveryPosition(for: frame, displayBounds: [CGRect(x: 0, y: 0, width: 1920, height: 1080)]),
            frame.position
        )
    }

    func testRecoveryCentersParkedWindowWithoutResizing() {
        let frame = WindowFrame(position: CGPoint(x: 1919, y: 1079), size: CGSize(width: 800, height: 600))
        XCTAssertEqual(
            WorkspaceEngine.recoveryPosition(for: frame, displayBounds: [CGRect(x: 0, y: 0, width: 1920, height: 1080)]),
            CGPoint(x: 560, y: 240)
        )
    }

    func testQuitRecoveryMovesSecondaryDisplayWindowFullyOntoMainDisplay() {
        let frame = WindowFrame(position: CGPoint(x: -2800, y: 100), size: CGSize(width: 1200, height: 900))
        let mainDisplay = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        let recovered = WorkspaceEngine.quitRecoveryFrame(
            savedFrame: frame,
            currentFrame: nil,
            mainDisplayBounds: mainDisplay
        )

        XCTAssertTrue(mainDisplay.contains(CGRect(origin: recovered.position, size: recovered.size)))
        XCTAssertGreaterThanOrEqual(recovered.position.x, 12)
        XCTAssertGreaterThanOrEqual(recovered.position.y, 12)
    }

    func testQuitRecoveryShrinksOversizedWindowToMainDisplay() {
        let recovered = WorkspaceEngine.quitRecoveryFrame(
            savedFrame: WindowFrame(position: .zero, size: CGSize(width: 4000, height: 3000)),
            currentFrame: nil,
            mainDisplayBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        )

        XCTAssertEqual(recovered.position, CGPoint(x: 12, y: 12))
        XCTAssertEqual(recovered.size, CGSize(width: 1896, height: 1056))
    }

    func testQuitRecoveryUsesFiniteFallbackForIncompleteFrames() {
        let invalid = WindowFrame(
            position: CGPoint(x: CGFloat.infinity, y: CGFloat.nan),
            size: CGSize(width: -1, height: CGFloat.nan)
        )
        let recovered = WorkspaceEngine.quitRecoveryFrame(
            savedFrame: invalid,
            currentFrame: nil,
            mainDisplayBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        )

        XCTAssertEqual(recovered, WindowFrame(
            position: CGPoint(x: 560, y: 240),
            size: CGSize(width: 800, height: 600)
        ))
    }

    func testDisplayPlacementPreservesPositionOnSameDisplay() {
        let displays = testDisplays()
        let frame = WindowFrame(position: CGPoint(x: 2200, y: 180), size: CGSize(width: 900, height: 700))
        let placement = WorkspaceEngine.displayPlacement(for: frame, displays: displays)

        let resolved = WorkspaceEngine.resolveDisplayFrame(
            savedFrame: frame,
            placement: placement,
            displays: displays
        )

        XCTAssertEqual(resolved.frame, frame)
        XCTAssertFalse(resolved.usedFallbackDisplay)
        XCTAssertEqual(placement?.displayIdentifier, "external")
    }

    func testDisplayPlacementTracksRelativePositionAfterResolutionChange() {
        let original = [
            DisplaySnapshot(identifier: "external", bounds: CGRect(x: 1920, y: 0, width: 2000, height: 1000), isMain: false, name: "External")
        ]
        let frame = WindowFrame(position: CGPoint(x: 2120, y: 200), size: CGSize(width: 600, height: 400))
        let placement = WorkspaceEngine.displayPlacement(for: frame, displays: original)
        let changed = [
            DisplaySnapshot(identifier: "external", bounds: CGRect(x: -3000, y: -200, width: 3000, height: 1500), isMain: true, name: "External")
        ]

        let resolved = WorkspaceEngine.resolveDisplayFrame(
            savedFrame: frame,
            placement: placement,
            displays: changed
        )

        XCTAssertEqual(resolved.frame.position, CGPoint(x: -2700, y: 100))
        XCTAssertEqual(resolved.frame.size, frame.size)
    }

    func testDisconnectedPreferredDisplayFallsBackInsideMainWithoutLosingAffinity() {
        let main = DisplaySnapshot(
            identifier: "main",
            bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            isMain: true,
            name: "Main"
        )
        let placement = PersistedDisplayPlacement(
            displayIdentifier: "external",
            normalizedOrigin: CGPoint(x: 0.75, y: 0.6)
        )
        let saved = WindowFrame(position: CGPoint(x: 3000, y: 400), size: CGSize(width: 800, height: 600))

        let resolved = WorkspaceEngine.resolveDisplayFrame(
            savedFrame: saved,
            placement: placement,
            displays: [main]
        )

        XCTAssertTrue(resolved.usedFallbackDisplay)
        XCTAssertTrue(main.bounds.contains(CGRect(origin: resolved.frame.position, size: resolved.frame.size)))
        XCTAssertEqual(placement.displayIdentifier, "external")
    }

    func testReconnectedDisplayRestoresPreferredDisplay() {
        let displays = testDisplays()
        let placement = PersistedDisplayPlacement(
            displayIdentifier: "external",
            normalizedOrigin: CGPoint(x: 0.1, y: 0.2)
        )
        let saved = WindowFrame(position: CGPoint(x: 2120, y: 200), size: CGSize(width: 600, height: 400))

        let resolved = WorkspaceEngine.resolveDisplayFrame(
            savedFrame: saved,
            placement: placement,
            displays: displays
        )

        XCTAssertFalse(resolved.usedFallbackDisplay)
        XCTAssertEqual(resolved.frame.position, CGPoint(x: 2176, y: 216))
    }

    func testDisplayFallbackShrinksOversizedWindowInsideMain() {
        let main = DisplaySnapshot(
            identifier: "main",
            bounds: CGRect(x: 0, y: 0, width: 1440, height: 900),
            isMain: true,
            name: "Main"
        )
        let resolved = WorkspaceEngine.resolveDisplayFrame(
            savedFrame: WindowFrame(position: CGPoint(x: 2500, y: 100), size: CGSize(width: 2400, height: 1400)),
            placement: PersistedDisplayPlacement(
                displayIdentifier: "external",
                normalizedOrigin: CGPoint(x: 0.2, y: 0.2)
            ),
            displays: [main]
        )

        XCTAssertEqual(resolved.frame.size, main.bounds.size)
        XCTAssertEqual(resolved.frame.position, main.bounds.origin)
        XCTAssertTrue(resolved.usedFallbackDisplay)
    }

    func testIndependentWorkspaceSwitchLeavesOtherDisplayActiveWorkspaceUntouched() {
        let mainWorkspace = WorkspaceDefinition.defaults[0].id
        let oldExternalWorkspace = WorkspaceDefinition.defaults[1].id
        let newExternalWorkspace = WorkspaceDefinition.defaults[2].id
        let before = ["main": mainWorkspace, "external": oldExternalWorkspace]

        let after = WorkspaceEngine.switchingIndependentWorkspace(
            newExternalWorkspace,
            displayIdentifier: "external",
            in: before
        )

        XCTAssertEqual(after["main"], mainWorkspace)
        XCTAssertEqual(after["external"], newExternalWorkspace)
    }

    func testNewWindowJoinsActiveWorkspaceOnItsOwnDisplayInIndependentMode() {
        let mainWorkspace = WorkspaceDefinition.defaults[0].id
        let externalWorkspace = WorkspaceDefinition.defaults[1].id

        let selected = WorkspaceEngine.initialWorkspaceID(
            for: "external",
            mode: .independent,
            currentWorkspaceID: mainWorkspace,
            activeWorkspaceIDByDisplay: ["main": mainWorkspace, "external": externalWorkspace]
        )

        XCTAssertEqual(selected, externalWorkspace)
    }

    func testWindowFocusCycleWrapsWithinOrderedCandidates() {
        let candidates = ["left", "middle", "right"]

        XCTAssertEqual(
            WorkspaceEngine.focusCycleTarget(current: "right", orderedCandidates: candidates, offset: 1),
            "left"
        )
        XCTAssertEqual(
            WorkspaceEngine.focusCycleTarget(current: "left", orderedCandidates: candidates, offset: -1),
            "right"
        )
    }

    func testWindowFocusCycleNeverSelectsOutsideProvidedVisibleWorkspace() {
        let visibleCurrentWorkspace = ["one", "two"]

        XCTAssertEqual(
            WorkspaceEngine.focusCycleTarget(
                current: "parked-other-workspace",
                orderedCandidates: visibleCurrentWorkspace,
                offset: 1
            ),
            "one"
        )
        XCTAssertNil(WorkspaceEngine.focusCycleTarget(
            current: "one",
            orderedCandidates: [String](),
            offset: 1
        ))
    }

    func testParkedFrameIsExcludedFromVisibleFocusCandidates() {
        let displays = testDisplays()
        XCTAssertFalse(WorkspaceEngine.isMeaningfullyVisible(
            WindowFrame(position: CGPoint(x: 4479, y: 1079), size: CGSize(width: 800, height: 600)),
            displays: displays
        ))
        XCTAssertTrue(WorkspaceEngine.isMeaningfullyVisible(
            WindowFrame(position: CGPoint(x: 200, y: 200), size: CGSize(width: 800, height: 600)),
            displays: displays
        ))
    }

    func testExternalFocusPlansUnifiedWorkspaceSwitch() {
        let current = WorkspaceDefinition.defaults[0].id
        let focused = WorkspaceDefinition.defaults[1].id

        XCTAssertEqual(
            WorkspaceEngine.focusFollowPlan(
                focusedWorkspaceID: focused,
                mode: .unified,
                currentWorkspaceID: current,
                activeWorkspaceIDByDisplay: [:],
                homeDisplayIdentifier: nil
            ),
            FocusFollowPlan(
                displayIdentifier: nil,
                sourceWorkspaceID: current,
                targetWorkspaceID: focused
            )
        )
    }

    func testExternalFocusPlansOnlyAssignedDisplaySwitchInIndependentMode() {
        let main = WorkspaceDefinition.defaults[0].id
        let oldExternal = WorkspaceDefinition.defaults[1].id
        let focusedExternal = WorkspaceDefinition.defaults[2].id
        let active = ["main": main, "external": oldExternal]
        let plan = WorkspaceEngine.focusFollowPlan(
            focusedWorkspaceID: focusedExternal,
            mode: .independent,
            currentWorkspaceID: main,
            activeWorkspaceIDByDisplay: active,
            homeDisplayIdentifier: "external"
        )

        XCTAssertEqual(plan, FocusFollowPlan(
            displayIdentifier: "external",
            sourceWorkspaceID: oldExternal,
            targetWorkspaceID: focusedExternal
        ))
        XCTAssertEqual(
            WorkspaceEngine.switchingIndependentWorkspace(
                focusedExternal,
                displayIdentifier: "external",
                in: active
            )["main"],
            main
        )
    }

    func testFocusFollowDoesNothingForAlreadyActiveWorkspace() {
        let active = WorkspaceDefinition.defaults[0].id
        XCTAssertNil(WorkspaceEngine.focusFollowPlan(
            focusedWorkspaceID: active,
            mode: .unified,
            currentWorkspaceID: active,
            activeWorkspaceIDByDisplay: [:],
            homeDisplayIdentifier: nil
        ))
    }

    func testProgrammaticFocusDoesNotTriggerFollowLoop() {
        XCTAssertEqual(
            WorkspaceEngine.focusObservationDisposition(
                focusedWindow: "target",
                lastObservedFocusedWindow: "source",
                programmaticFocusTarget: "target",
                programmaticGraceActive: true
            ),
            .programmaticTarget
        )
        XCTAssertEqual(
            WorkspaceEngine.focusObservationDisposition(
                focusedWindow: "external",
                lastObservedFocusedWindow: "source",
                programmaticFocusTarget: "target",
                programmaticGraceActive: true
            ),
            .deferExternalChange
        )
        XCTAssertEqual(
            WorkspaceEngine.focusObservationDisposition(
                focusedWindow: "external",
                lastObservedFocusedWindow: "source",
                programmaticFocusTarget: "target",
                programmaticGraceActive: false
            ),
            .externalChange
        )
    }

    func testIndependentModeMigrationKeepsCurrentWorkspaceAndSeedsEachDisplay() {
        let first = WorkspaceDefinition.defaults[0].id
        let current = WorkspaceDefinition.defaults[1].id
        let external = WorkspaceDefinition.defaults[2].id
        let homes = [first: "main", current: "main", external: "external"]

        let active = WorkspaceEngine.reconciledIndependentActiveWorkspaces(
            workspaceIDs: [first, current, external],
            displayByWorkspace: homes,
            existing: [:],
            preferredWorkspaceID: current
        )

        XCTAssertEqual(active, ["main": current, "external": external])
    }

    func testDisconnectedIndependentDisplayKeepsItsLogicalActiveWorkspace() {
        let mainWorkspace = WorkspaceDefinition.defaults[0].id
        let externalWorkspace = WorkspaceDefinition.defaults[1].id
        let active = WorkspaceEngine.reconciledIndependentActiveWorkspaces(
            workspaceIDs: [mainWorkspace, externalWorkspace],
            displayByWorkspace: [mainWorkspace: "main", externalWorkspace: "disconnected-external"],
            existing: ["main": mainWorkspace, "disconnected-external": externalWorkspace]
        )

        XCTAssertEqual(active["main"], mainWorkspace)
        XCTAssertEqual(active["disconnected-external"], externalWorkspace)
    }

    func testLegacyWorkspaceStateWithoutDisplayFieldsStillDecodes() throws {
        let workspaceID = WorkspaceDefinition.defaults[0].id.uuidString
        let json = """
        {
          "version": 1,
          "windowServerSession": "test-session",
          "activeWorkspaceID": "\(workspaceID)",
          "windows": {
            "42": {
              "bundleIdentifier": "com.example.Editor",
              "workspaceID": "\(workspaceID)",
              "restoreFrame": {
                "position": [100, 200],
                "size": [800, 600]
              }
            }
          }
        }
        """

        let decoded = try JSONDecoder().decode(PersistedWorkspaceState.self, from: Data(json.utf8))

        XCTAssertNil(decoded.activeWorkspaceIDsByDisplay)
        XCTAssertNil(decoded.windows["42"]?.displayPlacement)
        XCTAssertEqual(decoded.windows["42"]?.isFloating, false)
    }

    func testFloatingOverridePersistsAcrossRestartWithinWindowServerSession() {
        let fileURL = temporaryStateURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let workspace = WorkspaceDefinition.defaults[1]
        let assignment = PersistedWindowAssignment(
            bundleIdentifier: "com.example.Editor",
            workspaceID: workspace.id,
            restoreFrame: WindowFrame(
                position: CGPoint(x: 240, y: 180),
                size: CGSize(width: 900, height: 700)
            ),
            displayPlacement: PersistedDisplayPlacement(
                displayIdentifier: "external",
                normalizedOrigin: CGPoint(x: 0.15, y: 0.2)
            ),
            isFloating: true
        )
        let state = PersistedWorkspaceState(
            version: PersistedWorkspaceState.currentVersion,
            windowServerSession: "floating-session",
            activeWorkspaceID: workspace.id,
            windows: ["88": assignment]
        )

        WorkspaceStateStore(fileURL: fileURL) { "floating-session" }
            .save(state, waitForCompletion: true)
        let restored = WorkspaceStateStore(fileURL: fileURL) { "floating-session" }.load()

        XCTAssertEqual(restored?.windows["88"], assignment)
        XCTAssertEqual(restored?.windows["88"]?.isFloating, true)
        XCTAssertNil(WorkspaceStateStore(fileURL: fileURL) { "different-session" }.load())
    }

    func testWorkspaceStateRoundTripsWithinWindowServerSession() throws {
        let fileURL = temporaryStateURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let workspace = WorkspaceDefinition.defaults[1]
        let frame = WindowFrame(position: CGPoint(x: 120, y: 240), size: CGSize(width: 960, height: 720))
        let placement = PersistedDisplayPlacement(
            displayIdentifier: "external",
            normalizedOrigin: CGPoint(x: 0.2, y: 0.3)
        )
        let state = PersistedWorkspaceState(
            version: PersistedWorkspaceState.currentVersion,
            windowServerSession: "test-session",
            activeWorkspaceID: workspace.id,
            windows: [
                "42": PersistedWindowAssignment(
                    bundleIdentifier: "com.example.Editor",
                    workspaceID: workspace.id,
                    restoreFrame: frame,
                    displayPlacement: placement
                )
            ],
            activeWorkspaceIDsByDisplay: ["external": workspace.id]
        )
        let writer = WorkspaceStateStore(fileURL: fileURL) { "test-session" }

        writer.save(state, waitForCompletion: true)

        let restored = WorkspaceStateStore(fileURL: fileURL) { "test-session" }.load()
        XCTAssertEqual(restored, state)
        XCTAssertEqual(restored?.activeWorkspaceID, workspace.id)
        XCTAssertEqual(restored?.windows["42"]?.restoreFrame, frame)
        XCTAssertEqual(restored?.windows["42"]?.displayPlacement, placement)
        XCTAssertEqual(restored?.activeWorkspaceIDsByDisplay, ["external": workspace.id])
        let permissions = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testWorkspaceStateRetriesAnUnchangedStateAfterWriteFailure() {
        let fileAccess = TestWorkspaceStateFileAccess()
        fileAccess.remainingWriteFailures = 1
        let workspace = WorkspaceDefinition.defaults[0]
        let state = PersistedWorkspaceState(
            version: PersistedWorkspaceState.currentVersion,
            windowServerSession: "retry-session",
            activeWorkspaceID: workspace.id,
            windows: [:]
        )
        let store = WorkspaceStateStore(
            fileURL: URL(fileURLWithPath: "/virtual/workspace-state.json"),
            sessionProvider: { "retry-session" },
            fileAccess: fileAccess
        )

        store.save(state, waitForCompletion: true)
        XCTAssertEqual(fileAccess.writeAttemptCount, 1)
        XCTAssertFalse(fileAccess.hasData)

        store.save(state, waitForCompletion: true)
        XCTAssertEqual(fileAccess.writeAttemptCount, 2)
        XCTAssertEqual(store.load(), state)
    }

    func testWorkspaceStateRecreatesAnExternallyRemovedUnchangedFile() {
        let fileAccess = TestWorkspaceStateFileAccess()
        let workspace = WorkspaceDefinition.defaults[0]
        let state = PersistedWorkspaceState(
            version: PersistedWorkspaceState.currentVersion,
            windowServerSession: "recreate-session",
            activeWorkspaceID: workspace.id,
            windows: [:]
        )
        let store = WorkspaceStateStore(
            fileURL: URL(fileURLWithPath: "/virtual/workspace-state.json"),
            sessionProvider: { "recreate-session" },
            fileAccess: fileAccess
        )

        store.save(state, waitForCompletion: true)
        fileAccess.removeData()
        store.save(state, waitForCompletion: true)

        XCTAssertEqual(fileAccess.writeAttemptCount, 2)
        XCTAssertEqual(store.load(), state)
    }

    func testWorkspaceStateRejectsOversizedDataBeforeReadingIt() {
        let fileAccess = TestWorkspaceStateFileAccess()
        fileAccess.seed(Data(repeating: 0x20, count: WorkspaceStateStore.maximumStateFileBytes + 1))
        let store = WorkspaceStateStore(
            fileURL: URL(fileURLWithPath: "/virtual/workspace-state.json"),
            sessionProvider: { "oversized-session" },
            fileAccess: fileAccess
        )

        XCTAssertNil(store.load())
        XCTAssertEqual(fileAccess.readCount, 0)
    }

    func testWorkspaceStateIsIgnoredAfterWindowServerChanges() {
        let fileURL = temporaryStateURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let workspace = WorkspaceDefinition.defaults[0]
        let state = PersistedWorkspaceState(
            version: PersistedWorkspaceState.currentVersion,
            windowServerSession: "old-session",
            activeWorkspaceID: workspace.id,
            windows: [:]
        )
        WorkspaceStateStore(fileURL: fileURL) { "old-session" }.save(state, waitForCompletion: true)

        XCTAssertNil(WorkspaceStateStore(fileURL: fileURL) { "new-session" }.load())
    }

    func testPersistedAssignmentRequiresExactAppAndExistingWorkspace() {
        let workspace = WorkspaceDefinition.defaults[2]
        let assignment = PersistedWindowAssignment(
            bundleIdentifier: "com.example.Editor",
            workspaceID: workspace.id,
            restoreFrame: WindowFrame(position: .zero, size: CGSize(width: 800, height: 600))
        )
        let state = PersistedWorkspaceState(
            version: PersistedWorkspaceState.currentVersion,
            windowServerSession: "test-session",
            activeWorkspaceID: workspace.id,
            windows: ["73": assignment]
        )

        XCTAssertEqual(
            state.assignment(
                for: 73,
                bundleIdentifier: "com.example.Editor",
                validWorkspaceIDs: [workspace.id]
            ),
            assignment
        )
        XCTAssertNil(state.assignment(
            for: 73,
            bundleIdentifier: "com.example.Other",
            validWorkspaceIDs: [workspace.id]
        ))
        XCTAssertNil(state.assignment(
            for: 73,
            bundleIdentifier: "com.example.Editor",
            validWorkspaceIDs: []
        ))
    }

    private func temporaryStateURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("WindowRangerTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("workspace-state.json")
    }

    private func testDisplays() -> [DisplaySnapshot] {
        [
            DisplaySnapshot(
                identifier: "main",
                bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                isMain: true,
                name: "Main"
            ),
            DisplaySnapshot(
                identifier: "external",
                bounds: CGRect(x: 1920, y: 0, width: 2560, height: 1080),
                isMain: false,
                name: "External"
            ),
        ]
    }
}

private final class TestWorkspaceStateFileAccess: WorkspaceStateFileAccess, @unchecked Sendable {
    private enum Failure: Error { case simulatedWrite, missingData }

    private let lock = NSLock()
    private var data: Data?
    private var writeAttempts = 0
    private var reads = 0
    var remainingWriteFailures = 0

    var writeAttemptCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return writeAttempts
    }

    var readCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return reads
    }

    var hasData: Bool {
        lock.lock()
        defer { lock.unlock() }
        return data != nil
    }

    func seed(_ data: Data) {
        lock.lock()
        self.data = data
        lock.unlock()
    }

    func removeData() {
        lock.lock()
        data = nil
        lock.unlock()
    }

    func fileExists(at url: URL) -> Bool { hasData }

    func fileSize(at url: URL) throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard let data else { throw Failure.missingData }
        return data.count
    }

    func read(from url: URL) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        reads += 1
        guard let data else { throw Failure.missingData }
        return data
    }

    func write(_ data: Data, to url: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        writeAttempts += 1
        if remainingWriteFailures > 0 {
            remainingWriteFailures -= 1
            throw Failure.simulatedWrite
        }
        self.data = data
    }
}
