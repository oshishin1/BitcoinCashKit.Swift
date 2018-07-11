import UIKit
import WalletKit

class BackupRouter {
    weak var navigationController: UINavigationController?
}

extension BackupRouter: IBackupRouter {


    func close() {
        navigationController?.dismiss(animated: true)
    }

    func navigateToMain() {
        navigationController?.topViewController?.view.endEditing(true)

        guard let window = UIApplication.shared.keyWindow else {
            return
        }

        let viewController = MainRouter.module()

        UIView.transition(with: window, duration: 0.5, options: .transitionCrossDissolve, animations: {
            window.rootViewController = viewController
        })
    }

}

extension BackupRouter {

    static func module(dismissMode: BackupPresenter.DismissMode) -> UIViewController {
        let router = BackupRouter()
        let interactor = BackupInteractor(walletManager: Singletons.instance.walletManager, indexesProvider: Factory.instance.randomProvider)
        let presenter = BackupPresenter(interactor: interactor, router: router, dismissMode: dismissMode)
        let navigationController = BackupNavigationController(viewDelegate: presenter)

        interactor.delegate = presenter
        presenter.view = navigationController
        router.navigationController = navigationController

        return navigationController
    }

}
