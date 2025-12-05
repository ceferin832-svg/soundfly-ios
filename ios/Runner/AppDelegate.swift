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
    
    // Configure AVAudioSession for background audio playback
    configureAudioSession()
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  private func configureAudioSession() {
    do {
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(
        .playback,
        mode: .default,
        options: [.allowAirPlay, .allowBluetooth, .allowBluetoothA2DP]
      )
      try audioSession.setActive(true)
      print("Audio session configured for background playback")
    } catch {
      print("Failed to configure audio session: \(error)")
    }
  }
  
  override func applicationDidEnterBackground(_ application: UIApplication) {
    do {
      try AVAudioSession.sharedInstance().setActive(true)
      print("Keeping audio session active in background")
    } catch {
      print("Error keeping audio active: \(error)")
    }
    super.applicationDidEnterBackground(application)
  }
  
  override func applicationWillEnterForeground(_ application: UIApplication) {
    do {
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      print("Error reactivating audio: \(error)")
    }
    super.applicationWillEnterForeground(application)
  }
}
