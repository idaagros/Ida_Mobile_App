// lib/screens/farm_precision_ag_screen.dart
//
// Per-farm precision-agriculture view: boundary + field health map
// (colorized NDVI overlay), vegetation health verdict, NDVI trend, and
// soil properties with the same plain-language interpretation the web
// app shows. Mobile counterpart of webapp/src/pages/FarmPrecisionAg.jsx
// — reads the exact same /farms/:id/satellite endpoint, so the two
// stay in sync by construction rather than by copying logic twice and
// hoping they don't drift.
//
// `canEdit` (passed in from the dashboard tile, computed there via
// _canEdit('farm_masters')) gates drawing/editing the boundary and
// triggering a refresh — a view-only grant sees everything except
// those two actions, matching the same farm_masters permission model
// already used on web.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'farm_boundary_map_screen.dart';

class FarmPrecisionAgScreen extends StatefulWidget {
  final int farmId;
  final String farmName;
  final bool canEdit;
  const FarmPrecisionAgScreen(
      {super.key,
      required this.farmId,
      required this.farmName,
      required this.canEdit});

  @override
  State<FarmPrecisionAgScreen> createState() => _FarmPrecisionAgScreenState();
}

class _FarmPrecisionAgScreenState extends State<FarmPrecisionAgScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const apiBase = 'https://excusable-moving-preorder.ngrok-free.dev/api';
  static const assetBase =
      'https://excusable-moving-preorder.ngrok-free.dev'; // apiBase without /api - where /uploads/... images are served from

  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  String? _refreshNote;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, String>> get _headers async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${prefs.getString('token') ?? ''}',
      'ngrok-skip-browser-warning': 'true',
    };
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final h = await _headers;
      final res = await http.get(
          Uri.parse('$apiBase/farms/${widget.farmId}/satellite'),
          headers: h);
      if (res.statusCode == 200) {
        _data = jsonDecode(res.body);
      } else {
        _error =
            'Could not load precision agriculture data (${res.statusCode})';
      }
    } catch (e) {
      _error = 'Could not reach server: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _refreshing = true;
      _refreshNote = null;
    });
    try {
      final h = await _headers;
      final res = await http.post(
        Uri.parse('$apiBase/farms/${widget.farmId}/satellite/refresh'),
        headers: {...h, 'Content-Type': 'application/json'},
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        final errors = (data['errors'] as Map?) ?? {};
        _refreshNote = errors.isEmpty
            ? 'Analysis updated.'
            : errors.entries
                .map((e) => '${e.key.toString().toUpperCase()}: ${e.value}')
                .join(' · ');
      } else {
        _refreshNote = data['error'] ?? 'Refresh failed';
      }
      await _load();
    } catch (e) {
      setState(() => _refreshNote = 'Could not reach server: $e');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _openBoundaryDrawing() async {
    final farm = _data;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => FarmBoundaryMapScreen(
          farmId: widget.farmId,
          farmName: widget.farmName,
          existingBoundaryGeojson: farm?['boundary_geojson'] != null
              ? Map<String, dynamic>.from(farm!['boundary_geojson'])
              : null,
        ),
      ),
    );
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('🛰️ ${widget.farmName}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          if (widget.canEdit && _data?['boundary_geojson'] != null)
            IconButton(
              icon: _refreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.refresh),
              onPressed: _refreshing ? null : _refresh,
              tooltip: 'Refresh Analysis',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!,
                          style: const TextStyle(color: Colors.red))))
              : _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final data = _data!;
    final hasBoundary = data['boundary_geojson'] != null;

    if (!hasBoundary) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('📐', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 10),
            const Text('No boundary drawn yet',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              widget.canEdit
                  ? "Satellite and soil analysis needs this farm's actual shape, not just its GPS pin."
                  : "This farm's boundary hasn't been drawn yet. Ask an admin with Farm Masters edit access to draw it.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            if (widget.canEdit) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _openBoundaryDrawing,
                style: ElevatedButton.styleFrom(backgroundColor: idaGreen),
                child: const Text('Go draw a boundary',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ]),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        if (_refreshNote != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: const Color(0xFFFFF7E6),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF5D48A))),
            child: Text(_refreshNote!,
                style: const TextStyle(fontSize: 12, color: Color(0xFF8A6D1F))),
          ),
        _FieldHealthMapCard(
          data: data,
          idaGreen: idaGreen,
          assetBase: assetBase,
          canEdit: widget.canEdit,
          onEditBoundary: _openBoundaryDrawing,
        ),
        const SizedBox(height: 12),
        _VegetationHealthCard(snapshot: data['latest_ndvi']),
        const SizedBox(height: 12),
        _NdviTrendCard(history: (data['ndvi_history'] as List?) ?? []),
        const SizedBox(height: 12),
        _SoilCard(soil: data['soil']),
      ],
    );
  }
}

