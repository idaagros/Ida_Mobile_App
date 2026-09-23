// lib/services/push_service.dart
//
// Push notifications through Firebase Cloud Messaging (free).
//
//  - init() once at app start (main.dart). Safe if Firebase isn't set up
//    yet (no google-services.json): push is simply off and the app runs.
//  - registerDevice() after login (called from the dashboard): asks for
//    notification permission (Android 13+), gets this phone's FCM token
//    and sends it to the backend so notifications reach this device.
//  - unregisterDevice() on sign-out, so the next person to log in on this
//    phone doesn't receive the previous user's notifications.
//  - Tapping a notification (app closed, in background, or the in-app
//    banner when open) opens the matching screen via openRoute().
//
// When the app is closed or in the background, Android shows the
// notification in the tray by itself. When the app is open, it appears
// as a banner at the bottom of the screen with an "Open" button.

import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../screens/admin_review_screen.dart';
import '../screens/attendance_screen.dart';
import '../screens/electricity_screen.dart';
import '../screens/factory_screen.dart';
import '../screens/factory_tractor_diesel_screen.dart';
import '../screens/machine_maintenance_screen.dart';
import '../screens/machine_pf_screen.dart';
import '../screens/machine_reading_screen.dart';
import '../screens/maintenance_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/otp_approvals_screen.dart';
import '../screens/outward_register_review_screen.dart';
import '../screens/outward_register_screen.dart';
import '../screens/tractor_screen.dart';
import '../screens/work_allocation_screen.dart';

// Shared with MaterialApp in main.dart so notifications can navigate and
// show banners from outside any screen.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> appMessengerKey = GlobalKey<ScaffoldMessengerState>();

// Background messages: Android shows the tray notification itself; the
// handler only has to exist (and be a top-level function).
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
}

class PushService {
  static bool _ready = false;
  static bool get isReady => _ready;
  static final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  static Future<void> init() async {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
      _ready = true;
    } catch (e) {
      // No google-services.json yet, or Firebase not configured — the app
      // works normally, just without push.
      debugPrint('Push disabled: $e');
      _ready = false;
      return;
    }

