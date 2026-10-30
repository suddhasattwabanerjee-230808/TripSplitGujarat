import Flutter
import GoogleMaps
import UIKit
import UserNotifications
import flutter_local_notifications
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Mirrors Android's manifest-placeholder injection (see AndroidManifest.xml /
    // build.gradle.kts): CI writes the real key into Info.plist's GMSApiKey before
    // building, so it never lives in source.
    if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String, !apiKey.isEmpty {
      GMSServices.provideAPIKey(apiKey)
    }
    // Lets flutter_local_notifications show notifications and hear taps.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    // ExpenseNotifier's background check: iOS wants the task registered before
    // launch finishes, under an id listed in BGTaskSchedulerPermittedIdentifiers.
    // iOS decides when it really runs; 15 minutes is only the earliest.
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "trip_split.check_expenses",
      earliestBeginInSeconds: NSNumber(value: 15 * 60)
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    // The background check and notification actions run in their own engines,
    // which need the plugins too.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TripSplitChannels") {
      TripSplitChannels.register(with: registrar.messenger())
    }
  }
}

/// The iOS side of the email and UPI channels MainActivity.kt answers on
/// Android. iOS can't see other apps' payments or icons, so those answers are
/// empty and the Dart side falls back to asking ("Mark Paid") or a letter tile.
enum TripSplitChannels {
  /// UPI apps that can be opened by URL scheme, Google Pay and PhonePe first.
  /// Each scheme must be in Info.plist's LSApplicationQueriesSchemes, or
  /// canOpenURL says it isn't installed.
  private static let upiApps: [(id: String, label: String, scheme: String, payPath: String)] = [
    ("gpay", "Google Pay", "tez", "upi/pay"),
    ("phonepe", "PhonePe", "phonepe", "pay"),
    ("paytm", "Paytm", "paytmmp", "pay"),
    ("bhim", "BHIM", "bhim", "upi/pay"),
    ("cred", "CRED", "credpay", "upi/pay"),
  ]

  private static let unreserved = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

  static func register(with messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "tripsplit/email", binaryMessenger: messenger).setMethodCallHandler(email)
    FlutterMethodChannel(name: "tripsplit/upi_pay", binaryMessenger: messenger).setMethodCallHandler(upiPay)
  }

  private static func email(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard call.method == "compose" else { return result(FlutterMethodNotImplemented) }
    let args = call.arguments as? [String: Any] ?? [:]
    let to = encode(args["to"] as? String, keeping: "@")
    let url = URL(string: "mailto:\(to)?subject=\(encode(args["subject"] as? String))&body=\(encode(args["body"] as? String))")
    open(url) { ok in
      result(ok ? nil : FlutterError(code: "no_email_app", message: "No email app is installed", details: nil))
    }
  }

  private static func upiPay(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let app = upiApps.first { $0.id == args["package"] as? String }
    switch call.method {
    case "apps":
      let installed = upiApps.filter { URL(string: "\($0.scheme)://").map { UIApplication.shared.canOpenURL($0) } ?? false }
      result(installed.map {
        ["package": $0.id, "label": $0.label, "icon": FlutterStandardTypedData(bytes: Data()), "canPay": true] as [String: Any]
      })
    case "pay":
      // The upi://pay link, sent to the chosen app's own scheme (for upi://
      // itself iOS picks an app). Nothing comes back, so the status is unknown.
      guard let link = args["uri"] as? String else {
        return result(FlutterError(code: "bad_args", message: "Missing UPI link", details: nil))
      }
      let query = link.split(separator: "?", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
      open(URL(string: app.map { "\($0.scheme)://\($0.payPath)?\(query)" } ?? link)) { ok in
        result(ok ? "" as Any : FlutterError(code: "no_upi_app", message: "No UPI app is installed", details: nil))
      }
    case "open", "payTo", "scan":
      // No deep link to a UPI ID field or scanner on iOS: the app's home screen.
      open(app.flatMap { URL(string: "\($0.scheme)://") }) { result($0) }
    case "shareQr":
      // iOS can't hand an image to one chosen app; Dart then copies the UPI ID and calls payTo.
      result(false)
    case "expectSettle", "cancelSettle":
      result(nil)
    case "settleStatus":
      result([String: Any]())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func encode(_ text: String?, keeping extra: String = "") -> String {
    text?.addingPercentEncoding(withAllowedCharacters: unreserved.union(CharacterSet(charactersIn: extra))) ?? ""
  }

  private static func open(_ url: URL?, done: @escaping (Bool) -> Void) {
    guard let url = url else { return done(false) }
    UIApplication.shared.open(url, options: [:], completionHandler: done)
  }
}
