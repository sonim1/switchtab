import AppKit
import Foundation
@testable import SwitchTab
import XCTest

@MainActor
enum PermissionRecoveryCopyTests {
    static func run() throws {
        try testPermissionStatusItemsNamePermissionCapabilityAndSettingsStep()
        try testPermissionStatusItemDetailCombinesBlockedCapabilityAndSettingsStep()
        try testPermissionStatusItemsIncludeGrantedAndMissingPermissions()
        try testPermissionStatusItemsMapToSystemSettingsDestinations()
        try testPermissionStatusItemsExposeAllowActionTitle()
        try testPermissionStatusItemsExposeCombinedRecoveryActionHelp()
        try testPermissionStatusItemRecoveryActionHelpUsesPermissionName()
    }

    static func testPermissionStatusItemsNamePermissionCapabilityAndSettingsStep() throws {
        let state = PermissionState(accessibility: .missing, screenRecording: .missing)

        for item in state.permissionStatusItems {
            try expectFalse(item.permissionName.isEmpty)
            try expectFalse(item.detailText.isEmpty)
            try expectTrue(item.detailText.contains("System Settings"))
        }
    }

    static func testPermissionStatusItemDetailCombinesBlockedCapabilityAndSettingsStep() throws {
        let state = PermissionState(accessibility: .missing, screenRecording: .granted)
        guard let item = state.permissionStatusItems.first else {
            throw TestFailure.failed("Expected permission status item")
        }

        try expectTrue(item.detailText.contains("Window observation and focus changes are blocked."))
        try expectTrue(item.detailText.contains("System Settings"))
    }

    static func testPermissionStatusItemsIncludeGrantedAndMissingPermissions() throws {
        let state = PermissionState(accessibility: .missing, screenRecording: .granted)

        try expectEqual(state.permissionStatusItems.map(\.permissionName), ["Accessibility", "Screen Recording"])
        try expectFalse(state.permissionStatusItems[0].isGranted)
        try expectTrue(state.permissionStatusItems[0].detailText.contains("System Settings"))
        try expectTrue(state.permissionStatusItems[1].isGranted)
        try expectTrue(state.permissionStatusItems[1].detailText.contains("enabled"))
    }

    static func testPermissionStatusItemsMapToSystemSettingsDestinations() throws {
        let state = PermissionState(accessibility: .missing, screenRecording: .missing)

        let destinations = state.permissionStatusItems.map(\.settingsDestination)

        try expectEqual(destinations, [.accessibility, .screenRecording])
        try expectEqual(
            PermissionSettingsDestination.accessibility.systemSettingsURL.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
        try expectEqual(
            PermissionSettingsDestination.screenRecording.systemSettingsURL.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )
    }

    static func testPermissionStatusItemsExposeAllowActionTitle() throws {
        let state = PermissionState(accessibility: .missing, screenRecording: .missing)

        try expectEqual(state.permissionStatusItems.map(\.recoveryActionTitle), ["Allow", "Allow"])
    }

    static func testPermissionStatusItemsExposeCombinedRecoveryActionHelp() throws {
        let state = PermissionState(accessibility: .missing, screenRecording: .missing)

        try expectEqual(
            state.permissionStatusItems.map(\.recoveryActionHelp),
            [
                "Open Accessibility Settings and show SwitchTab in Finder.",
                "Open Screen Recording Settings and show SwitchTab in Finder."
            ]
        )
    }

    static func testPermissionStatusItemRecoveryActionHelpUsesPermissionName() throws {
        let item = PermissionStatusItem(
            permissionName: "Custom Permission",
            settingsDestination: .accessibility,
            grantState: .missing,
            blockedCapability: "A capability is blocked.",
            settingsStep: "Open System Settings."
        )

        try expectEqual(
            item.recoveryActionHelp,
            "Open Custom Permission Settings and show SwitchTab in Finder."
        )
    }

}

@MainActor
final class PermissionRecoveryActivationWaiterTests: XCTestCase {
    func testWrongPIDIsIgnoredUntilExactPIDActivates() async {
        let center = NotificationCenter()
        var observerRemovalCount = 0
        let waiter = WorkspacePermissionRecoveryActivationWaiter(
            notificationCenter: center,
            onObserverRemoved: {
                observerRemovalCount += 1
            }
        )
        let exactApplication = TestPermissionRecoveryRunningApplication(
            processIdentifier: 4101,
            isActive: false
        )
        let wrongPIDApplication = TestPermissionRecoveryRunningApplication(
            processIdentifier: 4102,
            isActive: true
        )
        let waitTask = Task { @MainActor in
            await waiterOutcome(waiter, application: exactApplication)
        }

        postActivation(of: wrongPIDApplication, on: center)

        XCTAssertEqual(observerRemovalCount, 0)

        postActivation(of: exactApplication, on: center)
        let outcome = await waitTask.value

        XCTAssertEqual(outcome, .succeeded)
        XCTAssertEqual(observerRemovalCount, 1)
    }

    func testExactPIDEventBeforeWaitIsBuffered() async {
        let center = NotificationCenter()
        var observerRemovalCount = 0
        let waiter = WorkspacePermissionRecoveryActivationWaiter(
            notificationCenter: center,
            onObserverRemoved: {
                observerRemovalCount += 1
            }
        )
        let application = TestPermissionRecoveryRunningApplication(
            processIdentifier: 4101,
            isActive: false
        )

        postActivation(of: application, on: center)
        let outcome = await waiterOutcome(waiter, application: application)

        XCTAssertEqual(outcome, .succeeded)
        XCTAssertEqual(observerRemovalCount, 1)
    }

