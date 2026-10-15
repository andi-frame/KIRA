"""Target mingguan pribadi dan kemajuannya. Fungsi murni.

Tiap target dinilai pada satu minggu (Senin sampai Minggu, WIB) dari catatan pengguna sendiri. Tidak ada "streak" yang
menghukum hari terlewat: yang ditampilkan hanya kemajuan minggu ini dan berapa dari empat minggu terakhir tercapai.

Angka bawaan:
- Aktif 150 menit/minggu: WHO 2020 Guidelines on physical activity and sedentary behaviour (dewasa: minimal 150 menit
  aktivitas intensitas sedang per minggu). Pengguna boleh mengubahnya.
- Tidur >= 7 jam: konsensus AASM/SRS (Watson dkk., J Clin Sleep Med 2015;11:591). Jumlah malamnya (5) keputusan KIRA.
- Minuman manis <= 7 per minggu (rata-rata 1 per hari) dan hari mencatat >= 5: keputusan KIRA, bukan angka klinis.
"""
from dataclasses import dataclass

SLEEP_TARGET_HOURS = 7.0

# kind -> (arah, bawaan, minimum, maksimum, satuan, kunci di deret harian)
GOAL_KINDS: dict[str, dict] = {
    "active_minutes_week": {
        "direction": "min", "default": 150, "lo": 30, "hi": 600, "unit": "menit", "label": "Bergerak minggu ini", "series_key": "active_minutes",
    },
    "sweet_drinks_week": {
        "direction": "max", "default": 7, "lo": 0, "hi": 28, "unit": "gelas", "label": "Minuman manis minggu ini", "series_key": "sweet_drinks",
    },
    "sleep_nights": {
        "direction": "min", "default": 5, "lo": 1, "hi": 7, "unit": "malam", "label": "Malam tidur 7 jam atau lebih", "series_key": "sleep_hours",
    },
    "logging_days": {
        "direction": "min", "default": 5, "lo": 1, "hi": 7, "unit": "hari", "label": "Hari mencatat", "series_key": "logged",
    },
}


@dataclass(frozen=True)
class Progress:
    kind: str
    target: float
    current: float
    direction: str  # min (capai/lewati) | max (jangan lewati)
    met: bool  # min: current >= target; max: current <= target
    status: str  # met | in_progress (min) | within (max) | over (max)
    remaining: float  # min: sisa menuju target; max: sisa ruang sebelum melewati batas

    @property
    def fraction(self) -> float:
        """Untuk bilah kemajuan 0..1. Target maks nol dianggap penuh bila belum ada yang tercatat."""
        if self.target <= 0:
            return 1.0 if self.current <= 0 else 0.0
        return max(0.0, min(1.0, self.current / self.target))


def validate_target(kind: str, target: float) -> float:
    spec = GOAL_KINDS.get(kind)
    if spec is None:
        raise ValueError(f"jenis target tidak dikenal: {kind}")
    if not spec["lo"] <= target <= spec["hi"]:
        raise ValueError(f"target {spec['label'].lower()} harus {spec['lo']}-{spec['hi']} {spec['unit']}")
    return float(target)


def current_value(kind: str, week_days: list[dict]) -> float:
    """Nilai minggu ini dari deret harian (satu entri per hari, tanggal berurutan)."""
    key = GOAL_KINDS[kind]["series_key"]
    if kind == "sleep_nights":
        return float(sum(1 for d in week_days if d.get("sleep_hours") is not None and d["sleep_hours"] >= SLEEP_TARGET_HOURS))
    if kind == "logging_days":
        return float(sum(1 for d in week_days if d.get("logged")))
    return round(sum(float(d[key]) for d in week_days if d.get(key) is not None), 1)


def evaluate(kind: str, target: float, week_days: list[dict]) -> Progress:
    spec = GOAL_KINDS[kind]
    current = current_value(kind, week_days)
    if spec["direction"] == "min":
        met = current >= target
        return Progress(kind, target, current, "min", met, "met" if met else "in_progress", max(0.0, round(target - current, 1)))
    met = current <= target
    return Progress(kind, target, current, "max", met, "within" if met else "over", max(0.0, round(target - current, 1)))
