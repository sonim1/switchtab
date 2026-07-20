import CoreGraphics
@testable import SwitchTab

@MainActor
enum HotkeyServiceTests {
    static func run() throws {
        try testFallbackRegistrationRecordsWarningWhenRequestedShortcutUnavailable()
        try testExactRegistrationDoesNotUseFallbackWhenRequestedShortcutIsUnavailable()
        try testSameModeForwardAndReverseHotkeysCanHaveSeparateHandlers()
        try testModeInvocationKeepsFirstRegisteredSettingWhenHandlerIsUpdated()
        try testPreferredRegistrarUsesPrimaryBeforeFallback()
        try testPreferredRegistrarFallsBackWhenPrimaryRejectsShortcut()
        try testPreferredRegistrarPrimaryAndFallbackOrderedChainsCoexist()
        try testUnregisterAllSkipsRegistrarWhenAlreadyClean()
        try testUnregisterAllClearsMessagesWithoutRegistrarWhenNoHotkeysRegistered()
    }

    static func testFallbackRegistrationRecordsWarningWhenRequestedShortcutUnavailable() throws {
        let registrar = SelectivelyFailingHotkeyRegistrar(blockedDisplayText: "Cmd + `")
        let service = HotkeyService(registrar: registrar)

        let result = service.registerFirstUsable(
            primaryCandidate: .defaultCurrentAppWindowSwitching,
            fallbackCandidate: .fallbackCurrentAppWindowSwitching,
            existing: [.defaultCurrentAppWindowSwitching],
            mode: .currentAppWindowSwitching
        ) {}

        try expectEqual(result, .registered)
        try expectEqual(service.registeredSetting(for: .currentAppWindowSwitching)?.displayText, "Option + Ctrl + `")
        let registrationMessages = service.registrationMessageSnapshot()
        try expectEqual(registrationMessages.first?.mode, .currentAppWindowSwitching)
        try expectTrue(registrationMessages.first?.message.contains("Cmd + `") == true)
        try expectTrue(registrationMessages.first?.message.contains("Option + Ctrl + `") == true)
    }

    static func testExactRegistrationDoesNotUseFallbackWhenRequestedShortcutIsUnavailable() throws {
        let registrar = SelectivelyFailingHotkeyRegistrar(blockedDisplayText: "Cmd + `")
        let service = HotkeyService(registrar: registrar)

        let result = service.register(
            setting: .defaultCurrentAppWindowSwitching,
            existing: [] as [ShortcutSetting],
            mode: .currentAppWindowSwitching
        ) {}

        try expectEqual(result, .noUsableShortcut)
        try expectEqual(service.registeredSetting(for: .currentAppWindowSwitching), nil)
        try expectEqual(registrar.attemptedDisplayTexts, ["Cmd + `"])
    }

    static func testSameModeForwardAndReverseHotkeysCanHaveSeparateHandlers() throws {
        let registrar = InMemoryHotkeyRegistrar()
        let service = HotkeyService(registrar: registrar)
        let reverse = ShortcutSetting.defaultCurrentAppWindowSwitching.reverseVariant(id: "current-app-window-switching-reverse")
        var forwardCount = 0
        var reverseCount = 0

        _ = service.registerFirstUsable(
            primaryCandidate: .defaultCurrentAppWindowSwitching,
            fallbackCandidate: .fallbackCurrentAppWindowSwitching,
            existing: [] as [ShortcutSetting],
            mode: .currentAppWindowSwitching
        ) {
            forwardCount += 1
        }
        _ = service.registerFirstUsable(
            primaryCandidate: reverse,
            fallbackCandidate: reverse,
            existing: [.defaultCurrentAppWindowSwitching],
            mode: .currentAppWindowSwitching
        ) {
            reverseCount += 1
        }

        registrar.invoke(mode: .currentAppWindowSwitching)
        registrar.invoke(settingID: "current-app-window-switching-reverse")

        try expectEqual(forwardCount, 1)
        try expectEqual(reverseCount, 1)
        try expectEqual(service.registeredSetting(for: .currentAppWindowSwitching), .defaultCurrentAppWindowSwitching)
    }

    static func testModeInvocationKeepsFirstRegisteredSettingWhenHandlerIsUpdated() throws {
        let registrar = InMemoryHotkeyRegistrar()
        let reverse = ShortcutSetting.defaultCurrentAppWindowSwitching.reverseVariant(id: "current-app-window-switching-reverse")
        var forwardCount = 0
        var reverseCount = 0

        _ = registrar.register(setting: .defaultCurrentAppWindowSwitching) {
            forwardCount += 1
        }
        _ = registrar.register(setting: reverse) {
            reverseCount += 1
        }
        _ = registrar.register(setting: .defaultCurrentAppWindowSwitching) {
            forwardCount += 10
        }

        registrar.invoke(mode: .currentAppWindowSwitching)

        try expectEqual(forwardCount, 10)
        try expectEqual(reverseCount, 0)
    }

