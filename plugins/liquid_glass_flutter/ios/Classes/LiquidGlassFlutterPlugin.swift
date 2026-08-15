import Flutter
import UIKit

public final class LiquidGlassFlutterPlugin: NSObject, FlutterPlugin {
  private var views: [Int64: LiquidGlassHostView] = [:]

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "liquid_glass_flutter",
      binaryMessenger: registrar.messenger()
    )
    let instance = LiquidGlassFlutterPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.register(
      LiquidGlassViewFactory(plugin: instance),
      withId: "liquid_glass_flutter/view"
    )
  }

  fileprivate func register(view: LiquidGlassHostView, id: Int64) {
    views[id] = view
  }

  fileprivate func unregisterView(id: Int64) {
    views.removeValue(forKey: id)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isLiquidGlassSupported":
      result(Self.isLiquidGlassSupported())
    case "updateView":
      guard
        let arguments = call.arguments as? [String: Any],
        let viewId = Self.int64Value(from: arguments["id"])
      else {
        result(
          FlutterError(
            code: "bad-arguments",
            message: "updateView requires an integer id.",
            details: nil
          )
        )
        return
      }

      views[viewId]?.apply(arguments: arguments)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  fileprivate static func isLiquidGlassSupported() -> Bool {
#if compiler(>=6.2)
    if #available(iOS 26.0, *) {
      if requiresCompatibilityMode() {
        return false
      }

      guard let glassEffectClass = NSClassFromString("UIGlassEffect") as? NSObject.Type else {
        return false
      }

      return glassEffectClass.responds(to: Selector(("effectWithStyle:")))
    }
#endif
    return false
  }

  private static func requiresCompatibilityMode() -> Bool {
    if let value = Bundle.main.object(forInfoDictionaryKey: "UIDesignRequiresCompatibility") as? Bool {
      return value
    }
    if let value = Bundle.main.object(forInfoDictionaryKey: "UIDesignRequiresCompatibility") as? NSNumber {
      return value.boolValue
    }
    return false
  }

  private static func int64Value(from value: Any?) -> Int64? {
    if let value = value as? NSNumber {
      return value.int64Value
    }
    if let value = value as? Int {
      return Int64(value)
    }
    return nil
  }
}

private final class LiquidGlassViewFactory: NSObject, FlutterPlatformViewFactory {
  private weak var plugin: LiquidGlassFlutterPlugin?

  init(plugin: LiquidGlassFlutterPlugin) {
    self.plugin = plugin
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    LiquidGlassPlatformView(
      frame: frame,
      viewIdentifier: viewId,
      arguments: args,
      plugin: plugin
    )
  }
}

private final class LiquidGlassPlatformView: NSObject, FlutterPlatformView {
  private let viewId: Int64
  private weak var plugin: LiquidGlassFlutterPlugin?
  private let hostView: LiquidGlassHostView

  init(
    frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?,
    plugin: LiquidGlassFlutterPlugin?
  ) {
    self.viewId = viewId
    self.plugin = plugin
    self.hostView = LiquidGlassHostView(frame: frame)
    super.init()

    plugin?.register(view: hostView, id: viewId)
    hostView.apply(arguments: args as? [String: Any] ?? [:])
  }

  deinit {
    plugin?.unregisterView(id: viewId)
  }

  func view() -> UIView {
    hostView
  }
}

private final class LiquidGlassHostView: UIView {
  private let effectView = UIVisualEffectView(effect: nil)
  private let tintOverlayView = UIView(frame: .zero)
  private var configuration = LiquidGlassConfiguration()

  override init(frame: CGRect) {
    super.init(frame: frame)
    isOpaque = false
    backgroundColor = .clear
    isUserInteractionEnabled = false
    effectView.isOpaque = false
    effectView.backgroundColor = .clear
    effectView.contentView.isUserInteractionEnabled = false
    tintOverlayView.isOpaque = false
    tintOverlayView.isUserInteractionEnabled = false
    addSubview(effectView)
    addSubview(tintOverlayView)
  }

  required init?(coder: NSCoder) {
    return nil
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    effectView.frame = bounds
    tintOverlayView.frame = bounds
    layer.cornerRadius = configuration.cornerRadius
    layer.masksToBounds = configuration.cornerRadius > 0
  }

  func apply(arguments: [String: Any]) {
    configuration = LiquidGlassConfiguration(arguments: arguments)
    apply(configuration: configuration)
  }

