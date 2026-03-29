package com.example.flutter_messenger_v2

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.Configuration
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
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val TAG = "PiP"
    private val CHANNEL = "com.example.flutter_messenger_v2/pip"
    private val AUDIO_CHANNEL = "com.example.flutter_messenger_v2/audio_recorder"
    private val QUICK_REPLY_CHANNEL = "com.example.flutter_messenger_v2/quick_reply"
    private val SHARE_CHANNEL = "com.example.flutter_messenger_v2/share_target"
    private var methodChannel: MethodChannel? = null
    private var shareMethodChannel: MethodChannel? = null
    private var pendingSharedItems: List<Map<String, String>> = emptyList()
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
        pendingSharedItems = extractSharedItemsFromIntent(intent)
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
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        val sharedItems = extractSharedItemsFromIntent(intent)
        if (sharedItems.isEmpty()) {
            return
        }

        pendingSharedItems = sharedItems
        shareMethodChannel?.invokeMethod("onSharedItems", sharedItems)
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

        return extractedItems
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
        val groupId = (args["groupId"] as? String).orEmpty()
        val baseUrl = (args["baseUrl"] as? String).orEmpty()
        val payloadJson = (args["payloadJson"] as? String).orEmpty()

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

        val senderPerson = Person.Builder().setName(senderName).build()
        val mePerson = Person.Builder().setName("You").build()

        val style = NotificationCompat.MessagingStyle(mePerson)
            .addMessage(body, System.currentTimeMillis(), senderPerson)

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
            .setOnlyAlertOnce(false)
            .addAction(replyAction)
            .setAllowSystemGeneratedContextualActions(true)

        if (contentPendingIntent != null) {
            builder.setContentIntent(contentPendingIntent)
        }

        NotificationManagerCompat.from(this).notify(notificationId, builder.build())
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
