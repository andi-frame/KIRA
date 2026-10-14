# Plan implementasi KIRA

Oct 14, 2026 · @Andi Farhan

## Keputusan stack &amp; prinsip implementasi

KIRA dibangun sebagai **aplikasi mobile Flutter**, backend **Python FastAPI**, dan **PostgreSQL di server**. Target pertama adalah MVP yang bisa didemokan untuk pengumpulan, lalu disempurnakan untuk Grand Final bila lolos.


| Lapisan           | Pilihan                                                                                        | Catatan                                                                                                |
| ----------------- | ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| Mobile app        | Flutter (Android sebagai target utama)                                                         | Build APK untuk juri; build Flutter web opsional sebagai link prototype yang bisa dibuka tanpa install |
| Backend           | Python 3.11+, FastAPI, Pydantic v2                                                             | Satu bahasa untuk API, orkestrasi LLM, dan tool kalkulator                                             |
| Orkestrasi LLM    | LangGraph (`StateGraph` + `ToolNode`)                                                          | Alur per pesan sebagai graf: ekstraksi, cek tanda bahaya, konteks, agent ↔ tools, guardrail            |
| ORM &amp; migrasi | SQLAlchemy 2.0 (async) + Alembic                                                               | Skema versi-terkontrol                                                                                 |
| Database          | PostgreSQL di server                                                                           | Semua data pengguna disimpan di server, aplikasi hanya menyimpan token login                           |
| LLM               | Model chat dengan tool calling + input gambar, lewat integrasi LangChain penyedia yang dipilih | Penyedia bisa diganti tanpa mengubah graf                                                              |
| Speech-to-text    | STT API di backend                                                                             | Aplikasi hanya merekam audio dan mengunggah                                                            |
| Bot WhatsApp      | Service Node.js terpisah dengan Baileys                                                        | Baileys adalah library JavaScript, jadi tidak bisa ditanam di FastAPI                                  |


**Prinsip yang dijaga selama pengerjaan**

1. Angka (risiko, gizi, target) hanya dari tool Python, tidak pernah dari teks LLM.
2. Satu alur demo jalan penuh lebih penting daripada banyak fitur setengah jadi.
3. Kontrak API dan skema JSON ekstraksi dikunci di awal, supaya frontend dan backend bisa dikerjakan paralel.
4. Semua data demo adalah data dummy.

## Struktur repository

Satu GitHub Organization dengan tiga repo, atau satu monorepo dengan tiga folder. Monorepo lebih mudah untuk pengumpulan karena cukup satu link dan satu README.

```text
kira/
├── README.md              # alur solusi + cara menjalankan (wajib untuk submission)
├── docker-compose.yml     # postgres + backend + wa-bot untuk dev lokal
├── app/                   # Flutter
│   └── lib/
│       ├── main.dart
│       ├── core/          # api_client (dio), auth, theme, router
│       ├── features/
│       │   ├── onboarding/
│       │   ├── chat/      # teks, rekam suara, foto
│       │   ├── projection/  # layar Kira-kira 10 Tahun + slider
│       │   ├── check/     # rekomendasi cek + input hasil
│       │   ├── family/    # nice-to-have
│       │   └── profile/
│       └── shared/        # widget umum, model data
├── backend/               # FastAPI
│   ├── app/
│   │   ├── main.py
│   │   ├── api/           # router per domain
│   │   ├── models/        # SQLAlchemy
│   │   ├── schemas/       # Pydantic (request/response + skema ekstraksi)
│   │   ├── graph/
│   │   │   ├── kira_graph.py     # StateGraph + run_kira_graph()
│   │   │   ├── state.py          # KiraState
│   │   │   └── nodes/            # extract, safety_check, save_logs, build_context, output_guardrail
│   │   ├── services/      # stt.py, vision.py, summarizer.py, llm.py (model chat)
│   │   ├── tools/         # findrisc.py, nutrition.py, targets.py, whatif.py, faskes.py (@tool)
│   │   └── db.py
│   ├── alembic/
│   ├── seed/              # data gizi + persona Raka
│   └── tests/
└── wa-bot/                # Node.js + Baileys
    └── src/index.ts
```

