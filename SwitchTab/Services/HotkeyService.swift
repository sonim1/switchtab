import Carbon
import CoreGraphics
import Foundation

public enum HotkeyRegistrationResult: Equatable, Sendable {
    case registered
    case noUsableShortcut
}

struct HotkeyRegistrationSnapshot: Equatable, Sendable {
    let mode: SwitcherMode
    let expectedEnabled: Bool
    let settings: [ShortcutSetting]
    let registrationMessages: [ShortcutRegistrationMessage]

    var hasCompleteLiveRegistrationState: Bool {
        guard settings.allSatisfy({ $0.mode == mode }),
              registrationMessages.allSatisfy({ $0.mode == mode }) else {
            return false
        }

        return expectedEnabled ? settings.count == 2 : settings.isEmpty
    }
}

public protocol HotkeyRegistering {
    @discardableResult
    func register(setting: ShortcutSetting, handler: @escaping () -> Void) -> Bool
    func unregisterAll()
}

public final class HotkeyService {
    private let registrar: any HotkeyRegistering
    private let validator: ShortcutValidationService
    private var registeredSettingsByMode: [SwitcherMode: [ShortcutSetting]] = [:]
    private var registrationMessages: [ShortcutRegistrationMessage] = []

    public init(
        registrar: any HotkeyRegistering = PreferredHotkeyRegistrar(),
        validator: ShortcutValidationService = ShortcutValidationService()
    ) {
        self.registrar = registrar
        self.validator = validator
    }

    public func registerFirstUsable<Settings: Sequence>(
        primaryCandidate: ShortcutSetting,
        fallbackCandidate: @autoclosure () -> ShortcutSetting,
        existing settings: Settings,
        mode: SwitcherMode,
        handler: @escaping () -> Void
    ) -> HotkeyRegistrationResult where Settings.Element == ShortcutSetting {
        var requestedDisplayText: String?

        if registerIfUsable(
            primaryCandidate,
            existing: settings,
            mode: mode,
            requestedDisplayText: &requestedDisplayText,
            handler: handler
        ) {
            return .registered
        }

        if registerIfUsable(
            fallbackCandidate(),
            existing: settings,
            mode: mode,
            requestedDisplayText: &requestedDisplayText,
            handler: handler
        ) {
            return .registered
        }

        return finishRegistrationAttempt(requestedDisplayText, mode: mode)
    }

    public func register<Settings: Sequence>(
        setting: ShortcutSetting,
        existing settings: Settings,
        mode: SwitcherMode,
        handler: @escaping () -> Void
    ) -> HotkeyRegistrationResult where Settings.Element == ShortcutSetting {
        var requestedDisplayText: String?
        guard registerIfUsable(
            setting,
            existing: settings,
            mode: mode,
            requestedDisplayText: &requestedDisplayText,
            handler: handler
        ) else {
            return finishRegistrationAttempt(requestedDisplayText, mode: mode)
        }

        return .registered
    }

    public func unregisterAll() {
        let hasRegisteredHotkeys = !registeredSettingsByMode.isEmpty
        guard hasRegisteredHotkeys || !registrationMessages.isEmpty else {
            return
        }

        if hasRegisteredHotkeys {
            registrar.unregisterAll()
        }
        registeredSettingsByMode.removeAll(keepingCapacity: true)
        registrationMessages.removeAll(keepingCapacity: true)
    }

    public func registeredSetting(for mode: SwitcherMode) -> ShortcutSetting? {
        registeredSettingsByMode[mode]?.first
    }

    public func registeredSettings(for mode: SwitcherMode) -> [ShortcutSetting] {
        registeredSettingsByMode[mode] ?? []
    }

    public func registrationMessageSnapshot() -> [ShortcutRegistrationMessage] {
        registrationMessages
    }

    func registrationSnapshot(
        for mode: SwitcherMode,
        expectedEnabled: Bool
    ) -> HotkeyRegistrationSnapshot {
        HotkeyRegistrationSnapshot(
            mode: mode,
            expectedEnabled: expectedEnabled,
            settings: registeredSettings(for: mode),
            registrationMessages: registrationMessages.filter { $0.mode == mode }
        )
    }

    func restoreRegistrationMetadata(from snapshot: HotkeyRegistrationSnapshot) -> Bool {
        guard snapshot.hasCompleteLiveRegistrationState,
              registeredSettings(for: snapshot.mode) == snapshot.settings else {
            return false
        }

        registrationMessages.removeAll { $0.mode == snapshot.mode }
        registrationMessages.append(contentsOf: snapshot.registrationMessages)
        return true
    }

