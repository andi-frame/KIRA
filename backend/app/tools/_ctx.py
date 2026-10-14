import uuid

from langchain_core.runnables import RunnableConfig


def ctx(config: RunnableConfig):
    """user_id dan session_factory selalu dari config graf, tidak pernah dari argumen yang diisi LLM."""
    configurable = (config or {}).get("configurable", {})
    return uuid.UUID(str(configurable["user_id"])), configurable["session_factory"]
