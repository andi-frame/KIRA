from typing import Any

from langchain_anthropic import ChatAnthropic
from langchain_core.language_models.chat_models import BaseChatModel

from app.config import settings

_chat: BaseChatModel | None = None
_extract: Any | None = None


def get_chat_model() -> BaseChatModel:
    global _chat
    if _chat is None:
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
