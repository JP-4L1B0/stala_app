package com.example.stala_app

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max
import kotlin.math.min

/**
 * Handles document boundary detection and crop output for the STALA capture flow.
 *
 * Current version:
 * - Returns a simple centered document candidate when the image is large enough
 * - Returns explicit failure when no usable image is found
 * - Crops using the normalized bounds received from Flutter
 *
 * Later upgrade path:
 * - Replace detectDocumentBounds with OpenCV contour detection
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
    fun detectDocumentBounds(imagePath: String): Map<String, Any?> {
        val imageFile = File(imagePath)
        if (!imageFile.exists()) {
            return failure("Image file does not exist.")
        }

        val bitmap = BitmapFactory.decodeFile(imagePath)
            ?: return failure("Failed to decode image.")

        val width = bitmap.width
        val height = bitmap.height

        if (width < 200 || height < 200) {
            bitmap.recycle()
            return failure("Image is too small for document detection.")
        }

        // Downscale for faster scanning.
        val targetWidth = 400
        val scale = targetWidth.toFloat() / width.toFloat()
        val scaledWidth = targetWidth
        val scaledHeight = (height * scale).toInt().coerceAtLeast(1)

        val scaledBitmap = Bitmap.createScaledBitmap(bitmap, scaledWidth, scaledHeight, true)
        bitmap.recycle()

        val left = findLeftEdge(scaledBitmap)
        val right = findRightEdge(scaledBitmap)
        val top = findTopEdge(scaledBitmap)
        val bottom = findBottomEdge(scaledBitmap)

        val normalizedLeft = left.toDouble() / scaledBitmap.width.toDouble()
        val normalizedRight = right.toDouble() / scaledBitmap.width.toDouble()
        val normalizedTop = top.toDouble() / scaledBitmap.height.toDouble()
        val normalizedBottom = bottom.toDouble() / scaledBitmap.height.toDouble()

        val detectedWidth = normalizedRight - normalizedLeft
        val detectedHeight = normalizedBottom - normalizedTop
        val detectedArea = detectedWidth * detectedHeight

        val isValid =
            normalizedLeft in 0.0..0.85 &&
                    normalizedRight in 0.15..1.0 &&
                    normalizedTop in 0.0..0.85 &&
                    normalizedBottom in 0.15..1.0 &&
                    detectedWidth > 0.35 &&
                    detectedHeight > 0.35 &&
                    detectedArea > 0.20 &&
                    normalizedLeft < normalizedRight &&
                    normalizedTop < normalizedBottom

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

        val bounds = mapOf(
            "topLeft" to mapOf("x" to normalizedLeft, "y" to normalizedTop),
            "topRight" to mapOf("x" to normalizedRight, "y" to normalizedTop),
            "bottomRight" to mapOf("x" to normalizedRight, "y" to normalizedBottom),
            "bottomLeft" to mapOf("x" to normalizedLeft, "y" to normalizedBottom)
        )

        scaledBitmap.recycle()

        return mapOf(
            "hasDocument" to true,
            "confidence" to confidence,
            "bounds" to bounds
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

    private fun findLeftEdge(bitmap: Bitmap): Int {
        val width = bitmap.width
        val height = bitmap.height
        val startX = (width * 0.05).toInt()
        val endX = (width * 0.45).toInt()

        for (x in startX until endX) {
            val darkRatio = columnDarkRatio(bitmap, x)
            if (darkRatio > 0.18) {
                return x
            }
        }

        return (width * 0.08).toInt()
    }

    private fun findRightEdge(bitmap: Bitmap): Int {
        val width = bitmap.width
        val startX = (width * 0.95).toInt()
        val endX = (width * 0.55).toInt()

        for (x in startX downTo endX) {
            val darkRatio = columnDarkRatio(bitmap, x)
            if (darkRatio > 0.18) {
                return x
            }
        }

        return (width * 0.92).toInt()
    }

    private fun findTopEdge(bitmap: Bitmap): Int {
        val height = bitmap.height
        val startY = (height * 0.05).toInt()
        val endY = (height * 0.45).toInt()

        for (y in startY until endY) {
            val darkRatio = rowDarkRatio(bitmap, y)
            if (darkRatio > 0.18) {
                return y
            }
        }

        return (height * 0.12).toInt()
    }

    private fun findBottomEdge(bitmap: Bitmap): Int {
        val height = bitmap.height
        val startY = (height * 0.95).toInt()
        val endY = (height * 0.55).toInt()

        for (y in startY downTo endY) {
            val darkRatio = rowDarkRatio(bitmap, y)
            if (darkRatio > 0.18) {
                return y
            }
        }

        return (height * 0.90).toInt()
    }

    private fun columnDarkRatio(bitmap: Bitmap, x: Int): Double {
        val height = bitmap.height
        var darkPixels = 0
        var sampled = 0

        for (y in 0 until height step 4) {
            val pixel = bitmap.getPixel(x, y)
            val luminance = luminance(pixel)
            if (luminance < 210) {
                darkPixels++
            }
            sampled++
        }

        return if (sampled == 0) 0.0 else darkPixels.toDouble() / sampled.toDouble()
    }

    private fun rowDarkRatio(bitmap: Bitmap, y: Int): Double {
        val width = bitmap.width
        var darkPixels = 0
        var sampled = 0

        for (x in 0 until width step 4) {
            val pixel = bitmap.getPixel(x, y)
            val luminance = luminance(pixel)
            if (luminance < 210) {
                darkPixels++
            }
            sampled++
        }

        return if (sampled == 0) 0.0 else darkPixels.toDouble() / sampled.toDouble()
    }

    private fun luminance(pixel: Int): Int {
        val r = android.graphics.Color.red(pixel)
        val g = android.graphics.Color.green(pixel)
        val b = android.graphics.Color.blue(pixel)
        return ((0.299 * r) + (0.587 * g) + (0.114 * b)).toInt()
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
}