import Foundation
import ServiceManagement

public extension Notification.Name {
    static let applicationSettingsDidChange = Notification.Name("WindowSwitcher.applicationSettingsDidChange")
}

public struct ApplicationSettingsStore {
    public static let menuBarIconVisibleKey = "ApplicationSettings.menuBarIconVisible"
    public static let overlaySizeKey = "ApplicationSettings.overlaySize"

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public var menuBarIconVisible: Bool {
        userDefaults.object(forKey: Self.menuBarIconVisibleKey) as? Bool ?? true
    }

    public func saveMenuBarIconVisible(_ visible: Bool) {
        userDefaults.set(visible, forKey: Self.menuBarIconVisibleKey)
        NotificationCenter.default.post(name: .applicationSettingsDidChange, object: nil)
    }

    public var overlaySize: OverlaySizePreference {
        guard let rawValue = userDefaults.string(forKey: Self.overlaySizeKey),
              let preference = OverlaySizePreference(rawValue: rawValue) else {
            return .standard
        }

        return preference
    }

    public func saveOverlaySize(_ size: OverlaySizePreference) {
        userDefaults.set(size.rawValue, forKey: Self.overlaySizeKey)
        NotificationCenter.default.post(name: .applicationSettingsDidChange, object: nil)
    }
}

@MainActor
public protocol LaunchAtLoginServicing: AnyObject {
    var startsAtLogin: Bool { get }
    func setStartsAtLogin(_ startsAtLogin: Bool) throws
}

@MainActor
public final class LaunchAtLoginService: LaunchAtLoginServicing {
    public init() {}

    public var startsAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func setStartsAtLogin(_ startsAtLogin: Bool) throws {
        guard self.startsAtLogin != startsAtLogin else {
            return
        }

        if startsAtLogin {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

public enum ApplicationLaunchPresentationPolicy {
    public static func shouldShowSettingsWindowOnLaunch(
        menuBarIconVisible: Bool,
        permissionState: PermissionState
    ) -> Bool {
        !menuBarIconVisible
            || permissionState.blocksFocusChanges
            || permissionState.blocksWindowPreviews
    }
}
