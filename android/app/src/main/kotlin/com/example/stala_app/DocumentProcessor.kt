package com.example.stala_app

import android.graphics.Bitmap
import android.util.Log
import androidx.core.graphics.createBitmap
import androidx.core.graphics.get
import androidx.core.graphics.scale
import org.opencv.android.Utils
import org.opencv.core.Mat
import org.opencv.core.MatOfPoint
import org.opencv.core.MatOfPoint2f
import org.opencv.core.Size
import org.opencv.imgproc.Imgproc
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max
import kotlin.math.sqrt

/**
 * Refactored document processor for the STALA capture flow.
 *
 * Main goals:
 * - keep OpenCV as the primary detector
 * - keep the old heuristic logic as fallback
 * - add music-sheet-aware validation instead of only page-aware validation
 * - support a second validation pass after the user manually adjusts the crop
 *
 * Decision model:
 * - strong: confident music-sheet region, proceed normally
 * - weak: usable but uncertain, suggest manual adjustment
 * - fail: not a reliable music-sheet region, allow only guarded override in UI
 */
object DocumentProcessor {

    private const val BRIGHTNESS_THRESHOLD = 160

    private const val STATE_STRONG = "strong"
    private const val STATE_WEAK = "weak"
    private const val STATE_FAIL = "fail"

    fun detectDocumentBounds(imagePath: String): Map<String, Any?> {
        Log.d("DocumentProcessor", "=== detectDocumentBounds called ===")
        Log.d("DocumentProcessor", "imagePath=$imagePath")

        val imageFile = File(imagePath)
        if (!imageFile.exists()) {
            return detectionFailure("Image file does not exist.")
        }

        val bitmap = ImageDecodeUtils.decodeBitmapWithCorrectOrientation(imagePath)
            ?: return detectionFailure("Failed to decode image.")

        if (bitmap.width < 200 || bitmap.height < 200) {
            bitmap.recycle()
            return detectionFailure("Image is too small for document detection.")
        }

        val targetWidth = 400
        val scale = targetWidth.toFloat() / bitmap.width.toFloat()
        val scaledHeight = (bitmap.height * scale).toInt().coerceAtLeast(1)
        val scaledBitmap = bitmap.scale(targetWidth, scaledHeight)
        bitmap.recycle()

        Log.d(
            "DocumentProcessor",
            "scaledWidth=${scaledBitmap.width} scaledHeight=${scaledBitmap.height}"
        )

        val openCvBounds = findOpenCvDocumentBounds(scaledBitmap)
        val validOpenCvBounds = openCvBounds?.takeIf {
            isAcceptableOpenCvBounds(it, scaledBitmap)
        }

        val fullSheetBounds =
            if (validOpenCvBounds == null && isLikelyMusicSheetImage(scaledBitmap)) {
                findFullSheetBounds(scaledBitmap)
            } else {
                null
            }

        val contourFallbackBounds =
            if (validOpenCvBounds == null && fullSheetBounds == null) {
                findContourDocumentBounds(scaledBitmap)
            } else {
                null
            }

        val brightFallbackBounds =
            if (validOpenCvBounds == null &&
                fullSheetBounds == null &&
                contourFallbackBounds == null
            ) {
                findBrightDocumentBounds(scaledBitmap)
            } else {
                null
            }

        val detectedBounds =
            validOpenCvBounds
                ?: fullSheetBounds
                ?: contourFallbackBounds
                ?: brightFallbackBounds

        Log.d("DocumentProcessor", "openCvBounds=${openCvBounds?.contentToString()}")
        Log.d("DocumentProcessor", "validOpenCvBounds=${validOpenCvBounds?.contentToString()}")
        Log.d("DocumentProcessor", "fullSheetBounds=${fullSheetBounds?.contentToString()}")
        Log.d("DocumentProcessor", "contourFallbackBounds=${contourFallbackBounds?.contentToString()}")
        Log.d("DocumentProcessor", "brightFallbackBounds=${brightFallbackBounds?.contentToString()}")
        Log.d("DocumentProcessor", "detectedBounds=${detectedBounds?.contentToString()}")

        if (detectedBounds == null) {
            scaledBitmap.recycle()
            return detectionFailure("Can't confidently detect a document. Kindly adjust the box.")
        }

        var left = detectedBounds[0]
        var top = detectedBounds[1]
        var right = detectedBounds[2]
        var bottom = detectedBounds[3]

        val usedHeuristicFallback =
            validOpenCvBounds == null &&
                    fullSheetBounds == null &&
                    (contourFallbackBounds != null || brightFallbackBounds != null)

        if (usedHeuristicFallback) {
            left = refineLeftEdge(scaledBitmap, left, top, bottom)
            right = refineRightEdge(scaledBitmap, right, top, bottom)
            top = refineTopEdge(scaledBitmap, top, left, right)
            bottom = refineBottomEdge(scaledBitmap, bottom, left, right)
        }

        val flutterBounds = buildFlutterBounds(
            scaledBitmap = scaledBitmap,
            left = left,
            top = top,
            right = right,
            bottom = bottom
        )

        val validation = validateBoundsOnBitmap(
            bitmap = scaledBitmap,
            left = left,
            top = top,
            right = right,
            bottom = bottom,
            acceptedByOpenCv = validOpenCvBounds != null,
            acceptedByFullSheet = fullSheetBounds != null,
            acceptedByHeuristic = usedHeuristicFallback
        )

        scaledBitmap.recycle()

        return mapOf(
            "hasDocument" to true,
            "confidence" to validation.confidence,
            "bounds" to flutterBounds,
            "validationState" to validation.state,
            "needsManualAdjustment" to (validation.state != STATE_STRONG),
            "reason" to validation.reason
        )
    }

