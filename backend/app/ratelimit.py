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


# Permintaan kode atur ulang PIN: dibatasi per akun/identitas agar tidak dipakai membanjiri WhatsApp pemilik.
otp_limiter = LoginLimiter(max_failures=3, lock_seconds=60 * 60)


class SlidingWindowLimiter:
    """Batas panggilan per kunci dalam jendela waktu geser. Di memori: cukup untuk satu proses."""

    def __init__(self, max_calls: int, window_seconds: float):
        self.max_calls = max_calls
        self.window = window_seconds
        self._calls: dict[str, list[float]] = {}

    def check(self, key: str) -> float | None:
        """None bila boleh (dan panggilan dicatat); selain itu detik sampai boleh lagi."""
        now = time.monotonic()
        recent = [t for t in self._calls.get(key, []) if now - t < self.window]
        if len(recent) >= self.max_calls:
            self._calls[key] = recent
            return max(0.0, self.window - (now - recent[0]))
        recent.append(now)
        self._calls[key] = recent
        return None

    def clear(self) -> None:
        self._calls.clear()


# Setiap pesan ke KIRA memanggil model bahasa berbayar: batasi per pengguna agar satu akun tidak menghabiskan kuota.
llm_limiter = SlidingWindowLimiter(max_calls=20, window_seconds=60)
llm_daily_limiter = SlidingWindowLimiter(max_calls=400, window_seconds=24 * 3600)
