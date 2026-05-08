package com.example.stala_app

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object RuntimeFileLogger {
    private const val LOG_FILE_NAME = "stala_runtime_log.txt"

    private fun logFile(context: Context): File {
        return File(context.filesDir, LOG_FILE_NAME)
    }

    fun log(context: Context, message: String) {
        try {
            val timestamp = SimpleDateFormat(
                "yyyy-MM-dd HH:mm:ss.SSS",
                Locale.US
            ).format(Date())

            logFile(context).appendText("[$timestamp] $message\n")
        } catch (_: Exception) {
        }
    }

    fun clear(context: Context) {
        try {
            logFile(context).writeText("")
        } catch (_: Exception) {
        }
    }

    fun exportToDownloads(context: Context): String {
        val source = logFile(context)

        if (!source.exists()) {
            source.writeText("No runtime log entries yet.\n")
        }

        val exportName = "STALA_runtime_log_${System.currentTimeMillis()}.txt"

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = context.contentResolver

            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, exportName)
                put(MediaStore.Downloads.MIME_TYPE, "text/plain")
                put(
                    MediaStore.Downloads.RELATIVE_PATH,
                    Environment.DIRECTORY_DOWNLOADS + "/STALA Logs"
                )
            }

            val uri = resolver.insert(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                values
            ) ?: throw IllegalStateException("Failed to create log export file.")

            resolver.openOutputStream(uri)?.use { output ->
                source.inputStream().use { input ->
                    input.copyTo(output)
                }
            }

            "Downloads/STALA Logs/$exportName"
        } else {
            val dir = File(
                Environment.getExternalStoragePublicDirectory(
                    Environment.DIRECTORY_DOWNLOADS
                ),
                "STALA Logs"
            )

            if (!dir.exists()) dir.mkdirs()

            val target = File(dir, exportName)
            source.copyTo(target, overwrite = true)

            target.absolutePath
        }
    }
}