    /**
     * Second-pass validation used after the user manually adjusts the crop box.
     *
     * This is more forgiving than auto-detection but still music-sheet-aware.
     */
    fun validateSelectedCrop(
        imagePath: String,
        bounds: Map<String, Any?>
    ): Map<String, Any?> {

        Log.d("DocumentProcessor", "=== validateSelectedCrop called ===")

        val imageFile = File(imagePath)
        if (!imageFile.exists()) {
            return validationFailure("Image file does not exist.")
        }

        val bitmap = ImageDecodeUtils.decodeBitmapWithCorrectOrientation(imagePath)
            ?: return validationFailure("Failed to decode image.")

        try {
            val rect = boundsToRect(bitmap, bounds) ?: return validationFailure(
                "The selected crop is not yet a reliable music-sheet region. Please adjust the box."
            )

            val left = rect[0]
            val top = rect[1]
            val right = rect[2]
            val bottom = rect[3]

            val cropWidth = (right - left).coerceAtLeast(1)
            val cropHeight = (bottom - top).coerceAtLeast(1)

            val marginX = (cropWidth * 0.02).toInt()
            val marginY = (cropHeight * 0.02).toInt()

            val expandedLeft = (left - marginX).coerceAtLeast(0)
            val expandedTop = (top - marginY).coerceAtLeast(0)
            val expandedRight = (right + marginX).coerceAtMost(bitmap.width)
            val expandedBottom = (bottom + marginY).coerceAtMost(bitmap.height)

            val expandedWidth = (expandedRight - expandedLeft).coerceAtLeast(1)
            val expandedHeight = (expandedBottom - expandedTop).coerceAtLeast(1)

            val croppedBitmap = Bitmap.createBitmap(
                bitmap,
                expandedLeft,
                expandedTop,
                expandedWidth,
                expandedHeight
            )

            val targetWidth = 400
            val scale = targetWidth.toFloat() / croppedBitmap.width.toFloat()
            val scaledHeight = (croppedBitmap.height * scale).toInt().coerceAtLeast(1)
            val scaledCrop = croppedBitmap.scale(targetWidth, scaledHeight)

            Log.d(
                "DocumentProcessor",
                "validate rect=[$left, $top, $right, $bottom] expanded=[$expandedLeft, $expandedTop, $expandedRight, $expandedBottom]"
            )
            Log.d("DocumentProcessor", "validate scaledWidth=${scaledCrop.width} scaledHeight=${scaledCrop.height}")

            croppedBitmap.recycle()

            val validation = validateBoundsOnBitmap(
                bitmap = scaledCrop,
                left = 0,
                top = 0,
                right = scaledCrop.width,
                bottom = scaledCrop.height,
                acceptedByOpenCv = false,
                acceptedByFullSheet = false,
                acceptedByHeuristic = true
            )

            Log.d("DocumentProcessor", "validate result state=${validation.state} confidence=${validation.confidence} reason=${validation.reason}")

            scaledCrop.recycle()

            return mapOf(
                "validationState" to validation.state,
                "confidence" to validation.confidence,
                "reason" to validation.reason
            )
        } finally {
            bitmap.recycle()
        }
    }

