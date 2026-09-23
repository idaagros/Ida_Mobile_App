// lib/screens/weather_screen.dart
//
// Shows current conditions + 7-day forecast for whichever farm is
// selected, using coordinates manually entered in Farm Master -
// deliberately not device GPS. A farm with no coordinates set is
// excluded from the picker entirely rather than shown with an error,
// since there's nothing useful to show for it here.

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
  static const baseUrl = AppConfig.apiBaseUrl;

  Future<Map<String, String>> get _headers async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${prefs.getString('token') ?? ''}',
      'ngrok-skip-browser-warning': 'true',
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
                                .map(_dailyRow),
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

  Widget _dailyRow(Map<String, dynamic> day) {
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
      ]),
    );
  }
}
