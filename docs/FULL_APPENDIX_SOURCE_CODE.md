# File 1 — StaffSegmentationProcessor.kt

## Full Path

```text
D:\MyApps\AndroidStudio_Folder\stala_app\android\app\src\main\kotlin\com\example\stala_app\StaffSegmentationProcessor.kt
```

## Purpose

This file performs native OpenCV staff segmentation for cropped sheet images, detecting validated staff systems, staff lines, ledger lines, stems, beams, barlines, and measure regions. It supports the thesis objective of extracting structural music notation geometry for the OMR-to-tablature pipeline. It is important because later pitch translation, rhythm grouping, and tablature generation depend on reliable staff coordinates and symbol-context anchors.

## Full Source Code

```kotlin
package com.example.stala_app

import android.content.Context
import java.io.File
import android.util.Log

import org.opencv.core.Mat
import org.opencv.core.Point
import org.opencv.core.Scalar
import org.opencv.core.Size
import org.opencv.imgcodecs.Imgcodecs
import org.opencv.imgproc.Imgproc
import kotlin.math.roundToInt
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

object StaffSegmentationProcessor {

    private enum class SymbolState {
        DETECTED,
        INFERRED,
        REJECTED
    }

    fun segmentStaffLines(
        context: Context,
        imagePath: String,
        symbolDetections: List<Map<String, Any?>> = emptyList()
    ): Map<String, Any?> {

        val src = Imgcodecs.imread(imagePath)
        if (src.empty()) {
            return error("Failed to load image")
        }

        val gray = Mat()
        Imgproc.cvtColor(src, gray, Imgproc.COLOR_BGR2GRAY)

        val blurred = Mat()
        Imgproc.GaussianBlur(gray, blurred, Size(3.0, 3.0), 0.0)

        val binary = Mat()
        Imgproc.threshold(
            blurred,
            binary,
            0.0,
            255.0,
            Imgproc.THRESH_BINARY_INV or Imgproc.THRESH_OTSU
        )

        val horizontal = binary.clone()
        val kernelWidth = (src.cols() / 12).coerceAtLeast(25)
        val horizontalKernel = Imgproc.getStructuringElement(
            Imgproc.MORPH_RECT,
            Size(kernelWidth.toDouble(), 1.0)
        )

        Imgproc.morphologyEx(horizontal, horizontal, Imgproc.MORPH_OPEN, horizontalKernel)

        val closeKernelWidth = (src.cols() / 80).coerceAtLeast(9).coerceAtMost(41)
        val closeKernel = Imgproc.getStructuringElement(
            Imgproc.MORPH_RECT,
            Size(closeKernelWidth.toDouble(), 1.0)
        )
        Imgproc.morphologyEx(horizontal, horizontal, Imgproc.MORPH_CLOSE, closeKernel)

        val rowStrength = mutableListOf<Pair<Int, Int>>()
        val rowMetrics = mutableMapOf<Int, RowLineMetrics>()

        for (y in 0 until horizontal.rows()) {
            val metrics = lineMetricsAtRow(horizontal, y)
            rowStrength.add(y to metrics.inkCount)
            rowMetrics[y] = metrics
        }

        val strongestRow = rowStrength.maxOfOrNull { it.second } ?: 0
        val relativeThreshold = (strongestRow * 0.72).roundToInt()
        val absoluteThreshold = (src.cols() * 0.42).roundToInt()
        val threshold = max(relativeThreshold, absoluteThreshold).coerceAtLeast(1)
        val rawRows = rowStrength
            .filter { (_, strength) -> strength >= threshold }
            .filter { (y, _) ->
                val metrics = rowMetrics[y] ?: return@filter false
                metrics.coverage >= 0.42 &&
                    metrics.longestRunRatio >= 0.34 &&
                    metrics.continuityScore >= 0.52 &&
                    metrics.segmentCount <= 18
            }
            .map { it.first }

        val deduped = deduplicateRows(rawRows, rowStrength.toMap())

        val staffs = buildValidatedStaffs(
            lines = deduped,
            rowStrengthByY = rowStrength.toMap(),
            rowMetricsByY = rowMetrics,
            imageWidth = src.cols(),
            symbolDetections = symbolDetections
        )

        val barLines = detectBarLines(
            binary = binary,
            staffs = staffs
        )

        val stems = detectStems(
            binary = binary,
            staffs = staffs,
            symbolDetections = symbolDetections
        )

        val ledgerDetection = detectLedgerLines(
            binary = binary,
            staffs = staffs,
            symbolDetections = symbolDetections,
            stems = stems
        )
        val ledgerLines = ledgerDetection.validatedLedgers

        val beams = detectBeams(
            binary = binary,
            staffs = staffs,
            stems = stems
        )

        val measures = buildMeasures(
            staffs = staffs,
            barLines = barLines,
            imageWidth = src.cols()
        )

        // Draw overlay
        val overlay = src.clone()
        for (staff in staffs) {
            val lines = staff["lines"] as List<Double>

            for (yVal in lines) {
                val y = yVal.toInt()
                Imgproc.line(
                    overlay,
                    Point(0.0, y.toDouble()),
                    Point(overlay.cols().toDouble(), y.toDouble()),
                    Scalar(0.0, 0.0, 255.0),
                    2
                )
            }

            /*
            // Draw detected ledger lines in green
            for (ledger in ledgerLines) {
                val x1 = ledger["x1"] as Int
                val x2 = ledger["x2"] as Int
                val y = (ledger["y"] as Double).toInt()

                Imgproc.line(
                    overlay,
                    Point(x1.toDouble(), y.toDouble()),
                    Point(x2.toDouble(), y.toDouble()),
                    Scalar(0.0, 255.0, 0.0), // green in BGR
                    2
                )
            }

            val spacing = staff["spacing"] as Double

            val virtualColor = Scalar(255.0, 180.0, 0.0) // light blue in BGR

            // Draw 3 virtual lines above
            for (i in 1..3) {
                val y = lines.first() - (spacing * i)

                if (y >= 0 && y < overlay.rows()) {
                    Imgproc.line(
                        overlay,
                        Point(0.0, y),
                        Point(overlay.cols().toDouble(), y),
                        virtualColor,
                        1
                    )
                }
            }

            // Draw 3 virtual lines below
            for (i in 1..3) {
                val y = lines.last() + (spacing * i)

                if (y >= 0 && y < overlay.rows()) {
                    Imgproc.line(
                        overlay,
                        Point(0.0, y),
                        Point(overlay.cols().toDouble(), y),
                        virtualColor,
                        1
                    )
                }
            }
            */
        }

        for (symbol in symbolDetections) {
            drawSymbolOverlay(overlay, symbol)
        }

        for (ledger in ledgerLines) {
            val x1 = ledger["x1"] as Int
            val x2 = ledger["x2"] as Int
            val y = (ledger["y"] as Double).toInt()

            Imgproc.line(
                overlay,
                Point(x1.toDouble(), y.toDouble()),
                Point(x2.toDouble(), y.toDouble()),
                symbolOverlayColor("ledger"),
                2
            )
        }

        for (stem in stems) {
            val x = (stem["x"] as Double).toInt()
            val y1 = (stem["y1"] as Double).toInt()
            val y2 = (stem["y2"] as Double).toInt()

            Imgproc.line(
                overlay,
                Point(x.toDouble(), y1.toDouble()),
                Point(x.toDouble(), y2.toDouble()),
                symbolOverlayColor("stem"),
                2
            )
        }

        for (beam in beams) {
            val x1 = (beam["x1"] as Number).toInt()
            val x2 = (beam["x2"] as Number).toInt()
            val y = (beam["y"] as Double).toInt()

            Imgproc.line(
                overlay,
                Point(x1.toDouble(), y.toDouble()),
                Point(x2.toDouble(), y.toDouble()),
                symbolOverlayColor("beam"),
                3
            )
        }

        for (barLine in barLines) {
            val x = (barLine["x"] as Double).toInt()
            val y1 = (barLine["y1"] as Double).toInt()
            val y2 = (barLine["y2"] as Double).toInt()

            Imgproc.line(
                overlay,
                Point(x.toDouble(), y1.toDouble()),
                Point(x.toDouble(), y2.toDouble()),
                symbolOverlayColor("barline"),
                2
            )
        }

        val staffLines = staffs.flatMap { staff ->
            val staffId = staff["id"] as String
            val topBoundary = staff["topBoundary"] as Double
            val bottomBoundary = staff["bottomBoundary"] as Double
            val spacing = staff["spacing"] as Double
            val confidence = staff["confidence"] as? Double ?: 1.0
            val lines = staff["lines"] as List<Double>

            lines.mapIndexed { index, y ->
                mapOf(
                    "id" to "${staffId}_line_$index",
                    "staffId" to staffId,
                    "y" to y,
                    "topBoundary" to topBoundary,
                    "bottomBoundary" to bottomBoundary,
                    "spacing" to spacing,
                    "confidence" to confidence
                )
            }
        }

        val outputPath = saveImage(context, overlay)

        gray.release()
        blurred.release()
        binary.release()
        horizontal.release()
        horizontalKernel.release()
        closeKernel.release()

        Log.d("STAFF_SEGMENT", "ledger final count=${ledgerLines.size}")
        Log.d("STAFF_SEGMENT", "barline final count=${barLines.size}")
        Log.d("STAFF_SEGMENT", "stem final count=${stems.size}")
        Log.d("STAFF_SEGMENT", "beam final count=${beams.size}")
        Log.d("STAFF_SEGMENT", "measure final count=${measures.size}")

        return mapOf(
            "status" to "success",
            "message" to "Native OpenCV segmentation completed",
            "segmentedImagePath" to outputPath,
            "imageWidth" to src.cols(),
            "imageHeight" to src.rows(),
            "staffLineCount" to staffs.sumOf { (it["lines"] as List<*>).size },
            "staffLines" to staffLines,
            "ledgerLines" to ledgerLines,
            "ledgerDiagnostics" to ledgerDetection.report,
            "barLines" to barLines,
            "stems" to stems,
            "beams" to beams,
            "measures" to measures,
            "validatedStaffs" to staffs
        )
    }

    private fun deduplicateRows(
        rawRows: List<Int>,
        rowStrengthByY: Map<Int, Int>
    ): List<Double> {
        if (rawRows.isEmpty()) return emptyList()

        val groups = mutableListOf<MutableList<Int>>()
        var current = mutableListOf(rawRows.first())

        for (i in 1 until rawRows.size) {
            if (rawRows[i] - rawRows[i - 1] <= 3) {
                current.add(rawRows[i])
            } else {
                groups.add(current)
                current = mutableListOf(rawRows[i])
            }
        }
        groups.add(current)

        return groups.map { group ->
            val totalWeight = group.sumOf { rowStrengthByY[it] ?: 1 }.coerceAtLeast(1)
            group.sumOf { it * (rowStrengthByY[it] ?: 1) }.toDouble() / totalWeight.toDouble()
        }.sorted()
    }

    private fun buildValidatedStaffs(
        lines: List<Double>,
        rowStrengthByY: Map<Int, Int>,
        rowMetricsByY: Map<Int, RowLineMetrics>,
        imageWidth: Int,
        symbolDetections: List<Map<String, Any?>>
    ): List<Map<String, Any>> {
        if (lines.size < 5) return emptyList()

        val candidates = mutableListOf<StaffCandidate>()

        for (topIndex in lines.indices) {
            for (otherIndex in topIndex + 1 until lines.size) {
                val distance = lines[otherIndex] - lines[topIndex]
                if (distance <= 0) continue

                for (stepCount in 1..4) {
                    val spacing = distance / stepCount.toDouble()
                    if (spacing < 6.0 || spacing > 44.0) continue

                    val candidateTemplates = listOf(
                        List(5) { offset -> lines[topIndex] + spacing * offset },
                        List(5) { offset -> lines[topIndex] - spacing + spacing * offset }
                    )

                    for (expected in candidateTemplates) {
                        if (expected.first() < 0.0) continue

                        val matched = expected.map { expectedY ->
                            nearestLine(
                                expectedY = expectedY,
                                lines = lines,
                                tolerance = max(2.75, spacing * 0.30)
                            )
                        }

                        val matchedCount = matched.count { it != null }
                        if (matchedCount < 4) continue

                        val repairedLines = expected.mapIndexed { index, expectedY ->
                            matched[index] ?: expectedY
                        }

                        val uniqueMatched = matched.filterNotNull().distinctBy { it.roundToInt() }
                        if (uniqueMatched.size != matchedCount) continue

                        val spacings = listOf(
                            repairedLines[1] - repairedLines[0],
                            repairedLines[2] - repairedLines[1],
                            repairedLines[3] - repairedLines[2],
                            repairedLines[4] - repairedLines[3]
                        )

                        val avg = spacings.average()
                        if (avg < 6.0 || avg > 44.0) continue

                        val maxDeviation = spacings.maxOf { abs(it - avg) }
                        val spacingConsistency =
                            1.0 - (maxDeviation / (avg * 0.45)).coerceIn(0.0, 1.0)
                        if (spacingConsistency < 0.72) continue

                        val projectionStrength = repairedLines.map { lineY ->
                            strengthNearLine(lineY, rowStrengthByY).toDouble() /
                                imageWidth.toDouble()
                        }.average().coerceIn(0.0, 1.0)

                        if (projectionStrength < 0.46) continue

                        val continuity = repairedLines.map { lineY ->
                            metricsNearLine(lineY, rowMetricsByY).continuityScore
                        }.average().coerceIn(0.0, 1.0)

                        val horizontalCoverage = repairedLines.map { lineY ->
                            metricsNearLine(lineY, rowMetricsByY).coverage
                        }.average().coerceIn(0.0, 1.0)

                        val runSupport = repairedLines.map { lineY ->
                            metricsNearLine(lineY, rowMetricsByY).longestRunRatio
                        }.average().coerceIn(0.0, 1.0)

                        if (continuity < 0.52 || horizontalCoverage < 0.42 || runSupport < 0.34) {
                            continue
                        }

                        val symbolSupport = symbolSupportForStaff(
                            lines = repairedLines,
                            spacing = avg,
                            symbolDetections = symbolDetections
                        )

                        if (
                            symbolDetections.isNotEmpty() &&
                            symbolSupport <= 0.0 &&
                            projectionStrength < 0.72
                        ) {
                            continue
                        }

                        if (
                            matchedCount == 4 &&
                            (spacingConsistency < 0.86 ||
                                projectionStrength < 0.58 ||
                                continuity < 0.64)
                        ) {
                            continue
                        }

                        val repairPenalty = if (matchedCount == 5) 1.0 else 0.88
                        val confidence = (
                            spacingConsistency * 0.34 +
                                projectionStrength * 0.28 +
                                continuity * 0.14 +
                                runSupport * 0.08 +
                                symbolSupport * 0.10 +
                                repairPenalty * 0.06
                            ).coerceIn(0.0, 1.0)

                        if (confidence < 0.58) continue

                        candidates.add(
                            StaffCandidate(
                                lines = repairedLines,
                                spacing = avg,
                                confidence = confidence,
                                matchedLineCount = matchedCount,
                                projectionStrength = projectionStrength,
                                symbolSupport = symbolSupport,
                                continuity = continuity
                            )
                        )
                    }
                }
            }
        }

        return candidates
            .sortedWith(
                compareByDescending<StaffCandidate> { it.matchedLineCount }
                    .thenByDescending { it.confidence }
                    .thenByDescending { it.projectionStrength }
                    .thenByDescending { it.continuity }
                    .thenBy { it.lines.first() }
                    .thenBy { it.spacing }
            )
            .fold(mutableListOf<StaffCandidate>()) { kept, candidate ->
                val overlaps = kept.any { existing ->
                    val closeTop = abs(existing.lines.first() - candidate.lines.first()) <=
                        min(existing.spacing, candidate.spacing) * 1.5
                    val closeCenter = abs(existing.lines.average() - candidate.lines.average()) <=
                        min(existing.spacing, candidate.spacing) * 2.0
                    closeTop || closeCenter
                }
                if (!overlaps) kept.add(candidate)
                kept
            }
            .sortedWith(
                compareBy<StaffCandidate> { it.lines.first() }
                    .thenBy { it.spacing }
                    .thenByDescending { it.confidence }
            )
            .mapIndexed { index, candidate ->
                mapOf(
                    "id" to "staff_$index",
                    "lines" to candidate.lines,
                    "spacing" to candidate.spacing,
                    "validatedStaffSpacing" to candidate.spacing,
                    "locked" to true,
                    "coordinateSpace" to "original_image",
                    "topBoundary" to candidate.lines.first() - candidate.spacing * 1.2,
                    "bottomBoundary" to candidate.lines.last() + candidate.spacing * 1.2,
                    "confidence" to candidate.confidence,
                    "matchedLineCount" to candidate.matchedLineCount,
                    "repairedLineCount" to 5 - candidate.matchedLineCount,
                    "projectionStrength" to candidate.projectionStrength,
                    "continuity" to candidate.continuity,
                    "symbolSupport" to candidate.symbolSupport
                )
            }
    }

    private data class StaffCandidate(
        val lines: List<Double>,
        val spacing: Double,
        val confidence: Double,
        val matchedLineCount: Int,
        val projectionStrength: Double,
        val symbolSupport: Double,
        val continuity: Double
    )

    private data class RowLineMetrics(
        val inkCount: Int,
        val coverage: Double,
        val longestRunRatio: Double,
        val continuityScore: Double,
        val segmentCount: Int
    )

    private fun lineMetricsAtRow(mat: Mat, y: Int): RowLineMetrics {
        var inkCount = 0
        var segmentCount = 0
        var longestRun = 0
        var currentRun = 0
        var inSegment = false

        for (x in 0 until mat.cols()) {
            val isInk = mat.get(y, x)[0] > 0
            if (isInk) {
                inkCount++
                currentRun++
                if (!inSegment) {
                    segmentCount++
                    inSegment = true
                }
            } else {
                longestRun = max(longestRun, currentRun)
                currentRun = 0
                inSegment = false
            }
        }
        longestRun = max(longestRun, currentRun)

        val width = mat.cols().coerceAtLeast(1).toDouble()
        val coverage = inkCount.toDouble() / width
        val longestRunRatio = longestRun.toDouble() / width
        val fragmentationPenalty = ((segmentCount - 1).coerceAtLeast(0).toDouble() / 18.0)
            .coerceIn(0.0, 1.0)
        val continuityScore = (longestRunRatio * 0.70 + coverage * 0.30 - fragmentationPenalty * 0.30)
            .coerceIn(0.0, 1.0)

        return RowLineMetrics(
            inkCount = inkCount,
            coverage = coverage,
            longestRunRatio = longestRunRatio,
            continuityScore = continuityScore,
            segmentCount = segmentCount
        )
    }

    private fun nearestLine(
        expectedY: Double,
        lines: List<Double>,
        tolerance: Double
    ): Double? {
        return lines
            .minByOrNull { abs(it - expectedY) }
            ?.takeIf { abs(it - expectedY) <= tolerance }
    }

    private fun strengthNearLine(
        lineY: Double,
        rowStrengthByY: Map<Int, Int>
    ): Int {
        val center = lineY.roundToInt()
        var best = 0
        for (y in center - 1..center + 1) {
            best = max(best, rowStrengthByY[y] ?: 0)
        }
        return best
    }

    private fun metricsNearLine(
        lineY: Double,
        rowMetricsByY: Map<Int, RowLineMetrics>
    ): RowLineMetrics {
        val center = lineY.roundToInt()
        var best = rowMetricsByY[center] ?: RowLineMetrics(0, 0.0, 0.0, 0.0, 0)
        for (y in center - 1..center + 1) {
            val metrics = rowMetricsByY[y] ?: continue
            if (metrics.continuityScore > best.continuityScore) {
                best = metrics
            }
        }
        return best
    }

    private fun symbolSupportForStaff(
        lines: List<Double>,
        spacing: Double,
        symbolDetections: List<Map<String, Any?>>
    ): Double {
        if (symbolDetections.isEmpty()) return 0.0

        val top = lines.first() - spacing * 3.0
        val bottom = lines.last() + spacing * 3.0
        var support = 0.0

        for (symbol in symbolDetections) {
            val className = symbolClassName(symbol)
            if (className !in setOf("notehead", "treble_clef", "bass_clef", "sharp", "flat", "natural")) {
                continue
            }

            val centerY = symbolCenterY(symbol) ?: continue
            if (centerY < top || centerY > bottom) continue

            support += when (className) {
                "treble_clef", "bass_clef" -> 0.28
                "notehead" -> 0.08
                else -> 0.05
            }
        }

        return support.coerceIn(0.0, 1.0)
    }

    private fun symbolClassName(symbol: Map<String, Any?>): String {
        return (
            symbol["className"] ?: symbol["labelName"] ?: symbol["label"] ?: ""
            ).toString().trim().lowercase()
    }

    private fun symbolCenterY(symbol: Map<String, Any?>): Double? {
        val direct = toDouble(symbol["centerY"] ?: symbol["y"])
        if (direct != null) return direct

        val bbox = symbol["bbox"] as? List<*> ?: return null
        if (bbox.size < 4) return null
        val y1 = toDouble(bbox[1]) ?: return null
        val y2 = toDouble(bbox[3]) ?: return null
        return (y1 + y2) / 2.0
    }

    private fun toDouble(value: Any?): Double? {
        return when (value) {
            null -> null
            is Number -> value.toDouble()
            else -> value.toString().toDoubleOrNull()
        }
    }

    private fun drawSymbolOverlay(overlay: Mat, symbol: Map<String, Any?>) {
        val box = symbolBox(symbol) ?: return
        val state = symbolState(symbol)
        Imgproc.rectangle(
            overlay,
            Point(box.x1, box.y1),
            Point(box.x2, box.y2),
            symbolOverlayColor(box.className, state),
            2
        )
    }

    private fun symbolOverlayColor(
        className: String,
        state: SymbolState = SymbolState.DETECTED
    ): Scalar {
        return when (state) {
            SymbolState.INFERRED -> Scalar(0.0, 255.0, 180.0)
            SymbolState.REJECTED -> Scalar(0.0, 0.0, 139.0)
            SymbolState.DETECTED -> classOverlayColor(className)
        }
    }

    private fun classOverlayColor(className: String): Scalar {
        return when (className.trim().lowercase()) {
            "notehead" -> Scalar(255.0, 255.0, 0.0)
            "treble_clef" -> Scalar(0.0, 255.0, 0.0)
            "bass_clef" -> Scalar(0.0, 120.0, 0.0)
            "sharp" -> Scalar(0.0, 165.0, 255.0)
            "flat" -> Scalar(0.0, 255.0, 255.0)
            "natural" -> Scalar(255.0, 0.0, 180.0)
            "rest" -> Scalar(203.0, 192.0, 255.0)
            "barline" -> Scalar(255.0, 255.0, 255.0)
            "stem" -> Scalar(128.0, 128.0, 0.0)
            "beam" -> Scalar(255.0, 200.0, 80.0)
            "ledger" -> Scalar(0.0, 70.0, 255.0)
            "invalid", "rejected" -> Scalar(0.0, 0.0, 139.0)
            else -> Scalar(0.0, 0.0, 255.0)
        }
    }

    private fun symbolState(symbol: Map<String, Any?>): SymbolState {
        return when (symbol["symbolState"]?.toString()?.trim()?.lowercase()) {
            "inferred" -> SymbolState.INFERRED
            "rejected" -> SymbolState.REJECTED
            else -> SymbolState.DETECTED
        }
    }

    private data class SymbolBox(
        val className: String,
        val centerX: Double,
        val centerY: Double,
        val x1: Double,
        val y1: Double,
        val x2: Double,
        val y2: Double
    )

    private data class LedgerDetectionResult(
        val validatedLedgers: List<Map<String, Any>>,
        val report: Map<String, Any>
    )

    private fun noteheadSymbols(symbolDetections: List<Map<String, Any?>>): List<SymbolBox> {
        val boxes = symbolDetections.mapNotNull { symbolBox(it) }
        val clefs = boxes.filter { it.className == "treble_clef" || it.className == "bass_clef" }

        return boxes.filter { box ->
            box.className == "notehead" &&
                clefs.none { clef -> centerInside(box, clef) || iou(box, clef) >= 0.12 }
        }
    }

    private fun symbolBox(symbol: Map<String, Any?>): SymbolBox? {
        val className = symbolClassName(symbol)
        val bbox = symbol["bbox"] as? List<*>
        if (bbox != null && bbox.size >= 4) {
            val x1 = toDouble(bbox[0]) ?: return null
            val y1 = toDouble(bbox[1]) ?: return null
            val x2 = toDouble(bbox[2]) ?: return null
            val y2 = toDouble(bbox[3]) ?: return null
            return SymbolBox(
                className = className,
                centerX = (x1 + x2) / 2.0,
                centerY = (y1 + y2) / 2.0,
                x1 = min(x1, x2),
                y1 = min(y1, y2),
                x2 = max(x1, x2),
                y2 = max(y1, y2)
            )
        }

        val centerX = toDouble(symbol["centerX"] ?: symbol["x"]) ?: return null
        val centerY = toDouble(symbol["centerY"] ?: symbol["y"]) ?: return null
        return SymbolBox(
            className = className,
            centerX = centerX,
            centerY = centerY,
            x1 = centerX,
            y1 = centerY,
            x2 = centerX,
            y2 = centerY
        )
    }

    private fun centerInside(inner: SymbolBox, outer: SymbolBox): Boolean {
        return inner.centerX >= outer.x1 &&
            inner.centerX <= outer.x2 &&
            inner.centerY >= outer.y1 &&
            inner.centerY <= outer.y2
    }

    private fun iou(a: SymbolBox, b: SymbolBox): Double {
        val left = max(a.x1, b.x1)
        val top = max(a.y1, b.y1)
        val right = min(a.x2, b.x2)
        val bottom = min(a.y2, b.y2)
        val intersection = max(0.0, right - left) * max(0.0, bottom - top)
        if (intersection <= 0.0) return 0.0
        val areaA = max(0.0, a.x2 - a.x1) * max(0.0, a.y2 - a.y1)
        val areaB = max(0.0, b.x2 - b.x1) * max(0.0, b.y2 - b.y1)
        val union = areaA + areaB - intersection
        if (union <= 0.0) return 0.0
        return intersection / union
    }

    private fun noteheadOutsideStaff(
        notehead: SymbolBox,
        topLine: Double,
        bottomLine: Double,
        spacing: Double
    ): Boolean {
        return notehead.centerY < topLine - spacing * 0.35 ||
            notehead.centerY > bottomLine + spacing * 0.35
    }

    private fun noteheadConnectedToStem(
        notehead: SymbolBox,
        x: Double,
        y1: Double,
        y2: Double,
        spacing: Double
    ): Boolean {
        val horizontalTolerance = max(4.0, spacing * 0.85)
        val endpointTolerance = max(5.0, spacing * 0.95)
        val nearStemX = x >= notehead.x1 - horizontalTolerance &&
            x <= notehead.x2 + horizontalTolerance
        if (!nearStemX) return false

        val overlapsBody = y2 >= notehead.y1 - endpointTolerance &&
            y1 <= notehead.y2 + endpointTolerance
        if (!overlapsBody) return false

        val touchesUpperEndpoint = abs(notehead.centerY - y1) <= endpointTolerance ||
            abs(notehead.y1 - y1) <= endpointTolerance ||
            abs(notehead.y2 - y1) <= endpointTolerance
        val touchesLowerEndpoint = abs(notehead.centerY - y2) <= endpointTolerance ||
            abs(notehead.y1 - y2) <= endpointTolerance ||
            abs(notehead.y2 - y2) <= endpointTolerance

        return touchesUpperEndpoint || touchesLowerEndpoint || notehead.centerY in y1..y2
    }

    private fun stemConnectsToBeam(
        stem: Map<String, Any>,
        beamX1: Double,
        beamX2: Double,
        beamY: Double,
        spacing: Double
    ): Boolean {
        val stemX = stem["x"] as? Double ?: return false
        val stemY1 = stem["y1"] as? Double ?: return false
        val stemY2 = stem["y2"] as? Double ?: return false
        val xTolerance = max(3.0, spacing * 0.45)
        val yTolerance = max(4.0, spacing * 0.65)

        val xClose = stemX >= beamX1 - xTolerance && stemX <= beamX2 + xTolerance
        if (!xClose) return false

        val connectsTop = abs(stemY1 - beamY) <= yTolerance
        val connectsBottom = abs(stemY2 - beamY) <= yTolerance
        return connectsTop || connectsBottom
    }

    private fun detectLedgerLines(
        binary: Mat,
        staffs: List<Map<String, Any>>,
        symbolDetections: List<Map<String, Any?>>,
        stems: List<Map<String, Any>>
    ): LedgerDetectionResult {
        val ledgerLines = mutableListOf<Map<String, Any>>()
        var rawCandidates = 0
        val rejectionReasons = mutableMapOf<String, Int>()
        var ledgerIndex = 0
        val noteheads = noteheadSymbols(symbolDetections)

        fun reject(reason: String) {
            rejectionReasons[reason] = (rejectionReasons[reason] ?: 0) + 1
        }

        for (staff in staffs) {
            val staffId = staff["id"] as String
            val lines = staff["lines"] as List<Double>
            val spacing = staff["spacing"] as Double

            val topLine = lines.first()
            val bottomLine = lines.last()

            val ledgerSearchSteps = 6.25

            val searchTop = (topLine - spacing * ledgerSearchSteps).toInt().coerceAtLeast(0)
            val searchBottom = (bottomLine + spacing * ledgerSearchSteps).toInt()
                .coerceAtMost(binary.rows() - 1)

            for (y in searchTop..searchBottom) {
                val isInsideMainStaff = y >= topLine && y <= bottomLine
                if (isInsideMainStaff) continue

                val segments = findHorizontalSegmentsAtRow(binary, y)

                val nearestVirtualLineY = nearestLedgerVirtualLineY(
                    y = y.toDouble(),
                    topLine = topLine,
                    bottomLine = bottomLine,
                    spacing = spacing
                )

                if (nearestVirtualLineY == null) continue

                if (kotlin.math.abs(y.toDouble() - nearestVirtualLineY) > spacing * 0.30) {
                    continue
                }

                for (segment in segments) {
                    rawCandidates++
                    val x1 = segment.first
                    val x2 = segment.second
                    val width = x2 - x1
                    val continuitySupport = ledgerContinuitySupport(
                        existingLedgers = ledgerLines,
                        staffId = staffId,
                        x1 = x1,
                        x2 = x2,
                        y = y.toDouble(),
                        spacing = spacing
                    )

                    val minWidth = spacing * (if (continuitySupport > 0.0) 1.52 else 1.65)
                    val maxWidth = spacing * (if (continuitySupport > 0.0) 3.82 else 3.65)

                    if (width < minWidth) {
                        reject("too short")
                        continue
                    }
                    if (width > maxWidth) {
                        reject("invalid geometry")
                        continue
                    }

                    val thickness = horizontalSegmentThickness(
                        binary = binary,
                        x1 = x1,
                        x2 = x2,
                        y = y
                    )
                    if (thickness < 1 || thickness > max(3.0, spacing * 0.34).roundToInt()) {
                        reject("inconsistent thickness")
                        continue
                    }

                    val fragmentCount = neighboringHorizontalFragments(
                        binary = binary,
                        x1 = x1,
                        x2 = x2,
                        y = y,
                        spacing = spacing
                    )
                    if (fragmentCount >= 4) {
                        reject("text-like fragment")
                        continue
                    }

                    val supportingNotehead = noteheads.firstOrNull { notehead ->
                        noteheadOutsideStaff(
                            notehead = notehead,
                            topLine = topLine,
                            bottomLine = bottomLine,
                            spacing = spacing
                        ) &&
                            abs(notehead.centerY - y.toDouble()) <= spacing * 0.55 &&
                            notehead.centerX >= x1 - spacing * 1.2 &&
                            notehead.centerX <= x2 + spacing * 1.2
                    }

                    val supportingStem = if (supportingNotehead == null) {
                        stems.firstOrNull { stem ->
                            val stemStaffId = stem["staffId"]?.toString()
                            val stemX = stem["x"] as? Double ?: return@firstOrNull false
                            val stemY1 = stem["y1"] as? Double ?: return@firstOrNull false
                            val stemY2 = stem["y2"] as? Double ?: return@firstOrNull false
                            val stemCenterY = (stemY1 + stemY2) / 2.0
                            stemStaffId == staffId &&
                                stemX >= x1 - spacing * 1.05 &&
                                stemX <= x2 + spacing * 1.05 &&
                                abs(stemCenterY - y.toDouble()) <= spacing * 3.2 &&
                                (stemY1 <= y + spacing * 2.7 && stemY2 >= y - spacing * 2.7)
                        }
                    } else {
                        null
                    }

                    if (supportingNotehead == null && supportingStem == null) {
                        reject("no note support")
                        continue
                    }

                    if (supportingNotehead == null && supportingStem != null) {
                        val stemHeight = abs(
                            (supportingStem["y2"] as? Double ?: 0.0) -
                                (supportingStem["y1"] as? Double ?: 0.0)
                        )
                        if (stemHeight < spacing * 2.2) {
                            reject("isolated")
                            continue
                        }
                    }

                    val virtualLinePenalty =
                        (kotlin.math.abs(y.toDouble() - nearestVirtualLineY) / spacing) * 0.18
                    val score = 0.34 +
                        (if (supportingNotehead != null) 0.34 else 0.0) +
                        (if (supportingStem != null) 0.18 else 0.0) +
                        continuitySupport +
                        (if (fragmentCount == 0) 0.08 else -0.08) -
                        virtualLinePenalty

                    val requiredScore = if (continuitySupport > 0.0) 0.52 else 0.56
                    if (score < requiredScore) {
                        reject("isolated")
                        continue
                    }

                    val position = if (y < topLine) "above" else "below"

                    val ledger = mutableMapOf<String, Any>(
                        "id" to "ledger_${ledgerIndex++}",
                        "staffId" to staffId,
                        "x1" to x1,
                        "x2" to x2,
                        "y" to y.toDouble(),
                        "position" to position,
                        "state" to "validated",
                        "confidence" to score.coerceIn(0.0, 1.0),
                        "validationReason" to if (supportingNotehead == null) {
                            "ledger validated with stem-supported inferred note structure"
                        } else if (continuitySupport > 0.0) {
                            "ledger validated with nearby notehead and ledger continuity"
                        } else {
                            "ledger validated with nearby notehead"
                        }
                    )
                    if (supportingNotehead != null) {
                        ledger["noteheadX"] = supportingNotehead.centerX
                        ledger["noteheadY"] = supportingNotehead.centerY
                    }
                    if (supportingStem != null) {
                        ledger["stemX"] = supportingStem["x"] as Double
                    }
                    ledgerLines.add(ledger)
                }
            }
        }
        Log.d("STAFF_SEGMENT", "ledger raw count=$rawCandidates")

        val deduped = deduplicateLedgerLines(ledgerLines)
        val report = mapOf(
            "rawCandidates" to rawCandidates,
            "validatedLedgers" to deduped.size,
            "rejectedFragments" to rejectionReasons.values.sum(),
            "rejectionReasons" to rejectionReasons.toMap()
        )

        return LedgerDetectionResult(
            validatedLedgers = deduped,
            report = report
        )
    }

    private fun ledgerContinuitySupport(
        existingLedgers: List<Map<String, Any>>,
        staffId: String,
        x1: Int,
        x2: Int,
        y: Double,
        spacing: Double
    ): Double {
        if (existingLedgers.isEmpty() || spacing <= 0.0) return 0.0

        val centerX = (x1 + x2) / 2.0
        val width = (x2 - x1).coerceAtLeast(1)
        val hasNeighbor = existingLedgers.any { ledger ->
            if (ledger["staffId"].toString() != staffId) return@any false
            val otherX1 = ledger["x1"] as? Int ?: return@any false
            val otherX2 = ledger["x2"] as? Int ?: return@any false
            val otherY = ledger["y"] as? Double ?: return@any false
            val otherCenterX = (otherX1 + otherX2) / 2.0
            val xAligned = abs(otherCenterX - centerX) <= spacing * 1.45
            val widthSimilar = abs((otherX2 - otherX1) - width) <= spacing * 1.25
            val dy = abs(otherY - y)
            val yStepAligned = (1..3).any { step ->
                abs(dy - spacing * step) <= spacing * 0.34
            }
            xAligned && widthSimilar && yStepAligned
        }

        return if (hasNeighbor) 0.05 else 0.0
    }

    private fun findHorizontalSegmentsAtRow(
        mat: Mat,
        y: Int
    ): List<Pair<Int, Int>> {
        val segments = mutableListOf<Pair<Int, Int>>()

        var inSegment = false
        var startX = 0

        for (x in 0 until mat.cols()) {
            val isWhite = mat.get(y, x)[0] > 0

            if (isWhite && !inSegment) {
                inSegment = true
                startX = x
            }

            if ((!isWhite || x == mat.cols() - 1) && inSegment) {
                val endX = if (isWhite) x else x - 1
                segments.add(startX to endX)
                inSegment = false
            }
        }

        return segments
    }

    private fun horizontalSegmentThickness(
        binary: Mat,
        x1: Int,
        x2: Int,
        y: Int
    ): Int {
        var top = y
        var bottom = y
        val centerX = ((x1 + x2) / 2.0).roundToInt().coerceIn(0, binary.cols() - 1)

        while (top - 1 >= 0 && binary.get(top - 1, centerX)[0] > 0) {
            top--
        }
        while (bottom + 1 < binary.rows() && binary.get(bottom + 1, centerX)[0] > 0) {
            bottom++
        }

        return bottom - top + 1
    }

    private fun neighboringHorizontalFragments(
        binary: Mat,
        x1: Int,
        x2: Int,
        y: Int,
        spacing: Double
    ): Int {
        val margin = (spacing * 4.0).roundToInt().coerceAtLeast(18)
        val left = (x1 - margin).coerceAtLeast(0)
        val right = (x2 + margin).coerceAtMost(binary.cols() - 1)
        val top = (y - spacing.roundToInt()).coerceAtLeast(0)
        val bottom = (y + spacing.roundToInt()).coerceAtMost(binary.rows() - 1)
        var fragments = 0
        val minTextStroke = max(2.0, spacing * 0.28).roundToInt()
        val maxTextStroke = max(5.0, spacing * 1.15).roundToInt()

        for (row in top..bottom) {
            for (segment in findHorizontalSegmentsAtRow(binary, row)) {
                if (segment.second < left || segment.first > right) continue
                if (abs(row - y) <= 1 &&
                    abs(segment.first - x1) <= 2 &&
                    abs(segment.second - x2) <= 2
                ) {
                    continue
                }

                val width = segment.second - segment.first
                if (width in minTextStroke..maxTextStroke) {
                    fragments++
                    if (fragments >= 4) return fragments
                }
            }
        }

        return fragments
    }

    private fun nearestLedgerVirtualLineY(
        y: Double,
        topLine: Double,
        bottomLine: Double,
        spacing: Double
    ): Double? {
        val virtualYs = mutableListOf<Double>()

        for (i in 1..6) {
            virtualYs.add(topLine - spacing * i)
            virtualYs.add(bottomLine + spacing * i)
        }

        return virtualYs.minByOrNull { kotlin.math.abs(it - y) }
    }

    private fun deduplicateLedgerLines(
        raw: List<Map<String, Any>>
    ): List<Map<String, Any>> {
        if (raw.isEmpty()) return emptyList()

        val sorted = raw.sortedWith(
            compareBy<Map<String, Any>> {
                it["staffId"].toString()
            }.thenBy {
                (it["y"] as Double)
            }.thenBy {
                it["x1"] as Int
            }
        )

        val result = mutableListOf<Map<String, Any>>()

        for (item in sorted) {
            val y = item["y"] as Double
            val x1 = item["x1"] as Int
            val x2 = item["x2"] as Int
            val staffId = item["staffId"].toString()

            val duplicate = result.any { existing ->
                val ey = existing["y"] as Double
                val ex1 = existing["x1"] as Int
                val ex2 = existing["x2"] as Int
                val estaffId = existing["staffId"].toString()

                estaffId == staffId &&
                        kotlin.math.abs(ey - y) <= 2.0 &&
                        kotlin.math.abs(ex1 - x1) <= 6 &&
                        kotlin.math.abs(ex2 - x2) <= 6
            }

            if (!duplicate) {
                result.add(item)
            }
        }

        return result
    }

    private fun detectBarLines(
        binary: Mat,
        staffs: List<Map<String, Any>>
    ): List<Map<String, Any>> {
        if (staffs.isEmpty()) return emptyList()

        val medianSpacing = staffs
            .mapNotNull { it["spacing"] as? Double }
            .sorted()
            .let { values ->
                if (values.isEmpty()) 12.0 else values[values.size / 2]
            }

        val kernelHeight = (medianSpacing * 3.4).roundToInt()
            .coerceAtLeast(12)
            .coerceAtMost(binary.rows().coerceAtLeast(12))

        val vertical = binary.clone()
        val verticalKernel = Imgproc.getStructuringElement(
            Imgproc.MORPH_RECT,
            Size(1.0, kernelHeight.toDouble())
        )

        Imgproc.erode(vertical, vertical, verticalKernel)
        Imgproc.dilate(vertical, vertical, verticalKernel)

        val raw = mutableListOf<Map<String, Any>>()
        var index = 0

        for (staff in staffs) {
            val staffId = staff["id"] as String
            val lines = staff["lines"] as List<Double>
            val spacing = staff["spacing"] as Double

            val y1 = (lines.first() - spacing * 0.45).roundToInt()
                .coerceAtLeast(0)
            val y2 = (lines.last() + spacing * 0.45).roundToInt()
                .coerceAtMost(binary.rows() - 1)

            if (y2 <= y1) continue

            val staffHeight = y2 - y1 + 1
            val minCoverage = (staffHeight * 0.70).roundToInt()
            val rawXs = mutableListOf<Int>()

            for (x in 0 until vertical.cols()) {
                var count = 0

                for (y in y1..y2) {
                    if (vertical.get(y, x)[0] > 0) count++
                }

                if (count >= minCoverage) {
                    rawXs.add(x)
                }
            }

            val xGroups = deduplicateColumns(rawXs)

            for (group in xGroups) {
                val width = group.last() - group.first() + 1
                if (width > spacing * 1.4) continue

                val xCenter = group.average()

                raw.add(
                    mapOf(
                        "id" to "bar_${index++}",
                        "staffId" to staffId,
                        "x" to xCenter,
                        "x1" to group.first(),
                        "x2" to group.last(),
                        "y1" to y1.toDouble(),
                        "y2" to y2.toDouble(),
                        "type" to "single"
                    )
                )
            }
        }

        vertical.release()

        return filterGrandStaffBarLines(
            staffs = staffs,
            barLines = deduplicateBarLines(raw)
        )
    }

    private fun detectStems(
        binary: Mat,
        staffs: List<Map<String, Any>>,
        symbolDetections: List<Map<String, Any?>>
    ): List<Map<String, Any>> {
        if (staffs.isEmpty()) return emptyList()

        val stems = mutableListOf<Map<String, Any>>()
        var index = 0
        val noteheads = noteheadSymbols(symbolDetections)

        for (staff in staffs) {
            val staffId = staff["id"] as String
            val lines = staff["lines"] as List<Double>
            val spacing = staff["spacing"] as Double

            val y1 = (lines.first() - spacing * 4.0).roundToInt()
                .coerceAtLeast(0)
            val y2 = (lines.last() + spacing * 4.0).roundToInt()
                .coerceAtMost(binary.rows() - 1)

            if (y2 <= y1) continue

            val minHeight = (spacing * 2.2).roundToInt().coerceAtLeast(14)
            val maxHeight = (spacing * 7.0).roundToInt().coerceAtLeast(minHeight)

            for (x in 0 until binary.cols()) {
                var inSegment = false
                var startY = y1

                for (y in y1..y2) {
                    val isWhite = binary.get(y, x)[0] > 0

                    if (isWhite && !inSegment) {
                        inSegment = true
                        startY = y
                    }

                    if ((!isWhite || y == y2) && inSegment) {
                        val endY = if (isWhite) y else y - 1
                        val height = endY - startY + 1
                        inSegment = false

                        if (height < minHeight || height > maxHeight) continue

                        val supportingNotehead = noteheads.firstOrNull { notehead ->
                            noteheadConnectedToStem(
                                notehead = notehead,
                                x = x.toDouble(),
                                y1 = startY.toDouble(),
                                y2 = endY.toDouble(),
                                spacing = spacing
                            )
                        } ?: continue

                        stems.add(
                            mapOf(
                                "id" to "stem_${index++}",
                                "staffId" to staffId,
                                "x" to x.toDouble(),
                                "y1" to startY.toDouble(),
                                "y2" to endY.toDouble(),
                                "height" to height.toDouble(),
                                "state" to "detected",
                                "confidence" to 0.70,
                                "noteheadX" to supportingNotehead.centerX,
                                "noteheadY" to supportingNotehead.centerY
                            )
                        )
                    }
                }
            }
        }

        return deduplicateStems(stems)
    }

    private fun detectBeams(
        binary: Mat,
        staffs: List<Map<String, Any>>,
        stems: List<Map<String, Any>>
    ): List<Map<String, Any>> {
        if (staffs.isEmpty()) return emptyList()

        val beams = mutableListOf<Map<String, Any>>()
        var index = 0

        for (staff in staffs) {
            val staffId = staff["id"] as String
            val lines = staff["lines"] as List<Double>
            val spacing = staff["spacing"] as Double

            val y1 = (lines.first() - spacing * 4.0).roundToInt()
                .coerceAtLeast(0)
            val y2 = (lines.last() + spacing * 4.0).roundToInt()
                .coerceAtMost(binary.rows() - 1)

            if (y2 <= y1) continue

            val minWidth = (spacing * 2.4).roundToInt().coerceAtLeast(18)
            val maxWidth = (spacing * 14.0).roundToInt().coerceAtLeast(minWidth)

            for (y in y1..y2) {
                val segments = findHorizontalSegmentsAtRow(binary, y)

                for (segment in segments) {
                    val width = segment.second - segment.first + 1
                    if (width < minWidth || width > maxWidth) continue

                    val isStaffLine = lines.any { kotlin.math.abs(it - y.toDouble()) <= spacing * 0.22 }
                    if (isStaffLine) continue

                    val connectedStems = stems.filter { stem ->
                        stem["staffId"].toString() == staffId &&
                            stemConnectsToBeam(
                                stem = stem,
                                beamX1 = segment.first.toDouble(),
                                beamX2 = segment.second.toDouble(),
                                beamY = y.toDouble(),
                                spacing = spacing
                            )
                    }
                    if (connectedStems.size < 2) continue

                    beams.add(
                        mapOf(
                            "id" to "beam_${index++}",
                            "staffId" to staffId,
                            "x1" to segment.first,
                            "x2" to segment.second,
                            "y" to y.toDouble(),
                            "width" to width.toDouble(),
                            "state" to "detected",
                            "confidence" to 0.72,
                            "connectedStemCount" to connectedStems.size
                        )
                    )
                }
            }
        }

        return deduplicateBeams(beams)
    }

    private fun deduplicateColumns(rawXs: List<Int>): List<List<Int>> {
        if (rawXs.isEmpty()) return emptyList()

        val groups = mutableListOf<MutableList<Int>>()
        var current = mutableListOf(rawXs.first())

        for (i in 1 until rawXs.size) {
            if (rawXs[i] - rawXs[i - 1] <= 2) {
                current.add(rawXs[i])
            } else {
                groups.add(current)
                current = mutableListOf(rawXs[i])
            }
        }
        groups.add(current)

        return groups
    }

    private fun deduplicateBarLines(
        raw: List<Map<String, Any>>
    ): List<Map<String, Any>> {
        if (raw.isEmpty()) return emptyList()

        val sorted = raw.sortedWith(
            compareBy<Map<String, Any>> {
                it["staffId"].toString()
            }.thenBy {
                it["x"] as Double
            }
        )

        val result = mutableListOf<Map<String, Any>>()

        for (item in sorted) {
            val staffId = item["staffId"].toString()
            val x = item["x"] as Double

            val duplicate = result.any { existing ->
                existing["staffId"].toString() == staffId &&
                        kotlin.math.abs((existing["x"] as Double) - x) <= 4.0
            }

            if (!duplicate) {
                result.add(item)
            }
        }

        return result.mapIndexed { index, item ->
            item + ("id" to "bar_$index")
        }
    }

    private fun filterGrandStaffBarLines(
        staffs: List<Map<String, Any>>,
        barLines: List<Map<String, Any>>
    ): List<Map<String, Any>> {
        if (staffs.size < 2 || barLines.isEmpty()) return barLines

        val sortedStaffIds = staffs
            .sortedBy { ((it["lines"] as List<Double>).first()) }
            .map { it["id"].toString() }

        val result = mutableListOf<Map<String, Any>>()

        for (barLine in barLines) {
            val staffId = barLine["staffId"].toString()
            val staffIndex = sortedStaffIds.indexOf(staffId)
            if (staffIndex < 0) continue

            val x = barLine["x"] as Double
            val aligned = barLines.any { other ->
                val otherStaffId = other["staffId"].toString()
                val otherStaffIndex = sortedStaffIds.indexOf(otherStaffId)
                otherStaffIndex >= 0 &&
                        kotlin.math.abs(otherStaffIndex - staffIndex) == 1 &&
                        kotlin.math.abs((other["x"] as Double) - x) <= 6.0
            }

            if (aligned) {
                result.add(barLine)
            }
        }

        return result
    }

    private fun deduplicateStems(
        raw: List<Map<String, Any>>
    ): List<Map<String, Any>> {
        if (raw.isEmpty()) return emptyList()

        val sorted = raw.sortedWith(
            compareBy<Map<String, Any>> { it["staffId"].toString() }
                .thenBy { it["x"] as Double }
                .thenBy { it["y1"] as Double }
        )

        val groups = mutableListOf<MutableList<Map<String, Any>>>()

        for (item in sorted) {
            val group = groups.firstOrNull { existingGroup ->
                existingGroup.any { existing -> stemsOverlapForNms(existing, item) }
            }

            if (group == null) {
                groups.add(mutableListOf(item))
            } else {
                group.add(item)
            }
        }

        return groups.mapIndexed { index, group ->
            val best = group.maxWithOrNull(
                compareBy<Map<String, Any>> { (it["confidence"] as? Number)?.toDouble() ?: 0.0 }
                    .thenBy { (it["height"] as? Number)?.toDouble() ?: 0.0 }
            ) ?: group.first()

            val x = group.mapNotNull { (it["x"] as? Number)?.toDouble() }.average()
            val y1 = group.mapNotNull { (it["y1"] as? Number)?.toDouble() }.minOrNull()
                ?: (best["y1"] as Double)
            val y2 = group.mapNotNull { (it["y2"] as? Number)?.toDouble() }.maxOrNull()
                ?: (best["y2"] as Double)

            best + mapOf(
                "id" to "stem_$index",
                "x" to x,
                "y1" to y1,
                "y2" to y2,
                "height" to y2 - y1,
                "mergedStemCount" to group.size
            )
        }
    }

    private fun stemsOverlapForNms(
        a: Map<String, Any>,
        b: Map<String, Any>
    ): Boolean {
        if (a["staffId"].toString() != b["staffId"].toString()) return false

        val ax = (a["x"] as? Number)?.toDouble() ?: return false
        val bx = (b["x"] as? Number)?.toDouble() ?: return false
        if (abs(ax - bx) > 3.0) return false

        val ay1 = (a["y1"] as? Number)?.toDouble() ?: return false
        val ay2 = (a["y2"] as? Number)?.toDouble() ?: return false
        val by1 = (b["y1"] as? Number)?.toDouble() ?: return false
        val by2 = (b["y2"] as? Number)?.toDouble() ?: return false

        val overlap = max(0.0, min(ay2, by2) - max(ay1, by1))
        if (overlap <= 0.0) return false

        val shorter = min(abs(ay2 - ay1), abs(by2 - by1)).coerceAtLeast(1.0)
        return overlap / shorter >= 0.45
    }

    private fun deduplicateBeams(
        raw: List<Map<String, Any>>
    ): List<Map<String, Any>> {
        if (raw.isEmpty()) return emptyList()

        val sorted = raw.sortedWith(
            compareBy<Map<String, Any>> { it["staffId"].toString() }
                .thenBy { it["y"] as Double }
                .thenBy { it["x1"] as Int }
        )

        val result = mutableListOf<Map<String, Any>>()

        for (item in sorted) {
            val duplicate = result.any { existing ->
                existing["staffId"].toString() == item["staffId"].toString() &&
                        kotlin.math.abs((existing["y"] as Double) - (item["y"] as Double)) <= 3.0 &&
                        kotlin.math.abs((existing["x1"] as Int) - (item["x1"] as Int)) <= 8 &&
                        kotlin.math.abs((existing["x2"] as Int) - (item["x2"] as Int)) <= 8
            }

            if (!duplicate) result.add(item)
        }

        return result.mapIndexed { index, item -> item + ("id" to "beam_$index") }
    }

    private fun buildMeasures(
        staffs: List<Map<String, Any>>,
        barLines: List<Map<String, Any>>,
        imageWidth: Int
    ): List<Map<String, Any?>> {
        val measures = mutableListOf<Map<String, Any?>>()
        var measureIndex = 0

        for (staff in staffs) {
            val staffId = staff["id"] as String
            val spacing = staff["spacing"] as Double
            val staffBars = barLines
                .filter { it["staffId"] == staffId }
                .sortedBy { it["x"] as Double }

            val boundaries = mutableListOf(0.0)
            boundaries.addAll(staffBars.map { it["x"] as Double })
            boundaries.add(imageWidth.toDouble())

            val minWidth = spacing * 2.0

            for (i in 0 until boundaries.size - 1) {
                val startX = boundaries[i]
                val endX = boundaries[i + 1]

                if (endX - startX < minWidth) continue

                measures.add(
                    mapOf(
                        "id" to "measure_${measureIndex++}",
                        "staffId" to staffId,
                        "indexInStaff" to measures.count { it["staffId"] == staffId },
                        "x1" to startX,
                        "x2" to endX,
                        "startBarLineId" to staffBars.lastOrNull { (it["x"] as Double) <= startX }?.get("id"),
                        "endBarLineId" to staffBars.firstOrNull { (it["x"] as Double) >= endX }?.get("id"),
                        "source" to if (staffBars.isEmpty()) "implicit_full_staff" else "barline_derived"
                    )
                )
            }
        }

        return measures
    }

    private fun saveImage(context: Context, mat: Mat): String {
        val file = File(
            context.cacheDir,
            "segmented_${System.currentTimeMillis()}.png"
        )
        Imgcodecs.imwrite(file.absolutePath, mat)
        return file.absolutePath
    }

    private fun error(msg: String): Map<String, Any?> {
        return mapOf(
            "status" to "error",
            "message" to msg,
            "segmentedImagePath" to null,
            "staffLineCount" to 0,
            "staffLines" to emptyList<Any>(),
            "ledgerLines" to emptyList<Any>(),
            "barLines" to emptyList<Any>(),
            "stems" to emptyList<Any>(),
            "beams" to emptyList<Any>(),
            "measures" to emptyList<Any>(),
            "validatedStaffs" to emptyList<Any>()
        )
    }
}
```

