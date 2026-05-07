package com.example.stala_app

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.nio.FloatBuffer
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface
import android.graphics.Canvas
import android.graphics.Color
import org.opencv.android.Utils
import org.opencv.core.Mat
import org.opencv.imgproc.Imgproc
import org.opencv.core.Core
import java.nio.ByteBuffer
import java.nio.ByteOrder

class OnnxDetector(private val context: Context) {

    companion object {
        const val MODEL_INPUT_WIDTH = 1024
        const val MODEL_INPUT_HEIGHT = 1024
        const val DEFAULT_SCORE_THRESHOLD = 0.5f
        private const val TAG = "STALA_ONNX"

        private const val ENABLE_VERBOSE_LOGS = false
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

        // perf(onnx): enable graph optimization and limit runtime threads
        val options = OrtSession.SessionOptions().apply {
            setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)

            // Safer for low-mid devices.
            setIntraOpNumThreads(2)
            setInterOpNumThreads(1)
        }

        session = environment.createSession(modelFile.absolutePath, options)
        // perf(onnx): enable graph optimization and limit runtime threads

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

        // fix(onnx): decode input image with exif orientation
        val originalBitmap = decodeBitmapWithCorrectOrientation(imagePath)
            ?: return errorResponse("Failed to decode image.", imagePath)
        // fix(onnx): decode input image with exif orientation

        if (ENABLE_VERBOSE_LOGS) {
            Log.d(
                TAG,
                "detectFromImagePath: original bitmap width=${originalBitmap.width} height=${originalBitmap.height}"
            )
        }

        return try {
            val enhancedBitmap = originalBitmap // perf(onnx): skip clahe enhancement during normal inference

            val resizedBitmap = letterboxBitmap(
                enhancedBitmap,
                MODEL_INPUT_WIDTH,
                MODEL_INPUT_HEIGHT
            )

            // perf(onnx): skip clahe enhancement during normal inference
            if (enhancedBitmap !== originalBitmap) {
                enhancedBitmap.recycle()
            }

            val preprocessedImagePath = imagePath // perf(onnx): avoid saving preprocessed image during release detection

            Log.d(
                TAG,
                "detectFromImagePath: letterboxed bitmap width=${resizedBitmap.width} height=${resizedBitmap.height}"
            )

            Log.d(TAG, "detectFromImagePath: preprocessedImagePath=$preprocessedImagePath")

            val inputBuffer = bitmapToFloatBuffer(resizedBitmap)
            Log.d(TAG, "detectFromImagePath: inputBuffer capacity=${inputBuffer.capacity()}")
            Log.d(TAG, "detectFromImagePath: bitmap loaded width=${originalBitmap.width} height=${originalBitmap.height}")

            val detections = run(
                inputBuffer = inputBuffer,
                inputWidth = MODEL_INPUT_WIDTH,
                inputHeight = MODEL_INPUT_HEIGHT,
                scoreThreshold = scoreThreshold
            )

            Log.d(TAG, "detectFromImagePath: detections count=${detections.size}")

            if (resizedBitmap !== originalBitmap && !resizedBitmap.isRecycled) {
                resizedBitmap.recycle()
            }

            if (!originalBitmap.isRecycled) {
                originalBitmap.recycle()
            }

            mapOf(
                "status" to "success",
                "message" to "ONNX detection completed successfully.",
                "modelVersion" to "stala_multiclass_detector.onnx",
                "inputImagePath" to imagePath,
                "preprocessedImagePath" to preprocessedImagePath,
                "detectionImagePath" to preprocessedImagePath,
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
            if (!originalBitmap.isRecycled) {
                originalBitmap.recycle()
            }
            errorResponse("ONNX detection failed: ${e.message}", imagePath)
        }
    }

