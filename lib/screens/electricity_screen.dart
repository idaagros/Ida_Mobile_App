import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import '../services/image_helper.dart';
import '../services/ocr_helper.dart';
import '../services/colored_date_picker.dart';
import '../services/responsive.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class ElectricityReadingScreen extends StatefulWidget {
  final String? returnedRecordId;
  final String? adminNote;
  const ElectricityReadingScreen(
      {super.key, this.returnedRecordId, this.adminNote});
  @override
  State<ElectricityReadingScreen> createState() =>
      _ElectricityReadingScreenState();
}

class _ElectricityReadingScreenState extends State<ElectricityReadingScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const amber = Color(0xFFF5A623);
  static const baseUrl = 'https://excusable-moving-preorder.ngrok-free.dev/api';

  final readingCtrl = TextEditingController();
  final notesCtrl = TextEditingController();
  // Optional, added after reconciling the bill projection against
  // real MSEDCL bills - kvah/rkvah for a more precise power-factor
  // derivation later, and the KVA MD fields because plain kva_md is
  // confirmed as the figure that actually drives the demand charge
  // (T1-T4/D captured too, for cross-referencing against a future
  // bill's own TOD breakdown, though not used in any calculation yet).
  final kvahCtrl = TextEditingController();
  final rkvahLagCtrl = TextEditingController();
  final rkvahLeadCtrl = TextEditingController();
  final kvaMdT1Ctrl = TextEditingController();
  final kvaMdT2Ctrl = TextEditingController();
  final kvaMdT3Ctrl = TextEditingController();
  final kvaMdT4Ctrl = TextEditingController();
  final kvaMdDCtrl = TextEditingController();
  final kvaMdCtrl = TextEditingController();
  bool _showAdvancedReadings = false;

  DateTime selectedDate = DateTime.now().subtract(const Duration(days: 1));
  TimeOfDay selectedTime = TimeOfDay.now();

  // Web-compatible image handling
  XFile? photoFile;
  Uint8List? photoBytes;
  String? photoName;
  // OCR (on-device, via ML Kit) - runs on the photo to try prefilling
  // the meter reading. _ocrRunning shows a brief loading state while
  // it works; _ocrPrefilled marks the reading field as OCR-sourced so
  // the UI can nudge the user to double check it before submitting.
  bool _ocrRunning = false;
  bool _ocrPrefilled = false;

  bool loading = false;
  bool submitting = false;
  // Submitting a reading is an 'add' operation (a new record each
  // time - there's no in-place edit of an existing one from this
  // screen). Starts false (safe default) until the async check
  // resolves - SharedPreferences reads are fast, so this is a brief
  // window, not a visible loading state of its own.
  bool canAdd = false;

  double? previousReading;
  String? previousDate;
  String? previousTime;
  double? unitsConsumed;
  double? monthlyTotal;
  String? successMessage;
  String? errorMessage;
  bool photoMissingWarning = false;

  // When the selected date already has an APPROVED reading, the form
  // switches into read-only mode: shows what was entered, blocks editing.
  // Only an admin can change an approved record (via Admin Review).
  bool isDateLocked = false;
  Map<String, dynamic>? lockedRecord;
  // Set when a record exists for the selected date but isn't approved
  // yet (pending/returned) — its data is still shown, but the date isn't
  // "locked" in the read-only sense; this just explains why the form is
  // pre-filled instead of empty.
  String? existingRecordStatus;

  // photo_url from the DB is a relative path like '/uploads/electricity/x.jpg'
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
    ApiService.canAdd('electricity').then((v) {
      if (mounted) setState(() => canAdd = v);
    });
    readingCtrl.addListener(_validateReading);
    readingCtrl.addListener(() {
      // Once the user actually edits the field after an OCR prefill,
      // clear the badge - they've engaged with the value, whether they
      // changed it or just confirmed it by editing/retyping.
      if (_ocrPrefilled) setState(() => _ocrPrefilled = false);
    });
    if (widget.returnedRecordId != null) {
      _fetchReturnedRecord();
    } else {
      _applySelectedDate();
    }
  }

  Future<void> _fetchReturnedRecord() async {
    setState(() => loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      final res = await http.get(
        Uri.parse('$baseUrl/electricity/${widget.returnedRecordId}'),
        headers: {
          'Authorization': 'Bearer $token',
          'ngrok-skip-browser-warning': 'true',
        },
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
          previousDate = data['previous_reading_date']?.toString();
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
    kvahCtrl.dispose();
    rkvahLagCtrl.dispose();
    rkvahLeadCtrl.dispose();
    kvaMdT1Ctrl.dispose();
    kvaMdT2Ctrl.dispose();
    kvaMdT3Ctrl.dispose();
    kvaMdT4Ctrl.dispose();
    kvaMdDCtrl.dispose();
    kvaMdCtrl.dispose();
    super.dispose();
  }

  void _validateReading() {
    final val = double.tryParse(readingCtrl.text);
    if (val == null) {
      setState(() {
        unitsConsumed = null;
        errorMessage = null;
      });
      return;
    }
    if (previousReading != null && val < previousReading!) {
      setState(() {
        errorMessage =
            'Must be ≥ previous reading of ${previousReading!.toStringAsFixed(2)} kWh';
        unitsConsumed = null;
      });
    } else {
      setState(() {
        errorMessage = null;
        unitsConsumed = previousReading != null ? val - previousReading! : null;
      });
    }
  }

  // Fetches the reading immediately preceding the currently `selectedDate`.
  // IMPORTANT: date-aware, not "last recorded entry" — if the selected date
  // is 20th June, this looks up the most recent reading strictly before
  // 20th June, even if a later entry (e.g. 21st June) already exists.
  // All validation and units-consumed calculations are based on this
  // date-relative previous reading.
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

  Future<void> _loadPreviousReading() async {
    setState(() => loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      final dateStr = DateFormat('yyyy-MM-dd').format(selectedDate);
      final res = await http.get(
        Uri.parse('$baseUrl/electricity/previous?date=$dateStr'),
        headers: {
          'Authorization': 'Bearer $token',
          'ngrok-skip-browser-warning': 'true',
        },
      );
      if (res.statusCode == 200 && res.body != 'null') {
        final data = jsonDecode(res.body);
        setState(() {
          if (data != null) {
            previousReading = double.tryParse(data['meter_reading'].toString());
            previousDate = data['reading_date']?.toString();
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
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showColoredDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      baseUrl: baseUrl,
      module: 'electricity',
      primaryColor: idaGreen,
    );
    if (picked == null) return;

    setState(() => selectedDate = picked);
    await _applySelectedDate();
  }

  // Loads whatever exists for `selectedDate`. If a record already exists
  // for that exact date — regardless of status — its data is shown
  // immediately; only an APPROVED record additionally becomes read-only
  // (isDateLocked), since only an admin can change approved data.
  // IMPORTANT: this branches on `exists`, not `locked` — a pending or
  // returned record for this date still has to be shown, otherwise the
  // app silently behaves as if the date were empty and the previous-
  // reading lookup skips straight past it to an earlier date's data.
  Future<void> _applySelectedDate() async {
    final status = await _checkDateStatus(selectedDate);
    final exists = status != null && status['exists'] == true;
    final locked = exists && status['locked'] == true;

    if (exists) {
      final record = status['record'] as Map<String, dynamic>?;
      setState(() {
        isDateLocked = locked;
        // IMPORTANT: lockedRecord holds the existing record's data for
        // display purposes (including its photo) whenever a record
        // exists for this date — approved, pending, or returned. It is
        // NOT the thing that decides editability; isDateLocked does
        // that. Previously this was set to null for non-approved
        // records, which correctly blocked editing but also silently
        // discarded the photo, so a pending/returned entry's photo
        // never showed even though it existed on the server.
        lockedRecord = record;
        existingRecordStatus = locked ? null : (status['status']?.toString());
        errorMessage = null;
        successMessage = null;
        if (record != null) {
          readingCtrl.text = record['meter_reading']?.toString() ?? '';
          notesCtrl.text = record['notes']?.toString() ?? '';
          unitsConsumed =
              double.tryParse(record['units_consumed']?.toString() ?? '');
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
        photoFile = null;
        photoName = null;
        unitsConsumed = null;
        errorMessage = null;
      });
    }

    // Previous-reading lookup & all consumption/validation are always
    // recalculated against the entry immediately before the newly
    // selected date, not whatever was already loaded — regardless of
    // whether the date itself turns out to have its own entry.
    await _loadPreviousReading();
  }

  // Asks the backend what (if anything) already exists for `date`.
  // Returns null on any network/parse error so a server hiccup never
  // blocks the date picker — the backend still enforces the lock on
  // submit regardless.
  Future<Map<String, dynamic>?> _checkDateStatus(DateTime date) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      final res = await http.get(
        Uri.parse('$baseUrl/electricity/check-date?date=$dateStr'),
        headers: {
          'Authorization': 'Bearer $token',
          'ngrok-skip-browser-warning': 'true',
        },
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
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: idaGreen),
        ),
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
        photoFile = null; // ImageHelper returns bytes directly
      });
      // Only attempt OCR prefill if the field is still empty - never
      // overwrite a value the user already typed in themselves.
      if (readingCtrl.text.trim().isEmpty) {
        setState(() => _ocrRunning = true);
        final lines = await OcrHelper.recognizeLines(result.originalBytes);
        final reading = OcrHelper.extractMeterReading(lines);
        if (mounted) {
          setState(() => _ocrRunning = false);
          if (reading != null) {
            readingCtrl.text = reading; // fires _validateReading too
            setState(() => _ocrPrefilled = true);
          }
        }
      }
    }
  }

  Future<void> _submit() async {
    if (isDateLocked) {
      setState(() => errorMessage =
          'This date already has an approved reading. Only an admin can change it.');
      return;
    }
    if (readingCtrl.text.isEmpty) {
      setState(() => errorMessage = 'Please enter the meter reading');
      return;
    }
    if (errorMessage != null) return;

    setState(() {
      submitting = true;
      successMessage = null;
      photoMissingWarning = false;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      final dateStr = DateFormat('yyyy-MM-dd').format(selectedDate);
      final timeStr =
          '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}:00';
      // For corrections, capture exact now as updated timestamp
      final updatedAt = DateTime.now().toIso8601String();

      final isCorrection = widget.returnedRecordId != null;
      final reqUrl = isCorrection
          ? Uri.parse('$baseUrl/electricity/${widget.returnedRecordId}')
          : Uri.parse('$baseUrl/electricity');

      final request =
          http.MultipartRequest(isCorrection ? 'PUT' : 'POST', reqUrl)
            ..headers['Authorization'] = 'Bearer $token'
            ..headers['ngrok-skip-browser-warning'] = 'true'
            ..fields['reading_date'] = dateStr
            ..fields['reading_time'] = timeStr
            ..fields['meter_reading'] = readingCtrl.text
            ..fields['notes'] = notesCtrl.text
            ..fields['status'] = 'pending'
            ..fields['updated_at'] = updatedAt;

      // All optional - only sent when actually filled in, so a plain
      // kWh-only submission behaves exactly as it always has.
      void addIfPresent(String key, TextEditingController ctrl) {
        if (ctrl.text.trim().isNotEmpty) request.fields[key] = ctrl.text.trim();
      }

      addIfPresent('kvah_reading', kvahCtrl);
      addIfPresent('rkvah_lag_reading', rkvahLagCtrl);
      addIfPresent('rkvah_lead_reading', rkvahLeadCtrl);
      addIfPresent('kva_md_t1', kvaMdT1Ctrl);
      addIfPresent('kva_md_t2', kvaMdT2Ctrl);
      addIfPresent('kva_md_t3', kvaMdT3Ctrl);
      addIfPresent('kva_md_t4', kvaMdT4Ctrl);
      addIfPresent('kva_md_d', kvaMdDCtrl);
      addIfPresent('kva_md', kvaMdCtrl);

      // Attach photo only if selected
      if (photoBytes != null && photoName != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'photo',
          photoBytes!,
          filename: photoName,
          contentType: MediaType('image', 'jpeg'),
        ));
      }

      final streamed = await request.send();
      final res = await http.Response.fromStream(streamed);
      final data = jsonDecode(res.body);

      if (res.statusCode == 200 || res.statusCode == 201) {
        setState(() {
          successMessage = isCorrection
              ? 'Correction submitted — pending admin review'
              : (data['message'] ?? 'Reading submitted');
          photoMissingWarning = data['photo_missing'] == true;
          unitsConsumed = double.tryParse(data['units_consumed'].toString());
          monthlyTotal = double.tryParse(data['monthly_total'].toString());
          previousReading = double.tryParse(readingCtrl.text);
          previousDate = dateStr;
          previousTime = timeStr;
          readingCtrl.clear();
          notesCtrl.clear();
          photoFile = null;
          photoBytes = null;
          photoName = null;
          selectedDate = DateTime.now().subtract(const Duration(days: 1));
          selectedTime = TimeOfDay.now();
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
              child: Text('Electricity Meter Reading',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFF5A623)))),
        ]),
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
                      // Correction banner (shown when opened from returned record)
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

                      // Previous reading card
                      previousReading != null
                          ? _infoCard(
                              icon: Icons.history,
                              color: idaGreen,
                              title: 'Previous reading',
                              value:
                                  '${previousReading!.toStringAsFixed(2)} kWh',
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

                      // Date & Time — locked for corrections, auto-captured on submit
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

                      // Meter reading input
                      _sectionLabel('METER READING (kWh)'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: readingCtrl,
                        enabled: !isDateLocked && existingRecordStatus == null,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: idaDark,
                        ),
                        decoration: InputDecoration(
                          hintText: '0.00',
                          hintStyle: TextStyle(
                              color: Colors.grey.shade400, fontSize: 24),
                          prefixIcon:
                              const Icon(Icons.electric_bolt, color: amber),
                          suffix: const Text('kWh',
                              style: TextStyle(
                                  color: idaGreen,
                                  fontWeight: FontWeight.w600)),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: Color(0xFFE0E7D8)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: idaGreen, width: 1.5),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.red),
                          ),
                          errorText: errorMessage,
                        ),
                      ),

                      if (_ocrRunning) ...[
                        const SizedBox(height: 8),
                        Row(children: [
                          const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: idaGreen)),
                          const SizedBox(width: 8),
                          Text('Reading the meter photo…',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade600)),
                        ]),
                      ],
                      if (_ocrPrefilled) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: amber.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(children: [
                            Icon(Icons.auto_awesome, size: 14, color: amber),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                  'Filled from the photo — please check it\'s correct',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      color: amber.withOpacity(0.9))),
                            ),
                          ]),
                        ),
                      ],

                      // Live units consumed preview
                      if (unitsConsumed != null && unitsConsumed! >= 0) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(children: [
                            const Icon(Icons.flash_on,
                                color: idaGreen, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'Units consumed: ${unitsConsumed!.toStringAsFixed(2)} kWh',
                              style: const TextStyle(
                                color: idaDark,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ]),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // Photo (required)
                      Row(children: [
                        _sectionLabel('METER PHOTO'),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                          ),
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
                                            'Tap to attach meter photo (camera or gallery)',
                                            style: TextStyle(
                                                color: Colors.grey.shade500,
                                                fontSize: 13)),
                                        const SizedBox(height: 4),
                                        Text(
                                            'Photo will be compressed automatically · Blurry images will be rejected',
                                            style: TextStyle(
                                                color: Colors.grey.shade400,
                                                fontSize: 11)),
                                      ],
                                    ),
                        ),
                      ),

                      if (!isDateLocked && photoBytes != null) ...[
                        const SizedBox(height: 6),
                        Row(children: [
                          const Icon(Icons.check_circle,
                              color: idaGreen, size: 14),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              photoName ?? 'Photo selected',
                              style: const TextStyle(
                                  fontSize: 12, color: idaGreen),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              photoFile = null;
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

                      // Notes
                      _sectionLabel('NOTES (OPTIONAL)'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: notesCtrl,
                        enabled: !isDateLocked && existingRecordStatus == null,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'Any observations about the meter...',
                          hintStyle: TextStyle(
                              color: Colors.grey.shade400, fontSize: 13),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: Color(0xFFE0E7D8)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: idaGreen, width: 1.5),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // ── Advanced Readings (optional) ──────────────
                      // All nine fields are optional and collapsed by
                      // default - most days, a plain kWh reading is all
                      // that's needed. This exists specifically to feed
                      // the electricity bill projection's demand-charge
                      // accuracy (the plain KVA MD field) and, longer
                      // term, a more precise power-factor calculation.
                      Theme(
                        data: Theme.of(context)
                            .copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text('Advanced Readings (optional)',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700)),
                          initiallyExpanded: _showAdvancedReadings,
                          onExpansionChanged: (v) =>
                              setState(() => _showAdvancedReadings = v),
                          childrenPadding:
                              const EdgeInsets.only(top: 8, bottom: 4),
                          children: [
                            Text(
                              'From the same meter\'s other display screens — used to make the electricity bill projection more accurate, not required for a normal reading.',
                              style: TextStyle(
                                  fontSize: 11.5, color: Colors.grey.shade500),
                            ),
                            const SizedBox(height: 12),
                            Row(children: [
                              Expanded(
                                  child: _advReadingField('KVAH', kvahCtrl)),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: _advReadingField(
                                      'RKVAH (Lag)', rkvahLagCtrl)),
                            ]),
                            const SizedBox(height: 10),
                            Row(children: [
                              Expanded(
                                  child: _advReadingField(
                                      'RKVAH (Lead)', rkvahLeadCtrl)),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: _advReadingField(
                                      'KVA MD (overall)', kvaMdCtrl)),
                            ]),
                            const SizedBox(height: 14),
                            Text(
                              'KVA MD by time zone (T1–T4) and D — captured for cross-checking against a future bill, not used in the projection yet.',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                  fontStyle: FontStyle.italic),
                            ),
                            const SizedBox(height: 10),
                            Row(children: [
                              Expanded(
                                  child: _advReadingField(
                                      'KVA MD T1', kvaMdT1Ctrl)),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: _advReadingField(
                                      'KVA MD T2', kvaMdT2Ctrl)),
                            ]),
                            const SizedBox(height: 10),
                            Row(children: [
                              Expanded(
                                  child: _advReadingField(
                                      'KVA MD T3', kvaMdT3Ctrl)),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: _advReadingField(
                                      'KVA MD T4', kvaMdT4Ctrl)),
                            ]),
                            const SizedBox(height: 10),
                            _advReadingField('KVA MD D', kvaMdDCtrl),
                          ],
                        ),
                      ),

                      const SizedBox(height: 4),

                      // Success card
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
                                if (unitsConsumed != null)
                                  _resultRow('Units consumed today',
                                      '${unitsConsumed!.toStringAsFixed(2)} kWh'),
                                if (monthlyTotal != null)
                                  _resultRow('Monthly total',
                                      '${monthlyTotal!.toStringAsFixed(2)} kWh'),
                                const SizedBox(height: 6),
                                const Text('Pending admin review',
                                    style: TextStyle(
                                        color: Color(0xFF6B7280),
                                        fontSize: 11)),
                              ]),
                        ),

                      // Photo-missing notice — never blocks saving, just a
                      // clear heads-up that no photo was attached this time.
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

                      // Existing-but-not-approved banner — data is shown
                      // pre-filled above, this just explains why.
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

                      // Locked-date banner
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

                      // Submit button
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton.icon(
                          onPressed: (submitting ||
                                  isDateLocked ||
                                  existingRecordStatus != null ||
                                  !canAdd)
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
                                        : !canAdd
                                            ? 'No permission to submit'
                                            : (widget.returnedRecordId != null
                                                ? 'Resubmit for Approval'
                                                : 'Submit Reading'),
                            style: const TextStyle(
                                fontSize: 16,
                                color: Colors.white,
                                fontWeight: FontWeight.w600),
                          ),
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

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF6B7280),
            letterSpacing: 0.8),
      );

  Widget _advReadingField(String label, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      enabled: !isDateLocked && existingRecordStatus == null,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE0E7D8))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: idaGreen, width: 1.5)),
      ),
    );
  }

  Widget _resultRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
            Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: idaDark)),
          ],
        ),
      );

  Widget _pickerTile({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) =>
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
                        color: idaDark)),
              ),
              const Icon(Icons.edit, size: 14, color: Color(0xFF9CA3AF)),
            ]),
          ]),
        ),
      );

  Widget _infoCard({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
    required String sub,
  }) =>
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
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
              const SizedBox(height: 2),
              Text(value,
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, color: color)),
              Text(sub,
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
            ]),
          ),
        ]),
      );
}
