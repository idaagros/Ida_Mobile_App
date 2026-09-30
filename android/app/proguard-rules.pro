# android/app/proguard-rules.pro
#
# Rules for the release build's shrinking step (R8).
#
# -dontwarn = "this class is referenced but deliberately not in the app -
# don't stop the build". It never removes anything; it only lets R8 finish.
# -keep     = "don't strip or rename this", for code that is looked up by
# name at run time (plugins, native libraries).

# ── ML Kit text recognition ─────────────────────────────────────────────
# The plugin's code refers to the recognisers for every script (Chinese,
# Devanagari, Japanese, Korean, Latin), but the app only includes Latin and
# Devanagari. Without these lines R8 stops with "Missing class
# com.google.mlkit.vision.text.chinese..." (30 Sep 2026 build).
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_** { *; }

# ── Flutter engine: Play Store split-install (deferred components) ─────
# Referenced by Flutter's engine but not used by this app.
-dontwarn com.google.android.play.core.**

# ── LiteRT / TensorFlow Lite (face recognition) ─────────────────────────
# The GPU helper classes are optional and not bundled.
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.gpu.**
-keep class com.google.ai.edge.litert.** { *; }
-dontwarn com.google.ai.edge.litert.gpu.**

# ── Phone notifications (flutter_local_notifications) ──────────────────
# Keep its classes and the generic type information it relies on.
-keep class com.dexterous.** { *; }
-keepattributes Signature
-keepattributes *Annotation*

# ── Background notification check (workmanager) ────────────────────────
-keep class dev.fluttercommunity.workmanager.** { *; }
-keep class androidx.work.** { *; }

# ── Harmless missing annotation classes some libraries refer to ────────
-dontwarn javax.annotation.**
-dontwarn org.checkerframework.**
-dontwarn com.google.errorprone.annotations.**