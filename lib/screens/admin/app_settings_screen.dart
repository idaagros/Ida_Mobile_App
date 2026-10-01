// lib/screens/admin/app_settings_screen.dart
//
// App settings (Oct 2026 redesign, group F), the same as the website's
// Administration › App settings, plus this phone's server address:
//  - Missing reading reminders: when the people who enter readings are
//    reminded in Needs attention (step 1), and when admins are told too
//    (step 2, must be later).
//  - Face login: how close a face must be to the saved photo (0.6
//    stricter … 1.6 more forgiving; it started at 1.1).
//  - Server address: this phone only (needed before signing in).
// Web counterpart: src/pages/AppSettings.jsx.
// API: GET/PUT /reading-reminder-settings, GET/PATCH /settings/face_login_threshold

import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import '../../widgets/server_address_dialog.dart';
import 'admin_common.dart';

const double kFaceDefault = 1.1;
const double kFaceMin = 0.6;
const double kFaceMax = 1.6;

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});
  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  bool _loading = true;
  String? _error;

  TimeOfDay? _user;
  TimeOfDay? _admin;
  TimeOfDay? _userSaved;
  TimeOfDay? _adminSaved;
  bool _savingTimes = false;

  double? _face;
  double? _faceSaved;
  bool _savingFace = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  TimeOfDay? _parse(dynamic v) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch('${v ?? ''}');
    if (m == null) return null;
    return TimeOfDay(hour: int.parse(m.group(1)!), minute: int.parse(m.group(2)!));
  }

  String _api(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  int _mins(TimeOfDay t) => t.hour * 60 + t.minute;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final errors = <String>[];
    try {
      final r = await AdminApi.get('/reading-reminder-settings');
      if (r is Map) {
        _user = _userSaved = _parse(r['user_reminder_time']);
        _admin = _adminSaved = _parse(r['admin_reminder_time']);
      }
    } catch (e) {
      errors.add('Reminder times: ${errText(e)}');
    }
    try {
      final r = await AdminApi.get('/settings/face_login_threshold');
      final v = r is Map ? double.tryParse('${r['setting_value']}') : null;
      _face = _faceSaved = v ?? kFaceDefault;
    } catch (e) {
      if (e is AdminApiError && e.status == 404) {
        _face = _faceSaved = kFaceDefault;
      } else {
        errors.add('Face login: ${errText(e)}');
      }
    }
    if (!mounted) return;
    setState(() {
      _error = errors.isEmpty ? null : errors.join('\n');
      _loading = false;
    });
  }

  Future<void> _pick(bool first) async {
    final now = (first ? _user : _admin) ?? const TimeOfDay(hour: 10, minute: 0);
    final t = await showTimePicker(context: context, initialTime: now);
    if (t == null) return;
    setState(() {
      if (first) {
        _user = t;
      } else {
        _admin = t;
      }
    });
  }

  String? get _timeProblem {
    if (_user == null || _admin == null) return 'Pick both times.';
    if (_mins(_admin!) <= _mins(_user!)) return 'Step 2 must be later than step 1.';
    return null;
  }

  bool get _timesChanged => _user != _userSaved || _admin != _adminSaved;

  Future<void> _saveTimes() async {
    if (_timeProblem != null) return;
    setState(() => _savingTimes = true);
    try {
      await AdminApi.put('/reading-reminder-settings', {'user_reminder_time': _api(_user!), 'admin_reminder_time': _api(_admin!)});
      _userSaved = _user;
      _adminSaved = _admin;
      if (mounted) showOk(context, 'Reminder times saved');
    } catch (e) {
      if (mounted) showErr(context, errText(e));
    } finally {
      if (mounted) setState(() => _savingTimes = false);
    }
  }

  Future<void> _saveFace(double v) async {
    setState(() => _savingFace = true);
    try {
      await AdminApi.patch('/settings/face_login_threshold', {'value': v.toStringAsFixed(2)});
      _face = _faceSaved = v;
      if (mounted) showOk(context, 'Face login saved');
    } catch (e) {
      if (mounted) showErr(context, errText(e));
    } finally {
      if (mounted) setState(() => _savingFace = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: aBg,
      appBar: adminBar('App settings'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
                AErrorBox(_error),
                if (_error != null) const SizedBox(height: 10),
                _remindersCard(),
                const SizedBox(height: 14),
                _faceCard(),
                const SizedBox(height: 14),
                _serverCard(),
              ]),
            ),
    );
  }

  Widget _title(IconData icon, String text) => Row(children: [
        Icon(icon, size: 22, color: aText),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: aText))),
      ]);

  Widget _remindersCard() {
    Widget pickBox(String label, String help, TimeOfDay? t, bool first) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF3A4833))),
          const SizedBox(height: 6),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _pick(first),
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFD5DCCD))),
              child: Row(children: [
                Text(t == null ? 'Pick a time' : t.format(context), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const Spacer(),
                const Icon(Icons.schedule, color: aMuted),
              ]),
            ),
          ),
          const SizedBox(height: 4),
          Text(help, style: const TextStyle(fontSize: 12.5, color: aMuted)),
        ]);
    final problem = _timeProblem;
    return ACard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title(Icons.alarm, 'Missing reading reminders'),
        const SizedBox(height: 6),
        const Text('If today’s electricity, tractor, machine or power factor reading is not in yet, Needs attention reminds people in two steps.',
            style: TextStyle(fontSize: 13.5, color: aMuted)),
        const SizedBox(height: 12),
        if (_user != null && _admin != null) _timeline(),
        const SizedBox(height: 12),
        pickBox('1. Remind the people who enter readings at', 'Everyone who can add that reading.', _user, true),
        const SizedBox(height: 12),
        pickBox('2. Tell admins too at', 'Must be later than step 1.', _admin, false),
        if (problem != null && _timesChanged) ...[const SizedBox(height: 10), AErrorBox(problem)],
        const SizedBox(height: 12),
        FilledButton(
          style: aPrimary(),
          onPressed: _savingTimes || !_timesChanged || problem != null ? null : _saveTimes,
          child: Text(_savingTimes ? 'Saving…' : 'Save times'),
        ),
      ]),
    );
  }

  // A day bar: grey until step 1, amber until step 2, red after.
  Widget _timeline() {
    final a = _mins(_user!) / 1440.0;
    final b = (_mins(_admin!) / 1440.0).clamp(a, 1.0).toDouble();
    return LayoutBuilder(builder: (ctx, c) {
      final w = c.maxWidth;
      return SizedBox(
        height: 52,
        child: Stack(children: [
          Positioned(
            left: 0,
            right: 0,
            top: 20,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Row(children: [
                Container(width: w * a, height: 14, color: aSoftGrey),
                Container(width: w * (b - a), height: 14, color: aSoftAmber),
                Expanded(child: Container(height: 14, color: aSoftRed)),
              ]),
            ),
          ),
          Positioned(left: (w * a - 30).clamp(0.0, w - 60).toDouble(), top: 0, child: SizedBox(width: 60, child: Text(_user!.format(context), textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: aAmber)))),
          Positioned(left: (w * b - 30).clamp(0.0, w - 60).toDouble(), top: 36, child: SizedBox(width: 60, child: Text(_admin!.format(context), textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: aRed)))),
        ]),
      );
    });
  }

  Widget _faceCard() {
    final v = _face ?? kFaceDefault;
    final changed = _faceSaved != null && (v - _faceSaved!).abs() > 0.001;
    return ACard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title(Icons.face_outlined, 'Face login'),
        const SizedBox(height: 6),
        const Text('How close a face must be to the person’s saved photo before the phone lets them in.', style: TextStyle(fontSize: 13.5, color: aMuted)),
        const SizedBox(height: 8),
        Slider(
          value: v.clamp(kFaceMin, kFaceMax).toDouble(),
          min: kFaceMin,
          max: kFaceMax,
          divisions: 20,
          label: v.toStringAsFixed(2),
          activeColor: aGreen,
          onChanged: _faceSaved == null ? null : (x) => setState(() => _face = double.parse(x.toStringAsFixed(2))),
        ),
        Row(children: [
          const Text('Stricter', style: TextStyle(fontSize: 12.5, color: aMuted)),
          const Spacer(),
          Text(v.toStringAsFixed(2), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: aText)),
          const Spacer(),
          const Text('More forgiving', style: TextStyle(fontSize: 12.5, color: aMuted)),
        ]),
        const SizedBox(height: 10),
        const ANote('Stricter = a wrong face is less likely to get in, but real people may need two or three tries. '
            'More forgiving = fewer failed logins, slightly more risk. If real logins keep failing, move it right a little. It started at 1.1.'),
        const SizedBox(height: 12),
        Row(children: [
          if ((v - kFaceDefault).abs() > 0.001)
            Expanded(
              child: OutlinedButton(style: aSecondary(height: 48), onPressed: _savingFace ? null : () => _saveFace(kFaceDefault), child: const Text('Back to 1.1')),
            ),
          if ((v - kFaceDefault).abs() > 0.001) const SizedBox(width: 10),
          Expanded(
            child: FilledButton(style: aPrimary(), onPressed: _savingFace || !changed ? null : () => _saveFace(v), child: Text(_savingFace ? 'Saving…' : 'Save')),
          ),
        ]),
      ]),
    );
  }

  // Which server this phone talks to. Used when moving hosting (e.g. to
  // Cloudflare): change it here on phones already in use, instead of
  // waiting for a new app build. Only saved if the new address answers.
  Widget _serverCard() => ACard(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _title(Icons.dns_outlined, 'Server address (this phone)'),
          const SizedBox(height: 6),
          const Text('Where this phone connects. Change it only when the server moves to a new web address.', style: TextStyle(fontSize: 13.5, color: aMuted)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(AppConfig.displayHost, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                Text(AppConfig.isCustomHost ? 'Changed on this phone' : 'Built-in address',
                    style: TextStyle(fontSize: 12, color: AppConfig.isCustomHost ? const Color(0xFFB45309) : aMuted)),
              ]),
            ),
            OutlinedButton(
              style: aSecondary(),
              onPressed: () async {
                final changed = await showServerAddressDialog(context);
                if (changed && mounted) setState(() {});
              },
              child: const Text('Change'),
            ),
          ]),
        ]),
      );
}