    private func registerIfUsable(
        _ setting: ShortcutSetting,
        existing settings: some Sequence<ShortcutSetting>,
        mode: SwitcherMode,
        requestedDisplayText: inout String?,
        handler: @escaping () -> Void
    ) -> Bool {
        guard setting.mode == mode else {
            return false
        }

        guard validator.validate(setting, existing: settings) == .valid,
              registrar.register(setting: setting, handler: handler) else {
            requestedDisplayText = requestedDisplayText ?? setting.displayText
            return false
        }

        registeredSettingsByMode[mode, default: []].append(setting)

        if let requestedDisplayText {
            registrationMessages.append(
                ShortcutRegistrationMessage(
                    mode: mode,
                    message: "\(requestedDisplayText) is unavailable or already used. Using \(setting.displayText)."
                )
            )
        }

        return true
    }

    private func finishRegistrationAttempt(
        _ requestedDisplayText: String?,
        mode: SwitcherMode
    ) -> HotkeyRegistrationResult {
        if let requestedDisplayText {
            registrationMessages.append(
                ShortcutRegistrationMessage(
                    mode: mode,
                    message: "\(requestedDisplayText) could not be registered. Choose another shortcut."
                )
            )
        }

        return .noUsableShortcut
    }
}

public final class PreferredHotkeyRegistrar: HotkeyRegistering {
    private let primary: any HotkeyRegistering
    private let fallback: any HotkeyRegistering

    public init(
        primary: any HotkeyRegistering = CarbonHotkeyRegistrar(),
        fallback: any HotkeyRegistering = EventTapHotkeyRegistrar()
    ) {
        self.primary = primary
        self.fallback = fallback
    }

    public func register(setting: ShortcutSetting, handler: @escaping () -> Void) -> Bool {
        if primary.register(setting: setting, handler: handler) {
            return true
        }

        return fallback.register(setting: setting, handler: handler)
    }

    public func unregisterAll() {
        primary.unregisterAll()
        fallback.unregisterAll()
    }
}

public final class EventTapHotkeyRegistrar: HotkeyRegistering {
    private let dispatcher: EventTapHotkeyDispatcher
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    public init(invokesHandlersForAutorepeat: Bool = false) {
        dispatcher = EventTapHotkeyDispatcher(
            invokesHandlersForAutorepeat: invokesHandlersForAutorepeat
        )
    }

    deinit {
        // The tap callback holds an unretained pointer to self; tear the tap
        // down before that pointer goes stale.
        unregisterAll()
    }

    public func register(setting: ShortcutSetting, handler: @escaping () -> Void) -> Bool {
        guard EventTapHotkey(setting: setting) != nil,
              installTapIfNeeded(),
              dispatcher.register(setting: setting, handler: handler) else {
            return false
        }

        return true
    }

    public func unregisterAll() {
        dispatcher.unregisterAll()
        if let tap {
            CFMachPortInvalidate(tap)
        }
        tap = nil
        runLoopSource = nil
    }

    private func installTapIfNeeded() -> Bool {
        if tap != nil {
            return true
        }

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.handleEvent,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = source
        return true
    }

    private static let handleEvent: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let registrar = Unmanaged<EventTapHotkeyRegistrar>.fromOpaque(userInfo).takeUnretainedValue()
        guard type == .keyDown else {
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput,
               let tap = registrar.tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let shouldConsume = registrar.dispatcher.dispatch(
            keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
            modifiers: EventTapModifierResolver.modifierNames(from: event.flags),
            isAutorepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        )
        guard shouldConsume else {
            return Unmanaged.passUnretained(event)
        }

        return nil
    }
}

final class EventTapHotkeyDispatcher {
    private let invokesHandlersForAutorepeat: Bool
    private var registrations: [EventTapHotkey: () -> Void] = [:]

    init(invokesHandlersForAutorepeat: Bool) {
        self.invokesHandlersForAutorepeat = invokesHandlersForAutorepeat
    }

    @discardableResult
    func register(setting: ShortcutSetting, handler: @escaping () -> Void) -> Bool {
        guard let hotkey = EventTapHotkey(setting: setting) else {
            return false
        }

        registrations[hotkey] = handler
        return true
    }

    func unregisterAll() {
        registrations.removeAll(keepingCapacity: true)
    }

    func dispatch(keyCode: UInt16, modifiers: [String], isAutorepeat: Bool) -> Bool {
        let hotkey = EventTapHotkey(keyCode: keyCode, modifiers: modifiers)
        guard let handler = registrations[hotkey] else {
            return false
        }

        if !isAutorepeat || invokesHandlersForAutorepeat {
            handler()
        }
        return true
    }
}

struct EventTapHotkey: Hashable {
    let keyCode: UInt16
    let modifiers: [String]

