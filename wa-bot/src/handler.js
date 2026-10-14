// Logika inti bot: tanpa Baileys, sehingga bisa dites tanpa nomor WhatsApp.
// Semua kecerdasan ada di API (POST /webhooks/whatsapp); bot hanya meneruskan pesan.

const BUSY_REPLY = "KIRA lagi sibuk sebentar. Coba lagi sebentar lagi ya.";

/** Mengubah pesan Baileys menjadi {jid, text, mediaType}; null untuk pesan yang harus diabaikan. */
export function extractIncoming(msg) {
  const jid = msg?.key?.remoteJid;
  if (!jid || !msg.message || msg.key.fromMe) return null;
  if (jid.endsWith("@g.us") || jid === "status@broadcast" || jid.endsWith("@broadcast")) return null;
  const m = msg.message;
  if (m.imageMessage) return { jid, text: m.imageMessage.caption ?? null, mediaType: "image" };
  if (m.audioMessage) return { jid, text: null, mediaType: "audio" };
  const text = m.conversation ?? m.extendedTextMessage?.text ?? null;
  return text ? { jid, text, mediaType: null } : null;
}

export function createHandler({ apiUrl, secret, fetchFn = fetch, now = Date.now, maxPerMinute = 6 }) {
  const windows = new Map(); // jid -> waktu balasan dalam 60 detik terakhir

  function allowed(jid) {
    const cutoff = now() - 60_000;
    const recent = (windows.get(jid) ?? []).filter((t) => t > cutoff);
    if (recent.length >= maxPerMinute) {
      windows.set(jid, recent);
      return false;
    }
    recent.push(now());
    windows.set(jid, recent);
    return true;
  }

  /** Mengembalikan teks balasan, atau null bila tidak perlu membalas (dibatasi). */
  return async function handle({ jid, text = null, mediaType = null, media = null }) {
    if (!allowed(jid)) return null;
    try {
      const res = await fetchFn(`${apiUrl}/webhooks/whatsapp`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Bot-Secret": secret },
        body: JSON.stringify({
          jid,
          text,
          media_type: mediaType,
          media: media ? Buffer.from(media).toString("base64") : null,
        }),
      });
      if (!res.ok) return BUSY_REPLY;
      return (await res.json()).reply ?? BUSY_REPLY;
    } catch {
      return BUSY_REPLY;
    }
  };
}
