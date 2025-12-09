import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// Service to extract audio URLs from YouTube using Cobalt API
/// Cobalt is a free, open-source media downloader
class CobaltService {
  // List of public Cobalt API instances to try (no JWT required)
  // Updated 2025: Many instances now require JWT auth, these are verified working
  static const List<String> _apiInstances = [
    'https://cobalt-api.kwiatekmiki.com',  // Verified working without JWT
  ];
  
  static String? _workingInstance;
  static bool _isExtracting = false;
  
  /// Returns the direct audio URL or null if extraction fails
  static Future<String?> extractAudioUrl(String videoId) async {
    if (_isExtracting) {
      debugPrint('[Cobalt] Already extracting, skipping');
      return null;
    }
    
    _isExtracting = true;
    
    final youtubeUrl = 'https://www.youtube.com/watch?v=$videoId';
    debugPrint('[Cobalt] Extracting audio for: $videoId');
    
    // Try working instance first, then others
    final instancesToTry = _workingInstance != null 
        ? [_workingInstance!, ..._apiInstances.where((i) => i != _workingInstance)]
        : _apiInstances;
    
    for (final instance in instancesToTry) {
      try {
        final result = await _tryExtract(instance, youtubeUrl);
        if (result != null) {
          _workingInstance = instance;
          _isExtracting = false;
          debugPrint('[Cobalt] ✅ Success with $instance');
          return result;
        }
      } catch (e) {
        debugPrint('[Cobalt] ❌ Failed with $instance: $e');
      }
    }
    
    _isExtracting = false;
    debugPrint('[Cobalt] All instances failed');
    return null;
  }
  /// Instance method for compatibility with home_screen.dart
  Future<String?> getAudioUrl(String youtubeUrl) async {
    if (_isExtracting) {
      debugPrint('[Cobalt] Already extracting, skipping');
      return null;
    }
    _isExtracting = true;
    final instancesToTry = _workingInstance != null 
        ? [_workingInstance!, ..._apiInstances.where((i) => i != _workingInstance)]
        : _apiInstances;
    for (final instance in instancesToTry) {
      try {
        final result = await _tryExtract(instance, youtubeUrl);
        if (result != null) {
          _workingInstance = instance;
          _isExtracting = false;
          debugPrint('[Cobalt] 	 Success with $instance');
          return result;
        }
      } catch (e) {
        debugPrint('[Cobalt]  Failed with $instance: $e');
      }
    }
    _isExtracting = false;
    debugPrint('[Cobalt] All instances failed');
    return null;
  }
  
  static Future<String?> _tryExtract(String apiUrl, String youtubeUrl) async {
    debugPrint('[Cobalt] Trying: $apiUrl');
    
    final response = await http.post(
      Uri.parse(apiUrl),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'url': youtubeUrl,
        'downloadMode': 'audio',
        'audioFormat': 'mp3',
        'audioBitrate': '128',
      }),
    ).timeout(const Duration(seconds: 15));
    
    debugPrint('[Cobalt] Response status: ${response.statusCode}');
    debugPrint('[Cobalt] Response body: ${response.body.substring(0, min(200, response.body.length))}...');
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final status = data['status'];
      
      if (status == 'tunnel' || status == 'redirect') {
        final url = data['url'];
        if (url != null && url.isNotEmpty) {
          debugPrint('[Cobalt] Got audio URL: ${url.substring(0, min(80, url.length))}...');
          return url;
        }
      } else if (status == 'picker') {
        // Multiple items, try to get audio
        final audio = data['audio'];
        if (audio != null && audio.isNotEmpty) {
          debugPrint('[Cobalt] Got picker audio URL');
          return audio;
        }
      } else if (status == 'error') {
        final error = data['error'];
        debugPrint('[Cobalt] API error: $error');
      }
    }
    
    return null;
  }
  
  static int min(int a, int b) => a < b ? a : b;
}
