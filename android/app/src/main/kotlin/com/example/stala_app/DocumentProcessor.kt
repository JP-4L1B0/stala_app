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
            return failure(
                reason = "Image file does not exist."
            )
        }

        val bitmap = BitmapFactory.decodeFile(imagePath)
            ?: return failure(reason = "Failed to decode image.")

        val width = bitmap.width
        val height = bitmap.height

        if (width < 200 || height < 200) {
            bitmap.recycle()
            return failure(
                reason = "Image is too small for document detection."
            )
        }

        // Temporary centered candidate.
        // Replace this later with real OpenCV contour detection.
        val bounds = mapOf(
            "topLeft" to mapOf("x" to 0.08, "y" to 0.12),
            "topRight" to mapOf("x" to 0.92, "y" to 0.12),
            "bottomRight" to mapOf("x" to 0.92, "y" to 0.90),
            "bottomLeft" to mapOf("x" to 0.08, "y" to 0.90)
        )

        bitmap.recycle()

        return mapOf(
            "hasDocument" to true,
            "confidence" to 0.35,
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
}