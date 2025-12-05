import 'dart:async';
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

  Future<void> _injectAudioFixes(InAppWebViewController controller) async {
    await controller.evaluateJavascript(source: '''
      (function() {
        console.log('=== Soundfly Audio Bridge v5 - YouTube + HTML Audio ===');
        
        // State tracking
        window._sfBridge = {
          active: false,
          currentSrc: null,
          audioElement: null,
          baseUrl: window.location.origin,
          youtubeReady: false,
          lastDetectedUrl: null
        };
        
        // Show visual notification (for debugging)
        function showNotification(msg) {
          console.log('[SF-Native] ' + msg);
          // Create a visual toast
          var toast = document.createElement('div');
          toast.style.cssText = 'position:fixed;top:60px;left:50%;transform:translateX(-50%);background:#333;color:#0f0;padding:8px 16px;border-radius:20px;z-index:99999;font-size:12px;';
          toast.textContent = msg;
          document.body.appendChild(toast);
          setTimeout(function() { toast.remove(); }, 3000);
        }
        
        // Send message to Flutter native player
        function sendToFlutter(action, url) {
          var fullUrl = url;
          
          // Convert relative URLs to absolute
          if (url && !url.startsWith('http') && !url.startsWith('blob:') && !url.startsWith('data:')) {
            fullUrl = window._sfBridge.baseUrl + '/' + url.replace(/^\\//, '');
          }
          
          console.log('[SF-Native] ' + action + ': ' + fullUrl);
          showNotification(action + ': ' + (fullUrl ? fullUrl.substring(0, 50) + '...' : 'none'));
          
          if (window.flutter_inappwebview) {
            window.flutter_inappwebview.callHandler('nativeAudio', action, fullUrl || '');
          }
        }
        
        // Check if this is a real audio URL
        function isValidAudioUrl(url) {
          if (!url || url.length < 5) return false;
          if (url.startsWith('blob:') || url.startsWith('data:')) return false;
          
          return url.includes('.mp3') || 
                 url.includes('.m4a') || 
                 url.includes('.wav') ||
                 url.includes('.ogg') ||
                 url.includes('.flac') ||
                 url.includes('.aac') ||
                 url.includes('storage/') ||
                 url.includes('track_media') ||
                 url.includes('/stream') ||
                 url.includes('/audio');
        }
        
        // ========== HTML AUDIO INTERCEPTION ==========
        function interceptAudio(audio) {
          if (audio._sfIntercepted) return;
          audio._sfIntercepted = true;
          
          showNotification('Found audio element!');
          
          var origPlay = audio.play.bind(audio);
          var origPause = audio.pause.bind(audio);
          
          function getCurrentSrc() {
            return audio.src || audio.currentSrc || audio.getAttribute('src') || '';
          }
          
          audio.play = function() {
            var src = getCurrentSrc();
            showNotification('audio.play(): ' + src.substring(0, 40));
            
            if (isValidAudioUrl(src) && src !== window._sfBridge.currentSrc) {
              window._sfBridge.active = true;
              window._sfBridge.currentSrc = src;
              window._sfBridge.audioElement = this;
              this.muted = true;
              this.volume = 0;
              sendToFlutter('play', src);
            }
            
            return origPlay().catch(function(e) { return Promise.resolve(); });
          };
          
          audio.pause = function() {
            if (window._sfBridge.active) {
              sendToFlutter('pause', '');
            }
            return origPause();
          };
          
          audio.addEventListener('ended', function() {
            if (window._sfBridge.active) {
              sendToFlutter('ended', '');
              window._sfBridge.active = false;
            }
          });
        }
        
        // Hook existing audio elements
        document.querySelectorAll('audio').forEach(interceptAudio);
        
        // Watch for new audio elements
        var observer = new MutationObserver(function(mutations) {
          mutations.forEach(function(mutation) {
            mutation.addedNodes.forEach(function(node) {
              if (node.nodeType === 1) {
                if (node.tagName === 'AUDIO') interceptAudio(node);
                if (node.tagName === 'IFRAME' && node.src && node.src.includes('youtube')) {
                  showNotification('YouTube iframe detected!');
                }
                if (node.querySelectorAll) {
                  node.querySelectorAll('audio').forEach(interceptAudio);
                }
              }
            });
          });
        });
        
        observer.observe(document.documentElement, { childList: true, subtree: true });
        
        // Override Audio constructor
        var OrigAudio = window.Audio;
        window.Audio = function(src) {
          showNotification('new Audio(): ' + (src || 'no src'));
          var audio = new OrigAudio(src);
          interceptAudio(audio);
          return audio;
        };
        window.Audio.prototype = OrigAudio.prototype;
        
        // ========== YOUTUBE INTERCEPTION ==========
        // BeMusic uses YouTube iframe API - intercept postMessage
        var origPostMessage = window.postMessage.bind(window);
        window.postMessage = function(msg, origin) {
          try {
            if (typeof msg === 'string' && msg.includes('command')) {
              var data = JSON.parse(msg);
              if (data.event === 'command') {
                showNotification('YT cmd: ' + data.func);
                
                // Detect play/pause commands to YouTube
                if (data.func === 'playVideo' || data.func === 'cueVideoById') {
                  showNotification('YouTube PLAY detected!');
                  // YouTube is being used - notify user
                  window._sfBridge.youtubeReady = true;
                }
                if (data.func === 'pauseVideo') {
                  showNotification('YouTube PAUSE detected');
                }
              }
            }
          } catch(e) {}
          return origPostMessage(msg, origin);
        };
        
        // Listen for YouTube state changes via message events
        window.addEventListener('message', function(event) {
          try {
            var data = typeof event.data === 'string' ? JSON.parse(event.data) : event.data;
            if (data && data.event === 'onStateChange') {
              showNotification('YT State: ' + data.info);
              // YouTube states: -1 unstarted, 0 ended, 1 playing, 2 paused, 3 buffering, 5 cued
              if (data.info === 1) {
                showNotification('YouTube PLAYING!');
              }
            }
            if (data && data.event === 'initialDelivery') {
              showNotification('YT Ready: ' + JSON.stringify(data).substring(0, 60));
            }
          } catch(e) {}
        });
        
        // ========== FETCH/XHR INTERCEPTION FOR AUDIO URLS ==========
        var origFetch = window.fetch;
        window.fetch = function(url, options) {
          if (url && typeof url === 'string') {
            if (isValidAudioUrl(url)) {
              showNotification('Fetch audio: ' + url.substring(0, 50));
              window._sfBridge.lastDetectedUrl = url;
            }
          }
          return origFetch.apply(this, arguments);
        };
        
        var origXHROpen = XMLHttpRequest.prototype.open;
        XMLHttpRequest.prototype.open = function(method, url) {
          if (url && isValidAudioUrl(url)) {
            showNotification('XHR audio: ' + url.substring(0, 50));
            window._sfBridge.lastDetectedUrl = url;
          }
          return origXHROpen.apply(this, arguments);
        };
        
        showNotification('Bridge v5 loaded!');
        console.log('[SF-Native] Audio Bridge v5 initialized');
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
