package uz.telefontv.telefon_tv

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.graphics.Matrix
import android.media.ExifInterface
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.webkit.MimeTypeMap
import androidx.annotation.OptIn
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.effect.Presentation
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * “USB orqali televizorga”: telefonga ulangan fleshkaga fayllarni oddiy
 * televizor (Yasin, Artel, Samsung…) o‘qiy oladigan shaklda yozadi.
 *
 * * Video H.264 bo‘lmasa, MP4 bo‘lmasa yoki televizor uchun juda katta
 *   bo‘lsa (masalan Yasin LED-32E58TS uchun 720p dan katta) → H.264 + AAC MP4
 *   (Media3 Transformer).
 * * HEIC / HEIF / WEBP yoki juda katta rasm → JPEG.
 * * Qolganlari o‘zgarishsiz nusxalanadi.
 */
@OptIn(UnstableApi::class)
class UsbExporter(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "telefon_tv/usb")
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null
    private var tree: Uri? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "pickTarget" -> pick(result)
                "copy" -> {
                    val root = call.argument<String>("root") ?: "TELEFON_TV"
                    val files = call.argument<List<Map<String, Any?>>>("files") ?: emptyList()
                    val maxShort = call.argument<Int>("maxVideoShort") ?: 1080
                    val maxImage = call.argument<Int>("maxImageSide") ?: 3840
                    copy(root, files, maxShort, maxImage, result)
                }
                "apkPath" -> result.success(activity.applicationInfo.sourceDir)
                else -> result.notImplemented()
            }
        }
    }

    private fun pick(result: MethodChannel.Result) {
        pending?.success(null)
        pending = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
        )
        try {
            activity.startActivityForResult(intent, REQUEST)
        } catch (e: Exception) {
            pending = null
            result.error("no_picker", "Fayl tanlash oynasi topilmadi", null)
        }
    }

    /** MainActivity.onActivityResult shu yerga uzatadi. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST) return false
        val result = pending ?: return true
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }
        try {
            activity.contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        } catch (_: SecurityException) {
        }
        tree = uri
        val name = displayName(rootDoc(uri)) ?: "Fleshka"
        result.success(mapOf("id" to uri.toString(), "name" to name))
        return true
    }

    private fun rootDoc(t: Uri): Uri =
        DocumentsContract.buildDocumentUriUsingTree(t, DocumentsContract.getTreeDocumentId(t))

    private fun displayName(doc: Uri): String? = try {
        activity.contentResolver.query(
            doc, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null,
        )?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
    } catch (_: Exception) {
        null
    }

    private fun findChild(parent: Uri, name: String): Uri? {
        val t = tree ?: return null
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(t, DocumentsContract.getDocumentId(parent))
        activity.contentResolver.query(
            children,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            ),
            null, null, null,
        )?.use { c ->
            while (c.moveToNext()) {
                if (c.getString(1).equals(name, ignoreCase = true)) {
                    return DocumentsContract.buildDocumentUriUsingTree(t, c.getString(0))
                }
            }
        }
        return null
    }

    private fun dir(parent: Uri, name: String): Uri {
        if (name.isEmpty()) return parent
        return findChild(parent, name)
            ?: DocumentsContract.createDocument(
                activity.contentResolver, parent, DocumentsContract.Document.MIME_TYPE_DIR, name,
            )
            ?: throw IOException("Papka yaratilmadi: $name")
    }

    private fun progress(done: Int, total: Int, name: String, converting: Boolean) = main.post {
        channel.invokeMethod(
            "progress",
            mapOf("done" to done, "total" to total, "name" to name, "converting" to converting),
        )
    }

    private fun copy(
        root: String,
        files: List<Map<String, Any?>>,
        maxShort: Int,
        maxImage: Int,
        result: MethodChannel.Result,
    ) {
        val t = tree
        if (t == null) {
            result.error("no_target", "Avval fleshkani tanlang", null)
            return
        }
        io.execute {
            var copied = 0
            var converted = 0
            val failed = ArrayList<String>()
            try {
                val base = dir(rootDoc(t), root)
                files.forEachIndexed { i, f ->
                    val path = f["path"] as? String ?: return@forEachIndexed
                    var name = f["name"] as? String ?: File(path).name
                    val folder = f["folder"] as? String ?: ""
                    try {
                        val ext = name.substringAfterLast('.', "").lowercase()
                        val videoHeight = if (ext in IMAGE_EXT || ext in AUDIO_EXT) null else videoPlan(path, ext, maxShort)
                        val temp: File?
                        when {
                            ext in IMAGE_EXT && imageNeedsJpeg(path, ext, maxImage) -> {
                                progress(i, files.size, name, true)
                                temp = toJpeg(path, ext, maxImage)
                                name = name.substringBeforeLast('.') + ".jpg"
                            }
                            videoHeight != null -> {
                                progress(i, files.size, name, true)
                                temp = toH264(path, videoHeight)
                                name = name.substringBeforeLast('.') + ".mp4"
                            }
                            else -> {
                                progress(i, files.size, name, false)
                                temp = null
                            }
                        }
                        write(dir(base, folder), name, temp ?: File(path))
                        if (temp != null) {
                            converted++
                            temp.delete()
                        }
                        copied++
                    } catch (e: Exception) {
                        failed.add(name)
                    }
                }
                progress(files.size, files.size, "", false)
                main.post {
                    result.success(mapOf("copied" to copied, "converted" to converted, "failed" to failed))
                }
            } catch (e: Exception) {
                main.post { result.error("copy_failed", e.message ?: "Fleshkaga yozib bo‘lmadi", null) }
            }
        }
    }

    private fun write(folder: Uri, name: String, src: File) {
        // Konvertatsiya kengaytmani o‘zgartirishi mumkin. Fleshka ichidagi
        // avvalgi fayllarni ham saqlaymiz, nomni yakuniy formatdan keyin tanlaymiz.
        val dot = name.lastIndexOf('.')
        val stem = if (dot > 0) name.substring(0, dot) else name
        val suffix = if (dot > 0) name.substring(dot) else ""
        var available = name
        var n = 2
        while (findChild(folder, available) != null) {
            available = "${stem}_${n++}$suffix"
        }
        val ext = name.substringAfterLast('.', "").lowercase()
        val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "application/octet-stream"
        val doc = DocumentsContract.createDocument(activity.contentResolver, folder, mime, available)
            ?: throw IOException("Fayl yaratilmadi: $available")
        activity.contentResolver.openOutputStream(doc, "w").use { out ->
            if (out == null) throw IOException("Fleshkaga yozib bo‘lmadi")
            FileInputStream(src).use { it.copyTo(out, 1 shl 20) }
        }
    }

    /**
     * Video o‘tkazish kerakmi. null — kerak emas (H.264, MP4, o‘lchami mos);
     * 0 — formatini o‘zgartirish; >0 — shu balandlikka kichraytirish ham.
     * Oddiy televizorlarning USB pleyeri (MStar va boshqalar) odatda faqat
     * H.264 ni ishonchli o‘qiydi.
     */
    private fun videoPlan(path: String, ext: String, maxShort: Int): Int? {
        val ex = MediaExtractor()
        return try {
            ex.setDataSource(path)
            val format = (0 until ex.trackCount)
                .map { ex.getTrackFormat(it) }
                .firstOrNull { it.getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true }
                ?: return null
            val mime = format.getString(MediaFormat.KEY_MIME)
            val w = if (format.containsKey(MediaFormat.KEY_WIDTH)) format.getInteger(MediaFormat.KEY_WIDTH) else 0
            val h = if (format.containsKey(MediaFormat.KEY_HEIGHT)) format.getInteger(MediaFormat.KEY_HEIGHT) else 0
            val tooBig = minOf(w, h) > maxShort
            when {
                tooBig -> maxShort
                mime != MimeTypes.VIDEO_H264 || (ext != "mp4" && ext != "m4v") -> 0
                else -> null
            }
        } catch (_: Exception) {
            null // o‘qib bo‘lmadi — o‘zgarishsiz nusxalaymiz
        } finally {
            ex.release()
        }
    }

    private fun toH264(path: String, height: Int): File {
        val out = File(activity.cacheDir, "usb_${System.nanoTime()}.mp4")
        val latch = CountDownLatch(1)
        var error: Exception? = null
        main.post {
            try {
                Transformer.Builder(activity)
                    .setVideoMimeType(MimeTypes.VIDEO_H264)
                    .setAudioMimeType(MimeTypes.AUDIO_AAC)
                    .addListener(object : Transformer.Listener {
                        override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                            latch.countDown()
                        }

                        override fun onError(
                            composition: Composition,
                            exportResult: ExportResult,
                            exportException: ExportException,
                        ) {
                            error = exportException
                            latch.countDown()
                        }
                    })
                    .build()
                    .start(editedItem(path, height), out.absolutePath)
            } catch (e: Exception) {
                error = e
                latch.countDown()
            }
        }
        if (!latch.await(60, TimeUnit.MINUTES)) throw IOException("Video juda uzoq o‘tkazilmoqda")
        error?.let { throw it }
        if (!out.exists() || out.length() == 0L) throw IOException("Video o‘tkazilmadi")
        return out
    }

    private fun editedItem(path: String, height: Int): EditedMediaItem {
        val builder = EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(File(path))))
        if (height > 0) {
            builder.setEffects(Effects(emptyList<AudioProcessor>(), listOf<Effect>(Presentation.createForHeight(height))))
        }
        return builder.build()
    }

    private fun imageBounds(path: String): Pair<Int, Int>? {
        val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, o)
        return if (o.outWidth > 0 && o.outHeight > 0) o.outWidth to o.outHeight else null
    }

    /** HEIC / WEBP ni oddiy televizor ochmaydi; juda katta JPEG ni ham ko‘pincha. */
    private fun imageNeedsJpeg(path: String, ext: String, maxSide: Int): Boolean {
        if (ext == "heic" || ext == "heif" || ext == "webp") return true
        val size = imageBounds(path) ?: return false
        return maxOf(size.first, size.second) > maxSide
    }

    private fun toJpeg(path: String, ext: String, maxSide: Int): File {
        val bitmap = if (Build.VERSION.SDK_INT >= 28) {
            ImageDecoder.decodeBitmap(ImageDecoder.createSource(File(path))) { decoder, info, _ ->
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                val longest = maxOf(info.size.width, info.size.height)
                if (longest > maxSide) {
                    val k = maxSide.toDouble() / longest
                    decoder.setTargetSize((info.size.width * k).toInt(), (info.size.height * k).toInt())
                }
            }
        } else {
            if (ext == "heic" || ext == "heif") throw IOException("HEIC rasm uchun Android 9+ kerak")
            decodeOld(path, maxSide)
        }
        val out = File(activity.cacheDir, "usb_${System.nanoTime()}.jpg")
        out.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 92, it) }
        bitmap.recycle()
        return out
    }

    /** Android 8 va eskisi: kichraytirib o‘qish va EXIF bo‘yicha burish. */
    private fun decodeOld(path: String, maxSide: Int): Bitmap {
        val (w, h) = imageBounds(path) ?: throw IOException("Rasmni o‘qib bo‘lmadi")
        var sample = 1
        while (maxOf(w, h) / (sample * 2) >= maxSide) sample *= 2
        var bitmap = BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample })
            ?: throw IOException("Rasmni o‘qib bo‘lmadi")
        val longest = maxOf(bitmap.width, bitmap.height)
        if (longest > maxSide) {
            val k = maxSide.toFloat() / longest
            val scaled = Bitmap.createScaledBitmap(bitmap, (bitmap.width * k).toInt(), (bitmap.height * k).toInt(), true)
            if (scaled !== bitmap) bitmap.recycle()
            bitmap = scaled
        }
        val degrees = when (
            ExifInterface(path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
        ) {
            ExifInterface.ORIENTATION_ROTATE_90 -> 90f
            ExifInterface.ORIENTATION_ROTATE_180 -> 180f
            ExifInterface.ORIENTATION_ROTATE_270 -> 270f
            else -> 0f
        }
        if (degrees == 0f) return bitmap
        val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, Matrix().apply { postRotate(degrees) }, true)
        if (rotated !== bitmap) bitmap.recycle()
        return rotated
    }

    companion object {
        private const val REQUEST = 4721
        private val IMAGE_EXT = setOf("jpg", "jpeg", "png", "heic", "heif", "webp", "bmp")
        private val AUDIO_EXT = setOf("mp3", "m4a", "aac", "wav", "flac", "ogg", "opus", "amr")
    }
}
