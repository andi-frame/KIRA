"""Proyeksi "kalau kebiasaanmu tetap": dihitung langsung dari catatan 14 hari terakhir, sehingga ikut berubah saat catatan
diubah, dan menjelaskan dasar perhitungannya."""
from datetime import datetime, timedelta, timezone

from app.repos import logs as logs_repo
from app.services import log_edit
from app.services.projection_view import projection_payload
from app.services.risk import compute_risk_state

BASE = dict(birth_date="1990-03-14", sex="male", height_cm=170, weight_kg=70, waist_cm=85,
            family_history_diabetes="none", on_bp_medication=False, history_high_glucose=False,
            usual_veg_fruit=False, usual_active_30min=False)


def days_ago(n: int) -> datetime:
    return datetime.now(timezone.utc) - timedelta(days=n)


async def add_activity(session, uid, n: int, minutes: int):
    return await logs_repo.add_log(session, uid, kind="activity", source="text", occurred_at=days_ago(n),
                                   extracted={"kind": "jalan", "minutes": minutes}, raw_text=None, items=[], commit=False)


async def test_sayur_dari_komponen_hidangan_ikut_dihitung(session_maker, make_user):
    uid = await make_user(**BASE)
    async with session_maker() as session:
        for n in range(4):  # gado-gado dipecah menjadi tauge, kol, timun, dst.: bukan food_id "gado_gado"
            await logs_repo.add_log(session, uid, kind="meal", source="text", occurred_at=days_ago(n), extracted={}, raw_text=None,
                                    items=[logs_repo.ItemData(name="tauge", food_id="tauge", kcal=30, group_name="Gado-gado"),
                                           logs_repo.ItemData(name="nasi putih", food_id="nasi_putih", kcal=200)], commit=False)
        await session.commit()
        state = await compute_risk_state(session, uid)
    assert state.inputs.daily_veg_fruit is True
    assert state.basis["veg_fruit"]["source"] == "log" and state.basis["veg_fruit"]["days_with"] == 4


async def test_proyeksi_mengikuti_penghapusan_catatan_aktivitas(session_maker, make_user):
    uid = await make_user(**BASE)
    async with session_maker() as session:
        logs = [await add_activity(session, uid, n, 60) for n in range(4)]
        await session.commit()
        before = await compute_risk_state(session, uid)
        assert before.inputs.active_30min is True and before.basis["activity"]["source"] == "log"
        for lg in logs:
            await log_edit.delete_log(session, lg)
        await log_edit.refresh_after_change(session, uid)
        await session.commit()
        after = await compute_risk_state(session, uid)
    assert after.inputs.active_30min is False  # kembali ke jawaban profil: tidak tertahan pada versi sebelum penghapusan
    assert after.basis["activity"]["source"] == "profile"
    assert after.rng.high >= before.rng.high


async def test_dasar_perhitungan_menyebut_apa_yang_belum_diketahui(session_maker, make_user):
    uid = await make_user(birth_date="1990-03-14", sex="male")
    async with session_maker() as session:
        payload = projection_payload(await compute_risk_state(session, uid))
    basis = payload["basis"]
    assert basis["window_days"] == 14 and basis["activity"]["source"] == "unknown"
    assert "berat/tinggi badan" in basis["unknown"] and basis["computed_at"]
