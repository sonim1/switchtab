import SwiftUI

#if !SWIFT_PACKAGE
@main
#endif
public struct SwitchTabApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    public init() {}

    public var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .showSettingsWindow, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
