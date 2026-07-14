# Flutter specific
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Firebase Messaging
-keep class com.google.firebase.messaging.** { *; }
-keep class com.google.firebase.iid.** { *; }

# Firebase Crashlytics
-keep class com.google.firebase.crashlytics.** { *; }

# Supabase
-keep class com.supabase.** { *; }
-keep class com.postgrest.** { *; }
-keep class com.auth0.** { *; }

# GSON
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keep class * implements com.google.gson.JsonSerializable { *; }
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# UCrop
-keep class com.yalantis.ucrop.** { *; }
-dontwarn com.yalantis.ucrop.**
-keep class com.bumptech.glide.** { *; }
-dontwarn com.bumptech.glide.**

# Models
-keep class com.example.flutter_application_1.models.** { *; }

# Parcelable
-keepclassmembers class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Serializable
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Local Notifications
-keep class com.dexterous.** { *; }
-keep class com.flutter.** { *; }

# Image Picker / Camera
-keep class android.support.v7.app.** { *; }
-keep class androidx.appcompat.app.** { *; }

# Third Party
-dontwarn javax.annotation.**
-dontwarn org.codehaus.mojo.**
-dontwarn org.apache.**
-dontwarn com.squareup.**
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn org.slf4j.**

# AndroidX
-keep class androidx.** { *; }
-keep public class * extends androidx.**

# Kotlin
-keep class kotlin.Metadata { *; }

# Enum
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Native
-keepclasseswithmembernames class * {
    native <methods>;
}

# Android Components
-keep public class * extends android.app.Activity
-keep public class * extends android.app.Service
-keep public class * extends android.content.BroadcastReceiver
-keep public class * extends android.content.ContentProvider

# R classes
-keep class **.R$* { *; }
-keep class **.R { *; }

# Optimization
-optimizationpasses 5
-dontpreverify
-dontoptimize
-dontobfuscate

# Debug
-keepattributes SourceFile,LineNumberTable
-keepattributes *Annotation*, Signature, Exception

# Missing Play Core classes - app doesn't use Play Store deferred components
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }
