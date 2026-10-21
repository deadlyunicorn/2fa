# Preserve descriptor classes (such as kotlin.coroutines.Continuation) on @Keep classes
-keep,includedescriptorclasses @androidx.annotation.Keep class * { *; }

# Keep SharedPreferences Pigeon JNI classes and their method descriptors
-keep,includedescriptorclasses class io.flutter.plugins.sharedpreferences.** { *; }

# Keep Kotlin stdlib / coroutine classes accessed directly by package:jni via JNI reflection
-keep class kotlin.Unit { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
-keep class kotlin.coroutines.Continuation { *; }
-keep class kotlin.coroutines.intrinsics.CoroutineSingletons { *; }
-keep class kotlin.coroutines.intrinsics.IntrinsicsKt { *; }
-keep class kotlin.jvm.internal.DefaultConstructorMarker { *; }
-keep class kotlin.enums.EnumEntries { *; }
