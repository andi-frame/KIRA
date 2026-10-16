package id.kira.kira.jeda

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Setelah ponsel menyala ulang atau KIRA diperbarui, penjagaan menyala lagi bila pengguna mengaktifkannya dan izin masih ada. */
class JedaBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            JedaService.sync(context)
        }
    }
}
