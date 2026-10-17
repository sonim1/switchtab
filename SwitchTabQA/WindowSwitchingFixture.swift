import AppKit
import Carbon

@MainActor
final class QALaunchDelegate: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []
    var eventLabels: [NSTextField] = []
    var keyMonitor: Any?
    var commandCount = 0
    var globalLabels: [NSTextField] = []
    var globalCount = 0
    var globalRegistrationStatus: OSStatus = OSStatus(eventNotHandledErr)
    var hotkeyReference: EventHotKeyRef?
    var handlerReference: EventHandlerRef?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let mainMenu = NSMenu()
        let diagnostics = NSMenuItem(title: "Diagnostics", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Diagnostics")
        let command = NSMenuItem(title: "Verify Command Modifier", action: #selector(markCommand), keyEquivalent: "k")
        command.keyEquivalentModifierMask = .command
        command.target = self
        submenu.addItem(command)
        diagnostics.submenu = submenu
        mainMenu.addItem(diagnostics)
        NSApp.mainMenu = mainMenu
        let windowNames = CommandLine.arguments.contains("--empty-windows") ? [] : ["A", "B", "C"]
        for (index, name) in windowNames.enumerated() {
            let window = NSWindow(contentRect: NSRect(x: 350 + index * 90, y: 320 + index * 50, width: 380, height: 220),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "SwitchTab Security QA " + name
            window.isReleasedWhenClosed = false
            let label = NSTextField(labelWithString: "Owned, disposable SwitchTab window-switching fixture " + name)
            label.frame = NSRect(x: 20, y: 100, width: 340, height: 50)
            window.contentView?.addSubview(label)
            let eventLabel = NSTextField(labelWithString: "No local keyboard event observed")
            eventLabel.frame = NSRect(x: 20, y: 65, width: 340, height: 35)
            window.contentView?.addSubview(eventLabel)
            eventLabels.append(eventLabel)
            let globalLabel = NSTextField(labelWithString: "Global probe initializing")
            globalLabel.frame = NSRect(x: 20, y: 50, width: 340, height: 15)
            window.contentView?.addSubview(globalLabel)
            globalLabels.append(globalLabel)
            let verify = NSButton(title: "Verify probe handler", target: self, action: #selector(verifyProbeHandler))
            verify.frame = NSRect(x: 20, y: 175, width: 200, height: 30)
            window.contentView?.addSubview(verify)
            let input = NSTextField(frame: NSRect(x: 20, y: 20, width: 340, height: 30))
            input.placeholderString = "Owned QA keyboard input"
            input.setAccessibilityLabel("Owned QA keyboard input")
            window.contentView?.addSubview(input)
            windows.append(window)
            window.makeKeyAndOrderFront(nil)
        }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr, identifier.signature == 0x53545141, identifier.id == 1 else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<QALaunchDelegate>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                delegate.globalCount += 1
                delegate.refreshGlobalLabels()
            }
            return OSStatus(noErr)
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerReference)
        if handlerStatus == noErr {
            globalRegistrationStatus = RegisterEventHotKey(UInt32(kVK_F12), UInt32(controlKey | optionKey),
                                                          EventHotKeyID(signature: 0x53545141, id: 1), GetApplicationEventTarget(),
                                                          0, &hotkeyReference)
        } else {
            globalRegistrationStatus = handlerStatus
        }
        refreshGlobalLabels()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            let flags = event.modifierFlags
            let description = "key=\(event.keyCode) command=\(flags.contains(.command)) control=\(flags.contains(.control)) option=\(flags.contains(.option)) shift=\(flags.contains(.shift))"
            for label in self?.eventLabels ?? [] { label.stringValue = description }
            return event
        }
        NSApp.activate()
    }
    @objc func markCommand() {
        commandCount += 1
        for label in eventLabels { label.stringValue = "Command menu executed \(commandCount)" }
    }
    func refreshGlobalLabels() {
        for label in globalLabels { label.stringValue = "Global Ctrl+Option+F12 status=\(globalRegistrationStatus) events=\(globalCount)" }
    }
    @objc func verifyProbeHandler() {
        var event: EventRef?
        guard CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), GetCurrentEventTime(),
                          EventAttributes(kEventAttributeUserEvent), &event) == noErr, let event else { return }
        defer { ReleaseEvent(event) }
        var identifier = EventHotKeyID(signature: 0x53545141, id: 1)
        let parameterStatus = SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                               MemoryLayout<EventHotKeyID>.size, &identifier)
        guard parameterStatus == noErr else { return }
        SendEventToEventTarget(event, GetApplicationEventTarget())
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let hotkeyReference { UnregisterEventHotKey(hotkeyReference) }
        if let handlerReference { RemoveEventHandler(handlerReference) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
@MainActor
enum SecurityQAFixture {
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        let qaDelegate = QALaunchDelegate()
        application.delegate = qaDelegate
        withExtendedLifetime(qaDelegate) { application.run() }
    }
}
