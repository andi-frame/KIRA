"""Waktu makan sebuah catatan: dari yang disebut pengguna, atau ditebak dari jam dan isinya.

Tebakan dari jam hanya dipercaya di jam inti (sarapan, makan siang, makan malam). Di luar itu, atau bila hidangan
berat (nasi + lauk) jatuh di jam selingan, KIRA bertanya alih-alih menebak diam-diam: "nasi ayam katsu" jam 15.30
tidak boleh otomatis menjadi selingan.
"""
from datetime import datetime

from app.timeutil import WIB

SLOTS = ("breakfast", "lunch", "snack", "dinner")
SLOT_LABELS = {"breakfast": "sarapan", "lunch": "makan siang", "snack": "selingan", "dinner": "makan malam"}

# Menit sejak 00:00 (WIB). Di dalam jendela inti, jamnya saja sudah cukup meyakinkan.
_CORE = (
    ("breakfast", 5 * 60 + 30, 9 * 60 + 30),
    ("lunch", 11 * 60, 14 * 60),
    ("dinner", 18 * 60, 20 * 60 + 30),
)
# Di atas ini sebuah catatan lebih mirip makan utama daripada selingan (asumsi KIRA; selingan umumnya jauh di bawahnya).
MAIN_MEAL_KCAL = 300.0


def slot_for_clock(moment: datetime) -> str:
    """Tebakan kasar dari jam (WIB), dipakai bila pengguna tidak menyebut waktu makan."""
    h = moment.astimezone(WIB).hour
    if h < 10:
        return "breakfast"
    if h < 15:
        return "lunch"
    if h < 17:
        return "snack"
    return "dinner"


def infer_meal_slot(stated: str | None, moment: datetime, *, total_kcal: float = 0.0, main_dish: bool = False) -> tuple[str, bool]:
    """(waktu makan, yakin). `stated`: yang disebut pengguna. Tidak yakin -> aplikasi dan balasan bertanya."""
    if stated in SLOTS:
        return stated, True
    local = moment.astimezone(WIB)
    minute = local.hour * 60 + local.minute
    guess = slot_for_clock(moment)
    in_core = next((name for name, lo, hi in _CORE if lo <= minute < hi), None)
    heavy = main_dish or total_kcal >= MAIN_MEAL_KCAL
    if in_core is not None:
        return in_core, True
    if guess == "snack" and not heavy:
        return "snack", True  # selingan ringan di jam selingan: tidak perlu ditanya
    return guess, False
