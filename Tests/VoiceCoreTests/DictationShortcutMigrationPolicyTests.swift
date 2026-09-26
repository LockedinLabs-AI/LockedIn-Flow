import XCTest
@testable import VoiceCore

final class DictationShortcutMigrationPolicyTests: XCTestCase {
    func testUnmigratedExactBareFunctionDefaultIsReplaced() {
        XCTAssertTrue(
            DictationShortcutMigrationPolicy.shouldReplaceLegacyDefault(
                completedVersion: 0,
                storedShortcut: .init(keyCode: 63, modifierFlags: 0)
            )
        )
    }

    func testCustomShortcutsAndDisabledShortcutArePreserved() {
        let customShortcuts = [
            ShortcutPreferenceSignature(keyCode: 49, modifierFlags: 4_608),
            ShortcutPreferenceSignature(keyCode: 63, modifierFlags: 512),
            ShortcutPreferenceSignature(keyCode: 62, modifierFlags: 0),
        ]

        for shortcut in customShortcuts {
            XCTAssertFalse(
                DictationShortcutMigrationPolicy.shouldReplaceLegacyDefault(
                    completedVersion: 0,
                    storedShortcut: shortcut
                )
            )
        }
        XCTAssertFalse(
            DictationShortcutMigrationPolicy.shouldReplaceLegacyDefault(
                completedVersion: 0,
                storedShortcut: nil
            )
        )
    }

    func testBareFunctionChosenAfterMigrationIsPreserved() {
        XCTAssertFalse(
            DictationShortcutMigrationPolicy.shouldReplaceLegacyDefault(
                completedVersion: DictationShortcutMigrationPolicy.currentVersion,
                storedShortcut: DictationShortcutMigrationPolicy.legacyBareFunction
            )
        )
    }

    func testPendingNoticeWaitsUntilModelIsReady() {
        XCTAssertFalse(
            DictationShortcutMigrationNoticePolicy.shouldPresent(
                isPending: true,
                modelIsReady: false
            )
        )
        XCTAssertTrue(
            DictationShortcutMigrationNoticePolicy.shouldPresent(
                isPending: true,
                modelIsReady: true
            )
        )
    }

    func testPendingNoticeSurvivesALaterLaunchWithoutAnotherMigration() {
        XCTAssertTrue(
            DictationShortcutMigrationNoticePolicy.pendingAfterLaunch(
                persistedPending: true,
                migrationDidOccur: false
            )
        )
        XCTAssertTrue(
            DictationShortcutMigrationNoticePolicy.pendingAfterLaunch(
                persistedPending: false,
                migrationDidOccur: true
            )
        )
    }

    func testAcknowledgedNoticeDoesNotReappear() {
        XCTAssertFalse(
            DictationShortcutMigrationNoticePolicy.pendingAfterLaunch(
                persistedPending: false,
                migrationDidOccur: false
            )
        )
        XCTAssertFalse(
            DictationShortcutMigrationNoticePolicy.shouldPresent(
                isPending: false,
                modelIsReady: true
            )
        )
    }
}
