import AppKit
import Carbon
import SwiftUI
import XCTest

final class ShortcutGuideTests: XCTestCase {
    func testGuideResolverAndHeaderFollowConfiguredFamilies() {
        var configuration = HotKeyConfiguration()
        XCTAssertNil(configuration.setModifierMask(UInt32(controlKey | shiftKey), for: .navigate))
        XCTAssertNil(configuration.setModifierMask(UInt32(optionKey | cmdKey | shiftKey), for: .arrange))

        XCTAssertEqual(
            ShortcutGuideModifierResolver.resolve(
                carbonModifiers: UInt32(controlKey | shiftKey),
                configuration: configuration
            ),
            .navigate
        )
        let content = ShortcutGuideContentBuilder.build(
            family: .navigate,
            workspaces: [WorkspaceDefinition(name: "One", key: "1")],
            configuration: configuration,
            runtimeIssues: []
        )
        XCTAssertEqual(content?.modifierLabel, "⌃ + ⇧")
    }

    func testModifierResolverRequiresExactFamiliesAndIgnoresCapsLock() {
        XCTAssertEqual(
            ShortcutGuideModifierResolver.resolve(carbonModifiers: UInt32(controlKey | optionKey)),
            .navigate
        )
        XCTAssertEqual(
            ShortcutGuideModifierResolver.resolve(carbonModifiers: UInt32(optionKey | cmdKey)),
            .arrange
        )
        XCTAssertNil(ShortcutGuideModifierResolver.resolve(carbonModifiers: UInt32(controlKey | optionKey | cmdKey)))
        XCTAssertNil(ShortcutGuideModifierResolver.resolve(carbonModifiers: UInt32(controlKey | optionKey | shiftKey)))
        XCTAssertNil(ShortcutGuideModifierResolver.resolve(carbonModifiers: UInt32(optionKey)))
        XCTAssertNil(ShortcutGuideModifierResolver.resolve([.control, .option, .function]))
    }

    func testContentBuilderUsesEligibleWorkspaceOwnersAndLetterKeys() {
        let workspaces = [
            WorkspaceDefinition(name: "Writing", key: "w"),
            WorkspaceDefinition(name: "3", key: "3"),
        ]
        let navigation = try! XCTUnwrap(ShortcutGuideContentBuilder.build(
            family: .navigate,
            workspaces: workspaces,
            configuration: HotKeyConfiguration(),
            runtimeIssues: []
        ))
        XCTAssertEqual(navigation.primaryActions.map(\.keyLabel), ["3", "W"])
        XCTAssertEqual(navigation.primaryActions.map(\.title), ["3", "Writing"])
        XCTAssertTrue(navigation.primaryActions.allSatisfy {
            if case .workspaceSwitch = $0.kind { return true }
            return false
        })

        let movement = try! XCTUnwrap(ShortcutGuideContentBuilder.build(
            family: .arrange,
            workspaces: workspaces,
            configuration: HotKeyConfiguration(),
            runtimeIssues: []
        ))
        XCTAssertTrue(movement.primaryActions.allSatisfy {
            if case .workspaceMove = $0.kind { return true }
            return false
        })
    }

    func testContentBuilderExcludesConflictedAndRuntimeFailedActions() {
        let workspace = WorkspaceDefinition(name: "Writing", key: "w")
        var configuration = HotKeyConfiguration()
        // Deliberately collides with workspace navigation, which makes both owners ineligible.
        configuration.setKeyCode(13, for: .toggleDropDownApp)
        let conflicted = try! XCTUnwrap(ShortcutGuideContentBuilder.build(
            family: .navigate,
            workspaces: [workspace],
            configuration: configuration,
            runtimeIssues: []
        ))
        XCTAssertFalse(conflicted.primaryActions.contains { $0.keyLabel == "W" })
        XCTAssertFalse(conflicted.secondaryActions.contains { $0.kind == .global(.toggleDropDownApp) })

        let runtimeIssue = HotKeyRuntimeIssue(
            owner: .workspaceSwitch(workspace),
            chord: HotKeyChord(keyCode: 13, modifiers: UInt32(controlKey | optionKey)),
            status: -9876
        )
        let runtimeFailed = try! XCTUnwrap(ShortcutGuideContentBuilder.build(
            family: .navigate,
            workspaces: [workspace],
            configuration: HotKeyConfiguration(),
            runtimeIssues: [runtimeIssue]
        ))
        XCTAssertFalse(runtimeFailed.primaryActions.contains { $0.keyLabel == "W" })
    }

