import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'config/app_config.dart';
import 'config/app_theme.dart';
import 'screens/splash_screen.dart';
import 'services/admob_service.dart';
import 'services/push_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  
  // Set fullscreen mode if enabled
  if (AppConfig.fullscreenEnabled) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }
  
  // Initialize AdMob if enabled
  if (AppConfig.admobEnabled) {
    await AdMobService.initialize();
  }
  
  // Initialize push notifications if enabled
  if (AppConfig.pushNotificationsEnabled) {
    await PushNotificationService.initialize();
  }
  
  runApp(const SoundflyApp());
}

class SoundflyApp extends StatelessWidget {
  const SoundflyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const SplashScreen(),
    );
  }
}
