# Scan nota (google_mlkit_text_recognition): hanya model huruf Latin yang dibawa.
# Model Cina, Devanagari, Jepang, dan Korea sengaja tidak ikut; tanpa aturan ini
# R8 menghentikan build rilis karena kelasnya tidak ditemukan.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
