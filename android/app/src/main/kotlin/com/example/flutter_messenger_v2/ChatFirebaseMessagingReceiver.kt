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
    }

    override fun onReceive(context: Context, intent: Intent) {
        try {
            val extras = intent.extras ?: return
            val remoteMessage = RemoteMessage(extras)
            val data = remoteMessage.data

            if (!isChatMessage(data)) {
                return
            }

            if (isAppInForeground(context)) {
                Log.d(TAG, "App in foreground, skipping native background notification")
                return
            }

            showQuickReplyNotification(context, data)
        } catch (e: Exception) {
            Log.e(TAG, "Error handling native FCM broadcast", e)
        }
    }

    private fun isChatMessage(data: Map<String, String>): Boolean {
        val type = data["type"]?.lowercase()
        if (type == "call" || type == "color_change") {
            return false
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

        val builder = NotificationCompat.Builder(context, CHAT_CHANNEL_ID)
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

        NotificationManagerCompat.from(context).notify(notificationId, builder.build())
        Log.d(TAG, "Native quick-reply notification shown: $notificationId")
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
        return if (content.isNullOrEmpty()) null else content
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
        data["room_id"]?.takeIf { it.isNotBlank() }?.let {
            return "room:$it"
        }

        if (conversationType == "group" && groupId.isNotBlank()) {
            return "group:$groupId"
        }

        if (replyRecipientId.isNotBlank()) {
            return "direct:$replyRecipientId"
        }

        data["sender_id"]?.takeIf { it.isNotBlank() }?.let {
            return "direct:$it"
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
        data["room_id"]?.takeIf { it.isNotBlank() }?.let {
            return it.hashCode() and 0x7FFFFFFF
        }

        data["group_id"]?.takeIf { it.isNotBlank() }?.let {
            return "group:$it".hashCode() and 0x7FFFFFFF
        }

        data["sender_id"]?.takeIf { it.isNotBlank() }?.let {
            return "direct:$it".hashCode() and 0x7FFFFFFF
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