    static func testPreferredRegistrarUsesPrimaryBeforeFallback() throws {
        let primary = CountingHotkeyRegistrar(shouldRegister: true)
        let fallback = CountingHotkeyRegistrar(shouldRegister: true)
        let registrar = PreferredHotkeyRegistrar(primary: primary, fallback: fallback)

        let registered = registrar.register(setting: .defaultCurrentAppWindowSwitching) {}

        try expectTrue(registered)
        try expectEqual(primary.registerCallCount, 1)
        try expectEqual(fallback.registerCallCount, 0)
    }

    static func testPreferredRegistrarFallsBackWhenPrimaryRejectsShortcut() throws {
        let primary = CountingHotkeyRegistrar(shouldRegister: false)
        let fallback = CountingHotkeyRegistrar(shouldRegister: true)
        let registrar = PreferredHotkeyRegistrar(primary: primary, fallback: fallback)

        let registered = registrar.register(setting: .defaultCurrentAppWindowSwitching) {}

        try expectTrue(registered)
        try expectEqual(primary.registerCallCount, 1)
        try expectEqual(fallback.registerCallCount, 1)
    }

    static func testPreferredRegistrarPrimaryAndFallbackOrderedChainsCoexist() throws {
        try assertOrderedChain(primaryAccepts: true)
        try assertOrderedChain(primaryAccepts: false)
    }

    private static func assertOrderedChain(primaryAccepts: Bool) throws {
        let primary = CountingHotkeyRegistrar(name: "CarbonPrimary", shouldRegister: primaryAccepts)
        let fallback = CountingHotkeyRegistrar(name: "EventTapFallback", shouldRegister: true)
        let preferred = PreferredHotkeyRegistrar(primary: primary, fallback: fallback)
        let service = HotkeyService(registrar: preferred)
        let tapBackend = OrderedChainEventTapBackend()
        let tapSink = OrderedChainEventSink()
        var overlayCommands: [SwitcherCommand] = []
        let tapOwner = SwitcherOverlayEventTapOwner(
            backend: tapBackend,
            eventSink: tapSink
        ) { command in
            overlayCommands.append(command)
        }
        var triggerCount = 0

        let result = service.registerFirstUsable(
            primaryCandidate: .defaultCurrentAppWindowSwitching,
            fallbackCandidate: .fallbackCurrentAppWindowSwitching,
            existing: [] as [ShortcutSetting],
            mode: .currentAppWindowSwitching
        ) {
            triggerCount += 1
        }

        try expectEqual(result, .registered)
        if primaryAccepts {
            primary.invoke()
            try expectEqual(primary.registerCallCount, 1)
            try expectEqual(fallback.registerCallCount, 0)
            try expectEqual(primary.registeredKeyCodes, [50])
        } else {
            try expectEqual(primary.registerCallCount, 1)
            try expectEqual(fallback.name, "EventTapFallback")
            fallback.invoke()
            try expectEqual(fallback.registerCallCount, 1)
            try expectEqual(fallback.registeredKeyCodes, [50])
            try expectFalse(fallback.registeredKeyCodes.contains(124))
        }
        try expectEqual(triggerCount, 1)
        try expectTrue(tapOwner.install())
        guard let tap = tapBackend.connection else {
            throw TestFailure.failed("Expected ordered-chain overlay tap")
        }
        try expectFalse(tap.emit(keyCode: 50))
        try expectTrue(tap.emit(keyCode: 124))
        try expectEqual(overlayCommands, [.moveDown])
        try expectFalse(tap.emit(eventType: .tapDisabledByTimeout, keyCode: 124))
        try expectEqual(tap.reenableCount, 1)
        try expectTrue(tap.emit(keyCode: 124, isAutorepeat: true))
        try expectEqual(overlayCommands, [.moveDown, .moveDown])
        try expectEqual(triggerCount, 1)
        try expectEqual(primary.registerCallCount, 1)
        try expectEqual(fallback.registerCallCount, primaryAccepts ? 0 : 1)
        try expectTrue(tap.emit(keyCode: 36))
        try expectTrue(tap.emit(keyCode: 53))
        try expectFalse(tap.emit(keyCode: 0))
        try expectEqual(overlayCommands, [.moveDown, .moveDown, .confirm, .cancel])
        tapOwner.remove()
    }

    static func testUnregisterAllSkipsRegistrarWhenAlreadyClean() throws {
        let registrar = InMemoryHotkeyRegistrar()
        let service = HotkeyService(registrar: registrar)

        service.unregisterAll()

        try expectEqual(registrar.unregisterAllCallCount, 0)

        _ = service.registerFirstUsable(
            primaryCandidate: .defaultCurrentAppWindowSwitching,
            fallbackCandidate: .fallbackCurrentAppWindowSwitching,
            existing: [] as [ShortcutSetting],
            mode: .currentAppWindowSwitching
        ) {}
        service.unregisterAll()
        service.unregisterAll()

        try expectEqual(registrar.unregisterAllCallCount, 1)
    }

