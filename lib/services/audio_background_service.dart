import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

/// Audio Background Service
/// 
/// Manages the audio session configuration to allow
/// background audio playback in the WebView.
class AudioBackgroundService {
  static AudioSession? _audioSession;
  static bool _isInitialized = false;

  /// Initialize the audio session for background playback
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _audioSession = await AudioSession.instance;
      
      // Configure for music playback with mixing enabled
      await _audioSession!.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers |
            AVAudioSessionCategoryOptions.allowAirPlay |
            AVAudioSessionCategoryOptions.defaultToSpeaker,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        avAudioSessionRouteSharingPolicy: AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ));

      // Listen to audio interruptions
      _audioSession!.interruptionEventStream.listen((event) {
        if (event.begin) {
          // Audio interrupted (phone call, etc.)
          debugPrint('Audio interrupted: ${event.type}');
        } else {
          // Audio interruption ended
          debugPrint('Audio interruption ended');
          // Reactivate session after interruption
          _audioSession!.setActive(true);
        }
      });

      // Listen to becoming noisy (headphones unplugged)
      _audioSession!.becomingNoisyEventStream.listen((_) {
        debugPrint('Headphones unplugged - audio continues in speaker');
      });

      // Activate the session
      await _audioSession!.setActive(true);

      _isInitialized = true;
      debugPrint('Audio background service initialized successfully');
    } catch (e) {
      debugPrint('Error initializing audio background service: $e');
    }
  }

  /// Activate the audio session (call when starting playback)
  static Future<void> activate() async {
    try {
      await _audioSession?.setActive(true);
      debugPrint('Audio session activated');
    } catch (e) {
      debugPrint('Error activating audio session: $e');
    }
  }

  /// Deactivate the audio session (call when stopping playback)
  static Future<void> deactivate() async {
    try {
      await _audioSession?.setActive(false);
      debugPrint('Audio session deactivated');
    } catch (e) {
      debugPrint('Error deactivating audio session: $e');
    }
  }

  /// Check if the audio session is active
  static bool get isActive => _isInitialized;
}
