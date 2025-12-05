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
import 'no_internet_screen.dart';

/// Home Screen with InAppWebView
/// 
/// Displays the Soundfly web application in a WebView with full
/// audio/video support for iOS.
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
    
    // iOS specific settings
    allowsBackForwardNavigationGestures: true,
    allowsLinkPreview: false,
    isFraudulentWebsiteWarningEnabled: false,
    
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
  }
  
  void _enableWakelock() {
    WakelockPlus.enable();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.paused:
        // App went to background - keep audio playing
        debugPrint('App paused - keeping audio session active for background playback');
        AudioBackgroundService.activate();
        // DO NOT pause the WebView - let audio continue
        break;
      case AppLifecycleState.resumed:
        debugPrint('App resumed');
        AudioBackgroundService.activate();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
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
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _injectAudioFixes(InAppWebViewController controller) async {
    await controller.evaluateJavascript(source: '''
      (function() {
        // Unlock AudioContext on iOS
        var AudioContext = window.AudioContext || window.webkitAudioContext;
        if (AudioContext) {
          var ctx = new AudioContext();
          if (ctx.state === 'suspended') {
            ctx.resume();
          }
        }
        
        // Ensure all audio/video elements have correct attributes
        document.querySelectorAll('audio, video').forEach(function(el) {
          el.setAttribute('playsinline', '');
          el.setAttribute('webkit-playsinline', '');
        });
        
        // Monitor for new audio elements
        var observer = new MutationObserver(function(mutations) {
          mutations.forEach(function(mutation) {
            mutation.addedNodes.forEach(function(node) {
              if (node.nodeType === 1) {
                if (node.tagName === 'AUDIO' || node.tagName === 'VIDEO') {
                  node.setAttribute('playsinline', '');
                  node.setAttribute('webkit-playsinline', '');
                }
                var elements = node.querySelectorAll ? node.querySelectorAll('audio, video') : [];
                elements.forEach(function(el) {
                  el.setAttribute('playsinline', '');
                  el.setAttribute('webkit-playsinline', '');
                });
              }
            });
          });
        });
        observer.observe(document.body, { childList: true, subtree: true });
        
        console.log('iOS audio fixes injected');
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