  private func apply(configuration: LiquidGlassConfiguration) {
    layer.cornerRadius = configuration.cornerRadius
    layer.masksToBounds = configuration.cornerRadius > 0
    effectView.contentView.isUserInteractionEnabled = false
    tintOverlayView.backgroundColor = .clear

    if #available(iOS 13.0, *) {
      overrideUserInterfaceStyle = configuration.colorScheme.interfaceStyle
    }

#if compiler(>=6.2)
    if #available(iOS 26.0, *), LiquidGlassFlutterPlugin.isLiquidGlassSupported() {
      applyNativeGlass(configuration: configuration)
      return
    }
#endif

    applyFallbackMaterial(configuration: configuration)
  }

#if compiler(>=6.2)
  @available(iOS 26.0, *)
  private func applyNativeGlass(configuration: LiquidGlassConfiguration) {
    guard let style = configuration.effect.glassStyle else {
      UIView.animate {
        self.effectView.effect = UIVisualEffect()
      }
      return
    }

    let effect = UIGlassEffect(style: style)
    effect.isInteractive = configuration.interactive
    effect.tintColor = configuration.tintColor

    if effectView.effect == nil {
      effectView.effect = effect
    } else {
      UIView.animate {
        self.effectView.effect = effect
      }
    }
  }
#endif

  private func applyFallbackMaterial(configuration: LiquidGlassConfiguration) {
    switch configuration.effect {
    case .none:
      effectView.effect = nil
      tintOverlayView.backgroundColor = .clear
    case .clear, .regular:
      if #available(iOS 13.0, *) {
        effectView.effect = UIBlurEffect(style: configuration.colorScheme.blurStyle)
      } else {
        effectView.effect = UIBlurEffect(style: .light)
      }
      tintOverlayView.backgroundColor = configuration.fallbackTintColor
    }
  }
}

private struct LiquidGlassConfiguration {
  var interactive: Bool = false
  var effect: LiquidGlassEffectMode = .regular
  var tintColor: UIColor?
  var colorScheme: LiquidGlassColorScheme = .system
  var cornerRadius: CGFloat = 20

  init() {}

  init(arguments: [String: Any]) {
    interactive = arguments["interactive"] as? Bool ?? false
    effect = LiquidGlassEffectMode(rawValue: arguments["effect"] as? String ?? "regular") ?? .regular
    tintColor = UIColor(argbValue: arguments["tintColor"])
    colorScheme = LiquidGlassColorScheme(rawValue: arguments["colorScheme"] as? String ?? "system") ?? .system

    if let value = arguments["cornerRadius"] as? NSNumber {
      cornerRadius = CGFloat(value.doubleValue)
    } else if let value = arguments["cornerRadius"] as? Double {
      cornerRadius = CGFloat(value)
    } else if let value = arguments["cornerRadius"] as? Int {
      cornerRadius = CGFloat(value)
    }
  }

  var fallbackTintColor: UIColor {
    let alpha = effect == .regular ? 0.15 : 0.08
    if let tintColor {
      return tintColor.withAlphaComponent(alpha)
    }
    let white = colorScheme == .dark ? 1.0 : 0.92
    return UIColor(white: white, alpha: alpha)
  }
}

private enum LiquidGlassEffectMode: String {
  case regular
  case clear
  case none

#if compiler(>=6.2)
  @available(iOS 26.0, *)
  var glassStyle: UIGlassEffect.Style? {
    switch self {
    case .regular:
      return .regular
    case .clear:
      return .clear
    case .none:
      return nil
    }
  }
#endif
}

private enum LiquidGlassColorScheme: String {
  case light
  case dark
  case system

  @available(iOS 13.0, *)
  var interfaceStyle: UIUserInterfaceStyle {
    switch self {
    case .light:
      return .light
    case .dark:
      return .dark
    case .system:
      return .unspecified
    }
  }

  @available(iOS 13.0, *)
  var blurStyle: UIBlurEffect.Style {
    switch self {
    case .light:
      return .systemUltraThinMaterialLight
    case .dark:
      return .systemUltraThinMaterialDark
    case .system:
      return .systemUltraThinMaterial
    }
  }
}

private extension UIColor {
  convenience init?(argbValue: Any?) {
    guard let number = argbValue as? NSNumber else {
      return nil
    }

    let value = number.uint32Value
    let alpha = CGFloat((value >> 24) & 0xff) / 255.0
    let red = CGFloat((value >> 16) & 0xff) / 255.0
    let green = CGFloat((value >> 8) & 0xff) / 255.0
    let blue = CGFloat(value & 0xff) / 255.0
    self.init(red: red, green: green, blue: blue, alpha: alpha)
  }
}
