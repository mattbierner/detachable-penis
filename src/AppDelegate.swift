import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow()
        let state = ProgramState()
        let rootController = ARViewController(state: state)        
        window?.rootViewController = UINavigationController(rootViewController: rootController)
        window?.makeKeyAndVisible()
        return true
    }
}
