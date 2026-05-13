package com.example.stala_app

import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import android.os.Bundle
import android.os.Environment
import android.util.Log
import org.opencv.android.OpenCVLoader
import java.io.File
import java.io.FileNotFoundException

class MainActivity : FlutterActivity() {
    private val accessibilityChannel = "stala_app/accessibility"
    private val visionPipelineChannel = "stala/python_bridge"
    private val storageAccessChannel = "stala/storage_access"
    private val storagePrefsName = "stala_storage_access"
    private val storageFolderUriKey = "storage_folder_uri"
    private val pickStorageFolderRequestCode = 4107
    private val pickImportDocumentRequestCode = 4108

    private var onnxDetector: OnnxDetector? = null
    private var pendingStoragePickResult: MethodChannel.Result? = null
    private var pendingImportPickResult: MethodChannel.Result? = null

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
            visionPipelineChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "detectDocumentBounds" -> handleDetectDocumentBounds(call, result)
                "validateSelectedCrop" -> handleValidateSelectedCrop(call, result)
                "cropDocumentImage" -> handleCropDocumentImage(call, result)
                "processImage" -> handleProcessImage(call, result)
                "segmentStaffLines" -> handleSegmentStaffLines(call, result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            storageAccessChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickStorageFolder" -> handlePickStorageFolder(result)
                "pickImportDocument" -> handlePickImportDocument(result)
                "getPublicStalaFolder" -> handleGetPublicStalaFolder(result)
                "listPublicFiles" -> handleListPublicFiles(call, result)
                "writePublicTextFile" -> handleWritePublicTextFile(call, result)
                "writePublicBinaryFile" -> handleWritePublicBinaryFile(call, result)
                "readPublicTextFile" -> handleReadPublicTextFile(call, result)
                "deletePublicFile" -> handleDeletePublicFile(call, result)
                "getStorageFolder" -> result.success(currentStorageFolderInfo())
                "clearStorageFolder" -> {
                    clearStorageFolder()
                    result.success(true)
                }
                "writeTextFile" -> handleWriteTextFile(call, result)
                "writeBinaryFile" -> handleWriteBinaryFile(call, result)
                "listFiles" -> handleListFiles(call, result)
                "readTextFile" -> handleReadTextFile(call, result)
                "writeTextToUri" -> handleWriteTextToUri(call, result)
                "deleteDocument" -> handleDeleteDocument(call, result)
                "renameDocument" -> handleRenameDocument(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun handlePickStorageFolder(result: MethodChannel.Result) {
        if (pendingStoragePickResult != null) {
            result.error("PICK_IN_PROGRESS", "A storage folder picker is already open.", null)
            return
        }

        pendingStoragePickResult = result

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
        }

        try {
            startActivityForResult(intent, pickStorageFolderRequestCode)
        } catch (e: Exception) {
            pendingStoragePickResult = null
            result.error("PICK_FAILED", e.message ?: "Unable to open folder picker.", null)
        }
    }

    private fun handlePickImportDocument(result: MethodChannel.Result) {
        if (pendingImportPickResult != null) {
            result.error("PICK_IN_PROGRESS", "An import picker is already open.", null)
            return
        }

        pendingImportPickResult = result

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf(
                    "application/zip",
                    "application/json",
                    "application/octet-stream",
                    "text/plain"
                )
            )
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        try {
            startActivityForResult(intent, pickImportDocumentRequestCode)
        } catch (e: Exception) {
            pendingImportPickResult = null
            result.error("PICK_FAILED", e.message ?: "Unable to open import picker.", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == pickImportDocumentRequestCode) {
            handleImportDocumentResult(resultCode, data)
            return
        }

        if (requestCode != pickStorageFolderRequestCode) return

        val result = pendingStoragePickResult ?: return
        pendingStoragePickResult = null

        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.success(
                mapOf(
                    "granted" to false,
                    "uri" to null,
                    "displayName" to null
                )
            )
            return
        }

        val flags = data.flags and (
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )

        try {
            contentResolver.takePersistableUriPermission(uri, flags)
        } catch (e: SecurityException) {
            Log.w("STALA_STORAGE", "Unable to persist URI permission", e)
        }

        getSharedPreferences(storagePrefsName, MODE_PRIVATE)
            .edit()
            .putString(storageFolderUriKey, uri.toString())
            .apply()

        result.success(
            mapOf(
                "granted" to true,
                "uri" to uri.toString(),
                "displayName" to displayNameForTreeUri(uri)
            )
        )
    }

