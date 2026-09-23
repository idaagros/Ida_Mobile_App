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

import '../config/app_config.dart';

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
  static const apiBase = AppConfig.apiBaseUrl;
  static const assetBase = AppConfig
      .apiHost; // apiBase without /api - where /uploads/... images are served from

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
    final ndviVerdict = _interpretNdvi(ndvi);
    final ndmiRaw = snapshot!['ndmi_mean'];
    final ndmi = ndmiRaw == null ? null : double.tryParse(ndmiRaw.toString());
    final ndmiVerdict = ndmi == null ? null : _interpretNdmi(ndmi);
    return _Card(
      title: 'VEGETATION HEALTH',
      onDetails: () =>
          _showDetailModal(context, 'Vegetation Health — Details', [
        _DetailEntry('NDVI: ${ndvi.toStringAsFixed(2)} (${ndviVerdict.label})',
            ndviVerdict.detail),
        if (ndmiVerdict != null)
          _DetailEntry(
              'Moisture index (NDMI): ${ndmi!.toStringAsFixed(2)} (${ndmiVerdict.label})',
              ndmiVerdict.detail),
      ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(ndvi.toStringAsFixed(2),
              style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: ndviVerdict.color)),
          const SizedBox(width: 6),
          const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text('NDVI',
                  style: TextStyle(fontSize: 11, color: Colors.grey))),
        ]),
        Text(ndviVerdict.label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: ndviVerdict.color)),
        const SizedBox(height: 8),
        _kv('Range this period',
            '${_fmt(snapshot!['ndvi_min'])} – ${_fmt(snapshot!['ndvi_max'])}'),
        if (ndmi != null) _kv('Moisture index (NDMI)', ndmi.toStringAsFixed(2)),
        _kv('Cloud cover', '${snapshot!['cloud_pct']}%'),
        _kv('Imagery date', '${snapshot!['snapshot_date']}'),
      ]),
    );
  }

  static String _fmt(dynamic v) => v == null
      ? '—'
      : (double.tryParse(v.toString())?.toStringAsFixed(2) ?? v.toString());

  static _Verdict _interpretNdvi(double ndvi) {
    if (ndvi < 0.1)
      return _Verdict(
          'Bare soil / no vegetation',
          const Color(0xFFA8A29E),
          const _Detail(
            "NDVI near zero indicates bare soil or essentially no live vegetation cover in this reading.",
            "If a crop should be growing at this time, this points to a failed stand, very early growth stage, or a recently harvested/fallow field — it isn't itself a health problem unless a crop was expected to already be well-established.",
            [
              "If a crop was recently sown, this is likely just too early for a reading — vegetation index checks are most useful from a few weeks after emergence onward.",
              "If a stand should already exist and doesn't, check the field itself for germination failure, waterlogging, or seedling-stage pest damage — the satellite reading can flag the problem but not diagnose the specific cause.",
            ],
          ));
    if (ndvi < 0.3)
      return _Verdict(
          'Sparse or stressed vegetation',
          const Color(0xFFF47D1E),
          const _Detail(
            "Low-to-moderate NDVI suggests sparse crop cover or vegetation under stress.",
            "This range often reflects early growth stage, patchy germination, water stress, nutrient deficiency, or pest/disease pressure reducing canopy cover.",
            [
              "Walk the field to check for a specific cause — uneven germination, waterlogging, visible pest/disease symptoms, or nutrient deficiency signs (yellowing, stunting).",
              "If early in the season, this may simply be normal for the crop's current growth stage — compare against the NDVI Trend chart rather than judging off one reading.",
              "If the crop is irrigation-dependent and rainfall/irrigation has been short recently, this is a common signature of water stress.",
            ],
          ));
    if (ndvi < 0.5)
      return _Verdict(
          'Moderate vegetation vigor',
          const Color(0xFFEAB308),
          const _Detail(
            "Moderate NDVI indicates a developing, reasonably healthy canopy — not yet at peak vigor.",
            "This is often just where a crop sits mid-season before full canopy closure, but it's also consistent with mild nutrient or water stress holding growth back.",
            [
              "Compare against the NDVI Trend chart — if it's climbing over recent readings, this is likely normal seasonal development, not a problem.",
              "If it's flat or declining, check nitrogen nutrition and the irrigation schedule.",
            ],
          ));
    if (ndvi < 0.7)
      return _Verdict(
          'Healthy, dense vegetation',
          const Color(0xFF659442),
          const _Detail(
            "This NDVI range reflects a healthy, well-developed crop canopy.",
            "Vegetation is growing vigorously with good canopy cover — generally a positive sign for the season.",
            ["No action needed — continue current management."],
          ));
    return _Verdict(
        'Very dense, vigorous vegetation',
        const Color(0xFF253917),
        const _Detail(
          "This is the highest NDVI band — very dense, vigorous vegetation.",
          "Usually excellent crop health. In a few crops, however, an extremely dense canopy late in the season can mean excess vegetative growth at the expense of yield (e.g. too much nitrogen pushing leaf growth over grain/fruit fill), so it's worth knowing the crop's normal pattern at this growth stage.",
          [
            "Generally no action needed.",
            "For crops prone to excess vegetative growth (e.g. cotton), confirm this dense canopy timing matches the crop's expected growth stage rather than an unusually late-season nitrogen-driven flush.",
          ],
        ));
  }

  static _Verdict _interpretNdmi(double ndmi) {
    if (ndmi > 0.4)
      return _Verdict(
          'High canopy moisture',
          const Color(0xFF659442),
          const _Detail(
            "High NDMI — the canopy is carrying a lot of water.",
            "Usually a good sign of well-watered vegetation, though a very high value right after heavy rain can also just reflect standing water/waterlogging rather than healthy moisture inside the plant.",
            [
              "No action needed if this follows normal irrigation/rainfall.",
              "If it follows heavy rain, check for waterlogged patches in the field — that's a drainage issue NDMI alone can't distinguish from healthy moisture.",
            ],
          ));
    if (ndmi > 0.2)
      return _Verdict(
          'Adequate canopy moisture',
          const Color(0xFF88BA63),
          const _Detail(
            "Moderate NDMI — adequate canopy moisture.",
            "Vegetation moisture is in a comfortable range; not a cause for concern on its own.",
            ["No action needed."],
          ));
    if (ndmi > 0)
      return _Verdict(
          'Mild moisture stress',
          const Color(0xFFF47D1E),
          const _Detail(
            "Low-moderate NDMI — canopy moisture is on the lower side.",
            "Can indicate the start of water stress, especially if irrigation or rainfall has been irregular recently.",
            [
              "Check the field and irrigation schedule — if the next irrigation/rain is more than a few days out, consider moving it up.",
              "Cross-check against the NDVI reading — moisture stress showing up here often shows up as reduced NDVI soon after, if not addressed.",
            ],
          ));
    return _Verdict(
        'Significant moisture stress',
        const Color(0xFFDC2626),
        const _Detail(
          "Negative NDMI indicates significant canopy moisture stress.",
          "This is a fairly strong water-stress signal — expect visible wilting or leaf rolling in the field if this persists.",
          [
            "Irrigate as soon as practical if water is available.",
            "If this is unexpected (irrigation was recent), check for a blockage/failure in the irrigation system or root damage limiting water uptake, rather than assuming the field is simply dry.",
          ],
        ));
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
      onDetails: () => _showDetailModal(context, 'Soil Properties — Details', [
        for (final r in rows)
          if (r.detail != null)
            _DetailEntry(
                '${r.label}: ${r.value}${r.verdict != null ? ' (${r.verdict})' : ''}',
                r.detail!),
      ]),
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
    if (v == null) return _SoilRowData('pH (H₂O)', '—', null, null, null, null);
    String verdict;
    Color tone;
    String? note;
    _Detail detail;
    if (v < 5.5) {
      verdict = 'Acidic';
      tone = Colors.red;
      note = 'liming may help most field crops';
      detail = const _Detail(
        "Your soil is acidic — below the neutral point of 7.0.",
        "Below this level, aluminium and manganese can become soluble enough to be toxic to root growth, and phosphorus gets chemically locked up, so crops often show poor root development and nutrient deficiency despite fertilization.",
        [
          "Apply agricultural lime (calcium carbonate) — broadcast and incorporate before sowing; a heavier, high-CEC soil needs more lime to shift pH than a sandy soil.",
          "Use dolomitic lime instead if a soil test also shows low magnesium.",
          "Avoid acidifying fertilizers (ammonium sulphate, excess urea) until pH recovers — they push pH lower.",
          "Retest after a season, since lime reacts slowly.",
        ],
      );
    } else if (v < 6.5) {
      verdict = 'Slightly acidic';
      tone = Colors.orange;
      note = 'fine for most crops';
      detail = const _Detail(
        "Mildly acidic, on the safe side of neutral.",
        "Most crops handle this comfortably — nutrient availability is close to optimal in this band.",
        [
          "No correction generally needed.",
          "If growing a pH-sensitive crop, a light lime application can nudge it closer to neutral.",
          "Keep monitoring — continuous use of acidifying nitrogen fertilizers over years can push this lower.",
        ],
      );
    } else if (v < 7.5) {
      verdict = 'Neutral';
      tone = const Color(0xFF659442);
      note = 'ideal range for most field crops';
      detail = const _Detail(
        "Your soil is at or near the ideal pH — around 7.0 is perfectly neutral.",
        "Nutrient availability is at its best in this range; almost nothing is chemically locked up.",
        [
          "No correction needed.",
          "Maintain organic matter inputs (FYM/compost) to keep this stable long-term."
        ],
      );
    } else if (v <= 8.5) {
      verdict = 'Slightly alkaline';
      tone = Colors.orange;
      note = 'watch zinc/iron availability over time';
      detail = const _Detail(
        "Your soil is mildly alkaline (7.0 is perfectly neutral).",
        "Most major crops tolerate this level well. However, some essential micronutrients like iron, zinc, and manganese start getting locked up in the soil, making them harder for plants to absorb.",
        [
          "Use acidifying fertilizers: when applying macronutrients, use nitrogen sources like ammonium sulphate or urea instead of calcium ammonium nitrate — these naturally lower pH right around the root zone.",
          "Apply elemental sulphur for a long-term fix — broadcast onto the field; soil bacteria slowly convert it to sulphuric acid, lowering the overall pH. (A high-CEC soil needs more sulphur than a sandy soil to shift pH by the same amount.)",
          "Use chelated micronutrients — if crops show yellowing leaves (micronutrient deficiency), apply micronutrients in chelated form or as foliar sprays so the plant bypasses the alkaline soil entirely.",
        ],
      );
    } else {
      verdict = 'Alkaline';
      tone = Colors.red;
      note = 'can limit micronutrient uptake';
      detail = const _Detail(
        "Your soil is strongly alkaline.",
        "At this level, iron, zinc, manganese and phosphorus availability drops sharply — expect visible micronutrient deficiency symptoms (interveinal yellowing) even with normal fertilization, and some crops may struggle to establish at all.",
        [
          "Apply elemental sulphur or gypsum (gypsum helps more where sodium is also a problem) — this is a slow, multi-season correction, not a quick fix.",
          "Lean on foliar/chelated micronutrient sprays every season until soil pH comes down, since root uptake will stay poor in the meantime.",
          "Improve drainage — high alkalinity is often paired with poor drainage/salt accumulation in this region; ensure fields aren't waterlogged after irrigation.",
          "Consider a proper soil test to check for a sodicity problem (high exchangeable sodium), which needs a different remedy (gypsum) than plain alkalinity.",
        ],
      );
    }
    return _SoilRowData('pH (H₂O)', v.toString(), verdict, tone, note, detail);
  }

  static _SoilRowData _interpretOrganicCarbon(dynamic raw) {
    final v = raw == null ? null : double.tryParse(raw.toString());
    if (v == null)
      return _SoilRowData('Organic carbon', '—', null, null, null, null);
    String verdict;
    Color tone;
    String? note;
    _Detail detail;
    if (v < 5) {
      verdict = 'Low';
      tone = Colors.red;
      note = 'consider FYM/compost to build fertility';
      detail = const _Detail(
        "Your soil's organic carbon reserve is low.",
        "Low organic carbon means poor natural fertility, weaker water-holding capacity, and less microbial activity — you'll depend more heavily on chemical fertilizer for the same yield, and the soil will dry out faster between irrigations/rain.",
        [
          "Apply farmyard manure (FYM) or compost every season — this is the single biggest lever for organic carbon.",
          "Incorporate crop residue instead of burning it — residue burning is exactly what keeps organic carbon low.",
          "Consider green manuring (e.g. dhaincha, sunhemp) ploughed in before the main crop.",
          "Reduce tillage where practical — organic carbon breaks down faster under heavy, repeated tillage.",
        ],
      );
    } else if (v < 7.5) {
      verdict = 'Medium';
      tone = Colors.orange;
      note = null;
      detail = const _Detail(
        "Your soil's organic carbon is in a moderate, workable range.",
        "Fertility is reasonable but not a strong buffer — yields depend more on season-to-season fertilizer management.",
        [
          "Keep up regular FYM/compost applications to build this further rather than let it plateau.",
          "Continue residue incorporation."
        ],
      );
    } else {
      verdict = 'High';
      tone = const Color(0xFF659442);
      note = 'good fertility reserve';
      detail = const _Detail(
        "Your soil has a strong organic carbon reserve.",
        "Good natural fertility, better water-holding capacity, and more resilient microbial activity — this soil buffers fertilizer mistakes better than most.",
        [
          "Maintain current organic matter practices — this is a genuine asset, worth protecting rather than mining through continuous heavy tillage."
        ],
      );
    }
    return _SoilRowData(
        'Organic carbon', '$v g/kg', verdict, tone, note, detail);
  }

  static _SoilRowData _interpretNitrogen(dynamic raw) {
    final v = raw == null ? null : double.tryParse(raw.toString());
    if (v == null)
      return _SoilRowData('Nitrogen (total)', '—', null, null, null, null);
    String verdict;
    Color tone;
    _Detail detail;
    if (v < 0.5) {
      verdict = 'Low reserve';
      tone = Colors.red;
      detail = const _Detail(
        "Total nitrogen reserve in the soil is low.",
        "This measures the soil's total nitrogen stock, not what's immediately available this season — but a low reserve generally means the field depends almost entirely on applied fertilizer for nitrogen, with little natural buffering.",
        [
          "Follow the full recommended nitrogen dose for the crop — don't cut corners assuming residual nitrogen is present.",
          "Split nitrogen doses across growth stages instead of one large basal dose — this reduces leaching loss and matches a low-reserve soil better.",
          "Build organic matter over time (FYM, green manure) — this is what actually raises the total reserve, not a single season of fertilizer.",
        ],
      );
    } else if (v < 1.5) {
      verdict = 'Medium reserve';
      tone = Colors.orange;
      detail = const _Detail(
        "Total nitrogen reserve is moderate.",
        "Reasonable natural nitrogen supply, but still needs full seasonal fertilization for good yields — don't rely on this reserve alone.",
        [
          "Standard recommended nitrogen dose for the crop is fine; no special adjustment needed."
        ],
      );
    } else {
      verdict = 'High reserve';
      tone = const Color(0xFF659442);
      detail = const _Detail(
        "Total nitrogen reserve is strong.",
        "Good natural nitrogen supply — some crops (especially after a legume rotation) may need slightly less applied nitrogen than the standard recommendation.",
        [
          "Consider a soil/tissue test before the season to fine-tune down from standard fertilizer doses — over-applying nitrogen on an already-rich soil wastes money and can encourage lodging/excess vegetative growth in some crops."
        ],
      );
    }
    return _SoilRowData(
        'Nitrogen (total)', '$v g/kg', verdict, tone, null, detail);
  }

  static _SoilRowData _interpretCec(dynamic raw) {
    final v = raw == null ? null : double.tryParse(raw.toString());
    if (v == null) return _SoilRowData('CEC', '—', null, null, null, null);
    String verdict;
    Color tone;
    String? note;
    _Detail detail;
    if (v < 10) {
      verdict = 'Low';
      tone = Colors.red;
      note = 'nutrients leach fast — fertilize little and often';
      detail = const _Detail(
        "Cation exchange capacity (CEC) is low — this is the soil's ability to hold onto and supply positively-charged nutrients (potassium, calcium, magnesium, ammonium) against leaching.",
        "A low-CEC soil loses nutrients to leaching quickly after heavy rain or irrigation, even when enough fertilizer has been applied — fertilizer can seem to \"not work as well\" as expected.",
        [
          "Fertilize in smaller, more frequent doses instead of one large application — matches how little the soil can hold at once.",
          "Build organic matter (FYM/compost) — organic matter itself contributes significant CEC, so this is a long-term fix as well as a fertility one.",
          "Avoid heavy fertilizer application right before expected heavy rain.",
        ],
      );
    } else if (v < 25) {
      verdict = 'Medium';
      tone = Colors.orange;
      note = null;
      detail = const _Detail(
        "CEC is in a moderate, workable range.",
        "Reasonable nutrient-holding capacity — standard fertilizer scheduling should work without major losses.",
        ["No special adjustment needed; continue normal practice."],
      );
    } else {
      verdict = 'High';
      tone = const Color(0xFF659442);
      note = 'holds nutrients well, less leaching';
      detail = const _Detail(
        "CEC is high — this soil holds onto nutrients well.",
        "Less nutrient loss to leaching, so fertilizer applications are used more efficiently — but a high-CEC soil (usually with heavier clay content) also needs proportionally more lime or sulphur to shift its pH than a lighter soil, since it \"holds onto\" its current pH too.",
        [
          "Standard fertilizer scheduling is fine.",
          "If also correcting pH (liming or sulphur), budget for a larger quantity than a generic recommendation assumes, precisely because of this high CEC.",
        ],
      );
    }
    return _SoilRowData('CEC', '$v cmol/kg', verdict, tone, note, detail);
  }

  static _SoilRowData _interpretBulkDensity(dynamic raw) {
    final v = raw == null ? null : double.tryParse(raw.toString());
    if (v == null)
      return _SoilRowData('Bulk density', '—', null, null, null, null);
    String verdict;
    Color tone;
    String? note;
    _Detail detail;
    if (v < 1.3) {
      verdict = 'Loose / well-aerated';
      tone = const Color(0xFF659442);
      note = null;
      detail = const _Detail(
        "Soil bulk density is low — the soil is loose and well-aerated.",
        "Good for root penetration and water infiltration; generally a favorable sign, though very low density can occasionally mean weaker structural stability in a sandy soil.",
        ["No correction needed for most crops."],
      );
    } else if (v <= 1.6) {
      verdict = 'Normal for cultivated soil';
      tone = Colors.orange;
      note = null;
      detail = const _Detail(
        "Bulk density is in the normal range for cultivated soil.",
        "Roots and water should move through this soil without much resistance.",
        ["No correction needed; maintain current tillage practice."],
      );
    } else {
      verdict = 'Compacted';
      tone = Colors.red;
      note =
          'may restrict roots/water — deep tillage or organic matter can help';
      detail = const _Detail(
        "Bulk density is high — the soil is compacted.",
        "Compacted soil restricts root penetration and water infiltration, which can show up as stunted growth, waterlogged patches after rain, and poor response to fertilizer (since roots can't reach it).",
        [
          "Deep tillage (subsoiling/chiseling) before the next season to break up the compacted layer — most effective when the soil is at the right moisture (not too wet, not bone dry).",
          "Build organic matter over time (FYM/compost, green manure, residue incorporation) — this is the long-term fix; deep tillage alone re-compacts within a season or two without it.",
          "Avoid field traffic (tractor, tillage implements) when the soil is wet — this is usually what causes compaction in the first place.",
        ],
      );
    }
    return _SoilRowData(
        'Bulk density', '$v g/cm³', verdict, tone, note, detail);
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
      return _SoilRowData('Texture', '—', null, null, null, null);
    final value = 'Clay ${clay}% · Sand ${sand}% · Silt ${_n(silt)}%';
    if (clay >= 40) {
      return _SoilRowData(
          'Texture',
          value,
          'Clayey (heavy soil)',
          Colors.blueGrey,
          'holds water/nutrients well but drains slowly — matches typical Vidarbha black-cotton soil; watch waterlogging in monsoon',
          const _Detail(
            "Your soil is clay-heavy — this matches the typical Vidarbha black-cotton soil profile.",
            "Clayey soil holds water and nutrients well (a good nutrient reserve) but drains slowly, so it's prone to waterlogging in heavy monsoon spells and can crack and become hard to work when it dries out.",
            [
              "Ensure field drainage channels are clear before monsoon — waterlogging is the main risk with this texture, not dryness.",
              "Avoid working the field (tillage, sowing) when it's too wet — clayey soil compacts badly under machinery/bullock traffic at the wrong moisture.",
              "Add organic matter (FYM/compost) over time — it improves clay soil's structure and workability without changing its water-holding strength.",
              "Time irrigation carefully — this soil holds moisture longer than most, so over-irrigating is a common mistake here.",
            ],
          ));
    }
    if (sand >= 60) {
      return _SoilRowData(
          'Texture',
          value,
          'Sandy (light soil)',
          Colors.blueGrey,
          'drains fast — water and fertilize in smaller, more frequent doses',
          const _Detail(
            "Your soil is sandy — light and fast-draining.",
            "Water and nutrients move through sandy soil quickly, so both dry out and leach away faster than in a clay or loam soil — expect more frequent irrigation and fertilizer needs.",
            [
              "Water and fertilize in smaller, more frequent doses rather than large infrequent ones — big doses leach straight through before the crop can use them.",
              "Build organic matter (FYM/compost) — this is the most effective way to improve a sandy soil's water and nutrient holding capacity over time.",
              "Mulch to help retain soil moisture between irrigations.",
            ],
          ));
    }
    return _SoilRowData(
        'Texture',
        value,
        'Loamy (balanced)',
        const Color(0xFF659442),
        'generally easy to manage for most crops',
        const _Detail(
          "Your soil has a balanced loamy texture.",
          "This is generally the easiest texture to manage — reasonable water retention without the drainage problems of clay or the leaching problems of sand.",
          [
            "Standard irrigation and fertilizer scheduling for the crop should work well; no texture-driven adjustment needed."
          ],
        ));
  }
}

