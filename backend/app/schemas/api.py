from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, Field, field_validator, model_validator

from app.schemas.extraction import Extraction


class ChatIn(BaseModel):
    text: str

    @field_validator("text")
    @classmethod
    def not_blank(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("pesan tidak boleh kosong")
        return v.strip()


class ChatOut(BaseModel):
    reply: str
    extraction: Extraction | None = None
    red_flag: str | None = None
    log_ids: list[str] = []
    tool_calls: list[dict] = []
    transcript: str | None = None
    meals: list["LogOut"] = []  # catatan makan dari pesan ini beserta item, gizi, dan kelompok hidangan (kartu koreksi)


class WhatIfIn(BaseModel):
    active_30min: bool | None = None
    daily_veg_fruit: bool | None = None
    weight_delta_kg: float | None = Field(default=None, ge=-60, le=60)
    sweet_drinks_delta_per_day: float = Field(default=0.0, ge=-20, le=20)


class ScenarioIn(WhatIfIn):
    name: str = Field(min_length=1, max_length=40)

    @field_validator("name")
    @classmethod
    def _clean(cls, v: str) -> str:
        v = " ".join(v.split())
        if not v:
            raise ValueError("nama tidak boleh kosong")
        return v


class ResultIn(BaseModel):
    kind: Literal["fasting_glucose", "random_glucose", "blood_pressure", "hba1c", "waist"]
    value: dict[str, float]
    measured_at: datetime | None = None
    source: Literal["ckg", "lab", "self"] = "self"


class DiagnosisIn(BaseModel):
    condition: Literal["diabetes", "prediabetes", "hypertension"]
    diagnosed_at: date | None = None
    confirmed_by: str | None = Field(default=None, max_length=80)


class ItemPatch(BaseModel):
    name: str = Field(min_length=1)
    portion_g: float | None = Field(default=None, gt=0, le=5000)
    food_id: str | None = None  # komponen yang sudah dikenali: tetap dihitung dari makanan yang sama
    group: str | None = Field(default=None, max_length=120)  # hidangan induk (komponen tetap terkelompok)


class LogPatch(BaseModel):
    """Ubah satu catatan. Makan/minum: ganti isi (item yang tidak dikirim = dihapus, mis. "tanpa nasi"), skalakan porsi
    (`scale`, dibatasi `group` untuk satu hidangan), atau `half` (saklar "setengah porsi": true = jadikan setengah, false =
    kembalikan; mengulang perintah yang sama tidak menurunkan angka lagi). `meal_slot` mengubah waktu makan.
    Aktivitas/tidur: `minutes`, `activity_kind`, `hours`, `bed_time`, `wake_time`. Minuman: `count`. `occurred_at` memindahkan waktunya."""

    items: list[ItemPatch] | None = None
    scale: float | None = Field(default=None, gt=0, le=10)
    group: str | None = Field(default=None, max_length=120)
    half: bool | None = None
    meal_slot: Literal["breakfast", "lunch", "dinner", "snack"] | None = None
    minutes: int | None = Field(default=None, ge=0, le=1440)
    activity_kind: str | None = Field(default=None, min_length=1, max_length=60)
    hours: float | None = Field(default=None, gt=0, le=24)
    bed_time: str | None = Field(default=None, pattern=r"^([01]\d|2[0-3]):[0-5]\d$")
    wake_time: str | None = Field(default=None, pattern=r"^([01]\d|2[0-3]):[0-5]\d$")
    count: float | None = Field(default=None, gt=0, le=50)
    occurred_at: datetime | None = None

    @model_validator(mode="after")
    def _something_to_do(self) -> "LogPatch":
        fields = (self.items, self.scale, self.half, self.meal_slot, self.minutes, self.activity_kind, self.hours,
                  self.bed_time, self.wake_time, self.count, self.occurred_at)
        if all(v is None for v in fields):
            raise ValueError("tidak ada yang diubah")
        return self


class LogItemOut(BaseModel):
    id: str
    name: str
    portion_g: float | None
    sugar_g: float | None
    sodium_mg: float | None
    fat_g: float | None
    kcal: float | None
    food_id: str | None = None
    group: str | None = None


class LogOut(BaseModel):
    id: str
    kind: str
    source: str
    occurred_at: datetime
    raw_text: str | None
    extracted: dict
    corrected: bool
    items: list[LogItemOut]
    meal_slot: str | None = None
    slot_confirmed: bool = True  # false: waktu makan hanya ditebak dari jam; aplikasi menawarkan pilihan
    halved_groups: list[str] = []  # hidangan yang sedang "setengah porsi" (tombolnya menjadi "Porsi biasa")


class CheckRespondIn(BaseModel):
    action: Literal["done", "snooze", "dismiss"]


ChatOut.model_rebuild()
