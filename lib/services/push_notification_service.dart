import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../config/app_config.dart';

/// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('Handling background message: ${message.messageId}');
}

/// Push Notification Service
/// 
/// Handles Firebase Cloud Messaging for push notifications.
class PushNotificationService {
  static FirebaseMessaging? _messaging;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// Initialize push notification service
  static Future<void> initialize() async {
    if (!AppConfig.pushNotificationsEnabled) return;

    try {
      // Initialize Firebase
      await Firebase.initializeApp();
      _messaging = FirebaseMessaging.instance;

      // Set background message handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Request permission for iOS
      await _requestPermission();

      // Initialize local notifications
      await _initializeLocalNotifications();

      // Configure message handlers
      _configureMessageHandlers();

      // Get FCM token
      await _getToken();
    } catch (e) {
      print('Error initializing push notifications: $e');
    }
  }

  /// Request notification permission
  static Future<void> _requestPermission() async {
    if (_messaging == null) return;
    
    final NotificationSettings settings = await _messaging!.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('User granted notification permission');
    } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
      print('User granted provisional notification permission');
    } else {
      print('User declined or has not accepted notification permission');
    }
  }

  /// Initialize local notifications plugin
  static Future<void> _initializeLocalNotifications() async {
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings =
        InitializationSettings(
      iOS: initializationSettingsIOS,
    );

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
  }

  /// Configure FCM message handlers
  static void _configureMessageHandlers() {
    if (_messaging == null) return;
    
    // Foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Message opened app
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    // Check for initial message (app opened from notification)
    _checkInitialMessage();
  }

  /// Handle foreground messages
  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    
    if (notification != null) {
      await _showLocalNotification(
        title: notification.title ?? AppConfig.appName,
        body: notification.body ?? '',
        payload: message.data.toString(),
      );
    }
  }

  /// Handle when user taps on notification
  static void _handleMessageOpenedApp(RemoteMessage message) {
    print('Message opened app: ${message.messageId}');
    // Navigate to specific screen based on message data
  }

  /// Check if app was opened from a notification
  static Future<void> _checkInitialMessage() async {
    if (_messaging == null) return;
    
    final RemoteMessage? initialMessage =
        await _messaging!.getInitialMessage();

    if (initialMessage != null) {
      _handleMessageOpenedApp(initialMessage);
    }
  }

  /// Show local notification
  static Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const DarwinNotificationDetails iosNotificationDetails =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      iOS: iosNotificationDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  /// Handle notification tap
  static void _onNotificationTapped(NotificationResponse response) {
    print('Notification tapped: ${response.payload}');
    // Navigate to specific screen based on payload
  }

  /// Get FCM token
  static Future<String?> _getToken() async {
    if (_messaging == null) return null;
    
    try {
      final String? token = await _messaging!.getToken();
      print('FCM Token: $token');
      
      // Listen for token refresh
      _messaging!.onTokenRefresh.listen((String token) {
        print('FCM Token refreshed: $token');
        // Send new token to your server
      });
      
      return token;
    } catch (e) {
      print('Error getting FCM token: $e');
      return null;
    }
  }

  /// Subscribe to topic
  static Future<void> subscribeToTopic(String topic) async {
    if (_messaging == null) return;
    await _messaging!.subscribeToTopic(topic);
  }

  /// Unsubscribe from topic
  static Future<void> unsubscribeFromTopic(String topic) async {
    if (_messaging == null) return;
    await _messaging!.unsubscribeFromTopic(topic);
  }
}
