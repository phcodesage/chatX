package com.cloudwebrtc.webrtc;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;

public class FlutterWebRTCForegroundService extends Service {

    private static final String CHANNEL_ID = "screen_share_channel";
    private static final int NOTIFICATION_ID = 9999;

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannel();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String title = "Screen Sharing";
        String text = "You are sharing your screen";

        if (intent != null) {
            if (intent.hasExtra("notificationTitle")) {
                title = intent.getStringExtra("notificationTitle");
            }
            if (intent.hasExtra("notificationText")) {
                text = intent.getStringExtra("notificationText");
            }
        }

        Notification notification = buildNotification(title, text);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION);
        } else {
            startForeground(NOTIFICATION_ID, notification);
        }

        return START_NOT_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                    CHANNEL_ID,
                    "Screen Sharing",
                    NotificationManager.IMPORTANCE_LOW
            );
            channel.setDescription("Notification for screen sharing");
            NotificationManager manager = getSystemService(NotificationManager.class);
            if (manager != null) {
                manager.createNotificationChannel(channel);
            }
        }
    }

    private Notification buildNotification(String title, String text) {
        Notification.Builder builder;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            builder = new Notification.Builder(this, CHANNEL_ID);
        } else {
            builder = new Notification.Builder(this);
        }
        return builder
                .setContentTitle(title)
                .setContentText(text)
                .setSmallIcon(android.R.drawable.ic_menu_camera)
                .build();
    }
}
