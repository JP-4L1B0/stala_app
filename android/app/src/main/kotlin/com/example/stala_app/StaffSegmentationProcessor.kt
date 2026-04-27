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

object StaffSegmentationProcessor {

    fun segmentStaffLines(
        context: Context,
        imagePath: String
    ): Map<String, Any?> {

        val src = Imgcodecs.imread(imagePath)
        if (src.empty()) {
            return error("Failed to load image")
        }

        val gray = Mat()
        Imgproc.cvtColor(src, gray, Imgproc.COLOR_BGR2GRAY)

        val binary = Mat()
        Imgproc.adaptiveThreshold(
            gray,
            binary,
            255.0,
            Imgproc.ADAPTIVE_THRESH_MEAN_C,
            Imgproc.THRESH_BINARY_INV,
            15,
            2.0
        )

        // Extract horizontal lines
        val horizontal = binary.clone()
        val kernelWidth = src.cols() / 15
        val horizontalKernel = Imgproc.getStructuringElement(
            Imgproc.MORPH_RECT,
            Size(kernelWidth.toDouble(), 1.0)
        )

        Imgproc.erode(horizontal, horizontal, horizontalKernel)
        Imgproc.dilate(horizontal, horizontal, horizontalKernel)

        // Detect row intensities
        val rowStrength = mutableListOf<Pair<Int, Int>>()

        for (y in 0 until horizontal.rows()) {
            var count = 0
            for (x in 0 until horizontal.cols()) {
                if (horizontal.get(y, x)[0] > 0) count++
            }
            rowStrength.add(y to count)
        }

        val threshold = src.cols() * 0.3
        val rawRows = rowStrength
            .filter { it.second > threshold }
            .map { it.first }

        val deduped = deduplicateRows(rawRows)

        val staffs = buildValidatedStaffs(deduped)

        val ledgerLines = detectLedgerLines(
            binary = binary,
            staffs = staffs
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

        val staffLines = staffs.flatMap { staff ->
            val staffId = staff["id"] as String
            val topBoundary = staff["topBoundary"] as Double
            val bottomBoundary = staff["bottomBoundary"] as Double
            val spacing = staff["spacing"] as Double
            val lines = staff["lines"] as List<Double>

            lines.mapIndexed { index, y ->
                mapOf(
                    "id" to "${staffId}_line_$index",
                    "staffId" to staffId,
                    "y" to y,
                    "topBoundary" to topBoundary,
                    "bottomBoundary" to bottomBoundary,
                    "spacing" to spacing
                )
            }
        }

        val outputPath = saveImage(context, overlay)

        Log.d("STAFF_SEGMENT", "ledger final count=${ledgerLines.size}")

        return mapOf(
            "status" to "success",
            "message" to "Native OpenCV segmentation completed",
            "segmentedImagePath" to outputPath,
            "staffLineCount" to staffs.sumOf { (it["lines"] as List<*>).size },
            "staffLines" to staffLines,
            "ledgerLines" to ledgerLines,
            "validatedStaffs" to staffs
        )
    }

    private fun deduplicateRows(rawRows: List<Int>): List<Double> {
        if (rawRows.isEmpty()) return emptyList()

        val groups = mutableListOf<MutableList<Int>>()
        var current = mutableListOf(rawRows.first())

        for (i in 1 until rawRows.size) {
            if (rawRows[i] - rawRows[i - 1] <= 2) {
                current.add(rawRows[i])
            } else {
                groups.add(current)
                current = mutableListOf(rawRows[i])
            }
        }
        groups.add(current)

        return groups.map { it.average() }.sorted()
    }

    private fun buildValidatedStaffs(lines: List<Double>): List<Map<String, Any>> {
        val staffs = mutableListOf<Map<String, Any>>()
        val used = mutableSetOf<Int>()

        for (i in 0..lines.size - 5) {
            if (used.contains(i)) continue

            val candidate = lines.subList(i, i + 5)

            val spacings = listOf(
                candidate[1] - candidate[0],
                candidate[2] - candidate[1],
                candidate[3] - candidate[2],
                candidate[4] - candidate[3]
            )

            val avg = spacings.average()

            if (avg < 6 || avg > 40) continue

            val consistent = spacings.all {
                Math.abs(it - avg) <= avg * 0.3
            }

            if (!consistent) continue

            staffs.add(
                mapOf(
                    "id" to "staff_${staffs.size}",
                    "lines" to candidate,
                    "spacing" to avg,
                    "topBoundary" to candidate.first() - avg * 1.2,
                    "bottomBoundary" to candidate.last() + avg * 1.2
                )
            )

            for (k in 0 until 5) used.add(i + k)
        }

        return staffs
    }

    private fun detectLedgerLines(
        binary: Mat,
        staffs: List<Map<String, Any>>
    ): List<Map<String, Any>> {
        val ledgerLines = mutableListOf<Map<String, Any>>()
        var ledgerIndex = 0

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

                if (kotlin.math.abs(y.toDouble() - nearestVirtualLineY) > spacing * 0.25) {
                    continue
                }

                for (segment in segments) {
                    val x1 = segment.first
                    val x2 = segment.second
                    val width = x2 - x1

                    val minWidth = spacing * 1.4
                    val maxWidth = spacing * 4.0

                    if (width < minWidth || width > maxWidth) continue

                    val position = if (y < topLine) "above" else "below"

                    ledgerLines.add(
                        mapOf(
                            "id" to "ledger_${ledgerIndex++}",
                            "staffId" to staffId,
                            "x1" to x1,
                            "x2" to x2,
                            "y" to y.toDouble(),
                            "position" to position
                        )
                    )
                }
            }
        }
        Log.d("STAFF_SEGMENT", "ledger raw count=${ledgerLines.size}")

        return deduplicateLedgerLines(ledgerLines)
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
            "validatedStaffs" to emptyList<Any>()
        )
    }
}