    func testGeometryHonoursPositionsAndClampsToScreen() {
        let visible = CGRect(x: 0, y: 24, width: 800, height: 600)
        let center = ShortcutGuideGeometry.frame(
            panelSize: CGSize(width: 570, height: 178),
            visibleFrame: visible,
            position: .bottomCenter
        )
        XCTAssertEqual(center.midX, visible.midX, accuracy: 0.001)
        XCTAssertEqual(center.minY, 48, accuracy: 0.001)
        let topLeading = ShortcutGuideGeometry.frame(
            panelSize: CGSize(width: 900, height: 900),
            visibleFrame: visible,
            position: .topLeading
        )
        XCTAssertTrue(visible.contains(topLeading))
        XCTAssertEqual(ShortcutGuideSize.defaultValue, .medium)
        XCTAssertEqual(ShortcutGuidePosition.defaultValue, .bottomCenter)
        XCTAssertEqual(ShortcutGuidePosition.allCases.count, 9)
    }

    func testPassivePanelPolicyDoesNotTakeFocusOrInput() {
        XCTAssertFalse(ShortcutGuidePanelPolicy.passive.canBecomeKey)
        XCTAssertFalse(ShortcutGuidePanelPolicy.passive.canBecomeMain)
        XCTAssertTrue(ShortcutGuidePanelPolicy.passive.ignoresMouseEvents)
        XCTAssertFalse(ShortcutGuidePanelPolicy.passive.participatesInWindowCycle)
    }

