import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Firebase and push notifications are handled by Flutter plugins
    // No native initialization needed here
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
