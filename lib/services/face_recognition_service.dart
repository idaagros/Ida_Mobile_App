// lib/services/face_recognition_service.dart
//
// This is the file everything else imports — never import
// face_recognition_service_io.dart or _stub.dart directly.
//
// The `export ... if (dart.library.io) ...` line below is a Dart
// conditional export: the compiler picks whichever file actually
// applies to the platform being compiled for, BEFORE compiling
// anything else. On Android/iOS/desktop, `dart:io` exists, so the
// real implementation (face_recognition_service_io.dart, which uses
// flutter_litert + ML Kit) is used. On web, `dart:io` does not exist,
// so the stub (face_recognition_service_stub.dart, zero ffi-dependent
// imports) is used instead.
//
// This is what keeps the REST of the app compiling for web — without
// this, flutter_litert's `dart:ffi` import gets pulled into the web
// build's dependency graph the moment anything imports this file,
// and the whole build fails (exactly what happened before this file
// existed). With it, a web build simply can't reach real face
// recognition (calling it throws a clear UnsupportedError — see the
// stub), while a real Android/iOS build gets the genuine
// implementation, unchanged.

export 'face_recognition_service_stub.dart'
    if (dart.library.io) 'face_recognition_service_io.dart';
