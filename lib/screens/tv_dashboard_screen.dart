// lib/screens/tv_dashboard_screen.dart
//
// The old "TV dashboard" screen was replaced in Oct 2026 by the owner's
// dashboard (owner_dashboard_screen.dart), which shows the same three
// pages as the TV in the owner's room. Kept so older links still work.

import 'package:flutter/material.dart';
import 'owner_dashboard_screen.dart';

class TvDashboardScreen extends StatelessWidget {
  const TvDashboardScreen({super.key});
  @override
  Widget build(BuildContext context) => const OwnerDashboardScreen();
}
