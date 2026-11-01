// lib/screens/accounts/daily_jv_screen.dart
//
// Daily expenses -> ONE Journal voucher per day in TallyPrime.
//   the expense ledger(s) you say  Dr   /   who paid  Cr: the credit ledger you chose (e.g. Harsh Udrat), or another one said for
//   that item ("Omprakash ne diya"); one voucher can have several payers. Every item has its own narration (what you said besides
//   the ledger and amount, with the amount: "Fan 350"). Comments are kept ONLY at ledger level (under each ledger line in
//   Tally); there is no voucher-level narration.
// Say it ("Badi Akhar majuri pandrah sau", "diesel 2000"), check the card, tap Add. Keep adding
// through the day: the day's voucher in Tally is updated each time.
//  - The company and the credit ledger you choose stay until you change them.
//  - Tally closed: the entry waits on the server and goes in by itself when Tally is open.
//  - No signal on the phone: an entry you completed (ledger + amount) is kept on this phone and sent by
//    itself when there is signal (the app's normal send-later queue). What you only SAID (not yet read by the
//    server) is kept as words and read when there is signal; you check it before it is added.
//  - Who: admins, and users ticked for "Daily expenses" in Users & permissions (View = see the day, Add = enter, Delete = remove an entry).
// API: /daily-jv (routes/dailyJv.js).  Web counterpart: src/pages/DailyExpenses.jsx.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../models/user_model.dart';
import '../../services/api_client.dart';
import '../../widgets/tally_company_badge.dart';
import '../../services/offline_queue.dart';
import '../../widgets/offline_status_bar.dart';
import '../raw_material/rm_common.dart';

class _Card {
  String heard;
  String? ledger;
  String? payer; // who paid (credited)
  bool sure;
  List<String> choices;
  bool manual = false;
  DateTime date;
  List<Map<String, dynamic>> warns;
  // possible duplicates within 2 days (this app + Tally), from POST /daily-jv/check; dupSig = what was asked
  Map<String, dynamic>? dups;
  String dupSig = '';
  final TextEditingController amount;
  final TextEditingController note = TextEditingController();
  final TextEditingController alias = TextEditingController();
  _Card({required this.heard, this.ledger, this.payer, required this.sure, required this.choices, required this.date, required this.warns, String amountText = ''})
      : amount = TextEditingController(text: amountText);
  void dispose() {
    amount.dispose();
    note.dispose();
    alias.dispose();
  }
}

class DailyJvScreen extends StatefulWidget {
  const DailyJvScreen({super.key});
  @override
  State<DailyJvScreen> createState() => _DailyJvScreenState();
}

class _DailyJvScreenState extends State<DailyJvScreen> {
  static const _kLedgers = 'dj_cache_ledgers';
  static const _kSettings = 'dj_cache_settings';
  static const _kDrafts = 'dj_drafts';
  static const _kWaiting = 'dj_waiting';

  DateTime date = DateTime.now();
  Map<String, dynamic> settings = {};
  List<String> ledgers = [];
  List<Map<String, dynamic>> vouchers = [];
  List<Map<String, dynamic>> recent = [];
  List<Map<String, dynamic>> drafts = []; // words said without signal: {id, text}
  List<Map<String, dynamic>> waiting = []; // completed entries kept by the send-later queue: {ledger, amount, date}
  final List<_Card> cards = [];
  final typeCtrl = TextEditingController();
  bool loading = true;
  bool busy = false;
  bool offline = false;
  bool forbidden = false;
  final Map<_Card, Timer> _dupTimers = {};
  // From Users & permissions ("Daily expenses"): View = see the day, Add = enter / fix, Delete = remove an entry.
  bool mayAdd = false;
  bool mayDelete = false;
  String? error;
  String? notice;

  @override
  void initState() {
    super.initState();
    Offline.pendingCount.addListener(_queueChanged);
    _init();
  }

  @override
  void dispose() {
    Offline.pendingCount.removeListener(_queueChanged);
    typeCtrl.dispose();
    for (final t in _dupTimers.values) {
      t.cancel();
    }
    for (final c in cards) {
      c.dispose();
    }
    super.dispose();
  }

  // When the send-later queue empties, what was waiting has reached the server.
  void _queueChanged() {
    if (Offline.pendingCount.value == 0 && waiting.isNotEmpty && mounted) {
      waiting = [];
      _saveWaiting();
      _load();
    }
  }

