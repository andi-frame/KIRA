package id.kira.kira.jeda

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings as AndroidSettings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Jembatan Flutter <-> Android untuk Jeda Sosmed. Nama kanal sama dengan di jeda_bridge.dart. */
class JedaPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "id.kira.kira/jeda").also { it.setMethodCallHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val store = JedaStore(context)
        when (call.method) {
            "permissions" -> result.success(
                mapOf("usage_access" to JedaPermissions.usageAccess(context), "overlay" to JedaPermissions.overlay(context)),
            )
            "openUsageAccess" -> result.success(openSettings(AndroidSettings.ACTION_USAGE_ACCESS_SETTINGS, withPackage = false))
            "openOverlay" -> result.success(openSettings(AndroidSettings.ACTION_MANAGE_OVERLAY_PERMISSION, withPackage = true))
            "installedApps" -> result.success(installedApps())
            "apply" -> {
                store.saveConfig(call.argument<String>("settings") ?: "{}", call.argument<String>("payload"))
                JedaService.sync(context)
                result.success(true)
            }
            "stop" -> {
                store.clear()
                JedaService.sync(context)
                result.success(true)
            }
            "preview" -> result.success(preview(store, call.argument<String>("kind") ?: ""))
            "takeLaunchRoute" -> result.success(store.takeLaunchRoute() ?: "")
            else -> result.notImplemented()
        }
    }

    private fun openSettings(action: String, withPackage: Boolean): Boolean {
        val base = Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            context.startActivity(if (withPackage) Intent(base).setData(Uri.parse("package:${context.packageName}")) else base)
            true
        } catch (_: Exception) {
            try {
                context.startActivity(Intent(AndroidSettings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                true
            } catch (_: Exception) {
                false
            }
        }
    }

    /** Aplikasi yang terpasang dari daftar yang dikenal, lengkap dengan namanya. */
    private fun installedApps(): List<Map<String, String>> {
        val pm = context.packageManager
        return KNOWN_PACKAGES.mapNotNull { pkg ->
            try {
                mapOf("package" to pkg, "label" to pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString())
            } catch (_: Exception) {
                null
            }
        }
    }

    private fun preview(store: JedaStore, kind: String): Boolean {
        val p = store.payload() ?: return false
        val now = System.currentTimeMillis()
        val card = when (kind) {
            "morning" -> p.morningByDate[JedaStore.dateKey(now)] ?: p.morningGeneric
            "evening" -> p.evening ?: p.eveningGeneric
            "night" -> p.night
            "other" -> p.other
            else -> null
        } ?: return false
        JedaOverlay.show(context, listOf(card), target = context.packageName, targetLabel = null, preview = true)
        return true
    }

    companion object {
        /** Harus sama dengan knownSocialApps di jeda_models.dart dan daftar <queries> di AndroidManifest.xml. */
        val KNOWN_PACKAGES = listOf(
            "com.instagram.android", "com.twitter.android", "com.facebook.katana", "com.zhiliaoapp.musically",
            "com.ss.android.ugc.trill", "com.instagram.barcelona", "com.snapchat.android", "com.reddit.frontpage",
            "com.pinterest", "com.linkedin.android", "com.google.android.youtube",
        )
    }
}
