package com.example.stala_app

import android.graphics.BitmapFactory
import java.io.File

object PipelineProcessor {

    fun processImage(imagePath: String): Map<String, Any?> {
        if (imagePath.isBlank()) {
            return errorResponse(
                imagePath = "",
                message = "Image path is missing."
            )
        }

        val imageFile = File(imagePath)
        if (!imageFile.exists()) {
            return errorResponse(
                imagePath = imagePath,
                message = "Input image file does not exist."
            )
        }

        return try {
            // Stage 1: validate and inspect image
            val bitmap = BitmapFactory.decodeFile(imagePath)
                ?: return errorResponse(
                    imagePath = imagePath,
                    message = "Failed to decode input image."
                )

            val imageWidth = bitmap.width
            val imageHeight = bitmap.height
            bitmap.recycle()

            // Stage 2: placeholder preprocessing
            // For now, we keep the same image path.
            // Later, this can become a real output file path.
            val preprocessedImagePath = imagePath

            // Stage 3: placeholder detection result
            // Keep this as dummy data for now, but make it clearly stage-owned.
            val detections = listOf(
                mapOf(
                    "className" to "notehead",
                    "confidence" to 0.93,
                    "bbox" to listOf(120, 180, 156, 214)
                ),
                mapOf(
                    "className" to "notehead",
                    "confidence" to 0.88,
                    "bbox" to listOf(220, 260, 252, 292)
                )
            )

            // Stage 4: placeholder downstream outputs
            val staffMap = emptyList<Any>()
            val translationResult = emptyList<Any>()
            val tablature = emptyList<Any>()
            val errors = emptyList<String>()

            successResponse(
                imagePath = imagePath,
                preprocessedImagePath = preprocessedImagePath,
                detectionImagePath = preprocessedImagePath,
                imageWidth = imageWidth,
                imageHeight = imageHeight,
                detections = detections,
                staffMap = staffMap,
                translationResult = translationResult,
                tablature = tablature,
                message = "Pipeline completed successfully.",
                modelVersion = "notehead_dummy_v1"
            )
        } catch (e: Exception) {
            errorResponse(
                imagePath = imagePath,
                message = "Processing failed: ${e.message ?: "Unknown error"}"
            )
        }
    }

    private fun successResponse(
        imagePath: String,
        preprocessedImagePath: String,
        detectionImagePath: String,
        imageWidth: Int,
        imageHeight: Int,
        detections: List<Map<String, Any>>,
        staffMap: List<Any>,
        translationResult: List<Any>,
        tablature: List<Any>,
        message: String,
        modelVersion: String
    ): Map<String, Any?> {
        return mapOf(
            "status" to "success",
            "message" to message,
            "modelVersion" to modelVersion,
            "inputImagePath" to imagePath,
            "preprocessedImagePath" to preprocessedImagePath,
            "detectionImagePath" to detectionImagePath,
            "imageWidth" to imageWidth,
            "imageHeight" to imageHeight,
            "detections" to detections,
            "staffMap" to staffMap,
            "translationResult" to translationResult,
            "tablature" to tablature,
            "errors" to emptyList<String>()
        )
    }

    private fun errorResponse(
        imagePath: String,
        message: String
    ): Map<String, Any?> {
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
}