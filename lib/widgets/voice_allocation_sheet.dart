// lib/widgets/voice_allocation_sheet.dart
//
// Speak the work allocation: farm, work type, then the workers' names, e.g.
//     "Choufuli, fer, Raman, Rahul, Neelu"
// (Hindi or English). The phone's own speech recognition turns the voice into
// text; your server matches the words against the farm / work type / present
// worker lists (POST /voice-allocation/parse) and the answer goes to the normal
// review sheet. NOTHING is saved from here - the person checks and taps first.
//
// The text box stays editable: a wrong word can be fixed, or the keyboard's own
// microphone / typing can be used if the microphone button does not work.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../services/api_client.dart';
import '../services/grouped_scan_parser.dart';

class VoiceDraft {
  final List<ScanSection> sections;
  final List<String> unclassified;
  VoiceDraft(this.sections, this.unclassified);
}

class VoiceAllocationSheet extends StatefulWidget {
  final String dateStr; // yyyy-MM-dd of the attendance day
  final Color idaGreen;
  const VoiceAllocationSheet({super.key, required this.dateStr, required this.idaGreen});

  @override
  State<VoiceAllocationSheet> createState() => _VoiceAllocationSheetState();
}

class _VoiceAllocationSheetState extends State<VoiceAllocationSheet> {
  static const _prefKey = 'voice_alloc_locale';
  final stt.SpeechToText _speech = stt.SpeechToText();
  final TextEditingController _text = TextEditingController();
  bool _ready = false;
  bool _listening = false;
  bool _busy = false;
  String _locale = 'hi_IN'; // hi_IN | en_IN
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
      final saved = p.getString(_prefKey);
      if (saved == 'hi_IN' || saved == 'en_IN') _locale = saved!;
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
    if (!_ready && mounted) {
      _error = 'Voice is not available on this phone right now. You can type, or use the keyboard microphone.';
    }
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
      final p = await SharedPreferences.getInstance();
      await p.setString(_prefKey, l);
    } catch (_) {}
  }

  Future<void> _toggleListen() async {
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
      listenFor: const Duration(seconds: 90),
      pauseFor: const Duration(seconds: 8),
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        listenMode: stt.ListenMode.dictation,
      ),
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

  Future<void> _check() async {
    final said = _text.text.trim();
    if (said.isEmpty) {
      setState(() => _error = 'Say or type the allocation first.');
      return;
    }
    if (_listening) await _speech.stop();
    setState(() {
      _busy = true;
      _error = null;
      _listening = false;
    });
    try {
      final res = await Api.json('POST', '/voice-allocation/parse', body: {'date': widget.dateStr, 'transcript': said});
      final secs = <ScanSection>[];
      for (final s in (res['sections'] as List? ?? [])) {
        final farm = s['farm'];
        final wt = s['workType'];
        final sec = ScanSection(
          farmId: farm == null ? null : (farm['id'] as num).toInt(),
          workTypeId: wt == null ? null : (wt['id'] as num).toInt(),
          farmLabel: farm == null ? 'Choose farm' : '${farm['name']}',
          workTypeLabel: wt == null ? 'Choose work type' : '${wt['name']}',
        );
        for (final w in (s['workers'] as List? ?? [])) {
          final alts = (w['alts'] as List? ?? []).map((a) => '${a['name']}').toList();
          final heard = '${w['heard']}';
          sec.entries.add(ScanWorkerEntry(
            rawLine: alts.isEmpty ? heard : '$heard (could also be ${alts.join(' / ')})',
            selectedWorkerId: (w['id'] as num).toInt(),
            initialAmount: '',
            matchScore: w['sure'] == true ? 0.95 : 0.6,
          ));
        }
        if (sec.entries.isNotEmpty) secs.add(sec);
      }
      final un = (res['unclassified'] as List? ?? []).map((e) => '$e').toList();
      if (secs.isEmpty) {
        setState(() {
          _busy = false;
          _error = 'No worker names were recognised among today\'s present workers. Check the words above, or try again.';
        });
        return;
      }
      if (mounted) Navigator.pop(context, VoiceDraft(secs, un));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not check: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final green = widget.idaGreen;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Expanded(
              child: Text('Speak the allocation',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF1E4012))),
            ),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
          const Text(
              'Say the farm, then the work, then the workers. Then say the next farm and work, and so on. Example: "Choufuli, fer, Raman, Rahul, Neelu".',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF5F6A58))),
          const SizedBox(height: 10),
          Row(children: [
            ChoiceChip(
              label: const Text('हिन्दी'),
              selected: _locale == 'hi_IN',
              onSelected: _listening ? null : (_) => _setLocale('hi_IN'),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('English'),
              selected: _locale == 'en_IN',
              onSelected: _listening ? null : (_) => _setLocale('en_IN'),
            ),
          ]),
          const SizedBox(height: 14),
          Center(
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _ready && !_busy ? _toggleListen : null,
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: !_ready ? Colors.grey.shade400 : (_listening ? Colors.red.shade600 : green),
                  boxShadow: _listening ? [BoxShadow(color: Colors.red.withOpacity(0.35), blurRadius: 18, spreadRadius: 4)] : null,
                ),
                child: Icon(_listening ? Icons.stop : Icons.mic, color: Colors.white, size: 40),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(_listening ? 'Listening… tap to stop' : (_ready ? 'Tap and speak' : 'Microphone not available'),
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'What was heard (you can correct it)',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(fontSize: 12.5, color: Colors.orange.shade800)),
            ),
          const SizedBox(height: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: green, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _busy ? null : _check,
            child: Text(_busy ? 'Checking…' : 'Check and review',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 4),
          const Text('Nothing is saved yet. You review everything on the next screen.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: Color(0xFF5F6A58))),
        ]),
      ),
    );
  }
}