  // ── remembered on the phone ────────────────────────────────────────
  Future<void> _readPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      drafts = _list(p.getString(_kDrafts));
      waiting = _list(p.getString(_kWaiting));
      final admin = p.getBool('is_admin') ?? (p.getString('role') == 'admin');
      final perms = parsePermissions(jsonDecode(p.getString('permissions') ?? '[]'));
      mayAdd = admin || hasAddAccess(perms, 'daily_expenses');
      mayDelete = admin || hasDeleteAccess(perms, 'daily_expenses');
    } catch (_) {}
  }

  List<Map<String, dynamic>> _list(String? s) {
    if (s == null || s.isEmpty) return [];
    try {
      return (jsonDecode(s) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveDrafts() async {
    try {
      (await SharedPreferences.getInstance()).setString(_kDrafts, jsonEncode(drafts));
    } catch (_) {}
  }

  Future<void> _saveWaiting() async {
    try {
      (await SharedPreferences.getInstance()).setString(_kWaiting, jsonEncode(waiting));
    } catch (_) {}
  }

  // ── loading ────────────────────────────────────────────────────────
  Future<void> _init() async {
    await _readPrefs();
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final st = Map<String, dynamic>.from(await Api.json('GET', '/daily-jv/state', query: {'date': isoDay(date)}) as Map);
      settings = Map<String, dynamic>.from((st['settings'] as Map?) ?? {});
      vouchers = ((st['vouchers'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      recent = ((st['recent'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      offline = false;
      final p = await SharedPreferences.getInstance();
      await p.setString(_kSettings, jsonEncode(settings));
      try {
        final l = Map<String, dynamic>.from(await Api.json('GET', '/daily-jv/ledgers') as Map);
        ledgers = ((l['list'] as List?) ?? const []).map((e) => (e as Map)['name'].toString()).toList();
        await p.setString(_kLedgers, jsonEncode(ledgers));
      } catch (_) {
        _ledgersFromCache(p);
      }
      if (Offline.pendingCount.value == 0 && waiting.isNotEmpty) {
        waiting = [];
        _saveWaiting();
      }
    } on ApiException catch (e) {
      if (e.statusCode == 403) {
        forbidden = true;
      } else if (e.statusCode == null) {
        offline = true;
        final p = await SharedPreferences.getInstance();
        try {
          settings = Map<String, dynamic>.from(jsonDecode(p.getString(_kSettings) ?? '{}') as Map);
        } catch (_) {}
        _ledgersFromCache(p);
        vouchers = [];
      } else {
        error = e.message;
      }
    } catch (e) {
      error = e.toString();
    }
    if (mounted) setState(() => loading = false);
  }

  void _ledgersFromCache(SharedPreferences p) {
    try {
      ledgers = (jsonDecode(p.getString(_kLedgers) ?? '[]') as List).map((e) => e.toString()).toList();
    } catch (_) {}
  }

  String get company => (settings['company'] ?? '').toString();
  String get credit => (settings['credit_ledger'] ?? '').toString();
  // who can be picked as payer with one tap: the saved credit ledger and the ones used before
  List<String> get payerChoices {
    final out = <String>[];
    if (credit.isNotEmpty) out.add(credit);
    for (final p in ((settings['payers'] as List?) ?? const [])) {
      final n = p.toString();
      if (n.isNotEmpty && !out.contains(n)) out.add(n);
    }
    return out;
  }

  // the item's narration as it will be written (same rule as the server)
  String _itemText(String? ledger, String note, String amountText) {
    var t = note.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty) t = (ledger ?? '').trim();
    final a = double.tryParse(amountText.replaceAll(',', '').trim()) ?? 0;
    final tail = RegExp(r'(\d+(?:\.\d+)?)\s*(?:/-)?$').firstMatch(t);
    if (a <= 0 || t.isEmpty) return t;
    if (tail != null && ((double.tryParse(tail.group(1)!) ?? -1) - a).abs() < 0.005) return t;
    return '$t ${a == a.roundToDouble() ? a.round().toString() : a.toStringAsFixed(2)}';
  }

  // ── choosing company / credit ledger ───────────────────────────────
  Future<void> _saveSettings(Map<String, dynamic> patch) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await Api.json('PUT', '/daily-jv/settings', body: patch);
      for (final c in cards) {
        c.dispose();
      }
      cards.clear();
      await _load();
    } on ApiException catch (e) {
      error = e.statusCode == null ? 'You need signal to change this.' : e.message;
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _pickCompany() async {
    try {
      final r = Map<String, dynamic>.from(await Api.json('GET', '/daily-jv/companies') as Map);
      final list = ((r['list'] as List?) ?? const []).map((e) => e.toString()).toList();
      if (!mounted) return;
      final picked = await showDialog<String>(
        context: context,
        builder: (c) => SimpleDialog(
          title: const Text('Company in Tally'),
          children: [
            for (final n in list) SimpleDialogOption(onPressed: () => Navigator.pop(c, n), child: Text(n, style: TextStyle(fontWeight: n == company ? FontWeight.w800 : FontWeight.w400))),
          ],
        ),
      );
      if (picked != null && picked != company) await _saveSettings({'company': picked});
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.statusCode == null ? 'You need signal to change this.' : e.message);
    }
  }

  Future<void> _pickCredit() async {
    final suggested = ledgers.where((n) => RegExp('harsh', caseSensitive: false).hasMatch(n) && RegExp('udrat', caseSensitive: false).hasMatch(n)).toList();
    final picked = await _pickLedger('Credit ledger', first: suggested);
    if (picked != null && picked != credit) await _saveSettings({'credit_ledger': picked});
  }

  Future<String?> _pickLedger(String title, {List<String> first = const []}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _LedgerSheet(title: title, all: ledgers, first: first),
    );
  }

  // ── what was said ──────────────────────────────────────────────────
  Future<void> _speak() async {
    final said = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _SpeakSheet(),
    );
    if (said == null || said.trim().isEmpty) return;
    await _readText(text: said.trim());
  }

  Future<void> _readText({String? draftId, String? text}) async {
    final t = (text ?? typeCtrl.text).trim();
    if (t.isEmpty) return;
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      final r = Map<String, dynamic>.from(await Api.json('POST', '/daily-jv/parse', body: {'transcript': t}) as Map);
      final list = ((r['entries'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      for (final e in list) {
        final lg = e['ledger'] is Map ? Map<String, dynamic>.from(e['ledger'] as Map) : <String, dynamic>{};
        final a = e['amount'];
        final py = e['payer'] is Map ? (e['payer'] as Map)['ledger']?.toString() : null;
        final c = _Card(
          heard: (e['heard'] ?? t).toString(),
          ledger: lg['ledger']?.toString(),
          payer: (py != null && py.isNotEmpty) ? py : (credit.isEmpty ? null : credit),
          sure: lg['sure'] == true,
          choices: ((lg['candidates'] as List?) ?? const []).map((x) => x.toString()).toList(),
          date: DateTime.tryParse((e['date'] ?? '').toString()) ?? DateTime.now(),
          warns: ((e['warnings'] as List?) ?? const []).map((x) => Map<String, dynamic>.from(x as Map)).toList(),
          amountText: a == null ? '' : (toD(a) == toD(a).roundToDouble() ? toD(a).round().toString() : toD(a).toStringAsFixed(2)),
        );
        c.note.text = (e['note'] ?? '').toString();
        cards.add(c);
      }
      typeCtrl.clear();
      if (draftId != null) {
        drafts.removeWhere((d) => d['id'] == draftId);
        _saveDrafts();
      }
    } on ApiException catch (e) {
      if (e.statusCode == null) {
        // no signal: keep the words, read them later
        if (draftId == null) {
          drafts.add({'id': DateTime.now().microsecondsSinceEpoch.toString(), 'text': t});
          _saveDrafts();
          typeCtrl.clear();
          notice = 'No signal. What you said is saved on this phone. Read it when there is signal (see "Said without signal" below).';
        } else {
          error = 'Still no signal.';
        }
      } else {
        error = e.message;
      }
    } catch (e) {
      error = Api.errorText(e);
    }
    if (mounted) setState(() => busy = false);
  }

  // ── add / remove ───────────────────────────────────────────────────
  // Possible duplicates: the same ledger (debited or credited) within 2 days either side, in this app and in Tally.
  Future<Map<String, dynamic>?> _fetchDup(_Card c, double amount) async {
    try {
      final r = await Api.json('POST', '/daily-jv/check',
          body: {'debit_ledger': c.ledger, if (c.payer != null && c.payer!.isNotEmpty) 'credit_ledger': c.payer, 'amount': amount, 'date': isoDay(c.date)},
          timeout: const Duration(seconds: 25));
      return r is Map ? Map<String, dynamic>.from(r) : null;
    } catch (_) {
      return null; // the check is a help, never a blocker
    }
  }

  // Called while a card is drawn: asks again (after a short pause) when ledger, payer, amount or date changed.
  void _watchDup(_Card c) {
    final amount = double.tryParse(c.amount.text.replaceAll(',', '').trim()) ?? 0;
    final sig = '${c.ledger}|${c.payer}|$amount|${isoDay(c.date)}';
    if (sig == c.dupSig) return;
    c.dupSig = sig;
    _dupTimers[c]?.cancel();
    if (c.ledger == null || amount <= 0 || offline) {
      c.dups = null;
      return;
    }
    _dupTimers[c] = Timer(const Duration(milliseconds: 600), () async {
      final r = await _fetchDup(c, amount);
      if (!mounted || c.dupSig != sig) return;
      setState(() => c.dups = r);
    });
  }

  Widget _dupNote(Map<String, dynamic>? d) {
    if (d == null) return const SizedBox.shrink();
    final strong = ((d['strong'] as List?) ?? const []).map((e) => (e as Map)['text'].toString()).toList();
    final soft = ((d['soft'] as List?) ?? const []).map((e) => (e as Map)['text'].toString()).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (strong.isNotEmpty)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFFDF2F1), border: Border.all(color: const Color(0xFFEFB9B3)), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Possible duplicate: the same ledger and amount, within 2 days.', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: Color(0xFF9E2419))),
            for (final t in strong) Text('• $t', style: const TextStyle(fontSize: 12.5, color: Color(0xFF9E2419))),
            const Text('You will be asked before it is added again.', style: TextStyle(fontSize: 12, color: Color(0xFF9E2419))),
          ]),
        ),
      if (soft.isNotEmpty)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFF6F8F3), border: Border.all(color: const Color(0xFFE0E7D8)), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Same ledger, other amounts, within 2 days:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            for (final t in soft) Text('• $t', style: const TextStyle(fontSize: 12)),
          ]),
        ),
      if (d['tally_checked'] == false)
        const Padding(padding: EdgeInsets.only(top: 6), child: Text('Tally is not answering, so only entries made in this app were checked.', style: TextStyle(fontSize: 12, color: Color(0xFF6B4A00)))),
    ]);
  }

  Future<void> _add(_Card c) async {
    final amount = double.tryParse(c.amount.text.replaceAll(',', '').trim()) ?? 0;
    if (c.ledger == null || amount <= 0) return;
    // ask again right now: someone may have entered it a moment ago
    if (!offline) {
      final dup = await _fetchDup(c, amount) ?? c.dups;
      final same = ((dup?['strong'] as List?) ?? const []).map((e) => (e as Map)['text'].toString()).toList();
      if (same.isNotEmpty) {
        if (!mounted) return;
        final again = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Possible duplicate'),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('The same ledger and amount is already there, within 2 days:'),
              const SizedBox(height: 8),
              for (final t in same) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $t', style: const TextStyle(fontSize: 13))),
              const SizedBox(height: 6),
              const Text('Do you still want to enter it again as a duplicate?', style: TextStyle(fontWeight: FontWeight.w700)),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No, go back')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes, enter again')),
            ],
          ),
        );
        if (again != true) return;
      }
    }
    final strong = c.warns.where((w) => w['level'] == 'warn' && !RegExp('ledger|amount', caseSensitive: false).hasMatch(w['text'].toString())).toList();
    if (strong.isNotEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Please check'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final w in strong) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('• ${w['text']}')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Go back')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add anyway')),
          ],
        ),
      );
      if (go != true) return;
    }
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    final body = {
      'debit_ledger': c.ledger,
      if (c.payer != null && c.payer!.isNotEmpty) 'credit_ledger': c.payer,
      'amount': amount,
      'date': isoDay(c.date),
      'note': c.note.text.trim(),
      'spoken': c.heard,
      if (c.alias.text.trim().isNotEmpty) 'alias': c.alias.text.trim(),
    };
    try {
      final res = await Api.send(
        'POST',
        '/daily-jv/entries',
        body: body,
        queueLabel: 'Expense ${c.ledger} ${inr(amount)}',
        queueKey: 'dj-${DateTime.now().microsecondsSinceEpoch}',
      );
      if (Api.wasQueued(res)) {
        waiting.add({'ledger': c.ledger, 'amount': amount, 'date': isoDay(c.date)});
        _saveWaiting();
        notice = 'No signal. Saved on this phone; it will be sent by itself when there is signal.';
        _dropCard(c);
      } else if (res.statusCode >= 200 && res.statusCode < 300) {
        final d = Api.decode(res);
        final v = (d is Map && d['vouchers'] is List && (d['vouchers'] as List).isNotEmpty) ? Map<String, dynamic>.from((d['vouchers'] as List).first as Map) : <String, dynamic>{};
        notice = v['state'] == 'posted'
            ? 'Added. The day\'s voucher in Tally now has ${inr(v['total'])}.'
            : v['state'] == 'pending'
                ? 'Added and saved. Tally is not answering; it will go in by itself when Tally is open.'
                : 'Added, but Tally said: ${v['message'] ?? v['state']}';
        _dropCard(c);
        if (isoDay(c.date) != isoDay(date)) date = c.date;
        await _load();
      } else {
        error = Api.responseError(res);
      }
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = Api.errorText(e);
    }
    if (mounted) setState(() => busy = false);
  }

  void _dropCard(_Card c) {
    _dupTimers.remove(c)?.cancel();
    cards.remove(c);
    c.dispose();
  }

  Future<void> _remove(Map<String, dynamic> l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this entry?'),
        content: Text('${l['debit_ledger']} ${inr(l['amount'])}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => busy = true);
    try {
      await Api.json('DELETE', '/daily-jv/entries/${l['id']}');
      await _load();
    } on ApiException catch (e) {
      error = e.statusCode == null ? 'You need signal to remove an entry.' : e.message;
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _act(Map<String, dynamic> v, String what) async {
    if (what == 'overwrite') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Overwrite Tally?'),
          content: const Text('Make the voucher in Tally match the entries shown here. Whatever was changed in Tally will be replaced.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Overwrite')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => busy = true);
    try {
      await Api.json('POST', '/daily-jv/vouchers/${v['id']}/$what', body: {});
      await _load();
    } on ApiException catch (e) {
      error = e.message;
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _pickDate() async {
    final p = await showDatePicker(context: context, initialDate: date, firstDate: DateTime.now().subtract(const Duration(days: 400)), lastDate: DateTime.now());
    if (p == null) return;
    date = p;
    await _load();
  }

  // ── screen ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: rmBg,
      appBar: AppBar(
        title: const Text('Daily expenses'),
        backgroundColor: rmAppBar,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: loading ? null : _load),
        ],
      ),
      body: forbidden
          ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('You do not have access to Daily expenses. Ask an admin to tick it for you.', textAlign: TextAlign.center)))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(12), children: [
                const OfflineStatusBar(),
                TallyCompanyBadge(company: loading && settings.isEmpty ? null : company),
                if (loading && settings.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator())),
                if (error != null) RmCard(color: const Color(0xFFFDECEA), child: Text(error!)),
                if (notice != null) RmCard(color: const Color(0xFFF3F8EE), child: Text(notice!)),
                if (offline)
                  const RmCard(color: Color(0xFFFFF8E6), child: Text('No signal. You can still pick a ledger and add an entry (it is sent later), or say it and read it when there is signal.')),
                if (mayAdd) ...[
                  _settingsCard(),
                  _addCard(),
                  for (final c in cards) _entryCard(c),
                  if (drafts.isNotEmpty) _draftsCard(),
                ],
                if (!mayAdd)
                  const RmCard(child: Text('You can see the day. To add expenses, ask an admin to tick Add for you.', style: TextStyle(fontSize: 13))),
                _dayCard(),
              ]),
            ),
    );
  }

  Widget _settingsCard() {
    return RmCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Where entries go', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        InkWell(
          onTap: busy || offline ? null : _pickCompany,
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
            const Text('Company: ', style: TextStyle(fontSize: 13)),
            Expanded(child: Text(company.isEmpty ? '—' : company, style: const TextStyle(fontWeight: FontWeight.w700))),
            if (!offline) const Text('change', style: TextStyle(fontSize: 12, color: rmGreen)),
          ])),
        ),
        InkWell(
          onTap: busy || ledgers.isEmpty ? null : _pickCredit,
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
            const Text('Credit ledger: ', style: TextStyle(fontSize: 13)),
            Expanded(child: Text(credit.isEmpty ? 'Choose it (once)' : credit, style: TextStyle(fontWeight: FontWeight.w700, color: credit.isEmpty ? const Color(0xFF9E2419) : null))),
            const Text('change', style: TextStyle(fontSize: 12, color: rmGreen)),
          ])),
        ),
        Text('Both stay until you change them.', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
      ]),
    );
  }

  Widget _addCard() {
    final ready = credit.isNotEmpty;
    return RmCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Add an expense', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: rmGreen, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: busy || !ready ? null : _speak,
            icon: const Icon(Icons.mic),
            label: const Text('Say it', style: TextStyle(fontSize: 16)),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: typeCtrl,
              enabled: ready,
              decoration: const InputDecoration(hintText: 'or type: Badi Akhar majuri 1500', border: OutlineInputBorder(), isDense: true),
              onSubmitted: (_) => _readText(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: busy || !ready ? null : () => _readText(), child: const Text('Read')),
        ]),
        if (!ready) const Padding(padding: EdgeInsets.only(top: 6), child: Text('Choose the credit ledger first.', style: TextStyle(color: Color(0xFF9E2419), fontSize: 12.5))),
        if (offline && ledgers.isNotEmpty && ready)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: TextButton.icon(onPressed: _manualCard, icon: const Icon(Icons.edit_note), label: const Text('Pick the ledger myself')),
          ),
      ]),
    );
  }

  // an entry made by hand (used with no signal: pick from the saved ledger list)
  void _manualCard() {
    setState(() {
      cards.add(_Card(heard: '', sure: true, choices: const [], date: DateTime.now(), warns: const [], payer: credit.isEmpty ? null : credit)..manual = true);
    });
  }

  Widget _entryCard(_Card c) {
    _watchDup(c);
    final ok = c.ledger != null && (double.tryParse(c.amount.text.replaceAll(',', '').trim()) ?? 0) > 0;
    return RmCard(
      color: const Color(0xFFFAFCF8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (c.heard.isNotEmpty) Text('Heard: "${c.heard}"', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
        const SizedBox(height: 6),
        InkWell(
          onTap: () async {
            final p = await _pickLedger('Debit ledger', first: c.choices);
            if (p != null) {
              setState(() {
                c.ledger = p;
                c.sure = true;
                c.manual = true;
              });
            }
          },
          child: InputDecorator(
            decoration: InputDecoration(labelText: c.sure || c.ledger == null ? 'Debit ledger' : 'Debit ledger (please confirm)', border: const OutlineInputBorder(), isDense: true),
            child: Text(c.ledger ?? 'Choose the ledger', style: TextStyle(fontWeight: FontWeight.w700, color: c.ledger == null ? const Color(0xFF9E2419) : null)),
          ),
        ),
        if (!c.sure && c.choices.length > 1)
          Wrap(spacing: 6, children: [
            for (final n in c.choices)
              ActionChip(
                label: Text(n, style: const TextStyle(fontSize: 12)),
                onPressed: () => setState(() {
                  c.ledger = n;
                  c.sure = true;
                  c.manual = true;
                }),
              ),
          ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: c.amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount', border: OutlineInputBorder(), isDense: true),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () async {
              final p = await showDatePicker(context: context, initialDate: c.date, firstDate: DateTime.now().subtract(const Duration(days: 400)), lastDate: DateTime.now());
              if (p != null) setState(() => c.date = p);
            },
            icon: const Icon(Icons.event, size: 18),
            label: Text(dmy(isoDay(c.date))),
          ),
        ]),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            final p = await _pickLedger('Paid by (credited)', first: payerChoices);
            if (p != null) setState(() => c.payer = p);
          },
          child: InputDecorator(
            decoration: const InputDecoration(labelText: 'Paid by (credited)', border: OutlineInputBorder(), isDense: true),
            child: Text(c.payer ?? 'Who paid', style: TextStyle(fontWeight: FontWeight.w700, color: c.payer == null ? const Color(0xFF9E2419) : null)),
          ),
        ),
        if (payerChoices.length > 1)
          Wrap(spacing: 6, children: [
            for (final n in payerChoices)
              ChoiceChip(label: Text(n, style: const TextStyle(fontSize: 12)), selected: c.payer == n, onSelected: (_) => setState(() => c.payer = n)),
          ]),
        const SizedBox(height: 8),
        TextField(
          controller: c.note,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Narration for this item (the amount is added)', border: OutlineInputBorder(), isDense: true),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('Written as: ${_itemText(c.ledger, c.note.text, c.amount.text).isEmpty ? '—' : _itemText(c.ledger, c.note.text, c.amount.text)}', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
        ),
        if (c.manual) ...[
          const SizedBox(height: 8),
          TextField(controller: c.alias, decoration: const InputDecoration(labelText: 'Next time "…" means this ledger (optional, e.g. diesel)', border: OutlineInputBorder(), isDense: true)),
        ],
        for (final w in c.warns) Padding(padding: const EdgeInsets.only(top: 6), child: Text('⚑ ${w['text']}', style: const TextStyle(color: Color(0xFF9E2419), fontSize: 12.5))),
        _dupNote(c.dups),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: rmGreen),
              onPressed: busy || !ok ? null : () => _add(c),
              child: Text('Add to ${dm(isoDay(c.date))}'),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: () => setState(() => _dropCard(c)), child: const Text('Discard')),
        ]),
      ]),
    );
  }

  Widget _draftsCard() {
    return RmCard(
      color: const Color(0xFFFFF8E6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Said without signal', style: TextStyle(fontWeight: FontWeight.w800)),
        const Text('Saved on this phone. Tap Read when there is signal; you check it before it is added.', style: TextStyle(fontSize: 12)),
        for (final d in drafts)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              Expanded(child: Text('"${d['text']}"')),
              TextButton(onPressed: busy ? null : () => _readText(draftId: d['id'].toString(), text: d['text'].toString()), child: const Text('Read')),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  setState(() => drafts.removeWhere((x) => x['id'] == d['id']));
                  _saveDrafts();
                },
              ),
            ]),
          ),
      ]),
    );
  }

  Color _stateColor(String s) => s == 'posted' ? const Color(0xFF2C5E17) : s == 'pending' ? const Color(0xFF6B4A00) : s == 'empty' ? Colors.grey.shade700 : const Color(0xFF9E2419);

  Widget _dayCard() {
    return RmCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.chevron_left), onPressed: () { date = date.subtract(const Duration(days: 1)); _load(); }),
            Expanded(child: InkWell(onTap: _pickDate, child: Center(child: Text(dmy(isoDay(date)), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))))),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: isoDay(date) == isoDay(DateTime.now()) ? null : () { date = date.add(const Duration(days: 1)); _load(); },
            ),
          ]),
        ),
        if (waiting.isNotEmpty)
          Container(
            width: double.infinity,
            color: const Color(0xFFFFF8E6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Saved on this phone, not sent yet', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
              for (final w in waiting) Text('${dm(w['date'])} · ${w['ledger']} · ${inr(w['amount'])}', style: const TextStyle(fontSize: 13)),
            ]),
          ),
        if (vouchers.isEmpty && !offline) const Padding(padding: EdgeInsets.fromLTRB(12, 0, 12, 14), child: Text('No expenses entered for this day.')),
        for (final v in vouchers) _voucher(v),
        if (recent.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Wrap(spacing: 6, runSpacing: 4, children: [
              for (final r in {for (final x in recent) x['date'].toString(): x}.values)
                ActionChip(
                  label: Text('${dm(r['date'])} · ${inr(r['total'])}${r['state'] == 'posted' ? '' : ' ⚑'}', style: const TextStyle(fontSize: 12)),
                  onPressed: () {
                    date = DateTime.parse(r['date'].toString());
                    _load();
                  },
                ),
            ]),
          ),
      ]),
    );
  }

  String _creditsText(Map<String, dynamic> v) {
    final cs = ((v['credits'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (cs.isEmpty) return v['credit_ledger'].toString();
    return cs.map((c) => '${c['ledger']} ${inr(c['amount'])}').join(' · ');
  }

  Widget _voucher(Map<String, dynamic> v) {
    final state = v['state'].toString();
    final lines = ((v['lines'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: rmBorder))),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Journal${v['tally_number'] != null ? ' no. ${v['tally_number']}' : ''}', style: const TextStyle(fontWeight: FontWeight.w800))),
          Text('${v['state_text']}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _stateColor(state))),
        ]),
        Text(v['company'].toString(), style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700)),
        if (v['message'] != null && v['message'].toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(v['message'].toString(), style: TextStyle(fontSize: 12.5, color: _stateColor(state)))),
        const SizedBox(height: 4),
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${l['debit_ledger']}${(l['credit_ledger'] ?? '').toString().isNotEmpty && l['credit_ledger'] != v['credit_ledger'] ? ' · paid by ${l['credit_ledger']}' : ''}'),
                  if ((l['text'] ?? '').toString().isNotEmpty) Text(l['text'].toString(), style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                ]),
              ),
              Text(inr(l['amount']), style: const TextStyle(fontWeight: FontWeight.w700)),
              if (mayDelete) IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.close, size: 18, color: Color(0xFF9E2419)), tooltip: 'Remove', onPressed: busy ? null : () => _remove(l)),
            ]),
          ),
        Row(children: [
          Expanded(
            child: Text(
              'Total ${inr(v['total'])}  ·  credited: ${_creditsText(v)}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
        ]),
        if (mayAdd && (state == 'pending' || state == 'failed'))
          Align(alignment: Alignment.centerRight, child: TextButton(onPressed: busy ? null : () => _act(v, 'retry'), child: const Text('Try again now'))),
        if (mayAdd && state == 'conflict')
          Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: busy ? null : () => _act(v, 'overwrite'), child: const Text('Overwrite Tally / enter again'))),
      ]),
    );
  }
}

