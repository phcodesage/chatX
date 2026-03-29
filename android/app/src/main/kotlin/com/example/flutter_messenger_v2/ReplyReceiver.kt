package com.example.flutter_messenger_v2

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.RemoteInput
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

class ReplyReceiver : BroadcastReceiver() {
    companion object {
        const val KEY_TEXT_REPLY = "key_text_reply"

        private const val TAG = "ReplyReceiver"
        private const val CHAT_CHANNEL_ID = "chat_messages"
        private const val FLUTTER_PREFS = "FlutterSharedPreferences"
        private const val TOKEN_KEY = "flutter.auth_token"
        private const val DEFAULT_BASE_URL = "https://inspect.flask-call-app.site"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val pendingResult = goAsync()

        Thread {
            try {
                handleReply(context, intent)
            } catch (e: Exception) {
                Log.e(TAG, "Unexpected quick-reply error", e)
            } finally {
                pendingResult.finish()
            }
        }.start()
    }

    private fun handleReply(context: Context, intent: Intent) {
        val results = RemoteInput.getResultsFromIntent(intent) ?: return
        val replyText = results.getCharSequence(KEY_TEXT_REPLY)?.toString()?.trim()
        if (replyText.isNullOrEmpty()) {
            return
        }

        val notificationId = resolveNotificationId(intent)
        val endpoint = intent.getStringExtra("reply_endpoint")?.trim().orEmpty()
        val conversationType = intent.getStringExtra("conversation_type")?.lowercase()
        val groupId = intent.getStringExtra("group_id")?.trim()
        val recipientId = intent.getStringExtra("reply_recipient_id")?.trim()
        val baseUrl = intent.getStringExtra("base_url")?.trim().orEmpty()
        val channelId = intent.getStringExtra("channel_id")?.ifBlank { CHAT_CHANNEL_ID } ?: CHAT_CHANNEL_ID
        val notificationManager = NotificationManagerCompat.from(context)

        val url = resolveQuickReplyUrl(
            endpoint = endpoint,
            baseUrl = if (baseUrl.isNotEmpty()) baseUrl else DEFAULT_BASE_URL,
            conversationType = conversationType,
            groupId = groupId,
        ) ?: return

        val authToken = readAuthToken(context)
        if (authToken.isNullOrEmpty()) {
            Log.e(TAG, "No auth token available for quick reply")
            showFailureNotification(context, notificationManager, notificationId, channelId, "Sign in to reply")
            return
        }

        // Clear the source notification immediately before sending so there is
        // no transient "Sending reply" entry that can get stuck on some devices.
        cancelReplyNotifications(notificationManager, intent, notificationId)

        val isGroup = conversationType == "group" ||
            !groupId.isNullOrEmpty() ||
            endpoint.contains("/groups/")

        val payload = JSONObject().apply {
            put("content", replyText)
            if (!isGroup) {
                val recipientIdInt = recipientId?.toIntOrNull()
                if (recipientIdInt != null) {
                    put("recipient_id", recipientIdInt)
                }
            }
        }

        val statusCode = postJson(url, authToken, payload.toString())

        if (statusCode in 200..299) {
            Log.d(TAG, "Quick reply sent successfully")
        } else {
            Log.e(TAG, "Quick reply failed with status $statusCode")
            showFailureNotification(context, notificationManager, notificationId, channelId, "Failed to send")
        }
    }

