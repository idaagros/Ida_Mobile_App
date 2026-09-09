import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import '../services/image_helper.dart';
import '../services/colored_date_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'factory_tractor_diesel_screen.dart';
import '../services/responsive.dart';

class TractorReadingScreen extends StatefulWidget {
  final String? returnedRecordId;
  final String? adminNote;
  const TractorReadingScreen(
      {super.key, this.returnedRecordId, this.adminNote});
  @override
  State<TractorReadingScreen> createState() => _TractorReadingScreenState();
}

class _TractorReadingScreenState extends State<TractorReadingScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const amber = Color(0xFFF5A623);
  static const baseUrl = 'https://excusable-moving-preorder.ngrok-free.dev/api';

  final readingCtrl = TextEditingController();
  final notesCtrl = TextEditingController();

  DateTime selectedDate = DateTime.now().subtract(const Duration(days: 1));
  TimeOfDay selectedTime = TimeOfDay.now();

  Uint8List? photoBytes;
  String? photoName;

  bool loading = false;
  bool submitting = false;

  double? previousReading;
  String? previousDate;
  String? previousTime;
  double? hoursRun;
  double monthlyHours = 0;
  double overallHours = 0;
  bool summaryLoaded = false;
  String? successMessage;
  String? errorMessage;
  // Shown after a successful save when the backend reports no photo was
  // attached. Photo is optional — this is just a heads-up, not a block —
  // and the upload field stays open so it can still be added on a
  // correction later.
  bool photoMissingWarning = false;

  // When the selected date already has an APPROVED reading, the form
  // switches into read-only mode: shows what was entered, blocks editing.
  // Only an admin can change an approved record (via Admin Review).
  bool isDateLocked = false;
  Map<String, dynamic>? lockedRecord;
  String? existingRecordStatus;

  // photo_url from the DB is a relative path like '/uploads/tractor/x.jpg'
  // served from the API host root (not under /api), so strip the trailing
  // '/api' from baseUrl to build the actual image URL.
  String? get _lockedPhotoUrl {
    final url = lockedRecord?['photo_url']?.toString();
    if (url == null || url.isEmpty) return null;
    final host = baseUrl.endsWith('/api')
        ? baseUrl.substring(0, baseUrl.length - 4)
        : baseUrl;
    return '$host$url';
  }

  Map<String, dynamic>? _returnedRecord;

  @override
  void initState() {
    super.initState();
    readingCtrl.addListener(_validateReading);
    if (widget.returnedRecordId != null) {
      _fetchReturnedRecord();
    } else {
      _loadData();
    }
  }

  Future<void> _fetchReturnedRecord() async {
    setState(() => loading = true);
    try {
      final h = await _headers;
      final res = await http.get(
        Uri.parse('$baseUrl/tractor/${widget.returnedRecordId}'),
        headers: h,
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _returnedRecord = data;
          readingCtrl.text = data['meter_reading']?.toString() ?? '';
          notesCtrl.text = data['notes']?.toString() ?? '';
          try {
            selectedDate = DateTime.parse(data['reading_date']);
          } catch (_) {}
          previousReading =
              double.tryParse((data['previous_reading'] ?? 0).toString());
          previousDate =
              data['previous_reading_date']?.toString().substring(0, 10);
          previousTime = data['previous_reading_time']?.toString();
        });
        _validateReading();
      }
    } catch (e) {
      debugPrint('Fetch returned record error: $e');
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    readingCtrl.removeListener(_validateReading);
    readingCtrl.dispose();
    notesCtrl.dispose();
    super.dispose();
  }

  void _validateReading() {
    final val = double.tryParse(readingCtrl.text);
    if (val == null) {
      setState(() {
        hoursRun = null;
        errorMessage = null;
      });
      return;
    }
    if (previousReading != null && val < previousReading!) {
      setState(() {
        errorMessage =
            'Must be ≥ previous reading of ${previousReading!.toStringAsFixed(1)} hrs';
        hoursRun = null;
      });
    } else {
      setState(() {
        errorMessage = null;
        hoursRun = previousReading != null ? val - previousReading! : null;
      });
    }
  }

  Future<Map<String, String>> get _headers async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${prefs.getString('token') ?? ''}',
      'ngrok-skip-browser-warning': 'true',
    };
  }

  // Formats a reading_date ('yyyy-MM-dd') + optional reading_time
  // ('HH:mm:ss') pair into 'dd-MMM-yyyy hh:mm a', e.g. '20-Jun-2026 09:45 AM'.
  String _formatRecordedOn(String? dateStr, String? timeStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final datePart = DateTime.parse(dateStr);
      var dt = datePart;
      if (timeStr != null && timeStr.isNotEmpty) {
        final parts = timeStr.split(':');
        if (parts.length >= 2) {
          dt = DateTime(
            datePart.year,
            datePart.month,
            datePart.day,
            int.tryParse(parts[0]) ?? 0,
            int.tryParse(parts[1]) ?? 0,
          );
        }
      }
      return DateFormat('dd-MMM-yyyy hh:mm a').format(dt);
    } catch (_) {
      return dateStr;
    }
  }

  Future<void> _loadData() async {
    setState(() => loading = true);
    try {
      final h = await _headers;

      final results = await Future.wait([
        http.get(Uri.parse('$baseUrl/tractor/summary'), headers: h),
      ]);

      // Summary
      final summaryRes = results[0];
      if (summaryRes.statusCode == 200) {
        final data = jsonDecode(summaryRes.body);
        setState(() {
          monthlyHours = double.tryParse(data['monthly_hours'].toString()) ?? 0;
          overallHours = double.tryParse(data['overall_hours'].toString()) ?? 0;
          summaryLoaded = true;
        });
      }

      // Previous reading is date-aware — fetched separately so it can be
      // refreshed whenever the selected date changes. This also checks
      // whether today's date is already locked (approved).
      await _applySelectedDate();
    } catch (e) {
      debugPrint('Load error: $e');
    } finally {
      setState(() => loading = false);
    }
  }

  // Fetches the reading immediately preceding the currently `selectedDate`.
  // IMPORTANT: this is date-aware, not "last recorded entry" — if the
  // selected date is 20th June, this looks up the most recent reading
  // strictly before 20th June, even if a later entry (e.g. 21st June)
  // already exists in the system. All validation and consumption
  // calculations are based on this date-relative previous reading.
  Future<void> _loadPreviousReading() async {
    try {
      final h = await _headers;
      final dateStr = DateFormat('yyyy-MM-dd').format(selectedDate);
      final res = await http.get(
        Uri.parse('$baseUrl/tractor/previous?date=$dateStr'),
        headers: h,
      );
      if (res.statusCode == 200 && res.body != 'null') {
        final data = jsonDecode(res.body);
        setState(() {
          if (data != null) {
            previousReading = double.tryParse(data['meter_reading'].toString());
            previousDate = data['reading_date']?.toString().substring(0, 10);
            previousTime = data['reading_time']?.toString();
          } else {
            previousReading = null;
            previousDate = null;
            previousTime = null;
          }
        });
      } else {
        setState(() {
          previousReading = null;
          previousDate = null;
          previousTime = null;
        });
      }
      _validateReading();
    } catch (e) {
      debugPrint('Previous reading fetch error: $e');
    }
  }

  Future<void> _pickDate() async {
    final picked = await showColoredDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      baseUrl: baseUrl,
      module: 'tractor',
      primaryColor: idaGreen,
    );
    if (picked == null) return;

    setState(() => selectedDate = picked);
    await _applySelectedDate();
  }

  // Loads whatever exists for `selectedDate`. If that date already has an
  // APPROVED reading, the form switches to read-only mode showing exactly
  // what was entered — the date itself stays selectable, only editing is
  // blocked. Only an admin can change an approved record.
  Future<void> _applySelectedDate() async {
    final status = await _checkDateStatus(selectedDate);
    final exists = status != null && status['exists'] == true;
    final locked = exists && status['locked'] == true;

    if (exists) {
      final record = status['record'] as Map<String, dynamic>?;
      setState(() {
        isDateLocked = locked;
        lockedRecord = record;
        existingRecordStatus = locked ? null : (status['status']?.toString());
        errorMessage = null;
        successMessage = null;
        if (record != null) {
          readingCtrl.text = record['meter_reading']?.toString() ?? '';
          notesCtrl.text = record['notes']?.toString() ?? '';
          hoursRun = double.tryParse(record['hours_run']?.toString() ?? '');
          final t = record['reading_time']?.toString();
          if (t != null && t.isNotEmpty) {
            final parts = t.split(':');
            selectedTime = TimeOfDay(
              hour: int.tryParse(parts[0]) ?? selectedTime.hour,
              minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
            );
          }
        }
      });
    } else {
      setState(() {
        isDateLocked = false;
        lockedRecord = null;
        existingRecordStatus = null;
        readingCtrl.clear();
        notesCtrl.clear();
        photoBytes = null;
        photoName = null;
        hoursRun = null;
        errorMessage = null;
      });
    }

    // Previous-reading lookup & all consumption/validation are always
    // recalculated against the entry immediately before the newly
    // selected date, not whatever was already loaded — regardless of
    // whether the date itself turns out to be locked.
    await _loadPreviousReading();
  }

  // Asks the backend what (if anything) already exists for `date`.
  // Returns null on any network/parse error so a server hiccup never
  // blocks the date picker — the backend still enforces the lock on
  // submit regardless.
  Future<Map<String, dynamic>?> _checkDateStatus(DateTime date) async {
    try {
      final h = await _headers;
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      final res = await http.get(
        Uri.parse('$baseUrl/tractor/check-date?date=$dateStr'),
        headers: h,
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('check-date error: $e');
    }
    return null;
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: selectedTime,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx)
            .copyWith(colorScheme: const ColorScheme.light(primary: idaGreen)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => selectedTime = picked);
  }

  Future<void> _pickPhoto() async {
    final result = await ImageHelper.pickWithSheet(context);
    if (result != null) {
      setState(() {
        photoBytes = result.bytes;
        photoName = result.name;
      });
    }
  }

  Future<void> _submit() async {
    if (isDateLocked) {
      setState(() => errorMessage =
          'This date already has an approved reading. Only an admin can change it.');
      return;
    }
    if (readingCtrl.text.isEmpty) {
      setState(() => errorMessage = 'Please enter the tractor meter reading');
      return;
    }
    if (errorMessage != null) return;

    setState(() {
      submitting = true;
      successMessage = null;
      photoMissingWarning = false;
    });

    try {
      final h = await _headers;
      final dateStr = DateFormat('yyyy-MM-dd').format(selectedDate);
      final timeStr =
          '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}:00';
      final updatedAt = DateTime.now().toIso8601String();

      final isCorrection = widget.returnedRecordId != null;
      final reqUrl = isCorrection
          ? Uri.parse('$baseUrl/tractor/${widget.returnedRecordId}')
          : Uri.parse('$baseUrl/tractor');

      final request =
          http.MultipartRequest(isCorrection ? 'PUT' : 'POST', reqUrl)
            ..headers.addAll(h)
            ..fields['reading_date'] = dateStr
            ..fields['reading_time'] = timeStr
            ..fields['meter_reading'] = readingCtrl.text
            ..fields['notes'] = notesCtrl.text
            ..fields['status'] = 'pending'
            ..fields['updated_at'] = updatedAt;

      if (photoBytes != null && photoName != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'photo',
          photoBytes!,
          filename: photoName,
          contentType: MediaType('image', 'jpeg'),
        ));
      }

      final res = await http.Response.fromStream(await request.send());
      final data = jsonDecode(res.body);

      if (res.statusCode == 200 || res.statusCode == 201) {
        final newMonthly =
            double.tryParse(data['monthly_hours'].toString()) ?? 0;
        final newOverall =
            double.tryParse(data['overall_hours'].toString()) ?? 0;
        final newHours = double.tryParse(data['hours_run'].toString()) ?? 0;

        setState(() {
          successMessage = isCorrection
              ? 'Correction submitted — pending admin review'
              : (data['message'] ?? 'Reading submitted');
          photoMissingWarning = data['photo_missing'] == true;
          hoursRun = newHours;
          monthlyHours = newMonthly;
          overallHours = newOverall;
          previousReading = double.tryParse(readingCtrl.text);
          previousDate = dateStr;
          previousTime = timeStr;

          // Show maintenance alerts if any triggered
          final newAlerts = data['maintenance_alerts'] as List? ?? [];
          if (newAlerts.isNotEmpty && mounted) {
            Future.delayed(const Duration(milliseconds: 500), () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  title: const Row(children: [
                    Text('⚠️', style: TextStyle(fontSize: 20)),
                    SizedBox(width: 8),
                    Text('Maintenance Due!',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFE24B4A))),
                  ]),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('The following activities need attention:',
                          style: TextStyle(
                              fontSize: 13, color: Color(0xFF6B7280))),
                      const SizedBox(height: 12),
                      ...newAlerts
                          .map<Widget>((a) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(children: [
                                  const Icon(Icons.warning_amber_rounded,
                                      color: Color(0xFFE24B4A), size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: Text(
                                    '${a['activity_name']} — overdue by ${a['overdue_by']} hrs',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500),
                                  )),
                                ]),
                              ))
                          .toList(),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Later',
                          style: TextStyle(color: Colors.grey)),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B7A28)),
                      child: const Text('Go to Maintenance',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );
            });
          }
          readingCtrl.clear();
          notesCtrl.clear();
          photoBytes = null;
          photoName = null;
          selectedDate = DateTime.now().subtract(const Duration(days: 1));
          selectedTime = TimeOfDay.now();
          errorMessage = null;
        });
      } else {
        setState(() => errorMessage = data['error'] ?? 'Submission failed');
      }
    } catch (e) {
      setState(() => errorMessage = 'Error: $e');
    } finally {
      setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F5),
      appBar: AppBar(
        backgroundColor: idaDark,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(children: [
          Image.asset('assets/images/idalogo.png', height: 28),
          const SizedBox(width: 10),
          const Flexible(
              child: Text('Factory Tractor Hours Reading',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFF5A623)))),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.local_gas_station, color: Colors.white70),
            tooltip: 'Diesel Tracking',
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const FactoryTractorDieselScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _loadData,
            tooltip: 'Refresh totals',
          ),
        ],
        elevation: 0,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: idaGreen))
          : Responsive.constrainedContent(
              context,
              SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Correction banner
                      if (widget.returnedRecordId != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF8EC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: const Color(0xFFFFCC02), width: 1.5),
                          ),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(children: [
                                  Icon(Icons.assignment_return_rounded,
                                      color: Color(0xFFF57C00), size: 16),
                                  SizedBox(width: 8),
                                  Text('Correction Required',
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFFF57C00))),
                                ]),
                                if (widget.adminNote != null &&
                                    widget.adminNote!.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(widget.adminNote!,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFF6B7280))),
                                ],
                                const SizedBox(height: 6),
                                const Text(
                                    'Please correct the reading below and resubmit.',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF9CA3AF))),
                              ]),
                        ),
                      ],
                      // ── Summary cards ─────────────────────────────
                      Row(children: [
                        _summaryCard(
                          icon: Icons.calendar_month,
                          label: 'This month',
                          value: '${monthlyHours.toStringAsFixed(1)} hrs',
                          color: idaGreen,
                        ),
                        const SizedBox(width: 12),
                        _summaryCard(
                          icon: Icons.av_timer,
                          label: 'Overall total',
                          value: '${overallHours.toStringAsFixed(1)} hrs',
                          color: amber,
                        ),
                      ]),

                      const SizedBox(height: 16),

                      // ── Previous reading ──────────────────────────
                      previousReading != null
                          ? _infoCard(
                              icon: Icons.history,
                              color: idaGreen,
                              title: 'Previous reading',
                              value:
                                  '${previousReading!.toStringAsFixed(1)} hrs',
                              sub:
                                  'Recorded on ${_formatRecordedOn(previousDate, previousTime)}',
                            )
                          : _infoCard(
                              icon: Icons.info_outline,
                              color: amber,
                              title: 'First record',
                              value: 'No previous reading found',
                              sub: 'This will be the opening reading',
                            ),

                      const SizedBox(height: 20),

                      // ── Date & Time — locked for corrections ──────
                      if (widget.returnedRecordId != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F7F2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE0E7D8)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.lock_outline,
                                size: 16, color: Colors.grey),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Original record date (locked)',
                                        style: TextStyle(
                                            fontSize: 11, color: Colors.grey)),
                                    const SizedBox(height: 2),
                                    Text(
                                      DateFormat('dd MMM yyyy')
                                          .format(selectedDate),
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF1E4012)),
                                    ),
                                  ]),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('Updated at: now',
                                  style: TextStyle(
                                      fontSize: 10, color: Colors.grey)),
                            ),
                          ]),
                        ),
                      ] else ...[
                        Row(children: [
                          Expanded(
                              child: _pickerTile(
                            icon: Icons.calendar_today,
                            label: 'Date',
                            value:
                                DateFormat('dd MMM yyyy').format(selectedDate),
                            onTap: _pickDate,
                          )),
                          const SizedBox(width: 12),
                          Expanded(
                              child: _pickerTile(
                            icon: Icons.access_time,
                            label: 'Time',
                            value: selectedTime.format(context),
                            onTap: _pickTime,
                          )),
                        ]),
                      ],

                      const SizedBox(height: 20),

                      // ── Meter reading ─────────────────────────────
                      _sectionLabel('TRACTOR METER READING (hrs)'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: readingCtrl,
                        enabled: !isDateLocked && existingRecordStatus == null,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: idaDark),
                        decoration: InputDecoration(
                          hintText: '0.0',
                          hintStyle: TextStyle(
                              color: Colors.grey.shade400, fontSize: 24),
                          prefixIcon:
                              const Icon(Icons.agriculture, color: idaGreen),
                          suffix: const Text('hrs',
                              style: TextStyle(
                                  color: idaGreen,
                                  fontWeight: FontWeight.w600)),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  const BorderSide(color: Color(0xFFE0E7D8))),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: idaGreen, width: 1.5)),
                          errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Colors.red)),
                          focusedErrorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: Colors.red, width: 1.5)),
                          errorText: errorMessage,
                        ),
                      ),

                      // Live hours run preview
                      if (hoursRun != null &&
                          hoursRun! >= 0 &&
                          errorMessage == null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(children: [
                            const Icon(Icons.timelapse,
                                color: idaGreen, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'Hours run today: ${hoursRun!.toStringAsFixed(1)} hrs',
                              style: const TextStyle(
                                  color: idaDark,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13),
                            ),
                          ]),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // ── Auto-calculated totals (read-only) ────────
                      _sectionLabel('AUTO-CALCULATED TOTALS'),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                            child: _readonlyField(
                          label: 'Monthly total',
                          value: '${monthlyHours.toStringAsFixed(1)} hrs',
                          icon: Icons.calendar_month,
                        )),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _readonlyField(
                          label: 'Overall total',
                          value: '${overallHours.toStringAsFixed(1)} hrs',
                          icon: Icons.av_timer,
                        )),
                      ]),

                      const SizedBox(height: 20),

                      // ── Photo (required) ──────────────────────────
                      Row(children: [
                        _sectionLabel('METER PHOTO'),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(10)),
                          child: const Text('Optional but recommended',
                              style:
                                  TextStyle(fontSize: 10, color: Colors.grey)),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: (isDateLocked || existingRecordStatus != null)
                            ? null
                            : _pickPhoto,
                        child: Container(
                          width: double.infinity,
                          height:
                              (photoBytes != null || _lockedPhotoUrl != null)
                                  ? 200
                                  : 110,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: (photoBytes != null ||
                                      _lockedPhotoUrl != null)
                                  ? idaGreen
                                  : const Color(0xFFE0E7D8),
                              width: (photoBytes != null ||
                                      _lockedPhotoUrl != null)
                                  ? 1.5
                                  : 1,
                            ),
                          ),
                          child: (isDateLocked || existingRecordStatus != null)
                              ? (_lockedPhotoUrl != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.network(_lockedPhotoUrl!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Center(
                                              child: Text('Photo unavailable',
                                                  style: TextStyle(
                                                      color:
                                                          Colors.grey.shade500,
                                                      fontSize: 12)))),
                                    )
                                  : Center(
                                      child: Text('No photo for this entry',
                                          style: TextStyle(
                                              color: Colors.grey.shade500,
                                              fontSize: 13))))
                              : photoBytes != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.memory(photoBytes!,
                                          fit: BoxFit.cover),
                                    )
                                  : Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                          Icon(Icons.add_a_photo_outlined,
                                              size: 32,
                                              color: Colors.grey.shade400),
                                          const SizedBox(height: 8),
                                          Text(
                                              'Tap to attach photo (camera or gallery)',
                                              style: TextStyle(
                                                  color: Colors.grey.shade500,
                                                  fontSize: 13)),
                                          const SizedBox(height: 4),
                                          Text(
                                              'Photo will be compressed automatically · Blurry images will be rejected',
                                              style: TextStyle(
                                                  color: Colors.grey.shade400,
                                                  fontSize: 11)),
                                        ]),
                        ),
                      ),
                      if (!isDateLocked && photoBytes != null) ...[
                        const SizedBox(height: 6),
                        Row(children: [
                          const Icon(Icons.check_circle,
                              color: idaGreen, size: 14),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(photoName ?? 'Photo selected',
                                style: const TextStyle(
                                    fontSize: 12, color: idaGreen),
                                overflow: TextOverflow.ellipsis),
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              photoBytes = null;
                              photoName = null;
                            }),
                            style:
                                TextButton.styleFrom(padding: EdgeInsets.zero),
                            child: const Text('Remove',
                                style:
                                    TextStyle(color: Colors.red, fontSize: 12)),
                          ),
                        ]),
                      ],

                      const SizedBox(height: 20),

                      // ── Notes ─────────────────────────────────────
                      _sectionLabel('NOTES (OPTIONAL)'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: notesCtrl,
                        enabled: !isDateLocked && existingRecordStatus == null,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'Any observations about the tractor...',
                          hintStyle: TextStyle(
                              color: Colors.grey.shade400, fontSize: 13),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  const BorderSide(color: Color(0xFFE0E7D8))),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: idaGreen, width: 1.5)),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ── Success card ──────────────────────────────
                      if (successMessage != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFB8D99E)),
                          ),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(children: [
                                  Icon(Icons.check_circle,
                                      color: idaGreen, size: 18),
                                  SizedBox(width: 8),
                                  Text('Reading submitted!',
                                      style: TextStyle(
                                          color: idaDark,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14)),
                                ]),
                                const SizedBox(height: 12),
                                if (hoursRun != null)
                                  _resultRow('Hours run today',
                                      '${hoursRun!.toStringAsFixed(1)} hrs'),
                                _resultRow('Monthly total',
                                    '${monthlyHours.toStringAsFixed(1)} hrs'),
                                _resultRow('Overall total',
                                    '${overallHours.toStringAsFixed(1)} hrs'),
                                const SizedBox(height: 6),
                                const Text('Pending admin review',
                                    style: TextStyle(
                                        color: Color(0xFF6B7280),
                                        fontSize: 11)),
                              ]),
                        ),

                      // ── Photo-missing notice ──────────────────────
                      // Photo is optional, so this never blocks saving —
                      // it's just a clear heads-up that none was attached
                      // this time. The upload field above stays open so a
                      // photo can still be added on a correction later.
                      if (photoMissingWarning)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF8EC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFFCC02)),
                          ),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.info_outline,
                                    color: Color(0xFFF57C00), size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Photo not uploaded. Please upload a photo of the meter — '
                                    'you can add one on a correction.',
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        color: Colors.grey.shade800),
                                  ),
                                ),
                              ]),
                        ),

                      // Existing-but-not-approved banner
                      if (existingRecordStatus != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF8EC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFFCC02)),
                          ),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.info_outline,
                                    color: Color(0xFFF57C00), size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    existingRecordStatus == 'returned'
                                        ? 'A reading already exists for this date and was returned for correction. Open it from your returned records to edit it.'
                                        : 'A reading already exists for this date and is pending admin review. It cannot be edited here right now.',
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        color: Colors.grey.shade800),
                                  ),
                                ),
                              ]),
                        ),
                      ],

                      // ── Locked-date banner ────────────────────────
                      if (isDateLocked) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F0FE),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color:
                                    const Color(0xFF1A73E8).withOpacity(0.3)),
                          ),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.lock_outline,
                                    size: 18, color: Color(0xFF1A73E8)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text('This date is locked',
                                            style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF1A73E8))),
                                        const SizedBox(height: 2),
                                        Text(
                                          'This reading has already been approved by admin. '
                                          'You can view it here, but only an admin can change it.',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade700),
                                        ),
                                      ]),
                                ),
                              ]),
                        ),
                      ],

                      // ── Submit button ─────────────────────────────
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton.icon(
                          onPressed: (submitting ||
                                  isDateLocked ||
                                  existingRecordStatus != null)
                              ? null
                              : _submit,
                          icon: submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : Icon(
                                  (isDateLocked || existingRecordStatus != null)
                                      ? Icons.lock_outline
                                      : Icons.send,
                                  color: Colors.white,
                                  size: 18),
                          label: Text(
                              submitting
                                  ? 'Submitting...'
                                  : isDateLocked
                                      ? 'Locked — Approved'
                                      : existingRecordStatus != null
                                          ? 'Entry already exists for this date'
                                          : (widget.returnedRecordId != null
                                              ? 'Resubmit for Approval'
                                              : 'Submit Reading'),
                              style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: idaGreen,
                            disabledBackgroundColor: Colors.grey.shade300,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),
                    ]),
              )),
    );
  }

  // ── Widgets ───────────────────────────────────────────────

  Widget _summaryCard(
          {required IconData icon,
          required String label,
          required String value,
          required Color color}) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color == idaGreen
                ? const Color(0xFFE8F5E2)
                : const Color(0xFFFEF3DC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 8),
            Text(value,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
          ]),
        ),
      );

  Widget _readonlyField(
          {required String label,
          required String value,
          required IconData icon}) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F4EE),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0E7D8)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Row(children: [
            Icon(icon, size: 16, color: idaGreen),
            const SizedBox(width: 6),
            Text(value,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: idaDark)),
          ]),
          const SizedBox(height: 2),
          const Text('Auto-calculated',
              style: TextStyle(fontSize: 10, color: Color(0xFF9CA3AF))),
        ]),
      );

  Widget _infoCard(
          {required IconData icon,
          required Color color,
          required String title,
          required String value,
          required String sub}) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0E7D8)),
        ),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF6B7280))),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: color)),
                Text(sub,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF9CA3AF))),
              ])),
        ]),
      );

  Widget _pickerTile(
          {required IconData icon,
          required String label,
          required String value,
          required VoidCallback onTap}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE0E7D8)),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            Row(children: [
              Icon(icon, size: 16, color: idaGreen),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(value,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: idaDark))),
              const Icon(Icons.edit, size: 14, color: Color(0xFF9CA3AF)),
            ]),
          ]),
        ),
      );

  Widget _sectionLabel(String text) => Text(text,
      style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFF6B7280),
          letterSpacing: 0.8));

  Widget _resultRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
          Text(value,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: idaDark)),
        ]),
      );
}
