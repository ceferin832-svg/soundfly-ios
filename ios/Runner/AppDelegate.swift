import UIKit
import Flutter
import AVFoundation
import WebKit

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
      
      // Set category for playback - this is the key for background audio
      try audioSession.setCategory(
        .playback,
        mode: .default,
        options: [.allowAirPlay, .allowBluetooth, .allowBluetoothA2DP]
      )
      
      // Activate the audio session
      try audioSession.setActive(true)
      
      print("Audio session configured successfully for background playback")
    } catch {
      print("Failed to configure audio session: \(error.localizedDescription)")
    }
  }
  
  // CRITICAL: Keep audio playing when app goes to background
  override func applicationDidEnterBackground(_ application: UIApplication) {
    // Re-activate audio session when entering background
    do {
      try AVAudioSession.sharedInstance().setActive(true)
      print("Audio session kept active in background")
    } catch {
      print("Failed to keep audio session active: \(error)")
    }
    super.applicationDidEnterBackground(application)
  }
  
  override func applicationWillEnterForeground(_ application: UIApplication) {
    // Ensure audio session is active when coming back
    do {
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      print("Failed to activate audio session: \(error)")
    }
    super.applicationWillEnterForeground(application)
  }
}