class _SoilRowData {
  final String label;
  final String value;
  final String? verdict;
  final Color? tone;
  final String? note;
  final _Detail? detail;
  _SoilRowData(
      this.label, this.value, this.verdict, this.tone, this.note, this.detail);
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
  final VoidCallback? onDetails;
  const _Card(
      {required this.title,
      this.subtitle,
      required this.child,
      this.onDetails});

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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: Color(0xFF6B7280))),
            if (onDetails != null)
              OutlinedButton(
                onPressed: onDetails,
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  side: const BorderSide(color: Color(0x6688BA63)),
                ),
                child: const Text('Details',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF659442))),
              ),
          ],
        ),
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

// ── Detail modal (Vegetation Health / Soil Properties "Details" button) ──
// A plain-language meaning/impact/remedy breakdown for whichever
// reading(s) a card is currently showing, matched to the same range
// bands used for the compact verdict/tone shown inline in the card.
class _Detail {
  final String meaning;
  final String impact;
  final List<String> remedy;
  const _Detail(this.meaning, this.impact, this.remedy);
}

class _Verdict {
  final String label;
  final Color color;
  final _Detail detail;
  const _Verdict(this.label, this.color, this.detail);
}

class _DetailEntry {
  final String label;
  final _Detail detail;
  const _DetailEntry(this.label, this.detail);
}

