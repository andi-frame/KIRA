package id.kira.kira.jeda

/** Jeda Sosmed: kartu apa yang tampil saat aplikasi sosmed dibuka. Murni (tanpa Android) agar bisa diuji di JVM. */

data class Section(val heading: String, val body: String)

data class Card(
    val kind: String, // morning | evening | night | other
    val title: String,
    val sections: List<Section>,
    val actionLabel: String,
    val route: String,
    val footnote: String = "",
)

/** Satu fun fact kesehatan dengan sumbernya. Daftarnya dikirim dari Flutter bersama pengaturan. */
data class Fact(val id: String, val category: String, val text: String, val source: String)

data class Settings(
    val enabled: Boolean = false,
    val apps: Set<String> = emptySet(),
    val morningStart: Int = 5 * 60,
    val eveningStart: Int = 19 * 60,
    val nightStart: Int = 21 * 60 + 30,
    val graceMinutes: Int = 30,
    val showOther: Boolean = true,
    /** Tiap aplikasi pilihan dibuka (di luar jeda bebas), tampilkan satu fun fact. */
    val funFact: Boolean = false,
    /** Mati = tidak ada masa bebas setelah kartu ditutup: kartu muncul lagi tiap kali. */
    val useGrace: Boolean = true,
    val facts: List<Fact> = emptyList(),
)

data class Payload(
    val generatedAt: Long,
    val morningByDate: Map<String, Card> = emptyMap(),
    val morningGeneric: Card? = null,
    val evening: Card? = null,
    val eveningGeneric: Card? = null,
    val night: Card? = null,
    val other: Card? = null,
)

/** Yang diingat antar pembukaan: jeda setelah kartu ditutup, "lewati hari ini", dan berapa kali tiap kartu tampil hari ini. */
data class GateState(
    val graceUntil: Long = 0,
    val skipDay: String? = null,
    val countDay: String? = null,
    val counts: Map<String, Int> = emptyMap(),
    /** Fakta berikutnya yang akan tampil; berputar agar tidak berulang selama masih ada yang belum dilihat. */
    val factIndex: Int = 0,
)

object JedaDecider {
    /** Satu jenis kartu tampil paling banyak sekian kali sehari, supaya tidak menjadi gangguan. */
    const val MAX_PER_KIND = 3
    const val MAX_OTHER = 1

    /** Catatan malam lebih tua dari ini tidak dipercaya lagi: pakai ajakan umum. */
    const val EVENING_FRESH_MS = 5L * 60 * 60 * 1000
    const val OTHER_FRESH_MS = 3L * 24 * 60 * 60 * 1000
    const val MORNING_LENGTH = 6 * 60
    const val NIGHT_END = 4 * 60
    private const val DAY = 24 * 60

    /** Hari "logis" berganti pukul 04.00, jadi tidur larut malam dan pagi sesudah tengah malam tetap satu malam. */
    private fun inWindow(minute: Int, start: Int, length: Int): Boolean = (minute - start + DAY) % DAY < length

    /**
     * @param minute menit sejak tengah malam (waktu ponsel)
     * @param date tanggal kalender (yyyy-MM-dd), untuk memilih kartu pagi
     * @param day hari logis (yyyy-MM-dd), untuk batas tampil dan "lewati hari ini"
     * @param sameDayAsPayload catatan dibuat pada tanggal kalender yang sama dengan sekarang
     */
    fun due(
        now: Long,
        minute: Int,
        date: String,
        day: String,
        settings: Settings,
        payload: Payload?,
        state: GateState,
        sameDayAsPayload: Boolean,
    ): List<Card> {
        if (!settings.enabled || settings.apps.isEmpty()) return emptyList()
        // Masa bebas hanya berlaku bila pengguna memilihnya; mematikannya membuat sisa masa bebas lama tidak dipakai lagi.
        if (state.skipDay == day || (settings.useGrace && now < state.graceUntil)) return emptyList()
        val out = mutableListOf<Card>()
        if (payload != null) out += planned(now, minute, date, day, settings, payload, state, sameDayAsPayload)
        factCard(settings, state)?.let { out += it }
        return out
    }

    /** Fun fact berikutnya sebagai kartu tanpa tombol aksi. Tidak dibatasi per hari: pengguna sendiri yang memintanya. */
    fun factCard(settings: Settings, state: GateState): Card? {
        if (!settings.funFact || settings.facts.isEmpty()) return null
        val fact = settings.facts[Math.floorMod(state.factIndex, settings.facts.size)]
        return Card(
            kind = "fact",
            title = "Tahukah kamu?",
            sections = listOf(Section(fact.category, fact.text)),
            actionLabel = "",
            route = "",
            footnote = "Sumber: ${fact.source}",
        )
    }

    private fun planned(
        now: Long,
        minute: Int,
        date: String,
        day: String,
        settings: Settings,
        payload: Payload,
        state: GateState,
        sameDayAsPayload: Boolean,
    ): List<Card> {
        val counts = if (state.countDay == day) state.counts else emptyMap()
        fun left(kind: String, max: Int) = (counts[kind] ?: 0) < max

        val fresh = sameDayAsPayload && now - payload.generatedAt in 0..EVENING_FRESH_MS
        val out = mutableListOf<Card>()

        if (minute >= settings.eveningStart && left("evening", MAX_PER_KIND)) {
            // Tahu catatan terbaru: null berarti semua sudah tercatat (tidak ada alasan menahan). Tidak tahu: ajakan umum.
            (if (fresh) payload.evening else payload.eveningGeneric)?.let { out += it }
        }
        val night = minute >= settings.nightStart || minute < NIGHT_END
        if (night && left("night", MAX_PER_KIND)) payload.night?.let { out += it }
        if (inWindow(minute, settings.morningStart, MORNING_LENGTH) && minute < settings.eveningStart && left("morning", MAX_PER_KIND)) {
            (payload.morningByDate[date] ?: payload.morningGeneric)?.let { out += it }
        }
        if (settings.showOther && left("other", MAX_OTHER) && now - payload.generatedAt in 0..OTHER_FRESH_MS) {
            payload.other?.let { out += it }
        }
        return out
    }

    /** Keadaan sesudah [shown] ditampilkan: hitungannya naik satu. */
    fun afterShown(state: GateState, day: String, shown: List<Card>): GateState {
        val base = if (state.countDay == day) state.counts else emptyMap()
        val next = base.toMutableMap()
        for (c in shown) next[c.kind] = (next[c.kind] ?: 0) + 1
        val factShown = shown.any { it.kind == "fact" }
        return state.copy(countDay = day, counts = next, factIndex = if (factShown) state.factIndex + 1 else state.factIndex)
    }
}
