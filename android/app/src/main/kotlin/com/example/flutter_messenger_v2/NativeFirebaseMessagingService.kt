package com.example.flutter_messenger_v2

import android.util.Log
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

class NativeFirebaseMessagingService : FlutterFirebaseMessagingService() {
    companion object {
        private const val TAG = "NativeFcmService"
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        // Chat notification rendering is handled by ChatFirebaseMessagingReceiver.
        Log.d(TAG, "onMessageReceived: ${remoteMessage.messageId}")
        super.onMessageReceived(remoteMessage)
    }

    override fun onNewToken(token: String) {
        Log.d(TAG, "onNewToken received")
        super.onNewToken(token)
    }
}
