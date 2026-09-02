// lib/services/face_recognition_service_io.dart
//
// The REAL implementation — only ever compiled in when
// dart.library.io is available (Android/iOS/desktop), selected by the
// conditional export in face_recognition_service.dart. Never reached
// by a web build, which is what keeps `dart:ffi` (required by
// flutter_litert) out of the web compilation graph entirely.
//
// Turns a photo into a 192-number "embedding" — a face fingerprint,
// not the image itself. Two steps:
//   1. Google ML Kit finds the face and its bounding box.
//   2. That region is cropped, resized to 112×112, normalized, and
//      run through the MobileFaceNet TFLite model (assets/models/
//      mobilefacenet.tflite) to get the 192-number vector.
//
// Mirrors the exact preprocessing (crop with ~10px padding, resize to
// 112×112, normalize each channel as (value-128)/128) that this
// specific model was built and tested against, so the numbers coming
// out are meaningful to compare against enrolled embeddings.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter_litert/flutter_litert.dart';
import 'package:image/image.dart' as img;
import 'face_recognition_types.dart';
export 'face_recognition_types.dart';

class FaceRecognitionService {
  static const modelAssetPath = 'assets/models/mobilefacenet.tflite';
  static const embeddingLength = 192;
  static const inputSize = 112;

  Interpreter? _interpreter;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(performanceMode: FaceDetectorMode.accurate),
  );

  bool get isModelLoaded => _interpreter != null;

  Future<void> loadModel() async {
    if (_interpreter != null) return;
    _interpreter = await Interpreter.fromAsset(modelAssetPath);
  }

  /// Detects the (largest, if several) face in the photo at [imagePath]
  /// and returns its 192-number embedding, or null if no face was found.
  /// Throws [MultipleFacesException] if more than one face is clearly
  /// visible — safer to ask the user to retake than guess which one.
  Future<List<double>?> computeEmbeddingFromFile(String imagePath,
      {bool allowMultiple = false}) async {
    if (_interpreter == null) {
      throw StateError('Model not loaded — call loadModel() first');
    }

    final inputImage = InputImage.fromFilePath(imagePath);
    final faces = await _faceDetector.processImage(inputImage);
    if (faces.isEmpty) return null;

    if (faces.length > 1 && !allowMultiple) {
      throw MultipleFacesException(faces.length);
    }

    faces.sort((a, b) => (b.boundingBox.width * b.boundingBox.height)
        .compareTo(a.boundingBox.width * a.boundingBox.height));
    final face = faces.first;

    final bytes = await File(imagePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    const pad = 12;
    final rect = face.boundingBox;
    final x = (rect.left - pad).round().clamp(0, decoded.width - 1);
    final y = (rect.top - pad).round().clamp(0, decoded.height - 1);
    final w = (rect.width + pad * 2).round().clamp(1, decoded.width - x);
    final h = (rect.height + pad * 2).round().clamp(1, decoded.height - y);

    final cropped = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
    final resized =
        img.copyResize(cropped, width: inputSize, height: inputSize);

    final input =
        _imageToInputTensor(resized).reshape([1, inputSize, inputSize, 3]);
    final output = List.generate(1, (_) => List.filled(embeddingLength, 0.0));
    _interpreter!.run(input, output);

    return List<double>.from(output[0]);
  }

  Float32List _imageToInputTensor(img.Image image) {
    final buffer = Float32List(inputSize * inputSize * 3);
    int i = 0;
    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final pixel = image.getPixel(x, y);
        buffer[i++] = (pixel.r - 128) / 128;
        buffer[i++] = (pixel.g - 128) / 128;
        buffer[i++] = (pixel.b - 128) / 128;
      }
    }
    return buffer;
  }

  static double euclideanDistance(List<double> a, List<double> b) {
    double sum = 0;
    for (int i = 0; i < a.length; i++) {
      sum += (a[i] - b[i]) * (a[i] - b[i]);
    }
    return sqrt(sum);
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _faceDetector.close();
  }
}
