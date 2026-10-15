from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, Field, field_validator

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


class WhatIfIn(BaseModel):
    active_30min: bool | None = None
    daily_veg_fruit: bool | None = None
    weight_delta_kg: float | None = Field(default=None, ge=-60, le=60)
    sweet_drinks_delta_per_day: float = Field(default=0.0, ge=-20, le=20)


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


class LogPatch(BaseModel):
    items: list[ItemPatch]


class LogItemOut(BaseModel):
    id: str
    name: str
    portion_g: float | None
    sugar_g: float | None
    sodium_mg: float | None
    fat_g: float | None
    kcal: float | None


class LogOut(BaseModel):
    id: str
    kind: str
    source: str
    occurred_at: datetime
    raw_text: str | None
    extracted: dict
    corrected: bool
    items: list[LogItemOut]


class CheckRespondIn(BaseModel):
    action: Literal["done", "snooze", "dismiss"]
