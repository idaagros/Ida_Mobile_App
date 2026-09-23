// lib/screens/farm_boundary_map_screen.dart
//
// Draw or edit a farm's boundary on the phone, tap by tap - the mobile
// counterpart of the web app's FarmBoundaryMap.jsx (which uses Leaflet
// + Leaflet-Geoman). flutter_map has no equivalent polygon-drawing
// plugin worth depending on, so this hand-rolls the same simple
// pattern instead: tap the map to drop a point, see the shape build up
// live, Undo/Clear/Save. That mirrors what the web version does under
// the hood anyway.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/geo_utils.dart';

import '../config/app_config.dart';
class FarmBoundaryMapScreen extends StatefulWidget {
  final int farmId;
  final String farmName;
  final double? gpsLat;
  final double? gpsLong;
  final Map<String, dynamic>? existingBoundaryGeojson;

  const FarmBoundaryMapScreen({
    super.key,
    required this.farmId,
    required this.farmName,
    this.gpsLat,
    this.gpsLong,
    this.existingBoundaryGeojson,
  });

  @override
  State<FarmBoundaryMapScreen> createState() => _FarmBoundaryMapScreenState();
}

class _FarmBoundaryMapScreenState extends State<FarmBoundaryMapScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const baseUrl = AppConfig.apiBaseUrl;
  static const _defaultCenter = ll.LatLng(21.0, 77.75); // Amravati district, Maharashtra fallback

  final _mapController = MapController();
  final List<ll.LatLng> _points = [];
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingBoundaryGeojson;
    if (existing != null && existing['coordinates'] != null) {
      final ring = (existing['coordinates'] as List)[0] as List;
      for (final c in ring) {
        final lng = (c[0] as num).toDouble();
        final lat = (c[1] as num).toDouble();
        // Skip the closing point if the stored ring is explicitly
        // closed (first == last) - editing an already-closed ring
        // should still just be an editable list of its real corners.
        if (_points.isNotEmpty && _points.first.latitude == lat && _points.first.longitude == lng) continue;
        _points.add(ll.LatLng(lat, lng));
      }
    }
  }

  Future<Map<String, String>> get _headers async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${prefs.getString('token') ?? ''}',
      'ngrok-skip-browser-warning': 'true',
    };
  }

  double get _areaAcres {
    if (_points.length < 3) return 0;
    return polygonAreaAcres(_points.map((p) => [p.longitude, p.latitude]).toList());
  }

  void _undo() {
    if (_points.isNotEmpty) setState(() => _points.removeLast());
  }

  void _clear() {
    setState(() => _points.clear());
  }

  Future<void> _save() async {
    if (_points.length < 3) return;
    setState(() { _saving = true; _error = null; });
    final ring = _points.map((p) => [p.longitude, p.latitude]).toList();
    ring.add(ring.first); // close the ring - standard GeoJSON practice
    final geojson = {'type': 'Polygon', 'coordinates': [ring]};
    try {
      final h = await _headers;
      final res = await http.patch(
        Uri.parse('$baseUrl/farms/${widget.farmId}/boundary'),
        headers: {...h, 'Content-Type': 'application/json'},
        body: jsonEncode({'geojson': geojson}),
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        if (mounted) Navigator.pop(context, true);
      } else {
        setState(() => _error = data['error'] ?? 'Failed to save boundary');
      }
    } catch (e) {
      setState(() => _error = 'Could not reach server: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final center = widget.gpsLat != null && widget.gpsLong != null
        ? ll.LatLng(widget.gpsLat!, widget.gpsLong!)
        : (_points.isNotEmpty ? _points.first : _defaultCenter);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('Draw boundary — ${widget.farmName}',
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
      ),
      body: Column(children: [
        Container(
          width: double.infinity,
          color: idaDark,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Text(
            _points.length < 3
                ? 'Tap the map to drop corners around the field (${_points.length} point${_points.length == 1 ? '' : 's'} so far).'
                : 'Drawn area: ${_areaAcres.toStringAsFixed(2)} acres — keep tapping to add more corners, or Save.',
            style: const TextStyle(color: Colors.white70, fontSize: 12.5),
          ),
        ),
        if (_error != null)
          Container(
            width: double.infinity,
            color: Colors.red.shade50,
            padding: const EdgeInsets.all(10),
            child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12.5)),
          ),
        Expanded(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: widget.gpsLat != null ? 16 : 12,
              onTap: (tapPosition, point) => setState(() => _points.add(point)),
            ),
            children: [
              TileLayer(
                // Esri World Imagery - free satellite basemap, no API key -
                // same tile source the web app uses.
                urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                userAgentPackageName: 'com.ida.agrico',
              ),
              if (_points.length >= 3)
                PolygonLayer(polygons: [
                  Polygon(
                    points: _points,
                    color: idaGreen.withOpacity(0.18),
                    borderColor: idaGreen,
                    borderStrokeWidth: 3,
                  ),
                ]),
              if (_points.length == 2)
                PolylineLayer(polylines: [
                  Polyline(points: _points, color: idaGreen, strokeWidth: 3),
                ]),
              MarkerLayer(
                markers: _points
                    .map((p) => Marker(
                          point: p,
                          width: 14,
                          height: 14,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: idaGreen, width: 2),
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _points.isEmpty ? null : _undo,
                  child: const Text('Undo'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _points.isEmpty ? null : _clear,
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Clear'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: (_points.length < 3 || _saving) ? null : _save,
                  style: ElevatedButton.styleFrom(backgroundColor: idaGreen),
                  child: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Save Boundary', style: TextStyle(color: Colors.white)),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
