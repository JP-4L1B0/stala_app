package com.example.stala_app

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max
import android.util.Log

/**
 * Handles document boundary detection and crop output for the STALA capture flow.
 *
 * Current version:
 * - Downscales the image for faster scanning
 * - Estimates document borders through row/column darkness checks
 * - Returns explicit failure when no clear document region is found
 * - Crops using the normalized bounds received from Flutter
 *
 * Later upgrade path:
 * - Replace border scanning with OpenCV contour detection
 * - Replace rectangular crop with perspective warp
 */
object DocumentProcessor {

    /**
     * Detects likely document bounds from an image path.
     *
     * Current implementation is a safe scaffold:
     * - validates the file
     * - validates that the bitmap can be decoded
     * - returns a structured success/failure payload matching Flutter expectations
     */

    private const val BRIGHTNESS_THRESHOLD = 160 // or 185

    fun detectDocumentBounds(imagePath: String): Map<String, Any?> {
        Log.d("DocumentProcessor", "=== detectDocumentBounds called ===")
        Log.d("DocumentProcessor", "imagePath=$imagePath")

        val imageFile = File(imagePath)
        if (!imageFile.exists()) {
            Log.d("DocumentProcessor", "Image file does not exist.")
            return failure("Image file does not exist.")
        }

        val bitmap = BitmapFactory.decodeFile(imagePath)
            ?: run {
                Log.d("DocumentProcessor", "Failed to decode image.")
                return failure("Failed to decode image.")
            }

        val width = bitmap.width
        val height = bitmap.height

        Log.d("DocumentProcessor", "originalWidth=$width originalHeight=$height")

        if (width < 200 || height < 200) {
            bitmap.recycle()
            Log.d("DocumentProcessor", "Image too small for detection.")
            return failure("Image is too small for document detection.")
        }

        val targetWidth = 400
        val scale = targetWidth.toFloat() / width.toFloat()
        val scaledWidth = targetWidth
        val scaledHeight = (height * scale).toInt().coerceAtLeast(1)

        val scaledBitmap = Bitmap.createScaledBitmap(bitmap, scaledWidth, scaledHeight, true)
        bitmap.recycle()

        Log.d("DocumentProcessor", "scaledWidth=$scaledWidth scaledHeight=$scaledHeight")

        val detectedBounds = findBrightDocumentBounds(scaledBitmap)
        if (detectedBounds == null) {
            Log.d("DocumentProcessor", "findBrightDocumentBounds returned null")
            scaledBitmap.recycle()
            return failure("No clear document detected.")
        }

        var left = detectedBounds[0]
        var top = detectedBounds[1]
        var right = detectedBounds[2]
        var bottom = detectedBounds[3]

        left = refineLeftEdge(scaledBitmap, left, top, bottom)
        right = refineRightEdge(scaledBitmap, right, top, bottom)
        top = refineTopEdge(scaledBitmap, top, left, right)
        bottom = refineBottomEdge(scaledBitmap, bottom, left, right)

        Log.d("DocumentProcessor", "left=$left right=$right top=$top bottom=$bottom")

        val normalizedLeft = left.toDouble() / scaledBitmap.width.toDouble()
        val normalizedRight = right.toDouble() / scaledBitmap.width.toDouble()
        val normalizedTop = top.toDouble() / scaledBitmap.height.toDouble()
        val normalizedBottom = bottom.toDouble() / scaledBitmap.height.toDouble()

        Log.d(
            "DocumentProcessor",
            "normalizedLeft=$normalizedLeft normalizedRight=$normalizedRight normalizedTop=$normalizedTop normalizedBottom=$normalizedBottom"
        )

        val detectedWidth = normalizedRight - normalizedLeft
        val detectedHeight = normalizedBottom - normalizedTop
        val detectedArea = detectedWidth * detectedHeight

        val pixelWidth = right - left
        val pixelHeight = bottom - top
        val aspectRatio = pixelWidth.toDouble() / pixelHeight.toDouble()

        val centerX = (normalizedLeft + normalizedRight) / 2.0
        val centerY = (normalizedTop + normalizedBottom) / 2.0

        val isValid =
            detectedWidth > 0.25 &&
                    detectedHeight > 0.25 &&
                    detectedArea in 0.10..0.65 &&
                    aspectRatio in 0.55..0.90 &&
                    centerX in 0.30..0.70 &&
                    centerY in 0.30..0.70 &&
                    normalizedLeft < normalizedRight &&
                    normalizedTop < normalizedBottom

        centerX in 0.30..0.70 &&
                centerY in 0.30..0.70

        if (!isValid) {
            scaledBitmap.recycle()
            return failure("No clear document detected.")
        }

        val confidence = estimateConfidence(
            normalizedLeft,
            normalizedTop,
            normalizedRight,
            normalizedBottom
        )

        val flutterBounds = mapOf(
            "topLeft" to mapOf("x" to normalizedLeft, "y" to normalizedTop),
            "topRight" to mapOf("x" to normalizedRight, "y" to normalizedTop),
            "bottomRight" to mapOf("x" to normalizedRight, "y" to normalizedBottom),
            "bottomLeft" to mapOf("x" to normalizedLeft, "y" to normalizedBottom)
        )

        scaledBitmap.recycle()

        return mapOf(
            "hasDocument" to true,
            "confidence" to confidence,
            "bounds" to flutterBounds
        )
    }