## Aplikasi Flutter

Aplikasi cukup punya lima layar inti; semua logika berat ada di backend, sehingga aplikasi hanya merekam input, memanggil API, dan menampilkan hasil.


| Layar                 | Isi                                                                                                                                                   | Endpoint yang dipanggil                                             | Fase   |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- | ------ |
| Onboarding            | Percakapan 6–8 pertanyaan (pakai komponen chat yang sama)                                                                                             | `POST /chat/message`, `PUT /profile`                                | MVP    |
| Chat (beranda)        | Bubble chat, tombol rekam suara (tahan untuk bicara), tombol kamera dengan pilihan makanan/struk/hasil cek, kartu hasil ekstraksi yang bisa dikoreksi | `POST /chat/message`, `POST /chat/voice`, `POST /chat/photo`        | MVP    |
| Kira-kira 10 Tahun    | Kurva risiko dengan pita rentang, kurva kedua dari slider (minuman manis/hari, jam tidur, menit jalan), kartu "kebiasaan paling berdampak"            | `GET /projection`, `POST /projection/whatif`                        | MVP    |
| Saatnya cek           | Alasan rekomendasi, jenis cek, daftar Posyandu/Puskesmas terdekat, tombol "masukkan hasil"                                                            | `GET /recommendations/check`, `GET /faskes/nearby`, `POST /results` | MVP    |
| Profil &amp; keluarga | Data profil, mode (pencegahan/pengelolaan), undang keluarga, atur yang dibagikan                                                                      | `GET/PUT /profile`, `POST /family/invite`                           | Fase 2 |


**Package yang disarankan**


| Kebutuhan               | Package                             |
| ----------------------- | ----------------------------------- |
| State management        | `flutter_riverpod`                  |
| HTTP + upload multipart | `dio`                               |
| Navigasi                | `go_router`                         |
| Rekam suara             | `record`                            |
| Kamera/galeri           | `image_picker`                      |
| Grafik kurva + pita     | `fl_chart`                          |
| Simpan token            | `flutter_secure_storage`            |
| Lokasi untuk faskes     | `geolocator` + `permission_handler` |


**Catatan teknis**

- Audio direkam sebagai m4a/aac lalu diunggah; STT dikerjakan backend, sehingga tidak bergantung pada dukungan bahasa di perangkat.
- Foto dikompres di aplikasi (lebar maksimal sekitar 1280 px) sebelum diunggah agar cepat di jaringan seluler.
- Kartu hasil ekstraksi bisa dikoreksi pengguna ("porsinya setengah, bukan satu"); koreksi dikirim balik dan dipakai untuk memperbaiki log.
- Slider what-if sebaiknya di-debounce (misalnya 300 ms) agar tidak memanggil API setiap piksel geseran.

## Backend FastAPI

Semua input (teks, suara, foto, WhatsApp) masuk ke satu fungsi `run_kira_graph()`, sehingga perilaku KIRA sama di aplikasi maupun WhatsApp.


