"""Short-window dispatch failure escalation for TEK.

A single Windows SendInput anomaly should be visible and temporarily block
input, but it should not immediately turn into ErrorLocked.  Repeated failures
inside a short window are escalated; a successful dispatch clears the window.
"""

from __future__ import annotations

from collections import deque
from dataclasses import dataclass, field
from time import monotonic
from typing import Callable


@dataclass
class DispatchFailureTracker:
    threshold: int = 3
    window_seconds: float = 5.0
    clock: Callable[[], float] = monotonic
    _failures: deque[float] = field(default_factory=deque)

    def __post_init__(self) -> None:
        self.threshold = max(1, int(self.threshold))
        self.window_seconds = max(0.1, float(self.window_seconds))

    def _prune(self, now: float) -> None:
        cutoff = now - self.window_seconds
        while self._failures and self._failures[0] < cutoff:
            self._failures.popleft()

    def record_failure(self) -> tuple[bool, dict[str, int | float]]:
        now = float(self.clock())
        self._prune(now)
        self._failures.append(now)
        return len(self._failures) >= self.threshold, self.snapshot(now)

    def record_success(self) -> dict[str, int | float]:
        self._failures.clear()
        return self.snapshot()

    def reset(self) -> None:
        """Clear failure history after the user explicitly recovers ErrorLocked."""
        self._failures.clear()

    def snapshot(self, now: float | None = None) -> dict[str, int | float]:
        current = float(self.clock()) if now is None else float(now)
        self._prune(current)
        return {
            "threshold": self.threshold,
            "window_seconds": self.window_seconds,
            "recent_failures": len(self._failures),
        }
