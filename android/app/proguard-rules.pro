# WebRTC proguard rules
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

# Flutter Local Notifications / Gson rules
# These are required to prevent "TypeToken must be created with a type argument" error
-keepattributes Signature,EnclosingMethod,InnerClasses,*Annotation*

-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.google.gson.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

-dontwarn com.google.gson.**
