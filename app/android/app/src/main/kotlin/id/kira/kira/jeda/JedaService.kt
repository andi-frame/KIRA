package id.kira.kira.jeda

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * Memantau aplikasi yang sedang di depan. Hanya nama paketnya yang dibaca (UsageStatsManager), tidak ada isi layar.
 * Begitu aplikasi pilihan pengguna terbuka, kartu yang berlaku sekarang ditampilkan di depannya.
 *
 * Tiap langkah penting dicatat ke [Diag] (aplikasi terakhir terdeteksi, alasan tidak ada kartu, galat) supaya layar status
 * di aplikasi bisa menjelaskan "mengapa kartu tidak muncul" tanpa harus membuka log perangkat.
 */
class JedaService : Service() {
    private lateinit var store: JedaStore
    private lateinit var thread: HandlerThread
    private lateinit var handler: Handler
    private var current: String? = null
    private var cachedRaw: String? = null
    private var cachedPayload: Payload? = null
    private var diag = Diag()
    private var diagWrittenAt = 0L

    private val tick = object : Runnable {
        override fun run() {
            val interactive = (getSystemService(Context.POWER_SERVICE) as PowerManager).isInteractive
            if (interactive) {
                try {
                    check()
                } catch (e: Exception) {
                    // Satu putaran gagal tidak boleh menghentikan penjagaan, tetapi alasannya dicatat.
                    diag = diag.copy(lastError = "${e.javaClass.simpleName}: ${e.message ?: ""}".take(200))
                    flush(force = true)
                }
            } else {
                current = null // layar mati: saat menyala lagi, aplikasi di depan dihitung baru dibuka
            }
            diag = diag.copy(lastTickAt = System.currentTimeMillis())
            flush()
            handler.postDelayed(this, if (interactive) POLL_MS else POLL_SLEEP_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        store = JedaStore(this)
        thread = HandlerThread("kira-jeda").also { it.start() }
        handler = Handler(thread.looper)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!store.settings().enabled || !JedaPermissions.ready(this)) {
            stopSelf()
            return START_NOT_STICKY
        }
        ServiceCompat.startForeground(
            this, NOTIFICATION_ID, notification(),
            if (Build.VERSION.SDK_INT >= 34) ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE else 0,
        )
        diag = store.diag().copy(startedAt = System.currentTimeMillis(), lastError = "")
        flush(force = true)
        handler.removeCallbacks(tick)
        handler.post(tick)
        return START_STICKY
    }

    override fun onDestroy() {
        JedaOverlay.dismissCurrent()
        handler.removeCallbacksAndMessages(null)
        thread.quitSafely()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    /** Menulis catatan kegiatan paling sering tiap beberapa detik (SharedPreferences tidak untuk ditulis tiap 0,7 detik). */
    private fun flush(force: Boolean = false) {
        val now = System.currentTimeMillis()
        if (!force && now - diagWrittenAt < DIAG_EVERY_MS) return
        diagWrittenAt = now
        store.saveDiag(diag)
    }

    private fun check() {
        val settings = store.settings()
        if (!settings.enabled) {
            stopSelf()
            return
        }
        val front = foregroundPackage() ?: return // tidak ada kejadian baru: aplikasi di depan tetap yang tadi
        val changed = front != current
        current = front
        if (!changed) return
        diag = diag.copy(lastFront = front, lastFrontAt = System.currentTimeMillis())
        flush(force = true)
        JedaOverlay.current?.let { shown ->
            // Kartu sedang tampil: berpindah ke aplikasi lain (Home, dll.) menutupnya, tanpa menghitung sebagai dibaca.
            if (shown.target != front) JedaOverlay.dismissCurrent()
            return
        }
        if (front !in settings.apps) return

        val now = System.currentTimeMillis()
        val raw = store.rawPayload()
        if (raw != cachedRaw) {
            cachedRaw = raw
            cachedPayload = JedaCodec.payload(raw)
        }
        val payload = cachedPayload
        val date = JedaStore.dateKey(now)
        val day = JedaStore.dayKey(now)
        val state = store.state()
        val minute = JedaStore.minuteOfDay(now)
        val same = payload != null && JedaStore.dateKey(payload.generatedAt) == date
        val cards = JedaDecider.due(now, minute, date, day, settings, payload, state, same)
        diag = diag.copy(lastGuarded = front, lastGuardedAt = now)
        if (cards.isEmpty()) {
            diag = diag.copy(lastReason = JedaDecider.explain(now, minute, date, day, settings, payload, state, same).code)
            flush(force = true)
            return
        }
        if (!JedaPermissions.overlay(this)) {
            diag = diag.copy(lastReason = "no_overlay_permission")
            flush(force = true)
            return
        }
        // Jatah tampil baru dihitung setelah jendela benar-benar berhasil dipasang: kegagalan memasang tidak boleh
        // menghabiskan jatah tiga kali sehari tanpa pengguna pernah melihat kartunya.
        JedaOverlay.show(this, cards, target = front, targetLabel = targetLabel(front), preview = false) { error ->
            if (error == null) {
                store.saveState(JedaDecider.afterShown(store.state(), day, cards))
                diag = diag.copy(lastReason = "shown", shownTotal = diag.shownTotal + 1, lastError = "")
            } else {
                diag = diag.copy(lastReason = "overlay_failed", lastError = error.take(200))
            }
            flush(force = true)
        }
    }

    private fun targetLabel(pkg: String): String? = try {
        packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0)).toString()
    } catch (_: Exception) {
        null
    }

    /** Aplikasi yang terakhir pindah ke depan dalam 10 detik terakhir; null bila tidak ada perpindahan. */
    private fun foregroundPackage(): String? {
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val end = System.currentTimeMillis()
        val events = usm.queryEvents(end - WINDOW_MS, end)
        val e = UsageEvents.Event()
        var last: String? = null
        while (events.hasNextEvent()) {
            events.getNextEvent(e)
            if (e.eventType == UsageEvents.Event.ACTIVITY_RESUMED) last = e.packageName
        }
        return last
    }

    private fun notification(): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26 && manager.getNotificationChannel(CHANNEL) == null) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "Jeda sosmed", NotificationManager.IMPORTANCE_MIN).apply {
                    description = "Tanda bahwa Jeda sosmed aktif. Tanpa data kesehatan."
                    setShowBadge(false)
                },
            )
        }
        val open = PendingIntent.getActivity(
            this, 0, packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("Jeda sosmed aktif")
            .setContentText("Matikan kapan saja di KIRA > Profil > Jeda sosmed")
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setContentIntent(open)
            .build()
    }

    companion object {
        private const val CHANNEL = "kira_jeda"
        private const val NOTIFICATION_ID = 7101
        private const val POLL_MS = 700L
        private const val POLL_SLEEP_MS = 3000L
        private const val WINDOW_MS = 10_000L
        private const val DIAG_EVERY_MS = 4_000L

        /** Menyalakan layanan bila diaktifkan dan izin lengkap; mematikannya bila tidak. */
        fun sync(context: Context) {
            val intent = Intent(context, JedaService::class.java)
            if (JedaStore(context).settings().enabled && JedaPermissions.ready(context)) {
                ContextCompat.startForegroundService(context, intent)
            } else {
                context.stopService(intent)
            }
        }
    }
}