| Method     | Endpoint                               | Fungsi                                                                        | Fase            |
| ---------- | -------------------------------------- | ----------------------------------------------------------------------------- | --------------- |
| POST       | `/auth/register`, `/auth/login`        | Login sederhana dengan nomor HP + PIN, mengembalikan JWT (OTP asli di fase 2) | MVP             |
| GET / PUT  | `/profile`                             | Profil kesehatan                                                              | MVP             |
| POST       | `/chat/message`                        | Pesan teks → orchestrator → balasan + kartu ekstraksi                         | MVP             |
| POST       | `/chat/voice`                          | Audio multipart → STT → `run_kira_graph`                                      | MVP             |
| POST       | `/chat/photo?kind=food|receipt|result` | Foto → model vision → ekstraksi → `run_kira_graph`                            | MVP             |
| PATCH      | `/logs/{id}`                           | Koreksi hasil ekstraksi oleh pengguna                                         | MVP             |
| GET        | `/logs?date=`                          | Riwayat log per hari                                                          | MVP             |
| GET        | `/targets/today`                       | Sisa target gula, garam, lemak hari ini                                       | MVP             |
| GET        | `/projection`                          | Skor + rentang terbaru, tren, kebiasaan paling berdampak                      | MVP             |
| POST       | `/projection/whatif`                   | Body: perubahan kebiasaan → skor + rentang baru                               | MVP             |
| GET        | `/recommendations/check`               | Rekomendasi cek aktif + alasannya                                             | MVP             |
| POST       | `/results`                             | Simpan hasil cek (manual atau hasil baca foto) → hitung ulang proyeksi        | MVP             |
| GET        | `/faskes/nearby?lat=&lng=`             | Posyandu/Puskesmas terdekat dari data seed                                    | MVP             |
| POST       | `/diagnoses`                           | Tandai diagnosis terkonfirmasi → mode pengelolaan                             | MVP (sederhana) |
| POST / GET | `/family/invite`, `/family`            | Undang dan kelola anggota keluarga                                            | Fase 2          |
| POST       | `/webhooks/whatsapp`                   | Dipanggil bot Baileys, dilindungi shared secret                               | Fase 2          |


**Job terjadwal** (APScheduler di dalam proses backend sudah cukup untuk demo)

- Ringkasan mingguan per pengguna → tabel `weekly_summaries`.
- Evaluasi pemicu "saatnya cek" setiap malam → tabel `check_recommendations`.
- Pengingat check-in harian (push notification di fase 2, atau pesan WhatsApp).

## Skema database PostgreSQL

Skema mengikuti lapisan konteks di tab konsep: profil, state terstruktur, ringkasan, log, dan percakapan. Kolom fleksibel memakai `jsonb` supaya skema ekstraksi bisa berkembang tanpa migrasi besar.

```sql
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone TEXT UNIQUE NOT NULL,
  pin_hash TEXT NOT NULL,
  display_name TEXT,
  mode TEXT NOT NULL DEFAULT 'prevention',   -- prevention | management
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE health_profiles (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  birth_date DATE, sex TEXT,
  height_cm NUMERIC, weight_kg NUMERIC, waist_cm NUMERIC,      -- waist boleh NULL (belum diukur)
  family_history_diabetes TEXT,   -- none | second_degree | first_degree
  parent_hypertension BOOLEAN,
  smoker BOOLEAN, on_bp_medication BOOLEAN, history_high_glucose BOOLEAN,
  food_preferences JSONB DEFAULT '{}',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  occurred_at TIMESTAMPTZ NOT NULL,
  kind TEXT NOT NULL,      -- meal | drink | sleep | activity
  source TEXT NOT NULL,    -- text | voice | photo_food | photo_receipt | whatsapp
  raw_text TEXT,
  extracted JSONB NOT NULL,  -- hasil ekstraksi sesuai skema Pydantic
  corrected BOOLEAN NOT NULL DEFAULT false
);
CREATE INDEX ON logs (user_id, occurred_at DESC);

CREATE TABLE log_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  log_id UUID NOT NULL REFERENCES logs(id) ON DELETE CASCADE,
  food_id TEXT REFERENCES foods(id),
  name TEXT NOT NULL, portion_g NUMERIC,
  sugar_g NUMERIC, sodium_mg NUMERIC, fat_g NUMERIC, kcal NUMERIC
);

CREATE TABLE foods (           -- seed dari tabel komposisi pangan + porsi lokal
  id TEXT PRIMARY KEY, name TEXT NOT NULL, aliases TEXT[] DEFAULT '{}',
  per100g JSONB NOT NULL,      -- {sugar_g, sodium_mg, fat_g, kcal, carb_g}
  default_portion_g NUMERIC
);

CREATE TABLE clinical_results (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind TEXT NOT NULL,     -- fasting_glucose | random_glucose | blood_pressure | hba1c | waist
  value JSONB NOT NULL,   -- contoh BP: {"sys":135,"dia":85}
  measured_at TIMESTAMPTZ NOT NULL,
  source TEXT NOT NULL    -- ckg | lab | self
);

CREATE TABLE diagnoses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  condition TEXT NOT NULL,   -- diabetes | prediabetes | hypertension
  diagnosed_at DATE, confirmed_by TEXT
);

CREATE TABLE risk_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  model TEXT NOT NULL,              -- findrisc | bp_category
  score_low INT, score_high INT,
  category_low TEXT, category_high TEXT,
  inputs JSONB NOT NULL, computed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE weekly_summaries (
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  week_start DATE, metrics JSONB, summary_text TEXT,
  PRIMARY KEY (user_id, week_start)
);

CREATE TABLE messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role TEXT NOT NULL,          -- user | assistant | tool
  content TEXT, tool_calls JSONB,
  channel TEXT NOT NULL,       -- app | whatsapp
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE check_recommendations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  test_kind TEXT NOT NULL, reason TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open',   -- open | done | dismissed
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE faskes (
  id SERIAL PRIMARY KEY, name TEXT, kind TEXT,   -- posyandu | puskesmas
  lat DOUBLE PRECISION, lng DOUBLE PRECISION, address TEXT
);

CREATE TABLE family_links (       -- fase 2
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  member_phone TEXT NOT NULL, member_id UUID REFERENCES users(id),
  permissions JSONB NOT NULL DEFAULT '{"checkin_status":true,"check_reminders":true}',
  status TEXT NOT NULL DEFAULT 'pending'
);
```

