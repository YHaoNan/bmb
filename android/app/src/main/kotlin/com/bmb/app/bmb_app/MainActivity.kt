package com.bmb.app.bmb_app

import android.app.Activity
import android.content.ContentValues
import android.content.Context
import android.content.SharedPreferences
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.MediaStore
import android.provider.Settings
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.TextView
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import android.util.Log
import java.io.File
import kotlin.math.abs

class MainActivity : FlutterActivity() {
    private val BACKUP_CHANNEL = "com.bmb.app/backup"
    private val WORKOUT_CHANNEL = "com.bmb.app/workout"
    private val TAG = "BMB_Main"
    private val PREFS_NAME = "bmb_floating_window"
    private val PREF_FLOATING_X = "floating_x"
    private val PREF_FLOATING_Y = "floating_y"

    // backup
    private var pendingResult: MethodChannel.Result? = null
    private val REQUEST_PICK_FILE = 9001

    // notification permission
    private var pendingWorkoutResult: MethodChannel.Result? = null
    private val REQUEST_NOTIFICATION_PERMISSION = 9003

    // floating window
    private var floatingView: View? = null
    private var floatingHandler: Handler? = null
    private var floatingRunnable: Runnable? = null
    private var floatingRunning = false
    private val REQUEST_OVERLAY_PERMISSION = 9002

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Backup channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BACKUP_CHANNEL).setMethodCallHandler { call, result ->
            Log.d(TAG, "backup method=${call.method}")
            when (call.method) {
                "saveToDownloads" -> handleSaveToDownloads(call, result)
                "listDownloads" -> handleListDownloads(call, result)
                "readFile" -> handleReadFile(call, result)
                "pickBackupFile" -> handlePickBackupFile(result)
                "saveLlmLog" -> handleSaveLlmLog(call, result)
                else -> result.notImplemented()
            }
        }

        // Workout channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WORKOUT_CHANNEL).setMethodCallHandler { call, result ->
            Log.d(TAG, "workout method=${call.method}")
            when (call.method) {
                "startWorkoutService" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            pendingWorkoutResult = result
                            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATION_PERMISSION)
                            return@setMethodCallHandler
                        }
                    }
                    startService(Intent(this, WorkoutService::class.java))
                    result.success(true)
                }
                "updateNotification" -> {
                    val state = call.argument<String>("state") ?: ""
                    val title = call.argument<String>("title") ?: ""
                    val text = call.argument<String>("text") ?: ""
                    val remaining = call.argument<Int>("remainingSeconds") ?: 0
                    val total = call.argument<Int>("totalSeconds") ?: 0
                    WorkoutService.instance?.updateNotification(state, title, text, remaining, total)
                    result.success(true)
                }
                "stopWorkoutService" -> {
                    WorkoutService.instance?.stopWorkout()
                    result.success(true)
                }
                "showFloatingTimer" -> {
                    val remaining = call.argument<Int>("remainingSeconds") ?: 0
                    val total = call.argument<Int>("totalSeconds") ?: 0
                    showFloatingTimer(remaining, total)
                    result.success(true)
                }
                "hideFloatingTimer" -> {
                    hideFloatingTimer()
                    result.success(true)
                }
                "updateFloatingTimer" -> {
                    val remaining = call.argument<Int>("remainingSeconds") ?: 0
                    val total = call.argument<Int>("totalSeconds") ?: 0
                    updateFloatingView(remaining, total)
                    result.success(true)
                }
                "showFloatingRestDone" -> {
                    showFloatingRestDone()
                    result.success(true)
                }
                "triggerVibration" -> {
                    triggerVibration()
                    result.success(true)
                }
                "checkOverlayPermission" -> {
                    result.success(Settings.canDrawOverlays(this))
                }
                "requestOverlayPermission" -> {
                    val intent = Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:$packageName")
                    )
                    startActivityForResult(intent, REQUEST_OVERLAY_PERMISSION)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    // ─── Backup methods ───

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_NOTIFICATION_PERMISSION) {
            pendingWorkoutResult?.let { result ->
                if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                    startService(Intent(this, WorkoutService::class.java))
                    result.success(true)
                } else {
                    result.success(false)
                }
                pendingWorkoutResult = null
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_PICK_FILE && resultCode == Activity.RESULT_OK) {
            val uri = data?.data?.toString()
            Log.d(TAG, "pickBackupFile uri=$uri")
            pendingResult?.success(uri)
            pendingResult = null
        }
    }

    private fun handlePickBackupFile(result: MethodChannel.Result) {
        pendingResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/json"
        }
        startActivityForResult(intent, REQUEST_PICK_FILE)
    }

    private fun handleSaveToDownloads(call: MethodCall, result: MethodChannel.Result) {
        val sourcePath = call.argument<String>("sourcePath")!!
        val fileName = call.argument<String>("fileName")!!
        val subDir = call.argument<String>("subDir") ?: ""
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val resolver = contentResolver
                val contentValues = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                    put(MediaStore.Downloads.MIME_TYPE, "application/json")
                    put(MediaStore.Downloads.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/$subDir")
                }
                val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)
                if (uri != null) {
                    resolver.openOutputStream(uri)?.use { output ->
                        output.write(File(sourcePath).readBytes())
                    }
                    result.success(uri.toString())
                } else {
                    result.error("INSERT_FAILED", "MediaStore 插入失败", null)
                }
            } else {
                val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                val targetDir = File(downloadsDir, subDir)
                targetDir.mkdirs()
                File(sourcePath).copyTo(File(targetDir, fileName), overwrite = true)
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
                resolver.query(collectionUri, projection, null, null, "${MediaStore.Downloads.DATE_MODIFIED} DESC")?.use { cursor ->
                    while (cursor.moveToNext()) {
                        val name = cursor.getString(cursor.getColumnIndexOrThrow(MediaStore.Downloads.DISPLAY_NAME))
                        if (!name.startsWith(prefix)) continue
                        val id = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Downloads._ID))
                        val modified = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Downloads.DATE_MODIFIED))
                        val size = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Downloads.SIZE))
                        val uri = Uri.withAppendedPath(collectionUri, id.toString()).toString()
                        files.add(mapOf("name" to name, "uri" to uri, "modified" to modified, "size" to size))
                    }
                }
            } else {
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
        try {
            val inputStream = contentResolver.openInputStream(Uri.parse(uriStr))
            val content = inputStream?.bufferedReader()?.readText() ?: ""
            result.success(content)
        } catch (e: Exception) {
            Log.e(TAG, "readFile error: ${e.message}", e)
            result.error("READ_FAILED", e.message, null)
        }
    }

    private fun handleSaveLlmLog(call: MethodCall, result: MethodChannel.Result) {
        val content = call.argument<String>("content") ?: ""
        val fileName = call.argument<String>("fileName") ?: "llm_log.json"
        val subDir = "BMB_Backup/llm_logs"
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val resolver = contentResolver
                val contentValues = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                    put(MediaStore.Downloads.MIME_TYPE, "application/json")
                    put(MediaStore.Downloads.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/$subDir")
                }
                val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)
                if (uri != null) {
                    resolver.openOutputStream(uri)?.use { output ->
                        output.write(content.toByteArray(Charsets.UTF_8))
                    }
                    result.success(uri.toString())
                } else {
                    result.error("INSERT_FAILED", "MediaStore 插入失败", null)
                }
            } else {
                val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                val targetDir = File(downloadsDir, subDir)
                targetDir.mkdirs()
                File(targetDir, fileName).writeText(content, Charsets.UTF_8)
                result.success(targetDir.absolutePath)
            }
        } catch (e: Exception) {
            Log.e(TAG, "saveLlmLog error: ${e.message}", e)
            result.error("SAVE_FAILED", e.message, null)
        }
    }

    // ─── Floating Window ───

    private fun getFloatingPrefs(): SharedPreferences =
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun saveFloatingPosition(x: Int, y: Int) {
        getFloatingPrefs().edit().putInt(PREF_FLOATING_X, x).putInt(PREF_FLOATING_Y, y).apply()
    }

    private fun loadFloatingPosition(): Pair<Int, Int> {
        val prefs = getFloatingPrefs()
        return Pair(prefs.getInt(PREF_FLOATING_X, 100), prefs.getInt(PREF_FLOATING_Y, 300))
    }

    private fun showFloatingTimer(remainingSeconds: Int, totalSeconds: Int) {
        if (!Settings.canDrawOverlays(this)) return
        hideFloatingTimer()

        val inflater = getSystemService(Context.LAYOUT_INFLATER_SERVICE) as LayoutInflater
        val view = inflater.inflate(R.layout.floating_timer_overlay, null)
        floatingView = view

        val progressBar = view.findViewById<android.widget.ProgressBar>(R.id.floating_progress)
        val textView = view.findViewById<TextView>(R.id.floating_timer_text)

        // Reset visibility for new timer
        progressBar.visibility = View.VISIBLE
        textView.visibility = View.VISIBLE
        textView.textSize = 18f
        textView.setTextColor(android.graphics.Color.parseColor("#B7FF00"))

        val initialProgress = if (totalSeconds > 0) (remainingSeconds * 100 / totalSeconds) else 0
        progressBar.progress = initialProgress
        textView.text = remainingSeconds.toString()

        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val params = WindowManager.LayoutParams(
            200, 200,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            android.graphics.PixelFormat.TRANSLUCENT
        ).apply {
            gravity = android.view.Gravity.TOP or android.view.Gravity.START
            val savedPos = loadFloatingPosition()
            x = savedPos.first
            y = savedPos.second
        }

        wm.addView(view, params)

        // Drag handling
        var initialX = 0f
        var initialY = 0f
        var initialTouchX = 0f
        var initialTouchY = 0f
        var isDragging = false
        view.setOnTouchListener { v, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x.toFloat()
                    initialY = params.y.toFloat()
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    isDragging = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - initialTouchX
                    val dy = event.rawY - initialTouchY
                    if (abs(dx) > 10 || abs(dy) > 10) {
                        isDragging = true
                    }
                    params.x = (initialX + dx).toInt()
                    params.y = (initialY + dy).toInt()
                    wm.updateViewLayout(v, params)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (isDragging) {
                        saveFloatingPosition(params.x, params.y)
                    } else {
                        val intent = Intent(this, MainActivity::class.java).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                        }
                        startActivity(intent)
                    }
                    true
                }
                else -> false
            }
        }

        // Native countdown timer — update once per second
        var remaining = remainingSeconds
        val total = totalSeconds
        floatingHandler = Handler(Looper.getMainLooper())
        floatingRunning = true
        floatingRunnable = object : Runnable {
            override fun run() {
                if (!floatingRunning) return
                val targetProgress = if (total > 0) (remaining * 100 / total) else 0
                progressBar.progress = targetProgress
                textView.text = remaining.toString()

                if (remaining > 0) {
                    remaining--
                    floatingHandler?.postDelayed(this, 1000)
                }
                // remaining == 0: stay at 0 until Dart signals showFloatingRestDone
            }
        }
        floatingHandler?.post(floatingRunnable!!)
    }

    private fun updateFloatingView(remainingSeconds: Int, totalSeconds: Int) {
        // Called from Dart — update text immediately, progress updates via native timer
        floatingView?.let { view ->
            val textView = view.findViewById<TextView>(R.id.floating_timer_text)
            textView.text = remainingSeconds.toString()
        }
    }

    private fun showFloatingRestDone() {
        floatingHandler?.removeCallbacksAndMessages(null)
        floatingRunning = false
        floatingView?.let { view ->
            val progressBar = view.findViewById<android.widget.ProgressBar>(R.id.floating_progress)
            val textView = view.findViewById<TextView>(R.id.floating_timer_text)
            progressBar.visibility = View.GONE
            textView.text = "返回"
            textView.setTextColor(android.graphics.Color.parseColor("#B7FF00"))
            textView.textSize = 14f
        }
    }

    private fun hideFloatingTimer() {
        floatingHandler?.removeCallbacksAndMessages(null)
        floatingHandler = null
        floatingRunnable = null
        floatingRunning = false
        floatingView?.let { view ->
            try {
                val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
                wm.removeView(view)
            } catch (_: Exception) {}
        }
        floatingView = null
    }

    // ─── Vibration ───

    private fun triggerVibration() {
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vm.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(
                    VibrationEffect.createOneShot(500, VibrationEffect.DEFAULT_AMPLITUDE)
                )
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(500)
            }
        } catch (e: Exception) {
            Log.e(TAG, "vibration error: ${e.message}", e)
        }
    }

    override fun onDestroy() {
        hideFloatingTimer()
        super.onDestroy()
    }
}