    // App open → show an in-app banner.
    FirebaseMessaging.onMessage.listen((message) {
      final title = message.notification?.title ?? '';
      final body = message.notification?.body ?? '';
      refreshUnread();
      appMessengerKey.currentState?.showSnackBar(SnackBar(
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (body.isNotEmpty) Text(body, maxLines: 3, overflow: TextOverflow.ellipsis),
        ]),
        action: SnackBarAction(label: 'Open', onPressed: () => openFromData(message.data)),
      ));
    });

    // Tapped while the app was in the background.
    FirebaseMessaging.onMessageOpenedApp.listen((message) => openFromData(message.data));

    // Tapped while the app was closed — handled once the dashboard is up
    // (see handleLaunchNotification), since we need to be logged in first.
  }

  static Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${prefs.getString('token') ?? ''}',
      'Content-Type': 'application/json',
      'ngrok-skip-browser-warning': 'true',
    };
  }

  /// Call after login (the dashboard does this on open).
  static Future<void> registerDevice() async {
    if (!_ready) return;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(alert: true, badge: true, sound: true);
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('Notification permission denied');
        return;
      }
      final token = await messaging.getToken();
      if (token == null) return;
      await _sendToken(token);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('push_token', token);
      messaging.onTokenRefresh.listen(_sendToken);
    } catch (e) {
      debugPrint('Push registration failed: $e');
    }
  }

  static Future<void> _sendToken(String token) async {
    try {
      await http.post(
        Uri.parse('${AppConfig.apiBaseUrl}/notifications/token'),
        headers: await _headers(),
        body: jsonEncode({'token': token, 'platform': 'android', 'device_info': 'Ida AgriCo Android app'}),
      );
    } catch (e) {
      debugPrint('Could not send push token: $e');
    }
  }

  /// Call on sign-out, BEFORE clearing the saved login.
  static Future<void> unregisterDevice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('push_token');
      if (token != null) {
        await http.delete(
          Uri.parse('${AppConfig.apiBaseUrl}/notifications/token'),
          headers: await _headers(),
          body: jsonEncode({'token': token}),
        );
      }
      if (_ready) await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('Push unregister failed: $e');
    }
    unreadCount.value = 0;
  }

  /// Unread count for the bell on the dashboard.
  static Future<void> refreshUnread() async {
    try {
      final res = await http.get(Uri.parse('${AppConfig.apiBaseUrl}/notifications/unread-count'), headers: await _headers());
      if (res.statusCode == 200) {
        unreadCount.value = (jsonDecode(res.body)['unread'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}
  }

  /// If the app was opened by tapping a notification, go to its screen.
  /// Called once by the dashboard after login.
  static Future<void> handleLaunchNotification() async {
    if (!_ready) return;
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) openFromData(initial.data);
    } catch (_) {}
  }

  static Future<void> markRead(dynamic id) async {
    if (id == null || id.toString().isEmpty) return;
    try {
      await http.patch(Uri.parse('${AppConfig.apiBaseUrl}/notifications/$id/read'), headers: await _headers());
    } catch (_) {}
    refreshUnread();
  }

  static void openFromData(Map<String, dynamic> data) {
    markRead(data['notification_id']);
    openRoute(data['route']?.toString() ?? '', data);
  }

  /// Route keys come from the backend (services/notificationHooks.js and
  /// reminderScheduler.js). Destinations mirror the Needs Attention screen
  /// and the dashboard's "returned" banner, so a notification lands on the
  /// same place those do. Unknown keys open the notifications list.
  static void openRoute(String route, Map<String, dynamic> data) {
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    final type = (data['type'] ?? '').toString();
    final module = (data['module'] ?? '').toString();
    final id = (data['id'] ?? '').toString();
    final note = (data['note'] ?? '').toString();
    final returned = type == 'returned' && id.isNotEmpty;
    final approval = type == 'approval_request';
    final date = DateTime.tryParse((data['date'] ?? '').toString());
    final recordId = int.tryParse((data['record_id'] ?? '').toString());

    // Same tab order as AdminReviewScreen / NeedsAttentionScreen.
    const reviewTab = {'electricity': 0, 'tractor': 1, 'factory': 3, 'machine': 4, 'machine_pf': 5};

    Widget screen;
    switch (route) {
      case 'admin_review':
        screen = AdminReviewScreen(initialFilter: 'pending', initialTabIndex: reviewTab[module] ?? 0);
        break;
      case 'electricity':
        screen = returned ? ElectricityReadingScreen(returnedRecordId: id, adminNote: note) : const ElectricityReadingScreen();
        break;
      case 'tractor':
        screen = returned ? TractorReadingScreen(returnedRecordId: id, adminNote: note) : const TractorReadingScreen();
        break;
      case 'machine':
        screen = returned ? MachineReadingScreen(returnedRecordId: id, adminNote: note) : const MachineReadingScreen();
        break;
      case 'machine_pf':
        screen = returned ? MachinePfScreen(returnedRecordId: id, adminNote: note) : const MachinePfScreen();
        break;
      case 'factory':
        screen = const FactoryRunScreen();
        break;
      case 'factory_tractor_diesel':
        screen = const FactoryTractorDieselScreen();
        break;
      case 'attendance':
        screen = (data['stage'] == 'allocation' && date != null)
            ? WorkAllocationScreen(attendanceDate: date)
            : AttendanceScreen(initialDate: date);
        break;
      case 'machine_maintenance':
        screen = approval ? const MachineMaintScreen(initialTabIndex: 2) : const MachineMaintScreen();
        break;
      case 'tractor_maintenance':
        screen = approval ? const MaintenanceScreen(initialTabIndex: 2) : const MaintenanceScreen();
        break;
      case 'outward_register_review':
        screen = recordId != null ? OutwardRegisterReviewScreen(recordId: recordId) : const OutwardRegisterReviewListScreen();
        break;
      case 'outward_register_entry':
        screen = OutwardRegisterScreen(recordId: recordId);
        break;
      case 'otp_approvals':
        screen = const OtpApprovalsScreen();
        break;
      default:
        screen = const NotificationsScreen();
    }
    nav.push(MaterialPageRoute(builder: (_) => screen));
  }
}