Catatan: buat tabel `foods` sebelum `log_items` di migrasi (urutan di atas disusun per topik). Jarak faskes untuk demo cukup dihitung di Python dengan rumus haversine; PostGIS tidak diperlukan.

## Orkestrasi LLM dengan LangGraph

Setiap pesan dijalankan lewat satu graf LangGraph dengan delapan node. Tanda bahaya dicegat oleh aturan sebelum LLM bekerja, dan LLM hanya berputar di loop `agent` ↔ `tools` sampai tidak ada lagi tool yang perlu dipanggil.

\[embed: node/dfcd7d6a-b691\]

Graf dijalankan per pesan dan membaca semua konteks dari PostgreSQL di node `build_context`, sehingga tabel milik KIRA tetap menjadi sumber kebenaran.

### Kerangka graf

```python
# graph/kira_graph.py
from typing import Annotated, TypedDict
from langgraph.graph import StateGraph, START, END
from langgraph.graph.message import add_messages
from langgraph.prebuilt import ToolNode, tools_condition

class KiraState(TypedDict):
    user_id: str
    channel: str                 # app | whatsapp
    input_text: str | None
    image: bytes | None
    image_kind: str | None       # food | receipt | result
    extraction: dict | None
    red_flag: str | None
    messages: Annotated[list, add_messages]
    reply: str | None

TOOLS = [cari_gizi, sisa_target_harian, hitung_risiko, simulasi_whatif, cari_faskes]
llm = chat_model.bind_tools(TOOLS)

async def agent(state: KiraState):
    return {"messages": [await llm.ainvoke(state["messages"])]}

g = StateGraph(KiraState)
g.add_node("extract", extract)               # STT/vision -> JSON terstruktur
g.add_node("safety_check", safety_check)     # aturan tanda bahaya, isi state["red_flag"]
g.add_node("emergency_reply", emergency_reply)
g.add_node("save_logs", save_logs)           # log, hasil cek, hitung ulang skor
g.add_node("build_context", build_context)   # profil, state, ringkasan, log, riwayat
g.add_node("agent", agent)
g.add_node("tools", ToolNode(TOOLS))
g.add_node("output_guardrail", output_guardrail)

g.add_edge(START, "extract")
g.add_edge("extract", "safety_check")
g.add_conditional_edges("safety_check",
    lambda s: "emergency_reply" if s["red_flag"] else "save_logs")
g.add_edge("emergency_reply", END)
g.add_edge("save_logs", "build_context")
g.add_edge("build_context", "agent")
g.add_conditional_edges("agent", tools_condition,
    {"tools": "tools", END: "output_guardrail"})
g.add_edge("tools", "agent")
g.add_edge("output_guardrail", END)

kira_graph = g.compile()

async def run_kira_graph(user_id, channel, **inputs):
    out = await kira_graph.ainvoke(
        {"user_id": user_id, "channel": channel, "messages": [], **inputs},
        config={"recursion_limit": 12},     # batas putaran agent <-> tools
    )
    await messages_repo.save(user_id, channel, inputs.get("input_text"), out["reply"])
    return out["reply"]
```