<div style="page-break-after: always;"></div>

# File 2 — DocumentProcessor.kt

## Full Path

```text
D:\MyApps\AndroidStudio_Folder\stala_app\android\app\src\main\kotlin\com\example\stala_app\DocumentProcessor.kt
```

## Purpose

This file detects, validates, and crops the music-sheet document region from a captured image using OpenCV and music-sheet-aware heuristics. It supports the thesis objective of preparing clean input images before optical music recognition. It is important because accurate document bounds reduce downstream detection errors and allow the pipeline to operate on the intended sheet area.

## Full Source Code

```kotlin
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
```

<div style="page-break-after: always;"></div>

# File 3 — processing_page.dart

## Full Path

```text
D:\MyApps\AndroidStudio_Folder\stala_app\lib\processing_page.dart
```

## Purpose

This file coordinates the main STALA processing workflow from image preparation through symbol detection, staff segmentation, interpretation, fretboard mapping, and result generation while presenting progress to the user. It supports the thesis objective of integrating the complete OMR-to-tablature pipeline into an application flow. It is important because it connects the native vision layer, musical interpretation services, and final tablature output.

## Full Source Code

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/session_data.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_text_styles.dart';
import 'data/debug_settings_repository.dart';
import 'result_page.dart';
import 'dummy_page.dart';
import 'services/staff_segmentation_service.dart';
import 'services/barline_refinement_service.dart';
import 'models/translation_group_models.dart';
import 'services/translation_grouping_service.dart';
import 'services/note_grouping_service.dart';
import 'services/grand_staff_pairing_service.dart';
import 'services/polyphonic_to_monophonic_service.dart';
import 'services/musical_interpretation_service.dart';
import 'services/fretboard_mapping_service.dart';
import 'services/event_manager_service.dart';
import 'services/rhythm_interpretation_service.dart';
import 'services/tablature_result_adapter.dart';
import 'services/generation_service.dart';
import 'services/save_export_service.dart';
import 'data/app_settings_repository.dart';
import 'services/tutorial_service.dart';

/// Processing screen shown after the image crop is confirmed.
///
/// Responsibilities:
/// - display overall processing progress
/// - show each pipeline stage and its status
/// - simulate the current workflow for UI development
/// - bridge to the native OpenCV/ONNX vision pipeline
class ProcessingPage extends StatefulWidget {
  final String sourceImagePath;
  final String croppedImagePath;

  const ProcessingPage({
    super.key,
    required this.sourceImagePath,
    required this.croppedImagePath,
  });

  @override
  State<ProcessingPage> createState() => _ProcessingPageState();
}

/// High-level state of one processing stage in the pipeline.
enum ProcessingStageStatus { pending, active, completed, failed }

/// UI model for a single pipeline stage row.
class ProcessingStageItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final ProcessingStageStatus status;

  const ProcessingStageItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.status,
  });

  ProcessingStageItem copyWith({
    String? title,
    String? subtitle,
    IconData? icon,
    ProcessingStageStatus? status,
  }) {
    return ProcessingStageItem(
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      icon: icon ?? this.icon,
      status: status ?? this.status,
    );
  }
}

class SheetInterpretationException implements Exception {
  final String message;

  const SheetInterpretationException(this.message);

  @override
  String toString() => message;
}

class _SymbolGeometry {
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double centerX;
  final double centerY;

  const _SymbolGeometry({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.centerX,
    required this.centerY,
  });

  double get width => (x2 - x1).abs();
  double get height => (y2 - y1).abs();
}

enum StemAttachmentType { leftEdge, rightEdge, center, unknown }

class _StemAttachmentAnalysis {
  final StemAttachmentType type;
  final Map<String, dynamic>? stem;
  final double? stemCenterX;

  const _StemAttachmentAnalysis({
    required this.type,
    required this.stem,
    required this.stemCenterX,
  });
}

class _DetectionFilterResult {
  final List<Map<String, dynamic>> symbolGraph;
  final List<Map<String, dynamic>> translationDetections;
  final List<Map<String, dynamic>> rejectedNoteheads;
  final List<Map<String, dynamic>> semanticRegions;
  final List<Map<String, dynamic>> clefSafetyRegions;
  final List<Map<String, dynamic>> inferredSymbols;
  final Map<String, int> rejectionReasonCounts;

  const _DetectionFilterResult({
    required this.symbolGraph,
    required this.translationDetections,
    required this.rejectedNoteheads,
    required this.semanticRegions,
    required this.clefSafetyRegions,
    required this.inferredSymbols,
    required this.rejectionReasonCounts,
  });
}

class SymbolNode {
  final Map<String, dynamic> rawDetection;
  final SymbolState state;
  final double structuralScore;
  final bool isInferred;
  final List<String> rejectionReasons;
  final List<String> supportSources;
  final Map<String, dynamic> validation;

  const SymbolNode({
    required this.rawDetection,
    required this.state,
    required this.structuralScore,
    required this.isInferred,
    required this.rejectionReasons,
    required this.supportSources,
    required this.validation,
  });

  bool get isRejected => state == SymbolState.rejected;

  Map<String, dynamic> toMap() {
    return {
      ...rawDetection,
      'symbolState': state.name,
      'structuralScore': structuralScore,
      'isInferred': isInferred,
      'isRejected': isRejected,
      'rejectionReasons': rejectionReasons,
      'supportSources': supportSources,
      'validation': validation,
    };
  }
}

class _NoteheadValidation {
  final bool valid;
  final bool baseValid;
  final double finalScore;
  final double supportScore;
  final double nonStemSupportScore;
  final StemAttachmentType attachmentType;
  final double? attachmentStemCenterX;
  final double attachmentPenalty;
  final String reason;
  final bool ledgerCandidate;
  final bool ledgerPreserved;
  final bool edgeLedgerCandidate;
  final bool continuityRelaxed;
  final String? ledgerRejectionReason;

  const _NoteheadValidation({
    required this.valid,
    required this.baseValid,
    required this.finalScore,
    required this.supportScore,
    required this.nonStemSupportScore,
    required this.attachmentType,
    required this.attachmentStemCenterX,
    required this.attachmentPenalty,
    required this.reason,
    required this.ledgerCandidate,
    required this.ledgerPreserved,
    required this.edgeLedgerCandidate,
    required this.continuityRelaxed,
    required this.ledgerRejectionReason,
  });

  const _NoteheadValidation.invalid(String failureReason)
    : valid = false,
      baseValid = false,
      finalScore = 0.0,
      supportScore = 0.0,
      nonStemSupportScore = 0.0,
      attachmentType = StemAttachmentType.unknown,
      attachmentStemCenterX = null,
      attachmentPenalty = 0.0,
      ledgerCandidate = false,
      ledgerPreserved = false,
      edgeLedgerCandidate = false,
      continuityRelaxed = false,
      ledgerRejectionReason = null,
      reason = failureReason;
}

class _SupportScore {
  final double total;
  final double nonStem;

  const _SupportScore({required this.total, required this.nonStem});
}

class _SymbolAttachmentValidation {
  final bool valid;
  final String reason;

  const _SymbolAttachmentValidation({
    required this.valid,
    required this.reason,
  });
}

class _StructuralSupportContext {
  final bool ledger;
  final bool edgeStem;
  final bool beam;
  final bool chord;
  final bool rhythmicGrouping;
  final bool centerStem;

  const _StructuralSupportContext({
    required this.ledger,
    required this.edgeStem,
    required this.beam,
    required this.chord,
    required this.rhythmicGrouping,
    required this.centerStem,
  });
}

class _ClefOverlapPenalty {
  final double penalty;
  final List<String> reasons;
  final bool coreRejected;
  final bool transitionPenalty;
  final bool validNearClef;

  const _ClefOverlapPenalty({
    required this.penalty,
    required this.reasons,
    required this.coreRejected,
    required this.transitionPenalty,
    required this.validNearClef,
  });
}

class _ProcessingPageState extends State<ProcessingPage> {
  static const MethodChannel _visionPipelineChannel = MethodChannel(
    'stala/python_bridge',
  );

  late List<ProcessingStageItem> _stages;
  int _activeStageIndex = -1;
  bool _isProcessingFinished = false;
  bool _hasProcessingFailed = false;
  bool _isProcessingActive = false;
  String _statusMessage = 'Getting your music sheet ready...';

  final StaffSegmentationService _segmentationService =
      StaffSegmentationService();

  final BarlineRefinementService _barlineRefinementService =
      const BarlineRefinementService();

  final TranslationGroupingService _translationGroupingService =
      TranslationGroupingService();

  final NoteGroupingService _noteGroupingService = NoteGroupingService();

  final GrandStaffPairingService _grandStaffPairingService =
      GrandStaffPairingService();

  final PolyphonicToMonophonicService _polyMonoService =
      PolyphonicToMonophonicService();

  final MusicalInterpretationService _musicalInterpretationService =
      MusicalInterpretationService();

  final FretboardMappingService _fretboardMappingService =
      FretboardMappingService();

  final EventManagerService _eventManagerService = EventManagerService();

  final RhythmInterpretationService _rhythmInterpretationService =
      const RhythmInterpretationService();

  final SaveExportService _saveExportService = const SaveExportService();
  final AppSettingsRepository _appSettingsRepository =
      const AppSettingsRepository();

