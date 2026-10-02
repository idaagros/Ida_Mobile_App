// lib/screens/admin/farm_masters_screen.dart
//
// Admin-managed master data for the Farm Attendance module: Farms,
// Work Types, and Farm Workers — three simple lists switched via a
// segmented toggle rather than separate screens, since they're small
// and closely related (a worker picks a farm + work type from the
// other two). Same add/edit/activate-deactivate shape as
// parties_screen.dart / destinations_screen.dart, with a richer form
// for Farm Workers (wage, farm, work type, phone).

import 'dart:convert';
import 'package:flutter/material.dart';
import '../../localization/app_localizations.dart';
import '../../localization/transliterate.dart';
import '../face_enrollment_screen.dart';
import '../../services/responsive.dart';
import '../../services/api_client.dart';

class FarmMastersScreen extends StatefulWidget {
  const FarmMastersScreen({super.key});
  @override
  State<FarmMastersScreen> createState() => _FarmMastersScreenState();
}

enum _Tab { farms, workTypes, workers }

class _FarmMastersScreenState extends State<FarmMastersScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);

  _Tab _tab = _Tab.farms;
  bool loading = true;

  List farms = [];
  List workTypes = [];
  List workers = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => loading = true);
    try {
      final results = await Future.wait([
        Api.get('/farms?all=1'),
        Api.get('/work-types'),
        Api.get('/farm-workers?all=1'),
        Api.get('/face/status'),
      ]);
      if (results[0].statusCode == 200) farms = jsonDecode(results[0].body);
      if (results[1].statusCode == 200) workTypes = jsonDecode(results[1].body);
      if (results[2].statusCode == 200) {
        workers = jsonDecode(results[2].body);
        workers.sort((a, b) => (a['name'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo((b['name'] ?? '').toString().toLowerCase()));
      }
      // Face enrollment status is fetched separately (its own endpoint)
      // and merged in client-side — the farm-workers response itself
      // is untouched.
      if (results[3].statusCode == 200) {
        final enrolledIds = (jsonDecode(results[3].body) as List)
            .where((r) => r['enrolled'] == true)
            .map((r) => r['worker_id'])
            .toSet();
        for (final w in workers) {
          w['face_enrolled'] = enrolledIds.contains(w['id']);
        }
      }
    } catch (e) {
      debugPrint('Load error: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.red.shade700 : idaGreen,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
    ));
  }

  // ── Farms ──────────────────────────────────────────────────
  Future<void> _saveFarm({
    int? id,
    required String name,
    String? location,
    double? totalAreaAcre,
    String? irrigationType,
    String? surveyNumber,
    double? gpsLat,
    double? gpsLong,
    bool? sprinklerPossible,
  }) async {
    try {
      final body = {
        'name': name,
        'location': location,
        'total_area_acre': totalAreaAcre,
        'irrigation_type': irrigationType,
        'survey_number': surveyNumber,
        'gps_lat': gpsLat,
        'gps_long': gpsLong,
        // Oct 2026: shown on the owner's TV dashboard (water stress card)
        if (sprinklerPossible != null) 'sprinkler_possible': sprinklerPossible,
      };
      final res = id == null
          ? await Api.post('/farms', body: body)
          : await Api.patch('/farms/$id', body: body);
      if (res.statusCode == 200) {
        _loadAll();
      } else {
        _showSnack(Api.responseError(res), isError: true);
      }
    } catch (e) {
      _showSnack('Error: ${Api.errorText(e)}', isError: true);
    }
  }

  Future<void> _toggleFarmActive(Map farm) async {
    try {
      await Api.patch(
        '/farms/${farm['id']}',
        body: {'is_active': farm['is_active'] == 1 ? false : true},
      );
      _loadAll();
    } catch (e) {
      debugPrint('Toggle error: $e');
    }
  }

  // ── Work types ─────────────────────────────────────────────
  Future<void> _saveWorkType(
      {int? id,
      required String name,
      String appliesTo = 'both',
      List<String> detailOptions = const []}) async {
    try {
      final body = {
        'name': name,
        'applies_to': appliesTo,
        'detail_options': detailOptions,
      };
      final res = id == null
          ? await Api.post('/work-types', body: body)
          : await Api.patch('/work-types/$id', body: body);
      if (res.statusCode == 200) {
        _loadAll();
      } else {
        _showSnack(Api.responseError(res), isError: true);
      }
    } catch (e) {
      _showSnack('Error: ${Api.errorText(e)}', isError: true);
    }
  }

  // ── Farm workers ───────────────────────────────────────────
  Future<void> _saveWorker({
    int? id,
    required String name,
    required String dailyWage,
    int? workTypeId,
    int? farmId,
    String? phone,
    String? gender,
    bool? isPermanent,
  }) async {
    try {
      final body = {
        'name': name,
        'daily_wage': dailyWage,
        'work_type_id': workTypeId,
        'farm_id': farmId,
        'phone': phone,
        'gender': gender,
        if (isPermanent != null) 'is_permanent': isPermanent,
      };
      final res = id == null
          ? await Api.post('/farm-workers', body: body)
          : await Api.patch('/farm-workers/$id', body: body);
      if (res.statusCode == 200) {
        _loadAll();
      } else {
        _showSnack(Api.responseError(res), isError: true);
      }
    } catch (e) {
      _showSnack('Error: ${Api.errorText(e)}', isError: true);
    }
  }

  Future<void> _toggleWorkerActive(Map worker) async {
    try {
      await Api.patch(
        '/farm-workers/${worker['id']}',
        body: {'is_active': worker['is_active'] == 1 ? false : true},
      );
      _loadAll();
    } catch (e) {
      debugPrint('Toggle error: $e');
    }
  }

  // ── Dialogs ────────────────────────────────────────────────
  void _showFarmDialog({Map? farm}) {
    final loc = AppLocalizations.of(context)!;
    final nameCtrl = TextEditingController(text: farm?['name'] ?? '');
    final locCtrl = TextEditingController(text: farm?['location'] ?? '');
    final areaCtrl =
        TextEditingController(text: farm?['total_area_acre']?.toString() ?? '');
    final surveyCtrl =
        TextEditingController(text: farm?['survey_number'] ?? '');
    final gpsLatCtrl =
        TextEditingController(text: farm?['gps_lat']?.toString() ?? '');
    final gpsLongCtrl =
        TextEditingController(text: farm?['gps_long']?.toString() ?? '');
    String? irrigationType = '${farm?['irrigation_type'] ?? ''}'.isEmpty ? null : '${farm!['irrigation_type']}';
    bool sprinkler = farm?['sprinkler_possible'] == 1 || farm?['sprinkler_possible'] == true;
    // The website lets people type any irrigation text; keep such a value
    // as its own choice so the drop-down doesn't break.
    const knownIrrigation = ['rainfed', 'drip', 'flood', 'sprinkler'];
    final extraIrrigation = irrigationType != null && irrigationType.isNotEmpty && !knownIrrigation.contains(irrigationType) ? irrigationType : null;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(farm == null ? loc.faAddFarm : loc.faEditFarm,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: loc.faFarmNameLabel,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: locCtrl,
                decoration: InputDecoration(
                  labelText: loc.faLocationOptionalLabel,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: areaCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: loc.faTotalAreaLabel,
                  helperText:
                      'Used to track how much of this farm is currently sown/planted',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: irrigationType,
                decoration: InputDecoration(
                    labelText: 'Irrigation type (optional)',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
                items: [
                  const DropdownMenuItem(value: null, child: Text('—')),
                  const DropdownMenuItem(value: 'rainfed', child: Text('Rainfed')),
                  const DropdownMenuItem(value: 'drip', child: Text('Drip')),
                  const DropdownMenuItem(value: 'flood', child: Text('Flood')),
                  const DropdownMenuItem(
                      value: 'sprinkler', child: Text('Sprinkler')),
                  if (extraIrrigation != null)
                    DropdownMenuItem(value: extraIrrigation, child: Text(extraIrrigation)),
                ],
                onChanged: (v) => setDialogState(() => irrigationType = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Sprinkler can be used here', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: const Text('Shown on the owner\'s dashboard next to water stress', style: TextStyle(fontSize: 12)),
                value: sprinkler,
                onChanged: (v) => setDialogState(() => sprinkler = v),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: surveyCtrl,
                decoration: InputDecoration(
                    labelText: 'Survey / Gat number (optional)',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: gpsLatCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                    decoration: InputDecoration(
                        labelText: 'Latitude (optional)',
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10))),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: gpsLongCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                    decoration: InputDecoration(
                        labelText: 'Longitude (optional)',
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10))),
                  ),
                ),
              ]),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    'Used to show weather for this farm — enter manually, not auto-detected.',
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(loc.cancel,
                    style: const TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: idaGreen),
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                _saveFarm(
                  id: farm?['id'],
                  name: nameCtrl.text.trim(),
                  location: locCtrl.text.trim(),
                  totalAreaAcre: double.tryParse(areaCtrl.text.trim()),
                  irrigationType: irrigationType,
                  surveyNumber: surveyCtrl.text.trim().isEmpty
                      ? null
                      : surveyCtrl.text.trim(),
                  gpsLat: double.tryParse(gpsLatCtrl.text.trim()),
                  gpsLong: double.tryParse(gpsLongCtrl.text.trim()),
                  sprinklerPossible: sprinkler,
                );
              },
              child:
                  Text(loc.save, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showWorkTypeDialog({Map? workType}) {
    final loc = AppLocalizations.of(context)!;
    final nameCtrl = TextEditingController(text: workType?['name'] ?? '');
    String appliesTo = workType?['applies_to'] ?? 'both';
    // Edited in place by _QuickDetailsEditor; sent on save.
    final detailOptions = _parseDetailOptions(workType?['detail_options']);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
              workType == null ? loc.faAddWorkType : loc.faRenameWorkType,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: loc.faWorkTypeNameHint,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            // Which screens this work type shows up in — Farm
            // Attendance's picker, Farm Tractor's picker, or both.
            // Doesn't affect anything already logged with this work
            // type, only where it's offered going forward.
            DropdownButtonFormField<String>(
              value: appliesTo,
              decoration: InputDecoration(
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10))),
              items: const [
                DropdownMenuItem(
                    value: 'both', child: Text('Worker + Tractor')),
                DropdownMenuItem(value: 'worker', child: Text('Worker only')),
                DropdownMenuItem(value: 'tractor', child: Text('Tractor only')),
              ],
              onChanged: (v) => setDialogState(() => appliesTo = v!),
            ),
            const SizedBox(height: 16),
            _QuickDetailsEditor(items: detailOptions),
          ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(loc.cancel,
                    style: const TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: idaGreen),
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                _saveWorkType(
                    id: workType?['id'],
                    name: nameCtrl.text.trim(),
                    appliesTo: appliesTo,
                    detailOptions: List<String>.from(detailOptions));
              },
              child:
                  Text(loc.save, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showWorkerDialog({Map? worker}) {
    final loc = AppLocalizations.of(context)!;
    final nameCtrl = TextEditingController(text: worker?['name'] ?? '');
    final wageCtrl =
        TextEditingController(text: worker?['daily_wage']?.toString() ?? '');
    final phoneCtrl = TextEditingController(text: worker?['phone'] ?? '');
    int? farmId = worker?['farm_id'];
    int? workTypeId = worker?['work_type_id'];
    String? gender = worker?['gender'];
    bool isPermanent = worker?['is_permanent'] == 1 || worker?['is_permanent'] == true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
              worker == null ? loc.faAddFarmWorker : loc.faEditFarmWorker,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: loc.faWorkerNameLabel,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: ChoiceChip(
                    label: Text(loc.faMaleFull),
                    selected: gender == 'M',
                    selectedColor: idaGreen.withOpacity(0.15),
                    onSelected: (_) => setDialogState(() => gender = 'M'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ChoiceChip(
                    label: Text(loc.faFemaleFull),
                    selected: gender == 'F',
                    selectedColor: idaGreen.withOpacity(0.15),
                    onSelected: (_) => setDialogState(() => gender = 'F'),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: wageCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: loc.faDailyWageLabel,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: farms.any((f) => f['id'] == farmId) ? farmId : null,
                decoration: InputDecoration(
                  labelText: loc.faHomeFarmLabel,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                items: farms
                    .map<DropdownMenuItem<int>>((f) => DropdownMenuItem(
                        value: f['id'],
                        child: Text(tl(ctx, f['name']),
                            style: const TextStyle(fontSize: 13))))
                    .toList(),
                onChanged: (v) => setDialogState(() => farmId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: workTypes.any((w) => w['id'] == workTypeId)
                    ? workTypeId
                    : null,
                decoration: InputDecoration(
                  labelText: loc.faWorkType,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                items: workTypes
                    .map<DropdownMenuItem<int>>((w) => DropdownMenuItem(
                        value: w['id'],
                        child: Text(tl(ctx, w['name']),
                            style: const TextStyle(fontSize: 13))))
                    .toList(),
                onChanged: (v) => setDialogState(() => workTypeId = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: loc.faPhoneOptionalLabel,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 4),
              // Permanent workers are auto-suggested (pre-checked, still
              // removable for that one day) on every Farm Attendance
              // present-worker list, instead of being picked by hand
              // every single day.
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                activeColor: idaGreen,
                value: isPermanent,
                onChanged: (v) => setDialogState(() => isPermanent = v),
                title: const Text('📌 Permanent worker',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                subtitle: const Text('Auto-suggested on every attendance day',
                    style: TextStyle(fontSize: 11.5)),
              ),
              if (worker != null) ...[
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Row(children: [
                  Icon(
                      worker['face_enrolled'] == true
                          ? Icons.check_circle
                          : Icons.face_retouching_natural,
                      size: 18,
                      color: worker['face_enrolled'] == true
                          ? idaGreen
                          : Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      worker['face_enrolled'] == true
                          ? 'Face enrolled — Mark via Face will recognize them'
                          : 'No face enrolled yet',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: worker['face_enrolled'] == true
                              ? idaGreen
                              : Colors.grey.shade600),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final result = await Navigator.push<bool>(
                        ctx,
                        MaterialPageRoute(
                            builder: (_) => FaceEnrollmentScreen(
                                workerId: worker['id'],
                                workerName: worker['name'] ?? '')),
                      );
                      if (result == true) {
                        setDialogState(() => worker['face_enrolled'] = true);
                        _loadAll();
                      }
                    },
                    child: Text(
                        worker['face_enrolled'] == true
                            ? 'Re-enroll'
                            : 'Enroll Face',
                        style: const TextStyle(
                            color: idaGreen, fontWeight: FontWeight.w600)),
                  ),
                ]),
              ],
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(loc.cancel,
                    style: const TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: idaGreen),
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty ||
                    wageCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                _saveWorker(
                  id: worker?['id'],
                  name: nameCtrl.text.trim(),
                  dailyWage: wageCtrl.text.trim(),
                  workTypeId: workTypeId,
                  farmId: farmId,
                  phone: phoneCtrl.text.trim(),
                  gender: gender,
                  isPermanent: isPermanent,
                );
              },
              child:
                  Text(loc.save, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(loc.faSetupTitle,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: idaGreen,
        onPressed: () {
          switch (_tab) {
            case _Tab.farms:
              _showFarmDialog();
              break;
            case _Tab.workTypes:
              _showWorkTypeDialog();
              break;
            case _Tab.workers:
              _showWorkerDialog();
              break;
          }
        },
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Column(children: [
        Container(
          color: idaDark,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(children: [
            _segment(loc.faFarmsTab, _Tab.farms, farms.length),
            const SizedBox(width: 8),
            _segment(loc.faWorkTypesTab, _Tab.workTypes, workTypes.length),
            const SizedBox(width: 8),
            _segment(loc.faWorkersTab, _Tab.workers, workers.length),
          ]),
        ),
        Expanded(
          child: Responsive.constrainedContent(
              context,
              loading
                  ? const Center(
                      child: CircularProgressIndicator(color: idaGreen))
                  : RefreshIndicator(
                      color: idaGreen,
                      onRefresh: _loadAll,
                      child: _buildList(),
                    )),
        ),
      ]),
    );
  }

  Widget _segment(String label, _Tab tab, int count) {
    final selected = _tab == tab;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = tab),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? idaGreen : Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Column(children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : Colors.white70)),
            Text('$count',
                style: TextStyle(
                    fontSize: 10,
                    color: selected ? Colors.white70 : Colors.white38)),
          ]),
        ),
      ),
    );
  }

  Widget _buildList() {
    switch (_tab) {
      case _Tab.farms:
        return farms.isEmpty
            ? _empty(AppLocalizations.of(context)!.faNoFarmsYet)
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                itemCount: farms.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final f = farms[i];
                  final active = f['is_active'] == 1;
                  return _row(
                    title: tl(context, f['name'] ?? ''),
                    subtitle: f['location'] != null
                        ? tl(context, f['location'])
                        : null,
                    active: active,
                    onTap: () => _showFarmDialog(farm: f),
                    onToggle: () => _toggleFarmActive(f),
                  );
                },
              );
      case _Tab.workTypes:
        return workTypes.isEmpty
            ? _empty(AppLocalizations.of(context)!.faNoWorkTypesYet)
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                itemCount: workTypes.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final w = workTypes[i];
                  return _row(
                    title: tl(context, w['name'] ?? ''),
                    subtitle: _parseDetailOptions(w['detail_options']).join(' · '),
                    active: true,
                    showSwitch: false,
                    onTap: () => _showWorkTypeDialog(workType: w),
                  );
                },
              );
      case _Tab.workers:
        return workers.isEmpty
            ? _empty(AppLocalizations.of(context)!.faNoFarmWorkersYet)
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                itemCount: workers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final w = workers[i];
                  final active = w['is_active'] == 1;
                  final loc = AppLocalizations.of(context)!;
                  final permanent = w['is_permanent'] == 1 || w['is_permanent'] == true;
                  final parts = <String>[
                    if (w['gender'] != null)
                      (w['gender'] == 'M' ? loc.faMaleFull : loc.faFemaleFull),
                    '₹${w['daily_wage']}/day',
                    if (w['work_type_name'] != null)
                      tl(context, w['work_type_name']),
                    if (w['farm_name'] != null) tl(context, w['farm_name']),
                  ];
                  return _row(
                    title: (permanent ? '📌 ' : '') + tl(context, w['name'] ?? ''),
                    subtitle: parts.join(' · '),
                    active: active,
                    onTap: () => _showWorkerDialog(worker: w),
                    onToggle: () => _toggleWorkerActive(w),
                  );
                },
              );
    }
  }

  Widget _empty(String text) =>
      Center(child: Text(text, style: const TextStyle(color: Colors.black54)));

  Widget _row({
    required String title,
    String? subtitle,
    required bool active,
    bool showSwitch = true,
    VoidCallback? onTap,
    VoidCallback? onToggle,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE0E7D8)),
        ),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          onTap: onTap,
          title: Text(title,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.black87 : Colors.grey,
                  decoration: active ? null : TextDecoration.lineThrough)),
          subtitle: (subtitle != null && subtitle.isNotEmpty)
              ? Text(subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600))
              : null,
          trailing: showSwitch
              ? Switch(
                  value: active,
                  activeColor: idaGreen,
                  onChanged: (_) => onToggle?.call())
              : const Icon(Icons.edit_outlined, size: 18, color: Colors.grey),
        ),
      );
}

