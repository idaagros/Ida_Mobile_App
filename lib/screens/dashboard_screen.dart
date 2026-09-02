import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/user_model.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'electricity_screen.dart';
import 'tractor_screen.dart';
import 'labour_screen.dart';
import 'factory_screen.dart';
import 'maintenance_screen.dart';
import 'machine_reading_screen.dart';
import 'machine_maintenance_screen.dart';
import 'admin_review_screen.dart';
import 'daily_reports_screen.dart';
import 'pf_alerts_screen.dart';
import 'outward_register_report_screen.dart';
import 'outward_register_list_screen.dart';
import 'outward_register_review_screen.dart';
import 'machine_pf_screen.dart';
import 'admin/parties_screen.dart';
import 'admin/destinations_screen.dart';
import 'admin/farm_masters_screen.dart';
import 'attendance_screen.dart';
import 'farm_tractor_work_screen.dart';
import 'admin/crop_masters_screen.dart';
import 'admin/agronomy_setup_screen.dart';
import 'crop_cycles_screen.dart';
import 'crop_reports_screen.dart';
import 'sector_picker_screen.dart';
import 'needs_attention_screen.dart';
import 'weather_screen.dart';
import 'electricity_bill_projection_screen.dart';
import '../localization/app_localizations.dart';
import '../localization/app_locale.dart';
import '../services/api_service.dart';
import 'transport_screen.dart';
import 'password_screen.dart';
import 'otp_approvals_screen.dart';

// ── Returned record model ─────────────────────────────────────────────────────
class ReturnedRecord {
  final String id;
  final String module;
  final String moduleLabel;
  final String adminNote;
  final String date;
  final String status; // 'returned' (needs fix) | 'rejected' (final)
  bool acknowledged; // dismissed by user but NOT yet resubmitted

  ReturnedRecord({
    required this.id,
    required this.module,
    required this.moduleLabel,
    required this.adminNote,
    required this.date,
    this.status = 'returned',
    this.acknowledged = false,
  });
}