    func testAlreadyActiveApplicationReturnsWithoutEvent() async {
        let center = NotificationCenter()
        var observerRemovalCount = 0
        let waiter = WorkspacePermissionRecoveryActivationWaiter(
            notificationCenter: center,
            onObserverRemoved: {
                observerRemovalCount += 1
            }
        )
        let application = TestPermissionRecoveryRunningApplication(
            processIdentifier: 4101,
            isActive: true
        )

        let outcome = await waiterOutcome(waiter, application: application)

        XCTAssertEqual(outcome, .succeeded)
        XCTAssertEqual(observerRemovalCount, 1)
    }

    func testCancellationDuringWaitTransitionsOnceAndIgnoresLateEvent() async {
        let center = NotificationCenter()
        var observerRemovalCount = 0
        let waiter = WorkspacePermissionRecoveryActivationWaiter(
            notificationCenter: center,
            onObserverRemoved: {
                observerRemovalCount += 1
            }
        )
        let application = TestPermissionRecoveryRunningApplication(
            processIdentifier: 4101,
            isActive: false
        )
        let taskStarted = expectation(description: "Waiter task started")
        let waitTask = Task { @MainActor in
            taskStarted.fulfill()
            return await waiterOutcome(waiter, application: application)
        }

        await fulfillment(of: [taskStarted], timeout: 1)
        waitTask.cancel()
        let outcome = await waitTask.value

        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(observerRemovalCount, 1)

        postActivation(of: application, on: center)

        XCTAssertEqual(observerRemovalCount, 1)
    }

    func testEventFirstAndCancelFirstEachTransitionOnce() async {
        let eventFirstCenter = NotificationCenter()
        var eventFirstRemovalCount = 0
        let eventFirstWaiter = WorkspacePermissionRecoveryActivationWaiter(
            notificationCenter: eventFirstCenter,
            onObserverRemoved: {
                eventFirstRemovalCount += 1
            }
        )
        let eventFirstApplication = TestPermissionRecoveryRunningApplication(
            processIdentifier: 4101,
            isActive: false
        )
        let eventFirstStarted = expectation(description: "Event-first waiter task started")
        let eventFirstTask = Task { @MainActor in
            eventFirstStarted.fulfill()
            return await waiterOutcome(eventFirstWaiter, application: eventFirstApplication)
        }

        await fulfillment(of: [eventFirstStarted], timeout: 1)
        postActivation(of: eventFirstApplication, on: eventFirstCenter)
        let eventFirstOutcome = await eventFirstTask.value

        XCTAssertEqual(eventFirstOutcome, .succeeded)
        XCTAssertEqual(eventFirstRemovalCount, 1)

        let cancelFirstCenter = NotificationCenter()
        let cancelFirstRemoved = expectation(description: "Cancel-first observer removed")
        var cancelFirstRemovalCount = 0
        let cancelFirstWaiter = WorkspacePermissionRecoveryActivationWaiter(
            notificationCenter: cancelFirstCenter,
            onObserverRemoved: {
                cancelFirstRemovalCount += 1
                cancelFirstRemoved.fulfill()
            }
        )
        let cancelFirstApplication = TestPermissionRecoveryRunningApplication(
            processIdentifier: 4101,
            isActive: false
        )
        let cancelFirstStarted = expectation(description: "Cancel-first waiter task started")
        let cancelFirstTask = Task { @MainActor in
            cancelFirstStarted.fulfill()
            return await waiterOutcome(cancelFirstWaiter, application: cancelFirstApplication)
        }

        await fulfillment(of: [cancelFirstStarted], timeout: 1)
        cancelFirstTask.cancel()
        await fulfillment(of: [cancelFirstRemoved], timeout: 1)
        postActivation(of: cancelFirstApplication, on: cancelFirstCenter)
        let cancelFirstOutcome = await cancelFirstTask.value

        XCTAssertEqual(cancelFirstOutcome, .cancelled)
        XCTAssertEqual(cancelFirstRemovalCount, 1)
    }

    func testDeinitRemovesObserverAndLaterEventHasNoEffect() {
        let center = NotificationCenter()
        var observerRemovalCount = 0
        var waiter: WorkspacePermissionRecoveryActivationWaiter? =
            WorkspacePermissionRecoveryActivationWaiter(
                notificationCenter: center,
                onObserverRemoved: {
                    observerRemovalCount += 1
                }
            )
        weak let weakWaiter = waiter
        let application = TestPermissionRecoveryRunningApplication(
            processIdentifier: 4101,
            isActive: true
        )

        XCTAssertNotNil(weakWaiter)
        waiter = nil

        XCTAssertNil(weakWaiter)
        XCTAssertEqual(observerRemovalCount, 1)

        postActivation(of: application, on: center)

        XCTAssertEqual(observerRemovalCount, 1)
    }
}

@MainActor
final class PermissionRecoveryAsyncTests: XCTestCase {
    func testRecoveryWaitsForExactActivationForBothDestinations() async {
        await assertExactActivationRecovery(
            destination: .accessibility,
            appURL: URL(fileURLWithPath: "/private/tmp/SwitchTab-accessibility.app")
        )
        await assertExactActivationRecovery(
            destination: .screenRecording,
            appURL: URL(fileURLWithPath: "/private/tmp/SwitchTab-screen-recording.app")
        )
    }

