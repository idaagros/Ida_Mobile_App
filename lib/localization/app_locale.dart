// lib/localization/app_locale.dart
//
// Global, app-wide current language. Deliberately NOT using the
// `flutter gen-l10n` code-generation pipeline (ARB files + build_runner)
// — that requires a build step this project's toolchain (FlutLab's
// online editor) may not support. Instead, translations are plain Dart
// (see app_localizations.dart), and this file just tracks "which
// language is active right now" as a simple ValueNotifier that
// main.dart listens to, rebuilding the MaterialApp when it changes.
//
// Source of truth for a logged-in user is their account's
// `preferred_language` (returned on login, settable via
// PUT /api/users/me/language) — NOT a per-device setting. Before
// login, we fall back to whatever was last cached locally on this
// device (or English), purely so the login screen itself has
// something reasonable to show.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kSupportedLanguages = ['en', 'mr'];
const kDefaultLanguage = 'en';

/// The single source of truth for the app's current UI language.
/// Wrap MaterialApp in a ValueListenableBuilder on this in main.dart.
final ValueNotifier<Locale> appLocaleNotifier = ValueNotifier(const Locale(kDefaultLanguage));

class AppLocale {
  AppLocale._();

  /// Call once at app startup, before the first frame if possible —
  /// applies whatever language was cached on this device from the last
  /// session, so returning users don't see a flash of English before
  /// their real preference (from login) arrives.
  static Future<void> loadCachedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('language') ?? kDefaultLanguage;
    if (kSupportedLanguages.contains(code)) {
      appLocaleNotifier.value = Locale(code);
    }
  }

  /// Applies a language code as the app's current display language and
  /// caches it locally. Called with the value from a login response
  /// (authoritative) or from the in-app language switcher.
  static Future<void> apply(String code) async {
    if (!kSupportedLanguages.contains(code)) return;
    appLocaleNotifier.value = Locale(code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', code);
  }

  static String get current => appLocaleNotifier.value.languageCode;
}