  Map<String, dynamic>? _processingResult;
  final GlobalKey _processingHelpTourKey = GlobalKey();
  final GlobalKey _processingProgressTourKey = GlobalKey();
  final GlobalKey _processingStepsTourKey = GlobalKey();
  final GlobalKey _processingFooterTourKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _stages = _buildInitialStages();
    _startProcessingPipeline();
    TutorialService.autoStartTour(
      context,
      pageKey: TutorialService.processingPageKey,
      keys: _processingTourKeys,
      page: TutorialPage.processingPage,
    );
  }

  List<GlobalKey> get _processingTourKeys => [
    _processingProgressTourKey,
    _processingStepsTourKey,
    _processingFooterTourKey,
    _processingHelpTourKey,
  ];

  List<ProcessingStageItem> _buildInitialStages() {
    return [
      const ProcessingStageItem(
        title: 'Preparing Image',
        subtitle:
            'Cleaning up the crop so the notes and staff lines are easier to read.',
        icon: Icons.tune_rounded,
        status: ProcessingStageStatus.pending,
      ),
      const ProcessingStageItem(
        title: 'Finding Music Symbols',
        subtitle: 'Looking for notes, accidentals, and clefs on the sheet.',
        icon: Icons.center_focus_strong_rounded,
        status: ProcessingStageStatus.pending,
      ),
      const ProcessingStageItem(
        title: 'Reading Staff Lines',
        subtitle: 'Locating each staff so STALA can understand note positions.',
        icon: Icons.horizontal_rule_rounded,
        status: ProcessingStageStatus.pending,
      ),
      const ProcessingStageItem(
        title: 'Interpreting Notes',
        subtitle:
            'Matching the detected marks to pitches and guitar-friendly choices.',
        icon: Icons.music_note_rounded,
        status: ProcessingStageStatus.pending,
      ),
      const ProcessingStageItem(
        title: 'Building Tablature',
        subtitle: 'Creating the guitar tab and playback-ready result.',
        icon: Icons.library_music_rounded,
        status: ProcessingStageStatus.pending,
      ),
    ];
  }

  Future<void> _startProcessingPipeline() async {
    if (_isProcessingActive) return;
    _isProcessingActive = true;
    try {
      if (!mounted) return;

      setState(() {
        _activeStageIndex = 0;
        _statusMessage = 'Getting your music sheet ready...';
        _stages[0] = _stages[0].copyWith(status: ProcessingStageStatus.active);
      });

      await Future.delayed(const Duration(milliseconds: 400));

      if (!mounted) return;

      setState(() {
        _stages[0] = _stages[0].copyWith(
          status: ProcessingStageStatus.completed,
        );
        _activeStageIndex = 1;
        _statusMessage = 'Finding the notes and symbols on the page...';
        _stages[1] = _stages[1].copyWith(status: ProcessingStageStatus.active);
      });

      setState(() {
        _statusMessage = 'Scanning the music symbols...';
      });

      final dynamic result = await _visionPipelineChannel.invokeMethod(
        'processImage',
        {'imagePath': widget.croppedImagePath},
      );

      setState(() {
        _statusMessage = 'Music symbols found. Reading the staff lines next...';
      });

      if (!mounted) return;

      final response = Map<String, dynamic>.from(result as Map);
      response['croppedImagePath'] ??= widget.croppedImagePath;
      _processingResult = response;

      final status = response['status']?.toString() ?? 'error';
      final message = response['message']?.toString();
      final errors = (response['errors'] as List?)?.cast<dynamic>() ?? const [];

      if (status == 'success') {
        final rawDetections = response['detections'] is List
            ? response['detections'] as List
            : const [];
        final immutableRawDetections = rawDetections
            .whereType<Map>()
            .map((item) {
              return Map<String, dynamic>.unmodifiable(
                Map<String, dynamic>.from(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ),
              );
            })
            .toList(growable: false);
        response['rawDetections'] = immutableRawDetections;
        print('STALA_COUNTS: RAW ONNX COUNT=${immutableRawDetections.length}');
        var classItems = _parseClassItems(rawDetections);

        setState(() {
          _stages[1] = _stages[1].copyWith(
            status: ProcessingStageStatus.completed,
          );
          _activeStageIndex = 2;
          _statusMessage = 'Reading staff lines and note positions...';
          _stages[2] = _stages[2].copyWith(
            status: ProcessingStageStatus.active,
          );
        });

        final segmentationInputPath =
            response['preprocessedImagePath'] ??
            response['detectionImagePath'] ??
            response['croppedImagePath'] ??
            widget.croppedImagePath;

        final segmentationResult = await _segmentationService.segmentStaffLines(
          imagePath: segmentationInputPath,
          symbolDetections: rawDetections,
        );

        if (segmentationResult['status'] == 'success') {
          response['segmentedImagePath'] =
              segmentationResult['segmentedImagePath'];
          response['staffLineCount'] = segmentationResult['staffLineCount'];
          response['staffLines'] = segmentationResult['staffLines'];
          final lockedValidatedStaffs = _freezeValidatedStaffs(
            segmentationResult['validatedStaffs'],
          );
          response['validatedStaffs'] = lockedValidatedStaffs;
          response['ledgerLines'] = segmentationResult['ledgerLines'];
          response['ledgerDiagnostics'] =
              segmentationResult['ledgerDiagnostics'] ?? const {};
          response['barLines'] = segmentationResult['barLines'];
          response['stems'] = segmentationResult['stems'];
          response['beams'] = segmentationResult['beams'];
          response['measures'] = segmentationResult['measures'];

          _logInputCoordinateLock(response);
          _logStaffIntegrityCheck('after_segmentation', lockedValidatedStaffs);
          _warnCoordinateSpaceDrift(
            'after_segmentation',
            lockedValidatedStaffs,
          );
          final staffIntegrity = _staffIntegrityReport(lockedValidatedStaffs);
          print(
            'STAFF_VALIDATION: '
            'staffs=${staffIntegrity['staffs']} '
            'avgSpacing=${(_toDouble(staffIntegrity['avgSpacing']) ?? 0).toStringAsFixed(2)} '
            'fragmented=${staffIntegrity['fragmented']}',
          );
          print(
            'SEGMENT_COUNTS: '
            'stems=${((response['stems'] as List?) ?? const []).length} '
            'beams=${((response['beams'] as List?) ?? const []).length} '
            'ledgers=${((response['ledgerLines'] as List?) ?? const []).length} '
            'barlines=${((response['barLines'] as List?) ?? const []).length} '
            'measures=${((response['measures'] as List?) ?? const []).length}',
          );

          final detectionValidation = _filterStructureAwareDetections(
            rawDetections: rawDetections,
            validatedStaffs: (response['validatedStaffs'] as List?) ?? const [],
            ledgerLines: (response['ledgerLines'] as List?) ?? const [],
            stems: (response['stems'] as List?) ?? const [],
            beams: (response['beams'] as List?) ?? const [],
          );

          final translationDetections =
              detectionValidation.translationDetections;
          response['symbolGraph'] = detectionValidation.symbolGraph;
          response['translationDetections'] = translationDetections;
          response['rejectedNoteheads'] = detectionValidation.rejectedNoteheads;
          response['semanticRegions'] = detectionValidation.semanticRegions;
          response['clefSafetyRegions'] = detectionValidation.clefSafetyRegions;
          response['inferredSymbols'] = detectionValidation.inferredSymbols;
          response['rejectionStats'] =
              detectionValidation.rejectionReasonCounts;
          classItems = _parseClassItems(translationDetections);

          print(
            'STALA_COUNTS: AFTER STRUCTURAL ANNOTATION '
            'graph=${detectionValidation.symbolGraph.length}',
          );
          final semanticPenaltyCount = detectionValidation.symbolGraph.where((
            item,
          ) {
            final reason = item['validationReason']?.toString() ?? '';
            return reason.contains('semantic penalty');
          }).length;
          print(
            'STALA_COUNTS: AFTER SEMANTIC SCORING '
            'semanticRegions=${detectionValidation.semanticRegions.length} '
            'semanticPenalties=$semanticPenaltyCount '
            'rejected=${detectionValidation.rejectedNoteheads.length}',
          );
          print(
            'STALA_COUNTS: REJECTION STATS '
            '${detectionValidation.rejectionReasonCounts}',
          );
          print(
            'STALA_COUNTS: AFTER INFERRED GENERATION '
            'inferred=${detectionValidation.inferredSymbols.length} '
            'graph=${detectionValidation.symbolGraph.length}',
          );
          _logStaffIntegrityCheck(
            'after_semantic_scoring',
            response['validatedStaffs'] as List? ?? const [],
          );
          _logStaffIntegrityCheck(
            'after_inferred_generation',
            response['validatedStaffs'] as List? ?? const [],
          );
          print(
            'SYMBOL_VALIDATION: '
            'detected=${detectionValidation.translationDetections.length} '
            'inferred=${detectionValidation.inferredSymbols.length} '
            'rejected=${detectionValidation.rejectedNoteheads.length}',
          );

          final refinedBarlines = _barlineRefinementService.refine(
            rawBarLines: (response['barLines'] as List?) ?? const [],
            rawMeasures: (response['measures'] as List?) ?? const [],
            rawValidatedStaffs:
                (response['validatedStaffs'] as List?) ?? const [],
            classItems: classItems,
            rawStems: (response['stems'] as List?) ?? const [],
          );

          response['barLines'] = refinedBarlines.barLines;
          response['measures'] = refinedBarlines.measures;
          _logDuplicateMeasureIds(refinedBarlines.measures);
          print(
            'SEGMENT_COUNTS: '
            'stems=${((response['stems'] as List?) ?? const []).length} '
            'beams=${((response['beams'] as List?) ?? const []).length} '
            'ledgers=${((response['ledgerLines'] as List?) ?? const []).length} '
            'barlines=${refinedBarlines.barLines.length} '
            'measures=${refinedBarlines.measures.length}',
          );

          setState(() {
            _stages[2] = _stages[2].copyWith(
              status: ProcessingStageStatus.completed,
            );
            _activeStageIndex = 3;
            _statusMessage = 'Connecting notes to their staff positions...';
            _stages[3] = _stages[3].copyWith(
              status: ProcessingStageStatus.active,
            );
          });

          print(
            'STALA_PIPELINE: interpreting start '
            'TRANSLATION-CONSUMED COUNT=${classItems.length} '
            'staffs=${(response['validatedStaffs'] as List?)?.length ?? 0} '
            'measures=${(response['measures'] as List?)?.length ?? 0}',
          );
          _logStaffIntegrityCheck(
            'before_translation',
            response['validatedStaffs'] as List? ?? const [],
          );

          final translateGroups = _translationGroupingService.buildGroups(
            classItems: classItems,
            staffLines: (response['staffLines'] as List?) ?? const [],
            validatedStaffs: (response['validatedStaffs'] as List?) ?? const [],
            ledgerLines: (response['ledgerLines'] as List?) ?? const [],
            measures: (response['measures'] as List?) ?? const [],
          );

          print(
            'STALA_PIPELINE: translateGroups=${translateGroups.length} '
            'symbols=${translateGroups.fold<int>(0, (sum, group) => sum + group.symbols.length)}',
          );

          final groupedNotes = _noteGroupingService.groupNotes(
            staffGroups: translateGroups,
          );

          final interpretedNoteCount = groupedNotes.values.fold<int>(
            0,
            (sum, groups) =>
                sum +
                groups.fold<int>(0, (inner, group) => inner + group.length),
          );

          if (interpretedNoteCount == 0) {
            throw const SheetInterpretationException(
              'No readable noteheads were matched to the staff lines. Please try a clearer crop with the full staff area visible.',
            );
          }

          print(
            'STALA_PIPELINE: groupedNotes=${groupedNotes.length} '
            'noteEvents=$interpretedNoteCount',
          );

          final noteGroupViewItems = groupedNotes.entries.map((entry) {
            return NoteGroupViewItem(
              staffId: entry.key,
              groups: entry.value
                  .map(
                    (group) => group
                        .map((note) => note.defaultKeyLabel ?? 'Unresolved')
                        .toList(),
                  )
                  .toList(),
            );
          }).toList();

          response['noteGroups'] = noteGroupViewItems;

          final rhythmResult = _rhythmInterpretationService.interpret(
            groupedNotes: groupedNotes,
            rawStems: (response['stems'] as List?) ?? const [],
            rawBeams: (response['beams'] as List?) ?? const [],
          );

          final rhythmViewItems = rhythmResult.events.map((event) {
            return RhythmEventViewItem(
              staffId: event.staffId,
              measureIndex: event.measureIndex,
              label: event.label,
              durationBeats: event.durationBeats,
              timingSource: event.timingSource,
              confidence: event.confidence,
              hasStem: event.hasStem,
              hasBeam: event.hasBeam,
            );
          }).toList();

          response['rhythmEvents'] = rhythmViewItems;

          print('STALA_PIPELINE: rhythmEvents=${rhythmResult.events.length}');
          print(
            'TRANSLATION_COUNTS: '
            'symbols=${translateGroups.fold<int>(0, (sum, group) => sum + group.symbols.length)} '
            'noteEvents=$interpretedNoteCount '
            'rhythmEvents=${rhythmResult.events.length}',
          );

          final grandStaffPairs = _grandStaffPairingService.pairStaffs(
            noteGroups: noteGroupViewItems,
            translateGroups: translateGroups,
          );

          print('STALA_PIPELINE: grandStaffPairs=${grandStaffPairs.length}');

          final grandStaffPairViewItems = grandStaffPairs
              .map((pair) {
                final trebleView = _findNoteGroupViewItem(
                  noteGroupViewItems,
                  pair.trebleStaffId,
                );

                if (trebleView == null) return null;

                final bassView = pair.bassStaffId == null
                    ? null
                    : _findNoteGroupViewItem(
                        noteGroupViewItems,
                        pair.bassStaffId!,
                      );

                return GrandStaffPairViewItem(
                  id: pair.id,
                  trebleStaffId: pair.trebleStaffId,
                  bassStaffId: pair.bassStaffId,
                  trebleGroups: trebleView.groups,
                  bassGroups: bassView?.groups ?? const [],
                );
              })
              .whereType<GrandStaffPairViewItem>()
              .toList();

          response['grandStaffPairs'] = grandStaffPairViewItems;

          final polyMonoResults = _polyMonoService.convert(
            grandStaffPairs: grandStaffPairs,
            groupedNotes: groupedNotes,
          );

          print(
            'STALA_PIPELINE: polyMonoResults=${polyMonoResults.length} '
            'stacks=${polyMonoResults.fold<int>(0, (sum, result) => sum + result.harmonicStacks.length)}',
          );

          final polyMonoViewItems = polyMonoResults.map((result) {
            final chordAwareStrings = result.chordAwareStacks.map((stack) {
              final notes = stack.notes
                  .map((n) => n.defaultKeyLabel ?? 'Unresolved')
                  .join(' + ');

              final chord = stack.chordName;

              if (chord == null) {
                return 'NO_CHORD';
              }

              return '[$notes] → $chord';
            }).toList();

            final allNoChord = chordAwareStrings.every(
              (item) => item == 'NO_CHORD',
            );

            final finalChordAware = allNoChord
                ? ['No chords detected']
                : chordAwareStrings
                      .where((item) => item != 'NO_CHORD')
                      .toList();

            return PolyMonoViewItem(
              grandStaffId: result.grandStaffId,
              harmonicStacks: result.harmonicStacks.map((stack) {
                return stack.notes
                    .map((n) => n.defaultKeyLabel ?? 'Unresolved')
                    .toList();
              }).toList(),
              chordAwareStacks: finalChordAware,
              strictMelody: result.strictMelody.map((n) => n.pitch).toList(),
            );
          }).toList();

          response['polyMonoResults'] = polyMonoViewItems;

          // Music interpretation service
          final musicInterpretation = _musicalInterpretationService.interpret(
            polyMonoResults: polyMonoResults,
          );

          print(
            'STALA_PIPELINE: musicInterpretation '
            'grandStaff=${musicInterpretation.grandStaffLine.events.length} '
            'trebleOnly=${musicInterpretation.trebleOnlyLine.events.length}',
          );

          final musicInterpretationViewItems = [
            MusicInterpretationViewItem(
              title: musicInterpretation.grandStaffLine.title,
              labels: musicInterpretation.grandStaffLine.events
                  .map((event) => event.label)
                  .toList(),
            ),
            MusicInterpretationViewItem(
              title: musicInterpretation.trebleOnlyLine.title,
              labels: musicInterpretation.trebleOnlyLine.events
                  .map((event) => event.label)
                  .toList(),
            ),
          ];

          response['musicInterpretations'] = musicInterpretationViewItems;

          // F-map
          final fretboardMapping = _fretboardMappingService.mapInterpretation(
            interpretation: musicInterpretation,
          );

          print(
            'STALA_PIPELINE: fretboardMapping '
            'events=${fretboardMapping.lines.fold<int>(0, (sum, line) => sum + line.events.length)} '
            'candidates=${fretboardMapping.lines.fold<int>(0, (sum, line) => sum + line.events.fold<int>(0, (inner, event) => inner + event.candidates.length))}',
          );

          final fretboardMappingViewItems = fretboardMapping.lines.map((line) {
            return FretboardMappingViewItem(
              title: line.title,
              eventSummaries: line.events.map((event) {
                final preview = event.candidates
                    .take(3)
                    .map((candidate) {
                      return candidate.positions
                          .map((pos) {
                            return 'S${pos.stringNumber} F${pos.fret}';
                          })
                          .join(' + ');
                    })
                    .join(', ');

                final suffix = event.candidates.length > 3 ? '...' : '';

                return '${event.label} → ${event.candidates.length} candidates: $preview$suffix';
              }).toList(),
            );
          }).toList();

          response['fretboardMappings'] = fretboardMappingViewItems;

          // Event manager
          final eventManagerResult = _eventManagerService.manage(
            fretboardMapping: fretboardMapping,
          );

          print(
            'STALA_PIPELINE: eventManager '
            'lines=${eventManagerResult.lines.length}',
          );

          final eventManagerViewItems = eventManagerResult.lines.map((line) {
            return EventManagerViewItem(
              title: line.title,
              totalCost: line.totalCost.toStringAsFixed(2),
              events: line.events.map((event) {
                final positions = event.chosenPositions
                    .map((pos) {
                      return '${pos.pitch}: S${pos.stringNumber} F${pos.fret}';
                    })
                    .join(' + ');

                return '${event.label} → $positions';
              }).toList(),
            );
          }).toList();

          response['eventManagerResults'] = eventManagerViewItems;

          final chordVoicingViewItems = const <ChordVoicingViewItem>[];
          response['chordVoicingResults'] = chordVoicingViewItems;

          if (!mounted) return;

          setState(() {
            _stages[3] = _stages[3].copyWith(
              status: ProcessingStageStatus.completed,
            );
            _activeStageIndex = 4;
            _statusMessage = 'Building your tablature result...';
            _stages[4] = _stages[4].copyWith(
              status: ProcessingStageStatus.active,
            );
          });

          final tablatureResults = const TablatureResultAdapter().combine(
            eventManagerResult: eventManagerResult,
            rhythmResult: rhythmResult,
            titleFallback: 'Sample 1',
          );

          debugPrint('TABLATURE RESULTS: ${tablatureResults.length} mode(s)');

          response['tablatureResults'] = tablatureResults
              .map((result) => result.toJson())
              .toList();

          for (final result in tablatureResults) {
            debugPrint('${result.mode.name}: ${result.events.length} events');

            if (result.events.isNotEmpty) {
              final first = result.events.first;
              debugPrint(
                'First event: index=${first.eventIndex}, '
                'duration=${first.durationSeconds}, '
                'label=${first.label}, '
                'positions=${first.positions.length}',
              );
            }
          }

          // Session save
          final session = SessionData(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            projectName: 'Sample 1',

            originalImagePath: widget.sourceImagePath,
            croppedImagePath:
                response['croppedImagePath']?.toString() ??
                widget.croppedImagePath,
            preprocessedImagePath: response['preprocessedImagePath']
                ?.toString(),
            detectionImagePath: response['detectionImagePath']?.toString(),
            segmentationImagePath: response['segmentedImagePath']?.toString(),

            detectedSymbols:
                (response['symbolGraph'] as List? ??
                        response['rawDetections'] as List? ??
                        const [])
                    .whereType<Map>()
                    .map((item) => Map<String, dynamic>.from(item))
                    .toList(),

            segmentationData: _buildDebugSegmentationSnapshot(response),

            pitchMappingData:
                (response['rejectedNoteheads'] as List? ?? const [])
                    .whereType<Map>()
                    .map((item) => Map<String, dynamic>.from(item))
                    .toList(),
            fretboardEvents: const [],

            tablatureResults: tablatureResults,

            processingTimestamp: DateTime.now(),
            modelVersion: 'v1',
            hasPipelineSnapshot: true,
          );

          // Generate display data
          final generatedTabs = const GenerationService().generateAll(
            results: tablatureResults,
          );
          response['pipelineReport'] = _buildPipelineReport(
            response: response,
            translateGroups: translateGroups,
            rhythmEvents: rhythmViewItems,
            generatedTabs: generatedTabs,
          );

          debugPrint('GENERATED TABS: ${generatedTabs.length} mode(s)');

          for (final tab in generatedTabs) {
            debugPrint(
              '${tab.mode.name}: '
              '${tab.columns.length} columns, '
              '${tab.fretboardFrames.length} fretboard frames, '
              '${tab.exportPages.length} export pages',
            );
          }

          final generatedTabViewItems = generatedTabs.map((tab) {
            final first = tab.columns.isNotEmpty ? tab.columns.first : null;

            return GeneratedTabViewItem(
              mode: tab.mode.name,
              columns: tab.columns.length,
              fretboardFrames: tab.fretboardFrames.length,
              exportPages: tab.exportPages.length,
              firstEventSummary: first == null
                  ? 'No events'
                  : '${first.label} → ${first.numbers.length} note(s)',
            );
          }).toList();

          final frozenDebugSnapshot = _buildFrozenDebugSnapshot(
            translateGroups: translateGroups,
            noteGroups: noteGroupViewItems,
            rhythmEvents: rhythmViewItems,
            grandStaffPairs: grandStaffPairViewItems,
            polyMonoResults: polyMonoViewItems,
            musicInterpretations: musicInterpretationViewItems,
            fretboardMappings: fretboardMappingViewItems,
            eventManagerResults: eventManagerViewItems,
            chordVoicingResults: chordVoicingViewItems,
            generatedTabs: generatedTabViewItems,
            pipelineReport: Map<String, dynamic>.from(
              response['pipelineReport'] as Map? ?? const {},
            ),
          );

          /// Apply an auto-save to the session data
          SessionData finalSession = session.copyWith(
            debugSnapshot: frozenDebugSnapshot,
          );

          try {
            final autoSaveEnabled = await _appSettingsRepository
                .getAutoSaveEnabled();

            if (autoSaveEnabled) {
              final savedFile = await _saveExportService.saveStalaFile(
                session: finalSession,
              );

              finalSession = finalSession.copyWith(
                autoSavedFilePath: savedFile.path,
                autoSavedAt: DateTime.now(),
                autoSaveFailed: false,
              );
            }
          } catch (error) {
            finalSession = finalSession.copyWith(autoSaveFailed: true);

            debugPrint('AUTO_SAVE_FAILED: $error');
          }

          response['sessionData'] = finalSession;
          response['generatedTabResults'] = generatedTabs;
          response['generatedTabViewItems'] = generatedTabViewItems;

          response['translateGroups'] = translateGroups;
          _processingResult = response;

          setState(() {
            _stages[4] = _stages[4].copyWith(
              status: ProcessingStageStatus.completed,
            );

            _isProcessingFinished = true;
            _statusMessage = 'Your guitar tablature is ready to review.';
          });
        } else {
          final segmentationMessage =
              segmentationResult['message']?.toString() ??
              'The staff lines could not be read clearly.';
          throw Exception(segmentationMessage);
        }
      } else {
        setState(() {
          _stages[1] = _stages[1].copyWith(
            status: ProcessingStageStatus.failed,
          );
          _hasProcessingFailed = true;
          _statusMessage = errors.isNotEmpty
              ? 'The sheet could not be read clearly. Please try a sharper crop.'
              : (message ??
                    'The sheet could not be processed. Please try again.');
        });
      }
    } on PlatformException catch (error, stackTrace) {
      print('STALA_PIPELINE: platform error $error');
      print(stackTrace);

      if (!mounted) return;

      setState(() {
        if (_activeStageIndex >= 0 && _activeStageIndex < _stages.length) {
          _stages[_activeStageIndex] = _stages[_activeStageIndex].copyWith(
            status: ProcessingStageStatus.failed,
          );
        }
        _hasProcessingFailed = true;
        _statusMessage =
            'STALA could not start the reading step. Please try again.';
      });
    } on SheetInterpretationException catch (error, stackTrace) {
      print('STALA_PIPELINE: interpretation data error ${error.message}');
      print(stackTrace);

      if (!mounted) return;

      setState(() {
        if (_activeStageIndex >= 0 && _activeStageIndex < _stages.length) {
          _stages[_activeStageIndex] = _stages[_activeStageIndex].copyWith(
            status: ProcessingStageStatus.failed,
          );
        }
        _hasProcessingFailed = true;
        _statusMessage = error.message;
      });
    } catch (error, stackTrace) {
      print('STALA_PIPELINE: interpretation error $error');
      print(stackTrace);

      if (!mounted) return;

      setState(() {
        if (_activeStageIndex >= 0 && _activeStageIndex < _stages.length) {
          _stages[_activeStageIndex] = _stages[_activeStageIndex].copyWith(
            status: ProcessingStageStatus.failed,
          );
        }
        _hasProcessingFailed = true;
        _statusMessage = 'Something went wrong while reading the sheet.';
      });
    } finally {
      _isProcessingActive = false;
    }
  }

  NoteGroupViewItem? _findNoteGroupViewItem(
    List<NoteGroupViewItem> items,
    String staffId,
  ) {
    for (final item in items) {
      if (item.staffId == staffId) return item;
    }
    return null;
  }

  /// Resets the page state and runs the mock pipeline again.
  Future<void> _retryProcessing() async {
    if (_isProcessingActive) return;
    setState(() {
      _activeStageIndex = -1;
      _isProcessingFinished = false;
      _hasProcessingFailed = false;
      _statusMessage = 'Getting your music sheet ready...';
      _stages = _buildInitialStages();
      _processingResult = null;
    });

    await _startProcessingPipeline();
  }

  /// Number of completed stages already finished in the current run.
  int get _completedStageCount {
    return _stages
        .where((stage) => stage.status == ProcessingStageStatus.completed)
        .length;
  }

  /// Progress value for the summary progress bar.
  double get _progressValue {
    if (_stages.isEmpty) return 0;
    return _completedStageCount / _stages.length;
  }

  /// This helps verify that the response from native side is really being received.
  Future<void> _showNextStepMessage() async {
    if (_processingResult == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.backgroundSecondary,
          content: Text(
            'No processing result available yet.',
            style: AppTextStyles.body,
          ),
        ),
      );
      return;
    }

    final result = _processingResult!;

    final croppedImagePath = _pickFirstNonEmptyString(result, const [
      'croppedImagePath',
    ]);

    final detectedImagePath = _pickFirstNonEmptyString(result, const [
      'detectedImagePath',
      'annotatedImagePath',
      'visualizedImagePath',
      'detectionImagePath',
      'preprocessedImagePath',
    ]);

    final segmentedImagePath = _pickFirstNonEmptyString(result, const [
      'segmentedImagePath',
    ]);

    final detections = _parseDetectionPoints(result['detections']);
    final classItems = _parseClassItems(
      result['translationDetections'] ??
          result['symbolGraph'] ??
          result['detections'],
    );
    final translateGroups =
        (result['translateGroups'] as List<StaffTranslateGroup>?) ?? const [];

    final noteGroups =
        (result['noteGroups'] as List<NoteGroupViewItem>?) ?? const [];

    final rhythmEvents =
        (result['rhythmEvents'] as List<RhythmEventViewItem>?) ?? const [];

    final grandStaffPairs =
        (result['grandStaffPairs'] as List<GrandStaffPairViewItem>?) ??
        const [];

    final polyMonoResults =
        (result['polyMonoResults'] as List<PolyMonoViewItem>?) ?? const [];

    final musicInterpretations =
        (result['musicInterpretations']
            as List<MusicInterpretationViewItem>?) ??
        const [];

    final fretboardMappings =
        (result['fretboardMappings'] as List<FretboardMappingViewItem>?) ??
        const [];

    final eventManagerResults =
        (result['eventManagerResults'] as List<EventManagerViewItem>?) ??
        const [];

    final chordVoicingResults =
        (result['chordVoicingResults'] as List<ChordVoicingViewItem>?) ??
        const [];

    final session = result['sessionData'] as SessionData;
    final generatedTabResults =
        (result['generatedTabResults'] as List<GeneratedTabResult>?) ??
        const [];

    final generatedTabs =
        (result['generatedTabViewItems'] as List<GeneratedTabViewItem>?) ??
        const [];

    final ledgerLines = _parseConfirmedLedgerLines(
      result['ledgerLines'],
      translateGroups,
    );

    final isDebugEnabled = await const DebugSettingsRepository()
        .isDebugPageEnabled();

    if (!mounted) return;

    if (isDebugEnabled) {
      final debugResult = await Navigator.push<Object?>(
        context,
        MaterialPageRoute(
          builder: (_) => DummyPage(
            croppedImagePath: croppedImagePath ?? widget.croppedImagePath,
            detectedImagePath:
                detectedImagePath ??
                croppedImagePath ??
                widget.croppedImagePath,
            segmentedImagePath: segmentedImagePath,
            detections: detections,
            classItems: classItems,
            staffOverlays: _normalizeMapList(result['validatedStaffs']),
            barLineOverlays: _normalizeMapList(result['barLines']),
            stemOverlays: _normalizeMapList(result['stems']),
            beamOverlays: _normalizeMapList(result['beams']),
            semanticRegions: _normalizeMapList(result['semanticRegions']),
            clefSafetyRegions: _normalizeMapList(result['clefSafetyRegions']),
            rejectedNoteheads: _normalizeMapList(result['rejectedNoteheads']),
            translateGroups: translateGroups,
            noteGroups: noteGroups,
            rhythmEvents: rhythmEvents,
            grandStaffPairs: grandStaffPairs,
            polyMonoResults: polyMonoResults,
            musicInterpretations: musicInterpretations,
            fretboardMappings: fretboardMappings,
            eventManagerResults: eventManagerResults,
            chordVoicingResults: chordVoicingResults,
            session: session,
            generatedTabResults: generatedTabResults,
            generatedTabs: generatedTabs,
            ledgerLines: ledgerLines,
            generateOutputs: const [],
            pipelineReport: Map<String, dynamic>.from(
              result['pipelineReport'] as Map? ?? const {},
            ),
            onRetry: () => Navigator.pop(context, 'retry'),
          ),
        ),
      );

      if (!mounted) return;

      if (debugResult == 'retry') {
        await _retryProcessing();
        if (!mounted || !_isProcessingFinished || _hasProcessingFailed) return;
        await _showNextStepMessage();
      } else if (debugResult == 'openResult') {
        final shouldRefreshHome = await Navigator.pushReplacement<bool, bool>(
          context,
          MaterialPageRoute(
            builder: (_) => ResultPage(
              session: session,
              generatedTabs: generatedTabResults,
            ),
          ),
        );

        if (!mounted) return;

        if (shouldRefreshHome == true) {
          Navigator.pop(context, true);
        }
      } else if (debugResult == true) {
        Navigator.pop(context, true);
      }
    } else {
      final shouldRefreshHome = await Navigator.pushReplacement<bool, bool>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ResultPage(session: session, generatedTabs: generatedTabResults),
        ),
      );

      if (!mounted) return;

      if (shouldRefreshHome == true) {
        Navigator.pop(context, true);
      }
    }
  }

  String? _pickFirstNonEmptyString(
    Map<String, dynamic> source,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = source[key];
      if (value is String && value.trim().isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  List<DetectionPoint> _parseDetectionPoints(dynamic rawDetections) {
    if (rawDetections is! List) return const [];

    final List<DetectionPoint> points = [];

    for (final item in rawDetections) {
      if (item is! Map) continue;

      final map = Map<String, dynamic>.from(
        item.map((key, value) => MapEntry(key.toString(), value)),
      );

      final className =
          map['className']?.toString() ??
          map['labelName']?.toString() ??
          map['label']?.toString() ??
          'symbol';

      final score = _toDouble(map['score'] ?? map['confidence']);

      double? centerX;
      double? centerY;

      if (map['centerX'] != null && map['centerY'] != null) {
        centerX = _toDouble(map['centerX']);
        centerY = _toDouble(map['centerY']);
      } else if (map['bbox'] is List && (map['bbox'] as List).length >= 4) {
        final bbox = List.from(map['bbox']);
        final x1 = _toDouble(bbox[0]);
        final y1 = _toDouble(bbox[1]);
        final x2 = _toDouble(bbox[2]);
        final y2 = _toDouble(bbox[3]);

        if (x1 != null && y1 != null && x2 != null && y2 != null) {
          centerX = (x1 + x2) / 2.0;
          centerY = (y1 + y2) / 2.0;
        }
      } else {
        final left = _toDouble(map['left'] ?? map['x1'] ?? map['xmin']);
        final top = _toDouble(map['top'] ?? map['y1'] ?? map['ymin']);
        final right = _toDouble(map['right'] ?? map['x2'] ?? map['xmax']);
        final bottom = _toDouble(map['bottom'] ?? map['y2'] ?? map['ymax']);

        if (left != null && top != null && right != null && bottom != null) {
          centerX = (left + right) / 2.0;
          centerY = (top + bottom) / 2.0;
        }
      }

      if (centerX == null || centerY == null) continue;

      points.add(
        DetectionPoint(
          className: className,
          centerX: centerX,
          centerY: centerY,
          score: score,
        ),
      );
    }

    return points;
  }

  List<Map<String, dynamic>> _normalizeMapList(dynamic rawItems) {
    if (rawItems is! List) return const [];

    return rawItems.whereType<Map>().map((item) {
      return Map<String, dynamic>.from(
        item.map((key, value) => MapEntry(key.toString(), value)),
      );
    }).toList();
  }

  List<Map<String, dynamic>> _freezeValidatedStaffs(dynamic rawStaffs) {
    if (rawStaffs is! List) return const [];

    final frozen = rawStaffs
        .whereType<Map>()
        .map((item) {
          final staff = Map<String, dynamic>.from(
            item.map((key, value) => MapEntry(key.toString(), value)),
          );

          final rawLines = staff['lines'];

          final List<double> lines;

          if (rawLines is List) {
            lines = rawLines
                .map((e) => _toDouble(e))
                .whereType<double>()
                .toList();

            lines.sort();
          } else {
            lines = <double>[];
          }

          final spacing =
              _toDouble(staff['validatedStaffSpacing']) ??
              _toDouble(staff['spacing']) ??
              _averageSpacing(lines);

          return Map<String, dynamic>.unmodifiable({
            ...staff,
            'lines': List<double>.unmodifiable(lines),
            'spacing': spacing,
            'validatedStaffSpacing': spacing,
            'locked': true,
            'coordinateSpace': 'original_image',
          });
        })
        .toList();

    frozen.sort((a, b) {
      final aLines =
          (a['lines'] as List?)?.whereType<double>().toList() ??
          const <double>[];
      final bLines =
          (b['lines'] as List?)?.whereType<double>().toList() ??
          const <double>[];
      final aY = aLines.isEmpty ? double.infinity : aLines.first;
      final bY = bLines.isEmpty ? double.infinity : bLines.first;
      final yCompare = aY.compareTo(bY);
      if (yCompare != 0) return yCompare;
      final aSpacing = _toDouble(a['spacing']) ?? 0.0;
      final bSpacing = _toDouble(b['spacing']) ?? 0.0;
      final spacingCompare = aSpacing.compareTo(bSpacing);
      if (spacingCompare != 0) return spacingCompare;
      return (a['id']?.toString() ?? '').compareTo(b['id']?.toString() ?? '');
    });

    return List<Map<String, dynamic>>.unmodifiable(frozen);
  }

  Map<String, dynamic> _staffIntegrityReport(List<dynamic> validatedStaffs) {
    final staffs = _normalizeMapList(validatedStaffs);
    final spacings = staffs
        .map(
          (staff) =>
              _toDouble(staff['validatedStaffSpacing'] ?? staff['spacing']),
        )
        .whereType<double>()
        .where((spacing) => spacing > 0)
        .toList();
    final avgSpacing = spacings.isEmpty
        ? 0.0
        : spacings.reduce((a, b) => a + b) / spacings.length;
    final fragmented = staffs.where((staff) {
      final lines = staff['lines'];
      return lines is! List || lines.length != 5;
    }).length;

    return {
      'status': fragmented == 0 && staffs.isNotEmpty ? 'PASSED' : 'WARNING',
      'staffs': staffs.length,
      'avgSpacing': avgSpacing,
      'fragmented': fragmented,
    };
  }

  void _logStaffIntegrityCheck(String stage, List<dynamic> validatedStaffs) {
    final report = _staffIntegrityReport(validatedStaffs);
    print(
      'STAFF_INTEGRITY_CHECK: '
      'stage=$stage '
      'status=${report['status']} '
      'staffs=${report['staffs']} '
      'avgSpacing=${(_toDouble(report['avgSpacing']) ?? 0).toStringAsFixed(2)} '
      'fragmented=${report['fragmented']}',
    );
  }

  void _logInputCoordinateLock(Map<String, dynamic> response) {
    final originalWidth =
        response['originalImageWidth'] ??
        response['sourceImageWidth'] ??
        response['imageWidth'];
    final originalHeight =
        response['originalImageHeight'] ??
        response['sourceImageHeight'] ??
        response['imageHeight'];
    final letterboxWidth = response['imageWidth'];
    final letterboxHeight = response['imageHeight'];
    print(
      'INPUT_COORDINATE_LOCK: '
      'originalWidth=${originalWidth ?? '-'} '
      'originalHeight=${originalHeight ?? '-'} '
      'letterboxWidth=${letterboxWidth ?? '-'} '
      'letterboxHeight=${letterboxHeight ?? '-'} '
      'coordinateSpace=original_image',
    );
  }

  void _logDuplicateMeasureIds(List<dynamic> measures) {
    final ids = <String>{};
    final duplicates = <String>{};
    for (final item in measures.whereType<Map>()) {
      final id = item['id']?.toString();
      if (id == null || id.isEmpty) continue;
      if (!ids.add(id)) duplicates.add(id);
    }
    if (duplicates.isNotEmpty) {
      print('MEASURE_ID_WARNING: duplicates=${duplicates.join(',')}');
    }
  }

  void _warnCoordinateSpaceDrift(String stage, Iterable<dynamic> items) {
    for (final item in items.whereType<Map>()) {
      final space = item['coordinateSpace']?.toString();
      if (space != null && space != 'original_image') {
        print(
          'COORDINATE_SPACE_WARNING: '
          'stage=$stage id=${item['id'] ?? '-'} coordinateSpace=$space',
        );
      }
    }
  }

  Map<String, dynamic> _buildPipelineReport({
    required Map<String, dynamic> response,
    required List<StaffTranslateGroup> translateGroups,
    required List<RhythmEventViewItem> rhythmEvents,
    required List<GeneratedTabResult> generatedTabs,
  }) {
    final staffs = _normalizeMapList(response['validatedStaffs']);
    final symbolGraph = _normalizeMapList(response['symbolGraph']);
    final inferredSymbols = _normalizeMapList(response['inferredSymbols']);
    final rejectedNoteheads = _normalizeMapList(response['rejectedNoteheads']);
    final ledgerDiagnostics = Map<String, dynamic>.from(
      response['ledgerDiagnostics'] as Map? ?? const {},
    );
    final staffReport = staffs.map((staff) {
      final lines = (staff['lines'] as List?) ?? const [];
      return {
        'id': staff['id']?.toString() ?? '',
        'spacing':
            _toDouble(staff['validatedStaffSpacing'] ?? staff['spacing']) ??
            0.0,
        'lineCount': lines.length,
        'continuityScore':
            _toDouble(
              staff['continuityScore'] ??
                  staff['continuity'] ??
                  staff['confidence'],
            ) ??
            0.0,
        'region':
            '${_toDouble(staff['topBoundary'])?.toStringAsFixed(1) ?? '-'}-${_toDouble(staff['bottomBoundary'])?.toStringAsFixed(1) ?? '-'}',
        'grandStaffPairId': staff['grandStaffPairId']?.toString() ?? '-',
      };
    }).toList();

    final attachmentTypes = <String, int>{};
    var semanticPenalties = 0;
    var centerAttachmentPenalties = 0;
    for (final symbol in symbolGraph) {
      final attachment = symbol['stemAttachmentType']?.toString();
      if (attachment != null && attachment.isNotEmpty) {
        attachmentTypes[attachment] = (attachmentTypes[attachment] ?? 0) + 1;
      }
      final validationReason = symbol['validation'] is Map
          ? (symbol['validation'] as Map)['reason']?.toString()
          : null;
      final reason =
          symbol['validationReason']?.toString() ?? validationReason ?? '';
      if (reason.contains('semantic penalty')) semanticPenalties++;
      if (reason.contains('center_stem_attachment'))
        centerAttachmentPenalties++;
    }

    return {
      'staff': staffReport,
      'symbols': {
        'detectedSymbols': symbolGraph.length,
        'inferredSymbols': inferredSymbols.length,
        'rejectedSymbols': rejectedNoteheads.length,
        'rejectionReasons': response['rejectionStats'] ?? const {},
        'attachmentTypes': attachmentTypes,
      },
      'segments': {
        'stems': ((response['stems'] as List?) ?? const []).length,
        'beams': ((response['beams'] as List?) ?? const []).length,
        'ledgerLines': ((response['ledgerLines'] as List?) ?? const []).length,
        'barlines': ((response['barLines'] as List?) ?? const []).length,
        'measures': ((response['measures'] as List?) ?? const []).length,
        'semanticRegions':
            ((response['semanticRegions'] as List?) ?? const []).length,
        'clefSafetyRegions':
            ((response['clefSafetyRegions'] as List?) ?? const []).length,
      },
      'ledger': ledgerDiagnostics.isEmpty
          ? {
              'rawCandidates':
                  ((response['ledgerLines'] as List?) ?? const []).length,
              'validatedLedgers':
                  ((response['ledgerLines'] as List?) ?? const []).length,
              'rejectedFragments': 0,
              'rejectionReasons': const {},
            }
          : ledgerDiagnostics,
      'validation': {
        'semanticPenalties': semanticPenalties,
        'centerAttachmentPenalties': centerAttachmentPenalties,
        'inferredRecoveryCount': inferredSymbols.length,
        'accidentalAssociations': symbolGraph.where((symbol) {
          final sources = symbol['supportSources'];
          return sources is List && sources.contains('attached_notehead');
        }).length,
      },
      'translation': {
        'translationConsumedSymbols': translateGroups.fold<int>(
          0,
          (sum, group) => sum + group.symbols.length,
        ),
        'groupedNotes': ((response['noteGroups'] as List?) ?? const [])
            .whereType<NoteGroupViewItem>()
            .fold<int>(
              0,
              (sum, item) =>
                  sum +
                  item.groups.fold<int>(
                    0,
                    (inner, group) => inner + group.length,
                  ),
            ),
        'rhythmEvents': rhythmEvents.length,
        'generatedTablatureEvents': generatedTabs.fold<int>(
          0,
          (sum, tab) => sum + tab.columns.length,
        ),
      },
      'coordinates': {
        'coordinateSpace': 'original_image',
        'imageWidth': response['imageWidth'],
        'imageHeight': response['imageHeight'],
        'lockedStaffs': staffs.where((staff) => staff['locked'] == true).length,
      },
    };
  }

  Map<String, dynamic> _buildFrozenDebugSnapshot({
    required List<StaffTranslateGroup> translateGroups,
    required List<NoteGroupViewItem> noteGroups,
    required List<RhythmEventViewItem> rhythmEvents,
    required List<GrandStaffPairViewItem> grandStaffPairs,
    required List<PolyMonoViewItem> polyMonoResults,
    required List<MusicInterpretationViewItem> musicInterpretations,
    required List<FretboardMappingViewItem> fretboardMappings,
    required List<EventManagerViewItem> eventManagerResults,
    required List<ChordVoicingViewItem> chordVoicingResults,
    required List<GeneratedTabViewItem> generatedTabs,
    required Map<String, dynamic> pipelineReport,
  }) {
    return {
      'translateGroups': translateGroups
          .map(_staffTranslateGroupToJson)
          .toList(),
      'noteGroups': noteGroups.map((item) {
        return {'staffId': item.staffId, 'groups': item.groups};
      }).toList(),
      'rhythmEvents': rhythmEvents.map((item) {
        return {
          'staffId': item.staffId,
          'measureIndex': item.measureIndex,
          'label': item.label,
          'durationBeats': item.durationBeats,
          'timingSource': item.timingSource,
          'confidence': item.confidence,
          'hasStem': item.hasStem,
          'hasBeam': item.hasBeam,
        };
      }).toList(),
      'grandStaffPairs': grandStaffPairs.map((item) {
        return {
          'id': item.id,
          'trebleStaffId': item.trebleStaffId,
          'bassStaffId': item.bassStaffId,
          'trebleGroups': item.trebleGroups,
          'bassGroups': item.bassGroups,
        };
      }).toList(),
      'polyMonoResults': polyMonoResults.map((item) {
        return {
          'grandStaffId': item.grandStaffId,
          'harmonicStacks': item.harmonicStacks,
          'chordAwareStacks': item.chordAwareStacks,
          'strictMelody': item.strictMelody,
        };
      }).toList(),
      'musicInterpretations': musicInterpretations.map((item) {
        return {'title': item.title, 'labels': item.labels};
      }).toList(),
      'fretboardMappings': fretboardMappings.map((item) {
        return {'title': item.title, 'eventSummaries': item.eventSummaries};
      }).toList(),
      'eventManagerResults': eventManagerResults.map((item) {
        return {
          'title': item.title,
          'totalCost': item.totalCost,
          'events': item.events,
        };
      }).toList(),
      'chordVoicingResults': chordVoicingResults.map((item) {
        return {'title': item.title, 'events': item.events};
      }).toList(),
      'generatedTabs': generatedTabs.map((item) {
        return {
          'mode': item.mode,
          'columns': item.columns,
          'fretboardFrames': item.fretboardFrames,
          'exportPages': item.exportPages,
          'firstEventSummary': item.firstEventSummary,
        };
      }).toList(),
      'pipelineReport': pipelineReport,
    };
  }

  Map<String, dynamic> _staffTranslateGroupToJson(StaffTranslateGroup group) {
    return {
      'staffId': group.staffId,
      'summary': {
        'lineCount': group.summary.lineCount,
        'symbolCount': group.summary.symbolCount,
        'clefStatusLabel': group.summary.clefStatusLabel,
      },
      'segmentMap': group.segmentMap.map((item) {
        return {
          'id': item.id,
          'type': item.type,
          'centerY': item.centerY,
          'startY': item.startY,
          'endY': item.endY,
          'defaultKeyLabel': item.defaultKeyLabel,
        };
      }).toList(),
      'symbols': group.symbols.map((symbol) {
        return {
          'className': symbol.className,
          'centerX': symbol.centerX,
          'centerY': symbol.centerY,
          'score': symbol.score,
          'bbox': symbol.bbox,
          'staffId': symbol.staffId,
          'staffRole': symbol.staffRole,
          'locationId': symbol.locationId,
          'locationType': symbol.locationType,
          'assignmentStatus': symbol.assignmentStatus,
          'measureId': symbol.measureId,
          'measureIndex': symbol.measureIndex,
          'defaultKeyLabel': symbol.defaultKeyLabel,
          'accidentalState': symbol.accidentalState,
          'symbolState': symbol.symbolState.name,
          'inferredReason': symbol.inferredReason,
        };
      }).toList(),
    };
  }

  List<Map<String, dynamic>> _buildDebugSegmentationSnapshot(
    Map<String, dynamic> response,
  ) {
    final snapshot = <Map<String, dynamic>>[];

    void addList(String kind, dynamic rawItems) {
      if (rawItems is! List) return;
      for (final item in rawItems.whereType<Map>()) {
        snapshot.add({
          'kind': kind,
          ...Map<String, dynamic>.from(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        });
      }
    }

    addList('staffLine', response['staffLines']);
    addList('validatedStaff', response['validatedStaffs']);
    addList('ledgerLine', response['ledgerLines']);
    addList('barLine', response['barLines']);
    addList('stem', response['stems']);
    addList('beam', response['beams']);
    addList('measure', response['measures']);
    addList('semanticRegion', response['semanticRegions']);
    addList('clefSafetyRegion', response['clefSafetyRegions']);
    addList('inferredSymbol', response['inferredSymbols']);
    addList('symbolGraphNode', response['symbolGraph']);
    return snapshot;
  }

  _DetectionFilterResult _filterStructureAwareDetections({
    required List<dynamic> rawDetections,
    required List<dynamic> validatedStaffs,
    required List<dynamic> ledgerLines,
    required List<dynamic> stems,
    required List<dynamic> beams,
  }) {
    final symbols = rawDetections
        .whereType<Map>()
        .map((item) {
          return Map<String, dynamic>.from(
            item.map((key, value) => MapEntry(key.toString(), value)),
          );
        })
        .where((item) => _symbolGeometry(item) != null)
        .toList();

    print('STALA_COUNTS: AFTER STAFF ASSOCIATION symbols=${symbols.length}');

    final clefs = symbols.where((item) {
      final className = _symbolClassName(item);
      return className == 'treble_clef' || className == 'bass_clef';
    }).toList();

    final semanticRegions = _buildPreMeasureSemanticRegions(
      clefs: clefs,
      validatedStaffs: validatedStaffs,
    );
    final clefSafetyRegions = _buildClefSafetyRegions(
      clefs: clefs,
      validatedStaffs: validatedStaffs,
    );

    final noteheadCandidates = symbols.where((item) {
      return _symbolClassName(item) == 'notehead';
    }).toList();

    final timeSignatureLike = _likelyTimeSignatureNoteheads(
      noteheadCandidates: noteheadCandidates,
      semanticRegions: semanticRegions,
      stems: stems,
      beams: beams,
    );

    final symbolGraph = <Map<String, dynamic>>[];
    final translationDetections = <Map<String, dynamic>>[];
    final rejectedNoteheads = <Map<String, dynamic>>[];
    final rejectionReasonCounts = <String, int>{};
    final stemAttachmentCounts = {
      StemAttachmentType.leftEdge: 0,
      StemAttachmentType.rightEdge: 0,
      StemAttachmentType.center: 0,
      StemAttachmentType.unknown: 0,
    };
    var centerAttachmentPenaltyCount = 0;
    var rawDetectedLedgerCount = 0;
    var preservedLedgerCount = 0;
    var rejectedLedgerCount = 0;
    var edgeLedgerCount = 0;
    var continuityRelaxationCount = 0;
    final ledgerRejectionReasonCounts = <String, int>{};

    void countReasons(List<String> reasons) {
      for (final reason in reasons) {
        rejectionReasonCounts[reason] =
            (rejectionReasonCounts[reason] ?? 0) + 1;
      }
    }

    void countLedgerReason(String? reason) {
      if (reason == null || reason.isEmpty) return;
      ledgerRejectionReasonCounts[reason] =
          (ledgerRejectionReasonCounts[reason] ?? 0) + 1;
    }

    for (final item in symbols.where((item) {
      final className = _symbolClassName(item);
      return className == 'treble_clef' ||
          className == 'bass_clef' ||
          className == 'notehead';
    })) {
      final geometry = _symbolGeometry(item);
      if (geometry == null) continue;

      final className = _symbolClassName(item);
      if (className == 'treble_clef' || className == 'bass_clef') {
        final node = SymbolNode(
          rawDetection: item,
          state: SymbolState.detected,
          structuralScore:
              _toDouble(item['score'] ?? item['confidence']) ?? 1.0,
          isInferred: false,
          rejectionReasons: const [],
          supportSources: const ['onnx'],
          validation: const {'reason': 'clef preserved'},
        ).toMap();
        symbolGraph.add(node);
        translationDetections.add(node);
        continue;
      }

      if (className == 'notehead') {
        final validation = _validateNoteheadCandidate(
          item: item,
          allSymbols: symbols,
          validatedStaffs: validatedStaffs,
          ledgerLines: ledgerLines,
          stems: stems,
          beams: beams,
          semanticRegions: semanticRegions,
          clefSafetyRegions: clefSafetyRegions,
          timeSignatureLike: timeSignatureLike,
        );

        final enriched = {
          ...item,
          'baseValid': validation.baseValid,
          'structuralSupportScore': validation.supportScore,
          'nonStemSupportScore': validation.nonStemSupportScore,
          'stemAttachmentType': validation.attachmentType.name,
          'stemAttachmentX': validation.attachmentStemCenterX,
          'stemAttachmentPenalty': validation.attachmentPenalty,
          'finalValidationScore': validation.finalScore,
          'validationReason': validation.reason,
        };

        stemAttachmentCounts[validation.attachmentType] =
            (stemAttachmentCounts[validation.attachmentType] ?? 0) + 1;
        if (validation.attachmentPenalty > 0 &&
            validation.attachmentType == StemAttachmentType.center) {
          centerAttachmentPenaltyCount++;
        }
        if (validation.ledgerCandidate) rawDetectedLedgerCount++;
        if (validation.ledgerPreserved) preservedLedgerCount++;
        if (validation.edgeLedgerCandidate) edgeLedgerCount++;
        if (validation.continuityRelaxed) continuityRelaxationCount++;

        if (validation.valid) {
          final node = SymbolNode(
            rawDetection: enriched,
            state: SymbolState.detected,
            structuralScore: validation.finalScore,
            isInferred: false,
            rejectionReasons: const [],
            supportSources: _supportSourcesForScore(enriched),
            validation: {
              'reason': validation.reason,
              'baseValid': validation.baseValid,
              'supportScore': validation.supportScore,
              'nonStemSupportScore': validation.nonStemSupportScore,
              'stemAttachmentType': validation.attachmentType.name,
              'stemAttachmentX': validation.attachmentStemCenterX,
              'stemAttachmentPenalty': validation.attachmentPenalty,
              'ledgerCandidate': validation.ledgerCandidate,
              'ledgerPreserved': validation.ledgerPreserved,
              'edgeLedgerCandidate': validation.edgeLedgerCandidate,
              'continuityRelaxed': validation.continuityRelaxed,
            },
          ).toMap();
          symbolGraph.add(node);
          translationDetections.add(node);
        } else {
          final reasons = _splitValidationReasons(validation.reason);
          final node = SymbolNode(
            rawDetection: enriched,
            state: SymbolState.rejected,
            structuralScore: validation.finalScore,
            isInferred: false,
            rejectionReasons: reasons,
            supportSources: _supportSourcesForScore(enriched),
            validation: {
              'reason': validation.reason,
              'baseValid': validation.baseValid,
              'supportScore': validation.supportScore,
              'nonStemSupportScore': validation.nonStemSupportScore,
              'stemAttachmentType': validation.attachmentType.name,
              'stemAttachmentX': validation.attachmentStemCenterX,
              'stemAttachmentPenalty': validation.attachmentPenalty,
              'ledgerCandidate': validation.ledgerCandidate,
              'ledgerPreserved': validation.ledgerPreserved,
              'edgeLedgerCandidate': validation.edgeLedgerCandidate,
              'continuityRelaxed': validation.continuityRelaxed,
              'ledgerRejectionReason': validation.ledgerRejectionReason,
            },
          ).toMap();
          symbolGraph.add(node);
          rejectedNoteheads.add({...node, 'className': 'notehead'});
          if (validation.ledgerCandidate) {
            rejectedLedgerCount++;
            countLedgerReason(validation.ledgerRejectionReason);
          }
          countReasons(reasons);
        }
        continue;
      }
    }

    print(
      'STEM_ATTACHMENT: '
      'left=${stemAttachmentCounts[StemAttachmentType.leftEdge] ?? 0} '
      'right=${stemAttachmentCounts[StemAttachmentType.rightEdge] ?? 0} '
      'center=${stemAttachmentCounts[StemAttachmentType.center] ?? 0} '
      'unknown=${stemAttachmentCounts[StemAttachmentType.unknown] ?? 0}',
    );
    print('CENTER_ATTACHMENT_PENALTIES=$centerAttachmentPenaltyCount');
    print(
      'LEDGER_STABILITY: '
      'rawDetectedLedgerCount=$rawDetectedLedgerCount '
      'preservedLedgerCount=$preservedLedgerCount '
      'rejectedLedgerCount=$rejectedLedgerCount '
      'edgeLedgerCount=$edgeLedgerCount '
      'continuityRelaxationCount=$continuityRelaxationCount '
      'rejectionReasons=$ledgerRejectionReasonCounts',
    );

    final inferredSymbols = _generateInferredLedgerNoteheads(
      validSymbols: translationDetections,
      rejectedNoteheads: rejectedNoteheads,
      ledgerLines: ledgerLines,
      stems: stems,
      validatedStaffs: validatedStaffs,
    );
    symbolGraph.addAll(inferredSymbols);
    translationDetections.addAll(inferredSymbols);

    for (final item in symbols.where((item) {
      final className = _symbolClassName(item);
      return className != 'treble_clef' &&
          className != 'bass_clef' &&
          className != 'notehead';
    })) {
      final geometry = _symbolGeometry(item);
      if (geometry == null) continue;

      final className = _symbolClassName(item);
      if (_isAccidentalClass(className)) {
        final validation = _validateAccidental(
          symbol: geometry,
          validSymbols: translationDetections,
          ledgerLines: ledgerLines,
          validatedStaffs: validatedStaffs,
          semanticRegions: semanticRegions,
          clefSafetyRegions: clefSafetyRegions,
        );
        if (validation.valid) {
          final node = SymbolNode(
            rawDetection: {...item, 'validationReason': validation.reason},
            state: SymbolState.detected,
            structuralScore:
                (_toDouble(item['score'] ?? item['confidence']) ?? 0.65)
                    .clamp(0.0, 1.0)
                    .toDouble(),
            isInferred: false,
            rejectionReasons: const [],
            supportSources: const ['attached_notehead'],
            validation: {'reason': validation.reason},
          ).toMap();
          symbolGraph.add(node);
          translationDetections.add(node);
        } else {
          final reasons = _splitValidationReasons(validation.reason);
          final node = SymbolNode(
            rawDetection: {...item, 'validationReason': validation.reason},
            state: SymbolState.rejected,
            structuralScore:
                (_toDouble(item['score'] ?? item['confidence']) ?? 0.45)
                    .clamp(0.0, 1.0)
                    .toDouble(),
            isInferred: false,
            rejectionReasons: reasons,
            supportSources: const [],
            validation: {'reason': validation.reason},
          ).toMap();
          symbolGraph.add(node);
          countReasons(reasons);
        }
        continue;
      }

      if (_insideAnyStaffRegion(geometry.centerY, validatedStaffs) ||
          _supportedByLedger(geometry, ledgerLines) ||
          _nearSupportedNotehead(geometry, translationDetections)) {
        final node = SymbolNode(
          rawDetection: item,
          state: SymbolState.detected,
          structuralScore:
              (_toDouble(item['score'] ?? item['confidence']) ?? 0.62)
                  .clamp(0.0, 1.0)
                  .toDouble(),
          isInferred: false,
          rejectionReasons: const [],
          supportSources: const ['staff_or_ledger_context'],
          validation: const {'reason': 'staff/ledger context'},
        ).toMap();
        symbolGraph.add(node);
        translationDetections.add(node);
      } else {
        const reasons = ['outside structural context'];
        final node = SymbolNode(
          rawDetection: item,
          state: SymbolState.rejected,
          structuralScore:
              (_toDouble(item['score'] ?? item['confidence']) ?? 0.40)
                  .clamp(0.0, 1.0)
                  .toDouble(),
          isInferred: false,
          rejectionReasons: reasons,
          supportSources: const [],
          validation: const {'reason': 'outside structural context'},
        ).toMap();
        symbolGraph.add(node);
        countReasons(reasons);
      }
    }

    final clefRegionStats = _clefRegionStats(
      symbolGraph: symbolGraph,
      clefSafetyRegions: clefSafetyRegions,
    );
    final clefCoreRejected = clefRegionStats['coreRejected'] ?? 0;
    final clefTransitionPenalties = clefRegionStats['transitionPenalties'] ?? 0;
    final validNearClef = clefRegionStats['validNearClef'] ?? 0;
    final overlapCoreCount = rejectionReasonCounts['overlap_core'] ?? 0;
    final centerNearClefCount =
        rejectionReasonCounts['center_attachment_near_clef'] ?? 0;
    final unsupportedAccidentalCount =
        rejectionReasonCounts['unsupported_accidental'] ?? 0;
    final numeralStackNearClefCount =
        rejectionReasonCounts['numeral_stack_near_clef'] ?? 0;
    print(
      'CLEF_REGION: '
      'coreRejected=$clefCoreRejected '
      'transitionPenalties=$clefTransitionPenalties '
      'validNearClef=$validNearClef',
    );
    print(
      'CLEF_REGION_REASONS: '
      'overlap_core=$overlapCoreCount '
      'center_attachment_near_clef=$centerNearClefCount '
      'unsupported_accidental=$unsupportedAccidentalCount '
      'numeral_stack_near_clef=$numeralStackNearClefCount',
    );

    return _DetectionFilterResult(
      symbolGraph: symbolGraph,
      translationDetections: translationDetections,
      rejectedNoteheads: rejectedNoteheads,
      semanticRegions: semanticRegions,
      clefSafetyRegions: clefSafetyRegions,
      inferredSymbols: inferredSymbols,
      rejectionReasonCounts: rejectionReasonCounts,
    );
  }

  List<Map<String, dynamic>> _buildClefSafetyRegions({
    required List<Map<String, dynamic>> clefs,
    required List<dynamic> validatedStaffs,
  }) {
    final regions = <Map<String, dynamic>>[];

    for (final clef in clefs) {
      final clefGeometry = _symbolGeometry(clef);
      if (clefGeometry == null) continue;

      final staff = _nearestStaffForSymbol(clefGeometry, validatedStaffs);
      if (staff == null) continue;

      final staffId = staff['id']?.toString() ?? '';
      final spacing =
          _toDouble(staff['validatedStaffSpacing'] ?? staff['spacing']) ?? 12.0;
      final top = _toDouble(staff['topBoundary']);
      final bottom = _toDouble(staff['bottomBoundary']);
      if (staffId.isEmpty || top == null || bottom == null || spacing <= 0) {
        continue;
      }

      final padding = spacing * 0.65;
      final expansionPaddingX = spacing * 0.9;
      final expansionPaddingY = spacing * 0.9;
      final transitionWidth = spacing * 3.2;
      regions.add({
        'id': 'clef_safety_${regions.length}',
        'staffId': staffId,
        'type': 'ClefSafetyRegion',
        'x1': clefGeometry.x1 - expansionPaddingX,
        'x2': clefGeometry.x2 + expansionPaddingX,
        'y1': top - expansionPaddingY,
        'y2': bottom + expansionPaddingY,
        'coreX1': clefGeometry.x1,
        'coreX2': clefGeometry.x2,
        'coreY1': clefGeometry.y1,
        'coreY2': clefGeometry.y2,
        'expansionX1': clefGeometry.x1 - expansionPaddingX,
        'expansionX2': clefGeometry.x2 + expansionPaddingX,
        'expansionY1': top - expansionPaddingY,
        'expansionY2': bottom + expansionPaddingY,
        'transitionX1': clefGeometry.x2,
        'transitionX2': clefGeometry.x2 + transitionWidth,
        'transitionY1': top - padding,
        'transitionY2': bottom + padding,
        'sourceClass': _symbolClassName(clef),
        'penalty': 0.30,
      });
    }

    return regions;
  }

  List<Map<String, dynamic>> _buildPreMeasureSemanticRegions({
    required List<Map<String, dynamic>> clefs,
    required List<dynamic> validatedStaffs,
  }) {
    final regions = <Map<String, dynamic>>[];

    for (final clef in clefs) {
      final clefGeometry = _symbolGeometry(clef);
      if (clefGeometry == null) continue;

      final staff = _nearestStaffForSymbol(clefGeometry, validatedStaffs);
      if (staff == null) continue;

      final staffId = staff['id']?.toString() ?? '';
      final spacing =
          _toDouble(staff['validatedStaffSpacing'] ?? staff['spacing']) ?? 12.0;
      final top = _toDouble(staff['topBoundary']);
      final bottom = _toDouble(staff['bottomBoundary']);
      if (staffId.isEmpty || top == null || bottom == null) continue;

      final clefTransitionWidth = spacing * 1.1;
      final keySignatureWidth = spacing * 4.2;
      final timeSignatureWidth = spacing * 2.7;
      final regionTop = top - spacing * 0.5;
      final regionBottom = bottom + spacing * 0.5;
      final clefRight = clefGeometry.x2;
      final keyStart = clefRight + spacing * 0.45;
      final timeStart = keyStart + keySignatureWidth;

      regions.add({
        'id': 'clef_transition_${regions.length}',
        'staffId': staffId,
        'type': 'clefTransitionSemanticRegion',
        'semanticRole': 'clef',
        'x1': clefRight,
        'x2': clefRight + clefTransitionWidth,
        'y1': regionTop,
        'y2': regionBottom,
        'sourceClass': _symbolClassName(clef),
        'penalty': 0.25,
      });
      regions.add({
        'id': 'key_signature_${regions.length}',
        'staffId': staffId,
        'type': 'keySignatureSemanticRegion',
        'semanticRole': 'keySignature',
        'x1': keyStart,
        'x2': keyStart + keySignatureWidth,
        'y1': regionTop,
        'y2': regionBottom,
        'sourceClass': _symbolClassName(clef),
        'penalty': 0.0,
      });
      regions.add({
        'id': 'time_signature_${regions.length}',
        'staffId': staffId,
        'type': 'timeSignatureSemanticRegion',
        'semanticRole': 'timeSignature',
        'x1': timeStart - spacing * 0.35,
        'x2': timeStart + timeSignatureWidth,
        'y1': regionTop,
        'y2': regionBottom,
        'sourceClass': _symbolClassName(clef),
        'penalty': 0.32,
      });
    }

    return regions;
  }

  List<String> _splitValidationReasons(String reason) {
    return reason
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  List<String> _supportSourcesForScore(Map<String, dynamic> symbol) {
    final sources = <String>['onnx'];
    final support = _toDouble(symbol['structuralSupportScore']) ?? 0.0;
    final nonStem = _toDouble(symbol['nonStemSupportScore']) ?? 0.0;
    if (support > 0) sources.add('structural_support');
    if (nonStem > 0) sources.add('non_stem_support');
    return sources;
  }

  Map<String, int> _clefRegionStats({
    required List<Map<String, dynamic>> symbolGraph,
    required List<Map<String, dynamic>> clefSafetyRegions,
  }) {
    var coreRejected = 0;
    var transitionPenalties = 0;
    var validNearClef = 0;

    for (final item in symbolGraph) {
      final reasons = (item['rejectionReasons'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false);
      if (reasons.contains('overlap_core')) coreRejected++;
      if (reasons.contains('clef_transition_penalty')) transitionPenalties++;

      if (item['isRejected'] == true) continue;
      final className = _symbolClassName(item);
      if (className != 'notehead' && !_isAccidentalClass(className)) continue;
      final geometry = _symbolGeometry(item);
      if (geometry == null) continue;
      if (_regionContaining(geometry, clefSafetyRegions) == null) continue;

      final validation = item['validation'] as Map?;
      final reason = validation?['reason']?.toString() ?? '';
      final supportSources = (item['supportSources'] as List? ?? const [])
          .map((value) => value.toString())
          .toSet();
      final hasSupport =
          supportSources.contains('non_stem_support') ||
          reason.contains('attached') ||
          reason.contains('ledger') ||
          reason.contains('cluster');
      if (hasSupport) validNearClef++;
    }

    return {
      'coreRejected': coreRejected,
      'transitionPenalties': transitionPenalties,
      'validNearClef': validNearClef,
    };
  }

  _NoteheadValidation _validateNoteheadCandidate({
    required Map<String, dynamic> item,
    required List<Map<String, dynamic>> allSymbols,
    required List<dynamic> validatedStaffs,
    required List<dynamic> ledgerLines,
    required List<dynamic> stems,
    required List<dynamic> beams,
    required List<Map<String, dynamic>> semanticRegions,
    required List<Map<String, dynamic>> clefSafetyRegions,
    required Set<Map<String, dynamic>> timeSignatureLike,
  }) {
    final geometry = _symbolGeometry(item);
    if (geometry == null) {
      return const _NoteheadValidation.invalid('missing geometry');
    }

    final staff = _nearestStaffForSymbol(geometry, validatedStaffs);
    final spacing =
        _toDouble(staff?['validatedStaffSpacing'] ?? staff?['spacing']) ?? 12.0;
    final morphology = _noteheadMorphologyScore(geometry, spacing);
    final alignment = _staffAlignmentScore(geometry, staff);
    final confidence = (_toDouble(item['score'] ?? item['confidence']) ?? 0.50)
        .clamp(0.0, 1.0)
        .toDouble();
    final insideStaff = _insideAnyStaffRegion(
      geometry.centerY,
      validatedStaffs,
    );
    final ledgerSupported = _supportedByLedger(
      geometry,
      ledgerLines,
      spacing: spacing,
    );
    final overlapsClef = allSymbols.any((other) {
      final otherClass = _symbolClassName(other);
      if (otherClass != 'treble_clef' && otherClass != 'bass_clef')
        return false;
      final otherGeometry = _symbolGeometry(other);
      return otherGeometry != null && _iou(geometry, otherGeometry) >= 0.12;
    });

    final baseValid = _isBaseValidNotehead(
      insideStaff: insideStaff,
      ledgerSupported: ledgerSupported,
      morphology: morphology,
      alignment: alignment,
      overlapsClef: overlapsClef,
    );

    final wholeNote = _isWholeNoteShape(
      symbol: geometry,
      staff: staff,
      spacing: spacing,
      morphology: morphology,
      alignment: alignment,
      confidence: confidence,
      stems: stems,
    );

    final support = _computeNoteheadSupportScore(
      symbol: geometry,
      allSymbols: allSymbols,
      ledgerLines: ledgerLines,
      stems: stems,
      beams: beams,
      spacing: spacing,
    );

    double score = confidence;
    final reasons = <String>[];
    var attachmentPenalty = 0.0;
    var ledgerPreserved = false;
    var continuityRelaxed = false;
    String? ledgerRejectionReason;

    if (!baseValid && !wholeNote) {
      if (!insideStaff && !ledgerSupported) reasons.add('outside staff/ledger');
      if (morphology < 0.38) reasons.add('weak morphology');
      if (alignment < 0.32) reasons.add('weak staff alignment');
    }

    score += (morphology - 0.50) * 0.20;
    score += (alignment - 0.50) * 0.18;
    score += support.total;

    if (overlapsClef) {
      score -= 0.12;
      reasons.add('clef overlap penalty');
    }

    final inPostClefRegion = _penalizingSemanticRegionContaining(
      geometry,
      semanticRegions,
    );
    final inClefSafetyRegion = _regionContaining(geometry, clefSafetyRegions);
    final attachment = wholeNote
        ? const _StemAttachmentAnalysis(
            type: StemAttachmentType.unknown,
            stem: null,
            stemCenterX: null,
          )
        : _analyzeStemAttachment(geometry, stems, spacing: spacing);
    final hasBeamSupport = _supportedByBeam(geometry, beams, spacing: spacing);
    final hasRhythmicNeighbor = _hasRhythmicNeighbor(
      geometry,
      allSymbols,
      spacing: spacing,
    );
    final hasNearbyNotehead = _nearSupportedNotehead(
      geometry,
      allSymbols,
      spacing: spacing,
    );
    final ledgerContinuitySupport = _ledgerContinuitySupportForNotehead(
      symbol: geometry,
      ledgerLines: ledgerLines,
      spacing: spacing,
    );
    final edgeLedgerCandidate =
        ledgerSupported && !hasNearbyNotehead && !hasRhythmicNeighbor;
    final rawDetectedLedgerCandidate =
        ledgerSupported &&
        SymbolState.fromValue(item['symbolState']) != SymbolState.inferred;
    final attachedToValidEdgeStem =
        attachment.type == StemAttachmentType.leftEdge ||
        attachment.type == StemAttachmentType.rightEdge;
    final structuralSupport = _StructuralSupportContext(
      ledger: ledgerSupported,
      edgeStem: attachedToValidEdgeStem,
      beam: hasBeamSupport,
      chord: hasNearbyNotehead,
      rhythmicGrouping: hasRhythmicNeighbor,
      centerStem: attachment.type == StemAttachmentType.center,
    );

    if (inPostClefRegion != null) {
      score -= 0.25;
      reasons.add('post-clef semantic penalty');
    }

    if (!wholeNote && inClefSafetyRegion != null) {
      final outsideClefCore = !_insideClefCore(geometry, inClefSafetyRegion);
      final stronglySupportedNearbyNote =
          attachedToValidEdgeStem &&
          hasBeamSupport &&
          hasRhythmicNeighbor &&
          outsideClefCore &&
          confidence >= 0.72;

      if (!stronglySupportedNearbyNote) {
        final protectedNearClef =
            outsideClefCore &&
            (ledgerSupported || hasNearbyNotehead || attachedToValidEdgeStem);
        var clefPenalty = protectedNearClef ? 0.08 : 0.30;
        reasons.add('clef safety region penalty');
        if (attachment.type == StemAttachmentType.center) {
          clefPenalty += 0.18;
          reasons.add('clef safety center_stem_attachment');
        }
        if (!hasBeamSupport) clefPenalty += 0.05;
        if (!hasRhythmicNeighbor) clefPenalty += 0.04;
        score -= clefPenalty.clamp(0.0, 0.50).toDouble();
      }
    }

    if (!wholeNote) {
      final clefPenalty = computeClefOverlapPenalty(
        symbol: geometry,
        clefSafetyRegions: clefSafetyRegions,
        staffSpacing: spacing,
        support: structuralSupport,
      );
      if (clefPenalty.reasons.isNotEmpty) {
        score -= clefPenalty.penalty;
        reasons.addAll(clefPenalty.reasons);
      }
    }

    if (!wholeNote &&
        attachment.type == StemAttachmentType.center &&
        inPostClefRegion != null) {
      var penalty = 0.45;
      reasons.add('center_stem_attachment');

      if (!hasBeamSupport) {
        penalty += 0.08;
        reasons.add('no beam support');
      }
      if (!hasRhythmicNeighbor) {
        penalty += 0.05;
        reasons.add('no rhythmic grouping');
      }
      if (!hasNearbyNotehead && support.nonStem < 0.08 && !ledgerSupported) {
        penalty += 0.06;
        reasons.add('isolated center-stem notehead');
      }
      if (overlapsClef) {
        penalty += 0.05;
        reasons.add('near clef center-stem');
      }
      if (timeSignatureLike.contains(item)) {
        penalty += 0.08;
        reasons.add('vertical numeral stack nearby');
      }

      attachmentPenalty = penalty.clamp(0.0, 0.72).toDouble();
      score -= attachmentPenalty;
    }

    if (!wholeNote &&
        inPostClefRegion != null &&
        _hasStemDirectionMismatch(
          notehead: geometry,
          stem: attachment.stem,
          attachmentType: attachment.type,
        )) {
      score -= 0.06;
      attachmentPenalty += 0.06;
      reasons.add('stem direction attachment mismatch');
    }

    final semanticConflict =
        inPostClefRegion != null || timeSignatureLike.contains(item);
    final clefCoreConflict =
        inClefSafetyRegion != null &&
        _insideClefCore(geometry, inClefSafetyRegion);
    final centerStemConflict =
        attachment.type == StemAttachmentType.center &&
        !hasBeamSupport &&
        !hasRhythmicNeighbor;
    final plausibleRawLedger =
        rawDetectedLedgerCandidate &&
        confidence >= 0.62 &&
        morphology >= 0.34 &&
        alignment >= 0.26 &&
        !semanticConflict &&
        !clefCoreConflict &&
        !centerStemConflict;

    if (plausibleRawLedger) {
      final continuityBias = ledgerContinuitySupport > 0.0 ? 0.05 : 0.0;
      final edgeBias = edgeLedgerCandidate ? 0.03 : 0.0;
      score += 0.06 + continuityBias + edgeBias;
      ledgerPreserved = true;
      continuityRelaxed = continuityBias > 0.0;
      reasons.remove('isolated notehead');
      reasons.remove('weak staff alignment');
    }

    if (timeSignatureLike.contains(item)) {
      score -= 0.38;
      reasons.add('vertical time-signature-like stack');
      if (inPostClefRegion != null || inClefSafetyRegion != null) {
        reasons.add('numeral_stack_near_clef');
      }
    }

    if (!wholeNote &&
        !hasNearbyNotehead &&
        support.total < 0.12 &&
        !ledgerSupported) {
      score -= 0.10;
      reasons.add('isolated notehead');
    }

    final threshold = inPostClefRegion == null ? 0.45 : 0.52;
    final ledgerThreshold = plausibleRawLedger ? threshold - 0.04 : threshold;
    final finalScore = score.clamp(0.0, 1.0).toDouble();
    final valid = wholeNote
        ? finalScore >= 0.56 && !timeSignatureLike.contains(item)
        : baseValid && finalScore >= ledgerThreshold;

    if (rawDetectedLedgerCandidate && !valid) {
      ledgerRejectionReason = _ledgerRejectionReason(
        ledgerSupported: ledgerSupported,
        semanticConflict: semanticConflict,
        clefCoreConflict: clefCoreConflict,
        morphology: morphology,
        alignment: alignment,
        supportScore: support.total,
      );
    }

    return _NoteheadValidation(
      valid: valid,
      baseValid: baseValid || wholeNote,
      finalScore: finalScore,
      supportScore: support.total,
      nonStemSupportScore: support.nonStem,
      attachmentType: attachment.type,
      attachmentStemCenterX: attachment.stemCenterX,
      attachmentPenalty: attachmentPenalty.clamp(0.0, 1.0).toDouble(),
      ledgerCandidate: rawDetectedLedgerCandidate,
      ledgerPreserved: valid && ledgerPreserved,
      edgeLedgerCandidate: edgeLedgerCandidate,
      continuityRelaxed: continuityRelaxed,
      ledgerRejectionReason: ledgerRejectionReason,
      reason: valid
          ? wholeNote
                ? 'accepted whole-note geometry score=${finalScore.toStringAsFixed(2)}'
                : 'accepted score=${finalScore.toStringAsFixed(2)} support=${support.total.toStringAsFixed(2)} nonStem=${support.nonStem.toStringAsFixed(2)} attachment=${attachment.type.name}${ledgerPreserved ? ' ledger_preserved' : ''}'
          : (reasons.isEmpty ? 'score below threshold' : reasons.join(', ')),
    );
  }

  bool _isBaseValidNotehead({
    required bool insideStaff,
    required bool ledgerSupported,
    required double morphology,
    required double alignment,
    required bool overlapsClef,
  }) {
    return (insideStaff || ledgerSupported) &&
        morphology >= 0.38 &&
        alignment >= 0.32;
  }

  _SupportScore _computeNoteheadSupportScore({
    required _SymbolGeometry symbol,
    required List<Map<String, dynamic>> allSymbols,
    required List<dynamic> ledgerLines,
    required List<dynamic> stems,
    required List<dynamic> beams,
    required double spacing,
  }) {
    var score = 0.0;
    var nonStem = 0.0;

    void add(double value, {required bool stem}) {
      score += value;
      if (!stem) nonStem += value;
    }

    if (_supportedByLedger(symbol, ledgerLines, spacing: spacing)) {
      add(0.18, stem: false);
    }
    if (_supportedByStem(symbol, stems, spacing: spacing)) score += 0.12;
    if (_supportedByBeam(symbol, beams, spacing: spacing)) {
      add(0.08, stem: false);
    }
    if (_nearSupportedNotehead(symbol, allSymbols, spacing: spacing)) {
      add(0.08, stem: false);
    }
    if (_hasRhythmicNeighbor(symbol, allSymbols, spacing: spacing)) {
      add(0.05, stem: false);
    }
    return _SupportScore(
      total: score.clamp(0.0, 0.36).toDouble(),
      nonStem: nonStem.clamp(0.0, 0.36).toDouble(),
    );
  }

  bool _isWholeNoteShape({
    required _SymbolGeometry symbol,
    required Map<String, dynamic>? staff,
    required double spacing,
    required double morphology,
    required double alignment,
    required double confidence,
    required List<dynamic> stems,
  }) {
    if (staff == null || spacing <= 0) return false;
    if (confidence < 0.68 || morphology < 0.62 || alignment < 0.58) {
      return false;
    }
    if (_supportedByStem(symbol, stems, spacing: spacing)) return false;

    final width = symbol.width;
    final height = symbol.height;
    if (width <= 0 || height <= 0) return false;
    final ratio = width > height ? width / height : height / width;
    if (ratio > 2.05) return false;
    if (width < spacing * 0.55 || width > spacing * 1.95) return false;
    if (height < spacing * 0.40 || height > spacing * 1.55) return false;

    return _insideExtendedStaffRegion(symbol.centerY, staff, spacing);
  }

  bool _isAccidentalClass(String className) {
    return className == 'sharp' ||
        className == 'flat' ||
        className == 'natural';
  }

  List<Map<String, dynamic>> _generateInferredLedgerNoteheads({
    required List<Map<String, dynamic>> validSymbols,
    required List<Map<String, dynamic>> rejectedNoteheads,
    required List<dynamic> ledgerLines,
    required List<dynamic> stems,
    required List<dynamic> validatedStaffs,
  }) {
    final inferred = <Map<String, dynamic>>[];

    for (final ledgerItem in ledgerLines.whereType<Map>()) {
      final ledger = Map<String, dynamic>.from(
        ledgerItem.map((key, value) => MapEntry(key.toString(), value)),
      );
      final staffId = ledger['staffId']?.toString();
      final x1 = _toDouble(ledger['x1']);
      final x2 = _toDouble(ledger['x2']);
      final y = _toDouble(ledger['y']);
      if (staffId == null || x1 == null || x2 == null || y == null) continue;

      final staff = _staffById(validatedStaffs, staffId);
      final spacing =
          _toDouble(staff?['validatedStaffSpacing'] ?? staff?['spacing']) ??
          12.0;
      if (spacing <= 0) continue;

      final ledgerCenterX = (x1 + x2) / 2.0;
      Map<String, dynamic>? supportingStem;
      for (final rawStem in stems.whereType<Map>()) {
        final stem = Map<String, dynamic>.from(
          rawStem.map((key, value) => MapEntry(key.toString(), value)),
        );
        if (stem['staffId']?.toString() != staffId) continue;
        final sx = _toDouble(stem['x']);
        final sy1 = _toDouble(stem['y1']);
        final sy2 = _toDouble(stem['y2']);
        if (sx == null || sy1 == null || sy2 == null) continue;
        final xClose = sx >= x1 - spacing * 1.3 && sx <= x2 + spacing * 1.3;
        final yClose = y >= sy1 - spacing * 0.9 && y <= sy2 + spacing * 0.9;
        if (xClose && yClose) {
          supportingStem = stem;
          break;
        }
      }
      if (supportingStem == null) continue;

      final stemX = _toDouble(supportingStem['x']) ?? ledgerCenterX;
      final centerX = (stemX - ledgerCenterX).abs() <= spacing * 1.3
          ? (stemX + ledgerCenterX) / 2.0
          : ledgerCenterX;

      final candidate = _SymbolGeometry(
        x1: centerX - spacing * 0.52,
        y1: y - spacing * 0.38,
        x2: centerX + spacing * 0.52,
        y2: y + spacing * 0.38,
        centerX: centerX,
        centerY: y,
      );

      final alreadyRepresented =
          validSymbols.any((symbol) {
            if (_symbolClassName(symbol) != 'notehead') return false;
            final geometry = _symbolGeometry(symbol);
            if (geometry == null) return false;
            return (geometry.centerX - candidate.centerX).abs() <=
                    spacing * 0.9 &&
                (geometry.centerY - candidate.centerY).abs() <= spacing * 0.7;
          }) ||
          rejectedNoteheads.any((symbol) {
            final geometry = _symbolGeometry(symbol);
            if (geometry == null) return false;
            return (geometry.centerX - candidate.centerX).abs() <=
                    spacing * 0.55 &&
                (geometry.centerY - candidate.centerY).abs() <= spacing * 0.45;
          }) ||
          inferred.any((symbol) {
            final geometry = _symbolGeometry(symbol);
            if (geometry == null) return false;
            return (geometry.centerX - candidate.centerX).abs() <=
                    spacing * 0.9 &&
                (geometry.centerY - candidate.centerY).abs() <= spacing * 0.7;
          });
      if (alreadyRepresented) continue;

      final ledgerId = ledger['id']?.toString() ?? 'ledger_${inferred.length}';
      final stemId = supportingStem['id']?.toString() ?? 'stem_unknown';
      inferred.add({
        'id': 'inferred_notehead_${inferred.length}',
        'className': 'notehead',
        'centerX': candidate.centerX,
        'centerY': candidate.centerY,
        'x': candidate.centerX,
        'y': candidate.centerY,
        'bbox': [candidate.x1, candidate.y1, candidate.x2, candidate.y2],
        'score': 0.64,
        'confidence': 0.64,
        'symbolState': 'inferred',
        'structuralScore': 0.64,
        'isInferred': true,
        'isRejected': false,
        'inferred': true,
        'inferredReason':
            'validated ledger and stem with missing ONNX notehead',
        'supportingLedgerId': ledgerId,
        'supportingStemId': stemId,
        'supportingStructureIds': [ledgerId, stemId],
        'supportSources': [ledgerId, stemId],
        'rejectionReasons': const <String>[],
        'validation': const {
          'reason': 'inferred from ledger/stem structure',
          'baseValid': true,
          'supportScore': 0.30,
          'nonStemSupportScore': 0.18,
        },
        'validationReason': 'inferred from ledger/stem structure',
        'structuralSupportScore': 0.30,
        'nonStemSupportScore': 0.18,
        'finalValidationScore': 0.64,
      });
    }

    return inferred;
  }

  Map<String, dynamic>? _staffById(List<dynamic> validatedStaffs, String id) {
    for (final item in validatedStaffs) {
      if (item is! Map) continue;
      if (item['id']?.toString() != id) continue;
      return Map<String, dynamic>.from(
        item.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    return null;
  }

  _SymbolAttachmentValidation _validateAccidental({
    required _SymbolGeometry symbol,
    required List<Map<String, dynamic>> validSymbols,
    required List<dynamic> ledgerLines,
    required List<dynamic> validatedStaffs,
    required List<Map<String, dynamic>> semanticRegions,
    required List<Map<String, dynamic>> clefSafetyRegions,
  }) {
    final staff = _nearestStaffForSymbol(symbol, validatedStaffs);
    final spacing =
        _toDouble(staff?['validatedStaffSpacing'] ?? staff?['spacing']) ?? 12.0;
    final semanticRole = _semanticRoleContaining(symbol, semanticRegions);
    if (semanticRole == 'keySignature') {
      return const _SymbolAttachmentValidation(
        valid: true,
        reason: 'key signature semantic region',
      );
    }

    final clefPenalty = computeClefOverlapPenalty(
      symbol: symbol,
      clefSafetyRegions: clefSafetyRegions,
      staffSpacing: spacing,
      support: const _StructuralSupportContext(
        ledger: false,
        edgeStem: false,
        beam: false,
        chord: false,
        rhythmicGrouping: false,
        centerStem: false,
      ),
    );

    final attachedNotehead = validSymbols.any((item) {
      if (_symbolClassName(item) != 'notehead') return false;
      final note = _symbolGeometry(item);
      if (note == null) return false;
      final leftOfNote = symbol.centerX < note.centerX;
      final horizontalDistance = note.centerX - symbol.centerX;
      final verticallyClose =
          (note.centerY - symbol.centerY).abs() <= spacing * 1.35;
      return leftOfNote &&
          horizontalDistance >= spacing * 0.20 &&
          horizontalDistance <= spacing * 3.2 &&
          verticallyClose;
    });
    if (attachedNotehead) {
      return const _SymbolAttachmentValidation(
        valid: true,
        reason: 'attached to validated notehead',
      );
    }

    if (clefPenalty.reasons.isNotEmpty && clefPenalty.penalty >= 0.18) {
      return _SymbolAttachmentValidation(
        valid: false,
        reason: ['unsupported_accidental', ...clefPenalty.reasons].join(', '),
      );
    }

    final ledgerContext =
        _supportedByLedger(symbol, ledgerLines, spacing: spacing) &&
        validSymbols.any((item) {
          if (_symbolClassName(item) != 'notehead') return false;
          final note = _symbolGeometry(item);
          if (note == null) return false;
          return (note.centerX - symbol.centerX).abs() <= spacing * 3.6 &&
              (note.centerY - symbol.centerY).abs() <= spacing * 1.8;
        });
    if (ledgerContext) {
      return const _SymbolAttachmentValidation(
        valid: true,
        reason: 'ledger note accidental context',
      );
    }

    final clusterContext = validSymbols.where((item) {
      final className = _symbolClassName(item);
      if (className != 'notehead' && !_isAccidentalClass(className)) {
        return false;
      }
      final other = _symbolGeometry(item);
      if (other == null) return false;
      return (other.centerX - symbol.centerX).abs() <= spacing * 3.0 &&
          (other.centerY - symbol.centerY).abs() <= spacing * 2.0;
    }).length;

    if (clusterContext >= 2 &&
        _insideExtendedStaffRegion(symbol.centerY, staff, spacing)) {
      return const _SymbolAttachmentValidation(
        valid: true,
        reason: 'musical context cluster',
      );
    }

    return const _SymbolAttachmentValidation(
      valid: false,
      reason: 'no validated note attachment',
    );
  }

  String _symbolClassName(Map<String, dynamic> item) {
    return (item['className'] ?? item['labelName'] ?? item['label'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
  }

  _SymbolGeometry? _symbolGeometry(Map<String, dynamic> item) {
    if (item['bbox'] is List && (item['bbox'] as List).length >= 4) {
      final bbox = List.from(item['bbox']);
      final x1 = _toDouble(bbox[0]);
      final y1 = _toDouble(bbox[1]);
      final x2 = _toDouble(bbox[2]);
      final y2 = _toDouble(bbox[3]);
      if (x1 == null || y1 == null || x2 == null || y2 == null) return null;

      final left = x1 < x2 ? x1 : x2;
      final right = x1 < x2 ? x2 : x1;
      final top = y1 < y2 ? y1 : y2;
      final bottom = y1 < y2 ? y2 : y1;
      return _SymbolGeometry(
        x1: left,
        y1: top,
        x2: right,
        y2: bottom,
        centerX: (left + right) / 2.0,
        centerY: (top + bottom) / 2.0,
      );
    }

    final centerX = _toDouble(item['centerX'] ?? item['x']);
    final centerY = _toDouble(item['centerY'] ?? item['y']);
    if (centerX == null || centerY == null) return null;
    return _SymbolGeometry(
      x1: centerX,
      y1: centerY,
      x2: centerX,
      y2: centerY,
      centerX: centerX,
      centerY: centerY,
    );
  }

  Map<String, dynamic>? _nearestStaffForSymbol(
    _SymbolGeometry symbol,
    List<dynamic> validatedStaffs,
  ) {
    Map<String, dynamic>? best;
    double? bestDistance;

    for (final item in validatedStaffs) {
      if (item is! Map) continue;
      final staff = Map<String, dynamic>.from(
        item.map((key, value) => MapEntry(key.toString(), value)),
      );
      final top = _toDouble(staff['topBoundary']);
      final bottom = _toDouble(staff['bottomBoundary']);
      if (top == null || bottom == null) continue;
      final center = (top + bottom) / 2.0;
      final distance = symbol.centerY >= top && symbol.centerY <= bottom
          ? 0.0
          : (symbol.centerY - center).abs();
      if (bestDistance == null || distance < bestDistance) {
        best = staff;
        bestDistance = distance;
      }
    }

    return best;
  }

  bool _insideAnyStaffRegion(double y, List<dynamic> validatedStaffs) {
    for (final item in validatedStaffs) {
      if (item is! Map) continue;
      final top = _toDouble(item['topBoundary']);
      final bottom = _toDouble(item['bottomBoundary']);
      final spacing = _toDouble(item['spacing']) ?? 12.0;
      if (top == null || bottom == null) continue;
      if (y >= top - spacing * 0.35 && y <= bottom + spacing * 0.35) {
        return true;
      }
    }
    return false;
  }

  bool _insideExtendedStaffRegion(
    double y,
    Map<String, dynamic>? staff,
    double spacing,
  ) {
    if (staff == null) return false;
    final top = _toDouble(staff['topBoundary']);
    final bottom = _toDouble(staff['bottomBoundary']);
    if (top == null || bottom == null) return false;
    return y >= top - spacing * 5.5 && y <= bottom + spacing * 5.5;
  }

  double _noteheadMorphologyScore(_SymbolGeometry symbol, double spacing) {
    final width = symbol.width;
    final height = symbol.height;
    if (width <= 0 || height <= 0 || spacing <= 0) return 0.0;

    final ratio = width > height ? width / height : height / width;
    final ratioScore = (1.0 - ((ratio - 1.25).abs() / 1.25))
        .clamp(0.0, 1.0)
        .toDouble();
    final widthScore =
        (1.0 - ((width - spacing * 0.95).abs() / (spacing * 0.9)))
            .clamp(0.0, 1.0)
            .toDouble();
    final heightScore =
        (1.0 - ((height - spacing * 0.75).abs() / (spacing * 0.75)))
            .clamp(0.0, 1.0)
            .toDouble();

    return (ratioScore * 0.42 + widthScore * 0.30 + heightScore * 0.28)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  double _staffAlignmentScore(
    _SymbolGeometry symbol,
    Map<String, dynamic>? staff,
  ) {
    if (staff == null) return 0.0;
    final rawLines = staff['lines'];
    if (rawLines is! List || rawLines.length < 2) return 0.0;
    final lines = rawLines.map(_toDouble).whereType<double>().toList()..sort();
    if (lines.length < 2) return 0.0;
    final spacing = _toDouble(staff['spacing']) ?? _averageSpacing(lines);
    if (spacing <= 0) return 0.0;

    final anchors = <double>[];
    for (var i = -5; i <= 9; i++) {
      anchors.add(lines.first + spacing * 0.5 * i);
    }

    final nearest = anchors
        .map((anchor) => (anchor - symbol.centerY).abs())
        .fold<double>(
          double.infinity,
          (best, value) => value < best ? value : best,
        );

    return (1.0 - (nearest / (spacing * 0.34))).clamp(0.0, 1.0).toDouble();
  }

  double _averageSpacing(List<double> lines) {
    if (lines.length < 2) return 12.0;
    final spacings = <double>[];
    for (var i = 1; i < lines.length; i++) {
      spacings.add((lines[i] - lines[i - 1]).abs());
    }
    return spacings.reduce((a, b) => a + b) / spacings.length;
  }

  bool _supportedByLedger(
    _SymbolGeometry symbol,
    List<dynamic> ledgerLines, {
    double? spacing,
  }) {
    final unit = spacing ?? 12.0;
    for (final item in ledgerLines) {
      if (item is! Map) continue;
      final x1 = _toDouble(item['x1']);
      final x2 = _toDouble(item['x2']);
      final y = _toDouble(item['y']);
      if (x1 == null || x2 == null || y == null) continue;

      final yClose = (symbol.centerY - y).abs() <= unit * 1.35;
      final xClose =
          symbol.centerX >= x1 - unit * 1.8 &&
          symbol.centerX <= x2 + unit * 1.8;
      if (yClose && xClose) return true;
    }
    return false;
  }

  double _ledgerContinuitySupportForNotehead({
    required _SymbolGeometry symbol,
    required List<dynamic> ledgerLines,
    required double spacing,
  }) {
    final unit = spacing > 0 ? spacing : 12.0;
    final matchingLedgers = <_SymbolGeometry>[];

    for (final item in ledgerLines) {
      if (item is! Map) continue;
      final x1 = _toDouble(item['x1']);
      final x2 = _toDouble(item['x2']);
      final y = _toDouble(item['y']);
      if (x1 == null || x2 == null || y == null) continue;

      final yClose = (symbol.centerY - y).abs() <= unit * 1.35;
      final xClose =
          symbol.centerX >= x1 - unit * 1.8 &&
          symbol.centerX <= x2 + unit * 1.8;
      if (!yClose || !xClose) continue;

      matchingLedgers.add(
        _SymbolGeometry(
          x1: x1 < x2 ? x1 : x2,
          y1: y,
          x2: x1 < x2 ? x2 : x1,
          y2: y,
          centerX: (x1 + x2) / 2.0,
          centerY: y,
        ),
      );
    }

    if (matchingLedgers.isEmpty) return 0.0;

    final hasNeighboringLedger = ledgerLines.whereType<Map>().any((item) {
      final x1 = _toDouble(item['x1']);
      final x2 = _toDouble(item['x2']);
      final y = _toDouble(item['y']);
      if (x1 == null || x2 == null || y == null) return false;
      final centerX = (x1 + x2) / 2.0;
      final dx = (centerX - symbol.centerX).abs();
      final dy = (y - symbol.centerY).abs();
      final supportsCurrentNote =
          dy <= unit * 0.35 &&
          symbol.centerX >= x1 - unit * 1.8 &&
          symbol.centerX <= x2 + unit * 1.8;
      if (supportsCurrentNote) return false;
      final xAligned = dx <= unit * 1.6;
      final yStepAligned = (1 <= dy / unit && dy / unit <= 3.2) ||
          dy <= unit * 0.75;
      return xAligned && yStepAligned;
    });

    return hasNeighboringLedger ? 1.0 : 0.0;
  }

  String _ledgerRejectionReason({
    required bool ledgerSupported,
    required bool semanticConflict,
    required bool clefCoreConflict,
    required double morphology,
    required double alignment,
    required double supportScore,
  }) {
    if (!ledgerSupported) return 'no ledger support';
    if (semanticConflict || clefCoreConflict) return 'semantic conflict';
    if (morphology < 0.34 || alignment < 0.26) return 'geometry mismatch';
    if (supportScore < 0.12) return 'weak structure support';
    return 'virtual alignment fail';
  }

  bool _supportedByStem(
    _SymbolGeometry symbol,
    List<dynamic> stems, {
    double? spacing,
  }) {
    final unit = spacing ?? 12.0;
    for (final item in stems) {
      if (item is! Map) continue;
      final x = _toDouble(item['x']);
      final y1 = _toDouble(item['y1']);
      final y2 = _toDouble(item['y2']);
      if (x == null || y1 == null || y2 == null) continue;

      final xClose =
          x >= symbol.x1 - unit * 0.65 && x <= symbol.x2 + unit * 0.65;
      final yClose =
          y2 >= symbol.y1 - unit * 0.9 && y1 <= symbol.y2 + unit * 4.2;
      if (xClose && yClose) return true;
    }
    return false;
  }

  _StemAttachmentAnalysis _analyzeStemAttachment(
    _SymbolGeometry notehead,
    List<dynamic> stems, {
    required double spacing,
  }) {
    final stem = _supportingStemForNotehead(notehead, stems, spacing: spacing);
    if (stem == null) {
      return const _StemAttachmentAnalysis(
        type: StemAttachmentType.unknown,
        stem: null,
        stemCenterX: null,
      );
    }

    final stemGeometry = _stemGeometry(stem, spacing: spacing);
    if (stemGeometry == null) {
      return _StemAttachmentAnalysis(
        type: StemAttachmentType.unknown,
        stem: stem,
        stemCenterX: null,
      );
    }

    return _StemAttachmentAnalysis(
      type: computeStemAttachmentType(notehead, stemGeometry),
      stem: stem,
      stemCenterX: stemGeometry.centerX,
    );
  }

  StemAttachmentType computeStemAttachmentType(
    _SymbolGeometry noteheadBBox,
    _SymbolGeometry stemBBox,
  ) {
    final width = noteheadBBox.width;
    if (width <= 0) return StemAttachmentType.unknown;

    final stemCenterX = stemBBox.centerX;
    if (stemCenterX.isNaN || stemCenterX.isInfinite) {
      return StemAttachmentType.unknown;
    }

    final centerLeft = noteheadBBox.x1 + width * 0.30;
    final centerRight = noteheadBBox.x1 + width * 0.70;
    if (centerLeft >= centerRight) return StemAttachmentType.unknown;

    if (stemCenterX < centerLeft) return StemAttachmentType.leftEdge;
    if (stemCenterX > centerRight) return StemAttachmentType.rightEdge;
    return StemAttachmentType.center;
  }

  Map<String, dynamic>? _supportingStemForNotehead(
    _SymbolGeometry notehead,
    List<dynamic> stems, {
    required double spacing,
  }) {
    Map<String, dynamic>? bestStem;
    double bestDistance = double.infinity;
    final unit = spacing > 0 ? spacing : 12.0;

    for (final item in stems) {
      if (item is! Map) continue;
      final stem = Map<String, dynamic>.from(
        item.map((key, value) => MapEntry(key.toString(), value)),
      );
      final stemGeometry = _stemGeometry(stem, spacing: unit);
      if (stemGeometry == null) continue;

      final xClose =
          stemGeometry.centerX >= notehead.x1 - unit * 0.65 &&
          stemGeometry.centerX <= notehead.x2 + unit * 0.65;
      final yIntersects =
          stemGeometry.y2 >= notehead.y1 - unit * 0.9 &&
          stemGeometry.y1 <= notehead.y2 + unit * 4.2;
      if (!xClose || !yIntersects) continue;

      final edgeDistance = [
        (stemGeometry.centerX - notehead.x1).abs(),
        (stemGeometry.centerX - notehead.x2).abs(),
      ].reduce((a, b) => a < b ? a : b);
      final verticalOverlapPenalty =
          stemGeometry.y1 <= notehead.y2 && stemGeometry.y2 >= notehead.y1
          ? 0.0
          : unit * 0.25;
      final distance = edgeDistance + verticalOverlapPenalty;

      if (distance < bestDistance) {
        bestDistance = distance;
        bestStem = stem;
      }
    }

    return bestStem;
  }

  _SymbolGeometry? _stemGeometry(
    Map<String, dynamic> stem, {
    required double spacing,
  }) {
    final rawX1 = _toDouble(stem['x1'] ?? stem['left'] ?? stem['xmin']);
    final rawX2 = _toDouble(stem['x2'] ?? stem['right'] ?? stem['xmax']);
    final rawY1 = _toDouble(stem['y1'] ?? stem['top'] ?? stem['ymin']);
    final rawY2 = _toDouble(stem['y2'] ?? stem['bottom'] ?? stem['ymax']);
    final x = _toDouble(stem['x'] ?? stem['centerX']);

    if (rawY1 == null || rawY2 == null) return null;
    if (x == null && (rawX1 == null || rawX2 == null)) return null;

    final halfWidth = (spacing > 0 ? spacing : 12.0) * 0.08;
    final left = rawX1 ?? (x! - halfWidth);
    final right = rawX2 ?? (x! + halfWidth);
    final top = rawY1 < rawY2 ? rawY1 : rawY2;
    final bottom = rawY1 < rawY2 ? rawY2 : rawY1;
    final normalizedLeft = left < right ? left : right;
    final normalizedRight = left < right ? right : left;

    if (bottom <= top || normalizedRight < normalizedLeft) return null;

    return _SymbolGeometry(
      x1: normalizedLeft,
      y1: top,
      x2: normalizedRight,
      y2: bottom,
      centerX: (normalizedLeft + normalizedRight) / 2.0,
      centerY: (top + bottom) / 2.0,
    );
  }

  bool _hasStemDirectionMismatch({
    required _SymbolGeometry notehead,
    required Map<String, dynamic>? stem,
    required StemAttachmentType attachmentType,
  }) {
    if (stem == null) return false;
    if (attachmentType != StemAttachmentType.leftEdge &&
        attachmentType != StemAttachmentType.rightEdge) {
      return false;
    }

    final y1 = _toDouble(stem['y1'] ?? stem['top'] ?? stem['ymin']);
    final y2 = _toDouble(stem['y2'] ?? stem['bottom'] ?? stem['ymax']);
    if (y1 == null || y2 == null) return false;

    final top = y1 < y2 ? y1 : y2;
    final bottom = y1 < y2 ? y2 : y1;
    final extendsUp = top < notehead.centerY && bottom <= notehead.y2;
    final extendsDown = bottom > notehead.centerY && top >= notehead.y1;

    if (extendsUp && attachmentType == StemAttachmentType.leftEdge) return true;
    if (extendsDown && attachmentType == StemAttachmentType.rightEdge)
      return true;
    return false;
  }

  bool _supportedByBeam(
    _SymbolGeometry symbol,
    List<dynamic> beams, {
    double? spacing,
  }) {
    final unit = spacing ?? 12.0;
    for (final item in beams) {
      if (item is! Map) continue;
      final x1 = _toDouble(item['x1']);
      final x2 = _toDouble(item['x2']);
      final y = _toDouble(item['y']);
      if (x1 == null || x2 == null || y == null) continue;
      final xClose = symbol.centerX >= x1 - unit && symbol.centerX <= x2 + unit;
      final yClose = (symbol.centerY - y).abs() <= unit * 5.0;
      if (xClose && yClose) return true;
    }
    return false;
  }

  bool _nearSupportedNotehead(
    _SymbolGeometry symbol,
    List<Map<String, dynamic>> symbols, {
    double? spacing,
  }) {
    final unit = spacing ?? 12.0;
    return symbols.any((item) {
      if (_symbolClassName(item) != 'notehead') return false;
      final notehead = _symbolGeometry(item);
      if (notehead == null) return false;
      if ((notehead.centerX - symbol.centerX).abs() < 0.01 &&
          (notehead.centerY - symbol.centerY).abs() < 0.01) {
        return false;
      }
      return (notehead.centerX - symbol.centerX).abs() <= unit * 1.2 &&
          (notehead.centerY - symbol.centerY).abs() <= unit * 2.0;
    });
  }

  bool _hasRhythmicNeighbor(
    _SymbolGeometry symbol,
    List<Map<String, dynamic>> symbols, {
    required double spacing,
  }) {
    return symbols.any((item) {
      if (_symbolClassName(item) != 'notehead') return false;
      final other = _symbolGeometry(item);
      if (other == null) return false;
      if ((other.centerX - symbol.centerX).abs() < 0.01 &&
          (other.centerY - symbol.centerY).abs() < 0.01) {
        return false;
      }
      final dx = (other.centerX - symbol.centerX).abs();
      if (dx <= spacing * 1.2 || dx > spacing * 8.0) return false;
      return (other.centerY - symbol.centerY).abs() <= spacing * 4.0;
    });
  }

  Map<String, dynamic>? _regionContaining(
    _SymbolGeometry symbol,
    List<Map<String, dynamic>> regions,
  ) {
    for (final region in regions) {
      final x1 = _toDouble(region['x1']);
      final x2 = _toDouble(region['x2']);
      final y1 = _toDouble(region['y1']);
      final y2 = _toDouble(region['y2']);
      if (x1 == null || x2 == null || y1 == null || y2 == null) continue;
      if (symbol.centerX >= x1 &&
          symbol.centerX <= x2 &&
          symbol.centerY >= y1 &&
          symbol.centerY <= y2) {
        return region;
      }
    }
    return null;
  }

  String? _semanticRoleContaining(
    _SymbolGeometry symbol,
    List<Map<String, dynamic>> regions,
  ) {
    final region = _regionContaining(symbol, regions);
    return region?['semanticRole']?.toString();
  }

  Map<String, dynamic>? _penalizingSemanticRegionContaining(
    _SymbolGeometry symbol,
    List<Map<String, dynamic>> regions,
  ) {
    for (final region in regions) {
      final role = region['semanticRole']?.toString();
      if (role == 'keySignature') continue;
      if (_regionContaining(symbol, [region]) != null) return region;
    }
    return null;
  }

  bool _insideClefCore(
    _SymbolGeometry symbol,
    Map<String, dynamic> clefSafetyRegion,
  ) {
    final x1 = _toDouble(clefSafetyRegion['coreX1']);
    final x2 = _toDouble(clefSafetyRegion['coreX2']);
    final y1 = _toDouble(clefSafetyRegion['coreY1']);
    final y2 = _toDouble(clefSafetyRegion['coreY2']);
    if (x1 == null || x2 == null || y1 == null || y2 == null) return false;
    final core = _SymbolGeometry(
      x1: x1 < x2 ? x1 : x2,
      y1: y1 < y2 ? y1 : y2,
      x2: x1 < x2 ? x2 : x1,
      y2: y1 < y2 ? y2 : y1,
      centerX: (x1 + x2) / 2.0,
      centerY: (y1 + y2) / 2.0,
    );
    return _iou(symbol, core) >= 0.08 || _centerInside(symbol, core);
  }

  _ClefOverlapPenalty computeClefOverlapPenalty({
    required _SymbolGeometry symbol,
    required List<Map<String, dynamic>> clefSafetyRegions,
    required double staffSpacing,
    required _StructuralSupportContext support,
  }) {
    final spacing = staffSpacing > 0 ? staffSpacing : 12.0;

    for (final region in clefSafetyRegions) {
      final core = _regionGeometry(
        region,
        x1Key: 'coreX1',
        x2Key: 'coreX2',
        y1Key: 'coreY1',
        y2Key: 'coreY2',
      );
      final expansion = _regionGeometry(
        region,
        x1Key: 'expansionX1',
        x2Key: 'expansionX2',
        y1Key: 'expansionY1',
        y2Key: 'expansionY2',
      );
      final transition = _regionGeometry(
        region,
        x1Key: 'transitionX1',
        x2Key: 'transitionX2',
        y1Key: 'transitionY1',
        y2Key: 'transitionY2',
      );
      if (core == null || expansion == null || transition == null) continue;

      final inCore = _iou(symbol, core) >= 0.06 || _centerInside(symbol, core);
      final inExpansion =
          !inCore &&
          (_iou(symbol, expansion) >= 0.04 || _centerInside(symbol, expansion));
      final inTransition = _centerInside(symbol, transition);
      if (!inCore && !inExpansion && !inTransition) continue;

      final hasProtectiveSupport =
          support.ledger || support.edgeStem || support.beam || support.chord;
      final hasCoreStructuralSupport = support.ledger || support.beam;
      final outsideTransition = symbol.centerX > transition.x2 + spacing * 0.35;
      if (outsideTransition) {
        return const _ClefOverlapPenalty(
          penalty: 0.0,
          reasons: [],
          coreRejected: false,
          transitionPenalty: false,
          validNearClef: false,
        );
      }

      if (hasProtectiveSupport && !inCore) {
        return const _ClefOverlapPenalty(
          penalty: 0.0,
          reasons: [],
          coreRejected: false,
          transitionPenalty: false,
          validNearClef: true,
        );
      }

      final reasons = <String>[];
      var penalty = 0.0;

      if (inCore) {
        penalty += hasCoreStructuralSupport ? 0.38 : 0.68;
        reasons.add('overlap_core');
        if (!hasCoreStructuralSupport) {
          penalty += 0.14;
          reasons.add('clef_core_dominance');
        }
        if (region['sourceClass']?.toString() == 'bass_clef') {
          penalty += 0.06;
          reasons.add('bass_clef_core');
        }
      } else if (inExpansion) {
        penalty += hasProtectiveSupport ? 0.10 : 0.34;
        reasons.add('clef_expansion_overlap');
      } else if (inTransition) {
        penalty += hasProtectiveSupport ? 0.06 : 0.18;
        reasons.add('clef_transition_penalty');
      }

      if (support.centerStem && (inCore || inExpansion || inTransition)) {
        penalty += 0.22;
        reasons.add('center_attachment_near_clef');
      }

      if (!support.rhythmicGrouping && !hasProtectiveSupport) {
        penalty += inCore ? 0.18 : 0.08;
        reasons.add('no rhythmic grouping');
      }

      return _ClefOverlapPenalty(
        penalty: penalty.clamp(0.0, 0.92).toDouble(),
        reasons: reasons,
        coreRejected: inCore && penalty >= 0.56,
        transitionPenalty: inTransition,
        validNearClef: hasProtectiveSupport && penalty < 0.20,
      );
    }

    return const _ClefOverlapPenalty(
      penalty: 0.0,
      reasons: [],
      coreRejected: false,
      transitionPenalty: false,
      validNearClef: false,
    );
  }

  _SymbolGeometry? _regionGeometry(
    Map<String, dynamic> region, {
    required String x1Key,
    required String x2Key,
    required String y1Key,
    required String y2Key,
  }) {
    final x1 = _toDouble(region[x1Key]);
    final x2 = _toDouble(region[x2Key]);
    final y1 = _toDouble(region[y1Key]);
    final y2 = _toDouble(region[y2Key]);
    if (x1 == null || x2 == null || y1 == null || y2 == null) return null;
    final left = x1 < x2 ? x1 : x2;
    final right = x1 < x2 ? x2 : x1;
    final top = y1 < y2 ? y1 : y2;
    final bottom = y1 < y2 ? y2 : y1;
    return _SymbolGeometry(
      x1: left,
      y1: top,
      x2: right,
      y2: bottom,
      centerX: (left + right) / 2.0,
      centerY: (top + bottom) / 2.0,
    );
  }

  Set<Map<String, dynamic>> _likelyTimeSignatureNoteheads({
    required List<Map<String, dynamic>> noteheadCandidates,
    required List<Map<String, dynamic>> semanticRegions,
    required List<dynamic> stems,
    required List<dynamic> beams,
  }) {
    final likely = <Map<String, dynamic>>{};

    for (final region in semanticRegions) {
      final role = region['semanticRole']?.toString();
      if (role != null && role != 'timeSignature') continue;

      final regionSpacing =
          ((_toDouble(region['x2']) ?? 0) - (_toDouble(region['x1']) ?? 0)) /
          (role == 'timeSignature' ? 2.7 : 6.0);
      final spacing = regionSpacing > 0 ? regionSpacing : 12.0;
      final inside = noteheadCandidates.where((item) {
        final geometry = _symbolGeometry(item);
        if (geometry == null || _regionContaining(geometry, [region]) == null) {
          return false;
        }
        final hasStructure =
            _supportedByStem(geometry, stems, spacing: spacing) ||
            _supportedByBeam(geometry, beams, spacing: spacing);
        return !hasStructure;
      }).toList();

      for (var i = 0; i < inside.length; i++) {
        final a = _symbolGeometry(inside[i]);
        if (a == null) continue;
        final stack = inside.where((item) {
          final b = _symbolGeometry(item);
          if (b == null) return false;
          return (a.centerX - b.centerX).abs() <= spacing * 1.15 &&
              (a.centerY - b.centerY).abs() >= spacing * 0.65 &&
              (a.centerY - b.centerY).abs() <= spacing * 4.8;
        }).toList();
        if (stack.length >= 1) {
          likely.add(inside[i]);
          likely.addAll(stack);
        }
      }
    }

    return likely;
  }

  bool _centerInside(_SymbolGeometry inner, _SymbolGeometry outer) {
    return inner.centerX >= outer.x1 &&
        inner.centerX <= outer.x2 &&
        inner.centerY >= outer.y1 &&
        inner.centerY <= outer.y2;
  }

  double _iou(_SymbolGeometry a, _SymbolGeometry b) {
    final left = a.x1 > b.x1 ? a.x1 : b.x1;
    final top = a.y1 > b.y1 ? a.y1 : b.y1;
    final right = a.x2 < b.x2 ? a.x2 : b.x2;
    final bottom = a.y2 < b.y2 ? a.y2 : b.y2;
    final intersection =
        ((right - left) > 0 ? right - left : 0.0) *
        ((bottom - top) > 0 ? bottom - top : 0.0);
    if (intersection <= 0) return 0;

    final areaA =
        ((a.x2 - a.x1) > 0 ? a.x2 - a.x1 : 0.0) *
        ((a.y2 - a.y1) > 0 ? a.y2 - a.y1 : 0.0);
    final areaB =
        ((b.x2 - b.x1) > 0 ? b.x2 - b.x1 : 0.0) *
        ((b.y2 - b.y1) > 0 ? b.y2 - b.y1 : 0.0);
    final union = areaA + areaB - intersection;
    if (union <= 0) return 0;
    return intersection / union;
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.backgroundSecondary,
                AppColors.background,
                AppColors.surface,
              ],
            ),
          ),
          child: Column(
            children: [
              _ProcessingHeader(
                helpTourKey: _processingHelpTourKey,
                onBackTap: () => Navigator.pop(context),
                onHelpTap: () {
                  TutorialService.showHowToUse(
                    context,
                    page: TutorialPage.processingPage,
                    onStartTour: () => TutorialService.showProcessingGuide(
                      context,
                      _processingTourKeys,
                    ),
                  );
                },
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      /// Top summary card with thumbnail, status, and progress.
                      TutorialService.showcase(
                        key: _processingProgressTourKey,
                        title: 'Reading Progress',
                        description:
                            'This shows how far STALA has read your sheet and what it is doing now.',
                        child: _ProcessingSummaryCard(
                          progressValue: _progressValue,
                          title: _hasProcessingFailed
                              ? 'Could Not Read Sheet'
                              : _isProcessingFinished
                              ? 'Tablature Ready'
                              : 'Reading Your Music',
                          subtitle: _statusMessage,
                          imagePath: widget.croppedImagePath,
                          completedCount: _completedStageCount,
                          totalCount: _stages.length,
                          isFinished: _isProcessingFinished,
                          hasFailed: _hasProcessingFailed,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Current Steps',
                        style: AppTextStyles.sectionTitle.copyWith(
                          fontSize: 20,
                        ),
                      ),
                      const SizedBox(height: 12),

                      /// Scrollable list of pipeline stage cards.
                      Expanded(
                        child: TutorialService.showcase(
                          key: _processingStepsTourKey,
                          title: 'Reading Steps',
                          description:
                              'These steps show the path from your sheet image to the final guitar tab.',
                          child: ListView.separated(
                            physics: const BouncingScrollPhysics(),
                            itemCount: _stages.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final stage = _stages[index];
                              return _ProcessingStageCard(
                                stage: stage,
                                isActive:
                                    index == _activeStageIndex &&
                                    !_isProcessingFinished &&
                                    !_hasProcessingFailed,
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              /// Footer reacts to three states:
              /// running, failed, and completed.
              TutorialService.showcase(
                key: _processingFooterTourKey,
                title: 'Next Step',
                description:
                    'When reading is finished, use this area to open the result or try again if needed.',
                child: _ProcessingFooter(
                  isFinished: _isProcessingFinished,
                  hasFailed: _hasProcessingFailed,
                  onRetry: _retryProcessing,
                  onContinue: _showNextStepMessage,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<SymbolClassItem> _parseClassItems(dynamic rawDetections) {
    if (rawDetections is! List) return const [];

    final List<SymbolClassItem> items = [];

    for (final item in rawDetections) {
      if (item is! Map) continue;

      final map = Map<String, dynamic>.from(
        item.map((key, value) => MapEntry(key.toString(), value)),
      );

      final className =
          map['className']?.toString() ??
          map['labelName']?.toString() ??
          map['label']?.toString() ??
          'unknown';

      final score = _toDouble(map['score'] ?? map['confidence']);

      double? centerX;
      double? centerY;
      List<double>? bbox;

      if (map['bbox'] is List && (map['bbox'] as List).length >= 4) {
        final rawBbox = List.from(map['bbox']);
        final x1 = _toDouble(rawBbox[0]);
        final y1 = _toDouble(rawBbox[1]);
        final x2 = _toDouble(rawBbox[2]);
        final y2 = _toDouble(rawBbox[3]);

        if (x1 != null && y1 != null && x2 != null && y2 != null) {
          bbox = [x1, y1, x2, y2];
          centerX = (x1 + x2) / 2.0;
          centerY = (y1 + y2) / 2.0;
        }
      }

      centerX ??= _toDouble(map['centerX']);
      centerY ??= _toDouble(map['centerY']);

      if (centerX == null || centerY == null) continue;

      items.add(
        SymbolClassItem(
          className: className,
          x: centerX,
          y: centerY,
          score: score,
          bbox: bbox,
          symbolState: SymbolState.fromValue(map['symbolState']),
          validationReason: map['validationReason']?.toString(),
          inferredReason: map['inferredReason']?.toString(),
        ),
      );
    }

    return _sortSymbolsTopLeftToBottomRight(items);
  }

  List<SymbolClassItem> _sortSymbolsTopLeftToBottomRight(
    List<SymbolClassItem> items,
  ) {
    final sorted = List<SymbolClassItem>.from(items);

    const double rowTolerance = 12.0;

    sorted.sort((a, b) {
      final yDiff = (a.y - b.y).abs();

      if (yDiff <= rowTolerance) {
        return a.x.compareTo(b.x);
      }

      return a.y.compareTo(b.y);
    });

    return sorted;
  }

  List<LedgerLineViewItem> _parseConfirmedLedgerLines(
    dynamic rawLedgerLines,
    List<StaffTranslateGroup> groups,
  ) {
    if (rawLedgerLines is! List) return const [];

    final result = <LedgerLineViewItem>[];

    for (final item in rawLedgerLines) {
      if (item is! Map) continue;

      final map = Map<String, dynamic>.from(
        item.map((key, value) => MapEntry(key.toString(), value)),
      );

      final staffId = map['staffId']?.toString();
      final x1 = _toDouble(map['x1']);
      final x2 = _toDouble(map['x2']);
      final y = _toDouble(map['y']);

      if (staffId == null || x1 == null || x2 == null || y == null) continue;

      result.add(LedgerLineViewItem(staffId: staffId, x1: x1, x2: x2, y: y));
    }

    return result;
  }
}

/// Top app header for the processing page.
class _ProcessingHeader extends StatelessWidget {
  final GlobalKey helpTourKey;
  final VoidCallback onBackTap;
  final VoidCallback onHelpTap;

  const _ProcessingHeader({
    required this.helpTourKey,
    required this.onBackTap,
    required this.onHelpTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          _HeaderCircleButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: onBackTap,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Reading Sheet',
              style: AppTextStyles.sectionTitle.copyWith(fontSize: 20),
            ),
          ),
          TutorialService.showcase(
            key: helpTourKey,
            title: 'Need Processing Help?',
            description:
                'Tap this if you want a quick reminder about what this screen is doing.',
            targetShapeBorder: const CircleBorder(),
            child: _HeaderCircleButton(
              icon: Icons.help_outline_rounded,
              onTap: onHelpTap,
            ),
          ),
        ],
      ),
    );
  }
}

/// Top summary card showing:
/// - source image thumbnail
/// - overall processing state
/// - current message
/// - progress bar and completed count
class _ProcessingSummaryCard extends StatelessWidget {
  final double progressValue;
  final String title;
  final String subtitle;
  final String imagePath;
  final int completedCount;
  final int totalCount;
  final bool isFinished;
  final bool hasFailed;

  const _ProcessingSummaryCard({
    required this.progressValue,
    required this.title,
    required this.subtitle,
    required this.imagePath,
    required this.completedCount,
    required this.totalCount,
    required this.isFinished,
    required this.hasFailed,
  });

  Color _progressColor() {
    if (hasFailed) return AppColors.accentSoft;
    if (isFinished) return AppColors.success;
    return AppColors.accent;
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = !isFinished && !hasFailed;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 82,
              height: 100,
              color: AppColors.card,
              child: Image.file(
                File(imagePath),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  return const Center(
                    child: Icon(
                      Icons.image_outlined,
                      color: AppColors.textSecondary,
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatusPill(
                  label: hasFailed
                      ? 'Needs Retry'
                      : isFinished
                      ? 'Ready'
                      : 'Working',
                  icon: hasFailed
                      ? Icons.error_outline_rounded
                      : isFinished
                      ? Icons.check_circle_outline_rounded
                      : Icons.sync_rounded,
                  accentColor: hasFailed
                      ? AppColors.accentSoft
                      : isFinished
                      ? AppColors.success
                      : AppColors.warning,
                  animate: isRunning,
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: AppTextStyles.cardTitle.copyWith(fontSize: 18),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: AppTextStyles.bodySecondary.copyWith(
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                if (isRunning) ...[
                  const _RunningActivityIndicator(),
                  const SizedBox(height: 12),
                ],
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progressValue,
                    minHeight: 8,
                    backgroundColor: AppColors.border,
                    valueColor: AlwaysStoppedAnimation<Color>(_progressColor()),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$completedCount of $totalCount steps complete',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Single stage card inside the pipeline list.
///
/// Shows:
/// - stage order
/// - functional icon
/// - title and explanation
/// - current status marker
class _ProcessingStageCard extends StatelessWidget {
  final ProcessingStageItem stage;
  final bool isActive;

  const _ProcessingStageCard({required this.stage, required this.isActive});

  Color _statusColor() {
    switch (stage.status) {
      case ProcessingStageStatus.pending:
        return AppColors.textMuted;
      case ProcessingStageStatus.active:
        return AppColors.warning;
      case ProcessingStageStatus.completed:
        return AppColors.success;
      case ProcessingStageStatus.failed:
        return AppColors.accentSoft;
    }
  }

  IconData _statusIcon() {
    switch (stage.status) {
      case ProcessingStageStatus.pending:
        return Icons.schedule_rounded;
      case ProcessingStageStatus.active:
        return Icons.autorenew_rounded;
      case ProcessingStageStatus.completed:
        return Icons.check_circle_rounded;
      case ProcessingStageStatus.failed:
        return Icons.error_rounded;
    }
  }

  String _statusLabel() {
    switch (stage.status) {
      case ProcessingStageStatus.pending:
        return 'Waiting';
      case ProcessingStageStatus.active:
        return 'Working';
      case ProcessingStageStatus.completed:
        return 'Done';
      case ProcessingStageStatus.failed:
        return 'Failed';
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isActive ? AppColors.card : const Color(0xFF101C31),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isActive
              ? statusColor.withValues(alpha: 0.55)
              : Colors.white.withValues(alpha: 0.04),
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: statusColor.withValues(alpha: 0.10),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(stage.icon, color: statusColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stage.title,
                  style: AppTextStyles.cardTitle.copyWith(fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  stage.subtitle,
                  style: AppTextStyles.bodySecondary.copyWith(
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            children: [
              isActive
                  ? _RotatingStatusIcon(
                      icon: _statusIcon(),
                      color: statusColor,
                      size: 20,
                    )
                  : Icon(_statusIcon(), size: 20, color: statusColor),
              const SizedBox(height: 6),
              Text(
                _statusLabel(),
                style: AppTextStyles.caption.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RunningActivityIndicator extends StatefulWidget {
  const _RunningActivityIndicator();

  @override
  State<_RunningActivityIndicator> createState() =>
      _RunningActivityIndicatorState();
}

class _RunningActivityIndicatorState extends State<_RunningActivityIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        return SizedBox(
          height: 18,
          child: Row(
            children: List.generate(4, (index) {
              final offset = (index / 4.0);
              final value = ((_pulse.value + offset) % 1.0);
              final height = 6.0 + (value * 12.0);

              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: index == 3 ? 0 : 6),
                  child: Align(
                    alignment: Alignment.center,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      height: height,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(
                          alpha: 0.28 + (value * 0.42),
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

class _RotatingStatusIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  final double size;

  const _RotatingStatusIcon({
    required this.icon,
    required this.color,
    this.size = 24,
  });

  @override
  State<_RotatingStatusIcon> createState() => _RotatingStatusIconState();
}

class _RotatingStatusIconState extends State<_RotatingStatusIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: Icon(widget.icon, color: widget.color, size: widget.size),
    );
  }
}

/// Footer action area.
///
/// States:
/// - running: informational disabled label
/// - failed: retry button
/// - finished: continue button
class _ProcessingFooter extends StatelessWidget {
  final bool isFinished;
  final bool hasFailed;
  final VoidCallback onRetry;
  final VoidCallback onContinue;

  const _ProcessingFooter({
    required this.isFinished,
    required this.hasFailed,
    required this.onRetry,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: hasFailed
                ? _FooterActionButton(
                    icon: Icons.refresh_rounded,
                    label: 'Retry',
                    onTap: onRetry,
                    backgroundColor: AppColors.card,
                    foregroundColor: AppColors.warning,
                  )
                : isFinished
                ? _FooterActionButton(
                    icon: Icons.arrow_forward_rounded,
                    label: 'Review Result',
                    onTap: onContinue,
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.textPrimary,
                  )
                : const _FooterInfoLabel(
                    icon: Icons.auto_awesome_rounded,
                    label: 'Keep this screen open while STALA reads the sheet.',
                  ),
          ),
        ],
      ),
    );
  }
}

/// Shared circular header button used for back navigation.
class _HeaderCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HeaderCircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0x220B162B),
        border: Border.all(color: AppColors.border),
      ),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 19, color: AppColors.textSecondary),
      ),
    );
  }
}

/// Small pill that summarizes the overall processing state.
class _StatusPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accentColor;
  final bool animate;

  const _StatusPill({
    required this.label,
    required this.icon,
    required this.accentColor,
    this.animate = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          animate
              ? _RotatingStatusIcon(icon: icon, color: accentColor, size: 15)
              : Icon(icon, size: 15, color: accentColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: accentColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Reusable tappable footer button for retry and continue actions.
class _FooterActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color backgroundColor;
  final Color foregroundColor;

  const _FooterActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          height: 54,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: foregroundColor, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: AppTextStyles.button.copyWith(color: foregroundColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Passive footer label shown while the pipeline is still running.
class _FooterInfoLabel extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FooterInfoLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 19),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySecondary.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

<div style="page-break-after: always;"></div>

# File 4 — fretboard_mapping_service.dart

## Full Path

```text
D:\MyApps\AndroidStudio_Folder\stala_app\lib\services\fretboard_mapping_service.dart
```

## Purpose

This file maps interpreted musical pitches and pitch groups to possible guitar string-and-fret positions under standard tuning. It supports the thesis objective of translating staff notation into playable guitar tablature candidates. It is important because it forms the bridge between symbolic pitch recognition and guitar-specific tab placement.

## Full Source Code

```dart
import 'musical_interpretation_service.dart';

class GuitarPosition {
  final int stringNumber; // 1 = high E, 6 = low E
  final int fret;
  final String pitch;

  const GuitarPosition({
    required this.stringNumber,
    required this.fret,
    required this.pitch,
  });
}

class FretboardCandidate {
  final String label;
  final List<GuitarPosition> positions;

  const FretboardCandidate({required this.label, required this.positions});
}

class FretboardMappedEvent {
  final int eventIndex;
  final String label;
  final List<String> pitches;
  final String? measureId;
  final int? measureIndex;
  final double? sourceX;
  final List<FretboardCandidate> candidates;

  const FretboardMappedEvent({
    required this.eventIndex,
    required this.label,
    required this.pitches,
    this.measureId,
    this.measureIndex,
    this.sourceX,
    required this.candidates,
  });
}

class FretboardMappedLine {
  final String id;
  final String title;
  final List<FretboardMappedEvent> events;

  const FretboardMappedLine({
    required this.id,
    required this.title,
    required this.events,
  });
}

class FretboardMappingResult {
  final List<FretboardMappedLine> lines;

  const FretboardMappingResult({required this.lines});
}

class FretboardMappingService {
  static const int maxFret = 24;
  static const int _maxChordPitches = 6;
  static const int _maxPositionsPerPitch = 4;
  static const int _maxMultiPitchCandidates = 240;

  // Standard tuning:
  // string 1 = high E4, string 6 = low E2
  static const Map<int, int> _openStringMidi = {
    1: 64, // E4
    2: 59, // B3
    3: 55, // G3
    4: 50, // D3
    5: 45, // A2
    6: 40, // E2
  };

  FretboardMappingResult mapInterpretation({
    required MusicalInterpretationResult interpretation,
  }) {
    final lines = [
      _mapLine(interpretation.grandStaffLine),
      _mapLine(interpretation.trebleOnlyLine),
    ];

    return FretboardMappingResult(lines: lines);
  }

  FretboardMappedLine _mapLine(InterpretedMusicLine line) {
    return FretboardMappedLine(
      id: line.id,
      title: line.title,
      events: line.events.map(_mapEvent).toList(),
    );
  }

  FretboardMappedEvent _mapEvent(InterpretedMusicEvent event) {
    final candidates = <FretboardCandidate>[];

    if (event.pitches.length == 1) {
      final pitch = event.pitches.first;
      final positions = _positionsForPitch(pitch);

      for (final pos in positions) {
        candidates.add(
          FretboardCandidate(
            label: '${pos.pitch}: S${pos.stringNumber} F${pos.fret}',
            positions: [pos],
          ),
        );
      }
    } else {
      candidates.addAll(_multiPitchCandidates(event));
    }

    return FretboardMappedEvent(
      eventIndex: event.eventIndex,
      label: event.label,
      pitches: event.pitches,
      measureId: event.measureId,
      measureIndex: event.measureIndex,
      sourceX: event.sourceX,
      candidates: candidates,
    );
  }

  List<GuitarPosition> _positionsForPitch(String pitch) {
    final midi = _pitchToMidiValue(pitch);
    if (midi == null) return const [];

    final positions = <GuitarPosition>[];

    for (final entry in _openStringMidi.entries) {
      final stringNumber = entry.key;
      final openMidi = entry.value;
      final fret = midi - openMidi;

      if (fret >= 0 && fret <= maxFret) {
        positions.add(
          GuitarPosition(stringNumber: stringNumber, fret: fret, pitch: pitch),
        );
      }
    }

    positions.sort((a, b) {
      final fretCompare = a.fret.compareTo(b.fret);
      if (fretCompare != 0) return fretCompare;
      return a.stringNumber.compareTo(b.stringNumber);
    });

    return positions;
  }

  List<FretboardCandidate> _multiPitchCandidates(InterpretedMusicEvent event) {
    final uniquePitches = <String>[];
    final seen = <String>{};

    for (final pitch in event.pitches) {
      final normalized = pitch.trim();
      if (normalized.isEmpty || normalized == 'Unresolved') continue;
      if (seen.add(normalized)) {
        uniquePitches.add(normalized);
      }
      if (uniquePitches.length >= _maxChordPitches) break;
    }

    if (uniquePitches.isEmpty) return const [];

    final pitchPositions = uniquePitches.map((pitch) {
      return _positionsForPitch(pitch).take(_maxPositionsPerPitch).toList();
    }).toList();

    if (pitchPositions.any((list) => list.isEmpty)) {
      return const [];
    }

    final combinations = <List<GuitarPosition>>[];

    void build(int index, List<GuitarPosition> current) {
      if (combinations.length >= _maxMultiPitchCandidates) return;

      if (index == pitchPositions.length) {
        final usedStrings = current.map((p) => p.stringNumber).toSet();

        // Cannot play two pitches on the same string at the same time.
        if (usedStrings.length != current.length) return;

        if (!_isPlayableShape(current)) return;

        combinations.add(List<GuitarPosition>.from(current));
        return;
      }

      for (final pos in pitchPositions[index]) {
        if (current.any(
          (existing) => existing.stringNumber == pos.stringNumber,
        )) {
          continue;
        }

        final next = [...current, pos];
        if (!_canStillBecomePlayable(next)) continue;

        build(index + 1, next);
      }
    }

    build(0, []);

    return combinations.map((combo) {
      final label = combo
          .map((p) => '${p.pitch}: S${p.stringNumber} F${p.fret}')
          .join(' | ');

      return FretboardCandidate(label: label, positions: combo);
    }).toList();
  }

  bool _isPlayableShape(List<GuitarPosition> positions) {
    if (positions.isEmpty) return false;

    final fretted = positions.where((p) => p.fret > 0).toList();
    if (fretted.isEmpty) return true;

    final minFret = fretted.map((p) => p.fret).reduce((a, b) => a < b ? a : b);
    final maxFret = fretted.map((p) => p.fret).reduce((a, b) => a > b ? a : b);

    final fretSpan = maxFret - minFret;

    // Base playable range. EventManager/A* can optimize later.
    return fretSpan <= 5;
  }

  bool _canStillBecomePlayable(List<GuitarPosition> positions) {
    final fretted = positions.where((p) => p.fret > 0).toList();
    if (fretted.length < 2) return true;

    final minFret = fretted.map((p) => p.fret).reduce((a, b) => a < b ? a : b);
    final maxFret = fretted.map((p) => p.fret).reduce((a, b) => a > b ? a : b);

    return maxFret - minFret <= 5;
  }

  int? _pitchToMidiValue(String pitch) {
    final match = RegExp(r'^([A-G])([#b]?)(-?\d+)$').firstMatch(pitch);
    if (match == null) return null;

    final letter = match.group(1)!;
    final accidental = match.group(2) ?? '';
    final octave = int.tryParse(match.group(3) ?? '');
    if (octave == null) return null;

    const baseSemitones = {
      'C': 0,
      'D': 2,
      'E': 4,
      'F': 5,
      'G': 7,
      'A': 9,
      'B': 11,
    };

    var semitone = baseSemitones[letter];
    if (semitone == null) return null;

    if (accidental == '#') semitone += 1;
    if (accidental == 'b') semitone -= 1;

    return ((octave + 1) * 12) + semitone;
  }
}
```

<div style="page-break-after: always;"></div>

# File 5 — chord_voicing_service.dart

## Full Path

```text
D:\MyApps\AndroidStudio_Folder\stala_app\lib\services\chord_voicing_service.dart
```

## Purpose

This file selects playable chord voicings by scoring fretboard candidates and optimizing transitions across chord events. It supports the thesis objective of producing guitar-friendly tablature for polyphonic or chordal passages. It is important because it improves playability by preferring compact shapes, smooth movement, and practical fretboard positions.

## Full Source Code

```dart
import 'fretboard_mapping_service.dart';

class ChordVoicedEvent {
  final int eventIndex;
  final String label;
  final String? measureId;
  final int? measureIndex;
  final double? sourceX;
  final List<GuitarPosition> chosenPositions;
  final double cost;
  final String voicingReason;

  const ChordVoicedEvent({
    required this.eventIndex,
    required this.label,
    this.measureId,
    this.measureIndex,
    this.sourceX,
    required this.chosenPositions,
    required this.cost,
    required this.voicingReason,
  });
}

class ChordVoicingLine {
  final String sourceLineId;
  final String title;
  final List<ChordVoicedEvent> events;

  const ChordVoicingLine({
    required this.sourceLineId,
    required this.title,
    required this.events,
  });
}

class ChordVoicingResult {
  final List<ChordVoicingLine> lines;

  const ChordVoicingResult({required this.lines});
}

class ChordVoicingService {
  ChordVoicingResult voice({required FretboardMappingResult fretboardMapping}) {
    final lines = fretboardMapping.lines
        .where((line) => line.id.contains('chord'))
        .map(_voiceLine)
        .whereType<ChordVoicingLine>()
        .toList();

    return ChordVoicingResult(lines: lines);
  }

  ChordVoicingLine? _voiceLine(FretboardMappedLine line) {
    final sourceEvents = line.events
        .where((event) => event.candidates.isNotEmpty)
        .toList();
    if (sourceEvents.isEmpty) return null;

    final path = _findLowestCostPath(sourceEvents);
    if (path.isEmpty) return null;

    final voicedEvents = <ChordVoicedEvent>[];

    for (int i = 0; i < path.length; i++) {
      final event = sourceEvents[i];
      final current = path[i];
      final previous = i > 0 ? path[i - 1] : null;
      final transition = previous == null
          ? 0.0
          : _transitionCost(previous, current);
      final cost = _scoreCandidate(current).cost + transition;

      voicedEvents.add(
        ChordVoicedEvent(
          eventIndex: event.eventIndex,
          label: event.label,
          measureId: event.measureId,
          measureIndex: event.measureIndex,
          sourceX: event.sourceX,
          chosenPositions: current.positions,
          cost: cost,
          voicingReason: _reasonFor(current, previous),
        ),
      );
    }

    if (voicedEvents.isEmpty) return null;

    return ChordVoicingLine(
      sourceLineId: line.id,
      title: line.title,
      events: voicedEvents,
    );
  }

  List<FretboardCandidate> _findLowestCostPath(
    List<FretboardMappedEvent> events,
  ) {
    final dp = <Map<int, _PathState>>[];

    final firstStates = <int, _PathState>{};
    for (int i = 0; i < events.first.candidates.length; i++) {
      final candidate = events.first.candidates[i];
      firstStates[i] = _PathState(
        cost: _scoreCandidate(candidate).cost,
        previousIndex: null,
      );
    }
    dp.add(firstStates);

    for (int eventIndex = 1; eventIndex < events.length; eventIndex++) {
      final previousCandidates = events[eventIndex - 1].candidates;
      final currentCandidates = events[eventIndex].candidates;
      final currentStates = <int, _PathState>{};

      for (
        int currentIndex = 0;
        currentIndex < currentCandidates.length;
        currentIndex++
      ) {
        final current = currentCandidates[currentIndex];
        final localCost = _scoreCandidate(current).cost;
        double bestCost = double.infinity;
        int? bestPreviousIndex;

        for (
          int previousIndex = 0;
          previousIndex < previousCandidates.length;
          previousIndex++
        ) {
          final previousState = dp[eventIndex - 1][previousIndex];
          if (previousState == null) continue;

          final previous = previousCandidates[previousIndex];
          final cost =
              previousState.cost +
              localCost +
              _transitionCost(previous, current);

          if (cost < bestCost) {
            bestCost = cost;
            bestPreviousIndex = previousIndex;
          }
        }

        currentStates[currentIndex] = _PathState(
          cost: bestCost,
          previousIndex: bestPreviousIndex,
        );
      }

      dp.add(currentStates);
    }

    final lastStates = dp.last;
    int? bestFinalIndex;
    double bestFinalCost = double.infinity;

    for (final entry in lastStates.entries) {
      if (entry.value.cost < bestFinalCost) {
        bestFinalCost = entry.value.cost;
        bestFinalIndex = entry.key;
      }
    }

    if (bestFinalIndex == null) return const [];

    final path = List<FretboardCandidate?>.filled(events.length, null);
    int? currentIndex = bestFinalIndex;

    for (int eventIndex = events.length - 1; eventIndex >= 0; eventIndex--) {
      if (currentIndex == null) break;
      path[eventIndex] = events[eventIndex].candidates[currentIndex];
      currentIndex = dp[eventIndex][currentIndex]?.previousIndex;
    }

    return path.whereType<FretboardCandidate>().toList();
  }

  double _transitionCost(
    FretboardCandidate previous,
    FretboardCandidate current,
  ) {
    final previousCenter = _candidateCenter(previous);
    final currentCenter = _candidateCenter(current);

    final fretDistance = (currentCenter.fret - previousCenter.fret).abs();
    final stringDistance =
        (currentCenter.stringNumber - previousCenter.stringNumber).abs();
    final currentSpan = _fretSpan(current.positions);
    final openCount = current.positions.where((p) => p.fret == 0).length;

    double cost = 0;
    cost += fretDistance * 4.0;
    cost += stringDistance * 2.0;
    cost += currentSpan * 3.0;

    if (fretDistance > 5) cost += 20;
    if (fretDistance > 9) cost += 40;
    if (stringDistance == 0) cost -= 2;
    cost -= openCount * 1.0;

    return cost;
  }

  String _reasonFor(FretboardCandidate current, FretboardCandidate? previous) {
    final localReason = _scoreCandidate(current).reason;
    if (previous == null) return '$localReason+path_start';

    final transition = _transitionCost(previous, current);
    if (transition <= 8) return '$localReason+smooth_transition';
    if (transition <= 20) return '$localReason+reachable_transition';
    return '$localReason+larger_shift';
  }

  _CandidateCenter _candidateCenter(FretboardCandidate candidate) {
    final positions = candidate.positions;
    if (positions.isEmpty) {
      return const _CandidateCenter(stringNumber: 3, fret: 0);
    }

    final averageString =
        positions.map((p) => p.stringNumber).reduce((a, b) => a + b) /
        positions.length;
    final averageFret =
        positions.map((p) => p.fret).reduce((a, b) => a + b) / positions.length;

    return _CandidateCenter(
      stringNumber: averageString.round(),
      fret: averageFret.round(),
    );
  }

  _VoicingScore _scoreCandidate(FretboardCandidate candidate) {
    final positions = candidate.positions;

    final span = _fretSpan(positions);
    final avgFret = _averageFret(positions);
    final stringSpread = _stringSpread(positions);
    final openCount = positions.where((p) => p.fret == 0).length;
    final mutedGapCount = _mutedGapCount(positions);
    final hasRootInBass = _hasLowestStringRoot(candidate);

    double cost = 0;
    final reasons = <String>[];

    // 1. Compact fret span
    cost += span * 5.0;
    if (span <= 3) reasons.add('compact_shape');

    // 2. Prefer lower/mid fret region for beginner-friendliness
    cost += avgFret * 0.9;
    if (avgFret <= 5) reasons.add('low_position');

    // 3. Penalize wide string spread slightly
    cost += stringSpread * 1.5;

    // 4. Reward open strings slightly
    cost -= openCount * 1.5;
    if (openCount > 0) reasons.add('open_string_support');

    // 5. Penalize skipped/muted gaps in simple voicings
    cost += mutedGapCount * 3.0;
    if (mutedGapCount == 0) reasons.add('continuous_strings');

    // 6. Prefer root or low chord tone on lower string when possible
    if (hasRootInBass) {
      cost -= 4.0;
      reasons.add('root_in_bass');
    }

    // 7. Strong penalty for difficult shapes
    if (span > 5) {
      cost += 50;
      reasons.add('wide_span_penalty');
    }

    if (avgFret > 12) {
      cost += 25;
      reasons.add('high_position_penalty');
    }

    return _VoicingScore(
      candidate: candidate,
      cost: cost,
      reason: reasons.isEmpty ? 'best_available_shape' : reasons.join('+'),
    );
  }

  int _fretSpan(List<GuitarPosition> positions) {
    final fretted = positions.where((p) => p.fret > 0).toList();
    if (fretted.length < 2) return 0;

    final minFret = fretted.map((p) => p.fret).reduce((a, b) => a < b ? a : b);

    final maxFret = fretted.map((p) => p.fret).reduce((a, b) => a > b ? a : b);

    return maxFret - minFret;
  }

  double _averageFret(List<GuitarPosition> positions) {
    if (positions.isEmpty) return 999;

    return positions.map((p) => p.fret).reduce((a, b) => a + b) /
        positions.length;
  }

  int _stringSpread(List<GuitarPosition> positions) {
    if (positions.length < 2) return 0;

    final minString = positions
        .map((p) => p.stringNumber)
        .reduce((a, b) => a < b ? a : b);

    final maxString = positions
        .map((p) => p.stringNumber)
        .reduce((a, b) => a > b ? a : b);

    return maxString - minString;
  }

  int _mutedGapCount(List<GuitarPosition> positions) {
    if (positions.length < 2) return 0;

    final strings = positions.map((p) => p.stringNumber).toList()..sort();

    int gaps = 0;
    for (int i = 0; i < strings.length - 1; i++) {
      final diff = strings[i + 1] - strings[i];

      if (diff > 1) {
        gaps += diff - 1;
      }
    }

    return gaps;
  }

  bool _hasLowestStringRoot(FretboardCandidate candidate) {
    if (candidate.positions.isEmpty) return false;

    final root = _extractRootFromLabel(candidate.label);
    if (root == null) return false;

    final sortedByLowString = [...candidate.positions]
      ..sort((a, b) => b.stringNumber.compareTo(a.stringNumber));

    final lowest = sortedByLowString.first;

    return _pitchLetter(lowest.pitch) == root;
  }

  String? _extractRootFromLabel(String label) {
    final match = RegExp(r'^([A-G])([#b]?)').firstMatch(label);
    if (match == null) return null;

    return '${match.group(1)}${match.group(2) ?? ''}';
  }

  String? _pitchLetter(String pitch) {
    final match = RegExp(r'^([A-G])([#b]?)').firstMatch(pitch);
    if (match == null) return null;

    return '${match.group(1)}${match.group(2) ?? ''}';
  }
}

class _VoicingScore {
  final FretboardCandidate candidate;
  final double cost;
  final String reason;

  const _VoicingScore({
    required this.candidate,
    required this.cost,
    required this.reason,
  });
}

class _PathState {
  final double cost;
  final int? previousIndex;

  const _PathState({required this.cost, required this.previousIndex});
}

class _CandidateCenter {
  final int stringNumber;
  final int fret;

  const _CandidateCenter({required this.stringNumber, required this.fret});
}
```

<div style="page-break-after: always;"></div>

# File 6 — OnnxDetector.kt

## Full Path

```text
D:\MyApps\AndroidStudio_Folder\stala_app\android\app\src\main\kotlin\com\example\stala_app\OnnxDetector.kt
```

## Purpose

This file loads the STALA ONNX symbol detector, preprocesses cropped sheet images, runs inference, and returns classified symbol detections. It supports the thesis objective of applying machine learning-based optical music symbol recognition. It is important because detected noteheads, clefs, and accidentals provide the core visual evidence for translation into notes and tablature.

## Full Source Code

```kotlin
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
```

<div style="page-break-after: always;"></div>

# File 7 — translation_grouping_service.dart

## Full Path

```text
D:\MyApps\AndroidStudio_Folder\stala_app\lib\services\translation_grouping_service.dart
```

## Purpose

This file groups detected symbols by staff, assigns them to staff lines, spaces, virtual ledger positions, measures, clefs, key signatures, and accidentals. It supports the thesis objective of converting visual symbol detections into musically meaningful staff-position data. It is important because it transforms raw detection geometry into pitch-ready symbolic note information.

## Full Source Code

```dart
import '../models/translation_group_models.dart';
import '../dummy_page.dart';
import 'clef_resolution_service.dart';
import 'pitch_mapping_service.dart';
import 'accidental_service.dart';
import 'key_signature_service.dart';

class TranslationGroupingService {
  /// Builds staff_n groups using segmented staff lines and detected symbols.
  ///
  /// Current behavior:
  /// - groups every 5 detected staff lines into one staff_n
  /// - creates line_0 to line_4 and space_0 to space_3
  /// - assigns symbols to the nearest staff group
  /// - assigns each symbol to nearest line/space segment
  /// - shows default note mapping like "F / A" while clef detection and
  ///   accidental rules are still pending
  ///
  /// Future-ready notes:
  /// - accidentalState is reserved for accidental logic
  /// - clefStatusLabel is reserved for real clef resolution
  /// - defaultKeyLabel can later be replaced by resolved pitch output

  final ClefResolutionService _clefResolutionService = ClefResolutionService();
  final PitchMappingService _pitchMappingService = PitchMappingService();
  final AccidentalService _accidentalService = AccidentalService();
  final KeySignatureService _keySignatureService = KeySignatureService();

  static const int _virtualLedgerSteps = 5;
  static const double _virtualLedgerPadding = 0.75;

  List<StaffTranslateGroup> buildGroups({
    required List<SymbolClassItem> classItems,
    required List<dynamic> staffLines,
    List<dynamic> validatedStaffs = const [],
    List<dynamic> ledgerLines = const [],
    List<dynamic> measures = const [],
  }) {
    final staffGeometries = _normalizeStaffGeometries(
      validatedStaffs: validatedStaffs,
      staffLines: staffLines,
    );
    final normalizedLedgerLines = _normalizeLedgerLines(ledgerLines);
    final measureRegions = _normalizeMeasures(measures);

    if (staffGeometries.isEmpty) {
      return const [];
    }

    final staffLineMap = <String, List<double>>{
      for (final geometry in staffGeometries) geometry.staffId: geometry.lines,
    };

    final clefResults = _clefResolutionService.resolveClefs(
      classItems: classItems,
      staffLineGroups: staffLineMap,
    );

    final clefByStaffId = {
      for (final result in clefResults) result.staffId: result,
    };

    final result = <StaffTranslateGroup>[];

    for (final geometry in staffGeometries) {
      final staffId = geometry.staffId;
      final clefResult = clefByStaffId[staffId];

      final lines = geometry.lines;
      if (lines.length < 5) continue;

      final segmentMap = _buildSegmentMap(lines);

      final topBoundary = geometry.topBoundary ?? _computeTopBoundary(lines);
      final bottomBoundary =
          geometry.bottomBoundary ?? _computeBottomBoundary(lines);
      final spacing = geometry.spacing ?? _averageSpacing(lines);

      final extendedTopBoundary =
          lines.first -
          (spacing * (_virtualLedgerSteps + _virtualLedgerPadding));

      final extendedBottomBoundary =
          lines.last +
          (spacing * (_virtualLedgerSteps + _virtualLedgerPadding));

      final symbolsInStaff = classItems.where((item) {
        final className = item.className.trim().toLowerCase();

        final insideNormalStaff =
            item.y >= topBoundary && item.y <= bottomBoundary;

        final insideVirtualExtension =
            item.y >= extendedTopBoundary && item.y <= extendedBottomBoundary;

        if (insideNormalStaff) return true;

        if (className == 'notehead' && insideVirtualExtension) {
          return true;
        }

        return false;
      }).toList()..sort((a, b) => a.x.compareTo(b.x));

      final keySignature = _keySignatureService.resolveKeySignature(
        staffId: staffId,
        symbolsInStaff: symbolsInStaff,
        spacing: spacing,
      );

      final staffRole = _resolveStaffRole(clefResult?.label);

      final translatedSymbols = symbolsInStaff.map((item) {
        final location = _findNearestSegment(item.y, segmentMap);
        final measure = _measureForSymbol(
          symbol: item,
          staffId: staffId,
          measures: measureRegions,
        );

        // Computes pitch
        final pitch = item.className.trim().toLowerCase() == 'notehead'
            ? _pitchMappingService.resolvePitch(
                segment: location,
                clef: clefResult?.clef ?? ResolvedClef.unknown,
              )
            : null;

        final pitchWithKey = pitch != null
            ? _keySignatureService.applyToPitch(
                pitch: pitch,
                keySignature: keySignature,
              )
            : null;

        // Add accidental effect to pitch
        final isNotehead = item.className.trim().toLowerCase() == 'notehead';

        final accidentalResult = isNotehead && pitchWithKey != null
            ? _accidentalService.applyMeasureAwareAccidental(
                basePitch: pitchWithKey,
                notehead: item,
                symbolsInStaff: symbolsInStaff,
                spacing: spacing,
                measureStartX: measure?.x1,
                measureEndX: measure?.x2,
              )
            : null;

        // Ledger line
        final insideNormalStaff =
            item.y >= topBoundary && item.y <= bottomBoundary;

        String assignmentStatus;

        if (insideNormalStaff) {
          assignmentStatus = 'normal';
        } else {
          final confirmed =
              _isNearLedgerLine(
                symbol: item,
                staffId: staffId,
                ledgerLines: normalizedLedgerLines,
                spacing: spacing,
              ) ||
              _isSupportedLedgerSpace(
                location: location,
                symbol: item,
                staffId: staffId,
                ledgerLines: normalizedLedgerLines,
                spacing: spacing,
              );

          assignmentStatus = confirmed ? 'ledgerConfirmed' : 'ledgerCandidate';
        }

        return TranslatedSymbolViewItem(
          className: item.className,
          centerX: item.x,
          centerY: item.y,
          score: item.score,
          bbox: item.bbox,
          staffId: staffId,
          staffRole: staffRole,
          locationId: location.id,
          locationType: location.type,
          assignmentStatus: assignmentStatus,
          measureId: measure?.id,
          measureIndex: measure?.indexInStaff,
          defaultKeyLabel: accidentalResult?.pitch,
          accidentalState:
              accidentalResult?.accidental.name ??
              _defaultAccidentalState(item.className),
          symbolState: item.symbolState,
          inferredReason: item.inferredReason,
        );
      }).toList();

      result.add(
        StaffTranslateGroup(
          staffId: staffId,
          summary: StaffSummary(
            lineCount: lines.length,
            symbolCount: translatedSymbols.length,
            clefStatusLabel:
                '${clefResult?.label ?? 'Unknown clef'} • ${keySignature.label}',
          ),
          segmentMap: segmentMap,
          symbols: translatedSymbols,
        ),
      );
    }

    return result;
  }

  List<double> _normalizeStaffLines(List<dynamic> rawStaffLines) {
    final values = <double>[];

    for (final item in rawStaffLines) {
      if (item is Map) {
        final map = Map<String, dynamic>.from(
          item.map((key, value) => MapEntry(key.toString(), value)),
        );

        final y = _toDouble(map['y']);
        if (y != null) {
          values.add(y);
        }
      } else {
        final y = _toDouble(item);
        if (y != null) {
          values.add(y);
        }
      }
    }

    values.sort();
    return values;
  }

  List<_StaffGeometry> _normalizeStaffGeometries({
    required List<dynamic> validatedStaffs,
    required List<dynamic> staffLines,
  }) {
    final fromValidated = <_StaffGeometry>[];

    for (final item in validatedStaffs) {
      if (item is! Map) continue;

      final map = Map<String, dynamic>.from(
        item.map((key, value) => MapEntry(key.toString(), value)),
      );

      final staffId = map['id']?.toString();
      final rawLines = map['lines'];
      if (staffId == null || rawLines is! List) continue;

      final lines = rawLines.map(_toDouble).whereType<double>().toList()
        ..sort();

      if (lines.length != 5) continue;

      fromValidated.add(
        _StaffGeometry(
          staffId: staffId,
          lines: lines,
          spacing: _toDouble(map['validatedStaffSpacing'] ?? map['spacing']),
          topBoundary: _toDouble(map['topBoundary']),
          bottomBoundary: _toDouble(map['bottomBoundary']),
        ),
      );
    }

    if (fromValidated.isNotEmpty) {
      fromValidated.sort((a, b) {
        final yCompare = a.lines.first.compareTo(b.lines.first);
        if (yCompare != 0) return yCompare;

        final spacingCompare = (a.spacing ?? 0.0).compareTo(b.spacing ?? 0.0);
        if (spacingCompare != 0) return spacingCompare;

        return a.staffId.compareTo(b.staffId);
      });
      return fromValidated;
    }

    final normalizedLines = _normalizeStaffLines(staffLines);
    if (normalizedLines.length < 5) return const [];

    final grouped = _buildStaffLineGroups(normalizedLines);
    return grouped.asMap().entries.map((entry) {
      final staffId = 'staff_${entry.key}';
      final lines = entry.value;
      return _StaffGeometry(
        staffId: staffId,
        lines: lines,
        spacing: _averageSpacing(lines),
        topBoundary: _computeTopBoundary(lines),
        bottomBoundary: _computeBottomBoundary(lines),
      );
    }).toList();
  }

  List<_LedgerLineItem> _normalizeLedgerLines(List<dynamic> rawLedgerLines) {
    final result = <_LedgerLineItem>[];

    for (final item in rawLedgerLines) {
      if (item is! Map) continue;

      final map = Map<String, dynamic>.from(
        item.map((key, value) => MapEntry(key.toString(), value)),
      );

      final staffId = map['staffId']?.toString();
      final x1 = _toDouble(map['x1']);
      final x2 = _toDouble(map['x2']);
      final y = _toDouble(map['y']);
      final position = map['position']?.toString() ?? 'unknown';

      if (staffId == null || x1 == null || x2 == null || y == null) continue;

      result.add(
        _LedgerLineItem(
          staffId: staffId,
          x1: x1,
          x2: x2,
          y: y,
          position: position,
        ),
      );
    }

    return result;
  }

  List<_MeasureRegion> _normalizeMeasures(List<dynamic> rawMeasures) {
    final result = <_MeasureRegion>[];

    for (final item in rawMeasures) {
      if (item is! Map) continue;

      final map = Map<String, dynamic>.from(
        item.map((key, value) => MapEntry(key.toString(), value)),
      );

      final id = map['id']?.toString();
      final staffId = map['staffId']?.toString();
      final indexInStaff = _toInt(map['indexInStaff']);
      final x1 = _toDouble(map['x1']);
      final x2 = _toDouble(map['x2']);

      if (id == null ||
          staffId == null ||
          indexInStaff == null ||
          x1 == null ||
          x2 == null) {
        continue;
      }

      result.add(
        _MeasureRegion(
          id: id,
          staffId: staffId,
          indexInStaff: indexInStaff,
          x1: x1,
          x2: x2,
        ),
      );
    }

    return result;
  }

  List<List<double>> _buildStaffLineGroups(List<double> lines) {
    final grouped = <List<double>>[];

    for (int i = 0; i < lines.length; i += 5) {
      final end = (i + 5 < lines.length) ? i + 5 : lines.length;
      final chunk = lines.sublist(i, end);

      if (chunk.length == 5) {
        grouped.add(chunk);
      }
    }

    return grouped;
  }

  List<SegmentMapItem> _buildSegmentMap(List<double> lines) {
    final items = <SegmentMapItem>[];

    const lineLabels = ['line_0', 'line_1', 'line_2', 'line_3', 'line_4'];
    const spaceLabels = ['space_0', 'space_1', 'space_2', 'space_3'];

    const defaultMap = [
      'F / A',
      'E / G',
      'D / F',
      'C / E',
      'B / D',
      'A / C',
      'G / B',
      'F / A',
      'E / G',
    ];

    // line_0
    items.add(
      SegmentMapItem(
        id: lineLabels[0],
        type: 'line',
        centerY: lines[0],
        defaultKeyLabel: defaultMap[0],
      ),
    );

    // space_0, line_1, ...
    for (int i = 0; i < 4; i++) {
      final spaceStart = lines[i];
      final spaceEnd = lines[i + 1];
      final spaceCenter = (spaceStart + spaceEnd) / 2.0;

      items.add(
        SegmentMapItem(
          id: spaceLabels[i],
          type: 'space',
          centerY: spaceCenter,
          startY: spaceStart,
          endY: spaceEnd,
          defaultKeyLabel: defaultMap[(i * 2) + 1],
        ),
      );

      items.add(
        SegmentMapItem(
          id: lineLabels[i + 1],
          type: 'line',
          centerY: lines[i + 1],
          defaultKeyLabel: defaultMap[(i * 2) + 2],
        ),
      );
    }

    final spacing = _averageSpacing(lines);

    const aboveVirtualMap = {
      1: 'G / B',
      2: 'A / C',
      3: 'B / D',
      4: 'C / E',
      5: 'D / F',
    };

    const belowVirtualMap = {
      1: 'D / F',
      2: 'C / E',
      3: 'B / D',
      4: 'A / C',
      5: 'G / B',
    };

    // Virtual lines above staff
    for (int i = _virtualLedgerSteps; i >= 1; i--) {
      final lineY = lines.first - (spacing * i);
      final spaceY = lines.first - (spacing * (i - 0.5));

      items.insert(
        0,
        SegmentMapItem(
          id: 'v_line_above_$i',
          type: 'virtual_line',
          centerY: lineY,
          defaultKeyLabel: aboveVirtualMap[i] ?? 'virtual',
        ),
      );

      items.insert(
        0,
        SegmentMapItem(
          id: 'v_space_above_$i',
          type: 'virtual_space',
          centerY: spaceY,
          defaultKeyLabel: 'virtual',
        ),
      );
    }

    // Virtual lines below staff
    for (int i = 1; i <= _virtualLedgerSteps; i++) {
      final spaceY = lines.last + (spacing * (i - 0.5));
      final lineY = lines.last + (spacing * i);

      items.add(
        SegmentMapItem(
          id: 'v_space_below_$i',
          type: 'virtual_space',
          centerY: spaceY,
          defaultKeyLabel: 'virtual',
        ),
      );

      items.add(
        SegmentMapItem(
          id: 'v_line_below_$i',
          type: 'virtual_line',
          centerY: lineY,
          defaultKeyLabel: belowVirtualMap[i] ?? 'virtual',
        ),
      );
    }

    items.sort((a, b) => a.centerY.compareTo(b.centerY));
    return items;
  }

  SegmentMapItem _findNearestSegment(
    double symbolY,
    List<SegmentMapItem> segmentMap,
  ) {
    SegmentMapItem nearest = segmentMap.first;
    double minDistance = (symbolY - nearest.centerY).abs();

    for (final item in segmentMap.skip(1)) {
      final dist = (symbolY - item.centerY).abs();
      if (dist < minDistance) {
        minDistance = dist;
        nearest = item;
      }
    }

    return nearest;
  }

  double _computeTopBoundary(List<double> lines) {
    final spacing = _averageSpacing(lines);
    return lines.first - (spacing * 0.8);
  }

  double _computeBottomBoundary(List<double> lines) {
    final spacing = _averageSpacing(lines);
    return lines.last + (spacing * 0.8);
  }

  double _averageSpacing(List<double> lines) {
    if (lines.length < 2) return 0;
    double total = 0;

    for (int i = 0; i < lines.length - 1; i++) {
      total += (lines[i + 1] - lines[i]);
    }

    return total / (lines.length - 1);
  }

  String? _defaultAccidentalState(String className) {
    final key = className.trim().toLowerCase();
    if (key == 'sharp' || key == 'flat' || key == 'natural') {
      return key;
    }
    return null;
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  _MeasureRegion? _measureForSymbol({
    required SymbolClassItem symbol,
    required String staffId,
    required List<_MeasureRegion> measures,
  }) {
    final staffMeasures =
        measures.where((measure) => measure.staffId == staffId).toList()
          ..sort((a, b) => a.x1.compareTo(b.x1));

    for (final measure in staffMeasures) {
      final inside = symbol.x >= measure.x1 && symbol.x <= measure.x2;
      if (inside) return measure;
    }

    return null;
  }

  bool _isNearLedgerLine({
    required SymbolClassItem symbol,
    required String staffId,
    required List<_LedgerLineItem> ledgerLines,
    required double spacing,
  }) {
    final xTolerance = spacing * 0.95;
    final yTolerance = spacing * 0.8;

    for (final ledger in ledgerLines) {
      if (ledger.staffId != staffId) continue;

      final yClose = (symbol.y - ledger.y).abs() <= yTolerance;

      final symbolLeft = symbol.bbox != null
          ? symbol.bbox![0]
          : symbol.x - spacing;
      final symbolRight = symbol.bbox != null
          ? symbol.bbox![2]
          : symbol.x + spacing;

      final xOverlaps =
          symbolRight >= (ledger.x1 - xTolerance) &&
          symbolLeft <= (ledger.x2 + xTolerance);

      final ledgerCenterX = (ledger.x1 + ledger.x2) / 2.0;
      final centerClose = (symbol.x - ledgerCenterX).abs() <= spacing * 1.6;

      if (yClose && xOverlaps && centerClose) {
        return true;
      }
    }

    return false;
  }

  bool _isSupportedLedgerSpace({
    required SegmentMapItem location,
    required SymbolClassItem symbol,
    required String staffId,
    required List<_LedgerLineItem> ledgerLines,
    required double spacing,
  }) {
    if (location.type != 'virtual_space') return false;

    final adjacentToStaff =
        location.id == 'v_space_above_1' || location.id == 'v_space_below_1';
    if (adjacentToStaff) return true;

    return ledgerLines.any((ledger) {
      if (ledger.staffId != staffId) return false;

      final yClose = (symbol.y - ledger.y).abs() <= spacing * 1.35;
      final symbolLeft = symbol.bbox != null
          ? symbol.bbox![0]
          : symbol.x - spacing;
      final symbolRight = symbol.bbox != null
          ? symbol.bbox![2]
          : symbol.x + spacing;

      final xTolerance = spacing * 1.1;
      final xOverlaps =
          symbolRight >= ledger.x1 - xTolerance &&
          symbolLeft <= ledger.x2 + xTolerance;

      return yClose && xOverlaps;
    });
  }

  String _resolveStaffRole(String? clefLabel) {
    final label = clefLabel?.toLowerCase() ?? '';

    if (label.contains('treble')) return 'treble';
    if (label.contains('bass')) return 'bass';

    return 'unknown';
  }
}

class _StaffGeometry {
  final String staffId;
  final List<double> lines;
  final double? spacing;
  final double? topBoundary;
  final double? bottomBoundary;

  const _StaffGeometry({
    required this.staffId,
    required this.lines,
    this.spacing,
    this.topBoundary,
    this.bottomBoundary,
  });
}

class _LedgerLineItem {
  final String staffId;
  final double x1;
  final double x2;
  final double y;
  final String position;

  const _LedgerLineItem({
    required this.staffId,
    required this.x1,
    required this.x2,
    required this.y,
    required this.position,
  });
}

class _MeasureRegion {
  final String id;
  final String staffId;
  final int indexInStaff;
  final double x1;
  final double x2;

  const _MeasureRegion({
    required this.id,
    required this.staffId,
    required this.indexInStaff,
    required this.x1,
    required this.x2,
  });
}
```

<div style="page-break-after: always;"></div>

# File 8 — polyphonic_to_monophonic_service.dart

## Full Path

```text
D:\MyApps\AndroidStudio_Folder\stala_app\lib\services\polyphonic_to_monophonic_service.dart
```

## Purpose

This file organizes notes into harmonic stacks, detects basic chord identities, and derives a strict treble melody line from polyphonic grand-staff content. It supports the thesis objective of handling both polyphonic interpretation and monophonic melody extraction for tablature generation. It is important because it prepares alternate musical representations used by later mapping and output stages.

## Full Source Code

```dart
import '../models/translation_group_models.dart';
import 'grand_staff_pairing_service.dart';

class HarmonicStack {
  final String id;
  final String grandStaffId;
  final int eventIndex;
  final String? measureId;
  final int? measureIndex;
  final double sourceX;
  final List<TranslatedSymbolViewItem> notes;

  const HarmonicStack({
    required this.id,
    required this.grandStaffId,
    required this.eventIndex,
    this.measureId,
    this.measureIndex,
    required this.sourceX,
    required this.notes,
  });
}

class ChordAwareStack {
  final String id;
  final String grandStaffId;
  final int eventIndex;
  final String? measureId;
  final int? measureIndex;
  final double sourceX;
  final List<TranslatedSymbolViewItem> notes;
  final String? chordName;
  final String? root;
  final String? quality;

  const ChordAwareStack({
    required this.id,
    required this.grandStaffId,
    required this.eventIndex,
    this.measureId,
    this.measureIndex,
    required this.sourceX,
    required this.notes,
    this.chordName,
    this.root,
    this.quality,
  });
}

class MonophonicNote {
  final String id;
  final String grandStaffId;
  final int eventIndex;
  final String? measureId;
  final int? measureIndex;
  final double sourceX;
  final String pitch;
  final TranslatedSymbolViewItem sourceNote;
  final List<String> harmonyContext;
  final String selectionReason;

  const MonophonicNote({
    required this.id,
    required this.grandStaffId,
    required this.eventIndex,
    this.measureId,
    this.measureIndex,
    required this.sourceX,
    required this.pitch,
    required this.sourceNote,
    required this.harmonyContext,
    required this.selectionReason,
  });
}

class PolyphonicToMonophonicResult {
  final String grandStaffId;
  final List<HarmonicStack> harmonicStacks;
  final List<ChordAwareStack> chordAwareStacks;
  final List<MonophonicNote> strictMelody;

  const PolyphonicToMonophonicResult({
    required this.grandStaffId,
    required this.harmonicStacks,
    required this.chordAwareStacks,
    required this.strictMelody,
  });
}

class _HarmonicCandidate {
  final double centerX;
  final List<TranslatedSymbolViewItem> notes;
  final int? measureIndex;
  final String? measureId;

  const _HarmonicCandidate({
    required this.centerX,
    required this.notes,
    this.measureIndex,
    this.measureId,
  });
}

class PolyphonicToMonophonicService {
  List<PolyphonicToMonophonicResult> convert({
    required List<GrandStaffPair> grandStaffPairs,
    required Map<String, List<List<TranslatedSymbolViewItem>>> groupedNotes,
  }) {
    return grandStaffPairs.map((pair) {
      final stacks = _buildHarmonicStacks(
        pair: pair,
        groupedNotes: groupedNotes,
      );

      final chordAwareStacks = _buildChordAwareStacks(stacks);

      final strict = _prioritizeMelodyStrict(
        grandStaffId: pair.id,
        stacks: stacks,
      );

      return PolyphonicToMonophonicResult(
        grandStaffId: pair.id,
        harmonicStacks: stacks,
        chordAwareStacks: chordAwareStacks,
        strictMelody: strict,
      );
    }).toList();
  }

  List<HarmonicStack> _buildHarmonicStacks({
    required GrandStaffPair pair,
    required Map<String, List<List<TranslatedSymbolViewItem>>> groupedNotes,
  }) {
    final trebleGroups =
        groupedNotes[pair.trebleStaffId] ??
        const <List<TranslatedSymbolViewItem>>[];

    final bassGroups = pair.bassStaffId == null
        ? const <List<TranslatedSymbolViewItem>>[]
        : groupedNotes[pair.bassStaffId] ??
              const <List<TranslatedSymbolViewItem>>[];

    final allGroups = <List<TranslatedSymbolViewItem>>[
      ...trebleGroups,
      ...bassGroups,
    ];

    final eventCandidates =
        allGroups.where((group) => group.isNotEmpty).map((group) {
          final avgX =
              group.map((note) => note.centerX).reduce((a, b) => a + b) /
              group.length;

          return _HarmonicCandidate(
            centerX: avgX,
            notes: group,
            measureIndex: _measureIndexForNotes(group),
            measureId: _measureIdForNotes(group),
          );
        }).toList()..sort((a, b) {
          final measureCompare = (a.measureIndex ?? 0).compareTo(
            b.measureIndex ?? 0,
          );
          if (measureCompare != 0) return measureCompare;
          return a.centerX.compareTo(b.centerX);
        });

    if (eventCandidates.isEmpty) return const [];

    final threshold = _estimateHarmonicThreshold(eventCandidates);

    final clusters = <List<_HarmonicCandidate>>[];
    List<_HarmonicCandidate> currentCluster = [];

    for (final candidate in eventCandidates) {
      if (currentCluster.isEmpty) {
        currentCluster.add(candidate);
        continue;
      }

      final sameMeasure =
          (currentCluster.first.measureIndex ?? 0) ==
          (candidate.measureIndex ?? 0);

      final clusterCenter =
          currentCluster.map((item) => item.centerX).reduce((a, b) => a + b) /
          currentCluster.length;

      final dx = (candidate.centerX - clusterCenter).abs();

      if (sameMeasure && dx <= threshold) {
        currentCluster.add(candidate);
      } else {
        clusters.add(currentCluster);
        currentCluster = [candidate];
      }
    }

    if (currentCluster.isNotEmpty) {
      clusters.add(currentCluster);
    }

    final stacks = <HarmonicStack>[];

    for (int i = 0; i < clusters.length; i++) {
      final notes = clusters[i]
          .expand((candidate) => candidate.notes)
          .where(
            (note) =>
                note.defaultKeyLabel != null &&
                note.defaultKeyLabel!.trim().isNotEmpty,
          )
          .toList();

      if (notes.isEmpty) continue;

      final sourceX =
          notes.map((note) => note.centerX).reduce((a, b) => a + b) /
          notes.length;

      stacks.add(
        HarmonicStack(
          id: '${pair.id}_stack_$i',
          grandStaffId: pair.id,
          eventIndex: i,
          measureId: _measureIdForNotes(notes),
          measureIndex: _measureIndexForNotes(notes),
          sourceX: sourceX,
          notes: notes,
        ),
      );
    }

    return stacks;
  }

  List<ChordAwareStack> _buildChordAwareStacks(List<HarmonicStack> stacks) {
    return stacks.map((stack) {
      final chord = _detectChord(stack.notes);

      return ChordAwareStack(
        id: '${stack.id}_chord',
        grandStaffId: stack.grandStaffId,
        eventIndex: stack.eventIndex,
        measureId: stack.measureId,
        measureIndex: stack.measureIndex,
        sourceX: stack.sourceX,
        notes: stack.notes,
        chordName: chord?.chordName,
        root: chord?.root,
        quality: chord?.quality,
      );
    }).toList();
  }

  _ChordResult? _detectChord(List<TranslatedSymbolViewItem> notes) {
    final pitchClasses = notes
        .map((note) => note.defaultKeyLabel)
        .whereType<String>()
        .map(_pitchClass)
        .whereType<int>()
        .toSet();

    if (pitchClasses.length == 1) return null;

    if (pitchClasses.length == 2) {
      return _detectDyadOrInterval(pitchClasses);
    }

    const names = {
      0: 'C',
      1: 'C#',
      2: 'D',
      3: 'D#',
      4: 'E',
      5: 'F',
      6: 'F#',
      7: 'G',
      8: 'G#',
      9: 'A',
      10: 'A#',
      11: 'B',
    };

    for (int root = 0; root < 12; root++) {
      final major = {root, (root + 4) % 12, (root + 7) % 12};

      final minor = {root, (root + 3) % 12, (root + 7) % 12};

      final diminished = {root, (root + 3) % 12, (root + 6) % 12};

      if (pitchClasses.containsAll(major)) {
        final rootName = names[root]!;
        return _ChordResult(
          chordName: rootName,
          root: rootName,
          quality: 'major',
        );
      }

      if (pitchClasses.containsAll(minor)) {
        final rootName = names[root]!;
        return _ChordResult(
          chordName: '${rootName}m',
          root: rootName,
          quality: 'minor',
        );
      }

      if (pitchClasses.containsAll(diminished)) {
        final rootName = names[root]!;
        return _ChordResult(
          chordName: '${rootName}dim',
          root: rootName,
          quality: 'diminished',
        );
      }
    }

    return null;
  }

  String? _measureIdForNotes(List<TranslatedSymbolViewItem> notes) {
    final ids = notes.map((note) => note.measureId).whereType<String>();
    if (ids.isEmpty) return null;
    return ids.first;
  }

  int? _measureIndexForNotes(List<TranslatedSymbolViewItem> notes) {
    final indexes = notes.map((note) => note.measureIndex).whereType<int>();
    if (indexes.isEmpty) return null;
    return indexes.first;
  }

  int? _pitchClass(String pitch) {
    final match = RegExp(r'^([A-G])([#b]?)-?\d+$').firstMatch(pitch);
    if (match == null) return null;

    final letter = match.group(1)!;
    final accidental = match.group(2) ?? '';

    const base = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};

    var value = base[letter];
    if (value == null) return null;

    if (accidental == '#') value += 1;
    if (accidental == 'b') value -= 1;

    return value % 12;
  }

  _ChordResult? _detectDyadOrInterval(Set<int> pitchClasses) {
    final notes = pitchClasses.toList()..sort();
    final a = notes[0];
    final b = notes[1];

    final interval = (b - a) % 12;

    const names = {
      0: 'C',
      1: 'C#',
      2: 'D',
      3: 'D#',
      4: 'E',
      5: 'F',
      6: 'F#',
      7: 'G',
      8: 'G#',
      9: 'A',
      10: 'A#',
      11: 'B',
    };

    final rootName = names[a] ?? 'Unknown';

    switch (interval) {
      case 3:
        return _ChordResult(
          chordName: '$rootName minor third',
          root: rootName,
          quality: 'minor third interval',
        );

      case 4:
        return _ChordResult(
          chordName: '$rootName major third',
          root: rootName,
          quality: 'major third interval',
        );

      case 5:
        return _ChordResult(
          chordName: '$rootName perfect fourth',
          root: rootName,
          quality: 'perfect fourth interval',
        );

      case 7:
        return _ChordResult(
          chordName: '${rootName}5',
          root: rootName,
          quality: 'power chord / perfect fifth',
        );

      case 8:
        return _ChordResult(
          chordName: '$rootName minor sixth',
          root: rootName,
          quality: 'minor sixth interval',
        );

      case 9:
        return _ChordResult(
          chordName: '$rootName major sixth',
          root: rootName,
          quality: 'major sixth interval',
        );

      default:
        return _ChordResult(
          chordName: '$rootName interval',
          root: rootName,
          quality: 'dyad interval',
        );
    }
  }

  List<MonophonicNote> _prioritizeMelodyStrict({
    required String grandStaffId,
    required List<HarmonicStack> stacks,
  }) {
    final melody = <MonophonicNote>[];

    for (final stack in stacks) {
      final trebleNotes = stack.notes.where((n) {
        return n.staffRole == 'treble' &&
            n.defaultKeyLabel != null &&
            n.defaultKeyLabel!.trim().isNotEmpty;
      }).toList();

      if (trebleNotes.isEmpty) continue;

      trebleNotes.sort((a, b) {
        return _pitchToMidiValue(
          b.defaultKeyLabel!,
        ).compareTo(_pitchToMidiValue(a.defaultKeyLabel!));
      });

      final selected = trebleNotes.first;

      melody.add(
        MonophonicNote(
          id: '${grandStaffId}_strict_${stack.eventIndex}',
          grandStaffId: grandStaffId,
          eventIndex: stack.eventIndex,
          measureId: stack.measureId,
          measureIndex: stack.measureIndex,
          sourceX: stack.sourceX,
          pitch: selected.defaultKeyLabel!,
          sourceNote: selected,
          harmonyContext: stack.notes
              .map((n) => n.defaultKeyLabel ?? 'Unresolved')
              .toList(),
          selectionReason: 'strict_treble_only',
        ),
      );
    }

    return melody;
  }

  int _pitchToMidiValue(String pitch) {
    final match = RegExp(r'^([A-G])([#b]?)(-?\d+)$').firstMatch(pitch);
    if (match == null) return -9999;

    final letter = match.group(1)!;
    final accidental = match.group(2) ?? '';
    final octave = int.tryParse(match.group(3) ?? '') ?? 0;

    const baseSemitones = {
      'C': 0,
      'D': 2,
      'E': 4,
      'F': 5,
      'G': 7,
      'A': 9,
      'B': 11,
    };

    var semitone = baseSemitones[letter] ?? 0;

    if (accidental == '#') semitone += 1;
    if (accidental == 'b') semitone -= 1;

    return ((octave + 1) * 12) + semitone;
  }

  double _estimateHarmonicThreshold(List<_HarmonicCandidate> candidates) {
    if (candidates.length < 2) return 8.0;

    final gaps = <double>[];

    for (int i = 0; i < candidates.length - 1; i++) {
      final dx = (candidates[i + 1].centerX - candidates[i].centerX).abs();

      if (dx > 0) {
        gaps.add(dx);
      }
    }

    if (gaps.isEmpty) return 8.0;

    gaps.sort();

    final medianGap = gaps[gaps.length ~/ 2];

    return (medianGap * 0.35).clamp(6.0, 18.0);
  }
}

class _ChordResult {
  final String chordName;
  final String root;
  final String quality;

  const _ChordResult({
    required this.chordName,
    required this.root,
    required this.quality,
  });
}
```

<div style="page-break-after: always;"></div>

# File 9 — generation_service.dart

## Full Path

```text
D:\MyApps\AndroidStudio_Folder\stala_app\lib\services\generation_service.dart
```

## Purpose

This file converts finalized tablature events into drawable tab columns, rows, fretboard highlight frames, and export pages. It supports the thesis objective of presenting the OMR translation as usable guitar tablature. It is important because it structures the final result for review, playback visualization, and export.

## Full Source Code

```dart
import '../models/tablature_result.dart';

class GeneratedTabResult {
  final String title;
  final TranslationMode mode;
  final List<GeneratedTabColumn> columns;
  final List<GeneratedTabRow> rows;
  final List<FretboardHighlightFrame> fretboardFrames;
  final List<TabExportPage> exportPages;
  final double totalWidth;
  final double rowHeight;
  final double columnWidth;

  const GeneratedTabResult({
    required this.title,
    required this.mode,
    required this.columns,
    required this.rows,
    required this.fretboardFrames,
    required this.exportPages,
    required this.totalWidth,
    required this.rowHeight,
    required this.columnWidth,
  });

  GeneratedTabColumn? columnForEvent(int eventIndex) {
    for (final column in columns) {
      if (column.eventIndex == eventIndex) return column;
    }
    return null;
  }

  FretboardHighlightFrame? fretboardFrameForEvent(int eventIndex) {
    for (final frame in fretboardFrames) {
      if (frame.eventIndex == eventIndex) return frame;
    }
    return null;
  }
}

class GeneratedTabRow {
  final int stringNumber;
  final String label;
  final int visualIndex;

  const GeneratedTabRow({
    required this.stringNumber,
    required this.label,
    required this.visualIndex,
  });
}

class GeneratedTabColumn {
  final int eventIndex;
  final String label;
  final int? measureIndex;
  final bool startsMeasure;
  final double durationSeconds;
  final double x;
  final double width;
  final List<GeneratedTabNumber> numbers;
  final EventDetail eventDetail;

  const GeneratedTabColumn({
    required this.eventIndex,
    required this.label,
    this.measureIndex,
    this.startsMeasure = false,
    required this.durationSeconds,
    required this.x,
    required this.width,
    required this.numbers,
    required this.eventDetail,
  });

  bool get isRest => numbers.isEmpty;
  bool get isChord => numbers.length > 1;
}

class GeneratedTabNumber {
  final int eventIndex;
  final int stringNumber;
  final int fret;
  final String pitch;
  final double x;
  final int visualRowIndex;

  const GeneratedTabNumber({
    required this.eventIndex,
    required this.stringNumber,
    required this.fret,
    required this.pitch,
    required this.x,
    required this.visualRowIndex,
  });
}

class EventDetail {
  final int eventIndex;
  final String label;
  final double durationSeconds;
  final List<TabPosition> positions;

  const EventDetail({
    required this.eventIndex,
    required this.label,
    required this.durationSeconds,
    required this.positions,
  });

  String get displayTitle {
    if (positions.isEmpty) return 'Rest';
    if (positions.length > 1) return label.isNotEmpty ? label : 'Chord';
    return label.isNotEmpty ? label : positions.first.pitch;
  }

  String get displaySubtitle {
    if (positions.isEmpty) {
      return 'No fretboard position';
    }

    if (positions.length == 1) {
      final p = positions.first;
      return 'String: ${p.stringNumber}, Fret: ${p.fret}';
    }

    return positions.map((p) => 'S${p.stringNumber}:F${p.fret}').join('  •  ');
  }
}

class FretboardHighlightFrame {
  final int eventIndex;
  final String label;
  final List<TabPosition> highlights;

  const FretboardHighlightFrame({
    required this.eventIndex,
    required this.label,
    required this.highlights,
  });
}

class TabExportPage {
  final int pageIndex;
  final int startEventIndex;
  final int endEventIndex;
  final List<GeneratedTabColumn> columns;

  const TabExportPage({
    required this.pageIndex,
    required this.startEventIndex,
    required this.endEventIndex,
    required this.columns,
  });
}

class GenerationService {
  static const List<GeneratedTabRow> standardGuitarRows = [
    GeneratedTabRow(stringNumber: 6, label: 'E', visualIndex: 0), // Low E
    GeneratedTabRow(stringNumber: 5, label: 'A', visualIndex: 1),
    GeneratedTabRow(stringNumber: 4, label: 'D', visualIndex: 2),
    GeneratedTabRow(stringNumber: 3, label: 'G', visualIndex: 3),
    GeneratedTabRow(stringNumber: 2, label: 'B', visualIndex: 4),
    GeneratedTabRow(stringNumber: 1, label: 'e', visualIndex: 5), // High E
  ];

  const GenerationService();

  GeneratedTabResult generate({
    required TablatureResult result,
    double columnWidth = 48,
    double rowHeight = 32,
    int exportEventsPerPage = 24,
  }) {
    final columns = <GeneratedTabColumn>[];

    for (int i = 0; i < result.events.length; i++) {
      final event = result.events[i];
      final previous = i > 0 ? result.events[i - 1] : null;
      final startsMeasure = _startsMeasure(event, previous);
      final measureGap = startsMeasure && i > 0 ? columnWidth * 0.45 : 0.0;
      final eventWidth = _widthForDuration(event.durationSeconds, columnWidth);
      final x =
          (columns.isEmpty ? 0.0 : columns.last.x + columns.last.width) +
          measureGap;

      columns.add(
        GeneratedTabColumn(
          eventIndex: event.eventIndex,
          label: event.label,
          measureIndex: _metadataInt(event, 'measureIndex'),
          startsMeasure: startsMeasure,
          durationSeconds: event.durationSeconds,
          x: x,
          width: eventWidth,
          numbers: _buildNumbers(event: event, x: x + (eventWidth / 2)),
          eventDetail: EventDetail(
            eventIndex: event.eventIndex,
            label: event.label,
            durationSeconds: event.durationSeconds,
            positions: event.positions,
          ),
        ),
      );
    }

    final fretboardFrames = result.events.map((event) {
      return FretboardHighlightFrame(
        eventIndex: event.eventIndex,
        label: event.label,
        highlights: event.positions,
      );
    }).toList();

    return GeneratedTabResult(
      title: result.title,
      mode: result.mode,
      columns: columns,
      rows: standardGuitarRows,
      fretboardFrames: fretboardFrames,
      exportPages: _buildExportPages(
        columns: columns,
        eventsPerPage: exportEventsPerPage,
      ),
      totalWidth: columns.isEmpty ? 0.0 : columns.last.x + columns.last.width,
      rowHeight: rowHeight,
      columnWidth: columnWidth,
    );
  }

  List<GeneratedTabResult> generateAll({
    required List<TablatureResult> results,
    double columnWidth = 48,
    double rowHeight = 32,
    int exportEventsPerPage = 24,
  }) {
    return results.map((result) {
      return generate(
        result: result,
        columnWidth: columnWidth,
        rowHeight: rowHeight,
        exportEventsPerPage: exportEventsPerPage,
      );
    }).toList();
  }

  List<GeneratedTabNumber> _buildNumbers({
    required TablatureEvent event,
    required double x,
  }) {
    return event.positions.map((position) {
      return GeneratedTabNumber(
        eventIndex: event.eventIndex,
        stringNumber: position.stringNumber,
        fret: position.fret,
        pitch: position.pitch,
        x: x,
        visualRowIndex: _visualRowIndexForString(position.stringNumber),
      );
    }).toList();
  }

  int _visualRowIndexForString(int stringNumber) {
    switch (stringNumber) {
      case 6:
        return 0;
      case 5:
        return 1;
      case 4:
        return 2;
      case 3:
        return 3;
      case 2:
        return 4;
      case 1:
        return 5;
      default:
        return 5;
    }
  }

  double _widthForDuration(double durationSeconds, double columnWidth) {
    final multiplier = durationSeconds.clamp(0.5, 2.5).toDouble();
    return columnWidth * multiplier;
  }

  bool _startsMeasure(TablatureEvent event, TablatureEvent? previous) {
    if (previous == null) return true;

    final currentMeasure = _metadataInt(event, 'measureIndex');
    final previousMeasure = _metadataInt(previous, 'measureIndex');

    if (currentMeasure == null || previousMeasure == null) return false;
    return currentMeasure != previousMeasure;
  }

  int? _metadataInt(TablatureEvent event, String key) {
    final value = event.metadata[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  List<TabExportPage> _buildExportPages({
    required List<GeneratedTabColumn> columns,
    required int eventsPerPage,
  }) {
    if (columns.isEmpty) return const [];

    final pages = <TabExportPage>[];

    for (int start = 0; start < columns.length; start += eventsPerPage) {
      final endExclusive = (start + eventsPerPage > columns.length)
          ? columns.length
          : start + eventsPerPage;

      final pageColumns = columns.sublist(start, endExclusive);

      pages.add(
        TabExportPage(
          pageIndex: pages.length,
          startEventIndex: pageColumns.first.eventIndex,
          endEventIndex: pageColumns.last.eventIndex,
          columns: pageColumns,
        ),
      );
    }

    return pages;
  }
}
```

<div style="page-break-after: always;"></div>

# File 10 — event_manager_service.dart

## Full Path

```text
D:\MyApps\AndroidStudio_Folder\stala_app\lib\services\event_manager_service.dart
```

## Purpose

This file optimizes selected fretboard candidates across sequential events using dynamic programming and playability scoring. It supports the thesis objective of producing practical guitar tablature rather than only theoretically correct pitch mappings. It is important because it minimizes awkward transitions and chooses playable positions for the final tab line.

## Full Source Code

```dart
import 'fretboard_mapping_service.dart';
import 'playability_scoring_service.dart';

class PlayableEvent {
  final int eventIndex;
  final String label;
  final String? measureId;
  final int? measureIndex;
  final double? sourceX;
  final List<GuitarPosition> chosenPositions;
  final double transitionCost;

  const PlayableEvent({
    required this.eventIndex,
    required this.label,
    this.measureId,
    this.measureIndex,
    this.sourceX,
    required this.chosenPositions,
    required this.transitionCost,
  });
}

class ManagedEventLine {
  final String sourceLineId;
  final String title;
  final List<PlayableEvent> events;
  final double totalCost;

  const ManagedEventLine({
    required this.sourceLineId,
    required this.title,
    required this.events,
    required this.totalCost,
  });
}

class EventManagerResult {
  final List<ManagedEventLine> lines;

  const EventManagerResult({required this.lines});
}

class EventManagerService {
  final PlayabilityScoringService _playabilityScoring =
      const PlayabilityScoringService();

  EventManagerResult manage({
    required FretboardMappingResult fretboardMapping,
  }) {
    final lines = fretboardMapping.lines
        .where(
          (line) =>
              line.id.contains('treble') || line.id.contains('grand_staff'),
        )
        .map(_optimizeLine)
        .whereType<ManagedEventLine>()
        .toList();

    return EventManagerResult(lines: lines);
  }

  ManagedEventLine? _optimizeLine(FretboardMappedLine line) {
    final events = line.events
        .where((event) => event.candidates.isNotEmpty)
        .toList();

    if (events.isEmpty) return null;

    final path = _findLowestCostPath(events);
    if (path.isEmpty) return null;

    double totalCost = 0;

    final playableEvents = <PlayableEvent>[];

    for (int i = 0; i < path.length; i++) {
      final current = path[i];
      final previous = i > 0 ? path[i - 1] : null;

      final cost = previous == null
          ? _initialCandidateCost(current)
          : _transitionCost(previous, current);

      totalCost += cost;

      playableEvents.add(
        PlayableEvent(
          eventIndex: events[i].eventIndex,
          label: events[i].label,
          measureId: events[i].measureId,
          measureIndex: events[i].measureIndex,
          sourceX: events[i].sourceX,
          chosenPositions: current.positions,
          transitionCost: cost,
        ),
      );
    }

    return ManagedEventLine(
      sourceLineId: line.id,
      title: line.title,
      events: playableEvents,
      totalCost: totalCost,
    );
  }

  List<FretboardCandidate> _findLowestCostPath(
    List<FretboardMappedEvent> events,
  ) {
    final dp = <Map<int, _PathState>>[];

    // First event
    final firstStates = <int, _PathState>{};
    for (int i = 0; i < events.first.candidates.length; i++) {
      final candidate = events.first.candidates[i];

      firstStates[i] = _PathState(
        cost: _initialCandidateCost(candidate),
        previousIndex: null,
      );
    }

    dp.add(firstStates);

    // Remaining events
    for (int eventIndex = 1; eventIndex < events.length; eventIndex++) {
      final prevCandidates = events[eventIndex - 1].candidates;
      final currCandidates = events[eventIndex].candidates;

      final currStates = <int, _PathState>{};

      for (int currIndex = 0; currIndex < currCandidates.length; currIndex++) {
        final curr = currCandidates[currIndex];

        double bestCost = double.infinity;
        int? bestPrevIndex;

        for (
          int prevIndex = 0;
          prevIndex < prevCandidates.length;
          prevIndex++
        ) {
          final prevState = dp[eventIndex - 1][prevIndex];
          if (prevState == null) continue;

          final prev = prevCandidates[prevIndex];

          final cost = prevState.cost + _transitionCost(prev, curr);

          if (cost < bestCost) {
            bestCost = cost;
            bestPrevIndex = prevIndex;
          }
        }

        currStates[currIndex] = _PathState(
          cost: bestCost,
          previousIndex: bestPrevIndex,
        );
      }

      dp.add(currStates);
    }

    // Find best final candidate
    final lastStates = dp.last;

    int? bestFinalIndex;
    double bestFinalCost = double.infinity;

    for (final entry in lastStates.entries) {
      if (entry.value.cost < bestFinalCost) {
        bestFinalCost = entry.value.cost;
        bestFinalIndex = entry.key;
      }
    }

    if (bestFinalIndex == null) return const [];

    // Backtrack
    final path = List<FretboardCandidate?>.filled(events.length, null);
    int? currentIndex = bestFinalIndex;

    for (int eventIndex = events.length - 1; eventIndex >= 0; eventIndex--) {
      if (currentIndex == null) break;

      path[eventIndex] = events[eventIndex].candidates[currentIndex];
      currentIndex = dp[eventIndex][currentIndex]?.previousIndex;
    }

    return path.whereType<FretboardCandidate>().toList();
  }

  double _initialCandidateCost(FretboardCandidate candidate) {
    return _playabilityScoring.initialCandidateCost(candidate).cost;
  }

  double _transitionCost(
    FretboardCandidate previous,
    FretboardCandidate current,
  ) {
    return _playabilityScoring.transitionCost(previous, current);
  }
}

class _PathState {
  final double cost;
  final int? previousIndex;

  const _PathState({required this.cost, required this.previousIndex});
}
```

<div style="page-break-after: always;"></div>

# Appendix Notes

This appendix contains a total of 10 project-owned source files.

The approximate total lines of code included are 10478 lines.

This appendix contains the core implementation files of the STALA OMR-to-Tablature pipeline, covering document preparation, ONNX symbol detection, staff segmentation, translation grouping, polyphonic and monophonic interpretation, fretboard mapping, playability-aware event management, chord voicing, and final tablature generation.
