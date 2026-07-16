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
    }
}