// ── pick a ledger: search + list, suggested ones first ───────────────
class _LedgerSheet extends StatefulWidget {
  final String title;
  final List<String> all;
  final List<String> first;
  const _LedgerSheet({required this.title, required this.all, required this.first});
  @override
  State<_LedgerSheet> createState() => _LedgerSheetState();
}

class _LedgerSheetState extends State<_LedgerSheet> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    final k = q.trim().toLowerCase();
    final top = widget.first.where((n) => k.isEmpty || n.toLowerCase().contains(k)).toList();
    final rest = widget.all.where((n) => !widget.first.contains(n) && (k.isEmpty || n.toLowerCase().contains(k))).take(80).toList();
    final list = [...top, ...rest];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(children: [Expanded(child: Text(widget.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))), IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(autofocus: true, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Find a ledger', border: OutlineInputBorder(), isDense: true), onChanged: (v) => setState(() => q = v)),
        ),
        Flexible(
          child: ListView(shrinkWrap: true, children: [
            for (var i = 0; i < list.length; i++)
              ListTile(
                dense: true,
                title: Text(list[i]),
                subtitle: i < top.length ? const Text('suggested', style: TextStyle(fontSize: 11)) : null,
                onTap: () => Navigator.pop(context, list[i]),
              ),
            if (list.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('No ledger matches.')),
          ]),
        ),
      ]),
    );
  }
}

