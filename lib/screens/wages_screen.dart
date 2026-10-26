// lib/screens/wages_screen.dart
//
// "Wages": how much is to be paid. Ask by voice (phone) or by typing:
//   "viju bhau this week", "viju 22 oct", "total this week", "women last week", "Sunday to Saturday for Choufuli".
// Pay week is Sunday to Saturday. Approved days are what is payable; days still waiting for approval are shown apart.
// Nothing here changes any data. Server: /wages (routes/wages.js).

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/wage_speech.dart';
import '../widgets/voice_allocation_sheet.dart';

const Color _green = Color(0xFF3B7A28);
const Color _dark = Color(0xFF1E4012);
const Color _line = Color(0xFFCFDDC3);
const Color _muted = Color(0xFF5F6A58);

String _rs(num v) {
  final n = v.round();
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final left = s.length - i;
    b.write(s[i]);
    if (left > 1 && (left == 4 || (left > 4 && (left - 3) % 2 == 0))) b.write(',');
  }
  return '${n < 0 ? '-' : ''}₹$b';
}

class WagesScreen extends StatefulWidget {
  const WagesScreen({super.key});
  @override
  State<WagesScreen> createState() => _WagesScreenState();
}

class _WagesScreenState extends State<WagesScreen> {
  final _ask = TextEditingController();
  Map<String, dynamic>? _data; // {question?, result}
  String _title = '';
  bool _busy = false;
  String? _error;
  final Set<int> _open = {};

  @override
  void initState() {
    super.initState();
    _preset('this');
  }

  @override
  void dispose() {
    WageSpeech.stop();
    _ask.dispose();
    super.dispose();
  }

