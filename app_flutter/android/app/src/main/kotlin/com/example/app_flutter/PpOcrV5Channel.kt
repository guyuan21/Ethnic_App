package com.example.app_flutter

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.FileInputStream
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.nio.channels.FileChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

/** Offline PP-OCRv5 mobile OCR optimized for ethnic-title search across the image. */
class PpOcrV5Channel(
    context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    companion object {
        private const val CHANNEL_NAME = "ethnic_culture_app/pp_ocr_v5"
        private const val DET_MODEL_ASSET =
            "assets/ocr/ppocrv5/ppocrv5_mobile_det.onnx"
        private const val REC_MODEL_ASSET =
            "assets/ocr/ppocrv5/ppocrv5_mobile_rec.onnx"
        private const val DICTIONARY_ASSET = "assets/ocr/ppocrv5/ppocrv5_dict.txt"
        private const val DETECTOR_LONG_SIDE = 640
        private const val MAX_DECODE_SIDE = 2048
        private const val REC_HEIGHT = 48
        private const val REC_WIDTH = 320
        private const val DET_THRESHOLD = 0.30f
        private const val BOX_THRESHOLD = 0.45f
        private const val TEXT_THRESHOLD = 0.45f
    }

    private data class TextBox(
        val left: Int,
        val top: Int,
        val right: Int,
        val bottom: Int,
        val score: Float,
    )

    private data class TextLine(
        val text: String,
        val confidence: Float,
        val top: Int,
        val left: Int,
    )

    private data class RecognitionResult(
        val lines: List<TextLine>,
        val stage: String,
        val mirrored: Boolean = false,
    )

    private val applicationContext = context.applicationContext
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private val environment = OrtEnvironment.getEnvironment()
    private var detector: OrtSession? = null
    private var recognizer: OrtSession? = null
    private var characters: List<String>? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "recognizeTitle") {
            result.notImplemented()
            return
        }
        val imagePath = call.argument<String>("imagePath").orEmpty()
        if (imagePath.isBlank()) {
            result.error("INVALID_OCR_IMAGE", "OCR image path is empty.", null)
            return
        }

        executor.execute {
            val startedAt = System.nanoTime()
            try {
                ensureLoaded()
                val bitmap = decodeOrientedBitmap(imagePath)
                    ?: error("Unable to decode OCR image.")
                val recognition = try {
                    recognizeWithFallback(bitmap)
                } finally {
                    bitmap.recycle()
                }
                val lines = recognition.lines
                val elapsedMs = (System.nanoTime() - startedAt) / 1_000_000
                val text = lines.joinToString("\n") { it.text }
                val confidence = if (lines.isEmpty()) {
                    0.0
                } else {
                    lines.map { it.confidence.toDouble() }.average()
                }
                mainHandler.post {
                    result.success(
                        mapOf(
                            "text" to text,
                            "confidence" to confidence,
                            "elapsedMs" to elapsedMs,
                            "engine" to "ppocrv5_mobile_title_search",
                            "searchStage" to recognition.stage,
                            "mirrored" to recognition.mirrored,
                            "lines" to lines.map {
                                mapOf(
                                    "text" to it.text,
                                    "confidence" to it.confidence.toDouble(),
                                )
                            },
                        ),
                    )
                }
            } catch (error: Throwable) {
                mainHandler.post {
                    result.error(
                        "PPOCRV5_INFERENCE_FAILED",
                        error.message ?: "PP-OCRv5 inference failed.",
                        null,
                    )
                }
            }
        }
    }

    private fun ensureLoaded() {
        if (detector != null && recognizer != null && characters != null) return

        val options = OrtSession.SessionOptions().apply {
            setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
            setIntraOpNumThreads(max(1, min(4, Runtime.getRuntime().availableProcessors() - 1)))
            setInterOpNumThreads(1)
        }
        try {
            detector = createSessionFromAsset(DET_MODEL_ASSET, options)
            recognizer = createSessionFromAsset(REC_MODEL_ASSET, options)
            val dictionaryKey = assetKey(DICTIONARY_ASSET)
            val loadedCharacters = applicationContext.assets.open(dictionaryKey).bufferedReader(
                Charsets.UTF_8,
            ).use { it.readLines() }.toMutableList()
            // PP-OCRv5's exported recognition head has: blank + dictionary + ASCII space.
            loadedCharacters.add(" ")
            characters = loadedCharacters
        } finally {
            options.close()
        }
    }

    private fun createSessionFromAsset(
        assetPath: String,
        options: OrtSession.SessionOptions,
    ): OrtSession {
        val assetDescriptor = applicationContext.assets.openFd(assetKey(assetPath))
        assetDescriptor.use { descriptor ->
            FileInputStream(descriptor.fileDescriptor).use { input ->
                val modelBuffer = input.channel.map(
                    FileChannel.MapMode.READ_ONLY,
                    descriptor.startOffset,
                    descriptor.declaredLength,
                ).order(ByteOrder.nativeOrder())
                return environment.createSession(modelBuffer, options)
            }
        }
    }

    private fun assetKey(assetPath: String): String = FlutterInjector.instance()
        .flutterLoader()
        .getLookupKeyForAsset(assetPath)

    private fun decodeOrientedBitmap(path: String): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

        var sampleSize = 1
        while (
            max(bounds.outWidth / sampleSize, bounds.outHeight / sampleSize) >
            MAX_DECODE_SIDE
        ) {
            sampleSize *= 2
        }
        val decoded = BitmapFactory.decodeFile(
            path,
            BitmapFactory.Options().apply {
                inSampleSize = sampleSize
                inPreferredConfig = Bitmap.Config.ARGB_8888
            },
        ) ?: return null

        val orientation = try {
            ExifInterface(path).getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL,
            )
        } catch (_: Throwable) {
            ExifInterface.ORIENTATION_NORMAL
        }
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.postScale(-1f, 1f)
                matrix.postRotate(90f)
            }
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.postScale(-1f, 1f)
                matrix.postRotate(270f)
            }
        }
        if (matrix.isIdentity) return decoded
        val oriented = Bitmap.createBitmap(
            decoded,
            0,
            0,
            decoded.width,
            decoded.height,
            matrix,
            true,
        )
        if (oriented !== decoded) decoded.recycle()
        return oriented
    }

    private fun recognizeWithFallback(bitmap: Bitmap): RecognitionResult {
        recognizeStage(
            bitmap,
            stage = "top_left",
            widthRatio = 0.62f,
            heightRatio = 0.42f,
            maxBoxes = 8,
        )?.let { return it }

        recognizeStage(
            bitmap,
            stage = "top_band",
            widthRatio = 1f,
            heightRatio = 0.50f,
            maxBoxes = 12,
        )?.let { return it }

        recognizeStage(
            bitmap,
            stage = "full_image",
            widthRatio = 1f,
            heightRatio = 1f,
            maxBoxes = 20,
        )?.let { return it }

        // A photo taken through a mirrored camera may contain baked-in reversed
        // pixels even after EXIF orientation is handled. Allocate and scan the
        // mirrored bitmap only after every normal-image path has failed.
        val mirrored = horizontallyFlipped(bitmap)
        try {
            recognizeStage(
                mirrored,
                stage = "top_left_mirrored",
                widthRatio = 0.62f,
                heightRatio = 0.42f,
                maxBoxes = 8,
                mirrored = true,
            )?.let { return it }

            recognizeStage(
                mirrored,
                stage = "top_band_mirrored",
                widthRatio = 1f,
                heightRatio = 0.50f,
                maxBoxes = 12,
                mirrored = true,
            )?.let { return it }

            recognizeStage(
                mirrored,
                stage = "full_image_mirrored",
                widthRatio = 1f,
                heightRatio = 1f,
                maxBoxes = 20,
                mirrored = true,
            )?.let { return it }
        } finally {
            mirrored.recycle()
        }

        // Do not expose unrelated background text as an ethnic OCR hint.
        return RecognitionResult(emptyList(), stage = "not_found")
    }

    private fun recognizeStage(
        source: Bitmap,
        stage: String,
        widthRatio: Float,
        heightRatio: Float,
        maxBoxes: Int,
        mirrored: Boolean = false,
    ): RecognitionResult? {
        val lines = recognizeRegion(
            source,
            widthRatio = widthRatio,
            heightRatio = heightRatio,
            maxBoxes = maxBoxes,
        )
        val match = EthnicTitleMatcher.find(lines.map { it.text }) ?: return null
        return RecognitionResult(
            lines = selectTitleLines(lines, match),
            stage = stage,
            mirrored = mirrored,
        )
    }

    private fun selectTitleLines(
        lines: List<TextLine>,
        match: EthnicTitleMatcher.Match,
    ): List<TextLine> {
        val sourceLine = lines[match.lineIndex]
        val titleLine = if (match.exact) {
            sourceLine
        } else {
            sourceLine.copy(text = match.canonicalName)
        }
        val result = mutableListOf(titleLine)
        lines.getOrNull(match.lineIndex + 1)?.let { nextLine ->
            val latinTitle = nextLine.text.trim()
            if (
                nextLine.confidence >= 0.70f &&
                latinTitle.length in 2..32 &&
                latinTitle.any { it in 'A'..'Z' || it in 'a'..'z' } &&
                latinTitle.all {
                    it.isWhitespace() || it.isLetter() || it == '-' || it == '\'' || it == '.'
                }
            ) {
                result.add(nextLine)
            }
        }
        return result
    }

    private fun horizontallyFlipped(source: Bitmap): Bitmap {
        val matrix = Matrix().apply { postScale(-1f, 1f) }
        return Bitmap.createBitmap(
            source,
            0,
            0,
            source.width,
            source.height,
            matrix,
            true,
        )
    }

    private fun recognizeRegion(
        source: Bitmap,
        widthRatio: Float,
        heightRatio: Float,
        maxBoxes: Int,
    ): List<TextLine> {
        val cropWidth = max(64, min(source.width, (source.width * widthRatio).toInt()))
        val cropHeight = max(64, min(source.height, (source.height * heightRatio).toInt()))
        val region = Bitmap.createBitmap(source, 0, 0, cropWidth, cropHeight)
        return try {
            val detectorScale = min(
                DETECTOR_LONG_SIDE.toFloat() / max(region.width, region.height),
                4f,
            )
            val detWidth = roundUp32(max(32, ceil(region.width * detectorScale).toInt()))
            val detHeight = roundUp32(max(32, ceil(region.height * detectorScale).toInt()))
            val detectorBitmap = Bitmap.createScaledBitmap(region, detWidth, detHeight, true)
            try {
                detectTextBoxes(detectorBitmap)
                    .take(maxBoxes)
                    .mapNotNull { box -> recognizeBox(detectorBitmap, box) }
                    .filter { it.confidence >= TEXT_THRESHOLD && it.text.isNotBlank() }
                    .sortedWith(compareBy<TextLine> { it.top }.thenBy { it.left })
            } finally {
                if (detectorBitmap !== region) detectorBitmap.recycle()
            }
        } finally {
            region.recycle()
        }
    }

    private fun detectTextBoxes(bitmap: Bitmap): List<TextBox> {
        val width = bitmap.width
        val height = bitmap.height
        val pixels = IntArray(width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
        val input = FloatArray(3 * width * height)
        val plane = width * height
        for (index in pixels.indices) {
            val color = pixels[index]
            val red = ((color shr 16) and 0xff) / 255f
            val green = ((color shr 8) and 0xff) / 255f
            val blue = (color and 0xff) / 255f
            input[index] = (red - 0.485f) / 0.229f
            input[plane + index] = (green - 0.456f) / 0.224f
            input[2 * plane + index] = (blue - 0.406f) / 0.225f
        }

        val session = detector ?: error("PP-OCRv5 detector is not loaded.")
        val probabilities = OnnxTensor.createTensor(
            environment,
            FloatBuffer.wrap(input),
            longArrayOf(1, 3, height.toLong(), width.toLong()),
        ).use { tensor ->
            session.run(mapOf(session.inputNames.first() to tensor)).use { outputs ->
                val output = outputs[0] as OnnxTensor
                FloatArray(width * height).also { output.floatBuffer.get(it) }
            }
        }
        return connectedTextBoxes(probabilities, width, height)
    }

    private fun connectedTextBoxes(
        probabilities: FloatArray,
        width: Int,
        height: Int,
    ): List<TextBox> {
        val visited = BooleanArray(probabilities.size)
        val queue = IntArray(probabilities.size)
        val boxes = mutableListOf<TextBox>()
        val neighbors = intArrayOf(-1, 0, 1)

        for (start in probabilities.indices) {
            if (visited[start] || probabilities[start] <= DET_THRESHOLD) continue
            var head = 0
            var tail = 0
            queue[tail++] = start
            visited[start] = true
            var minX = width
            var minY = height
            var maxX = 0
            var maxY = 0
            var count = 0

            while (head < tail) {
                val current = queue[head++]
                val x = current % width
                val y = current / width
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
                count++
                for (dy in neighbors) {
                    val nextY = y + dy
                    if (nextY !in 0 until height) continue
                    for (dx in neighbors) {
                        if (dx == 0 && dy == 0) continue
                        val nextX = x + dx
                        if (nextX !in 0 until width) continue
                        val next = nextY * width + nextX
                        if (!visited[next] && probabilities[next] > DET_THRESHOLD) {
                            visited[next] = true
                            queue[tail++] = next
                        }
                    }
                }
            }
            if (count < 12 || maxX - minX < 3 || maxY - minY < 3) continue

            var scoreSum = 0f
            var scoreCount = 0
            for (y in minY..maxY) {
                val offset = y * width
                for (x in minX..maxX) {
                    scoreSum += probabilities[offset + x]
                    scoreCount++
                }
            }
            val score = scoreSum / max(1, scoreCount)
            if (score < BOX_THRESHOLD) continue

            val boxHeight = maxY - minY + 1
            val padding = max(2, (boxHeight * 0.20f).toInt())
            val left = max(0, minX - padding)
            val top = max(0, minY - padding)
            val right = min(width, maxX + padding + 1)
            val bottom = min(height, maxY + padding + 1)
            val areaRatio = (right - left).toLong() * (bottom - top) /
                (width.toDouble() * height)
            if (areaRatio < 0.90) {
                boxes.add(TextBox(left, top, right, bottom, score))
            }
        }
        return boxes.sortedWith(compareBy<TextBox> { it.top }.thenBy { it.left })
    }

    private fun recognizeBox(bitmap: Bitmap, box: TextBox): TextLine? {
        val cropWidth = box.right - box.left
        val cropHeight = box.bottom - box.top
        if (cropWidth <= 0 || cropHeight <= 0) return null
        val crop = Bitmap.createBitmap(bitmap, box.left, box.top, cropWidth, cropHeight)
        return try {
            val resizedWidth = min(
                REC_WIDTH,
                max(8, ceil(REC_HEIGHT * crop.width.toDouble() / crop.height).toInt()),
            )
            val resized = Bitmap.createScaledBitmap(crop, resizedWidth, REC_HEIGHT, true)
            try {
                val input = FloatArray(3 * REC_HEIGHT * REC_WIDTH)
                val pixels = IntArray(resizedWidth * REC_HEIGHT)
                resized.getPixels(pixels, 0, resizedWidth, 0, 0, resizedWidth, REC_HEIGHT)
                val plane = REC_HEIGHT * REC_WIDTH
                for (y in 0 until REC_HEIGHT) {
                    for (x in 0 until resizedWidth) {
                        val color = pixels[y * resizedWidth + x]
                        val target = y * REC_WIDTH + x
                        // The recognition model uses PaddleOCR's BGR normalization.
                        input[target] = (((color and 0xff) / 255f) - 0.5f) / 0.5f
                        input[plane + target] =
                            ((((color shr 8) and 0xff) / 255f) - 0.5f) / 0.5f
                        input[2 * plane + target] =
                            ((((color shr 16) and 0xff) / 255f) - 0.5f) / 0.5f
                    }
                }
                decodeRecognition(input)?.let {
                    TextLine(it.first, it.second, box.top, box.left)
                }
            } finally {
                if (resized !== crop) resized.recycle()
            }
        } finally {
            crop.recycle()
        }
    }

    private fun decodeRecognition(input: FloatArray): Pair<String, Float>? {
        val session = recognizer ?: error("PP-OCRv5 recognizer is not loaded.")
        val dictionary = characters ?: error("PP-OCRv5 dictionary is not loaded.")
        return OnnxTensor.createTensor(
            environment,
            FloatBuffer.wrap(input),
            longArrayOf(1, 3, REC_HEIGHT.toLong(), REC_WIDTH.toLong()),
        ).use { tensor ->
            session.run(mapOf(session.inputNames.first() to tensor)).use { outputs ->
                val output = outputs[0] as OnnxTensor
                val shape = output.info.shape
                val steps = shape[1].toInt()
                val classes = shape[2].toInt()
                val scores = FloatArray(steps * classes)
                output.floatBuffer.get(scores)
                val text = StringBuilder()
                var previous = -1
                var confidenceSum = 0f
                var characterCount = 0
                for (step in 0 until steps) {
                    val offset = step * classes
                    var bestIndex = 0
                    var bestScore = scores[offset]
                    for (index in 1 until classes) {
                        val score = scores[offset + index]
                        if (score > bestScore) {
                            bestScore = score
                            bestIndex = index
                        }
                    }
                    if (bestIndex != 0 && bestIndex != previous) {
                        val dictionaryIndex = bestIndex - 1
                        if (dictionaryIndex in dictionary.indices) {
                            text.append(dictionary[dictionaryIndex])
                            confidenceSum += bestScore
                            characterCount++
                        }
                    }
                    previous = bestIndex
                }
                if (characterCount == 0) null else {
                    text.toString() to (confidenceSum / characterCount)
                }
            }
        }
    }

    private fun roundUp32(value: Int): Int = ((value + 31) / 32) * 32

    fun dispose() {
        channel.setMethodCallHandler(null)
        executor.shutdownNow()
        detector?.close()
        detector = null
        recognizer?.close()
        recognizer = null
        characters = null
    }
}
