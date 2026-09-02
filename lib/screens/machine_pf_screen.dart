import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../services/image_helper.dart';
import '../services/colored_date_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MachinePfScreen extends StatefulWidget {
  final String? returnedRecordId;
  final String? adminNote;
  const MachinePfScreen({super.key, this.returnedRecordId, this.adminNote});
  @override
  State<MachinePfScreen> createState() => _MachinePfScreenState();
}

class _MachinePfScreenState extends State<MachinePfScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const amber = Color(0xFFF5A623);
  static const baseUrl = 'https://excusable-moving-preorder.ngrok-free.dev/api';

  final pfCtrl = TextEditingController();
  final notesCtrl = TextEditingController();

  DateTime selectedDate = DateTime.now().subtract(const Duration(days: 1));
  TimeOfDay selectedTime = TimeOfDay.now();

  Uint8List? photoBytes;
  String? photoName;

  bool loading = false;
  bool submitting = false;

  double? previousPf;
  String? previousDate;
  String? previousTime;
  String? successMessage;
  String? errorMessage;
  bool photoMissingWarning = false;

  // When the selected date already has an APPROVED reading, the form
  // switches into read-only mode: shows what was entered, blocks editing.
  // Only an admin can change an approved record (via Admin Review).
  bool isDateLocked = false;
  Map<String, dynamic>? lockedRecord;
  String? existingRecordStatus;

  // photo_url from the DB is a relative path like '/uploads/machine_pf/x.jpg'
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
    pfCtrl.addListener(_onPfChanged);
    if (widget.returnedRecordId != null) {
      _fetchReturnedRecord();
    } else {
      _applySelectedDate();
    }
  }

  // Triggers a rebuild as the PF value is typed, so the inline
  // healthy/low banner updates live.
  void _onPfChanged() {
    if (mounted) setState(() {});
  }

  Future<Map<String, String>> get _headers async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${prefs.getString('token') ?? ''}',
      'ngrok-skip-browser-warning': 'true',
    };
  }

  Future<void> _fetchReturnedRecord() async {
    setState(() => loading = true);
    try {
      final h = await _headers;
      final res = await http.get(
        Uri.parse('$baseUrl/machine-pf/${widget.returnedRecordId}'),
        headers: h,
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _returnedRecord = data;
          pfCtrl.text = data['pf_value']?.toString() ?? '';
          notesCtrl.text = data['notes']?.toString() ?? '';
          try {
            selectedDate = DateTime.parse(data['reading_date']);
          } catch (_) {}
        });
      }
    } catch (e) {
      debugPrint('Fetch returned record error: $e');
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    pfCtrl.removeListener(_onPfChanged);
    pfCtrl.dispose();
    notesCtrl.dispose();
    super.dispose();
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

  // Fetches the PF reading immediately preceding `selectedDate`. PF has
  // no "consumption" to calculate (it's a point-in-time measurement, not
  // cumulative), so this is shown purely as context — same date-aware
  // pattern used across every other reading module.
  Future<void> _loadPreviousReading() async {
    setState(() => loading = true);
    try {
      final h = await _headers;
      final dateStr = DateFormat('yyyy-MM-dd').format(selectedDate);
      final res = await http.get(
        Uri.parse('$baseUrl/machine-pf/previous?date=$dateStr'),
        headers: h,
      );
      if (res.statusCode == 200 && res.body != 'null') {
        final data = jsonDecode(res.body);
        setState(() {
          if (data != null) {
            previousPf = double.tryParse(data['pf_value'].toString());
            previousDate = data['reading_date']?.toString();
            previousTime = data['reading_time']?.toString();
          } else {
            previousPf = null;
            previousDate = null;
            previousTime = null;
          }
        });
      } else {
        setState(() {
          previousPf = null;
          previousDate = null;
          previousTime = null;
        });
      }
    } catch (e) {
      debugPrint('Previous PF fetch error: $e');
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
      module: 'machine-pf',
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
          pfCtrl.text = record['pf_value']?.toString() ?? '';
          notesCtrl.text = record['notes']?.toString() ?? '';
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
        pfCtrl.clear();
        notesCtrl.clear();
        photoBytes = null;
        photoName = null;
        errorMessage = null;
      });
    }

    // Previous-reading lookup is always recalculated against the entry
    // immediately before the newly selected date, regardless of whether
    // the date itself turns out to be locked.
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
        Uri.parse('$baseUrl/machine-pf/check-date?date=$dateStr'),
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
    if (pfCtrl.text.isEmpty) {
      setState(() => errorMessage = 'Please enter the PF (Power Factor) value');
      return;
    }
    final pf = double.tryParse(pfCtrl.text);
    if (pf == null || pf <= 0 || pf > 1) {
      setState(() => errorMessage =
          'PF value must be greater than 0 and at most 1 (e.g. 0.97)');
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

      final isCorrection = widget.returnedRecordId != null;
      final reqUrl = isCorrection
          ? Uri.parse('$baseUrl/machine-pf/${widget.returnedRecordId}')
          : Uri.parse('$baseUrl/machine-pf');

      final request =
          http.MultipartRequest(isCorrection ? 'PUT' : 'POST', reqUrl)
            ..headers.addAll(h)
            ..fields['reading_date'] = dateStr
            ..fields['reading_time'] = timeStr
            ..fields['pf_value'] = pfCtrl.text
            ..fields['notes'] = notesCtrl.text
            ..fields['status'] = 'pending';

      if (photoBytes != null && photoName != null) {
        request.files.add(http.MultipartFile.fromBytes('photo', photoBytes!,
            filename: photoName, contentType: MediaType('image', 'jpeg')));
      }

      final streamed = await request.send();
      final res = await http.Response.fromStream(streamed);
      final data = jsonDecode(res.body);

      if (res.statusCode == 200 || res.statusCode == 201) {
        setState(() {
          successMessage = isCorrection
              ? 'Correction submitted — pending admin review'
              : (data['message'] ?? 'PF reading submitted');
          photoMissingWarning = data['photo_missing'] == true;
          previousPf = double.tryParse(pfCtrl.text);
          previousDate = dateStr;
          previousTime = timeStr;

          final pfAlert = data['pf_alert'];
          if (pfAlert != null && mounted) {
            Future.delayed(const Duration(milliseconds: 500), () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  title: const Row(children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Color(0xFFB23A3A), size: 22),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('Low PF Recorded',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFB23A3A))),
                    ),
                  ]),
                  content: Text(
                    'PF of ${(double.tryParse(pfAlert['pf_value']?.toString() ?? '') ?? 0).toStringAsFixed(3)} is below the '
                    'healthy threshold (0.99). This may lead to a power-factor '
                    'penalty on the electricity bill. The admin has been notified.',
                    style:
                        const TextStyle(fontSize: 13, color: Color(0xFF374151)),
                  ),
                  actions: [
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style:
                          ElevatedButton.styleFrom(backgroundColor: idaGreen),
                      child: const Text('OK',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );
            });
          }

          pfCtrl.clear();
          notesCtrl.clear();
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
    final pf = double.tryParse(pfCtrl.text);
    final showPfBanner = !isDateLocked && pf != null && pf > 0 && pf <= 1;
    final isLowPf = showPfBanner && pf! < 0.99;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F5),
      appBar: AppBar(
        backgroundColor: idaDark,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(children: [
          Image.asset('assets/images/idalogo.png', height: 28),
          const SizedBox(width: 10),
          const Flexible(
              child: Text('Machine PF Reading',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFF5A623)))),
        ]),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: idaGreen))
          : SingleChildScrollView(
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
                                  'Please correct the PF reading below and resubmit.',
                                  style: TextStyle(
                                      fontSize: 12, color: Color(0xFF9CA3AF))),
                            ]),
                      ),
                    ],

                    // Previous PF reading card (context only — no diff math)
                    previousPf != null
                        ? _infoCard(
                            icon: Icons.history,
                            color: idaGreen,
                            title: 'Previous PF reading',
                            value: previousPf!.toStringAsFixed(3),
                            sub:
                                'Recorded on ${_formatRecordedOn(previousDate, previousTime)}',
                          )
                        : _infoCard(
                            icon: Icons.info_outline,
                            color: amber,
                            title: 'First record',
                            value: 'No previous PF reading found',
                            sub: 'This will be the first recorded entry',
                          ),

                    const SizedBox(height: 20),

                    // Date & Time
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
                        ]),
                      ),
                    ] else ...[
                      Row(children: [
                        Expanded(
                            child: _pickerTile(
                          icon: Icons.calendar_today,
                          label: 'Date',
                          value: DateFormat('dd MMM yyyy').format(selectedDate),
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

                    // PF value input
                    Row(children: [
                      _sectionLabel('PF (POWER FACTOR)'),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                            color: const Color(0xFFFDE8E8),
                            borderRadius: BorderRadius.circular(10)),
                        child: const Text('Required',
                            style: TextStyle(
                                fontSize: 10, color: Color(0xFFB23A3A))),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    TextField(
                      controller: pfCtrl,
                      enabled: !isDateLocked && existingRecordStatus == null,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: idaDark),
                      decoration: InputDecoration(
                        hintText: '0.99',
                        hintStyle: TextStyle(
                            color: Colors.grey.shade400, fontSize: 24),
                        prefixIcon: const Icon(Icons.bolt, color: idaGreen),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: Color(0xFFE0E7D8))),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: idaGreen, width: 1.5)),
                        errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.red)),
                        errorText: errorMessage,
                      ),
                    ),

                    if (showPfBanner) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isLowPf
                              ? const Color(0xFFFDE8E8)
                              : const Color(0xFFE8F5E2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(children: [
                          Icon(
                            isLowPf
                                ? Icons.warning_amber_rounded
                                : Icons.check_circle,
                            color: isLowPf ? const Color(0xFFB23A3A) : idaGreen,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isLowPf
                                  ? 'Low PF — below 0.99 may incur a power-factor penalty. Admin will be alerted.'
                                  : 'PF looks healthy.',
                              style: TextStyle(
                                color:
                                    isLowPf ? const Color(0xFFB23A3A) : idaDark,
                                fontWeight: FontWeight.w600,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Photo (optional)
                    Row(children: [
                      _sectionLabel('PF METER PHOTO'),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10)),
                        child: const Text('Optional but recommended',
                            style: TextStyle(fontSize: 10, color: Colors.grey)),
                      ),
                    ]),
                    const SizedBox(height: 8),

                    GestureDetector(
                      onTap: (isDateLocked || existingRecordStatus != null)
                          ? null
                          : _pickPhoto,
                      child: Container(
                        width: double.infinity,
                        height: (photoBytes != null || _lockedPhotoUrl != null)
                            ? 200
                            : 110,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                                (photoBytes != null || _lockedPhotoUrl != null)
                                    ? idaGreen
                                    : const Color(0xFFE0E7D8),
                            width:
                                (photoBytes != null || _lockedPhotoUrl != null)
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
                                                    color: Colors.grey.shade500,
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
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.add_a_photo_outlined,
                                          size: 32,
                                          color: Colors.grey.shade400),
                                      const SizedBox(height: 8),
                                      Text(
                                          'Tap to attach PF meter photo (camera or gallery)',
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
                            style:
                                const TextStyle(fontSize: 12, color: idaGreen),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            photoBytes = null;
                            photoName = null;
                          }),
                          style: TextButton.styleFrom(padding: EdgeInsets.zero),
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
                        hintText: 'Any observations about the PF meter...',
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

                    const SizedBox(height: 24),

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
                                Text('PF reading submitted!',
                                    style: TextStyle(
                                        color: idaDark,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14)),
                              ]),
                              const SizedBox(height: 6),
                              const Text('Pending admin review',
                                  style: TextStyle(
                                      color: Color(0xFF6B7280), fontSize: 11)),
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
                                  'Photo not uploaded. Please upload a photo of the PF meter — '
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
                                      ? 'A PF reading already exists for this date and was returned for correction. Open it from your returned records to edit it.'
                                      : 'A PF reading already exists for this date and is pending admin review. It cannot be edited here right now.',
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
                              color: const Color(0xFF1A73E8).withOpacity(0.3)),
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
                                          : 'Submit PF Reading'),
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
            ),
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
