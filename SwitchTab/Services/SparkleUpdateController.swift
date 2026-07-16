#if DIRECT_DISTRIBUTION && canImport(Sparkle)
import Foundation
import Sparkle

@MainActor
public final class SparkleUpdateController: NSObject, UpdateChecking {
    private let updaterController: SPUStandardUpdaterController

    public override init() {
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    public var isUpdateCheckingAvailable: Bool {
        updaterController.updater.canCheckForUpdates
    }

    public var automaticallyChecksForUpdates: Bool {
        get {
            updaterController.updater.automaticallyChecksForUpdates
        }
        set {
            updaterController.updater.automaticallyChecksForUpdates = newValue
        }
    }

    public var currentVersionDisplay: String {
        ApplicationVersionProvider.currentVersionDisplay()
    }

    public func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
#endif