void _showDetailModal(
    BuildContext context, String title, List<_DetailEntry> entries) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF253917)))),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: entries.isEmpty
                  ? const Text('No details available yet.',
                      style: TextStyle(fontSize: 12, color: Colors.grey))
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const Divider(height: 26),
                      itemBuilder: (_, i) => _DetailSection(entry: entries[i]),
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DetailSection extends StatelessWidget {
  final _DetailEntry entry;
  const _DetailSection({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(entry.label,
            style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF253917))),
        const SizedBox(height: 6),
        RichText(
            text: TextSpan(
                style: const TextStyle(
                    fontSize: 12, color: Colors.black87, height: 1.45),
                children: [
              const TextSpan(
                  text: 'What it means: ',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: Colors.grey)),
              TextSpan(text: entry.detail.meaning),
            ])),
        const SizedBox(height: 6),
        RichText(
            text: TextSpan(
                style: const TextStyle(
                    fontSize: 12, color: Colors.black87, height: 1.45),
                children: [
              const TextSpan(
                  text: 'Impact: ',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: Colors.grey)),
              TextSpan(text: entry.detail.impact),
            ])),
        if (entry.detail.remedy.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(entry.detail.remedy.length > 1 ? 'The remedy:' : 'Remedy:',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey)),
          const SizedBox(height: 4),
          for (final r in entry.detail.remedy)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('•  ',
                    style: TextStyle(fontSize: 12, color: Colors.black87)),
                Expanded(
                    child: Text(r,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black87, height: 1.4))),
              ]),
            ),
        ],
      ],
    );
  }
}