// ── say it: the phone's own speech recognition, Hindi or English ─────
class _SpeakSheet extends StatefulWidget {
  const _SpeakSheet();
  @override
  State<_SpeakSheet> createState() => _SpeakSheetState();
}

class _SpeakSheetState extends State<_SpeakSheet> {
  static const _prefKey = 'dj_locale';
  final stt.SpeechToText _speech = stt.SpeechToText();
  final TextEditingController _text = TextEditingController();
  bool _ready = false;
  bool _listening = false;
  String _locale = 'hi_IN';
  String _base = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_prefKey);
      if (s == 'hi_IN' || s == 'en_IN') _locale = s!;
    } catch (_) {}
    try {
      _ready = await _speech.initialize(
        onStatus: (s) {
          if (!mounted) return;
          if (s == 'done' || s == 'notListening') setState(() => _listening = false);
        },
        onError: (e) {
          if (!mounted) return;
          setState(() {
            _listening = false;
            _error = 'Could not listen (${e.errorMsg}). You can type, or use the keyboard microphone.';
          });
        },
      );
    } catch (_) {
      _ready = false;
    }
    if (!_ready && mounted) _error = 'Voice is not available on this phone right now. You can type, or use the keyboard microphone.';
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _speech.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _setLocale(String l) async {
    setState(() => _locale = l);
    try {
      (await SharedPreferences.getInstance()).setString(_prefKey, l);
    } catch (_) {}
  }

  Future<void> _toggle() async {
    if (!_ready) return;
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    _base = _text.text.trim();
    setState(() {
      _error = null;
      _listening = true;
    });
    await _speech.listen(
      localeId: _locale,
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 6),
      listenOptions: stt.SpeechListenOptions(partialResults: true, listenMode: stt.ListenMode.dictation),
      onResult: (r) {
        if (!mounted) return;
        final said = r.recognizedWords.trim();
        setState(() {
          _text.text = _base.isEmpty ? said : '$_base $said';
          _text.selection = TextSelection.collapsed(offset: _text.text.length);
        });
      },
    );
  }

  Future<void> _done() async {
    if (_listening) await _speech.stop();
    if (mounted) Navigator.pop(context, _text.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('Say the expense', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        ]),
        const Text('Say the ledger and the amount, for example "Badi Akhar majuri pandrah sau" or "diesel 2000". Add "yesterday" or a date if it is not today. You can say two: "diesel 2000, sokari 500".', style: TextStyle(fontSize: 12.5)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: [
          ChoiceChip(label: const Text('हिंदी'), selected: _locale == 'hi_IN', onSelected: (_) => _setLocale('hi_IN')),
          ChoiceChip(label: const Text('English'), selected: _locale == 'en_IN', onSelected: (_) => _setLocale('en_IN')),
        ]),
        const SizedBox(height: 10),
        TextField(controller: _text, minLines: 2, maxLines: 4, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'What you say appears here; you can correct it')),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, style: const TextStyle(color: Color(0xFF9E2419), fontSize: 12.5))),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(onPressed: _ready ? _toggle : null, icon: Icon(_listening ? Icons.stop : Icons.mic), label: Text(_listening ? 'Stop' : 'Speak')),
          ),
          const SizedBox(width: 10),
          Expanded(child: FilledButton(style: FilledButton.styleFrom(backgroundColor: rmGreen), onPressed: _done, child: const Text('Use this'))),
        ]),
      ]),
    );
  }
}
