package com.example.item2art

import android.app.PendingIntent
import android.content.Intent
import android.nfc.NfcAdapter
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private val channelName = "nfc_foreground"
	private var pendingIntent: PendingIntent? = null
	private var nfcAdapter: NfcAdapter? = null
	private var foregroundEnabled = false

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		nfcAdapter = NfcAdapter.getDefaultAdapter(this)
		createPendingIntent()

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
			when (call.method) {
				"enableExclusive" -> {
					val ok = enableExclusive()
					result.success(ok)
				}
				"disableExclusive" -> {
					disableExclusive()
					result.success(true)
				}
				else -> result.notImplemented()
			}
		}
	}

	private fun createPendingIntent() {
		val intent = Intent(this, javaClass).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
		pendingIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
			PendingIntent.getActivity(
				this, 0, intent,
				PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
			)
		} else {
			PendingIntent.getActivity(
				this, 0, intent,
				PendingIntent.FLAG_UPDATE_CURRENT
			)
		}
	}

	private fun enableExclusive(): Boolean {
		if (foregroundEnabled) return true
		val adapter = nfcAdapter ?: return false
		val pi = pendingIntent ?: return false
		return try {
			adapter.enableForegroundDispatch(this, pi, null, null)
			foregroundEnabled = true
			true
		} catch (e: Exception) {
			false
		}
	}

	private fun disableExclusive() {
		if (!foregroundEnabled) return
		val adapter = nfcAdapter ?: return
		try {
			adapter.disableForegroundDispatch(this)
		} catch (_: Exception) {
		} finally {
			foregroundEnabled = false
		}
	}

	override fun onPause() {
		super.onPause()
		// Al salir de foreground se libera
		disableExclusive()
	}

	override fun onDestroy() {
		disableExclusive()
		super.onDestroy()
	}
}
