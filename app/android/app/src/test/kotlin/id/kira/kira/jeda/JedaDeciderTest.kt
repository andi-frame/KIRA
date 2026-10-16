package id.kira.kira.jeda

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class JedaDeciderTest {
    private fun card(kind: String, title: String = kind) = Card(kind, title, listOf(Section("h", "b")), "Buka", "/chat")

    private val settings = Settings(enabled = true, apps = setOf("com.instagram.android"))
    private val t0 = 1_800_000_000_000L
    private val payload = Payload(
        generatedAt = t0,
        morningByDate = mapOf("2026-10-17" to card("morning", "pagi-17")),
        morningGeneric = card("morning", "pagi-umum"),
        evening = card("evening", "malam-khusus"),
        eveningGeneric = card("evening", "malam-umum"),
        night = card("night"),
        other = card("other"),
    )

    private fun due(
        minute: Int,
        now: Long = t0,
        date: String = "2026-10-17",
        day: String = date,
        s: Settings = settings,
        p: Payload? = payload,
        state: GateState = GateState(),
        same: Boolean = true,
    ) = JedaDecider.due(now, minute, date, day, s, p, state, same)

    private fun h(hour: Int, min: Int = 0) = hour * 60 + min

    @Test fun `mati atau tanpa aplikasi atau tanpa isi kartu tidak menahan siapa pun`() {
        assertTrue(due(h(8), s = settings.copy(enabled = false)).isEmpty())
        assertTrue(due(h(8), s = settings.copy(apps = emptySet())).isEmpty())
        assertTrue(due(h(8), p = null).isEmpty())
    }

    @Test fun `pagi memilih kartu menurut tanggal, tanpa tanggal itu memakai yang umum`() {
        assertEquals(listOf("pagi-17"), due(h(7)).filter { it.kind == "morning" }.map { it.title })
        assertEquals(listOf("pagi-umum"), due(h(7), date = "2026-10-20").filter { it.kind == "morning" }.map { it.title })
    }

    @Test fun `jendela pagi enam jam dari jam mulai`() {
        assertEquals(0, due(h(4, 59)).count { it.kind == "morning" }) // sebelum jam mulai
        assertEquals(1, due(h(5)).count { it.kind == "morning" })
        assertEquals(1, due(h(10, 59)).count { it.kind == "morning" })
        assertEquals(0, due(h(11)).count { it.kind == "morning" })
    }

    @Test fun `siang hari tidak ada kartu kecuali info lain`() {
        assertEquals(listOf("other"), due(h(14)).map { it.kind })
        assertTrue(due(h(14), s = settings.copy(showOther = false)).isEmpty())
    }

    @Test fun `malam hari catat memakai catatan terbaru bila segar`() {
        assertEquals("malam-khusus", due(h(20)).first { it.kind == "evening" }.title)
    }

    @Test fun `catatan lama atau dari hari lain diganti ajakan umum`() {
        val old = t0 + JedaDecider.EVENING_FRESH_MS + 1
        assertEquals("malam-umum", due(h(20), now = old).first { it.kind == "evening" }.title)
        assertEquals("malam-umum", due(h(20), same = false).first { it.kind == "evening" }.title)
    }

    @Test fun `semua sudah tercatat maka tidak ada kartu catat`() {
        val done = payload.copy(evening = null)
        assertEquals(0, due(h(20), p = done).count { it.kind == "evening" })
    }

    @Test fun `larut malam kartu catat dan tidur tampil bersama, urut catat lalu tidur`() {
        assertEquals(listOf("evening", "night", "other"), due(h(22)).map { it.kind })
    }

    @Test fun `lewat tengah malam hanya kartu tidur sampai 04 00`() {
        val kinds = due(h(1)).map { it.kind }
        assertTrue("night" in kinds)
        assertTrue("evening" !in kinds)
        assertTrue(due(h(4), s = settings.copy(showOther = false)).isEmpty())
    }

    @Test fun `jeda sesudah kartu ditutup menahan semuanya sampai habis`() {
        val state = GateState(graceUntil = t0 + 1)
        assertTrue(due(h(22), state = state).isEmpty())
        assertTrue(due(h(22), now = t0 + 2, state = state).isNotEmpty())
    }

    @Test fun `lewati hari ini berlaku untuk hari logis yang sama saja`() {
        val state = GateState(skipDay = "2026-10-17")
        assertTrue(due(h(22), state = state).isEmpty())
        assertTrue(due(h(22), day = "2026-10-18", state = state).isNotEmpty())
    }

    @Test fun `tiap jenis kartu tampil paling banyak tiga kali sehari, info lain sekali`() {
        var state = GateState()
        repeat(JedaDecider.MAX_PER_KIND) {
            val shown = due(h(22), state = state)
            assertTrue(shown.any { it.kind == "night" })
            state = JedaDecider.afterShown(state, "2026-10-17", shown)
        }
        assertTrue(due(h(22), state = state).isEmpty())
        assertEquals(1, state.counts["other"])
    }

    @Test fun `hitungan dimulai dari nol pada hari logis berikutnya`() {
        val state = GateState(countDay = "2026-10-16", counts = mapOf("night" to 3, "evening" to 3, "other" to 1))
        assertTrue(due(h(22), state = state).isNotEmpty())
    }

    @Test fun `info lain lebih tua dari tiga hari tidak ditampilkan`() {
        val stale = t0 + JedaDecider.OTHER_FRESH_MS + 1
        assertTrue(due(h(14), now = stale).isEmpty())
    }

    // ----- fun fact dan masa bebas -----

    private val facts = listOf(
        Fact("a", "Tidur", "Tidur 7 jam atau lebih.", "AASM 2015"),
        Fact("b", "Makan", "Buah dan sayur 400 gram.", "WHO 2026"),
        Fact("c", "Bergerak", "150 menit per minggu.", "WHO 2024"),
    )
    private val withFacts = settings.copy(funFact = true, facts = facts)

    @Test fun `fun fact mati secara bawaan dan tanpa daftar fakta tidak ada kartu fakta`() {
        assertTrue(due(h(14), s = settings.copy(showOther = false)).none { it.kind == "fact" })
        assertNull(JedaDecider.factCard(settings.copy(funFact = true), GateState()))
        assertNull(JedaDecider.factCard(withFacts.copy(funFact = false), GateState()))
    }

    @Test fun `fun fact tampil walau tidak ada kartu terjadwal dan membawa sumbernya tanpa tombol aksi`() {
        val shown = due(h(14), s = withFacts.copy(showOther = false))
        assertEquals(listOf("fact"), shown.map { it.kind })
        val fact = shown.single()
        assertEquals("Tahukah kamu?", fact.title)
        assertEquals("Tidur", fact.sections.single().heading)
        assertEquals("Sumber: AASM 2015", fact.footnote)
        assertEquals("", fact.actionLabel) // kartu fakta tidak punya tombol; hanya Lanjut atau lewati
    }

    @Test fun `fun fact ditaruh setelah kartu terjadwal`() {
        val kinds = due(h(22), s = withFacts).map { it.kind }
        assertEquals("fact", kinds.last())
        assertTrue(kinds.contains("night"))
    }

    @Test fun `fun fact tetap tampil tanpa isi kartu dari Flutter (tanpa sinyal)`() {
        assertEquals(listOf("fact"), due(h(14), s = withFacts, p = null).map { it.kind })
    }

    @Test fun `fakta berputar berurutan dan kembali ke awal, tidak dibatasi tiga kali sehari`() {
        var state = GateState()
        val seen = mutableListOf<String>()
        repeat(7) {
            val shown = due(h(14), s = withFacts.copy(showOther = false), state = state)
            assertEquals(1, shown.size)
            seen += shown.single().sections.single().body
            state = JedaDecider.afterShown(state, "2026-10-17", shown)
        }
        assertEquals(
            listOf("Tidur 7 jam atau lebih.", "Buah dan sayur 400 gram.", "150 menit per minggu.", "Tidur 7 jam atau lebih."),
            seen.take(4),
        )
        assertEquals(7, state.counts["fact"])
        assertEquals(7, state.factIndex)
    }

    @Test fun `indeks fakta di luar rentang atau negatif tetap memilih fakta yang sah`() {
        assertEquals("Tidur 7 jam atau lebih.", JedaDecider.factCard(withFacts, GateState(factIndex = 300))!!.sections.single().body)
        assertEquals("150 menit per minggu.", JedaDecider.factCard(withFacts, GateState(factIndex = -1))!!.sections.single().body)
        assertNotNull(JedaDecider.factCard(withFacts, GateState(factIndex = -5)))
    }

    @Test fun `lewati sampai besok juga melewati fun fact`() {
        assertTrue(due(h(14), s = withFacts, state = GateState(skipDay = "2026-10-17")).isEmpty())
    }

    @Test fun `masa bebas menahan kartu dan fakta, kecuali pengguna mematikannya`() {
        val freeUntil = GateState(graceUntil = t0 + 10 * 60_000L)
        assertTrue(due(h(22), s = withFacts, state = freeUntil).isEmpty())
        assertTrue(due(h(22), s = withFacts.copy(useGrace = false), state = freeUntil).isNotEmpty())
        assertTrue(due(h(22), now = t0 + 11 * 60_000L, s = withFacts, state = freeUntil).isNotEmpty())
    }

    // ----- penjelasan keputusan (layar status) -----

    private fun explain(
        minute: Int,
        now: Long = t0,
        s: Settings = settings,
        p: Payload? = payload,
        state: GateState = GateState(),
    ) = JedaDecider.explain(now, minute, "2026-10-17", "2026-10-17", s, p, state, true)

    @Test fun `penjelasan siap menyebut jenis kartu`() {
        val e = explain(h(22))
        assertEquals("ready", e.code)
        assertTrue("night" in e.kinds)
    }

    @Test fun `penjelasan mati tanpa aplikasi dilewati dan masa bebas`() {
        assertEquals("off", explain(h(22), s = settings.copy(enabled = false)).code)
        assertEquals("no_apps", explain(h(22), s = settings.copy(apps = emptySet())).code)
        assertEquals("skip_day", explain(h(22), state = GateState(skipDay = "2026-10-17")).code)
        val grace = explain(h(22), state = GateState(graceUntil = t0 + 60_000))
        assertEquals("grace", grace.code)
        assertEquals(t0 + 60_000, grace.graceUntil)
        assertEquals("ready", explain(h(22), s = settings.copy(useGrace = false), state = GateState(graceUntil = t0 + 60_000)).code)
    }

    @Test fun `siang hari tanpa fun fact dijelaskan sebagai di luar jam`() {
        val noOther = settings.copy(showOther = false)
        assertEquals("outside_window", explain(h(14), s = noOther).code)
        assertEquals("ready", explain(h(14), s = noOther.copy(funFact = true, facts = listOf(Fact("a", "T", "teks", "S")))).code)
    }

    @Test fun `tanpa isi kartu dan tanpa fakta dijelaskan, dengan fakta tetap siap`() {
        assertEquals("no_content", explain(h(22), p = null).code)
        assertEquals("ready", explain(h(22), p = null, s = settings.copy(funFact = true, facts = listOf(Fact("a", "T", "teks", "S")))).code)
    }

    @Test fun `jatah habis dan semua sudah tercatat dibedakan`() {
        val capped = GateState(countDay = "2026-10-17", counts = mapOf("night" to 3, "evening" to 3, "other" to 1))
        assertEquals("cap_reached", explain(h(22), state = capped).code)
        val done = payload.copy(evening = null, eveningGeneric = null, other = null, night = null)
        assertEquals("already_logged", explain(h(20), p = done).code)
    }

    @Test fun `jendela aktif mengikuti jam`() {
        assertEquals(listOf("morning"), JedaDecider.activeKinds(h(7), settings))
        assertEquals(listOf("evening"), JedaDecider.activeKinds(h(20), settings))
        assertEquals(listOf("evening", "night"), JedaDecider.activeKinds(h(22), settings))
        assertEquals(listOf("night"), JedaDecider.activeKinds(h(2), settings))
        assertTrue(JedaDecider.activeKinds(h(14), settings).isEmpty())
    }
}