**Catatan penting**

- `user_id` jangan pernah menjadi argumen yang diisi LLM. Suntikkan ke tool dari state graf (misalnya lewat mekanisme injected state di LangGraph) supaya LLM tidak bisa membaca data pengguna lain.
- API LangGraph cukup sering berubah: kunci versi di `requirements.txt` dan cocokkan nama import dengan dokumentasi versi yang terpasang.
- Checkpointer LangGraph tidak wajib di MVP, karena riwayat percakapan sudah disimpan di tabel `messages`.

### Contoh tool

```python
# tools/nutrition.py
from langchain_core.tools import tool

@tool
async def cari_gizi(makanan: str, porsi_gram: float | None = None) -> dict:
    """Ambil gula, natrium, lemak, dan kalori untuk makanan dan porsi tertentu dari database gizi KIRA.
    Wajib dipanggil sebelum menyebut angka gizi apa pun."""
    food = await foods_repo.match(makanan)          # fuzzy match nama + alias
    if not food:
        return {"found": False}
    grams = porsi_gram or food.default_portion_g
    return {"found": True, "name": food.name, "portion_g": grams,
            **{k: v * grams / 100 for k, v in food.per100g.items()}}
```

### Node `build_context`

```python
# graph/nodes/build_context.py
async def build_context(state: KiraState):
    uid = state["user_id"]
    profile = await profile_repo.get(uid)             # ringkas, selalu ada
    health  = await state_repo.current(uid)           # skor+rentang, hasil cek, mode, target
    summary = await summaries_repo.latest(uid)        # ringkasan mingguan
    recent  = await logs_repo.since(uid, hours=72)    # log detail terbaru
    history = await messages_repo.last(uid, n=8)      # percakapan aktif
    query   = state["input_text"] or state["extraction"].get("summary", "")
    older   = await logs_repo.search(uid, query, limit=5)   # log lama yang relevan
    system  = SystemMessage(SYSTEM_PROMPT.format(mode=health.mode))
    context = SystemMessage(render_context(profile, health, summary, recent, older))
    return {"messages": [system, context, *history, HumanMessage(query)]}
```

### Skema ekstraksi (structured output di node `extract`)

```json
{
  "items": [{"name": "rendang", "portion_text": "1 potong", "portion_g_guess": 70, "meal_time": "lunch"}],
  "drinks": [{"name": "es teh manis", "size": "gelas", "count": 1}],
  "sleep": {"bed_time": "02:00", "wake_time": "07:00"},
  "activity": [{"kind": "jalan kaki", "minutes": 15}],
  "clinical_result": null,
  "intent": "log | question_portion | question_general | result_input"
}
```

### Isi system prompt (poin wajib)

- Peran: teman kesehatan berbahasa Indonesia santai, singkat (maksimal sekitar 4 kalimat per balasan di WhatsApp).
- Dilarang menyebut angka gizi atau risiko tanpa memanggil tool.
- Dilarang memberi saran obat, dosis, atau diagnosis; arahkan ke tenaga kesehatan.
- Gunakan "masih sesuai targetmu hari ini", bukan "aman".
- Mode pengelolaan: target lebih ketat dan ingatkan arahan dokter.

**Jika tim belum familiar dengan LangGraph:** bangun MVP dengan loop manual yang memakai fungsi node yang sama (`extract`, `safety_check`, `save_logs`, `build_context`, loop agent–tool, `output_guardrail`), lalu bungkus ke `StateGraph` di fase 2. Karena nodenya sama, migrasinya hanya mengganti cara menyambungkan fungsi.

## Tool kalkulator: FINDRISC, kategori tensi, dan rentang

