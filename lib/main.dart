import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/welcome_screen.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/admin/users_screen.dart';
import 'screens/review/review_queue_screen.dart';
import 'screens/offline_queue_screen.dart';
import 'localization/app_locale.dart';
import 'localization/app_localizations.dart';
import 'services/push_service.dart';
import 'services/offline_queue.dart';
import 'config/app_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Server address: the built-in one, or one an admin saved on this
  // phone (App settings -> Server address). Must load before anything
  // calls the API.
  await AppConfig.load();
  // Apply whatever language was cached from the last session before the
  // first frame, so returning users don't see a flash of English before
  // their real account preference (set again after login) is applied.
  await AppLocale.loadCachedLanguage();
  // Notifications: the app checks the server itself (no outside push
  // service). Safe if anything fails - the app runs normally without them.
  await PushService.init();
  // Offline entry: load entries waiting to be sent and start trying.
  await Offline.init();
  runApp(const IdaAgriCoApp());
}

class IdaAgriCoApp extends StatefulWidget {
  const IdaAgriCoApp({super.key});

  @override
  State<IdaAgriCoApp> createState() => _IdaAgriCoAppState();
}

class _IdaAgriCoAppState extends State<IdaAgriCoApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back in front: try to send anything saved without signal.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) Offline.onResume();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: appLocaleNotifier,
      builder: (context, locale, _) {
        return MaterialApp(
          title: 'Ida AgriCo',
          debugShowCheckedModeBanner: false,
          // Lets a tapped notification open a screen and show an in-app
          // banner from outside any widget (see services/push_service.dart).
          navigatorKey: appNavigatorKey,
          scaffoldMessengerKey: appMessengerKey,
          locale: locale,
          supportedLocales: const [Locale('en'), Locale('mr')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData(
            colorSchemeSeed: const Color(0xFF3B7A28),
            useMaterial3: true,
          ),
          home: const WelcomeScreen(),
          routes: {
            '/login': (_) => const LoginScreen(),
            '/dashboard': (_) => const DashboardScreen(),
            '/admin/users': (_) => const UsersScreen(),
            '/admin/review': (_) => const ReviewQueueScreen(),
            '/offline': (_) => const OfflineQueueScreen(),
          },
        );
      },
    );
  }
}