    func testActivationBeforeOpenCompletionIsBuffered() async {
        let scenario = PermissionRecoveryScenario(
            appURL: URL(fileURLWithPath: "/private/tmp/SwitchTab-buffered-event.app")
        )
        let recoveryTask = scenario.start()

        await fulfillment(of: [scenario.openStarted], timeout: 1)
        scenario.workspace.postActivation(of: scenario.settingsApplication)
        scenario.workspace.completeOpen(with: .opened(scenario.settingsApplication))
        await fulfillment(of: [scenario.finderOpenStarted], timeout: 1)
        scenario.workspace.completeFinderOpen(
            with: .opened(scenario.finderApplication)
        )
        scenario.workspace.postActivation(of: scenario.finderApplication)

        let outcome = await recoveryTask.value
        let expectedResult = PermissionRecoveryResult(
            didOpenSettings: true,
            finderProcessIdentifier: scenario.finderApplication.processIdentifier,
            didActivateFinder: true
        )

        XCTAssertEqual(outcome, .succeeded(expectedResult))
        XCTAssertEqual(scenario.providerCalls, 1)
        XCTAssertEqual(scenario.workspace.waiterObserverRemovalCount, 2)
        XCTAssertEqual(scenario.workspace.revealCount, 1)
        XCTAssertEqual(scenario.workspace.finderOpenCount, 1)
        XCTAssertEqual(
            scenario.eventSink.events,
            [
                .openCompleted(processIdentifier: 4101, didOpenSettings: true),
                .settingsBecameActive(processIdentifier: 4101, alreadyActive: false),
                .finderOpenCompleted(
                    processIdentifier: 5100,
                    bundleIdentifierMatches: true,
                    canonicalURLMatches: true,
                    didOpenFinder: true
                ),
                .finderBecameActive(
                    processIdentifier: 5100,
                    alreadyActiveOrBuffered: true
                )
            ]
        )
    }

    func testAlreadyActiveApplicationsNeedNoNotification() async {
        let scenario = PermissionRecoveryScenario(
            destination: .screenRecording,
            appURL: URL(fileURLWithPath: "/private/tmp/SwitchTab-already-active.app")
        )
        scenario.settingsApplication.isActive = true
        scenario.finderApplication.isActive = true
        let recoveryTask = scenario.start()

        await fulfillment(of: [scenario.openStarted], timeout: 1)
        scenario.workspace.completeOpen(with: .opened(scenario.settingsApplication))
        await fulfillment(of: [scenario.finderOpenStarted], timeout: 1)
        scenario.workspace.completeFinderOpen(
            with: .opened(scenario.finderApplication)
        )
        let outcome = await recoveryTask.value

        XCTAssertEqual(
            outcome,
            .succeeded(
                PermissionRecoveryResult(
                    didOpenSettings: true,
                    finderProcessIdentifier: 5100,
                    didActivateFinder: true
                )
            )
        )
        XCTAssertEqual(scenario.providerCalls, 1)
        XCTAssertEqual(scenario.workspace.waiterObserverRemovalCount, 2)
        XCTAssertEqual(scenario.workspace.revealCount, 1)
        XCTAssertEqual(scenario.workspace.finderOpenCount, 1)
        XCTAssertEqual(
            scenario.eventSink.events,
            [
                .openCompleted(processIdentifier: 4101, didOpenSettings: true),
                .settingsBecameActive(processIdentifier: 4101, alreadyActive: true),
                .finderOpenCompleted(
                    processIdentifier: 5100,
                    bundleIdentifierMatches: true,
                    canonicalURLMatches: true,
                    didOpenFinder: true
                ),
                .finderBecameActive(
                    processIdentifier: 5100,
                    alreadyActiveOrBuffered: true
                )
            ]
        )
    }

    func testOpenFailureRevealsOnceAndReturnsSeparateFinderResultForBothDestinations() async {
        for destination in [
            PermissionSettingsDestination.accessibility,
            PermissionSettingsDestination.screenRecording
        ] {
            let suffix = destination == .accessibility ? "accessibility" : "screen-recording"
            let appURL = URL(fileURLWithPath: "/private/tmp/SwitchTab-\(suffix)-open-failure.app")
            let scenario = PermissionRecoveryScenario(
                destination: destination,
                appURL: appURL
            )
            let recoveryTask = scenario.start()

            await fulfillment(of: [scenario.openStarted], timeout: 1)
            scenario.workspace.completeOpen(with: .failed)
            await fulfillment(of: [scenario.finderOpenStarted], timeout: 1)
            scenario.workspace.completeFinderOpen(with: .failed)
            let expectedResult = PermissionRecoveryResult(
                didOpenSettings: false,
                finderProcessIdentifier: nil,
                didActivateFinder: false
            )
            let outcome = await recoveryTask.value

            XCTAssertEqual(outcome, .succeeded(expectedResult))
            XCTAssertEqual(scenario.providerCalls, 1)
            XCTAssertEqual(scenario.workspace.revealCount, 1)
            XCTAssertEqual(scenario.workspace.finderOpenCount, 1)
            XCTAssertEqual(scenario.workspace.waiterObserverRemovalCount, 2)
            XCTAssertEqual(
                scenario.log.events,
                [
                    .observerInstalled,
                    .openStart(destination.systemSettingsURL),
                    .openComplete(processIdentifier: nil, didOpenSettings: false),
                    .observerRemoved,
                    .reveal([appURL]),
                    .observerInstalled,
                    .finderOpenStart,
                    .observerRemoved,
                    .recoverResult(expectedResult)
                ]
            )
            XCTAssertEqual(
                scenario.eventSink.events,
                [
                    .openCompleted(processIdentifier: nil, didOpenSettings: false),
                    .finderOpenCompleted(
                        processIdentifier: nil,
                        bundleIdentifierMatches: false,
                        canonicalURLMatches: false,
                        didOpenFinder: false
                    )
                ]
            )
        }
    }