Untuk MVP cukup dua kalkulator: **FINDRISC** (risiko diabetes 10 tahun) dan **kategori tekanan darah** dari hasil ukur. Framingham Hypertension Risk Score ditambahkan di fase 2.

**Tabel poin FINDRISC** (disusun dari ingatan; cocokkan dengan paper asli Lindström &amp; Tuomilehto, Diabetes Care 2003, sebelum dipakai di pitch)


| Faktor                         | Kategori → poin                                                                    |
| ------------------------------ | ---------------------------------------------------------------------------------- |
| Usia                           | &lt;45 → 0 · 45–54 → 2 · 55–64 → 3 · &gt;64 → 4                                    |
| IMT                            | &lt;25 → 0 · 25–30 → 1 · &gt;30 → 3                                                |
| Lingkar perut pria             | &lt;94 → 0 · 94–102 → 3 · &gt;102 → 4                                              |
| Lingkar perut wanita           | &lt;80 → 0 · 80–88 → 3 · &gt;88 → 4                                                |
| Aktivitas fisik ≥30 menit/hari | ya → 0 · tidak → 2                                                                 |
| Makan sayur/buah setiap hari   | ya → 0 · tidak → 1                                                                 |
| Pernah minum obat hipertensi   | tidak → 0 · ya → 2                                                                 |
| Pernah gula darah tinggi       | tidak → 0 · ya → 5                                                                 |
| Riwayat diabetes keluarga      | tidak → 0 · kakek/nenek/paman/bibi/sepupu → 3 · orang tua/saudara kandung/anak → 5 |


Total 0–26. Kategori risiko 10 tahun: &lt;7 rendah · 7–11 sedikit meningkat · 12–14 sedang · 15–20 tinggi · &gt;20 sangat tinggi.

**Penyesuaian untuk populasi Asia:** batas IMT dan lingkar perut orang Asia lebih rendah dari standar Eropa. Pilih satu varian yang sudah dipublikasikan (versi FINDRISC yang diadaptasi untuk Asia, atau cut-off Asia-Pasifik), tulis sumbernya di proposal, dan konsisten memakainya.

**Rentang ketidakpastian:** setiap input yang belum diketahui dihitung untuk semua kemungkinan kategorinya, lalu diambil skor terendah dan tertinggi.

```python
# tools/findrisc.py
from itertools import product

UNKNOWN_OPTIONS = {
    "waist_points": [0, 3, 4],
    "activity_points": [0, 2],
    "veg_points": [0, 1],
    "high_glucose_points": [0, 5],
}

def score_range(known: dict) -> tuple[int, int]:
    unknown = [k for k in UNKNOWN_OPTIONS if known.get(k) is None]
    base = sum(v for k, v in known.items() if v is not None)
    combos = product(*(UNKNOWN_OPTIONS[k] for k in unknown)) if unknown else [()]
    totals = [base + sum(c) for c in combos]
    return min(totals), max(totals)
```

Aktivitas dan konsumsi sayur/buah diturunkan dari log 14 hari terakhir. Hasil cek gula darah yang tinggi mengisi faktor "pernah gula darah tinggi" dengan pasti, sehingga rentang langsung menyempit.

**Kategori tekanan darah** dari hasil ukur: normal, prehipertensi, atau hipertensi, mengikuti kategori yang dipakai Kemenkes dan CKG. Ambang angkanya ambil dari pedoman resmi, lalu tulis di kode sebagai konstanta.

**What-if yang jujur:**

- Slider aktivitas dan sayur/buah mengubah poin FINDRISC secara langsung.
- Slider berat badan mengubah IMT, jadi poinnya ikut berubah.
- Minuman manis dan jam tidur tidak ada di FINDRISC. Tampilkan dampaknya sebagai perubahan **gula harian dibanding target** dan kebiasaan tidur, bukan sebagai angka risiko, kecuali tim sudah mengutip relative risk dari meta-analisis.

## Bot WhatsApp (Baileys)

Bot dibuat sebagai service Node.js kecil yang hanya meneruskan pesan: semua logika tetap di FastAPI melalui `POST /webhooks/whatsapp`. Ini fitur fase 2 (nice-to-have) dan hanya untuk prototype.

