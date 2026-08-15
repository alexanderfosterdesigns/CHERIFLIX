package com.example.cheriflix

import android.content.ComponentCallbacks2
import android.graphics.Bitmap
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import kotlin.math.PI
import kotlin.math.min
import kotlin.math.sin

private const val THUMBNAIL_CHANNEL = "cheriflix/native_thumbnail_extractor"
private const val FOCUS_SOUND_CHANNEL = "cheriflix/focus_navigation_sound"
private const val THUMBNAIL_THREAD_COUNT = 2
private const val THUMBNAIL_QUEUE_CAPACITY = 6
private const val CHERIFLIX_LOG_TAG = "CHERIFLIX"

class MainActivity : FlutterActivity() {
    private val thumbnailExecutor = ThreadPoolExecutor(
        THUMBNAIL_THREAD_COUNT,
        THUMBNAIL_THREAD_COUNT,
        20L,
        TimeUnit.SECONDS,
        ArrayBlockingQueue(THUMBNAIL_QUEUE_CAPACITY),
    )
    private val focusSoundPlayer = FocusNavigationSoundPlayer()

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (isPlaybackOrAssistantKey(event.keyCode)) {
            Log.d(
                CHERIFLIX_LOG_TAG,
                "tv_key action=${event.action} keyCode=${event.keyCode} repeat=${event.repeatCount}"
            )
        }
        return super.dispatchKeyEvent(event)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, THUMBNAIL_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "extractFrame" -> handleExtractFrame(call, result)
                    "extractFrames" -> handleExtractFrames(call, result)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FOCUS_SOUND_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "playFocusMove" -> {
                        focusSoundPlayer.play()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun handleExtractFrame(call: MethodCall, result: MethodChannel.Result) {
        val sourceUri = call.argument<String>("sourceUri") ?: call.argument<String>("videoPath")
        val timeMs = call.argument<Int>("timeMs") ?: 0
        val width = call.argument<Int>("width") ?: 320
        val height = call.argument<Int>("height") ?: 180
        val exact = call.argument<Boolean>("exact") ?: false
        val jpegQuality = call.argument<Int>("jpegQuality") ?: if (exact) 90 else 80
        val httpHeaders = parseHttpHeaders(call.argument<Map<*, *>>("httpHeaders"))

        if (sourceUri.isNullOrBlank()) {
            result.error("invalid_args", "sourceUri is required", null)
            return
        }
        if (!canOpenSourceUri(sourceUri)) {
            result.success(null)
            return
        }

        executeThumbnailTask(result, null) {
            try {
                val extraction = extractFrameBytes(
                    sourceUri = sourceUri,
                    timeMs = timeMs.coerceAtLeast(0),
                    width = width.coerceAtLeast(1),
                    height = height.coerceAtLeast(1),
                    exact = exact,
                    jpegQuality = jpegQuality.coerceIn(40, 100),
                    httpHeaders = httpHeaders,
                )
                runOnUiThread {
                    if (extraction == null) {
                        result.success(null)
                    } else {
                        result.success(
                            hashMapOf(
                                "bytes" to extraction.bytes,
                                "requestedTimeMs" to extraction.requestedTimeMs,
                                "actualTimeMs" to extraction.actualTimeMs,
                            )
                        )
                    }
                }
            } catch (error: Throwable) {
                runOnUiThread {
                    result.error("extract_failed", error.message, null)
                }
            }
        }
    }

    private fun handleExtractFrames(call: MethodCall, result: MethodChannel.Result) {
        val sourceUri = call.argument<String>("sourceUri") ?: call.argument<String>("videoPath")
        val rawTimes = call.argument<List<Any?>>("timeMsList").orEmpty()
        val width = call.argument<Int>("width") ?: 320
        val height = call.argument<Int>("height") ?: 180
        val exact = call.argument<Boolean>("exact") ?: false
        val jpegQuality = call.argument<Int>("jpegQuality") ?: if (exact) 90 else 80
        val httpHeaders = parseHttpHeaders(call.argument<Map<*, *>>("httpHeaders"))
        val timeMsList = rawTimes.mapNotNull(::readInt).map { it.coerceAtLeast(0) }.distinct().sorted()

        if (sourceUri.isNullOrBlank()) {
            result.error("invalid_args", "sourceUri is required", null)
            return
        }
        if (timeMsList.isEmpty()) {
            result.success(emptyList<Map<String, Any>>())
            return
        }
        if (!canOpenSourceUri(sourceUri)) {
            result.success(emptyList<Map<String, Any>>())
            return
        }

        executeThumbnailTask(result, emptyList<Map<String, Any>>()) {
            try {
                val extractions = extractFrameBatch(
                    sourceUri = sourceUri,
                    timeMsList = timeMsList,
                    width = width.coerceAtLeast(1),
                    height = height.coerceAtLeast(1),
                    exact = exact,
                    jpegQuality = jpegQuality.coerceIn(40, 100),
                    httpHeaders = httpHeaders,
                )
                runOnUiThread {
                    result.success(
                        extractions.map { extraction ->
                            hashMapOf(
                                "bytes" to extraction.bytes,
                                "requestedTimeMs" to extraction.requestedTimeMs,
                                "actualTimeMs" to extraction.actualTimeMs,
                            )
                        }
                    )
                }
            } catch (error: Throwable) {
                runOnUiThread {
                    result.error("extract_failed", error.message, null)
                }
            }
        }
    }

    private fun executeThumbnailTask(
        result: MethodChannel.Result,
        fallbackValue: Any?,
        task: () -> Unit,
    ) {
        try {
            thumbnailExecutor.execute { task() }
        } catch (_: RejectedExecutionException) {
            result.success(fallbackValue)
        }
    }

    private fun extractFrameBytes(
        sourceUri: String,
        timeMs: Int,
        width: Int,
        height: Int,
        exact: Boolean,
        jpegQuality: Int,
        httpHeaders: Map<String, String>,
    ): FrameExtractionResult? {
        val retriever = MediaMetadataRetriever()
        try {
            setRetrieverDataSource(
                retriever = retriever,
                sourceUri = sourceUri,
                httpHeaders = httpHeaders,
            )

            val timeUs = timeMs.toLong() * 1000L
            val options = if (exact) {
                intArrayOf(
                    MediaMetadataRetriever.OPTION_CLOSEST,
                    MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                    MediaMetadataRetriever.OPTION_PREVIOUS_SYNC,
                    MediaMetadataRetriever.OPTION_NEXT_SYNC,
                )
            } else {
                intArrayOf(
                    MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                    MediaMetadataRetriever.OPTION_PREVIOUS_SYNC,
                    MediaMetadataRetriever.OPTION_NEXT_SYNC,
                )
            }

            var bitmap: Bitmap? = null
            for (option in options) {
                bitmap = extractScaledBitmap(
                    retriever = retriever,
                    timeUs = timeUs,
                    option = option,
                    width = width,
                    height = height,
                )
                if (bitmap != null) {
                    break
                }
            }
            if (bitmap == null) {
                return null
            }

            val output = ByteArrayOutputStream()
            val compressed = try {
                bitmap.compress(Bitmap.CompressFormat.JPEG, jpegQuality, output)
            } finally {
                bitmap.recycle()
            }
            if (!compressed) {
                return null
            }

            return FrameExtractionResult(
                bytes = output.toByteArray(),
                requestedTimeMs = timeMs,
                // Android framework does not expose decoded-frame timestamp from
                // MediaMetadataRetriever, so we report requested timestamp.
                actualTimeMs = timeMs,
            )
        } finally {
            try {
                retriever.release()
            } catch (_: Throwable) {
            }
        }
    }

    private fun extractFrameBatch(
        sourceUri: String,
        timeMsList: List<Int>,
        width: Int,
        height: Int,
        exact: Boolean,
        jpegQuality: Int,
        httpHeaders: Map<String, String>,
    ): List<FrameExtractionResult> {
        val retriever = MediaMetadataRetriever()
        try {
            setRetrieverDataSource(
                retriever = retriever,
                sourceUri = sourceUri,
                httpHeaders = httpHeaders,
            )
            val results = ArrayList<FrameExtractionResult>(timeMsList.size)
            for (timeMs in timeMsList) {
                val extraction = extractFrameBytes(
                    retriever = retriever,
                    timeMs = timeMs,
                    width = width,
                    height = height,
                    exact = exact,
                    jpegQuality = jpegQuality,
                )
                if (extraction != null) {
                    results.add(extraction)
                }
            }
            return results
        } finally {
            try {
                retriever.release()
            } catch (_: Throwable) {
            }
        }
    }

    private fun extractFrameBytes(
        retriever: MediaMetadataRetriever,
        timeMs: Int,
        width: Int,
        height: Int,
        exact: Boolean,
        jpegQuality: Int,
    ): FrameExtractionResult? {
        val timeUs = timeMs.toLong() * 1000L
        val options = if (exact) {
            intArrayOf(
                MediaMetadataRetriever.OPTION_CLOSEST,
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                MediaMetadataRetriever.OPTION_PREVIOUS_SYNC,
                MediaMetadataRetriever.OPTION_NEXT_SYNC,
            )
        } else {
            intArrayOf(
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                MediaMetadataRetriever.OPTION_PREVIOUS_SYNC,
                MediaMetadataRetriever.OPTION_NEXT_SYNC,
            )
        }

        var bitmap: Bitmap? = null
        for (option in options) {
            bitmap = extractScaledBitmap(
                retriever = retriever,
                timeUs = timeUs,
                option = option,
                width = width,
                height = height,
            )
            if (bitmap != null) {
                break
            }
        }
        if (bitmap == null) {
            return null
        }

        val output = ByteArrayOutputStream()
        val compressed = try {
            bitmap.compress(Bitmap.CompressFormat.JPEG, jpegQuality, output)
        } finally {
            bitmap.recycle()
        }
        if (!compressed) {
            return null
        }

        return FrameExtractionResult(
            bytes = output.toByteArray(),
            requestedTimeMs = timeMs,
            actualTimeMs = timeMs,
        )
    }

    private fun setRetrieverDataSource(
        retriever: MediaMetadataRetriever,
        sourceUri: String,
        httpHeaders: Map<String, String>,
    ) {
        when {
            sourceUri.startsWith("content://") || sourceUri.startsWith("file://") -> {
                retriever.setDataSource(this, Uri.parse(sourceUri))
            }
            sourceUri.startsWith("http://") || sourceUri.startsWith("https://") -> {
                retriever.setDataSource(sourceUri, httpHeaders)
            }
            else -> {
                retriever.setDataSource(sourceUri)
            }
        }
    }

    private fun canOpenSourceUri(sourceUri: String): Boolean {
        if (sourceUri.startsWith("content://")) {
            return true
        }
        if (sourceUri.startsWith("http://") || sourceUri.startsWith("https://")) {
            return true
        }
        if (sourceUri.startsWith("file://")) {
            val path = Uri.parse(sourceUri).path
            return !path.isNullOrBlank() && File(path).exists()
        }
        return File(sourceUri).exists()
    }

    private fun parseHttpHeaders(rawHeaders: Map<*, *>?): Map<String, String> {
        if (rawHeaders.isNullOrEmpty()) {
            return emptyMap()
        }
        val headers = LinkedHashMap<String, String>(rawHeaders.size)
        for ((key, value) in rawHeaders) {
            val headerName = key?.toString()?.trim().orEmpty()
            val headerValue = value?.toString()?.trim().orEmpty()
            if (headerName.isEmpty() || headerValue.isEmpty()) {
                continue
            }
            headers[headerName] = headerValue
        }
        return headers
    }

    private fun readInt(value: Any?): Int? {
        return when (value) {
            is Int -> value
            is Long -> value.toInt()
            is Double -> value.toInt()
            is Float -> value.toInt()
            is Number -> value.toInt()
            is String -> value.toIntOrNull()
            else -> null
        }
    }

    private fun extractScaledBitmap(
        retriever: MediaMetadataRetriever,
        timeUs: Long,
        option: Int,
        width: Int,
        height: Int,
    ): Bitmap? {
        val source: Bitmap? =
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O_MR1) {
                retriever.getScaledFrameAtTime(timeUs, option, width, height)
            } else {
                retriever.getFrameAtTime(timeUs, option)
            }
        source ?: return null

        if (source.width == width && source.height == height) {
            return source
        }

        val scaled = Bitmap.createScaledBitmap(source, width, height, true)
        source.recycle()
        return scaled
    }

