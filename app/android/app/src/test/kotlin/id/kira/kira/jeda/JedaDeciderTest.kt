package id.kira.kira.jeda

import org.junit.Assert.assertEquals
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
}