**Alur**

1. Bot login dengan scan QR sekali, sesi disimpan di folder auth.
2. Pesan masuk (teks, voice note, gambar) → media diunduh → dikirim ke webhook bersama nomor pengirim.
3. FastAPI mencocokkan nomor ke akun. Nomor baru diminta menautkan akun dengan kode dari aplikasi ("KIRA 4821").
4. FastAPI menjalankan `run_kira_graph` yang sama dengan aplikasi, lalu mengembalikan teks balasan.
5. Bot mengirim balasan ke pengguna.

```ts
// wa-bot/src/index.ts (sketsa)
import makeWASocket, { useMultiFileAuthState, downloadMediaMessage } from "@whiskeysockets/baileys";

const { state, saveCreds } = await useMultiFileAuthState("auth");
const sock = makeWASocket({ auth: state, printQRInTerminal: true });
sock.ev.on("creds.update", saveCreds);

sock.ev.on("messages.upsert", async ({ messages }) => {
  const msg = messages[0];
  if (!msg.message || msg.key.fromMe) return;
  const jid = msg.key.remoteJid!;
  const text = msg.message.conversation ?? msg.message.extendedTextMessage?.text ?? null;
  const hasMedia = !!(msg.message.imageMessage || msg.message.audioMessage);
  const media = hasMedia ? await downloadMediaMessage(msg, "buffer", {}) : null;

  const res = await fetch(`${process.env.API_URL}/webhooks/whatsapp`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Bot-Secret": process.env.BOT_SECRET! },
    body: JSON.stringify({ jid, text, mediaType: hasMedia ? (msg.message.imageMessage ? "image" : "audio") : null,
                           media: media ? media.toString("base64") : null }),
  });
  const { reply } = await res.json();
  await sock.sendMessage(jid, { text: reply });
});
```

Nama paket dan API Baileys berubah antar versi, jadi cek dokumentasi versi yang dipasang sebelum menulis kode final.

**Batasan yang dipasang**

- Pakai nomor WhatsApp khusus, bukan nomor pribadi anggota tim.
- Batasi jumlah balasan per menit agar tidak terlihat seperti spam (risiko blokir lebih kecil).
- Hanya data dummy; tulis di README bahwa produksi memakai WhatsApp Business Platform resmi.

## Deployment &amp; environment

Untuk demo, satu VPS atau satu platform PaaS sudah cukup menampung backend, PostgreSQL, dan bot WhatsApp. Yang penting backend punya URL HTTPS publik agar APK di HP mana pun bisa terhubung.


| Komponen         | Opsi deploy                                                                                  | Catatan                                                              |
| ---------------- | -------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| PostgreSQL       | Managed Postgres (Supabase, Neon, Railway) atau container di VPS                             | Simpan connection string di env, jangan di repo                      |
| Backend FastAPI  | Railway/Render/Fly.io, atau VPS + Docker + Caddy untuk HTTPS                                 | Jalankan `alembic upgrade head` dan seed saat deploy                 |
| Bot WhatsApp     | Proses Node yang selalu menyala di VPS/Railway                                               | Folder sesi Baileys harus persisten, kalau tidak perlu scan QR ulang |
| Aplikasi Flutter | APK release diunggah ke Google Drive/GitHub Releases; opsional Flutter web di Vercel/Netlify | Link prototype untuk juri                                            |


**Variabel environment backend**

```text
DATABASE_URL=postgresql+asyncpg://...
JWT_SECRET=...
LLM_API_KEY=...
LLM_MODEL_CHAT=...
LLM_MODEL_EXTRACT=...
STT_API_KEY=...
BOT_SECRET=...            # dicek di /webhooks/whatsapp
CORS_ORIGINS=...          # bila memakai Flutter web
```

**Keamanan minimum:** HTTPS, PIN di-hash (bcrypt/argon2), JWT berumur pendek, semua query difilter per `user_id`, dan secret tidak pernah di-commit.

## Timeline &amp; pembagian tugas

