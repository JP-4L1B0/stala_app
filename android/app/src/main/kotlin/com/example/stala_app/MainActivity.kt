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

        // Temporary placeholder response.
        // Replace this later with OpenCV or Chaquopy logic.
        result.success(
            mapOf(
                "hasDocument" to false,
                "confidence" to 0.0,
                "reason" to "Auto-crop detection is not implemented yet."
            )
        )
    }

    private fun handleCropDocumentImage(call: MethodCall, result: MethodChannel.Result) {
        val imagePath = call.argument<String>("imagePath")

        if (imagePath.isNullOrBlank()) {
            result.success("")
            return
        }

        // Temporary fallback:
        // return original path until real crop logic is added.
        result.success(imagePath)
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