from app.services import llm, stt
from tests.graph.fakes import FakeChatModel, FakeExtractModel, ai

RAKA = {
    "items": [{"name": "rendang", "portion_text": "1 potong", "portion_g_guess": 70, "meal_time": "lunch"}],
    "drinks": [{"name": "es teh manis", "size": "gelas", "count": 1}],
    "sleep": {"bed_time": "02:00", "wake_time": "07:00"},
    "activity": [],
    "clinical_result": None,
    "intent": "log",
}


def install_models(reply="Sip, sudah kucatat.", extract=RAKA, extract_error=None):
    chat = FakeChatModel(responses=[ai(reply)])
    ext = FakeExtractModel(extract, extract_error)
    llm.set_models_for_tests(chat, ext)
    return chat, ext


def reset_models():
    llm.set_models_for_tests(None, None)
    stt.set_stt_for_tests(None)


class FakeStt:
    def __init__(self, text="tadi makan nasi padang", error: Exception | None = None):
        self.text, self.error, self.calls = text, error, 0

    async def transcribe(self, audio: bytes, filename: str) -> str:
        self.calls += 1
        if self.error:
            raise self.error
        return self.text


PROFILE_RAKA = {
    "birth_date": "1998-03-14", "sex": "male", "height_cm": 170, "weight_kg": 78,
    "family_history_diabetes": "first_degree", "on_bp_medication": False,
    "usual_active_30min": False, "usual_veg_fruit": True,
}


async def complete_profile(client, headers, **overrides):
    resp = await client.put("/profile", json={**PROFILE_RAKA, **overrides}, headers=headers)
    assert resp.status_code == 200, resp.text