// ── Dashboard ─────────────────────────────────────────────────────────────────
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const amber = Color(0xFFF5A623);
  static const _base = 'https://excusable-moving-preorder.ngrok-free.dev/api';

  String _displayName = '';
  bool _isAdmin = false;
  List<PermissionEntry> _permissions = [];
  int _needsAttentionCount = 0;
  bool _loaded = false;
  bool _hasFactory = false;
  bool _hasAgriculture = false;
  String? _currentSector; // 'factory' | 'agriculture' | null

  // Returned records for this user
  List<ReturnedRecord> _returned = [];
  Timer? _pollTimer;
  Timer? _needsAttentionTimer;

  // Pulse animation for banner
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    // Pulsing border animation
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _loadUser();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _needsAttentionTimer?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    final perms =
        parsePermissions(jsonDecode(prefs.getString('permissions') ?? '[]'));
    final isAdmin =
        prefs.getBool('is_admin') ?? (prefs.getString('role') == 'admin');
    final displayName =
        prefs.getString('display_name') ?? prefs.getString('name') ?? 'User';

    final hasFactory =
        isAdmin || kFactoryModuleKeys.any((k) => hasModuleAccess(perms, k));
    final hasAgriculture =
        isAdmin || kAgricultureModuleKeys.any((k) => hasModuleAccess(perms, k));

    String? sector = prefs.getString('selected_sector');
    final validRemembered = sector == 'factory' || sector == 'agriculture';

    if (hasFactory && hasAgriculture) {
      if (!validRemembered) {
        // Dual-sector account, no remembered choice yet — must pick.
        final chosen = await Navigator.push<String>(
          context,
          MaterialPageRoute(builder: (_) => const SectorPickerScreen()),
        );
        if (!mounted) return;
        sector = chosen ??
            'factory'; // picker always returns a value; fallback is defensive only
        await prefs.setString('selected_sector', sector);
      }
      // else: keep the valid remembered choice, no picker shown.
    } else if (hasFactory) {
      sector = 'factory';
    } else if (hasAgriculture) {
      sector = 'agriculture';
    } else {
      sector =
          null; // no sector-relevant access at all (e.g. passwords-only account)
    }

    if (!mounted) return;
    setState(() {
      _displayName = displayName;
      _isAdmin = isAdmin;
      _permissions = perms;
      _hasFactory = hasFactory;
      _hasAgriculture = hasAgriculture;
      _currentSector = sector;
      _loaded = true;
    });

    // Non-admin users: poll for returned records every 60 seconds
    if (!_isAdmin) {
      await _fetchReturned();
      _pollTimer = Timer.periodic(
        const Duration(seconds: 60),
        (_) => _fetchReturned(),
      );
    }

    // Needs Attention count - relevant to admins AND any non-admin
    // with edit access to at least one reviewable module, so this
    // runs unconditionally; the backend's own permission filtering
    // decides what (if anything) comes back.
    await _fetchNeedsAttention();
    _needsAttentionTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _fetchNeedsAttention(),
    );
  }

  Future<void> _switchSector() async {
    final chosen = await Navigator.push<String>(
      context,
      MaterialPageRoute(
          builder: (_) => const SectorPickerScreen(allowCancel: true)),
    );
    if (chosen == null || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_sector', chosen);
    if (!mounted) return;
    setState(() => _currentSector = chosen);
  }

  Future<void> _fetchReturned() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    if (token.isEmpty) return;

    final headers = {
      'Authorization': 'Bearer $token',
      'ngrok-skip-browser-warning': 'true',
    };

    final modules = {
      'electricity': 'Electricity Reading',
      'tractor': 'Tractor Hours',
      'labour': 'Labour Record',
      'factory': 'Factory Run Hours',
      'machine': 'Machine Hours',
    };

    final fresh = <ReturnedRecord>[];
    for (final m in modules.entries) {
      // Fetch both 'returned' (needs correction) and 'rejected' (final decision)
      for (final fetchStatus in ['returned', 'rejected']) {
        try {
          final res = await http
              .get(
                Uri.parse('$_base/${m.key}?status=$fetchStatus&mine=1'),
                headers: headers,
              )
              .timeout(const Duration(seconds: 6));
          if (res.statusCode == 200) {
            final body = jsonDecode(res.body);
            final list = body is List ? body : (body['data'] as List? ?? []);
            for (final r in list) {
              // Keep acknowledged state if already known
              final existing = _returned.firstWhere(
                (e) => e.id == r['id']?.toString() && e.module == m.key,
                orElse: () => ReturnedRecord(
                  id: r['id']?.toString() ?? '',
                  module: m.key,
                  moduleLabel: m.value,
                  adminNote: r['admin_note']?.toString() ?? '',
                  date:
                      (r['reading_date'] ?? r['date'] ?? r['created_at'] ?? '')
                          .toString(),
                  status: fetchStatus,
                ),
              );
              fresh.add(existing);
            }
          }
        } catch (_) {}
      }
    }

    if (mounted) setState(() => _returned = fresh);
  }

  // Separate from _fetchReturned above (which is field-worker-facing:
  // "your submission was rejected, fix it") - this is the
  // approver-facing counterpart: "these are waiting on YOUR decision".
  // Backend already filters by permission, so an empty/zero result
  // here can mean either genuinely nothing pending, or this account
  // just doesn't have edit access to any reviewable module - either
  // way the card simply doesn't show, no extra client-side check needed.
  Future<void> _fetchNeedsAttention() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    if (token.isEmpty) return;
    try {
      final res = await http.get(
        Uri.parse('$_base/needs-attention'),
        headers: {
          'Authorization': 'Bearer $token',
          'ngrok-skip-browser-warning': 'true'
        },
      ).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) setState(() => _needsAttentionCount = data['total'] ?? 0);
      }
    } catch (_) {}
  }

  bool _can(String key) => _isAdmin || hasModuleAccess(_permissions, key);
  bool _canEdit(String key) => _isAdmin || hasEditAccess(_permissions, key);

  // Called when user taps "Fix now" on a returned record
  void _openModuleForFix(ReturnedRecord r) {
    // Acknowledge (hides from banner temporarily) until resubmit
    setState(() => r.acknowledged = true);

    Widget screen;
    switch (r.module) {
      case 'electricity':
        screen = ElectricityReadingScreen(
            returnedRecordId: r.id, adminNote: r.adminNote);
        break;
      case 'tractor':
        screen = TractorReadingScreen(
            returnedRecordId: r.id, adminNote: r.adminNote);
        break;
      case 'labour':
        screen = LabourScreen();
        break;
      case 'machine':
        screen = MachineReadingScreen(
            returnedRecordId: r.id, adminNote: r.adminNote);
        break;
      default:
        screen = FactoryRunScreen();
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    ).then((_) {
      // Re-fetch after returning from module — if record still returned,
      // un-acknowledge so banner reappears
      _fetchReturned();
    });
  }

  void _showLanguagePicker() {
    final loc = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => ValueListenableBuilder<Locale>(
        valueListenable: appLocaleNotifier,
        builder: (context, locale, _) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(loc.selectLanguage,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            RadioListTile<String>(
              value: 'en',
              groupValue: locale.languageCode,
              activeColor: idaGreen,
              title: Text(loc.english),
              onChanged: (v) => _changeLanguage(ctx, 'en'),
            ),
            RadioListTile<String>(
              value: 'mr',
              groupValue: locale.languageCode,
              activeColor: idaGreen,
              title: Text(loc.marathi),
              onChanged: (v) => _changeLanguage(ctx, 'mr'),
            ),
          ]),
        ),
      ),
    );
  }

  // Only closes the dialog on a CONFIRMED success — if the request to
  // persist the language failed (migration not run, network issue,
  // etc.), the dialog stays open and a clear error shows, instead of
  // silently closing as if it worked and leaving the app stuck on the
  // old language with no explanation.
  Future<void> _changeLanguage(BuildContext dialogContext, String code) async {
    final ok = await ApiService.setLanguage(code);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(dialogContext);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text(
            'Could not change language — check your connection and try again.'),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ));
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign out',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: idaGreen),
            child:
                const Text('Sign out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true) {
      _pollTimer?.cancel();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      if (mounted) Navigator.pushReplacementNamed(context, '/');
    }
  }

  // Unacknowledged returned records shown in banner
  List<ReturnedRecord> get _activeReturned =>
      _returned.where((r) => !r.acknowledged).toList();

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(
        backgroundColor: Color(0xFFF7F9F5),
        body: Center(child: CircularProgressIndicator(color: idaGreen)),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F5),
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(children: [
          Image.asset('assets/images/idalogo.png', height: 28),
          const SizedBox(width: 10),
          const Flexible(
            child: Text('Ida AgriCo',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
        ]),
        actions: [
          // Bell icon with count badge for non-admin
          if (!_isAdmin && _activeReturned.isNotEmpty)
            Stack(children: [
              IconButton(
                icon:
                    const Icon(Icons.notifications_active, color: Colors.white),
                onPressed: () => _scrollToBanner(),
              ),
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
                      color: Colors.red, shape: BoxShape.circle),
                  child: Center(
                    child: Text('${_activeReturned.length}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ]),
          if (_hasFactory && _hasAgriculture)
            IconButton(
                icon: Icon(
                    _currentSector == 'factory' ? Icons.factory : Icons.eco,
                    color: Colors.white70),
                onPressed: _switchSector,
                tooltip: AppLocalizations.of(context)!.sectorSwitchTitle),
          IconButton(
              icon: const Icon(Icons.translate, color: Colors.white70),
              onPressed: _showLanguagePicker,
              tooltip: AppLocalizations.of(context)!.language),
          IconButton(
              icon: const Icon(Icons.logout, color: Colors.white70),
              onPressed: _logout,
              tooltip: 'Sign out'),
        ],
      ),
      body: SingleChildScrollView(
        controller: _scrollCtrl,
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Returned records banner (non-admin, pulsing) ───────────
          if (!_isAdmin && _activeReturned.isNotEmpty) ...[
            _ReturnedBanner(
              records: _activeReturned,
              pulseAnim: _pulseAnim,
              onFix: _openModuleForFix,
              onDismiss: (r) => setState(() => r.acknowledged = true),
            ),
            const SizedBox(height: 16),
          ],

          // ── Welcome card ───────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: idaDark, borderRadius: BorderRadius.circular(16)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(AppLocalizations.of(context)!.welcomeBack(_displayName),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
                style: TextStyle(
                    color: Colors.white.withOpacity(0.5), fontSize: 13),
              ),
            ]),
          ),

          const SizedBox(height: 20),

          // ── Needs Attention summary (admin AND edit-level non-admin
          // alike - the backend already filters by permission, so if
          // this is non-zero, the current user genuinely has something
          // to act on) ─────────────────────────────────────────────
          if (_needsAttentionCount > 0) ...[
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const NeedsAttentionScreen()))
                  .then((_) => _fetchNeedsAttention()),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: const Color(0xFFFEF3DC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFF5D399))),
                child: Row(children: [
                  const Icon(Icons.notifications_active_outlined,
                      color: Color(0xFF92600A), size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '$_needsAttentionCount item${_needsAttentionCount == 1 ? '' : 's'} need${_needsAttentionCount == 1 ? 's' : ''} your attention',
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF92600A))),
                          const Text('Tap to review',
                              style: TextStyle(
                                  fontSize: 12, color: Color(0xFF92600A))),
                        ]),
                  ),
                  const Icon(Icons.chevron_right, color: Color(0xFF92600A)),
                ]),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Admin stats (admin only) ───────────────────────────────
          if (_isAdmin) ...[
            Row(children: [
              _statCard('—', 'Submissions\nthis month', idaGreen),
              const SizedBox(width: 12),
              _statCard('—', 'Pending\nreview', amber),
              const SizedBox(width: 12),
              _statCard('—', 'Rejected /\nreturned', Colors.red.shade400),
            ]),
            const SizedBox(height: 28),
          ] else
            const SizedBox(height: 8),

          // ══════════════════════════════════════════════════════════
          // FACTORY SECTOR
          // ══════════════════════════════════════════════════════════
          if (_currentSector == 'factory') ...[
            // ── Modules ────────────────────────────────────────────────
            if (_can('daily_report') ||
                _can('electricity') ||
                _can('tractor') ||
                _can('labour') ||
                _can('factory') ||
                _can('machine') ||
                _can('machine_pf') ||
                _can('outward_register')) ...[
              _sectionHeader(AppLocalizations.of(context)!.sectionDailyEntries),
              const SizedBox(height: 12),
            ],

            if (_can('electricity'))
              _tile(
                icon: Icons.electric_bolt,
                label: AppLocalizations.of(context)!
                    .moduleLabel('electricity', 'Electricity Reading'),
                sub: AppLocalizations.of(context)!.moduleDescription(
                    'electricity', 'Submit daily meter reading'),
                iconBg: const Color(0xFFFEF3DC),
                iconColor: amber,
                hasPending: _returned
                    .any((r) => r.module == 'electricity' && !r.acknowledged),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ElectricityReadingScreen())),
              ),

            if (_can('electricity'))
              _tile(
                icon: Icons.receipt_long_outlined,
                label: 'Bill Projection',
                sub: 'Estimated monthly bill and cost of low power factor',
                iconBg: const Color(0xFFFEF3DC),
                iconColor: amber,
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            const ElectricityBillProjectionScreen())),
              ),

            if (_can('tractor'))
              _tile(
                icon: Icons.agriculture,
                label: AppLocalizations.of(context)!
                    .moduleLabel('tractor', 'Factory Tractor'),
                sub: AppLocalizations.of(context)!.moduleDescription('tractor',
                    'Submit daily meter reading for the factory\'s own tractor'),
                hasPending: _returned
                    .any((r) => r.module == 'tractor' && !r.acknowledged),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const TractorReadingScreen())),
              ),

            if (_can('labour'))
              _tile(
                icon: Icons.people,
                label: AppLocalizations.of(context)!
                    .moduleLabel('labour', 'Labour Management'),
                sub: AppLocalizations.of(context)!.moduleDescription(
                    'labour', 'Add, edit and view labour records'),
                hasPending: _returned
                    .any((r) => r.module == 'labour' && !r.acknowledged),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const LabourScreen())),
              ),

            if (_can('factory'))
              _tile(
                icon: Icons.factory,
                label: AppLocalizations.of(context)!
                    .moduleLabel('factory', 'Factory Run Hours'),
                sub: AppLocalizations.of(context)!.moduleDescription(
                    'factory', 'Log machine start/stop times for today'),
                hasPending: _returned
                    .any((r) => r.module == 'factory' && !r.acknowledged),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const FactoryRunScreen())),
              ),

            if (_can('machine'))
              _tile(
                icon: Icons.precision_manufacturing,
                label: 'Machine Hours Reading',
                sub: 'Submit daily machine meter reading',
                iconBg: const Color(0xFFE8F0FE),
                iconColor: Color(0xFF1A73E8),
                hasPending: _returned
                    .any((r) => r.module == 'machine' && !r.acknowledged),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const MachineReadingScreen())),
              ),

            if (_can('machine_pf'))
              _tile(
                icon: Icons.bolt,
                label: 'Machine PF Reading',
                sub: 'Submit daily Power Factor (PF) meter reading',
                iconBg: const Color(0xFFFDE8E8),
                iconColor: Color(0xFFE53935),
                hasPending: _returned
                    .any((r) => r.module == 'machine_pf' && !r.acknowledged),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const MachinePfScreen())),
              ),

            if (_can('outward_register'))
              _tile(
                icon: Icons.local_shipping,
                label: 'Outward Sales Register',
                sub: 'Log truck dispatches: weighment, bhada, invoice & agent',
                iconBg: const Color(0xFFE8F0FE),
                iconColor: Color(0xFF1A73E8),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const OutwardRegisterListScreen())),
              ),

            // ── Reports & Analytics ────────────────────────────────────
            if (_can('reports_analytics')) ...[
              const SizedBox(height: 20),
              _sectionHeader(
                  AppLocalizations.of(context)!.sectionReportsAnalytics),
              const SizedBox(height: 12),
              _tile(
                icon: Icons.picture_as_pdf_outlined,
                label: AppLocalizations.of(context)!
                    .moduleLabel('daily_report', 'Daily Reports'),
                sub: AppLocalizations.of(context)!.moduleDescription(
                    'daily_report',
                    'Generate PDF reports of tractor, electricity & machine readings'),
                iconBg: const Color(0xFFFDE8E8),
                iconColor: const Color(0xFFE53935),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const DailyReportsScreen())),
              ),
              _tile(
                icon: Icons.bolt,
                label: 'Low PF Alerts',
                sub: 'Machine power-factor readings below 0.99',
                iconBg: const Color(0xFFFDE8E8),
                iconColor: const Color(0xFFE53935),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const PfAlertsScreen())),
              ),
              _tile(
                icon: Icons.bar_chart_outlined,
                label: 'Electricity History',
                sub: 'View all meter readings & monthly totals',
                iconBg: const Color(0xFFFEF3DC),
                iconColor: amber,
                onTap: () => _soon('Electricity history'),
              ),
              _tile(
                icon: Icons.query_stats,
                label: 'Tractor History',
                sub: 'View all tractor hours & monthly totals',
                onTap: () => _soon('Tractor history'),
              ),
              if (_can('outward_register'))
                _tile(
                  icon: Icons.summarize_outlined,
                  label: 'Outward Sales Report',
                  sub:
                      'Date-range report: Excel or PDF, with section status badges',
                  iconBg: const Color(0xFFE8F0FE),
                  iconColor: const Color(0xFF1A73E8),
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const OutwardRegisterReportScreen())),
                ),
            ],

            // ── Payroll ──────────────────────────────────────────────
            if (_can('payroll')) ...[
              const SizedBox(height: 20),
              _sectionHeader(AppLocalizations.of(context)!.sectionPayroll),
              const SizedBox(height: 12),
              _tile(
                icon: Icons.payments_outlined,
                label: AppLocalizations.of(context)!
                    .moduleLabel('payroll', 'Payroll'),
                sub: AppLocalizations.of(context)!.moduleDescription(
                    'payroll', 'Manage worker wages and deductions'),
                onTap: () => _soon('Payroll'),
              ),
            ],

            // ── Transport ────────────────────────────────────────────
            if (_can('transport')) ...[
              const SizedBox(height: 20),
              _sectionHeader(
                  AppLocalizations.of(context)!.sectionAdministrative),
              const SizedBox(height: 12),
              _tile(
                icon: Icons.local_shipping_outlined,
                label: 'Transport Directory',
                sub: 'Transporter contacts with call & WhatsApp support',
                iconBg: const Color(0xFFE3F2FD),
                iconColor: const Color(0xFF0D47A1),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const TransportScreen())),
              ),
            ],

            // ── Maintenance ──────────────────────────────────────────
            if (_can('tractor_maintenance') || _can('machine_maintenance')) ...[
              const SizedBox(height: 20),
              _sectionHeader('Maintenance'),
              const SizedBox(height: 12),
              if (_can('tractor_maintenance'))
                _tile(
                  icon: Icons.build_circle_outlined,
                  label: 'Tractor Maintenance',
                  sub: 'Maintenance schedule, alerts & history',
                  iconBg: const Color(0xFFFEF3DC),
                  iconColor: amber,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const MaintenanceScreen())),
                ),
              if (_can('machine_maintenance'))
                _tile(
                  icon: Icons.precision_manufacturing_outlined,
                  label: 'Machine Maintenance',
                  sub: 'Machine maintenance schedule, alerts & history',
                  iconBg: const Color(0xFFE8F0FE),
                  iconColor: Color(0xFF1A73E8),
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const MachineMaintScreen())),
                ),
            ],
          ],

          // ══════════════════════════════════════════════════════════
          // AGRICULTURE SECTOR
          // ══════════════════════════════════════════════════════════
          if (_currentSector == 'agriculture') ...[
            if (_can('farm_attendance') ||
                _can('farm_tractor') ||
                _can('agri')) ...[
              _sectionHeader(
                  AppLocalizations.of(context)!.sectionFarmOperations),
              const SizedBox(height: 12),
              if (_can('farm_attendance'))
                _tile(
                  icon: Icons.groups_outlined,
                  label: AppLocalizations.of(context)!
                      .moduleLabel('farm_attendance', 'Farm Attendance'),
                  sub: AppLocalizations.of(context)!.moduleDescription(
                      'farm_attendance',
                      'Mark daily attendance & wages for farm field workers'),
                  iconBg: const Color(0xFFE8F5E2),
                  iconColor: idaGreen,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AttendanceScreen())),
                ),
              if (_can('farm_tractor'))
                _tile(
                  icon: Icons.agriculture,
                  label: 'Farm Tractor',
                  sub:
                      'Assign tractor field work and log hours, diesel and billing',
                  iconBg: const Color(0xFFFEF3DC),
                  iconColor: Colors.orange.shade800,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const FarmTractorWorkScreen())),
                ),
              if (_can('agri')) ...[
                _tile(
                  icon: Icons.wb_sunny_outlined,
                  label: 'Weather',
                  sub: 'Current conditions and 7-day forecast, per farm',
                  iconBg: const Color(0xFFFEF3DC),
                  iconColor: Colors.orange.shade800,
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const WeatherScreen())),
                ),
                _tile(
                  icon: Icons.eco_outlined,
                  label: AppLocalizations.of(context)!.agriCropMastersTitle,
                  sub: 'Manage crops and their varieties',
                  iconBg: const Color(0xFFE8F5E2),
                  iconColor: idaGreen,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const CropMastersScreen())),
                ),
                _tile(
                  icon: Icons.spa_outlined,
                  label: AppLocalizations.of(context)!.agriAgronomySetupTitle,
                  sub: 'Orchard blocks and agronomy schedule templates',
                  iconBg: const Color(0xFFE8F5E2),
                  iconColor: idaGreen,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AgronomySetupScreen())),
                ),
                _tile(
                  icon: Icons.calendar_month_outlined,
                  label: AppLocalizations.of(context)!.agriCyclesTitle,
                  sub:
                      'Sow, log operations, and track the planned-vs-actual calendar',
                  iconBg: const Color(0xFFE8F5E2),
                  iconColor: idaGreen,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const CropCyclesScreen())),
                ),
                _tile(
                  icon: Icons.insert_chart_outlined,
                  label: AppLocalizations.of(context)!.agriReportsTitle,
                  sub:
                      'Planning view of what\'s due, plus cost & yield reports',
                  iconBg: const Color(0xFFE8F5E2),
                  iconColor: idaGreen,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const CropReportsScreen())),
                ),
              ],
            ],
          ],

          // ══════════════════════════════════════════════════════════
          // CROSS-CUTTING — shown regardless of which sector is active
          // ══════════════════════════════════════════════════════════
          if (_can('passwords')) ...[
            const SizedBox(height: 20),
            _sectionHeader(AppLocalizations.of(context)!.sectionAdministrative),
            const SizedBox(height: 12),
            _tile(
              icon: Icons.vpn_key_outlined,
              label: 'Password Manager',
              sub: 'Secure credentials store — OTP required for non-admins',
              iconBg: const Color(0xFFEDE7F6),
              iconColor: const Color(0xFF4A148C),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const PasswordScreen())),
            ),
          ],

          // ── Administration (admin only) ────────────────────────────
          if (_isAdmin) ...[
            const SizedBox(height: 20),
            _sectionHeader(AppLocalizations.of(context)!.sectionAdministration),
            const SizedBox(height: 12),
            _tile(
              icon: Icons.fact_check_outlined,
              label: 'Review Submissions',
              sub: 'Approve, reject or return records to staff',
              iconBg: const Color(0xFFE8F0FE),
              iconColor: const Color(0xFF1A73E8),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AdminReviewScreen())),
            ),
            _tile(
              icon: Icons.local_shipping_outlined,
              label: 'Dispatch Review',
              sub: 'Approve each section of an outward dispatch entry',
              iconBg: const Color(0xFFE8F0FE),
              iconColor: const Color(0xFF1A73E8),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const OutwardRegisterReviewListScreen())),
            ),
            _tile(
              icon: Icons.lock_clock_outlined,
              label: 'OTP Approvals',
              sub: 'Approve password access requests & share OTP with users',
              iconBg: const Color(0xFFEDE7F6),
              iconColor: const Color(0xFF4A148C),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const OtpApprovalsScreen())),
            ),
            _tile(
              icon: Icons.manage_accounts_outlined,
              label: 'Manage Users',
              sub: 'Create accounts and assign module access',
              onTap: () => Navigator.pushNamed(context, '/admin/users'),
            ),
            _tile(
              icon: Icons.business_outlined,
              label: 'Manage Parties',
              sub: 'Buyer list used in the Outward Sales Register',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const PartiesScreen())),
            ),
            _tile(
              icon: Icons.flag_outlined,
              label: 'Manage Destinations',
              sub: 'Destination list used in the Outward Sales Register',
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const DestinationsScreen())),
            ),
            _tile(
              icon: Icons.agriculture_outlined,
              label: 'Farm Attendance Setup',
              sub: 'Manage farms, work types & farm worker master list',
              iconBg: const Color(0xFFE8F5E2),
              iconColor: idaGreen,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const FarmMastersScreen())),
            ),
          ],

          if (!_isAdmin && _permissions.isEmpty) ...[
            const SizedBox(height: 40),
            Center(
              child: Column(children: [
                Icon(Icons.lock_outline, size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                const Text('No modules assigned',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black54)),
                const SizedBox(height: 6),
                const Text('Contact your admin to get access to modules.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                    textAlign: TextAlign.center),
              ]),
            ),
          ],

          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  final _scrollCtrl = ScrollController();
  void _scrollToBanner() {
    _scrollCtrl.animateTo(0,
        duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
  }

  void _soon(String n) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$n coming soon'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ));

  Widget _sectionHeader(String t) => Text(t,
      style: const TextStyle(
          fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A)));

  Widget _statCard(String value, String label, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE0E7D8)),
          ),
          child: Column(children: [
            Text(value,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
                textAlign: TextAlign.center),
          ]),
        ),
      );

  Widget _tile({
    required IconData icon,
    required String label,
    required String sub,
    required VoidCallback onTap,
    Color iconBg = const Color(0xFFE8F5E2),
    Color iconColor = idaGreen,
    bool hasPending = false,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  hasPending ? amber.withOpacity(0.8) : const Color(0xFFE0E7D8),
              width: hasPending ? 1.5 : 1,
            ),
          ),
          child: Row(children: [
            Stack(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: hasPending ? amber.withOpacity(0.15) : iconBg,
                    borderRadius: BorderRadius.circular(10)),
                child:
                    Icon(icon, color: hasPending ? amber : iconColor, size: 20),
              ),
              if (hasPending)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                        color: Colors.red, shape: BoxShape.circle),
                  ),
                ),
            ]),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(label,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                      if (hasPending)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text('Action needed',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFFF57C00),
                                  fontWeight: FontWeight.w600)),
                        ),
                    ]),
                    const SizedBox(height: 2),
                    Text(sub,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF6B7280))),
                  ]),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFFB0BEC5), size: 20),
          ]),
        ),
      );
}