    fun cropDocumentImage(
        imagePath: String,
        bounds: Map<String, Any?>
    ): String? {
        val sourceFile = File(imagePath)
        if (!sourceFile.exists()) return null

        val bitmap = ImageDecodeUtils.decodeBitmapWithCorrectOrientation(imagePath) ?: return null

        val width = bitmap.width.toFloat()
        val height = bitmap.height.toFloat()

        val topLeft = bounds["topLeft"] as? Map<*, *> ?: return recycleAndNull(bitmap)
        val topRight = bounds["topRight"] as? Map<*, *> ?: return recycleAndNull(bitmap)
        val bottomRight = bounds["bottomRight"] as? Map<*, *> ?: return recycleAndNull(bitmap)
        val bottomLeft = bounds["bottomLeft"] as? Map<*, *> ?: return recycleAndNull(bitmap)

        val tlx = ((topLeft["x"] as? Number)?.toFloat() ?: return recycleAndNull(bitmap))
            .coerceIn(0f, 1f) * width
        val tly = ((topLeft["y"] as? Number)?.toFloat() ?: return recycleAndNull(bitmap))
            .coerceIn(0f, 1f) * height

        val trx = ((topRight["x"] as? Number)?.toFloat() ?: return recycleAndNull(bitmap))
            .coerceIn(0f, 1f) * width
        val tryy = ((topRight["y"] as? Number)?.toFloat() ?: return recycleAndNull(bitmap))
            .coerceIn(0f, 1f) * height

        val brx = ((bottomRight["x"] as? Number)?.toFloat() ?: return recycleAndNull(bitmap))
            .coerceIn(0f, 1f) * width
        val bry = ((bottomRight["y"] as? Number)?.toFloat() ?: return recycleAndNull(bitmap))
            .coerceIn(0f, 1f) * height

        val blx = ((bottomLeft["x"] as? Number)?.toFloat() ?: return recycleAndNull(bitmap))
            .coerceIn(0f, 1f) * width
        val bly = ((bottomLeft["y"] as? Number)?.toFloat() ?: return recycleAndNull(bitmap))
            .coerceIn(0f, 1f) * height

        val topWidth = distance(tlx, tly, trx, tryy)
        val bottomWidth = distance(blx, bly, brx, bry)
        val leftHeight = distance(tlx, tly, blx, bly)
        val rightHeight = distance(trx, tryy, brx, bry)

        val outputWidth = maxOf(1, max(topWidth, bottomWidth).toInt())
        val outputHeight = maxOf(1, max(leftHeight, rightHeight).toInt())

        if (outputWidth < 50 || outputHeight < 50) {
            return recycleAndNull(bitmap)
        }

        val src = floatArrayOf(
            tlx, tly,
            trx, tryy,
            brx, bry,
            blx, bly
        )

        val dst = floatArrayOf(
            0f, 0f,
            outputWidth.toFloat(), 0f,
            outputWidth.toFloat(), outputHeight.toFloat(),
            0f, outputHeight.toFloat()
        )

        val matrix = android.graphics.Matrix()
        val success = matrix.setPolyToPoly(src, 0, dst, 0, 4)

        if (!success) {
            bitmap.recycle()
            return null
        }

        val outputBitmap = createBitmap(outputWidth, outputHeight)
        val canvas = android.graphics.Canvas(outputBitmap)
        canvas.drawBitmap(bitmap, matrix, null)

        val finalBitmap = outputBitmap

        val outputFile = File(
            sourceFile.parentFile,
            "cropped_${System.currentTimeMillis()}.jpg"
        )

        FileOutputStream(outputFile).use { out ->
            finalBitmap.compress(Bitmap.CompressFormat.JPEG, 95, out)
            out.flush()
        }

        bitmap.recycle()
        finalBitmap.recycle()

        return outputFile.absolutePath
    }

    private data class SheetValidation(
        val state: String,
        val confidence: Double,
        val reason: String
    )

    private fun detectionFailure(reason: String): Map<String, Any?> {
        return mapOf(
            "hasDocument" to false,
            "confidence" to 0.0,
            "reason" to reason,
            "validationState" to STATE_FAIL,
            "needsManualAdjustment" to true
        )
    }

    private fun validationFailure(reason: String): Map<String, Any?> {
        return mapOf(
            "validationState" to STATE_FAIL,
            "confidence" to 0.0,
            "reason" to reason
        )
    }

