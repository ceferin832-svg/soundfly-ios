import UIKit
import Flutter
import AVFoundation

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Configure audio session for background playback
    do {
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(.playback, mode: .default, options: [])
      try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
      print("✅ Audio session configured for background playback")
    } catch {
      print("❌ Audio session error: \(error)")
    }
    
    // Keep app active for audio
    application.beginReceivingRemoteControlEvents()
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  override func applicationDidEnterBackground(_ application: UIApplication) {
    // Ensure audio session stays active in background
    do {
      try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
      print("✅ Keeping audio session active in background")
    } catch {
      print("❌ Error keeping audio active: \(error)")
    }
  }
  
  override func applicationWillEnterForeground(_ application: UIApplication) {
    do {
      try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
    } catch {
      print("Error reactivating audio: \(error)")
    }
  }
}
