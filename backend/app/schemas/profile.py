from datetime import date
from typing import Literal

from pydantic import BaseModel, Field

Sex = Literal["male", "female"]
FamilyHistory = Literal["none", "second_degree", "first_degree"]


class ProfileIn(BaseModel):
    display_name: str | None = Field(default=None, max_length=60)
    birth_date: date | None = None
    sex: Sex | None = None
    height_cm: float | None = Field(default=None, ge=50, le=260)
    weight_kg: float | None = Field(default=None, ge=20, le=400)
    waist_cm: float | None = Field(default=None, ge=30, le=250)
    family_history_diabetes: FamilyHistory | None = None
    parent_hypertension: bool | None = None
    smoker: bool | None = None
    on_bp_medication: bool | None = None
    history_high_glucose: bool | None = None
    usual_active_30min: bool | None = None
    usual_veg_fruit: bool | None = None
    food_preferences: dict | None = None


class ProfileOut(ProfileIn):
    username: str | None = None
    consented: bool = False  # sudah menyetujui versi teks persetujuan yang berlaku
    mode: str = "prevention"
    age: int | None = None