    private fun buildFlutterBounds(
        scaledBitmap: Bitmap,
        left: Int,
        top: Int,
        right: Int,
        bottom: Int
    ): Map<String, Any?> {
        val normalizedTopLeftX = left.toDouble() / scaledBitmap.width.toDouble()
        val normalizedTopLeftY = top.toDouble() / scaledBitmap.height.toDouble()

        val normalizedTopRightX = right.toDouble() / scaledBitmap.width.toDouble()
        val normalizedTopRightY = top.toDouble() / scaledBitmap.height.toDouble()

        val normalizedBottomRightX = right.toDouble() / scaledBitmap.width.toDouble()
        val normalizedBottomRightY = bottom.toDouble() / scaledBitmap.height.toDouble()

        val normalizedBottomLeftX = left.toDouble() / scaledBitmap.width.toDouble()
        val normalizedBottomLeftY = bottom.toDouble() / scaledBitmap.height.toDouble()

        return mapOf(
            "topLeft" to mapOf("x" to normalizedTopLeftX, "y" to normalizedTopLeftY),
            "topRight" to mapOf("x" to normalizedTopRightX, "y" to normalizedTopRightY),
            "bottomRight" to mapOf("x" to normalizedBottomRightX, "y" to normalizedBottomRightY),
            "bottomLeft" to mapOf("x" to normalizedBottomLeftX, "y" to normalizedBottomLeftY)
        )
    }

    private fun validateBoundsOnBitmap(
        bitmap: Bitmap,
        left: Int,
        top: Int,
        right: Int,
        bottom: Int,
        acceptedByOpenCv: Boolean,
        acceptedByFullSheet: Boolean,
        acceptedByHeuristic: Boolean
    ): SheetValidation {
        val safeLeft = left.coerceIn(0, bitmap.width - 1)
        val safeTop = top.coerceIn(0, bitmap.height - 1)
        val safeRight = right.coerceIn(safeLeft + 1, bitmap.width)
        val safeBottom = bottom.coerceIn(safeTop + 1, bitmap.height)

        val widthRatio = (safeRight - safeLeft).toDouble() / bitmap.width.toDouble()
        val heightRatio = (safeBottom - safeTop).toDouble() / bitmap.height.toDouble()
        val areaRatio = widthRatio * heightRatio

        val shapeScore = when {
            acceptedByOpenCv -> 0.18
            acceptedByFullSheet -> 0.12
            acceptedByHeuristic -> 0.08
            else -> 0.0
        }

        val evidence = scoreMusicSheetRegion(
            bitmap = bitmap,
            left = safeLeft,
            top = safeTop,
            right = safeRight,
            bottom = safeBottom
        )

        var score = 0.0

        // Strong signal: actual music structure
        score += evidence.staffGroupScore * 0.50

        // Secondary: horizontal line evidence
        score += evidence.strongHorizontalLineDensity * 0.25
        score += evidence.horizontalLineDensity * 0.15

        // Weak tone-based signals
        score += (1.0 - evidence.lightRatio) * 0.05
        score += evidence.darkRatio * 0.05

        // Small crop-shape trust bonus
        score += shapeScore

        if (
            evidence.staffGroupScore in 0.40..0.60 &&
            evidence.horizontalLineDensity > 0.30
        ) {
            score += 0.08
        }

        // HARD REJECTION: looks like lines but no real staff structure
        if (
            evidence.staffGroupScore < 0.45 &&
            evidence.strongHorizontalLineDensity > 0.6
        ) {
            Log.d("DocumentProcessor", "Rejected: strong lines but weak staff structure")

            return SheetValidation(
                state = STATE_FAIL,
                confidence = score.coerceIn(0.0, 1.0),
                reason = "This crop has lines, but they do not look like a clear music sheet."
            )
        }

        // STRONG override after rejection
        if (evidence.staffGroupScore > 0.60) {
            return SheetValidation(
                state = STATE_STRONG,
                confidence = evidence.staffGroupScore.coerceIn(0.0, 1.0),
                reason = "Music sheet detected via staff structure."
            )
        }

        Log.d(
            "DocumentProcessor",
            "musicSheetScore=$score lightRatio=${evidence.lightRatio} darkRatio=${evidence.darkRatio} horizontalLineDensity=${evidence.horizontalLineDensity} strongHorizontalLineDensity=${evidence.strongHorizontalLineDensity} edgeLineDensity=${evidence.edgeLineDensity} continuityDensity=${evidence.continuityDensity} staffGroupScore=${evidence.staffGroupScore} shapeScore=$shapeScore"
        )

        return when {
            score >= 0.60 -> SheetValidation(
                state = STATE_STRONG,
                confidence = score.coerceIn(0.0, 1.0),
                reason = "Music-sheet region detected."
            )
            score >= 0.40 -> SheetValidation(
                state = STATE_WEAK,
                confidence = score.coerceIn(0.0, 1.0),
                reason = "Music sheet detected, but the crop is still unclear. Try tightening the box around the notes and staff lines."
            )
            else -> SheetValidation(
                state = STATE_FAIL,
                confidence = score.coerceIn(0.0, 1.0),
                reason = "This crop does not look like a clear music sheet. Adjust the box to include the full staff area, or proceed if this is intentional."
            )
        }
    }