Pengerjaan dibagi dua fase: **Fase 1** membangun MVP untuk pengumpulan (ditutup 16 Oktober pukul 23.50 WIB), **Fase 2** menyempurnakan produk menuju Grand Final 1 November bila lolos.

\[embed: node/9f9de247-5256\]

Fase 2 sebaiknya dimulai tanpa menunggu pengumuman finalis 23 Oktober, karena jarak pengumuman ke Grand Final hanya sekitar seminggu.


| Peran              | Fase 1 (MVP, 14–16 Okt)                                                                                                                                       | Fase 2 (17–31 Okt)                                                                          |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| AI/ML              | Skema ekstraksi + prompt, graf LangGraph (extract, safety\_check, agent ↔ tools, guardrail), tool FINDRISC &amp; gizi, seed sekitar 100 makanan lokal populer | Framingham Hypertension, ringkasan mingguan, evaluasi akurasi ekstraksi, cache respons demo |
| Backend            | Kerangka FastAPI, auth sederhana, PostgreSQL + Alembic, endpoint chat/voice/photo/projection/results, deploy HTTPS                                            | Webhook + bot WhatsApp (Baileys), endpoint keluarga, scheduler, pengamanan                  |
| Flutter            | Layar chat (teks, suara, foto), layar Kira-kira 10 Tahun + slider, layar Saatnya cek + input hasil, build APK                                                 | Layar profil &amp; keluarga, polish UI, notifikasi pengingat                                |
| Produk &amp; pitch | Seed persona Raka, video 2 menit, pitch deck + slide penggunaan AI, README, proposal                                                                          | Revisi deck dari masukan, latihan pitching dan sesi tanya jawab                             |


**Kalau waktu Fase 1 tidak cukup, potong dengan urutan ini:**

1. Foto struk (foto makanan tetap ada).
2. Input suara (teks tetap ada).
3. Peta faskes (ganti daftar statis).

**Jangan dipotong:** chat teks + ekstraksi, layar Kira-kira 10 Tahun, rekomendasi "saatnya cek", dan input hasil yang mengkalibrasi ulang proyeksi. Empat ini adalah inti alur demo.

## Testing, risiko, dan fallback demo

Yang wajib dites otomatis hanya bagian yang menghasilkan angka; sisanya dites manual dengan skrip demo.

**Tes otomatis (pytest)**

- `findrisc`: skor untuk beberapa profil contoh cocok dengan hitungan manual dari tabel poin; rentang menyempit setelah input diisi.
- `nutrition`: porsi dan agregasi gula/natrium/lemak benar; makanan tidak dikenal mengembalikan "tidak ditemukan", bukan angka karangan.
- `targets`: sisa target harian benar setelah beberapa log.
- `guardrail`: pesan berisi tanda bahaya selalu mendapat balasan darurat; balasan yang menyebut obat/dosis ditolak.

**Tes manual**

- 20 kalimat check-in variasi bahasa campur ("tadi makan seblak sama boba", "sarapan nasi uduk, kopi sachet 2") → cek hasil ekstraksi.
- 5 foto struk dan 5 foto makanan nyata → cek item yang terbaca.
- Skrip demo lengkap diulang minimal 5 kali di HP yang dipakai saat pitching.


| Risiko                              | Dampak                                | Fallback                                                           |
| ----------------------------------- | ------------------------------------- | ------------------------------------------------------------------ |
| API LLM lambat atau gagal saat demo | Demo macet                            | Cache respons untuk input skrip demo + video rekaman layar         |
| Internet venue buruk                | Aplikasi tidak bisa memanggil backend | Hotspot cadangan dari HP lain; video rekaman                       |
| Nomor WhatsApp diblokir             | Bagian WhatsApp gagal                 | Tunjukkan alur yang sama di aplikasi; nomor cadangan               |
| Ekstraksi foto salah                | Angka gizi meleset                    | Kartu ekstraksi bisa dikoreksi; pakai foto yang sudah dites        |
| Waktu tidak cukup                   | Fitur belum selesai                   | Ikuti urutan prioritas di timeline; potong fitur fase 2 lebih dulu |
