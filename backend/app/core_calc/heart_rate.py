"""Detak jantung istirahat (kali per menit). Fungsi murni.

Rentang normal dewasa saat istirahat 60-100 kali/menit (American Heart Association; Mayo Clinic "Heart rate: What's normal?").
Di bawah 60 sering wajar pada orang yang rutin berolahraga; bila bukan atlet dan sering di bawah 60, atau di atas 100 saat benar-benar
istirahat, bahas dengan tenaga kesehatan. Ini penanda kebiasaan untuk dibawa ke dokter, bukan diagnosis.

Batas 25-250 hanya penyaring salah ketik (di luar itu hampir pasti salah angka), bukan batas klinis.
"""
RESTING_LOW = 60
RESTING_HIGH = 100
SANITY_MIN = 25
SANITY_MAX = 250

SOURCE = "American Heart Association dan Mayo Clinic: detak jantung istirahat dewasa 60-100 kali per menit"


def validate_bpm(bpm: float) -> int:
    """Bulatkan ke bilangan bulat; ValueError bila mustahil (salah ketik)."""
    if not SANITY_MIN <= bpm <= SANITY_MAX:
        raise ValueError("detak jantung tidak masuk akal")
    return round(bpm)


def classify_resting(bpm: float) -> str:
    """below_range (< 60) | normal_range (60-100) | above_range (> 100)."""
    if bpm < RESTING_LOW:
        return "below_range"
    return "above_range" if bpm > RESTING_HIGH else "normal_range"
