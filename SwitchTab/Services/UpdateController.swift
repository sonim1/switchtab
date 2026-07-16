import Foundation

public extension Notification.Name {
    static let checkForUpdates = Notification.Name("SwitchTab.checkForUpdates")
}

@MainActor
public protocol UpdateChecking: AnyObject {
    var isUpdateCheckingAvailable: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    var currentVersionDisplay: String { get }
    func checkForUpdates()
}

@MainActor
public final class UnavailableUpdateController: UpdateChecking {
    public init() {}

    public var isUpdateCheckingAvailable: Bool {
        false
    }

    public var automaticallyChecksForUpdates: Bool {
        get { false }
        set {}
    }

    public var currentVersionDisplay: String {
        ApplicationVersionProvider.currentVersionDisplay()
    }

    public func checkForUpdates() {}
}

public enum ApplicationVersionProvider {
    public static func currentVersionDisplay(bundle: Bundle = .main) -> String {
        currentVersionDisplay(infoDictionary: bundle.infoDictionary ?? [:])
    }

    public static func currentVersionDisplay(infoDictionary: [String: Any]) -> String {
        let version = infoDictionary["CFBundleShortVersionString"] as? String
        let build = infoDictionary["CFBundleVersion"] as? String
        let displayedVersion = version?.isEmpty == false ? version! : "Unknown"

        guard let build,
              !build.isEmpty else {
            return displayedVersion
        }

        return "\(displayedVersion) (\(build))"
    }
}

@MainActor
public enum UpdateControllerFactory {
    public static func make() -> any UpdateChecking {
        #if DIRECT_DISTRIBUTION && canImport(Sparkle)
        return SparkleUpdateController()
        #else
        return UnavailableUpdateController()
        #endif
    }
}

public enum UpdateRequestPoster {
    public static func postCheckForUpdatesRequest(
        notificationCenter: NotificationCenter = .default
    ) {
        notificationCenter.post(name: .checkForUpdates, object: nil)
    }
}
