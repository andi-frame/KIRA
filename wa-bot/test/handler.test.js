import assert from "node:assert/strict";
import { test } from "node:test";

import { createHandler, extractIncoming } from "../src/handler.js";

const JID = "6281200000001@s.whatsapp.net";

function fakeFetch(replyBody, { status = 200, calls = [] } = {}) {
  const fn = async (url, init) => {
    calls.push({ url, init, body: JSON.parse(init.body) });
    return { ok: status < 400, status, json: async () => replyBody };
  };
  fn.calls = calls;
  return fn;
}

test("meneruskan teks ke webhook dengan rahasia bot dan mengembalikan balasan", async () => {
  const f = fakeFetch({ reply: "Halo juga!" });
  const handle = createHandler({ apiUrl: "http://api", secret: "s3cret", fetchFn: f });
  const out = await handle({ jid: JID, text: "halo" });
  assert.equal(out, "Halo juga!");
  assert.equal(f.calls[0].url, "http://api/webhooks/whatsapp");
  assert.equal(f.calls[0].init.headers["X-Bot-Secret"], "s3cret");
  assert.deepEqual(f.calls[0].body, { jid: JID, text: "halo", media_type: null, media: null });
});

test("mengirim media sebagai base64 beserta jenisnya", async () => {
  const f = fakeFetch({ reply: "ok" });
  const handle = createHandler({ apiUrl: "http://api", secret: "x", fetchFn: f });
  await handle({ jid: JID, text: "struk", mediaType: "image", media: Buffer.from("abc") });
  assert.equal(f.calls[0].body.media_type, "image");
  assert.equal(f.calls[0].body.media, Buffer.from("abc").toString("base64"));
});

test("membatasi balasan per nomor agar tidak terlihat seperti spam", async () => {
  const f = fakeFetch({ reply: "ok" });
  let t = 0;
  const handle = createHandler({ apiUrl: "http://api", secret: "x", fetchFn: f, maxPerMinute: 2, now: () => t });
  assert.equal(await handle({ jid: JID, text: "1" }), "ok");
  assert.equal(await handle({ jid: JID, text: "2" }), "ok");
  assert.equal(await handle({ jid: JID, text: "3" }), null); // dibatasi, diam saja
  assert.equal(f.calls.length, 2);
  t += 61_000;
  assert.equal(await handle({ jid: JID, text: "4" }), "ok"); // jendela baru
});

test("batas berlaku per nomor, bukan global", async () => {
  const f = fakeFetch({ reply: "ok" });
  const handle = createHandler({ apiUrl: "http://api", secret: "x", fetchFn: f, maxPerMinute: 1, now: () => 0 });
  assert.equal(await handle({ jid: JID, text: "a" }), "ok");
  assert.equal(await handle({ jid: "6281299999999@s.whatsapp.net", text: "a" }), "ok");
});

test("API mati: balasan sopan, bukan crash", async () => {
  const handle = createHandler({ apiUrl: "http://api", secret: "x", fetchFn: async () => { throw new Error("down"); } });
  assert.match(await handle({ jid: JID, text: "halo" }), /coba lagi/i);
});

test("status HTTP gagal dari API: balasan sopan", async () => {
  const handle = createHandler({ apiUrl: "http://api", secret: "x", fetchFn: fakeFetch({}, { status: 502 }) });
  assert.match(await handle({ jid: JID, text: "halo" }), /coba lagi/i);
});

test("mengabaikan grup, status, dan pesan dari bot sendiri", () => {
  assert.equal(extractIncoming({ key: { remoteJid: "1203@g.us", fromMe: false }, message: { conversation: "hi" } }), null);
  assert.equal(extractIncoming({ key: { remoteJid: "status@broadcast" }, message: { conversation: "hi" } }), null);
  assert.equal(extractIncoming({ key: { remoteJid: JID, fromMe: true }, message: { conversation: "hi" } }), null);
  assert.equal(extractIncoming({ key: { remoteJid: JID }, message: null }), null);
});

test("mengenali teks, teks panjang, caption gambar, dan voice note", () => {
  const key = { remoteJid: JID, fromMe: false };
  assert.deepEqual(extractIncoming({ key, message: { conversation: "halo" } }), { jid: JID, text: "halo", mediaType: null });
  assert.deepEqual(
    extractIncoming({ key, message: { extendedTextMessage: { text: "panjang" } } }),
    { jid: JID, text: "panjang", mediaType: null },
  );
  assert.deepEqual(
    extractIncoming({ key, message: { imageMessage: { caption: "struk" } } }),
    { jid: JID, text: "struk", mediaType: "image" },
  );
  assert.deepEqual(extractIncoming({ key, message: { audioMessage: {} } }), { jid: JID, text: null, mediaType: "audio" });
});
