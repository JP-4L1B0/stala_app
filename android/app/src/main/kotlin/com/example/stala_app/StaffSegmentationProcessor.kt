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
