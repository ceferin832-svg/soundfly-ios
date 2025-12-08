import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show min;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../config/app_config.dart';
import '../config/app_strings.dart';
import '../config/app_theme.dart';
import '../services/admob_service.dart';
import '../services/native_audio_player.dart';
import '../services/cobalt_service.dart';
import 'no_internet_screen.dart';

/// Home Screen with InAppWebView
/// 
/// Displays the Soundfly web application in a WebView with full
/// audio/video support for iOS using native audio player for background playback.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  InAppWebViewController? _webViewController;
  bool _isLoading = true;
  bool _hasError = false;
  bool _isConnected = true;
  int _pageLoadCount = 0;
  DateTime? _lastBackPress;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  
  final GlobalKey webViewKey = GlobalKey();

  // WebView settings optimized for audio/video playback
  InAppWebViewSettings get _webViewSettings => InAppWebViewSettings(
    // Basic settings
    javaScriptEnabled: true,
    javaScriptCanOpenWindowsAutomatically: true,
    
    // Media playback settings - CRITICAL for audio
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,
    allowsAirPlayForMediaPlayback: true,
    allowsPictureInPictureMediaPlayback: true,
    
    // iOS specific settings
    allowsBackForwardNavigationGestures: true,
    allowsLinkPreview: false,
    isFraudulentWebsiteWarningEnabled: false,
    limitsNavigationsToAppBoundDomains: false,
    
    // Allow mixed content (http in https)
    mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
    
    // Cache and storage
    cacheEnabled: true,
    domStorageEnabled: true,
    databaseEnabled: true,
    
    // User agent - use default Safari to avoid detection issues
    userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
    
    // Allow universal access
    allowUniversalAccessFromFileURLs: true,
    allowFileAccessFromFileURLs: true,
    
    // Transparency
    transparentBackground: false,
    
    // Disable annoying features
    disableContextMenu: false,
    supportZoom: true,
    
    // iOS 15+ settings
    upgradeKnownHostsToHTTPS: false,
    isInspectable: true,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeConnectivity();
    _enableWakelock();
    NativeAudioPlayer.initialize();
  }
  
  void _enableWakelock() {
    WakelockPlus.enable();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.paused:
        // App went to background - just_audio_background handles background playback
        debugPrint('App paused - native audio continues in background');
        break;
      case AppLifecycleState.resumed:
        debugPrint('App resumed');
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }
  
  /// Try to keep audio alive when going to background
  Future<void> _keepAudioAlive() async {
    if (_webViewController == null) return;
    
    try {
      await _webViewController!.evaluateJavascript(source: '''
        (function() {
          // Find all audio elements and ensure they keep playing
          var audios = document.querySelectorAll('audio');
          audios.forEach(function(audio) {
            if (!audio.paused) {
              console.log('Keeping audio alive in background');
              // Store reference to keep it playing
              window._backgroundAudio = audio;
            }
          });
          
          // Also check for any AudioContext
          if (window.AudioContext || window.webkitAudioContext) {
            var ctx = new (window.AudioContext || window.webkitAudioContext)();
            if (ctx.state === 'suspended') {
              ctx.resume();
            }
          }
        })();
      ''');
    } catch (e) {
      debugPrint('Error keeping audio alive: $e');
    }
  }

  void _initializeConnectivity() {
    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen((ConnectivityResult result) {
      final isConnected = result != ConnectivityResult.none;
      
      if (isConnected != _isConnected) {
        setState(() {
          _isConnected = isConnected;
        });
        
        if (isConnected) {
          _showSnackBar(AppStrings.internetRestored, Colors.green);
          _webViewController?.reload();
        } else {
          _showSnackBar(AppStrings.internetLost, Colors.red);
        }
      }
    });
    
    _checkConnectivity();
  }

  Future<void> _checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    setState(() {
      _isConnected = result != ConnectivityResult.none;
    });
  }

  void _showInterstitialAd() {
    if (AppConfig.admobEnabled &&
        _pageLoadCount > 0 &&
        _pageLoadCount % AppConfig.interstitialInterval == 0) {
      AdMobService.showInterstitialAd();
    }
  }

  void _showSnackBar(String message, Color backgroundColor) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<bool> _onWillPop() async {
    if (_webViewController != null && await _webViewController!.canGoBack()) {
      _webViewController!.goBack();
      return false;
    }
    
    final now = DateTime.now();
    if (_lastBackPress == null ||
        now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
      _lastBackPress = now;
      _showSnackBar(AppStrings.twiceExit, AppTheme.lightBlack);
      return false;
    }
    
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isConnected) {
      return NoInternetScreen(
        onRetry: () async {
          await _checkConnectivity();
          if (_isConnected) {
            _webViewController?.reload();
          }
        },
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              // WebView
              InAppWebView(
                key: webViewKey,
                initialUrlRequest: URLRequest(
                  url: WebUri(AppConfig.websiteUrl),
                ),
                initialSettings: _webViewSettings,
                onWebViewCreated: (controller) {
                  _webViewController = controller;
                  debugPrint('WebView created');
                  
                  // Add JavaScript handler for native audio player
                  controller.addJavaScriptHandler(
                    handlerName: 'nativeAudio',
                    callback: (args) {
                      if (args.isEmpty) return;
                      final command = args[0] as String;
                      final url = args.length > 1 ? args[1] as String : '';
                      final title = args.length > 2 ? args[2] as String : 'Soundfly';
                      final artist = args.length > 3 ? args[3] as String : 'Unknown';
                      
                      debugPrint('Native Audio Command: $command, URL: $url');
                      
                      switch (command) {
                        case 'play':
                          if (url.isNotEmpty) {
                            NativeAudioPlayer.play(url, title: title, artist: artist);
                          }
                          break;
                        case 'pause':
                          NativeAudioPlayer.pause();
                          break;
                        case 'resume':
                          NativeAudioPlayer.resume();
                          break;
                        case 'stop':
                        case 'ended':
                          NativeAudioPlayer.stop();
                          break;
                        case 'seek':
                          if (url.isNotEmpty) {
                            final position = double.tryParse(url) ?? 0;
                            NativeAudioPlayer.seek(position);
                          }
                          break;
                      }
                    },
                  );
                  
                  // Add handler for YouTube audio extraction and playback
                  controller.addJavaScriptHandler(
                    handlerName: 'youtubeAudio',
                    callback: (args) async {
                      if (args.isEmpty) return;
                      final command = args[0] as String;
                      final videoId = args.length > 1 ? args[1] as String : '';
                      
                      debugPrint('YouTube Audio Command: $command, VideoID: $videoId');
                      
                      switch (command) {
                        case 'prepare':
                        case 'play':
                        case 'background':
                          if (videoId.isNotEmpty) {
                            // Extract and play YouTube audio via native player
                            _playYouTubeAudio(videoId);
                          }
                          break;
                        case 'pause':
                          NativeAudioPlayer.pause();
                          break;
                        case 'ended':
                          NativeAudioPlayer.stop();
                          break;
                        case 'foreground':
                          // When app comes back, we could stop native and let WebView play
                          // But for now, keep native playing for consistency
                          break;
                      }
                    },
                  );
                  
                  // NOTE: Background audio is now handled entirely by just_audio_background
                  // No need for separate audio session management
                },
                onLoadStart: (controller, url) {
                  setState(() {
                    _isLoading = true;
                    _hasError = false;
                  });
                  // Inject early
                  _injectAudioFixes(controller);
                },
                onLoadStop: (controller, url) async {
                  setState(() {
                    _isLoading = false;
                  });
                  _pageLoadCount++;
                  _showInterstitialAd();
                  
                  // Inject JavaScript again after page loads
                  await _injectAudioFixes(controller);
                },
                onProgressChanged: (controller, progress) {
                  // Inject as soon as DOM is ready (around 30-50%)
                  if (progress > 30 && progress < 60) {
                    _injectAudioFixes(controller);
                  }
                },
                onReceivedError: (controller, request, error) {
                  if (request.isForMainFrame ?? true) {
                    setState(() {
                      _hasError = true;
                      _isLoading = false;
                    });
                  }
                },
                onConsoleMessage: (controller, consoleMessage) {
                  debugPrint('JS Console: ${consoleMessage.message}');
                },
                onPermissionRequest: (controller, request) async {
                  // Grant all permissions (audio, video, etc.)
                  return PermissionResponse(
                    resources: request.resources,
                    action: PermissionResponseAction.GRANT,
                  );
                },
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  final uri = navigationAction.request.url;
                  if (uri != null) {
                    final baseUrl = Uri.parse(AppConfig.websiteUrl);
                    if (uri.host != baseUrl.host && 
                        !uri.toString().startsWith('javascript:') &&
                        !uri.toString().startsWith('about:')) {
                      // External link - could open in browser
                      return NavigationActionPolicy.ALLOW;
                    }
                  }
                  return NavigationActionPolicy.ALLOW;
                },
              ),
              
              // Loading indicator
              if (_isLoading)
                Container(
                  color: AppTheme.white.withOpacity(0.8),
                  child: const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppTheme.primaryColor,
                      ),
                    ),
                  ),
                ),
              
              // Error view
              if (_hasError && !_isLoading)
                _buildErrorView(),
              
              // DEBUG: Native audio status indicator and test buttons
              Positioned(
                bottom: 100,
                right: 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Status indicator
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: NativeAudioPlayer.isPlaying ? Colors.green : Colors.grey,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        NativeAudioPlayer.isPlaying ? '🎵 Playing' : '⏸️ Stopped',
                        style: const TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Test YouTube extraction button (RED)
                    FloatingActionButton.small(
                      heroTag: 'testYouTube',
                      backgroundColor: Colors.red,
                      onPressed: _testYouTubeExtraction,
                      child: const Icon(Icons.play_arrow, color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    // Test MP3 button (PURPLE) - SoundHelix
                    FloatingActionButton.small(
                      heroTag: 'testAudio',
                      backgroundColor: Colors.purple,
                      onPressed: _testNativeAudio,
                      child: const Icon(Icons.music_note, color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    // Test another URL (BLUE) - Internet Archive
                    FloatingActionButton.small(
                      heroTag: 'testArchive',
                      backgroundColor: Colors.blue,
                      onPressed: _testAnotherAudio,
                      child: const Icon(Icons.cloud, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  /// Test YouTube extraction with a known video ID
  Future<void> _testYouTubeExtraction() async {
    // Use a popular music video ID for testing
    const testVideoId = 'dQw4w9WgXcQ'; // Never Gonna Give You Up
    
    _showSnackBar('Testing YouTube extraction: $testVideoId', Colors.orange);
    await _playYouTubeAudio(testVideoId);
  }
  
  /// Test native audio player with a sample MP3
  Future<void> _testNativeAudio() async {
    // Using a public domain audio file for testing
    const testUrl = 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3';
    
    if (NativeAudioPlayer.isPlaying) {
      await NativeAudioPlayer.pause();
      _showSnackBar('Native audio paused', Colors.orange);
    } else {
      await NativeAudioPlayer.play(
        testUrl,
        title: 'SoundHelix Song 1',
        artist: 'SoundHelix Test',
      );
      _showSnackBar('Playing test audio - minimize app to test background!', Colors.green);
    }
    setState(() {}); // Refresh UI
  }
  
  /// Test with another public audio URL (Internet Archive)
  Future<void> _testAnotherAudio() async {
    // Public domain audio from Internet Archive
    const testUrl = 'https://archive.org/download/testmp3testfile/mpthreetest.mp3';
    
    await NativeAudioPlayer.play(
      testUrl,
      title: 'Archive Test',
      artist: 'Internet Archive',
    );
    _showSnackBar('Playing Archive audio - test background!', Colors.blue);
    setState(() {});
  }
  
  /// Play YouTube audio using Cobalt API (free service)
  String? _currentYouTubeVideoId;
  bool _isExtracting = false;
  final CobaltService _cobaltService = CobaltService();
  String? _currentVideoTitle;
  String? _currentVideoArtist;
  
  Future<void> _playYouTubeAudio(String videoId) async {
    if (videoId.isEmpty) return;
    
    if (_isExtracting) {
      debugPrint('Already extracting, skipping');
      return;
    }
    
    if (videoId == _currentYouTubeVideoId && NativeAudioPlayer.isPlaying) {
      debugPrint('Already playing this video: $videoId');
      return;
    }
    
    _isExtracting = true;
    _currentYouTubeVideoId = videoId;
    
    debugPrint('=== EXTRACTING YOUTUBE AUDIO VIA COBALT ===');
    debugPrint('Video ID: $videoId');
    
    _showSnackBar('Extracting audio via Cobalt...', Colors.orange);
    
    try {
      // Build YouTube URL from video ID
      final youtubeUrl = 'https://www.youtube.com/watch?v=$videoId';
      
      // Use Cobalt to get audio URL
      
      if (audioUrl != null) {
        debugPrint('Cobalt returned audio URL: ${audioUrl.substring(0, min(100, audioUrl.length))}...');
        
        _isExtracting = false;
        
        // Play the audio
        _showSnackBar('Starting playback...', Colors.blue);
        
        await NativeAudioPlayer.play(
          audioUrl,
          title: _currentVideoTitle ?? 'Soundfly Music',
          artist: _currentVideoArtist ?? 'Unknown Artist',
        );
        
        // Wait for playback to stabilize
        await Future.delayed(const Duration(seconds: 2));
        
        if (NativeAudioPlayer.isPlaying) {
          _showSnackBar('🎵 Cobalt: Playing! Test background now', Colors.green);
        } else {
          _showSnackBar('⚠️ Playback may have issues', Colors.orange);
      final audioUrl = await _cobaltService.getAudioUrl(youtubeUrl);
      if (audioUrl != null) {
        // Use min with explicit int type
        debugPrint('Cobalt returned audio URL: ${audioUrl.substring(0, min<int>(100, audioUrl.length))}...');
        _isExtracting = false;
        // Play the audio
        _showSnackBar('Starting playback...', Colors.blue);
        await NativeAudioPlayer.play(
          audioUrl,
          title: _currentVideoTitle ?? 'Soundfly Music',
          artist: _currentVideoArtist ?? 'Unknown Artist',
        );
        // Wait for playback to stabilize
        await Future.delayed(const Duration(seconds: 2));
        if (NativeAudioPlayer.isPlaying) {
          _showSnackBar('🎵 Cobalt: Playing! Test background now', Colors.green);
        } else {
          _showSnackBar('⚠️ Playback may have issues', Colors.orange);
        }
        setState(() {});
      } else {
        _isExtracting = false;
        debugPrint('Cobalt returned null - no audio URL');
        _showSnackBar('Cobalt: Could not extract audio', Colors.red);
      }
        }
        setState(() {});
      } else {
        _isExtracting = false;
        debugPrint('Cobalt returned null - no audio URL');
        _showSnackBar('Cobalt: Could not extract audio', Colors.red);
      }
    } catch (e) {
      _isExtracting = false;
      debugPrint('Cobalt extraction error: $e');
      _showSnackBar('Cobalt failed: ${e.toString().substring(0, min(50, e.toString().length))}', Colors.red);
    }
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _injectAudioFixes(InAppWebViewController controller) async {
    await controller.evaluateJavascript(source: '''
      (function() {
        console.log('=== Soundfly Audio Bridge v13 - YouTube Search API Intercept ===');
        
        window._sfBridge = {
          active: false,
          currentVideoId: null,
          lastVideoId: null,
          intercepting: false,
          currentTrackInfo: null
        };
        
        // Show notification
        function showNotification(msg, color) {
          console.log('[SF-Bridge] ' + msg);
          var toast = document.createElement('div');
          toast.style.cssText = 'position:fixed;top:80px;left:10px;right:10px;background:' + (color || '#333') + ';color:#fff;padding:12px;border-radius:8px;z-index:999999;font-size:14px;text-align:center;box-shadow:0 4px 20px rgba(0,0,0,0.5);font-weight:bold;';
          toast.textContent = msg;
          document.body.appendChild(toast);
          setTimeout(function() { toast.remove(); }, 4000);
        }
        
        // Send YouTube video ID to Flutter for native playback
        function playYouTubeNatively(videoId, trackInfo) {
          if (!videoId || window._sfBridge.intercepting) return;
          if (videoId === window._sfBridge.lastVideoId) return;
          
          window._sfBridge.intercepting = true;
          window._sfBridge.lastVideoId = videoId;
          window._sfBridge.currentVideoId = videoId;
          window._sfBridge.currentTrackInfo = trackInfo;
          
          console.log('[SF-Bridge] Sending YouTube ID to Flutter: ' + videoId);
          showNotification('🎵 Preparando: ' + (trackInfo ? trackInfo.name : videoId), '#0a0');
          
          if (window.flutter_inappwebview) {
            window.flutter_inappwebview.callHandler('youtubeAudio', 'play', videoId);
          }
          
          setTimeout(function() { window._sfBridge.intercepting = false; }, 3000);
        }
        
        // Check if response is from the audio search API
        function checkAudioSearchResponse(url, responseText) {
          if (!url.includes('search/audio/')) return false;
          
          try {
            var data = JSON.parse(responseText);
            console.log('[SF-Bridge] Audio search API response:', url);
            
            // Extract track info from URL: /search/audio/{trackId}/{artist}/{trackName}
            var urlParts = url.split('/');
            var trackInfo = {
              id: urlParts[urlParts.length - 3],
              artist: decodeURIComponent(decodeURIComponent(urlParts[urlParts.length - 2] || '')),
              name: decodeURIComponent(decodeURIComponent(urlParts[urlParts.length - 1] || ''))
            };
            console.log('[SF-Bridge] Track info:', trackInfo.artist, '-', trackInfo.name);
            
            // Get the first YouTube video ID from results
            if (data && data.results && Array.isArray(data.results) && data.results.length > 0) {
              var firstResult = data.results[0];
              if (firstResult && firstResult.id) {
                var videoId = firstResult.id;
                console.log('[SF-Bridge] Found YouTube ID: ' + videoId + ' (title: ' + firstResult.title + ')');
                playYouTubeNatively(videoId, trackInfo);
                return true;
              }
            }
          } catch(e) {
            console.log('[SF-Bridge] Error parsing response:', e);
          }
          return false;
        }
        
        // ========== INTERCEPT XHR FOR AUDIO SEARCH API ==========
        var origXHROpen = XMLHttpRequest.prototype.open;
        var origXHRSend = XMLHttpRequest.prototype.send;
        
        XMLHttpRequest.prototype.open = function(method, url) {
          this._sfUrl = url;
          this._sfMethod = method;
          return origXHROpen.apply(this, arguments);
        };
        
        XMLHttpRequest.prototype.send = function(body) {
          var xhr = this;
          
          xhr.addEventListener('load', function() {
            var url = xhr._sfUrl || '';
            if (url.includes('search/audio/')) {
              console.log('[SF-Bridge] XHR: ' + url.substring(0, 80));
              checkAudioSearchResponse(url, xhr.responseText);
            }
          });
          
          return origXHRSend.apply(this, arguments);
        };
        
        // ========== INTERCEPT FETCH FOR AUDIO SEARCH API ==========
        var origFetch = window.fetch;
        window.fetch = function(input, init) {
          var url = typeof input === 'string' ? input : (input && input.url ? input.url : '');
          
          return origFetch.apply(this, arguments).then(function(response) {
            if (url.includes('search/audio/')) {
              var cloned = response.clone();
              cloned.text().then(function(text) {
                console.log('[SF-Bridge] Fetch: ' + url.substring(0, 80));
                checkAudioSearchResponse(url, text);
              }).catch(function(e) {});
            }
            return response;
          });
        };
        
        // ========== ALSO MONITOR YOUTUBE IFRAME ==========
        var observer = new MutationObserver(function(mutations) {
          mutations.forEach(function(m) {
            m.addedNodes.forEach(function(node) {
              if (node.tagName === 'IFRAME') {
                var src = node.src || '';
                if (src.includes('youtube') || src.includes('youtube-nocookie')) {
                  var match = src.match(/embed\\/([a-zA-Z0-9_-]{11})/);
                  if (match) {
                    console.log('[SF-Bridge] YouTube iframe detected: ' + match[1]);
                    playYouTubeNatively(match[1], window._sfBridge.currentTrackInfo);
                  }
                }
              }
            });
          });
        });
        observer.observe(document.documentElement, { childList: true, subtree: true });
        
        showNotification('🎧 Bridge v13 ready!', '#0a0');
        console.log('[SF-Bridge] Audio Bridge v13 initialized - intercepting /search/audio/ API');
      })();
    ''');
  }

  Widget _buildErrorView() {
    return Container(
      color: AppTheme.white,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 80,
              color: AppTheme.red,
            ),
            const SizedBox(height: 16),
            const Text(
              AppStrings.errorLoading,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _hasError = false;
                  _isLoading = true;
                });
                _webViewController?.reload();
              },
              icon: const Icon(Icons.refresh),
              label: const Text(AppStrings.tryAgain),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: AppTheme.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