    private fun cancelReplyNotifications(
        notificationManager: NotificationManagerCompat,
        intent: Intent,
        resolvedNotificationId: Int,
    ) {
        val candidateIds = linkedSetOf<Int>()

        if (resolvedNotificationId > 0) {
            candidateIds.add(resolvedNotificationId)
        }

        intent.getIntExtra("notification_id", 0).takeIf { it > 0 }?.let {
            candidateIds.add(it)
        }
        intent.getIntExtra("notif_id", 0).takeIf { it > 0 }?.let {
            candidateIds.add(it)
        }

        val payloadJson = intent.getStringExtra("payload_json")
        if (!payloadJson.isNullOrBlank()) {
            try {
                val json = JSONObject(payloadJson)
                json.optString("room_id", "")
                    .takeIf { it.isNotBlank() }
                    ?.let { candidateIds.add(it.hashCode() and 0x7FFFFFFF) }

                json.optString("group_id", "")
                    .takeIf { it.isNotBlank() }
                    ?.let { candidateIds.add("group:$it".hashCode() and 0x7FFFFFFF) }

                json.optString("sender_id", "")
                    .takeIf { it.isNotBlank() }
                    ?.let { candidateIds.add("direct:$it".hashCode() and 0x7FFFFFFF) }

                json.optString("message_id", "")
                    .takeIf { it.isNotBlank() }
                    ?.let { candidateIds.add("msg:$it".hashCode() and 0x7FFFFFFF) }
            } catch (e: Exception) {
                Log.w(TAG, "Unable to parse payload_json while clearing notifications", e)
            }
        }

        candidateIds.forEach { id ->
            notificationManager.cancel(id)
        }
    }

    private fun resolveNotificationId(intent: Intent): Int {
        val primaryId = intent.getIntExtra("notification_id", 0)
        if (primaryId > 0) {
            return primaryId
        }

        // Backward-compat for older payload key naming.
        val legacyId = intent.getIntExtra("notif_id", 0)
        if (legacyId > 0) {
            return legacyId
        }

        val payloadJson = intent.getStringExtra("payload_json")
        if (!payloadJson.isNullOrBlank()) {
            try {
                val json = JSONObject(payloadJson)

                val roomId = json.optString("room_id", "")
                if (roomId.isNotBlank()) {
                    return roomId.hashCode() and 0x7FFFFFFF
                }

                val groupId = json.optString("group_id", "")
                if (groupId.isNotBlank()) {
                    return "group:$groupId".hashCode() and 0x7FFFFFFF
                }

                val senderId = json.optString("sender_id", "")
                if (senderId.isNotBlank()) {
                    return "direct:$senderId".hashCode() and 0x7FFFFFFF
                }
            } catch (e: Exception) {
                Log.w(TAG, "Unable to parse payload_json for notification ID", e)
            }
        }

        return (System.currentTimeMillis() / 1000L).toInt()
    }

    private fun resolveQuickReplyUrl(
        endpoint: String,
        baseUrl: String,
        conversationType: String?,
        groupId: String?,
    ): String? {
        if (endpoint.isNotEmpty()) {
            if (endpoint.startsWith("http://") || endpoint.startsWith("https://")) {
                return endpoint
            }

            val normalizedPath = if (endpoint.startsWith("/")) endpoint else "/$endpoint"
            return baseUrl.trimEnd('/') + normalizedPath
        }

        if (conversationType == "group" || !groupId.isNullOrEmpty()) {
            val validGroupId = groupId ?: return null
            return "${baseUrl.trimEnd('/')}/api/mobile/groups/$validGroupId/messages/quick-reply"
        }

        return "${baseUrl.trimEnd('/')}/api/mobile/messages/quick-reply"
    }

    private fun readAuthToken(context: Context): String? {
        val prefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
        return prefs.getString(TOKEN_KEY, null)
    }

    private fun postJson(url: String, authToken: String, body: String): Int {
        var connection: HttpURLConnection? = null

        return try {
            connection = (URL(url).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 15000
                readTimeout = 20000
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("Authorization", "Bearer $authToken")
            }

            connection.outputStream.bufferedWriter(Charsets.UTF_8).use { writer ->
                writer.write(body)
                writer.flush()
            }

            connection.responseCode
        } catch (e: Exception) {
            Log.e(TAG, "Quick reply network error", e)
            -1
        } finally {
            connection?.disconnect()
        }
    }

    private fun showFailureNotification(
        context: Context,
        notificationManager: NotificationManagerCompat,
        notificationId: Int,
        channelId: String,
        message: String,
    ) {
        val notification = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(android.R.drawable.stat_notify_error)
            .setContentTitle("Reply failed")
            .setContentText(message)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()

        notificationManager.notify(notificationId, notification)
    }
}
