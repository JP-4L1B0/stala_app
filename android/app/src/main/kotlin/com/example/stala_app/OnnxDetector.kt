package com.example.stala_app

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import ai.onnxruntime.TensorInfo
import android.content.Context
import android.graphics.Bitmap
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.nio.FloatBuffer
import android.graphics.Canvas
import android.graphics.Color
import org.opencv.android.Utils
import org.opencv.core.Mat
import org.opencv.imgproc.Imgproc
import org.opencv.core.Core

class OnnxDetector(private val context: Context) {

    companion object {
        const val MODEL_INPUT_WIDTH = 1024
        const val MODEL_INPUT_HEIGHT = 1024
        const val DEFAULT_SCORE_THRESHOLD = 0.5f
        private const val TAG = "STALA_ONNX"
    }

    private val environment: OrtEnvironment = OrtEnvironment.getEnvironment()
    private var session: OrtSession? = null

    fun loadModel(assetPath: String = "models/stala_multiclass_detector.onnx") {
        if (session != null) {
            Log.d(TAG, "loadModel: session already loaded")
            return
        }

        Log.d(TAG, "loadModel: copying model asset: $assetPath")
        val modelFile = copyAssetToInternalFile(assetPath)
        Log.d(TAG, "loadModel: model file path=${modelFile.absolutePath}")
        Log.d(TAG, "loadModel: model file exists=${modelFile.exists()} size=${modelFile.length()}")

        val options = OrtSession.SessionOptions()
        session = environment.createSession(modelFile.absolutePath, options)

        val activeSession = session
        Log.d(TAG, "loadModel: ONNX session created")
        Log.d(TAG, "loadModel: inputNames=${activeSession?.inputNames}")
        Log.d(TAG, "loadModel: outputNames=${activeSession?.outputNames}")
    }

    fun detectFromImagePath(
        imagePath: String,
        scoreThreshold: Float = DEFAULT_SCORE_THRESHOLD
    ): Map<String, Any?> {
        val imageFile = File(imagePath)
        Log.d(TAG, "detectFromImagePath: called imagePath=$imagePath scoreThreshold=$scoreThreshold")

        if (!imageFile.exists()) {
            Log.e(TAG, "detectFromImagePath: input image does not exist")
            return errorResponse("Input image file does not exist.", imagePath)
        }

        Log.d(TAG, "detectFromImagePath: input file size=${imageFile.length()}")

        val originalBitmap = ImageDecodeUtils.decodeBitmapWithCorrectOrientation(imagePath)
            ?: return errorResponse("Failed to decode image.", imagePath)

        Log.d(
            TAG,
            "detectFromImagePath: original bitmap width=${originalBitmap.width} height=${originalBitmap.height}"
        )
        val originalWidth = originalBitmap.width
        val originalHeight = originalBitmap.height

        return try {
            val enhancedBitmap = applyClaheEnhancement(originalBitmap)

            val resizedBitmap = letterboxBitmap(
                enhancedBitmap,
                MODEL_INPUT_WIDTH,
                MODEL_INPUT_HEIGHT
            )

            if (enhancedBitmap != originalBitmap) {
                enhancedBitmap.recycle()
            }

            val preprocessedImagePath = saveBitmapToCache(
                resizedBitmap,
                "onnx_preprocessed_${System.currentTimeMillis()}.png"
            )

            Log.d(
                TAG,
                "detectFromImagePath: letterboxed bitmap width=${resizedBitmap.width} height=${resizedBitmap.height}"
            )

            Log.d(TAG, "detectFromImagePath: preprocessedImagePath=$preprocessedImagePath")

            val inputData = bitmapToFloatArray(resizedBitmap)
            Log.d(TAG, "detectFromImagePath: inputData size=${inputData.size}")
            Log.d(TAG, "detectFromImagePath: bitmap loaded width=${originalBitmap.width} height=${originalBitmap.height}")

            val detections = run(
                inputData = inputData,
                inputWidth = MODEL_INPUT_WIDTH,
                inputHeight = MODEL_INPUT_HEIGHT,
                scoreThreshold = scoreThreshold
            )

            Log.d(TAG, "detectFromImagePath: detections count=${detections.size}")

            resizedBitmap.recycle()
            originalBitmap.recycle()

            mapOf(
                "status" to "success",
                "message" to "ONNX detection completed successfully.",
                "modelVersion" to "stala_multiclass_detector.onnx",
                "inputImagePath" to imagePath,
                "preprocessedImagePath" to preprocessedImagePath,
                "detectionImagePath" to preprocessedImagePath,
                "originalImageWidth" to originalWidth,
                "originalImageHeight" to originalHeight,
                "imageWidth" to MODEL_INPUT_WIDTH,
                "imageHeight" to MODEL_INPUT_HEIGHT,
                "detections" to detections,
                "staffMap" to emptyList<Any>(),
                "translationResult" to emptyList<Any>(),
                "tablature" to emptyList<Any>(),
                "errors" to emptyList<String>()
            )
        } catch (e: Exception) {
            Log.e(TAG, "detectFromImagePath: ONNX detection failed", e)
            originalBitmap.recycle()
            errorResponse("ONNX detection failed: ${e.message}", imagePath)
        }
    }

