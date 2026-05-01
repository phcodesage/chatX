package com.example.flutter_messenger_v2

import android.app.ActivityManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person
import androidx.core.app.RemoteInput
import com.google.firebase.messaging.RemoteMessage
import org.json.JSONArray
import org.json.JSONObject

class ChatFirebaseMessagingReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "ChatFcmReceiver"
        private const val CHAT_CHANNEL_ID = "chat_messages"
        private const val CHAT_CHANNEL_NAME = "Chat Messages"
        private val DEFAULT_BASE_URL: String = BuildConfig.BASE_URL
        private const val REQUEST_QUICK_REPLY = 4100
        private const val CHAT_NOTIFICATION_HISTORY_PREFS = "chat_notification_history"
        private const val CHAT_NOTIFICATION_HISTORY_LIMIT = 12
        private const val FLUTTER_PREFS = "FlutterSharedPreferences"
        private const val CURRENT_USER_ID_KEY = "flutter.user_id"
        private const val DUPLICATE_WINDOW_MS = 8000L
        private const val MAX_RECENT_KEYS = 120
        private val recentNotificationKeys = LinkedHashMap<String, Long>()
    }

    override fun onReceive(context: Context, intent: Intent) {
        try {
            val extras = intent.extras ?: return
            val remoteMessage = RemoteMessage(extras)
            handleDataMessage(
                context,
                remoteMessage.data,
                source = "broadcast",
                transportMessageId = remoteMessage.messageId,
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error handling native FCM broadcast", e)
        }
    }

    fun handleDataMessage(
        context: Context,
        data: Map<String, String>,
        source: String = "service",
        transportMessageId: String? = null,
    ) {
        if (!isChatMessage(data)) {
            return
        }

        val dedupeKey = buildDedupeKey(data, transportMessageId)
        if (isLikelyDuplicate(dedupeKey)) {
            Log.d(TAG, "Skipping duplicate chat notification ($source): $dedupeKey")
            return
        }

        if (isAppInForeground(context)) {
            Log.d(TAG, "App in foreground, skipping native background notification ($source)")
            return
        }

        // Suppress echo notifications for messages sent by the current user
        // (e.g. quick-reply echoes from the server after a notification reply)
        // Flutter's shared_preferences stores int values via putLong on Android.
        val senderId = data["sender_id"]?.trim()
        if (!senderId.isNullOrBlank()) {
            try {
                val currentUserId = context
                    .getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
                    .getLong(CURRENT_USER_ID_KEY, -1L)
                if (currentUserId != -1L && senderId == currentUserId.toString()) {
                    Log.d(TAG, "Suppressing echo notification from self (sender=$senderId, source=$source)")
                    return
                }
            } catch (e: Exception) {
                Log.w(TAG, "Could not read current user ID for echo suppression", e)
            }
        }

        showQuickReplyNotification(context, data)
    }

    private fun buildDedupeKey(data: Map<String, String>, transportMessageId: String?): String {
        if (!transportMessageId.isNullOrBlank()) {
            return "fcm:$transportMessageId"
        }

        val stableMessageId = data["message_id"]?.trim()
        if (!stableMessageId.isNullOrEmpty()) {
            return "msg:$stableMessageId"
        }

        val senderId = data["sender_id"]?.trim().orEmpty()
        val roomId = data["room_id"]?.trim().orEmpty()
        val groupId = data["group_id"]?.trim().orEmpty()
        val body = resolveBody(data)?.trim().orEmpty()
        val content = data["content"]?.trim().orEmpty()
        val ts = data["timestamp"]?.trim().orEmpty()

        return "fallback:$senderId:$roomId:$groupId:$ts:${body.hashCode()}:${content.hashCode()}"
    }

    private fun isLikelyDuplicate(key: String): Boolean {
        val now = System.currentTimeMillis()

        synchronized(recentNotificationKeys) {
            val iterator = recentNotificationKeys.entries.iterator()
            while (iterator.hasNext()) {
                val entry = iterator.next()
                if (now - entry.value > DUPLICATE_WINDOW_MS) {
                    iterator.remove()
                }
            }

            val lastSeenAt = recentNotificationKeys[key]
            if (lastSeenAt != null && now - lastSeenAt <= DUPLICATE_WINDOW_MS) {
                return true
            }

            recentNotificationKeys[key] = now

            while (recentNotificationKeys.size > MAX_RECENT_KEYS) {
                val oldestKey = recentNotificationKeys.keys.firstOrNull() ?: break
                recentNotificationKeys.remove(oldestKey)
            }

            return false
        }
    }

    private fun isChatMessage(data: Map<String, String>): Boolean {
        val type = data["type"]?.lowercase()
        if (type == "call") {
            return false
        }

        if (type == "message" || type == "chat") {
            return true
        }

        if (!data["title"].isNullOrBlank() ||
            !data["body"].isNullOrBlank() ||
            !data["content"].isNullOrBlank()) {
            return true
        }

        return !data["room_id"].isNullOrBlank() ||
            !data["group_id"].isNullOrBlank() ||
            !data["sender_id"].isNullOrBlank() ||
            !data["sender_name"].isNullOrBlank()
    }

    private fun supportsQuickReply(data: Map<String, String>): Boolean {
        val type = data["type"]?.lowercase() ?: return false
        return type == "message" || type == "chat"
    }

    private fun showQuickReplyNotification(context: Context, data: Map<String, String>) {
        val title = resolveTitle(data) ?: return
        val body = resolveBody(data) ?: return
        val notificationId = resolveNotificationId(data)
        val senderName = data["sender_name"].orEmpty().ifBlank { "Someone" }
        val groupName = data["group_name"].orEmpty()
        val conversationType = data["conversation_type"]?.lowercase() ?: if (data["group_id"].isNullOrEmpty()) "direct" else "group"
        val groupId = data["group_id"].orEmpty()
        val isGroup = conversationType == "group" || groupId.isNotBlank()
        val replyEndpoint = resolveReplyEndpoint(data, conversationType, groupId)
        val replyRecipientId = (data["reply_recipient_id"] ?: data["sender_id"]).orEmpty()
        val enableQuickReply = supportsQuickReply(data)
        val baseUrl = data["base_url"].orEmpty().ifBlank { DEFAULT_BASE_URL }
        val payloadJson = JSONObject(data as Map<*, *>).toString()

        ensureChannel(context)

        val replyIntent = Intent(context, ReplyReceiver::class.java).apply {
            putExtra("notification_id", notificationId)
            putExtra("reply_endpoint", replyEndpoint)
            putExtra("reply_recipient_id", replyRecipientId)
            putExtra("conversation_type", conversationType)
            putExtra("group_id", groupId)
            putExtra("base_url", baseUrl)
            putExtra("channel_id", CHAT_CHANNEL_ID)
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
            context,
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

        val conversationKey = buildConversationKey(data, conversationType, groupId, replyRecipientId, notificationId)
        val history = appendChatHistory(context, conversationKey, senderName, body)

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

        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("notification_payload", payloadJson)
        }

        val contentPendingIntent = launchIntent?.let {
            PendingIntent.getActivity(
                context,
                notificationId,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        val groupKey = "chat:$conversationKey"
        val nm = NotificationManagerCompat.from(context)

        // ── Per-message notification: unique ID ensures each message triggers its own
        // heads-up popup so rapid messages appear one-by-one (Skype/WhatsApp style).
        val messageNotifId = resolveMessageNotificationId(data)
        val msgBuilder = NotificationCompat.Builder(context, CHAT_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.sym_action_chat)
            .setContentTitle(title)
            .setContentText(body)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .setGroup(groupKey)
            .setOnlyAlertOnce(false)
            .setSortKey(System.currentTimeMillis().toString())
        if (enableQuickReply) msgBuilder.addAction(replyAction)
        if (contentPendingIntent != null) msgBuilder.setContentIntent(contentPendingIntent)
        nm.notify(messageNotifId, msgBuilder.build())

        // ── Group summary: MessagingStyle with full accumulated history.
        // setGroupSummary(true) collapses all individual notifications into one expandable
        // thread in the drawer. setOnlyAlertOnce(true) avoids double-vibrating.
        val summaryBuilder = NotificationCompat.Builder(context, CHAT_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.sym_action_chat)
            .setContentTitle(title)
            .setContentText(body)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .setStyle(style)
            .setGroup(groupKey)
            .setGroupSummary(true)
            .setNumber(history.length())
            .setOnlyAlertOnce(true)
            .setAllowSystemGeneratedContextualActions(true)
        if (enableQuickReply) summaryBuilder.addAction(replyAction)
        if (contentPendingIntent != null) summaryBuilder.setContentIntent(contentPendingIntent)
        nm.notify(notificationId, summaryBuilder.build())

        Log.d(TAG, "Notifications: msg=$messageNotifId summary=$notificationId group=$groupKey msgs=${history.length()}")
    }

    private fun resolveMessageNotificationId(data: Map<String, String>): Int {
        data["message_id"]?.takeIf { it.isNotBlank() }?.let {
            return "msg:$it".hashCode() and 0x7FFFFFFF
        }
        return ("msg_ts:${System.currentTimeMillis()}").hashCode() and 0x7FFFFFFF
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            CHAT_CHANNEL_ID,
            CHAT_CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            enableVibration(true)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    private fun resolveTitle(data: Map<String, String>): String? {
        val providedTitle = data["title"]?.trim()
        if (!providedTitle.isNullOrEmpty()) {
            return providedTitle
        }

        val senderName = data["sender_name"]?.trim().orEmpty()
        if (senderName.isBlank()) {
            return "New message"
        }

        val groupName = data["group_name"]?.trim().orEmpty()
        if (groupName.isNotBlank()) {
            return "💬 $senderName ($groupName)"
        }

        return "💬 $senderName"
    }

    private fun resolveBody(data: Map<String, String>): String? {
        val body = data["body"]?.trim()
        if (!body.isNullOrEmpty()) {
            return body
        }

        val content = data["content"]?.trim()
        if (!content.isNullOrEmpty()) {
            return content
        }

        val messageType = (data["message_type"] ?: data["messageType"])?.lowercase()
        val fileName = (data["file_name"] ?: data["fileName"]).orEmpty().trim()

        return when (messageType) {
            "audio", "voice" -> "🎤 Voice message"
            "image" -> if (fileName.isNotBlank()) "🖼️ Image: $fileName" else "🖼️ Image"
            "video" -> if (fileName.isNotBlank()) "🎬 Video: $fileName" else "🎬 Video"
            "file" -> if (fileName.isNotBlank()) "📎 File: $fileName" else "📎 File"
            "contact" -> "👤 Contact card"
            else -> if (fileName.isNotBlank()) "📎 $fileName" else null
        }
    }

    private fun resolveReplyEndpoint(
        data: Map<String, String>,
        conversationType: String,
        groupId: String,
    ): String {
        val explicit = data["reply_endpoint"]?.trim()
        if (!explicit.isNullOrEmpty()) {
            return explicit
        }

        if (conversationType == "group" && groupId.isNotBlank()) {
            return "/api/mobile/groups/$groupId/messages/quick-reply"
        }

        return "/api/mobile/messages/quick-reply"
    }

    private fun buildConversationKey(
        data: Map<String, String>,
        conversationType: String,
        groupId: String,
        replyRecipientId: String,
        notificationId: Int,
    ): String {
        if (conversationType == "group" && groupId.isNotBlank()) {
            return "group:$groupId"
        }

        data["sender_id"]?.takeIf { it.isNotBlank() }?.let {
            return "direct:$it"
        }

        if (replyRecipientId.isNotBlank()) {
            return "direct:$replyRecipientId"
        }

        data["room_id"]?.takeIf { it.isNotBlank() }?.let {
            return "room:$it"
        }

        data["sender_name"]?.takeIf { it.isNotBlank() }?.let {
            return "sender:$it"
        }

        return "id:$notificationId"
    }

    private fun appendChatHistory(
        context: Context,
        conversationKey: String,
        senderName: String,
        body: String,
    ): JSONArray {
        val prefs = context.getSharedPreferences(CHAT_NOTIFICATION_HISTORY_PREFS, Context.MODE_PRIVATE)
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

    private fun resolveNotificationId(data: Map<String, String>): Int {
        data["group_id"]?.takeIf { it.isNotBlank() }?.let {
            return "group:$it".hashCode() and 0x7FFFFFFF
        }

        data["sender_id"]?.takeIf { it.isNotBlank() }?.let {
            return "direct:$it".hashCode() and 0x7FFFFFFF
        }

        data["room_id"]?.takeIf { it.isNotBlank() }?.let {
            return it.hashCode() and 0x7FFFFFFF
        }

        data["message_id"]?.takeIf { it.isNotBlank() }?.let {
            return "msg:$it".hashCode() and 0x7FFFFFFF
        }

        return (System.currentTimeMillis() / 1000L).toInt()
    }

    private fun isAppInForeground(context: Context): Boolean {
        val activityManager =
            context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                ?: return false

        val runningProcesses = activityManager.runningAppProcesses ?: return false
        val packageName = context.packageName

        return runningProcesses.any { process ->
            process.processName == packageName &&
                process.importance <= ActivityManager.RunningAppProcessInfo.IMPORTANCE_VISIBLE
        }
    }
}
