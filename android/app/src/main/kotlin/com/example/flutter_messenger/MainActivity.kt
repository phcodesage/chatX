package com.example.flutter_messenger

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
import android.os.Build
import android.util.Log
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val TAG = "PiP"
    private val CHANNEL = "com.example.flutter_messenger/pip"
    private val AUDIO_CHANNEL = "com.example.flutter_messenger/audio_recorder"
    private var methodChannel: MethodChannel? = null
    private var isInCall = false
    private var isMuted = false

    // Native audio recorder for accurate amplitude readings
    @Suppress("DEPRECATION")
    private var audioRecorder: MediaRecorder? = null
    private var currentRecordingPath: String? = null

    companion object {
        private const val ACTION_TOGGLE_MIC = "com.example.flutter_messenger.PIP_TOGGLE_MIC"
        private const val ACTION_END_CALL = "com.example.flutter_messenger.PIP_END_CALL"
        private const val REQUEST_TOGGLE_MIC = 1001
        private const val REQUEST_END_CALL = 1002
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
        val screenShareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.flutter_messenger/screen_share")
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
        super.onDestroy()
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
