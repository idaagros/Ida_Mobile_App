// lib/screens/weather_screen.dart
//
// Shows current conditions + 7-day forecast for whichever farm is
// selected, using coordinates manually entered in Farm Master -
// deliberately not device GPS. A farm with no coordinates set is
// excluded from the picker entirely rather than shown with an error,
// since there's nothing useful to show for it here.
//
// Sep 2026 (group C): spray advice from /weather/farm/:id → spray —
// spraying now, sprays due on this farm with the best time, hour by
// hour for today and tomorrow, the rule, and a spray word per day.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/responsive.dart';

import '../config/app_config.dart';
class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});
  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static String get baseUrl => AppConfig.apiBaseUrl;

  Future<Map<String, String>> get _headers async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${prefs.getString('token') ?? ''}',
    };
  }

  bool loading = true;
  String? error;
  List<Map<String, dynamic>> farms = [];
  int? selectedFarmId;
  Map<String, dynamic>? weatherData;
  bool loadingWeather = false;

  @override
  void initState() {
    super.initState();
    _loadFarms();
  }

  Future<void> _loadFarms() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final h = await _headers;
      final res = await http.get(Uri.parse('$baseUrl/farms'), headers: h);
      if (res.statusCode == 200) {
        final all = List<Map<String, dynamic>>.from(jsonDecode(res.body));
        // Only farms with coordinates actually set - nothing useful to
        // show for the others, and this keeps the picker meaningful.
        final withCoords = all
            .where((f) => f['gps_lat'] != null && f['gps_long'] != null)
            .toList();
        setState(() {
          farms = withCoords;
          selectedFarmId =
              withCoords.isNotEmpty ? withCoords.first['id'] : null;
        });
        if (selectedFarmId != null) await _loadWeather(selectedFarmId!);
      } else {
        setState(() => error = 'Failed to load farms');
      }
    } catch (e) {
      setState(() => error = 'Could not reach server: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _loadWeather(int farmId) async {
    setState(() {
      loadingWeather = true;
      error = null;
    });
    try {
      final h = await _headers;
      final res = await http.get(Uri.parse('$baseUrl/weather/farm/$farmId'),
          headers: h);
      if (res.statusCode == 200) {
        setState(() => weatherData = jsonDecode(res.body));
      } else {
        final data = jsonDecode(res.body);
        setState(() {
          weatherData = null;
          error = data['error'] ?? 'Failed to load weather';
        });
      }
    } catch (e) {
      setState(() {
        weatherData = null;
        error = 'Could not reach server: $e';
      });
    } finally {
      if (mounted) setState(() => loadingWeather = false);
    }
  }

  IconData _iconFor(String? icon) {
    switch (icon) {
      case 'sunny':
        return Icons.wb_sunny_outlined;
      case 'partly_cloudy':
        return Icons.wb_cloudy_outlined;
      case 'cloudy':
        return Icons.cloud_outlined;
      case 'fog':
        return Icons.foggy;
      case 'drizzle':
        return Icons.grain;
      case 'rain':
        return Icons.water_drop_outlined;
      case 'snow':
        return Icons.ac_unit;
      case 'thunderstorm':
        return Icons.thunderstorm_outlined;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Weather',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: idaGreen))
          : farms.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.location_off_outlined,
                          size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text(
                        'No farms have coordinates set yet.\nAdd latitude and longitude in Farm Master to see weather.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 13.5),
                      ),
                    ]),
                  ),
                )
              : RefreshIndicator(
                  color: idaGreen,
                  onRefresh: () => selectedFarmId != null
                      ? _loadWeather(selectedFarmId!)
                      : _loadFarms(),
                  child: Responsive.constrainedContent(
                      context,
                      ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        children: [
                          DropdownButtonFormField<int>(
                            value: selectedFarmId,
                            decoration: InputDecoration(
                                labelText: 'Farm',
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10))),
                            items: farms
                                .map<DropdownMenuItem<int>>((f) =>
                                    DropdownMenuItem(
                                        value: f['id'],
                                        child: Text(f['name'] ?? '')))
                                .toList(),
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => selectedFarmId = v);
                              _loadWeather(v);
                            },
                          ),
                          const SizedBox(height: 16),
                          if (loadingWeather)
                            const Center(
                                child: Padding(
                                    padding: EdgeInsets.all(30),
                                    child: CircularProgressIndicator(
                                        color: idaGreen)))
                          else if (error != null)
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                  color: const Color(0xFFFDE8E8),
                                  borderRadius: BorderRadius.circular(12)),
                              child: Text(error!,
                                  style: const TextStyle(
                                      color: Color(0xFFC0392B), fontSize: 13)),
                            )
                          else if (weatherData != null) ...[
                            _currentCard(weatherData!['current']),
                            if (weatherData!['spray'] is Map)
                              ..._spraySection(weatherData!['spray']),
                            const SizedBox(height: 20),
                            Text('7-DAY FORECAST',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.grey.shade600,
                                    letterSpacing: 0.6)),
                            const SizedBox(height: 10),
                            ...List<Map<String, dynamic>>.from(
                                    weatherData!['daily'] ?? [])
                                .map((d) => _dailyRow(d, _sprayDay(d['date']))),
                          ],
                        ],
                      )),
                ),
    );
  }

  Widget _currentCard(Map<String, dynamic>? current) {
    if (current == null) return const SizedBox.shrink();
    final rainy = current['icon'] == 'rain' ||
        current['icon'] == 'thunderstorm' ||
        current['icon'] == 'drizzle';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: rainy ? const Color(0xFFE3F2FD) : const Color(0xFFFEF3DC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: [
        Icon(_iconFor(current['icon']),
            size: 48,
            color: rainy ? const Color(0xFF0D47A1) : const Color(0xFF92600A)),
        const SizedBox(height: 8),
        Text('${current['temperature_c']}°C',
            style: const TextStyle(
                fontSize: 32, fontWeight: FontWeight.w700, color: idaDark)),
        Text(current['label'] ?? '',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _statChip(Icons.water_drop_outlined, '${current['humidity_pct']}%',
              'Humidity'),
          _statChip(Icons.air, '${current['wind_speed_kmh']} km/h', 'Wind'),
          _statChip(Icons.grain, '${current['precipitation_mm']} mm', 'Rain'),
        ]),
      ]),
    );
  }

  Widget _statChip(IconData icon, String value, String label) {
    return Column(children: [
      Icon(icon, size: 18, color: Colors.grey.shade600),
      const SizedBox(height: 2),
      Text(value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      Text(label,
          style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
    ]);
  }

  Map? _sprayDay(dynamic date) {
    final days = (weatherData?['spray'] is Map ? weatherData!['spray']['days'] : null) as List?;
    if (days == null) return null;
    for (final d in days) {
      if (d['date'] == date) return d;
    }
    return null;
  }

  Widget _dailyRow(Map<String, dynamic> day, [Map? spray]) {
    DateTime? date;
    try {
      date = DateTime.parse(day['date']);
    } catch (_) {}
    final rainProb = day['precipitation_probability_pct'];
    final highRain = rainProb != null && rainProb >= 50;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0E7D8))),
      child: Row(children: [
        SizedBox(
          width: 56,
          child: Text(
              date != null ? DateFormat('EEE\ndd MMM').format(date) : '',
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, height: 1.3)),
        ),
        Icon(_iconFor(day['icon']),
            size: 22,
            color: highRain ? const Color(0xFF0D47A1) : Colors.grey.shade600),
        const SizedBox(width: 10),
        Expanded(
          child: Text(day['label'] ?? '',
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis,
              maxLines: 1),
        ),
        if (rainProb != null && rainProb > 0)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Text('$rainProb%',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: highRain
                        ? const Color(0xFF0D47A1)
                        : Colors.grey.shade500)),
          ),
        Text('${day['temp_max_c']}° / ${day['temp_min_c']}°',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        if (spray != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(color: _sc(spray['status']).$1, borderRadius: BorderRadius.circular(20)),
            child: Text(_sc(spray['status']).$3, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: _sc(spray['status']).$2)),
          ),
        ],
      ]),
    );
  }

  // ── Spray advice (Sep 2026, group C) ──────────────────────────────
  // Same rule as the website and the crop calendar (utils/sprayRule.js):
  // Good = rain chance under 30% for the next 4 h, wind 3–15 km/h, below
  // 32°; Careful = 32–35°, still air, or rain 30–49%; Avoid otherwise.
  static const _sprayCol = {
    'good': (Color(0xFFE3F0DA), Color(0xFF2C5E17), 'Good'),
    'careful': (Color(0xFFFCEFD2), Color(0xFF7A4D00), 'Careful'),
    'avoid': (Color(0xFFFBE2DF), Color(0xFF9E2419), 'Avoid'),
  };

  (Color, Color, String) _sc(String? s) => _sprayCol[s] ?? (const Color(0xFFECEEE8), const Color(0xFF4A5643), '—');

  String _hourText(dynamic h) {
    final n = int.tryParse('$h') ?? 0;
    final ampm = n < 12 ? 'am' : 'pm';
    final x = n % 12 == 0 ? 12 : n % 12;
    return '$x $ampm';
  }

  String _dayName(String? d, List days) {
    if (d == null) return '';
    if (days.isNotEmpty && days[0]['date'] == d) return 'Today';
    if (days.length > 1 && days[1]['date'] == d) return 'Tomorrow';
    final t = DateTime.tryParse(d);
    return t == null ? d : DateFormat('EEE d MMM').format(t);
  }

  List<Widget> _spraySection(Map sp) {
    final now = sp['now'] is Map ? sp['now'] as Map : null;
    final days = (sp['days'] as List?) ?? [];
    final due = (sp['sprays_due'] as List?) ?? [];
    final rule = sp['rule'] is Map ? sp['rule'] as Map : {};
    final nc = _sc(now?['status']);
    Widget heading(String t) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 10),
          child: Text(t.toUpperCase(),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade600, letterSpacing: 0.6)),
        );
    return [
      if (now != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: nc.$1, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Icon(Icons.water_drop_outlined, color: nc.$2),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Spraying now: ${nc.$3}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: nc.$2)),
                Text('${now['text'] ?? ''}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: nc.$2)),
                if (days.isNotEmpty)
                  Text(
                    days[0]['best_text'] != null ? 'Best time today: ${days[0]['best_text']}' : 'No good time to spray today',
                    style: TextStyle(fontSize: 12.5, color: nc.$2),
                  ),
              ]),
            ),
          ]),
        ),
      ],
      heading('Sprays due on this farm (next 7 days)'),
      if (due.isEmpty)
        Text('No sprays due here in the next 7 days.', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
      for (final j in due)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: j['overdue'] == true ? const Color(0xFFF1C4BE) : const Color(0xFFE0E7D8)),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${j['label'] ?? ''}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  '${j['crop'] ?? ''} · ${j['overdue'] == true ? 'Overdue' : 'Due ${_dayName(j['planned_date'], days)}'}',
                  style: TextStyle(fontSize: 12, color: j['overdue'] == true ? const Color(0xFF9E2419) : Colors.grey.shade600),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ]),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                j['best_text'] != null
                    ? '${_dayName(j['best_date'], days)}, ${j['best_text']}'
                    : j['advice_status'] == 'no_forecast' ? 'Too far to tell' : 'No good time yet',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: j['best_text'] != null ? const Color(0xFF2C5E17) : const Color(0xFF7A4D00)),
              ),
            ),
          ]),
        ),
      heading('Spray advice, hour by hour'),
      for (final d in days.take(2)) ...[
        Row(children: [
          Text(_dayName(d['date'], days), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              d['best_text'] != null ? 'Best time to spray: ${d['best_text']}' : 'No good time to spray',
              style: TextStyle(fontSize: 12.5, color: d['best_text'] != null ? const Color(0xFF2C5E17) : const Color(0xFF7A4D00), fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
        const SizedBox(height: 6),
        SizedBox(
          height: 74,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final h in (d['hours'] as List? ?? []))
                Builder(builder: (_) {
                  final c = _sc(h['status']);
                  return Container(
                    width: 58,
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(color: c.$1, borderRadius: BorderRadius.circular(10)),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(_hourText(h['hour']), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: c.$2)),
                      Text('${h['temp_c'] ?? ''}°', style: TextStyle(fontSize: 11, color: c.$2)),
                      Text(h['reason'] != null ? '${h['reason']}' : c.$3,
                          style: TextStyle(fontSize: 9.5, color: c.$2), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ]),
                  );
                }),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE0E7D8))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final k in const ['good', 'careful', 'avoid'])
            if (rule[k] != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${_sc(k).$3} — ', style: TextStyle(fontWeight: FontWeight.w800, color: _sc(k).$2)),
                    TextSpan(text: '${rule[k]}'),
                  ]),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
        ]),
      ),
    ];
  }
}