// ── Field Health Map ──────────────────────────────────────────────
class _FieldHealthMapCard extends StatelessWidget {
  final Map data;
  final Color idaGreen;
  final String assetBase;
  final bool canEdit;
  final VoidCallback onEditBoundary;
  const _FieldHealthMapCard(
      {required this.data,
      required this.idaGreen,
      required this.assetBase,
      required this.canEdit,
      required this.onEditBoundary});

  @override
  Widget build(BuildContext context) {
    final geojson = data['boundary_geojson'] as Map;
    final ring = (geojson['coordinates'] as List)[0] as List;
    final points = ring
        .map((c) =>
            ll.LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
        .toList();

    final latest = data['latest_ndvi'] as Map?;
    final heatmapPath = latest?['heatmap_path'] as String?;
    final heatmapBbox = latest?['heatmap_bbox'];

    double sumLat = 0, sumLng = 0;
    for (final p in points) {
      sumLat += p.latitude;
      sumLng += p.longitude;
    }
    final center = ll.LatLng(sumLat / points.length, sumLng / points.length);

    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0E7D8))),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
          child: Row(children: [
            const Expanded(
                child: Text('FIELD HEALTH MAP',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: Color(0xFF6B7280)))),
            if (canEdit)
              TextButton.icon(
                onPressed: onEditBoundary,
                icon: const Icon(Icons.edit, size: 14),
                label: const Text('Edit', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                    padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
              ),
            const SizedBox(width: 4),
            Text(
              data['boundary_area_acre'] != null
                  ? '${double.tryParse(data['boundary_area_acre'].toString())?.toStringAsFixed(2)} ac'
                  : '—',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ]),
        ),
        SizedBox(
          height: 240,
          child: FlutterMap(
            options: MapOptions(
                initialCenter: center,
                initialZoom: 15,
                interactionOptions:
                    const InteractionOptions(flags: InteractiveFlag.all)),
            children: [
              TileLayer(
                urlTemplate:
                    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                userAgentPackageName: 'com.ida.agrico',
              ),
              if (heatmapPath != null && heatmapBbox != null)
                OverlayImageLayer(overlayImages: [
                  OverlayImage(
                    bounds: LatLngBounds(
                      ll.LatLng((heatmapBbox[1] as num).toDouble(),
                          (heatmapBbox[0] as num).toDouble()),
                      ll.LatLng((heatmapBbox[3] as num).toDouble(),
                          (heatmapBbox[2] as num).toDouble()),
                    ),
                    imageProvider: NetworkImage('$assetBase$heatmapPath'),
                    opacity: 0.85,
                  ),
                ]),
              PolygonLayer(polygons: [
                Polygon(
                    points: points,
                    color: Colors.transparent,
                    borderColor: const Color(0xFFF47D1E),
                    borderStrokeWidth: 3),
              ]),
            ],
          ),
        ),
        if (heatmapPath != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            child: Row(children: [
              const Text('Stressed',
                  style: TextStyle(fontSize: 10, color: Colors.grey)),
              const SizedBox(width: 6),
              Expanded(
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: const LinearGradient(colors: [
                      Color(0xFF997545),
                      Color(0xFFD9B859),
                      Color(0xFFEED83D),
                      Color(0xFF8FBF45),
                      Color(0xFF177226)
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Text('Healthy',
                  style: TextStyle(fontSize: 10, color: Colors.grey)),
            ]),
          )
        else
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Text(
                'No field health image yet — refresh analysis to generate one (needs a cloud-free Sentinel-2 pass).',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
          ),
      ]),
    );
  }
}

