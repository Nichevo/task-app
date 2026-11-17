# Item 111: the release build's shrinker broke ML Kit's word boxes ("Attempt to read from field
# ... on a null object reference" when reading a calendar photo). Keep ML Kit's text classes whole.
-keep class com.google.mlkit.vision.text.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keep class com.google.mlkit.vision.common.** { *; }
