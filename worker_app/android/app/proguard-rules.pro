# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

-keep class dev.flutter.pigeon.** { *; }

# AndroidX / Support libraries
-keep class androidx.lifecycle.DefaultLifecycleObserver

-keep class com.example.** { *; }

# Google Play Core Library (Split Install / Dynamic Feature Modules)
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

-keep class com.google.android.gms.tasks.** { *; }
-dontwarn com.google.android.gms.tasks.**
-keep class com.google.android.play.core.tasks.** { *; }