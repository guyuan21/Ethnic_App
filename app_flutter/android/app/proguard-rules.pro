# ONNX Runtime's JNI bridge looks up these Java classes by their original
# binary names. R8 renaming them makes release builds abort in GetMethodID
# during PP-OCR inference instead of returning a catchable Java exception.
-keep class ai.onnxruntime.** { *; }

# ExecuTorch's Java facade and fbjni exception bridge are both entered from
# native code. The AAR's consumer rules keep annotated members, but R8 can
# still rename unannotated helper/exception classes in a Flutter release APK.
# That makes fbjni abort while translating a C++ exception during Module.load.
# Keep only these small JNI bridge packages; Dart code and all other Android
# dependencies remain fully optimised.
-keep class org.pytorch.executorch.** { *; }
-keep class com.facebook.jni.** { *; }
-keepclasseswithmembers,includedescriptorclasses class * {
    native <methods>;
}
-dontwarn javax.annotation.Nullable