    override fun onDestroy() {
        thumbnailExecutor.queue.clear()
        thumbnailExecutor.shutdownNow()
        focusSoundPlayer.release()
        super.onDestroy()
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        if (level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW) {
            thumbnailExecutor.queue.clear()
        }
    }

    override fun onLowMemory() {
        super.onLowMemory()
        thumbnailExecutor.queue.clear()
    }

    private fun isPlaybackOrAssistantKey(keyCode: Int): Boolean {
        return keyCode == KeyEvent.KEYCODE_ASSIST ||
            keyCode == KeyEvent.KEYCODE_VOICE_ASSIST ||
            keyCode == KeyEvent.KEYCODE_MEDIA_PLAY ||
            keyCode == KeyEvent.KEYCODE_MEDIA_PAUSE ||
            keyCode == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE ||
            keyCode == KeyEvent.KEYCODE_MEDIA_FAST_FORWARD ||
            keyCode == KeyEvent.KEYCODE_MEDIA_REWIND ||
            keyCode == KeyEvent.KEYCODE_BUTTON_SELECT ||
            keyCode == KeyEvent.KEYCODE_DPAD_CENTER ||
            keyCode == KeyEvent.KEYCODE_ENTER
    }
}

private class FocusNavigationSoundPlayer {
    private val handler = Handler(Looper.getMainLooper())
    private val pcmData = buildFocusPcm()
    private var track: AudioTrack? = null
    private var lastPlayUptimeMs = 0L
    private val releaseRunnable = Runnable {
        releaseTrack()
    }

