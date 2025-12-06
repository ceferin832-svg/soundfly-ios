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

  Future<void> _injectAudioFixes(InAppWebViewController controller) async {
    // Enable media playback in background for WebView
    await controller.evaluateJavascript(source: '''
      (function() {
        console.log('=== Soundfly Audio Bridge v8 - Background WebView Audio ===');
        
        // Keep audio session alive
        window._sfBridge = {
          active: false,
          silentAudio: null,
          keepAliveInterval: null
        };
        
        // Show notification
        function showNotification(msg, isSuccess) {
          console.log('[SF-Native] ' + msg);
          var toast = document.createElement('div');
          toast.style.cssText = 'position:fixed;top:60px;left:50%;transform:translateX(-50%);background:' + (isSuccess ? '#0a0' : '#333') + ';color:#fff;padding:8px 16px;border-radius:20px;z-index:99999;font-size:11px;max-width:90%;text-align:center;box-shadow:0 2px 10px rgba(0,0,0,0.3);';
          toast.textContent = msg;
          document.body.appendChild(toast);
          setTimeout(function() { toast.remove(); }, 3000);
        }
        
        // Create a silent audio context to keep iOS audio session active
        function createSilentAudioKeepAlive() {
          try {
            var AudioContext = window.AudioContext || window.webkitAudioContext;
            if (!AudioContext) return;
            
            var ctx = new AudioContext();
            
            // Create silent oscillator
            var oscillator = ctx.createOscillator();
            var gainNode = ctx.createGain();
            gainNode.gain.value = 0.001; // Nearly silent
            oscillator.connect(gainNode);
            gainNode.connect(ctx.destination);
            oscillator.start();
            
            window._sfBridge.audioContext = ctx;
            console.log('[SF-Native] Silent audio context created');
          } catch(e) {
            console.log('[SF-Native] AudioContext error: ' + e);
          }
        }
        
        // Notify Flutter to start background audio session
        function notifyFlutterBackgroundAudio(isPlaying) {
          if (window.flutter_inappwebview) {
            window.flutter_inappwebview.callHandler('backgroundAudio', isPlaying ? 'start' : 'stop', '');
          }
        }
        
        // ========== YOUTUBE IFRAME DETECTION ==========
        function detectYouTubePlayback() {
          // Find YouTube iframes
          var iframes = document.querySelectorAll('iframe[src*="youtube"]');
          if (iframes.length > 0) {
            console.log('[SF-Native] YouTube iframe found: ' + iframes.length);
            return true;
          }
          return false;
        }
        
        // ========== MEDIA SESSION API ==========
        // Use Media Session API to get better background support
        if ('mediaSession' in navigator) {
          navigator.mediaSession.setActionHandler('play', function() {
            console.log('[SF-Native] Media Session: play');
            notifyFlutterBackgroundAudio(true);
          });
          navigator.mediaSession.setActionHandler('pause', function() {
            console.log('[SF-Native] Media Session: pause');
            notifyFlutterBackgroundAudio(false);
          });
        }
        
        // ========== VISIBILITY CHANGE DETECTION ==========
        document.addEventListener('visibilitychange', function() {
          console.log('[SF-Native] Visibility: ' + document.visibilityState);
          
          if (document.visibilityState === 'hidden') {
            // App going to background
            showNotification('App going to background...', false);
            notifyFlutterBackgroundAudio(true);
            
            // Try to keep audio alive
            if (window._sfBridge.audioContext) {
              window._sfBridge.audioContext.resume();
            }
          } else {
            // App coming to foreground
            showNotification('App in foreground', true);
          }
        });
        
        // ========== AUDIO ELEMENT MONITORING ==========
        function monitorAudioElements() {
          var audios = document.querySelectorAll('audio, video');
          audios.forEach(function(media) {
            if (media._sfMonitored) return;
            media._sfMonitored = true;
            
            media.addEventListener('play', function() {
              console.log('[SF-Native] Media playing: ' + (this.src || 'no src'));
              window._sfBridge.active = true;
              notifyFlutterBackgroundAudio(true);
              showNotification('🎵 Audio playing', true);
            });
            
            media.addEventListener('pause', function() {
              console.log('[SF-Native] Media paused');
            });
            
            media.addEventListener('ended', function() {
              console.log('[SF-Native] Media ended');
              window._sfBridge.active = false;
            });
          });
        }
        
        // Monitor periodically for new audio elements
        setInterval(monitorAudioElements, 1000);
        monitorAudioElements();
        
        // Watch for YouTube iframes
        var observer = new MutationObserver(function(mutations) {
          mutations.forEach(function(mutation) {
            mutation.addedNodes.forEach(function(node) {
              if (node.nodeType === 1) {
                if (node.tagName === 'IFRAME' && node.src && node.src.includes('youtube')) {
                  console.log('[SF-Native] YouTube iframe added');
                  showNotification('🎬 YouTube player loaded', false);
                  notifyFlutterBackgroundAudio(true);
                }
                if (node.tagName === 'AUDIO' || node.tagName === 'VIDEO') {
                  monitorAudioElements();
                }
              }
            });
          });
        });
        observer.observe(document.documentElement, { childList: true, subtree: true });
        
        // Initialize
        createSilentAudioKeepAlive();
        showNotification('Bridge v8 ready!', true);
        console.log('[SF-Native] Audio Bridge v8 initialized');
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
