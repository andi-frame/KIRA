package id.kira.kira.jeda

import android.Manifest
import android.app.AppOpsManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager
import android.os.Process
import android.provider.Settings as AndroidSettings

object JedaPermissions {
    fun usageAccess(context: Context): Boolean {
        val ops = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= 29) {
            ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
        } else {
            @Suppress("DEPRECATION")
            ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
        }
        // MODE_DEFAULT: sebagian perangkat tidak mengisi mode, izinnya harus dibaca dari status izin biasa.
        if (mode == AppOpsManager.MODE_DEFAULT) {
            return context.checkCallingOrSelfPermission(Manifest.permission.PACKAGE_USAGE_STATS) == PackageManager.PERMISSION_GRANTED
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /** Penghemat baterai yang agresif mematikan layanan latar. true = KIRA dikecualikan (baik untuk Jeda sosmed). */
    fun ignoringBatteryOptimizations(context: Context): Boolean =
        (context.getSystemService(Context.POWER_SERVICE) as PowerManager).isIgnoringBatteryOptimizations(context.packageName)

    fun overlay(context: Context): Boolean = AndroidSettings.canDrawOverlays(context)

    fun ready(context: Context): Boolean = usageAccess(context) && overlay(context)
}
