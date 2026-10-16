package id.kira.kira.jeda

import android.content.Context
import android.content.SharedPreferences
import java.util.Calendar

/**
 * Penyimpanan di ponsel (SharedPreferences pribadi aplikasi): pengaturan, isi kartu dari Flutter, dan keadaan tampil.
 * Tidak ada yang dikirim ke jaringan.
 */
class JedaStore(context: Context) {
    private val prefs: SharedPreferences = context.applicationContext.getSharedPreferences("kira_jeda", Context.MODE_PRIVATE)

    fun settings(): Settings = JedaCodec.settings(prefs.getString(KEY_SETTINGS, null))
    fun rawPayload(): String? = prefs.getString(KEY_PAYLOAD, null)
    fun payload(): Payload? = JedaCodec.payload(rawPayload())
    fun state(): GateState = JedaCodec.state(prefs.getString(KEY_STATE, null))

    /** Payload null = pertahankan isi kartu yang sudah ada (mis. tanpa sinyal). */
    fun saveConfig(settingsJson: String, payloadJson: String?) {
        prefs.edit().apply {
            putString(KEY_SETTINGS, settingsJson)
            if (payloadJson != null) putString(KEY_PAYLOAD, payloadJson)
        }.apply()
    }

    fun saveState(s: GateState) = prefs.edit().putString(KEY_STATE, JedaCodec.stateJson(s)).apply()

    fun clear() = prefs.edit().clear().apply()

    /** Rute yang diminta tombol kartu; diambil sekali oleh Flutter. */
    fun setLaunchRoute(route: String?) = prefs.edit().putString(KEY_ROUTE, route).apply()

    fun takeLaunchRoute(): String? {
        val r = prefs.getString(KEY_ROUTE, null)
        if (r != null) setLaunchRoute(null)
        return r
    }

    companion object {
        private const val KEY_SETTINGS = "settings"
        private const val KEY_PAYLOAD = "payload"
        private const val KEY_STATE = "state"
        private const val KEY_ROUTE = "route"

        fun dateKey(cal: Calendar): String =
            "%04d-%02d-%02d".format(cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1, cal.get(Calendar.DAY_OF_MONTH))

        /** Hari logis berganti pukul 04.00 (lihat [JedaDecider]). */
        fun dayKey(nowMs: Long): String {
            val cal = Calendar.getInstance().apply { timeInMillis = nowMs - JedaDecider.NIGHT_END * 60_000L }
            return dateKey(cal)
        }

        fun dateKey(nowMs: Long): String = dateKey(Calendar.getInstance().apply { timeInMillis = nowMs })

        fun minuteOfDay(nowMs: Long): Int {
            val cal = Calendar.getInstance().apply { timeInMillis = nowMs }
            return cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE)
        }
    }
}
