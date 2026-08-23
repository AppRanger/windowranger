import Carbon
import Foundation
import XCTest

final class ShortcutFamilyTests: XCTestCase {
    func testApprovedDefaultsResolveEveryActionFromItsFamilyAndSuffix() {
        let configuration = HotKeyConfiguration()

        XCTAssertEqual(configuration.modifierMask(for: .navigate), UInt32(controlKey | optionKey))
        XCTAssertEqual(configuration.modifierMask(for: .arrange), UInt32(optionKey | cmdKey))
        XCTAssertEqual(
            configuration.chord(for: .previousWindow),
            HotKeyChord(keyCode: 43, modifiers: UInt32(controlKey | optionKey))
        )
        XCTAssertEqual(
            configuration.chord(for: .selectAccordion),
            HotKeyChord(keyCode: 43, modifiers: UInt32(optionKey | cmdKey))
        )
        XCTAssertEqual(
            configuration.chord(for: .moveWorkspaceToNextDisplay),
            HotKeyChord(keyCode: 2, modifiers: UInt32(optionKey | cmdKey))
        )
    }

    func testChangingFamilyRegeneratesActionsAndDerivedWorkspaceChords() {
        var configuration = HotKeyConfiguration()
        XCTAssertNil(configuration.setModifierMask(UInt32(controlKey | shiftKey), for: .navigate))

        XCTAssertEqual(
            configuration.chord(for: .commandWheel),
            HotKeyChord(keyCode: 49, modifiers: UInt32(controlKey | shiftKey))
        )
        XCTAssertEqual(
            configuration.chord(forWorkspaceKeyCode: 18, family: .navigate),
            HotKeyChord(keyCode: 18, modifiers: UInt32(controlKey | shiftKey))
        )
        XCTAssertEqual(
            configuration.chord(forWorkspaceKeyCode: 18, family: .arrange),
            HotKeyChord(keyCode: 18, modifiers: UInt32(optionKey | cmdKey))
        )
    }

    func testFamilyValidationRejectsEqualSubsetAndUnsafeModifierSets() {
        let navigate = UInt32(controlKey | optionKey)
        XCTAssertNotNil(HotKeyConfiguration.familyValidationMessage(navigate: navigate, arrange: navigate))
        XCTAssertNotNil(HotKeyConfiguration.familyValidationMessage(
            navigate: navigate,
            arrange: UInt32(controlKey | optionKey | shiftKey)
        ))
        XCTAssertNotNil(HotKeyConfiguration.familyValidationMessage(
            navigate: UInt32(shiftKey),
            arrange: UInt32(optionKey | cmdKey)
        ))
    }

    func testFamilyResetReportsAConflictInsteadOfSilentlyDoingNothing() {
        var configuration = HotKeyConfiguration()
        XCTAssertNil(configuration.setModifierMask(UInt32(controlKey | shiftKey), for: .navigate))
        XCTAssertNil(configuration.setModifierMask(UInt32(controlKey | optionKey), for: .arrange))

        XCTAssertNotNil(configuration.resetModifierMask(for: .navigate))
        XCTAssertEqual(
            configuration.modifierMask(for: .navigate),
            UInt32(controlKey | shiftKey)
        )
    }

    func testKeyAssignmentsCanBeUnassignedAndCrossFamilyDuplicatesRemainValid() {
        var configuration = HotKeyConfiguration()
        configuration.setKeyCode(nil, for: .toggleFloating)
        XCTAssertNil(configuration.optionalChord(for: .toggleFloating))

        configuration.setKeyCode(43, for: .selectAccordion)
        let report = ShortcutConflictModel.evaluate(configuration: configuration, workspaces: [])
        XCTAssertTrue(report.issues(for: .selectAccordion).isEmpty)
        XCTAssertTrue(report.issues(for: .previousWindow).isEmpty)
    }

    func testLegacyCompleteChordPayloadMigratesSafelyToApprovedFamilyMap() throws {
        let legacy = Data("""
        {"overrides":{"previousWindow":{"keyCode":6,"modifiers":4352}}}
        """.utf8)
        let configuration = try JSONDecoder().decode(HotKeyConfiguration.self, from: legacy)

        XCTAssertEqual(configuration, HotKeyConfiguration())
        XCTAssertEqual(
            configuration.chord(for: .previousWindow),
            HotKeyChord(keyCode: 43, modifiers: UInt32(controlKey | optionKey))
        )
    }

    func testNewFamilyAndSuffixFormatRoundTripsIncludingUnassignedActions() throws {
        var configuration = HotKeyConfiguration()
        XCTAssertNil(configuration.setModifierMask(UInt32(controlKey | shiftKey), for: .navigate))
        configuration.setKeyCode(6, for: .previousWindow)
        configuration.setKeyCode(nil, for: .moveWorkspaceToNextDisplay)

        let encoded = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(HotKeyConfiguration.self, from: encoded)

        XCTAssertEqual(decoded, configuration)
        XCTAssertEqual(
            decoded.optionalChord(for: .previousWindow),
            HotKeyChord(keyCode: 6, modifiers: UInt32(controlKey | shiftKey))
        )
        XCTAssertNil(decoded.optionalChord(for: .moveWorkspaceToNextDisplay))
    }

    func testRemovedShortcutAssignmentsAreDiscardedWhenDecoding() throws {
        let legacy = Data("""
        {
          "familyModifiers": {"navigate": 6144, "arrange": 2304},
          "keyOverrides": {"cycleQuickApp": 18},
          "disabledActions": ["cycleQuickApp"]
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(HotKeyConfiguration.self, from: legacy)
        let reencoded = try JSONEncoder().encode(decoded)

        XCTAssertEqual(decoded, HotKeyConfiguration())
        XCTAssertFalse(String(decoding: reencoded, as: UTF8.self).contains("cycleQuickApp"))
    }

    func testUnassignedReorderKeyDisablesTwoArrowGestureFamily() {
        var configuration = HotKeyConfiguration()
        configuration.setKeyCode(nil, for: .moveLeft)

        XCTAssertEqual(
            DirectionalMoveChordFamily.resolve(configuration: configuration),
            .failure(.shortcutConflict)
        )
    }
}
