from typing import Literal

from pydantic import BaseModel, Field, field_validator

TimeStr = Field(default=None, pattern=r"^([01]\d|2[0-3]):[0-5]\d$")


MAX_COMPONENTS = 8


class ComponentGuess(BaseModel):
    """Komponen hidangan yang tidak ada di katalog, dipecah oleh model. Model TIDAK mengisi angka gizi."""

    name: str = Field(min_length=1)
    food_id: str | None = None  # hanya dari katalog; id lain dibuang server
    portion_g_guess: float | None = Field(default=None, gt=0, le=2000)


class FoodItem(BaseModel):
    name: str = Field(min_length=1)
    portion_text: str | None = None
    portion_g_guess: float | None = Field(default=None, gt=0, le=5000)
    meal_time: Literal["breakfast", "lunch", "dinner", "snack"] | None = None
    dish_id: str | None = None  # hidangan dari katalog (dipecah server menjadi komponen)
    food_id: str | None = None  # makanan tunggal dari katalog
    components: list[ComponentGuess] = []

    @field_validator("components")
    @classmethod
    def _cap_components(cls, v: list[ComponentGuess]) -> list[ComponentGuess]:
        return v[:MAX_COMPONENTS]  # dipotong, bukan ditolak: satu komponen berlebih tidak boleh menggagalkan ekstraksi


class DrinkItem(BaseModel):
    name: str = Field(min_length=1)
    size: str | None = None
    count: float = Field(default=1, gt=0, le=50)


class SleepInfo(BaseModel):
    bed_time: str | None = TimeStr
    wake_time: str | None = TimeStr
    hours: float | None = Field(default=None, gt=0, le=24)  # "tidur cuma 5 jam" tanpa jam tidur/bangun


class ActivityItem(BaseModel):
    kind: str = Field(min_length=1)
    minutes: int = Field(ge=0, le=1440)


class ClinicalResultExtract(BaseModel):
    kind: Literal["fasting_glucose", "random_glucose", "blood_pressure", "hba1c", "waist", "resting_heart_rate"]
    # glukosa: {"mg_dl": 110}; tensi: {"sys": 135, "dia": 85, "pulse": 72 (opsional)}; hba1c: {"percent": 5.8};
    # waist: {"cm": 92}; detak jantung istirahat: {"bpm": 72}
    value: dict[str, float]


class LabelExtract(BaseModel):
    """Isi tabel informasi nilai gizi di kemasan, persis seperti tercetak (tanpa menebak)."""

    product_name: str = Field(min_length=1)
    is_drink: bool = False
    basis: Literal["per_serving", "per_100g"] = "per_serving"
    serving_g: float | None = Field(default=None, gt=0, le=5000)  # takaran saji (g atau ml)
    servings_consumed: float = Field(default=1, gt=0, le=50)
    sugar_g: float | None = Field(default=None, ge=0)
    sodium_mg: float | None = Field(default=None, ge=0)
    fat_g: float | None = Field(default=None, ge=0)
    kcal: float | None = Field(default=None, ge=0)


class LogCorrection(BaseModel):
    """Pengguna mengoreksi atau membatalkan catatan sebelumnya ("ralat, tadi cuma setengah porsi", "itu makan siang,
    bukan selingan", "hapus yang tadi"). Tidak boleh dicatat sebagai entri baru: itu membuat catatan dobel."""

    action: Literal["update", "delete"] = "update"
    target: Literal["meal", "drink", "sleep", "activity"] = "meal"
    match_text: str | None = None  # nama makanan/minuman/aktivitas yang dimaksud; kosong = yang terbaru
    day: Literal["today", "yesterday"] = "today"
    # Perubahan (hanya yang disebut pengguna):
    portion_scale: float | None = Field(default=None, gt=0, le=10)  # "setengah porsi" 0.5, "dua kali lipat" 2
    meal_time: Literal["breakfast", "lunch", "dinner", "snack"] | None = None
    replacement_items: list[FoodItem] = []  # "bukan nasi goreng, tapi mie goreng"
    minutes: int | None = Field(default=None, ge=0, le=1440)
    hours: float | None = Field(default=None, gt=0, le=24)
    bed_time: str | None = TimeStr
    wake_time: str | None = TimeStr
    count: float | None = Field(default=None, gt=0, le=50)


class RecordValue(BaseModel):
    name: str = Field(min_length=1, max_length=80)  # "Kolesterol total"
    value: str = Field(min_length=1, max_length=40)  # "210" (disalin apa adanya)
    unit: str | None = Field(default=None, max_length=20)  # "mg/dL"


class MedicalRecordExtract(BaseModel):
    """Riwayat medis yang diceritakan pengguna (bukan makan/minum/tidur/olahraga): diagnosis, hasil lab, obat yang
    sedang dipakai, alergi, tindakan, vaksin, kunjungan. Hanya menyalin yang disebut; tidak menilai."""

    kind: Literal["diagnosis", "lab", "medication", "allergy", "procedure", "vaccination", "imaging", "visit", "other"]
    title: str = Field(min_length=1, max_length=120)
    recorded_on: str | None = Field(default=None, pattern=r"^\d{4}-\d{2}-\d{2}$")  # YYYY-MM-DD bila disebut
    provider: str | None = Field(default=None, max_length=120)
    details: str | None = Field(default=None, max_length=1000)
    values: list[RecordValue] = []


class Extraction(BaseModel):
    items: list[FoodItem] = []
    drinks: list[DrinkItem] = []
    sleep: SleepInfo | None = None
    activity: list[ActivityItem] = []
    clinical_result: ClinicalResultExtract | None = None
    label: LabelExtract | None = None
    correction: LogCorrection | None = None
    medical_record: MedicalRecordExtract | None = None
    intent: Literal["log", "question_portion", "question_general", "result_input", "correction", "medical_record"] = "log"
    summary: str | None = None
