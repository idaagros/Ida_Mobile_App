// lib/screens/face_attendance_capture_screen.dart
//
// The Stage A "mark via face" alternative to manually searching the
// worker list. Opens the camera, captures a photo, computes its
// embedding, and asks the server for the closest enrolled match.
// On a confirmed match, pops back to the caller with the matched
// worker's id/name/gender/daily_wage — the CALLER (attendance_screen)
// decides what to do with that (add to the present list), reusing its
// existing logic rather than this screen touching that state itself.

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:camera/camera.dart';
import '../services/face_recognition_service.dart';

class FaceMatchResult {
  final int workerId;
  final String name;
  final String? gender;
  final dynamic dailyWage;
  FaceMatchResult(
      {required this.workerId,
      required this.name,
      this.gender,
      this.dailyWage});
}

class FaceAttendanceCaptureScreen extends StatefulWidget {
  const FaceAttendanceCaptureScreen({super.key});
  @override
  State<FaceAttendanceCaptureScreen> createState() =>
      _FaceAttendanceCaptureScreenState();
}

class _FaceAttendanceCaptureScreenState
    extends State<FaceAttendanceCaptureScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const baseUrl = 'https://excusable-moving-preorder.ngrok-free.dev/api';

  CameraController? _controller;
  final _faceService = FaceRecognitionService();
  bool _ready = false;
  bool _processing = false;
  String? _error;
  XFile? _capturedPhoto;
  Uint8List?
      _capturedBytes; // XFile.path isn't a real filesystem path on web; read bytes instead for display
  Map<String, dynamic>?
      _matchResult; // {matched, name, worker_id, gender, daily_wage, distance}

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _faceService.loadModel();
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _controller =
          CameraController(front, ResolutionPreset.medium, enableAudio: false);
      await _controller!.initialize();
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      setState(() => _error = 'Could not start camera/model: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _faceService.dispose();
    super.dispose();
  }

  Future<void> _captureAndMatch() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() {
      _error = null;
      _matchResult = null;
    });
    try {
      final file = await _controller!.takePicture();
      final bytes = await file
          .readAsBytes(); // cross-platform — works on web too, unlike dart:io File
      setState(() {
        _capturedPhoto = file;
        _capturedBytes = bytes;
        _processing = true;
      });
      final embedding = await _faceService.computeEmbeddingFromFile(file.path);
      if (embedding == null) {
        setState(() => _error =
            'No face detected — please retake with your face clearly visible');
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final res = await http.post(
        Uri.parse('$baseUrl/face/match'),
        headers: {
          'Authorization': 'Bearer ${prefs.getString('token') ?? ''}',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({'embedding': embedding}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() => _matchResult = data);
      } else {
        final data = jsonDecode(res.body);
        setState(() => _error = data['error'] ?? 'Recognition failed');
      }
    } on MultipleFacesException catch (e) {
      setState(() => _error = e.toString());
    } catch (e) {
      setState(() => _error = 'Could not reach server: $e');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _retake() {
    setState(() {
      _capturedPhoto = null;
      _capturedBytes = null;
      _matchResult = null;
      _error = null;
    });
  }

  void _confirmMatch() {
    final m = _matchResult;
    if (m == null || m['matched'] != true) return;
    Navigator.pop(
      context,
      FaceMatchResult(
          workerId: m['worker_id'],
          name: m['name'],
          gender: m['gender'],
          dailyWage: m['daily_wage']),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Mark via Face',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: !_ready
          ? Center(
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!,
                          style: const TextStyle(color: Colors.white),
                          textAlign: TextAlign.center))
                  : const CircularProgressIndicator(color: idaGreen),
            )
          : Column(children: [
              Expanded(
                child: _capturedPhoto == null
                    ? CameraPreview(_controller!)
                    : Stack(fit: StackFit.expand, children: [
                        Image.memory(_capturedBytes!, fit: BoxFit.cover),
                        if (_processing)
                          Container(
                            color: Colors.black54,
                            alignment: Alignment.center,
                            child: const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(color: idaGreen),
                                  SizedBox(height: 12),
                                  Text('Recognizing…',
                                      style: TextStyle(color: Colors.white)),
                                ]),
                          ),
                      ]),
              ),
              if (_matchResult != null && _matchResult!['matched'] == true)
                Container(
                  width: double.infinity,
                  color: idaGreen,
                  padding: const EdgeInsets.all(14),
                  child: Column(children: [
                    Text('Recognized: ${_matchResult!['name']}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('Confidence distance: ${_matchResult!['distance']}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11)),
                  ]),
                ),
              if (_matchResult != null && _matchResult!['matched'] == false)
                Container(
                  width: double.infinity,
                  color: Colors.orange.shade800,
                  padding: const EdgeInsets.all(14),
                  child: const Text(
                      'No confident match found — try retaking, or use the manual list instead',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center),
                ),
              if (_error != null)
                Container(
                  width: double.infinity,
                  color: Colors.red.shade900,
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 12.5),
                      textAlign: TextAlign.center),
                ),
              Container(
                color: idaDark,
                padding: const EdgeInsets.all(20),
                child: _capturedPhoto == null
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                            ElevatedButton.icon(
                              onPressed: _captureAndMatch,
                              icon: const Icon(Icons.camera_alt,
                                  color: Colors.white),
                              label: const Text('Capture & Recognize',
                                  style: TextStyle(color: Colors.white)),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: idaGreen,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 14)),
                            ),
                          ])
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                            OutlinedButton.icon(
                              onPressed: _processing ? null : _retake,
                              icon: const Icon(Icons.refresh,
                                  color: Colors.white),
                              label: const Text('Retake',
                                  style: TextStyle(color: Colors.white)),
                              style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Colors.white),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 14)),
                            ),
                            if (_matchResult != null &&
                                _matchResult!['matched'] == true)
                              ElevatedButton.icon(
                                onPressed: _confirmMatch,
                                icon: const Icon(Icons.check,
                                    color: Colors.white),
                                label: const Text('Add to Present',
                                    style: TextStyle(color: Colors.white)),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: idaGreen,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 14)),
                              ),
                          ]),
              ),
            ]),
    );
  }
}