    private data class SheetEvidence(
        val lightRatio: Double,
        val darkRatio: Double,
        val horizontalLineDensity: Double,
        val strongHorizontalLineDensity: Double,
        val edgeLineDensity: Double,
        val continuityDensity: Double,
        val staffGroupScore: Double
    )

    private fun scoreMusicSheetRegion(
        bitmap: Bitmap,
        left: Int,
        top: Int,
        right: Int,
        bottom: Int
    ): SheetEvidence {
        val width = (right - left).coerceAtLeast(1)
        val height = (bottom - top).coerceAtLeast(1)

        var lightPixels = 0
        var darkPixels = 0
        var totalPixels = 0

        var sampledRows = 0
        var lineLikeRows = 0
        var strongLineRows = 0
        var edgeLineRows = 0
        var continuityRows = 0

        val rowSignalScores = mutableListOf<Double>()

        val stepX = maxOf(1, width / 180)
        val stepY = maxOf(1, height / 260)

        for (y in (top + 1) until (bottom - 1) step stepY) {
            var rowDark = 0
            var rowTotal = 0
            var rowEdgeHits = 0
            var longestRun = 0
            var currentRun = 0

            for (x in left until right step stepX) {
                val centerPixel = bitmap.getPixel(x, y)
                val upPixel = bitmap.getPixel(x, (y - 1).coerceAtLeast(top))
                val downPixel = bitmap.getPixel(x, (y + 1).coerceAtMost(bottom - 1))

                val center = averageBrightness(centerPixel)
                val up = averageBrightness(upPixel)
                val down = averageBrightness(downPixel)

                if (center > 210) lightPixels++
                if (center < 165) {
                    darkPixels++
                    rowDark++
                    currentRun++
                } else {
                    if (currentRun > longestRun) longestRun = currentRun
                    currentRun = 0
                }

                // Edge-based detection for thin horizontal lines:
                // a dark row between brighter rows is likely a staff line.
                val surroundAvg = (up + down) / 2.0
                val edgeStrength = surroundAvg - center.toDouble()
                if (edgeStrength > 18.0) {
                    rowEdgeHits++
                }

                totalPixels++
                rowTotal++
            }

            if (currentRun > longestRun) longestRun = currentRun

            if (rowTotal > 0) {
                val rowDarkRatio = rowDark.toDouble() / rowTotal.toDouble()
                val rowEdgeRatio = rowEdgeHits.toDouble() / rowTotal.toDouble()
                val continuityRatio = longestRun.toDouble() / rowTotal.toDouble()

                // Generic line-like rows
                if (rowDarkRatio in 0.03..0.30 || rowEdgeRatio in 0.08..0.70) {
                    lineLikeRows++
                }

                // Stronger evidence rows
                if (rowDarkRatio in 0.05..0.22 || rowEdgeRatio in 0.14..0.75) {
                    strongLineRows++
                }

                // Thin-line edge detector
                if (rowEdgeRatio in 0.10..0.85) {
                    edgeLineRows++
                }

                // Horizontal continuity detector
                if (continuityRatio >= 0.18) {
                    continuityRows++
                }

                // Combined row signal used for staff grouping
                val rowSignal =
                    (rowDarkRatio * 0.25) +
                            (rowEdgeRatio * 0.50) +
                            (continuityRatio * 0.25)

                rowSignalScores.add(rowSignal)
                sampledRows++
            }
        }

        val lightRatio =
            if (totalPixels == 0) 0.0 else lightPixels.toDouble() / totalPixels.toDouble()
        val darkRatio =
            if (totalPixels == 0) 0.0 else darkPixels.toDouble() / totalPixels.toDouble()
        val horizontalLineDensity =
            if (sampledRows == 0) 0.0 else lineLikeRows.toDouble() / sampledRows.toDouble()
        val strongHorizontalLineDensity =
            if (sampledRows == 0) 0.0 else strongLineRows.toDouble() / sampledRows.toDouble()
        val edgeLineDensity =
            if (sampledRows == 0) 0.0 else edgeLineRows.toDouble() / sampledRows.toDouble()
        val continuityDensity =
            if (sampledRows == 0) 0.0 else continuityRows.toDouble() / sampledRows.toDouble()

        val staffGroupScore = detectStaffGroupScore(rowSignalScores)

        return SheetEvidence(
            lightRatio = lightRatio,
            darkRatio = darkRatio,
            horizontalLineDensity = horizontalLineDensity,
            strongHorizontalLineDensity = strongHorizontalLineDensity,
            edgeLineDensity = edgeLineDensity,
            continuityDensity = continuityDensity,
            staffGroupScore = staffGroupScore
        )
    }

