// lib/screens/admin/user_face_enrollment_screen.dart
//
// Admin-only: capture a user's (app account, not field worker) face
// once so they can use Face Login alongside their password. Same
// structure as face_enrollment_screen.dart (worker enrollment for
// attendance) - opens the camera, lets the admin retake until happy,
// computes and saves the embedding (never the photo itself) via
// POST /api/auth/face-enroll.

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:camera/camera.dart';
import '../../services/face_recognition_service.dart';
import '../../services/api_service.dart';

class UserFaceEnrollmentScreen extends StatefulWidget {
  final String userId;
  final String userName;
  const UserFaceEnrollmentScreen(
      {super.key, required this.userId, required this.userName});

  @override
  State<UserFaceEnrollmentScreen> createState() =>
      _UserFaceEnrollmentScreenState();
}

class _UserFaceEnrollmentScreenState extends State<UserFaceEnrollmentScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);

  CameraController? _controller;
  final _faceService = FaceRecognitionService();
  bool _ready = false;
  bool _processing = false;
  String? _error;
  XFile? _capturedPhoto;
  Uint8List? _capturedBytes;

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

  Future<void> _capture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() => _error = null);
    try {
      final file = await _controller!.takePicture();
      final bytes = await file.readAsBytes();
      setState(() {
        _capturedPhoto = file;
        _capturedBytes = bytes;
      });
    } catch (e) {
      setState(() => _error = 'Capture failed: $e');
    }
  }

  void _retake() => setState(() {
        _capturedPhoto = null;
        _capturedBytes = null;
      });

  Future<void> _confirmAndEnroll() async {
    if (_capturedPhoto == null) return;
    setState(() {
      _processing = true;
      _error = null;
    });
    try {
      final embedding =
          await _faceService.computeEmbeddingFromFile(_capturedPhoto!.path);
      if (embedding == null) {
        setState(() => _error =
            'No face detected — please retake with your face clearly visible');
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final res = await http.post(
        Uri.parse('${ApiService.baseUrl}/api/auth/face-enroll'),
        headers: {
          'Authorization': 'Bearer ${prefs.getString('token') ?? ''}',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({'user_id': widget.userId, 'embedding': embedding}),
      );
      if (res.statusCode == 200) {
        if (mounted) Navigator.pop(context, true);
      } else {
        final data = jsonDecode(res.body);
        setState(() => _error = data['error'] ?? 'Failed to save enrollment');
      }
    } on MultipleFacesException catch (e) {
      setState(() => _error = e.toString());
    } catch (e) {
      setState(() => _error = 'Could not reach server: $e');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('Enroll Face Login — ${widget.userName}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: !_ready
          ? Center(
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!,
                          style: const TextStyle(color: Colors.white),
                          textAlign: TextAlign.center),
                    )
                  : const CircularProgressIndicator(color: idaGreen),
            )
          : Column(children: [
              Expanded(
                child: _capturedPhoto == null
                    ? CameraPreview(_controller!)
                    : Image.memory(_capturedBytes!,
                        fit: BoxFit.cover, width: double.infinity),
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
                            onPressed: _capture,
                            icon: const Icon(Icons.camera_alt,
                                color: Colors.white),
                            label: const Text('Capture',
                                style: TextStyle(color: Colors.white)),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: idaGreen,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 28, vertical: 14)),
                          ),
                        ],
                      )
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
                          ElevatedButton.icon(
                            onPressed: _processing ? null : _confirmAndEnroll,
                            icon: _processing
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.check,
                                    color: Colors.white),
                            label: Text(
                                _processing ? 'Saving…' : 'Use This Photo',
                                style: const TextStyle(color: Colors.white)),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: idaGreen,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 14)),
                          ),
                        ],
                      ),
              ),
            ]),
    );
  }
}
