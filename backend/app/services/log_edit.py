"""Mengubah atau menghapus catatan (dari layar Riwayat/kartu chat, atau dari koreksi lewat chat) dengan satu jalur yang sama.

Setelah perubahan apa pun, `refresh_after_change` menghitung ulang kondisi turunan (snapshot risiko, rekomendasi cek)
supaya tidak tertahan pada versi sebelum perubahan. Angka lain (total harian, proyeksi, rencana, tren) dihitung langsung
dari catatan setiap kali diminta, jadi otomatis ikut.
"""
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta

from sqlalchemy import delete
from sqlalchemy.ext.asyncio import AsyncSession

from app.core_calc.red_flags import parse_sleep_hours
from app.models import Log, LogItem
from app.repos import foods as foods_repo
from app.repos import logs as logs_repo
from app.schemas.api import ItemPatch
from app.schemas.extraction import LogCorrection
from app.services import risk
from app.services.meal_slot import SLOT_LABELS, SLOTS
from app.services.nutrition_items import item_data, resolve_food_item
from app.timeutil import WIB, local_date, utcnow

HALVED_KEY = "halved_groups"
_NUTRIENT_FIELDS = ("portion_g", "sugar_g", "sodium_mg", "fat_g", "kcal")


class EditError(ValueError):
    """Permintaan ubah tidak masuk akal untuk jenis catatan ini."""


def group_key(item: LogItem) -> str:
    return item.group_name or item.name


def halved_groups(log: Log) -> list[str]:
    raw = (log.extracted or {}).get(HALVED_KEY, [])
    return [g for g in raw if isinstance(g, str)] if isinstance(raw, list) else []


def _set_extracted(log: Log, **updates) -> None:
    """JSONB tidak melacak perubahan di tempat: selalu tetapkan dict baru."""
    log.extracted = {**(log.extracted or {}), **updates}


async def _items_of(session: AsyncSession, log: Log) -> list[LogItem]:
    return (await logs_repo._with_items(session, [log]))[0][1]


def _patches_from(items: list[LogItem]) -> list[ItemPatch]:
    return [ItemPatch(name=i.name, portion_g=i.portion_g, food_id=i.food_id, group=i.group_name) for i in items]


def _scaled(p: ItemPatch, scale: float) -> ItemPatch:
    return p.model_copy(update={"portion_g": None if p.portion_g is None else p.portion_g * scale})


def _scaled_label_items(existing: list[LogItem], patches: list[ItemPatch]) -> list[logs_repo.ItemData]:
    """Log dari label kemasan: angkanya tercetak, bukan dari tabel pangan. Koreksi porsi menskalakan angka itu
    secara proporsional (nama tidak dicocokkan ulang, supaya gizi tidak hilang)."""
    by_name = {i.name.lower(): i for i in existing}
    out: list[logs_repo.ItemData] = []
    for p in patches:
        old = by_name.get(p.name.lower())
        if old is None or p.portion_g is None or not old.portion_g:
            out.append(logs_repo.ItemData(name=p.name, portion_g=p.portion_g))
            continue
        ratio = p.portion_g / old.portion_g

        def scale(v):
            return None if v is None else v * ratio

        out.append(logs_repo.ItemData(name=old.name, portion_g=p.portion_g, sugar_g=scale(old.sugar_g),
                                      sodium_mg=scale(old.sodium_mg), fat_g=scale(old.fat_g), kcal=scale(old.kcal)))
    return out


async def edit_meal_items(
    session: AsyncSession, log: Log, *, items: list[ItemPatch] | None = None, scale: float | None = None,
    group: str | None = None, half: bool | None = None,
) -> list[LogItem]:
    """Ganti isi catatan makan/minum.

    - `items`: daftar baru (yang tidak dikirim = dihapus). Angka eksplisit menggantikan tanda "setengah porsi".
    - `scale` (+ `group`): skalakan porsi yang ada.
    - `half` (+ `group`): "setengah porsi" sebagai SAKLAR yang idempoten. half=true pada hidangan yang sudah setengah tidak
      mengubah apa pun; half=false mengembalikan ke porsi sebelumnya. Penekanan ganda tidak menurunkan angkanya berulang.
    """
    current = await _items_of(session, log)
    patches = items if items is not None else _patches_from(current)
    flags = [] if items is not None else halved_groups(log)
    keys = {group_key(i) for i in current}

    def key_of(p: ItemPatch) -> str:
        return p.group or p.name

    if half is not None:
        targets = {group} if group else keys
        if half:
            todo = sorted(k for k in targets if k in keys and k not in flags)
            factor = 0.5
            flags = flags + todo
        else:
            todo = sorted(k for k in targets if k in flags)
            factor = 2.0
            flags = [k for k in flags if k not in todo]
        if todo:
            patches = [_scaled(p, factor) if key_of(p) in todo else p for p in patches]
    elif scale is not None:
        affected = {group} if group else keys
        patches = [_scaled(p, scale) if key_of(p) in affected else p for p in patches]
        if scale == 0.5:
            flags = sorted(set(flags) | {k for k in affected if k in keys})
        else:  # porsi bukan lagi "setengah dari semula"
            flags = [k for k in flags if k not in affected]

    if log.source in {"photo_label", "barcode"}:  # angka tercetak di kemasan, bukan dari tabel pangan
        new_items = _scaled_label_items(current, patches)
    else:
        catalog = await foods_repo.catalog(session)
        new_items = [item_data(p.name, catalog.find_food(p.name, p.food_id), p.portion_g, group_name=p.group)
                     for p in patches]
    _set_extracted(log, **{HALVED_KEY: flags})
    return await logs_repo.replace_items(session, log, new_items, commit=False)


