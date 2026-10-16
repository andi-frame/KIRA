package id.kira.kira.jeda

import org.json.JSONArray
import org.json.JSONObject

/** JSON antara bagian Flutter dan Android. Rusak atau kosong jatuh ke nilai bawaan, tidak pernah melempar. */
object JedaCodec {
    private fun JSONObject.str(key: String): String = if (isNull(key)) "" else optString(key, "")

    fun card(o: JSONObject?): Card? {
        if (o == null) return null
        return try {
            val sections = o.optJSONArray("sections") ?: JSONArray()
            Card(
                kind = o.str("kind"),
                title = o.str("title"),
                sections = (0 until sections.length()).map {
                    val s = sections.getJSONObject(it)
                    Section(s.str("heading"), s.str("body"))
                },
                actionLabel = o.str("action_label"),
                route = o.str("route"),
                footnote = o.str("footnote"),
            )
        } catch (_: Exception) {
            null
        }
    }

    fun cardJson(c: Card): JSONObject = JSONObject()
        .put("kind", c.kind)
        .put("title", c.title)
        .put("sections", JSONArray(c.sections.map { JSONObject().put("heading", it.heading).put("body", it.body) }))
        .put("action_label", c.actionLabel)
        .put("route", c.route)
        .put("footnote", c.footnote)

    fun cardsJson(cards: List<Card>): String = JSONArray(cards.map { cardJson(it) }).toString()

    fun cards(raw: String?): List<Card> {
        if (raw.isNullOrEmpty()) return emptyList()
        return try {
            val a = JSONArray(raw)
            (0 until a.length()).mapNotNull { card(a.optJSONObject(it)) }
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun settings(raw: String?): Settings {
        if (raw.isNullOrEmpty()) return Settings()
        return try {
            val o = JSONObject(raw)
            val apps = o.optJSONArray("apps") ?: JSONArray()
            Settings(
                enabled = o.optBoolean("enabled", false),
                apps = (0 until apps.length()).map { apps.getString(it) }.toSet(),
                morningStart = o.optInt("morning_start", 5 * 60).coerceIn(0, 1439),
                eveningStart = o.optInt("evening_start", 19 * 60).coerceIn(0, 1439),
                nightStart = o.optInt("night_start", 21 * 60 + 30).coerceIn(0, 1439),
                graceMinutes = o.optInt("grace_minutes", 30).coerceIn(5, 240),
                showOther = o.optBoolean("show_other", true),
                funFact = o.optBoolean("fun_fact", false),
                useGrace = o.optBoolean("use_grace", true),
                facts = facts(o.optJSONArray("facts")),
            )
        } catch (_: Exception) {
            Settings()
        }
    }

    private fun facts(a: JSONArray?): List<Fact> {
        if (a == null) return emptyList()
        return (0 until a.length()).mapNotNull {
            try {
                val f = a.getJSONObject(it)
                val text = f.str("text")
                if (text.isEmpty()) null else Fact(f.str("id"), f.str("category"), text, f.str("source"))
            } catch (_: Exception) {
                null
            }
        }
    }

    fun payload(raw: String?): Payload? {
        if (raw.isNullOrEmpty()) return null
        return try {
            val o = JSONObject(raw)
            val byDate = o.optJSONObject("morning_by_date")
            Payload(
                generatedAt = o.optLong("generated_at", 0),
                morningByDate = byDate?.keys()?.asSequence()?.mapNotNull { k -> card(byDate.optJSONObject(k))?.let { k to it } }?.toMap()
                    ?: emptyMap(),
                morningGeneric = card(o.optJSONObject("morning_generic")),
                evening = card(o.optJSONObject("evening")),
                eveningGeneric = card(o.optJSONObject("evening_generic")),
                night = card(o.optJSONObject("night")),
                other = card(o.optJSONObject("other")),
            )
        } catch (_: Exception) {
            null
        }
    }

    fun state(raw: String?): GateState {
        if (raw.isNullOrEmpty()) return GateState()
        return try {
            val o = JSONObject(raw)
            val counts = o.optJSONObject("counts")
            GateState(
                graceUntil = o.optLong("grace_until", 0),
                skipDay = if (o.isNull("skip_day")) null else o.optString("skip_day"),
                countDay = if (o.isNull("count_day")) null else o.optString("count_day"),
                counts = counts?.keys()?.asSequence()?.associateWith { counts.optInt(it, 0) } ?: emptyMap(),
                factIndex = o.optInt("fact_index", 0).coerceAtLeast(0),
            )
        } catch (_: Exception) {
            GateState()
        }
    }

    fun stateJson(s: GateState): String = JSONObject()
        .put("grace_until", s.graceUntil)
        .put("skip_day", s.skipDay ?: JSONObject.NULL)
        .put("count_day", s.countDay ?: JSONObject.NULL)
        .put("counts", JSONObject(s.counts as Map<*, *>))
        .put("fact_index", s.factIndex)
        .toString()
}
