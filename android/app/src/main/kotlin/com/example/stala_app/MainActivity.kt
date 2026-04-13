package com.example.stala_app

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val accessibilityChannel = "stala_app/accessibility"
    private val pythonBridgeChannel = "stala/python_bridge"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            accessibilityChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAccessibilityEnabled" -> {
                    result.success(isMyAccessibilityServiceEnabled())
                }

                "openAccessibilitySettings" -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            pythonBridgeChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "detectDocumentBounds" -> handleDetectDocumentBounds(call, result)
                "cropDocumentImage" -> handleCropDocumentImage(call, result)
                "processImage" -> handleProcessImage(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun handleDetectDocumentBounds(call: MethodCall, result: MethodChannel.Result) {
        val imagePath = call.argument<String>("imagePath")

        if (imagePath.isNullOrBlank()) {
            result.success(
                mapOf(
                    "hasDocument" to false,
                    "confidence" to 0.0,
                    "reason" to "Image path is missing."
                )
            )
            return
        }

        try {
            val detection = DocumentProcessor.detectDocumentBounds(imagePath)
            result.success(detection)
        } catch (e: Exception) {
            result.success(
                mapOf(
                    "hasDocument" to false,
                    "confidence" to 0.0,
                    "reason" to "Detection failed: ${e.message ?: "Unknown error"}"
                )
            )
        }
    }

    private fun handleCropDocumentImage(call: MethodCall, result: MethodChannel.Result) {
        val imagePath = call.argument<String>("imagePath")
        val bounds = call.argument<Map<String, Any?>>("bounds")

        if (imagePath.isNullOrBlank()) {
            result.success("")
            return
        }

        if (bounds == null) {
            result.success(imagePath)
            return
        }

        try {
            val croppedPath = DocumentProcessor.cropDocumentImage(
                imagePath = imagePath,
                bounds = bounds
            )

            result.success(croppedPath ?: imagePath)
        } catch (e: Exception) {
            result.success(imagePath)
        }
    }

    private fun handleProcessImage(call: MethodCall, result: MethodChannel.Result) {
        val imagePath = call.argument<String>("imagePath")

        if (imagePath.isNullOrBlank()) {
            result.success(
                mapOf(
                    "status" to "error",
                    "message" to "Image path is missing.",
                    "modelVersion" to "unavailable",
                    "inputImagePath" to "",
                    "preprocessedImagePath" to "",
                    "detectionImagePath" to "",
                    "detections" to emptyList<Map<String, Any?>>(),
                    "staffMap" to emptyList<Any>(),
                    "translationResult" to emptyList<Any>(),
                    "tablature" to emptyList<Any>(),
                    "errors" to listOf("Image path is missing.")
                )
            )
            return
        }

        try {
            // Temporary dummy response for bridge testing.
            // Replace this later with real Python / Chaquopy pipeline call.
            val response = mapOf(
                "status" to "success",
                "message" to "Dummy processing completed.",
                "modelVersion" to "notehead_dummy_v1",
                "inputImagePath" to imagePath,
                "preprocessedImagePath" to imagePath,
                "detectionImagePath" to imagePath,
                "detections" to listOf(
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
                ),
                "staffMap" to emptyList<Any>(),
                "translationResult" to emptyList<Any>(),
                "tablature" to emptyList<Any>(),
                "errors" to emptyList<String>()
            )

            result.success(response)
        } catch (e: Exception) {
            result.success(
                mapOf(
                    "status" to "error",
                    "message" to "Processing failed: ${e.message ?: "Unknown error"}",
                    "modelVersion" to "unavailable",
                    "inputImagePath" to imagePath,
                    "preprocessedImagePath" to "",
                    "detectionImagePath" to "",
                    "detections" to emptyList<Map<String, Any?>>(),
                    "staffMap" to emptyList<Any>(),
                    "translationResult" to emptyList<Any>(),
                    "tablature" to emptyList<Any>(),
                    "errors" to listOf("Processing failed: ${e.message ?: "Unknown error"}")
                )
            )
        }
    }

    private fun isMyAccessibilityServiceEnabled(): Boolean {
        val expectedService = "$packageName/com.example.stala_app.MyAccessibilityService"
        val enabledServices = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false

        return enabledServices.split(":").any {
            it.equals(expectedService, ignoreCase = true)
        }
    }
}