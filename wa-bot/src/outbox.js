// Mengirim pesan keluar dari API (pengingat check-in, ajakan keluarga). Pesan baru di-ack setelah terkirim,
// sehingga yang gagal dicoba lagi pada putaran berikutnya.

export async function drainOutbox({ apiUrl, secret, fetchFn = fetch, send }) {
  const headers = { "X-Bot-Secret": secret };
  let messages;
  try {
    const res = await fetchFn(`${apiUrl}/webhooks/whatsapp/outbox`, { headers });
    if (!res.ok) return 0;
    messages = (await res.json()).messages ?? [];
  } catch {
    return 0;
  }
  let sent = 0;
  for (const m of messages) {
    try {
      await send(m.jid, m.text);
      await fetchFn(`${apiUrl}/webhooks/whatsapp/outbox/${m.id}/ack`, { method: "POST", headers });
      sent += 1;
    } catch {
      // tidak di-ack: dicoba lagi nanti
    }
  }
  return sent;
}