    /**
     * Crops the bitmap using normalized bounds from Flutter and saves a new file.
     *
     * Current implementation uses an axis-aligned rectangle based on the outer
     * min/max corner values. This is enough to make the pipeline work end-to-end.
     *
     * Later upgrade path:
     * - use perspective transform / warp for skewed documents
     */
    fun cropDocumentImage(
        imagePath: String,
        bounds: Map<String, Any?>
    ): String? {
        val sourceFile = File(imagePath)
        if (!sourceFile.exists()) return null

        val bitmap = BitmapFactory.decodeFile(imagePath) ?: return null

        val width = bitmap.width
        val height = bitmap.height

        val topLeft = bounds["topLeft"] as? Map<*, *> ?: return recycleAndNull(bitmap)
        val topRight = bounds["topRight"] as? Map<*, *> ?: return recycleAndNull(bitmap)
        val bottomRight = bounds["bottomRight"] as? Map<*, *> ?: return recycleAndNull(bitmap)
        val bottomLeft = bounds["bottomLeft"] as? Map<*, *> ?: return recycleAndNull(bitmap)

        val xs = listOf(
            (topLeft["x"] as? Number)?.toFloat(),
            (topRight["x"] as? Number)?.toFloat(),
            (bottomRight["x"] as? Number)?.toFloat(),
            (bottomLeft["x"] as? Number)?.toFloat()
        )

        val ys = listOf(
            (topLeft["y"] as? Number)?.toFloat(),
            (topRight["y"] as? Number)?.toFloat(),
            (bottomRight["y"] as? Number)?.toFloat(),
            (bottomLeft["y"] as? Number)?.toFloat()
        )

        if (xs.any { it == null } || ys.any { it == null }) {
            return recycleAndNull(bitmap)
        }

        val minX = (xs.filterNotNull().minOrNull() ?: 0f).coerceIn(0f, 1f)
        val maxX = (xs.filterNotNull().maxOrNull() ?: 1f).coerceIn(0f, 1f)
        val minY = (ys.filterNotNull().minOrNull() ?: 0f).coerceIn(0f, 1f)
        val maxY = (ys.filterNotNull().maxOrNull() ?: 1f).coerceIn(0f, 1f)

        // A quick normalized size check before trying to crop
        val normalizedWidth = maxX - minX
        val normalizedHeight = maxY - minY

        if (normalizedWidth < 0.08f || normalizedHeight < 0.08f) {
            return recycleAndNull(bitmap)
        }

        val left = (minX * width).toInt().coerceIn(0, width - 1)
        val top = (minY * height).toInt().coerceIn(0, height - 1)
        val right = (maxX * width).toInt().coerceIn(left + 1, width)
        val bottom = (maxY * height).toInt().coerceIn(top + 1, height)

        val cropWidth = max(1, right - left)
        val cropHeight = max(1, bottom - top)

        val croppedBitmap = try {
            Bitmap.createBitmap(bitmap, left, top, cropWidth, cropHeight)
        } catch (_: Exception) {
            bitmap.recycle()
            return null
        }

        val outputFile = File(
            sourceFile.parentFile,
            "cropped_${System.currentTimeMillis()}.jpg"
        )

        FileOutputStream(outputFile).use { out ->
            croppedBitmap.compress(Bitmap.CompressFormat.JPEG, 95, out)
            out.flush()
        }

        bitmap.recycle()
        croppedBitmap.recycle()

        return outputFile.absolutePath
    }

    private fun failure(reason: String): Map<String, Any?> {
        return mapOf(
            "hasDocument" to false,
            "confidence" to 0.0,
            "reason" to reason
        )
    }

    private fun recycleAndNull(bitmap: Bitmap): String? {
        bitmap.recycle()
        return null
    }



    private fun luminance(pixel: Int): Int {
        val r = android.graphics.Color.red(pixel)
        val g = android.graphics.Color.green(pixel)
        val b = android.graphics.Color.blue(pixel)
        return ((0.299 * r) + (0.587 * g) + (0.114 * b)).toInt()
    }

