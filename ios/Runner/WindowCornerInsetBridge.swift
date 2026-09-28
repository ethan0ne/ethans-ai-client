import Flutter
import UIKit

final class WindowCornerInsetChannel: NSObject, FlutterStreamHandler {
  static let channelName = "financial_memory/window_corner_inset"
  static let eventChannelName = "financial_memory/window_corner_inset/events"

  private var eventSink: FlutterEventSink?
  private var observer: NSObjectProtocol?

  static func register(with messenger: FlutterBinaryMessenger) {
    let method = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    method.setMethodCallHandler { call, result in
      guard call.method == "current" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(WindowCornerInsetSupport.currentInsets())
    }
    let events = FlutterEventChannel(name: eventChannelName, binaryMessenger: messenger)
    events.setStreamHandler(WindowCornerInsetChannel())
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    observer = NotificationCenter.default.addObserver(
      forName: WindowCornerInsetSupport.didChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let scene = notification.object as? UIWindowScene else { return }
      self?.eventSink?(WindowCornerInsetSupport.currentInsets(for: scene))
    }
    events(WindowCornerInsetSupport.currentInsets())
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    if let observer { NotificationCenter.default.removeObserver(observer) }
    observer = nil
    eventSink = nil
    return nil
  }
}

enum WindowCornerInsetSupport {
  static let didChangeNotification = Notification.Name("WindowCornerInsetDidChange")
  private static var insetsByScene: [ObjectIdentifier: [String: Double]] = [:]

  static func currentInsets() -> [String: Double] {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    return currentInsets(for: scene)
  }

  static func currentInsets(for scene: UIWindowScene?) -> [String: Double] {
    guard #available(iOS 26.0, *), let scene else {
      return [
        "leading": 0, "trailing": 0, "top": 0,
        "isPhone": UIDevice.current.userInterfaceIdiom == .phone ? 1 : 0,
        "windowTouchesTop": 0, "controlsVisible": 0,
      ]
    }
    return insetsByScene[ObjectIdentifier(scene)] ?? [
      "leading": 0, "trailing": 0, "top": 0,
      "isPhone": UIDevice.current.userInterfaceIdiom == .phone ? 1 : 0,
      "windowTouchesTop": 0, "controlsVisible": 0,
    ]
  }

  static func updateInsets(_ insets: [String: Double], for scene: UIWindowScene) {
    guard #available(iOS 26.0, *) else { return }
    let next: [String: Double] = [
      "leading": max(0, insets["leading"] ?? 0),
      "trailing": max(0, insets["trailing"] ?? 0),
      "top": max(0, insets["top"] ?? 0),
      "isPhone": UIDevice.current.userInterfaceIdiom == .phone ? 1 : 0,
      "windowTouchesTop": (insets["windowTouchesTop"] ?? 0) > 0.5 ? 1 : 0,
      "controlsVisible": (insets["controlsVisible"] ?? 0) > 0.5 ? 1 : 0,
    ]
    let key = ObjectIdentifier(scene)
    guard insetsByScene[key] != next else { return }
    insetsByScene[key] = next
    NotificationCenter.default.post(name: didChangeNotification, object: scene)
  }
}

final class WindowCornerInsetProbeView: UIView {
  override func layoutSubviews() {
    super.layoutSubviews()
    guard #available(iOS 26.0, *), let window, let scene = window.windowScene else { return }

    let regular = layoutGuide(for: .margins()).layoutFrame
    let adaptive = layoutGuide(for: .margins(cornerAdaptation: .horizontal)).layoutFrame
    let vertical = layoutGuide(for: .margins(cornerAdaptation: .vertical)).layoutFrame
    let windowFrame = scene.screen.coordinateSpace.convert(window.bounds, from: window)
    let screenBounds = scene.screen.coordinateSpace.bounds
    let touchesTop = windowFrame.minY <= screenBounds.minY + 32
    let systemTop = max(
      safeAreaInsets.top,
      max(window.safeAreaInsets.top, window.rootViewController?.view.safeAreaInsets.top ?? 0)
    )
    let adaptiveTop = max(0, max(vertical.minY - bounds.minY, systemTop))
    let leadingExtra = adaptive.minX - regular.minX
    let trailingExtra = regular.maxX - adaptive.maxX

    WindowCornerInsetSupport.updateInsets(
      [
        "leading": Double(max(0, adaptive.minX - bounds.minX)),
        "trailing": Double(max(0, bounds.maxX - adaptive.maxX)),
        "top": Double(adaptiveTop),
        "windowTouchesTop": touchesTop ? 1 : 0,
        "controlsVisible": leadingExtra > 0.5 || trailingExtra > 0.5 ? 1 : 0,
      ],
      for: scene
    )
  }

  override func safeAreaInsetsDidChange() {
    super.safeAreaInsetsDidChange()
    setNeedsLayout()
  }
}
