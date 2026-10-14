import time


class LoginLimiter:
    """Batas percobaan login gagal per kunci (nomor HP). Di memori: cukup untuk satu proses/demo.

    Produksi dengan banyak proses perlu penyimpanan bersama (mis. Redis).
    """

    def __init__(self, max_failures: int = 5, lock_seconds: int = 15 * 60):
        self.max_failures = max_failures
        self.lock_seconds = lock_seconds
        self._failures: dict[str, list[float]] = {}

    def _recent(self, key: str) -> list[float]:
        cutoff = time.monotonic() - self.lock_seconds
        recent = [t for t in self._failures.get(key, []) if t > cutoff]
        self._failures[key] = recent
        return recent

    def blocked(self, key: str) -> bool:
        return len(self._recent(key)) >= self.max_failures

    def fail(self, key: str) -> None:
        self._recent(key).append(time.monotonic())

    def reset(self, key: str) -> None:
        self._failures.pop(key, None)

    def clear(self) -> None:
        self._failures.clear()


login_limiter = LoginLimiter()
