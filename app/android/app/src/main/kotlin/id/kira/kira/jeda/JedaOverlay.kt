package id.kira.kira.jeda

import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat

/**
 * Kartu layar penuh yang digambar langsung oleh layanan di atas aplikasi sosmed (jendela overlay), bukan Activity:
 * tidak bergantung pada aturan peluncuran Activity dari latar yang berbeda antarversi dan pabrikan, tidak membuat tugas
 * (task) baru yang mengubah urutan aplikasi, dan muncul seketika karena dibangun dari kode (tanpa Flutter).
 *
 * Tombol kembali menuju layar utama, bukan ke aplikasi sosmed: itu inti "jeda"-nya. Melanjutkan baru bisa setelah
 * beberapa detik, dan selalu ada pilihan melewati sampai besok.
 */
class JedaOverlay private constructor(private val context: Context, val target: String) {
    private val main = Handler(Looper.getMainLooper())
    private val windows = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val store = JedaStore(context)
    private var view: View? = null

    private val dark: Boolean
        get() = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES

    private val bg get() = if (dark) Color.parseColor("#0F1716") else Color.parseColor("#F4F8F7")
    private val surface get() = if (dark) Color.parseColor("#182321") else Color.WHITE
    private val outline get() = if (dark) Color.parseColor("#2A3A37") else Color.parseColor("#DCE8E6")
    private val ink get() = if (dark) Color.parseColor("#E0ECEA") else Color.parseColor("#0D1F1D")
    private val muted get() = if (dark) Color.parseColor("#A9BDBA") else Color.parseColor("#4A6360")
    private val primary get() = if (dark) Color.parseColor("#6FD3CB") else Color.parseColor("#0B6E6A")
    private val onPrimary get() = if (dark) Color.parseColor("#04302E") else Color.WHITE

