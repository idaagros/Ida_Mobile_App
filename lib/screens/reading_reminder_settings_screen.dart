// lib/screens/reading_reminder_settings_screen.dart
//
// The missing-reading reminder times moved into App settings in Oct 2026
// (group F), next to face login, the same as on the website. This screen
// is kept so the button in Needs attention still works: it simply opens
// App settings.

import 'package:flutter/material.dart';
import 'admin/app_settings_screen.dart';

class ReadingReminderSettingsScreen extends StatelessWidget {
  const ReadingReminderSettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => const AppSettingsScreen();
}