    func testSettingsOpenFailurePreservesSuccessfulFinderHandoffResult() async {
        let appURL = URL(fileURLWithPath: "/private/tmp/SwitchTab-settings-open-failure-finder-success.app")
        let scenario = PermissionRecoveryScenario(appURL: appURL)
        let recoveryTask = scenario.start()

        await fulfillment(of: [scenario.openStarted], timeout: 1)
        scenario.workspace.completeOpen(with: .failed)
        await fulfillment(of: [scenario.finderOpenStarted], timeout: 1)
        scenario.workspace.completeFinderOpen(
            with: .opened(scenario.finderApplication)
        )
        await fulfillment(of: [scenario.finderWaitStarted], timeout: 1)
        scenario.workspace.postActivation(of: scenario.finderApplication)

        let expectedResult = PermissionRecoveryResult(
            didOpenSettings: false,
            finderProcessIdentifier: scenario.finderApplication.processIdentifier,
            didActivateFinder: true
        )
        let outcome = await recoveryTask.value

        XCTAssertEqual(outcome, .succeeded(expectedResult))
        XCTAssertFalse(expectedResult.didOpenSettings)
        XCTAssertEqual(expectedResult.finderProcessIdentifier, 5100)
        XCTAssertTrue(expectedResult.didActivateFinder)
        XCTAssertEqual(scenario.providerCalls, 1)
        XCTAssertEqual(scenario.workspace.revealCount, 1)
        XCTAssertEqual(scenario.workspace.finderOpenCount, 1)
        XCTAssertEqual(scenario.workspace.waiterObserverRemovalCount, 2)
        XCTAssertEqual(
            scenario.log.events,
            [
                .observerInstalled,
                .openStart(scenario.destination.systemSettingsURL),
                .openComplete(processIdentifier: nil, didOpenSettings: false),
                .observerRemoved,
                .reveal([appURL]),
                .observerInstalled,
                .finderOpenStart,
                .observerRemoved,
                .recoverResult(expectedResult)
            ]
        )
        XCTAssertEqual(
            scenario.eventSink.events,
            [
                .openCompleted(processIdentifier: nil, didOpenSettings: false),
                .finderOpenCompleted(
                    processIdentifier: 5100,
                    bundleIdentifierMatches: true,
                    canonicalURLMatches: true,
                    didOpenFinder: true
                ),
                .finderBecameActive(
                    processIdentifier: 5100,
                    alreadyActiveOrBuffered: false
                )
            ]
        )

        scenario.workspace.postActivation(of: scenario.finderApplication)

        XCTAssertEqual(scenario.workspace.revealCount, 1)
        XCTAssertEqual(scenario.workspace.finderOpenCount, 1)
        XCTAssertEqual(scenario.workspace.waiterObserverRemovalCount, 2)
        XCTAssertEqual(scenario.eventSink.events.count, 3)
    }

