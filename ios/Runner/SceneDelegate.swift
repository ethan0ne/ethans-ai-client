import Flutter
import UIKit

final class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    guard let controller = window?.rootViewController as? FlutterViewController,
          let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
      return
    }

    appDelegate.configureFlutterChannels(for: controller)
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    (UIApplication.shared.delegate as? AppDelegate)?.sceneDidBecomeActive()
  }
}
