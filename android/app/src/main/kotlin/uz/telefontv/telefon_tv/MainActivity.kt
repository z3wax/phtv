package uz.telefontv.telefon_tv

import android.app.Activity
import android.app.Presentation
import android.app.UiModeManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.hardware.display.DisplayManager
import android.media.AudioManager
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.os.Handler
import android.os.Looper
import android.view.Display
import android.view.WindowManager
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * Telefon ekrani — pult, televizor (HDMI kabel, Miracast) — Smart TV.
 *
 * Televizor ulanganda ikkinchi Flutter dvigateli `tvMain` bilan ishga
 * tushadi va Android Presentation orqali faqat televizorda ko‘rinadi.
 */
class MainActivity : FlutterActivity() {
    private var displayManager: DisplayManager? = null
    private var presentation: TvPresentation? = null
    private var tvEngine: FlutterEngine? = null
    private var phoneChannel: MethodChannel? = null
    private var usb: UsbExporter? = null
    private var voice: VoiceInput? = null

    /** YouTube kabi boshqa ilova ochilganda TV oynasi vaqtincha yopiladi. */
    private var stepAside = false

    private val displayListener = object : DisplayManager.DisplayListener {
        override fun onDisplayAdded(displayId: Int) = showOnTv()
        override fun onDisplayRemoved(displayId: Int) {
            if (presentation?.display?.displayId == displayId) hideTv()
            // Televizor uzildi: TV dvigateli (va uning pult serveri) to‘xtaydi,
            // aks holda telefon ekranidagi Smart TV portni ololmaydi.
            if (presentation == null && !stepAside) releaseTvEngine()
        }
        override fun onDisplayChanged(displayId: Int) {}
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        phoneChannel = bindChannel(flutterEngine.dartExecutor.binaryMessenger)
        usb = UsbExporter(this, flutterEngine.dartExecutor.binaryMessenger)
        voice = VoiceInput(this, flutterEngine.dartExecutor.binaryMessenger)
        val dm = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        displayManager = dm
        dm.registerDisplayListener(displayListener, Handler(Looper.getMainLooper()))
    }