    func testWrongFinderIdentityDoesNotActivateOrRetry() async {
        let cases: [(String?, URL?, Bool, Bool)] = [
            ("com.example.not-finder", URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"), false, true),
            ("com.apple.finder", URL(fileURLWithPath: "/private/tmp/not-finder.app"), true, false)
        ]

        for (bundleIdentifier, bundleURL, expectedBundleMatch, expectedURLMatch) in cases {
            let scenario = PermissionRecoveryScenario(
                appURL: URL(fileURLWithPath: "/private/tmp/SwitchTab-wrong-finder.app"),
                finderApplication: TestPermissionRecoveryRunningApplication(
                    processIdentifier: 5300,
                    isActive: true,
                    bundleIdentifier: bundleIdentifier,
                    bundleURL: bundleURL
                )
            )
            scenario.settingsApplication.isActive = true
            let recoveryTask = scenario.start()

            await fulfillment(of: [scenario.openStarted], timeout: 1)
            scenario.workspace.completeOpen(with: .opened(scenario.settingsApplication))
            await fulfillment(of: [scenario.finderOpenStarted], timeout: 1)
            scenario.workspace.completeFinderOpen(
                with: .opened(scenario.finderApplication)
            )
            let outcome = await recoveryTask.value

            XCTAssertEqual(
                outcome,
                .succeeded(
                    PermissionRecoveryResult(
                        didOpenSettings: true,
                        finderProcessIdentifier: nil,
                        didActivateFinder: false
                    )
                )
            )
            XCTAssertEqual(scenario.workspace.revealCount, 1)
            XCTAssertEqual(scenario.workspace.finderOpenCount, 1)
            XCTAssertEqual(scenario.workspace.waiterObserverRemovalCount, 2)
            XCTAssertEqual(
                scenario.eventSink.events.last,
                .finderOpenCompleted(
                    processIdentifier: 5300,
                    bundleIdentifierMatches: expectedBundleMatch,
                    canonicalURLMatches: expectedURLMatch,
                    didOpenFinder: false
                )
            )
        }
    }

    func testCancellingPendingOpenThrowsAndIgnoresLateCallbackAndEvent() async {
        let scenario = PermissionRecoveryScenario(
            appURL: URL(fileURLWithPath: "/private/tmp/SwitchTab-cancelled-open.app")
        )
        let recoveryTask = scenario.start()

        await fulfillment(of: [scenario.openStarted], timeout: 1)
        recoveryTask.cancel()
        let outcome = await recoveryTask.value

        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(scenario.workspace.waiterObserverRemovalCount, 1)
        XCTAssertEqual(scenario.workspace.revealCount, 0)
        XCTAssertEqual(scenario.workspace.finderOpenCount, 0)
        XCTAssertTrue(scenario.eventSink.events.isEmpty)

        let lateApplication = TestPermissionRecoveryRunningApplication(
            processIdentifier: 4101,
            isActive: true
        )
        scenario.workspace.completeOpen(with: .opened(lateApplication))
        scenario.workspace.postActivation(of: lateApplication)

        XCTAssertEqual(scenario.workspace.waiterObserverRemovalCount, 1)
        XCTAssertEqual(scenario.workspace.revealCount, 0)
        XCTAssertEqual(scenario.workspace.finderOpenCount, 0)
        XCTAssertFalse(scenario.log.events.contains { event in
            if case .recoverResult = event {
                return true
            }
            return false
        })
    }

    func testCancellingActivationWaitThrowsAndIgnoresLateExactEvent() async {
        let scenario = PermissionRecoveryScenario(
            destination: .screenRecording,
            appURL: URL(fileURLWithPath: "/private/tmp/SwitchTab-cancelled-activation.app"),
            waitsForActivation: true
        )
        let recoveryTask = scenario.start()

        await fulfillment(of: [scenario.openStarted], timeout: 1)
        scenario.workspace.completeOpen(with: .opened(scenario.settingsApplication))
        if let waitStarted = scenario.waitStarted {
            await fulfillment(of: [waitStarted], timeout: 1)
        }

        recoveryTask.cancel()
        let outcome = await recoveryTask.value

        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(scenario.workspace.waiterObserverRemovalCount, 1)
        XCTAssertEqual(scenario.workspace.revealCount, 0)
        XCTAssertEqual(scenario.workspace.finderOpenCount, 0)
        XCTAssertEqual(
            scenario.eventSink.events,
            [.openCompleted(processIdentifier: 4101, didOpenSettings: true)]
        )

        scenario.workspace.postActivation(of: scenario.settingsApplication)

        XCTAssertEqual(scenario.workspace.waiterObserverRemovalCount, 1)
        XCTAssertEqual(scenario.workspace.revealCount, 0)
        XCTAssertEqual(scenario.workspace.finderOpenCount, 0)
    }

    func testCancellingAfterSettingsActivationBeforeYieldPreventsFinderHandoff() async {
        let scenario = PermissionRecoveryScenario(
            appURL: URL(fileURLWithPath: "/private/tmp/SwitchTab-cancelled-after-settings-activation.app"),
            waitsForActivation: true
        )
        let recoveryTask = scenario.start()

        await fulfillment(of: [scenario.openStarted], timeout: 1)
        scenario.workspace.completeOpen(with: .opened(scenario.settingsApplication))
        if let waitStarted = scenario.waitStarted {
            await fulfillment(of: [waitStarted], timeout: 1)
        }

        scenario.workspace.postActivation(of: scenario.settingsApplication)
        recoveryTask.cancel()
        let outcome = await recoveryTask.value

        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(scenario.workspace.waiterObserverRemovalCount, 1)
        XCTAssertEqual(scenario.workspace.revealCount, 0)
        XCTAssertEqual(scenario.workspace.finderOpenCount, 0)
        XCTAssertEqual(
            scenario.eventSink.events,
            [.openCompleted(processIdentifier: 4101, didOpenSettings: true)]
        )
        XCTAssertEqual(
            scenario.log.events,
            [
                .observerInstalled,
                .openStart(scenario.destination.systemSettingsURL),
                .openComplete(processIdentifier: 4101, didOpenSettings: true),
                .observerRemoved
            ]
        )

        scenario.workspace.postActivation(of: scenario.settingsApplication)

        XCTAssertEqual(scenario.workspace.waiterObserverRemovalCount, 1)
        XCTAssertEqual(scenario.workspace.revealCount, 0)
        XCTAssertEqual(scenario.workspace.finderOpenCount, 0)
        XCTAssertEqual(
            scenario.eventSink.events,
            [.openCompleted(processIdentifier: 4101, didOpenSettings: true)]
        )
        XCTAssertEqual(scenario.log.events.count, 4)
    }

    func testFinderActivationBeforeOpenCompletionIsBuffered() async {
        let scenario = PermissionRecoveryScenario(
            appURL: URL(fileURLWithPath: "/private/tmp/SwitchTab-finder-buffered-event.app")
        )
        scenario.settingsApplication.isActive = true
        let recoveryTask = scenario.start()

        await fulfillment(of: [scenario.openStarted], timeout: 1)
        scenario.workspace.completeOpen(with: .opened(scenario.settingsApplication))
        await fulfillment(of: [scenario.finderOpenStarted], timeout: 1)
        scenario.workspace.postActivation(of: scenario.finderApplication)
        scenario.workspace.completeFinderOpen(
            with: .opened(scenario.finderApplication)
        )

        let outcome = await recoveryTask.value

        XCTAssertEqual(
            outcome,
            .succeeded(
                PermissionRecoveryResult(
                    didOpenSettings: true,
                    finderProcessIdentifier: 5100,
                    didActivateFinder: true
                )
            )
        )
        XCTAssertEqual(
            scenario.eventSink.events.last,
            .finderBecameActive(
                processIdentifier: 5100,
                alreadyActiveOrBuffered: true
            )
        )
    }

    func testCancellingPendingFinderOpenAllowsOneHandoffAndIgnoresLateCallbacks() async {
        let scenario = PermissionRecoveryScenario(
            appURL: URL(fileURLWithPath: "/private/tmp/SwitchTab-cancelled-finder-open.app")
        )
        scenario.settingsApplication.isActive = true
        let recoveryTask = scenario.start()

        await fulfillment(of: [scenario.openStarted], timeout: 1)
        scenario.workspace.completeOpen(with: .opened(scenario.settingsApplication))
        await fulfillment(of: [scenario.finderOpenStarted], timeout: 1)

        recoveryTask.cancel()
        let outcome = await recoveryTask.value

        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(scenario.workspace.revealCount, 1)
        XCTAssertEqual(scenario.workspace.finderOpenCount, 1)
        XCTAssertEqual(scenario.workspace.waiterObserverRemovalCount, 2)
        XCTAssertEqual(
            scenario.eventSink.events,
            [
                .openCompleted(processIdentifier: 4101, didOpenSettings: true),
                .settingsBecameActive(processIdentifier: 4101, alreadyActive: true)
            ]
        )

        scenario.workspace.completeFinderOpen(
            with: .opened(scenario.finderApplication)
        )
        scenario.workspace.postActivation(of: scenario.finderApplication)

        XCTAssertEqual(scenario.workspace.revealCount, 1)
        XCTAssertEqual(scenario.workspace.finderOpenCount, 1)
        XCTAssertEqual(scenario.workspace.waiterObserverRemovalCount, 2)
        XCTAssertFalse(scenario.log.events.contains { event in
            if case .recoverResult = event {
                return true
            }
            return false
        })
    }

    private func assertExactActivationRecovery(
        destination: PermissionSettingsDestination,
        appURL: URL
    ) async {
        let scenario = PermissionRecoveryScenario(
            destination: destination,
            appURL: appURL,
            waitsForActivation: true
        )
        let recoveryTask = scenario.start()

        await fulfillment(of: [scenario.openStarted], timeout: 1)

        XCTAssertEqual(
            Array(scenario.log.events.prefix(2)),
            [.observerInstalled, .openStart(destination.systemSettingsURL)]
        )
        XCTAssertEqual(scenario.providerCalls, 1)
        XCTAssertEqual(scenario.workspace.revealCount, 0)
        XCTAssertEqual(scenario.workspace.finderOpenCount, 0)

        scenario.workspace.completeOpen(with: .opened(scenario.settingsApplication))
        if let waitStarted = scenario.waitStarted {
            await fulfillment(of: [waitStarted], timeout: 1)
        }

        XCTAssertEqual(scenario.workspace.revealCount, 0)
        XCTAssertEqual(scenario.workspace.finderOpenCount, 0)

        scenario.workspace.postActivation(of: scenario.wrongPIDApplication)
        XCTAssertEqual(scenario.workspace.revealCount, 0)
        XCTAssertEqual(scenario.workspace.finderOpenCount, 0)

        scenario.workspace.postActivation(of: scenario.settingsApplication)
        await fulfillment(of: [scenario.finderOpenStarted], timeout: 1)

        XCTAssertEqual(scenario.workspace.revealCount, 1)
        XCTAssertEqual(scenario.workspace.finderOpenCount, 1)
        XCTAssertEqual(
            Array(scenario.log.events.suffix(2)),
            [.observerInstalled, .finderOpenStart]
        )

        scenario.workspace.completeFinderOpen(
            with: .opened(scenario.finderApplication)
        )
        await fulfillment(of: [scenario.finderWaitStarted], timeout: 1)
        scenario.workspace.postActivation(of: scenario.wrongFinderApplication)
        XCTAssertEqual(scenario.workspace.finderOpenCount, 1)
        scenario.workspace.postActivation(of: scenario.finderApplication)

        let expectedResult = PermissionRecoveryResult(
            didOpenSettings: true,
            finderProcessIdentifier: 5100,
            didActivateFinder: true
        )
        let outcome = await recoveryTask.value

        XCTAssertEqual(outcome, .succeeded(expectedResult))
        XCTAssertEqual(scenario.providerCalls, 1)
        XCTAssertEqual(scenario.workspace.revealCount, 1)
        XCTAssertEqual(scenario.workspace.finderOpenCount, 1)
        XCTAssertEqual(scenario.workspace.waiterObserverRemovalCount, 2)
        XCTAssertEqual(
            scenario.log.events,
            [
                .observerInstalled,
                .openStart(destination.systemSettingsURL),
                .openComplete(processIdentifier: 4101, didOpenSettings: true),
                .observerRemoved,
                .reveal([appURL]),
                .observerInstalled,
                .finderOpenStart,
                .observerRemoved,
                .recoverResult(expectedResult)
            ]
        )
        XCTAssertEqual(
            scenario.eventSink.events,
            [
                .openCompleted(processIdentifier: 4101, didOpenSettings: true),
                .settingsBecameActive(processIdentifier: 4101, alreadyActive: false),
                .finderOpenCompleted(
                    processIdentifier: 5100,
                    bundleIdentifierMatches: true,
                    canonicalURLMatches: true,
                    didOpenFinder: true
                ),
                .finderBecameActive(
                    processIdentifier: 5100,
                    alreadyActiveOrBuffered: false
                )
            ]
        )
    }
}

@MainActor
private final class PermissionRecoveryScenario {
    let destination: PermissionSettingsDestination
    let appURL: URL
    let settingsApplication: TestPermissionRecoveryRunningApplication
    let wrongPIDApplication: TestPermissionRecoveryRunningApplication
    let finderApplication: TestPermissionRecoveryRunningApplication
    let wrongFinderApplication: TestPermissionRecoveryRunningApplication
    let openStarted: XCTestExpectation
    let finderOpenStarted: XCTestExpectation
    let waitStarted: XCTestExpectation?
    let finderWaitStarted: XCTestExpectation
    let log: RecoveryTestLog
    let eventSink: RecordingPermissionRecoveryEventSink
    let workspace: ControllablePermissionRecoveryWorkspace

