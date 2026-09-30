// lib/services/push_service.dart
//
// Phone notifications without any outside push service (Sep 2026).
//
// The phone asks the server for new notifications itself:
//  - when the app is open: every minute (the dashboard's timer) — a new
//    one shows as a banner at the bottom with an "Open" button;
//  - when the app is closed or in the background: about every 15 minutes
//    (Android's shortest interval for background work, via workmanager) —
//    a new one shows as a normal phone notification. Android may delay
//    this on battery saver, and some phones (Xiaomi, Oppo, Vivo, Realme)
//    need battery "No restrictions" + Autostart for it to run at all.
//  - Tapping a notification opens the matching screen via openRoute().
//
//  - init() once at app start (main.dart).
//  - registerDevice() after login (dashboard): asks for notification
//    permission (Android 13+), starts the background check and tells the
//    server this phone is checking (admin's "Notification setup" list).
//  - unregisterDevice() on sign-out, so the next person to log in on this
//    phone doesn't get the previous user's notifications.
//
// Server side: GET /api/notifications (the same list as the bell).

import 'dart:convert';
import 'dart:math';
import 'dart:ui' show DartPluginRegistrant;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../config/app_config.dart';
import '../screens/review/review_queue_screen.dart';
import '../screens/attendance_screen.dart';
import '../screens/electricity_screen.dart';
import '../screens/factory_screen.dart';
import '../screens/factory_tractor_diesel_screen.dart';
import '../screens/machine_maintenance_screen.dart';
import '../screens/machine_pf_screen.dart';
import '../screens/machine_reading_screen.dart';
import '../screens/maintenance_screen.dart';
import '../screens/mandi/mandi_commodity_screen.dart';
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

const String _checkTask = 'ida-notification-check';
const String _prefLastId = 'notif_last_shown_id';
const String _prefDeviceId = 'notif_device_id';
const String _channelId = 'ida_notifications';
const String _channelName = 'Ida AgriCo';

final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

// Background check (runs in its own isolate, app closed or not).
@pragma('vm:entry-point')
void notificationCheckDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      DartPluginRegistrant.ensureInitialized();
      await AppConfig.load();
      await PushService._initLocal();
      await PushService.checkNow(background: true);
    } catch (_) {}
    return true; // never ask Android to retry; the next run comes anyway
  });
}