    private fun detectStaffGroupScore(rowSignals: List<Double>): Double {
        if (rowSignals.isEmpty()) return 0.0

        val candidateRows = mutableListOf<Int>()

        for (i in rowSignals.indices) {
            val signal = rowSignals[i]

            // Lower threshold now that row signal includes edge + continuity evidence.
            if (signal >= 0.10) {
                candidateRows.add(i)
            }
        }

        if (candidateRows.isEmpty()) return 0.0

        // Merge nearby detections into single centers
        val mergedCenters = mutableListOf<Double>()
        var currentGroup = mutableListOf<Int>()

        for (index in candidateRows) {
            if (currentGroup.isEmpty()) {
                currentGroup.add(index)
            } else {
                val prev = currentGroup.last()
                if (index - prev <= 2) {
                    currentGroup.add(index)
                } else {
                    mergedCenters.add(currentGroup.average())
                    currentGroup = mutableListOf(index)
                }
            }
        }

        if (currentGroup.isNotEmpty()) {
            mergedCenters.add(currentGroup.average())
        }

        if (mergedCenters.size < 5) return 0.0

        var bestGroupScore = 0.0

        for (start in 0..mergedCenters.size - 5) {
            val group = mergedCenters.subList(start, start + 5)
            val gaps = mutableListOf<Double>()

            for (i in 0 until 4) {
                gaps.add(group[i + 1] - group[i])
            }

            val avgGap = gaps.average()
            if (avgGap <= 0.0) continue

            val variance = gaps.sumOf { gap ->
                val d = gap - avgGap
                d * d
            } / gaps.size.toDouble()

            val normalizedVariance = variance / (avgGap * avgGap)
            val spacingScore = (1.0 - normalizedVariance).coerceIn(0.0, 1.0)

            val plausibilityScore = when {
                avgGap in 1.0..16.0 -> 1.0
                avgGap in 16.0..26.0 -> 0.7
                else -> 0.2
            }

            val groupScore = spacingScore * plausibilityScore
            if (groupScore > bestGroupScore) {
                bestGroupScore = groupScore
            }
        }

        return bestGroupScore
    }

    private fun isAcceptableOpenCvBounds(bounds: IntArray, bitmap: Bitmap): Boolean {
        val width = bounds[2] - bounds[0]
        val height = bounds[3] - bounds[1]

        val widthRatio = width.toDouble() / bitmap.width
        val heightRatio = height.toDouble() / bitmap.height
        val areaRatio = widthRatio * heightRatio

        if (widthRatio < 0.25 || heightRatio < 0.25) return false
        if (areaRatio < 0.15) return false

        return true
    }

    private fun findFullSheetBounds(bitmap: Bitmap): IntArray {
        val insetX = (bitmap.width * 0.03).toInt()
        val insetY = (bitmap.height * 0.03).toInt()

        return intArrayOf(
            insetX,
            insetY,
            bitmap.width - insetX,
            bitmap.height - insetY
        )
    }

    private fun isLikelyMusicSheetImage(bitmap: Bitmap): Boolean {
        val evidence = scoreMusicSheetRegion(
            bitmap = bitmap,
            left = 0,
            top = 0,
            right = bitmap.width,
            bottom = bitmap.height
        )

        val score =
            (evidence.lightRatio * 0.16) +
                    (evidence.darkRatio * 0.12) +
                    (evidence.horizontalLineDensity * 0.16) +
                    (evidence.edgeLineDensity * 0.22) +
                    (evidence.continuityDensity * 0.14) +
                    (evidence.staffGroupScore * 0.20)

        Log.d(
            "DocumentProcessor",
            "fullImageSheetScore=$score lightRatio=${evidence.lightRatio} darkRatio=${evidence.darkRatio} horizontalLineDensity=${evidence.horizontalLineDensity} edgeLineDensity=${evidence.edgeLineDensity} continuityDensity=${evidence.continuityDensity} staffGroupScore=${evidence.staffGroupScore}"
        )

        return score >= 0.34
    }