    private let applicationURLProvider: RecoveryApplicationURLProvider
    private let coordinator: PermissionRecoveryCoordinator

    var providerCalls: Int {
        applicationURLProvider.callCount
    }

    init(
        destination: PermissionSettingsDestination = .accessibility,
        appURL: URL,
        settingsApplication: TestPermissionRecoveryRunningApplication =
            TestPermissionRecoveryRunningApplication(
                processIdentifier: 4101,
                isActive: false
            ),
        finderApplication: TestPermissionRecoveryRunningApplication =
            TestPermissionRecoveryRunningApplication(
                processIdentifier: 5100,
                isActive: false,
                bundleIdentifier: "com.apple.finder",
                bundleURL: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
            ),
        waitsForActivation: Bool = false
    ) {
        self.destination = destination
        self.appURL = appURL
        self.settingsApplication = settingsApplication
        wrongPIDApplication = TestPermissionRecoveryRunningApplication(
            processIdentifier: settingsApplication.processIdentifier + 1,
            isActive: true
        )
        self.finderApplication = finderApplication
        wrongFinderApplication = TestPermissionRecoveryRunningApplication(
            processIdentifier: finderApplication.processIdentifier + 1,
            isActive: true,
            bundleIdentifier: finderApplication.bundleIdentifier,
            bundleURL: finderApplication.bundleURL
        )
        openStarted = XCTestExpectation(
            description: "Settings open started for \(destination)"
        )
        finderOpenStarted = XCTestExpectation(description: "Finder open started")
        finderWaitStarted = XCTestExpectation(description: "Exact Finder activation wait started")
        waitStarted = waitsForActivation
            ? XCTestExpectation(description: "Exact Settings activation wait started")
            : nil
        log = RecoveryTestLog()
        eventSink = RecordingPermissionRecoveryEventSink()
        workspace = ControllablePermissionRecoveryWorkspace(
            notificationCenter: NotificationCenter(),
            log: log,
            openStarted: openStarted,
            waitStarted: waitStarted,
            finderWaitStarted: finderWaitStarted,
            finderOpenStarted: finderOpenStarted
        )
        let provider = RecoveryApplicationURLProvider(appURL: appURL)
        applicationURLProvider = provider
        coordinator = PermissionRecoveryCoordinator(
            workspace: workspace,
            applicationURL: { provider.value() },
            eventSink: eventSink
        )
    }

