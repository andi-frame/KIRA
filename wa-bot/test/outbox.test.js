import assert from "node:assert/strict";
import { test } from "node:test";

import { drainOutbox } from "../src/outbox.js";

function api(messages) {
  const calls = [];
  const fn = async (url, init = {}) => {
    calls.push({ url, method: init.method ?? "GET", secret: init.headers?.["X-Bot-Secret"] });
    if (url.endsWith("/outbox")) return { ok: true, status: 200, json: async () => ({ messages }) };
    return { ok: true, status: 200, json: async () => ({ ok: true }) };
  };
  fn.calls = calls;
  return fn;
}

test("mengirim tiap pesan lalu memberi ack", async () => {
  const f = api([{ id: "m1", jid: "62811@s.whatsapp.net", text: "Hai, sudah check-in?" }]);
  const sent = [];
  const n = await drainOutbox({ apiUrl: "http://api", secret: "s", fetchFn: f, send: async (j, t) => sent.push([j, t]) });
  assert.equal(n, 1);
  assert.deepEqual(sent, [["62811@s.whatsapp.net", "Hai, sudah check-in?"]]);
  assert.ok(f.calls.some((c) => c.url === "http://api/webhooks/whatsapp/outbox/m1/ack" && c.method === "POST"));
  assert.ok(f.calls.every((c) => c.secret === "s"));
});

test("pesan yang gagal terkirim tidak di-ack agar dicoba lagi", async () => {
  const f = api([{ id: "m1", jid: "j", text: "t" }]);
  const n = await drainOutbox({ apiUrl: "http://api", secret: "s", fetchFn: f, send: async () => { throw new Error("offline"); } });
  assert.equal(n, 0);
  assert.ok(!f.calls.some((c) => c.url.endsWith("/ack")));
});

test("API tidak bisa dihubungi: tidak melempar", async () => {
  const n = await drainOutbox({ apiUrl: "http://api", secret: "s", fetchFn: async () => { throw new Error("down"); }, send: async () => {} });
  assert.equal(n, 0);
});
