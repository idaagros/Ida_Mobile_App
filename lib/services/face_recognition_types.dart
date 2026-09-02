// lib/services/face_recognition_types.dart
//
// Platform-independent — shared by both the real (mobile) and stub
// (web) implementations of FaceRecognitionService, so callers can
// catch it regardless of which platform they're running on.

class MultipleFacesException implements Exception {
  final int count;
  MultipleFacesException(this.count);
  @override
  String toString() => 'Detected $count faces — please retake with only one person in frame';
}
