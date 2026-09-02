// lib/services/face_recognition_service_stub.dart
//
// Selected automatically on web builds (see the conditional export in
// face_recognition_service.dart) — same class name and method
// signatures as the real implementation, so calling code doesn't need
// to know which one it got, but with NO imports of flutter_litert or
// google_mlkit_face_detection (both require dart:ffi, which doesn't
// exist on web — that's what breaks a web compile if this stub isn't
// used instead).
//
// Every method throws a clear, specific error rather than silently
// doing nothing — if this somehow gets reached at runtime on web
// (it shouldn't, since the calling screens are only ever launched
// from mobile-only entry points), the failure explains itself instead
// of looking like a mysterious bug.

export 'face_recognition_types.dart';

class FaceRecognitionService {
  static const embeddingLength = 192;

  bool get isModelLoaded => false;

  Future<void> loadModel() async {
    throw UnsupportedError(
      'Face recognition requires an Android or iOS build — it is not available in the web preview.',
    );
  }

  Future<List<double>?> computeEmbeddingFromFile(String imagePath,
      {bool allowMultiple = false}) async {
    throw UnsupportedError(
      'Face recognition requires an Android or iOS build — it is not available in the web preview.',
    );
  }

  static double euclideanDistance(List<double> a, List<double> b) {
    throw UnsupportedError(
        'Face recognition requires an Android or iOS build.');
  }

  void dispose() {}
}
