import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../config/app_config.dart';

/// AdMob Service
/// 
/// Handles Google AdMob interstitial ads integration.
class AdMobService {
  static InterstitialAd? _interstitialAd;
  static bool _isAdLoaded = false;

  /// Initialize AdMob SDK
  static Future<void> initialize() async {
    if (!AppConfig.admobEnabled) return;
    
    await MobileAds.instance.initialize();
    await _loadInterstitialAd();
  }

  /// Load an interstitial ad
  static Future<void> _loadInterstitialAd() async {
    await InterstitialAd.load(
      adUnitId: AppConfig.admobInterstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          _interstitialAd = ad;
          _isAdLoaded = true;
          
          _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (InterstitialAd ad) {
              ad.dispose();
              _isAdLoaded = false;
              _loadInterstitialAd(); // Load the next ad
            },
            onAdFailedToShowFullScreenContent: (InterstitialAd ad, AdError error) {
              ad.dispose();
              _isAdLoaded = false;
              _loadInterstitialAd();
            },
          );
        },
        onAdFailedToLoad: (LoadAdError error) {
          _isAdLoaded = false;
          // Retry loading after a delay
          Future.delayed(const Duration(seconds: 30), () {
            _loadInterstitialAd();
          });
        },
      ),
    );
  }

  /// Show interstitial ad if loaded
  static void showInterstitialAd() {
    if (!AppConfig.admobEnabled) return;
    
    if (_isAdLoaded && _interstitialAd != null) {
      _interstitialAd!.show();
    }
  }

  /// Dispose of resources
  static void dispose() {
    _interstitialAd?.dispose();
  }
}