    private fun dp(v: Int) = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), context.resources.displayMetrics).toInt()

    private fun rounded(color: Int, radiusDp: Int, stroke: Int? = null) = GradientDrawable().apply {
        setColor(color)
        cornerRadius = dp(radiusDp).toFloat()
        if (stroke != null) setStroke(dp(1), stroke)
    }

    private fun text(value: String, sp: Float, color: Int, bold: Boolean = false) = TextView(context).apply {
        text = value
        setTextSize(TypedValue.COMPLEX_UNIT_SP, sp)
        setTextColor(color)
        if (bold) setTypeface(typeface, Typeface.BOLD)
        setLineSpacing(0f, 1.15f)
    }

    private fun lp(w: Int, h: Int, top: Int = 0) = LinearLayout.LayoutParams(w, h).apply { topMargin = top }
    private val match = ViewGroup.LayoutParams.MATCH_PARENT
    private val wrap = ViewGroup.LayoutParams.WRAP_CONTENT

    private fun show(cards: List<Card>, targetLabel: String?, preview: Boolean) {
        dismiss()
        val root = build(cards, targetLabel, preview)
        val params = WindowManager.LayoutParams(
            match, match,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            PixelFormat.OPAQUE,
        ).apply { gravity = Gravity.TOP or Gravity.START }
        windows.addView(root, params)
        root.requestFocus() // agar tombol kembali sampai ke kartu
        view = root
        current = this
    }

    fun dismiss() {
        main.removeCallbacksAndMessages(null)
        view?.let {
            try {
                windows.removeView(it)
            } catch (_: Exception) {
                // sudah dilepas sistem
            }
        }
        view = null
        if (current === this) current = null
    }

    private fun build(cards: List<Card>, targetLabel: String?, preview: Boolean): View {
        val root = object : LinearLayout(context) {
            override fun dispatchKeyEvent(event: KeyEvent): Boolean {
                if (event.keyCode == KeyEvent.KEYCODE_BACK) {
                    if (event.action == KeyEvent.ACTION_UP) goHome()
                    return true
                }
                return super.dispatchKeyEvent(event)
            }
        }.apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(bg)
            isFocusable = true
            isFocusableInTouchMode = true
        }

        val list = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(24), dp(20), dp(16))
        }
        list.addView(text("KIRA  ·  jeda sebentar", 13f, primary, bold = true))
        for (card in cards) list.addView(cardView(card, preview), lp(match, wrap, dp(16)))
        root.addView(ScrollView(context).apply { addView(list) }, LinearLayout.LayoutParams(match, 0, 1f))

        val bar = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(8), dp(20), dp(16))
        }
        val proceed = Button(context).apply {
            isAllCaps = false
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setTextColor(primary)
            background = rounded(Color.TRANSPARENT, 24, primary)
        }
        bar.addView(proceed, lp(match, dp(52)))
        if (preview) {
            proceed.text = "Tutup contoh"
            proceed.setOnClickListener { dismiss() }
        } else {
            val label = targetLabel?.let { "Lanjut ke $it" } ?: "Lanjut"
            proceed.isEnabled = false
            proceed.alpha = 0.5f
            var left = HOLD_SECONDS
            val countdown = object : Runnable {
                override fun run() {
                    if (left > 0) {
                        proceed.text = "$label ($left)"
                        left--
                        main.postDelayed(this, 1000)
                    } else {
                        proceed.text = label
                        proceed.isEnabled = true
                        proceed.alpha = 1f
                    }
                }
            }
            main.post(countdown)
            proceed.setOnClickListener {
                grace()
                dismiss()
            }
            val skip = Button(context).apply {
                text = "Lewati sampai besok"
                isAllCaps = false
                setTextColor(muted)
                background = null
                setOnClickListener {
                    store.saveState(store.state().copy(skipDay = JedaStore.dayKey(System.currentTimeMillis())))
                    dismiss()
                }
            }
            bar.addView(skip, lp(match, dp(44), dp(4)))
        }
        root.addView(bar)

        ViewCompat.setOnApplyWindowInsetsListener(root) { v, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            v.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            WindowInsetsCompat.CONSUMED
        }
        return root
    }

    private fun cardView(card: Card, preview: Boolean): View {
        val box = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            background = rounded(surface, 20, outline)
            setPadding(dp(18), dp(18), dp(18), dp(18))
        }
        box.addView(text(card.title, 22f, ink, bold = true))
        for (s in card.sections) {
            box.addView(text(s.heading, 13f, primary, bold = true), lp(wrap, wrap, dp(14)))
            box.addView(text(s.body, 16f, ink))
        }
        if (card.footnote.isNotEmpty()) box.addView(text(card.footnote, 12f, muted), lp(wrap, wrap, dp(14)))
        if (card.actionLabel.isNotEmpty()) {
            val action = Button(context).apply {
                text = card.actionLabel
                isAllCaps = false
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                setTextColor(onPrimary)
                background = rounded(primary, 24)
                setOnClickListener { openKira(card.route, preview) }
            }
            box.addView(action, lp(match, dp(48), dp(16)))
        }
        return box
    }

    private fun grace() {
        val now = System.currentTimeMillis()
        store.saveState(store.state().copy(graceUntil = now + store.settings().graceMinutes * 60_000L))
    }

    /** Membuka KIRA di layar yang diminta kartu. Dihitung sebagai kartu sudah dibaca, jadi jeda berlaku. */
    private fun openKira(route: String, preview: Boolean) {
        if (!preview) grace()
        store.setLaunchRoute(route)
        context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
            it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
            context.startActivity(it)
        }
        dismiss()
    }

    private fun goHome() {
        context.startActivity(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        dismiss()
    }

    companion object {
        private const val HOLD_SECONDS = 3

        @Volatile
        var current: JedaOverlay? = null
            private set

        val showing: Boolean get() = current != null

        /**
         * Tampilkan [cards] di utas utama. Mengganti kartu yang sedang tampil. [target] adalah aplikasi yang ditahan:
         * begitu pengguna berpindah ke aplikasi lain (mis. menekan Home), kartu ikut hilang.
         */
        fun show(context: Context, cards: List<Card>, target: String, targetLabel: String?, preview: Boolean) {
            Handler(Looper.getMainLooper()).post {
                try {
                    JedaOverlay(context.applicationContext, target).show(cards, targetLabel, preview)
                } catch (_: Exception) {
                    // izin dicabut di tengah jalan atau jendela ditolak sistem: lebih baik tidak menahan apa pun
                }
            }
        }

        fun dismissCurrent() {
            Handler(Looper.getMainLooper()).post { current?.dismiss() }
        }
    }
}
