package uz.telefontv.telefon_tv

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Pultdagi mikrofon: telefonning o‘z ovoz tanish xizmati (Google) orqali
 * gapni matnga aylantiradi. Eshitilayotgan so‘zlar `partial`, tayyor gap
 * `final` bilan Flutter’ga yuboriladi.
 */
class VoiceInput(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "telefon_tv/voice")
    private var recognizer: SpeechRecognizer? = null
    private var pending: (() -> Unit)? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "available" -> result.success(SpeechRecognizer.isRecognitionAvailable(activity))
                "start" -> {
                    if (!SpeechRecognizer.isRecognitionAvailable(activity)) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val locale = call.argument<String>("locale") ?: "uz-UZ"
                    withPermission { start(locale) }
                    result.success(true)
                }
                "stop" -> {
                    recognizer?.stopListening()
                    result.success(true)
                }
                "cancel" -> {
                    recognizer?.cancel()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun send(method: String, value: String) {
        activity.runOnUiThread { channel.invokeMethod(method, value) }
    }

    private fun withPermission(then: () -> Unit) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                pending = then
                activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST)
                return
            }
        }
        then()
    }

    /** MainActivity.onRequestPermissionsResult dan chaqiriladi. */
    fun onPermissionResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != REQUEST) return false
        val then = pending
        pending = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            then?.invoke()
        } else {
            send("error", "permission")
        }
        return true
    }

    private fun start(locale: String) {
        recognizer?.destroy()
        val r = SpeechRecognizer.createSpeechRecognizer(activity)
        r.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) = send("ready", locale)
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() = send("end", "")
            override fun onEvent(eventType: Int, params: Bundle?) {}

            override fun onPartialResults(partialResults: Bundle?) {
                val text = partialResults
                    ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    ?.firstOrNull()
                if (!text.isNullOrBlank()) send("partial", text)
            }

            override fun onResults(results: Bundle?) {
                val text = results
                    ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    ?.firstOrNull() ?: ""
                send("final", text)
            }

            override fun onError(error: Int) {
                val code = when (error) {
                    SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "permission"
                    SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "network"
                    SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "busy"
                    SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "nomatch"
                    12, 13 -> "language" // LANGUAGE_NOT_SUPPORTED / LANGUAGE_UNAVAILABLE
                    else -> "error"
                }
                send("error", code)
            }
        })
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, locale)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, activity.packageName)
        }
        r.startListening(intent)
        recognizer = r
    }

    fun dispose() {
        recognizer?.destroy()
        recognizer = null
    }

    companion object {
        private const val REQUEST = 4711
    }
}
