// lib/screens/tv_dashboard_screen.dart
//
// Full-screen, unattended display for an office/factory TV - not a
// normal in-hand mobile screen. Two things follow from that:
//
// 1. NO scrolling, anywhere, ever. A screen nobody is touching can't
//    be scrolled to see what's cut off, so every section sizes itself
//    to whatever space it's given (LayoutBuilder + Expanded/Flexible
//    throughout) rather than assuming a fixed pixel size and letting
//    overflow happen quietly off-screen. Variable-length lists
//    (upcoming sprays, crop sown) are defensively capped in the UI
//    itself, not just trusted to arrive short from the backend.
//
// 2. It fetches once, then re-fetches every 30 minutes on a timer -
//    not on every rebuild, since this keeps running unattended for
//    hours. A stale-data indicator (last-updated timestamp) is always
//    visible, since a silently-frozen number looks identical to a
//    correct one until someone thinks to check.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../config/app_config.dart';
class TvDashboardScreen extends StatefulWidget {
  const TvDashboardScreen({super.key});
  @override
  State<TvDashboardScreen> createState() => _TvDashboardScreenState();
}

class _TvDashboardScreenState extends State<TvDashboardScreen> {
  static const baseUrl = AppConfig.apiBaseUrl;

  Map<String, dynamic>? data;
  bool loading = true;
  String? error;
  DateTime? lastUpdated;
  Timer? _refreshTimer;

  static const _bg = Color(0xFF0B1410);
  static const _cardBg = Color(0xFF152119);
  static const _overviewColor = Color(0xFFF5A623);
  static const _factoryColor = Color(0xFF4FA3E3);
  static const _agriColor = Color(0xFF6FCF6F);
  static const _textMuted = Color(0xFF8FA396);

