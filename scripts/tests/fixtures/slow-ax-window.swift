import AppKit

final class SlowWindow: NSWindow {
    override func isAccessibilityMinimized() -> Bool {
        Thread.sleep(forTimeInterval: 0.8)
        return false
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let window = SlowWindow(contentRect: NSRect(x: 300, y: 300, width: 250, height: 150), styleMask: [.titled], backing: .buffered, defer: false)
window.title = "SwitchTab timeout QA"
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
FileHandle.standardOutput.write(Data("ready \(getpid())\n".utf8))
DispatchQueue.main.asyncAfter(deadline: .now() + 20) { exit(0) }
app.run()
