# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }

# Google Sign-In / Play Services
-keep class com.google.android.gms.** { *; }

# Supabase / OkHttp (used by supabase_flutter)
-dontwarn okhttp3.**
-dontwarn okio.**

# Play Core (deferred components, not used but referenced by Flutter engine)
-dontwarn com.google.android.play.core.**
