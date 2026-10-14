from pydantic import BaseModel, Field


class Credentials(BaseModel):
    phone: str = Field(pattern=r"^\+?\d{8,15}$")
    pin: str = Field(pattern=r"^\d{4,6}$")


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
