package com.example.app_flutter

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.tencent.cloud.libqcloudtts.MediaPlayer.QCloudMediaPlayer
import com.tencent.cloud.libqcloudtts.MediaPlayer.QCloudPlayerCallback
import com.tencent.cloud.libqcloudtts.MediaPlayer.QPlayerError
import com.tencent.cloud.libqcloudtts.TtsController
import com.tencent.cloud.libqcloudtts.TtsError
import com.tencent.cloud.libqcloudtts.TtsMode
import com.tencent.cloud.libqcloudtts.TtsResultListener
import com.tencent.cloud.libqcloudtts.engine.offlineModule.auth.QCloudOfflineAuthInfo
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer

/** Flutter bridge for Tencent Cloud's online TTS Android SDK v2.x. */
class TencentTtsChannel(
    context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    companion object {
        private const val CHANNEL_NAME = "ethnic_culture_app/tencent_tts"
    }

    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val controller = TtsController.getInstance()
    private var initialized = false
    private var activeRequestPrefix: String? = null
    private var pendingResult: MethodChannel.Result? = null
    private var pendingTimeout: Runnable? = null

    private val player = QCloudMediaPlayer(object : QCloudPlayerCallback {
        override fun onTTSPlayStart() = Unit
        override fun onTTSPlayWait() = Unit
        override fun onTTSPlayResume() = Unit
        override fun onTTSPlayPause() = Unit
        override fun onTTSPlayNext(text: String?, utteranceId: String?) = Unit
        override fun onTTSPlayStop() = Unit

        override fun onTTSPlayError(error: QPlayerError?) {
            completeError(
                "TENCENT_TTS_PLAY_FAILED",
                error?.getmMessage() ?: "腾讯云语音播放失败。",
            )
        }

        override fun onTTSPlayProgress(currentWord: String?, currentIndex: Int) = Unit
    })

    private val listener = object : TtsResultListener {
        override fun onSynthesizeData(
            bytes: ByteArray?,
            utteranceId: String?,
            text: String?,
            engineType: Int,
        ) = Unit

        override fun onSynthesizeData(
            bytes: ByteArray?,
            utteranceId: String?,
            text: String?,
            engineType: Int,
            requestId: String?,
        ) = Unit

        override fun onSynthesizeData(
            bytes: ByteArray?,
            utteranceId: String?,
            text: String?,
            engineType: Int,
            requestId: String?,
            responseJson: String?,
        ) {
            val audio = bytes ?: return
            val id = utteranceId.orEmpty()
            val prefix = activeRequestPrefix ?: return
            if (audio.isEmpty() || !id.startsWith(prefix)) return

            mainHandler.post {
                val playerError = player.enqueue(audio, text.orEmpty(), id, responseJson)
                if (playerError != null) {
                    completeError(
                        "TENCENT_TTS_PLAY_FAILED",
                        playerError.getmMessage() ?: "腾讯云语音播放失败。",
                    )
                } else {
                    completeSuccess()
                }
            }
        }

        override fun onError(error: TtsError?, utteranceId: String?, text: String?) {
            val serviceError = error?.serviceError
            val message = when {
                serviceError != null ->
                    "${serviceError.code}: ${serviceError.message ?: "腾讯云服务返回错误"}"
                error != null -> "${error.code}: ${error.message ?: "腾讯云语音合成失败"}"
                else -> "腾讯云语音合成失败。"
            }
            completeError("TENCENT_TTS_SYNTHESIS_FAILED", message)
        }

        override fun onOfflineAuthInfo(offlineAuthInfo: QCloudOfflineAuthInfo?) = Unit
        override fun onChunk(chunk: ByteBuffer?) = Unit
    }

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "speak" -> speak(call, result)
            "stop" -> {
                stopInternal()
                result.success(null)
            }
            "isAvailable" -> result.success(true)
            else -> result.notImplemented()
        }
    }

    private fun speak(call: MethodCall, result: MethodChannel.Result) {
        val texts = call.argument<List<String>>("texts")
            ?.map(String::trim)
            ?.filter(String::isNotEmpty)
            .orEmpty()
        val secretId = call.argument<String>("secretId").orEmpty().trim()
        val secretKey = call.argument<String>("secretKey").orEmpty().trim()
        if (texts.isEmpty()) {
            result.error("INVALID_TTS_TEXT", "没有可朗读的文字。", null)
            return
        }
        if (secretId.isEmpty() || secretKey.isEmpty()) {
            result.error(
                "TENCENT_TTS_NOT_CONFIGURED",
                "请先配置腾讯云 SecretId 和 SecretKey。",
                null,
            )
            return
        }

        stopInternal()
        try {
            val appId = call.argument<Number>("appId")?.toLong() ?: 0L
            if (appId > 0) controller.setAppId(appId)
            controller.setSecretId(secretId)
            controller.setSecretKey(secretKey)
            controller.setToken(call.argument<String>("token")?.trim()?.ifEmpty { null })
            controller.setOnlineVoiceType(
                (call.argument<Number>("voiceType")?.toInt() ?: 1001).coerceAtLeast(0),
            )
            controller.setOnlineVoiceSpeed(
                (call.argument<Number>("speed")?.toFloat() ?: 0f).coerceIn(-2f, 6f),
            )
            controller.setOnlineVoiceVolume(
                (call.argument<Number>("volume")?.toFloat() ?: 0f).coerceIn(-10f, 10f),
            )
            controller.setOnlineVoiceLanguage(1)
            controller.setOnlineCodec("mp3")
            controller.setConnectTimeout(15_000)
            controller.setReadTimeout(30_000)
            call.argument<String>("region")
                ?.trim()
                ?.takeIf(String::isNotEmpty)
                ?.let(controller::setOnlineRegion)

            if (!initialized) {
                controller.init(appContext, TtsMode.ONLINE, listener)
                initialized = true
            }

            val prefix = "flutter_${System.currentTimeMillis()}_"
            activeRequestPrefix = prefix
            pendingResult = result
            val timeout = Runnable {
                completeError("TENCENT_TTS_TIMEOUT", "腾讯云语音合成超时，请检查网络和凭证。")
            }
            pendingTimeout = timeout
            mainHandler.postDelayed(timeout, 35_000)

            for ((index, text) in texts.withIndex()) {
                val error = controller.synthesize(text, "$prefix$index")
                if (error != null) {
                    controller.cancel()
                    completeError(
                        "TENCENT_TTS_REQUEST_REJECTED",
                        "${error.code}: ${error.message ?: "腾讯云拒绝了朗读请求"}",
                    )
                    return
                }
            }
        } catch (error: Throwable) {
            completeError(
                "TENCENT_TTS_START_FAILED",
                error.message ?: "腾讯云语音合成启动失败。",
            )
        }
    }

    private fun completeSuccess() {
        mainHandler.post {
            val result = pendingResult ?: return@post
            clearPending()
            result.success(null)
        }
    }

    private fun completeError(code: String, message: String) {
        mainHandler.post {
            val result = pendingResult ?: return@post
            clearPending()
            result.error(code, message, null)
        }
    }

    private fun clearPending() {
        pendingTimeout?.let(mainHandler::removeCallbacks)
        pendingTimeout = null
        pendingResult = null
    }

    private fun stopInternal() {
        controller.cancel()
        player.StopPlay()
        activeRequestPrefix = null
        val result = pendingResult
        clearPending()
        result?.error("TENCENT_TTS_CANCELLED", "朗读已停止。", null)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        stopInternal()
        TtsController.release()
        initialized = false
    }
}