// Quick-detail chips of a work type, read defensively (null, non-list and
// non-string items are ignored; blanks and case-insensitive repeats dropped;
// at most 12 kept).
List<String> _parseDetailOptions(dynamic raw) {
  final out = <String>[];
  if (raw is! List) return out;
  for (final o in raw) {
    if (o is! String) continue;
    final t = o.trim();
    if (t.isEmpty || t.length > 40) continue;
    if (out.any((x) => x.toLowerCase() == t.toLowerCase())) continue;
    if (out.length >= 12) break;
    out.add(t);
  }
  return out;
}

// "Quick details" editor for a work type: a text field + Add button that
// makes removable chips. Max 12, each 1-40 chars, no case-insensitive
// duplicates. Edits the given list in place.
class _QuickDetailsEditor extends StatefulWidget {
  final List<String> items;
  const _QuickDetailsEditor({required this.items});

  @override
  State<_QuickDetailsEditor> createState() => _QuickDetailsEditorState();
}

class _QuickDetailsEditorState extends State<_QuickDetailsEditor> {
  static const _maxItems = 12;
  static const _maxLen = 40;
  final TextEditingController _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _add() {
    final loc = AppLocalizations.of(context)!;
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    if (t.length > _maxLen) {
      setState(() => _error = loc.faDetailTooLong);
      return;
    }
    if (widget.items.any((x) => x.toLowerCase() == t.toLowerCase())) {
      setState(() => _error = loc.faDetailDuplicate);
      return;
    }
    if (widget.items.length >= _maxItems) {
      setState(() => _error = loc.faDetailMaxChips);
      return;
    }
    setState(() {
      widget.items.add(t);
      _ctrl.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${loc.faQuickDetails} (${widget.items.length}/$_maxItems)',
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6B7280))),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _add(),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: InputDecoration(
              hintText: loc.faQuickDetailsHint,
              isDense: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(width: 6),
        TextButton(
            onPressed: _add,
            child: Text(loc.faQuickDetailAdd,
                style: const TextStyle(
                    color: Color(0xFF3B7A28), fontWeight: FontWeight.w700))),
      ]),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(_error!,
              style: const TextStyle(color: Colors.red, fontSize: 12)),
        ),
      if (widget.items.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 0, children: [
          for (final item in widget.items)
            Chip(
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(item,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis),
              ),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onDeleted: () => setState(() => widget.items.remove(item)),
            ),
        ]),
      ],
    ]);
  }
}
