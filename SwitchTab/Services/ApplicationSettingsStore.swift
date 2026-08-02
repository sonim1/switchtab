import Foundation
import ServiceManagement

public extension Notification.Name {
    static let applicationSettingsDidChange = Notification.Name("SwitchTab.applicationSettingsDidChange")
    // TODO(Task 4): Remove this deprecated compatibility notification with AppDelegate's legacy observer.
    static let commandTabReplacementDidChange = Notification.Name(
        "SwitchTab.commandTabReplacementDidChange"
    )
}

public struct ApplicationSettingsStore {
    public static let menuBarIconVisibleKey = "ApplicationSettings.menuBarIconVisible"
    /// Legacy migration key. Active app-switching state lives in ShortcutSettingsStore.
    public static let replacesCommandTabKey = "ApplicationSettings.replacesCommandTab"
    public static let overlaySizeScaleKey = "ApplicationSettings.overlaySizeScale"
    /// Legacy three-step preference, read once to migrate onto the scale.
    public static let overlaySizeKey = "ApplicationSettings.overlaySize"

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public var menuBarIconVisible: Bool {
        userDefaults.object(forKey: Self.menuBarIconVisibleKey) as? Bool ?? true
    }

    public func saveMenuBarIconVisible(_ visible: Bool) {
        guard menuBarIconVisible != visible else {
            return
        }

        userDefaults.set(visible, forKey: Self.menuBarIconVisibleKey)
        NotificationCenter.default.post(name: .applicationSettingsDidChange, object: nil)
    }

    // TODO(Task 4): Remove this deprecated forwarding shim after AppDelegate reads unified configurations.
    public var replacesCommandTab: Bool {
        ShortcutSettingsStore(userDefaults: userDefaults)
            .loadConfigurations()
            .first { $0.mode == .applicationSwitching }?
            .isEnabled ?? SwitcherShortcutConfiguration.defaultApplicationSwitching.isEnabled
    }

    // TODO(Task 5): Remove this deprecated forwarding shim after the settings UI uses ShortcutSettingsViewModel.
    public func saveReplacesCommandTab(_ enabled: Bool) {
        let shortcutStore = ShortcutSettingsStore(userDefaults: userDefaults)
        var configurations = shortcutStore.loadConfigurations()
        guard let index = configurations.firstIndex(where: { $0.mode == .applicationSwitching }),
              configurations[index].isEnabled != enabled else {
            return
        }

        configurations[index].isEnabled = enabled
        guard (try? shortcutStore.saveConfigurations(configurations)) != nil else {
            return
        }

        NotificationCenter.default.post(name: .applicationSettingsDidChange, object: nil)
        NotificationCenter.default.post(name: .commandTabReplacementDidChange, object: nil)
    }

    public var overlaySizeScale: OverlaySizeScale {
        if let storedValue = userDefaults.object(forKey: Self.overlaySizeScaleKey) as? Double {
            return OverlaySizeScale(storedValue)
        }

        guard let legacyRawValue = userDefaults.string(forKey: Self.overlaySizeKey),
              let legacyPreference = OverlaySizePreference(rawValue: legacyRawValue) else {
            return .default
        }

        return legacyPreference.scale
    }

    public func saveOverlaySizeScale(_ scale: OverlaySizeScale) {
        guard overlaySizeScale != scale else {
            return
        }

        userDefaults.set(scale.value, forKey: Self.overlaySizeScaleKey)
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
