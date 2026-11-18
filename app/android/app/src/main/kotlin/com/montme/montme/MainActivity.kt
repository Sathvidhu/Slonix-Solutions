package com.montme.montme

import com.google.firebase.messaging.FirebaseMessaging
import org.json.JSONObject
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.net.Uri
import android.provider.DocumentsContract
import android.media.MediaMetadataRetriever
import android.util.Base64
import io.flutter.plugin.common.EventChannel
import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.CallLog
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private var since: Long = 0
    private var fileResult: MethodChannel.Result? = null
    private var fileData: String = ""
    private var binaryFile = false
    private var folderResult: MethodChannel.Result? = null
    private var callObserver: ContentObserver? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,"com.montme/alerts").setMethodCallHandler { call,result ->
            when(call.method) {
                "permission" -> { if(Build.VERSION.SDK_INT>=33 && !MontmeAlerts.allowed(this))requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS),704);result.success(MontmeAlerts.allowed(this)) }
                "status" -> result.success(mapOf("allowed" to MontmeAlerts.allowed(this),"token" to getSharedPreferences("montme.alerts",MODE_PRIVATE).getString("push_token",null),"openInbox" to intent.getBooleanExtra("open_notifications",false)))
                "show" -> result.success(MontmeAlerts.show(this,call.argument<String>("key") ?: "work",call.argument<String>("title") ?: "Montme",call.argument<String>("body") ?: ""))
                "schedule" -> { MontmeAlerts.schedule(this,call.argument<String>("key")!!,call.argument<String>("title")!!,call.argument<String>("body")!!,call.argument<Number>("at")!!.toLong());result.success(true) }
                "cancel" -> { MontmeAlerts.cancel(this,call.argument<String>("key")!!);result.success(true) }
                "clear" -> { MontmeAlerts.cancelAll(this);if(call.argument<Boolean>("dismiss")==true)getSystemService(android.app.NotificationManager::class.java).cancelAll();result.success(true) }
                "configurePush" -> {
                    val config=call.argument<Map<String,String>>("config") ?: emptyMap()
                    if(listOf("appId","apiKey","projectId","senderId").any{config[it].isNullOrBlank()}) {result.success(null)}
                    else {
                        getSharedPreferences("montme.alerts",MODE_PRIVATE).edit().putString("firebase",JSONObject(config).toString()).apply()
                        if(MontmeAlerts.initializeFirebase(this)==null)result.error("PUSH","Firebase configuration is invalid.",null)
                        else FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                            if(task.isSuccessful){getSharedPreferences("montme.alerts",MODE_PRIVATE).edit().putString("push_token",task.result).apply();result.success(task.result)}
                            else result.error("PUSH","Push registration failed. Check Firebase configuration and Google Play services.",null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.montme/callChanges").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                callObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
                    override fun onChange(selfChange: Boolean) { events.success(true) }
                }
                contentResolver.registerContentObserver(CallLog.Calls.CONTENT_URI, true, callObserver!!)
            }
            override fun onCancel(arguments: Any?) { callObserver?.let { contentResolver.unregisterContentObserver(it) }; callObserver = null }
        })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.montme/files")
            .setMethodCallHandler { call, result ->
                if (call.method == "selectFolder") {
                    if (folderResult != null) { result.error("BUSY", "Folder picker is open.", null); return@setMethodCallHandler }
                    folderResult = result
                    try { startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply { addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION) }, 703) }
                    catch (e: Exception) { folderResult = null; result.error("FOLDER", "Folder picker unavailable.", null) }
                    return@setMethodCallHandler
                }
                if (call.method == "recordings") { readRecordings(result); return@setMethodCallHandler }
                if (call.method != "save") { result.notImplemented(); return@setMethodCallHandler }
                if (fileResult != null) { result.error("BUSY", "A file picker is already open.", null); return@setMethodCallHandler }
                fileResult = result
                fileData = call.argument<String>("data") ?: ""
                binaryFile = call.argument<Boolean>("base64") ?: false
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = call.argument<String>("mime") ?: "text/plain"
                    putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "montme-export.txt")
                }
                try { startActivityForResult(intent, 702) }
                catch (e: Exception) { fileResult = null; fileData = ""; result.error("SAVE", "No file picker is available.", null) }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.montme/calls")
            .setMethodCallHandler { call, result ->
                if (call.method != "readCalls") { result.notImplemented(); return@setMethodCallHandler }
                if (pending != null) { result.error("BUSY", "An import is already running.", null); return@setMethodCallHandler }
                since = call.argument<Number>("since")?.toLong() ?: System.currentTimeMillis()
                if (Build.VERSION.SDK_INT >= 23 && checkSelfPermission(Manifest.permission.READ_CALL_LOG) != PackageManager.PERMISSION_GRANTED) {
                    pending = result
                    requestPermissions(arrayOf(Manifest.permission.READ_CALL_LOG), 701)
                } else { readCalls(result) }
            }
    }
    @Deprecated("Uses the FlutterActivity activity result bridge")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 703) {
            val result = folderResult ?: return
            folderResult = null
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) { result.success(null); return }
            try {
                contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                getSharedPreferences("montme.native", MODE_PRIVATE).edit().putString("folder", uri.toString()).apply()
                result.success(uri.toString())
            } catch (e: Exception) { result.error("FOLDER", "Could not retain folder access.", null) }
            return
        }
        if (requestCode != 702) return
        val result = fileResult ?: return
        val payload = fileData
        val isBinary = binaryFile
        fileResult = null
        fileData = ""
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { result.success(false); return }
        Thread {
            try {
                val stream = contentResolver.openOutputStream(uri) ?: throw IllegalStateException("No output stream")
                stream.use { it.write(if (isBinary) Base64.decode(payload, Base64.DEFAULT) else payload.toByteArray(Charsets.UTF_8)) }
                runOnUiThread { result.success(true) }
            } catch (e: Exception) { runOnUiThread { result.error("SAVE", "Could not save this file.", null) } }
        }.start()
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 701) return
        val result = pending ?: return
        pending = null
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) readCalls(result)
        else result.error("PERMISSION", "Call-log access was not granted. Manual call logging is still available. Enable permission in Android settings to retry.", null)
    }
    private fun readRecordings(result: MethodChannel.Result) {
        val raw = getSharedPreferences("montme.native", MODE_PRIVATE).getString("folder", null)
        if (raw == null) { result.error("FOLDER", "Select a recording folder first.", null); return }
        Thread {
            try {
                val tree = Uri.parse(raw)
                val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
                val rows = mutableListOf<Map<String, Any?>>()
                contentResolver.query(children, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE, DocumentsContract.Document.COLUMN_LAST_MODIFIED), null, null, null)?.use { cursor ->
                    while(cursor.moveToNext()) {
                        val name = cursor.getString(1) ?: "Recording"
                        val mime = cursor.getString(2) ?: ""
                        if (!mime.startsWith("audio/") && !name.lowercase().matches(Regex(".*\\.(m4a|mp3|wav|amr|aac|ogg|3gp)"))) continue
                        val uri = DocumentsContract.buildDocumentUriUsingTree(tree, cursor.getString(0))
                        var duration: Long? = null
                        val metadata = MediaMetadataRetriever()
                        try { metadata.setDataSource(this, uri); duration = metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() } catch (_: Exception) {} finally { metadata.release() }
                        rows.add(mapOf("name" to name, "uri" to uri.toString(), "modified" to cursor.getLong(3), "duration" to duration))
                    }
                }
                runOnUiThread { result.success(rows) }
            } catch(e: Exception) { runOnUiThread { result.error("FOLDER", "Folder access unavailable. Ask admin to select it again.", null) } }
        }.start()
    }
    private fun readCalls(result: MethodChannel.Result) {
        val lowerBound = since
        Thread {
            try {
                val rows = mutableListOf<Map<String, Any>>()
                val columns = arrayOf(CallLog.Calls._ID, CallLog.Calls.NUMBER, CallLog.Calls.DATE, CallLog.Calls.DURATION, CallLog.Calls.TYPE)
                contentResolver.query(CallLog.Calls.CONTENT_URI, columns, "${CallLog.Calls.DATE} >= ?", arrayOf(lowerBound.toString()), "${CallLog.Calls.DATE} DESC")?.use { cursor ->
                    while (cursor.moveToNext()) {
                        val type = cursor.getInt(4)
                        if (type !in listOf(CallLog.Calls.INCOMING_TYPE, CallLog.Calls.OUTGOING_TYPE, CallLog.Calls.MISSED_TYPE, CallLog.Calls.REJECTED_TYPE)) continue
                        rows.add(mapOf("id" to cursor.getString(0), "number" to (cursor.getString(1) ?: ""), "date" to cursor.getLong(2), "duration" to cursor.getLong(3), "direction" to when(type) {
                            CallLog.Calls.INCOMING_TYPE -> "Incoming"
                            CallLog.Calls.MISSED_TYPE -> "Missed"
                            CallLog.Calls.REJECTED_TYPE -> "Rejected"
                            else -> "Outgoing"
                        }))
                    }
                }
                runOnUiThread { result.success(rows) }
            } catch (e: SecurityException) { runOnUiThread { result.error("PERMISSION", "Call-log permission was revoked. Enable it in Android settings or log manually.", null) } }
            catch (e: Exception) { runOnUiThread { result.error("IMPORT", "Could not read this device's call log. Please retry.", null) } }
        }.start()
    }
}