    fun play() {
        val now = SystemClock.uptimeMillis()
        if (now - lastPlayUptimeMs < FOCUS_MIN_INTERVAL_MS) {
            return
        }
        lastPlayUptimeMs = now

        val reusableTrack = ensureTrack() ?: return

        try {
            handler.removeCallbacks(releaseRunnable)
            if (reusableTrack.playState == AudioTrack.PLAYSTATE_PLAYING) {
                reusableTrack.stop()
            }
            reusableTrack.reloadStaticData()
            reusableTrack.setPlaybackHeadPosition(0)
            reusableTrack.setVolume(FOCUS_PLAYBACK_VOLUME)
            reusableTrack.play()
            handler.postDelayed(releaseRunnable, FOCUS_IDLE_RELEASE_DELAY_MS)
        } catch (_: Throwable) {
            releaseTrack()
        }
    }

    fun release() {
        handler.removeCallbacks(releaseRunnable)
        releaseTrack()
    }

    private fun ensureTrack(): AudioTrack? {
        val existing = track
        if (existing != null) {
            return existing
        }
        return try {
            AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setSampleRate(FOCUS_SAMPLE_RATE)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build()
                )
                .setTransferMode(AudioTrack.MODE_STATIC)
                .setBufferSizeInBytes(pcmData.size)
                .build()
                .also {
                    it.write(pcmData, 0, pcmData.size)
                    track = it
                }
        } catch (_: Throwable) {
            null
        }
    }

    private fun releaseTrack() {
        val existing = track ?: return
        track = null
        try {
            if (existing.playState == AudioTrack.PLAYSTATE_PLAYING) {
                existing.stop()
            }
        } catch (_: Throwable) {
        }
        try {
            existing.release()
        } catch (_: Throwable) {
        }
    }

    private fun buildFocusPcm(): ByteArray {
        val frameCount = FOCUS_SAMPLE_RATE * FOCUS_DURATION_MS / 1000
        val output = ByteArray(frameCount * 2)
        for (index in 0 until frameCount) {
            val t = index.toDouble() / FOCUS_SAMPLE_RATE.toDouble()
            val attack = min(1.0, index / FOCUS_ATTACK_FRAMES.toDouble())
            val release = min(
                1.0,
                (frameCount - index) / FOCUS_RELEASE_FRAMES.toDouble()
            )
            val envelope = attack * release
            val sample = (
                sin(2.0 * PI * FOCUS_FREQUENCY_HZ * t) *
                    FOCUS_TONE_GAIN.toDouble() *
                    envelope *
                    Short.MAX_VALUE
                ).toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
            output[index * 2] = (sample and 0xFF).toByte()
            output[index * 2 + 1] = ((sample shr 8) and 0xFF).toByte()
        }
        return output
    }

    private companion object {
        const val FOCUS_SAMPLE_RATE = 48000
        const val FOCUS_DURATION_MS = 38
        const val FOCUS_MIN_INTERVAL_MS = 70L
        const val FOCUS_IDLE_RELEASE_DELAY_MS = 2_000L
        const val FOCUS_ATTACK_FRAMES = 160
        const val FOCUS_RELEASE_FRAMES = 420
        const val FOCUS_FREQUENCY_HZ = 720.0
        const val FOCUS_TONE_GAIN = 0.55f
        const val FOCUS_PLAYBACK_VOLUME = 0.95f
    }
}

data class FrameExtractionResult(
    val bytes: ByteArray,
    val requestedTimeMs: Int,
    val actualTimeMs: Int,
)
