package com.example.app_flutter

import android.content.Context
import android.content.res.AssetManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import org.pytorch.executorch.EValue
import org.pytorch.executorch.Module
import org.pytorch.executorch.Tensor

class ExecuTorchClassifierChannel(
    context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    companion object {
        private const val CHANNEL_NAME = "ethnic_culture_app/executorch_classifier"
        private const val INPUT_ELEMENTS = 1 * 3 * 224 * 224
        private const val OUTPUT_CLASSES = 56
        private const val LOG_TAG = "EthnicExecuTorch"
    }

    private val applicationContext = context.applicationContext
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var module: Module? = null
    private var loadedVersion: String? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "loadModel" -> loadModel(call, result)
            "classify" -> classify(call, result)
            else -> result.notImplemented()
        }
    }

    private fun loadModel(call: MethodCall, result: MethodChannel.Result) {
        val version = call.argument<String>("version").orEmpty()
        val modelAsset = call.argument<String>("modelAsset").orEmpty()
        val expectedModelBytes =
            call.argument<Number>("expectedModelBytes")?.toLong() ?: 0L
        if (
            !version.matches(Regex("[A-Za-z0-9._-]+")) ||
            modelAsset.isBlank() ||
            expectedModelBytes <= 0L
        ) {
            result.error("INVALID_EXECUTORCH_MODEL", "Invalid model parameters.", null)
            return
        }

        executor.execute {
            try {
                if (module == null || loadedVersion != version) {
                    val modelDir = File(applicationContext.filesDir, "executorch/$version")
                    if (!modelDir.exists() && !modelDir.mkdirs()) {
                        error("Unable to create the ExecuTorch model directory.")
                    }
                    val modelFile = copyFlutterAsset(
                        modelAsset,
                        File(modelDir, "model.pte"),
                        expectedModelBytes,
                    )
                    module?.close()
                    Log.i(
                        LOG_TAG,
                        "Loading ${modelFile.absolutePath} " +
                            "(${modelFile.length()} bytes) with MMAP",
                    )
                    // FILE mode first copies the complete 25 MiB PTE into a native
                    // buffer. MMAP is the Android-oriented load path and avoids that
                    // extra allocation, which is important on memory-constrained and
                    // heavily customised Android devices.
                    module = Module.load(
                        modelFile.absolutePath,
                        Module.LOAD_MODE_MMAP,
                    )
                    Log.i(LOG_TAG, "ExecuTorch model loaded successfully")
                    loadedVersion = version
                }
                mainHandler.post { result.success(null) }
            } catch (error: Throwable) {
                postError(result, "LOAD_EXECUTORCH_MODEL_FAILED", error)
            }
        }
    }

    private fun classify(call: MethodCall, result: MethodChannel.Result) {
        val input = floatArrayArgument(call.argument<Any>("input"))
        if (input == null || input.size != INPUT_ELEMENTS) {
            result.error(
                "INVALID_EXECUTORCH_INPUT",
                "Expected $INPUT_ELEMENTS float32 input values.",
                null,
            )
            return
        }
        executor.execute {
            try {
                val currentModule = module ?: error("ExecuTorch model is not loaded.")
                val tensor = Tensor.fromBlob(
                    input,
                    longArrayOf(1, 3, 224, 224),
                )
                val outputs = currentModule.forward(EValue.from(tensor))
                if (outputs.isEmpty()) error("ExecuTorch returned no outputs.")
                val scores = outputs[0].toTensor().dataAsFloatArray
                if (scores.size != OUTPUT_CLASSES) {
                    error(
                        "Expected $OUTPUT_CLASSES output values, received ${scores.size}.",
                    )
                }
                val serializableScores = scores.map { it.toDouble() }
                mainHandler.post { result.success(serializableScores) }
            } catch (error: Throwable) {
                postError(result, "EXECUTORCH_INFERENCE_FAILED", error)
            }
        }
    }

    private fun floatArrayArgument(value: Any?): FloatArray? {
        return when (value) {
            is FloatArray -> value
            is DoubleArray -> FloatArray(value.size) { value[it].toFloat() }
            is List<*> -> {
                val numbers = value.mapNotNull { it as? Number }
                if (numbers.size != value.size) null
                else FloatArray(numbers.size) { numbers[it].toFloat() }
            }
            else -> null
        }
    }

    private fun copyFlutterAsset(
        assetPath: String,
        target: File,
        expectedBytes: Long,
    ): File {
        if (target.isFile && target.length() == expectedBytes) return target
        val assetKey = FlutterInjector.instance()
            .flutterLoader()
            .getLookupKeyForAsset(assetPath)
        val temporary = File(target.parentFile, "${target.name}.copying")
        if (temporary.exists()) temporary.delete()

        applicationContext.assets.open(assetKey, AssetManager.ACCESS_STREAMING).use { input ->
            temporary.outputStream().buffered(1024 * 1024).use { output ->
                input.copyTo(output, 1024 * 1024)
                output.flush()
            }
        }
        val copiedBytes = temporary.length()
        if (copiedBytes != expectedBytes) {
            temporary.delete()
            error(
                "The bundled ExecuTorch model has an unexpected size: " +
                    "$assetPath ($copiedBytes != $expectedBytes)",
            )
        }
        if (target.exists() && !target.delete()) {
            temporary.delete()
            error("Unable to update the ExecuTorch model file.")
        }
        if (!temporary.renameTo(target)) {
            temporary.delete()
            error("Unable to save the ExecuTorch model file.")
        }
        return target
    }

    private fun postError(
        result: MethodChannel.Result,
        code: String,
        error: Throwable,
    ) {
        mainHandler.post {
            result.error(code, error.message ?: error.javaClass.simpleName, null)
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        executor.execute {
            module?.close()
            module = null
        }
        executor.shutdown()
    }
}