    private fun findBrightDocumentBounds(bitmap: Bitmap): IntArray? {
        val width = bitmap.width
        val height = bitmap.height

        val marginX = (width * 0.05).toInt()
        val marginY = (height * 0.05).toInt()

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        var brightCount = 0

        for (y in marginY until (height - marginY) step 2) {
            for (x in marginX until (width - marginX) step 2) {
                val pixel = bitmap.getPixel(x, y)
                val lum = luminance(pixel)

                if (lum > BRIGHTNESS_THRESHOLD) {
                    val localBright = localBrightScore(bitmap, x, y)
                    if (localBright >= 6) {
                        if (x < minX) minX = x
                        if (y < minY) minY = y
                        if (x > maxX) maxX = x
                        if (y > maxY) maxY = y
                        brightCount++
                    }
                }
            }
        }

        Log.d(
            "DocumentProcessor",
            "brightCount=$brightCount minX=$minX minY=$minY maxX=$maxX maxY=$maxY"
        )

        if (brightCount < 500) {
            Log.d("DocumentProcessor", "Rejected: brightCount too low")
            return null
        }

        if (maxX <= minX || maxY <= minY) {
            Log.d("DocumentProcessor", "Rejected: invalid bounds")
            return null
        }

        return intArrayOf(minX, minY, maxX, maxY)
    }

    private fun localBrightScore(bitmap: Bitmap, centerX: Int, centerY: Int): Int {
        var score = 0
        val width = bitmap.width
        val height = bitmap.height

        for (dy in -2..2) {
            for (dx in -2..2) {
                val x = (centerX + dx).coerceIn(0, width - 1)
                val y = (centerY + dy).coerceIn(0, height - 1)
                val lum = luminance(bitmap.getPixel(x, y))
                if (lum > BRIGHTNESS_THRESHOLD) score++
            }
        }

        return score
    }

    private fun estimateConfidence(
        left: Double,
        top: Double,
        right: Double,
        bottom: Double
    ): Double {
        val width = right - left
        val height = bottom - top
        val area = width * height

        return when {
            area >= 0.55 -> 0.85
            area >= 0.40 -> 0.72
            area >= 0.25 -> 0.58
            else -> 0.42
        }
    }

    private fun refineLeftEdge(bitmap: Bitmap, initialLeft: Int, top: Int, bottom: Int): Int {
        val searchEnd = (bitmap.width * 0.6).toInt()
        var best = initialLeft
        var streak = 0

        for (x in initialLeft until searchEnd) {
            val ratio = verticalBrightRatio(bitmap, x, top, bottom)
            if (ratio >= 0.75) {
                if (streak == 0) best = x
                streak++
                if (streak >=4) return best
            } else {
                streak = 0
            }
        }

        return initialLeft
    }

    private fun refineRightEdge(bitmap: Bitmap, initialRight: Int, top: Int, bottom: Int): Int {
        val searchStart = (bitmap.width * 0.4).toInt()
        var best = initialRight
        var streak = 0

        for (x in initialRight downTo searchStart) {
            val ratio = verticalBrightRatio(bitmap, x, top, bottom)
            if (ratio >= 0.75) {
                if (streak == 0) best = x
                streak++
                if (streak >=4) return best
            } else {
                streak = 0
            }
        }

        return initialRight
    }

    private fun refineTopEdge(bitmap: Bitmap, initialTop: Int, left: Int, right: Int): Int {
        val searchEnd = (bitmap.height * 0.6).toInt()
        var best = initialTop
        var streak = 0

        for (y in initialTop until searchEnd) {
            val ratio = horizontalBrightRatio(bitmap, y, left, right)
            if (ratio >= 0.75) {
                if (streak == 0) best = y
                streak++
                if (streak >= 4) return best
            } else {
                streak = 0
            }
        }

        return initialTop
    }

    private fun refineBottomEdge(bitmap: Bitmap, initialBottom: Int, left: Int, right: Int): Int {
        val searchStart = (bitmap.height * 0.4).toInt()
        var best = initialBottom
        var streak = 0

        for (y in initialBottom downTo searchStart) {
            val ratio = horizontalBrightRatio(bitmap, y, left, right)
            if (ratio >= 0.75) {
                if (streak == 0) best = y
                streak++
                if (streak >= 4) return best
            } else {
                streak = 0
            }
        }

        return initialBottom
    }

    private fun verticalBrightRatio(bitmap: Bitmap, x: Int, top: Int, bottom: Int): Double {
        var bright = 0
        var total = 0

        for (y in top..bottom step 2) {
            val lum = luminance(bitmap.getPixel(x, y))
            if (lum > BRIGHTNESS_THRESHOLD) bright++
            total++
        }

        return if (total == 0) 0.0 else bright.toDouble() / total.toDouble()
    }

    private fun horizontalBrightRatio(bitmap: Bitmap, y: Int, left: Int, right: Int): Double {
        var bright = 0
        var total = 0

        for (x in left..right step 2) {
            val lum = luminance(bitmap.getPixel(x, y))
            if (lum > BRIGHTNESS_THRESHOLD) bright++
            total++
        }

        return if (total == 0) 0.0 else bright.toDouble() / total.toDouble()
    }
}