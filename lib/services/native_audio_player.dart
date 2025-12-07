import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_session/audio_session.dart';

/// Native Audio Player Service using just_audio
/// This provides robust background audio support on iOS
class NativeAudioPlayer {
  static final AudioPlayer _player = AudioPlayer();
  static String? _currentUrl;
  static String? _currentTitle;
  static String? _currentArtist;
  static String? _currentArtwork;
  static bool _isInitialized = false;
  static AudioSession? _audioSession;
  
  /// Initialize the audio player with proper audio session for background
  static Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Get and configure audio session for background playback
      _audioSession = await AudioSession.instance;
      await _audioSession!.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
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
      
      // Activate the session
      await _audioSession!.setActive(true);
      debugPrint('NativeAudioPlayer: Audio session configured and activated');
      
      _isInitialized = true;
      debugPrint('NativeAudioPlayer initialized with background support');
    } catch (e) {
      debugPrint('Error initializing audio session: $e');
      _isInitialized = true;
    }
  }
  
  /// Play audio from URL or local file path with optional metadata for lock screen
  static Future<void> play(String source, {String? title, String? artist, String? artworkUrl}) async {
    if (!_isInitialized) await initialize();
    
    try {
      // CRITICAL: Ensure audio session is active before playing
      if (_audioSession != null) {
        await _audioSession!.setActive(true);
        debugPrint('NativeAudioPlayer: Audio session activated');
      }
      
      // Store metadata
      _currentTitle = title ?? 'Soundfly';
      _currentArtist = artist ?? 'Unknown Artist';
      _currentArtwork = artworkUrl;
      
      // Always reload for new sources
      _currentUrl = source;
      
      // Determine if source is a local file or URL
      final bool isLocalFile = source.startsWith('/') || source.startsWith('file://');
      final Uri sourceUri = isLocalFile 
          ? Uri.file(source.replaceFirst('file://', ''))
          : Uri.parse(source);
      
      debugPrint('NativeAudioPlayer: Source type = ${isLocalFile ? "LOCAL FILE" : "URL"}');
      debugPrint('NativeAudioPlayer: URI = $sourceUri');
      
      // Use AudioSource with metadata for lock screen controls
      final audioSource = AudioSource.uri(
        sourceUri,
        tag: MediaItem(
          id: source,
          title: _currentTitle!,
          artist: _currentArtist,
          artUri: _currentArtwork != null ? Uri.parse(_currentArtwork!) : null,
        ),
      );
      
      debugPrint('NativeAudioPlayer: Setting audio source...');
      await _player.setAudioSource(audioSource);
      
      debugPrint('NativeAudioPlayer: Starting playback...');
      await _player.play();
      
      // Wait a bit for playback to actually start
      await Future.delayed(const Duration(milliseconds: 500));
      
      debugPrint('NativeAudioPlayer: Playing = ${_player.playing}, state = ${_player.playerState.processingState}');
    } catch (e) {
      debugPrint('Error playing audio: $e');
      rethrow;
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
