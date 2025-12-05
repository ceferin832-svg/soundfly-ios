import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';

/// Native Audio Player Service using just_audio
/// This provides robust background audio support on iOS
class NativeAudioPlayer {
  static final AudioPlayer _player = AudioPlayer();
  static String? _currentUrl;
  static bool _isInitialized = false;
  
  /// Initialize the audio player and audio session
  static Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Configure audio session for background playback
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.allowBluetooth |
            AVAudioSessionCategoryOptions.allowAirPlay,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        avAudioSessionRouteSharingPolicy: AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ));
      
      // Handle audio interruptions (phone calls, etc.)
      session.interruptionEventStream.listen((event) {
        if (event.begin) {
          // Interruption began - pause playback
          _player.pause();
        } else {
          // Interruption ended - resume if we should
          if (event.type == AudioInterruptionType.pause) {
            _player.play();
          }
        }
      });
      
      // Handle becoming noisy (headphones unplugged)
      session.becomingNoisyEventStream.listen((_) {
        _player.pause();
      });
      
      _isInitialized = true;
      debugPrint('NativeAudioPlayer initialized with just_audio');
    } catch (e) {
      debugPrint('Error initializing NativeAudioPlayer: $e');
    }
  }
  
  /// Play audio from URL
  static Future<void> play(String url) async {
    if (!_isInitialized) await initialize();
    
    try {
      // Only reload if URL changed
      if (url != _currentUrl) {
        _currentUrl = url;
        await _player.setUrl(url);
        debugPrint('NativeAudioPlayer: Loading $url');
      }
      
      await _player.play();
      debugPrint('NativeAudioPlayer: Playing');
    } catch (e) {
      debugPrint('Error playing audio: $e');
    }
  }
  
  /// Pause playback
  static Future<void> pause() async {
    try {
      await _player.pause();
      debugPrint('NativeAudioPlayer: Paused');
    } catch (e) {
      debugPrint('Error pausing audio: $e');
    }
  }
  
  /// Resume playback
  static Future<void> resume() async {
    try {
      await _player.play();
      debugPrint('NativeAudioPlayer: Resumed');
    } catch (e) {
      debugPrint('Error resuming audio: $e');
    }
  }
  
  /// Stop playback
  static Future<void> stop() async {
    try {
      await _player.stop();
      _currentUrl = null;
      debugPrint('NativeAudioPlayer: Stopped');
    } catch (e) {
      debugPrint('Error stopping audio: $e');
    }
  }
  
  /// Seek to position in seconds
  static Future<void> seek(double positionSeconds) async {
    try {
      await _player.seek(Duration(milliseconds: (positionSeconds * 1000).round()));
      debugPrint('NativeAudioPlayer: Seeked to $positionSeconds');
    } catch (e) {
      debugPrint('Error seeking: $e');
    }
  }
  
  /// Set volume (0.0 to 1.0)
  static Future<void> setVolume(double volume) async {
    try {
      await _player.setVolume(volume);
    } catch (e) {
      debugPrint('Error setting volume: $e');
    }
  }
  
  /// Get current position in seconds
  static double get position {
    return _player.position.inMilliseconds / 1000.0;
  }
  
  /// Get duration in seconds
  static double get duration {
    return (_player.duration?.inMilliseconds ?? 0) / 1000.0;
  }
  
  /// Check if playing
  static bool get isPlaying {
    return _player.playing;
  }
  
  /// Get the player instance for advanced usage
  static AudioPlayer get player => _player;
  
  /// Dispose player
  static Future<void> dispose() async {
    await _player.dispose();
    _isInitialized = false;
  }
}
