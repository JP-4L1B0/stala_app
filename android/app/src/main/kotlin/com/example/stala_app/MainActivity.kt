package com.example.stala_app

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import android.os.Bundle
import android.util.Log
import org.opencv.android.OpenCVLoader

class MainActivity : FlutterActivity() {
    private val accessibilityChannel = "stala_app/accessibility"
    private val pythonBridgeChannel = "stala/python_bridge"

    private var onnxDetector: OnnxDetector? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        onnxDetector = OnnxDetector(this)

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
                "validateSelectedCrop" -> handleValidateSelectedCrop(call, result)
                "cropDocumentImage" -> handleCropDocumentImage(call, result)
                "processImage" -> handleProcessImage(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun handleValidateSelectedCrop(call: MethodCall, result: MethodChannel.Result) {
        val imagePath = call.argument<String>("imagePath")
        val bounds = call.argument<Map<String, Any?>>("bounds")

        if (imagePath.isNullOrBlank() || bounds == null) {
            result.success(
                mapOf(
                    "validationState" to "fail",
                    "confidence" to 0.0,
                    "reason" to "The selected crop is not yet a reliable music-sheet region."
                )
            )
            return
        }

        try {
            val validation = DocumentProcessor.validateSelectedCrop(
                imagePath = imagePath,
                bounds = bounds
            )
            result.success(validation)
        } catch (e: Exception) {
            result.success(
                mapOf(
                    "validationState" to "fail",
                    "confidence" to 0.0,
                    "reason" to "Validation failed: ${e.message ?: "Unknown error"}"
                )
            )
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
            result.error("INVALID_PATH", "Image path is missing.", null)
            return
        }

        if (bounds == null) {
            result.error("INVALID_BOUNDS", "Crop bounds are missing.", null)
            return
        }

        try {
            val croppedPath = DocumentProcessor.cropDocumentImage(
                imagePath = imagePath,
                bounds = bounds
            )

            if (croppedPath.isNullOrBlank()) {
                result.error("CROP_FAILED", "Crop returned empty result.", null)
                return
            }

            result.success(croppedPath)
        } catch (e: Exception) {
            result.error(
                "CROP_EXCEPTION",
                e.message ?: "Unknown crop error",
                null
            )
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
                    "imageWidth" to 0,
                    "imageHeight" to 0,
                    "detections" to emptyList<Map<String, Any?>>(),
                    "staffMap" to emptyList<Any>(),
                    "translationResult" to emptyList<Any>(),
                    "tablature" to emptyList<Any>(),
                    "errors" to listOf("Image path is missing.")
                )
            )
            return
        }

        Thread {
            try {
                android.util.Log.d("STALA_ONNX", "handleProcessImage called")
                android.util.Log.d("STALA_ONNX", "imagePath=$imagePath")

                val detector = onnxDetector ?: OnnxDetector(this).also { onnxDetector = it }

                android.util.Log.d("STALA_ONNX", "loading model")
                detector.loadModel("models/stala_notehead_detector.onnx")

                android.util.Log.d("STALA_ONNX", "running detectFromImagePath")
                val response = detector.detectFromImagePath(imagePath)

                android.util.Log.d("STALA_ONNX", "detection finished")
                android.util.Log.d("STALA_ONNX", "response status=${response["status"]}")

                runOnUiThread {
                    result.success(response)
                }
            } catch (e: Exception) {
                android.util.Log.e("STALA_ONNX", "ONNX processing failed", e)

                runOnUiThread {
                    result.success(
                        mapOf(
                            "status" to "error",
                            "message" to "ONNX processing failed: ${e.message ?: "Unknown error"}",
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
                            "errors" to listOf("ONNX processing failed: ${e.message ?: "Unknown error"}")
                        )
                    )
                }
            }
        }.start()
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (OpenCVLoader.initDebug()) {
            Log.d("OpenCV", "OpenCV loaded successfully")
        } else {
            Log.e("OpenCV", "OpenCV failed to load")
        }
    }
}