    func start() -> Task<RecoveryTaskOutcome, Never> {
        let recoveryCoordinator = coordinator
        let recoveryDestination = destination
        let recoveryWorkspace = workspace
        return Task { @MainActor in
            do {
                let result = try await recoveryCoordinator.recover(recoveryDestination)
                recoveryWorkspace.recordRecoverResult(result)
                return .succeeded(result)
            } catch is CancellationError {
                return .cancelled
            } catch {
                return .otherFailure
            }
        }
    }
}

@MainActor
private final class RecoveryApplicationURLProvider {
    private let appURL: URL
    private(set) var callCount = 0

    init(appURL: URL) {
        self.appURL = appURL
    }

    func value() -> URL {
        callCount += 1
        return appURL
    }
}

private enum WaiterOutcome: Equatable, Sendable {
    case succeeded
    case cancelled
    case otherFailure
}

private enum RecoveryTaskOutcome: Equatable, Sendable {
    case succeeded(PermissionRecoveryResult)
    case cancelled
    case otherFailure
}

@MainActor
private func waiterOutcome(
    _ waiter: WorkspacePermissionRecoveryActivationWaiter,
    application: TestPermissionRecoveryRunningApplication
) async -> WaiterOutcome {
    do {
        _ = try await waiter.waitUntilActive(application)
        return .succeeded
    } catch is CancellationError {
        return .cancelled
    } catch {
        return .otherFailure
    }
}

@MainActor
private func postActivation(
    of application: TestPermissionRecoveryRunningApplication,
    on notificationCenter: NotificationCenter
) {
    notificationCenter.post(
        name: NSWorkspace.didActivateApplicationNotification,
        object: nil,
        userInfo: [NSWorkspace.applicationUserInfoKey: application]
    )
}

@MainActor
private final class TestPermissionRecoveryRunningApplication:
    PermissionRecoveryRunningApplication
{
    let processIdentifier: pid_t
    var isActive: Bool
    let bundleIdentifier: String?
    let bundleURL: URL?

    init(
        processIdentifier: pid_t,
        isActive: Bool,
        bundleIdentifier: String? = nil,
        bundleURL: URL? = nil
    ) {
        self.processIdentifier = processIdentifier
        self.isActive = isActive
        self.bundleIdentifier = bundleIdentifier
        self.bundleURL = bundleURL
    }
}

@MainActor
private final class RecordingPermissionRecoveryEventSink: PermissionRecoveryEventSink {
    private(set) var events: [PermissionRecoveryEvent] = []