async def replace_meal(session: AsyncSession, log: Log, food_items: list) -> list[LogItem]:
    """"Bukan nasi goreng, tapi mie goreng": isi diganti seluruhnya; waktu dan waktu makannya tetap."""
    catalog = await foods_repo.catalog(session)
    new_items, resolved = [], []
    for it in food_items:
        res = resolve_food_item(it, catalog)
        new_items.extend(res.items)
        resolved.append(res.trace)
    _set_extracted(log, items=[i.model_dump() for i in food_items], resolved=resolved, **{HALVED_KEY: []})
    return await logs_repo.replace_items(session, log, new_items, commit=False)


def set_meal_slot(log: Log, slot: str) -> None:
    if log.kind != "meal":
        raise EditError("Waktu makan hanya untuk catatan makan.")
    if slot not in SLOTS:
        raise EditError("Waktu makan tidak dikenal.")
    log.meal_slot, log.slot_confirmed, log.corrected = slot, True, True


async def set_drink_count(session: AsyncSession, log: Log, count: float) -> None:
    """Jumlah minuman berubah: gizi (yang sudah dikali jumlah lama) diskalakan sebanding."""
    if log.kind != "drink":
        raise EditError("Jumlah hanya untuk catatan minuman.")
    old = float((log.extracted or {}).get("count", 1) or 1)
    ratio = count / old
    for item in await _items_of(session, log):
        for field in _NUTRIENT_FIELDS:
            value = getattr(item, field)
            if value is not None:
                setattr(item, field, value * ratio)
    _set_extracted(log, count=count)
    log.corrected = True
    await session.flush()


def update_fields(log: Log, *, minutes: int | None = None, activity_kind: str | None = None, hours: float | None = None,
                  bed_time: str | None = None, wake_time: str | None = None) -> None:
    """Ubah isi catatan tidur atau aktivitas. Hanya yang dikirim yang berubah."""
    ex = dict(log.extracted or {})
    if log.kind == "activity":
        if minutes is not None:
            ex["minutes"] = minutes
        if activity_kind:
            ex["kind"] = activity_kind
    elif log.kind == "sleep":
        if bed_time is not None:
            ex["bed_time"] = bed_time
        if wake_time is not None:
            ex["wake_time"] = wake_time
        if hours is not None:
            ex["hours"] = hours
        elif ex.get("bed_time") and ex.get("wake_time") and (bed_time is not None or wake_time is not None):
            ex["hours"] = parse_sleep_hours(ex["bed_time"], ex["wake_time"])
    else:
        raise EditError("Jenis catatan ini diubah lewat daftar item.")
    log.extracted = ex
    log.corrected = True


def move_to(log: Log, when: datetime) -> None:
    log.occurred_at = when
    log.corrected = True


async def delete_log(session: AsyncSession, log: Log) -> None:
    await session.execute(delete(LogItem).where(LogItem.log_id == log.id))
    await session.delete(log)
    await session.flush()


async def refresh_after_change(session: AsyncSession, user_id: uuid.UUID) -> None:
    """Hitung ulang yang diturunkan dari catatan dan disimpan: snapshot risiko dan rekomendasi cek."""
    await session.flush()
    state = await risk.compute_risk_state(session, user_id)
    await risk.save_snapshot_if_changed(session, user_id, state, commit=False)
    await risk.refresh_check_recommendation(session, user_id, state, commit=False)


# ----- koreksi lewat chat -----

@dataclass
class CorrectionResult:
    ok: bool
    note: str  # kalimat untuk CATATAN SISTEM: apa yang terjadi, supaya balasan menyebutnya dengan jujur
    log_id: str | None = None