  @override
  void initState() {
    super.initState();
    _load();
    // 30-minute auto-refresh, per the agreed cadence - this is meant
    // to run unattended, so the timer (not user action) is the only
    // thing keeping the numbers current.
    _refreshTimer = Timer.periodic(const Duration(minutes: 30), (_) => _load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      final res = await http.get(
        Uri.parse('$baseUrl/tv-dashboard/'),
        headers: {
          'Authorization': 'Bearer $token',
          'ngrok-skip-browser-warning': 'true'
        },
      );
      if (res.statusCode == 200) {
        setState(() {
          data = jsonDecode(res.body);
          loading = false;
          error = null;
          lastUpdated = DateTime.now();
        });
      } else {
        // The backend sends { error: err.message } on a 500 - show
        // that actual message rather than just the status code, so
        // diagnosing a failure doesn't require server log access at
        // all. Falls back to the status code only if the body isn't
        // parseable JSON for some reason.
        String detail = 'status ${res.statusCode}';
        try {
          final body = jsonDecode(res.body);
          if (body is Map && body['error'] != null)
            detail = body['error'].toString();
        } catch (_) {}
        setState(() {
          loading = false;
          error = 'Failed to load: $detail';
        });
      }
    } catch (e) {
      setState(() {
        loading = false;
        error = 'Connection error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: loading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white))
            : error != null
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.wifi_off, color: _textMuted, size: 48),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: _textMuted, fontSize: 16)),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: _load,
                        child: const Text('Retry',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ]),
                  )
                : LayoutBuilder(builder: (context, constraints) {
                    // Scale factor so text/icons grow on a genuinely
                    // large TV panel rather than staying phone-sized -
                    // 1.0 around a 1000px-wide window, up to ~1.6x on
                    // a 1900px+ display.
                    final scale =
                        (constraints.maxWidth / 1000).clamp(0.75, 1.6);
                    return Padding(
                      padding: EdgeInsets.all(16 * scale),
                      child: Column(children: [
                        _header(scale),
                        SizedBox(height: 14 * scale),
                        Expanded(
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                    flex: 5, child: _overviewColumn(scale)),
                                SizedBox(width: 14 * scale),
                                Expanded(flex: 6, child: _factoryColumn(scale)),
                                SizedBox(width: 14 * scale),
                                Expanded(
                                    flex: 6, child: _agricultureColumn(scale)),
                              ]),
                        ),
                      ]),
                    );
                  }),
      ),
    );
  }

  Widget _header(double scale) {
    final updatedLabel = lastUpdated != null
        ? 'Updated ${DateFormat('h:mm a').format(lastUpdated!)}'
        : '';
    return Row(children: [
      Icon(Icons.eco, color: _agriColor, size: 30 * scale),
      SizedBox(width: 10 * scale),
      Text('Ida AgriCo',
          style: TextStyle(
              color: Colors.white,
              fontSize: 24 * scale,
              fontWeight: FontWeight.w700)),
      SizedBox(width: 10 * scale),
      Text('Live Dashboard',
          style: TextStyle(
              color: _textMuted,
              fontSize: 16 * scale,
              fontWeight: FontWeight.w500)),
      const Spacer(),
      Text(DateFormat('EEEE, d MMM yyyy').format(DateTime.now()),
          style: TextStyle(color: _textMuted, fontSize: 14 * scale)),
      SizedBox(width: 14 * scale),
      Icon(Icons.circle, color: _agriColor, size: 8 * scale),
      SizedBox(width: 6 * scale),
      Text(updatedLabel,
          style: TextStyle(color: _textMuted, fontSize: 13 * scale)),
    ]);
  }

  // ── Section: Overview ──────────────────────────────────────
  Widget _overviewColumn(double scale) {
    final ov = data!['overview'] as Map<String, dynamic>;
    final upcoming = (ov['upcoming_sprays'] as List).take(3).toList();
    return _sectionCard(
      scale: scale,
      title: 'Overview',
      icon: Icons.dashboard_customize_outlined,
      color: _overviewColor,
      children: [
        _statTile(
            scale,
            Icons.local_shipping_outlined,
            'Finished Goods Dispatched',
            '${_fmt(ov['finished_goods_dispatched_tons'])} tons',
            _overviewColor,
            sub: 'till date'),
        _statTile(scale, Icons.fact_check_outlined, 'Pending Approvals',
            '${ov['pending_approvals']}', _overviewColor),
        _statTile(scale, Icons.warning_amber_rounded, 'Spray Overdue',
            '${ov['spray_overdue']}', const Color(0xFFE05D5D)),
        _listTile(
          scale,
          Icons.event_outlined,
          'Upcoming Spray',
          _agriColor,
          upcoming.isEmpty
              ? ['None scheduled']
              : upcoming
                  .map<String>((s) =>
                      '${s['crop_name']} — ${DateFormat('d MMM').format(DateTime.parse(s['planned_date']))}')
                  .toList(),
        ),
      ],
    );
  }

  // ── Section: Factory ───────────────────────────────────────
  Widget _factoryColumn(double scale) {
    final f = data!['factory'] as Map<String, dynamic>;
    return _sectionCard(
      scale: scale,
      title: 'Factory',
      icon: Icons.factory_outlined,
      color: _factoryColor,
      children: [
        _statPairRow(
            scale,
            Icons.bolt_outlined,
            'Units Consumed',
            _fmt(f['units_consumed_yesterday']),
            'yesterday',
            _fmt(f['units_consumed_month']),
            'this month',
            _factoryColor),
        _statPairRow(
            scale,
            Icons.precision_manufacturing_outlined,
            'Machine Run Hours',
            _fmt(f['machine_hours_yesterday']),
            'yesterday',
            _fmt(f['machine_hours_month']),
            'this month',
            _factoryColor),
        _statPairRow(
            scale,
            Icons.speed_outlined,
            'Power Factor',
            _fmtPf(f['pf_yesterday']),
            'yesterday',
            _fmtPf(f['avg_pf_all_time']),
            'all-time avg',
            _factoryColor),
        _statTile(
            scale,
            Icons.receipt_long_outlined,
            'Projected Electricity Bill',
            f['projected_electricity_bill'] != null
                ? '₹${_fmtMoney(f['projected_electricity_bill'])}'
                : '—',
            _factoryColor,
            sub: 'this month'),
        _statPairRow(
            scale,
            Icons.agriculture,
            'Tractor',
            '${_fmt(f['tractor_hours_month'])} hrs',
            'hours/mo',
            '${_fmt(f['tractor_diesel_liters_month'])} L',
            'diesel/mo',
            _factoryColor),
      ],
    );
  }

  // ── Section: Agriculture ───────────────────────────────────
  Widget _agricultureColumn(double scale) {
    final a = data!['agriculture'] as Map<String, dynamic>;
    final today = a['workers_today'] as Map<String, dynamic>;
    final week = a['workers_week'] as Map<String, dynamic>;
    // Defensive cap in the UI itself, not just trusting the backend
    // to always return a short list - "no scrolling" has to hold even
    // if someone eventually sows six or seven different crops at once.
    final crops = (a['crop_sown'] as List);
    final shownCrops = crops.take(4).toList();
    final extraCropCount = crops.length - shownCrops.length;

    return _sectionCard(
      scale: scale,
      title: 'Agriculture',
      icon: Icons.grass_outlined,
      color: _agriColor,
      children: [
        _workersTile(scale, 'Workers Present Today', today, _agriColor),
        _workersTile(scale, 'Workers This Week (Sun–Sat)', week, _agriColor),
        _statPairRow(
            scale,
            Icons.agriculture,
            'Tractor',
            '${_fmt(a['tractor_hours_month'])} hrs',
            'hours/mo',
            '${_fmt(a['tractor_diesel_liters_month'])} L',
            'diesel/mo',
            _agriColor),
        _listTile(
          scale,
          Icons.spa_outlined,
          'Crop Sown',
          _agriColor,
          shownCrops.isEmpty
              ? ['None currently sown']
              : [
                  ...shownCrops.map<String>(
                      (c) => '${c['crop_name']} — ${_fmt(c['acres'])} acres'),
                  if (extraCropCount > 0) '+ $extraCropCount more',
                ],
        ),
      ],
    );
  }

  // ── Shared building blocks ─────────────────────────────────

  Widget _sectionCard({
    required double scale,
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Container(
      padding: EdgeInsets.all(14 * scale),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16 * scale),
        border: Border.all(color: color.withOpacity(0.25), width: 1.2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, color: color, size: 22 * scale),
          SizedBox(width: 8 * scale),
          Text(title,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18 * scale,
                  fontWeight: FontWeight.w700)),
        ]),
        SizedBox(height: 10 * scale),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 320 * scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final c in children) ...[
                    c,
                    SizedBox(height: 14 * scale)
                  ],
                ],
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _statTile(
      double scale, IconData icon, String label, String value, Color color,
      {String? sub}) {
    return Row(children: [
      Container(
        padding: EdgeInsets.all(8 * scale),
        decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10 * scale)),
        child: Icon(icon, color: color, size: 18 * scale),
      ),
      SizedBox(width: 10 * scale),
      Expanded(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: TextStyle(
                      color: _textMuted,
                      fontSize: 12 * scale,
                      fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Row(children: [
                Text(value,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20 * scale,
                        fontWeight: FontWeight.w800)),
                if (sub != null) ...[
                  SizedBox(width: 6 * scale),
                  Text(sub,
                      style:
                          TextStyle(color: _textMuted, fontSize: 11 * scale)),
                ],
              ]),
            ]),
      ),
    ]);
  }

  Widget _statPairRow(double scale, IconData icon, String label, String value1,
      String sub1, String value2, String sub2, Color color) {
    return Row(children: [
      Container(
        padding: EdgeInsets.all(8 * scale),
        decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10 * scale)),
        child: Icon(icon, color: color, size: 18 * scale),
      ),
      SizedBox(width: 10 * scale),
      Expanded(
        flex: 3,
        child: Text(label,
            style: TextStyle(
                color: _textMuted,
                fontSize: 12 * scale,
                fontWeight: FontWeight.w600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
      ),
      Expanded(
        flex: 2,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value1,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15 * scale,
                      fontWeight: FontWeight.w700)),
              Text(sub1,
                  style: TextStyle(color: _textMuted, fontSize: 10 * scale)),
            ]),
      ),
      SizedBox(width: 8 * scale),
      Expanded(
        flex: 2,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value2,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15 * scale,
                      fontWeight: FontWeight.w700)),
              Text(sub2,
                  style: TextStyle(color: _textMuted, fontSize: 10 * scale)),
            ]),
      ),
    ]);
  }

  Widget _listTile(double scale, IconData icon, String label, Color color,
      List<String> lines) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: EdgeInsets.all(8 * scale),
        decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10 * scale)),
        child: Icon(icon, color: color, size: 18 * scale),
      ),
      SizedBox(width: 10 * scale),
      Expanded(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: TextStyle(
                      color: _textMuted,
                      fontSize: 12 * scale,
                      fontWeight: FontWeight.w600)),
              SizedBox(height: 2 * scale),
              ...lines.map((l) => Text(l,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 13 * scale,
                      fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)),
            ]),
      ),
    ]);
  }

  Widget _workersTile(
      double scale, String label, Map<String, dynamic> counts, Color color) {
    return Row(children: [
      Container(
        padding: EdgeInsets.all(8 * scale),
        decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10 * scale)),
        child: Icon(Icons.groups_outlined, color: color, size: 18 * scale),
      ),
      SizedBox(width: 10 * scale),
      Expanded(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: TextStyle(
                      color: _textMuted,
                      fontSize: 12 * scale,
                      fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Row(children: [
                Text('${counts['total']}',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20 * scale,
                        fontWeight: FontWeight.w800)),
                SizedBox(width: 10 * scale),
                Icon(Icons.male,
                    color: const Color(0xFF4FA3E3), size: 14 * scale),
                Text(' ${counts['male']}',
                    style: TextStyle(color: _textMuted, fontSize: 13 * scale)),
                SizedBox(width: 8 * scale),
                Icon(Icons.female,
                    color: const Color(0xFFE07BB0), size: 14 * scale),
                Text(' ${counts['female']}',
                    style: TextStyle(color: _textMuted, fontSize: 13 * scale)),
              ]),
            ]),
      ),
    ]);
  }

  String _fmt(dynamic v) {
    if (v == null) return '—';
    final n = v is num ? v : double.tryParse(v.toString());
    if (n == null) return '—';
    return n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(1);
  }

  String _fmtPf(dynamic v) {
    if (v == null) return '—';
    final n = v is num ? v : double.tryParse(v.toString());
    if (n == null) return '—';
    return n.toStringAsFixed(2);
  }

  String _fmtMoney(dynamic v) {
    final n = v is num ? v : double.tryParse(v.toString()) ?? 0;
    return NumberFormat('#,##,##0', 'en_IN').format(n);
  }
}
