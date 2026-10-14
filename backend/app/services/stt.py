from typing import Protocol

import httpx

from app.config import settings


class SttError(Exception):
    """Transkripsi suara gagal."""


class SttService(Protocol):
    async def transcribe(self, audio: bytes, filename: str) -> str: ...


class OpenAICompatibleStt:
    """STT lewat endpoint /audio/transcriptions bergaya OpenAI (Groq, OpenAI, dan sejenisnya)."""

    def __init__(
        self,
        base_url: str,
        api_key: str,
        model: str,
        transport: httpx.AsyncBaseTransport | None = None,
    ):
        self._base_url = base_url.rstrip("/")
        self._api_key = api_key
        self._model = model
        self._transport = transport

    async def transcribe(self, audio: bytes, filename: str) -> str:
        try:
            async with httpx.AsyncClient(transport=self._transport, timeout=30) as client:
                resp = await client.post(
                    f"{self._base_url}/audio/transcriptions",
                    headers={"Authorization": f"Bearer {self._api_key}"},
                    files={"file": (filename, audio)},
                    data={"model": self._model, "language": "id", "response_format": "json"},
                )
            resp.raise_for_status()
            return str(resp.json().get("text", "")).strip()
        except (httpx.HTTPError, ValueError) as exc:
            raise SttError("transkripsi suara gagal") from exc


_override: SttService | None = None


def get_stt() -> SttService:
    return _override or OpenAICompatibleStt(settings.stt_base_url, settings.stt_api_key, settings.stt_model)


def set_stt_for_tests(service: SttService | None) -> None:
    global _override
    _override = service
