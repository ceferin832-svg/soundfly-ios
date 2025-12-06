import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../config/app_config.dart';
import '../config/app_strings.dart';
import '../config/app_theme.dart';
import '../services/admob_service.dart';
import '../services/audio_background_service.dart';
import '../services/native_audio_player.dart';
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
    AudioBackgroundService.initialize();
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
        // App went to background - try to keep audio playing
        debugPrint('App paused - keeping audio session active for background playback');
        AudioBackgroundService.activate();
        // Inject JavaScript to try to keep audio alive
        _keepAudioAlive();
        break;
      case AppLifecycleState.resumed:
        debugPrint('App resumed');
        AudioBackgroundService.activate();
        break;
      case AppLifecycleState.inactive:
        // App is transitioning - activate audio session
        AudioBackgroundService.activate();
        break;
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
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    WakelockPlus.disable();
    super.dispose();
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
                      
                      debugPrint('Native Audio Command: $command, URL: $url');
                      
                      switch (command) {
                        case 'play':
                          if (url.isNotEmpty) {
                            NativeAudioPlayer.play(url);
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
                  
                  // Add handler for background audio state
                  controller.addJavaScriptHandler(
                    handlerName: 'backgroundAudio',
                    callback: (args) {
                      if (args.isEmpty) return;
                      final command = args[0] as String;
                      
                      debugPrint('Background Audio Command: $command');
                      
                      if (command == 'start') {
                        // Activate audio session to allow background playback
                        AudioBackgroundService.activate();
                        // Play silent audio to keep audio session alive
                        NativeAudioPlayer.playSilent();
                      } else if (command == 'stop') {
                        NativeAudioPlayer.stopSilent();
                      }
                    },
                  );
                },
                onLoadStart: (controller, url) {
                  setState(() {
                    _isLoading = true;
                    _hasError = false;
                  });
                  AudioBackgroundService.activate();
                },
                onLoadStop: (controller, url) async {
                  setState(() {
                    _isLoading = false;
                  });
                  _pageLoadCount++;
                  _showInterstitialAd();
                  
                  // Inject JavaScript for iOS audio support
                  await _injectAudioFixes(controller);
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
              
              // DEBUG: Native audio status indicator and test button
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
                    // Test play button
                    FloatingActionButton.small(
                      heroTag: 'testAudio',
                      backgroundColor: Colors.purple,
                      onPressed: _testNativeAudio,
                      child: const Icon(Icons.music_note, color: Colors.white),
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
  
  /// Test native audio player with a sample MP3
  Future<void> _testNativeAudio() async {
    // Using a public domain audio file for testing
    const testUrl = 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3';
    
    if (NativeAudioPlayer.isPlaying) {
      await NativeAudioPlayer.pause();
      _showSnackBar('Native audio paused', Colors.orange);
    } else {
      await NativeAudioPlayer.play(testUrl);
      _showSnackBar('Playing test audio - minimize app to test background!', Colors.green);
    }
    setState(() {}); // Refresh UI
  }
  
  /// Play YouTube audio using extraction service
  String? _currentYouTubeVideoId;
  
  Future<void> _playYouTubeAudio(String videoId) async {
    if (videoId.isEmpty) return;
    
    // Don't re-extract if same video
    if (videoId == _currentYouTubeVideoId && NativeAudioPlayer.isPlaying) {
      debugPrint('Already playing this video: $videoId');
      return;
    }
    
    _currentYouTubeVideoId = videoId;
    debugPrint('Extracting audio for YouTube video: $videoId');
    
    try {
      // Use Piped API (privacy-friendly YouTube frontend) to get audio stream
      // This is a public API that extracts YouTube audio URLs
      final pipedInstances = [
        'pipedapi.kavin.rocks',
        'pipedapi.adminforge.de', 
        'api.piped.yt',
      ];
      
      String? audioUrl;
      
      for (final instance in pipedInstances) {
        try {
          final uri = Uri.parse('https://$instance/streams/$videoId');
          debugPrint('Trying Piped instance: $instance');
          
          final response = await HttpClient().getUrl(uri).then((req) => req.close());
          
          if (response.statusCode == 200) {
            final body = await response.transform(const Utf8Decoder()).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            
            // Get audio streams
            final audioStreams = json['audioStreams'] as List?;
            if (audioStreams != null && audioStreams.isNotEmpty) {
              // Find best quality audio stream (prefer m4a/mp4 for iOS compatibility)
              for (final stream in audioStreams) {
                final mimeType = stream['mimeType'] as String? ?? '';
                final url = stream['url'] as String?;
                
                if (url != null && (mimeType.contains('mp4') || mimeType.contains('m4a'))) {
                  audioUrl = url;
                  debugPrint('Found audio stream: $mimeType');
                  break;
                }
              }
              
              // If no m4a, use first audio stream
              if (audioUrl == null && audioStreams.isNotEmpty) {
                audioUrl = audioStreams.first['url'] as String?;
              }
            }
            
            if (audioUrl != null) {
              debugPrint('Got audio URL from $instance');
              break;
            }
          }
        } catch (e) {
          debugPrint('Piped instance $instance failed: $e');
        }
      }
      
      if (audioUrl != null) {
        // Play the extracted audio
        await NativeAudioPlayer.play(audioUrl);
        _showSnackBar('🎵 Playing in background mode', Colors.green);
        setState(() {});
      } else {
        debugPrint('Could not extract audio URL for video: $videoId');
        _showSnackBar('Could not extract audio', Colors.red);
      }
    } catch (e) {
      debugPrint('Error extracting YouTube audio: $e');
      _showSnackBar('Audio extraction failed', Colors.red);
    }
  }

  Future<void> _injectAudioFixes(InAppWebViewController controller) async {
    await controller.evaluateJavascript(source: '''
      (function() {
        console.log('=== Soundfly Audio Bridge v9 - YouTube Audio Extraction ===');
        
        window._sfBridge = {
          active: false,
          currentVideoId: null,
          lastVideoId: null
        };
        
        // Show notification
        function showNotification(msg, isSuccess) {
          console.log('[SF-Native] ' + msg);
          var toast = document.createElement('div');
          toast.style.cssText = 'position:fixed;top:60px;left:50%;transform:translateX(-50%);background:' + (isSuccess ? '#0a0' : '#f80') + ';color:#fff;padding:10px 20px;border-radius:20px;z-index:99999;font-size:12px;max-width:90%;text-align:center;box-shadow:0 2px 10px rgba(0,0,0,0.5);font-weight:bold;';
          toast.textContent = msg;
          document.body.appendChild(toast);
          setTimeout(function() { toast.remove(); }, 4000);
        }
        
        // Send YouTube video ID to Flutter for native playback
        function sendYouTubeToFlutter(videoId, action) {
          if (!videoId) return;
          console.log('[SF-Native] Sending YouTube: ' + action + ' -> ' + videoId);
          
          if (window.flutter_inappwebview) {
            window.flutter_inappwebview.callHandler('youtubeAudio', action, videoId);
          }
        }
        
        // Extract video ID from various YouTube URL formats
        function extractVideoId(url) {
          if (!url) return null;
          
          // youtube.com/watch?v=VIDEO_ID
          var match = url.match(/[?&]v=([^&]+)/);
          if (match) return match[1];
          
          // youtu.be/VIDEO_ID
          match = url.match(/youtu\\.be\\/([^?&]+)/);
          if (match) return match[1];
          
          // youtube.com/embed/VIDEO_ID
          match = url.match(/\\/embed\\/([^?&]+)/);
          if (match) return match[1];
          
          // Just the ID (11 chars)
          if (/^[a-zA-Z0-9_-]{11}\$/.test(url)) return url;
          
          return null;
        }
        
        // ========== INTERCEPT XHR TO CATCH YOUTUBE SEARCH RESULTS ==========
        var origXHROpen = XMLHttpRequest.prototype.open;
        var origXHRSend = XMLHttpRequest.prototype.send;
        
        XMLHttpRequest.prototype.open = function(method, url) {
          this._sfUrl = url;
          return origXHROpen.apply(this, arguments);
        };
        
        XMLHttpRequest.prototype.send = function(body) {
          var xhr = this;
          var url = this._sfUrl || '';
          
          // Intercept search/audio API responses to get YouTube video IDs
          if (url.includes('/search/audio') || url.includes('api/v1/search')) {
            xhr.addEventListener('load', function() {
              try {
                var response = JSON.parse(xhr.responseText);
                if (response.results && response.results.length > 0) {
                  var videoId = response.results[0].id;
                  console.log('[SF-Native] YouTube video ID from API: ' + videoId);
                  showNotification('🎬 YouTube ID: ' + videoId, true);
                  
                  window._sfBridge.currentVideoId = videoId;
                  
                  // Send to Flutter to prepare native playback
                  sendYouTubeToFlutter(videoId, 'prepare');
                }
              } catch(e) {
                console.log('[SF-Native] XHR parse error: ' + e);
              }
            });
          }
          
          return origXHRSend.apply(this, arguments);
        };
        
        // ========== INTERCEPT YOUTUBE IFRAME ==========
        var origCreateElement = document.createElement.bind(document);
        document.createElement = function(tag) {
          var el = origCreateElement(tag);
          
          if (tag.toLowerCase() === 'iframe') {
            // Watch for src changes on iframes
            var origSetAttr = el.setAttribute.bind(el);
            el.setAttribute = function(name, value) {
              if (name === 'src' && value && value.includes('youtube')) {
                var videoId = extractVideoId(value);
                if (videoId) {
                  console.log('[SF-Native] YouTube iframe src: ' + videoId);
                  window._sfBridge.currentVideoId = videoId;
                }
              }
              return origSetAttr(name, value);
            };
            
            // Also watch the src property
            var srcDescriptor = Object.getOwnPropertyDescriptor(HTMLIFrameElement.prototype, 'src');
            if (srcDescriptor) {
              Object.defineProperty(el, 'src', {
                set: function(value) {
                  if (value && value.includes('youtube')) {
                    var videoId = extractVideoId(value);
                    if (videoId) {
                      console.log('[SF-Native] YouTube iframe src property: ' + videoId);
                      window._sfBridge.currentVideoId = videoId;
                    }
                  }
                  srcDescriptor.set.call(this, value);
                },
                get: function() {
                  return srcDescriptor.get.call(this);
                }
              });
            }
          }
          return el;
        };
        
        // ========== DETECT PLAYBACK STATE VIA POSTMESSAGE ==========
        window.addEventListener('message', function(event) {
          try {
            var data = typeof event.data === 'string' ? JSON.parse(event.data) : event.data;
            
            // YouTube iframe API messages
            if (data && data.event === 'onStateChange') {
              var state = data.info;
              console.log('[SF-Native] YouTube state: ' + state);
              
              // States: -1=unstarted, 0=ended, 1=playing, 2=paused, 3=buffering, 5=cued
              if (state === 1 && window._sfBridge.currentVideoId) {
                // YouTube started playing - tell Flutter to take over
                if (window._sfBridge.currentVideoId !== window._sfBridge.lastVideoId) {
                  window._sfBridge.lastVideoId = window._sfBridge.currentVideoId;
                  showNotification('▶️ Starting native player...', true);
                  sendYouTubeToFlutter(window._sfBridge.currentVideoId, 'play');
                }
              } else if (state === 2) {
                sendYouTubeToFlutter(window._sfBridge.currentVideoId, 'pause');
              } else if (state === 0) {
                sendYouTubeToFlutter(window._sfBridge.currentVideoId, 'ended');
              }
            }
            
            // Also check for infoDelivery with video data
            if (data && data.event === 'infoDelivery' && data.info) {
              if (data.info.videoData && data.info.videoData.video_id) {
                var videoId = data.info.videoData.video_id;
                if (videoId !== window._sfBridge.currentVideoId) {
                  console.log('[SF-Native] Video ID from infoDelivery: ' + videoId);
                  window._sfBridge.currentVideoId = videoId;
                }
              }
            }
          } catch(e) {}
        });
        
        // ========== VISIBILITY CHANGE - TRIGGER NATIVE PLAYBACK ==========
        document.addEventListener('visibilitychange', function() {
          console.log('[SF-Native] Visibility: ' + document.visibilityState);
          
          if (document.visibilityState === 'hidden') {
            // App going to background - native player should take over
            if (window._sfBridge.currentVideoId) {
              showNotification('⏳ Switching to native player...', true);
              sendYouTubeToFlutter(window._sfBridge.currentVideoId, 'background');
            }
          } else if (document.visibilityState === 'visible') {
            // App back in foreground
            sendYouTubeToFlutter(window._sfBridge.currentVideoId || '', 'foreground');
          }
        });
        
        showNotification('Bridge v9 ready!', true);
        console.log('[SF-Native] Audio Bridge v9 initialized');
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
