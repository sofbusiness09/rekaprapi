# Scan nota (google_mlkit_text_recognition): hanya model huruf Latin yang dibawa.
# Model Cina, Devanagari, Jepang, dan Korea sengaja tidak ikut; tanpa aturan ini
# R8 menghentikan build rilis karena kelasnya tidak ditemukan.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ML Kit mencari sebagian kelasnya lewat nama saat berjalan (pendaftaran komponen).
# Bila R8 membuang atau mengganti nama kelas itu, pembacaan gagal dengan
# "getClass() on a null object reference". Kelas ML Kit dan plugin Flutter-nya
# dibiarkan utuh.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_common.** { *; }
-keep class com.google.android.gms.common.internal.ReflectionUtils { *; }
-keep class com.google.firebase.components.** { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { *; }
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }
-dontwarn com.google.android.gms.internal.mlkit_vision_text_common.**
-dontwarn com.google.android.gms.internal.mlkit_vision_common.**