class PushService {
  static bool _ready = false;
  static bool get isReady => _ready;
  static bool _checking = false;
  static final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  static Future<void> _initLocal({void Function(NotificationResponse)? onTap}) async {
    await _local.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: onTap,
    );
  }

  static Future<void> init() async {
    try {
      await _initLocal(onTap: (r) => _openPayload(r.payload));
      await Workmanager().initialize(notificationCheckDispatcher);
      _ready = true;
    } catch (e) {
      debugPrint('Notifications disabled: $e');
      _ready = false;
    }
  }

  static void _openPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      openFromData(Map<String, dynamic>.from(jsonDecode(payload) as Map));
    } catch (_) {}
  }

  static Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${prefs.getString('token') ?? ''}',
      'Content-Type': 'application/json',
    };
  }

  static Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_prefDeviceId);
    if (id == null || id.isEmpty) {
      final r = Random.secure();
      id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await prefs.setString(_prefDeviceId, id);
    }
    return id;
  }

  /// Call after login (the dashboard does this on open).
  static Future<void> registerDevice() async {
    if (!_ready) return;
    try {
      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {}
    try {
      await Workmanager().registerPeriodicTask(
        _checkTask,
        _checkTask,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } catch (e) {
      debugPrint('Background check not started: $e');
    }
    await _tellServer();
    await checkNow();
  }

  // Shows this phone in the admin's device list, with when it last checked.
  static Future<void> _tellServer() async {
    try {
      await http.post(
        Uri.parse('${AppConfig.apiBaseUrl}/notifications/token'),
        headers: await _headers(),
        body: jsonEncode({'token': 'check:${await _deviceId()}', 'platform': 'android', 'device_info': 'Ida AgriCo Android app'}),
      );
    } catch (_) {}
  }

  /// Fetches the latest notifications; new unread ones are shown as phone
  /// notifications (background) or a banner (app open). Also refreshes the
  /// bell count. The first check after login only remembers where the list
  /// is, so old notifications don't all pop up at once.
  static Future<void> checkNow({bool background = false}) async {
    if (_checking) return;
    _checking = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      // The background check runs in its own isolate and writes the same
      // keys - re-read so neither side shows a notification twice.
      await prefs.reload();
      if ((prefs.getString('token') ?? '').isEmpty) return;
      final res = await http.get(Uri.parse('${AppConfig.apiBaseUrl}/notifications?limit=20'), headers: await _headers());
      if (res.statusCode != 200) return;
      final d = jsonDecode(res.body) as Map;
      unreadCount.value = (d['unread'] as num?)?.toInt() ?? 0;
      final items = ((d['items'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (items.isEmpty) return;
      int idOf(Map n) => int.tryParse('${n['id']}') ?? 0;
      final newest = items.map(idOf).reduce(max);
      final last = prefs.getInt(_prefLastId);
      await prefs.setInt(_prefLastId, max(newest, last ?? 0));
      if (last == null) return; // first check on this phone / after login
      final fresh = items.where((n) => idOf(n) > last && n['read_at'] == null).toList()
        ..sort((a, b) => idOf(a).compareTo(idOf(b)));
      if (fresh.isEmpty) return;

      // Banner only when the app is actually on screen; otherwise (e.g. the
      // dashboard's timer firing while the app is in the background) show
      // it as a phone notification so it isn't missed.
      final onScreen = !background && WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
      if (onScreen && appMessengerKey.currentState != null) {
        _banner(fresh.last, more: fresh.length - 1);
      } else {
        for (final n in fresh.length > 5 ? fresh.sublist(fresh.length - 5) : fresh) {
          await _showPhoneNotification(n);
        }
      }
      if (background) await _tellServer();
    } catch (e) {
      debugPrint('Notification check failed: $e');
    } finally {
      _checking = false;
    }
  }

  static Map<String, dynamic> _dataOf(Map<String, dynamic> n) => {
        ...(n['data'] is Map ? Map<String, dynamic>.from(n['data'] as Map) : const <String, dynamic>{}),
        'type': n['type'],
        'module': n['module'],
        'route': n['route'],
        'notification_id': '${n['id']}',
      };

  static Future<void> _showPhoneNotification(Map<String, dynamic> n) async {
    await _local.show(
      int.tryParse('${n['id']}') ?? 0,
      '${n['title'] ?? 'Ida AgriCo'}',
      '${n['body'] ?? ''}',
      const NotificationDetails(
        android: AndroidNotificationDetails(_channelId, _channelName,
            channelDescription: 'Approvals, returned entries, reminders and price alerts',
            importance: Importance.high,
            priority: Priority.high),
      ),
      payload: jsonEncode(_dataOf(n)),
    );
  }

  static void _banner(Map<String, dynamic> n, {int more = 0}) {
    appMessengerKey.currentState?.showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      behavior: SnackBarBehavior.floating,
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${n['title'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
        if ('${n['body'] ?? ''}'.isNotEmpty) Text('${n['body']}', maxLines: 3, overflow: TextOverflow.ellipsis),
        if (more > 0) Text('+ $more more in Notifications', style: const TextStyle(fontSize: 12)),
      ]),
      action: SnackBarAction(label: 'Open', onPressed: () => openFromData(_dataOf(n))),
    ));
  }

  /// Call on sign-out, BEFORE clearing the saved login.
  static Future<void> unregisterDevice() async {
    try {
      await http.delete(
        Uri.parse('${AppConfig.apiBaseUrl}/notifications/token'),
        headers: await _headers(),
        body: jsonEncode({'token': 'check:${await _deviceId()}'}),
      );
    } catch (_) {}
    try {
      await Workmanager().cancelByUniqueName(_checkTask);
      await _local.cancelAll();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefLastId);
    } catch (e) {
      debugPrint('Notification sign-out tidy-up failed: $e');
    }
    unreadCount.value = 0;
  }

  /// Unread count for the bell on the dashboard; also picks up new
  /// notifications while the app is open.
  static Future<void> refreshUnread() => checkNow();

  /// If the app was opened by tapping a phone notification, go to its
  /// screen. Called once by the dashboard after login.
  static bool _launchHandled = false;
  static Future<void> handleLaunchNotification() async {
    if (!_ready || _launchHandled) return;
    _launchHandled = true;
    try {
      final details = await _local.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp == true) _openPayload(details!.notificationResponse?.payload);
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
    final commodityId = int.tryParse((data['commodity_id'] ?? '').toString());

    // Modules the Review submissions screen can filter to.
    const reviewTab = {'electricity', 'tractor', 'factory', 'machine', 'machine_pf', 'machine_maintenance', 'tractor_maintenance'};

    Widget screen;
    switch (route) {
      case 'admin_review':
        screen = ReviewQueueScreen(
            module: !reviewTab.contains(module) ? null : module.endsWith('_maintenance') ? 'maintenance' : module,
            openKey: id.isNotEmpty && reviewTab.contains(module) ? '$module:$id' : null,
            openDate: date == null ? null : date.toIso8601String().substring(0, 10));
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
      case 'mandi_commodity':
        screen = commodityId != null
            ? MandiCommodityScreen(
                commodityId: commodityId,
                title: (data['commodity_name'] ?? 'Mandi price').toString(),
                openAlerts: true)
            : const NotificationsScreen();
        break;
      default:
        screen = const NotificationsScreen();
    }
    nav.push(MaterialPageRoute(builder: (_) => screen));
  }
}
