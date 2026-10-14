from typing import Literal

from pydantic import BaseModel, Field

TimeStr = Field(default=None, pattern=r"^([01]\d|2[0-3]):[0-5]\d$")


class FoodItem(BaseModel):
    name: str = Field(min_length=1)
    portion_text: str | None = None
    portion_g_guess: float | None = Field(default=None, gt=0, le=5000)
    meal_time: Literal["breakfast", "lunch", "dinner", "snack"] | None = None


class DrinkItem(BaseModel):
    name: str = Field(min_length=1)
    size: str | None = None
    count: float = Field(default=1, gt=0, le=50)


class SleepInfo(BaseModel):
    bed_time: str | None = TimeStr
    wake_time: str | None = TimeStr


class ActivityItem(BaseModel):
    kind: str = Field(min_length=1)
    minutes: int = Field(ge=0, le=1440)


class ClinicalResultExtract(BaseModel):
    kind: Literal["fasting_glucose", "random_glucose", "blood_pressure", "hba1c", "waist"]
    # glukosa: {"mg_dl": 110}; tensi: {"sys": 135, "dia": 85}; hba1c: {"percent": 5.8}; waist: {"cm": 92}
    value: dict[str, float]


class Extraction(BaseModel):
    items: list[FoodItem] = []
    drinks: list[DrinkItem] = []
    sleep: SleepInfo | None = None
    activity: list[ActivityItem] = []
    clinical_result: ClinicalResultExtract | None = None
    intent: Literal["log", "question_portion", "question_general", "result_input"] = "log"
    summary: str | None = None
