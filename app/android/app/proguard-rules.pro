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
