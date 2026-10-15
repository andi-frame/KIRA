import asyncio

import pytest

from app.services.hedge import hedged


class Counter:
    def __init__(self, delays, fail=()):
        self.delays, self.fail, self.calls, self.cancelled = list(delays), set(fail), 0, 0

    async def __call__(self):
        i = self.calls
        self.calls += 1
        try:
            await asyncio.sleep(self.delays[min(i, len(self.delays) - 1)])
        except asyncio.CancelledError:
            self.cancelled += 1
            raise
        if i in self.fail:
            raise RuntimeError(f"gagal {i}")
        return f"hasil {i}"


async def test_panggilan_cepat_tidak_menggandakan_permintaan():
    c = Counter([0.01])
    assert await hedged(c, after=0.2) == "hasil 0"
    assert c.calls == 1


async def test_panggilan_lambat_dilindungi_salinan_yang_lebih_cepat_dan_yang_kalah_dibatalkan():
    c = Counter([5, 0.01])  # yang pertama macet, salinannya cepat
    assert await hedged(c, after=0.05) == "hasil 1"
    await asyncio.sleep(0.05)
    assert c.calls == 2 and c.cancelled == 1


async def test_yang_pertama_tetap_menang_bila_selesai_sebelum_salinan():
    c = Counter([0.15, 5])
    assert await hedged(c, after=0.05) == "hasil 0"
    await asyncio.sleep(0.05)
    assert c.calls == 2 and c.cancelled == 1


async def test_satu_gagal_yang_lain_berhasil_hasilnya_diambil():
    c = Counter([0.1, 0.2], fail={0})
    assert await hedged(c, after=0.05) == "hasil 1"


async def test_keduanya_gagal_melempar_galat_pertama():
    c = Counter([0.1, 0.1], fail={0, 1})
    with pytest.raises(RuntimeError, match="gagal 0"):
        await hedged(c, after=0.05)


async def test_galat_sebelum_batas_waktu_langsung_dilempar_tanpa_salinan():
    c = Counter([0.01], fail={0})
    with pytest.raises(RuntimeError):
        await hedged(c, after=0.5)
    assert c.calls == 1


async def test_nol_mematikan_lindung_nilai():
    c = Counter([0.1, 0.01])
    assert await hedged(c, after=0) == "hasil 0"
    assert c.calls == 1


async def test_pembatalan_dari_luar_membatalkan_kedua_panggilan():
    c = Counter([5, 5])
    task = asyncio.ensure_future(hedged(c, after=0.05))
    await asyncio.sleep(0.15)
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task
    await asyncio.sleep(0.05)
    assert c.calls == 2 and c.cancelled == 2
