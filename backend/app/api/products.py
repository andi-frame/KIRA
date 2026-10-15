"""Kode batang kemasan: cari gizinya, lalu catat sesuai porsi yang dimakan."""
import uuid

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, model_validator
from sqlalchemy.ext.asyncio import AsyncSession

from app.core_calc.label import LabelFacts, label_totals
from app.db import get_session
from app.repos import logs as logs_repo
from app.repos.logs import ItemData
from app.security import current_user_id
from app.services import barcode, risk
from app.timeutil import utcnow

router = APIRouter(tags=["products"])
NOT_FOUND = "Produk ini belum ada di basis data. Coba foto tabel nilai gizi di kemasannya."


class BarcodeLogIn(BaseModel):
    barcode: str
    grams: float | None = Field(default=None, gt=0, le=5000)
    servings: float | None = Field(default=None, gt=0, le=50)

    @model_validator(mode="after")
    def _one_amount(self) -> "BarcodeLogIn":
        if (self.grams is None) == (self.servings is None):
            raise ValueError("isi salah satu: grams atau servings")
        return self


def _product_out(p: barcode.ProductData) -> dict:
    return {
        "barcode": p.barcode,
        "name": p.name,
        "brand": p.brand,
        "serving_g": p.serving_g,
        "is_drink": p.is_drink,
        "per100g": p.per100g,
        "complete": p.complete,
        "source": barcode.SOURCE_NOTE,
    }


async def _find(session: AsyncSession, code: str) -> barcode.ProductData:
    if not barcode.valid_gtin(code):
        raise HTTPException(422, "Kode batang tidak valid. Periksa angkanya, atau pindai ulang.")
    try:
        product = await barcode.lookup(session, code)
    except barcode.ProductLookupError as exc:
        raise HTTPException(503, str(exc)) from None
    if product is None:
        raise HTTPException(404, NOT_FOUND)
    return product


@router.get("/products/{code}")
async def get_product(
    code: str, _: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)
) -> dict:
    return _product_out(await _find(session, code))


@router.post("/logs/barcode")
async def log_barcode(
    body: BarcodeLogIn, user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)
) -> dict:
    """Mencatat produk sesuai jumlah yang dimakan. Perhitungan memakai `core_calc.label` yang sama dengan foto label."""
    product = await _find(session, body.barcode)
    if not product.complete:
        raise HTTPException(422, "Data gizi produk ini belum lengkap di basis data. Coba foto label kemasannya.")
    if body.servings is not None and product.serving_g is None:
        raise HTTPException(422, "Takaran saji produk ini tidak diketahui. Isi porsinya dalam gram.")
    facts = LabelFacts(
        basis="per_100g",
        serving_g=body.grams if body.grams is not None else product.serving_g,
        servings_consumed=1.0 if body.grams is not None else body.servings,
        **product.per100g,
    )
    try:
        totals = label_totals(facts)
    except ValueError:
        raise HTTPException(422, "Angka gizi produk ini tampak tidak masuk akal. Coba foto label kemasannya.") from None

    kind = "drink" if product.is_drink else "meal"
    extracted: dict = {"barcode": product.barcode, "source_note": barcode.SOURCE_NOTE}
    if product.is_drink:
        extracted.update({"name": product.name, "size": None, "count": 1})
    else:
        extracted["items"] = [{"name": product.name}]
    item = ItemData(
        name=product.name, portion_g=totals["portion_g"], sugar_g=totals["sugar_g"], sodium_mg=totals["sodium_mg"],
        fat_g=totals["fat_g"], kcal=totals["kcal"],
    )
    log = await logs_repo.add_log(
        session, user_id, kind=kind, source="barcode", occurred_at=utcnow(), extracted=extracted,
        raw_text=None, items=[item], commit=False,
    )
    state = await risk.compute_risk_state(session, user_id)
    await risk.save_snapshot(session, user_id, state, commit=False)
    await risk.refresh_check_recommendation(session, user_id, state, commit=False)
    await session.commit()
    return {"log_id": str(log.id), "kind": kind, "item": {"name": item.name, **{k: totals[k] for k in totals}},
            "source": barcode.SOURCE_NOTE}
