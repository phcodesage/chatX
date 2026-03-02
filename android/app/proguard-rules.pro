# WebRTC proguard rules to prevent obfuscation issues in release builds
-keep class org.webrtc.** { *; }
-keep class com.cloudwebrtc.webrtc.** { *; }
-dontwarn org.webrtc.**

# Keep Flutter WebRTC plugin classes
-keep class io.flutter.plugins.webrtc.** { *; }

# Keep MediaProjection related classes for screen sharing
-keep class android.media.projection.** { *; }
-keep class androidx.media.** { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep Flutter plugin registrant
-keep class io.flutter.plugins.** { *; }

# Keep method channel classes
-keep class io.flutter.plugin.common.** { *; }