    private fun handleImportDocumentResult(resultCode: Int, data: Intent?) {
        val result = pendingImportPickResult ?: return
        pendingImportPickResult = null

        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.success(null)
            return
        }

        try {
            val bytes = contentResolver.openInputStream(uri)?.use { input ->
                input.readBytes()
            } ?: throw FileNotFoundException("Unable to open selected file.")

            result.success(
                mapOf(
                    "fileName" to displayNameForDocumentUri(uri),
                    "mimeType" to contentResolver.getType(uri),
                    "bytes" to bytes
                )
            )
        } catch (e: Exception) {
            result.error("READ_FAILED", e.message ?: "Unable to read selected file.", null)
        }
    }

    private fun handleGetPublicStalaFolder(result: MethodChannel.Result) {
        try {
            val dir = publicStalaDirectory("")
            result.success(
                mapOf(
                    "granted" to true,
                    "uri" to dir.absolutePath,
                    "displayName" to dir.absolutePath
                )
            )
        } catch (e: Exception) {
            result.success(
                mapOf(
                    "granted" to false,
                    "uri" to null,
                    "displayName" to null
                )
            )
        }
    }

    private fun handleListPublicFiles(call: MethodCall, result: MethodChannel.Result) {
        val relativeDir = call.argument<String>("relativeDir") ?: ""
        val extension = call.argument<String>("extension")?.lowercase()

        try {
            val dir = publicStalaDirectory(relativeDir)
            val files = dir.listFiles()
                ?.filter { it.isFile }
                ?.filter { extension == null || it.name.lowercase().endsWith(extension) }
                ?.map {
                    mapOf(
                        "uri" to it.absolutePath,
                        "fileName" to it.name,
                        "mimeType" to null,
                        "lastModified" to it.lastModified(),
                        "size" to it.length()
                    )
                }
                ?: emptyList()

            result.success(files)
        } catch (e: Exception) {
            result.error("LIST_FAILED", e.message ?: "Unable to list public STALA files.", null)
        }
    }

    private fun handleWritePublicTextFile(call: MethodCall, result: MethodChannel.Result) {
        val relativeDir = call.argument<String>("relativeDir") ?: ""
        val fileName = call.argument<String>("fileName")
        val content = call.argument<String>("content")

        if (fileName.isNullOrBlank() || content == null) {
            result.error("INVALID_ARGS", "File name and content are required.", null)
            return
        }

        try {
            val dir = publicStalaDirectory(relativeDir)
            val file = File(dir, fileName)
            file.writeText(content, Charsets.UTF_8)

            result.success(writeResult(Uri.fromFile(file), relativeDir, fileName))
        } catch (e: Exception) {
            result.error("WRITE_FAILED", e.message ?: "Unable to write public STALA file.", null)
        }
    }

    private fun handleWritePublicBinaryFile(call: MethodCall, result: MethodChannel.Result) {
        val relativeDir = call.argument<String>("relativeDir") ?: ""
        val fileName = call.argument<String>("fileName")
        val bytes = call.argument<ByteArray>("bytes")

        if (fileName.isNullOrBlank() || bytes == null) {
            result.error("INVALID_ARGS", "File name and bytes are required.", null)
            return
        }

        try {
            val dir = publicStalaDirectory(relativeDir)
            val file = File(dir, fileName)
            file.writeBytes(bytes)

            result.success(writeResult(Uri.fromFile(file), relativeDir, fileName))
        } catch (e: Exception) {
            result.error("WRITE_FAILED", e.message ?: "Unable to write public STALA file.", null)
        }
    }

    private fun handleReadPublicTextFile(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")

        if (path.isNullOrBlank()) {
            result.error("INVALID_ARGS", "Path is required.", null)
            return
        }

        try {
            result.success(File(path).readText(Charsets.UTF_8))
        } catch (e: Exception) {
            result.error("READ_FAILED", e.message ?: "Unable to read public STALA file.", null)
        }
    }

    private fun handleDeletePublicFile(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")

        if (path.isNullOrBlank()) {
            result.error("INVALID_ARGS", "Path is required.", null)
            return
        }

        try {
            result.success(File(path).delete())
        } catch (e: Exception) {
            result.error("DELETE_FAILED", e.message ?: "Unable to delete public STALA file.", null)
        }
    }

    private fun handleWriteTextFile(call: MethodCall, result: MethodChannel.Result) {
        val relativeDir = call.argument<String>("relativeDir") ?: ""
        val fileName = call.argument<String>("fileName")
        val mimeType = call.argument<String>("mimeType") ?: "text/plain"
        val content = call.argument<String>("content")

        if (fileName.isNullOrBlank() || content == null) {
            result.error("INVALID_ARGS", "File name and content are required.", null)
            return
        }

        try {
            val fileUri = createDocumentInSelectedFolder(relativeDir, fileName, mimeType)
            contentResolver.openOutputStream(fileUri, "w")?.use { output ->
                output.write(content.toByteArray(Charsets.UTF_8))
            } ?: throw FileNotFoundException("Unable to open output stream.")

            result.success(writeResult(fileUri, relativeDir, fileName))
        } catch (e: Exception) {
            result.error("WRITE_FAILED", e.message ?: "Unable to write text file.", null)
        }
    }

    private fun handleWriteBinaryFile(call: MethodCall, result: MethodChannel.Result) {
        val relativeDir = call.argument<String>("relativeDir") ?: ""
        val fileName = call.argument<String>("fileName")
        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
        val bytes = call.argument<ByteArray>("bytes")

        if (fileName.isNullOrBlank() || bytes == null) {
            result.error("INVALID_ARGS", "File name and bytes are required.", null)
            return
        }

        try {
            val fileUri = createDocumentInSelectedFolder(relativeDir, fileName, mimeType)
            contentResolver.openOutputStream(fileUri, "w")?.use { output ->
                output.write(bytes)
            } ?: throw FileNotFoundException("Unable to open output stream.")

            result.success(writeResult(fileUri, relativeDir, fileName))
        } catch (e: Exception) {
            result.error("WRITE_FAILED", e.message ?: "Unable to write binary file.", null)
        }
    }

    private fun handleListFiles(call: MethodCall, result: MethodChannel.Result) {
        val relativeDir = call.argument<String>("relativeDir") ?: ""
        val extension = call.argument<String>("extension")?.lowercase()

        try {
            val treeUri = selectedStorageTreeUri()
                ?: throw IllegalStateException("No STALA storage folder is selected.")
            val directoryUri = findDirectoryInSelectedFolder(treeUri, relativeDir)

            if (directoryUri == null) {
                result.success(emptyList<Map<String, Any?>>())
                return
            }

            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
                treeUri,
                DocumentsContract.getDocumentId(directoryUri)
            )
            val files = mutableListOf<Map<String, Any?>>()

            contentResolver.query(
                childrenUri,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                    DocumentsContract.Document.COLUMN_LAST_MODIFIED,
                    DocumentsContract.Document.COLUMN_SIZE
                ),
                null,
                null,
                null
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    val documentId = cursor.getString(0)
                    val name = cursor.getString(1) ?: continue
                    val mimeType = cursor.getString(2)
                    val lastModified = cursor.getLong(3)
                    val size = cursor.getLong(4)

                    if (mimeType == DocumentsContract.Document.MIME_TYPE_DIR) continue
                    if (extension != null && !name.lowercase().endsWith(extension)) continue

                    val documentUri = DocumentsContract.buildDocumentUriUsingTree(
                        treeUri,
                        documentId
                    )

                    files.add(
                        mapOf(
                            "uri" to documentUri.toString(),
                            "fileName" to name,
                            "mimeType" to mimeType,
                            "lastModified" to lastModified,
                            "size" to size
                        )
                    )
                }
            }

            result.success(files)
        } catch (e: Exception) {
            result.error("LIST_FAILED", e.message ?: "Unable to list files.", null)
        }
    }

    private fun handleReadTextFile(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")

        if (uriString.isNullOrBlank()) {
            result.error("INVALID_ARGS", "Document URI is required.", null)
            return
        }

        try {
            val uri = Uri.parse(uriString)
            val text = contentResolver.openInputStream(uri)?.bufferedReader(Charsets.UTF_8).use {
                it?.readText()
            } ?: throw FileNotFoundException("Unable to open input stream.")

            result.success(text)
        } catch (e: Exception) {
            result.error("READ_FAILED", e.message ?: "Unable to read text file.", null)
        }
    }

    private fun handleWriteTextToUri(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        val content = call.argument<String>("content")

        if (uriString.isNullOrBlank() || content == null) {
            result.error("INVALID_ARGS", "Document URI and content are required.", null)
            return
        }

        try {
            val uri = Uri.parse(uriString)
            contentResolver.openOutputStream(uri, "w")?.use { output ->
                output.write(content.toByteArray(Charsets.UTF_8))
            } ?: throw FileNotFoundException("Unable to open output stream.")

            result.success(true)
        } catch (e: Exception) {
            result.error("WRITE_FAILED", e.message ?: "Unable to update text file.", null)
        }
    }

    private fun handleDeleteDocument(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")

        if (uriString.isNullOrBlank()) {
            result.error("INVALID_ARGS", "Document URI is required.", null)
            return
        }

        try {
            result.success(DocumentsContract.deleteDocument(contentResolver, Uri.parse(uriString)))
        } catch (e: Exception) {
            result.error("DELETE_FAILED", e.message ?: "Unable to delete document.", null)
        }
    }

    private fun handleRenameDocument(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        val newName = call.argument<String>("newName")

        if (uriString.isNullOrBlank() || newName.isNullOrBlank()) {
            result.error("INVALID_ARGS", "Document URI and new name are required.", null)
            return
        }

        try {
            val renamedUri = DocumentsContract.renameDocument(
                contentResolver,
                Uri.parse(uriString),
                newName
            )

            result.success(renamedUri?.toString())
        } catch (e: Exception) {
            result.error("RENAME_FAILED", e.message ?: "Unable to rename document.", null)
        }
    }

    private fun createDocumentInSelectedFolder(
        relativeDir: String,
        fileName: String,
        mimeType: String
    ): Uri {
        val treeUri = selectedStorageTreeUri()
            ?: throw IllegalStateException("No STALA storage folder is selected.")

        val treeDocumentId = DocumentsContract.getTreeDocumentId(treeUri)
        var parentDocumentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, treeDocumentId)

        relativeDir
            .split("/")
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .forEach { segment ->
                parentDocumentUri = findOrCreateDirectory(treeUri, parentDocumentUri, segment)
            }

        findChildDocument(treeUri, parentDocumentUri, fileName)?.let { existing ->
            DocumentsContract.deleteDocument(contentResolver, existing)
        }

        return DocumentsContract.createDocument(
            contentResolver,
            parentDocumentUri,
            mimeType,
            fileName
        ) ?: throw FileNotFoundException("Unable to create $fileName.")
    }

    private fun findDirectoryInSelectedFolder(treeUri: Uri, relativeDir: String): Uri? {
        val treeDocumentId = DocumentsContract.getTreeDocumentId(treeUri)
        var parentDocumentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, treeDocumentId)

        relativeDir
            .split("/")
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .forEach { segment ->
                parentDocumentUri = findChildDocument(treeUri, parentDocumentUri, segment)
                    ?: return null
            }

        return parentDocumentUri
    }

    private fun findOrCreateDirectory(treeUri: Uri, parentDocumentUri: Uri, name: String): Uri {
        findChildDocument(treeUri, parentDocumentUri, name)?.let { return it }

        return DocumentsContract.createDocument(
            contentResolver,
            parentDocumentUri,
            DocumentsContract.Document.MIME_TYPE_DIR,
            name
        ) ?: throw FileNotFoundException("Unable to create directory $name.")
    }

    private fun findChildDocument(treeUri: Uri, parentDocumentUri: Uri, displayName: String): Uri? {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri,
            DocumentsContract.getDocumentId(parentDocumentUri)
        )

        contentResolver.query(
            childrenUri,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME
            ),
            null,
            null,
            null
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val documentId = cursor.getString(0)
                val name = cursor.getString(1)

                if (name == displayName) {
                    return DocumentsContract.buildDocumentUriUsingTree(
                        treeUri,
                        documentId
                    )
                }
            }
        }

        return null
    }

    private fun currentStorageFolderInfo(): Map<String, Any?> {
        val uri = selectedStorageTreeUri()

        return mapOf(
            "granted" to (uri != null),
            "uri" to uri?.toString(),
            "displayName" to uri?.let { displayNameForTreeUri(it) }
        )
    }

    private fun selectedStorageTreeUri(): Uri? {
        val uriString = getSharedPreferences(storagePrefsName, MODE_PRIVATE)
            .getString(storageFolderUriKey, null)
            ?: return null

        return Uri.parse(uriString)
    }

    private fun clearStorageFolder() {
        val uri = selectedStorageTreeUri()
        if (uri != null) {
            try {
                contentResolver.releasePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                )
            } catch (_: Exception) {
                // Some providers do not expose a releasable persisted grant.
            }
        }

        getSharedPreferences(storagePrefsName, MODE_PRIVATE)
            .edit()
            .remove(storageFolderUriKey)
            .apply()
    }

    private fun displayNameForTreeUri(uri: Uri): String {
        return DocumentsContract.getTreeDocumentId(uri)
            ?.substringAfterLast(":")
            ?.ifBlank { "Selected folder" }
            ?: "Selected folder"
    }

    private fun displayNameForDocumentUri(uri: Uri): String {
        contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val name = cursor.getString(0)
                if (!name.isNullOrBlank()) return name
            }
        }

        return uri.lastPathSegment?.substringAfterLast("/") ?: "import.stala"
    }

    private fun publicStalaDirectory(relativeDir: String): File {
        val root = File(Environment.getExternalStorageDirectory(), "STALA")
        val target = relativeDir
            .split("/")
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .fold(root) { parent, segment -> File(parent, segment) }

        if (!target.exists() && !target.mkdirs()) {
            throw FileNotFoundException("Unable to create ${target.absolutePath}.")
        }

        return target
    }

    private fun writeResult(fileUri: Uri, relativeDir: String, fileName: String): Map<String, Any?> {
        return mapOf(
            "uri" to fileUri.toString(),
            "relativeDir" to relativeDir,
            "fileName" to fileName
        )
    }

    private fun handleSegmentStaffLines(call: MethodCall, result: MethodChannel.Result) {
        val imagePath = call.argument<String>("imagePath")

        if (imagePath.isNullOrBlank()) {
            result.success(
                mapOf(
                    "status" to "error",
                    "message" to "Image path is missing.",
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
            )
            return
        }

        Thread {
            try {
                val response = StaffSegmentationProcessor.segmentStaffLines(
                    context = this,
                    imagePath = imagePath
                )

                runOnUiThread {
                    result.success(response)
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.success(
                        mapOf(
                            "status" to "error",
                            "message" to "Native segmentation failed: ${e.message ?: "Unknown error"}",
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
                    )
                }
            }
        }.start()
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
                detector.loadModel("models/stala_multiclass_detector.onnx")

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
