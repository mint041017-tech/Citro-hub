# flutter_local_notifications 会用 Gson 持久化已排程通知。
# R8 若裁掉泛型签名或 TypeToken 子类，后台排程会抛 "Missing type parameter"，
# 表现为计时到点没有任何系统通知。
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses,EnclosingMethod
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.google.gson.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keepclassmembers,allowobfuscation class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
-dontwarn com.google.gson.**
