package id.kira.kira

import id.kira.kira.jeda.JedaPlugin
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

// FlutterFragmentActivity: Health Connect meminta izin lewat registerForActivityResult (Android 14).
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(JedaPlugin())
    }
}
