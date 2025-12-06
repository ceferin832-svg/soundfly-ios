import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

/// Native Audio Player Service using just_audio
/// This provides robust background audio support on iOS
class NativeAudioPlayer {
  static final AudioPlayer _player = AudioPlayer();
  static String? _currentUrl;
  static String? _currentTitle;
  static String? _currentArtist;
  static String? _currentArtwork;
  static bool _isInitialized = false;
  
  /// Initialize the audio player (no audio session config - JustAudioBackground handles it)
  static Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    debugPrint('NativeAudioPlayer initialized');
  }
  
  /// Play audio from URL with optional metadata for lock screen
  static Future<void> play(String url, {String? title, String? artist, String? artworkUrl}) async {
    if (!_isInitialized) await initialize();
    
    try {
      // Store metadata
      _currentTitle = title ?? 'Soundfly';
      _currentArtist = artist ?? 'Unknown Artist';
      _currentArtwork = artworkUrl;
      
      // Only reload if URL changed
      if (url != _currentUrl) {
        _currentUrl = url;
        
        // Use AudioSource with metadata for lock screen controls
        final audioSource = AudioSource.uri(
          Uri.parse(url),
          tag: MediaItem(
            id: url,
            title: _currentTitle!,
            artist: _currentArtist,
            artUri: _currentArtwork != null ? Uri.parse(_currentArtwork!) : null,
          ),
        );
        
        await _player.setAudioSource(audioSource);
        debugPrint('NativeAudioPlayer: Loading $url with metadata');
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
