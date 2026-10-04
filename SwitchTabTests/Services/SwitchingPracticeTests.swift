import Foundation
import XCTest
@testable import SwitchTab

@MainActor
final class SwitchingPracticeTests: XCTestCase {
    private let suiteName = "SwitchTabTests.Practice.\(UUID().uuidString)"
    private lazy var defaults = UserDefaults(suiteName: suiteName)!

    override func tearDown() async throws {
        clearDefaults()
    }

    private func clearDefaults() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testRegisteredFallbackIsTheGuidedShortcut() {
        let model = makeModel(windowShortcut: .fallbackCurrentAppWindowSwitching)
        XCTAssertEqual(model.windowShortcut, .fallbackCurrentAppWindowSwitching)
        XCTAssertTrue(model.canBegin)
    }

    func testUnregisteredWindowModeCannotBeginPractice() {
        let model = makeModel(windowShortcut: nil)
        XCTAssertFalse(model.begin())
        XCTAssertFalse(model.hasCompletedPractice)
    }

    func testAccessibilityIsRequiredButScreenRecordingIsOptional() {
        let model = makeModel()
        XCTAssertTrue(model.begin())
        model.cancel()
        model.update(
            windowShortcut: .defaultCurrentAppWindowSwitching,
            applicationShortcut: nil,
            permissionState: PermissionState(accessibility: .missing, screenRecording: .granted)
        )
        XCTAssertFalse(model.begin())
        XCTAssertFalse(model.hasCompletedPractice)
    }

    func testSuccessfulFocusRequestWaitsForExactObservedWindow() throws {
        let model = makeModel()
        XCTAssertTrue(model.begin())
        let generation = try XCTUnwrap(model.confirm(windowID: "42-7", result: .focused))
        XCTAssertFalse(model.hasCompletedPractice)
        model.verify(generation: generation, focusedWindowID: "42-7")
        XCTAssertTrue(model.hasCompletedPractice)
        XCTAssertEqual(model.state, .completed)
    }

    func testAnotherFocusedWindowDoesNotCompletePractice() throws {
        let model = makeModel()
        XCTAssertTrue(model.begin())
        let generation = try XCTUnwrap(model.confirm(windowID: "42-7", result: .focused))
        model.verify(generation: generation, focusedWindowID: "42-8")
        XCTAssertFalse(model.hasCompletedPractice)
        XCTAssertEqual(model.state, .failed(.focusNotConfirmed))
    }

    func testUnavailableAndPermissionBlockedFocusNeverComplete() {
        for result in [WindowFocusResult.unavailableTarget, .permissionBlocked] {
            let model = makeModel()
            XCTAssertTrue(model.begin())
            XCTAssertNil(model.confirm(windowID: "42-7", result: result))
            XCTAssertFalse(model.hasCompletedPractice)
        }
    }

    func testNormalSwitchWithoutPracticeDoesNotRecordCompletion() {
        let model = makeModel()
        XCTAssertNil(model.confirm(windowID: "42-7", result: .focused))
        XCTAssertFalse(model.hasCompletedPractice)
    }

    func testCancellationInvalidatesPendingVerification() throws {
        let model = makeModel()
        XCTAssertTrue(model.begin())
        let generation = try XCTUnwrap(model.confirm(windowID: "42-7", result: .focused))
        model.cancel()
        model.verify(generation: generation, focusedWindowID: "42-7")
        XCTAssertFalse(model.hasCompletedPractice)
        XCTAssertEqual(model.state, .cancelled)
    }

    func testRestartCannotAcceptPreviousVerification() throws {
        let model = makeModel()
        XCTAssertTrue(model.begin())
        let previous = try XCTUnwrap(model.confirm(windowID: "42-7", result: .focused))
        XCTAssertTrue(model.begin())
        let current = try XCTUnwrap(model.confirm(windowID: "42-9", result: .focused))
        model.verify(generation: previous, focusedWindowID: "42-7")
        XCTAssertFalse(model.hasCompletedPractice)
        model.verify(generation: current, focusedWindowID: "42-9")
        XCTAssertTrue(model.hasCompletedPractice)
    }

    func testPermissionLossInvalidatesPendingVerification() throws {
        let model = makeModel()
        XCTAssertTrue(model.begin())
        let generation = try XCTUnwrap(model.confirm(windowID: "42-7", result: .focused))
        model.update(
            windowShortcut: .defaultCurrentAppWindowSwitching,
            applicationShortcut: nil,
            permissionState: PermissionState(accessibility: .missing, screenRecording: .missing)
        )
        model.verify(generation: generation, focusedWindowID: "42-7")
        XCTAssertFalse(model.hasCompletedPractice)
    }

    func testSkipPersistsWithoutClaimingSuccess() {
        let model = makeModel()
        model.skipGuide()
        let reloaded = SwitchingPracticeModel(userDefaults: defaults)
        XCTAssertTrue(reloaded.hasDismissedGuide)
        XCTAssertFalse(reloaded.hasCompletedPractice)
    }

    func testVerifiedCompletionPersistsWithoutChangingShortcutSettings() throws {
        let key = "SwitchTab.Shortcuts.fixture"
        defaults.set("original-setting", forKey: key)
        let model = makeModel()
        XCTAssertTrue(model.begin())
        let generation = try XCTUnwrap(model.confirm(windowID: "42-7", result: .focused))
        model.verify(generation: generation, focusedWindowID: "42-7")
        let reloaded = SwitchingPracticeModel(userDefaults: defaults)
        XCTAssertTrue(reloaded.hasCompletedPractice)
        XCTAssertTrue(reloaded.hasDismissedGuide)
        XCTAssertEqual(reloaded.state, .completed)
        XCTAssertEqual(defaults.string(forKey: key), "original-setting")
    }

    private func makeModel(windowShortcut: ShortcutSetting? = .defaultCurrentAppWindowSwitching) -> SwitchingPracticeModel {
        let model = SwitchingPracticeModel(userDefaults: defaults)
        model.update(
            windowShortcut: windowShortcut,
            applicationShortcut: .defaultApplicationSwitching,
            permissionState: PermissionState(accessibility: .granted, screenRecording: .missing)
        )
        return model
    }
}
