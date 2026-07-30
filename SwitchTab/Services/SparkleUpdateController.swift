#if DIRECT_DISTRIBUTION && canImport(Sparkle)
import AppKit
import Foundation
import OSLog
import Sparkle

@MainActor
public final class SparkleUpdateController: NSObject, UpdateChecking, SPUUpdaterDelegate {
    private let logger = Logger(subsystem: "com.royjen.switchtab", category: "Updates")
    private let errorPresenter: SparkleUpdateErrorPresenter
    private let userDriver: SwitchTabUpdateUserDriver
    private var updater: SPUUpdater!
    private static let retryPollLimit = 50

    public override init() {
        errorPresenter = SparkleUpdateErrorPresenter()
        userDriver = SwitchTabUpdateUserDriver(errorPresenter: errorPresenter)
        super.init()
        updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: userDriver,
            delegate: self
        )
        userDriver.didChooseAction = { [weak self] action in
            self?.handleUpdateAction(action)
        }
        startUpdater()
    }

    public var isUpdateCheckingAvailable: Bool {
        updater.canCheckForUpdates
    }

    public var automaticallyChecksForUpdates: Bool {
        get {
            updater.automaticallyChecksForUpdates
        }
        set {
            updater.automaticallyChecksForUpdates = newValue
        }
    }

    public var currentVersionDisplay: String {
        ApplicationVersionProvider.currentVersionDisplay()
    }

    public func checkForUpdates() {
        updater.checkForUpdates()
    }

    public func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let diagnostic = UpdateDiagnostic.make(error: error as NSError)
        logger.error("\(diagnostic.report, privacy: .public)")
    }

    private func startUpdater() {
        do {
            try updater.start()
        } catch {
            let action = errorPresenter.present(error: error as NSError)
            switch action {
            case .retry:
                DispatchQueue.main.async { [weak self] in
                    self?.startUpdater()
                }
            case .downloadManually:
                NSWorkspace.shared.open(UpdateSupportLinks.latestRelease)
            case .cancel:
                break
            }
        }
    }

    private func handleUpdateAction(_ action: UpdateErrorAlertAction) {
        switch action {
        case .retry:
            retryUpdateCheck(attemptsRemaining: Self.retryPollLimit)
        case .downloadManually:
            NSWorkspace.shared.open(UpdateSupportLinks.latestRelease)
        case .cancel:
            break
        }
    }

    private func retryUpdateCheck(attemptsRemaining: Int) {
        guard updater.sessionInProgress else {
            updater.checkForUpdates()
            return
        }
        guard attemptsRemaining > 0 else {
            logger.error("Timed out waiting for the previous update session to finish")
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.retryUpdateCheck(attemptsRemaining: attemptsRemaining - 1)
        }
    }
}
#endif