    func record(_ event: PermissionRecoveryEvent) {
        events.append(event)
    }
}

@MainActor
private final class RecoveryTestLog {
    var events: [RecoveryTestEvent] = []
}

private enum RecoveryTestEvent: Equatable {
    case observerInstalled
    case openStart(URL)
    case openComplete(processIdentifier: pid_t?, didOpenSettings: Bool)
    case observerRemoved
    case reveal([URL])
    case finderOpenStart
    case recoverResult(PermissionRecoveryResult)
}

@MainActor
private final class RecoveryActivationWaiterProbe: PermissionRecoveryActivationWaiter {
    private let waiter: any PermissionRecoveryActivationWaiter
    private let onWait: @MainActor () -> Void

    init(
        waiter: any PermissionRecoveryActivationWaiter,
        onWait: @escaping @MainActor () -> Void
    ) {
        self.waiter = waiter
        self.onWait = onWait
    }

    func waitUntilActive(
        _ application: any PermissionRecoveryRunningApplication
    ) async throws -> Bool {
        onWait()
        return try await waiter.waitUntilActive(application)
    }

    func cancel() {
        waiter.cancel()
    }
}

@MainActor
private final class ControllablePermissionRecoveryWorkspace: PermissionRecoveryWorkspace {
    private let notificationCenter: NotificationCenter
    private let log: RecoveryTestLog
    private let openStarted: XCTestExpectation
    private let finderOpenStarted: XCTestExpectation
    private let waitStarted: XCTestExpectation?
    private let finderWaitStarted: XCTestExpectation
    private let openBridge = PermissionRecoveryApplicationOpenBridge()
    private var openCompletion: PermissionRecoveryApplicationOpenBridge.Completion?
    private let finderOpenBridge = PermissionRecoveryApplicationOpenBridge()
    private var finderOpenCompletion: PermissionRecoveryApplicationOpenBridge.Completion?
    private var waiterCount = 0
    private(set) var waiterObserverRemovalCount = 0

    init(
        notificationCenter: NotificationCenter,
        log: RecoveryTestLog,
        openStarted: XCTestExpectation,
        waitStarted: XCTestExpectation? = nil,
        finderWaitStarted: XCTestExpectation,
        finderOpenStarted: XCTestExpectation
    ) {
        self.notificationCenter = notificationCenter
        self.log = log
        self.openStarted = openStarted
        self.waitStarted = waitStarted
        self.finderWaitStarted = finderWaitStarted
        self.finderOpenStarted = finderOpenStarted
    }

    var revealCount: Int {
        log.events.reduce(into: 0) { count, event in
            if case .reveal = event {
                count += 1
            }
        }
    }

    var finderOpenCount: Int {
        log.events.reduce(into: 0) { count, event in
            if case .finderOpenStart = event {
                count += 1
            }
        }
    }

    func makeActivationWaiter() -> any PermissionRecoveryActivationWaiter {
        waiterCount += 1
        let waiter = WorkspacePermissionRecoveryActivationWaiter(
            notificationCenter: notificationCenter,
            onObserverRemoved: { [weak self] in
                guard let self else {
                    return
                }
                waiterObserverRemovalCount += 1
                log.events.append(.observerRemoved)
            }
        )
        log.events.append(.observerInstalled)
        if waiterCount == 1, let waitStarted {
            return RecoveryActivationWaiterProbe(waiter: waiter) {
                waitStarted.fulfill()
            }
        }
        if waiterCount == 2 {
            return RecoveryActivationWaiterProbe(waiter: waiter) {
                self.finderWaitStarted.fulfill()
            }
        }
        return waiter
    }

    func openSettings(
        _ url: URL
    ) async throws -> PermissionRecoveryApplicationOpenResult {
        log.events.append(.openStart(url))
        openStarted.fulfill()
        return try await openBridge.wait { [weak self] completion in
            self?.openCompletion = completion
        }
    }

    func completeOpen(with result: PermissionRecoveryApplicationOpenResult) {
        let processIdentifier: pid_t?
        let didOpenSettings: Bool
        switch result {
        case .opened(let application):
            processIdentifier = application.processIdentifier
            didOpenSettings = true
        case .failed:
            processIdentifier = nil
            didOpenSettings = false
        }
        log.events.append(
            .openComplete(
                processIdentifier: processIdentifier,
                didOpenSettings: didOpenSettings
            )
        )
        guard let openCompletion else {
            XCTFail("Expected an installed AppKit-style open completion")
            return
        }
        openCompletion(result)
    }

    func openFinder() async throws -> PermissionRecoveryApplicationOpenResult {
        log.events.append(.finderOpenStart)
        finderOpenStarted.fulfill()
        return try await finderOpenBridge.wait { [weak self] completion in
            self?.finderOpenCompletion = completion
        }
    }

    func completeFinderOpen(with result: PermissionRecoveryApplicationOpenResult) {
        guard let finderOpenCompletion else {
            XCTFail("Expected an installed Finder open completion")
            return
        }
        finderOpenCompletion(result)
    }

    func postActivation(of application: TestPermissionRecoveryRunningApplication) {
        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: application]
        )
    }

    func activateFileViewerSelecting(_ fileURLs: [URL]) {
        log.events.append(.reveal(fileURLs))
    }

    func recordRecoverResult(_ result: PermissionRecoveryResult) {
        log.events.append(.recoverResult(result))
    }
}
