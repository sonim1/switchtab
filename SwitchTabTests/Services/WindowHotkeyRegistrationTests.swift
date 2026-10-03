@testable import SwitchTab
import XCTest

final class WindowHotkeyRegistrationTests: XCTestCase {
    private static let windowReverse = ShortcutSetting.defaultCurrentAppWindowSwitching
        .reverseVariant(id: "current-app-window-switching-reverse")

    @MainActor
    func testForwardFailureLeavesNeitherDirectionRegistered() {
        let registrar = ApplicationSwitchingRecordingRegistrar { $0.modifiers.contains("shift") }
        let service = HotkeyService(registrar: registrar)
        var invocations = 0

        XCTAssertFalse(WindowSwitchingHotkeyController(hotkeyService: service).register(
            setting: .defaultCurrentAppWindowSwitching,
            configurations: [],
            forwardHandler: { invocations += 1 },
            reverseHandler: { invocations += 1 }
        ))
        registrar.invoke(settingID: Self.windowReverse.id)

        XCTAssertEqual(invocations, 0)
        XCTAssertEqual(service.registeredSettings(for: .currentAppWindowSwitching), [])
        XCTAssertEqual(service.registrationMessageSnapshot(), failedMessages(
            for: .defaultCurrentAppWindowSwitching,
            fallback: .fallbackCurrentAppWindowSwitching
        ))
    }

    @MainActor
    func testFallbackReverseFailureDiscardsPartialPairAndFallbackNotice() {
        let registrar = ApplicationSwitchingRecordingRegistrar {
            $0 == .fallbackCurrentAppWindowSwitching
        }
        let service = HotkeyService(registrar: registrar)
        var invocations = 0

        XCTAssertFalse(WindowSwitchingHotkeyController(hotkeyService: service).register(
            setting: .defaultCurrentAppWindowSwitching,
            configurations: [],
            forwardHandler: { invocations += 1 },
            reverseHandler: { invocations += 1 }
        ))
        registrar.invoke(settingID: ShortcutSetting.fallbackCurrentAppWindowSwitching.id)

        XCTAssertEqual(invocations, 0)
        XCTAssertEqual(registrar.unregisterAllCallCount, 1)
        XCTAssertEqual(service.registeredSettings(for: .currentAppWindowSwitching), [])
        XCTAssertEqual(service.registrationMessageSnapshot(), failedMessages(
            for: Self.windowReverse,
            fallback: .fallbackCurrentAppWindowSwitchingReverse
        ))
    }

    @MainActor
    func testExactReverseFailureDiscardsPartialPair() {
        let registrar = ApplicationSwitchingRecordingRegistrar { !$0.modifiers.contains("shift") }
        let service = HotkeyService(registrar: registrar)
        var invocations = 0

        XCTAssertFalse(WindowSwitchingHotkeyController(hotkeyService: service).restore(
            snapshot: snapshot(settings: [
                .defaultCurrentAppWindowSwitching,
                Self.windowReverse
            ]),
            configuredSetting: .defaultCurrentAppWindowSwitching,
            configurations: [],
            forwardHandler: { invocations += 1 },
            reverseHandler: { invocations += 1 }
        ))
        registrar.invoke(settingID: ShortcutSetting.defaultCurrentAppWindowSwitching.id)

        XCTAssertEqual(invocations, 0)
        XCTAssertEqual(registrar.unregisterAllCallCount, 1)
        XCTAssertEqual(service.registeredSettings(for: .currentAppWindowSwitching), [])
        XCTAssertEqual(service.registrationMessageSnapshot(), failedMessages(
            for: Self.windowReverse
        ))
    }

    @MainActor
    func testFallbackRegistrationKeepsDistinctDirectionHandlers() {
        let registrar = ApplicationSwitchingRecordingRegistrar {
            $0 != Self.windowReverse
        }
        let service = HotkeyService(registrar: registrar)
        var invocations: [String] = []

        XCTAssertTrue(WindowSwitchingHotkeyController(hotkeyService: service).register(
            setting: .defaultCurrentAppWindowSwitching,
            configurations: [],
            forwardHandler: { invocations.append("forward") },
            reverseHandler: { invocations.append("reverse") }
        ))
        registrar.invoke(settingID: ShortcutSetting.defaultCurrentAppWindowSwitching.id)
        registrar.invoke(settingID: ShortcutSetting.fallbackCurrentAppWindowSwitchingReverse.id)

        XCTAssertEqual(invocations, ["forward", "reverse"])
        XCTAssertEqual(service.registeredSettings(for: .currentAppWindowSwitching), [
            .defaultCurrentAppWindowSwitching,
            .fallbackCurrentAppWindowSwitchingReverse
        ])
        XCTAssertEqual(service.registrationMessageSnapshot().count, 1)
        XCTAssertEqual(registrar.unregisterAllCallCount, 0)
    }