// ── Vegetation Health ─────────────────────────────────────────────
class _VegetationHealthCard extends StatelessWidget {
  final Map? snapshot;
  const _VegetationHealthCard({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    if (snapshot == null) {
      return _Card(
          title: 'VEGETATION HEALTH',
          child: const Text(
              'No vegetation reading yet. Refresh above — if it stays empty, it\'s usually cloud cover.',
              style: TextStyle(fontSize: 12, color: Colors.grey)));
    }
    final ndvi = double.tryParse(snapshot!['ndvi_mean'].toString()) ?? 0;
    final (label, color) = _interpretNdvi(ndvi);
    return _Card(
      title: 'VEGETATION HEALTH',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(ndvi.toStringAsFixed(2),
              style: TextStyle(
                  fontSize: 30, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(width: 6),
          const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text('NDVI',
                  style: TextStyle(fontSize: 11, color: Colors.grey))),
        ]),
        Text(label,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 8),
        _kv('Range this period',
            '${_fmt(snapshot!['ndvi_min'])} – ${_fmt(snapshot!['ndvi_max'])}'),
        if (snapshot!['ndmi_mean'] != null)
          _kv('Moisture index (NDMI)', _fmt(snapshot!['ndmi_mean'])),
        _kv('Cloud cover', '${snapshot!['cloud_pct']}%'),
        _kv('Imagery date', '${snapshot!['snapshot_date']}'),
      ]),
    );
  }

  static String _fmt(dynamic v) => v == null
      ? '—'
      : (double.tryParse(v.toString())?.toStringAsFixed(2) ?? v.toString());

  static (String, Color) _interpretNdvi(double ndvi) {
    if (ndvi < 0.1)
      return ('Bare soil / no vegetation', const Color(0xFFA8A29E));
    if (ndvi < 0.3)
      return ('Sparse or stressed vegetation', const Color(0xFFF47D1E));
    if (ndvi < 0.5)
      return ('Moderate vegetation vigor', const Color(0xFFEAB308));
    if (ndvi < 0.7)
      return ('Healthy, dense vegetation', const Color(0xFF659442));
    return ('Very dense, vigorous vegetation', const Color(0xFF253917));
  }
}

// ── NDVI trend ─────────────────────────────────────────────────────
class _NdviTrendCard extends StatelessWidget {
  final List history;
  const _NdviTrendCard({required this.history});

  @override
  Widget build(BuildContext context) {
    final points = history
        .where((h) => h['ndvi_mean'] != null)
        .map((h) => double.tryParse(h['ndvi_mean'].toString()) ?? 0.0)
        .toList();

    return _Card(
      title: 'NDVI TREND',
      child: points.length < 2
          ? const Text('Need at least two refreshes over time to show a trend.',
              style: TextStyle(fontSize: 12, color: Colors.grey))
          : SizedBox(
              height: 160,
              child: LineChart(LineChartData(
                minY: 0,
                maxY: 1,
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                titlesData: const FlTitlesData(
                  topTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                      sideTitles:
                          SideTitles(showTitles: true, reservedSize: 30)),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (var i = 0; i < points.length; i++)
                        FlSpot(i.toDouble(), points[i])
                    ],
                    isCurved: true,
                    color: const Color(0xFF659442),
                    barWidth: 2,
                    dotData: const FlDotData(show: true),
                  ),
                ],
              )),
            ),
    );
  }
}

