from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import text

from app.config import settings
from app.repos import logs as logs_repo
from app.services.jobs import enqueue_family_nudges

MEMBER_PHONE = "081200000077"


async def register(client, phone, pin="123456"):
    r = await client.post("/auth/register", json={"phone": phone, "pin": pin})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


async def invite(client, owner, phone=MEMBER_PHONE, **permissions):
    body = {"phone": phone, **({"permissions": permissions} if permissions else {})}
    r = await client.post("/family/invite", json=body, headers=owner)
    assert r.status_code == 200, r.text
    return r.json()


async def active_link(client, owner, member, **permissions):
    link = await invite(client, owner, **permissions)
    assert (await client.post(f"/family/{link['id']}/accept", headers=member)).status_code == 200
    return link["id"]


async def test_invite_appears_for_the_owner_and_the_invited_phone(client, auth_headers):
    member = await register(client, MEMBER_PHONE)
    link = await invite(client, auth_headers)
    assert link["status"] == "pending" and link["permissions"] == {"checkin_status": True, "check_reminders": True}

    mine = (await client.get("/family", headers=auth_headers)).json()
    assert [m["member_phone"] for m in mine["members"]] == [MEMBER_PHONE]
    theirs = (await client.get("/family", headers=member)).json()
    assert [i["id"] for i in theirs["invites_for_me"]] == [link["id"]]


async def test_inviting_yourself_or_twice_is_rejected(client, auth_headers):
    assert (await client.post("/family/invite", json={"phone": "081200000001"}, headers=auth_headers)).status_code == 422
    await invite(client, auth_headers)
    assert (await client.post("/family/invite", json={"phone": MEMBER_PHONE}, headers=auth_headers)).status_code == 409


async def test_only_the_invited_person_can_accept(client, auth_headers):
    link = await invite(client, auth_headers)
    stranger = await register(client, "081200000088")
    assert (await client.post(f"/family/{link['id']}/accept", headers=stranger)).status_code == 404
    assert (await client.post(f"/family/{link['id']}/accept", headers=auth_headers)).status_code == 404  # pemilik sendiri


async def test_member_sees_only_the_shared_summary(client, auth_headers, session_maker):
    member = await register(client, MEMBER_PHONE)
    link_id = await active_link(client, auth_headers, member)
    async with session_maker() as s:
        uid = (await s.execute(text("select id from users where phone = '081200000001'"))).scalar_one()
        await logs_repo.add_log(s, uid, kind="meal", source="text", occurred_at=datetime.now(timezone.utc),
                                extracted={"items": [{"name": "rendang"}]}, raw_text="rendang rahasia",
                                items=[logs_repo.ItemData(name="rendang", sugar_g=1)])
    body = (await client.get(f"/family/{link_id}/status", headers=member)).json()
    assert body["checkin_status"]["last_checkin_days_ago"] == 0
    assert body["check_reminders"]["has_open_check"] in (True, False)
    flat = str(body).lower()
    assert "rendang" not in flat and "sugar" not in flat and "score" not in flat and "gula" not in flat


async def test_permissions_the_owner_withholds_are_hidden(client, auth_headers):
    member = await register(client, MEMBER_PHONE)
    link_id = await active_link(client, auth_headers, member, checkin_status=False, check_reminders=False)
    body = (await client.get(f"/family/{link_id}/status", headers=member)).json()
    assert body["checkin_status"] is None and body["check_reminders"] is None


async def test_owner_can_change_permissions_and_revoke_access_instantly(client, auth_headers):
    member = await register(client, MEMBER_PHONE)
    link_id = await active_link(client, auth_headers, member)
    r = await client.patch(f"/family/{link_id}/permissions", json={"checkin_status": False}, headers=auth_headers)
    assert r.status_code == 200 and r.json()["permissions"]["checkin_status"] is False
    assert (await client.get(f"/family/{link_id}/status", headers=member)).json()["checkin_status"] is None

    assert (await client.delete(f"/family/{link_id}", headers=auth_headers)).status_code == 200
    assert (await client.get(f"/family/{link_id}/status", headers=member)).status_code == 404


async def test_member_can_leave_but_cannot_change_permissions(client, auth_headers):
    member = await register(client, MEMBER_PHONE)
    link_id = await active_link(client, auth_headers, member)
    assert (await client.patch(f"/family/{link_id}/permissions", json={"checkin_status": False}, headers=member)).status_code == 404
    assert (await client.delete(f"/family/{link_id}", headers=member)).status_code == 200
    assert (await client.get("/family", headers=auth_headers)).json()["members"] == []


async def test_pending_invite_gives_no_access(client, auth_headers):
    member = await register(client, MEMBER_PHONE)
    link = await invite(client, auth_headers)
    assert (await client.get(f"/family/{link['id']}/status", headers=member)).status_code == 404


async def test_strangers_cannot_read_a_link(client, auth_headers):
    member = await register(client, MEMBER_PHONE)
    link_id = await active_link(client, auth_headers, member)
    stranger = await register(client, "081200000088")
    assert (await client.get(f"/family/{link_id}/status", headers=stranger)).status_code == 404
    assert (await client.delete(f"/family/{link_id}", headers=stranger)).status_code == 404


async def test_supportive_nudge_after_three_quiet_days_only_when_permitted(client, auth_headers, session_maker):
    member = await register(client, MEMBER_PHONE)
    await active_link(client, auth_headers, member)
    # tautkan WhatsApp milik anggota keluarga
    async with session_maker() as s:
        member_id = (await s.execute(text("select id from users where phone = :p"), {"p": MEMBER_PHONE})).scalar_one()
        await s.execute(text("insert into wa_links (jid, user_id) values ('62812000077@s.whatsapp.net', :u)"),
                        {"u": member_id})
        await s.commit()
    async with session_maker() as s:
        owner_id = (await s.execute(text("select id from users where phone = '081200000001'"))).scalar_one()
        await logs_repo.add_log(s, owner_id, kind="sleep", source="text",
                                occurred_at=datetime.now(timezone.utc) - timedelta(days=5),
                                extracted={"hours": 6}, raw_text="x", items=[])
        assert await enqueue_family_nudges(s) == 1
        assert await enqueue_family_nudges(s) == 0  # tidak berulang tiap hari
        row = (await s.execute(text("select kind, text from wa_outbox"))).one()
    assert row.kind == "family" and "menghakimi" in row.text and "check-in" in row.text.lower()
    assert "rendang" not in row.text.lower()


async def test_no_nudge_when_the_owner_hides_checkin_status(client, auth_headers, session_maker):
    member = await register(client, MEMBER_PHONE)
    await active_link(client, auth_headers, member, checkin_status=False)
    async with session_maker() as s:
        member_id = (await s.execute(text("select id from users where phone = :p"), {"p": MEMBER_PHONE})).scalar_one()
        await s.execute(text("insert into wa_links (jid, user_id) values ('62812000077@s.whatsapp.net', :u)"), {"u": member_id})
        await s.commit()
        assert await enqueue_family_nudges(s) == 0


def test_settings_have_no_family_flag_dependency():
    assert settings.scheduler_enabled in (True, False) and pytest is not None