def _title(kind: str, log: Log, items: list[LogItem]) -> str:
    if kind in {"meal", "drink"}:
        names: list[str] = []
        for i in items:
            label = i.group_name or i.name
            if label not in names:
                names.append(label)
        return ", ".join(names) or "catatan"
    if kind == "activity":
        return str((log.extracted or {}).get("kind") or "aktivitas")
    return "tidur"


def _matches(text: str | None, log: Log, items: list[LogItem]) -> bool:
    if not text or not text.strip():
        return True
    needle = text.strip().lower()
    haystacks = [i.name.lower() for i in items] + [(i.group_name or "").lower() for i in items]
    haystacks += [str((log.extracted or {}).get(k, "")).lower() for k in ("name", "kind")]
    return any(h and (needle in h or h in needle) for h in haystacks)


async def find_target(session: AsyncSession, user_id: uuid.UUID, c: LogCorrection) -> tuple[Log, list[LogItem], int] | None:
    """Catatan yang dimaksud: yang terbaru pada hari itu dengan jenis dan nama yang cocok. Mengembalikan juga berapa
    kandidat yang cocok (bila > 1 dan pengguna tidak menyebut nama, balasan menyebut yang mana yang diubah)."""
    day = local_date(utcnow()) - timedelta(days=1 if c.day == "yesterday" else 0)
    rows = [(lg, it) for lg, it in await logs_repo.on_date(session, user_id, day)
            if lg.kind == c.target and _matches(c.match_text, lg, it)]
    if not rows:
        return None
    return rows[0][0], rows[0][1], len(rows)  # on_date: terbaru dulu


async def apply_correction(session: AsyncSession, user_id: uuid.UUID, c: LogCorrection) -> CorrectionResult:
    found = await find_target(session, user_id, c)
    if found is None:
        what = c.match_text or {"meal": "makan", "drink": "minuman", "sleep": "tidur", "activity": "aktivitas"}[c.target]
        when = "kemarin" if c.day == "yesterday" else "hari ini"
        return CorrectionResult(False, f"Tidak ada catatan '{what}' {when} yang bisa diubah. Tanyakan catatan yang mana yang "
                                       "dimaksud; JANGAN mencatatnya sebagai entri baru.")
    log, items, n = found
    at = log.occurred_at.astimezone(WIB).strftime("%H:%M")
    title = _title(c.target, log, items)
    extra = f" (ada {n} catatan serupa; yang terbaru yang diubah)" if n > 1 and not c.match_text else ""

    if c.action == "delete":
        log_id = str(log.id)
        await delete_log(session, log)
        await refresh_after_change(session, user_id)
        return CorrectionResult(True, f"Catatan {c.target} '{title}' pukul {at} sudah DIHAPUS atas permintaan pengguna{extra}. "
                                      "Konfirmasi singkat; jangan mencatat apa pun yang baru.", log_id)

    changes: list[str] = []
    try:
        if c.target == "meal":
            if c.replacement_items:
                await replace_meal(session, log, c.replacement_items)
                changes.append("isi makanan diganti")
            if c.portion_scale is not None:
                await edit_meal_items(session, log, scale=c.portion_scale)
                changes.append(f"porsi dikali {c.portion_scale:g}")
            if c.meal_time:
                set_meal_slot(log, c.meal_time)
                changes.append(f"dicatat sebagai {SLOT_LABELS[c.meal_time]}")
        elif c.target == "drink":
            count = c.count
            if count is None and c.portion_scale is not None:
                count = float((log.extracted or {}).get("count", 1) or 1) * c.portion_scale
            if count is not None:
                await set_drink_count(session, log, count)
                changes.append(f"jumlah minuman menjadi {count:g}")
        else:
            update_fields(log, minutes=c.minutes, hours=c.hours, bed_time=c.bed_time, wake_time=c.wake_time)
            if any(v is not None for v in (c.minutes, c.hours, c.bed_time, c.wake_time)):
                changes.append("isi catatan diperbarui")
    except EditError as exc:
        return CorrectionResult(False, str(exc))
    if not changes:
        return CorrectionResult(False, "Pesan ini terdengar seperti koreksi tetapi tidak jelas apa yang diubah. "
                                       "Tanyakan apa yang ingin diubah.")
    log.corrected = True
    await refresh_after_change(session, user_id)
    return CorrectionResult(True, f"Catatan {c.target} '{title}' pukul {at}{extra} DIKOREKSI ({'; '.join(changes)}). "
                                  "Jangan mencatat entri baru; konfirmasi singkat apa yang berubah.", str(log.id))