    private fun boundsToRect(
        bitmap: Bitmap,
        bounds: Map<String, Any?>
    ): IntArray? {
        val topLeft = bounds["topLeft"] as? Map<*, *> ?: return null
        val topRight = bounds["topRight"] as? Map<*, *> ?: return null
        val bottomRight = bounds["bottomRight"] as? Map<*, *> ?: return null
        val bottomLeft = bounds["bottomLeft"] as? Map<*, *> ?: return null

        val tlx = (((topLeft["x"] as? Number)?.toDouble() ?: return null) * bitmap.width).toInt()
        val tly = (((topLeft["y"] as? Number)?.toDouble() ?: return null) * bitmap.height).toInt()
        val trx = (((topRight["x"] as? Number)?.toDouble() ?: return null) * bitmap.width).toInt()
        val tryy = (((topRight["y"] as? Number)?.toDouble() ?: return null) * bitmap.height).toInt()
        val brx = (((bottomRight["x"] as? Number)?.toDouble() ?: return null) * bitmap.width).toInt()
        val bry = (((bottomRight["y"] as? Number)?.toDouble() ?: return null) * bitmap.height).toInt()
        val blx = (((bottomLeft["x"] as? Number)?.toDouble() ?: return null) * bitmap.width).toInt()
        val bly = (((bottomLeft["y"] as? Number)?.toDouble() ?: return null) * bitmap.height).toInt()

        val left = minOf(tlx, trx, brx, blx).coerceIn(0, bitmap.width - 1)
        val top = minOf(tly, tryy, bry, bly).coerceIn(0, bitmap.height - 1)
        val right = maxOf(tlx, trx, brx, blx).coerceIn(left + 1, bitmap.width)
        val bottom = maxOf(tly, tryy, bry, bly).coerceIn(top + 1, bitmap.height)

        return intArrayOf(left, top, right, bottom)
    }

    private fun recycleAndNull(bitmap: Bitmap): String? {
        bitmap.recycle()
        return null
    }

    private fun findOpenCvDocumentBounds(bitmap: Bitmap): IntArray? {
        val rgba = Mat()
        val gray = Mat()
        val blurred = Mat()
        val binary = Mat()
        val morphed = Mat()
        val hierarchy = Mat()

        return try {
            Utils.bitmapToMat(bitmap, rgba)

            Imgproc.cvtColor(rgba, gray, Imgproc.COLOR_RGBA2GRAY)
            Imgproc.GaussianBlur(gray, blurred, Size(5.0, 5.0), 0.0)

            Imgproc.adaptiveThreshold(
                blurred,
                binary,
                255.0,
                Imgproc.ADAPTIVE_THRESH_GAUSSIAN_C,
                Imgproc.THRESH_BINARY_INV,
                21,
                15.0
            )

            val kernel = Imgproc.getStructuringElement(
                Imgproc.MORPH_RECT,
                Size(5.0, 5.0)
            )
            Imgproc.morphologyEx(
                binary,
                morphed,
                Imgproc.MORPH_CLOSE,
                kernel
            )
            kernel.release()

            val contours = mutableListOf<MatOfPoint>()
            Imgproc.findContours(
                morphed,
                contours,
                hierarchy,
                Imgproc.RETR_EXTERNAL,
                Imgproc.CHAIN_APPROX_SIMPLE
            )

            Log.d("DocumentProcessor", "OpenCV contours=${contours.size}")

            val imageArea = bitmap.width.toDouble() * bitmap.height.toDouble()
            val imageCenterX = bitmap.width / 2.0
            val imageCenterY = bitmap.height / 2.0

            var bestRect: IntArray? = null
            var bestScore = Double.NEGATIVE_INFINITY

            for (contour in contours) {
                val contour2f = MatOfPoint2f(*contour.toArray())
                val perimeter = Imgproc.arcLength(contour2f, true)

                val approx = MatOfPoint2f()
                Imgproc.approxPolyDP(
                    contour2f,
                    approx,
                    0.02 * perimeter,
                    true
                )

                val rect = Imgproc.boundingRect(contour)
                val rectArea = rect.width.toDouble() * rect.height.toDouble()
                val fillRatio = rectArea / imageArea
                val aspectRatio =
                    if (rect.height == 0) 999.0 else rect.width.toDouble() / rect.height.toDouble()

                val centerX = rect.x + rect.width / 2.0
                val centerY = rect.y + rect.height / 2.0
                val centerDistance =
                    kotlin.math.abs(centerX - imageCenterX) / bitmap.width.toDouble() +
                            kotlin.math.abs(centerY - imageCenterY) / bitmap.height.toDouble()

                val approxPoints = approx.toArray().size

                var score = fillRatio * 120.0
                score -= kotlin.math.abs(aspectRatio - 0.72) * 14.0
                score -= centerDistance * 16.0
                score += when {
                    approxPoints == 4 -> 16.0
                    approxPoints == 5 -> 10.0
                    approxPoints == 6 -> 6.0
                    else -> 0.0
                }
                score += (rect.height.toDouble() / bitmap.height.toDouble()) * 10.0

                val isReasonable =
                    rect.width > bitmap.width * 0.12 &&
                            rect.height > bitmap.height * 0.18 &&
                            fillRatio > 0.035 &&
                            aspectRatio in 0.20..1.60

                if (isReasonable && score > bestScore) {
                    bestScore = score
                    bestRect = intArrayOf(
                        rect.x.coerceIn(0, bitmap.width - 1),
                        rect.y.coerceIn(0, bitmap.height - 1),
                        (rect.x + rect.width).coerceIn(0, bitmap.width - 1),
                        (rect.y + rect.height).coerceIn(0, bitmap.height - 1)
                    )
                }

                contour2f.release()
                approx.release()
                contour.release()
            }

            Log.d("DocumentProcessor", "OpenCV bestScore=$bestScore")
            bestRect
        } catch (e: Exception) {
            Log.e("DocumentProcessor", "OpenCV detection failed", e)
            null
        } finally {
            rgba.release()
            gray.release()
            blurred.release()
            binary.release()
            morphed.release()
            hierarchy.release()
        }
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
                val pixel = bitmap[x, y]
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

        if (brightCount < 500) return null
        if (maxX <= minX || maxY <= minY) return null

        return intArrayOf(minX, minY, maxX, maxY)
    }