// ── Returned records pulsing banner ──────────────────────────────────────────

class _ReturnedBanner extends StatelessWidget {
  final List<ReturnedRecord> records;
  final Animation<double> pulseAnim;
  final void Function(ReturnedRecord) onFix;
  final void Function(ReturnedRecord) onDismiss;

  const _ReturnedBanner({
    required this.records,
    required this.pulseAnim,
    required this.onFix,
    required this.onDismiss,
  });

  static const amber = Color(0xFFF5A623);
  static const idaDark = Color(0xFF1E4012);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseAnim,
      builder: (_, __) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8EC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: amber.withOpacity(pulseAnim.value),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: amber.withOpacity(pulseAnim.value * 0.3),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: amber.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.assignment_return_rounded,
                    color: Colors.orange.shade800, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Builder(builder: (ctx) {
                  final returnedCount =
                      records.where((r) => r.status == 'returned').length;
                  final rejectedCount =
                      records.where((r) => r.status == 'rejected').length;
                  String title;
                  String sub;
                  if (returnedCount > 0 && rejectedCount > 0) {
                    title = '$returnedCount returned · $rejectedCount rejected';
                    sub = 'Some records need correction; others were rejected';
                  } else if (returnedCount > 0) {
                    title =
                        '$returnedCount record${returnedCount > 1 ? "s" : ""} returned for correction';
                    sub = 'Correct and resubmit for admin approval';
                  } else {
                    title =
                        '$rejectedCount record${rejectedCount > 1 ? "s" : ""} rejected';
                    sub = 'Admin has rejected these entries';
                  }
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.orange.shade900)),
                        Text(sub,
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF6B7280))),
                      ]);
                }),
              ),
            ]),
          ),

          const Divider(
              height: 1, indent: 16, endIndent: 16, color: Color(0xFFFFE0A0)),

          // Individual records
          ...records.map((r) => _RecordRow(
                record: r,
                onFix: () => onFix(r),
                onDismiss: () => onDismiss(r),
              )),
        ]),
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  final ReturnedRecord record;
  final VoidCallback onFix;
  final VoidCallback onDismiss;

  const _RecordRow({
    required this.record,
    required this.onFix,
    required this.onDismiss,
  });

  static const amber = Color(0xFFF5A623);
  static const idaGreen = Color(0xFF3B7A28);

  IconData get _icon {
    switch (record.module) {
      case 'electricity':
        return Icons.electric_bolt;
      case 'tractor':
        return Icons.agriculture;
      case 'labour':
        return Icons.people_outline;
      case 'factory':
        return Icons.factory_outlined;
      case 'machine':
        return Icons.precision_manufacturing_outlined;
      default:
        return Icons.assignment_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFFE0A0)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(_icon, size: 15, color: amber),
            const SizedBox(width: 6),
            Expanded(
              child: Text(record.moduleLabel,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            if (record.date.isNotEmpty)
              Text(record.date,
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ]),
          if (record.adminNote.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(8),
              ),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.info_outline,
                    size: 13, color: Color(0xFFF57C00)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    record.adminNote,
                    style:
                        const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  ),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 10),
          Row(children: [
            // Rejected records: just show a dismiss button (no fix possible)
            if (record.status == 'rejected') ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text('Rejected',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.red.shade700)),
              ),
              const Spacer(),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onDismiss,
                child: const Text('Dismiss', style: TextStyle(fontSize: 12)),
              ),
            ] else ...[
              // Returned records: show Later + Fix & Resubmit
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onDismiss,
                child: const Text('Later', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.edit_outlined,
                      size: 14, color: Colors.white),
                  label: const Text('Fix & Resubmit',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: idaGreen,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    elevation: 0,
                  ),
                  onPressed: onFix,
                ),
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}
