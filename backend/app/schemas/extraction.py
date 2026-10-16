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
    kind: Literal["fasting_glucose", "random_glucose", "blood_pressure", "hba1c", "waist"]
    # glukosa: {"mg_dl": 110}; tensi: {"sys": 135, "dia": 85}; hba1c: {"percent": 5.8}; waist: {"cm": 92}
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


class Extraction(BaseModel):
    items: list[FoodItem] = []
    drinks: list[DrinkItem] = []
    sleep: SleepInfo | None = None
    activity: list[ActivityItem] = []
    clinical_result: ClinicalResultExtract | None = None
    label: LabelExtract | None = None
    intent: Literal["log", "question_portion", "question_general", "result_input"] = "log"
    summary: str | None = None
