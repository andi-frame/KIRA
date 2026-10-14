from typing import Annotated, TypedDict

from langgraph.graph.message import add_messages


class KiraState(TypedDict, total=False):
    user_id: str
    channel: str  # app | whatsapp
    source: str  # text | voice | photo_food | photo_receipt | photo_result
    input_text: str | None
    image: bytes | None
    image_kind: str | None  # food | receipt | result
    extraction: dict | None
    red_flag: str | None
    error: str | None
    notes: list[str]
    log_ids: list[str]
    messages: Annotated[list, add_messages]
    reply: str | None