  Future<void> _preset(String which) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // /wages returns this week by default, with the dates of this and last week
      final first = Map<String, dynamic>.from(await Api.json('GET', '/wages') as Map);
      Map<String, dynamic> r = first;
      if (which == 'last') {
        final w = Map<String, dynamic>.from(first['week'] as Map);
        final lw = Map<String, dynamic>.from(w['last_week'] as Map);
        r = Map<String, dynamic>.from(await Api.json('GET', '/wages', query: {'from': '${lw['from']}', 'to': '${lw['to']}'}) as Map);
      }
      if (!mounted) return;
      setState(() {
        _data = {'result': r['result']};
        _title = which == 'last' ? 'Last week (Sun–Sat)' : 'This week';
        _open.clear();
      });
    } catch (e) {
      if (mounted) setState(() => _error = Api.errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = Map<String, dynamic>.from(await Api.json('POST', '/wages/ask', body: {'transcript': t}) as Map);
      if (!mounted) return;
      setState(() {
        _data = r;
        _title = _questionTitle(r['question']);
        _open.clear();
        if ((r['result']?['workers'] as List?)?.length == 1) _open.add(0);
      });
    } catch (e) {
      if (mounted) setState(() => _error = Api.errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _questionTitle(dynamic q) {
    if (q is! Map) return '';
    final parts = <String>[];
    if (q['person'] is Map) parts.add('${q['person']['name']}');
    if (q['gender'] == 'F') parts.add('Women');
    if (q['gender'] == 'M') parts.add('Men');
    if (q['farm'] is Map) parts.add('${q['farm']['name']}');
    if (q['workType'] is Map) parts.add('${q['workType']['name']}');
    final p = q['period'];
    if (p is Map) parts.add('${p['label']}');
    return parts.join(' · ');
  }

  Future<void> _voice() async {
    final res = await showModalBottomSheet<Map>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => VoiceAllocationSheet(
        dateStr: DateTime.now().toIso8601String().substring(0, 10),
        idaGreen: _green,
        endpoint: '/wages/ask',
        title: 'Ask about wages',
        hint: 'For example: "Viju bhau this week", "Viju 22 October", "total this week", "women last week".',
      ),
    );
    if (res == null || !mounted) return;
    if (res['result'] == null) {
      _toast('I could not understand the question.');
      WageSpeech.speak(res);
      return;
    }
    setState(() {
      _data = Map<String, dynamic>.from(res);
      _title = _questionTitle(res['question']);
      _open.clear();
      if ((res['result']?['workers'] as List?)?.length == 1) _open.add(0);
    });
    // asked by voice -> answer by voice (phone only; typed questions stay silent)
    WageSpeech.speak(res);
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final result = _data == null ? null : Map<String, dynamic>.from(_data!['result'] as Map);
    final totals = result == null ? null : Map<String, dynamic>.from(result['totals'] as Map);
    final workers = result == null ? <Map<String, dynamic>>[] : (result['workers'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F3),
      appBar: AppBar(backgroundColor: _green, foregroundColor: Colors.white, title: const Text('Wages', style: TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _ask,
              textInputAction: TextInputAction.search,
              onSubmitted: (v) => _send(v),
              decoration: InputDecoration(
                hintText: 'Ask: "Viju bhau this week"',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: () => _send(_ask.text)),
              ),
            ),
          ),
          if (!kIsWeb) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 52,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _dark, padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: _busy ? null : _voice,
                child: const Icon(Icons.mic, color: Colors.white),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: [
          ActionChip(label: const Text('This week'), onPressed: _busy ? null : () => _preset('this')),
          ActionChip(label: const Text('Last week'), onPressed: _busy ? null : () => _preset('last')),
          ActionChip(label: const Text('Everyone today'), onPressed: _busy ? null : () => _send('everyone today')),
          ActionChip(label: const Text('Women this week'), onPressed: _busy ? null : () => _send('women this week')),
          ActionChip(label: const Text('Men this week'), onPressed: _busy ? null : () => _send('men this week')),
        ]),
        if (_busy) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
        if (_error != null)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFFDE8E6), borderRadius: BorderRadius.circular(10)),
            child: Text(_error!, style: const TextStyle(color: Color(0xFF9E2419), fontWeight: FontWeight.w600)),
          ),
        if (result != null && totals != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_title, style: const TextStyle(fontSize: 13, color: _muted, fontWeight: FontWeight.w700)),
              Text('${result['from']} to ${result['to']}', style: const TextStyle(fontSize: 12, color: _muted)),
              const SizedBox(height: 6),
              const Text('To be paid (approved days)', style: TextStyle(fontSize: 12.5, color: _muted)),
              Text(_rs(totals['approved'] as num), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: _dark)),
              if ((totals['pending'] as num) > 0)
                Text('+ ${_rs(totals['pending'] as num)} waiting for approval', style: const TextStyle(fontSize: 13.5, color: Color(0xFF9A5B00), fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('${totals['workers']} worker${totals['workers'] == 1 ? '' : 's'} · ${totals['men']} men · ${totals['women']} women',
                  style: const TextStyle(fontSize: 12.5, color: _muted)),
            ]),
          ),
          const SizedBox(height: 10),
          if (workers.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No work found for this.', style: TextStyle(color: _muted))),
          for (var i = 0; i < workers.length; i++) _workerCard(i, workers[i]),
        ],
      ]),
    );
  }

  Widget _workerCard(int i, Map<String, dynamic> w) {
    final open = _open.contains(i);
    final days = (w['days'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final pending = (w['pending'] as num) > 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(children: [
        ListTile(
          onTap: () => setState(() => open ? _open.remove(i) : _open.add(i)),
          title: Text('${w['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(
            '${w['days_approved']} day${w['days_approved'] == 1 ? '' : 's'} approved${pending ? ' · ${w['days_pending']} waiting' : ''}',
            style: const TextStyle(fontSize: 12.5),
          ),
          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_rs(w['approved'] as num), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: _dark)),
            if (pending) Text('+${_rs(w['pending'] as num)}', style: const TextStyle(fontSize: 12, color: Color(0xFF9A5B00), fontWeight: FontWeight.w700)),
          ]),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(children: [
              for (final d in days)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Expanded(child: Text('${d['date']}${d['kind'] == 'paid_leave' ? ' · paid leave' : d['kind'] == 'half' ? ' · half day' : ''}', style: const TextStyle(fontSize: 13))),
                    Text(_rs(d['amount'] as num), style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    Text('${d['status']}' == 'approved' ? 'approved' : 'waiting', style: TextStyle(fontSize: 11.5, color: '${d['status']}' == 'approved' ? _green : const Color(0xFF9A5B00))),
                  ]),
                ),
            ]),
          ),
      ]),
    );
  }
}
