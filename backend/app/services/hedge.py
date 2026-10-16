"""Permintaan "lindung nilai" untuk memangkas ekor latensi panggilan model.

Panggilan model biasanya selesai dalam 5-12 detik, tetapi sesekali macet puluhan detik (terukur: satu ekstraksi 53 detik, yang lain 6).
Bila panggilan pertama belum selesai setelah `after` detik, kirim satu salinan lagi dan pakai yang selesai lebih dulu; yang kalah dibatalkan.
Hasilnya sama persis jenisnya (permintaan identik), jadi kualitas tidak berubah; biayanya hanya satu panggilan tambahan pada kasus yang lambat.
Hanya untuk panggilan tanpa efek samping (ekstraksi dan agent: tool dijalankan sesudahnya, bukan di dalam panggilan model).
"""
import asyncio
from collections.abc import Awaitable, Callable
from typing import TypeVar

T = TypeVar("T")


async def hedged(factory: Callable[[], Awaitable[T]], *, after: float) -> T:
    """Jalankan `factory()`; bila belum selesai setelah `after` detik, jalankan satu lagi dan ambil yang lebih dulu berhasil.

    `after <= 0` mematikan lindung nilai. Bila keduanya gagal, galat pertama yang dilempar. Pembatalan dari luar ikut
    membatalkan kedua panggilan.
    """
    first = asyncio.ensure_future(factory())
    if after <= 0:
        return await first
    try:
        done, _ = await asyncio.wait({first}, timeout=after)
        if done:
            return first.result()
        second = asyncio.ensure_future(factory())
        pending = {first, second}
        errors: list[BaseException] = []
        while pending:
            done, pending = await asyncio.wait(pending, return_when=asyncio.FIRST_COMPLETED)
            for task in done:
                if task.exception() is None:
                    for other in pending:
                        other.cancel()
                    return task.result()
                errors.append(task.exception())
        raise errors[0]
    except asyncio.CancelledError:
        for task in (first, locals().get("second")):
            if task is not None and not task.done():
                task.cancel()
        raise
