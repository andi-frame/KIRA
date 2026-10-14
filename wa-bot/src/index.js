// Bot WhatsApp KIRA (Baileys, TIDAK RESMI): hanya untuk prototype dengan nomor khusus dan data dummy.
// Produksi wajib memakai WhatsApp Business Platform resmi. Lihat README.md.
import makeWASocket, {
  DisconnectReason,
  downloadMediaMessage,
  fetchLatestBaileysVersion,
  useMultiFileAuthState,
} from "@whiskeysockets/baileys";
import pino from "pino";
import qrcode from "qrcode-terminal";

import { createHandler, extractIncoming } from "./handler.js";
import { drainOutbox } from "./outbox.js";

const apiUrl = process.env.API_URL ?? "http://localhost:8000";
const secret = process.env.BOT_SECRET;
const authDir = process.env.AUTH_DIR ?? "auth";
const outboxIntervalMs = Number(process.env.OUTBOX_INTERVAL_MS ?? 60_000);

if (!secret) {
  console.error("BOT_SECRET wajib diisi (samakan dengan BOT_SECRET di backend).");
  process.exit(1);
}

const handle = createHandler({ apiUrl, secret, maxPerMinute: Number(process.env.MAX_REPLIES_PER_MINUTE ?? 6) });
const logger = pino({ level: process.env.LOG_LEVEL ?? "warn" });
let outboxTimer = null;

async function start() {
  const { state, saveCreds } = await useMultiFileAuthState(authDir); // sesi disimpan agar tidak scan QR ulang
  const { version } = await fetchLatestBaileysVersion();
  const sock = makeWASocket({ version, auth: state, logger });
  const send = (jid, text) => sock.sendMessage(jid, { text });

  sock.ev.on("creds.update", saveCreds);

  sock.ev.on("connection.update", ({ connection, lastDisconnect, qr }) => {
    if (qr) qrcode.generate(qr, { small: true });
    if (connection === "open") {
      console.log("WhatsApp terhubung.");
      clearInterval(outboxTimer);
      outboxTimer = setInterval(() => drainOutbox({ apiUrl, secret, send }), outboxIntervalMs);
    }
    if (connection === "close") {
      clearInterval(outboxTimer);
      const code = lastDisconnect?.error?.output?.statusCode;
      if (code === DisconnectReason.loggedOut) {
        console.error("Sesi keluar. Hapus folder auth lalu scan QR lagi.");
        process.exit(1);
      }
      setTimeout(start, 3000); // sambung ulang
    }
  });

  sock.ev.on("messages.upsert", async ({ messages, type }) => {
    if (type !== "notify") return;
    for (const msg of messages) {
      const incoming = extractIncoming(msg);
      if (!incoming) continue;
      try {
        const media = incoming.mediaType ? await downloadMediaMessage(msg, "buffer", {}) : null;
        const reply = await handle({ ...incoming, media });
        if (reply) await send(incoming.jid, reply);
      } catch (err) {
        logger.error({ err }, "gagal memproses pesan");
      }
    }
  });
}

start();
