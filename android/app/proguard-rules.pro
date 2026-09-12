# android/app/proguard-rules.pro
#
# google_mlkit_text_recognition's plugin registration code references
# ALL script-specific recognizer option classes (Chinese, Devanagari,
# Japanese, Korean, Latin) in its initialize() method, even though
# this app only uses TextRecognitionScript.latin. Only the Latin
# recognizer's actual dependency is pulled in by the plugin, so R8's
# minifier (running because this is a release/assembleRelease build)
# strips the other four as unused - then fails because the plugin
# code still references them. This does NOT mean those languages are
# bundled or usable; it just stops R8 from erroring on a reference
# path the plugin always includes regardless of which script you
# actually configured.
#
# This is a common, well-documented issue for this exact plugin
# (confirmed directly against multiple real reports of this identical
# error). The broad keep below is the widely-used, proven fix -
# narrower per-package rules risk missing some other ML Kit reference
# path and re-failing on a different missing class.
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

# Same category of issue can surface for the Play Services layer ML
# Kit builds on.
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-dontwarn com.google.android.gms.internal.mlkit_vision_text_common.**
