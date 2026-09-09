// lib/screens/face_login_screen.dart
//
// Face login — an ADDITIONAL way to sign in, alongside the existing
// username/password form (not a replacement; password keeps working
// exactly as before). Structured directly on face_enrollment_screen.dart's
// pattern: open the camera, let the person retake until happy, compute
// the on-device embedding, then send it to the server.
//
// The one real difference from enrollment: this call carries NO auth
// token, because the whole point is the person isn't logged in yet.
// POST /api/auth/face-login is a public endpoint on the server for
// exactly that reason (see auth.js) - it's rate-limited server-side,
// so repeated failures here will eventually get a clear "too many
// attempts" message rather than hanging or silently retrying forever.

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:camera/camera.dart';
import '../services/face_recognition_service.dart';
import '../services/api_service.dart';

class FaceLoginScreen extends StatefulWidget {
  const FaceLoginScreen({super.key});

  @override
  State<FaceLoginScreen> createState() => _FaceLoginScreenState();
}

class _FaceLoginScreenState extends State<FaceLoginScreen> {
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
      // Covers both a real camera/model failure AND the web stub's
      // UnsupportedError - face login simply isn't available there,
      // and the person still has the password form one tap back.
      setState(() => _error =
          'Face login isn\'t available here: $e\n\nUse your password instead.');
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

  Future<void> _confirmAndLogin() async {
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
      final res = await http.post(
        Uri.parse('${ApiService.baseUrl}/api/auth/face-login'),
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        // Deliberately no Authorization header - this IS the login,
        // there's no token to send yet.
        body: jsonEncode({'embedding': embedding}),
      );
      final result = jsonDecode(res.body);
      if (res.statusCode == 200 && result['token'] != null) {
        await ApiService.saveSession(result);
        if (mounted) Navigator.pushReplacementNamed(context, '/dashboard');
      } else if (res.statusCode == 429) {
        setState(() => _error =
            result['error'] ?? 'Too many attempts — please use your password instead.');
      } else {
        setState(() => _error =
            result['error'] ?? 'Face not recognized. Try again or use your password.');
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
        title: const Text('Sign In With Face',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: !_ready
          ? Center(
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!,
                              style: const TextStyle(color: Colors.white),
                              textAlign: TextAlign.center),
                          const SizedBox(height: 20),
                          OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.white)),
                            child: const Text('Back to password login',
                                style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
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
                            onPressed: _processing ? null : _confirmAndLogin,
                            icon: _processing
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.login,
                                    color: Colors.white),
                            label: Text(
                                _processing ? 'Signing in…' : 'Sign In',
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