    init?(setting: ShortcutSetting) {
        guard let keyCode = setting.keyCode ?? ShortcutKeyCodeResolver.keyCode(for: setting.keyEquivalent) else {
            return nil
        }

        self.init(keyCode: keyCode, modifiers: setting.modifiers)
    }

    init(keyCode: UInt16, modifiers: [String]) {
        self.keyCode = keyCode
        self.modifiers = EventTapModifierResolver.normalizedModifierNames(modifiers)
    }
}

private enum EventTapModifierResolver {
    static func modifierNames(from flags: CGEventFlags) -> [String] {
        var names: [String] = []
        names.reserveCapacity(4)
        if flags.contains(.maskCommand) {
            names.append("command")
        }
        if flags.contains(.maskAlternate) {
            names.append("option")
        }
        if flags.contains(.maskControl) {
            names.append("control")
        }
        if flags.contains(.maskShift) {
            names.append("shift")
        }
        return names
    }

    static func normalizedModifierNames(_ modifiers: [String]) -> [String] {
        var hasCommand = false
        var hasOption = false
        var hasControl = false
        var hasShift = false

        for modifier in modifiers {
            switch modifier {
            case "command":
                hasCommand = true
            case "option":
                hasOption = true
            case "control":
                hasControl = true
            case "shift":
                hasShift = true
            default:
                break
            }
        }

        var normalized: [String] = []
        normalized.reserveCapacity(4)
        if hasCommand {
            normalized.append("command")
        }
        if hasOption {
            normalized.append("option")
        }
        if hasControl {
            normalized.append("control")
        }
        if hasShift {
            normalized.append("shift")
        }
        return normalized
    }
}

public final class CarbonHotkeyRegistrar: HotkeyRegistering {
    private var registrations: [UInt32: EventHotKeyRef] = [:]

    public init() {
        CarbonHotkeyRegistry.shared.installIfNeeded()
    }

    public func register(setting: ShortcutSetting, handler: @escaping () -> Void) -> Bool {
        guard let keyCode = setting.keyCode ?? ShortcutKeyCodeResolver.keyCode(for: setting.keyEquivalent) else {
            return false
        }

        let id = CarbonHotkeyRegistry.shared.reserve(handler: handler)
        let hotkeyID = EventHotKeyID(signature: CarbonHotkeyRegistry.signature, id: id)
        var hotkeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            CarbonModifierResolver.flags(for: setting.modifiers),
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        guard status == noErr, let hotkeyRef else {
            CarbonHotkeyRegistry.shared.remove(id: id)
            return false
        }

        registrations[id] = hotkeyRef
        return true
    }

    public func unregisterAll() {
        for (id, registration) in registrations {
            UnregisterEventHotKey(registration)
            CarbonHotkeyRegistry.shared.remove(id: id)
        }

        registrations.removeAll(keepingCapacity: true)
    }
}

private final class CarbonHotkeyRegistry: @unchecked Sendable {
    static let shared = CarbonHotkeyRegistry()
    static let signature = OSType(0x57535754)

    private let lock = NSLock()
    private var nextID: UInt32 = 1
    private var handlers: [UInt32: () -> Void] = [:]
    private var didInstallHandler = false

    func installIfNeeded() {
        lock.lock()
        defer { lock.unlock() }

        guard !didInstallHandler else {
            return
        }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var hotkeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotkeyID
                )

                guard status == noErr else {
                    return status
                }

                CarbonHotkeyRegistry.shared.invoke(id: hotkeyID.id)
                return noErr
            },
            1,
            &eventSpec,
            nil,
            nil
        )
        didInstallHandler = true
    }

    func reserve(handler: @escaping () -> Void) -> UInt32 {
        lock.lock()
        defer { lock.unlock() }

        let id = nextID
        nextID += 1
        handlers[id] = handler
        return id
    }

    func remove(id: UInt32) {
        lock.lock()
        defer { lock.unlock() }
        handlers.removeValue(forKey: id)
    }

    private func invoke(id: UInt32) {
        lock.lock()
        let handler = handlers[id]
        lock.unlock()

        guard let handler else {
            return
        }

        guard !Thread.isMainThread else {
            handler()
            return
        }

        DispatchQueue.main.async {
            handler()
        }
    }
}

private enum CarbonModifierResolver {
    static func flags(for modifiers: [String]) -> UInt32 {
        var flags: UInt32 = 0
        for modifier in modifiers {
            flags |= flag(for: modifier)
        }
        return flags
    }

    private static func flag(for modifier: String) -> UInt32 {
        switch modifier {
        case "command":
            UInt32(cmdKey)
        case "option":
            UInt32(optionKey)
        case "control":
            UInt32(controlKey)
        case "shift":
            UInt32(shiftKey)
        default:
            0
        }
    }
}