    @MainActor
    func testExactRestoreKeepsMixedPairAndItsDiagnostic() {
        let previousService = HotkeyService(registrar: ApplicationSwitchingRecordingRegistrar {
            $0 != Self.windowReverse
        })
        XCTAssertTrue(WindowSwitchingHotkeyController(hotkeyService: previousService).register(
            setting: .defaultCurrentAppWindowSwitching,
            configurations: [],
            forwardHandler: {},
            reverseHandler: {}
        ))
        let previous = previousService.registrationSnapshot(
            for: .currentAppWindowSwitching,
            expectedEnabled: true
        )
        let registrar = ApplicationSwitchingRecordingRegistrar()
        let service = HotkeyService(registrar: registrar)
        var invocations: [String] = []

        XCTAssertTrue(WindowSwitchingHotkeyController(hotkeyService: service).restore(
            snapshot: previous,
            configuredSetting: .defaultCurrentAppWindowSwitching,
            configurations: [],
            forwardHandler: { invocations.append("forward") },
            reverseHandler: { invocations.append("reverse") }
        ))
        registrar.invoke(settingID: ShortcutSetting.defaultCurrentAppWindowSwitching.id)
        registrar.invoke(settingID: ShortcutSetting.fallbackCurrentAppWindowSwitchingReverse.id)

        XCTAssertEqual(invocations, ["forward", "reverse"])
        XCTAssertEqual(service.registrationSnapshot(for: .currentAppWindowSwitching, expectedEnabled: true), previous)
        XCTAssertEqual(registrar.attemptedSettings, previous.settings)
    }

    @MainActor
    func testInvalidSnapshotDoesNotInstallAnyHandlers() {
        let registrar = ApplicationSwitchingRecordingRegistrar()
        let service = HotkeyService(registrar: registrar)
        let invalid = HotkeyRegistrationSnapshot(
            mode: .currentAppWindowSwitching,
            expectedEnabled: true,
            settings: [.defaultCurrentAppWindowSwitching, Self.windowReverse],
            registrationMessages: [ShortcutRegistrationMessage(
                mode: .applicationSwitching,
                message: ApplicationSwitchingHotkeyController.registrationFailureMessage
            )]
        )

        XCTAssertFalse(WindowSwitchingHotkeyController(hotkeyService: service).restore(
            snapshot: invalid,
            configuredSetting: .defaultCurrentAppWindowSwitching,
            configurations: [],
            forwardHandler: {},
            reverseHandler: {}
        ))

        XCTAssertEqual(registrar.attemptedSettings, [])
        XCTAssertEqual(service.registeredSettings(for: .currentAppWindowSwitching), [])
    }

    @MainActor
    func testDisabledSnapshotClearsLivePair() {
        let registrar = ApplicationSwitchingRecordingRegistrar()
        let service = HotkeyService(registrar: registrar)
        let controller = WindowSwitchingHotkeyController(hotkeyService: service)
        XCTAssertTrue(controller.register(
            setting: .defaultCurrentAppWindowSwitching,
            configurations: [],
            forwardHandler: {},
            reverseHandler: {}
        ))

        XCTAssertTrue(controller.restore(
            snapshot: HotkeyRegistrationSnapshot(
                mode: .currentAppWindowSwitching,
                expectedEnabled: false,
                settings: [],
                registrationMessages: []
            ),
            configuredSetting: .defaultCurrentAppWindowSwitching,
            configurations: [],
            forwardHandler: {},
            reverseHandler: {}
        ))

        XCTAssertEqual(service.registeredSettings(for: .currentAppWindowSwitching), [])
        XCTAssertEqual(registrar.unregisterAllCallCount, 1)
    }

    private func snapshot(settings: [ShortcutSetting]) -> HotkeyRegistrationSnapshot {
        HotkeyRegistrationSnapshot(
            mode: .currentAppWindowSwitching,
            expectedEnabled: true,
            settings: settings,
            registrationMessages: []
        )
    }

    private func failedMessages(
        for setting: ShortcutSetting,
        fallback: ShortcutSetting? = nil
    ) -> [ShortcutRegistrationMessage] {
        let service = HotkeyService(registrar: RejectingHotkeyRegistrar())
        if let fallback {
            _ = service.registerFirstUsable(
                primaryCandidate: setting,
                fallbackCandidate: fallback,
                existing: [] as [ShortcutSetting],
                mode: .currentAppWindowSwitching,
                handler: {}
            )
        } else {
            _ = service.register(
                setting: setting,
                existing: [] as [ShortcutSetting],
                mode: .currentAppWindowSwitching,
                handler: {}
            )
        }
        return service.registrationMessageSnapshot()
    }
}
