from dataclasses import dataclass


class InputPlanError(ValueError):
    pass


MODIFIER_KEYS = {
    "CTRL": "CTRL",
    "CONTROL": "CTRL",
    "ALT": "ALT",
    "SHIFT": "SHIFT",
    "WIN": "WIN",
    "WINDOWS": "WIN",
}

SUPPORTED_MAIN_KEYS = {str(index) for index in range(10)} | {chr(value) for value in range(ord("A"), ord("Z") + 1)} | {f"F{index}" for index in range(1, 5)} | {"`", "-", "=", "MOUSEWHEELUP", "MOUSEWHEELDOWN", "BUTTON3"}


@dataclass(frozen=True)
class KeyEvent:
    key: str
    event: str


@dataclass(frozen=True)
class InputPlan:
    binding: str
    events: tuple[KeyEvent, ...]


@dataclass(frozen=True)
class DispatchResult:
    sent: bool
    backend: str
    reason: str
    events_sent: int = 0


class DryRunInputDispatcher:
    backend = "dry_run"

    def dispatch(self, plan: InputPlan) -> DispatchResult:
        return DispatchResult(
            sent=False,
            backend=self.backend,
            reason="dry_run_planned",
            events_sent=len(plan.events),
        )


def normalize_binding(binding: str) -> str:
    parts = split_binding(binding)
    return "+".join(parts)


def split_binding(binding: str) -> list[str]:
    parts = [part.strip().upper() for part in str(binding).split("+") if part.strip()]
    if not parts:
        raise InputPlanError("empty_binding")
    return parts


def validate_binding(binding: str, *, allow_unsupported_main: bool = False) -> str:
    parts = split_binding(binding)
    modifiers = []
    main_keys = []
    for part in parts:
        modifier = MODIFIER_KEYS.get(part)
        if modifier:
            if modifier in modifiers:
                raise InputPlanError(f"duplicate_modifier:{modifier}")
            modifiers.append(modifier)
        else:
            main_keys.append(part)

    if len(main_keys) != 1:
        raise InputPlanError(f"invalid_main_key_count:{len(main_keys)}")
    if not allow_unsupported_main and main_keys[0] not in SUPPORTED_MAIN_KEYS:
        raise InputPlanError(f"unsupported_key:{main_keys[0]}")
    return "+".join([*modifiers, main_keys[0]])


def plan_binding(binding: str) -> InputPlan:
    normalized = validate_binding(binding)
    parts = normalized.split("+")
    modifiers = []
    main_key = None
    for part in parts:
        modifier = MODIFIER_KEYS.get(part)
        if modifier:
            modifiers.append(modifier)
        else:
            main_key = part

    if not main_key:
        raise InputPlanError("missing_main_key")

    if main_key in {"MOUSEWHEELUP", "MOUSEWHEELDOWN"}:
        if modifiers:
            raise InputPlanError("mouse_modifier_unsupported")
        return InputPlan(binding=normalized, events=(KeyEvent(key=main_key, event="wheel"),))
    events = []
    for key in modifiers:
        events.append(KeyEvent(key=key, event="down"))
    events.append(KeyEvent(key=main_key, event="down"))
    events.append(KeyEvent(key=main_key, event="up"))
    for key in reversed(modifiers):
        events.append(KeyEvent(key=key, event="up"))

    return InputPlan(binding=normalized, events=tuple(events))
