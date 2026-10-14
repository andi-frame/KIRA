import pytest

from app.config import DEFAULT_JWT_SECRET, Settings, validate_settings


def test_development_may_use_the_default_secret():
    validate_settings(Settings(environment="development", jwt_secret=DEFAULT_JWT_SECRET))


def test_production_refuses_the_public_default_secret():
    with pytest.raises(RuntimeError):
        validate_settings(Settings(environment="production", jwt_secret=DEFAULT_JWT_SECRET))


def test_production_refuses_short_secrets():
    with pytest.raises(RuntimeError):
        validate_settings(Settings(environment="production", jwt_secret="pendek"))


def test_production_accepts_a_long_random_secret():
    validate_settings(Settings(environment="production", jwt_secret="x" * 40))