    fun run(
        inputData: FloatArray,
        inputWidth: Int,
        inputHeight: Int,
        scoreThreshold: Float = DEFAULT_SCORE_THRESHOLD
    ): List<Map<String, Any>> {
        val activeSession = session
            ?: throw IllegalStateException("ONNX model session is not loaded.")

        val inputName = activeSession.inputNames.first()
        val candidateShapes = candidateInputShapes(
            activeSession = activeSession,
            inputName = inputName,
            inputWidth = inputWidth,
            inputHeight = inputHeight
        )

        Log.d(TAG, "run: inputName=$inputName")
        Log.d(
            TAG,
            "run: candidateInputShapes=${candidateShapes.joinToString { it.joinToString(prefix = "[", postfix = "]") }}"
        )
        Log.d(TAG, "run: scoreThreshold=$scoreThreshold")

        var lastError: Exception? = null

        for (inputShape in candidateShapes) {
            try {
                return runWithInputShape(
                    activeSession = activeSession,
                    inputName = inputName,
                    inputData = inputData,
                    inputShape = inputShape,
                    scoreThreshold = scoreThreshold
                )
            } catch (e: Exception) {
                lastError = e
                Log.w(
                    TAG,
                    "run: failed with inputShape=${inputShape.joinToString(prefix = "[", postfix = "]")}",
                    e
                )
            }
        }

        throw lastError ?: IllegalStateException("ONNX inference failed for all candidate input shapes.")
    }

    private fun runWithInputShape(
        activeSession: OrtSession,
        inputName: String,
        inputData: FloatArray,
        inputShape: LongArray,
        scoreThreshold: Float
    ): List<Map<String, Any>> {
        Log.d(TAG, "runWithInputShape: trying ${inputShape.joinToString(prefix = "[", postfix = "]")}")

        OnnxTensor.createTensor(
            environment,
            FloatBuffer.wrap(inputData),
            inputShape
        ).use { inputTensor ->

            Log.d(TAG, "run: input tensor created")

            activeSession.run(mapOf(inputName to inputTensor)).use { output ->
                Log.d(TAG, "run: session.run completed")
                Log.d(TAG, "run: output size=${output.size()}")

                for (i in 0 until output.size()) {
                    val value = output[i].value
                    Log.d(
                        TAG,
                        "run: output[$i] type=${value?.javaClass?.name}"
                    )
                }

                val boxes = parseBoxes(output[0].value)
                val labels = parseLabels(output[1].value)
                val scores = parseScores(output[2].value)

                Log.d(TAG, "run: boxes size=${boxes.size}")
                Log.d(TAG, "run: labels size=${labels.size}")
                Log.d(TAG, "run: scores size=${scores.size}")

                val detections = mutableListOf<Map<String, Any>>()

                for (i in scores.indices) {
                    val confidence = scores[i]
                    if (confidence < scoreThreshold) continue

                    val labelValue = labels.getOrNull(i)?.toInt() ?: -1
                    val boxValue = boxes.getOrNull(i)?.map { it.toInt() } ?: emptyList()

                    detections.add(
                        mapOf(
                            "className" to labelToClassName(labelValue),
                            "confidence" to confidence.toDouble(),
                            "bbox" to boxValue
                        )
                    )
                }

                Log.d(TAG, "run: filtered detections count=${detections.size}")

                if (detections.isNotEmpty()) {
                    Log.d(TAG, "run: first detection=${detections.first()}")
                }

                Log.d(TAG, "runWithInputShape: success")
                return detections
            }
        }
    }

