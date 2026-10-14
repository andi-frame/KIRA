"""Model palsu untuk tes: tidak ada panggilan jaringan, semua deterministik."""
from typing import Any

from langchain_core.language_models.chat_models import BaseChatModel
from langchain_core.messages import AIMessage, BaseMessage
from langchain_core.outputs import ChatGeneration, ChatResult
from langchain_core.runnables import RunnableLambda


class FakeChatModel(BaseChatModel):
    """Mengembalikan pesan terjadwal berurutan; setelah habis mengulang pesan terakhir."""

    responses: list[BaseMessage]
    call_count: int = 0
    seen: list[list[BaseMessage]] = []

    @property
    def _llm_type(self) -> str:
        return "fake-kira"

    def bind_tools(self, tools: Any, **kwargs: Any) -> "FakeChatModel":
        return self

    def _generate(self, messages: list[BaseMessage], stop=None, run_manager=None, **kwargs: Any) -> ChatResult:
        index = min(self.call_count, len(self.responses) - 1)
        self.call_count += 1
        self.seen.append(list(messages))
        # id unik per panggilan, seperti model sungguhan (add_messages menimpa pesan ber-id sama)
        message = self.responses[index].model_copy(update={"id": f"fake-{self.call_count}"})
        return ChatResult(generations=[ChatGeneration(message=message)])


def ai(text: str = "", tool_calls: list[dict] | None = None) -> AIMessage:
    return AIMessage(content=text, tool_calls=tool_calls or [])


class FakeExtractModel:
    """Pengganti model ekstraksi: with_structured_output(...) mengembalikan runnable terjadwal."""

    def __init__(self, result: Any = None, error: Exception | None = None):
        self.result = result
        self.error = error
        self.calls: list[list[BaseMessage]] = []

    def with_structured_output(self, schema: Any, **kwargs: Any) -> RunnableLambda:
        def run(messages: list[BaseMessage]) -> Any:
            self.calls.append(list(messages))
            if self.error:
                raise self.error
            return self.result

        return RunnableLambda(run)
