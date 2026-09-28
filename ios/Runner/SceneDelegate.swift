import Flutter
import UIKit

final class SceneDelegate: FlutterSceneDelegate {
  private weak var observedWindowScene: UIWindowScene?
  private var effectiveGeometryObservation: NSKeyValueObservation?
  private var probeRefreshScheduled = false

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    installWindowCornerInsetProbe(for: scene)

    guard let controller = window?.rootViewController as? FlutterViewController,
          let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
      return
    }

    appDelegate.configureFlutterChannels(for: controller)
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    (UIApplication.shared.delegate as? AppDelegate)?.sceneDidBecomeActive()
    installWindowCornerInsetProbe(for: scene)
  }

  @available(iOS 26.0, *)
  override func windowScene(
    _ windowScene: UIWindowScene,
    didUpdateEffectiveGeometry previousEffectiveGeometry: UIWindowScene.Geometry
  ) {
    installWindowCornerInsetProbe(for: windowScene)
    scheduleWindowCornerInsetProbeRefresh(for: windowScene)
  }

  @available(iOS 26.0, *)
  override func preferredWindowingControlStyle(
    for scene: UIWindowScene
  ) -> UIWindowScene.WindowingControlStyle {
    .unified
  }

  private func installWindowCornerInsetProbe(for scene: UIScene) {
    guard let windowScene = scene as? UIWindowScene else { return }
    if #available(iOS 26.0, *) { observeEffectiveGeometry(for: windowScene) }

    let window = windowScene.windows.first(where: \.isKeyWindow) ?? windowScene.windows.first
    guard let rootView = window?.rootViewController?.view else {
      DispatchQueue.main.async { [weak self] in
        self?.installWindowCornerInsetProbe(for: windowScene)
      }
      return
    }

    if let existing = rootView.subviews.first(where: { $0 is WindowCornerInsetProbeView }) as? WindowCornerInsetProbeView {
      existing.setNeedsLayout()
      if #available(iOS 26.0, *) { scheduleWindowCornerInsetProbeRefresh(for: windowScene) }
      return
    }

    let probe = WindowCornerInsetProbeView(frame: rootView.bounds)
    probe.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    probe.isUserInteractionEnabled = false
    probe.backgroundColor = .clear
    rootView.addSubview(probe)
    DispatchQueue.main.async { probe.setNeedsLayout() }
    if #available(iOS 26.0, *) { scheduleWindowCornerInsetProbeRefresh(for: windowScene) }
  }

  @available(iOS 26.0, *)
  private func observeEffectiveGeometry(for scene: UIWindowScene) {
    guard observedWindowScene !== scene else { return }
    effectiveGeometryObservation?.invalidate()
    observedWindowScene = scene
    effectiveGeometryObservation = scene.observe(\.effectiveGeometry, options: [.new]) { [weak self, weak scene] _, _ in
      guard let scene else { return }
      self?.scheduleWindowCornerInsetProbeRefresh(for: scene)
    }
  }

  private func scheduleWindowCornerInsetProbeRefresh(for scene: UIWindowScene) {
    guard !probeRefreshScheduled else { return }
    probeRefreshScheduled = true
    DispatchQueue.main.async { [weak self, weak scene] in
      guard let self, let scene else { return }
      self.refreshWindowCornerInsetProbe(for: scene)
      DispatchQueue.main.async { [weak self, weak scene] in
        guard let self, let scene else { return }
        self.probeRefreshScheduled = false
        self.refreshWindowCornerInsetProbe(for: scene)
      }
    }
  }

  private func refreshWindowCornerInsetProbe(for scene: UIWindowScene) {
    let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
    guard let rootView = window?.rootViewController?.view else {
      installWindowCornerInsetProbe(for: scene)
      return
    }
    if let probe = rootView.subviews.first(where: { $0 is WindowCornerInsetProbeView }) as? WindowCornerInsetProbeView {
      probe.setNeedsLayout()
      window?.layoutIfNeeded()
      rootView.layoutIfNeeded()
    } else {
      installWindowCornerInsetProbe(for: scene)
    }
  }
}