// ── Soil properties (same interpretation bands as web) ────────────
class _SoilCard extends StatelessWidget {
  final Map? soil;
  const _SoilCard({required this.soil});

  @override
  Widget build(BuildContext context) {
    if (soil == null) {
      return _Card(
          title: 'SOIL PROPERTIES',
          child: const Text('No soil data yet — refresh analysis above.',
              style: TextStyle(fontSize: 12, color: Colors.grey)));
    }
    final rows = <_SoilRowData>[
      _interpretPh(soil!['ph_h2o']),
      _interpretOrganicCarbon(soil!['organic_carbon_g_kg']),
      _interpretNitrogen(soil!['nitrogen_g_kg']),
      _interpretTexture(soil!),
      _interpretCec(soil!['cec_cmol_kg']),
      _interpretBulkDensity(soil!['bulk_density_kg_m3']),
    ];
    return _Card(
      title: 'SOIL PROPERTIES',
      subtitle:
          'Modeled (SoilGrids, 250m resolution, topsoil 0–5cm) — a lab soil test will be more precise for this exact field',
      child: Column(children: [
        for (final r in rows) _SoilRow(data: r),
        const Divider(height: 20),
        const Text(
          "SoilGrids doesn't report phosphorus or potassium, and its \"nitrogen\" is total nitrogen, not the plant-available nitrogen a Soil Health Card gives. For an actual fertilizer dose, a lab or Soil Health Card test is still the right tool.",
          style: TextStyle(fontSize: 10.5, color: Colors.grey),
        ),
      ]),
    );
  }

  static String _n(dynamic v) => v == null ? '—' : v.toString();

  static _SoilRowData _interpretPh(dynamic raw) {
    final v = raw == null ? null : double.tryParse(raw.toString());
    if (v == null) return _SoilRowData('pH (H₂O)', '—', null, null, null);
    String verdict;
    Color tone;
    String? note;
    if (v < 5.5) {
      verdict = 'Acidic';
      tone = Colors.red;
      note = 'liming may help most field crops';
    } else if (v < 6.5) {
      verdict = 'Slightly acidic';
      tone = Colors.orange;
      note = 'fine for most crops';
    } else if (v <= 7.5) {
      verdict = 'Neutral';
      tone = const Color(0xFF659442);
      note = 'ideal range for most field crops';
    } else if (v <= 8.5) {
      verdict = 'Slightly alkaline';
      tone = Colors.orange;
      note = 'watch zinc/iron availability over time';
    } else {
      verdict = 'Alkaline';
      tone = Colors.red;
      note = 'can limit micronutrient uptake';
    }
    return _SoilRowData('pH (H₂O)', v.toString(), verdict, tone, note);
  }

  static _SoilRowData _interpretOrganicCarbon(dynamic raw) {
    final v = raw == null ? null : double.tryParse(raw.toString());
    if (v == null) return _SoilRowData('Organic carbon', '—', null, null, null);
    String verdict;
    Color tone;
    String? note;
    if (v < 5) {
      verdict = 'Low';
      tone = Colors.red;
      note = 'consider FYM/compost to build fertility';
    } else if (v < 7.5) {
      verdict = 'Medium';
      tone = Colors.orange;
      note = null;
    } else {
      verdict = 'High';
      tone = const Color(0xFF659442);
      note = 'good fertility reserve';
    }
    return _SoilRowData('Organic carbon', '$v g/kg', verdict, tone, note);
  }

  static _SoilRowData _interpretNitrogen(dynamic raw) {
    final v = raw == null ? null : double.tryParse(raw.toString());
    if (v == null)
      return _SoilRowData('Nitrogen (total)', '—', null, null, null);
    String verdict;
    Color tone;
    if (v < 0.5) {
      verdict = 'Low reserve';
      tone = Colors.red;
    } else if (v < 1.5) {
      verdict = 'Medium reserve';
      tone = Colors.orange;
    } else {
      verdict = 'High reserve';
      tone = const Color(0xFF659442);
    }
    return _SoilRowData('Nitrogen (total)', '$v g/kg', verdict, tone, null);
  }

