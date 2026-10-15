import re

from pydantic import AliasChoices, BaseModel, Field, field_validator

PHONE_PATTERN = r"^\+?\d{8,15}$"
PIN_PATTERN = r"^\d{4,6}$"
# Diawali huruf: nama pengguna tidak pernah bisa menyerupai nomor HP, jadi "identifier" saat masuk tidak ambigu.
USERNAME_PATTERN = re.compile(r"^[a-z][a-z0-9_.]{2,19}$")
USERNAME_RULE = "Nama pengguna 3-20 karakter: huruf kecil, angka, titik, atau garis bawah, diawali huruf."


def normalize_username(value: str) -> str:
    name = value.strip().lower()
    if not USERNAME_PATTERN.fullmatch(name):
        raise ValueError(USERNAME_RULE)
    return name


class UsernameIn(BaseModel):
    username: str

    @field_validator("username")
    @classmethod
    def _valid(cls, v: str) -> str:
        return normalize_username(v)


class Credentials(BaseModel):
    """Pendaftaran: nomor HP tetap wajib (WhatsApp dan undangan keluarga), nama pengguna untuk masuk."""

    phone: str = Field(pattern=PHONE_PATTERN)
    username: str
    pin: str = Field(pattern=PIN_PATTERN)
    # Persetujuan eksplisit atas pemrosesan data kesehatan (UU PDP No. 27/2022). Tanpa ini pendaftaran ditolak.
    consent: bool = False

    @field_validator("username")
    @classmethod
    def _valid(cls, v: str) -> str:
        return normalize_username(v)


class LoginIn(BaseModel):
    """Masuk dengan nama pengguna atau nomor HP. Kunci lama `phone` tetap diterima."""

    identifier: str = Field(min_length=1, max_length=40, validation_alias=AliasChoices("identifier", "phone"))
    pin: str = Field(pattern=PIN_PATTERN)

    @field_validator("identifier")
    @classmethod
    def _strip(cls, v: str) -> str:
        return v.strip()


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    refresh_token: str | None = None
    expires_in: int | None = None  # detik berlakunya token akses


class RefreshIn(BaseModel):
    refresh_token: str = Field(min_length=20, max_length=200)
