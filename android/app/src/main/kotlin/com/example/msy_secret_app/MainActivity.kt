package com.example.msy_secret_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.telephony.SmsMessage
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private val SMS_CHANNEL = "msy_secret/sms"
    private var smsReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        startService(Intent(this, MsySecretService::class.java))

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    smsReceiver = object : BroadcastReceiver() {
                        override fun onReceive(context: Context?, intent: Intent?) {
                            val bundle = intent?.extras ?: return
                            val pdus = bundle.get("pdus") as? Array<*> ?: return
                            
                            for (pdu in pdus) {
                                val sms = SmsMessage.createFromPdu(pdu as ByteArray)
                                val event = mapOf(
                                    "address" to (sms.originatingAddress ?: ""),
                                    "body" to (sms.messageBody ?: "")
                                )
                                events?.success(event)
                            }
                        }
                    }
                    registerReceiver(smsReceiver, IntentFilter("android.provider.Telephony.SMS_RECEIVED"))
                }

                override fun onCancel(arguments: Any?) {
                    unregisterReceiver(smsReceiver)
                    smsReceiver = null
                }
            }
        )
    }
}