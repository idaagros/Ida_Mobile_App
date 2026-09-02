// lib/screens/sector_picker_screen.dart
//
// Shown once after login, ONLY for accounts with tiles in both
// sectors (dashboard_screen.dart decides this before ever pushing
// here — a single-sector user never sees this screen at all). Choice
// is remembered in SharedPreferences by the caller; this screen just
// returns which one was picked via Navigator.pop(context, sector).
//
// No back navigation — PopScope blocks the system back button, since
// a dual-sector user landing here genuinely needs to pick one to
// proceed. Reachable again anytime via the switch icon in the
// dashboard app bar (see dashboard_screen.dart's _switchSector), which
// pushes this same screen but doesn't need the same forced-choice
// framing since the user already has a working sector to fall back on.

import 'package:flutter/material.dart';
import '../localization/app_localizations.dart';

class SectorPickerScreen extends StatelessWidget {
  final bool allowCancel;
  const SectorPickerScreen({super.key, this.allowCancel = false});

  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return PopScope(
      canPop: allowCancel,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F7F2),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset('assets/images/idalogo.png', height: 40),
                const SizedBox(height: 24),
                Text(loc.sectorPickerTitle,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: idaDark)),
                const SizedBox(height: 8),
                Text(loc.sectorPickerSubtitle,
                    style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600, height: 1.4)),
                const SizedBox(height: 32),
                _sectorCard(
                  context,
                  icon: Icons.factory,
                  color: Colors.orange.shade800,
                  bg: const Color(0xFFFEF3DC),
                  label: loc.sectorFactoryLabel,
                  desc: loc.sectorFactoryDesc,
                  value: 'factory',
                ),
                const SizedBox(height: 16),
                _sectorCard(
                  context,
                  icon: Icons.eco,
                  color: idaGreen,
                  bg: const Color(0xFFE8F5E2),
                  label: loc.sectorAgricultureLabel,
                  desc: loc.sectorAgricultureDesc,
                  value: 'agriculture',
                ),
                if (allowCancel) ...[
                  const SizedBox(height: 20),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(MaterialLocalizations.of(context).cancelButtonLabel,
                          style: TextStyle(color: Colors.grey.shade600)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectorCard(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required Color bg,
    required String label,
    required String desc,
    required String value,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.pop(context, value),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0E7D8)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(desc, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.3)),
            ]),
          ),
          Icon(Icons.chevron_right, color: Colors.grey.shade400),
        ]),
      ),
    );
  }
}
