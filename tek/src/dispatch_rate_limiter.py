"""Bounded dispatch-rate limiter for TEK UI-linked input.

This is not a dispatch budget. It never exhausts a session and does not alter
TEAP validation; it only prevents a high sampling rate from producing an
unbounded burst of Windows input. The limiter is global across action changes
and has a stricter wheel sub-limit.

The runtime reserves a slot before the final hook/manual ownership checks, then
rolls that reservation back if those late safety gates reject the frame. This
keeps the pre-dispatch race closed without charging the limiter for an input
that TEK never attempted.
"""

from __future__ import annotations

from collections import deque
from dataclasses import dataclass, field
from time import monotonic
from typing import Callable

from tek.src.input_planner import InputPlan


@dataclass(frozen=True)
class DispatchReservation:
    """One provisional rate-limit slot owned by a pending dispatch."""

    reservation_id: int
    timestamp: float
    is_wheel: bool


@dataclass
class DispatchRateLimiter:
    max_per_second: int = 10
    max_wheel_per_second: int = 5
    clock: Callable[[], float] = monotonic
    _all: deque[DispatchReservation] = field(default_factory=deque)
    _wheel: deque[DispatchReservation] = field(default_factory=deque)
    _next_reservation_id: int = 1
    _last_allow_reservation: DispatchReservation | None = None

    def __post_init__(self) -> None:
        self.max_per_second = max(1, min(20, int(self.max_per_second)))
        self.max_wheel_per_second = max(1, min(5, int(self.max_wheel_per_second)))

    @staticmethod
    def _is_wheel(plan: InputPlan) -> bool:
        return any(event.event == "wheel" for event in plan.events)

    @staticmethod
    def _prune(events: deque[DispatchReservation], now: float) -> None:
        cutoff = now - 1.0
        while events and events[0].timestamp <= cutoff:
            events.popleft()

    def reserve(self, plan: InputPlan) -> tuple[DispatchReservation | None, str]:
        """Reserve a provisional slot before late dispatch gates.

        The caller must call :meth:`rollback` when a subsequent hook/manual
        check prevents the actual dispatch. A reservation is intentionally kept
        after a real SendInput attempt, including partial/native failures,
        because Windows may have accepted part of that attempt.
        """

        now = float(self.clock())
        self._prune(self._all, now)
        self._prune(self._wheel, now)
        if len(self._all) >= self.max_per_second:
            return None, f"dispatch_rate_limited:global:{self.max_per_second}"
        is_wheel = self._is_wheel(plan)
        if is_wheel and len(self._wheel) >= self.max_wheel_per_second:
            return None, f"dispatch_rate_limited:wheel:{self.max_wheel_per_second}"
        reservation = DispatchReservation(
            reservation_id=self._next_reservation_id,
            timestamp=now,
            is_wheel=is_wheel,
        )
        self._next_reservation_id += 1
        self._all.append(reservation)
        if is_wheel:
            self._wheel.append(reservation)
        return reservation, "dispatch_rate_ok"

    def allow(self, plan: InputPlan) -> tuple[bool, str]:
        """Compatibility helper for callers without a late gate.

        Legacy users that call ``allow`` retain the historical semantics: a
        successful call consumes a slot for the one-second window.  The most
        recent successful reservation can be claimed by the engine to support
        late-gate rollback without breaking integrations that monkey-patch or
        instrument ``allow``.
        """

        reservation, reason = self.reserve(plan)
        self._last_allow_reservation = reservation
        return reservation is not None, reason

    def claim_last_allow_reservation(self) -> DispatchReservation | None:
        """Return the provisional slot created by the latest ``allow`` call.

        This is intentionally a one-shot hand-off for the single TEK worker
        thread. Ordinary callers never claim it, so their ``allow`` calls keep
        the original consume-on-success behavior.
        """

        reservation = self._last_allow_reservation
        self._last_allow_reservation = None
        return reservation

    def rollback(self, reservation: DispatchReservation | None) -> bool:
        """Return a provisional slot when no dispatch was attempted."""

        if reservation is None:
            return False
        removed = self._remove_identity(self._all, reservation)
        if reservation.is_wheel:
            self._remove_identity(self._wheel, reservation)
        return removed

    def commit(self, reservation: DispatchReservation | None) -> bool:
        """Mark a reservation final after dispatch begins.

        Slots are inserted at reservation time, so commit is intentionally a
        no-op apart from confirming that the reservation is currently tracked.
        The method keeps the caller protocol explicit and testable.
        """

        if reservation is None:
            return False
        return any(item is reservation for item in self._all)

    @staticmethod
    def _remove_identity(events: deque[DispatchReservation], reservation: DispatchReservation) -> bool:
        for index, item in enumerate(events):
            if item is reservation:
                del events[index]
                return True
        return False

    def reset(self) -> None:
        """Clear temporary reservations after an explicit ErrorLocked recovery."""
        self._all.clear()
        self._wheel.clear()
        self._last_allow_reservation = None

    def snapshot(self) -> dict[str, int]:
        now = float(self.clock())
        self._prune(self._all, now)
        self._prune(self._wheel, now)
        return {
            "max_per_second": self.max_per_second,
            "max_wheel_per_second": self.max_wheel_per_second,
            "used_global": len(self._all),
            "used_wheel": len(self._wheel),
        }
