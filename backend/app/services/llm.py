"""Pemilihan model bahasa. Graf hanya memakai get_chat_model() dan get_extract_model(); penyedianya bisa diganti lewat env.

- LLM_BASE_URL kosong: Anthropic langsung (ANTHROPIC_API_KEY).
- LLM_BASE_URL terisi: penyedia yang kompatibel OpenAI, mis. gerbang 9router (kunci: LLM_API_KEY atau 9ROUTER_API_KEY).

Angka risiko, gizi, dan target tidak pernah berasal dari model mana pun; model hanya membaca bahasa dan merangkai kalimat.
"""
from typing import Any

from langchain_anthropic import ChatAnthropic
from langchain_core.language_models.chat_models import BaseChatModel
from langchain_openai import ChatOpenAI

from app.config import settings

_chat: BaseChatModel | None = None
_extract: Any | None = None

# Model penalaran (mis. Gemini "high") menghabiskan token untuk berpikir sebelum menjawab: beri ruang lebih besar.
OPENAI_COMPAT_CHAT_TOKENS = 4000
OPENAI_COMPAT_EXTRACT_TOKENS = 6000
OPENAI_COMPAT_TIMEOUT = 90
# Sebagian gerbang menolak klien tanpa User-Agent.
_HEADERS = {"User-Agent": "KIRA/1.0 (+https://github.com/andi-frame/KIRA)"}


class _FunctionCallingModel:
    """Output terstruktur lewat function calling: didukung hampir semua gerbang, tidak seperti response_format json_schema."""

    def __init__(self, model: BaseChatModel):
        self._model = model

    def with_structured_output(self, schema: Any) -> Any:
        return self._model.with_structured_output(schema, method="function_calling")


def uses_openai_compatible() -> bool:
    return bool(settings.llm_base_url.strip())


def _openai_compatible(model: str, *, temperature: float, max_tokens: int) -> ChatOpenAI:
    return ChatOpenAI(
        model=model,
        base_url=settings.llm_base_url.strip(),
        api_key=settings.llm_api_key or "missing",
        temperature=temperature,
        max_tokens=max_tokens,
        timeout=OPENAI_COMPAT_TIMEOUT,
        default_headers=_HEADERS,
    )


def get_chat_model() -> BaseChatModel:
    global _chat
    if _chat is None:
        if uses_openai_compatible():
            _chat = _openai_compatible(settings.llm_model_chat, temperature=0.2, max_tokens=OPENAI_COMPAT_CHAT_TOKENS)
        else:
            _chat = ChatAnthropic(
                model=settings.llm_model_chat,
                api_key=settings.anthropic_api_key or "missing",
                temperature=0.2,
                max_tokens=700,
                timeout=30,
            )
    return _chat


def get_extract_model() -> Any:
    """Model untuk structured output (punya with_structured_output)."""
    global _extract
    if _extract is None:
        if uses_openai_compatible():
            _extract = _FunctionCallingModel(
                _openai_compatible(settings.llm_model_extract, temperature=0, max_tokens=OPENAI_COMPAT_EXTRACT_TOKENS)
            )
        else:
            _extract = ChatAnthropic(
                model=settings.llm_model_extract,
                api_key=settings.anthropic_api_key or "missing",
                temperature=0,
                max_tokens=1200,
                timeout=30,
            )
    return _extract


def set_models_for_tests(chat: BaseChatModel | None, extract: Any | None) -> None:
    global _chat, _extract
    _chat, _extract = chat, extract
