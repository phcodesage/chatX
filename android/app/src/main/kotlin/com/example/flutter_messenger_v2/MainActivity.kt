package com.example.flutter_messenger_v2

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.ComponentName
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.Typeface
import android.graphics.drawable.Icon
import android.media.MediaRecorder
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.util.Log
import android.util.Rational
import android.webkit.MimeTypeMap
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person
import androidx.core.app.RemoteInput
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val TAG = "PiP"
    private val CHANNEL = "com.example.flutter_messenger_v2/pip"
    private val AUDIO_CHANNEL = "com.example.flutter_messenger_v2/audio_recorder"
    private val QUICK_REPLY_CHANNEL = "com.example.flutter_messenger_v2/quick_reply"
    private val SHARE_CHANNEL = "com.example.flutter_messenger_v2/share_target"
    private val SHORTCUT_CHANNEL = "com.example.flutter_messenger_v2/shortcuts"
    private val NOTIFICATION_PAYLOAD_CHANNEL = "com.example.flutter_messenger_v2/notification_payload"
    private val DIRECT_SHARE_CATEGORY = "com.example.flutter_messenger_v2.directshare"
    private var methodChannel: MethodChannel? = null
    private var shareMethodChannel: MethodChannel? = null
    private var shortcutMethodChannel: MethodChannel? = null
    private var notificationPayloadChannel: MethodChannel? = null
    private var pendingSharedItems: List<Map<String, String>> = emptyList()
    private var pendingSharedTargetUserId: String? = null
    private var pendingShortcutTargetUserId: String? = null
    private var pendingNotificationPayload: String? = null
    private var isInCall = false
    private var isMuted = false

    // Native audio recorder for accurate amplitude readings
    @Suppress("DEPRECATION")
    private var audioRecorder: MediaRecorder? = null
    private var currentRecordingPath: String? = null

    companion object {
        private const val ACTION_TOGGLE_MIC = "com.example.flutter_messenger_v2.PIP_TOGGLE_MIC"
        private const val ACTION_END_CALL = "com.example.flutter_messenger_v2.PIP_END_CALL"
        private const val REQUEST_TOGGLE_MIC = 1001
        private const val REQUEST_END_CALL = 1002
        private const val REQUEST_QUICK_REPLY = 2001
        private const val CHAT_NOTIFICATION_HISTORY_PREFS = "chat_notification_history"
        private const val CHAT_NOTIFICATION_HISTORY_LIMIT = 12
    }

    private val pipActionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                ACTION_TOGGLE_MIC -> {
                    Log.d(TAG, "PiP action: toggle mic (was muted=$isMuted)")
                    isMuted = !isMuted
                    methodChannel?.invokeMethod("onPipAction", "toggleMic")
                    // Update PiP actions to reflect new mute state
                    updatePipActions()
                }
                ACTION_END_CALL -> {
                    Log.d(TAG, "PiP action: end call")
                    isInCall = false
                    // Exit PiP by bringing activity back to full screen
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && isInPictureInPictureMode) {
                        moveTaskToBack(true)
                    }
                    methodChannel?.invokeMethod("onPipAction", "endCall")
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        logIntent(intent, "onCreate")
        pendingSharedItems = extractSharedItemsFromIntent(intent)
        pendingSharedTargetUserId = extractSharedTargetUserId(intent)
        pendingShortcutTargetUserId = extractShortcutTargetUserId(intent)
        pendingNotificationPayload = intent?.getStringExtra("notification_payload")
        Log.d("ShareDebug", "onCreate result: items=${pendingSharedItems.size}, sharedTarget=$pendingSharedTargetUserId, shortcutTarget=$pendingShortcutTargetUserId")

        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            Log.e(TAG, "Uncaught exception in thread ${thread.name}: ${throwable.message}", throwable)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        shareMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHARE_CHANNEL,
        )
        shareMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "consumeInitialSharedItems" -> {
                    val currentItems = pendingSharedItems
                    pendingSharedItems = emptyList()
                    result.success(currentItems)
                }
                "consumeInitialSharedTargetUserId" -> {
                    val currentTarget = pendingSharedTargetUserId
                    pendingSharedTargetUserId = null
                    result.success(currentTarget)
                }
                else -> result.notImplemented()
            }
        }

        // ── Direct Share shortcuts channel ─────────────────────────────────
        shortcutMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHORTCUT_CHANNEL,
        )
        shortcutMethodChannel?.setMethodCallHandler { call, result ->
                when (call.method) {
                    "pushShareTargets" -> {
                        try {
                            @Suppress("UNCHECKED_CAST")
                            val users = call.arguments as? List<Map<String, Any>> ?: emptyList()
                            pushShareShortcuts(users)
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "pushShareTargets error: ${e.message}", e)
                            result.error("SHORTCUT_ERROR", e.message, null)
                        }
                    }
                    "reportShareUsed" -> {
                        try {
                            val userId = call.argument<String>("userId")
                            if (userId.isNullOrBlank()) {
                                result.error("BAD_ARGS", "userId is required", null)
                            } else {
                                reportShareShortcutUsed(userId)
                                result.success(true)
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "reportShareUsed error: ${e.message}", e)
                            result.error("SHORTCUT_ERROR", e.message, null)
                        }
                    }
                    "consumeInitialShortcutTarget" -> {
                        val currentTarget = pendingShortcutTargetUserId
                        pendingShortcutTargetUserId = null
                        result.success(currentTarget)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Audio recorder channel ─────────────────────────────────────────
        // Uses MediaRecorder.getMaxAmplitude() for accurate real-time amplitude.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startRecording" -> {
                        try {
                            val path = call.argument<String>("path")
                                ?: return@setMethodCallHandler result.error(
                                    "NO_PATH", "Recording path is required", null
                                )
                            // Release any existing recorder
                            audioRecorder?.apply { try { stop() } catch (_: Exception) {}; release() }
                            @Suppress("DEPRECATION")
                            audioRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                MediaRecorder(this)
                            } else {
                                @Suppress("DEPRECATION")
                                MediaRecorder()
                            }
                            audioRecorder!!.apply {
                                setAudioSource(MediaRecorder.AudioSource.MIC)
                                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                                setAudioEncodingBitRate(128000)
                                setAudioSamplingRate(44100)
                                setOutputFile(path)
                                prepare()
                                start()
                            }
                            currentRecordingPath = path
                            Log.d(TAG, "Audio recording started: $path")
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "startRecording error: ${e.message}", e)
                            result.error("RECORD_ERROR", e.message, null)
                        }
                    }
                    "getAmplitude" -> {
                        // getMaxAmplitude() resets after each call — perfect for scrolling waveform
                        val amplitude = audioRecorder?.maxAmplitude ?: 0
                        result.success(amplitude)
                    }
                    "pauseRecording" -> {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                audioRecorder?.pause()
                                result.success(true)
                            } else {
                                result.error("API_LEVEL", "Pause requires API 24+", null)
                            }
                        } catch (e: Exception) {
                            result.error("PAUSE_ERROR", e.message, null)
                        }
                    }
                    "resumeRecording" -> {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                audioRecorder?.resume()
                                result.success(true)
                            } else {
                                result.error("API_LEVEL", "Resume requires API 24+", null)
                            }
                        } catch (e: Exception) {
                            result.error("RESUME_ERROR", e.message, null)
                        }
                    }
                    "stopRecording" -> {
                        try {
                            audioRecorder?.apply {
                                stop()
                                release()
                            }
                            audioRecorder = null
                            val path = currentRecordingPath
                            currentRecordingPath = null
                            Log.d(TAG, "Audio recording stopped: $path")
                            result.success(path)
                        } catch (e: Exception) {
                            audioRecorder = null
                            Log.e(TAG, "stopRecording error: ${e.message}", e)
                            result.error("STOP_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Screen share foreground service channel ────────────────────────
        val screenShareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.flutter_messenger_v2/screen_share")
        screenShareChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startForegroundService" -> {
                    try {
                        val title = call.argument<String>("notificationTitle") ?: "Screen Sharing"
                        val text = call.argument<String>("notificationText") ?: "You are sharing your screen"
                        val serviceIntent = Intent(this, com.cloudwebrtc.webrtc.FlutterWebRTCForegroundService::class.java).apply {
                            putExtra("notificationTitle", title)
                            putExtra("notificationText", text)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(serviceIntent)
                        } else {
                            startService(serviceIntent)
                        }
                        Log.d(TAG, "Screen share foreground service started")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error starting foreground service: ${e.message}", e)
                        result.error("FOREGROUND_SERVICE_ERROR", e.message, null)
                    }
                }
                "stopForegroundService" -> {
                    try {
                        val serviceIntent = Intent(this, com.cloudwebrtc.webrtc.FlutterWebRTCForegroundService::class.java)
                        stopService(serviceIntent)
                        Log.d(TAG, "Screen share foreground service stopped")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error stopping foreground service: ${e.message}", e)
                        result.error("FOREGROUND_SERVICE_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // ── Native quick-reply notification bridge ───────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, QUICK_REPLY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "showChatQuickReplyNotification" -> {
                        try {
                            val args = call.arguments as? Map<*, *>
                            if (args == null) {
                                result.error("BAD_ARGS", "Expected Map arguments", null)
                                return@setMethodCallHandler
                            }

                            showChatQuickReplyNotification(args)
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to show native quick-reply notification", e)
                            result.error("NATIVE_NOTIFICATION_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Native notification payload bridge ────────────────────────────
        notificationPayloadChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NOTIFICATION_PAYLOAD_CHANNEL,
        )
        notificationPayloadChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "consumeInitialNotificationPayload" -> {
                    val payload = pendingNotificationPayload
                    pendingNotificationPayload = null
                    result.success(payload)
                }
                else -> result.notImplemented()
            }
        }

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isPipAvailable" -> {
                    val available = isPipAvailable()
                    Log.d(TAG, "isPipAvailable: $available")
                    result.success(available)
                }
                "enterPipMode" -> {
                    Log.d(TAG, "enterPipMode called from Flutter")
                    result.success(enterPipMode())
                }
                "setInCall" -> {
                    isInCall = call.argument<Boolean>("inCall") ?: false
                    Log.d(TAG, "setInCall: $isInCall")
                    result.success(true)
                }
                "updateMuteState" -> {
                    isMuted = call.argument<Boolean>("isMuted") ?: false
                    Log.d(TAG, "updateMuteState: $isMuted")
                    updatePipActions()
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Register broadcast receiver for PiP actions
        val filter = IntentFilter().apply {
            addAction(ACTION_TOGGLE_MIC)
            addAction(ACTION_END_CALL)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(pipActionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(pipActionReceiver, filter)
        }
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(pipActionReceiver)
        } catch (e: Exception) {
            Log.w(TAG, "Receiver already unregistered")
        }
        shareMethodChannel = null
        shortcutMethodChannel = null
        notificationPayloadChannel = null
        super.onDestroy()
    }

    /**
     * Forward activity results to the FragmentManager so that
     * ScreenRequestPermissionsFragment (used by flutter_webrtc's getDisplayMedia)
     * receives the screen-capture permission result.
     *
     * FlutterActivity.onActivityResult() does NOT call super (Activity.onActivityResult),
     * so android.app.Fragments added via getFragmentManager() never receive their results.
     * We find the fragment by tag and dispatch directly.
     */
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        Log.d(TAG, "onActivityResult: requestCode=0x${requestCode.toString(16)} resultCode=$resultCode")
        // Screen capture permission result from ScreenRequestPermissionsFragment.
        // The fragment is added with tag = its fully-qualified class name.
        val screenFragTag =
            "com.cloudwebrtc.webrtc.GetUserMediaImpl\$ScreenRequestPermissionsFragment"
        val screenFrag = fragmentManager.findFragmentByTag(screenFragTag)
        if (screenFrag != null) {
            Log.d(TAG, "Dispatching activity result to ScreenRequestPermissionsFragment")
            // Strip the high-16-bit fragment-index encoding added by startActivityFromFragment()
            screenFrag.onActivityResult(requestCode and 0xffff, resultCode, data)
        }
        // Always let FlutterActivity / the engine handle it too.
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        logIntent(intent, "onNewIntent")

        val sharedItems = extractSharedItemsFromIntent(intent)
        pendingSharedTargetUserId = extractSharedTargetUserId(intent)
        Log.d("ShareDebug", "onNewIntent result: items=${sharedItems.size}, sharedTarget=$pendingSharedTargetUserId")
        if (sharedItems.isNotEmpty()) {
            pendingSharedItems = sharedItems
            Log.d("ShareDebug", "onNewIntent: invoking onSharedItems, first item directShareUserId=${sharedItems.firstOrNull()?.get("directShareUserId")}")
            shareMethodChannel?.invokeMethod("onSharedItems", sharedItems)
        }

        val shortcutTargetUserId = extractShortcutTargetUserId(intent)
        if (!shortcutTargetUserId.isNullOrBlank() && sharedItems.isEmpty()) {
            pendingShortcutTargetUserId = shortcutTargetUserId
            shortcutMethodChannel?.invokeMethod("onShortcutTarget", shortcutTargetUserId)
        }

        val notificationPayload = intent.getStringExtra("notification_payload")
        if (!notificationPayload.isNullOrBlank()) {
            pendingNotificationPayload = notificationPayload
            notificationPayloadChannel?.invokeMethod("onNotificationTap", notificationPayload)
        }
    }

    private fun extractShortcutTargetUserId(intent: Intent?): String? {
        if (intent == null) {
            return null
        }

        val shortcutUserId = intent.getStringExtra("direct_share_user_id")
        if (shortcutUserId.isNullOrBlank()) {
            return null
        }

        // Reuse the same shortcut for two cases:
        // 1) launcher recent-chat tap -> ACTION_SEND but with no shared payload -> open chat
        // 2) sharesheet direct-share tap -> ACTION_SEND with EXTRA_STREAM/clipData/text -> auto-send shared content
        if (intentHasSharedPayload(intent)) {
            return null
        }

        return shortcutUserId
    }

    private fun logIntent(intent: Intent?, source: String) {
        if (intent == null) {
            Log.d("ShareDebug", "[$source] intent is null")
            return
        }
        Log.d("ShareDebug", "[$source] action=${intent.action}, type=${intent.type}")
        Log.d("ShareDebug", "[$source] direct_share_user_id=${intent.getStringExtra("direct_share_user_id")}")
        val stream = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION") intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        }
        Log.d("ShareDebug", "[$source] EXTRA_STREAM=$stream")
        Log.d("ShareDebug", "[$source] clipData=${intent.clipData}, clipData.itemCount=${intent.clipData?.itemCount ?: 0}")
        Log.d("ShareDebug", "[$source] EXTRA_TEXT=${intent.getStringExtra(Intent.EXTRA_TEXT)?.take(80)}")
        val extras = intent.extras
        if (extras != null) {
            val keys = extras.keySet().joinToString(", ")
            Log.d("ShareDebug", "[$source] all extras keys: $keys")
        }
    }

    private fun intentHasSharedPayload(intent: Intent): Boolean {
        if (intent.clipData != null && intent.clipData!!.itemCount > 0) {
            return true
        }

        if (!intent.getStringExtra(Intent.EXTRA_TEXT).isNullOrBlank()) {
            return true
        }

        val action = intent.action ?: return false
        return when (action) {
            Intent.ACTION_SEND -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java) != null
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM) != null
                }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    val list = intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                    !list.isNullOrEmpty()
                } else {
                    @Suppress("DEPRECATION")
                    val list = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                    !list.isNullOrEmpty()
                }
            }
            else -> false
        }
    }

    private fun extractSharedTargetUserId(intent: Intent?): String? {
        if (intent == null) {
            return null
        }

        val action = intent.action ?: return null
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) {
            return null
        }

        val id = intent.getStringExtra("direct_share_user_id")
            ?: userIdFromShortcutIdExtra(intent)
        Log.d("ShareDebug", "extractSharedTargetUserId: action=$action, direct_share_user_id=${intent.getStringExtra("direct_share_user_id")}, shortcut_fallback=${userIdFromShortcutIdExtra(intent)}, resolved=$id")
        return id
    }

    private fun userIdFromShortcutIdExtra(intent: Intent): String? {
        val sid = intent.getStringExtra("shortcut_id")
            ?: intent.getStringExtra("android.intent.extra.shortcut.ID")
            ?: intent.extras?.getString("android.intent.extra.shortcut.ID")
            ?: intent.extras?.getString("android.intent.extra.shortcut_id")
            ?: return null
        val prefix = "share_target_user_"
        return if (sid.startsWith(prefix)) sid.removePrefix(prefix) else null
    }

    private fun extractSharedItemsFromIntent(intent: Intent?): List<Map<String, String>> {
        if (intent == null) {
            return emptyList()
        }

        val action = intent.action ?: return emptyList()
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) {
            return emptyList()
        }

        val uris = mutableListOf<Uri>()
        if (action == Intent.ACTION_SEND) {
            val singleUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            }
            if (singleUri != null) {
                uris.add(singleUri)
            }
        } else if (action == Intent.ACTION_SEND_MULTIPLE) {
            val multipleUris = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            }
            if (multipleUris != null) {
                uris.addAll(multipleUris)
            }
        }

        if (uris.isEmpty() && intent.clipData != null) {
            val clipData = intent.clipData ?: return emptyList()
            for (index in 0 until clipData.itemCount) {
                val uri = clipData.getItemAt(index).uri
                if (uri != null) {
                    uris.add(uri)
                }
            }
        }

        if (uris.isEmpty()) {
            // Some apps share vCards using EXTRA_TEXT instead of EXTRA_STREAM.
            val textPayload = intent.getStringExtra(Intent.EXTRA_TEXT)
            val mimeType = intent.type?.lowercase() ?: ""
            if (!textPayload.isNullOrBlank() && mimeType.contains("vcard")) {
                val textItem = copySharedTextToCache(
                    text = textPayload,
                    mimeType = if (mimeType.isBlank()) "text/x-vcard" else mimeType,
                    extension = "vcf",
                    index = 0,
                )
                return if (textItem != null) listOf(textItem) else emptyList()
            }
            return emptyList()
        }

        val extractedItems = mutableListOf<Map<String, String>>()
        uris.forEachIndexed { index, uri ->
            try {
                val sharedItem = copySharedUriToCache(uri, index)
                if (sharedItem != null) {
                    extractedItems.add(sharedItem)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to parse shared URI: $uri", e)
            }
        }

        // If arrived via a Direct Share shortcut the shortcut intent merges its extras
        // into the ACTION_SEND intent — pick up the user id and annotate each item.
        val directShareUserId = intent.getStringExtra("direct_share_user_id")
            ?: userIdFromShortcutIdExtra(intent)
        Log.d("ShareDebug", "extractSharedItemsFromIntent: directShareUserId=$directShareUserId (raw=${intent.getStringExtra("direct_share_user_id")}, shortcutFallback=${userIdFromShortcutIdExtra(intent)})")
        if (!directShareUserId.isNullOrBlank() && extractedItems.isNotEmpty()) {
            return extractedItems.map { it + ("directShareUserId" to directShareUserId) }
        }

        return extractedItems
    }

    // ── Sharing Shortcuts (Direct Share row) ───────────────────────────────

    private fun pushShareShortcuts(users: List<Map<String, Any>>) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N_MR1) return // shortcuts require API 25+

        val shortcuts = users.take(6).mapIndexedNotNull { rank, user ->
            val userId = user["id"]?.toString() ?: return@mapIndexedNotNull null
            val name = (user["name"] as? String)?.ifBlank { "User $userId" } ?: "User $userId"
            val colorIndex = (user["avatarColorIndex"] as? Int) ?: 0
            val shortcutId = "share_target_user_$userId"
            val person = Person.Builder().setName(name).build()

            // The shortcut's own intent — Android will merge its extras with the
            // incoming ACTION_SEND intent when the user picks this shortcut.
            val directShareIntent = Intent(this, MainActivity::class.java).apply {
                action = Intent.ACTION_SEND
                putExtra("direct_share_user_id", userId)
                // Secondary identifier: allows us to recover userId from shortcut ID
                // even if the primary extra is dropped during intent merging.
                putExtra("shortcut_id", shortcutId)
            }

            ShortcutInfoCompat.Builder(this, shortcutId)
                .setShortLabel(name)
                .setLongLabel(name)
                .setIcon(IconCompat.createWithBitmap(makeInitialsIcon(name, colorIndex)))
                .setActivity(ComponentName(this, MainActivity::class.java))
                .setIntent(directShareIntent)
                .setPersons(arrayOf(person))
                .setLongLived(true)
                .setCategories(setOf(DIRECT_SHARE_CATEGORY))
                .setRank(rank)
                .build()
        }

        if (shortcuts.isNotEmpty()) {
            ShortcutManagerCompat.removeAllDynamicShortcuts(this)
            ShortcutManagerCompat.addDynamicShortcuts(this, shortcuts)
        }
    }

    private fun reportShareShortcutUsed(userId: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N_MR1) return
        ShortcutManagerCompat.reportShortcutUsed(this, "share_target_user_$userId")
    }

    /** Render a coloured circle with up to two initials — used as shortcut icon. */
    private fun makeInitialsIcon(name: String, colorIndex: Int): Bitmap {
        val avatarColors = intArrayOf(
            0xFFE91E63.toInt(), 0xFF9C27B0.toInt(), 0xFF673AB7.toInt(),
            0xFF3F51B5.toInt(), 0xFF2196F3.toInt(), 0xFF00BCD4.toInt(),
            0xFF009688.toInt(), 0xFF4CAF50.toInt(), 0xFFFF9800.toInt(), 0xFFFF5722.toInt(),
        )
        val bg = avatarColors[colorIndex % avatarColors.size]
        val size = 192
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = bg }
        canvas.drawCircle(size / 2f, size / 2f, size / 2f, paint)

        val initials = name.trim().split(' ')
            .filter { it.isNotEmpty() }
            .take(2)
            .map { it.first().uppercaseChar() }
            .joinToString("")
            .ifEmpty { "?" }

        paint.apply {
            color = android.graphics.Color.WHITE
            textSize = size * 0.38f
            typeface = Typeface.DEFAULT_BOLD
            textAlign = Paint.Align.CENTER
        }
        val textBounds = Rect()
        paint.getTextBounds(initials, 0, initials.length, textBounds)
        canvas.drawText(initials, size / 2f, size / 2f + textBounds.height() / 2f, paint)
        return bmp
    }

    private fun copySharedTextToCache(
        text: String,
        mimeType: String,
        extension: String,
        index: Int,
    ): Map<String, String>? {
        val sharedDir = File(cacheDir, "shared_imports")
        if (!sharedDir.exists()) {
            sharedDir.mkdirs()
        }

        val targetFile = File(
            sharedDir,
            "${System.currentTimeMillis()}_$index-shared_contact.$extension",
        )

        return try {
            targetFile.writeText(text)
            mapOf(
                "path" to targetFile.absolutePath,
                "fileName" to targetFile.name,
                "mimeType" to mimeType,
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to persist shared text payload", e)
            null
        }
    }

    private fun copySharedUriToCache(uri: Uri, index: Int): Map<String, String>? {
        val mimeType = contentResolver.getType(uri) ?: "application/octet-stream"
        val defaultExtension = extensionFromMimeType(mimeType)
        val displayName = resolveDisplayName(uri)
            ?: "shared_${System.currentTimeMillis()}_$index.$defaultExtension"
        val safeName = sanitizeFileName(displayName)

        val sharedDir = File(cacheDir, "shared_imports")
        if (!sharedDir.exists()) {
            sharedDir.mkdirs()
        }

        val targetFile = File(
            sharedDir,
            "${System.currentTimeMillis()}_$index-$safeName",
        )

        contentResolver.openInputStream(uri)?.use { input ->
            FileOutputStream(targetFile).use { output ->
                input.copyTo(output)
            }
        } ?: return null

        return mapOf(
            "path" to targetFile.absolutePath,
            "fileName" to safeName,
            "mimeType" to mimeType,
        )
    }

    private fun resolveDisplayName(uri: Uri): String? {
        if (uri.scheme == "file") {
            return File(uri.path ?: return null).name
        }

        contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val columnIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (columnIndex != -1) {
                    return cursor.getString(columnIndex)
                }
            }
        }

        return null
    }

    private fun sanitizeFileName(fileName: String): String {
        return fileName.replace(Regex("[^A-Za-z0-9._-]"), "_")
    }

    private fun extensionFromMimeType(mimeType: String): String {
        val ext = MimeTypeMap.getSingleton().getExtensionFromMimeType(mimeType)
        return if (ext.isNullOrBlank()) "bin" else ext
    }

    private fun isPipAvailable(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
    }

    private fun buildPipActions(): List<RemoteAction> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return emptyList()

        val actions = mutableListOf<RemoteAction>()

        // Mute/Unmute action
        val micIcon = if (isMuted) {
            Icon.createWithResource(this, android.R.drawable.stat_notify_call_mute)
        } else {
            Icon.createWithResource(this, android.R.drawable.ic_btn_speak_now)
        }
        val micTitle = if (isMuted) "Unmute" else "Mute"
        val micIntent = PendingIntent.getBroadcast(
            this,
            REQUEST_TOGGLE_MIC,
            Intent(ACTION_TOGGLE_MIC),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        actions.add(RemoteAction(micIcon, micTitle, micTitle, micIntent))

        // End Call action
        val endCallIcon = Icon.createWithResource(this, android.R.drawable.ic_menu_close_clear_cancel)
        val endCallIntent = PendingIntent.getBroadcast(
            this,
            REQUEST_END_CALL,
            Intent(ACTION_END_CALL),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        actions.add(RemoteAction(endCallIcon, "End Call", "End Call", endCallIntent))

        return actions
    }

    private fun updatePipActions() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && isInPictureInPictureMode) {
            try {
                val params = PictureInPictureParams.Builder()
                    .setAspectRatio(Rational(9, 16))
                    .setActions(buildPipActions())
                    .build()
                setPictureInPictureParams(params)
                Log.d(TAG, "PiP actions updated (muted=$isMuted)")
            } catch (e: Exception) {
                Log.e(TAG, "Error updating PiP actions: ${e.message}", e)
            }
        }
    }

    private fun showChatQuickReplyNotification(args: Map<*, *>) {
        val notificationId = (args["notificationId"] as? Number)?.toInt() ?: return
        val channelId = (args["channelId"] as? String)?.ifBlank { "chat_messages" } ?: "chat_messages"
        val channelName = (args["channelName"] as? String)?.ifBlank { "Chat Messages" } ?: "Chat Messages"
        val title = (args["title"] as? String)?.ifBlank { "New message" } ?: "New message"
        val body = (args["body"] as? String)?.ifBlank { "" } ?: ""
        val senderName = (args["senderName"] as? String)?.ifBlank { "Someone" } ?: "Someone"
        val groupName = (args["groupName"] as? String).orEmpty()
        val isGroup = args["isGroup"] as? Boolean ?: false
        val replyEndpoint = (args["replyEndpoint"] as? String).orEmpty()
        val replyRecipientId = (args["replyRecipientId"] as? String).orEmpty()
        val conversationType = (args["conversationType"] as? String)?.ifBlank { "direct" } ?: "direct"
        val enableQuickReply = args["enableQuickReply"] as? Boolean ?: true
        val groupId = (args["groupId"] as? String).orEmpty()
        val baseUrl = (args["baseUrl"] as? String).orEmpty()
        val payloadJson = (args["payloadJson"] as? String).orEmpty()
        val conversationKey = (args["conversationKey"] as? String)?.ifBlank { null }
            ?: buildConversationKey(conversationType, groupId, replyRecipientId, notificationId)
        val history = appendChatHistory(conversationKey, senderName, body)

        ensureNotificationChannel(channelId, channelName)

        val replyIntent = Intent(this, ReplyReceiver::class.java).apply {
            putExtra("notification_id", notificationId)
            putExtra("reply_endpoint", replyEndpoint)
            putExtra("reply_recipient_id", replyRecipientId)
            putExtra("conversation_type", conversationType)
            putExtra("group_id", groupId)
            putExtra("base_url", baseUrl)
            putExtra("channel_id", channelId)
            putExtra("payload_json", payloadJson)
        }

        val replyPendingIntentFlags =
            PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    PendingIntent.FLAG_MUTABLE
                } else {
                    0
                }

        val replyPendingIntent = PendingIntent.getBroadcast(
            this,
            notificationId + REQUEST_QUICK_REPLY,
            replyIntent,
            replyPendingIntentFlags,
        )

        val remoteInput = RemoteInput.Builder(ReplyReceiver.KEY_TEXT_REPLY)
            .setLabel("Write a reply...")
            .build()

        val replyAction = NotificationCompat.Action.Builder(
            android.R.drawable.ic_menu_send,
            "Reply",
            replyPendingIntent,
        )
            .addRemoteInput(remoteInput)
            .setAllowGeneratedReplies(true)
            .build()

        val mePerson = Person.Builder().setName("You").build()

        val style = NotificationCompat.MessagingStyle(mePerson)

        for (i in 0 until history.length()) {
            val entry = history.optJSONObject(i) ?: continue
            val lineSender = entry.optString("sender").ifBlank { senderName }
            val lineText = entry.optString("text").ifBlank { body }
            val lineTimestamp = entry.optLong("ts", System.currentTimeMillis())
            val senderPerson = Person.Builder().setName(lineSender).build()
            style.addMessage(lineText, lineTimestamp, senderPerson)
        }

        if (isGroup && groupName.isNotBlank()) {
            style.setConversationTitle(groupName)
            style.setGroupConversation(true)
        }

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            if (payloadJson.isNotBlank()) {
                putExtra("notification_payload", payloadJson)
            }
        }

        val contentPendingIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                notificationId,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.sym_action_chat)
            .setContentTitle(title)
            .setContentText(body)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .setStyle(style)
            .setNumber(history.length())
            .setOnlyAlertOnce(false)
            .setAllowSystemGeneratedContextualActions(true)

        if (enableQuickReply) {
            builder.addAction(replyAction)
        }

        if (contentPendingIntent != null) {
            builder.setContentIntent(contentPendingIntent)
        }

        NotificationManagerCompat.from(this).notify(notificationId, builder.build())
    }

    private fun buildConversationKey(
        conversationType: String,
        groupId: String,
        replyRecipientId: String,
        notificationId: Int,
    ): String {
        if (conversationType == "group" && groupId.isNotBlank()) {
            return "group:$groupId"
        }

        if (replyRecipientId.isNotBlank()) {
            return "direct:$replyRecipientId"
        }

        return "id:$notificationId"
    }

    private fun appendChatHistory(
        conversationKey: String,
        senderName: String,
        body: String,
    ): JSONArray {
        val prefs = getSharedPreferences(CHAT_NOTIFICATION_HISTORY_PREFS, Context.MODE_PRIVATE)
        val prefKey = "history_$conversationKey"
        val existingRaw = prefs.getString(prefKey, null)
        val updated = JSONArray()

        if (!existingRaw.isNullOrBlank()) {
            try {
                val existing = JSONArray(existingRaw)
                val start = maxOf(0, existing.length() - (CHAT_NOTIFICATION_HISTORY_LIMIT - 1))
                for (i in start until existing.length()) {
                    updated.put(existing.optJSONObject(i) ?: JSONObject())
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to parse notification history for $conversationKey", e)
            }
        }

        updated.put(
            JSONObject().apply {
                put("sender", senderName)
                put("text", body)
                put("ts", System.currentTimeMillis())
            },
        )

        prefs.edit().putString(prefKey, updated.toString()).apply()
        return updated
    }

    private fun ensureNotificationChannel(channelId: String, channelName: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager = getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            channelId,
            channelName,
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            enableVibration(true)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    private fun enterPipMode(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val params = PictureInPictureParams.Builder()
                    .setAspectRatio(Rational(9, 16))
                    .setActions(buildPipActions())
                    .build()
                Log.d(TAG, "Entering PiP mode with actions...")
                val success = enterPictureInPictureMode(params)
                Log.d(TAG, "enterPictureInPictureMode result: $success")
                return success
            } catch (e: Exception) {
                Log.e(TAG, "Error entering PiP mode: ${e.message}", e)
                return false
            }
        }
        Log.d(TAG, "PiP not available (SDK < O)")
        return false
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        Log.d(TAG, "onUserLeaveHint: isInCall=$isInCall, pipAvailable=${isPipAvailable()}")
        // Auto-enter PiP when user presses home button during a call
        if (isInCall && isPipAvailable()) {
            enterPipMode()
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        Log.d(TAG, "onPictureInPictureModeChanged: $isInPictureInPictureMode")
        // Notify Flutter about PiP mode change
        methodChannel?.invokeMethod("onPipModeChanged", isInPictureInPictureMode)
    }
}