    private fun findContourDocumentBounds(bitmap: Bitmap): IntArray? {
        val width = bitmap.width
        val height = bitmap.height

        val marginX = (width * 0.08).toInt()
        val marginY = (height * 0.08).toInt()

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        var edgeCount = 0

        for (y in marginY until height - marginY - 2 step 2) {
            for (x in marginX until width - marginX - 2 step 2) {
                val center = luminance(bitmap[x, y])
                val right = luminance(bitmap[x + 2, y])
                val bottom = luminance(bitmap[x, y + 2])

                val horizontalDiff = kotlin.math.abs(center - right)
                val verticalDiff = kotlin.math.abs(center - bottom)

                if (horizontalDiff > 45 || verticalDiff > 45) {
                    if (x < minX) minX = x
                    if (y < minY) minY = y
                    if (x > maxX) maxX = x
                    if (y > maxY) maxY = y
                    edgeCount++
                }
            }
        }

        Log.d("DocumentProcessor", "contour edgeCount=$edgeCount")

        if (edgeCount < 600) return null
        if (maxX <= minX || maxY <= minY) return null

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
                val lum = luminance(bitmap[x, y])
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
                if (streak >= 4) return best
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
                if (streak >= 4) return best
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
            val lum = luminance(bitmap[x, y])
            if (lum > BRIGHTNESS_THRESHOLD) bright++
            total++
        }

        return if (total == 0) 0.0 else bright.toDouble() / total.toDouble()
    }

    private fun horizontalBrightRatio(bitmap: Bitmap, y: Int, left: Int, right: Int): Double {
        var bright = 0
        var total = 0

        for (x in left..right step 2) {
            val lum = luminance(bitmap[x, y])
            if (lum > BRIGHTNESS_THRESHOLD) bright++
            total++
        }

        return if (total == 0) 0.0 else bright.toDouble() / total.toDouble()
    }

    private fun luminance(pixel: Int): Int {
        val r = android.graphics.Color.red(pixel)
        val g = android.graphics.Color.green(pixel)
        val b = android.graphics.Color.blue(pixel)
        return ((0.299 * r) + (0.587 * g) + (0.114 * b)).toInt()
    }

    private fun averageBrightness(pixel: Int): Int {
        val r = (pixel shr 16) and 0xff
        val g = (pixel shr 8) and 0xff
        val b = pixel and 0xff
        return (r + g + b) / 3
    }

    private fun distance(x1: Float, y1: Float, x2: Float, y2: Float): Float {
        val dx = x2 - x1
        val dy = y2 - y1
        return sqrt(dx * dx + dy * dy)
    }
}
