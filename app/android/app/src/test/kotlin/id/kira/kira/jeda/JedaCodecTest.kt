package id.kira.kira.jeda

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class JedaCodecTest {
    // Bentuk yang sama dengan JedaSettings.toMap dan JedaPayload.toMap di Dart.
    private val settingsJson = """{"enabled":true,"apps":["com.instagram.android","com.twitter.android"],
        "morning_start":300,"evening_start":1140,"night_start":1290,"grace_minutes":30,"show_other":false}"""

    private val payloadJson = """{"generated_at":1800000000000,
        "morning_by_date":{"2026-10-17":{"kind":"morning","title":"Rencana hari ini",
          "sections":[{"heading":"Olahraga","body":"Jalan cepat 10 menit."}],
          "action_label":"Buka rencana","route":"/plan","footnote":"Usulan."}},
        "morning_generic":{"kind":"morning","title":"Selamat pagi","sections":[],"action_label":"Buka rencana","route":"/plan","footnote":""},
        "evening":null,
        "evening_generic":{"kind":"evening","title":"Catat hari ini dulu?","sections":[],"action_label":"Catat sekarang","route":"/chat","footnote":""},
        "night":{"kind":"night","title":"Waktunya bersiap tidur","sections":[],"action_label":"","route":"/plan","footnote":""},
        "other":null}"""

    @Test fun `pengaturan dari Dart terbaca utuh`() {
        val s = JedaCodec.settings(settingsJson)
        assertEquals(setOf("com.instagram.android", "com.twitter.android"), s.apps)
        assertEquals(true, s.enabled)
        assertEquals(1290, s.nightStart)
        assertFalse(s.showOther)
    }

    @Test fun `isi kartu dari Dart terbaca, null tetap null`() {
        val p = JedaCodec.payload(payloadJson)!!
        assertEquals("Jalan cepat 10 menit.", p.morningByDate["2026-10-17"]!!.sections.single().body)
        assertEquals("/plan", p.morningByDate["2026-10-17"]!!.route)
        assertNull(p.evening)
        assertNull(p.other)
        assertNotNull(p.eveningGeneric)
        assertEquals("", p.night!!.actionLabel)
        assertEquals(1_800_000_000_000L, p.generatedAt)
    }

    @Test fun `rusak atau kosong jatuh ke bawaan tanpa melempar`() {
        assertEquals(Settings(), JedaCodec.settings("bukan json"))
        assertEquals(Settings(), JedaCodec.settings(null))
        assertNull(JedaCodec.payload("{rusak"))
        assertNull(JedaCodec.payload(""))
        assertEquals(GateState(), JedaCodec.state("???"))
        assertEquals(emptyList<Card>(), JedaCodec.cards("nope"))
    }

    @Test fun `nilai di luar rentang dijepit`() {
        val s = JedaCodec.settings("""{"morning_start":99999,"grace_minutes":0}""")
        assertEquals(1439, s.morningStart)
        assertEquals(5, s.graceMinutes)
    }

    @Test fun `keadaan dan daftar kartu bolak-balik tanpa berubah`() {
        val state = GateState(graceUntil = 5, skipDay = "2026-10-17", countDay = "2026-10-17", counts = mapOf("night" to 2))
        assertEquals(state, JedaCodec.state(JedaCodec.stateJson(state)))
        val cards = listOf(Card("night", "Tidur", listOf(Section("a", "b")), "Buka", "/plan", "catatan"))
        assertEquals(cards, JedaCodec.cards(JedaCodec.cardsJson(cards)))
    }

    @Test fun `pengaturan lama tanpa kolom baru memakai nilai bawaan`() {
        val s = JedaCodec.settings(settingsJson)
        assertFalse(s.funFact)
        assertEquals(true, s.useGrace)
        assertEquals(emptyList<Fact>(), s.facts)
    }

    @Test fun `fun fact dan daftar fakta dari Dart terbaca, fakta rusak dilewati`() {
        val json = """{"enabled":true,"apps":["com.instagram.android"],"fun_fact":true,"use_grace":false,
            "facts":[{"id":"a","category":"Tidur","text":"Tidur 7 jam.","source":"AASM"},
                     {"id":"b","category":"X","text":"","source":"kosong dibuang"},
                     {"id":"c","category":"Makan","text":"400 gram.","source":"WHO"}, 5]}"""
        val s = JedaCodec.settings(json)
        assertEquals(true, s.funFact)
        assertEquals(false, s.useGrace)
        assertEquals(listOf("a", "c"), s.facts.map { it.id })
        assertEquals("WHO", s.facts[1].source)
    }

    @Test fun `indeks fakta tersimpan dan terbaca, nilai rusak jatuh ke nol`() {
        val back = JedaCodec.state(JedaCodec.stateJson(GateState(factIndex = 4, counts = mapOf("fact" to 4))))
        assertEquals(4, back.factIndex)
        assertEquals(0, JedaCodec.state("""{"fact_index":-3}""").factIndex)
        assertEquals(0, JedaCodec.state("bukan json").factIndex)
    }

    @Test fun `catatan kegiatan tersimpan dan terbaca, rusak jatuh ke kosong`() {
        val d = Diag(startedAt = 5, lastTickAt = 9, lastFront = "com.instagram.android", lastFrontAt = 8, lastGuarded = "com.instagram.android",
            lastGuardedAt = 8, lastReason = "outside_window", lastError = "", shownTotal = 3)
        assertEquals(d, JedaCodec.diag(JedaCodec.diagJson(d)))
        assertEquals(Diag(), JedaCodec.diag("bukan json"))
        assertEquals(Diag(), JedaCodec.diag(null))
        assertNull(JedaCodec.diag(JedaCodec.diagJson(Diag())).lastFront)
    }
}
