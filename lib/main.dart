import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/welcome_screen.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/admin/users_screen.dart';
import 'screens/admin_review_screen.dart';
import 'localization/app_locale.dart';
import 'localization/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Apply whatever language was cached from the last session before the
  // first frame, so returning users don't see a flash of English before
  // their real account preference (set again after login) is applied.
  await AppLocale.loadCachedLanguage();
  runApp(const IdaAgriCoApp());
}

class IdaAgriCoApp extends StatelessWidget {
  const IdaAgriCoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: appLocaleNotifier,
      builder: (context, locale, _) {
        return MaterialApp(
          title: 'Ida AgriCo',
          debugShowCheckedModeBanner: false,
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
            '/admin/review': (_) => const AdminReviewScreen(),
          },
        );
      },
    );
  }
}