    static func testUnregisterAllClearsMessagesWithoutRegistrarWhenNoHotkeysRegistered() throws {
        let registrar = RejectingHotkeyRegistrar()
        let service = HotkeyService(registrar: registrar)

        _ = service.registerFirstUsable(
            primaryCandidate: .defaultCurrentAppWindowSwitching,
            fallbackCandidate: .fallbackCurrentAppWindowSwitching,
            existing: [] as [ShortcutSetting],
            mode: .currentAppWindowSwitching
        ) {}
        try expectEqual(service.registrationMessageSnapshot().count, 1)

        service.unregisterAll()

        try expectEqual(service.registrationMessageSnapshot().count, 0)
        try expectEqual(registrar.unregisterAllCallCount, 0)
    }
}

@MainActor
private final class OrderedChainEventTapBackend: SwitcherOverlayEventTapBackend {
    private(set) var connection: OrderedChainEventTapConnection?

    func install(
        handler: @escaping @MainActor (SwitcherOverlayEventTapInput) -> Bool
    ) -> (any SwitcherOverlayEventTapConnection)? {
        let connection = OrderedChainEventTapConnection(handler: handler)
        self.connection = connection
        return connection
    }
}

@MainActor
private final class OrderedChainEventTapConnection: SwitcherOverlayEventTapConnection {
    private let handler: @MainActor (SwitcherOverlayEventTapInput) -> Bool
    private(set) var reenableCount = 0

    init(handler: @escaping @MainActor (SwitcherOverlayEventTapInput) -> Bool) {
        self.handler = handler
    }

    func emit(
        eventType: CGEventType = .keyDown,
        keyCode: UInt16,
        isAutorepeat: Bool = false
    ) -> Bool {
        handler(SwitcherOverlayEventTapInput(
            eventType: eventType,
            keyCode: keyCode,
            isAutorepeat: isAutorepeat
        ))
    }

    func reenable() {
        reenableCount += 1
    }

    func invalidate() {}
}

@MainActor
private final class OrderedChainEventSink: SwitcherOverlayEventRecording {
    func record(_: SwitcherOverlayDiagnosticEvent) {}
}

final class SelectivelyFailingHotkeyRegistrar: HotkeyRegistering {
    let blockedDisplayText: String
    private(set) var attemptedDisplayTexts: [String] = []

    init(blockedDisplayText: String) {
        self.blockedDisplayText = blockedDisplayText
    }

    func register(setting: ShortcutSetting, handler: @escaping () -> Void) -> Bool {
        attemptedDisplayTexts.append(setting.displayText)
        return setting.displayText != blockedDisplayText
    }

    func unregisterAll() {}
}

final class InMemoryHotkeyRegistrar: HotkeyRegistering {
    private var handlers: [String: () -> Void] = [:]
    private var firstSettingIDByMode: [SwitcherMode: String] = [:]
    private(set) var unregisterAllCallCount = 0

    func register(setting: ShortcutSetting, handler: @escaping () -> Void) -> Bool {
        handlers[setting.id] = handler
        if firstSettingIDByMode[setting.mode] == nil {
            firstSettingIDByMode[setting.mode] = setting.id
        }
        return true
    }

    func unregisterAll() {
        unregisterAllCallCount += 1
        handlers.removeAll(keepingCapacity: true)
        firstSettingIDByMode.removeAll(keepingCapacity: true)
    }

    func invoke(mode: SwitcherMode) {
        guard let settingID = firstSettingIDByMode[mode] else {
            return
        }

        handlers[settingID]?()
    }

    func invoke(settingID: String) {
        handlers[settingID]?()
    }
}

final class RejectingHotkeyRegistrar: HotkeyRegistering {
    private(set) var unregisterAllCallCount = 0

    func register(setting: ShortcutSetting, handler: @escaping () -> Void) -> Bool {
        false
    }

    func unregisterAll() {
        unregisterAllCallCount += 1
    }
}

final class CountingHotkeyRegistrar: HotkeyRegistering {
    let name: String
    let shouldRegister: Bool
    private(set) var registerCallCount = 0
    private(set) var unregisterAllCallCount = 0
    private(set) var registeredKeyCodes: [UInt16] = []
    private var handler: (() -> Void)?

    init(name: String = "Counting", shouldRegister: Bool) {
        self.name = name
        self.shouldRegister = shouldRegister
    }

    func register(setting: ShortcutSetting, handler: @escaping () -> Void) -> Bool {
        registerCallCount += 1
        if let keyCode = setting.keyCode {
            registeredKeyCodes.append(keyCode)
        }
        if shouldRegister {
            self.handler = handler
        }
        return shouldRegister
    }

    func invoke() {
        handler?()
    }

    func unregisterAll() {
        unregisterAllCallCount += 1
    }
}
