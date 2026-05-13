# ONNX Runtime creates Java wrapper objects from native code via JNI.
# R8 must not shrink, rename, or change members used by those native calls.
-keep class ai.onnxruntime.** { *; }
-keep enum ai.onnxruntime.** { *; }
-keep interface ai.onnxruntime.** { *; }
-keep class com.microsoft.onnxruntime.** { *; }

