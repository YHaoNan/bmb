package com.bmb.app.bmb_app

import android.content.ContentValues
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import android.util.Log
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.bmb.app/backup"
    private val TAG = "BMB_Backup"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            Log.d(TAG, "method=${call.method} args=${call.arguments}")
            when (call.method) {
                "saveToDownloads" -> handleSaveToDownloads(call, result)
                "listDownloads" -> handleListDownloads(call, result)
                "readFile" -> handleReadFile(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun handleSaveToDownloads(call: MethodCall, result: MethodChannel.Result) {
        val sourcePath = call.argument<String>("sourcePath")!!
        val fileName = call.argument<String>("fileName")!!
        val subDir = call.argument<String>("subDir") ?: ""

        Log.d(TAG, "saveToDownloads sourcePath=$sourcePath fileName=$fileName subDir=$subDir")
        Log.d(TAG, "saveToDownloads SDK_INT=${Build.VERSION.SDK_INT}")

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val resolver = contentResolver
                val contentValues = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                    put(MediaStore.Downloads.MIME_TYPE, "application/json")
                    put(MediaStore.Downloads.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/$subDir")
                }
                Log.d(TAG, "saveToDownloads inserting RELATIVE_PATH=${Environment.DIRECTORY_DOWNLOADS}/$subDir")
                val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)
                Log.d(TAG, "saveToDownloads insert result uri=$uri")
                if (uri != null) {
                    resolver.openOutputStream(uri)?.use { output ->
                        output.write(File(sourcePath).readBytes())
                        Log.d(TAG, "saveToDownloads wrote ${File(sourcePath).length()} bytes")
                    }
                    result.success(uri.toString())
                } else {
                    Log.e(TAG, "saveToDownloads MediaStore insert returned null")
                    result.error("INSERT_FAILED", "MediaStore 插入失败", null)
                }
            } else {
                val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                val targetDir = File(downloadsDir, subDir)
                targetDir.mkdirs()
                File(sourcePath).copyTo(File(targetDir, fileName), overwrite = true)
                Log.d(TAG, "saveToDownloads copied to ${targetDir.absolutePath}")
                result.success(targetDir.absolutePath)
            }
        } catch (e: Exception) {
            Log.e(TAG, "saveToDownloads error: ${e.message}", e)
            result.error("SAVE_FAILED", e.message, null)
        }
    }

    private fun handleListDownloads(call: MethodCall, result: MethodChannel.Result) {
        val prefix = call.argument<String>("prefix") ?: ""
        val files = mutableListOf<Map<String, Any>>()

        Log.d(TAG, "listDownloads prefix=$prefix SDK_INT=${Build.VERSION.SDK_INT}")

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val resolver = contentResolver
                val collectionUri = MediaStore.Downloads.EXTERNAL_CONTENT_URI
                val projection = arrayOf(
                    MediaStore.Downloads._ID,
                    MediaStore.Downloads.DISPLAY_NAME,
                    MediaStore.Downloads.DATE_MODIFIED,
                    MediaStore.Downloads.SIZE,
                )
                var totalRows = 0
                resolver.query(collectionUri, projection, null, null, "${MediaStore.Downloads.DATE_MODIFIED} DESC")?.use { cursor ->
                    totalRows = cursor.count
                    Log.d(TAG, "listDownloads query returned $totalRows rows")
                    while (cursor.moveToNext()) {
                        val name = cursor.getString(cursor.getColumnIndexOrThrow(MediaStore.Downloads.DISPLAY_NAME))
                        if (!name.startsWith(prefix)) continue
                        val id = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Downloads._ID))
                        val modified = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Downloads.DATE_MODIFIED))
                        val size = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Downloads.SIZE))
                        val uri = Uri.withAppendedPath(collectionUri, id.toString()).toString()
                        Log.d(TAG, "listDownloads match name=$name uri=$uri size=$size")
                        files.add(mapOf("name" to name, "uri" to uri, "modified" to modified, "size" to size))
                    }
                } ?: Log.e(TAG, "listDownloads query returned null cursor")
                Log.d(TAG, "listDownloads totalRows=$totalRows matched=${files.size}")
            } else {
                Log.d(TAG, "listDownloads SDK < 29, branching to file path")
                val dir = File("/storage/emulated/0/Download/BMB_Backups")
                if (dir.exists()) {
                    dir.listFiles()?.forEach { f ->
                        if (f.name.startsWith(prefix)) {
                            files.add(mapOf("name" to f.name, "uri" to f.absolutePath, "modified" to 0L, "size" to f.length()))
                        }
                    }
                }
            }
            result.success(files)
        } catch (e: Exception) {
            Log.e(TAG, "listDownloads error: ${e.message}", e)
            result.error("LIST_FAILED", e.message, null)
        }
    }

    private fun handleReadFile(call: MethodCall, result: MethodChannel.Result) {
        val uriStr = call.argument<String>("uri")!!
        Log.d(TAG, "readFile uri=$uriStr")
        try {
            val inputStream = contentResolver.openInputStream(Uri.parse(uriStr))
            val content = inputStream?.bufferedReader()?.readText() ?: ""
            Log.d(TAG, "readFile length=${content.length}")
            result.success(content)
        } catch (e: Exception) {
            Log.e(TAG, "readFile error: ${e.message}", e)
            result.error("READ_FAILED", e.message, null)
        }
    }
}