    fun run(
        inputBuffer: FloatBuffer,
        inputWidth: Int,
        inputHeight: Int,
        scoreThreshold: Float = DEFAULT_SCORE_THRESHOLD
    ): List<Map<String, Any>> {
        val activeSession = session
            ?: throw IllegalStateException("ONNX model session is not loaded.")

        val inputName = activeSession.inputNames.first()

        // Keep this as [3, H, W] if your current model works with it.
        val inputShape = longArrayOf(3, inputHeight.toLong(), inputWidth.toLong())

        OnnxTensor.createTensor(
            environment,
            inputBuffer,
            inputShape
        ).use { inputTensor ->

            activeSession.run(mapOf(inputName to inputTensor)).use { output ->
                @Suppress("UNCHECKED_CAST")
                val boxes = output[0].value as Array<FloatArray>
                val labels = output[1].value as LongArray
                val scores = output[2].value as FloatArray

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

                return detections
            }
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

    private fun bitmapToFloatBuffer(bitmap: Bitmap): FloatBuffer {
        val width = bitmap.width
        val height = bitmap.height
        val pixelCount = width * height

        val buffer = ByteBuffer
            .allocateDirect(4 * 3 * pixelCount)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()

        val pixels = IntArray(pixelCount)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)

        for (i in pixels.indices) {
            val pixel = pixels[i]
            buffer.put(i, ((pixel shr 16) and 0xFF) / 255.0f)
            buffer.put(pixelCount + i, ((pixel shr 8) and 0xFF) / 255.0f)
            buffer.put((2 * pixelCount) + i, (pixel and 0xFF) / 255.0f)
        }

        buffer.rewind()
        return buffer
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

    // perf(onnx): reuse copied model asset during startup
    private fun copyAssetToInternalFile(assetPath: String): File {
        val fileName = assetPath.substringAfterLast("/")
        val outFile = File(context.filesDir, fileName)

        if (outFile.exists() && outFile.length() > 1024 * 1024) {
            Log.d(
                TAG,
                "copyAssetToInternalFile: using existing model file size=${outFile.length()}"
            )
            return outFile
        }

        Log.d(TAG, "copyAssetToInternalFile: copying asset=$assetPath to ${outFile.absolutePath}")

        context.assets.open(assetPath).use { input ->
            FileOutputStream(outFile, false).use { output ->
                input.copyTo(output)
            }
        }

        Log.d(TAG, "copyAssetToInternalFile: copy complete size=${outFile.length()}")

        if (outFile.length() <= 1024 * 1024) {
            Log.e(TAG, "copyAssetToInternalFile: copied model is suspiciously small")
        }

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

    private fun decodeBitmapWithCorrectOrientation(imagePath: String): Bitmap? {
        val bitmap = decodeSampledBitmap(imagePath, 1600, 1600) ?: return null  // perf(onnx): downsample large input images before inference

        return try {
            val exif = ExifInterface(imagePath)
            val orientation = exif.getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL
            )

            if (ENABLE_VERBOSE_LOGS) {
                Log.d(TAG, "decodeBitmap: EXIF orientation=$orientation")
            }

            val matrix = Matrix()

            when (orientation) {
                ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
                ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
                ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
                ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.preScale(-1f, 1f)
                ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.preScale(1f, -1f)
                else -> return bitmap
            }

            val rotated = Bitmap.createBitmap(
                bitmap,
                0,
                0,
                bitmap.width,
                bitmap.height,
                matrix,
                true
            )

            Log.d(TAG, "decodeBitmap: rotated width=${rotated.width} height=${rotated.height}")

            if (rotated != bitmap) {
                bitmap.recycle()
            }

            rotated
        } catch (e: Exception) {
            bitmap
        }
    }

    // perf(onnx): downsample large input images before inference
    private fun decodeSampledBitmap(
        imagePath: String,
        reqWidth: Int,
        reqHeight: Int
    ): Bitmap? {
        val boundsOptions = BitmapFactory.Options().apply {
            inJustDecodeBounds = true
        }

        BitmapFactory.decodeFile(imagePath, boundsOptions)

        val decodeOptions = BitmapFactory.Options().apply {
            inSampleSize = calculateInSampleSize(
                boundsOptions.outWidth,
                boundsOptions.outHeight,
                reqWidth,
                reqHeight
            )
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }

        Log.d(
            TAG,
            "decodeSampledBitmap: original=${boundsOptions.outWidth}x${boundsOptions.outHeight} " +
                    "sampleSize=${decodeOptions.inSampleSize}"
        )

        return BitmapFactory.decodeFile(imagePath, decodeOptions)
    }

    private fun calculateInSampleSize(
        width: Int,
        height: Int,
        reqWidth: Int,
        reqHeight: Int
    ): Int {
        var inSampleSize = 1

        if (height > reqHeight || width > reqWidth) {
            var halfHeight = height / 2
            var halfWidth = width / 2

            while (
                (halfHeight / inSampleSize) >= reqHeight &&
                (halfWidth / inSampleSize) >= reqWidth
            ) {
                inSampleSize *= 2
            }
        }

        return inSampleSize
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