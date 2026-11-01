// lib/widgets/tally_company_badge.dart
//
// A small label on every screen that talks to TallyPrime: which company it is connected to.
//   TallyCompanyBadge(company: name)   the company this screen is using (chosen on the screen / read from its settings)
//   TallyCompanyBadge()                the app's default Tally company (TALLY_COMPANY on the server, GET /api/tally-info)
// Shows nothing while the name is still being read. An empty name shows an orange "no company chosen".
// Web counterpart: src/components/TallyBadge.jsx.

import 'package:flutter/material.dart';
import '../services/api_client.dart';

String? _cachedDefaultCompany;

class TallyCompanyBadge extends StatefulWidget {
  final String? company;
  const TallyCompanyBadge({super.key, this.company});

  @override
  State<TallyCompanyBadge> createState() => _TallyCompanyBadgeState();
}

class _TallyCompanyBadgeState extends State<TallyCompanyBadge> {
  String? _def = _cachedDefaultCompany;

  @override
  void initState() {
    super.initState();
    if (widget.company == null && _def == null) _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.json('GET', '/tally-info');
      final name = (r is Map ? (r['company'] ?? '') : '').toString();
      _cachedDefaultCompany = name;
      if (mounted) setState(() => _def = name);
    } catch (_) {
      // stays hidden when the server cannot be reached
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.company ?? _def;
    if (name == null) return const SizedBox.shrink();
    final none = name.trim().isEmpty;
    final fg = none ? const Color(0xFF6B4A00) : const Color(0xFF1F4A0E);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: none ? const Color(0xFFFFF8E6) : const Color(0xFFF3F8EE),
          border: Border.all(color: none ? const Color(0xFFECD9A4) : const Color(0xFFCFE3C0)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, size: 9, color: none ? const Color(0xFFE0A526) : const Color(0xFF4A9A2B)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              none ? 'Tally: no company chosen' : 'Connected to Tally: $name',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: fg),
            ),
          ),
        ]),
      ),
    );
  }
}
