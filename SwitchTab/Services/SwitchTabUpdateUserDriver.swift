#if DIRECT_DISTRIBUTION && canImport(Sparkle)
import AppKit
import Sparkle

@MainActor
public final class SwitchTabUpdateUserDriver: SPUStandardUserDriver {
    public var didChooseAction: ((UpdateErrorAlertAction) -> Void)?
    private let errorPresenter: SparkleUpdateErrorPresenter

    public init(
        hostBundle: Bundle = .main,
        errorPresenter: SparkleUpdateErrorPresenter
    ) {
        self.errorPresenter = errorPresenter
        super.init(hostBundle: hostBundle, delegate: nil)
    }

    public override func showUpdaterError(
        _ error: Error,
        acknowledgement: @escaping () -> Void
    ) {
        super.dismissUpdateInstallation()
        let action = errorPresenter.present(error: error as NSError)
        acknowledgement()
        didChooseAction?(action)
    }
}
#endif
