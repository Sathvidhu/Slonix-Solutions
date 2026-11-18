package com.montme.montme

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.os.Build
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import org.json.JSONObject

object MontmeAlerts {
    const val CHANNEL = "montme_work"
    fun channels(context: Context) {
        if (Build.VERSION.SDK_INT >= 26) context.getSystemService(NotificationManager::class.java).createNotificationChannel(NotificationChannel(CHANNEL,"Montme work and break alerts",NotificationManager.IMPORTANCE_HIGH))
    }
    fun allowed(context: Context): Boolean = Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
    fun show(context: Context, key: String, title: String, body: String): Boolean {
        channels(context)
        if (!allowed(context)) return false
        val prefs=context.getSharedPreferences("montme.alerts",Context.MODE_PRIVATE)
        val shown=prefs.getStringSet("shown",emptySet())!!.toMutableSet()
        if(shown.contains(key)) return true
        val intent = Intent(context, MainActivity::class.java).apply { flags=Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP; putExtra("open_notifications",true) }
        val pending = PendingIntent.getActivity(context,key.hashCode(),intent,PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if(Build.VERSION.SDK_INT>=26) Notification.Builder(context,CHANNEL) else Notification.Builder(context)
        val notification=builder.setSmallIcon(R.drawable.montme_notification).setContentTitle(title).setContentText(body).setStyle(Notification.BigTextStyle().bigText(body)).setAutoCancel(true).setContentIntent(pending).build()
        context.getSystemService(NotificationManager::class.java).notify(key,key.hashCode(),notification)
        shown.add(key);prefs.edit().putStringSet("shown",shown.toList().takeLast(1000).toSet()).apply()
        return true
    }
    private fun alarmIntent(context: Context,key: String,title: String="",body: String="") = Intent(context,MontmeAlarmReceiver::class.java).apply { action="com.montme.ALERT"; putExtra("key",key); putExtra("title",title);putExtra("body",body) }
    fun schedule(context:Context,key:String,title:String,body:String,at:Long) {
        val prefs=context.getSharedPreferences("montme.alerts",Context.MODE_PRIVATE)
        val saved=JSONObject(prefs.getString("scheduled","{}")!!)
        saved.put(key,JSONObject().put("title",title).put("body",body).put("at",at));prefs.edit().putString("scheduled",saved.toString()).apply()
        val pending=PendingIntent.getBroadcast(context,key.hashCode(),alarmIntent(context,key,title,body),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val manager=context.getSystemService(AlarmManager::class.java)
        if(Build.VERSION.SDK_INT>=23) manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,at,pending) else manager.set(AlarmManager.RTC_WAKEUP,at,pending)
    }
    fun cancel(context:Context,key:String) {
        val pending=PendingIntent.getBroadcast(context,key.hashCode(),alarmIntent(context,key),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        context.getSystemService(AlarmManager::class.java).cancel(pending);pending.cancel()
        val prefs=context.getSharedPreferences("montme.alerts",Context.MODE_PRIVATE);val saved=JSONObject(prefs.getString("scheduled","{}")!!);saved.remove(key);prefs.edit().putString("scheduled",saved.toString()).apply()
    }
    fun cancelAll(context:Context) { val saved=JSONObject(context.getSharedPreferences("montme.alerts",Context.MODE_PRIVATE).getString("scheduled","{}")!!);saved.keys().asSequence().toList().forEach{cancel(context,it)} }
    fun initializeFirebase(context:Context): FirebaseApp? {
        if(FirebaseApp.getApps(context).isNotEmpty())return FirebaseApp.getInstance()
        val raw=context.getSharedPreferences("montme.alerts",Context.MODE_PRIVATE).getString("firebase",null) ?: return null
        return try { val c=JSONObject(raw);FirebaseApp.initializeApp(context,FirebaseOptions.Builder().setApplicationId(c.getString("appId")).setApiKey(c.getString("apiKey")).setProjectId(c.getString("projectId")).setGcmSenderId(c.getString("senderId")).build()) } catch(_:Exception){null}
    }
}
class MontmeApplication: Application() { override fun onCreate(){super.onCreate();MontmeAlerts.channels(this);MontmeAlerts.initializeFirebase(this)} }
class MontmeMessagingService: FirebaseMessagingService() {
    override fun onNewToken(token:String) {getSharedPreferences("montme.alerts",MODE_PRIVATE).edit().putString("push_token",token).apply()}
    override fun onMessageReceived(message:RemoteMessage) {
        val key=message.data["notification_id"] ?: message.messageId ?: "work"
        MontmeAlerts.show(this,key,message.notification?.title ?: message.data["title"] ?: "Montme",message.notification?.body ?: message.data["body"] ?: "You have a new work notification.")
    }
}
class MontmeAlarmReceiver: BroadcastReceiver() {
    override fun onReceive(context:Context,intent:Intent) {
        val key=intent.getStringExtra("key") ?: return
        MontmeAlerts.show(context,key,intent.getStringExtra("title") ?: "Montme break reminder",intent.getStringExtra("body") ?: "Open Montme to review your break.")
        MontmeAlerts.cancel(context,key)
    }
}
class MontmeBootReceiver: BroadcastReceiver() {
    override fun onReceive(context:Context,intent:Intent) {
        val saved=JSONObject(context.getSharedPreferences("montme.alerts",Context.MODE_PRIVATE).getString("scheduled","{}")!!)
        saved.keys().asSequence().toList().forEach{key -> val item=saved.getJSONObject(key);MontmeAlerts.schedule(context,key,item.getString("title"),item.getString("body"),maxOf(System.currentTimeMillis()+1000,item.getLong("at")))}
    }
}
