// lib/services/wage_speech.dart
//
// Speaks a wages answer aloud (phone only). Language follows how Ida asked (Hindi or English).
// Used by wages_screen.dart after a VOICE question only. Does nothing on web.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WageSpeech {
  static final FlutterTts _tts = FlutterTts();
  static bool _ready = false;

  static const _enMonths = ['', 'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  static const _hiMonths = ['', 'जनवरी', 'फ़रवरी', 'मार्च', 'अप्रैल', 'मई', 'जून', 'जुलाई', 'अगस्त', 'सितंबर', 'अक्टूबर', 'नवंबर', 'दिसंबर'];

  /// Speak the answer. [res] is the server reply: {question, result}. Never throws.
  static Future<void> speak(Map res) async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final hindi = (prefs.getString('voice_alloc_locale') ?? 'hi_IN').toLowerCase().startsWith('hi');
      final text = compose(res, hindi);
      if (text.isEmpty) return;
      await _tts.stop();
      if (!_ready) {
        await _tts.setSpeechRate(0.45);
        await _tts.awaitSpeakCompletion(false);
        _ready = true;
      }
      final lang = hindi ? 'hi-IN' : 'en-IN';
      var ok = await _tts.isLanguageAvailable(lang);
      if (ok != true && !hindi) {
        ok = await _tts.isLanguageAvailable('en-US');
        await _tts.setLanguage(ok == true ? 'en-US' : lang);
      } else {
        await _tts.setLanguage(lang);
      }
      await _tts.speak(text);
    } catch (_) {}
  }

  static Future<void> stop() async {
    if (kIsWeb) return;
    try {
      await _tts.stop();
    } catch (_) {}
  }

  static String _money(num v, bool hi) {
    final n = v.round();
    return hi ? '$n रुपये' : '$n rupees';
  }

  static String _date(String iso, bool hi) {
    final p = iso.split('-');
    if (p.length != 3) return iso;
    final m = int.tryParse(p[1]) ?? 0;
    final d = int.tryParse(p[2]) ?? 0;
    if (m < 1 || m > 12) return iso;
    return hi ? '$d ${_hiMonths[m]}' : '$d ${_enMonths[m]}';
  }

  static String _period(Map? q, Map? result, bool hi) {
    final label = q?['period'] is Map ? q!['period']['label'] : null;
    if (label is String && label.isNotEmpty) {
      if (!hi) return label;
      const m = {'this week': 'इस हफ़्ते', 'last week': 'पिछले हफ़्ते', 'this month': 'इस महीने', 'last month': 'पिछले महीने'};
      return m[label] ?? label;
    }
    final from = '${result?['from'] ?? ''}';
    final to = '${result?['to'] ?? ''}';
    if (from.isEmpty) return '';
    if (from == to) return hi ? '${_date(from, true)} को' : 'on ${_date(from, false)}';
    return hi ? '${_date(from, true)} से ${_date(to, true)} तक' : 'from ${_date(from, false)} to ${_date(to, false)}';
  }

  /// The sentence(s) to say. Short and natural.
  static String compose(Map res, bool hi) {
    final result = res['result'];
    if (result is! Map) return hi ? 'मुझे सवाल समझ नहीं आया।' : 'I could not understand the question.';
    final q = res['question'] is Map ? res['question'] as Map : null;
    final totals = result['totals'] is Map ? result['totals'] as Map : {};
    final workers = result['workers'] is List ? result['workers'] as List : [];
    final per = _period(q, result, hi);
    final approved = (totals['approved'] ?? 0) as num;
    final pending = (totals['pending'] ?? 0) as num;

    final who = <String>[];
    if (q?['person'] is Map) who.add('${q!['person']['name']}');
    if (q?['gender'] == 'F') who.add(hi ? 'महिलाएँ' : 'women');
    if (q?['gender'] == 'M') who.add(hi ? 'पुरुष' : 'men');
    if (q?['farm'] is Map) who.add('${q!['farm']['name']}');
    if (q?['workType'] is Map) who.add('${q!['workType']['name']}');
    final head = [if (who.isNotEmpty) who.join(', '), if (per.isNotEmpty) per].join(', ');

    if (workers.isEmpty || (approved == 0 && pending == 0)) {
      return hi ? '${head.isEmpty ? '' : '$head, '}कोई मज़दूरी नहीं मिली।' : 'No wages found${head.isEmpty ? '' : ' for $head'}.';
    }

    final b = StringBuffer();
    if (head.isNotEmpty) b.write(hi ? '$head। ' : '$head. ');
    if (workers.length == 1 && q?['person'] is Map) {
      final w = workers.first as Map;
      final da = (w['days_approved'] ?? 0) as num;
      final dp = (w['days_pending'] ?? 0) as num;
      if (hi) {
        b.write('$da दिन मंज़ूर, ${_money(w['approved'] ?? 0, true)}। ');
        if (dp > 0) b.write('$dp दिन मंज़ूरी बाकी, ${_money(w['pending'] ?? 0, true)}।');
      } else {
        b.write('$da ${da == 1 ? 'day' : 'days'} approved, ${_money(w['approved'] ?? 0, false)}. ');
        if (dp > 0) b.write('$dp ${dp == 1 ? 'day' : 'days'} pending, ${_money(w['pending'] ?? 0, false)}.');
      }
    } else {
      final n = workers.length;
      if (hi) {
        b.write('$n मज़दूर। मंज़ूर ${_money(approved, true)}। ');
        if (pending > 0) b.write('मंज़ूरी बाकी ${_money(pending, true)}।');
      } else {
        b.write('$n ${n == 1 ? 'worker' : 'workers'}. Approved ${_money(approved, false)}. ');
        if (pending > 0) b.write('Pending ${_money(pending, false)}.');
      }
    }
    return b.toString().trim();
  }
}
