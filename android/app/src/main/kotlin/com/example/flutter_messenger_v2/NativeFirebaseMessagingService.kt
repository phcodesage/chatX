package com.example.flutter_messenger_v2

import android.util.Log
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

class NativeFirebaseMessagingService : FlutterFirebaseMessagingService() {
    companion object {
        private const val TAG = "NativeFcmService"
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        val data = remoteMessage.data
        Log.d(TAG, "onMessageReceived: id=${remoteMessage.messageId}, keys=${data.keys}")

        if (data.isNotEmpty()) {
            try {
                ChatFirebaseMessagingReceiver().handleDataMessage(
                    this,
                    data,
                    source = "service",
                    transportMessageId = remoteMessage.messageId,
                )
            } catch (e: Exception) {
                Log.e(TAG, "Failed native chat notification fallback", e)
            }
        }

        super.onMessageReceived(remoteMessage)
    }

    override fun onNewToken(token: String) {
        Log.d(TAG, "onNewToken received")
        super.onNewToken(token)
    }
}