    @MainActor
    func testConfiguredPanelCarriesThePassivePolicy() {
        let controller = ShortcutGuidePanelController()
        let panel = controller.panelForTesting
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertTrue(panel.collectionBehavior.contains(.ignoresCycle))
        XCTAssertTrue(panel.collectionBehavior.contains(.moveToActiveSpace))
        XCTAssertFalse(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertFalse(panel.isVisible)
    }

    func testObservationGenerationRejectsCallbacksFromStoppedSessions() {
        var generation = ShortcutGuideObservationGeneration()
        let firstSession = generation.advance()
        XCTAssertTrue(generation.accepts(firstSession))
        _ = generation.advance()
        XCTAssertFalse(generation.accepts(firstSession))
    }

    func testMixedDirectionalFamiliesRemainVisibleAsRegularActions() {
        let actions = [
            ShortcutGuideAction(id: "move-left", kind: .global(.moveLeft), title: "Reorder left", keyLabel: "←", isDirectional: true),
            ShortcutGuideAction(id: "focus-right", kind: .global(.focusRight), title: "Focus right", keyLabel: "L", isDirectional: true),
            ShortcutGuideAction(id: "commands", kind: .global(.commandWheel), title: "Commands", keyLabel: "Space", isDirectional: false),
        ]
        let mixed = ShortcutGuidePresentationGroups(actions: actions)
        XCTAssertEqual(mixed.regularSecondaryActions, actions)
        XCTAssertTrue(mixed.clusteredDirectionalActions.isEmpty)

        let reorderOnly = ShortcutGuidePresentationGroups(actions: [actions[0], actions[2]])
        XCTAssertEqual(reorderOnly.regularSecondaryActions, [actions[2]])
        XCTAssertEqual(reorderOnly.clusteredDirectionalActions, [actions[0]])
    }

    func testPreferredInteractionDisplayWinsOverPointerDisplay() {
        XCTAssertEqual(
            ShortcutGuideDisplayChoice.resolve(
                preferredIdentifier: "display-b",
                pointerIdentifier: "display-a",
                availableIdentifiers: ["display-a", "display-b"]
            ),
            "display-b"
        )
        XCTAssertEqual(
            ShortcutGuideDisplayChoice.resolve(
                preferredIdentifier: "disconnected",
                pointerIdentifier: "display-a",
                availableIdentifiers: ["display-a", "display-b"]
            ),
            "display-a"
        )
    }

    func testDenseContentAddsRowsRatherThanClippingActions() {
        let workspaces = HotKeyManager.keyCodes.keys.sorted().enumerated().map { index, key in
            ShortcutGuideAction(
                id: "workspace-\(index)",
                kind: .workspaceSwitch(UUID()),
                title: "Workspace \(key.uppercased())",
                keyLabel: key.uppercased(),
                isDirectional: false
            )
        }
        let secondary = ConfigurableHotKeyAction.allCases.prefix(15).enumerated().map { index, action in
            ShortcutGuideAction(
                id: "secondary-\(index)",
                kind: .global(action),
                title: action.title,
                keyLabel: String(index + 1),
                isDirectional: false
            )
        }
        let content = ShortcutGuideContent(
            family: .navigate,
            primaryActions: workspaces,
            secondaryActions: secondary
        )
        for size in ShortcutGuideSize.allCases {
            let metrics = ShortcutGuideLayoutMetrics(size: size, content: content)
            XCTAssertGreaterThan(metrics.primaryRowCount, 1)
            XCTAssertGreaterThan(metrics.secondaryRowCount, 1)
            XCTAssertGreaterThan(metrics.panelSize.height, size.panelSize.height)
            XCTAssertGreaterThanOrEqual(
                metrics.primaryColumnCount * metrics.primaryRowCount,
                workspaces.count
            )
            XCTAssertGreaterThanOrEqual(
                metrics.secondaryColumnCount * metrics.secondaryRowCount,
                secondary.count
            )
        }
    }

    func testDirectionalOnlyContentKeepsThePrimaryBandVisible() {
        let action = ShortcutGuideAction(
            id: "directional",
            kind: .global(.moveLeft),
            title: "Move Left",
            keyLabel: "Left",
            isDirectional: true
        )
        let content = ShortcutGuideContent(
            family: .navigate,
            primaryActions: [],
            secondaryActions: [action]
        )
        XCTAssertTrue(ShortcutGuideLayoutMetrics(size: .medium, content: content).showsPrimaryBand)
    }

    func testMonitorStartStopIsIdempotentAndDoesNotRequireEventConsumption() {
        let fake = FakeShortcutGuideMonitor()
        let monitor = ShortcutGuideModifierMonitor(events: fake)
        var observed: [ShortcutFamily?] = []
        XCTAssertTrue(monitor.start { observed.append($0) })
        XCTAssertTrue(monitor.start { observed.append($0) })
        XCTAssertEqual(fake.globalAdds, 2)
        XCTAssertEqual(fake.localAdds, 2)
        XCTAssertEqual(fake.removals, 2) // restart removes the first pair
        fake.globalHandler?([.option, .command])
        XCTAssertEqual(observed.last!, .arrange)
        monitor.stop()
        monitor.stop()
        XCTAssertEqual(fake.removals, 4)
        XCTAssertNil(observed.last!)
    }

    @MainActor
    func testOffscreenShortcutGuideSnapshots() throws {
        guard let path = ProcessInfo.processInfo.environment["WINDOWRANGER_VISUAL_SNAPSHOT_OUTPUT_DIR"], !path.isEmpty else { return }
        let output = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let workspaces = (1...5).map { value in
            WorkspaceDefinition(name: String(value), key: String(value))
        }
        let contents = try [
            XCTUnwrap(ShortcutGuideContentBuilder.build(
                family: .navigate,
                workspaces: workspaces,
                configuration: HotKeyConfiguration(),
                runtimeIssues: []
            )),
            XCTUnwrap(ShortcutGuideContentBuilder.build(
                family: .arrange,
                workspaces: workspaces,
                configuration: HotKeyConfiguration(),
                runtimeIssues: []
            )),
        ]
        for content in contents {
            for scheme in [ColorScheme.light, .dark] {
                let name = scheme == .light ? "light" : "dark"
                let snapshotSize = ShortcutGuideSize.large.panelSize(for: content)
                let view = ShortcutGuideView(
                    content: content,
                    size: .large,
                    surfaceStyle: .snapshot
                )
                .frame(width: snapshotSize.width, height: snapshotSize.height)
                .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: view)
                renderer.proposedSize = ProposedViewSize(snapshotSize)
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.cgImage)
                let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                try data.write(to: output.appendingPathComponent("windowranger-shortcut-guide-\(content.family.rawValue)-\(name).png"), options: .atomic)
                XCTAssertGreaterThan(data.count, 10_000)
            }
        }
    }
}

private final class FakeShortcutGuideMonitor: ShortcutGuideEventMonitoring {
    var globalAdds = 0
    var localAdds = 0
    var removals = 0
    var globalHandler: ((NSEvent.ModifierFlags) -> Void)?

    func addGlobalFlagsChanged(_ handler: @escaping (NSEvent.ModifierFlags) -> Void) -> Any? {
        globalAdds += 1
        globalHandler = handler
        return "global-\(globalAdds)" as NSString
    }

    func addLocalFlagsChanged(_ handler: @escaping (NSEvent) -> NSEvent?) -> Any? {
        localAdds += 1
        return "local-\(localAdds)" as NSString
    }

    func removeMonitor(_ monitor: Any) { removals += 1 }
}