  static _SoilRowData _interpretCec(dynamic raw) {
    final v = raw == null ? null : double.tryParse(raw.toString());
    if (v == null) return _SoilRowData('CEC', '—', null, null, null);
    String verdict;
    Color tone;
    String? note;
    if (v < 10) {
      verdict = 'Low';
      tone = Colors.red;
      note = 'nutrients leach fast — fertilize little and often';
    } else if (v < 25) {
      verdict = 'Medium';
      tone = Colors.orange;
      note = null;
    } else {
      verdict = 'High';
      tone = const Color(0xFF659442);
      note = 'holds nutrients well, less leaching';
    }
    return _SoilRowData('CEC', '$v cmol/kg', verdict, tone, note);
  }

  static _SoilRowData _interpretBulkDensity(dynamic raw) {
    final v = raw == null ? null : double.tryParse(raw.toString());
    if (v == null) return _SoilRowData('Bulk density', '—', null, null, null);
    String verdict;
    Color tone;
    String? note;
    if (v < 1.3) {
      verdict = 'Loose / well-aerated';
      tone = const Color(0xFF659442);
      note = null;
    } else if (v <= 1.6) {
      verdict = 'Normal for cultivated soil';
      tone = Colors.orange;
      note = null;
    } else {
      verdict = 'Compacted';
      tone = Colors.red;
      note =
          'may restrict roots/water — deep tillage or organic matter can help';
    }
    return _SoilRowData('Bulk density', '$v g/cm³', verdict, tone, note);
  }

  static _SoilRowData _interpretTexture(Map soil) {
    final clay = soil['clay_pct'] == null
        ? null
        : double.tryParse(soil['clay_pct'].toString());
    final sand = soil['sand_pct'] == null
        ? null
        : double.tryParse(soil['sand_pct'].toString());
    final silt = soil['silt_pct'];
    if (clay == null || sand == null)
      return _SoilRowData('Texture', '—', null, null, null);
    final value = 'Clay ${clay}% · Sand ${sand}% · Silt ${_n(silt)}%';
    if (clay >= 40)
      return _SoilRowData(
          'Texture',
          value,
          'Clayey (heavy soil)',
          Colors.blueGrey,
          'holds water/nutrients well but drains slowly — matches typical Vidarbha black-cotton soil; watch waterlogging in monsoon');
    if (sand >= 60)
      return _SoilRowData(
          'Texture',
          value,
          'Sandy (light soil)',
          Colors.blueGrey,
          'drains fast — water and fertilize in smaller, more frequent doses');
    return _SoilRowData('Texture', value, 'Loamy (balanced)',
        const Color(0xFF659442), 'generally easy to manage for most crops');
  }
}

class _SoilRowData {
  final String label;
  final String value;
  final String? verdict;
  final Color? tone;
  final String? note;
  _SoilRowData(this.label, this.value, this.verdict, this.tone, this.note);
}

class _SoilRow extends StatelessWidget {
  final _SoilRowData data;
  const _SoilRow({required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(data.label,
              style: const TextStyle(fontSize: 12.5, color: Colors.grey)),
          Text(data.value,
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
        ]),
        if (data.verdict != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 11),
                children: [
                  TextSpan(
                      text: data.verdict,
                      style: TextStyle(
                          color: data.tone, fontWeight: FontWeight.w700)),
                  if (data.note != null)
                    TextSpan(
                        text: ' — ${data.note}',
                        style: const TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          ),
      ]),
    );
  }
}

Widget _kv(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );

class _Card extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  const _Card({required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0E7D8))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: Color(0xFF6B7280))),
        if (subtitle != null)
          Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 6),
              child: Text(subtitle!,
                  style: const TextStyle(fontSize: 10, color: Colors.grey))),
        const SizedBox(height: 6),
        child,
      ]),
    );
  }
}