    /** Telefon TV bosh ekran bo‘lsa, Home tugmasi bosh sahifaga qaytaradi. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.hasCategory(Intent.CATEGORY_HOME)) phoneChannel?.invokeMethod("home", null)
    }

    /** Fleshka tanlash oynasining natijasi. */
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (usb?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    /** Mikrofon ruxsati (pultdagi AI yordamchi). */
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (voice?.onPermissionResult(requestCode, grantResults) == true) return
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onResume() {
        super.onResume()
        stepAside = false
        showOnTv()
    }

    override fun onDestroy() {
        displayManager?.unregisterDisplayListener(displayListener)
        presentation?.setOnDismissListener(null)
        presentation?.dismiss()
        presentation = null
        releaseTvEngine()
        voice?.dispose()
        super.onDestroy()
    }

    private fun bindChannel(messenger: BinaryMessenger): MethodChannel {
        val channel = MethodChannel(messenger, "telefon_tv/native")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "externalDisplay" -> result.success(presentation != null)
                "openUrl" -> result.success(openUrl(call.argument<String>("url")))
                "isTvDevice" -> result.success(isTvDevice())
                "isHomeLauncher" -> result.success(
                    packageManager.getComponentEnabledSetting(homeAlias()) ==
                        PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                )
                "setHomeLauncher" -> result.success(setHomeLauncher(call.argument<Boolean>("on") == true))
                "listApps" -> listApps(result)
                "launchApp" -> result.success(launchApp(call.argument<String>("package")))
                "volume" -> result.success(volume(call.argument<String>("action")))
                else -> result.notImplemented()
            }
        }
        return channel
    }

    private fun openUrl(url: String?): Boolean {
        if (url.isNullOrEmpty()) return false
        return startExternal(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
    }

    private fun launchApp(pkg: String?): Boolean {
        if (pkg.isNullOrEmpty()) return false
        val intent = packageManager.getLeanbackLaunchIntentForPackage(pkg)
            ?: packageManager.getLaunchIntentForPackage(pkg)
            ?: return false
        return startExternal(intent)
    }

    /** Media ovozi: televizorga HDMI orqali boradigan ovoz ham shu. */
    private fun volume(action: String?): Boolean {
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val direction = when (action) {
            "volUp" -> AudioManager.ADJUST_RAISE
            "volDown" -> AudioManager.ADJUST_LOWER
            else -> AudioManager.ADJUST_TOGGLE_MUTE
        }
        audio.adjustStreamVolume(AudioManager.STREAM_MUSIC, direction, AudioManager.FLAG_SHOW_UI)
        return true
    }

    /** Android TV qutisi / stik yoki televizor rejimidagi qurilma. */
    private fun isTvDevice(): Boolean {
        val ui = getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
        return ui.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
    }

    // AndroidManifest.xml dagi activity-alias (namespace + .HomeAlias).
    private fun homeAlias() = ComponentName(packageName, "uz.telefontv.telefon_tv.HomeAlias")

    /**
     * TV qutisi yoqilganda (va Home bosilganda) Telefon TV ochilsin.
     * Telefonlarda o‘chiq turadi, aks holda Home bosilganda tanlash so‘raladi.
     */
    private fun setHomeLauncher(on: Boolean): Boolean {
        packageManager.setComponentEnabledSetting(
            homeAlias(),
            if (on) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP,
        )
        if (on) {
            try {
                startActivity(Intent(Settings.ACTION_HOME_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            } catch (_: Exception) {
                // Ba’zi qutilarda bu sahifa yo‘q: Home bosilganda tizim o‘zi so‘raydi.
            }
        }
        return true
    }

    /** O‘rnatilgan ilovalar (TV qutisidagi YouTube, brauzer, kinoteatrlar…). */
    private fun listApps(result: MethodChannel.Result) {
        Thread {
            val pm = packageManager
            val seen = HashSet<String>()
            val apps = ArrayList<Map<String, Any>>()
            for (category in listOf(Intent.CATEGORY_LEANBACK_LAUNCHER, Intent.CATEGORY_LAUNCHER)) {
                val query = Intent(Intent.ACTION_MAIN).addCategory(category)
                for (info in pm.queryIntentActivities(query, 0)) {
                    val pkg = info.activityInfo.packageName
                    if (pkg == packageName || !seen.add(pkg)) continue
                    val icon = try {
                        png(info.loadIcon(pm))
                    } catch (_: Exception) {
                        ByteArray(0)
                    }
                    apps.add(mapOf("package" to pkg, "label" to info.loadLabel(pm).toString(), "icon" to icon))
                }
            }
            apps.sortBy { (it["label"] as String).lowercase() }
            runOnUiThread { result.success(apps) }
        }.start()
    }

    private fun png(d: Drawable): ByteArray {
        val size = 128
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        d.setBounds(0, 0, size, size)
        d.draw(Canvas(bitmap))
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        bitmap.recycle()
        return out.toByteArray()
    }

    private fun startExternal(target: Intent): Boolean {
        return try {
            val intent = target.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            // Boshqa ilova bizning TV oynamizga chiza olmaydi: oynani yopamiz,
            // Android telefon ekranini televizorga takrorlaydi. Qaytganda —
            // onResume TV oynasini qayta ochadi.
            if (presentation != null) {
                stepAside = true
                hideTv()
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            stepAside = false
            showOnTv()
            false
        }
    }

    private fun showOnTv() {
        if (presentation != null || stepAside || isFinishing) return
        val dm = displayManager ?: return
        val display = dm.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION).firstOrNull() ?: return
        val engine = tvEngine ?: FlutterEngine(applicationContext).also { e ->
            val bundle = FlutterInjector.instance().flutterLoader().findAppBundlePath()
            e.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(bundle, "tvMain"))
            bindChannel(e.dartExecutor.binaryMessenger)
            tvEngine = e
        }
        val p = TvPresentation(this, display, engine)
        p.setOnDismissListener {
            if (presentation === p) {
                presentation = null
                if (!stepAside) phoneChannel?.invokeMethod("externalDisplay", false)
            }
        }
        try {
            p.show()
        } catch (e: WindowManager.InvalidDisplayException) {
            return
        }
        presentation = p
        phoneChannel?.invokeMethod("externalDisplay", true)
    }

    private fun releaseTvEngine() {
        tvEngine?.destroy()
        tvEngine = null
    }

    private fun hideTv() {
        val p = presentation ?: return
        presentation = null
        p.setOnDismissListener(null)
        p.dismiss()
        if (!stepAside) phoneChannel?.invokeMethod("externalDisplay", false)
    }
}

/** Televizordagi oyna: unda `tvMain` chizadi. */
class TvPresentation(
    activity: Activity,
    display: Display,
    private val engine: FlutterEngine,
) : Presentation(activity, display) {
    private var flutterView: FlutterView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val view = FlutterView(context)
        setContentView(view)
        view.attachToFlutterEngine(engine)
        engine.lifecycleChannel.appIsResumed()
        flutterView = view
    }

    override fun onStop() {
        flutterView?.detachFromFlutterEngine()
        flutterView = null
        super.onStop()
    }
}
