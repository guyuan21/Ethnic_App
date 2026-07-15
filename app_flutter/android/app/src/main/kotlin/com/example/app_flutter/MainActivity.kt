package com.example.app_flutter

import android.content.res.AssetManager
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val modelExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var tencentTtsChannel: TencentTtsChannel? = null
    private var execuTorchClassifierChannel: ExecuTorchClassifierChannel? = null
    private var ppOcrV5Channel: PpOcrV5Channel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        tencentTtsChannel = TencentTtsChannel(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        execuTorchClassifierChannel = ExecuTorchClassifierChannel(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        ppOcrV5Channel = PpOcrV5Channel(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "ethnic_culture_app/offline_asr",
        ).setMethodCallHandler { call, result ->
            if (call.method != "prepareModel") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val version = call.argument<String>("version").orEmpty()
            val modelAsset = call.argument<String>("modelAsset").orEmpty()
            val tokensAsset = call.argument<String>("tokensAsset").orEmpty()
            val minimumModelBytes = call.argument<Number>("minimumModelBytes")?.toLong() ?: 0L
            val minimumTokensBytes = call.argument<Number>("minimumTokensBytes")?.toLong() ?: 0L
            if (!version.matches(Regex("[A-Za-z0-9._-]+")) ||
                modelAsset.isBlank() ||
                tokensAsset.isBlank()
            ) {
                result.error("INVALID_ASR_MODEL", "离线语音模型参数无效。", null)
                return@setMethodCallHandler
            }

            modelExecutor.execute {
                try {
                    val modelDir = File(filesDir, "offline_asr/$version")
                    if (!modelDir.exists() && !modelDir.mkdirs()) {
                        error("无法创建离线语音模型目录。")
                    }
                    val modelFile = copyFlutterAsset(
                        modelAsset,
                        File(modelDir, "model.int8.onnx"),
                        minimumModelBytes,
                    )
                    val tokensFile = copyFlutterAsset(
                        tokensAsset,
                        File(modelDir, "tokens.txt"),
                        minimumTokensBytes,
                    )
                    mainHandler.post {
                        result.success(
                            mapOf(
                                "modelPath" to modelFile.absolutePath,
                                "tokensPath" to tokensFile.absolutePath,
                            ),
                        )
                    }
                } catch (error: Throwable) {
                    mainHandler.post {
                        result.error(
                            "PREPARE_ASR_MODEL_FAILED",
                            error.message ?: "准备离线语音模型失败。",
                            null,
                        )
                    }
                }
            }
        }
    }

    private fun copyFlutterAsset(assetPath: String, target: File, minimumBytes: Long): File {
        if (target.isFile && target.length() >= minimumBytes) return target

        val assetKey = FlutterInjector.instance()
            .flutterLoader()
            .getLookupKeyForAsset(assetPath)
        val temporary = File(target.parentFile, "${target.name}.copying")
        if (temporary.exists()) temporary.delete()

        assets.open(assetKey, AssetManager.ACCESS_STREAMING).use { input ->
            temporary.outputStream().buffered(1024 * 1024).use { output ->
                input.copyTo(output, 1024 * 1024)
                output.flush()
            }
        }
        if (temporary.length() < minimumBytes) {
            temporary.delete()
            error("离线语音模型文件不完整：$assetPath")
        }
        if (target.exists() && !target.delete()) {
            temporary.delete()
            error("无法更新离线语音模型：${target.name}")
        }
        if (!temporary.renameTo(target)) {
            temporary.delete()
            error("无法保存离线语音模型：${target.name}")
        }
        return target
    }

    override fun onDestroy() {
        tencentTtsChannel?.dispose()
        tencentTtsChannel = null
        execuTorchClassifierChannel?.dispose()
        execuTorchClassifierChannel = null
        ppOcrV5Channel?.dispose()
        ppOcrV5Channel = null
        modelExecutor.shutdownNow()
        super.onDestroy()
    }
}