    private fun candidateInputShapes(
        activeSession: OrtSession,
        inputName: String,
        inputWidth: Int,
        inputHeight: Int
    ): List<LongArray> {
        val batchShape = longArrayOf(1, 3, inputHeight.toLong(), inputWidth.toLong())
        val channelShape = longArrayOf(3, inputHeight.toLong(), inputWidth.toLong())
        val fallbackShapes = listOf(batchShape, channelShape)

        val declaredShape = try {
            val info = activeSession.inputInfo[inputName]?.info
            (info as? TensorInfo)?.shape
        } catch (e: Exception) {
            Log.w(TAG, "candidateInputShapes: failed to read input metadata", e)
            null
        }

        if (declaredShape == null) return fallbackShapes

        Log.d(
            TAG,
            "candidateInputShapes: declaredShape=${declaredShape.joinToString(prefix = "[", postfix = "]")}"
        )

        val metadataPreferred = when (declaredShape.size) {
            4 -> batchShape
            3 -> channelShape
            else -> null
        }

        if (metadataPreferred == null) return fallbackShapes

        return listOf(metadataPreferred) + fallbackShapes.filterNot {
            it.contentEquals(metadataPreferred)
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun parseBoxes(value: Any?): Array<FloatArray> {
        return when (value) {
            is Array<*> -> {
                val first = value.firstOrNull()
                when (first) {
                    is FloatArray -> value as Array<FloatArray>
                    is Array<*> -> first as Array<FloatArray>
                    else -> throw IllegalStateException(
                        "Unsupported ONNX boxes output item type: ${first?.javaClass?.name}"
                    )
                }
            }
            else -> throw IllegalStateException(
                "Unsupported ONNX boxes output type: ${value?.javaClass?.name}"
            )
        }
    }

    private fun parseLabels(value: Any?): LongArray {
        return when (value) {
            is LongArray -> value
            is IntArray -> LongArray(value.size) { value[it].toLong() }
            is Array<*> -> {
                val first = value.firstOrNull()
                when (first) {
                    is LongArray -> first
                    is IntArray -> LongArray(first.size) { first[it].toLong() }
                    else -> throw IllegalStateException(
                        "Unsupported ONNX labels output item type: ${first?.javaClass?.name}"
                    )
                }
            }
            else -> throw IllegalStateException(
                "Unsupported ONNX labels output type: ${value?.javaClass?.name}"
            )
        }
    }

    private fun parseScores(value: Any?): FloatArray {
        return when (value) {
            is FloatArray -> value
            is DoubleArray -> FloatArray(value.size) { value[it].toFloat() }
            is Array<*> -> {
                val first = value.firstOrNull()
                when (first) {
                    is FloatArray -> first
                    is DoubleArray -> FloatArray(first.size) { first[it].toFloat() }
                    else -> throw IllegalStateException(
                        "Unsupported ONNX scores output item type: ${first?.javaClass?.name}"
                    )
                }
            }
            else -> throw IllegalStateException(
                "Unsupported ONNX scores output type: ${value?.javaClass?.name}"
            )
        }
    }

    private fun bitmapToFloatArray(bitmap: Bitmap): FloatArray {
        val width = bitmap.width
        val height = bitmap.height
        val pixelCount = width * height

        Log.d(TAG, "bitmapToFloatArray: width=$width height=$height pixelCount=$pixelCount")

        val pixels = IntArray(pixelCount)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)

        val floatArray = FloatArray(3 * pixelCount)

        for (i in pixels.indices) {
            val pixel = pixels[i]

            val r = ((pixel shr 16) and 0xFF) / 255.0f
            val g = ((pixel shr 8) and 0xFF) / 255.0f
            val b = (pixel and 0xFF) / 255.0f

            floatArray[i] = r
            floatArray[pixelCount + i] = g
            floatArray[(2 * pixelCount) + i] = b
        }

        Log.d(TAG, "bitmapToFloatArray: floatArray size=${floatArray.size}")
        return floatArray
    }

    private fun labelToClassName(label: Int): String {
        return when (label) {
            1 -> "bass_clef"
            2 -> "flat"
            3 -> "natural"
            4 -> "notehead"
            5 -> "sharp"
            6 -> "treble_clef"
            else -> "unknown"
        }
    }

    private fun copyAssetToInternalFile(assetPath: String): File {
        val fileName = assetPath.substringAfterLast("/")
        val outFile = File(context.filesDir, fileName)

        Log.d(TAG, "copyAssetToInternalFile: copying asset=$assetPath to ${outFile.absolutePath}")

        context.assets.open(assetPath).use { input ->
            FileOutputStream(outFile, false).use { output ->
                input.copyTo(output)
            }
        }

        Log.d(TAG, "copyAssetToInternalFile: copy complete size=${outFile.length()}")
        return outFile
    }

    private fun errorResponse(message: String, imagePath: String): Map<String, Any?> {
        Log.e(TAG, "errorResponse: $message")
        return mapOf(
            "status" to "error",
            "message" to message,
            "modelVersion" to "unavailable",
            "inputImagePath" to imagePath,
            "preprocessedImagePath" to "",
            "detectionImagePath" to "",
            "imageWidth" to 0,
            "imageHeight" to 0,
            "detections" to emptyList<Map<String, Any?>>(),
            "staffMap" to emptyList<Any>(),
            "translationResult" to emptyList<Any>(),
            "tablature" to emptyList<Any>(),
            "errors" to listOf(message)
        )
    }

    private fun letterboxBitmap(
        source: Bitmap,
        targetWidth: Int,
        targetHeight: Int
    ): Bitmap {
        val scale = minOf(
            targetWidth.toFloat() / source.width.toFloat(),
            targetHeight.toFloat() / source.height.toFloat()
        )

        val resizedWidth = (source.width * scale).toInt().coerceAtLeast(1)
        val resizedHeight = (source.height * scale).toInt().coerceAtLeast(1)

        val resizedBitmap = Bitmap.createScaledBitmap(
            source,
            resizedWidth,
            resizedHeight,
            true
        )

        val outputBitmap = Bitmap.createBitmap(
            targetWidth,
            targetHeight,
            Bitmap.Config.ARGB_8888
        )

        val canvas = Canvas(outputBitmap)
        canvas.drawColor(Color.WHITE)

        val left = ((targetWidth - resizedWidth) / 2f)
        val top = ((targetHeight - resizedHeight) / 2f)

        canvas.drawBitmap(resizedBitmap, left, top, null)

        if (resizedBitmap != source) {
            resizedBitmap.recycle()
        }

        Log.d(TAG, "letterboxBitmap: source=${source.width}x${source.height} resized=${resizedWidth}x${resizedHeight} placedAt=($left,$top)")

        return outputBitmap
    }

    private fun applyClaheEnhancement(source: Bitmap): Bitmap {
        return try {
            val srcMat = Mat()
            val labMat = Mat()
            val enhancedLabMat = Mat()
            val dstMat = Mat()

            Utils.bitmapToMat(source, srcMat)

            Imgproc.cvtColor(srcMat, labMat, Imgproc.COLOR_RGB2Lab)

            val channels = mutableListOf<Mat>()
            Core.split(labMat, channels)

            val clahe = Imgproc.createCLAHE(
                2.0, // clipLimit
                org.opencv.core.Size(8.0, 8.0)
            )

            clahe.apply(channels[0], channels[0])

            Core.merge(channels, enhancedLabMat)

            Imgproc.cvtColor(enhancedLabMat, dstMat, Imgproc.COLOR_Lab2RGB)

            val output = Bitmap.createBitmap(
                source.width,
                source.height,
                Bitmap.Config.ARGB_8888
            )

            Utils.matToBitmap(dstMat, output)

            srcMat.release()
            labMat.release()
            enhancedLabMat.release()
            dstMat.release()
            channels.forEach { it.release() }
            clahe.collectGarbage()

            Log.d(TAG, "applyClaheEnhancement: success")

            output
        } catch (e: Exception) {
            Log.e(TAG, "applyClaheEnhancement: failed, using original bitmap", e)
            source
        }
    }

    private fun saveBitmapToCache(bitmap: Bitmap, fileName: String): String {
        val outFile = File(context.cacheDir, fileName)

        FileOutputStream(outFile).use { out ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        }

        Log.d(TAG, "saveBitmapToCache: saved ${outFile.absolutePath}")
        return outFile.absolutePath
    }
}
