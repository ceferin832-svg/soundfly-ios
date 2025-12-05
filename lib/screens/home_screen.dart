import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../config/app_config.dart';
import '../config/app_strings.dart';
import '../config/app_theme.dart';
import '../services/admob_service.dart';
import '../services/audio_background_service.dart';
import 'no_internet_screen.dart';

/// Home Screen with WebView
/// 
/// Displays the Soundfly web application in a WebView.
/// Handles connectivity, back navigation, AdMob integration,
/// and background audio playback.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late WebViewController _webViewController;
  bool _isLoading = true;
  bool _hasError = false;
  bool _isConnected = true;
  int _pageLoadCount = 0;
  DateTime? _lastBackPress;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeWebView();
    _initializeConnectivity();
    _enableWakelock();
  }
  
  /// Enable wakelock to prevent screen from sleeping during music playback
  void _enableWakelock() {
    WakelockPlus.enable();
  }
  
  /// Handle app lifecycle changes for background audio
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.paused:
        // App went to background - keep audio session active
        debugPrint('App paused - keeping audio session active for background playback');
        AudioBackgroundService.activate();
        break;
      case AppLifecycleState.resumed:
        // App came back to foreground
        debugPrint('App resumed');
        AudioBackgroundService.activate();
        break;
      case AppLifecycleState.inactive:
        // App is inactive (transitioning)
        break;
      case AppLifecycleState.detached:
        // App is being terminated
        break;
      case AppLifecycleState.hidden:
        // App is hidden
        break;
    }
  }

  void _initializeWebView() {
    // iOS specific configuration for audio and media playback
    late final PlatformWebViewControllerCreationParams params;
    if (Platform.isIOS) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{}, // No user action required for any media
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    _webViewController = WebViewController.fromPlatformCreationParams(params);
    
    // Enable media playback in WebView
    if (_webViewController.platform is WebKitWebViewController) {
      final webKitController = _webViewController.platform as WebKitWebViewController;
      webKitController.setAllowsBackForwardNavigationGestures(true);
    }
    
    _webViewController
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppTheme.white)
      ..setUserAgent(
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
              _hasError = false;
            });
            // Activate audio session when page starts loading
            AudioBackgroundService.activate();
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
            _pageLoadCount++;
            _showInterstitialAd();
            
            // Inject JavaScript to improve scrolling and audio
            _injectJavaScript();
          },
          onWebResourceError: (WebResourceError error) {
            // Only show error for main frame errors
            if (error.isForMainFrame ?? true) {
              setState(() {
                _hasError = true;
                _isLoading = false;
              });
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            // Handle external links
            if (_isExternalUrl(request.url)) {
              if (AppConfig.openExternalLinksInBrowser) {
                _openExternalUrl(request.url);
                return NavigationDecision.prevent;
              }
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(AppConfig.websiteUrl));
  }

  /// Inject JavaScript to improve iOS WebView behavior and enable audio
  void _injectJavaScript() {
    _webViewController.runJavaScript('''
      // Enable smooth scrolling
      document.body.style.webkitOverflowScrolling = 'touch';
      document.body.style.overflowY = 'scroll';
      
      // Fix viewport for proper scaling
      var viewport = document.querySelector('meta[name="viewport"]');
      if (viewport) {
        viewport.setAttribute('content', 'width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes');
      }
      
      // Force audio/video elements to allow inline playback
      document.querySelectorAll('audio, video').forEach(function(el) {
        el.setAttribute('playsinline', '');
        el.setAttribute('webkit-playsinline', '');
        el.removeAttribute('autoplay');
      });
      
      // Override Audio constructor to ensure playsinline
      (function() {
        var OriginalAudio = window.Audio;
        window.Audio = function(src) {
          var audio = new OriginalAudio(src);
          audio.setAttribute('playsinline', '');
          audio.setAttribute('webkit-playsinline', '');
          return audio;
        };
        window.Audio.prototype = OriginalAudio.prototype;
      })();
      
      // Monitor for dynamically added audio elements
      var observer = new MutationObserver(function(mutations) {
        mutations.forEach(function(mutation) {
          mutation.addedNodes.forEach(function(node) {
            if (node.tagName === 'AUDIO' || node.tagName === 'VIDEO') {
              node.setAttribute('playsinline', '');
              node.setAttribute('webkit-playsinline', '');
            }
            if (node.querySelectorAll) {
              node.querySelectorAll('audio, video').forEach(function(el) {
                el.setAttribute('playsinline', '');
                el.setAttribute('webkit-playsinline', '');
              });
            }
          });
        });
      });
      observer.observe(document.body, { childList: true, subtree: true });
      
      console.log('iOS audio enhancements injected');
    ''');
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
          _webViewController.reload();
        } else {
          _showSnackBar(AppStrings.internetLost, Colors.red);
        }
      }
    });
    
    // Check initial connectivity
    _checkConnectivity();
  }

  Future<void> _checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    setState(() {
      _isConnected = result != ConnectivityResult.none;
    });
  }

  bool _isExternalUrl(String url) {
    final baseUrl = Uri.parse(AppConfig.websiteUrl);
    final requestUrl = Uri.parse(url);
    
    // Check if it's an external URL
    return requestUrl.host != baseUrl.host &&
        !url.startsWith('javascript:') &&
        !url.startsWith('about:');
  }

  Future<void> _openExternalUrl(String url) async {
    // Use url_launcher to open external URLs
    // For now, we'll just prevent navigation
  }

  void _showInterstitialAd() {
    if (AppConfig.admobEnabled &&
        _pageLoadCount > 0 &&
        _pageLoadCount % AppConfig.interstitialInterval == 0) {
      AdMobService.showInterstitialAd();
    }
  }

  void _showSnackBar(String message, Color backgroundColor) {
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
    // Check if WebView can go back
    if (await _webViewController.canGoBack()) {
      _webViewController.goBack();
      return false;
    }
    
    // Double tap to exit
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
    // Show no internet screen if not connected
    if (!_isConnected) {
      return NoInternetScreen(
        onRetry: () async {
          await _checkConnectivity();
          if (_isConnected) {
            _webViewController.reload();
          }
        },
      );
    }

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
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
              // WebView - Direct without RefreshIndicator for better scroll
              WebViewWidget(controller: _webViewController),
              
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
            ],
          ),
        ),
      ),
    );
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
                _webViewController.reload();
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
