package com.example.deepmusic

import android.os.Build
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "deepmusic/device_info"
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getSdkInt" -> result.success(Build.VERSION.SDK_INT)
                else -> result.notImplemented()
            }
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        when (keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> {
                methodChannel?.invokeMethod("volumeUp", null)
                // consume event to prevent system volume UI
                return true
            }
            KeyEvent.KEYCODE_VOLUME_DOWN -> {
                methodChannel?.invokeMethod("volumeDown", null)
                return true
            }
        }
        return super.onKeyDown(keyCode, event)
    }
}


